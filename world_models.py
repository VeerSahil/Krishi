"""Contracts for permanent farm regions and transparent care-class policies."""
from typing import Literal
from pydantic import Field, model_validator
from schemas import RequestModel
from ml_pipeline import CITY_MAP, normalize_choice, supported_soil_types

ASSETS = {
    "potato": {"name": "Potato", "description": "Low leafy plants on earthen ridges", "family": "bush"},
    "wheat": {"name": "Wheat", "description": "Rows of slender stems and grain heads", "family": "grain"},
    "maize": {"name": "Maize", "description": "Tall stalks with broad leaves", "family": "stalk"},
    "rice": {"name": "Rice", "description": "Clusters of green blades in bunded beds", "family": "grass"},
    "cotton": {"name": "Cotton", "description": "Branching shrubs with cotton bolls", "family": "shrub"},
    "vegetables": {"name": "Vegetables", "description": "Compact leafy vegetable beds", "family": "leaf"},
}
POLICY_KEYS = {"moisture", "temperature", "nitrogen", "potassium"}

class CareRange(RequestModel):
    low: float
    high: float
    @model_validator(mode="after")
    def bounds(self):
        if self.low >= self.high: raise ValueError("Minimum must be lower than maximum")
        return self

class CarePolicy(RequestModel):
    name: str = Field(default="Prototype care bands", min_length=3, max_length=100)
    basis: Literal["demo_rules", "configured_rules"] = "demo_rules"
    moistureUnit: Literal["relative_percent", "vwc_percent"] = "relative_percent"
    nutrientUnit: Literal["unknown", "mg/kg", "kg/ha"] = "unknown"
    reference: str | None = Field(default=None, max_length=500)
    ranges: dict[str, CareRange] = Field(default_factory=lambda: {
        "moisture": CareRange(low=30, high=70), "temperature": CareRange(low=18, high=35),
        "nitrogen": CareRange(low=50, high=500), "potassium": CareRange(low=50, high=500)})
    @model_validator(mode="after")
    def validate_policy(self):
        if set(self.ranges) != POLICY_KEYS: raise ValueError("Supply moisture, temperature, nitrogen and potassium bands")
        limits = {"moisture": (0, 100), "temperature": (-40, 80), "nitrogen": (0, 10000), "potassium": (0, 10000)}
        for key, band in self.ranges.items():
            if band.low < limits[key][0] or band.high > limits[key][1]: raise ValueError(f"Invalid {key} band")
        if self.basis == "configured_rules" and (self.nutrientUnit == "unknown" or not self.reference):
            raise ValueError("Configured rules require nutrient units and a policy reference; this does not certify scientific validity")
        return self

class FarmRegionRequest(RequestModel):
    farmerId: str = Field(min_length=1, max_length=128, pattern=r"^[^/]+$")
    farmName: str = Field(min_length=1, max_length=100)
    farmAddress: str = Field(min_length=8, max_length=500)
    city: str
    soilType: str
    cropAsset: Literal["potato", "wheat", "maize", "rice", "cotton", "vegetables"]
    slot: int = Field(ge=1, le=10000)
    areaHectares: float | None = Field(default=None, gt=0, le=100000)
    policy: CarePolicy = Field(default_factory=CarePolicy)
    @model_validator(mode="after")
    def choices(self):
        self.city = normalize_choice(self.city, CITY_MAP, "city")
        self.soilType = normalize_choice(self.soilType, supported_soil_types(), "soil type")
        return self

class FarmPolicyRequest(RequestModel):
    version: int = Field(ge=1)
    policy: CarePolicy

class LinkSurveyRequest(RequestModel):
    surveyId: str = Field(min_length=1, max_length=200, pattern=r"^[^/]+$")

class FarmerReportRequest(RequestModel):
    model_config = {"extra": "forbid"}
    submissionId: str = Field(min_length=1, max_length=100)
    language: Literal["en", "hi", "mr"] = "en"
    summary: str = Field(min_length=10, max_length=2000)
    actions: list[str] = Field(min_length=1, max_length=6)
    @model_validator(mode="after")
    def action_lengths(self):
        self.actions = [value.strip() for value in self.actions]
        if any(not value or len(value) > 500 for value in self.actions): raise ValueError("Each action must contain 1-500 characters")
        return self
