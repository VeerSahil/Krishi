"""Trusted operator tool. Preview by default; --apply provisions one team account.

No email is sent. For a new account, a private password-setup link is saved in
the Git-ignored .tool-state directory for the operator to open locally.
"""
import argparse
import hashlib
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from firebase_admin import auth
from config import get_db


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("email")
    parser.add_argument("--name", default="Field team")
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    db = get_db()
    # The local client and backend must target the same project.
    client_config = json.loads((ROOT / "mobile/android/app/google-services.json").read_text())
    project = client_config["project_info"]["project_id"]
    if db.project != project:
        raise RuntimeError("Backend and Android Firebase projects differ; no changes made.")
    try:
        account = auth.get_user_by_email(args.email)
    except auth.UserNotFoundError:
        account = None
    profile = db.collection("users").document(account.uid).get() if account else None
    current_role = (profile.to_dict() or {}).get("role") if profile and profile.exists else None
    if current_role and current_role != "team":
        raise RuntimeError("This account already has another role. Use a separate team email.")
    if account and account.disabled:
        raise RuntimeError("This account is disabled. A project operator must review it first.")
    print(json.dumps({"project": project, "email": args.email, "role": "team",
                      "createAuthAccount": account is None, "apply": args.apply}), flush=True)
    if not args.apply:
        return
    new_account = account is None
    if new_account:
        account = auth.create_user(email=args.email, display_name=args.name)
    reference = db.collection("users").document(account.uid)
    if not profile or not profile.exists:
        # create() refuses to overwrite a profile created by a concurrent operator.
        reference.create({"name": args.name, "email": account.email, "role": "team",
                          "createdAt": datetime.now(timezone.utc)})
    if new_account or not account.provider_data:
        link = auth.generate_password_reset_link(account.email)
        private_dir = ROOT / ".tool-state/account-setup"
        private_dir.mkdir(parents=True, exist_ok=True)
        filename = hashlib.sha256(account.uid.encode()).hexdigest()[:16] + ".txt"
        destination = private_dir / filename
        destination.write_text(
            "Krishi field-team account: " + account.email + "\n\n"
            "Open this private link locally to choose the account password.\n"
            "Do not commit or share this file. The link expires.\n\n" + link + "\n",
            encoding="utf-8")
        print("Private password-setup instructions: " + str(destination), flush=True)
    saved = reference.get().to_dict()
    if saved.get("role") != "team":
        raise RuntimeError("Team profile verification failed.")
    print("Verified field-team profile. No email was sent.", flush=True)


if __name__ == "__main__":
    main()
