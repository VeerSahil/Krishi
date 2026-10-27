import asyncio
from copy import deepcopy
from types import SimpleNamespace
from unittest.mock import AsyncMock
import ast

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient

from memory_loop import run_async
import chatbot
import config
import main
import field_workflow
from ml_pipeline import (get_soil_nutrients, load_crop_data, predict_rainfall,
                         recommend_crop, run_ml_pipeline)

FARMER = {"Authorization": "Bearer farmer"}
ADMIN = {"Authorization": "Bearer admin"}
OTHER = {"Authorization": "Bearer other"}
TEAM = {"Authorization": "Bearer team"}
TEAM_OTHER = {"Authorization": "Bearer team-other"}
BOOK = {"city": "Pune", "soilType": "Black", "season": "Monsoon", "year": 2026,
        "farmName": "My farm", "farmAddress": "Survey farm, Road 1, Pune"}
READINGS = {"moisture": 45, "temperature": 28, "nitrogen": 400,
            "phosphorus": 200, "potassium": 150, "notes": "Collected during field visit"}


@pytest.mark.parametrize("category,value", [
    ("low", 15), ("low", 19.9), ("moderate", 20), ("moderate", 29.9),
    ("high", 30), ("high", 35),
])
def test_simulated_temperature_boundary_values(category, value):
    from schemas import FieldReadingsRequest
    reading = FieldReadingsRequest(**{**READINGS, "temperature": value,
        "temperatureSource": "simulated", "temperatureCategory": category})
    assert reading.temperature_metadata()["recommendationIsDemo"] is True


@pytest.mark.parametrize("changes", [
    {"temperatureCategory": "low", "temperature": 20},
    {"temperatureCategory": "moderate", "temperature": 30},
    {"temperatureCategory": "high", "temperature": 29.9},
    {"temperatureCategory": "high", "temperature": 35.1},
    {"temperatureCategory": None},
    {"temperatureSource": "measured", "temperatureCategory": "moderate"},
])
def test_simulated_temperature_requires_a_matching_band(changes):
    from pydantic import ValidationError
    from schemas import FieldReadingsRequest
    with pytest.raises(ValidationError):
        FieldReadingsRequest(**{**READINGS, "temperatureSource": "simulated", **changes})


def test_simulated_temperature_stays_labelled_through_prediction_and_release(api):
    client, db = api
    survey_id = book(client)
    assert approve(client, survey_id).status_code == 200
    result = submit(client, survey_id, temperature=32.4, temperatureSource="simulated",
                    temperatureCategory="high", recommendationIsDemo=False)
    assert result.status_code == 200, result.text
    draft = db.collection("survey_predictions").document(survey_id).get().to_dict()
    assert draft["temperature"] == 32.4
    assert draft["recommendationIsDemo"] is True
    assert "simulated" in draft["recommendationNotice"]
    report = client.get(f"/survey/{survey_id}", headers=FARMER).json()
    assert report["temperatureSource"] == "simulated"
    assert "draftPrediction" not in report and report["recommended_crop"] is None
    released = publish(client, survey_id)
    assert released.status_code == 200, released.text
    assert released.json()["recommendationIsDemo"] is True
    farmer = client.get(f"/survey/{survey_id}", headers=FARMER).json()
    assert farmer["recommendationIsDemo"] is True and farmer["temperatureCategory"] == "high"
    assert "simulated" in farmer["recommendationNotice"]
    assert "DEMO: simulated temperature" in main.recent_chat_context(db, "farmer")


def test_admin_prediction_preview_also_labels_simulated_temperature(api):
    client, _ = api
    payload = {"city": "Pune", "year": 2026, "season": "Monsoon", "soil_type": "Black",
               **{key: value for key, value in READINGS.items() if key != "notes"},
               "temperatureSource": "simulated", "temperatureCategory": "moderate"}
    response = client.post("/predict", headers=ADMIN, json=payload)
    assert response.status_code == 200, response.text
    assert response.json()["recommendationIsDemo"] is True


