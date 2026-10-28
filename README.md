# Smart Agro AI / Krishi

This workspace contains the FastAPI backend, separate Flutter farmer and team
Android apps in `mobile/`, and admin and field-team browser interfaces.
All interfaces use the same Firebase project. Automatic Arduino-to-app transfer is deferred;
the team enters the gadget readings manually for now.

## Live deployment

The three-role backend was deployed on 28 October 2026 to the existing Render
**Free** service at https://krishi-backend-ox3u.onrender.com . Render deploys
`codex/farmer-team-arduino-flow`; the GitHub default branch was not changed.
Both existing APKs already use this URL, so this rollout does not require a new
APK. The live backend reports version `1.2.0`.

- Admin: https://krishi-backend-ox3u.onrender.com/admin/
- Field team: https://krishi-backend-ox3u.onrender.com/team/

Firebase rules and indexes were deployed to `smart-agro-ai-fd974`; the team
assignment indexes are ready. Live verification confirmed team sign-in and the
assigned approved visit in both the full and filtered API lists. The operator
also confirmed a chatbot reply in the Farmer APK and the visible assigned visit
in the Team APK after deployment.

Render Free sleeps after 15 minutes without traffic, and its next request can
take about a minute to wake it. Firebase and Gemini usage remains subject to
their existing project plans and quotas. This deployment did not enable billing
or select a paid Render instance.

## Interfaces and responsibilities

| User | Interface | Responsibilities |
| --- | --- | --- |
| Farmer | Krishi Farmer Android app | Book surveys, track requests and recorded farm readings, see released recommendations, use the chatbot, contact admin |
| Admin | `/admin/` in a laptop browser | Monitor farmers and requests, approve and assign visits, inspect reports, release recommendations, answer support messages |
| Field team | Krishi Team Android app, or `/team/` in a browser | See only assigned visits, record visit progress, submit moisture, temperature and manual N/P/K |

The browser interfaces are served by FastAPI. They require no separate Node
server or build step. Farmer signup always creates a farmer profile. The team
APK has sign-in only and accepts provisioned `team` profiles. Farmer/admin
accounts cannot enter its workspace. Team accounts signing into the farmer
APK see instructions to install Krishi Team and an optional team website link;
admin accounts see their web dashboard address.

## Survey lifecycle

1. Farmer signs in with Firebase Authentication and books a survey. The form
   includes farm name, visit address, optional contact phone, supported city,
   soil type, season and year. The backend records `pending`; it ignores any
   farmer-supplied sensor readings.
2. Admin chooses an existing field-team account and approves the visit:
   `pending -> approved`. Approval does not run a prediction.
3. The assigned team member can start the visit:
   `approved -> in_progress`. Other team members cannot access that job.
4. The team enters moisture (%), temperature (degrees C), and manually supplied
   nitrogen, phosphorus and potassium values. N/P/K must use the same units as
   the training dataset; the current CSV does not document those units.
   Submission is allowed from `approved` or `in_progress`.
5. The backend estimates rainfall from historical data and classifies a crop
   using rainfall plus all five submitted values. It atomically saves the
   readings and a private draft: `awaiting_review`.
6. Admin opens the report, inspects the draft and releases it:
   `awaiting_review -> completed`. Only then does the recommendation appear
   in the farmer app and become available as chatbot context.
7. The farmer can review a completed survey. Human help goes through the
   separate Help screen; admin replies appear in that farmer's message history.
   The chatbot does not send messages to admin on the farmer's behalf.

Admin can reject an open request/report. Completed results cannot be approved,
resubmitted or published again. Conflicting updates return HTTP 409 so a stale
screen cannot overwrite another operator's action.

Farm monitoring shows the latest recorded field-visit readings and the latest
released recommendation for each farm name/address. It is not a continuous
sensor feed. No automatic Arduino upload is implemented yet.

## Local backend

On this configured Windows PC, double-click **`build.bat`** in the project root.
It starts the backend and opens **http://127.0.0.1:8000/admin/**, or reuses an
already running Krishi backend. Sign in with an existing account whose profile
has `role: admin`. Keep the server console open while using the panel. This
launcher serves the existing browser assets directly; no separate admin build
or cloud deployment is needed.

