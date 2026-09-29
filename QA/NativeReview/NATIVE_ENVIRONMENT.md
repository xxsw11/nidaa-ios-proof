# Native macOS backend feasibility and runtime

Prepared 2026-09-29. This document describes implemented scripts. Their existence and Windows syntax checks **do not establish successful macOS execution**. The actual `ea63b0f` capability run failed its isolation gate before services; native health and UI/backend journeys were not executed. A stricter precredential candidate at `0c12b736` also failed the expanded IPv4/IPv6 boundary. Original observations are recorded below and in their commit/run/attempt-associated reports; no further unchanged native attempt is planned.

## Selected method and primary references

The standard `macos-15` GitHub runner is a native macOS host; no Docker, nested VM, Colima, paid runner or public tunnel is assumed. GitHub explicitly lists nested virtualization as unsupported on its arm64 macOS runners. Its current image inventory includes Xcode, Homebrew and Go. [GitHub runner limitations](https://docs.github.com/en/actions/reference/runners/github-hosted-runners), [official image inventory](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-arm64-Readme.md).

Supabase Auth is built from official tag **v2.196.0**, pinned to commit `0204331ca41a5b49f076b6fa3dc6c0d20b996590`. That source's `go.mod` specifies Go **1.26.5**; preparation explicitly requests that toolchain and verifies modules. The official Makefile supports a Darwin arm64 build. [Pinned source](https://github.com/supabase/auth/tree/0204331ca41a5b49f076b6fa3dc6c0d20b996590), [Go requirement](https://github.com/supabase/auth/blob/v2.196.0/go.mod), [build targets](https://github.com/supabase/auth/blob/v2.196.0/Makefile).

Mailpit **v1.31.3** uses its official native Darwin asset. The arm64 and amd64 SHA-256 digests from the GitHub release metadata are pinned in `prepare_assets.py`; that release has no separate checksums asset. No downloaded installation shell script is executed. SMTP and HTTP both bind to literal IPv4 loopback; SMTP relay configuration is absent and the version checker is disabled. [Official release](https://github.com/axllent/mailpit/releases/tag/v1.31.3), [native installation](https://mailpit.axllent.org/docs/install/), [configuration](https://mailpit.axllent.org/docs/configuration/).

PostgreSQL is Homebrew `postgresql@17`, with the actually installed minor version recorded. This does **not** claim the identical minor binary used by the earlier Docker17.6 run. `initdb` creates an owned private cluster with SCRAM credentials; it never starts or changes a shared Homebrew service. Unix socket listeners are disabled and TCP binds to `127.0.0.1`. [PostgreSQL17 initialization and authentication options](https://www.postgresql.org/docs/17/app-initdb.html).

## Enforced runtime boundary

All service processes and their children are launched under the same `sandbox-exec` profile: deny networking by default, permit only the Seatbelt `localhost` network selector for binding/inbound/outbound (the parser rejects numeric host strings). Services still bind literal `127.0.0.1`. This uses a deprecated system mechanism for a disposable test environment, **not** a supported production sandbox design or complete filesystem sandbox. If the tool or policy is unavailable, the trial fails closed; it does not fall back to unconstrained services. [Apple App Sandbox guidance](https://developer.apple.com/documentation/security/app_sandbox), [Apple-hosted discussion of the deprecated command](https://developer.apple.com/forums/thread/661939).

Before credentials or services, the prepared runtime now requires the full 14-check matrix shared by `isolation_probe.py` and `isolation_candidate.py`: for each of IPv4 and IPv6, external TCP connect and UDP send must return `EPERM`/`EACCES`; wildcard TCP/UDP bind and implicit wildcard listen must be policy-denied; and loopback TCP/UDP exchanges must succeed. Explicit listening after a denied wildcard bind is unattempted; the separate implicit-listen case covers an unbound socket. Timeouts, refusal, unsupported families, missing results and non-boolean values never pass. The child timeout is 20 seconds. After real health checks, `lsof` inspects each owned service PID and rejects non-loopback listeners. The report includes the profile hash and all gate booleans.

This strengthened gate was prepared after the failed candidate below and verified with six local pure/mock classifier tests; it was not used to repeat the failed macOS setup. No isolation candidate passed and the active policy is unchanged. A future replacement must pass this full precredential gate under the same policy used by services; a standalone diagnostic result does not authorize launching the old profile.

Dependency downloads occur before runtime isolation. The controller makes only fixed loopback requests and launches the test command; Xcode may resolve packages separately. Backend processes receive an allowlisted environment without ambient SMTP, proxy, OAuth, database or CI credentials. Temporary credentials, database, mailbox and raw process logs live under a newly created owner-only runtime directory outside the repository/artifact tree. Cleanup stops only owned process groups and deletes only that generated directory. No existing cluster, service, Simulator or personal data is changed by these backend scripts.

## Exact invocation and artifacts

From the repository root on macOS:

```sh
bash Integration/native/prepare.sh
"$RUNNER_TEMP/nidaa-native-tools/venv/bin/python" Integration/native/runtime.py run
```

For a local Mac outside GitHub Actions, set `RUNNER_TEMP` to a private existing temporary parent directory first. `NIDAA_NATIVE_TOOLS` optionally selects a separate private tool directory; otherwise it is `$RUNNER_TEMP/nidaa-native-tools`. Use a fresh tool directory for dependency preparation. No credentials belong in these variables. Installed downloads are not evidence artifacts.

If the isolation gate succeeds, the health-only invocation is designed to create the real services, verify local email signup, consume the verification token through the fixed Auth API, sign in with a fictional password, provision the domain identity, log out, and verify the old session is rejected before stopping services. This sequence was not reached in the observed native trial. This smoke journey is API-based infrastructure evidence, **not native UI E2E**.

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

## Observed environment blocker (2026-09-29)

At commit `ea63b0f48bdc8e508792f065e3ccd3822893cdfb`, [run36512065014 attempt1](https://github.com/xxsw11/nidaa-ios-proof/actions/runs/36512065014), job109226173448, native preparation succeeded on macOS15.7.9 arm64, Xcode16.4, Python3.12.10, Go1.26.5 and PostgreSQL17.11. The actual Seatbelt probe denied external TCP/UDP and allowed loopback TCP. It **did not deny wildcard IPv4/IPv6 binds**. The required gate failed with exit3 before credentials, database or backend services were created.

The original probe measured bind only, which did not by itself prove permission to listen. A separate bounded diagnostic at031ffd5 ([run36516431643 attempt1](https://github.com/xxsw11/nidaa-ios-proof/actions/runs/36516431643)) subsequently measured both stages: wildcard IPv4/IPv6 bind **and listen succeeded**, while external TCP/UDP remained policy-denied and loopback worked. It started no backend or credentials and closed each probe socket immediately; it does not claim remote reachability or accepted external connections. See [diagnostic and primary references](ISOLATION_DIAGNOSTIC.md).

The justified stricter candidate removed the explicit bind allow while retaining filtered inbound/outbound rules. At `0c12b736a623f0da700e22fa9a0cbd18b154010d`, [run 36539307560 attempt 1](https://github.com/xxsw11/nidaa-ios-proof/actions/runs/36539307560), job `109310637268`, it **Failed**: for both IPv4 and IPv6, external TCP/UDP returned EPERM, but wildcard TCP bind/listen, wildcard UDP bind and implicit wildcard listen all succeeded. TCP/UDP loopback succeeded. The deny-all negative control passed, including loopback denial, so the observed failure concerns the candidate's permissive inbound/bind behavior rather than an entirely inactive sandbox. No backend or credentials were created.

The same report measured `VZVirtualMachine.isSupported=false`, unavailable `kern.hv_support`, and absent Docker/Colima/Podman commands on macOS 15.7.9 arm64. No usable VM/container fallback was established; no claim is made that command absence alone proves every alternative impossible. We identified no available supported alternative satisfying actual wildcard bind/listen policy denial. Packet filtering and application-only bind settings do not substitute for that requirement. The failed candidate is preserved as diagnostic evidence and is not installed as the runtime profile.

This is evidence about this configured network policy on this runner, **not a claim that macOS cannot run native Supabase/PostgreSQL**. The ready native UI scripts did not execute against a real backend. We did not relax the gate, replace the backend with mocks, or repeatedly retry the established limitation. Future ordinary pushes skip this native environment job; explicit workflow dispatch can request `native_trial` only after its isolation problem is resolved.

Minimum continuation environment: a Mac/Xcode16.4+ with an installed Simulator, Python3.12, Go1.26.5, Homebrew PostgreSQL17 and the pinned Auth/Mailpit components, plus a verified local runtime isolation mechanism satisfying the full IPv4/IPv6 external TCP/UDP, wildcard bind/listen and loopback matrix. The strengthened precredential runtime gate is prepared; a compliant policy/mechanism remains unavailable. No Apple account, paid service or physical iPhone is needed for this Simulator scope. The startup scripts remain fail-closed preparation for verification; they are not claimed successfully end-to-end tested or compatible with an unidentified replacement mechanism. Original preparation/policy reports and their artifact provenance are preserved under `evidence/environment-ea63b0f`.

## Separate evidence is not native runtime success

Later read-only inspection of the standard `macos-15-intel` runner at `569fbe03c072494130baad40fe2875947d5b4773`, [run36557137468](https://github.com/xxsw11/nidaa-ios-proof/actions/runs/36557137468), established macOS15.7.9 x86_64, `kern.hv_support=1` and `VZVirtualMachine.isSupported=true`. The first VZ helper compilation failed without a captured cause; selecting the installed macOS SDK and explicitly linking the framework produced a successful query. Docker/Colima/Podman/QEMU commands were absent. [Fixed report](evidence/intel-host-capability/36557137468.json). This corrects any inference that the ARM runner's unsupported Virtualization result applies to every available host.

No VM/container, backend, credentials or socket test was started in that inspection. Framework capability does not establish a booted VM or any replacement mechanism satisfying the existing14-check isolation contract. A VM alone is not credited as policy denial of wildcard bind/listen. The failed Seatbelt policy was not rerun on speculation or relaxed. Native real-backend E2E remains unexecuted while a compliant runtime mechanism is unverified.

The isolated Linux backend/client gates passed at `966f80a` and `ea63b0f`: 55 backend tests, 45 reference checks, 13 QA checks, 24 Swift-client tests and the live official Auth SDK journey. The existing local UI baseline passed all 17 tests and Debug/Release at `966f80a`. Neither result establishes this native service bootstrap or real native UI/backend execution.

Atd6f65ec the three functional AutoFill-On cases and all8 MOCK integration cases passed. The remaining source-bound UI results are in [current coverage](COVERAGE.md). They do not justify repeating the unchanged native isolation gate and do not establish native UI/backend success.
