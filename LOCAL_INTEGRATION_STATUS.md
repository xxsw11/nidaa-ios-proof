# Local integration trial — work in progress

Updated 2026-09-28. This stage implements PR #2 on its own dependent [PR #3](https://github.com/xxsw11/nidaa-ios-proof/pull/3). Neither PR is merged. The authoring environment is Windows with no available Docker runtime, Swift, Xcode or Apple device; execution uses an isolated standard Ubuntu CI runner.

## Observed results so far

| Check | Actual outcome |
|---|---|
| Existing reference-model Python tests | Passed: 45 on the authoring machine |
| Existing packaging/payload Python tests | Passed: 13 on the authoring machine |
| Integration Python compilation | Passed; this is not runtime integration evidence |
| First CI startup | Auth, PostgreSQL and migrations ran; host gateway health failed, so integration tests were skipped |
| Second CI preparation | Package-index connection timed out; no stack/test execution |
| Third CI startup | Actual service and gateway internal health passed. Docker omitted host port bindings for internal-only networking; external loopback health failed, so tests were skipped |
| Revised isolated stack | Passed real host-loopback Auth/domain health and internal-network isolation checks |
| Fourth CI integration | Signup, inbox verification and password login succeeded; all 45 tests stopped at their first domain read with HTTP 401. GoTrue RLS prevented the service from reading identity/session rows; additive migration 004 grants only required read columns/policies. Resolved by migration 004 and the following successful runs |
| Fifth CI real integration | Passed: all 45 real Auth/HTTP/PostgreSQL tests, 45 reference regressions and 13 packaging/payload regressions at `65e058b383d7785880cde33e8f4694b67cded384` |
| Official Swift HTTP/Auth client | Passed real A/B/C/B2 journey at `528b9535fbb7f1b229bb0efa0724572f7262cf6c`; 19 client unit tests also passed |
| Final backend regression | Passed: 47 real integration tests, 45 reference tests and 13 existing Python checks at the same commit |
| SwiftUI integration | Implemented; Debug/Release and 8 new + 17 existing UI tests are running on macOS |
| Simulator against real backend | Not tested |
| Physical iPhone / APNs / Critical Alerts | Deferred: no Apple devices; outside this stage |

Failed runs remain evidence of failures: [startup 1](https://github.com/xxsw11/nidaa-ios-proof/actions/runs/36422927726), [dependency download](https://github.com/xxsw11/nidaa-ios-proof/actions/runs/36423782357), [startup diagnostics](https://github.com/xxsw11/nidaa-ios-proof/actions/runs/36424119670). No notification was sent to a physical device.

The first successful actual integration run is [36425227273](https://github.com/xxsw11/nidaa-ios-proof/actions/runs/36425227273). It includes the verified A/B alert journey, C denial, real lost-response injection, database races, worker crash/restart and a real backup/restore drill with later deletion/withdrawal/block replay. The subsequent [successful run 36434112612](https://github.com/xxsw11/nidaa-ios-proof/actions/runs/36434112612) passed all 47 backend tests, including provider-secret column denial, Swift UUID compatibility and cancellation cursor progression. It also passed 19 Swift client unit tests and the real official Swift Auth A/B/C/B2 journey. Evidence is preserved in [backend-528b953](QA/LocalIntegration/backend-528b953/README.md).

The implementation includes actual Auth/database adapters, transactions, domain/session barriers, durable receipts, a fake outbox, retention and separately retained deletion/revocation-ledger replay. Test definitions cover verified fictional identities and failure/race cases; their existence is not a passing result. See [setup](Integration/README.md), [decisions](Integration/DECISIONS.md) and [work ownership](Integration/WORK_ITEMS.md).

The current next action is to finish Debug/Release Simulator verification and inspect exported RTL/large-text screenshots. The real Swift/backend fallback has passed; no Simulator-to-backend E2E is claimed. No user input is needed.

The first full client candidate at `c27af699` passed the backend and client units but its real Swift journey failed before signup because a generated fixture password exceeded GoTrue’s 72-byte limit. The corrected 42-byte fixture passed at `528b9535`; the failed run remains [36432898804](https://github.com/xxsw11/nidaa-ios-proof/actions/runs/36432898804).
