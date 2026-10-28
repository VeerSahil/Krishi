"""Evidence completeness checks, not an agronomic suitability classifier."""
from datetime import datetime, timezone
import unicodedata
from fastapi import Depends, HTTPException, Query
from fastapi.encoders import jsonable_encoder
from google.api_core.exceptions import FailedPrecondition, Conflict
from schemas import CropPlanRequest
from admin_portal import page_documents
from google.cloud.firestore_v1.base_query import FieldFilter


CROP_ALIASES = {
    "wheat": ("गेहूं", "गेहूँ", "गहू"),
    "rice": ("paddy", "धान", "चावल", "भात", "तांदूळ"),
    "maize": ("corn", "मक्का", "मका"),
    "sugarcane": ("गन्ना", "ऊस"),
    "soybean": ("सोयाबीन",), "cotton": ("कपास", "कापूस"),
    "barley": ("जौ", "जव"), "groundnut": ("मूंगफली", "भुईमूग"),
    "sorghum": ("ज्वार", "ज्वारी"), "lentils": ("मसूर",),
    "chickpea": ("चना", "हरभरा"), "pulses": ("दालें", "कडधान्ये"),
    "millet": ("मिलेट", "भरडधान्य"),
}


def crop_key(name):
    value = " ".join(unicodedata.normalize("NFKC", name).casefold().split())
    return next((crop for crop, aliases in CROP_ALIASES.items() if value == crop or value in aliases), value)


def check_plan(plan, survey):
    gaps = []
    if not plan.get("sowingDate"):
        gaps.append("Add a planned sowing date.")
    if plan.get("irrigation", "unknown") == "unknown":
        gaps.append("Confirm the irrigation source and water availability.")
    if not survey.get("measuredAt"):
        gaps.append("A field survey with dated readings is still needed.")
    if survey.get("nutrientSource") != "soil_test" or not survey.get("soilTestReference"):
        gaps.append("Add a soil-test reference; manual NPK is not a verified soil test.")
    if survey.get("nutrientUnit", "unknown") == "unknown":
        gaps.append("Record the units used by the soil test.")
    if survey.get("temperatureSource") != "measured":
        gaps.append("Record measured temperature; simulated values are for demonstration.")
    if survey.get("status") != "completed":
        gaps.append("Wait for admin review and release of the field report.")
    released = (survey.get("recommended_crop") or survey.get("recommendedCrop")) if survey.get("status") == "completed" else None
    comparison = "unavailable" if not released else ("same" if crop_key(released) == crop_key(plan["proposedCrop"]) else "different")
    actions = []
    if plan.get("irrigation") == "rainfed":
        actions.append("For a rainfed plan, check the local forecast near sowing and discuss a water backup with your adviser.")
    if plan.get("sowingDate") and str(plan["sowingDate"]) < datetime.now(timezone.utc).date().isoformat():
        actions.append("The planned sowing date has passed. Confirm whether sowing happened or update your plan.")
    if released and comparison == "different":
        actions.append("Ask admin to explain the difference between your chosen crop and the demonstration model result.")
    return {"actions": actions, "state": "needs_information" if gaps else "needs_expert_review", "gaps": gaps,
            "comparison": comparison, "releasedCrop": released,
            "limits": ["Historical rainfall is not a live weather forecast.",
                       "The crop model uses demonstration data and has not been validated for farm decisions.",
                       "Matching a model result does not establish crop suitability."]}


def evidence_record(doc):
    data = doc.to_dict()
    timeline = [{"event": name, "at": data[key]} for key, name in (
        ("createdAt", "Survey requested"), ("approvedAt", "Visit approved"),
        ("visitStartedAt", "Visit started"), ("teamSubmittedAt", "Report received"),
        ("publishedAt", "Recommendation released"), ("rejectedAt", "Survey rejected")) if data.get(key)]
    timeline.sort(key=lambda event: str(event["at"]))
    return {"surveyId": doc.id, "farmName": data.get("farmName", "Farm"),
            "farmAddress": data.get("farmAddress"), "status": data.get("status"),
            "timeline": timeline, "evidence": data.get("fieldEvidence"),
            "legacyRecord": not bool(data.get("fieldEvidence")),
            "publishedBy": data.get("publishedBy"),
            "releasedCrop": (data.get("recommended_crop") or data.get("recommendedCrop")) if data.get("status") == "completed" else None,
            "cropPlan": data.get("cropPlan"), "planHistory": data.get("cropPlanHistory", []),
            "planCheck": check_plan(data["cropPlan"], data) if data.get("cropPlan") else None}


def register_planning_routes(app, verify_farmer, get_db):
    @app.post("/farm/crop-plan")
    def save_plan(request: CropPlanRequest, user=Depends(verify_farmer), db=Depends(get_db)):
        ref = db.collection("farm_inputs").document(request.surveyId)
        doc = ref.get()
        if not doc.exists:
            raise HTTPException(404, "Survey not found")
        survey = doc.to_dict()
        if survey.get("userId") != user["uid"]:
            raise HTTPException(403, "Not your survey")
        plan = request.model_dump(mode="json", exclude={"surveyId"})
        plan["updatedAt"] = datetime.now(timezone.utc)
        try:
            ref.update({"cropPlan": plan, "cropPlanHistory": [*survey.get("cropPlanHistory", []), plan][-20:]}, option=db.write_option(last_update_time=doc.update_time))
        except (FailedPrecondition, Conflict):
            raise HTTPException(409, "This survey changed. Refresh and try again.") from None
        return jsonable_encoder({"plan": plan, "check": check_plan(plan, survey)})

    @app.get("/farm/evidence")
    def history(limit: int = Query(default=20, ge=1, le=50),
                cursor: str | None = Query(default=None, min_length=1, max_length=200, pattern=r"^[^/]+$"),
                user=Depends(verify_farmer), db=Depends(get_db)):
        collection = db.collection("farm_inputs")
        query = collection.where(filter=FieldFilter("userId", "==", user["uid"])).order_by("createdAt", direction="DESCENDING")
        if cursor:
            cursor_doc = collection.document(cursor).get()
            if not cursor_doc.exists or cursor_doc.to_dict().get("userId") != user["uid"]:
                raise HTTPException(400, "Invalid history page")
        docs, next_cursor = page_documents(query, collection, limit, cursor)
        return jsonable_encoder({"records": [evidence_record(doc) for doc in docs], "nextCursor": next_cursor})
