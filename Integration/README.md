# NIDAA isolated integration trial

This is a real local Supabase Auth (GoTrue), PostgreSQL and HTTP service. Verification and recovery messages go only to Mailpit. The notification worker writes to a database fake sink; it never contacts APNs. The original implementation is in [PR #3](https://github.com/xxsw11/nidaa-ios-proof/pull/3), which depends on open PR #2. Current review fixes and native verification are on `codex/native-integration-review` in [PR #4](https://github.com/xxsw11/nidaa-ios-proof/pull/4). None is automatically merged.

## Clean environment

Use Docker Engine with Compose v2, Git and Python 3.12 on a machine capable of Linux containers. Windows needs a working Docker-compatible Linux runtime; the current authoring machine has none. The `local-integration.yml` workflow runs the same stack on a standard Ubuntu runner. No Supabase account, CLI, subscription, Apple hardware or signing certificate is required for backend tests.

Use the current review delivery package's `Source` directory, or clone the review branch (it is deliberately not merged into main):

```sh
git clone --branch codex/native-integration-review https://github.com/xxsw11/nidaa-ios-proof.git nidaa-local-trial
cd nidaa-local-trial
```

For an exact tested review snapshot, use the executable commits recorded in `NATIVE_REVIEW_STATUS.md`; `LOCAL_INTEGRATION_STATUS.md` preserves the prior stage. From that repository root, create a private tooling environment and install the pinned requirements:

```sh
python3.12 -m venv .venv-integration
# Linux/macOS:
.venv-integration/bin/python -m pip install -r Integration/requirements.txt -c Integration/requirements-lock.txt
.venv-integration/bin/python Integration/manage.py start
.venv-integration/bin/python Integration/manage.py health
.venv-integration/bin/python Integration/manage.py test
```

Use Python 3.12 for the pinned dependency set; newer Python versions are not implied to be supported by this lockfile. On Windows, create the environment with `py -3.12 -m venv .venv-integration`, then replace `.venv-integration/bin/python` with `.venv-integration/Scripts/python.exe`. Initial image/package downloads require internet access. Running application containers share only an internal Docker network, with no external route. The lifecycle tool fails rather than reuse occupied ports on another project.

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

For the native interface, use a Mac with Xcode 16.4 or newer (Swift 6.1+) and an installed iOS Simulator. Open `NidaaProof.xcodeproj`, select `NidaaProof-Local`, use Debug and a Simulator destination. For manual Xcode runs, copy `Config/Developer.example.xcconfig` to ignored `Config/Developer.xcconfig` and choose a test Bundle ID; leave the team empty for unsigned Simulator builds. `Scripts/ci_simulator.sh` supplies the existing Simulator-only example identifier automatically and disables signing, so it needs no Apple account. Start the isolated stack on that same Mac; the app only accepts a loopback endpoint. The review stage also prepares real native Auth/PostgreSQL/Mailpit processes without Linux containers; see [native environment setup and capability checks](../QA/NativeReview/NATIVE_ENVIRONMENT.md). Script availability is not proof that the native environment or UI journey passed. In the Arabic app, open Settings → the local integration trial. Release keeps the original local experience and excludes the trial screens. Debug alone uses the local-network transport exception. Do not point the app at a hosted or LAN service.

Register fictional addresses ending in `.invalid`, with test-only passwords of 8–72 UTF-8 bytes. Open the local inbox at `http://127.0.0.1:55424`; copy the `token` value from the verification message into the app's secure verification field. Never share mailbox screenshots, tokens or credentials. Recovery uses the same inbox and its recovery toggle; explicitly sign in with the new password afterwards for fresh server authentication. Token refresh and local biometrics do not satisfy that requirement.

Use independent Simulator installations or the CLI for independent account sessions. A invites B; copy the invitation token locally and enter it as B, then explicitly accept that sending direction. A can select B, complete the local authentication prompt and separately confirm sending. A recipient acknowledgement or opening is distinct from a human response, and neither closes the case. A dropped reply stays unknown until a lookup of the original operation resolves it; reconnection does not resend. Logout/account changes isolate the local replica; sensitive sessions and pending operations use device-only Keychain in the Apple adapter, not UserDefaults. Simulator Keychain behavior is not physical-device security certification.

Historical CI used Linux for the real Swift/backend journey and cloud macOS separately for MOCK SwiftUI tests. The current review adds separate AutoFill-enabled and real native/backend UI suites. Its ordinary MOCK interface remains explicitly labeled `MOCK`; those results cannot establish a Simulator-to-backend journey. The real suite uses one disposable Simulator sequentially, with real local account authentication and a separately labeled simulated device-authentication prompt. It does not claim simultaneous reception. Consult the status documents for completed run/commit evidence; the new definitions do not establish a pass.

### Reproduce the current native review suites safely

From the review checkout on a Mac with the required Xcode and installed Simulator runtime, use the evidence-safe wrappers:

```sh
# Existing MOCK flow regressions, now with AutoFill enabled:
bash Scripts/ci_native_review.sh integration
# Full AutoFill suite: manual/paste/navigation/recovery/visibility and saved selection:
bash Scripts/ci_native_review.sh autofill
# After diagnosing a saved-selection failure, run only that scenario:
bash Scripts/ci_native_review.sh autofill-saved
# After diagnosing the local XXXL action fixture, run only that local scenario:
NIDAA_UI_SUITE=local-large bash Scripts/ci_simulator.sh
```

For the real native/backend journey, first complete [native preparation and isolation checks](../QA/NativeReview/NATIVE_ENVIRONMENT.md), then keep those owned services alive for the live suite:

```sh
"$RUNNER_TEMP/nidaa-native-tools/venv/bin/python" Integration/native/runtime.py run \
  --fixture QA/NativeReview/native_fixture.py -- bash Scripts/ci_native_review.sh live
```

The native tools use Python 3.12 with the pinned requirements. Follow the linked instructions for a private `RUNNER_TEMP` on a local Mac. Do not launch the live suite without its private runtime and fixture. The capability stays in the XCTest runner; it must not be passed to the app or pasted into a conversation.

The wrapper calls `Scripts/ci_simulator.sh`, which creates a fresh `NIDAA-Disposable-<UUID>` Simulator and cleans up only that owned destination. Existing Simulators and physical devices remain untouched. Native Settings must report **General → AutoFill & Passwords → AutoFill Passwords and Passkeys: On**, using [Apple's documented setting](https://support.apple.com/en-sg/guide/iphone/iphf9219d8c9/ios), before the integration tests proceed. Setup fails if On cannot be verified; there is no Off fallback. The retained cropped setting attachment is named `disposable-simulator-autofill-passwords-and-passkeys-on`.

Raw XCTest logs, recordings and result bundles can contain typed secrets even when fields appear masked. The wrapper keeps them under ignored, private `PrivateEvidence/` paths and exports only allowlisted evidence through `Scripts/export_native_review.py`. Do not publish raw bundles, UI logs, mailbox contents or recordings. Use the wrapper for these suites rather than directly invoking the simulator script into publicly collected artifacts. Debug tests and Release builds have separate observed outcomes; do not infer either from source preparation.

The current password control retains one native secure text field while visibility changes, with correct content semantics, an [ASCII-capable keyboard](https://developer.apple.com/documentation/uikit/uikeyboardtype/asciicapable), LTR credential entry and surrounding Arabic RTL layout. Paste uses a native user-initiated control. Visibility evidence uses only a demonstration string that never authenticates an account. Manual entry or paste with AutoFill On is distinct from selecting a saved credential. The saved-credential test creates a fictional username/site and a fresh random local-only password through disposable Passwords, never reads the native password value, and selects that entry through native AutoFill. Its actual result is recorded separately in the current status; the earlier availability probe alone did not prove selection. No personal iCloud account is requested.

The earlier implementation branch deliberately tested manual secure entry with **AutoFill Off** after system-overlay failures. Its `disposable-simulator-autofill-passwords-and-passkeys-off` screenshots and results are historical evidence only. They do not validate this review's enabled fixture or saved-credential selection. At031, the three functional AutoFill-On tests passed with Debug/Release and inspected originals; native UI/backend remains unexecuted due to the configured isolation failure. Saved-selection and later harness outcomes must be read from the exact-run status. See [UI coverage and handoff](../QA/NativeReview/UI_HANDOFF.md) for the suite boundaries and pending validation.

## Service and data boundaries

The server derives identity and recent authentication from verified provider sessions and signed AMR evidence. Provider token refresh and local biometrics do not renew server authentication. SQL constraints, RLS and a scoped service role protect domain tables; application mutations, receipts and fake jobs share a transaction. A trial-wide transaction lock deliberately serializes decisions; this does not establish production throughput.

Tests use separate sessions and HTTP/database connections. Administrative fixture access is restricted to arranging expiry, revocation and crash scenarios and asserting database state; ordinary journeys verify through the inbox. The backup drill creates a separate randomly named database, restores a private temporary pre-deletion dump, and replays a separately exported newer deletion ledger before reads. Dumps, ledger files, credentials and mailbox contents are not evidence artifacts.

The workflow collects test names/results, runtime versions, image identities and isolation checks. A passing test report is distinct from a successful build or an unexecuted test definition. See `NATIVE_REVIEW_STATUS.md` for current review outcomes and `LOCAL_INTEGRATION_STATUS.md` for the previous stage. Existing reference-model tests remain regression checks, not proof of live integration.

Provisional decisions and known design limitations are in [DECISIONS.md](DECISIONS.md). Production rollout, hosted services, external email, real push and physical-device validation are outside this trial.
