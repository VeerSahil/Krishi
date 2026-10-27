"""Rainfall estimation and crop matching using the bundled demonstration CSVs.

Predictions work without Firebase, Gemini, or Arduino. These small datasets
are not a validated agricultural forecasting service.
"""
import math
from datetime import datetime, timezone
from functools import lru_cache

import pandas as pd
from sklearn.ensemble import RandomForestRegressor, RandomForestClassifier

from config import BASE_DIR, get_db

CITY_MAP = {"Pune": 0, "Mumbai": 1, "Delhi": 2, "Bangalore": 3, "Hyderabad": 4}
SEASON_MAP = {"Summer": 0, "Monsoon": 1, "Winter": 2}
TEMP_CATEGORY_MAP = {"Low": 20.0, "Moderate": 28.0, "High": 35.0}
MOISTURE_CATEGORY_MAP = {"Low": 25.0, "Medium": 50.0, "Moderate": 50.0, "High": 75.0}


@lru_cache(maxsize=1)
def load_crop_data():
    crops = pd.read_csv(BASE_DIR / "crop_recommendation.csv")
    soils = pd.read_csv(BASE_DIR / "soil_nutrients.csv")
    numeric = ["rainfall_mm", "moisture", "temperature", "nitrogen", "phosphorus", "potassium"]
    if crops.empty or soils.empty or crops[numeric].isna().any().any():
        raise ValueError("Crop or soil dataset is empty or contains missing values")
    return crops, soils


def supported_soil_types():
    return load_crop_data()[1]["soil_type"].tolist()


def normalize_choice(value, choices, label):
    matches = {str(choice).casefold(): choice for choice in choices}
    result = matches.get(str(value).strip().casefold())
    if result is None:
        raise ValueError(f"Unsupported {label}. Choose from: {', '.join(choices)}")
    return result


def normalize_temperature_category(value):
    if str(value).strip().casefold() == "medium":
        return "Moderate"
    return normalize_choice(value, TEMP_CATEGORY_MAP, "temperature category")


def bounded_number(value, low, high, label):
    value = float(value)
    if not math.isfinite(value) or not low <= value <= high:
        raise ValueError(f"{label} must be between {low} and {high}")
    return value


@lru_cache(maxsize=1)
def train_rainfall_model():
    frames = []
    for city in CITY_MAP:
        frame = pd.read_csv(BASE_DIR / f"{city.lower()}_rainfall.csv")
        # API inputs identify a season, while rows contain monthly amounts.
        # Sum only the months actually present, never a monthly average.
        frame = frame.groupby(["year", "season"], as_index=False)["rainfall_mm"].sum()
        frame["city"] = CITY_MAP[city]
        frame["season"] = frame["season"].map(SEASON_MAP)
        frames.append(frame)
    training = pd.concat(frames, ignore_index=True)
    model = RandomForestRegressor(n_estimators=100, random_state=42, n_jobs=1)
    model.fit(training[["city", "year", "season"]], training["rainfall_mm"])
    # The old pickle used monthly means and another sklearn version. Rebuild
    # deterministically in memory without changing the historical artifact.
    return model


def predict_rainfall(city, year, season):
    city = normalize_choice(city, CITY_MAP, "city")
    season = normalize_choice(season, SEASON_MAP, "season")
    year = int(bounded_number(year, 1900, 2100, "year"))
    features = pd.DataFrame([[CITY_MAP[city], year, SEASON_MAP[season]]],
                            columns=["city", "year", "season"])
    return round(float(train_rainfall_model().predict(features)[0]), 2)


def get_soil_nutrients(soil_type):
    soil_type = normalize_choice(soil_type, supported_soil_types(), "soil type")
    soil = load_crop_data()[1].set_index("soil_type").loc[soil_type]
    return tuple(float(soil[key]) for key in ("nitrogen", "phosphorus", "potassium"))


CROP_FEATURES = ["rainfall_mm", "moisture", "temperature", "nitrogen", "phosphorus", "potassium"]


@lru_cache(maxsize=1)
def train_crop_model():
    crops = load_crop_data()[0]
    model = RandomForestClassifier(n_estimators=200, random_state=42, n_jobs=1, max_features=None)
    model.fit(crops[CROP_FEATURES], crops["crop"])
    return model


