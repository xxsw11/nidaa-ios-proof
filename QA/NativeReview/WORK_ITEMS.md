# Integration review work items

## Acceptance-blocker follow-up (2026-09-29)

Preserve the94403ff delivery and dirty authoring checkout. Work is limited to the three user-requested gates below; no feature work or merge.

| Owner | Scope | State | Acceptance gate |
|---|---|---|---|
| UI specialist | AutoFillUITests only | Running | Full redacted screen and accessibility tree establish actual transition; retained selection/fill/login assertions |
| Backend specialist | Integration/native and isolation diagnostic note | Running | Justified stricter precredential policy candidate; IPv4/IPv6 external, wildcard and loopback observations |
| Root | Evidence exporter, workflows, publication and integration | Running | Review diagnostic evidence, fix observed causes, freeze one SHA and execute all intended regression cases |
| Review specialist | Read-only workflow/PR audit | Reviewed | Five feasible jobs must share one source; local9+8, MOCK8, AutoFill4 with explicit skip/failure counts; branch protection read unavailable403 |

PR2/3/4 remain open and unmerged; PR4 is draft. No submitted reviews were returned. Mergeability is not approval; inaccessible branch-protection metadata must not be interpreted as no required checks.

PR4 branch:codex/native-integration-review; base PR3 180d965, dependent on open PR2. No merge authorized. Root integrates publication/evidence; existing specialists have handed off their bounded work.

| Owner | Scope | State | Evidence / remaining gate |
|---|---|---|---|
| Root | Client review, workflows, evidence and delivery | Delivered with explicit gaps | Nine backend/client findings fixed; final saved-selection failure retained in delivery |
| Backend | Auth/domain/RLS, restoration | Verified |031:55 backend+45 reference+14 QA+24 client and real official SDK journey passed |
| Runtime reviewer | Native setup/isolation | Environment blocked | Configured policy allows wildcard bind/listen; fail-closed before services, no repeated unchanged setup |
| UI | Input and MOCK/local regressions | Verified except saved selection |d6:8 MOCK+16 local passes;6a:remaining XXXL local case passes; three AutoFill-On functional cases pass |
| Root | Native saved selection | Unresolved, failed |9a507fe run36525193498 failed saved selection (0/1;0 skips; Release passed) after native Save and Passwords tap. Dynamic identity discovery did not resolve it; no personal-account requirement was observed |

Source-bound results, original failures and remaining limits: [status](../../NATIVE_REVIEW_STATUS.md), [coverage](COVERAGE.md), [attempt history](attempt-history.json), [next step](../../NEXT_REVIEW.md). No specialist may merge or independently publish.
