"""Connect the selected Gmail sender. No email is sent by this setup command.

Default/--check is read-only. --connect opens Google's system-browser consent
flow; the operator completes Google sign-in and permission approval themselves.
"""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from dotenv import set_key
import config  # Load backend .env before choosing the sender.
from email.utils import parseaddr
from email_notifications import valid_address
from gmail_sender import SCOPES, SEND_SCOPE, TOKEN_URL, verify_sender

DEFAULT_CLIENT_FILE = ROOT / '.tool-state/gmail/client_secret.json'


def load_client_config(path):
    payload = json.loads(Path(path).read_text(encoding='utf-8-sig'))
    client = payload.get('installed')
    if not isinstance(client, dict):
        raise ValueError('Download an OAuth client of type Desktop app, not an Android or Firebase key.')
    if (client.get('auth_uri') not in ('https://accounts.google.com/o/oauth2/auth',
                                     'https://accounts.google.com/o/oauth2/v2/auth')
            or client.get('token_uri') != TOKEN_URL):
        raise ValueError('Only official Google authorization endpoints are accepted.')
    if (not isinstance(client.get('client_id'), str)
            or not client['client_id'].endswith('.apps.googleusercontent.com')
            or not isinstance(client.get('client_secret'), str) or not client['client_secret']):
        raise ValueError('The downloaded OAuth client is incomplete.')
    return {'installed': client}


def authorize(client_config, sender, flow_class=None):
    if flow_class is None:
        from google_auth_oauthlib.flow import InstalledAppFlow
        flow_class = InstalledAppFlow
    flow = flow_class.from_client_config(client_config, scopes=SCOPES,
                                          autogenerate_code_verifier=True)
    credentials = flow.run_local_server(
        host='127.0.0.1', bind_addr='127.0.0.1', port=0, open_browser=True,
        authorization_prompt_message='', timeout_seconds=180,
        success_message='Google authorization received. Return to the terminal to verify the selected sender.',
        login_hint=sender, prompt='consent', include_granted_scopes='false')
    granted = set(credentials.granted_scopes or credentials.scopes or ())
    if SEND_SCOPE not in granted or not credentials.refresh_token:
        raise ValueError('Gmail send permission and offline access are required; nothing was saved.')
    # This identity request does not read Gmail messages.
    verify_sender(credentials.token, sender)
    return credentials


def save_connection(client_config, credentials, sender, root=ROOT):
    """Atomically update ignored backend config; never print or return secrets."""
    root = Path(root)
    env = root / '.env'
    client = client_config['installed']
    settings = {'EMAIL_PROVIDER':'gmail', 'EMAIL_FROM':sender,
                'GMAIL_CLIENT_ID':client['client_id'], 'GMAIL_CLIENT_SECRET':client['client_secret'],
                'GMAIL_REFRESH_TOKEN':credentials.refresh_token}
    private_dir = root / '.tool-state/gmail'
    private_dir.mkdir(parents=True, exist_ok=True)
    export = private_dir / 'render.env'
    # Temporary files are inside the git-ignored private setup directory.
    descriptor, name = tempfile.mkstemp(dir=private_dir, suffix='.env.tmp')
    os.close(descriptor)
    temporary = Path(name)
    try:
        temporary.write_text(env.read_text(encoding='utf-8') if env.exists() else '',encoding='utf-8')
        for key, value in settings.items():
            set_key(str(temporary),key,value,quote_mode='always')
        os.replace(temporary,env)
    finally:
        temporary.unlink(missing_ok=True)
    export.write_text('',encoding='utf-8')
    for key,value in settings.items():
        set_key(str(export),key,value,quote_mode='always')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--check',action='store_true',help='Inspect local setup only (default)')
    mode.add_argument('--connect',action='store_true',help='Open Google consent and save the selected account connection')
    parser.add_argument('--client-secrets',type=Path,default=DEFAULT_CLIENT_FILE)
    args = parser.parse_args()
    sender = parseaddr(os.getenv('EMAIL_FROM',''))[1]
    if not valid_address(sender):
        parser.exit(1,'Set the selected sender address in EMAIL_FROM first.\n')
    installed = importlib.util.find_spec('google_auth_oauthlib') is not None
    if not args.connect:
        print('Selected sender:',sender)
        print('Google OAuth setup library:', 'installed' if installed else 'not installed')
        print('Desktop OAuth client file:', 'present' if args.client_secrets.is_file() else 'missing')
        print('Read-only check. No Google login or email sending was attempted.')
        return
    if not installed:
        parser.exit(1,'Install setup support: python -m pip install -r requirements-gmail-setup.txt\n')
    if not args.client_secrets.is_file():
        parser.exit(1,'Download a Google Desktop app OAuth client JSON to .tool-state/gmail/client_secret.json first.\n')
    try:
        client = load_client_config(args.client_secrets)
        print('Complete Google sign-in and review the send-email permission in your browser.')
        print('Use the selected college account. No test email will be sent.')
        credentials = authorize(client,sender)
        save_connection(client,credentials,sender)
    except KeyboardInterrupt:
        parser.exit(1,'Connection cancelled.\n')
    except Exception as error:
        # OAuth/HTTP exceptions may contain tokens or codes. Do not print them.
        parser.exit(1,'Gmail connection was not completed ('+type(error).__name__+'). '
                    'Check the selected account, consent permissions and college policy. No email was sent.\n')
    print('Gmail connection saved privately. No email was sent.')
    print('Restart the local backend. For Render, import .tool-state/gmail/render.env into its environment settings.')
    print('That file contains credentials: do not commit, share in chat or put it in a mobile app.')


if __name__ == '__main__':
    main()