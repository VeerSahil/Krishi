from copy import deepcopy
import pytest
from test_pipeline import BOOK, READINGS, FARMER, OTHER, ADMIN, TEAM, TEAM_OTHER, book, approve, submit, publish


def test_offline_retry_is_idempotent_and_evidence_cannot_change(api):
    client, db = api
    sid = book(client); approve(client, sid)
    payload = {**READINGS, "clientSubmissionId": "offline-report-123456789", "capturedAt": "2026-01-01T10:00:00Z",
               "nutrientSource": "soil_test", "nutrientUnit": "mg/kg", "soilTestReference": "LAB-23"}
    path = f"/team/visits/{sid}/readings"
    assert client.post(path, headers=TEAM, json=payload).status_code == 200
    before = deepcopy(db.data)
    assert client.post(path, headers=TEAM, json=payload).json()["duplicate"] is True
    assert db.data == before
    assert client.post(path, headers=TEAM, json={**payload, "moisture": 50}).status_code == 409
    assert client.post(path, headers=TEAM_OTHER, json=payload).status_code == 403
    report = client.get("/farm/evidence", headers=FARMER).json()["records"][0]
    assert report["evidence"]["recordedBy"] == "team"
    assert report["evidence"]["capturedAt"] == "2026-01-01T10:00:00Z"
    assert report["releasedCrop"] is None
    publish(client, sid)
    assert client.post(path, headers=TEAM, json=payload).json()["duplicate"] is True
    assert len(client.get("/farm/evidence", headers=FARMER).json()["records"][0]["timeline"]) == 4


def test_plan_is_owned_and_never_leaks_private_prediction(api):
    client, db = api
    sid = book(client); approve(client, sid); submit(client, sid)
    plan = {"surveyId": sid, "proposedCrop": "Wheat"}
    assert client.post("/farm/crop-plan", headers=OTHER, json=plan).status_code == 403
    assert client.post("/farm/crop-plan", headers=TEAM, json=plan).status_code == 403
    data = client.post("/farm/crop-plan", headers=FARMER, json=plan).json()
    assert data["check"]["comparison"] == "unavailable"
    assert data["check"]["releasedCrop"] is None
    assert data["check"]["state"] == "needs_information"
    assert len(data["check"]["gaps"]) >= 4
    assert client.get("/farm/evidence", headers=OTHER).json()["records"] == []
    assert client.get("/farm/evidence", headers=TEAM).status_code == 403
    publish(client, sid)
    after = client.get("/farm/evidence", headers=FARMER).json()["records"][0]
    assert after["planCheck"]["releasedCrop"]
    assert after["planCheck"]["comparison"] in ("same", "different")


def test_complete_evidence_still_requires_expert_review(api):
    client, _ = api
    sid = book(client); approve(client, sid)
    submit(client, sid, nutrientSource="soil_test", nutrientUnit="kg/ha", soilTestReference="Lab 77")
    publish(client, sid)
    data = client.post("/farm/crop-plan", headers=FARMER, json={"surveyId": sid, "proposedCrop": "Rice", "sowingDate": "2026-11-01", "irrigation": "irrigated"}).json()
    assert data["check"]["state"] == "needs_expert_review"
    assert data["check"]["gaps"] == []


@pytest.mark.parametrize("fields", [{"nutrientSource": "soil_test"}, {"capturedAt": "2026-01-01T10:00:00"}, {"capturedAt": "2100-01-01T10:00:00Z"}, {"clientSubmissionId": "bad/id"}])
def test_invalid_provenance_does_not_close_visit(api, fields):
    client, _ = api
    sid = book(client); approve(client, sid)
    assert submit(client, sid, **fields).status_code == 422


def test_cancelled_offline_report_is_rejected(api):
    client, _ = api
    sid = book(client); approve(client, sid)
    client.post("/admin/process-survey", headers=ADMIN, json={"surveyId": sid, "action": "reject"})
    assert submit(client, sid, clientSubmissionId="saved-offline-123456").status_code == 409


def test_evidence_cursor_and_attachment_validation(api):
    client, _ = api
    sid = book(client)
    assert client.get('/farm/evidence?cursor=' + sid, headers=OTHER).status_code == 400
    approve(client, sid)
    for value in ('javascript:alert(1)', 'http://example.com/test.pdf', 'https://user:secret@example.com/report'):
        assert submit(client, sid, soilTestAttachmentUrl=value).status_code == 422
    assert submit(client, sid, soilTestAttachmentUrl='https://example.com/report.pdf').status_code == 200
    record = client.get('/farm/evidence', headers=FARMER).json()['records'][0]
    assert record['evidence']['soilTestAttachmentUrl'] == 'https://example.com/report.pdf'


def test_plan_history_and_rainfed_actions(api):
    client, _ = api
    sid = book(client)
    for crop in ('Wheat', 'Rice'):
        result = client.post('/farm/crop-plan', headers=FARMER, json={'surveyId': sid, 'proposedCrop': crop, 'irrigation': 'rainfed', 'sowingDate': '2020-01-01'})
        assert result.status_code == 200
        assert len(result.json()['check']['actions']) == 2
    record = client.get('/farm/evidence', headers=FARMER).json()['records'][0]
    assert [p['proposedCrop'] for p in record['planHistory']] == ['Wheat', 'Rice']


def test_selected_chat_language_is_forwarded(api, monkeypatch):
    from unittest.mock import AsyncMock
    import main
    client, _ = api
    answer = AsyncMock(return_value={"response": "test"})
    monkeypatch.setattr(main, "answer_chat", answer)
    assert client.post('/chat', headers=FARMER, json={'message': 'Question', 'language': 'mr'}).status_code == 200
    assert answer.await_args.kwargs['language'] == 'mr'
    assert client.post('/chat', headers=FARMER, json={'message': 'Question', 'language': 'invalid'}).status_code == 422


def test_crop_names_match_across_languages_and_aliases():
    from farm_planning import crop_key
    assert crop_key("Wheat") == crop_key("\u0917\u0939\u0942")
    assert crop_key("Corn") == crop_key("Maize")
    assert crop_key("Rice") == crop_key("Paddy")
    assert crop_key("Pulses") != crop_key("Chickpea")
