"""Isolated Firestore substitute: tests never access a real Firebase project."""
from copy import deepcopy
from types import SimpleNamespace
from datetime import datetime, timezone

import pytest
from fastapi import Header, HTTPException
from fastapi.testclient import TestClient
from google.api_core.exceptions import AlreadyExists, FailedPrecondition

import main
from memory_loop import backend_options


class Snapshot:
    def __init__(self, ref):
        self.id = ref.id
        self.exists = ref.id in ref.collection.db.data.get(ref.collection.name, {})
        stored = ref.collection.db.data.get(ref.collection.name, {}).get(ref.id)
        self.data = deepcopy(stored[0]) if stored else None
        self.update_time = stored[1] if stored else None

    def to_dict(self):
        return deepcopy(self.data)


class Document:
    def __init__(self, collection, doc_id):
        self.collection, self.id = collection, doc_id

    def get(self, **kwargs):
        return Snapshot(self)

    def set(self, data):
        self.collection.db.version += 1
        self.collection.db.data.setdefault(self.collection.name, {})[self.id] = (
            deepcopy(data), self.collection.db.version)

    def create(self, data):
        if self.get().exists:
            raise AlreadyExists("Already exists")
        self.set(data)

    def update(self, changes, option=None):
        old = self.get()
        if not old.exists or (option is not None and option != old.update_time):
            raise FailedPrecondition("Stale document")
        self.set({**old.to_dict(), **changes})


class Collection:
    def __init__(self, db, name, filters=(), order=None, maximum=None, after=None):
        self.db, self.name = db, name
        self.filters, self.order, self.maximum, self.after = filters, order, maximum, after

    def document(self, doc_id=None):
        if doc_id is None:
            self.db.sequence += 1
            doc_id = f"survey-{self.db.sequence}"
        return Document(self, doc_id)

    def where(self, *, filter):
        return Collection(self.db, self.name,
                          self.filters + ((filter.field_path, filter.value),),
                          self.order, self.maximum, self.after)

    def order_by(self, field, direction=None):
        return Collection(self.db, self.name, self.filters, (field, direction), self.maximum, self.after)

    def limit(self, maximum):
        return Collection(self.db, self.name, self.filters, self.order, maximum, self.after)

    def stream(self, **kwargs):
        docs = [self.document(key).get() for key in self.db.data.get(self.name, {})]
        docs = [doc for doc in docs if all(doc.to_dict().get(k) == v for k, v in self.filters)]
        if self.order:
            key, direction = self.order
            if key == "__name__":
                docs.sort(key=lambda doc: doc.id, reverse=direction == "DESCENDING")
            else:
                docs = [doc for doc in docs if key in doc.to_dict()]
                docs.sort(key=lambda doc: (doc.to_dict()[key], doc.id), reverse=direction == "DESCENDING")
        if self.after:
            position = next((index + 1 for index, doc in enumerate(docs) if doc.id == self.after), 0)
            docs = docs[position:]
        return iter(docs[:self.maximum] if self.maximum is not None else docs)

    def start_after(self, snapshot):
        return Collection(self.db, self.name, self.filters, self.order, self.maximum, snapshot.id)

    def count(self):
        query = self
        class Count:
            def get(self, **kwargs):
                return [[SimpleNamespace(value=len(list(query.stream())))]]
        return Count()


class FakeDB:
    def __init__(self):
        self.data, self.version, self.sequence = {}, 0, 0

    def collection(self, name):
        return Collection(self, name)

    def batch(self):
        db = self
        class Batch:
            def __init__(self):
                self.operations = []
            def update(self, ref, changes, option=None):
                self.operations.append(("update", ref, changes, option))
            def set(self, ref, data):
                self.operations.append(("set", ref, data, None))
            def commit(self):
                backup, version = deepcopy(db.data), db.version
                try:
                    for operation, ref, data, option in self.operations:
                        if operation == "update":
                            ref.update(data, option=option)
                        else:
                            ref.set(data)
                except Exception:
                    db.data, db.version = backup, version
                    raise
        return Batch()

    def write_option(self, *, last_update_time):
        return last_update_time


@pytest.fixture
def api(monkeypatch):
    db = FakeDB()
    for uid, role in (("farmer", "farmer"), ("other", "farmer"), ("admin", "admin"), ("team", "team"), ("team-other", "team")):
        db.collection("users").document(uid).set({"name": uid.title(), "role": role})

    def identity(authorization: str | None = Header(default=None)):
        if authorization not in ("Bearer farmer", "Bearer other", "Bearer admin", "Bearer team", "Bearer team-other"):
            raise HTTPException(401, "Test identity required")
        uid = authorization.split()[1]
        return {"uid": uid, "email": f"{uid}@example.invalid"}

    main.app.dependency_overrides[main.get_db] = lambda: db
    main.app.dependency_overrides[main.get_current_user] = identity
    for name in ("SMTP_EMAIL", "SMTP_PASSWORD", "GEMINI_API_KEY", "GOOGLE_API_KEY"):
        monkeypatch.delenv(name, raising=False)
    with TestClient(main.app, backend_options=backend_options()) as client:
        yield client, db
    main.app.dependency_overrides.clear()
