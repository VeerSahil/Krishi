"""End-to-end care workflow with isolated Firestore, no cloud data or emails."""
from copy import deepcopy
from hashlib import sha256
import json
import pytest
from google.api_core.exceptions import FailedPrecondition
from schemas import FieldReadingsRequest
from world_models import CarePolicy
from care_assessment import assess_care, report_template
from world_events import event_bytes
from test_pipeline import BOOK, READINGS, FARMER, OTHER, ADMIN, TEAM, TEAM_OTHER, book, approve, submit, publish

REGION = {"farmerId": "farmer", "farmName": "North potato field", "farmAddress": "Field road, Pune 411001",
          "city": "Pune", "soilType": "Black", "cropAsset": "potato", "slot": 1}


def create(client, **changes):
    response = client.post("/world/farms", headers=ADMIN, json={**REGION, **changes})
    assert response.status_code == 200, response.text
    return response.json()["farm"]


def prepare(client, sid, language="en"):
    response = client.get(f"/world/surveys/{sid}/report?language={language}", headers=ADMIN)
    assert response.status_code == 200, response.text
    report = response.json()["report"]
    response = client.post(f"/world/surveys/{sid}/report", headers=ADMIN,
        json={key: report[key] for key in ("submissionId", "language", "summary", "actions")})
    assert response.status_code == 200, response.text
    return response.json()["report"]


@pytest.mark.parametrize("path", ["/world/session", "/world/assets", "/world/farms", "/world/events"])
def test_world_data_requires_staff(api, path):
    client, _ = api
    assert client.get(path).status_code == 401
    assert client.get(path, headers=FARMER).status_code == 403


def test_create_and_assignment_scopes_and_farmer_metadata(api):
    client, _ = api
    assert client.post("/world/farms", headers=TEAM, json=REGION).status_code == 403
    assert client.post("/world/farms", headers=FARMER, json=REGION).status_code == 403
    assert client.post("/world/farms", headers=ADMIN, json={**REGION, "farmerId": "team"}).status_code == 422
    farm = create(client)
    assert farm["id"] == "plot-00001" and farm["assessment"] is None
    assert client.post("/world/farms", headers=ADMIN, json=REGION).status_code == 409
    assert client.get("/world/farms", headers=TEAM).json()["farms"] == []
    assert client.get("/world/farms/plot-00001", headers=TEAM).status_code == 403
    fields = client.get("/farm/fields", headers=FARMER).json()["fields"]
    assert fields[0]["id"] == farm["id"]
    assert not {"policy", "assessment", "assignedTeamId", "slot", "farmerId"} & fields[0].keys()
    assert client.get("/farm/fields", headers=OTHER).json()["fields"] == []
    assert client.get("/farm/fields", headers=TEAM).status_code == 403


def test_booking_uses_owned_canonical_field_and_prevents_two_open_visits(api):
    client, db = api
    farm = create(client)
    assert client.post("/survey/book", headers=OTHER, json={**BOOK, "farmId": farm["id"]}).status_code == 403
    sid = book(client, farmId=farm["id"], farmName="Spoofed", farmAddress="Another address")
    saved = db.collection("farm_inputs").document(sid).get().to_dict()
    assert saved["farmName"] == farm["farmName"] and saved["farmAddress"] == farm["farmAddress"]
    assert client.post("/survey/book", headers=FARMER, json={**BOOK, "farmId": farm["id"]}).status_code == 409
    assert len(db.data["farm_inputs"]) == 1
    approve(client, sid)
    assigned = client.get("/world/farms", headers=TEAM).json()["farms"][0]
    assert assigned["latestSurveyStatus"] == "approved" and assigned["assignedTeamId"] == "team"
    assert client.get(f"/world/farms/{farm['id']}", headers=TEAM_OTHER).status_code == 403


