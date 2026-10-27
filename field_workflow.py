"""Three-role survey lifecycle. Draft recommendations never live in farmer-readable documents."""
from datetime import datetime, timezone
from uuid import uuid4
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import RedirectResponse
from google.api_core.exceptions import FailedPrecondition, Conflict
from google.cloud.firestore_v1.base_query import FieldFilter

from admin_portal import AdminStaticFiles, page_documents
from config import BASE_DIR, get_db
from ml_pipeline import run_ml_pipeline
from schemas import FieldReadingsRequest, temperature_metadata

VISIT_STATES = ("approved", "in_progress")


def now():
    return datetime.now(timezone.utc)


def apply_changes(snapshot, changes, db):
    try:
        db.collection("farm_inputs").document(snapshot.id).update(
            changes, option=db.write_option(last_update_time=snapshot.update_time))
    except (FailedPrecondition, Conflict):
        raise HTTPException(409, "This survey changed. Refresh it before continuing.") from None


def assigned_visit(survey_id, user, db):
    snapshot = db.collection("farm_inputs").document(survey_id).get()
    if not snapshot.exists:
        raise HTTPException(404, "Survey not found")
    if snapshot.to_dict().get("assignedTeamId") != user["uid"]:
        raise HTTPException(403, "This visit is assigned to another team member")
    return snapshot


def admin_action(request, admin, db, background, send_email):
    snapshot = db.collection("farm_inputs").document(request.surveyId).get()
    if not snapshot.exists:
        raise HTTPException(404, "Survey not found")
    survey = snapshot.to_dict()
    status = survey.get("status")
    if request.action == "approve":
        if status != "pending":
            raise HTTPException(409, "Only a pending survey can be approved for a visit")
        team = db.collection("users").document(request.teamId).get()
        if not team.exists or team.to_dict().get("role") != "team":
            raise HTTPException(422, "Choose an existing field team account")
        apply_changes(snapshot, {
            "status": "approved", "assignedTeamId": request.teamId,
            "assignedTeamName": team.to_dict().get("name") or "Field team",
            "approvedBy": admin["uid"], "approvedAt": now(), "adminNotes": request.notes,
        }, db)
        return {"status": "approved", "message": "Visit approved and assigned to the field team"}
    if request.action == "reject":
        if status not in ("pending", "approved", "in_progress", "awaiting_review", "failed"):
            raise HTTPException(409, "This survey can no longer be rejected")
        apply_changes(snapshot, {"status": "rejected", "rejectedAt": now(),
                                "rejectedBy": admin["uid"], "adminNotes": request.notes}, db)
        return {"status": "rejected", "message": "Survey rejected"}
    if status != "awaiting_review":
        raise HTTPException(409, "A team report must be reviewed before publishing a result")
    draft = db.collection("survey_predictions").document(snapshot.id).get()
    if not draft.exists:
        raise HTTPException(409, "The field report has no saved prediction")
    prediction = draft.to_dict()
    if prediction.get("submissionId") != survey.get("measurementSubmissionId"):
        raise HTTPException(409, "The prediction does not match the latest team report")
    changes = {
        "status": "completed", "predicted_rainfall_mm": prediction["predicted_rainfall_mm"],
        "predictedRainfall": prediction["predicted_rainfall_mm"],
        "recommended_crop": prediction["recommended_crop"],
        "recommendedCrop": prediction["recommended_crop"],
        "recommendation_method": prediction["recommendation_method"],
        "rainfall_basis": prediction["rainfall_basis"],
        "completedAt": now(), "publishedAt": now(), "publishedBy": admin["uid"],
        "adminNotes": request.notes if request.notes is not None else survey.get("adminNotes"),
        **temperature_metadata(prediction.get("temperatureSource"), prediction.get("temperatureCategory")),
    }
    apply_changes(snapshot, changes, db)
    background.add_task(send_email, survey.get("farmerEmail", ""), survey.get("farmerName", "Farmer"),
                        prediction["recommended_crop"], prediction["predicted_rainfall_mm"],
                        snapshot.id, db, changes["recommendationNotice"])
    return {"status": "completed", "message": "Recommendation released to the farmer",
            "crop": prediction["recommended_crop"], "rainfall": prediction["predicted_rainfall_mm"],
            **temperature_metadata(prediction.get("temperatureSource"), prediction.get("temperatureCategory"))}


