"""Admin-only monitoring APIs and the separate browser interface."""
import json
import os
from datetime import datetime, timezone
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.encoders import jsonable_encoder
from fastapi.responses import RedirectResponse
from fastapi.staticfiles import StaticFiles
from google.cloud.firestore_v1.base_query import FieldFilter

from config import BASE_DIR, get_db

STATUSES = ("pending", "approved", "in_progress", "awaiting_review", "completed", "failed", "rejected")
CURSOR = r"^[^/]+$"


def public_firebase_config():
    """Return only client-visible Auth configuration, never an Admin SDK key."""
    api_key = os.getenv("FIREBASE_WEB_API_KEY", "").strip()
    project_id = os.getenv("FIREBASE_PROJECT_ID", "").strip()
    path = BASE_DIR / "mobile" / "android" / "app" / "google-services.json"
    if path.is_file():
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            project_id = project_id or data.get("project_info", {}).get("project_id", "")
            for client in data.get("client", []):
                keys = client.get("api_key", [])
                if not api_key and keys:
                    api_key = keys[0].get("current_key", "")
        except (OSError, ValueError, TypeError):
            pass
    return {"apiKey": api_key, "projectId": project_id,
            "configured": bool(api_key), "refreshSeconds": 30}


def count_documents(query):
    results = query.count().get(timeout=8, retry=None)
    return int(results[0][0].value) if results and results[0] else 0


def farmer_profile(snapshot):
    data = snapshot.to_dict()
    # Deliberately enumerate fields: future private user fields must not leak.
    return jsonable_encoder({
        "id": snapshot.id, "name": data.get("name") or "Farmer",
        "email": data.get("email", ""), "phone": data.get("phone", ""),
        "createdAt": data.get("createdAt"),
    })


def page_documents(query, collection, limit, cursor=None):
    if cursor:
        snapshot = collection.document(cursor).get(timeout=8, retry=None)
        if not snapshot.exists:
            raise HTTPException(400, "This page is no longer available. Refresh the list.")
        query = query.start_after(snapshot)
    docs = list(query.limit(limit + 1).stream(timeout=8, retry=None))
    return docs[:limit], docs[limit - 1].id if len(docs) > limit else None


class AdminStaticFiles(StaticFiles):
    async def get_response(self, path, scope):
        response = await super().get_response(path, scope)
        response.headers["Content-Security-Policy"] = (
            "default-src 'self'; script-src 'self'; style-src 'self'; "
            "connect-src 'self' https://identitytoolkit.googleapis.com https://securetoken.googleapis.com; "
            "img-src 'self' data:; frame-ancestors 'none'; base-uri 'self'; form-action 'self'"
        )
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["Referrer-Policy"] = "same-origin"
        response.headers["Cache-Control"] = "no-store"
        return response


def register_admin_routes(app, verify_admin, serialize_survey):
    router = APIRouter(prefix="/admin", tags=["Admin monitoring"])

    @router.get("/config")
    def config():
        return public_firebase_config()

    @router.get("/overview")
    def overview(admin=Depends(verify_admin), db=Depends(get_db)):
        surveys = db.collection("farm_inputs")
        totals = {
            "farmers": count_documents(db.collection("users").where(
                filter=FieldFilter("role", "==", "farmer"))),
            "surveys": count_documents(surveys),
        }
        totals["supportOpen"] = count_documents(db.collection("support_threads").where(filter=FieldFilter("status", "==", "open")))
        for status in STATUSES:
            totals[status] = count_documents(surveys.where(
                filter=FieldFilter("status", "==", status)))
        totals["other"] = max(0, totals["surveys"] - sum(totals[s] for s in STATUSES))
        recent = surveys.order_by("createdAt", direction="DESCENDING").limit(8)
        return {
            "totals": totals,
            "recentSurveys": [serialize_survey(doc) for doc in recent.stream(timeout=8, retry=None)],
            "updatedAt": datetime.now(timezone.utc),
            "admin": {"name": admin.get("name") or "Administrator",
                      "email": admin.get("email", "")},
        }

    @router.get("/farmers")
    def farmers(
        limit: int = Query(default=20, ge=1, le=100),
        cursor: str | None = Query(default=None, min_length=1, max_length=200, pattern=CURSOR),
        admin=Depends(verify_admin), db=Depends(get_db),
    ):
        collection = db.collection("users")
        query = collection.where(filter=FieldFilter("role", "==", "farmer")).order_by("__name__")
        docs, next_cursor = page_documents(query, collection, limit, cursor)
        return {"farmers": [farmer_profile(doc) for doc in docs], "nextCursor": next_cursor}

    @router.get("/team-members")
    def team_members(limit: int = Query(default=100, ge=1, le=100),
                     cursor: str | None = Query(default=None, min_length=1, max_length=200, pattern=CURSOR),
                     admin=Depends(verify_admin), db=Depends(get_db)):
        collection = db.collection("users")
        query = collection.where(filter=FieldFilter("role", "==", "team")).order_by("__name__")
        docs, next_cursor = page_documents(query, collection, limit, cursor)
        return {"members": [farmer_profile(doc) for doc in docs], "nextCursor": next_cursor}

    @router.get("/farmers/{farmer_id}")
    def farmer_details(farmer_id: str, admin=Depends(verify_admin), db=Depends(get_db)):
        profile = db.collection("users").document(farmer_id).get(timeout=8, retry=None)
        if not profile.exists or profile.to_dict().get("role") != "farmer":
            raise HTTPException(404, "Farmer not found")
        query = db.collection("farm_inputs").where(filter=FieldFilter("userId", "==", farmer_id))
        stats = {"surveys": count_documents(query)}
        for status in STATUSES:
            stats[status] = count_documents(query.where(filter=FieldFilter("status", "==", status)))
        return {"farmer": farmer_profile(profile), "stats": stats}

    @router.get("/surveys")
    def surveys(
        status: Literal["pending", "approved", "in_progress", "awaiting_review", "completed", "failed", "rejected"] | None = None,
        farmer_id: str | None = Query(default=None, min_length=1, max_length=200, pattern=CURSOR),
        limit: int = Query(default=20, ge=1, le=100),
        cursor: str | None = Query(default=None, min_length=1, max_length=200, pattern=CURSOR),
        admin=Depends(verify_admin), db=Depends(get_db),
    ):
        collection = db.collection("farm_inputs")
        query = collection.order_by("createdAt", direction="DESCENDING")
        if status:
            query = query.where(filter=FieldFilter("status", "==", status))
        if farmer_id:
            query = query.where(filter=FieldFilter("userId", "==", farmer_id))
        docs, next_cursor = page_documents(query, collection, limit, cursor)
        return {"surveys": [serialize_survey(doc) for doc in docs], "nextCursor": next_cursor}

    @router.get("")
    def admin_home():
        return RedirectResponse(url="/admin/", status_code=307)

    # Register JSON endpoints before the static mount so routes remain distinct.
    app.include_router(router)
    app.mount("/admin", AdminStaticFiles(directory=str(BASE_DIR / "admin_web"), html=True),
              name="admin-interface")
