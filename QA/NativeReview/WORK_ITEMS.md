# Integration review work items

Base: PR3 `180d9650b88e90b604d6837b5f2eea78ee83257d`, dependent on open PR2. Follow-up PR4 uses `codex/native-integration-review`. No merge authorized; v06 and prior deliveries preserved.

| Owner | Scope | State | Evidence / remaining gate |
|---|---|---|---|
| Root | Client review, workflows, evidence and delivery | Review | Nine backend/client findings fixed and tested; source package waits for latest UI outcomes |
| Backend | Auth/domain/RLS, restore, regressions | Verified |031 backend55, reference45, QA14, client24 and actual SDK journey passed |
| Runtime reviewer | Native Mac bootstrap and isolation | Environment blocked | Wildcard IPv4/IPv6 listen allowed by configured policy; no unchanged setup retry; real UI/backend not executed |
| UI | AutoFill, MOCK journeys, native script preparation | Verification |031 three functional AutoFill passes; integration7/8 and local-b7/8; candidate d6f65ec under test |

Candidate d6f65ec runs: AutoFill36519447212 and all UI shards36519447184, attempt1. It adds actual saved selection, stable scroll query and verified initial Sara-only recipient state. No product change after031 and no weakened assertions. Earlier failing artifacts stay in attempt-history.json. Root owns final reconciliation and merge recommendation; agents do not publish independently.

[Current status](../../NATIVE_REVIEW_STATUS.md) · [Coverage](COVERAGE.md) · [Exact next step](../../NEXT_REVIEW.md).

Compiler checkpoint:05ab0f failed UI-test compilation before execution (optional application inferred inside an array); Release passed. Candidate d6f65ec guards the nonoptional application without changing assertions. Original reports are in evidence/compile-05ab0f and attempt-history.json. This is a test-source failure, not a runtime environment failure.
