# Integration review and native verification

Base: PR #3 `180d9650b88e90b604d6837b5f2eea78ee83257d`, still depends on open PR #2. Branch `codex/native-integration-review`; no merge authorized. Prior working directories and deliveries are preserved.

| Owner | Scope | State | Acceptance gate |
|---|---|---|---|
| Root | Swift client review, workflow/project wiring, evidence and delivery | Running | Reviewed changes, actual cloud results, exact-source package, merge recommendation |
| Backend | Domain/Auth/RLS review; Integration/service, migrations and backend regression tests | Ready | Reproducible findings and fixes with real backend regression evidence |
| Runtime reviewer | Native macOS backend bootstrap in Integration/native; environment capability evidence | Ready | Real Auth/PostgreSQL/local inbox on loopback, fail closed isolation, bounded setup, no mocked backend |
| UI | App/Integration, AutoFill and real native UI test journeys | Ready | AutoFill actual enabled, secure manual/paste/navigation/visibility behavior, real UI journey when runtime available, original screenshots |

One writer per file scope; coordinate cross-scope changes with root. Do not merge/publish independently. Review historical failures before reruns; preserve failing evidence. No production deployment, paid services, external SMTP/APNs or physical-device claims.
