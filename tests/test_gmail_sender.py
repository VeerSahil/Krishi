"""Gmail/OAuth tests use fake tokens and HTTP; no real Google consent or mail."""
import base64
from email import policy
from email.parser import BytesParser
import json
from types import SimpleNamespace

import httpx
import pytest
from dotenv import dotenv_values

import email_notifications as mail
import gmail_sender as gmail
from scripts import connect_gmail as setup
from test_pipeline import ADMIN, FARMER, approve, book

SENDER = 'sahilveer2024.comp@mmcoe.edu.in'
CLIENT = {'installed': {'client_id':'test.apps.googleusercontent.com', 'client_secret':'client-secret-test',
    'auth_uri':'https://accounts.google.com/o/oauth2/auth','token_uri':gmail.TOKEN_URL}}


def configure(monkeypatch):
    for key,value in {'EMAIL_PROVIDER':'gmail','EMAIL_FROM':SENDER,'GMAIL_CLIENT_ID':'client-test',
                      'GMAIL_CLIENT_SECRET':'secret-test','GMAIL_REFRESH_TOKEN':'refresh-test'}.items():
        monkeypatch.setenv(key,value)


def response(url, data, status=200):
    return httpx.Response(status,json=data,request=httpx.Request('POST',url))


def test_approved_gmail_message_uses_selected_sender_and_registered_farmer(api,monkeypatch):
    client,db = api
    configure(monkeypatch)
    calls=[]
    def post(url,**kwargs):
        calls.append((url,kwargs))
        if url==gmail.TOKEN_URL:
            assert kwargs['data']['grant_type']=='refresh_token'
            return response(url,{'access_token':'access-test','scope':gmail.SEND_SCOPE})
        assert url==gmail.SEND_URL
        assert kwargs['headers']['Authorization']=='Bearer access-test'
        return response(url,{'id':'gmail-message-1'})
    def get(url,**kwargs):
        assert url==gmail.IDENTITY_URL
        return response(url,{'email':SENDER,'email_verified':True})
    monkeypatch.setattr(gmail.httpx,'post',post)
    monkeypatch.setattr(gmail.httpx,'get',get)
    survey_id=book(client,farmerEmail='spoofed@example.invalid')
    assert approve(client,survey_id).status_code==200
    encoded=calls[-1][1]['json']['raw']
    message=BytesParser(policy=policy.default).parsebytes(base64.urlsafe_b64decode(encoded))
    assert message['From']==SENDER
    assert message['To']=='farmer@example.invalid'
    assert 'approved' in message['Subject'].lower()
    assert survey_id in message.get_body(preferencelist=('plain',)).get_content()
    assert 'refresh-test' not in message.as_string()
    event=db.collection(mail.COLLECTION).document(mail.event_id(survey_id,'approved')).get().to_dict()
    assert event['provider']=='gmail' and event['providerId']=='gmail-message-1'
    assert event['deliveryStatus']=='sent'
    assert client.get('/health').json()['emailProvider']=='gmail'


@pytest.mark.parametrize('identity',[
    {'email':'other@example.invalid','email_verified':True},
    {'email':SENDER,'email_verified':False},
])
def test_unverified_or_wrong_google_account_cannot_send_as_selected_sender(api,monkeypatch,identity):
    client,db=api
    configure(monkeypatch)
    calls=[]
    def post(url,**kwargs):
        calls.append(url)
        assert url==gmail.TOKEN_URL
        return response(url,{'access_token':'access-test','scope':gmail.SEND_SCOPE})
    monkeypatch.setattr(gmail.httpx,'post',post)
    monkeypatch.setattr(gmail.httpx,'get',lambda url,**kwargs:response(url,identity))
    survey_id=book(client)
    assert approve(client,survey_id).status_code==200
    assert calls==[gmail.TOKEN_URL]
    event=db.collection(mail.COLLECTION).document(mail.event_id(survey_id,'approved')).get().to_dict()
    assert event['deliveryStatus']=='failed' and event['failureType']=='GmailAuthorizationError'
    assert client.get('/survey/'+survey_id,headers=FARMER).json()['status']=='approved'


