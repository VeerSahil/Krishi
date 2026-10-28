"""Validated request contracts; existing Flutter field names are preserved."""
from datetime import date, datetime, timezone
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

from ml_pipeline import (CITY_MAP, SEASON_MAP, normalize_choice,
                         normalize_temperature_category, supported_soil_types)


class RequestModel(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True, allow_inf_nan=False)


DEMO_TEMPERATURE_NOTICE = "Demo recommendation: temperature was simulated, not measured."


def temperature_metadata(source, category=None):
    simulated = source == "simulated"
    return {"temperatureSource": source, "temperatureCategory": category,
            "recommendationIsDemo": simulated,
            "recommendationNotice": DEMO_TEMPERATURE_NOTICE if simulated else None}


class TemperatureInput(RequestModel):
    temperature: float = Field(ge=-40, le=80)
    temperatureSource: Literal["measured", "simulated"] = "measured"
    temperatureCategory: Literal["low", "moderate", "high"] | None = None

    @model_validator(mode="after")
    def validate_simulated_temperature(self):
        if self.temperatureSource == "simulated":
            value = self.temperature
            valid = {"low": 15 <= value < 20, "moderate": 20 <= value < 30,
                     "high": 30 <= value <= 35}
            if not valid.get(self.temperatureCategory, False):
                raise ValueError("Demo temperature must match its category: low 15–<20, moderate 20–<30, high 30–35.")
        elif self.temperatureCategory is not None:
            raise ValueError("A demo category requires temperatureSource simulated.")
        return self

    def temperature_metadata(self):
        return temperature_metadata(self.temperatureSource, self.temperatureCategory)


class FarmRequest(TemperatureInput):
    city: str
    year: int = Field(default_factory=lambda: datetime.now(timezone.utc).year, ge=1900, le=2100)
    season: str = "Monsoon"
    soil_type: str
    nitrogen: float = Field(ge=0, le=10000)
    phosphorus: float = Field(ge=0, le=10000)
    potassium: float = Field(ge=0, le=10000)
    moisture: float = Field(ge=0, le=100)

    @model_validator(mode="after")
    def validate_location(self):
        self.city = normalize_choice(self.city, CITY_MAP, "city")
        self.season = normalize_choice(self.season, SEASON_MAP, "season")
        self.soil_type = normalize_choice(self.soil_type, supported_soil_types(), "soil type")
        return self


class CropPlanRequest(RequestModel):
    surveyId: str = Field(min_length=1, max_length=200, pattern=r"^[^/]+$")
    proposedCrop: str = Field(min_length=2, max_length=80)
    sowingDate: date | None = None
    irrigation: Literal["unknown", "rainfed", "irrigated", "supplemental"] = "unknown"


class BookSurveyRequest(RequestModel):
    farmId: str | None = Field(default=None, min_length=1, max_length=200, pattern=r"^[^/]+$")
    farmName: str = Field(default="My farm", min_length=1, max_length=100)
    farmAddress: str = Field(min_length=8, max_length=500)
    contactPhone: str | None = Field(default=None, min_length=7, max_length=25, pattern=r"^[+0-9() -]+$")
    city: str
    soilType: str
    year: int = Field(default_factory=lambda: datetime.now(timezone.utc).year, ge=1900, le=2100)
    season: str = "Monsoon"
    farmerName: str | None = Field(default="", max_length=200)
    farmerEmail: str | None = Field(default="", max_length=320)
    moisture: float | None = Field(default=None, ge=0, le=100)
    temperature: float | None = Field(default=None, ge=-40, le=80)

    @model_validator(mode="after")
    def validate_location(self):
        self.city = normalize_choice(self.city, CITY_MAP, "city")
        self.season = normalize_choice(self.season, SEASON_MAP, "season")
        self.soilType = normalize_choice(self.soilType, supported_soil_types(), "soil type")
        return self


class ReviewRequest(RequestModel):
    surveyId: str = Field(min_length=1, max_length=200, pattern=r"^[^/]+$")
    rating: int = Field(ge=1, le=5)
    comment: str = Field(min_length=1, max_length=2000)


class AdminActionRequest(RequestModel):
    surveyId: str = Field(min_length=1, max_length=200, pattern=r"^[^/]+$")
    action: Literal["approve", "reject", "publish"]
    teamId: str | None = Field(default=None, min_length=1, max_length=128, pattern=r"^[^/]+$")
    notes: str | None = Field(default=None, max_length=2000)

    @model_validator(mode="after")
    def approval_requires_team(self):
        if self.action == "approve" and self.teamId is None:
            raise ValueError("Choose a field team member before approving the visit")
        return self


class FieldReadingsRequest(TemperatureInput):
    clientSubmissionId: str | None = Field(default=None, min_length=16, max_length=80, pattern=r"^[a-zA-Z0-9_-]+$")
    capturedAt: datetime | None = None
    nutrientUnit: Literal["unknown", "mg/kg", "kg/ha"] = "unknown"
    nutrientSource: Literal["manual", "soil_test"] = "manual"
    soilTestReference: str | None = Field(default=None, max_length=200)
    soilTestAttachmentUrl: str | None = Field(default=None, max_length=1500)
    moistureSource: Literal["manual", "sensor"] = "manual"
    moistureUnit: Literal["relative_percent", "vwc_percent", "unknown"] = "unknown"

    @model_validator(mode="after")
    def validate_evidence(self):
        if self.soilTestAttachmentUrl:
            from urllib.parse import urlparse
            url = urlparse(self.soilTestAttachmentUrl)
            if url.scheme != "https" or not url.hostname or url.username or url.password:
                raise ValueError("Report attachments must use an HTTPS link without embedded credentials.")
        if self.nutrientSource == "soil_test" and (not self.soilTestReference or self.nutrientUnit == "unknown"):
            raise ValueError("A soil test requires a reference and nutrient units.")
        if self.capturedAt is not None:
            if self.capturedAt.tzinfo is None or self.capturedAt > datetime.now(timezone.utc):
                raise ValueError("Capture time must include a timezone and cannot be in the future.")
        return self

    moisture: float = Field(ge=0, le=100)
    nitrogen: float = Field(ge=0, le=10000)
    phosphorus: float = Field(ge=0, le=10000)
    potassium: float = Field(ge=0, le=10000)
    notes: str | None = Field(default=None, max_length=2000)


class SupportRequest(RequestModel):
    subject: str = Field(min_length=3, max_length=120)
    message: str = Field(min_length=5, max_length=4000)
    surveyId: str | None = Field(default=None, min_length=1, max_length=200, pattern=r"^[^/]+$")


class SupportReplyRequest(RequestModel):
    reply: str = Field(min_length=1, max_length=4000)


class ChatRequest(RequestModel):
    language: Literal["en", "hi", "mr"] = "en"
    message: str = Field(min_length=1, max_length=4000)
    # Accepted for compatibility; identity always comes from the verified token.
    userId: str | None = None
