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
| Fourth CI integration | Signup, inbox verification and password login succeeded; all 45 tests stopped at their first domain read with HTTP 401. GoTrue RLS prevented the service from reading identity/session rows; additive migration 004 grants only required read columns/policies. Retest pending |
| Fifth CI real integration | Passed: all 45 real Auth/HTTP/PostgreSQL tests, 45 reference regressions and 13 packaging/payload regressions at `65e058b383d7785880cde33e8f4694b67cded384` |
| SwiftUI/network integration | Backend gate passed; implementation now in progress |
| Simulator against real backend | Not tested |
| Physical iPhone / APNs / Critical Alerts | Deferred: no Apple devices; outside this stage |

Failed runs remain evidence of failures: [startup 1](https://github.com/xxsw11/nidaa-ios-proof/actions/runs/36422927726), [dependency download](https://github.com/xxsw11/nidaa-ios-proof/actions/runs/36423782357), [startup diagnostics](https://github.com/xxsw11/nidaa-ios-proof/actions/runs/36424119670). No notification was sent to a physical device.

The first successful actual integration run is [36425227273](https://github.com/xxsw11/nidaa-ios-proof/actions/runs/36425227273). It includes the verified A/B alert journey, C denial, real lost-response injection, database races, worker crash/restart and a real backup/restore drill with later deletion/withdrawal/block replay. A newly added 46th test of restricted provider-secret column access awaits the next run.

The implementation includes actual Auth/database adapters, transactions, domain/session barriers, durable receipts, a fake outbox, retention and separately retained deletion/revocation-ledger replay. Test definitions cover verified fictional identities and failure/race cases; their existence is not a passing result. See [setup](Integration/README.md), [decisions](Integration/DECISIONS.md) and [work ownership](Integration/WORK_ITEMS.md).

The current next action is to finish the Swift client and explicit Arabic integration screens, then run the Swift client against the private backend and independently verify Debug/Release Simulator UI. No user input is needed for this work.