def test_demo_email_preserves_temperature_provenance(api, monkeypatch):
    from schemas import DEMO_TEMPERATURE_NOTICE
    client, db = api
    survey_id = book(client)
    sent = []
    class SMTP:
        def __init__(self, *args, **kwargs): pass
        def __enter__(self): return self
        def __exit__(self, *args): pass
        def starttls(self): pass
        def login(self, *args): pass
        def send_message(self, message): sent.append(message)
    monkeypatch.setenv("SMTP_EMAIL", "test@example.invalid")
    monkeypatch.setenv("SMTP_PASSWORD", "test-only")
    monkeypatch.setattr(main.smtplib, "SMTP", SMTP)
    main.send_prediction_email("farmer@example.invalid", "Farmer", "Wheat", 100,
                               survey_id, db, DEMO_TEMPERATURE_NOTICE)
    assert "Demo" in sent[0]["Subject"]
    assert DEMO_TEMPERATURE_NOTICE in sent[0].get_payload(decode=True).decode("utf-8")


def book(client, **changes):
    response = client.post("/survey/book", json={**BOOK, **changes}, headers=FARMER)
    assert response.status_code == 200, response.text
    return response.json()["surveyId"]


def approve(client, survey_id, **changes):
    return client.post("/admin/process-survey", headers=ADMIN, json={
        "surveyId": survey_id, "action": "approve", "teamId": "team", **changes})


def submit(client, survey_id, **changes):
    return client.post(f"/team/visits/{survey_id}/readings", headers=TEAM,
                       json={**READINGS, **changes})


def publish(client, survey_id):
    return client.post("/admin/process-survey", headers=ADMIN, json={
        "surveyId": survey_id, "action": "publish"})


def complete(client, survey_id):
    assert approve(client, survey_id).status_code == 200
    assert submit(client, survey_id).status_code == 200
    assert publish(client, survey_id).status_code == 200


def test_full_farmer_admin_team_publish_lifecycle(api):
    client, db = api
    survey_id = book(client, farmerEmail="spoofed@example.invalid", moisture=99)
    data = db.collection("farm_inputs").document(survey_id).get().to_dict()
    assert data["status"] == "pending"
    assert data["moisture"] is None and data["nitrogen"] is None
    assert data["farmerEmail"] == "farmer@example.invalid"
    assert approve(client, survey_id).json()["status"] == "approved"
    assert "survey_predictions" not in db.data
    assert client.get("/team/visits", headers=TEAM).json()["visits"][0]["surveyId"] == survey_id
    assert client.post(f"/team/visits/{survey_id}/start", headers=TEAM).json()["status"] == "in_progress"
    response = submit(client, survey_id)
    assert response.status_code == 200, response.text
    assert response.json()["status"] == "awaiting_review"
    # The physical readings are visible for monitoring; the draft crop is private.
    raw = db.collection("farm_inputs").document(survey_id).get().to_dict()
    assert raw["moisture"] == 45 and raw["temperature"] == 28
    assert (raw["nitrogen"], raw["phosphorus"], raw["potassium"]) == (400, 200, 150)
    assert raw["nutrientSource"] == "manual"
    assert raw["recommended_crop"] is None and raw["predicted_rainfall_mm"] is None
    draft = db.collection("survey_predictions").document(survey_id).get().to_dict()
    assert draft["recommendation_method"] == "random_forest_classifier"
    assert draft["nitrogen"] == 400 and draft["submissionId"] == raw["measurementSubmissionId"]
    farmer = client.get(f"/survey/{survey_id}", headers=FARMER).json()
    admin = client.get(f"/survey/{survey_id}", headers=ADMIN).json()
    assert "draftPrediction" not in farmer and farmer["recommendedCrop"] is None
    assert admin["draftPrediction"]["recommended_crop"] == draft["recommended_crop"]
    assert client.get("/latest", headers=FARMER).json()["recommended_crop"] is None
    assert client.post("/review/add", headers=FARMER, json={
        "surveyId": survey_id, "rating": 5, "comment": "Not released yet"}).status_code == 400
    result = publish(client, survey_id)
    assert result.status_code == 200, result.text
    farmer = client.get(f"/survey/{survey_id}", headers=FARMER).json()
    assert farmer["status"] == "completed"
    assert farmer["recommendedCrop"] == farmer["recommended_crop"] == draft["recommended_crop"]
    assert farmer["emailSent"] is False
    assert farmer["emailStatus"] == "not_configured"
    assert publish(client, survey_id).status_code == 409
    assert submit(client, survey_id).status_code == 409
    review = {"surveyId": survey_id, "rating": 5, "comment": "Helpful result"}
    assert client.post("/review/add", headers=FARMER, json=review).status_code == 200
    assert client.post("/review/add", headers=FARMER, json=review).status_code == 409
    before = deepcopy(db.data)
    assert client.get("/latest", headers=FARMER).json()["surveyId"] == survey_id
    assert db.data == before


