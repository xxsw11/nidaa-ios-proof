# Integration test implementation handoff

These tests require the isolated container stack. They are not mock HTTP/database tests. This document describes coverage; a passing result must come from the recorded CI run, not this file or Python compilation.

Run inside the test container at repository root:

```text
python -m unittest discover -s Integration/tests -p 'test_*.py' -v
```

The small bring-up suite is `test_smoke.py`. `harness.py` creates randomized fictional Sami/Sara/Noor addresses under `example.invalid`, signs up through real GoTrue, requires signup to return no session, reads verification email from local Mailpit and verifies through the configured local Auth endpoint. It deliberately does not follow emailed URLs. It then logs in with the provider password flow. B's second client has a separate HTTP connection, provider session and derived device binding. No administrative user creation or email-confirmation bypass is used in these journeys.

Required test dependencies: httpx, psycopg, PyJWT plus the service dependencies; PostgreSQL client tools matching the server major version. Test environment supplies local `BASE_URL`, `AUTH_URL`, `MAIL_URL`, `DATABASE_ADMIN_URL`, `DATABASE_URL`, `JWT_SECRET`, `RECEIPT_KEY`, and `AUTH_ADMIN_TOKEN`. Never upload that environment or container logs containing provider mail links/tokens. Assertion messages deliberately omit response bodies, SQL parameters, credentials and email links. Database tools and workers capture output privately and report only generic failure codes.

## What is exercised

- Real signup, verification, login, refresh, local recovery email/password change, current/all-session logout, provider session removal, provider/domain disabling and account deletion with asynchronous real GoTrue Admin API cleanup.
- A-to-B invitation/explicit consent and alert flow; B cannot send in reverse without separate consent. C cannot accept B's real invitation token, access an alert or another actor's operation receipt, forge a response or write tables directly.
- Duplicate operation IDs/payload conflicts with concurrent independent HTTP clients. A test-only HTTP proxy binds an ephemeral loopback port, forwards one create request, waits for upstream acceptance after the transaction commits, then closes its downstream socket without returning headers or body. The caller observes a real HTTP protocol failure and reconciles the original operation ID; exactly one alert and outbox job exist. No production fault endpoint is added.
- Conflicting B responses with two sessions, per-device acknowledgements, duplicate event semantics, sender versus recipient authority, invitation expiry/replay/cancellation, strict fields/body size, guessing/issuance/target-cooling limits.
- Concurrent send/withdraw, block/worker and delete/worker races on independent connections/processes; complete multi-recipient rejection rollback with a durable rejected operation receipt.
- Separate worker processes crash before commit and after commit, restart and race duplicate jobs. **The fake delivery acceptance ledger is in PostgreSQL in the same transaction.** Exactly-once effects here concern this local fake adapter only; no result proves external-system/APNs exactly-once delivery or resolves a real provider timeout.
- Responders/decliners excluded from retry, retry cooldown/attempt bound, unchanged deadlines, worker expiry recheck, late-event rejection, personal history hiding and 30-day read-time/sweeper retention.
- Account-scoped synchronization cursors, acknowledgement cursor progression, complete snapshot removal and no unrelated-account cursor movement on deletion.
- A real `pg_dump` before deletion/withdrawal/blocking is restored to a unique temporary database. A separately exported **later deletion and revocation ledger** is applied twice before any account access is attempted. The deleted account's old session is rejected, account details erased and pending jobs suppressed. Other participants' withdrawal and blocking remain effective, with old detail access and consent denied. No HTTP service is connected to the restore database. Temporary backup/ledger files and that exact test database are removed; no other databases are reset.

## Deliberate test controls and limitations

Administrator SQL is used only for inspection and explicit fixture controls: aging deadlines/retention/cooldown, disabling an account and probing direct authenticated-role RLS. User journeys use real authenticated HTTP requests. A signed-token negative fixture changes AMR/iat/expiry to exercise validation; this is distinct from the real provider refresh test, which proves the provider preserves its authentication evidence. No client-supplied timestamp or biometric Boolean is accepted as authentication.

The backend trial uses a global PostgreSQL advisory transaction lock. Races prove serialized database behavior, not production throughput or distributed lock correctness. Invitation targets/third-party identifiers are test fixtures rather than address-book discovery. Backup replay demonstrates this specific isolated restore procedure; it does not establish production backup encryption, deletion SLA or immutable-backup expiry guarantees. SwiftUI/offline client behavior, Keychain and Simulator coverage require their separate client tests and are not inferred from these backend tests.
