"""Staff-only farm registry, linked visits and reviewed farmer reports."""
from datetime import datetime, timezone
from fastapi import Depends, HTTPException, Query
from fastapi.encoders import jsonable_encoder
from fastapi.responses import RedirectResponse
from google.api_core.exceptions import AlreadyExists, Conflict, FailedPrecondition
from google.cloud.firestore_v1.base_query import FieldFilter
from admin_portal import AdminStaticFiles
from config import BASE_DIR, get_db
from world_models import ASSETS, FarmRegionRequest, FarmPolicyRequest, LinkSurveyRequest, FarmerReportRequest
from care_assessment import report_template

ACTIVE = {"pending", "approved", "in_progress", "awaiting_review"}

def now(): return datetime.now(timezone.utc)

def public_region(doc):
    data = doc.to_dict()
    keys = ("farmerId", "farmerName", "farmName", "farmAddress", "city", "soilType", "cropAsset", "slot", "areaHectares",
            "policy", "version", "createdAt", "updatedAt", "assignedTeamId", "assignedTeamName", "latestSurveyId", "latestSurveyStatus",
            "assessment", "previousClass", "classChangedAt", "lastReportAt")
    return jsonable_encoder({"id": doc.id, **{key: data.get(key) for key in keys}})

def region_for_survey(survey, db):
    if not survey.get("farmId"): return None
    doc = db.collection("farms").document(survey["farmId"]).get()
    if not doc.exists or doc.to_dict().get("farmerId") != survey["userId"]:
        raise HTTPException(409, "The linked field is missing or belongs to another farmer")
    return doc

def queue_region_update(batch, db, survey_id, survey, changes, *, assessment=None):
    doc = region_for_survey(survey, db)
    if doc is None: return
    data = doc.to_dict()
    if data.get("latestSurveyId") not in (None, survey_id) and data.get("latestSurveyStatus") in ACTIVE:
        raise HTTPException(409, "Another open visit is linked to this field")
    update = {"latestSurveyId": survey_id, "latestSurveyStatus": changes.get("status", survey.get("status")),
              "updatedAt": now(), "version": data.get("version", 1) + 1}
    for key in ("assignedTeamId", "assignedTeamName"):
        if key in changes: update[key] = changes[key]
    if assessment:
        previous = (data.get("assessment") or {}).get("grade", "U")
        update.update({"assessment": assessment, "previousClass": previous})
        if previous != assessment["grade"]: update["classChangedAt"] = now()
        batch.set(db.collection("farm_assessments").document(assessment["submissionId"]), {
            **assessment, "farmId": doc.id, "farmerId": data["farmerId"], "teamId": survey.get("assignedTeamId")})
    if changes.get("status") == "completed": update["lastReportAt"] = now()
    batch.update(db.collection("farms").document(doc.id), update, option=db.write_option(last_update_time=doc.update_time))

def staff_regions(db, user):
    query = db.collection("farms")
    if user["role"] == "team": query = query.where(filter=FieldFilter("assignedTeamId", "==", user["uid"]))
    return query.order_by("__name__")

def require_region(doc, user):
    if not doc.exists: raise HTTPException(404, "Field not found")
    if user["role"] != "admin" and doc.to_dict().get("assignedTeamId") != user["uid"]:
        raise HTTPException(403, "This field is assigned to another inspector")
    return doc.to_dict()

