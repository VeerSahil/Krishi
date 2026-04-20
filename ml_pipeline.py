#!/usr/bin/env python
# coding: utf-8

# In[2]:


import firebase_admin
from firebase_admin import credentials, firestore
import pandas as pd
import numpy as np
import joblib
from datetime import datetime
from sklearn.ensemble import RandomForestRegressor

# Add this after your imports
temp_category_map = {
    "Low": 20,      # Treat as 20°C
    "Medium": 25,   # Treat as 25°C  
    "High": 35      # Treat as 35°C
}
# ============================================
# 1. INITIALIZATION
# ============================================

# Initialize Firebase (only once) — works both locally and on Render
if not firebase_admin._apps:
    import os, json, base64
    fb_json_b64 = os.getenv("FIREBASE_KEY_JSON")
    if fb_json_b64:
        cred_dict = json.loads(base64.b64decode(fb_json_b64))
        cred = credentials.Certificate(cred_dict)
    else:
        cred = credentials.Certificate("firebase_key.json")
    firebase_admin.initialize_app(cred)

db = firestore.client()

# Load the pre-trained rainfall model (create if doesn't exist)
def train_rainfall_model():
    """Train and save the rainfall prediction model"""
    try:
        model = joblib.load("rainfall_model.pkl")
        print("Model loaded successfully")
        return model
    except:
        print("Training new rainfall model...")

        # Load datasets
        pune = pd.read_csv("pune_rainfall.csv")
        mumbai = pd.read_csv("mumbai_rainfall.csv")
        delhi = pd.read_csv("delhi_rainfall.csv")
        bangalore = pd.read_csv("bangalore_rainfall.csv")
        hyderabad = pd.read_csv("hyderabad_rainfall.csv")

        # Add city column
        pune["city"] = "Pune"
        mumbai["city"] = "Mumbai"
        delhi["city"] = "Delhi"
        bangalore["city"] = "Bangalore"
        hyderabad["city"] = "Hyderabad"

        # Combine datasets
        df = pd.concat([pune, mumbai, delhi, bangalore, hyderabad])

        # Encode categorical variables
        city_map = {"Pune": 0, "Mumbai": 1, "Delhi": 2, "Bangalore": 3, "Hyderabad": 4}
        season_map = {"Summer": 0, "Monsoon": 1, "Winter": 2}

        df["city"] = df["city"].map(city_map)
        df["season"] = df["season"].map(season_map)

        # Train model
        X = df[["city", "year", "season"]]
        y = df["rainfall_mm"]

        model = RandomForestRegressor(n_estimators=100, random_state=42)
        model.fit(X, y)

        # Save model
        joblib.dump(model, "rainfall_model.pkl")
        print("Model trained and saved")

        return model

# Load crop recommendation data
def load_crop_data():
    """Load and prepare crop recommendation dataset"""
    crop_df = pd.read_csv("crop_recommendation.csv")
    soil_df = pd.read_csv("soil_nutrients.csv")
    return crop_df, soil_df

# Initialize models and data
rainfall_model = train_rainfall_model()
crop_df, soil_df = load_crop_data()

# ============================================
# 2. RAINFALL PREDICTION FUNCTION
# ============================================

def predict_rainfall(city, year, season):
    """
    Predict rainfall based on city, year, and season

    Args:
        city: "Pune", "Mumbai", "Delhi", "Bangalore", "Hyderabad"
        year: int (e.g., 2026)
        season: "Summer", "Monsoon", "Winter"

    Returns:
        float: Predicted rainfall in mm
    """
    city_map = {"Pune": 0, "Mumbai": 1, "Delhi": 2, "Bangalore": 3, "Hyderabad": 4}
    season_map = {"Summer": 0, "Monsoon": 1, "Winter": 2}

    prediction = rainfall_model.predict([[
        city_map[city],
        year,
        season_map[season]
    ]])

    return float(prediction[0])

