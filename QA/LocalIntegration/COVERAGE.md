# Integration evidence map

This file maps requirements to executable checks. Actual outcomes, tested commits and run links are recorded in `LOCAL_INTEGRATION_STATUS.md`; a test's presence alone does not establish a pass.

| Requirement | Evidence path | Boundary |
|---|---|---|
| Verified fictional A/B/C and independent B sessions | `Integration/tests/harness.py`, `test_smoke.py`, `test_integration.py` | Actual GoTrue signup, local Mailpit message, verification and HTTP login; no admin verification bypass |
| Password recovery, refresh, invalid/expired/revoked sessions, disabling/deletion | `test_integration.py` AuthenticationIntegration and worker cleanup tests | Actual provider HTTP journeys plus explicitly named signed-token/aging/admin negative fixtures |
| Directional invitation/consent and C denial | Backend integration tests; Swift `IntegrationTrialCLI` | Server verifies identity; invitation creation never grants consent |
| RLS and provider credential isolation | Backend role-policy and service-column tests | Actual PostgreSQL roles/connections; service cannot read password or refresh-token columns |
| Duplicate/conflicting operations, lost response | Backend idempotency tests and test-only drop-after-commit HTTP proxy | Response really lost after upstream commit; same receipt retrieved; no production fault endpoint |
| Transaction rollback and concurrent responses/revocation | Backend tests with independent HTTP clients/connections | Serialized PostgreSQL decisions; production throughput unproven |
| Worker crash/restart/deduplication and last-moment authorization | `test_workers.py` subprocess tests | Fake sink is in the same database transaction; no external exactly-once guarantee |
| Expiry, retry limits and original deadlines | Backend integration/worker tests | Fixture clock aging is explicit; actual request/worker validation |
| Retention, synchronization removal/cursors and backup restore | Backend retention tests, isolated pg_dump/pg_restore and separately newer ledger replay | No HTTP client can reach restore database before replay; no production backup SLA claim |
| Official Swift client against real backend | `IntegrationClient/Sources/IntegrationTrialCLI` | Real HTTP/Auth/database journey on isolated Linux; memory storage only in this test process |
| Pending unknown/never-sent, account/environment generation isolation, strict newer snapshots | 19 `NidaaIntegrationTests` | Injected HTTP/storage/clock tests; these are mocks, separately labeled |
| Arabic screens, consent, fresh local auth + confirmation, unknown lookup and logout | 8 `IntegrationUITests` plus 17 existing UI journeys | Debug Simulator mock; neither hardware biometrics nor native backend end-to-end |
| Arabic RTL and accessibility text | Original XCTest attachment exports and visual review | Screen images from the tested Simulator run; no fabricated preview |
| Existing behavior | 45 reference Python, 13 existing Python, 45 ProofCore Swift tests | Regression evidence separate from real integration |

No real device, external email, APNs notification, sound, Critical Alerts approval or public backend is exercised. New account data is fictional; historical simulation data is never uploaded automatically. Runtime env files, databases, backup dumps, mailboxes, verification/invitation tokens and raw secrets are excluded from delivery.
