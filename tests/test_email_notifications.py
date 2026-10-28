"""Status notification tests: all transports are mocked; no real mail is sent."""
import httpx
import pytest

import email_notifications as mail
from test_pipeline import ADMIN, FARMER, BOOK, READINGS, TEAM, approve, book, publish, submit


def capture_smtp(monkeypatch):
    messages = []
    class SMTP:
        def __init__(self, *args, **kwargs): pass
        def __enter__(self): return self
        def __exit__(self, *args): pass
        def starttls(self): pass
        def login(self, username, password):
            assert username == 'sender@example.invalid'
        def send_message(self, message): messages.append(message)
    monkeypatch.setenv('SMTP_EMAIL', 'sender@example.invalid')
    monkeypatch.setenv('SMTP_PASSWORD', 'test-only')
    monkeypatch.setattr(mail.smtplib, 'SMTP', SMTP)
    return messages


def event(db, survey_id, status):
    return db.collection(mail.COLLECTION).document(mail.event_id(survey_id, status)).get().to_dict()


def test_approval_email_uses_registered_farmer_and_is_not_duplicated(api, monkeypatch):
    client, db = api
    messages = capture_smtp(monkeypatch)
    survey_id = book(client, farmerEmail='attacker@example.invalid')
    assert messages == []  # Approval + results only by default.
    assert approve(client, survey_id, notes='Internal note: do not email this').status_code == 200
    assert len(messages) == 1
    message = messages[0]
    assert message['To'] == 'farmer@example.invalid'
    assert 'approved' in message['Subject'].lower()
    body = message.get_body(preferencelist=('plain',)).get_content()
    assert survey_id in body and 'assigned to our field team' in body
    assert 'Internal note' not in body
    assert 'Recommended crop' not in body
    assert event(db, survey_id, 'approved')['deliveryStatus'] == 'sent'
    assert approve(client, survey_id).status_code == 409
    mail.deliver_event(mail.event_id(survey_id, 'approved'), db)
    assert len(messages) == 1
    assert submit(client, survey_id).status_code == 200
    assert publish(client, survey_id).status_code == 200
    assert len(messages) == 2
    assert 'Recommended crop:' in messages[-1].get_body(preferencelist=('plain',)).get_content()
    assert client.get('/survey/'+survey_id, headers=FARMER).json()['emailSent'] is True


def test_pending_email_is_an_optional_single_booking_confirmation(api, monkeypatch):
    client, db = api
    monkeypatch.setenv('EMAIL_STATUSES', 'pending,approved,completed')
    messages = capture_smtp(monkeypatch)
    survey_id = book(client)
    assert len(messages) == 1
    assert 'awaiting approval' in messages[0]['Subject'].lower()
    assert event(db, survey_id, 'pending')['deliveryStatus'] == 'sent'
    client.get('/survey/'+survey_id, headers=FARMER)
    client.get('/survey/my-surveys', headers=FARMER)
    assert len(messages) == 1, 'Reading a status must not trigger repeated mail'


def test_under_review_notification_never_includes_the_private_crop(api, monkeypatch):
    client, _ = api
    monkeypatch.setenv('EMAIL_STATUSES', 'approved,awaiting_review,completed')
    messages = capture_smtp(monkeypatch)
    survey_id = book(client)
    assert approve(client, survey_id).status_code == 200
    assert submit(client, survey_id).status_code == 200
    body = messages[-1].get_body(preferencelist=('plain',)).get_content()
    assert 'has not been released yet' in body
    assert 'Recommended crop:' not in body
    assert 'Estimated rainfall:' not in body


def test_failed_transition_does_not_create_or_send_an_approval_email(api, monkeypatch):
    client, db = api
    messages = capture_smtp(monkeypatch)
    survey_id = book(client)
    original = db.batch
    def conflicting_batch():
        batch = original()
        commit = batch.commit
        def conflict():
            db.collection('farm_inputs').document(survey_id).update({'status':'rejected'})
            commit()
        batch.commit = conflict
        return batch
    monkeypatch.setattr(db, 'batch', conflicting_batch)
    assert approve(client, survey_id).status_code == 409
    assert messages == []
    assert event(db, survey_id, 'approved') is None