# ============================================
# 3. CROP RECOMMENDATION FUNCTION
# ============================================

def recommend_crop(nitrogen, phosphorus, potassium, soil_type=None, moisture=None, temperature=None):
    """
    Recommend crop based on soil nutrients and conditions

    Args:
        nitrogen: Soil nitrogen level
        phosphorus: Soil phosphorus level
        potassium: Soil potassium level
        soil_type: Optional - soil type for reference
        moisture: Optional - soil moisture
        temperature: Optional - temperature

    Returns:
        str: Recommended crop name
    """
    # Filter crops based on nutrient requirements
    filtered = crop_df[
        (crop_df["nitrogen"] <= nitrogen + 50) &
        (crop_df["phosphorus"] <= phosphorus + 50) &
        (crop_df["potassium"] <= potassium + 50)
    ]

    if len(filtered) == 0:
        # Fallback: get closest match
        filtered = crop_df.nsmallest(3, 
            abs(crop_df["nitrogen"] - nitrogen) + 
            abs(crop_df["phosphorus"] - phosphorus) + 
            abs(crop_df["potassium"] - potassium)
        )

    return filtered.iloc[0]["crop"]

# ============================================
# 4. SOIL NUTRIENTS FUNCTION
# ============================================

def get_soil_nutrients(soil_type):
    """
    Get soil nutrients based on soil type

    Args:
        soil_type: Type of soil (e.g., "Black", "Red", "Alluvial", etc.)

    Returns:
        tuple: (nitrogen, phosphorus, potassium)
    """
    soil_data = soil_df[soil_df["soil_type"] == soil_type]
    if len(soil_data) == 0:
        # Default values if soil type not found
        return 400, 200, 150

    return (
        float(soil_data["nitrogen"].values[0]),
        float(soil_data["phosphorus"].values[0]),
        float(soil_data["potassium"].values[0])
    )

# ============================================
# 5. COMPLETE PIPELINE FUNCTION
# ============================================

def run_ml_pipeline(city, year, season, soil_type, moisture, temperature):
    """
    Complete ML pipeline: predicts rainfall and recommends crop

    Args:
        city: City name
        year: Year
        season: Season
        soil_type: Soil type
        moisture: Soil moisture (%) OR "Low"/"Medium"/"High"
        temperature: Temperature (°C) OR "Low"/"Medium"/"High"

    Returns:
        dict: Contains rainfall prediction, crop recommendation, and soil data
    """
    # Convert categorical inputs to numerical values
    temp_category_map = {"Low": 20, "Medium": 25, "High": 35}
    moisture_category_map = {"Low": 25, "Medium": 50, "High": 75}

    if isinstance(temperature, str):
        temperature = temp_category_map.get(temperature, 25)
    if isinstance(moisture, str):
        moisture = moisture_category_map.get(moisture, 50)

    # Step 1: Predict rainfall
    rainfall = predict_rainfall(city, year, season)

    # Step 2: Get soil nutrients
    nitrogen, phosphorus, potassium = get_soil_nutrients(soil_type)

    # Step 3: Recommend crop
    recommended_crop = recommend_crop(nitrogen, phosphorus, potassium, soil_type, moisture, temperature)

    # Step 4: Return results
    result = {
        "city": city,
        "year": year,
        "season": season,
        "soil_type": soil_type,
        "moisture": moisture,
        "temperature": temperature,
        "nitrogen": nitrogen,
        "phosphorus": phosphorus,
        "potassium": potassium,
        "predicted_rainfall_mm": rainfall,
        "recommended_crop": recommended_crop,
        "timestamp": datetime.now()
    }

    return result

# ============================================
# 6. FIREBASE FUNCTIONS
# ============================================

def save_to_firebase(data):
    """
    Save ML pipeline results to Firebase Firestore

    Args:
        data: Dictionary with all farm data

    Returns:
        str: Document ID
    """
    doc_ref = db.collection("farm_inputs").document()
    doc_ref.set(data)
    return doc_ref.id

