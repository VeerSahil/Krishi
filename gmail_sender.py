"""Send through Gmail HTTPS using a sender-authorized OAuth refresh token.

No inbox-reading scope is used. A verified Google account identity must match
EMAIL_FROM; an unrelated Google sign-in can never silently replace the sender.
"""
import base64
import os

import httpx

SEND_SCOPE = "https://www.googleapis.com/auth/gmail.send"
IDENTITY_SCOPE = "https://www.googleapis.com/auth/userinfo.email"
SCOPES = ["openid", IDENTITY_SCOPE, SEND_SCOPE]
TOKEN_URL = "https://oauth2.googleapis.com/token"
IDENTITY_URL = "https://openidconnect.googleapis.com/v1/userinfo"
SEND_URL = "https://gmail.googleapis.com/gmail/v1/users/me/messages/send"
OAUTH_VARIABLES = ("GMAIL_CLIENT_ID", "GMAIL_CLIENT_SECRET", "GMAIL_REFRESH_TOKEN")


class GmailAuthorizationError(RuntimeError):
    """Only a sanitized explanation, never provider responses or tokens."""


def configured():
    return all(os.getenv(key, "").strip() for key in OAUTH_VARIABLES)


def verify_sender(access_token, expected_sender):
    response = httpx.get(IDENTITY_URL, headers={"Authorization": "Bearer " + access_token}, timeout=10)
    response.raise_for_status()
    identity = response.json()
    email = identity.get("email", "")
    if (identity.get("email_verified") is not True or not isinstance(email, str)
            or email.casefold() != expected_sender.casefold()):
        raise GmailAuthorizationError("Authorize the exact verified sender account.")
    return email


def send_message(message, expected_sender):
    # Refresh only at the official Google endpoint. Never persist access tokens
    # or log OAuth errors, whose request bodies can contain credentials.
    response = httpx.post(TOKEN_URL, timeout=12, data={
        "client_id": os.environ["GMAIL_CLIENT_ID"],
        "client_secret": os.environ["GMAIL_CLIENT_SECRET"],
        "refresh_token": os.environ["GMAIL_REFRESH_TOKEN"],
        "grant_type": "refresh_token",
    })
    response.raise_for_status()
    tokens = response.json()
    token = tokens.get("access_token")
    if not token:
        raise GmailAuthorizationError("Reconnect the sender account.")
    if tokens.get("scope") and SEND_SCOPE not in tokens["scope"].split():
        raise GmailAuthorizationError("Gmail send permission was not granted.")
    verify_sender(token, expected_sender)
    raw = base64.urlsafe_b64encode(message.as_bytes()).decode("ascii")
    response = httpx.post(SEND_URL, headers={"Authorization": "Bearer " + token},
                          json={"raw": raw}, timeout=12)
    response.raise_for_status()
    identifier = response.json().get("id")
    if not identifier:
        raise GmailAuthorizationError("Google returned no sent message ID.")
    return identifier