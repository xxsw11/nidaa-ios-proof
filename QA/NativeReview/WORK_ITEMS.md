# Integration review and native verification

Base: PR #3 `180d9650b88e90b604d6837b5f2eea78ee83257d`, still depends on open PR #2. Branch `codex/native-integration-review`; no merge authorized. Prior working directories and deliveries are preserved.

| Owner | Scope | State | Acceptance gate |
|---|---|---|---|
| Root | Swift client review, workflow/project wiring, evidence and delivery | Running | Reviewed changes, actual cloud results, exact-source package, merge recommendation |
| Backend | Domain/Auth/RLS review; Integration/service, migrations and backend regression tests | Verified at 966f80a and ea63b0f — 55 backend, 45 reference, 13 QA, 24 client tests and live SDK journey | Reproducible findings and fixes with real backend regression evidence |
| Runtime reviewer | Native macOS backend bootstrap in Integration/native; environment capability evidence | Blocked by observed wildcard-bind isolation failure; no repeat | Real Auth/PostgreSQL/local inbox on loopback, fail closed isolation, bounded setup, no mocked backend |
| UI | App/Integration, AutoFill and real native UI test journeys | Unresolved at 3759: 2 AutoFill failures, 1 pass, 1 skip; MOCK integration 0/8 passed; aff2323 same failures with short native draft before Done;031 step-isolation candidate running; both previous Release builds passed | AutoFill actual enabled, secure manual/paste/navigation/visibility behavior, real UI journey when runtime available, original screenshots |

One writer per file scope; coordinate cross-scope changes with root. Do not merge/publish independently. Review historical failures before reruns; preserve failing evidence. No production deployment, paid services, external SMTP/APNs or physical-device claims.

Evidence limits: the existing local UI baseline passed 9 + 8 tests with Debug/Release builds at `966f80a`. Native UI/backend E2E was **Not executed** at `ea63b0f`: the isolation probe failed before services; no unchanged environment retry is planned. Passing backend/client or historical local UI results do not close current AutoFill/MOCK UI failures or validate subsequent fixes. See [coverage and gaps](COVERAGE.md); root maintains exact run/attempt provenance and final delivery status.

Current cloud checkpoints:031ffd5 AutoFill run36516431533; integration/local-b run36516431563; backend run36516431478. Standalone policy diagnosis run36516431643 observed allowed wildcard listen, distinct from unexecuted native backend. Local-b deletion assertion publication/persistence regression added after3759 single failure; results pending.