def test_link_legacy_request_only_while_pending_and_same_farmer(api):
    client, db = api
    farm = create(client); sid = book(client)
    path = f"/world/farms/{farm['id']}/link-survey"
    foreign = client.post("/survey/book", headers=OTHER, json=BOOK).json()["surveyId"]
    assert client.post(path, headers=ADMIN, json={"surveyId": foreign}).status_code == 403
    assert client.post(path, headers=TEAM, json={"surveyId": sid}).status_code == 403
    assert client.post(path, headers=ADMIN, json={"surveyId": sid}).status_code == 200
    assert db.collection("farm_inputs").document(sid).get().to_dict()["farmId"] == farm["id"]
    assert client.post(path, headers=ADMIN, json={"surveyId": sid}).status_code == 409
    farm2 = create(client, slot=2)
    sid2 = book(client); approve(client, sid2)
    assert client.post(f"/world/farms/{farm2['id']}/link-survey", headers=ADMIN, json={"surveyId": sid2}).status_code == 409


@pytest.mark.parametrize("changes,grade,count", [({}, "A", 0), ({"moisture": 20}, "B", 1),
    ({"moisture": 20, "potassium": 20}, "C", 2),
    ({"moisture": 30, "temperature": 35, "nitrogen": 50, "potassium": 500}, "A", 0)])
def test_care_bands_boundaries(changes, grade, count):
    assessment = assess_care({**READINGS, "moistureUnit": "relative_percent", **changes}, CarePolicy().model_dump())
    assert assessment["grade"] == grade and len(assessment["findings"]) == count
    assert assessment["demonstrationOnly"] and assessment["notADiagnosis"]


def test_configured_policy_requires_units_and_retains_source_notices():
    from pydantic import ValidationError
    with pytest.raises(ValidationError): CarePolicy(basis="configured_rules")
    policy = CarePolicy(basis="configured_rules", nutrientUnit="mg/kg", reference="Example lab reference").model_dump()
    values = {**READINGS, "moistureUnit": "relative_percent", "nutrientUnit": "mg/kg", "nutrientSource": "soil_test"}
    assert assess_care(values, policy)["grade"] == "A"
    for changes in ({"nutrientUnit": "kg/ha"}, {"moistureUnit": "vwc_percent"}, {"moisture": None}):
        assert assess_care({**values, **changes}, policy)["grade"] == "U"
    result = assess_care({**values, "temperatureSource": "simulated"}, policy)
    assert result["demonstrationOnly"] and any("simulated" in w for w in result["warnings"])


def test_new_flow_bypasses_crop_ml_and_keeps_draft_private_until_admin_release(api, monkeypatch):
    import field_workflow
    client, db = api
    def forbidden_ml(*args, **kwargs): raise AssertionError("Care flow must not call demo crop ML")
    monkeypatch.setattr(field_workflow, "run_ml_pipeline", forbidden_ml)
    farm = create(client); sid = book(client, farmId=farm["id"]); approve(client, sid)
    result = submit(client, sid, moisture=20, potassium=20, clientSubmissionId="care-report-first-0001", moistureUnit="relative_percent",
                    temperatureSource="simulated", temperatureCategory="moderate")
    assert result.status_code == 200, result.text
    staff = client.get(f"/world/farms/{farm['id']}", headers=TEAM).json()
    assert staff["farm"]["assessment"]["grade"] == "C"
    assert staff["farm"]["previousClass"] == "U"
    private = client.get(f"/survey/{sid}", headers=FARMER).json()
    assert "draftPrediction" not in private and "farmerReport" not in private and "careClass" not in private
    assert client.get(f"/world/surveys/{sid}/report", headers=TEAM).status_code == 403
    assert publish(client, sid).status_code == 409
    prepared = prepare(client, sid, "mr")
    assert any("\u0900" <= ch <= "\u097f" for ch in prepared["summary"])
    assert prepared["careClass"] == "C" and len(prepared["notices"]) >= 3
    assert "farmerReport" not in client.get(f"/survey/{sid}", headers=FARMER).json()
    assert publish(client, sid).status_code == 200
    released = client.get(f"/survey/{sid}", headers=FARMER).json()
    assert released["farmerReport"]["careClass"] == "C" and released["careClass"] == "C"
    assert released["recommendedCrop"] is None and released["farmerReport"]["readings"]["temperatureSource"] == "simulated"
    assert client.get(f"/survey/{sid}", headers=OTHER).status_code == 403
    history = client.get("/farm/evidence", headers=FARMER).json()["records"][0]
    assert history["farmerReport"]["summary"] == prepared["summary"] and history["planCheck"] is None
    assert client.post("/farm/crop-plan", headers=FARMER, json={"surveyId": sid, "proposedCrop": "Potato"}).status_code == 409
    assert len(db.data["farm_assessments"]) == 1
    assert db.collection("farms").document(farm["id"]).get().to_dict()["latestSurveyStatus"] == "completed"
    # Subsequent inspections retain the previous grade for the visual transition.
    sid2 = book(client, farmId=farm["id"]); approve(client, sid2)
    assert submit(client, sid2, moistureUnit="relative_percent").status_code == 200
    changed = client.get(f"/world/farms/{farm['id']}", headers=ADMIN).json()["farm"]
    assert changed["previousClass"] == "C" and changed["assessment"]["grade"] == "A"
    assert len(db.data["farm_assessments"]) == 2


