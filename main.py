from fastapi import FastAPI, HTTPException, Depends, Header
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime
import firebase_admin
from firebase_admin import credentials, firestore, auth
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from ml_pipeline import run_ml_pipeline, predict_rainfall, get_soil_nutrients
from dotenv import load_dotenv
import os
import time

# ── NEW: correct google-genai import ──────────────────────────────────────────
from google import genai
from google.genai import types
# ─────────────────────────────────────────────────────────────────────────────

load_dotenv()

GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")
if not GEMINI_API_KEY:
    raise ValueError("GEMINI_API_KEY not found in .env")

# ── NEW: initialise the client (replaces genai.configure + GenerativeModel) ──
gemini_client = genai.Client(api_key=GEMINI_API_KEY)
GEMINI_MODEL = "gemini-2.5-flash"              # primary free-tier model
GEMINI_FALLBACK_MODEL = "gemini-2.5-flash-lite" # lighter fallback if primary is quota-limited
# ─────────────────────────────────────────────────────────────────────────────

# Initialize Firebase — works both locally and on Render
if not firebase_admin._apps:
    fb_json_b64 = os.getenv("FIREBASE_KEY_JSON")
    if fb_json_b64:
        import json, base64
        cred_dict = json.loads(base64.b64decode(fb_json_b64))
        cred = credentials.Certificate(cred_dict)
    else:
        cred = credentials.Certificate("firebase_key.json")
    firebase_admin.initialize_app(cred)

db = firestore.client()

# Email config
SMTP_CONFIG = {
    "server": "smtp.gmail.com",
    "port": 587,
    "email": "your-email@gmail.com",
    "password": "your-app-password",
}

# Temperature category → numeric mapping
TEMP_CATEGORY_MAP = {
    "Low": 20,
    "Moderate": 28,
    "High": 35,
}

app = FastAPI(title="Agro AI Backend")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ============================================
# AUTHENTICATION DEPENDENCY
# ============================================

async def get_current_user(authorization: str = Header(None)):
    """Verify Firebase ID token"""
    if not authorization:
        raise HTTPException(status_code=401, detail="No token provided")
    try:
        token = authorization.split("Bearer ")[1]
        decoded_token = auth.verify_id_token(token)
        return decoded_token
    except Exception as e:
        raise HTTPException(status_code=401, detail=f"Invalid token: {str(e)}")


async def verify_admin(user=Depends(get_current_user)):
    """Check if user is admin"""
    user_doc = db.collection("users").document(user["uid"]).get()
    if not user_doc.exists or user_doc.to_dict().get("role") != "admin":
        raise HTTPException(status_code=403, detail="Admin access required")
    return user

# ============================================
# MODELS
# ============================================

class BookSurveyRequest(BaseModel):
    city: str
    soilType: str
    year: int = 2026
    season: str = "Monsoon"
    farmerName: Optional[str] = ""
    farmerEmail: Optional[str] = ""
    moisture: Optional[float] = None
    temperature: Optional[float] = None


class SurveyResponse(BaseModel):
    surveyId: str
    status: str
    message: str


class ReviewRequest(BaseModel):
    surveyId: str
    rating: int = Field(..., ge=1, le=5)
    comment: str


class AdminActionRequest(BaseModel):
    surveyId: str
    action: str  # "approve" or "reject"
    moisture: Optional[float] = None
    temperatureCategory: Optional[str] = None  # "Low" | "Moderate" | "High"
    notes: Optional[str] = None


class ChatRequest(BaseModel):
    message: str
    userId: str

# ============================================
# FARMER APIS
# ============================================

