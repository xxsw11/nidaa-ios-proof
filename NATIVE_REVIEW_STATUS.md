# Integration review and native verification

Updated2026-09-29. [Follow-up PR4](https://github.com/xxsw11/nidaa-ios-proof/pull/4) targets PR3, which depends on PR2. All three remain open and unmerged. v06 and historical deliveries are preserved.

## Findings and fixes

Nine material backend/client findings were fixed: durable logout for expired or temporarily banned sessions; account-specific cursor advancement after provider visibility changes; complete bounded snapshots; restore cursors above the source watermark; replayed session revocation; unknown-operation receipt validation; validation before publishing an adopted identity; clearing rejected-session caches; and preserving the Auth API-version contract. The existing architecture and migrations001–004 remain; migration005 adds the required barriers. [Backend findings, impact and reproduction](QA/NativeReview/BACKEND_REVIEW.md) · [Client findings and regressions](QA/NativeReview/CLIENT_REVIEW.md).

A native input defect was also fixed by separating credential entry from the verification-token step. Manual typing, navigation, paste/recovery, visibility and focus now pass with **native AutoFill On**. The correction preserves validation and does not disable AutoFill. Test harness corrections retain every authorization/recipient assertion and add verified initial-recipient state, persisted-deletion checks and bounded offscreen navigation. [Input diagnosis and original failures](QA/NativeReview/INPUT_REVIEW.md).

## Actual evidence

All linked runs below are attempt1. Native tests used macOS15.7.9 arm64, Xcode16.4/Swift6.1.2 and a newly created iPhone16Pro Simulator, iOS18.5 build22F77. This Windows workstation did not build or run iOS.

| Scope | Observed outcome and source |
|---|---|
| Real backend and official Swift SDK | [Run36516431478](https://github.com/xxsw11/nidaa-ios-proof/actions/runs/36516431478), source031ffd5:55 actual backend tests+45 reference checks+14 QA checks+24 injected client tests, followed by the real SDK multi-account journey, passed |
| Core/client Swift regressions | [Run36522014170](https://github.com/xxsw11/nidaa-ios-proof/actions/runs/36522014170), source6a601cb:45 core+24 client tests and14 QA checks passed |
| MOCK SwiftUI integration | [Run36519447184](https://github.com/xxsw11/nidaa-ios-proof/actions/runs/36519447184), sourced6f65ec:all8 passed; Debug/Release passed; native AutoFill On |
| Existing local experience | Same d6 run:local-b8/8 and local-a8/9. The one XXXL fixture failure was diagnosed and fixed; targeted [run36522014170](https://github.com/xxsw11/nidaa-ios-proof/actions/runs/36522014170), source6a601cb, passed1/1 with Debug/Release. All17 unique cases have passing evidence across these sources; this is not a same-source all17 rerun |
| Manual/paste/navigation/visibility with AutoFill On | [Run36519447212](https://github.com/xxsw11/nidaa-ios-proof/actions/runs/36519447212), sourced6f65ec:three functional cases passed; Release passed. Saved selection failed separately, so the overall run is not green |
| Selecting a saved native credential | 9a507fe run36525193498 failed saved selection (0/1;0 skips; Release passed) after native Save and Passwords tap. Dynamic identity discovery did not resolve it; no personal-account requirement was observed; [actual result](https://github.com/xxsw11/nidaa-ios-proof/actions/runs/36525193498) |
| Native SwiftUI connected to real backend | **Not executed due to environment**; isolation gate failed before services |
| Physical iPhone/APNs/audio/Critical Alerts | **Not tested; deferred because no Apple devices** |

[Source provenance](QA/NativeReview/source-scope-provenance.json) verifies72 app/backend/client/core Git blobs unchanged between031 and9a507fe. Each test result still belongs to its recorded test-source commit. Original failed runs, the05ab test-compilation failure, artifact hashes and safe results remain in [attempt history](QA/NativeReview/attempt-history.json). Only original images actually viewed are in the delivery screenshot set; [visual findings](QA/NativeReview/VISUAL_REVIEW.md) state their limits. Raw typing logs, generated passwords, mailbox tokens and private result bundles are excluded.

## Native/backend blocker and prepared continuation

Native Auth/PostgreSQL/Mailpit preparation succeeded. At ea63b0f, [run36512065014](https://github.com/xxsw11/nidaa-ios-proof/actions/runs/36512065014) denied external TCP/UDP and allowed loopback, but did not deny wildcard IPv4/IPv6 binds. A separate bounded031 diagnostic in [run36516431643](https://github.com/xxsw11/nidaa-ios-proof/actions/runs/36516431643) confirmed wildcard listen also succeeds. Neither probe establishes remote reachability. The configured isolation mechanism failed its declared gate before credentials/backend startup; this does not imply macOS cannot host the real components. No unchanged full setup was repeated and no gate was relaxed.

Ready scripts encode registration/email verification for fictional A/B, targeted invitation and explicit directional consent, authenticated and separately confirmed creation, acknowledgment/open/response/resolution, logout isolation and restart/withdrawal. A separate fixture suite encodes disconnected refresh, lost-response lookup without duplicate creation, expiry and revocation. It uses one Simulator **sequentially**, with only local-device authentication simulated in Debug Simulator. No consent or human response is inserted to bypass the journey. These definitions remain unexecuted against a native real backend; broader native recovery/block/delete/retention and offline-mutation paths are explicit gaps in [coverage](QA/NativeReview/COVERAGE.md).

Minimum continuation: an available Mac with Xcode16.4+, installed Simulator, Python3.12, Go1.26.5, PostgreSQL17 and pinned Auth/Mailpit, plus verified isolation satisfying the existing external-egress/wildcard-bind/loopback probe. No personal Apple account, physical device or paid service is required for this Simulator scope. [Exact setup](QA/NativeReview/NATIVE_ENVIRONMENT.md) and [reproduction commands](Integration/README.md).

## Merge recommendation

**Not ready to merge at this checkpoint:** saved-credential selection remains unresolved, and native UI-to-real-backend verification remains unexecuted. The reviewed fixes and passing scopes are suitable for human code review; neither PR4 nor its dependencies is automatically merged. No production deployment, public tunnel, real email/SMS/APNs, audio or purchase occurred.