def test_missing_sender_is_visible_to_admin_but_mail_events_are_private(api):
    client, db = api
    survey_id = book(client)
    assert approve(client, survey_id).status_code == 200
    assert event(db, survey_id, 'approved')['deliveryStatus'] == 'not_configured'
    farmer = client.get('/survey/'+survey_id, headers=FARMER).json()
    admin = client.get('/survey/'+survey_id, headers=ADMIN).json()
    assert 'emailNotifications' not in farmer
    assert admin['emailNotifications'][0]['deliveryStatus'] == 'not_configured'
    assert set(admin['emailNotifications'][0]) == {'surveyStatus','deliveryStatus','createdAt','updatedAt','provider','attempts'}
    assert client.get('/health').json()['emailConfigured'] is False


@pytest.mark.parametrize('address', ['', 'invalid', 'a@example.invalid\r\nBcc:other@example.invalid'])
def test_missing_or_invalid_farmer_email_is_never_sent(api, monkeypatch, address):
    client, db = api
    messages = capture_smtp(monkeypatch)
    survey_id = book(client)
    db.collection('farm_inputs').document(survey_id).update({'farmerEmail':address})
    assert approve(client, survey_id).status_code == 200
    assert event(db, survey_id, 'approved')['deliveryStatus'] == 'skipped_no_recipient'
    assert messages == []


def test_resend_uses_https_and_stable_idempotency_for_explicit_retry(api, monkeypatch):
    client, db = api
    monkeypatch.setenv('RESEND_API_KEY','test-only-key')
    monkeypatch.setenv('EMAIL_FROM','Krishi <sender@example.invalid>')
    calls = []
    def post(url, **kwargs):
        calls.append((url,kwargs))
        if len(calls) == 1:
            raise httpx.ReadTimeout('Simulated timeout')
        return httpx.Response(200,json={'id':'provider-id'}, request=httpx.Request('POST',url))
    monkeypatch.setattr(mail.httpx, 'post', post)
    survey_id = book(client)
    assert approve(client, survey_id).status_code == 200
    assert event(db,survey_id,'approved')['deliveryStatus'] == 'failed'
    mail.deliver_event(mail.event_id(survey_id,'approved'), db, retry=True)
    assert event(db,survey_id,'approved')['deliveryStatus'] == 'sent'
    assert calls[0][0] == calls[1][0] == 'https://api.resend.com/emails'
    assert calls[0][1]['headers']['Idempotency-Key'] == calls[1][1]['headers']['Idempotency-Key']
    assert calls[0][1]['json'] == calls[1][1]['json']
    assert calls[0][1]['json']['to'] == ['farmer@example.invalid']
    mail.deliver_event(mail.event_id(survey_id,'approved'), db, retry=True)
    assert len(calls) == 2


def test_retry_skips_outdated_approval_after_survey_has_progressed(api, monkeypatch):
    client, db = api
    survey_id = book(client)
    assert approve(client,survey_id).status_code == 200
    assert event(db,survey_id,'approved')['deliveryStatus'] == 'not_configured'
    assert submit(client,survey_id).status_code == 200
    messages = capture_smtp(monkeypatch)
    mail.deliver_event(mail.event_id(survey_id,'approved'),db,retry=True)
    assert event(db,survey_id,'approved')['deliveryStatus'] == 'skipped_obsolete'
    assert messages == []

def test_email_markup_escapes_farmer_and_farm_names(api, monkeypatch):
    client, db = api
    messages = capture_smtp(monkeypatch)
    db.collection('users').document('farmer').update({'name':'<script>alert(1)</script>'})
    survey_id = book(client,farmName='<img src=x onerror=alert(1)>')
    assert approve(client,survey_id).status_code == 200
    markup = messages[0].get_body(preferencelist=('html',)).get_content()
    assert '<script>' not in markup and '<img src=x' not in markup
    assert '&lt;script&gt;' in markup and '&lt;img' in markup


def test_resend_uncertain_attempt_is_not_retried_after_idempotency_window(api, monkeypatch):
    from datetime import timedelta
    client, db = api
    monkeypatch.setenv('RESEND_API_KEY','test-only')
    monkeypatch.setenv('EMAIL_FROM','sender@example.invalid')
    calls = []
    def timeout(url,**kwargs):
        calls.append(url)
        raise httpx.ReadTimeout('Simulated lost response')
    monkeypatch.setattr(mail.httpx,'post',timeout)
    survey_id = book(client)
    assert approve(client,survey_id).status_code == 200
    ref = db.collection(mail.COLLECTION).document(mail.event_id(survey_id,'approved'))
    ref.update({'firstSendAttemptAt':mail.now()-timedelta(hours=25)})
    mail.deliver_event(ref.id,db,retry=True)
    assert len(calls) == 1
    assert ref.get().to_dict()['failureType'] == 'RetryWindowExpired'