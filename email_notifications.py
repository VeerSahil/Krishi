"""Transactional survey email events; immediate best-effort delivery after commit.

Delivery acceptance is not proof of inbox delivery. Unsent events remain in
Firestore for an operator retry; no background daemon or paid queue is required.
"""
from datetime import datetime, timedelta, timezone
from email.headerregistry import Address
from email.message import EmailMessage
from email.utils import parseaddr
import hashlib
import html
import logging
import os
import smtplib

import httpx
import gmail_sender
from google.api_core.exceptions import Conflict, FailedPrecondition

logger = logging.getLogger(__name__)
COLLECTION = "survey_email_events"
STATUS_COPY = {
    "pending": ("Request received - awaiting approval", "Your survey request has been received and is waiting for admin approval. No farm visit is confirmed yet."),
    "approved": ("Farm visit approved", "Your survey request has been approved and assigned to our field team. The team will contact you to coordinate the visit; a visit time is not yet confirmed."),
    "in_progress": ("Farm visit started", "Your assigned team member has marked the farm visit as started."),
    "awaiting_review": ("Field report received - under review", "The field team has submitted your readings. The admin is reviewing the report. A crop recommendation has not been released yet."),
    "completed": ("Your survey results are ready", "The admin has reviewed and released your survey result. Open Krishi Farmer to see your report and contact the admin if you have questions."),
    "rejected": ("Survey request declined", "The admin has declined or cancelled this survey request. Please use Help in Krishi Farmer if you need clarification."),
}


def now():
    return datetime.now(timezone.utc)


def email_configuration():
    """Safe presence metadata only. Never return credentials."""
    provider = os.getenv("EMAIL_PROVIDER", "auto").strip().lower()
    if provider == "auto":
        if gmail_sender.configured():
            provider = "gmail"
        elif os.getenv("RESEND_API_KEY", "").strip():
            provider = "resend"
        else:
            provider = "smtp"
    sender = os.getenv("EMAIL_FROM", "").strip()
    if provider == "gmail":
        configured = bool(sender and gmail_sender.configured())
    elif provider == "smtp":
        sender = sender or os.getenv("SMTP_EMAIL", "").strip()
        configured = bool(sender and os.getenv("SMTP_EMAIL") and os.getenv("SMTP_PASSWORD"))
    elif provider == "resend":
        configured = bool(sender and os.getenv("RESEND_API_KEY", "").strip())
    else:
        configured = False
    return {"provider": provider, "configured": configured}


def event_id(survey_id, status):
    return hashlib.sha256((survey_id + ":" + status).encode()).hexdigest()


def queue_survey_email(batch, db, survey_id, survey):
    """Add the email to the SAME batch as the successful status transition."""
    status = survey["status"]
    enabled = {value.strip() for value in os.getenv("EMAIL_STATUSES", "approved,completed").split(",")}
    if status not in enabled:
        return None
    title, explanation = STATUS_COPY[status]
    lines = ["Hello " + str(survey.get("farmerName") or "Farmer") + ",", "", explanation, "",
             "Farm: " + str(survey.get("farmName") or "Your farm"), "Survey ID: " + survey_id,
             "Location: " + str(survey.get("city") or "Not specified")]
    if status == "completed":
        lines += ["", "Recommended crop: " + str(survey.get("recommended_crop") or survey.get("recommendedCrop") or "See your report"),
                  "Estimated rainfall: " + str(survey.get("predicted_rainfall_mm", "See your report")) + " mm"]
        if survey.get("recommendationNotice"):
            title = "Demo results are ready"
            lines += ["", str(survey["recommendationNotice"])]
    lines += ["", "This update describes the status when the email was created. Open the app for the latest status.",
              "Need help? Use Help in Krishi Farmer to contact the admin.", "", "Krishi Team"]
    text = "\n".join(lines)
    paragraphs = "".join("<p>" + html.escape(part).replace("\n", "<br>") + "</p>" for part in text.split("\n\n"))
    markup = ('<html><body style="margin:0;background:#f5f7ef;font-family:Arial,sans-serif;color:#274332">'
              '<div style="max-width:560px;margin:24px auto;padding:30px;background:white;border-radius:16px">'
              '<p style="color:#63834e;font-size:12px;letter-spacing:2px">KRISHI FARMER</p>'
              '<h1 style="font-size:23px">' + html.escape(title) + '</h1>' + paragraphs + '</div></body></html>')
    identifier = event_id(survey_id, status)
    # The status is in the subject as well as the body, including pending approval.
    data = {"surveyId": survey_id, "surveyStatus": status, "recipient": survey.get("farmerEmail", ""),
            "subject": "Krishi | " + title, "text": text, "html": markup,
            "deliveryStatus": "queued", "createdAt": now(), "attempts": 0}
    batch.set(db.collection(COLLECTION).document(identifier), data)
    return identifier


