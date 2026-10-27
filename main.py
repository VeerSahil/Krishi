"""Smart Agro AI API: Firebase-authenticated surveys and manual-input predictions."""
import asyncio
import html
import logging
import os
import smtplib
from datetime import datetime, timezone
from email.mime.text import MIMEText

from fastapi import BackgroundTasks, Depends, FastAPI, Header, HTTPException
from fastapi.encoders import jsonable_encoder
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from firebase_admin import auth
from google.api_core.exceptions import (AlreadyExists, Conflict, FailedPrecondition,
                                        GoogleAPICallError)
from google.cloud.firestore_v1.base_query import FieldFilter

from config import ConfigurationError, firebase_configured, gemini_key, get_db
from chatbot import answer_chat
from ml_pipeline import (CITY_MAP, SEASON_MAP, TEMP_CATEGORY_MAP, get_soil_nutrients,
                         run_ml_pipeline, supported_soil_types)
from schemas import (AdminActionRequest, BookSurveyRequest, ChatRequest, FarmRequest,
                     ReviewRequest, temperature_metadata)
from field_workflow import admin_action, apply_changes

logger = logging.getLogger(__name__)
app = FastAPI(title="Agro AI Backend", version="1.2.0")
origins = [origin.strip() for origin in os.getenv("CORS_ORIGINS", "*").split(",") if origin.strip()]
app.add_middleware(CORSMiddleware, allow_origins=origins,
                   allow_credentials="*" not in origins,
                   allow_methods=["GET", "POST"], allow_headers=["Authorization", "Content-Type"])


@app.exception_handler(ConfigurationError)
async def configuration_error(_request, error):
    return JSONResponse(status_code=503, content={"detail": str(error)})


@app.exception_handler(GoogleAPICallError)
async def firebase_service_error(_request, error):
    logger.warning("Firebase request failed: %s", type(error).__name__)
    return JSONResponse(status_code=503, content={
        "detail": "Firebase is unavailable or its indexes/permissions need configuration. Please retry later."})


@app.exception_handler(RequestValidationError)
async def validation_error(_request, error):
    # Pydantic validator contexts contain ValueError objects; do not serialize them.
    errors = [{key: value for key, value in item.items() if key not in ("ctx", "input")}
              for item in error.errors()]
    return JSONResponse(status_code=422, content={"detail": jsonable_encoder(errors)})


def utcnow():
    return datetime.now(timezone.utc)


def get_current_user(authorization: str | None = Header(default=None)):
    scheme, _, token = (authorization or "").partition(" ")
    if scheme.casefold() != "bearer" or not token.strip():
        raise HTTPException(401, "Provide a Firebase ID token using Bearer authentication.",
                            headers={"WWW-Authenticate": "Bearer"})
    get_db()  # Initialize the same Firebase project used by token verification.
    try:
        return auth.verify_id_token(token.strip())
    except auth.CertificateFetchError:
        raise HTTPException(503, "Unable to verify login right now. Please retry.") from None
    except (ValueError, auth.InvalidIdTokenError, auth.RevokedIdTokenError):
        raise HTTPException(401, "Your login is invalid or expired. Please sign in again.",
                            headers={"WWW-Authenticate": "Bearer"}) from None


def require_role(user, db, role):
    profile = db.collection("users").document(user["uid"]).get()
    data = profile.to_dict() if profile.exists else {}
    if data.get("role") != role:
        raise HTTPException(403, f"{role.title()} access required")
    return {**user, "name": user.get("name") or data.get("name") or role.title()}


def verify_admin(user=Depends(get_current_user), db=Depends(get_db)):
    return require_role(user, db, "admin")


def verify_team(user=Depends(get_current_user), db=Depends(get_db)):
    return require_role(user, db, "team")


def verify_farmer(user=Depends(get_current_user), db=Depends(get_db)):
    return require_role(user, db, "farmer")


def serialize_survey(snapshot):
    data = snapshot.to_dict()
    data.update(temperature_metadata(data.get("temperatureSource"), data.get("temperatureCategory")))
    data["surveyId"] = snapshot.id
    data["document_id"] = snapshot.id
    # Support existing documents and both client naming conventions.
    for canonical, alias in (("predicted_rainfall_mm", "predictedRainfall"),
                             ("recommended_crop", "recommendedCrop"),
                             ("soilType", "soil_type")):
        value = data.get(canonical)
        if value is None:
            value = data.get(alias)
        data[canonical] = data[alias] = value
    return jsonable_encoder(data)


def latest_query(db, uid):
    return (db.collection("farm_inputs")
            .where(filter=FieldFilter("userId", "==", uid))
            .order_by("createdAt", direction="DESCENDING"))


def update_survey(snapshot, changes, db):
    try:
        # Two admins can read pending simultaneously. Only the first update wins.
        option = db.write_option(last_update_time=snapshot.update_time)
        db.collection("farm_inputs").document(snapshot.id).update(changes, option=option)
    except (FailedPrecondition, Conflict):
        raise HTTPException(409, "This survey changed. Refresh it before processing again.") from None


