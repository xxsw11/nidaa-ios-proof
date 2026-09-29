# Native macOS backend feasibility and runtime

Prepared 2026-09-29. This document describes implemented scripts. Their existence and Windows syntax checks **do not establish successful macOS execution**. Actual observations belong in the commit/run/attempt-associated `artifacts/native-environment/native-health.json` after the cloud capability job runs.

## Selected method and primary references

The standard `macos-15` GitHub runner is a native macOS host; no Docker, nested VM, Colima, paid runner or public tunnel is assumed. GitHub explicitly lists nested virtualization as unsupported on its arm64 macOS runners. Its current image inventory includes Xcode, Homebrew and Go. [GitHub runner limitations](https://docs.github.com/en/actions/reference/runners/github-hosted-runners), [official image inventory](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-arm64-Readme.md).

Supabase Auth is built from official tag **v2.196.0**, pinned to commit `0204331ca41a5b49f076b6fa3dc6c0d20b996590`. That source's `go.mod` specifies Go **1.26.5**; preparation explicitly requests that toolchain and verifies modules. The official Makefile supports a Darwin arm64 build. [Pinned source](https://github.com/supabase/auth/tree/0204331ca41a5b49f076b6fa3dc6c0d20b996590), [Go requirement](https://github.com/supabase/auth/blob/v2.196.0/go.mod), [build targets](https://github.com/supabase/auth/blob/v2.196.0/Makefile).

Mailpit **v1.31.3** uses its official native Darwin asset. The arm64 and amd64 SHA-256 digests from the GitHub release metadata are pinned in `prepare_assets.py`; that release has no separate checksums asset. No downloaded installation shell script is executed. SMTP and HTTP both bind to literal IPv4 loopback; SMTP relay configuration is absent and the version checker is disabled. [Official release](https://github.com/axllent/mailpit/releases/tag/v1.31.3), [native installation](https://mailpit.axllent.org/docs/install/), [configuration](https://mailpit.axllent.org/docs/configuration/).

PostgreSQL is Homebrew `postgresql@17`, with the actually installed minor version recorded. This does **not** claim the identical minor binary used by the earlier Docker17.6 run. `initdb` creates an owned private cluster with SCRAM credentials; it never starts or changes a shared Homebrew service. Unix socket listeners are disabled and TCP binds to `127.0.0.1`. [PostgreSQL17 initialization and authentication options](https://www.postgresql.org/docs/17/app-initdb.html).

## Enforced runtime boundary

All service processes and their children are launched under the same `sandbox-exec` profile: deny networking by default, permit only the Seatbelt `localhost` network selector for binding/inbound/outbound (the parser rejects numeric host strings). Services still bind literal `127.0.0.1`. This uses a deprecated system mechanism for a disposable test environment, **not** a supported production sandbox design or complete filesystem sandbox. If the tool or policy is unavailable, the trial fails closed; it does not fall back to unconstrained services. [Apple App Sandbox guidance](https://developer.apple.com/documentation/security/app_sandbox), [Apple-hosted discussion of the deprecated command](https://developer.apple.com/forums/thread/661939).

Before any service starts, a child under the profile must demonstrate: public documentation-address TCP connect and UDP send receive a policy-denial error (`EPERM`/`EACCES`); wildcard IPv4/IPv6 binds receive policy denial; and loopback TCP succeeds. A timeout or connection refusal does not count as egress isolation. After real health checks, `lsof` inspects each owned service PID and rejects non-loopback listeners. The report includes the profile hash and observed booleans. This checks the actual runner rather than assuming sandbox syntax or availability.

Dependency downloads occur before runtime isolation. The controller makes only fixed loopback requests and launches the test command; Xcode may resolve packages separately. Backend processes receive an allowlisted environment without ambient SMTP, proxy, OAuth, database or CI credentials. Temporary credentials, database, mailbox and raw process logs live under a newly created owner-only runtime directory outside the repository/artifact tree. Cleanup stops only owned process groups and deletes only that generated directory. No existing cluster, service, Simulator or personal data is changed by these backend scripts.

## Exact invocation and artifacts

From the repository root on macOS:

```sh
bash Integration/native/prepare.sh
"$RUNNER_TEMP/nidaa-native-tools/venv/bin/python" Integration/native/runtime.py run
```

For a local Mac outside GitHub Actions, set `RUNNER_TEMP` to a private existing temporary parent directory first. `NIDAA_NATIVE_TOOLS` optionally selects a separate private tool directory; otherwise it is `$RUNNER_TEMP/nidaa-native-tools`. Use a fresh tool directory for dependency preparation. No credentials belong in these variables. Installed downloads are not evidence artifacts.

The health-only invocation creates the real services, verifies actual local email signup, consumes the real verification token through the fixed Auth API, signs in with a fictional password, provisions the domain identity, logs out, and verifies the old session is rejected. It then stops the services. This smoke journey is API-based infrastructure evidence, **not native UI E2E**.

To keep the same owned services alive while the root-owned native UI script runs:

```sh
"$RUNNER_TEMP/nidaa-native-tools/venv/bin/python" Integration/native/runtime.py run \
  --fixture QA/NativeReview/native_fixture.py -- bash Scripts/ci_native_review.sh live
```

The fixture is optional and restricted to an explicitly supplied file under `QA/NativeReview`. It receives administrator/service credentials only as a private child environment, under the same network sandbox. The UI test runner receives only fixed loopback URLs and a random fixture capability. App launch configuration must not forward that capability or any administrator credential. Fixture actions may inject transport failures or explicitly labeled expiry/revocation conditions; they must never insert consent or human responses to bypass the application journey.

| Process | Literal loopback port |
|---|---:|
| Normal gateway, used by the app by default | 55421 |
| Private PostgreSQL | 55422 |
| Real Supabase Auth | 55423 |
| Local Mailpit HTTP | 55424 |
| Optional root-owned fixture control | 55425 |
| Local-only Mailpit SMTP | 55426 |
| Domain API | 55427 |
| Optional fixture fault proxy | 55428 |

The gateway switches between its existing Docker upstreams and these fixed native upstreams only with `NIDAA_NATIVE_LOOPBACK=1`; it never accepts an arbitrary target URL. Docker defaults remain unchanged.

Only `artifacts/native-environment/native-prepare.json` and `native-health.json` are generated as backend evidence. They contain versions, hashes, stages, coarse exit statuses and policy/health booleans; no response bodies, mail contents, account emails, passwords, database URLs, session tokens or keys. UI evidence must be reviewed separately before publication. Preparation failure or a failed policy/health probe is an environment failure to diagnose once, not a native UI pass.

Real data fetched through the API, local email reception and a fake notification sink establish no APNs delivery, audible sound, silent-mode bypass, physical-device security or biometric hardware behavior.