@app.post("/survey/book")
async def book_survey(request: BookSurveyRequest, user=Depends(get_current_user)):
    """Farmer books a new survey"""

    survey_data = {
        "userId": user["uid"],
        "farmerName": user.get("name", user["email"]),
        "farmerEmail": user["email"],
        "city": request.city,
        "soilType": request.soilType,
        "moisture": request.moisture if request.moisture is not None else None,
        "temperature": request.temperature if request.temperature is not None else None,
        "year": request.year,
        "season": request.season,
        "status": "pending",
        "predictedRainfall": None,
        "recommendedCrop": None,
        "createdAt": datetime.now(),
        "emailSent": False,
    }

    try:
        n, p, k = get_soil_nutrients(request.soilType)
        survey_data["nitrogen"] = n
        survey_data["phosphorus"] = p
        survey_data["potassium"] = k
    except Exception:
        survey_data["nitrogen"] = survey_data["phosphorus"] = survey_data["potassium"] = None

    doc_ref = db.collection("farm_inputs").add(survey_data)
    survey_id = doc_ref[1].id

    return {
        "surveyId": survey_id,
        "status": "pending",
        "message": "Survey booked successfully. Admin will process it soon.",
    }


@app.get("/survey/my-surveys")
async def get_my_surveys(user=Depends(get_current_user)):
    """Get all surveys for logged-in farmer"""

    surveys = (
        db.collection("farm_inputs")
        .where("userId", "==", user["uid"])
        .order_by("createdAt", direction=firestore.Query.DESCENDING)
        .stream()
    )

    result = []
    for survey in surveys:
        data = survey.to_dict()
        data["surveyId"] = survey.id
        if data.get("createdAt"):
            data["createdAt"] = data["createdAt"].isoformat()
        if data.get("completedAt"):
            data["completedAt"] = data["completedAt"].isoformat()
        result.append(data)

    return {"surveys": result}


@app.post("/review/add")
async def add_review(request: ReviewRequest, user=Depends(get_current_user)):
    """Add review for a completed survey"""

    survey_doc = db.collection("farm_inputs").document(request.surveyId).get()
    if not survey_doc.exists:
        raise HTTPException(status_code=404, detail="Survey not found")

    survey_data = survey_doc.to_dict()
    if survey_data["userId"] != user["uid"]:
        raise HTTPException(status_code=403, detail="Not your survey")

    if survey_data["status"] != "completed":
        raise HTTPException(status_code=400, detail="Can only review completed surveys")

    review_data = {
        "userId": user["uid"],
        "surveyId": request.surveyId,
        "rating": request.rating,
        "comment": request.comment,
        "createdAt": datetime.now(),
    }

    db.collection("reviews").add(review_data)
    return {"message": "Review added successfully"}


@app.get("/reviews/all")
async def get_all_reviews(user=Depends(get_current_user)):
    """Get all reviews (for farmers to see)"""

    reviews = (
        db.collection("reviews")
        .order_by("createdAt", direction=firestore.Query.DESCENDING)
        .limit(50)
        .stream()
    )

    result = []
    for review in reviews:
        data = review.to_dict()
        data["reviewId"] = review.id

        user_doc = db.collection("users").document(data["userId"]).get()
        if user_doc.exists:
            data["farmerName"] = user_doc.to_dict().get("name", "Anonymous")

        if data.get("createdAt"):
            data["createdAt"] = data["createdAt"].isoformat()
        result.append(data)

    return {"reviews": result}

# ============================================
# ADMIN APIS
# ============================================

@app.get("/admin/pending-surveys")
async def get_pending_surveys(admin=Depends(verify_admin)):
    """Admin: Get all pending surveys"""

    surveys = (
        db.collection("farm_inputs")
        .where("status", "==", "pending")
        .order_by("createdAt", direction=firestore.Query.DESCENDING)
        .stream()
    )

    result = []
    for survey in surveys:
        data = survey.to_dict()
        data["surveyId"] = survey.id
        if data.get("createdAt"):
            data["createdAt"] = data["createdAt"].isoformat()
        result.append(data)

    return {"pending_surveys": result}


