from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import Optional
from ml_pipeline import process_farm_request, get_latest_farm_data, process_latest_farm_entry
from datetime import datetime

app = FastAPI(title="Agro AI ML API", description="ML Pipeline for Rainfall Prediction & Crop Recommendation")

# Enable CORS for Flutter app
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # In production, replace with your Flutter app's domain
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ============================================
# Request/Response Models
# ============================================

class FarmRequest(BaseModel):
    city: str  # Pune, Mumbai, Delhi, Bangalore, Hyderabad
    year: int
    season: str  # Summer, Monsoon, Winter
    soil_type: str  # Black, Red, Alluvial, etc.
    moisture: float  # Soil moisture percentage
    temperature: float  # Temperature in Celsius

class FarmResponse(BaseModel):
    success: bool
    document_id: Optional[str] = None
    city: Optional[str] = None
    year: Optional[int] = None
    season: Optional[str] = None
    soil_type: Optional[str] = None
    moisture: Optional[float] = None
    temperature: Optional[float] = None
    nitrogen: Optional[float] = None
    phosphorus: Optional[float] = None
    potassium: Optional[float] = None
    predicted_rainfall_mm: Optional[float] = None
    recommended_crop: Optional[str] = None
    timestamp: Optional[str] = None
    error: Optional[str] = None

# ============================================
# API Endpoints
# ============================================

@app.get("/")
def root():
    return {
        "message": "Agro AI ML API",
        "version": "1.0",
        "endpoints": [
            "/predict",
            "/latest",
            "/health"
        ]
    }

@app.get("/health")
def health_check():
    return {"status": "healthy", "timestamp": datetime.now()}

@app.post("/predict", response_model=FarmResponse)
async def predict_crop(request: FarmRequest):
    """
    Main endpoint for crop prediction and rainfall forecast
    """
    try:
        result = process_farm_request(
            city=request.city,
            year=request.year,
            season=request.season,
            soil_type=request.soil_type,
            moisture=request.moisture,
            temperature=request.temperature
        )
        
        return FarmResponse(
            success=True,
            document_id=result.get("document_id"),
            city=result.get("city"),
            year=result.get("year"),
            season=result.get("season"),
            soil_type=result.get("soil_type"),
            moisture=result.get("moisture"),
            temperature=result.get("temperature"),
            nitrogen=result.get("nitrogen"),
            phosphorus=result.get("phosphorus"),
            potassium=result.get("potassium"),
            predicted_rainfall_mm=result.get("predicted_rainfall_mm"),
            recommended_crop=result.get("recommended_crop"),
            timestamp=str(result.get("timestamp"))
        )
    
    except Exception as e:
        return FarmResponse(success=False, error=str(e))

@app.get("/latest", response_model=FarmResponse)
async def get_latest():
    """
    Get the latest prediction from Firebase
    """
    try:
        result = process_latest_farm_entry()
        
        if "error" in result:
            return FarmResponse(success=False, error=result["error"])
        
        return FarmResponse(
            success=True,
            document_id=result.get("doc_id"),
            city=result.get("city"),
            year=result.get("year"),
            season=result.get("season"),
            soil_type=result.get("soil_type"),
            moisture=result.get("moisture"),
            temperature=result.get("temperature"),
            nitrogen=result.get("nitrogen"),
            phosphorus=result.get("phosphorus"),
            potassium=result.get("potassium"),
            predicted_rainfall_mm=result.get("predicted_rainfall_mm"),
            recommended_crop=result.get("recommended_crop"),
            timestamp=str(result.get("timestamp"))
        )
    
    except Exception as e:
        return FarmResponse(success=False, error=str(e))

@app.get("/cities")
def get_supported_cities():
    """Get list of supported cities"""
    return {
        "cities": ["Pune", "Mumbai", "Delhi", "Bangalore", "Hyderabad"]
    }

@app.get("/seasons")
def get_supported_seasons():
    """Get list of supported seasons"""
    return {
        "seasons": ["Summer", "Monsoon", "Winter"]
    }