def register_field_routes(app, verify_team, serialize_survey):
    router = APIRouter(prefix="/team", tags=["Field team"])

    @router.get("/overview")
    def overview(user=Depends(verify_team), db=Depends(get_db)):
        return {"member": {"uid": user["uid"], "name": user.get("name") or "Field team",
                           "email": user.get("email", "")}, "inputMode": "field_team_manual"}

    @router.get("/visits")
    def visits(status: Literal["approved", "in_progress", "awaiting_review", "completed", "rejected"] | None = None,
               limit: int = Query(default=20, ge=1, le=100),
               cursor: str | None = Query(default=None, min_length=1, max_length=200, pattern=r"^[^/]+$"),
               user=Depends(verify_team), db=Depends(get_db)):
        collection = db.collection("farm_inputs")
        query = collection.where(filter=FieldFilter("assignedTeamId", "==", user["uid"])).order_by(
            "createdAt", direction="DESCENDING")
        if status:
            query = query.where(filter=FieldFilter("status", "==", status))
        docs, next_cursor = page_documents(query, collection, limit, cursor)
        return {"visits": [serialize_survey(doc) for doc in docs], "nextCursor": next_cursor}

    @router.get("/visits/{survey_id}")
    def detail(survey_id: str, user=Depends(verify_team), db=Depends(get_db)):
        return serialize_survey(assigned_visit(survey_id, user, db))

    @router.post("/visits/{survey_id}/start")
    def start(survey_id: str, user=Depends(verify_team), db=Depends(get_db)):
        snapshot = assigned_visit(survey_id, user, db)
        if snapshot.to_dict().get("status") != "approved":
            raise HTTPException(409, "Only an approved visit can be started")
        apply_changes(snapshot, {"status": "in_progress", "visitStartedAt": now()}, db)
        return {"status": "in_progress", "message": "Visit started"}

    @router.post("/visits/{survey_id}/readings")
    def submit(survey_id: str, request: FieldReadingsRequest,
               user=Depends(verify_team), db=Depends(get_db)):
        snapshot = assigned_visit(survey_id, user, db)
        survey = snapshot.to_dict()
        if survey.get("status") not in VISIT_STATES:
            raise HTTPException(409, "Readings can only be submitted for an approved field visit")
        try:
            prediction = run_ml_pipeline(
                survey["city"], survey["year"], survey["season"],
                survey.get("soilType") or survey.get("soil_type"),
                request.moisture, request.temperature, request.nitrogen,
                request.phosphorus, request.potassium)
        except (ValueError, KeyError):
            raise HTTPException(422, "Check the survey location and all five readings.") from None
        except Exception:
            raise HTTPException(503, "Prediction is unavailable. Your visit is still open; retry submission.") from None
        submission_id = uuid4().hex
        metadata = request.temperature_metadata()
        prediction.update(metadata)
        changes = {
            "status": "awaiting_review", **request.model_dump(exclude={"notes"}),
            **metadata,
            "measuredAt": now(), "teamSubmittedAt": now(), "teamSubmittedBy": user["uid"],
            "teamNotes": request.notes, "inputSource": "field_team_manual",
            "nutrientSource": "manual", "measurementSubmissionId": submission_id,
        }
        draft = {**prediction, "surveyId": survey_id, "userId": survey["userId"],
                 "teamId": user["uid"], "submissionId": submission_id}
        # Both records change together; a cancellation or duplicate submission
        # must not leave a draft/result associated with the wrong report.
        batch = db.batch()
        batch.update(db.collection("farm_inputs").document(survey_id), changes,
                     option=db.write_option(last_update_time=snapshot.update_time))
        batch.set(db.collection("survey_predictions").document(survey_id), draft)
        try:
            batch.commit()
        except (FailedPrecondition, Conflict):
            raise HTTPException(409, "This visit changed. Refresh it before submitting again.") from None
        return {"status": "awaiting_review", "surveyId": survey_id,
                "message": "Readings saved. The recommendation is waiting for admin release."}

    @router.get("")
    def home():
        return RedirectResponse("/team/", status_code=307)

    app.include_router(router)
    app.mount("/team", AdminStaticFiles(directory=str(BASE_DIR / "team_web"), html=True),
              name="field-team-interface")