@app.post("/admin/process-survey")
async def process_survey(request: AdminActionRequest, admin=Depends(verify_admin)):
    """Admin: Approve/reject survey and run ML prediction.

    For 'approve', the request must include:
      - moisture (float, 0–100 %)
      - temperatureCategory ("Low" | "Moderate" | "High")

    The backend maps temperatureCategory → numeric:
      Low = 20, Moderate = 28, High = 35
    """

    survey_ref = db.collection("farm_inputs").document(request.surveyId)
    survey_doc = survey_ref.get()

    if not survey_doc.exists:
        raise HTTPException(status_code=404, detail="Survey not found")

    survey_data = survey_doc.to_dict()

    if request.action == "approve":
        if request.moisture is None:
            raise HTTPException(status_code=400, detail="moisture is required for approval")
        if not request.temperatureCategory:
            raise HTTPException(status_code=400, detail="temperatureCategory is required for approval")
        if request.temperatureCategory not in TEMP_CATEGORY_MAP:
            raise HTTPException(
                status_code=400,
                detail=f"temperatureCategory must be one of {list(TEMP_CATEGORY_MAP.keys())}",
            )

        temperature_numeric = TEMP_CATEGORY_MAP[request.temperatureCategory]

        try:
            ml_result = run_ml_pipeline(
                city=survey_data["city"],
                year=survey_data["year"],
                season=survey_data["season"],
                soil_type=survey_data["soilType"],
                moisture=request.moisture,
                temperature=temperature_numeric,
            )

            survey_ref.update({
                "status": "completed",
                "moisture": request.moisture,
                "temperatureCategory": request.temperatureCategory,
                "temperature": temperature_numeric,
                "predicted_rainfall_mm": ml_result["predicted_rainfall_mm"],
                "recommended_crop": ml_result["recommended_crop"],
                "nitrogen": ml_result["nitrogen"],
                "phosphorus": ml_result["phosphorus"],
                "potassium": ml_result["potassium"],
                "completedAt": datetime.now(),
                "adminNotes": request.notes,
            })

            send_prediction_email(
                email=survey_data["farmerEmail"],
                name=survey_data["farmerName"],
                crop=ml_result["recommended_crop"],
                rainfall=ml_result["predicted_rainfall_mm"],
                survey_id=request.surveyId,
            )

            return {
                "status": "success",
                "message": "Survey approved and processed",
                "crop": ml_result["recommended_crop"],
                "rainfall": ml_result["predicted_rainfall_mm"],
                "temperatureNumeric": temperature_numeric,
            }

        except HTTPException:
            raise
        except Exception as e:
            survey_ref.update({
                "status": "failed",
                "adminNotes": f"ML Error: {str(e)}",
            })
            raise HTTPException(status_code=500, detail=f"ML processing failed: {str(e)}")

    elif request.action == "reject":
        survey_ref.update({
            "status": "rejected",
            "adminNotes": request.notes,
            "completedAt": datetime.now(),
        })
        return {"status": "rejected", "message": "Survey rejected"}

    else:
        raise HTTPException(status_code=400, detail="Invalid action. Use 'approve' or 'reject'.")


@app.get("/admin/all-surveys")
async def get_all_surveys(admin=Depends(verify_admin)):
    """Admin: Get all surveys"""

    surveys = (
        db.collection("farm_inputs")
        .order_by("createdAt", direction=firestore.Query.DESCENDING)
        .limit(100)
        .stream()
    )

    result = []
    for survey in surveys:
        data = survey.to_dict()
        data["surveyId"] = survey.id
        if data.get("createdAt"):
            data["createdAt"] = data["createdAt"].isoformat()
        if data.get("completedAt"):
            data["completedAt"] = data["completedAt"].isoformat()
        result.append(data)

    return {"surveys": result}

# ============================================
# EMAIL SERVICE
# ============================================

def send_prediction_email(email: str, name: str, crop: str, rainfall: float, survey_id: str):
    """Send email with prediction results"""

    subject = "Your Agro AI Survey Results Are Ready!"

    body = f"""
    <html>
    <body>
        <h2>Hello {name}!</h2>
        <p>Your survey (ID: {survey_id}) has been processed.</p>

        <h3>Results:</h3>
        <ul>
            <li><b>Recommended Crop:</b> {crop}</li>
            <li><b>Predicted Rainfall:</b> {rainfall:.2f} mm</li>
        </ul>

        <p>You can view full details in the app.</p>

        <br>
        <p>Happy Farming! 🌾</p>
        <p><i>Agro AI Team</i></p>
    </body>
    </html>
    """

    try:
        msg = MIMEMultipart()
        msg["From"] = SMTP_CONFIG["email"]
        msg["To"] = email
        msg["Subject"] = subject
        msg.attach(MIMEText(body, "html"))

        with smtplib.SMTP(SMTP_CONFIG["server"], SMTP_CONFIG["port"]) as server:
            server.starttls()
            server.login(SMTP_CONFIG["email"], SMTP_CONFIG["password"])
            server.send_message(msg)

        db.collection("farm_inputs").document(survey_id).update({"emailSent": True})

    except Exception as e:
        print(f"Email failed: {e}")

