# Integration review and native verification — in progress

Updated 2026-09-29. Follow-up [PR4](https://github.com/xxsw11/nidaa-ios-proof/pull/4) targets PR3, which depends on PR2. No PR has been merged. Prior v06/interfaces/archives remain preserved.

## Findings and verified fixes

Five backend findings cover expired-token logout, external-provider visibility/cursors, bounded complete snapshots, restore cursors and restored session revocation. Four client/protocol findings cover unknown operation receipts, corrupt pending-state adoption, rejected-session cache clearing and Auth API-version metadata. See [backend review](QA/NativeReview/BACKEND_REVIEW.md) and [client review](QA/NativeReview/CLIENT_REVIEW.md) for impact, locations and reproduction.

At `966f80abae825e9e8ca9c55fa659c3cd76ef4527`, [run36511820301 attempt1](https://github.com/xxsw11/nidaa-ios-proof/actions/runs/36511820301) passed **55 actual backend tests, 45 reference-model tests, 13 Python checks, 24 injected Swift-client tests, and the real official Swift SDK multi-account journey**. This is Linux/backend/CLI evidence, not native UI. The complete gate passed again after host-relay changes at `ea63b0f48bdc8e508792f065e3ccd3822893cdfb`, [run36512065013 attempt1](https://github.com/xxsw11/nidaa-ios-proof/actions/runs/36512065013).

The latest source031ffd5f5177b41fa2717409ac15a7e50ad8b4fa also passed the complete Linux gate in [run36516431478 attempt1](https://github.com/xxsw11/nidaa-ios-proof/actions/runs/36516431478): **55 backend,45 reference,14 QA,24 client tests and the real official SDK journey**. Original evidence is in `QA/NativeReview/evidence/backend-031ffd5`.

## Native environment result

**Native SwiftUI-to-real-backend E2E: Not executed due to environment isolation failure.** On macOS15.7.9 arm64/Xcode16.4, native Auth/PostgreSQL/Mailpit preparation succeeded. [Run36512065014 attempt1](https://github.com/xxsw11/nidaa-ios-proof/actions/runs/36512065014), commit `ea63b0f48bdc8e508792f065e3ccd3822893cdfb`, then showed external TCP/UDP denied but wildcard IPv4/IPv6 binds still permitted by the configured Seatbelt policy. The gate stopped before credentials/services. A separate031ffd5 diagnostic run36516431643 then corrected the bind-only inference by measuring listen too: both wildcard families were permitted to listen. This verifies the configured policy limitation, without claiming external accept/reachability or that macOS cannot host native components. No backend setup was repeated. No weaker fallback or mocked substitution was used. Ordinary source pushes now skip unchanged native setup; explicit retry requires a resolved isolation condition.

The prepared native tests use one Simulator sequentially, real local inbox verification and UI-created consent/responses; only local device authentication would be simulated in Debug Simulator. Since the environment gate failed, none of those native/backend UI journeys are counted as passed. [Exact setup and minimum continuation environment](QA/NativeReview/NATIVE_ENVIRONMENT.md).

## Current verification

At `031ffd5f5177b41fa2717409ac15a7e50ad8b4fa`, [AutoFill run36516431533 attempt1](https://github.com/xxsw11/nidaa-ios-proof/actions/runs/36516431533) passed the three functional AutoFill-On tests and Debug/Release. Manual Arabic registration and field navigation, native paste/login/recovery and exact noncredential visibility/focus passed. Separating mounted credential and verification-token steps fixed the earlier short native draft failure. The original saved-credential availability probe was skipped and did not select credentials.

[Simulator run36516431563 attempt1](https://github.com/xxsw11/nidaa-ios-proof/actions/runs/36516431563) passed 7/8 MOCK integration tests and 7/8 local-b tests; both Release builds passed. The remaining integration failure was the scroll-container query in the large Arabic logout test after the consent screenshot. Local-b's deletion and non-reset persistence check passed; a different later assertion found Ahmad in an alert intended for Sara only. That test had not verified its initial switch state or original recipient set. Neither shard is reported green.

Candidate `d6f65ec253f6345e6ae2e368c4b2b8d7baf88681` keeps product code unchanged, resolves a stable visible scroll container, explicitly verifies Sara-only selection with one tap and bounded state assertions, and attempts actual saved-credential selection through the disposable Passwords application. [AutoFill run36519447212](https://github.com/xxsw11/nidaa-ios-proof/actions/runs/36519447212) and [all UI shards run36519447184](https://github.com/xxsw11/nidaa-ios-proof/actions/runs/36519447184) are pending. Existing authorization assertions and the scrolling budget remain. Current recommendation: **not ready to merge while these regressions/selection checks are unresolved**.

Historical `966f80a` local UI baseline passed all17 (9+8) with Debug/Release in run36511820230. Failed3759/aff input attempts and031 partial results remain in the attempt history; earlier passes do not replace newer failures. The numeric XCTest-ID collector defect was fixed with a privacy regression. Original safe screenshots from actual runs were inspected and retain source hashes.

No physical iPhone, APNs, audible sound, silent-mode bypass, Critical Alerts, hardware biometrics or physical Keychain validation was performed. Those remain deferred because no Apple devices are available. No hosted deployment, external email/SMS, purchases or merges occurred.

[Detailed coverage boundaries](QA/NativeReview/COVERAGE.md) · [preserved attempt history](QA/NativeReview/attempt-history.json).

Compiler checkpoint:05ab0f failed UI-test compilation before execution (optional application inferred inside an array); Release passed. Candidate d6f65ec guards the nonoptional application without changing assertions. Original reports are in evidence/compile-05ab0f and attempt-history.json. This is a test-source failure, not a runtime environment failure.
