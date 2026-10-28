"""Authenticated Firestore snapshots over fetch/SSE; tokens never appear in URLs."""
import asyncio
import json
import time
from fastapi import Depends, Request, Query
from fastapi.responses import StreamingResponse
from config import get_db
from farm_world import public_region, staff_regions


def event_bytes(name, payload):
    return "event: " + name + "\ndata: " + json.dumps(payload, ensure_ascii=True, separators=(",", ":")) + "\n\n"


def register_world_events(app, verify_staff):
    @app.get("/world/events")
    async def events(request: Request, limit: int = Query(default=200, ge=1, le=1000), user=Depends(verify_staff), db=Depends(get_db)):
        async def stream():
            loop = asyncio.get_running_loop()
            queue = asyncio.Queue(maxsize=1)
            closed = False
            watcher = None
            def accept(payload):
                if closed: return
                if queue.full():
                    try: queue.get_nowait()
                    except asyncio.QueueEmpty: pass
                queue.put_nowait(payload)
            def changed(docs, _changes, _read_time):
                try:
                    payload = {"farms": [public_region(doc) for doc in docs], "windowLimit": limit}
                    loop.call_soon_threadsafe(accept, payload)
                except (RuntimeError, TypeError): pass
            try:
                try:
                    watcher = staff_regions(db, user).limit(limit).on_snapshot(changed)
                except Exception:
                    yield event_bytes("reconnect", {"message": "Live updates are unavailable. Use the polling fallback."})
                    return
                yield event_bytes("connected", {"mode": "firestore_snapshot", "windowLimit": limit})
                started = time.monotonic()
                last_check = started
                # Reconnect periodically with refreshed credentials; check role revocation every 15s.
                while time.monotonic() - started < 180:
                    if await request.is_disconnected(): return
                    if time.monotonic() - last_check >= 15:
                        profile = await asyncio.to_thread(lambda: db.collection("users").document(user["uid"]).get())
                        if not profile.exists or profile.to_dict().get("role") != user["role"]:
                            yield event_bytes("revoked", {"message": "Staff access changed. Sign in again."})
                            return
                        last_check = time.monotonic()
                    if user.get("exp") and time.time() >= user["exp"] - 5:
                        return
                    try:
                        payload = await asyncio.wait_for(queue.get(), timeout=10)
                        yield event_bytes("snapshot", payload)
                    except asyncio.TimeoutError:
                        yield ": keepalive\n\n"
            finally:
                closed = True
                if watcher is not None:
                    await asyncio.to_thread(watcher.unsubscribe)
        return StreamingResponse(stream(), media_type="text/event-stream",
                                 headers={"Cache-Control": "no-store", "X-Accel-Buffering": "no"})