def test_role_and_assignment_boundaries(api):
    client, _ = api
    survey_id = book(client)
    assert submit(client, survey_id).status_code == 403
    for headers in (FARMER, OTHER, ADMIN):
        assert client.get("/team/visits", headers=headers).status_code == 403
    assert client.post("/survey/book", json=BOOK, headers=TEAM).status_code == 403
    assert client.post("/survey/book", json=BOOK, headers=ADMIN).status_code == 403
    assert client.get(f"/survey/{survey_id}", headers=OTHER).status_code == 403
    assert client.get("/admin/overview", headers=FARMER).status_code == 403
    assert client.get("/survey/my-surveys").status_code == 401
    assert client.get("/survey/my-surveys", headers=OTHER).json() == {"surveys": []}
    assert approve(client, survey_id).status_code == 200
    assert client.get("/team/visits", headers=TEAM_OTHER).json()["visits"] == []
    assert client.get(f"/team/visits/{survey_id}", headers=TEAM_OTHER).status_code == 403
    assert client.post(f"/team/visits/{survey_id}/readings", headers=TEAM_OTHER, json=READINGS).status_code == 403
    assert client.post("/admin/process-survey", headers=TEAM, json={
        "surveyId": survey_id, "action": "publish"}).status_code == 403


def test_admin_cannot_skip_field_report(api):
    client, _ = api
    survey_id = book(client)
    assert publish(client, survey_id).status_code == 409
    assert client.post("/admin/process-survey", headers=ADMIN, json={
        "surveyId": survey_id, "action": "approve", "moisture": 50, "temperature": 28}).status_code == 422
    assert approve(client, survey_id, teamId="farmer").status_code == 422
    assert approve(client, survey_id, teamId="missing").status_code == 422
    assert approve(client, survey_id).status_code == 200
    assert publish(client, survey_id).status_code == 409
    assert approve(client, survey_id).status_code == 409


@pytest.mark.parametrize("changes", [
    {"city": "Atlantis"}, {"soilType": "Desert"}, {"season": "Invalid"},
    {"year": 1800}, {"farmAddress": ""}, {"farmAddress": "short"},
])
def test_invalid_booking_is_rejected_before_storage(api, changes):
    client, db = api
    response = client.post("/survey/book", headers=FARMER, json={**BOOK, **changes})
    assert response.status_code == 422
    assert not db.data.get("farm_inputs")


@pytest.mark.parametrize("changes", [
    {"moisture": -1}, {"moisture": 101}, {"temperature": 100},
    {"nitrogen": None}, {"phosphorus": -1}, {"potassium": None},
])
def test_invalid_field_readings_leave_the_visit_open(api, changes):
    client, db = api
    survey_id = book(client)
    assert approve(client, survey_id).status_code == 200
    assert submit(client, survey_id, **changes).status_code == 422
    assert db.collection("farm_inputs").document(survey_id).get().to_dict()["status"] == "approved"
    assert not db.data.get("survey_predictions")


def test_rejection_cancels_visit_and_prevents_team_submission(api):
    client, _ = api
    survey_id = book(client)
    assert approve(client, survey_id).status_code == 200
    assert client.post("/admin/process-survey", headers=ADMIN, json={
        "surveyId": survey_id, "action": "reject", "notes": "Farmer cancelled"}).status_code == 200
    assert submit(client, survey_id).status_code == 409
    assert publish(client, survey_id).status_code == 409


def test_prediction_failure_does_not_close_visit_or_publish_data(api, monkeypatch):
    client, db = api
    survey_id = book(client)
    assert approve(client, survey_id).status_code == 200
    def broken_model(*args):
        raise RuntimeError("Unavailable")
    monkeypatch.setattr(field_workflow, "run_ml_pipeline", broken_model)
    assert submit(client, survey_id).status_code == 503
    assert not db.data.get("survey_predictions")
    assert db.collection("farm_inputs").document(survey_id).get().to_dict()["status"] == "approved"


def test_email_failure_happens_after_release_not_after_visit_approval(api, monkeypatch):
    client, _ = api
    monkeypatch.setenv("SMTP_EMAIL", "test@example.invalid")
    monkeypatch.setenv("SMTP_PASSWORD", "not-a-real-password")
    def broken_smtp(*args, **kwargs):
        raise OSError("Simulated failure")
    monkeypatch.setattr(main.smtplib, "SMTP", broken_smtp)
    survey_id = book(client)
    assert approve(client, survey_id).status_code == 200
    assert submit(client, survey_id).status_code == 200
    assert publish(client, survey_id).status_code == 200
    data = client.get(f"/survey/{survey_id}", headers=FARMER).json()
    assert data["status"] == "completed" and data["emailStatus"] == "failed"


def test_manual_nutrients_override_soil_lookup_and_models_have_distinct_targets():
    result = run_ml_pipeline("Pune", 2026, "Monsoon", "Black", 45, 28, 123, 45, 67)
    assert (result["nitrogen"], result["phosphorus"], result["potassium"]) == (123, 45, 67)
    assert result["nutrientSource"] == "manual"
    assert result["recommendation_method"] == "random_forest_classifier"
    assert result["recommended_crop"] in set(load_crop_data()[0]["crop"])
    assert isinstance(result["predicted_rainfall_mm"], float)


def test_support_messages_are_private_and_receive_a_real_admin_reply(api):
    client, _ = api
    survey_id = book(client)
    response = client.post("/support/messages", headers=FARMER, json={
        "subject": "Farm visit question", "message": "When will the team visit?", "surveyId": survey_id})
    assert response.status_code == 200
    thread_id = response.json()["threadId"]
    assert client.get("/support/messages", headers=OTHER).json()["messages"] == []
    assert client.get("/support/messages", headers=FARMER).json()["messages"][0]["threadId"] == thread_id
    assert client.get("/admin/support", headers=TEAM).status_code == 403
    assert client.post(f"/admin/support/{thread_id}/reply", headers=FARMER,
                       json={"reply": "Not allowed"}).status_code == 403
    assert client.post(f"/admin/support/{thread_id}/reply", headers=ADMIN,
                       json={"reply": "The assigned team will contact you."}).status_code == 200
    answered = client.get("/support/messages", headers=FARMER).json()["messages"][0]
    assert answered["status"] == "answered"
    assert answered["adminReply"] == "The assigned team will contact you."
    assert client.post("/support/messages", headers=OTHER, json={
        "subject": "Wrong survey", "message": "This is not mine", "surveyId": survey_id}).status_code == 403



def test_concurrent_processing_cannot_overwrite_result(api):
    _, db = api
    ref = db.collection("farm_inputs").document("concurrent")
    ref.set({"status": "pending"})
    stale_snapshot = ref.get()
    ref.update({"status": "completed"})
    with pytest.raises(HTTPException) as error:
        main.update_survey(stale_snapshot, {"status": "rejected"}, db)
    assert error.value.status_code == 409
    assert ref.get().to_dict()["status"] == "completed"

def test_legacy_document_aliases(api):
    client, db = api
    ref = db.collection("farm_inputs").document("legacy")
    ref.set({"userId": "farmer", "predictedRainfall": None, "predicted_rainfall_mm": 800,
             "recommendedCrop": None, "recommended_crop": "Rice", "soil_type": "Black"})
    result = client.get("/survey/legacy", headers=FARMER).json()
    assert result["predictedRainfall"] == 800
    assert result["recommendedCrop"] == "Rice"
    assert result["soilType"] == "Black"

def test_real_auth_header_parsing_and_expiration(monkeypatch):
    monkeypatch.setattr(main, "get_db", lambda: object())
    for header in (None, "", "Basic abc", "Bearer", "Bearer "):
        with pytest.raises(HTTPException) as error:
            main.get_current_user(header)
        assert error.value.status_code == 401
    monkeypatch.setattr(main.auth, "verify_id_token", lambda value: {"uid": value})
    assert main.get_current_user("bearer valid")["uid"] == "valid"
    def expired(value):
        raise main.auth.InvalidIdTokenError("expired")
    monkeypatch.setattr(main.auth, "verify_id_token", expired)
    with pytest.raises(HTTPException) as error:
        main.get_current_user("Bearer expired")
    assert error.value.status_code == 401

def test_public_routes_and_legacy_entrypoint(api):
    client, _ = api
    import api as legacy
    assert legacy.app is main.app
    assert client.get("/").status_code == 200
    assert client.get("/health").json()["chatbotConfigured"] is False
    assert client.get("/cities").json()["cities"] == ["Pune", "Mumbai", "Delhi", "Bangalore", "Hyderabad"]
    soils = client.get("/soil-types").json()["soil_types"]
    assert "Sandy" in soils and "Desert" not in soils
    assert client.get("/seasons").status_code == 200

def test_chat_missing_key_still_returns_flutter_contract(api):
    client, _ = api
    result = client.post("/chat", headers=FARMER, json={"message": "Which crop?", "userId": "other"})
    assert result.status_code == 200
    assert "not configured" in result.json()["response"]
    assert client.post("/chat", headers=FARMER, json={"message": " "}).status_code == 422

def test_rainfall_is_seasonal_and_assets_are_independent_of_cwd(monkeypatch):
    monkeypatch.chdir(config.BASE_DIR / "tests")
    assert 700 < predict_rainfall("Pune", 2026, "Monsoon") < 1000
    assert 0 < predict_rainfall("Pune", 2026, "Summer") < 100
    assert get_soil_nutrients("Black") == (480.0, 230.0, 190.0)
    assert run_ml_pipeline("Pune", 2026, "Monsoon", "Black", 40, "Medium")["temperature"] == 28
    with pytest.raises(ValueError):
        get_soil_nutrients("Unknown")

class QuotaError(Exception):
    code = 429


@pytest.mark.parametrize("errors,expected_calls", [
    ([QuotaError("RESOURCE_EXHAUSTED"), QuotaError("RESOURCE_EXHAUSTED"), None], 3),
    ([QuotaError("Quota exceeded, limit: 0"), None], 2),
    ([ValueError("Model not found"), None], 2),
])
def test_chat_retry_and_fallback(monkeypatch, errors, expected_calls):
    monkeypatch.setenv("GEMINI_API_KEY", "test-only")
    monkeypatch.setenv("GEMINI_MODEL", "gemini-flash-lite-latest")
    monkeypatch.setenv("GEMINI_FALLBACK_MODEL", "gemini-flash-latest")
    results = [error if error else SimpleNamespace(text="Use the survey result.") for error in errors]
    generate = AsyncMock(side_effect=results)
    client = SimpleNamespace(aio=SimpleNamespace(models=SimpleNamespace(generate_content=generate)))
    monkeypatch.setattr(chatbot, "get_gemini_client", lambda: client)
    result = run_async(chatbot.answer_chat("What can I grow?"))
    assert result == {"response": "Use the survey result."}
    assert generate.await_count == expected_calls
    assert generate.call_args.kwargs["model"] == "gemini-flash-latest"


def test_gemini_client_uses_a_deadline_the_provider_accepts(monkeypatch):
    monkeypatch.setenv("GEMINI_API_KEY", "test-only")
    sentinel = object()

    def provider_client(*, api_key, http_options):
        # The live provider rejects requests with a deadline below ten seconds.
        if http_options.timeout < 10000:
            raise ValueError("Minimum allowed deadline is 10s")
        assert api_key == "test-only"
        return sentinel

    chatbot.get_gemini_client.cache_clear()
    monkeypatch.setattr(chatbot.genai, "Client", provider_client)
    try:
        assert chatbot.get_gemini_client() is sentinel
    finally:
        chatbot.get_gemini_client.cache_clear()


