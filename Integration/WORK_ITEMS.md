# Integration work ownership

| Item | Owner | Scope | State | Gate |
|---|---|---|---|---|
| Runtime, gateway, CI, delivery | Root | Integration infrastructure, workflows, project wiring, docs | Review | 47 real backend + live Swift journey; all 25 native UI and Debug/Release passed |
| PostgreSQL domain/API | Backend agent | Integration/service, Integration/migrations | Review | 47 actual integration tests passed at 528b953; no PR merge |
| Independent integration tests | Test agent | Integration/tests | Review | 47 passed including permission and UUID regressions |
| Official Swift Auth and network adapter | Backend agent | IntegrationClient package and library sources | Review | Real Swift HTTP journey + 19 unit tests passed at 528b953 |
| Client tests and live Swift trial | Test agent | IntegrationClient tests and IntegrationTrialCLI sources | Review | Live A/B/C/B2 journey passed via actual local inbox; no admin credentials in client |
| Arabic SwiftUI integration screens | UI agent | App/Integration, minimal routing/settings, new UITests | Review | 8 new mock UI journeys passed; Arabic/RTL/large-text screenshots inspected; default experience preserved |

One writer per scope. Root integrates and reviews changes, but does not merge either PR. Handoffs are Integration/BACKEND_HANDOFF.md and TEST_HANDOFF.md. No shared skill extraction is warranted for this one trial.
