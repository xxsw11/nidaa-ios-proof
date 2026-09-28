# Integration work ownership

| Item | Owner | Scope | State | Gate |
|---|---|---|---|---|
| Runtime, gateway, CI, delivery | Root | Integration infrastructure, workflows, docs | Running | Isolation/health and actual CI evidence |
| PostgreSQL domain/API | Backend agent | Integration/service, Integration/migrations | Running | Real auth + DB/HTTP/race tests |
| Independent integration tests | Test agent | Integration/tests | Running | Actual identities, denial/failure/concurrency/restore coverage |
| SwiftUI adapter and views | Unassigned until backend green | Separate integration mode; preserve local experience | Backlog | Backend pass first, then client/UI/Debug/Release evidence |

One writer per scope. Root integrates and reviews changes, but does not merge either PR. Handoffs are Integration/BACKEND_HANDOFF.md and TEST_HANDOFF.md. No shared skill extraction is warranted for this one trial.