def get_latest_farm_data():
    """
    Get the most recent farm input from Firebase

    Returns:
        dict: Latest farm data or None if not found
    """
    docs = db.collection("farm_inputs")\
             .order_by("timestamp", direction=firestore.Query.DESCENDING)\
             .limit(1)\
             .stream()

    for doc in docs:
        data = doc.to_dict()
        data["doc_id"] = doc.id
        return data

    return None

def update_rainfall_in_firebase(doc_id, rainfall):
    """
    Update rainfall prediction in existing Firebase document

    Args:
        doc_id: Firebase document ID
        rainfall: Predicted rainfall value

    Returns:
        bool: Success status
    """
    try:
        doc_ref = db.collection("farm_inputs").document(doc_id)
        doc_ref.update({"rainfall": rainfall})
        return True
    except Exception as e:
        print(f"Error updating rainfall: {e}")
        return False

# ============================================
# 7. API-STYLE ENDPOINTS (for Flutter integration)
# ============================================

def process_farm_request(city, year, season, soil_type, moisture, temperature):
    """
    Main entry point for Flutter app to call

    Args:
        city, year, season, soil_type, moisture, temperature: Farm parameters

    Returns:
        dict: Complete results with document ID
    """
    # Run ML pipeline
    result = run_ml_pipeline(city, year, season, soil_type, moisture, temperature)

    # Save to Firebase
    doc_id = save_to_firebase(result)
    result["document_id"] = doc_id

    return result

def process_latest_farm_entry():
    """
    Process the latest farm entry from Firebase and update with rainfall

    Returns:
        dict: Updated farm data with predictions
    """
    # Get latest farm data
    farm_data = get_latest_farm_data()

    if not farm_data:
        return {"error": "No farm data found"}

    # Run prediction
    rainfall = predict_rainfall(
        farm_data["city"],
        farm_data["year"],
        farm_data["season"]
    )

    # Update in Firebase
    update_rainfall_in_firebase(farm_data["doc_id"], rainfall)

    # Get crop recommendation (if nutrients available)
    if "nitrogen" in farm_data and "phosphorus" in farm_data and "potassium" in farm_data:
        recommended_crop = recommend_crop(
            farm_data["nitrogen"],
            farm_data["phosphorus"],
            farm_data["potassium"]
        )

        doc_ref = db.collection("farm_inputs").document(farm_data["doc_id"])
        doc_ref.update({"recommended_crop": recommended_crop})

        farm_data["recommended_crop"] = recommended_crop

    farm_data["predicted_rainfall_mm"] = rainfall

    return farm_data

# ============================================
# 8. TEST/EXAMPLE USAGE
# ============================================

if __name__ == "__main__":
    # Example 1: Process a new farm request directly
    print("=" * 50)
    print("Example 1: New Farm Request")
    print("=" * 50)

    result = process_farm_request(
        city="Pune",
        year=2026,
        season="Monsoon",
        soil_type="Black",
        moisture=35.0,
        temperature=29.0
    )

    print(f"Document ID: {result['document_id']}")
    print(f"Predicted Rainfall: {result['predicted_rainfall_mm']:.2f} mm")
    print(f"Recommended Crop: {result['recommended_crop']}")
    print(f"Soil Nutrients - N:{result['nitrogen']}, P:{result['phosphorus']}, K:{result['potassium']}")

    # Example 2: Process latest entry from Firebase
    print("\n" + "=" * 50)
    print("Example 2: Process Latest Firebase Entry")
    print("=" * 50)

    latest_result = process_latest_farm_entry()
    print(f"Latest farm rainfall: {latest_result.get('predicted_rainfall_mm', 'N/A')} mm")
    print(f"Recommended crop: {latest_result.get('recommended_crop', 'N/A')}")


# In[ ]:





# In[ ]:




