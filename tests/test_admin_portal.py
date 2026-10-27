import pytest
from datetime import datetime, timezone
from fastapi.testclient import TestClient

import admin_portal
import main

FARMER = {"Authorization": "Bearer farmer"}
OTHER = {"Authorization": "Bearer other"}
ADMIN = {"Authorization": "Bearer admin"}
BOOK = {"city": "Pune", "soilType": "Black", "year": 2026, "season": "Monsoon", "farmAddress": "Road 1, Pune farm"}


def test_admin_monitoring_is_not_available_to_farmers(api):
    client, _ = api
    for route in ("/admin/overview", "/admin/farmers", "/admin/surveys", "/admin/farmers/farmer"):
        assert client.get(route, headers=FARMER).status_code == 403
        assert client.get(route).status_code == 401


def test_admin_overview_counts_real_profiles_and_survey_statuses(api):
    client, _ = api
    first = client.post("/survey/book", json=BOOK, headers=FARMER).json()["surveyId"]
    client.post("/survey/book", json=BOOK, headers=OTHER)
    assert client.post("/admin/process-survey", headers=ADMIN, json={
        "surveyId": first, "action": "approve", "teamId": "team"}).status_code == 200
    data = client.get("/admin/overview", headers=ADMIN).json()
    assert data["totals"] == {"farmers": 2, "surveys": 2, "pending": 1, "approved": 1, "in_progress": 0, "awaiting_review": 0, "completed": 0,
                              "failed": 0, "rejected": 0, "other": 0, "supportOpen": 0}
    assert len(data["recentSurveys"]) == 2
    assert data["admin"]["email"] == "admin@example.invalid"


def test_farmer_directory_pagination_reaches_every_farmer(api):
    client, db = api
    for index in range(6):
        db.collection("users").document(f"new-{index}").set({
            "name": f"Farmer {index}", "role": "farmer",
            "privateField": "not for the dashboard"})
    all_ids = []
    cursor = None
    for _ in range(10):
        params = {"limit": 2}
        if cursor:
            params["cursor"] = cursor
        response = client.get("/admin/farmers", headers=ADMIN, params=params)
        assert response.status_code == 200, response.text
        data = response.json()
        assert all("privateField" not in farmer for farmer in data["farmers"])
        all_ids.extend(farmer["id"] for farmer in data["farmers"])
        cursor = data["nextCursor"]
        if cursor is None:
            break
    assert len(all_ids) == len(set(all_ids)) == 8
    assert "admin" not in all_ids
    assert client.get("/admin/farmers", headers=ADMIN, params={"limit": 0}).status_code == 422
    assert client.get("/admin/farmers", headers=ADMIN, params={"cursor": "missing"}).status_code == 400


def test_farmer_details_and_surveys_are_scoped_to_the_selected_farmer(api):
    client, _ = api
    for _ in range(3):
        client.post("/survey/book", json=BOOK, headers=FARMER)
    client.post("/survey/book", json=BOOK, headers=OTHER)
    details = client.get("/admin/farmers/farmer", headers=ADMIN).json()
    assert details["farmer"]["id"] == "farmer"
    assert details["stats"]["surveys"] == details["stats"]["pending"] == 3
    first = client.get("/admin/surveys", headers=ADMIN,
                       params={"farmer_id": "farmer", "status": "pending", "limit": 2}).json()
    assert len(first["surveys"]) == 2
    assert all(survey["userId"] == "farmer" for survey in first["surveys"])
    assert first["nextCursor"] is not None
    second = client.get("/admin/surveys", headers=ADMIN, params={
        "farmer_id": "farmer", "status": "pending", "limit": 2, "cursor": first["nextCursor"]}).json()
    assert len(second["surveys"]) == 1 and second["nextCursor"] is None
    assert first["surveys"][0]["surveyId"] != second["surveys"][0]["surveyId"]
    assert client.get("/admin/farmers/admin", headers=ADMIN).status_code == 404
    assert client.get("/admin/farmers/missing", headers=ADMIN).status_code == 404
    assert client.get("/admin/surveys", headers=ADMIN, params={"status": "deleted"}).status_code == 422


def test_browser_interface_is_public_but_contains_no_farmer_data(api, monkeypatch):
    client, _ = api
    monkeypatch.setenv("FIREBASE_WEB_API_KEY", "public-test-key")
    monkeypatch.setenv("FIREBASE_PROJECT_ID", "test-project")
    config = client.get("/admin/config").json()
    assert config == {"apiKey": "public-test-key", "projectId": "test-project",
                      "configured": True, "refreshSeconds": 30}
    assert "private_key" not in config
    response = client.get("/admin/")
    assert response.status_code == 200
    assert "Krishi Admin" in response.text
    assert 'id="dashboard-view" class="app-shell" hidden' in response.text
    assert "farmer@example.invalid" not in response.text
    assert "frame-ancestors 'none'" in response.headers["content-security-policy"]
    assert response.headers["cache-control"] == "no-store"
    assert client.get("/admin/app.js").status_code == 200
    assert client.get("/admin/styles.css").status_code == 200
    assert client.get("/admin/config").headers["content-type"].startswith("application/json")