Optional commands: `build.bat --check` checks local readiness,
`build.bat --no-browser` skips opening a browser, and `build.bat --port 8001`
uses another local port. Python is selected from `.venv`, `venv`, then PATH;
set `KRISHI_PYTHON` to a Python executable to override it. Missing dependencies
are reported with an installation command.

Use Python 3.13 and run these commands from this directory:

```powershell
python -m venv venv
.\venv\Scripts\python.exe -m pip install -r requirements.txt
# Copy only when .env does not already exist:
Copy-Item .env.example .env
# Restore firebase_key.json and enter GEMINI_API_KEY in .env.
.\venv\Scripts\python.exe scripts/check_setup.py
.\venv\Scripts\python.exe -m uvicorn main:app --host 0.0.0.0 --port 8000
```

Open:

- Backend/API docs: http://127.0.0.1:8000/docs
- Admin workspace: http://127.0.0.1:8000/admin/
- Field-team workspace: http://127.0.0.1:8000/team/

For a team phone on the same Wi-Fi, replace `127.0.0.1` with the PC's LAN IP.
The backend must be reachable from that phone. Use HTTPS for a cloud service.

Firebase credentials can come from local `firebase_key.json`,
`GOOGLE_APPLICATION_CREDENTIALS`, or `FIREBASE_KEY_JSON` containing plain JSON
or the existing Render base64 value. Relative paths resolve against the backend
directory. Private keys and the completed `.env` are ignored by Git.

The browser login uses public Firebase configuration from Android's
`google-services.json`. If that API key is restricted to Android, provide a
suitable public web API key for the same project in `FIREBASE_WEB_API_KEY` and
set `FIREBASE_PROJECT_ID`. Never put a service-account key in a browser file.

Public routes include `/`, `/health`, `/cities`, `/soil-types`, `/seasons`
and browser assets/config. All survey, prediction, support and chatbot data
routes require a genuine Firebase ID token and the appropriate role.
`/health` reports configuration presence, not remote connectivity.
`uvicorn api:app` remains a compatibility alias for the same application.

## Accounts and Firebase data

Firebase Authentication must have Email/Password sign-in enabled for the
existing project, `smart-agro-ai-fd974`.

- Farmers register through the app. Signup creates `users/{uid}.role = farmer`.
- A trusted project operator provisions admin and team accounts in Firebase
  Authentication and corresponding `users/{uid}` documents. The profile
  contains `name`, `email`, optional `phone`, `createdAt`, and exactly
  `role: admin` or `role: team`. The document ID is the Authentication UID.
- Ordinary users cannot grant themselves another role. Role changes are not
  exposed by these interfaces. The admin assignment selector lists profiles
  whose role is `team`.

For future team members, a trusted operator can preview provisioning with
`python scripts/provision_team.py team@example.com`. Add `--apply` to create
the account/profile. The script refuses to replace a different existing role,
checks the Firebase project, and saves a private password-setup link under
Git-ignored `.tool-state/account-setup/` for new accounts. It sends no email.

| Collection | Purpose | Client read access |
| --- | --- | --- |
| `users` | Account profile and role | Own profile or admin |
| `farm_inputs` | Requests, assignments, readings, released results | Owning farmer, assigned team member, admin |
| `survey_predictions` | Draft model output awaiting admin release | Admin only |
| `support_threads` | Farmer messages and admin replies | Owning farmer or admin |
| `reviews` | Completed-survey feedback | Signed-in users |
| `survey_email_events` | Saved notification content and delivery attempts | Backend only; admin API exposes safe status fields |

Writes to surveys, drafts, support and reviews go through the authenticated
backend. Firestore rules deny direct client writes. Readings and their draft
prediction use one atomic batch with a version precondition. Publication checks
that the draft matches the submitted report.

`firestore.rules` and `firestore.indexes.json` were deployed on 28 October 2026.
For subsequent rollouts, review changes against the existing project. Deploy
compatible indexes and restrictive rules, wait for indexes to finish building,
and then enable the new backend and clients.
In particular, draft privacy depends on the new rules being active before any
real draft predictions are written. Use a coordinated rollout: older APKs do
not implement this lifecycle and may attempt direct writes.

A trusted operator can deploy reviewed rules/indexes with:

```powershell
firebase deploy --project smart-agro-ai-fd974 --only firestore
```

