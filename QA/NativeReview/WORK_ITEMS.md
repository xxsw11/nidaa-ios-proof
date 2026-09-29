# Integration review work items

PR4 branch:codex/native-integration-review; base PR3 180d965, dependent on open PR2. No merge authorized. Root integrates publication/evidence; existing specialists have handed off their bounded work.

| Owner | Scope | State | Evidence / remaining gate |
|---|---|---|---|
| Root | Client review, workflows, evidence and delivery | Delivered with explicit gaps | Nine backend/client findings fixed; final saved-selection failure retained in delivery |
| Backend | Auth/domain/RLS, restoration | Verified |031:55 backend+45 reference+14 QA+24 client and real official SDK journey passed |
| Runtime reviewer | Native setup/isolation | Environment blocked | Configured policy allows wildcard bind/listen; fail-closed before services, no repeated unchanged setup |
| UI | Input and MOCK/local regressions | Verified except saved selection |d6:8 MOCK+16 local passes;6a:remaining XXXL local case passes; three AutoFill-On functional cases pass |
| Root | Native saved selection | Unresolved, failed |9a507fe run36525193498 failed saved selection (0/1;0 skips; Release passed) after native Save and Passwords tap. Dynamic identity discovery did not resolve it; no personal-account requirement was observed |

Source-bound results, original failures and remaining limits: [status](../../NATIVE_REVIEW_STATUS.md), [coverage](COVERAGE.md), [attempt history](attempt-history.json), [next step](../../NEXT_REVIEW.md). No specialist may merge or independently publish.