def test_revoked_google_grant_is_safe_and_does_not_undo_approval(api,monkeypatch,caplog):
    client,db=api
    configure(monkeypatch)
    monkeypatch.setattr(gmail.httpx,'post',lambda url,**kwargs:response(url,{'error':'invalid_grant'},400))
    survey_id=book(client)
    assert approve(client,survey_id).status_code==200
    event=db.collection(mail.COLLECTION).document(mail.event_id(survey_id,'approved')).get().to_dict()
    assert event['deliveryStatus']=='failed'
    assert 'refresh-test' not in caplog.text and 'secret-test' not in caplog.text


def test_connect_flow_uses_pkce_loopback_and_send_scope_without_inbox_read(monkeypatch):
    options={}
    credentials=SimpleNamespace(scopes=gmail.SCOPES,granted_scopes=None,refresh_token='refresh-test',token='access-test')
    class Flow:
        @classmethod
        def from_client_config(cls,config,**kwargs):
            options.update(kwargs)
            return cls()
        def run_local_server(self,**kwargs):
            options.update(kwargs)
            return credentials
    verified=[]
    monkeypatch.setattr(setup,'verify_sender',lambda token,sender:verified.append((token,sender)))
    assert setup.authorize(CLIENT,SENDER,Flow) is credentials
    assert options['autogenerate_code_verifier'] is True
    assert options['host']==options['bind_addr']=='127.0.0.1'
    assert options['port']==0 and options['login_hint']==SENDER
    assert options['prompt']=='consent' and gmail.SEND_SCOPE in options['scopes']
    assert not any('gmail.readonly' in scope or 'gmail.modify' in scope for scope in options['scopes'])
    assert verified==[('access-test',SENDER)]


def test_connect_refuses_partial_consent_before_saving(monkeypatch):
    class Flow:
        @classmethod
        def from_client_config(cls,*args,**kwargs):return cls()
        def run_local_server(self,**kwargs):
            return SimpleNamespace(scopes=['openid'],granted_scopes=['openid'],refresh_token='refresh',token='access')
    monkeypatch.setattr(setup,'verify_sender',lambda *args:pytest.fail('Partial grants must not proceed'))
    with pytest.raises(ValueError):setup.authorize(CLIENT,SENDER,Flow)


def test_client_json_must_be_a_google_desktop_client(tmp_path):
    path=tmp_path/'client.json'
    path.write_text(json.dumps(CLIENT),encoding='utf-8')
    assert setup.load_client_config(path)==CLIENT
    path.write_text(json.dumps({'web':CLIENT['installed']}),encoding='utf-8')
    with pytest.raises(ValueError):setup.load_client_config(path)
    bad={'installed':{**CLIENT['installed'],'token_uri':'https://untrusted.invalid/token'}}
    path.write_text(json.dumps(bad),encoding='utf-8')
    with pytest.raises(ValueError):setup.load_client_config(path)


def test_connection_secrets_are_saved_privately_and_preserve_existing_config(tmp_path,capsys):
    (tmp_path/'.env').write_text('GEMINI_API_KEY=keep-existing\nSMTP_EMAIL=keep-existing-sender\n',encoding='utf-8')
    setup.save_connection(CLIENT,SimpleNamespace(refresh_token='refresh-test'),SENDER,root=tmp_path)
    saved=dotenv_values(tmp_path/'.env')
    assert saved['GEMINI_API_KEY']=='keep-existing'
    assert saved['EMAIL_FROM']==SENDER and saved['EMAIL_PROVIDER']=='gmail'
    assert saved['GMAIL_REFRESH_TOKEN']=='refresh-test'
    exported=dotenv_values(tmp_path/'.tool-state/gmail/render.env')
    assert exported['GMAIL_REFRESH_TOKEN']=='refresh-test'
    assert 'GEMINI_API_KEY' not in exported
    assert 'refresh-test' not in capsys.readouterr().out