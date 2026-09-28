# Identity/consent stage — actual coverage and limits

Reviewed 2026-09-28. Final code `bcc5dceb4c576da91eefc55abf3e26ad026326b2`; [successful cloud run](https://github.com/xxsw11/nidaa-ios-proof/actions/runs/36387113684). PR #2 stays open, unmerged.

| Check | Actual result | Evidence |
|---|---|---|
| Isolated reference + runtime JSON Schema | Passed: 45 tests, Windows and macOS | windows-shared-rules.log, cloud-job.log |
| Existing Python checks | Passed: 13 tests, Windows and macOS | windows-existing-python.log, cloud-job.log |
| Existing Swift core suite | Passed: 45 tests, macOS cloud | cloud-job.log |
| Native/source preservation | Passed: 54 pre-existing files match baseline content; repository bytes preserved in package | preservation-and-local-results.json |
| Historical v06/v03 archives | Passed: both SHA-256 match recorded prior stage | preservation-and-local-results.json |
| Existing SwiftUI/UI tests, Debug/Release | Not rerun in this stage; no app/UI/core changes | Prior run 36381069313 remains historical evidence |
| Real authentication/provider integration | Not tested; fixture sessions only | Explicit next-stage gate |
| HTTP middleware, SQL/RLS, distributed races | Not tested; serialized in-process model | Explicit next-stage gate |
| Physical iPhone/APNs/sound/Critical Alerts | Not tested; deferred because no Apple devices | No delivery claim |

## Scenario coverage

Tests in `SharedRules/tests/test_rules.py` are executable rule simulations, not real communication among accounts/devices.

| Concern | Representative tested behavior |
|---|---|
| Identity | Same display name grants nothing; unverified session rejected; body actor/Face ID fields rejected |
| Invitation | Intended email binding, sender self-accept forbidden, expiry boundary, replay, decline/cancel, account rate limits, recent auth |
| Directional consent | A → B never grants B → A; revoke before mutation rejects; revoke/block after acceptance suppresses queued handoff |
| Handoff race | Provider handoff before block remains an acceptance fact; no app/open/response inferred; block-first suppresses |
| Idempotency | Lost reply queried under same op ID, duplicate creates only one alert/job, mismatched payload conflicts, lookup actor-scoped |
| Offline | Never-left vs unknown distinguishable, reconnect does not send, stale envelope rejected |
| Permissions | Unrelated C cannot read/respond/ack/close; sender cannot forge response; recipient cannot globally resolve |
| Two B devices | First response wins, including concurrent threads; stale/opposite response rejected; device acknowledgements deduplicated and aggregated |
| Event correctness | Event ID cannot be reused with a different meaning; opening does not imply human response; response does not resolve |
| Limits/expiry | Fixed expiry, no late resurrection, retry cap/cooldown, exclude responders/decliners, atomic recipient addition/create |
| Privacy | Recipients see only their row; sender sees generic permission loss; C sees no relationships after unrelated deletion |
| Account lifecycle | One/all-session revocation, all-device account deletion, sender cancellation, no pending handoff, no profile email left |
| Replica isolation | Different-owner and previous-login-generation callbacks rejected, out-of-order snapshots cannot reopen terminal state |
| Retention/secrets | 30-day detail purge and read cutoff, old original envelope cannot resend after receipt expiry, used/expired invitation tokens erased |

## Review corrections included before final cloud run

Review found that deletion must not manufacture relationship rows with unrelated accounts; the model now restricts only known pairs and tests C's view. It also enforces retention on reads before the sweeper, rejects conflicting acknowledgement event reuse, erases consumed invitation tokens, and rejects callbacks from a previous login even when the account ID is the same. These changes are covered by the final 45-test suite.

## Explicit limits

The lock and rollback snapshot model transaction ordering, not real database serializability. Account throttling is implemented; target/IP/distributed controls are specified but not implemented. Production auth, email canonicalization, session refresh, provider deletion retries, HTTP limits, encryption, backups, restore/delete replay, per-account cursors and paginated sync are future adapter work. Fixture timestamps, IDs and `.invalid` addresses are test data.

The contract is generated locally and compared for drift; actual commands, receipts, account/relationship views, alerts, errors and empty/full sync results are schema-validated. No remote schema references or external service calls occur during test execution. Test dependency installation uses pinned packages; no dependencies were added to the iOS app.
