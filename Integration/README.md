# NIDAA isolated integration trial

This is a real local Supabase Auth (GoTrue), PostgreSQL and HTTP service. Verification and recovery messages go only to Mailpit. The notification worker writes to a database fake sink; it never contacts APNs. This implementation depends on open PR #2 and is proposed in [PR #3](https://github.com/xxsw11/nidaa-ios-proof/pull/3). Neither is automatically merged.

## Clean environment

Use Docker Engine with Compose v2, Git and Python 3.11+ on a machine capable of Linux containers. Windows needs a working Docker-compatible Linux runtime; the current authoring machine has none. The `local-integration.yml` workflow runs the same stack on a standard Ubuntu runner. No Supabase account, CLI, subscription, Apple hardware or signing certificate is required for backend tests.

From the repository root, create a private tooling environment and install the pinned requirements:

```sh
python -m venv .venv-integration
# Linux/macOS:
.venv-integration/bin/python -m pip install -r Integration/requirements.txt -c Integration/requirements-lock.txt
.venv-integration/bin/python Integration/manage.py start
.venv-integration/bin/python Integration/manage.py health
.venv-integration/bin/python Integration/manage.py test
```

On Windows, replace `.venv-integration/bin/python` with `.venv-integration/Scripts/python.exe`. Initial image/package downloads require internet access. Running application containers share only an internal Docker network, with no external route. The lifecycle tool fails rather than reuse occupied ports on another project.

Local addresses are `127.0.0.1:55421` (gateway) and `127.0.0.1:55424` (local inbox). Nothing binds to the LAN; the database has no host port. Internal-only Docker networks omit host publication on the observed runner, so a Python loopback relay transports each request through `docker compose exec` standard input into the isolated gateway. It does not add a network route or proxy arbitrary destinations. This deliberately favors isolation over throughput. `start` creates ignored, ephemeral `Integration/.runtime.env` credentials; do not copy that file into an app or upload it. On Windows, keep the working directory under your private user profile. Never paste credentials into a conversation.

```sh
# Fake notification worker; performs no audio or real delivery:
.venv-integration/bin/python Integration/manage.py worker
# Stop this project, retaining its database:
.venv-integration/bin/python Integration/manage.py stop
# Explicitly erase ONLY this trial's database volume and generated credentials:
.venv-integration/bin/python Integration/manage.py reset --confirm-nidaa-reset
```

Resetting the trial is intentional data deletion. The tool never runs a global Docker prune. `start` reapplies only previously unseen migrations and rejects changes to an already applied migration. Start from reset for reproducible clean-state results. Accounts/passwords are randomized fictional fixtures; signup requires consuming a real message from the isolated inbox.

## Swift client and Arabic interface

After `start`, run the official Swift Auth adapter against the same private stack:

```sh
.venv-integration/bin/python Integration/manage.py swift-test
```

This builds the pinned Swift toolchain image, runs client unit tests, then starts a separate Swift process with only the gateway and local inbox addresses. Each fictional identity has its own in-memory session store. The live journey uses actual signup, local email verification, directional consent, shared alerts, acknowledgements, responses and session isolation. It neither needs nor receives database/admin credentials. Package dependencies are locked in `IntegrationClient/Package.resolved`.

For the native interface, use a Mac with Xcode 16.4 or newer (Swift 6.1+) and an installed iOS Simulator. Open `NidaaProof.xcodeproj`, select `NidaaProof-Local`, use Debug and a Simulator destination. Start the container stack on that same Mac; the app only accepts a loopback endpoint. In the Arabic app, open Settings → the local integration trial. Release keeps the original local experience and excludes the trial screens. Debug alone uses the local-network transport exception. Do not point the app at a hosted or LAN service.

Register fictional addresses ending in `.invalid`, with test-only passwords of 8–72 UTF-8 bytes. Open the local inbox at `http://127.0.0.1:55424`; copy the `token` value from the verification message into the app's secure verification field. Never share mailbox screenshots, tokens or credentials. Recovery uses the same inbox and its recovery toggle; explicitly sign in with the new password afterwards for fresh server authentication. Token refresh and local biometrics do not satisfy that requirement.

Use independent Simulator installations or the CLI for independent account sessions. A invites B; copy the invitation token locally and enter it as B, then explicitly accept that sending direction. A can select B, complete the local authentication prompt and separately confirm sending. A recipient acknowledgement or opening is distinct from a human response, and neither closes the case. A dropped reply stays unknown until a lookup of the original operation resolves it; reconnection does not resend. Logout/account changes isolate the local replica; sensitive sessions and pending operations use device-only Keychain in the Apple adapter, not UserDefaults. Simulator Keychain behavior is not physical-device security certification.

The current CI uses Linux for the real Swift/backend journey and cloud macOS separately for mock-based SwiftUI tests. Its mock interface is labeled `MOCK`; it does not establish a Simulator-to-backend journey. To reproduce those UI tests and Debug/Release builds on a Mac, run `bash Scripts/ci_simulator.sh`. No public tunnel is required or authorized. See the status document for actual run results and remaining limits.

## Service and data boundaries

The server derives identity and recent authentication from verified provider sessions and signed AMR evidence. Provider token refresh and local biometrics do not renew server authentication. SQL constraints, RLS and a scoped service role protect domain tables; application mutations, receipts and fake jobs share a transaction. A trial-wide transaction lock deliberately serializes decisions; this does not establish production throughput.

Tests use separate sessions and HTTP/database connections. Administrative fixture access is restricted to arranging expiry, revocation and crash scenarios and asserting database state; ordinary journeys verify through the inbox. The backup drill creates a separate randomly named database, restores a private temporary pre-deletion dump, and replays a separately exported newer deletion ledger before reads. Dumps, ledger files, credentials and mailbox contents are not evidence artifacts.

The workflow collects test names/results, runtime versions, image identities and isolation checks. A passing test report is distinct from a successful build or an unexecuted test definition. See `LOCAL_INTEGRATION_STATUS.md` for observed outcomes once recorded. Existing reference-model tests remain regression checks, not proof of live integration.

Provisional decisions and known design limitations are in [DECISIONS.md](DECISIONS.md). Production rollout, hosted services, external email, real push and physical-device validation are outside this trial.
