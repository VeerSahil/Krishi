"""Farmer-to-admin support. Separate human replies from chatbot messages."""
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.encoders import jsonable_encoder
from google.cloud.firestore_v1.base_query import FieldFilter
from google.api_core.exceptions import FailedPrecondition, Conflict

from admin_portal import page_documents
from config import get_db
from schemas import SupportRequest, SupportReplyRequest


def register_support_routes(app, verify_farmer, verify_admin):
    router = APIRouter(tags=["Human support"])

    @router.post("/support/messages")
    def create(request: SupportRequest, user=Depends(verify_farmer), db=Depends(get_db)):
        if request.surveyId:
            survey = db.collection("farm_inputs").document(request.surveyId).get()
            if not survey.exists or survey.to_dict().get("userId") != user["uid"]:
                raise HTTPException(403, "Choose one of your own surveys")
        profile = db.collection("users").document(user["uid"]).get().to_dict() or {}
        ref = db.collection("support_threads").document()
        timestamp = datetime.now(timezone.utc)
        ref.set({
            "userId": user["uid"], "farmerName": user.get("name") or profile.get("name") or "Farmer",
            "farmerEmail": user.get("email", ""), **request.model_dump(),
            "status": "open", "adminReply": None, "createdAt": timestamp, "updatedAt": timestamp,
        })
        return {"threadId": ref.id, "status": "open", "message": "Your message has been sent to the admin."}

    @router.get("/support/messages")
    def own(user=Depends(verify_farmer), db=Depends(get_db)):
        docs = (db.collection("support_threads").where(filter=FieldFilter("userId", "==", user["uid"]))
                .order_by("createdAt", direction="DESCENDING").stream(timeout=8, retry=None))
        return {"messages": [jsonable_encoder({**doc.to_dict(), "threadId": doc.id}) for doc in docs]}

    @router.get("/admin/support")
    def inbox(limit: int = Query(default=20, ge=1, le=100),
              cursor: str | None = Query(default=None, min_length=1, max_length=200, pattern=r"^[^/]+$"),
              admin=Depends(verify_admin), db=Depends(get_db)):
        collection = db.collection("support_threads")
        docs, next_cursor = page_documents(
            collection.order_by("createdAt", direction="DESCENDING"), collection, limit, cursor)
        return {"messages": [jsonable_encoder({**doc.to_dict(), "threadId": doc.id}) for doc in docs],
                "nextCursor": next_cursor}

    @router.post("/admin/support/{thread_id}/reply")
    def reply(thread_id: str, request: SupportReplyRequest,
              admin=Depends(verify_admin), db=Depends(get_db)):
        ref = db.collection("support_threads").document(thread_id)
        snapshot = ref.get()
        if not snapshot.exists:
            raise HTTPException(404, "Message not found")
        timestamp = datetime.now(timezone.utc)
        try:
            ref.update({"adminReply": request.reply, "repliedBy": admin["uid"], "repliedAt": timestamp,
                        "updatedAt": timestamp, "status": "answered"},
                       option=db.write_option(last_update_time=snapshot.update_time))
        except (FailedPrecondition, Conflict):
            raise HTTPException(409, "This message changed. Refresh before replying.") from None
        return {"threadId": thread_id, "status": "answered", "message": "Reply sent to the farmer"}

    app.include_router(router)
