# Integration work ownership

| Item | Owner | Scope | State | Gate |
|---|---|---|---|---|
| Runtime, gateway, CI, delivery | Root | Integration infrastructure, workflows, project wiring, docs | Running | Isolation/health passed run 36425227273; client/UI evidence next |
| PostgreSQL domain/API | Backend agent | Integration/service, Integration/migrations | Review | 45 actual integration tests passed; no PR merge |
| Independent integration tests | Test agent | Integration/tests | Review | 45 passed; added permission regression pending next CI |
| Official Swift Auth and network adapter | Backend agent | IntegrationClient package and library sources | Running | Backend gate passed first; real Swift HTTP journey + unit tests |
| Client tests and live Swift trial | Test agent | IntegrationClient tests and IntegrationTrialCLI sources | Running | Auth through actual local inbox; no admin credentials in client |
| Arabic SwiftUI integration screens | UI agent | App/Integration, minimal routing/settings, new UITests | Running | Separate integration mode; mock UI labeled; Debug/Release + RTL screenshots |

One writer per scope. Root integrates and reviews changes, but does not merge either PR. Handoffs are Integration/BACKEND_HANDOFF.md and TEST_HANDOFF.md. No shared skill extraction is warranted for this one trial.