def valid_address(value, allow_display_name=False):
    if not isinstance(value, str) or not value or "\r" in value or "\n" in value:
        return False
    try:
        _, address = parseaddr(value)
        parsed = Address(addr_spec=address)
        return bool(parsed.username and parsed.domain and (allow_display_name or address == value))
    except (ValueError, IndexError):
        return False


def build_message(event, sender, identifier):
    message = EmailMessage()
    message["Subject"], message["From"], message["To"] = event["subject"], sender, event["recipient"]
    message["Message-ID"] = "<" + identifier + "@krishi.notification>"
    message.set_content(event["text"])
    message.add_alternative(event["html"], subtype="html")
    return message


def deliver_event(identifier, db, *, retry=False):
    """Attempt once after commit. Duplicate tasks cannot both claim an event.

    Explicit operator retries can retry queued, failed or unconfigured events.
    A crash during 'sending' is intentionally not retried automatically:
    Gmail/SMTP cannot prove whether a message was accepted before a lost connection.
    """
    if not identifier:
        return
    try:
        ref = db.collection(COLLECTION).document(identifier)
        snapshot = ref.get()
        if not snapshot.exists:
            return
        event = snapshot.to_dict()
        allowed = ("queued", "failed", "not_configured") if retry else ("queued",)
        if event.get("deliveryStatus") not in allowed:
            return
        if retry:
            current = db.collection("farm_inputs").document(event["surveyId"]).get()
            if not current.exists or current.to_dict().get("status") != event["surveyStatus"]:
                ref.update({"deliveryStatus": "skipped_obsolete", "updatedAt": now()},
                           option=db.write_option(last_update_time=snapshot.update_time))
                return
        if (retry and event.get("provider") == "resend" and event.get("firstSendAttemptAt")
                and now() - event["firstSendAttemptAt"] >= timedelta(hours=24)):
            ref.update({"failureType": "RetryWindowExpired", "updatedAt": now()})
            return
        config = email_configuration()
        sender = event.get("sender") or os.getenv("EMAIL_FROM", "").strip() or os.getenv("SMTP_EMAIL", "").strip()
        provider = event.get("provider") or config["provider"]
        claim = {"deliveryStatus": "sending", "attempts": event.get("attempts", 0) + 1, "attemptedAt": now()}
        try:
            ref.update(claim, option=db.write_option(last_update_time=snapshot.update_time))
        except (FailedPrecondition, Conflict):
            return
        state, provider_id, failure = "not_configured", None, None
        try:
            if not valid_address(event.get("recipient", "")):
                state = "skipped_no_recipient"
            elif config["configured"] and provider == config["provider"]:
                if not valid_address(sender, allow_display_name=True):
                    raise ValueError("Invalid email sender")
                # Freeze the provider/sender once a real attempt is made. Resend
                # retries must use the same payload and idempotency key.
                ref.update({"sender": sender, "provider": provider,
                            "firstSendAttemptAt": event.get("firstSendAttemptAt") or now()})
                if provider == "gmail":
                    message = build_message(event, sender, identifier)
                    provider_id = gmail_sender.send_message(message, parseaddr(sender)[1])
                elif provider == "resend":
                    response = httpx.post("https://api.resend.com/emails", timeout=12,
                        headers={"Authorization": "Bearer " + os.environ["RESEND_API_KEY"],
                                 "Idempotency-Key": "survey-status-" + identifier},
                        json={"from": sender, "to": [event["recipient"]], "subject": event["subject"],
                              "text": event["text"], "html": event["html"]})
                    response.raise_for_status()
                    provider_id = response.json().get("id")
                    if not provider_id:
                        raise ValueError("Email provider returned no message ID")
                elif provider == "smtp":
                    message = build_message(event, sender, identifier)
                    with smtplib.SMTP(os.getenv("SMTP_SERVER", "smtp.gmail.com"),
                                      int(os.getenv("SMTP_PORT", "587")), timeout=10) as server:
                        server.starttls()
                        server.login(os.environ["SMTP_EMAIL"], os.environ["SMTP_PASSWORD"])
                        server.send_message(message)
                else:
                    raise ValueError("Unsupported saved email provider")
                state = "sent"  # Accepted by provider; not a delivery/open receipt.
        except Exception as error:
            state, failure = "failed", type(error).__name__
            logger.warning("Survey status email failed: %s", failure)
        ref.update({"deliveryStatus": state, "providerId": provider_id, "failureType": failure, "updatedAt": now()})
        if event["surveyStatus"] == "completed":
            db.collection("farm_inputs").document(event["surveyId"]).update(
                {"emailSent": state == "sent", "emailStatus": state})
    except Exception as error:
        # A mail/storage failure must never undo the already committed workflow.
        logger.warning("Survey email delivery bookkeeping unavailable: %s", type(error).__name__)