def test_policy_changes_blocked_during_open_visit_and_reject_stale_version(api):
    client, _ = api
    farm = create(client); path = f"/world/farms/{farm['id']}/policy"
    body = {"version": farm["version"], "policy": CarePolicy(name="Updated demo policy").model_dump()}
    assert client.post(path, headers=TEAM, json=body).status_code == 403
    assert client.post(path, headers=ADMIN, json=body).status_code == 200
    assert client.post(path, headers=ADMIN, json=body).status_code == 409
    sid = book(client, farmId=farm["id"])
    current = client.get(f"/world/farms/{farm['id']}", headers=ADMIN).json()["farm"]
    assert client.post(path, headers=ADMIN, json={**body, "version": current["version"]}).status_code == 409


def test_stale_farm_cas_rolls_back_readings_and_private_draft(api, monkeypatch):
    client, db = api
    farm = create(client); sid = book(client, farmId=farm["id"]); approve(client, sid)
    before = deepcopy(db.data)
    from conftest import Document
    original = Document.update
    def reject_farm(self, changes, option=None):
        if self.collection.name == "farms": raise FailedPrecondition("Concurrent farm update")
        return original(self, changes, option)
    monkeypatch.setattr(Document, "update", reject_farm)
    assert submit(client, sid).status_code == 409
    assert db.data == before and "survey_predictions" not in db.data and "farm_assessments" not in db.data


def test_report_matches_current_submission_and_cannot_change_after_release(api):
    client, _ = api
    farm = create(client); sid = book(client, farmId=farm["id"]); approve(client, sid); submit(client, sid)
    report = prepare(client, sid)
    path = f"/world/surveys/{sid}/report"
    payload = {key: report[key] for key in ("submissionId", "language", "summary", "actions")}
    assert client.post(path, headers=ADMIN, json={**payload, "submissionId": "stale-id"}).status_code == 409
    assert client.post(path, headers=ADMIN, json={**payload, "actions": [" "]}).status_code == 422
    assert client.post(path, headers=ADMIN, json={**payload, "notices": []}).status_code == 422
    payload["summary"] = "We reviewed this visit. Please arrange the next check with our team."
    assert client.post(path, headers=ADMIN, json=payload).status_code == 200
    assert client.get(path, headers=ADMIN).json()["report"]["summary"] == payload["summary"]
    assert publish(client, sid).status_code == 200
    assert client.post(path, headers=ADMIN, json=payload).status_code == 409
    assert publish(client, sid).status_code == 409


