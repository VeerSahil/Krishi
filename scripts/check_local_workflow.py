"""Run the actual API against local Firebase Auth/Firestore emulators only.

firebase emulators:exec --only auth,firestore --project demo-krishi-workflow \
    "python scripts/check_local_workflow.py"

No production accounts, surveys, messages, emails or Gemini requests are used.
"""
import json
import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
PROJECT = "demo-krishi-workflow"


def main():
    hosts = {}
    for variable in ("FIREBASE_AUTH_EMULATOR_HOST", "FIRESTORE_EMULATOR_HOST"):
        value = os.environ.get(variable, "")
        host, separator, port = value.partition(":")
        if host != "127.0.0.1" or not separator or not port.isdigit():
            raise RuntimeError("Run through the local demo emulators; missing/invalid " + variable)
        hosts[variable] = value
    for variable in ("GEMINI_API_KEY", "GOOGLE_API_KEY", "SMTP_EMAIL", "SMTP_PASSWORD", "RESEND_API_KEY", "EMAIL_FROM", "GMAIL_CLIENT_ID", "GMAIL_CLIENT_SECRET", "GMAIL_REFRESH_TOKEN"):
        os.environ[variable] = ""
    os.environ["EMAIL_PROVIDER"] = "disabled"
    os.environ["GCLOUD_PROJECT"] = PROJECT

    import firebase_admin
    from firebase_admin import credentials
    from google.auth.credentials import AnonymousCredentials
    import httpx
    from fastapi.testclient import TestClient

    class EmulatorCredential(credentials.Base):
        def get_credential(self):
            return AnonymousCredentials()

    firebase_admin.initialize_app(EmulatorCredential(), {"projectId": PROJECT})
    import main as backend
    db = backend.get_db()
    assert db.project == PROJECT
    steps = []

    def passed(name):
        steps.append(name)
        print("PASS " + name, flush=True)

    with httpx.Client(timeout=15) as remote:
        users = {}
        for role in ("farmer", "admin", "team", "other-team", "other-farmer"):
            email = role + "@krishi-demo.invalid"
            response = remote.post(
                "http://" + hosts["FIREBASE_AUTH_EMULATOR_HOST"] +
                "/identitytoolkit.googleapis.com/v1/accounts:signUp?key=demo-key",
                json={"email": email, "password": "Local-demo-password-123!", "returnSecureToken": True})
            response.raise_for_status()
            user = response.json()
            users[role] = {"uid": user["localId"], "headers": {"Authorization": "Bearer " + user["idToken"]}}
            profile_role = "team" if role == "other-team" else "farmer" if role == "other-farmer" else role
            if role == "farmer":
                # Exercise real client security rules for normal farmer signup.
                response = remote.patch(
                    "http://" + hosts["FIRESTORE_EMULATOR_HOST"] + "/v1/projects/" + PROJECT +
                    "/databases/(default)/documents/users/" + user["localId"],
                    headers=users[role]["headers"], json={"fields": {
                        "role": {"stringValue": "farmer"}, "name": {"stringValue": "Demo farmer"},
                        "email": {"stringValue": email}}})
                response.raise_for_status()
            else:
                db.collection("users").document(user["localId"]).set({
                    "role": profile_role, "name": role.title(), "email": email})
        passed("Firebase emulator signup and farmer profile security rules")

        with TestClient(backend.app) as api:
            def request(method, path, role, body=None):
                result = api.request(method, path, headers=users[role]["headers"], json=body)
                assert result.status_code == 200, (path, result.status_code, result.text)
                return result.json()

            survey = request("POST", "/survey/book", "farmer", {
                "farmName": "Local integration test farm", "farmAddress": "Demo test address, Pune",
                "city": "Pune", "soilType": "Black", "year": 2026, "season": "Monsoon"})
            survey_id = survey["surveyId"]
            assert survey["status"] == "pending"
            passed("Farmer books a pending survey")

            request("POST", "/admin/process-survey", "admin", {
                "surveyId": survey_id, "action": "approve", "teamId": users["team"]["uid"]})
            visits = request("GET", "/team/visits?status=approved", "team")
            assert visits["visits"][0]["surveyId"] == survey_id
            assert api.get("/team/visits/" + survey_id, headers=users["other-team"]["headers"]).status_code == 403
            passed("Admin approves/assigns; only the assigned team can access the visit")

            request("POST", "/team/visits/" + survey_id + "/start", "team")
            request("POST", "/team/visits/" + survey_id + "/readings", "team", {
                "moisture": 45, "temperature": 33.1, "nitrogen": 400, "phosphorus": 200,
                "potassium": 150, "temperatureSource": "simulated", "temperatureCategory": "high",
                "notes": "Local integration test fixture, not physical farm measurements."})
            passed("Team starts visit; actual Firestore batch saves report and model draft")

            farmer_report = request("GET", "/survey/" + survey_id, "farmer")
            assert farmer_report["status"] == "awaiting_review"
            assert farmer_report["recommended_crop"] is None and "draftPrediction" not in farmer_report
            draft = request("GET", "/survey/" + survey_id, "admin")["draftPrediction"]
            assert draft["recommendationIsDemo"] and draft["temperature"] == 33.1
            direct = remote.get(
                "http://" + hosts["FIRESTORE_EMULATOR_HOST"] + "/v1/projects/" + PROJECT +
                "/databases/(default)/documents/survey_predictions/" + survey_id,
                headers=users["farmer"]["headers"])
            assert direct.status_code == 403, direct.text
            passed("Private prediction enforced by API and actual Firestore security rules")

            released = request("POST", "/admin/process-survey", "admin", {"surveyId": survey_id, "action": "publish"})
            final = request("GET", "/survey/" + survey_id, "farmer")
            assert final["status"] == "completed" and final["recommended_crop"] == released["crop"]
            assert final["recommendationIsDemo"] and "simulated" in final["recommendationNotice"]
            assert api.post("/team/visits/" + survey_id + "/readings", headers=users["team"]["headers"],
                            json={"moisture": 45, "temperature": 28, "nitrogen": 400,
                                  "phosphorus": 200, "potassium": 150}).status_code == 409
            passed("Admin releases result; farmer sees labelled recommendation; duplicate report rejected")

            thread = request("POST", "/support/messages", "farmer", {
                "subject": "Demo survey question", "message": "When is this result ready?", "surveyId": survey_id})
            request("POST", "/admin/support/" + thread["threadId"] + "/reply", "admin", {"reply": "The demo result is ready."})
            history = request("GET", "/support/messages", "farmer")["messages"]
            assert history[0]["adminReply"] == "The demo result is ready."
            assert request("GET", "/support/messages", "other-farmer")["messages"] == []
            request("POST", "/review/add", "farmer", {"surveyId": survey_id, "rating": 5, "comment": "Demo test review"})
            passed("Farmer/admin support exchange, support privacy and completed-survey review")

            context = backend.recent_chat_context(db, users["farmer"]["uid"])
            assert "DEMO: simulated temperature" in context
            chat = request("POST", "/chat", "farmer", {"message": "Explain my demo result"})
            assert isinstance(chat["response"], str) and "not configured" in chat["response"]
            passed("Chat context retains demo provenance; HTTP contract works without external Gemini calls")

    report = {"project": PROJECT, "environment": "local Firebase emulators", "steps": steps,
              "crop": final["recommended_crop"], "rainfall_mm": final["predicted_rainfall_mm"],
              "recommendationIsDemo": final["recommendationIsDemo"], "productionWrites": False,
              "externalGeminiOrEmailCalls": False}
    destination = ROOT / ".tool-state/local-workflow-report.json"
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print("Workflow report: " + str(destination), flush=True)


if __name__ == "__main__":
    main()