# ============================================
# GEMINI CHATBOT API
# ============================================

@app.post("/chat")
async def chat_with_gemini(request: ChatRequest, user=Depends(get_current_user)):
    """Gemini chatbot for farming advice"""

    # Get survey context
    survey_context = ""
    try:
        surveys = (
            db.collection("farm_inputs")
            .where("userId", "==", user["uid"])
            .where("status", "==", "completed")
            .order_by("createdAt", direction=firestore.Query.DESCENDING)
            .limit(3)
            .stream()
        )
        for survey in surveys:
            data = survey.to_dict()
            if data.get("recommended_crop"):
                survey_context += (
                    f"- Past: {data.get('recommended_crop')} "
                    f"in {data.get('city', '')}\n"
                )
    except Exception:
        pass

    prompt = (
        "You are a helpful farming assistant for Indian farmers. "
        "Provide practical, concise agricultural advice in simple language. "
        "Focus on crops, soil health, irrigation, and weather.\n"
    )
    if survey_context:
        prompt += f"\nFarmer's past survey results:\n{survey_context}"
    prompt += f"\nFarmer's question: {request.message}"

    # Try primary model → retry once on 429 → fallback model → friendly message
    models_to_try = [GEMINI_MODEL, GEMINI_FALLBACK_MODEL]

    for model in models_to_try:
        try:
            response = gemini_client.models.generate_content(
                model=model,
                contents=prompt,
            )
            return {"response": response.text}

        except Exception as e:
            err = str(e)
            print(f"[/chat] {model} error: {err}")

            # On 429 / quota error: wait briefly and retry with same model once
            if "429" in err or "RESOURCE_EXHAUSTED" in err:
                # Retry once after a short pause before moving to fallback
                if model == GEMINI_MODEL:
                    try:
                        time.sleep(5)  # short back-off
                        response = gemini_client.models.generate_content(
                            model=model,
                            contents=prompt,
                        )
                        return {"response": response.text}
                    except Exception:
                        print(f"[/chat] {model} retry also failed, trying fallback...")
                continue  # try next model in list

            # Non-quota error — still try fallback model before giving up
            continue

    # All attempts exhausted — return friendly message, NEVER 500
    return {
        "response": (
            "\U0001F33E Our AI assistant is currently busy due to high demand. "
            "Please try again in a minute or two. "
            "Your farming questions will be answered then!"
        )
    }

# ============================================
# UTILITY APIS
# ============================================

@app.get("/cities")
async def get_cities():
    return {"cities": ["Pune", "Mumbai", "Delhi", "Bangalore", "Hyderabad"]}


@app.get("/soil-types")
async def get_soil_types():
    return {"soil_types": ["Black", "Red", "Alluvial", "Laterite", "Desert"]}


@app.get("/survey/{survey_id}")
async def get_survey_details(survey_id: str, user=Depends(get_current_user)):
    """Get specific survey details"""

    survey_doc = db.collection("farm_inputs").document(survey_id).get()
    if not survey_doc.exists:
        raise HTTPException(status_code=404, detail="Survey not found")

    data = survey_doc.to_dict()

    user_doc = db.collection("users").document(user["uid"]).get()
    is_admin = user_doc.exists and user_doc.to_dict().get("role") == "admin"

    if data["userId"] != user["uid"] and not is_admin:
        raise HTTPException(status_code=403, detail="Access denied")

    data["surveyId"] = survey_id
    if data.get("createdAt"):
        data["createdAt"] = data["createdAt"].isoformat()
    if data.get("completedAt"):
        data["completedAt"] = data["completedAt"].isoformat()

    return data