This command changes the remote project. It was run for the initial three-role rollout.

## Separate Farmer and Team Android apps

The original source was recovered from
`D:\College Purpose\College 2nd year\krishi`. Development uses the copy in
`mobile/`; the original folder was not modified.

```powershell
cd mobile
flutter pub get
flutter analyze
flutter test
flutter build apk --release --flavor farmer -t lib/main.dart
flutter build apk --release --flavor team -t lib/main_team.dart
```

Both apps use the same source project with independent entry points and
Android product flavors:

| App | Android package | Entry point | Build-script output |
| --- | --- | --- | --- |
| Krishi Farmer | `com.sahil.krishi.krishi` | `lib/main.dart` | `mobile/build/apks/krishi-farmer.apk` |
| Krishi Team | `com.sahil.krishi.team` | `lib/main_team.dart` | `mobile/build/apks/krishi-team.apk` |

To share the existing APKs, open WhatsApp Desktop/Web, select your friend's
chat, choose the attachment button and **Document**, then select the two files
from `mobile/build/apks/`. Your friend downloads and installs the appropriate
APK on Android. Farmer users can sign up; team users need a provisioned team
account. Both apps can be installed together and use the deployed Render URL
from other networks. Running `build.bat` opens the local admin panel on this PC;
the live admin URL is listed above.

The two apps have different launcher names/icons and can be installed together.
The farmer package preserves the original app identity; both versions are
`1.2.0+3`. Firebase has a registered Android application for each package. The
team configuration is in `mobile/android/app/src/team/google-services.json`;
the existing root Android configuration remains the farmer configuration.

The native team app lists assigned visits with status filtering, cursor
pagination, pull-to-refresh and foreground polling. It opens current visit
details, starts an approved visit, validates moisture/temperature/manual N/P/K,
and submits reports through authenticated backend APIs. Reports awaiting review,
released results and cancelled visits are read-only. Starting a visit preserves
readings already typed into the form. Team members cannot publish crop results.

The default API URL remains https://krishi-backend-ox3u.onrender.com .
The three-role backend is live at that address. The `/admin/`, `/team/`,
`/admin/config` and authenticated team visit routes were verified after deployment.

On this Windows machine, Flutter's global `jdk-dir` points to a removed JDK.
Use the repeatable build script from the repository root:

```powershell
.\scripts\build_android.ps1
# Build just one app:
.\scripts\build_android.ps1 -Audience team
# Or supply your own installed JDK 17:
.\scripts\build_android.ps1 -JdkHome 'C:\path\to\jdk-17'
# Build against the PC backend for an Android emulator:
.\scripts\build_android.ps1 -ApiBaseUrl http://10.0.2.2:8000
```

It runs dependency resolution, analysis, tests and Gradle with a process-local
JDK 17. It detects the verified portable JDK in `.tool-state/java/` when present
and does not modify global Java/Flutter settings. `-SkipChecks` skips the already
completed analysis/tests for an incremental build. The existing Gradle 8.3
wrapper and current Android Studio's Java 21 are not a compatible build pair.

For an Android emulator using the PC backend:

