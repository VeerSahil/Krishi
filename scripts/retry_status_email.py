"""Inspect/retry ONE saved survey email. Read-only unless --send is provided."""
import argparse
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from config import get_db
from email_notifications import COLLECTION, STATUS_COPY, deliver_event, email_configuration, event_id


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--survey-id', required=True)
    parser.add_argument('--status', required=True, choices=STATUS_COPY)
    parser.add_argument('--send', action='store_true', help='Attempt delivery to the stored farmer email')
    args = parser.parse_args()
    db = get_db()
    identifier = event_id(args.survey_id,args.status)
    ref = db.collection(COLLECTION).document(identifier)
    snapshot = ref.get()
    if not snapshot.exists:
        parser.exit(1,'No saved email for this survey/status.\n')
    if args.send:
        if not email_configuration()['configured']:
            parser.exit(1,'Configure the sender first. No email was sent.\n')
        deliver_event(identifier,db,retry=True)
    result = ref.get().to_dict()
    print('Email status:',result['deliveryStatus'])
    print('Attempts:',result.get('attempts',0))
    print('Provider acceptance is not proof of inbox delivery.')
    if not args.send:
        print('Read-only check. Add --send to attempt delivery of this saved event.')


if __name__ == '__main__':
    main()