def test_chat_total_failure_returns_friendly_json(monkeypatch):
    monkeypatch.setenv("GEMINI_API_KEY", "test-only")
    generate = AsyncMock(side_effect=QuotaError("limit: 0"))
    client = SimpleNamespace(aio=SimpleNamespace(models=SimpleNamespace(generate_content=generate)))
    monkeypatch.setattr(chatbot, "get_gemini_client", lambda: client)
    assert run_async(chatbot.answer_chat("Hello")) == {"response": chatbot.BUSY_MESSAGE}


def test_invalid_firebase_key_has_sanitized_error(monkeypatch):
    monkeypatch.setenv("FIREBASE_KEY_JSON", "not-base64-and-private")
    monkeypatch.setattr(config.firebase_admin, "get_app", lambda: (_ for _ in ()).throw(ValueError()))
    config.get_db.cache_clear()
    with pytest.raises(config.ConfigurationError) as error:
        config.get_db()
    assert "not-base64" not in str(error.value)
    config.get_db.cache_clear()

def test_duplicate_or_cancelled_submission_cannot_leave_a_partial_draft(api, monkeypatch):
    client, db = api
    survey_id = book(client)
    assert approve(client, survey_id).status_code == 200
    original_batch = db.batch
    def conflicting_batch():
        batch = original_batch()
        commit = batch.commit
        def conflict():
            db.collection("farm_inputs").document(survey_id).update({"status": "rejected"})
            commit()
        batch.commit = conflict
        return batch
    monkeypatch.setattr(db, "batch", conflicting_batch)
    assert submit(client, survey_id).status_code == 409
    assert db.collection("farm_inputs").document(survey_id).get().to_dict()["status"] == "rejected"
    assert not db.data.get("survey_predictions")


def test_admin_rejects_a_prediction_that_does_not_match_the_report(api):
    client, db = api
    survey_id = book(client)
    assert approve(client, survey_id).status_code == 200
    assert submit(client, survey_id).status_code == 200
    db.collection("survey_predictions").document(survey_id).update({"submissionId": "stale-report"})
    assert publish(client, survey_id).status_code == 409
    assert db.collection("farm_inputs").document(survey_id).get().to_dict()["recommended_crop"] is None


def test_team_status_filters_and_workspaces_are_separate(api):
    client, _ = api
    survey_id = book(client)
    assert approve(client, survey_id).status_code == 200
    approved = client.get("/team/visits?status=approved", headers=TEAM).json()
    assert approved["visits"][0]["surveyId"] == survey_id
    assert client.post(f"/team/visits/{survey_id}/start", headers=TEAM).status_code == 200
    assert client.get("/team/visits?status=approved", headers=TEAM).json()["visits"] == []
    assert client.get("/team/visits?status=in_progress", headers=TEAM).json()["visits"][0]["surveyId"] == survey_id
    assert client.get("/team/overview", headers=TEAM).json()["member"]["uid"] == "team"
    assert client.get("/team/").status_code == 200
    assert client.get("/team/team.js").status_code == 200
    assert client.get("/admin/team-members", headers=FARMER).status_code == 403
    assert {member["id"] for member in client.get("/admin/team-members", headers=ADMIN).json()["members"]} == {"team", "team-other"}


def test_manual_preview_is_admin_only_and_requires_manual_nutrients(api):
    client, _ = api
    payload = {"city": "Pune", "year": 2026, "season": "Monsoon", "soil_type": "Black",
               **{key: value for key, value in READINGS.items() if key != "notes"}}
    assert client.post("/predict", headers=FARMER, json=payload).status_code == 403
    response = client.post("/predict", headers=ADMIN, json=payload)
    assert response.status_code == 200
    assert response.json()["nutrientSource"] == "manual"
    del payload["nitrogen"]
    assert client.post("/predict", headers=ADMIN, json=payload).status_code == 422