def test_old_offline_fingerprint_still_accepts_identical_retry(api):
    client, db = api
    sid = book(client); approve(client, sid)
    payload = {**READINGS, "clientSubmissionId": "offline-previous-format-0001"}
    assert submit(client, sid, clientSubmissionId=payload["clientSubmissionId"]).status_code == 200
    ref = db.collection("farm_inputs").document(sid); saved = ref.get().to_dict()
    evidence = saved["fieldEvidence"]; evidence.pop("moistureUnit")
    legacy = FieldReadingsRequest(**payload).model_dump(mode="json", exclude={"moistureUnit"})
    ref.update({"measurementFingerprint": sha256(json.dumps(legacy, sort_keys=True).encode()).hexdigest(), "fieldEvidence": evidence})
    path = f"/team/visits/{sid}/readings"
    assert client.post(path, headers=TEAM, json=payload).json()["duplicate"] is True
    assert client.post(path, headers=TEAM, json={**payload, "moisture": 50}).status_code == 409
    assert client.post(path, headers=TEAM, json={**payload, "moistureUnit": "relative_percent"}).status_code == 409


def test_world_pagination_and_events_fallback(api):
    client, _ = api
    create(client); create(client, slot=2)
    first = client.get("/world/farms?limit=1", headers=ADMIN).json()
    assert first["nextCursor"] == "plot-00001"
    second = client.get("/world/farms?limit=1&cursor="+first["nextCursor"], headers=ADMIN).json()
    assert second["farms"][0]["id"] == "plot-00002" and second["nextCursor"] is None
    assert client.get("/world/farms?limit=201", headers=ADMIN).status_code == 422
    stream = client.get("/world/events", headers=ADMIN)
    assert stream.status_code == 200 and "event: reconnect" in stream.text
    assert stream.headers["cache-control"] == "no-store"
    encoded = event_bytes("snapshot", {"farms": [{"farmName": "line1\nline2"}]})
    assert len(encoded.splitlines()) == 3 and json.loads(encoded.splitlines()[1][6:])["farms"][0]["farmName"] == "line1\nline2"


def test_new_report_email_contains_farmer_copy_not_crop_placeholders(api):
    from email_notifications import event_id
    client, db = api
    farm = create(client); sid = book(client, farmId=farm["id"]); approve(client, sid); submit(client, sid)
    report = prepare(client, sid)
    assert publish(client, sid).status_code == 200
    event = db.collection("survey_email_events").document(event_id(sid, "completed")).get().to_dict()
    assert report["summary"] in event["text"] and report["notices"][0] in event["text"]
    assert "Recommended crop:" not in event["text"] and event["deliveryStatus"] == "not_configured"


def test_snapshot_listener_sends_scoped_data_and_unsubscribes(api, monkeypatch):
    from types import SimpleNamespace
    import world_events
    from conftest import Collection
    client, _ = api
    create(client)
    unsubscribed = []
    def subscribe(query, callback):
        callback(list(query.stream()), [], None)
        return SimpleNamespace(unsubscribe=lambda: unsubscribed.append(True))
    ticks = iter([0, 1, 2, 181])
    monkeypatch.setattr(Collection, "on_snapshot", subscribe, raising=False)
    monkeypatch.setattr(world_events, "time", SimpleNamespace(monotonic=lambda: next(ticks), time=lambda: 0))
    response = client.get("/world/events", headers=ADMIN)
    assert "event: snapshot" in response.text and '"id":"plot-00001"' in response.text
    assert unsubscribed == [True]


def test_snapshot_listener_revokes_changed_staff_role(api, monkeypatch):
    from types import SimpleNamespace
    import world_events
    from conftest import Collection
    client, db = api
    create(client)
    unsubscribed = []
    def subscribe(query, callback):
        db.collection("users").document("team").update({"role": "farmer"})
        callback(list(query.stream()), [], None)
        return SimpleNamespace(unsubscribe=lambda: unsubscribed.append(True))
    ticks = iter([0, 1, 20])
    monkeypatch.setattr(Collection, "on_snapshot", subscribe, raising=False)
    monkeypatch.setattr(world_events, "time", SimpleNamespace(monotonic=lambda: next(ticks), time=lambda: 0))
    response = client.get("/world/events", headers=TEAM)
    assert "event: revoked" in response.text and "event: snapshot" not in response.text
    assert unsubscribed == [True]