def recommend_crop(nitrogen, phosphorus, potassium, soil_type=None,
                   moisture=None, temperature=None, rainfall=None):
    """Classify the crop. Full survey inputs always supply all six features."""
    values = {"nitrogen": nitrogen, "phosphorus": phosphorus, "potassium": potassium,
              "moisture": moisture, "temperature": temperature, "rainfall_mm": rainfall}
    # Compatibility for old NPK-only notebooks, not used for field submissions.
    medians = load_crop_data()[0][CROP_FEATURES].median()
    values = {key: float(value) if value is not None else float(medians[key])
              for key, value in values.items()}
    if not all(math.isfinite(value) for value in values.values()):
        raise ValueError("Crop inputs must be finite numbers")
    features = pd.DataFrame([[values[key] for key in CROP_FEATURES]], columns=CROP_FEATURES)
    return str(train_crop_model().predict(features)[0])


def run_ml_pipeline(city, year, season, soil_type, moisture, temperature,
                    nitrogen=None, phosphorus=None, potassium=None):
    city = normalize_choice(city, CITY_MAP, "city")
    season = normalize_choice(season, SEASON_MAP, "season")
    soil_type = normalize_choice(soil_type, supported_soil_types(), "soil type")
    if isinstance(moisture, str):
        try:
            moisture = float(moisture)
        except ValueError:
            moisture = MOISTURE_CATEGORY_MAP[
                normalize_choice(moisture, MOISTURE_CATEGORY_MAP, "moisture category")]
    if isinstance(temperature, str):
        try:
            temperature = float(temperature)
        except ValueError:
            temperature = TEMP_CATEGORY_MAP[normalize_temperature_category(temperature)]
    moisture = bounded_number(moisture, 0, 100, "moisture")
    temperature = bounded_number(temperature, -40, 80, "temperature")
    rainfall = predict_rainfall(city, year, season)
    supplied = (nitrogen, phosphorus, potassium)
    if any(value is not None for value in supplied) and not all(value is not None for value in supplied):
        raise ValueError("Supply all three nutrient values")
    nutrient_source = "manual" if all(value is not None for value in supplied) else "soil_type_dataset"
    if nutrient_source == "manual":
        nitrogen, phosphorus, potassium = (
            bounded_number(value, 0, 10000, label)
            for value, label in zip(supplied, ("nitrogen", "phosphorus", "potassium")))
    else:
        nitrogen, phosphorus, potassium = get_soil_nutrients(soil_type)
    crop = recommend_crop(nitrogen, phosphorus, potassium, soil_type, moisture, temperature, rainfall)
    return {"city": city, "year": int(year), "season": season, "soil_type": soil_type,
            "moisture": moisture, "temperature": temperature, "nitrogen": nitrogen,
            "phosphorus": phosphorus, "potassium": potassium, "predicted_rainfall_mm": rainfall,
            "recommended_crop": crop, "timestamp": datetime.now(timezone.utc),
            "rainfall_basis": "sum_of_available_months_per_season",
            "recommendation_method": "random_forest_classifier", "nutrientSource": nutrient_source}


# Retained for older notebooks. API endpoints use per-user queries instead.
def save_to_firebase(data):
    ref = get_db().collection("farm_inputs").document()
    ref.set(data)
    return ref.id


def get_latest_farm_data():
    docs = get_db().collection("farm_inputs").order_by(
        "createdAt", direction="DESCENDING").limit(1).stream()
    for doc in docs:
        return {**doc.to_dict(), "doc_id": doc.id}
    return None


def update_rainfall_in_firebase(doc_id, rainfall):
    get_db().collection("farm_inputs").document(doc_id).update(
        {"predicted_rainfall_mm": rainfall, "predictedRainfall": rainfall})
    return True


def process_farm_request(city, year, season, soil_type, moisture, temperature):
    result = run_ml_pipeline(city, year, season, soil_type, moisture, temperature)
    result["createdAt"] = result["timestamp"]
    result["document_id"] = save_to_firebase(result)
    return result


def process_latest_farm_entry():
    data = get_latest_farm_data()
    if data is None:
        return {"error": "No farm data found"}
    result = run_ml_pipeline(data["city"], data["year"], data["season"],
                             data.get("soilType", data.get("soil_type")),
                             data["moisture"], data["temperature"])
    get_db().collection("farm_inputs").document(data["doc_id"]).update(result)
    return {**data, **result}


if __name__ == "__main__":
    import json
    print(json.dumps(run_ml_pipeline("Pune", 2026, "Monsoon", "Black", 45, 28, 400, 200, 150),
                     default=str, indent=2))