```powershell
flutter run --flavor farmer -t lib/main.dart --dart-define=API_BASE_URL=http://10.0.2.2:8000
flutter run --flavor team -t lib/main_team.dart --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

For a physical phone, use the PC's LAN IP in `API_BASE_URL`. Local HTTP is
enabled in the existing Android manifest. Shared cloud APKs should use an HTTPS
URL. The existing Android signing configuration uses debug signing and needs
a release key before Play Store distribution. Firebase startup is configured
for Android; running Flutter web is not part of this implementation.

## Prediction models and limits

The existing LM393 prototype now has an explicit **demo temperature** option.
It generates low 15–19.9, moderate 20–29.9 or high 30–35 °C. The module's
two-state output can choose moderate/high; low is a manual demo selection.
These are software categories, not physically detected temperature thresholds.
See `hardware/README.md` for wiring and Serial commands. Team interfaces must
mark these values simulated. The backend validates the band, uses the submitted
number without resampling, and retains a demo notice through admin release,
farmer results, chatbot context and optional email. Measured input remains
available separately. No temperature sensor replacement was made.

- **Rainfall: RandomForestRegressor.** Historical monthly rainfall is summed
  for each city/year/season before training. The output is numeric millimetres.
  It represents the months actually present, not guaranteed full-season
  coverage. The bundled rainfall data ends in 2025; a future-year estimate is
  not a live weather forecast or an extrapolated climate trend.
- **Crop: RandomForestClassifier.** Inputs are estimated rainfall, moisture,
  temperature, nitrogen, phosphorus and potassium. The field workflow always
  requires manual N/P/K values; it does not silently substitute soil averages.
- **Data limitation:** the bundled crop CSV has only 15 demonstration rows.
  The classifier runs, but its accuracy has not been validated. Use a larger,
  representative dataset with documented units and held-out evaluation before
  relying on recommendations for real farming decisions.

Models are trained once per process from bundled CSVs with deterministic
settings. The historical `rainfall_model.pkl` is retained but not loaded; its
old target and library version differ. Legacy notebook helpers still support
soil-table nutrient lookup when no N/P/K values are provided. Survey submission
and the admin-only `POST /predict` preview require all three manual values.

## Chatbot, support and optional email

The Gemini key stays on the backend. Configure `GEMINI_API_KEY` and, if needed,
`GEMINI_MODEL` / `GEMINI_FALLBACK_MODEL` to models accessible to your AI project.
Defaults are `gemini-flash-lite-latest` and `gemini-flash-latest`. The previous
`gemini-2.5-flash` default was rejected for this account during live testing.
Explicit request deadlines are 12 seconds (the provider rejected 8 seconds),
with a 40-second total retry/fallback budget. A real response was verified
using the key stored only in the ignored local `.env` file.
Retries and fallback have a time budget; friendly unavailable/quota messages
do not restore quota. Real chatbot calls require a valid key and model access.

Farmer-to-admin messages use the in-app Help screen and admin Helpdesk. They
are independent of Gemini and do not require SMTP. This implementation stores
one current admin reply per support request; a farmer can send a new request
for a follow-up.

### Farmer status emails

Approval notifications are implemented locally but still need sender authentication
and deployment before they run on the live backend. The configured local sender
is the operator's selected college mailbox; no mailbox password was supplied or
changed. No real email was sent during implementation or automated tests.

By default, the backend sends a transactional email when:

- Admin approves and assigns a visit: **Farm visit approved**.
- Admin releases a recommendation: **Your survey results are ready**.

The recipient comes from the farmer's stored authenticated account, never a
request-supplied destination. The approval message includes the survey reference
and farm name. It does not invent a visit date, include internal admin notes or
reveal an unreleased recommendation. Released demo results preserve the simulated
temperature notice. No farmer APK change is required for these emails.

Email jobs are saved in `survey_email_events` in the same atomic batch as the
status update, then attempted immediately as a background task. Rejected or
conflicting approval attempts cannot send approval mail. Duplicate tasks cannot
both claim a job. Sender credentials and complete email content remain backend-only;
clients cannot read or write the jobs under the deny-by-default Firestore rules.
The admin survey details show each notification's safe delivery state.

`sent` means the provider accepted the message, not that it reached an inbox or
was opened. No delivery/open webhook has been added. Missing sender configuration,
network failure or provider refusal does not undo a successful survey action.
This is immediate best-effort sending, not guaranteed instantaneous delivery.
If the server restarts before its background task runs, the queued job remains
saved for an operator retry; there is no continuously running retry worker.

Choose backend environment settings for the hosting environment:

```dotenv
EMAIL_PROVIDER=gmail
EMAIL_STATUSES=approved,completed
EMAIL_FROM=sender@example.com
# Gmail HTTPS, after one-time Google consent:
GMAIL_CLIENT_ID=
GMAIL_CLIENT_SECRET=
GMAIL_REFRESH_TOKEN=
# Alternative HTTPS option:
RESEND_API_KEY=
# SMTP option:
SMTP_EMAIL=sender@example.com
SMTP_PASSWORD=
SMTP_SERVER=smtp.gmail.com
SMTP_PORT=587
```

`auto` uses configured Gmail OAuth first, then Resend when its API key is present, otherwise SMTP. Use `gmail`, `resend`, `smtp`, or `disabled` to select explicitly. Local Gmail SMTP uses an App Password
where the account permits one, with 2-Step Verification enabled. Do not paste
account passwords or API keys into chat, frontend files or Git. A college mailbox
may have administrator restrictions or use another mail host; confirm its provider
and allowed authentication method before supplying credentials.

#### Connect the selected Gmail sender

Gmail API support is implemented, but the selected mailbox is **not connected**
until its owner completes Google authorization. The setup check currently finds
no desktop OAuth client JSON or optional OAuth setup library. No Google permission
was granted and no real email was sent by this implementation.

For the selected college Gmail account, use the `gmail` HTTPS provider. It sends
through that account rather than verifying ownership of the college's entire DNS
domain. Each fresh access token is checked against the selected sender's verified
Google identity. Choosing a different Google account cannot silently change the
From address. The requested scopes allow sending mail and confirming the account
email; they do not allow reading or modifying the inbox.

One-time setup in the dedicated Google Cloud project `krishi-gmail-sender`
(Firebase remains in `smart-agro-ai-fd974`):

1. Enable the [Gmail API](https://console.cloud.google.com/apis/library/gmail.googleapis.com?project=krishi-gmail-sender).
2. Configure Google Auth Platform branding/audience and the requested scopes.
   If the app is External and in Testing, add the selected sender as a test user.
   Use Internal only if the project belongs to the college organization and its
   administrator permits this app. College policies may require administrator approval.
3. Create an OAuth client of type **Desktop app**, download its JSON, and save it
   as `.tool-state/gmail/client_secret.json` (or pass its path to `--client-secrets`).
   This is different from the Firebase service-account key and Android configuration.
4. From an ordinary local terminal at the repository root, run:

```powershell
python -m pip install -r requirements-gmail-setup.txt
python scripts/connect_gmail.py --check
python scripts/connect_gmail.py --connect
```

On Windows, double-click `connect_gmail.bat` in the repository root to install
the optional OAuth helper in an isolated local environment and start the same
connection flow without typing commands. It still needs the account owner to
review Google consent.

The official Google OAuth helper opens the system browser using a loopback-only
callback and PKCE. The account owner completes Google sign-in and reviews the
send-email permission. The helper checks that Google returned the exact selected
verified account, then saves the refresh token in ignored local `.env`. It sends
no test email and prints no tokens. Do not paste passwords, JSON client secrets
or refresh tokens into chat. A normal Gmail password or App Password is not
needed for the `gmail` HTTPS provider.

Restart the local backend after connecting. For the live backend, import the
privately generated `.tool-state/gmail/render.env` into Render environment settings
and deploy the changed backend. It contains only mail-related settings; existing
Firebase and Gemini settings must be retained. Keep this export private.
Google may revoke or expire refresh tokens; External apps in Testing typically
receive seven-day refresh tokens when requesting Gmail access. Plan the consent
app's production/internal configuration appropriately before long-term use.

Render Free blocks outbound SMTP on ports 25, 465 and 587; Gmail API and Resend
use HTTPS. Resend remains an alternative and requires a verified sending domain
for arbitrary farmer recipients. Its default test domain sends only to the account
owner. Merely setting a college address as `EMAIL_FROM` does not verify that
college domain for Resend. Gmail API uses the sender's own Google authorization
instead. Do not change the selected sender without the operator's instruction.

Optional extra statuses are `pending`, `in_progress`, `awaiting_review` and
`rejected`; include them in `EMAIL_STATUSES` only when wanted. A pending confirmation
runs once at booking, not repeatedly whenever someone checks the status.

Inspect a saved event without sending mail:

```powershell
python scripts/retry_status_email.py --survey-id SURVEY_ID --status approved
```

A trusted operator may add `--send` to retry that one queued, failed or unconfigured
message. The helper skips outdated status updates, already accepted mail and events
left in `sending` after an uncertain interruption. Resend retries use a stable
idempotency key and identical saved content/sender within its 24-hour window;
older attempted Resend messages are not retried. Gmail API and SMTP cannot guarantee duplicate
suppression after a lost connection, so review a failed attempt before an explicit
retry. This helper is not exposed as a public sending endpoint.

References: [Gmail send API](https://developers.google.com/workspace/gmail/api/guides/sending),
[Google desktop OAuth](https://developers.google.com/identity/protocols/oauth2/native-app),
[Render Free restrictions](https://render.com/docs/free),
[Google App Passwords](https://support.google.com/mail/answer/185833),
[Resend sender-domain requirements](https://resend.com/docs/knowledge-base/403-error-resend-dev-domain).

## Render deployment

- Build command: `pip install -r requirements.txt`
- Start command: `uvicorn main:app --host 0.0.0.0 --port $PORT`
- Keep the Firebase environment variables on Render. Configure `GEMINI_API_KEY`
  there and update `GEMINI_MODEL` / `GEMINI_FALLBACK_MODEL` to the working model
  aliases above. Local `.env` changes do not update Render secrets.
- Include `admin_web/` and `team_web/` in the deployed repository.
- Configure public Firebase browser settings if required by key restrictions.

GitHub source delivery and cloud deployment are separate steps. The Render
service and Firebase rules/indexes were deployed on 28 October 2026. Deployment
verification read the existing assigned survey without changing it or sending
email. One user-selected field-team account/profile was created and verified,
and the separate team Android package was registered in the existing Firebase
project. Private account setup instructions remain local in `.tool-state/`.

## Verification

```powershell
python -m pip install -r requirements-dev.txt
python -m pytest -q
node --test admin_web/tests/portal-api.test.js
python scripts/check_setup.py
```

Backend tests substitute Firebase, authentication and Gemini and do not send
real email. In a Windows sandbox that blocks asyncio's loopback wake-up socket:

```powershell
$env:PYTEST_DISABLE_PLUGIN_AUTOLOAD='1'
$env:AGRO_IN_MEMORY_TEST_LOOP='1'
python -m pytest -q
```

That alternative event loop is test-only and cannot register network sockets.
A separate read-only `python scripts/check_setup.py --live` probes Firebase
and Render, reports account-role counts, and checks required query indexes
without printing account or survey contents. Isolated tests do not prove live
connectivity.

The Firestore rules have a separate real-emulator suite. Install the Firebase
CLI and test dependencies, use Java 21 for the current emulator, then run from
the repository root:

```powershell
npm ci --prefix tests/firestore
firebase emulators:exec --only firestore --project demo-krishi-workflow "npm --prefix tests/firestore test"
```

These tests use only a local demo project. They refuse to run without the
loopback emulator setting, and do not change the real project's rules or data.

The complete API integration flow can also run against actual local Firebase
Auth and Firestore emulators, without production credentials or data writes:

```powershell
firebase emulators:exec --only auth,firestore --project demo-krishi-workflow "python scripts/check_local_workflow.py"
```

This checks genuine emulator signup/ID tokens, farmer profile rules, booking,
approval/assignment, team readings, atomic prediction storage, private drafts
through the actual rules, admin publication, farmer results, support privacy,
reviews and chatbot context. It disables external email/Gemini calls for this
isolated integration run. A JSON report is saved in `.tool-state/`.

Verified locally on 27–28 October 2026:

- 56 backend tests passed, including the complete staged lifecycle, role and
  assignment restrictions, private drafts, atomic conflicts, support and chat.
- 13 browser API/client wiring checks passed, including demo range boundaries.
- All 8 Firestore emulator rule tests passed: draft privacy, assigned-team
  access, farmer-scoped queries, support privacy, restricted profile updates,
  role escalation rejection, and denial of direct workflow writes.
- The full API lifecycle passed against real local Auth/Firestore emulators on
  28 October 2026. No production users/data, email or external Gemini calls
  were involved in that integration run.
- `flutter analyze`: no issues found.
- All 21 Flutter tests passed, including both account interfaces, team access
  restrictions, API contracts, pagination/filtering, form validation, preserving
  entered readings, successful submission and preventing report edits.
- Both release APKs built and their signatures verified: Farmer 22.1 MiB and
  Team 22.1 MiB, version 1.2.0 (code 3), Android API 21+, ARM32/ARM64/x86_64.
  Package names, launcher labels and independent Firebase app IDs were checked.
  Neither APK includes private `.env` or service-account files. Installation
  on a physical Android device was checked by the operator, who confirmed a
  Farmer APK chatbot reply and a visible Team APK assignment after deployment.
- Firebase credentials parse and their project matches the Android config.
- Live Firebase reads passed: 7 farmer profiles, 1 admin, 1 team member.
- A real Gemini chatbot response passed with the local configuration.
- Render reports backend version `1.2.0`; admin/team pages return HTTP 200.
- Live team sign-in and both assigned-visit lists return the existing approved task.
- Backend setup check finds all three interfaces and both model types.

Still unverified or blocked:

- Cloud Gemini configuration is present and a live farmer reply was confirmed
  by the operator. A complete live survey still needs operator verification. The
  existing assigned survey was deliberately left approved for the field visit.
- Browser login pages and their configuration load successfully. The default
  fetch receiver issue was fixed and has a regression test. Interactive live
  admin sign-in and dashboard actions still need operator verification.
- Uno USB upload, LCD initialization and demo Serial values were verified.
  Automatic Arduino-to-app transfer and physical moisture calibration remain pending.

Standalone Dart client checks, after dependency resolution:

```powershell
cd mobile
dart tool/check_backend_client.dart
```


### Crop plans, offline visits and evidence records

Farmer and Team Android apps now include an English / Hindi / Marathi selector. The selected language is stored privately on the phone; chatbot requests include its language code. User-entered notes, lab documents and admin replies retain their original text. The admin and fallback team websites remain in English.

From the farmer home, open **Crop plan & farm evidence**. Each survey has its own dated record (names alone do not identify the same plot). Add a proposed crop, planned sowing date and irrigation source. The check lists missing evidence, flags a past sowing date, gives a rainfed planning reminder, and compares with a recommendation only after admin releases it. It never certifies suitability. Up to 20 previous plan versions are retained per survey. Current records are derived from server-written timestamps; older surveys explicitly show that detailed provenance was not recorded.

The Team app caches visits that have already been opened/listed online. Before leaving, sign in and load assigned visits. During the visit, enter readings, declare their sources, and use **Save draft on phone** (partial drafts are allowed). A soil-test entry requires the original test reference and units; an optional HTTPS report link can refer to an existing lab document. Links are stored as references, not fetched or independently verified. Files are not uploaded by the app.

**Submit readings for review** first persists an immutable local report, then attempts sync. Saved reports survive restarts and are isolated by Firebase account UID. They sync while the Team app is open (refresh, foreground resume or periodic polling), or via **Sync saved reports**. No background or closed-app delivery is promised. The server rechecks role, assignment and visit status. A stable submission ID plus payload fingerprint acknowledges repeated deliveries without overwriting readings or repeating lifecycle actions. Conflicting reports remain on the phone with an error; explicit discard is available. Do not uninstall or clear app data before syncing.

Android Keystore AES-GCM protects the private local cache and language preference; Android backups are disabled, and minimum Android version is now 6.0 (API 23). Drafts require explicit saving. The fallback team website continues to require connectivity.

Field reports preserve device capture time (team-declared), server receipt time, recorded-by UID, source labels, soil-test reference/units/link and the submission ID. Admin can inspect these with the farmer's crop plan before releasing the recommendation. Farmer evidence history includes release time/reviewer and hides unreleased model results. History is paginated and ownership checked.

The existing model remains a demonstration model with undocumented training NPK units. Entering a lab unit does **not** convert inputs or establish model compatibility. Historical rainfall estimates are not live weather forecasts. Plan checks always require expert interpretation, even when all fields are present.

Validation commands after installing Flutter dependencies:

```powershell
python -m pytest -q
cd mobile
flutter analyze
flutter test
```

For physical-device validation: load an approved visit online, disable connectivity, save an incomplete draft, close/reopen the app, finish and submit the report, restore connectivity, then sync. Verify exactly one server report and no farmer-visible draft recommendation. Also test a visit cancelled/reassigned while the phone was offline. Switch languages with an existing screen open, restart, and check that the language is retained.

These source changes require a backend deployment and newly built farmer/team APKs before they are available to existing installations.


To update the phone apps after source changes, double-click `update_apps.bat` in the project root. It builds both release APKs with the existing JDK 17 setup and opens `mobile/build/apks` only after both builds succeed. Send the fresh `krishi-farmer.apk` / `krishi-team.apk` to the corresponding phones and choose **Update**. Keep installed apps and pending field reports until the update succeeds. The shortcut skips test execution because the current sandbox cannot run the normal Flutter test transport; checks should still run in an unrestricted developer environment before distribution. Building APKs does not deploy backend API changes.
