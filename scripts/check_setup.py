"""Read-only setup check; --live additionally probes Firebase and Render."""
import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from config import firebase_configured, firebase_key_path, gemini_key, get_db
from ml_pipeline import run_ml_pipeline


def check_live_firebase():
    """Return readiness metadata without printing account or survey contents."""
    from google.api_core.exceptions import FailedPrecondition
    from google.cloud.firestore_v1.base_query import FieldFilter

    db = get_db()
    report = {"accountProfiles": {}, "queries": {}}
    for role in ("farmer", "admin", "team"):
        result = db.collection("users").where(
            filter=FieldFilter("role", "==", role)).count().get(timeout=8, retry=None)
        report["accountProfiles"][role] = int(result[0][0].value)
    for name, collection, filters in (
        ("farmerHistory", "farm_inputs", [("userId", "setup-read-only-check")]),
        ("teamVisits", "farm_inputs", [("assignedTeamId", "setup-read-only-check")]),
        ("filteredTeamVisits", "farm_inputs", [
            ("assignedTeamId", "setup-read-only-check"), ("status", "approved")]),
        ("adminPending", "farm_inputs", [("status", "pending")]),
        ("farmerSupport", "support_threads", [("userId", "setup-read-only-check")]),
    ):
        query = db.collection(collection)
        for field, value in filters:
            query = query.where(filter=FieldFilter(field, "==", value))
        try:
            list(query.order_by("createdAt", direction="DESCENDING").limit(1).stream(
                timeout=8, retry=None))
            report["queries"][name] = "ready"
        except FailedPrecondition:
            report["queries"][name] = "index_required"
        except Exception as error:
            report["queries"][name] = type(error).__name__
    return report


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--live", action="store_true")
    args = parser.parse_args()
    key_path = firebase_key_path()
    report = {
        "firebaseConfigured": firebase_configured(),
        "chatbotConfigured": bool(gemini_key()),
        "flutterSourcePresent": (ROOT / "mobile/pubspec.yaml").is_file(),
        "teamAndroidSourcePresent": (ROOT / "mobile/lib/main_team.dart").is_file(),
        "adminInterfacePresent": (ROOT / "admin_web/index.html").is_file(),
        "teamInterfacePresent": (ROOT / "team_web/index.html").is_file(),
        "models": {"rainfall": "RandomForestRegressor", "crop": "RandomForestClassifier"},
    }
    if key_path and key_path.is_file():
        try:
            report["firebaseProjectId"] = json.loads(key_path.read_text())["project_id"]
            get_db()
            report["firebaseCredentialParsing"] = "ok"
        except Exception as error:
            report["firebaseCredentialParsing"] = type(error).__name__
    result = run_ml_pipeline("Pune", 2026, "Monsoon", "Black", 45, 28, 400, 200, 150)
    report["manualPrediction"] = {
        "crop": result["recommended_crop"], "rainfall_mm": result["predicted_rainfall_mm"]}
    print(json.dumps(report, indent=2), flush=True)
    if args.live:
        # No survey writes, role changes, messages, emails or account creation.
        try:
            print("Firebase live readiness: " + json.dumps(check_live_firebase()), flush=True)
        except Exception as error:
            print("Firebase live read: unavailable (" + type(error).__name__ + ")", flush=True)
        import httpx
        try:
            # The existing free Render service may need a cold start.
            with httpx.Client(base_url="https://krishi-backend-ox3u.onrender.com",
                              timeout=httpx.Timeout(60, connect=10)) as client:
                for path in ("/cities", "/admin/", "/team/"):
                    response = client.get(path)
                    print("Render " + path + ": HTTP " + str(response.status_code), flush=True)
        except Exception as error:
            print("Render cities: unavailable (" + type(error).__name__ + ")", flush=True)


if __name__ == "__main__":
    main()
