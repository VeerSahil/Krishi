"""Shared configuration, loaded before Firebase or Gemini is initialized."""
import base64
import json
import os
from functools import lru_cache
from pathlib import Path

import firebase_admin
from dotenv import load_dotenv
from firebase_admin import credentials, firestore

BASE_DIR = Path(__file__).resolve().parent
load_dotenv(BASE_DIR / ".env")


class ConfigurationError(RuntimeError):
    """A service cannot be used until its configuration is supplied."""


def firebase_key_path():
    configured = os.getenv("GOOGLE_APPLICATION_CREDENTIALS")
    if configured:
        path = Path(configured)
        return path if path.is_absolute() else BASE_DIR / path
    for name in ("firebase_key.json", "firebase_key.json.json"):
        path = BASE_DIR / name
        if path.is_file():
            return path
    return None


def firebase_configured():
    path = firebase_key_path()
    return bool(os.getenv("FIREBASE_KEY_JSON") or (path and path.is_file()))


@lru_cache(maxsize=1)
def get_db():
    """Initialize on demand. Public routes and predictions need no key."""
    try:
        try:
            app = firebase_admin.get_app()
        except ValueError:
            encoded = os.getenv("FIREBASE_KEY_JSON", "").strip()
            path = firebase_key_path()
            if encoded:
                raw = encoded if encoded.startswith("{") else base64.b64decode(encoded, validate=True)
                credential = credentials.Certificate(json.loads(raw))
            elif path and path.is_file():
                credential = credentials.Certificate(str(path))
            else:
                raise ConfigurationError(
                    "Firebase is not configured. Restore firebase_key.json or set FIREBASE_KEY_JSON."
                )
            app = firebase_admin.initialize_app(credential, {"httpTimeout": 10})
        return firestore.client(app)
    except ConfigurationError:
        raise
    except Exception:
        # Credential parsers can include private input in their exceptions.
        raise ConfigurationError("Firebase configuration is invalid. Check the service-account key.") from None


def gemini_key():
    return os.getenv("GEMINI_API_KEY") or os.getenv("GOOGLE_API_KEY")