def register_world_routes(app, verify_staff, verify_admin, verify_farmer, serialize_survey):
    @app.get("/world/session")
    def session(user=Depends(verify_staff)):
        return {"uid": user["uid"], "name": user.get("name"), "role": user["role"]}

    @app.get("/world/assets")
    def assets(user=Depends(verify_staff)):
        return {"assets": [{"id": key, **value} for key, value in ASSETS.items()]}

    @app.get("/world/farms")
    def farms(cursor: str | None = Query(default=None, max_length=200, pattern=r"^[^/]+$"),
              limit: int = Query(default=200, ge=1, le=200), user=Depends(verify_staff), db=Depends(get_db)):
        query = staff_regions(db, user)
        if cursor:
            doc = db.collection("farms").document(cursor).get()
            require_region(doc, user)
            query = query.start_after(doc)
        docs = list(query.limit(limit + 1).stream())
        return {"farms": [public_region(doc) for doc in docs[:limit]], "nextCursor": docs[limit-1].id if len(docs) > limit else None}

    @app.post("/world/farms")
    def create(request: FarmRegionRequest, user=Depends(verify_admin), db=Depends(get_db)):
        farmer = db.collection("users").document(request.farmerId).get()
        if not farmer.exists or farmer.to_dict().get("role") != "farmer": raise HTTPException(422, "Choose a registered farmer")
        identifier = f"plot-{request.slot:05d}"
        data = {**request.model_dump(), "farmerName": farmer.to_dict().get("name") or "Farmer", "version": 1,
                "createdAt": now(), "updatedAt": now(), "createdBy": user["uid"], "assignedTeamId": None,
                "assignedTeamName": None, "latestSurveyId": None, "latestSurveyStatus": None, "assessment": None,
                "policyConfiguredBy": user["uid"]}
        try: db.collection("farms").document(identifier).create(data)
        except AlreadyExists: raise HTTPException(409, "This world region is occupied. Choose another region number.") from None
        return {"farm": public_region(db.collection("farms").document(identifier).get())}

    @app.get("/world/farms/{farm_id}")
    def detail(farm_id: str, user=Depends(verify_staff), db=Depends(get_db)):
        doc = db.collection("farms").document(farm_id).get()
        data = require_region(doc, user)
        result = {"farm": public_region(doc), "survey": None}
        sid = data.get("latestSurveyId")
        if sid:
            survey = db.collection("farm_inputs").document(sid).get()
            if survey.exists and (user["role"] == "admin" or survey.to_dict().get("assignedTeamId") == user["uid"]):
                result["survey"] = serialize_survey(survey)
        return result

    @app.post("/world/farms/{farm_id}/policy")
    def policy(farm_id: str, request: FarmPolicyRequest, user=Depends(verify_admin), db=Depends(get_db)):
        ref = db.collection("farms").document(farm_id); doc = ref.get()
        data = require_region(doc, {**user, "role": "admin"})
        if data["version"] != request.version: raise HTTPException(409, "Field changed. Refresh it first.")
        if data.get("latestSurveyStatus") in ACTIVE: raise HTTPException(409, "Finish the open visit before changing assessment bands")
        try: ref.update({"policy": request.policy.model_dump(), "policyConfiguredBy": user["uid"], "version": data["version"]+1, "updatedAt": now()}, option=db.write_option(last_update_time=doc.update_time))
        except (Conflict, FailedPrecondition): raise HTTPException(409, "Field changed. Refresh it first.") from None
        return {"farm": public_region(ref.get())}

    @app.post("/world/farms/{farm_id}/link-survey")
    def link(farm_id: str, request: LinkSurveyRequest, user=Depends(verify_admin), db=Depends(get_db)):
        farm_doc = db.collection("farms").document(farm_id).get()
        farm = require_region(farm_doc, {**user, "role": "admin"})
        ref = db.collection("farm_inputs").document(request.surveyId); doc = ref.get()
        if not doc.exists: raise HTTPException(404, "Survey not found")
        data = doc.to_dict()
        if data["userId"] != farm["farmerId"]: raise HTTPException(403, "The field and request must belong to the same farmer")
        if data.get("status") != "pending" or data.get("farmId"): raise HTTPException(409, "Only an unlinked pending request can be attached")
        changes = {"farmId": farm_id, "farmName": farm["farmName"], "farmAddress": farm["farmAddress"], "city": farm["city"], "soilType": farm["soilType"], "soil_type": farm["soilType"]}
        batch = db.batch()
        batch.update(ref, changes, option=db.write_option(last_update_time=doc.update_time))
        queue_region_update(batch, db, doc.id, {**data, **changes}, {"status": "pending"})
        try: batch.commit()
        except (Conflict, FailedPrecondition): raise HTTPException(409, "Field or request changed. Refresh first.") from None
        return {"farmId": farm_id, "surveyId": doc.id}

    @app.get("/farm/fields")
    def owned_fields(user=Depends(verify_farmer), db=Depends(get_db)):
        docs = db.collection("farms").where(filter=FieldFilter("farmerId", "==", user["uid"])).stream()
        keys = ("farmName", "farmAddress", "city", "soilType", "cropAsset", "areaHectares")
        return {"fields": [{"id": doc.id, **{key: doc.to_dict().get(key) for key in keys}} for doc in docs]}

    @app.get("/world/surveys/{survey_id}/report")
    def preview_report(survey_id: str, language: str = Query(default="en", pattern=r"^(en|hi|mr)$"), user=Depends(verify_admin), db=Depends(get_db)):
        survey = db.collection("farm_inputs").document(survey_id).get()
        draft = db.collection("survey_predictions").document(survey_id).get()
        if not survey.exists or not draft.exists: raise HTTPException(404, "Field report not found")
        if survey.to_dict().get("status") != "awaiting_review" or draft.to_dict().get("kind") != "care_assessment": raise HTTPException(409, "No care report is awaiting review")
        saved = draft.to_dict().get("farmerReport")
        report = saved if saved and saved.get("language") == language else report_template(survey.to_dict(), draft.to_dict(), language)
        return jsonable_encoder({"report": report})

    @app.post("/world/surveys/{survey_id}/report")
    def save_report(survey_id: str, request: FarmerReportRequest, user=Depends(verify_admin), db=Depends(get_db)):
        survey_ref = db.collection("farm_inputs").document(survey_id); survey = survey_ref.get()
        ref = db.collection("survey_predictions").document(survey_id); draft = ref.get()
        if not survey.exists or not draft.exists: raise HTTPException(404, "Field report not found")
        sd, dd = survey.to_dict(), draft.to_dict()
        if sd.get("status") != "awaiting_review" or dd.get("kind") != "care_assessment" or request.submissionId != sd.get("measurementSubmissionId") or request.submissionId != dd.get("submissionId"):
            raise HTTPException(409, "Report changed or was already released. Refresh first.")
        report = {**report_template(sd, dd, request.language), **request.model_dump(), "preparedBy": user["uid"], "preparedAt": now()}
        # Touch the same survey with a lease: a concurrent release/rejection must not save a stale draft.
        batch = db.batch()
        batch.update(survey_ref, {"reportDraftUpdatedAt": now()}, option=db.write_option(last_update_time=survey.update_time))
        batch.update(ref, {"farmerReport": report}, option=db.write_option(last_update_time=draft.update_time))
        try: batch.commit()
        except (Conflict, FailedPrecondition): raise HTTPException(409, "Report changed. Refresh before saving.") from None
        return jsonable_encoder({"report": report, "message": "Draft saved. Release it after reviewing the farmer copy."})

    @app.get("/world")
    def world_home(): return RedirectResponse("/world/", status_code=307)

    from world_events import register_world_events
    register_world_events(app, verify_staff)
    app.mount("/world", AdminStaticFiles(directory=str(BASE_DIR / "world_web"), html=True), name="farm-world")