@app.get("/")
def root():
    return {"message": "Agro AI Backend", "version": app.version, "docs": "/docs",
            "sensor_input": "manual", "interfaces": {"farmer": "Android app", "admin": "/admin/", "team": "/team/"}}


@app.get("/health")
def health():
    # A configuration report is not evidence that the remote services connected.
    return {"status": "ok", "timestamp": utcnow(),
            "firebaseConfigured": firebase_configured(),
            "chatbotConfigured": bool(gemini_key()),
            "emailConfigured": bool(os.getenv("SMTP_EMAIL") and os.getenv("SMTP_PASSWORD")),
            "sensorInput": "manual"}


@app.get("/cities")
def get_cities():
    return {"cities": list(CITY_MAP)}


@app.get("/soil-types")
def get_soil_types():
    return {"soil_types": supported_soil_types()}


@app.get("/seasons")
def get_seasons():
    return {"seasons": list(SEASON_MAP)}


@app.post("/survey/book")
def book_survey(request: BookSurveyRequest, user=Depends(verify_farmer), db=Depends(get_db)):
    profile = db.collection("users").document(user["uid"]).get()
    profile_data = profile.to_dict() if profile.exists else {}
    data = {
        "userId": user["uid"],
        "farmerName": user.get("name") or profile_data.get("name") or request.farmerName or "Farmer",
        "farmerEmail": user.get("email") or profile_data.get("email") or "",
        "farmName": request.farmName, "farmAddress": request.farmAddress,
        "contactPhone": request.contactPhone or profile_data.get("phone", ""),
        "assignedTeamId": None, "assignedTeamName": None,
        "city": request.city, "soilType": request.soilType, "soil_type": request.soilType,
        "moisture": None, "temperature": None,
        "year": request.year, "season": request.season, "status": "pending",
        "predictedRainfall": None, "predicted_rainfall_mm": None,
        "recommendedCrop": None, "recommended_crop": None, "createdAt": utcnow(),
        "nitrogen": None, "phosphorus": None, "potassium": None,
        "nutrientSource": None, "inputSource": None,
        **temperature_metadata(None),
        "emailSent": False, "emailStatus": "not_sent",
    }
    ref = db.collection("farm_inputs").document()
    ref.set(data)
    return {"surveyId": ref.id, "status": "pending",
            "message": "Survey booked successfully. Admin will process it soon."}


@app.get("/survey/my-surveys")
def get_my_surveys(user=Depends(verify_farmer), db=Depends(get_db)):
    return {"surveys": [serialize_survey(doc) for doc in latest_query(db, user["uid"]).stream()]}


@app.post("/review/add")
def add_review(request: ReviewRequest, user=Depends(verify_farmer), db=Depends(get_db)):
    survey = db.collection("farm_inputs").document(request.surveyId).get()
    if not survey.exists:
        raise HTTPException(404, "Survey not found")
    data = survey.to_dict()
    if data.get("userId") != user["uid"]:
        raise HTTPException(403, "Not your survey")
    if data.get("status") != "completed":
        raise HTTPException(400, "Can only review completed surveys")
    profile = db.collection("users").document(user["uid"]).get()
    profile_data = profile.to_dict() if profile.exists else {}
    review = {"userId": user["uid"], "farmerId": user["uid"], "surveyId": request.surveyId, "rating": request.rating,
              "comment": request.comment, "createdAt": utcnow(),
              "farmerName": profile_data.get("name") or user.get("name") or "Farmer"}
    try:
        # Stable document ID makes repeated submissions safe, including races.
        db.collection("reviews").document(request.surveyId).create(review)
    except AlreadyExists:
        raise HTTPException(409, "This survey already has a review") from None
    return {"message": "Review added successfully"}


@app.get("/reviews/all")
def get_all_reviews(user=Depends(get_current_user), db=Depends(get_db)):
    result = []
    for doc in db.collection("reviews").order_by("createdAt", direction="DESCENDING").limit(50).stream():
        data = doc.to_dict()
        # Return only public review data, not stored user IDs or email addresses.
        result.append({"reviewId": doc.id, "surveyId": data.get("surveyId"),
                       "rating": data.get("rating"), "comment": data.get("comment"),
                       "farmerName": data.get("farmerName", "Anonymous"),
                       "createdAt": data.get("createdAt")})
    return {"reviews": jsonable_encoder(result)}


@app.get("/admin/pending-surveys")
def get_pending_surveys(admin=Depends(verify_admin), db=Depends(get_db)):
    docs = (db.collection("farm_inputs").where(filter=FieldFilter("status", "==", "pending"))
            .order_by("createdAt", direction="DESCENDING").stream())
    return {"pending_surveys": [serialize_survey(doc) for doc in docs]}


