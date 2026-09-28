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
| Revised isolated stack | A host loopback relay now bridges into the fixed gateway through Docker exec stdin; CI verification pending |
| SwiftUI/network integration | Not started; gated on successful real backend tests |
| Simulator against real backend | Not tested |
| Physical iPhone / APNs / Critical Alerts | Deferred: no Apple devices; outside this stage |

Failed runs remain evidence of failures: [startup 1](https://github.com/xxsw11/nidaa-ios-proof/actions/runs/36422927726), [dependency download](https://github.com/xxsw11/nidaa-ios-proof/actions/runs/36423782357), [startup diagnostics](https://github.com/xxsw11/nidaa-ios-proof/actions/runs/36424119670). No notification was sent to a physical device.

The implementation includes actual Auth/database adapters, transactions, domain/session barriers, durable receipts, a fake outbox, retention and separately retained deletion/revocation-ledger replay. Test definitions cover verified fictional identities and failure/race cases; their existence is not a passing result. See [setup](Integration/README.md), [decisions](Integration/DECISIONS.md) and [work ownership](Integration/WORK_ITEMS.md).

The current next action is to run the corrected isolated stack, fix actual runtime failures, and only then add and verify the SwiftUI client adapter. No user input is needed for this work.
