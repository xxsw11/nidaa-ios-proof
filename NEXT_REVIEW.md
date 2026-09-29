# Next review — integration fixes and native verification



Updated 2026-09-29. Review the follow-up [PR4](https://github.com/xxsw11/nidaa-ios-proof/pull/4) together with its dependency [PR3](https://github.com/xxsw11/nidaa-ios-proof/pull/3) and design [PR2](https://github.com/xxsw11/nidaa-ios-proof/pull/2). None is merged; tests do not authorize automatic merging. Preserve v06 and earlier delivery archives.



Current immediate gate: diagnose and fix actual AutoFill-enabled manual password/visibility failures, then verify all8 MOCK integration UI cases and3 input flows with independent Debug/Release outcomes. Candidate031ffd5 (separate credential/verification steps, input-mode diagnostics and persisted deletion check) is under cloud tests36516431533 and36516431563; see [current status](NATIVE_REVIEW_STATUS.md). Saved-credential selection is a separate scenario; the observed disposable Passwords onboarding must be completed or a concrete blocker recorded without a personal Apple account.



Backend/client fixes already passed55 actual backend tests,45 reference tests,24 client regressions and the real official Auth SDK journey in run36512065013 attempt1 at ea63b0f. All17 preserved local UI regressions passed at966f80a. Results and failures stay tied to their source commits rather than being assigned to later candidates.



Real native SwiftUI-to-backend E2E is **Not executed due to environment**. Native dependency preparation succeeded, but the actual macOS policy did not deny wildcard IPv4/IPv6 binds. A bounded031 diagnostic separately confirmed that listen also succeeds (run36516431643); this is not an external-reachability claim. It stopped before services. Do not repeat unchanged setup, relax the gate, use a hosted backend/tunnel, or count MOCK as real integration. The exact next environment step is to validate an isolation mechanism on an available Mac that passes the existing external-egress, wildcard-bind and loopback probe, then run the prepared native health gate and sequential real UI/fault suites. See [minimum setup and commands](QA/NativeReview/NATIVE_ENVIRONMENT.md).



No physical iPhone is available; notification reception and hardware behavior remain deferred and are not prerequisites for this review stage. No Apple account, purchase or real notification is needed for Simulator verification. Production deployment, external mail/SMS/APNs and merging remain outside authorization. Before any later physical-device notification/audio, obtain the exact device and testing window; never ask for secret keys or passwords in conversation.