@app.post("/admin/process-survey")
def process_survey(request: AdminActionRequest, background: BackgroundTasks,
                   admin=Depends(verify_admin), db=Depends(get_db)):
    return admin_action(request, admin, db, background, send_prediction_email)


@app.get("/admin/all-surveys")
def get_all_surveys(admin=Depends(verify_admin), db=Depends(get_db)):
    docs = db.collection("farm_inputs").order_by("createdAt", direction="DESCENDING").limit(100).stream()
    return {"surveys": [serialize_survey(doc) for doc in docs]}


def send_prediction_email(email, name, crop, rainfall, survey_id, db, demo_notice=None):
    email_address, password = os.getenv("SMTP_EMAIL"), os.getenv("SMTP_PASSWORD")
    status = "not_configured"
    if email_address and password and email:
        body = (f"<p>Hello {html.escape(name or 'Farmer')}!</p>"
                f"<p>Survey {html.escape(survey_id)} results:</p>"
                f"<p>Recommended crop: {html.escape(crop)}<br>"
                f"Estimated rainfall: {rainfall:.2f} mm</p>")
        if demo_notice:
            body += f"<p><strong>{html.escape(demo_notice)}</strong></p>"
        msg = MIMEText(body, "html", "utf-8")
        msg["Subject"] = "Your Agro AI Demo Results" if demo_notice else "Your Agro AI Survey Results"
        msg["From"], msg["To"] = email_address, email
        try:
            with smtplib.SMTP(os.getenv("SMTP_SERVER", "smtp.gmail.com"),
                              int(os.getenv("SMTP_PORT", "587")), timeout=10) as server:
                server.starttls()
                server.login(email_address, password)
                server.send_message(msg)
            status = "sent"
        except Exception as error:
            logger.warning("Survey email failed: %s", type(error).__name__)
            status = "failed"
    try:
        db.collection("farm_inputs").document(survey_id).update(
            {"emailSent": status == "sent", "emailStatus": status})
    except Exception as error:
        logger.warning("Email status update failed: %s", type(error).__name__)


def recent_chat_context(db, uid):
    query = (latest_query(db, uid).where(filter=FieldFilter("status", "==", "completed")).limit(3))
    lines = []
    for doc in query.stream(timeout=3, retry=None):
        data = doc.to_dict()
        crop = data.get("recommended_crop") or data.get("recommendedCrop")
        if crop:
            label = " [DEMO: simulated temperature]" if data.get("temperatureSource") == "simulated" else ""
            lines.append(f"- {crop} in {data.get('city', '')}{label}")
    return "\n".join(lines)


@app.post("/chat")
async def chat_with_gemini(request: ChatRequest, user=Depends(verify_farmer), db=Depends(get_db)):
    context = ""
    if gemini_key():
        try:
            context = await asyncio.wait_for(
                asyncio.to_thread(recent_chat_context, db, user["uid"]), timeout=4)
        except Exception as error:
            logger.warning("Chat context unavailable: %s", type(error).__name__)
    return await answer_chat(request.message, context)


@app.post("/predict")
def predict_preview(request: FarmRequest, user=Depends(verify_admin)):
    # Compatibility/manual-input endpoint. A preview must not create or process
    # surveys or expose other users' data.
    result = run_ml_pipeline(**request.model_dump(exclude={"temperatureSource", "temperatureCategory"}))
    result.update(request.temperature_metadata())
    return jsonable_encoder({"success": True, **result})


@app.get("/latest")
def get_latest(user=Depends(verify_farmer), db=Depends(get_db)):
    docs = list(latest_query(db, user["uid"]).limit(1).stream())
    if not docs:
        return {"success": False, "error": "No surveys found"}
    return {"success": True, **serialize_survey(docs[0])}


@app.get("/survey/{survey_id}")
def get_survey_details(survey_id: str, user=Depends(get_current_user), db=Depends(get_db)):
    snapshot = db.collection("farm_inputs").document(survey_id).get()
    if not snapshot.exists:
        raise HTTPException(404, "Survey not found")
    data = snapshot.to_dict()
    profile = db.collection("users").document(user["uid"]).get()
    is_admin = profile.exists and profile.to_dict().get("role") == "admin"
    if data.get("userId") != user["uid"] and not is_admin:
        raise HTTPException(403, "Access denied")
    result = serialize_survey(snapshot)
    if is_admin and data.get("status") == "awaiting_review":
        draft = db.collection("survey_predictions").document(survey_id).get()
        if draft.exists:
            result["draftPrediction"] = jsonable_encoder(draft.to_dict())
    return result


from admin_portal import register_admin_routes
from field_workflow import register_field_routes
from support import register_support_routes
register_support_routes(app, verify_farmer, verify_admin)
register_field_routes(app, verify_team, serialize_survey)
register_admin_routes(app, verify_admin, serialize_survey)
