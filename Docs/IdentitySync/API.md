# Shared API v1 contract — proposed, not deployed

The machine-checkable boundary is [`SharedRules/contract.schema.json`](../../SharedRules/contract.schema.json), generated deterministically by `build_contract.py`. Owners: future Swift networking adapter (consumer), shared command service (producer), fixture reference adapter (test implementation). The existing SwiftUI app is not a consumer yet. A JSON Schema contract was chosen instead of hand-maintained duplicate OpenAPI request definitions; the following HTTP mapping is normative for the next trial. No real endpoints are running.

## Transport and authentication

HTTPS JSON only; maximum body 16 KiB. All routes require a provider-authenticated, verified-email account and live revocation-checked session. The trusted adapter resolves the user and bound device; client body fields cannot supply an actor, recipient identity for a response, device owner, auth time or biometric proof. Do not accept unsigned JWT decoding as validation. `Authorization` and cookies must never reach application logs. Responses containing account data use `Cache-Control: no-store`.

Provider registration, email verification, login, recovery and refresh use the established provider SDK, not a new NIDAA password API. The account/session lifecycle is in [DESIGN](DESIGN.md). A later local trial must implement the adapter, not expose `fixture_account` or `fixture_session` over HTTP. Device registration for APNs is deferred and has no enabled endpoint in v1.

| Method / route | Request contract | Response / reference entry point |
|---|---|---|
| POST `/v1/commands` | `$defs.Command` | `$defs.Receipt`; `Server.execute` |
| GET `/v1/operations/{operation_id}` | UUID path; actor from session | `$defs.Receipt`; `Server.receipt` |
| GET `/v1/alerts/{alert_id}` | UUID path; participant from session | `$defs.Alert`; `Server.view` |
| GET `/v1/sync` | None; initial trial uses complete account snapshot | `$defs.Sync`; `Server.sync` |
| GET `/v1/me` | None | `$defs.Account`; `Server.account` |
| GET `/v1/relationships` | None | `$defs.Relationships`; `Server.relationships` |
| POST `/v1/session/logout` | Empty JSON object | 204; adapter revokes current provider/domain session and device binding; `Server.revoke_session(..., false)` models domain result |
| POST `/v1/session/revoke-all` | Empty JSON object, provider recent reauth required in real adapter | 204; domain barrier + provider revoke-all; `Server.revoke_session(..., true)` models domain result only |

Logout/revoke-all are control-plane adapter responsibilities, not alert command receipts. Retried logout for a revoked session must be safe and return a generic outcome, without re-enabling a session. Recent-auth enforcement on revoke-all is specified for the real adapter; fixture helper does not implement provider reauthentication.

## Command envelope

Every command has exactly four required fields: `operation_id` UUID, `issued_at` integer UTC seconds, `command` enum discriminator, and `payload` object. No undocumented properties; none of these is nullable. The first attempt must arrive within 60 seconds of `issued_at`, not in the future. An existing exact receipt can be fetched/replayed later while the account/session remains authorized. Client clock skew is an explicit error: fetch server time from an authenticated response, review intent and reconfirm; never silently adjust an uncertain submitted command. Production should use a server-issued freshness challenge if stronger tamper resistance is required.

| Command | Required payload | Rule |
|---|---|---|
| invite | recipient_email | Target-bound, generic issuance, 24-hour lifetime |
| decide_invite | token, decision accepted/declined | Intended verified target; recent provider auth; token single use |
| cancel_invite | invitation_id | Inviter; pending only |
| withdraw | sender_id | Actor withdraws sender → actor grant |
| block / unblock | user_id | Known participant; unblock grants nothing |
| create_alert | recipient_ids, expires_at | 1–5 distinct UUIDs with current consent; 0–900 seconds ahead |
| retry | alert_id, expected_version | Sender; unanswered eligible recipients; one extra attempt max |
| add_recipients | alert_id, expected_version, recipient_ids | Sender; atomic current grants; total ≤5; fixed original expiry |
| respond | alert_id, expected_version, response responding/declined | Actor is recipient; first valid response wins |
| acknowledge | alert_id, event_id, kind app_acknowledged/opened | Bound session device; same event cannot change semantics |
| close_alert | alert_id, expected_version, state cancelled/resolved | Sender only; active only |
| hide_history | alert_id | Own terminal history; no global deletion |
| delete_account | empty object | Own account; provider auth ≤5 minutes |

`expected_version` uses the alert's domain version, not a device clock. Ack events do not advance that version; they advance synchronization sequence only. An unrelated recipient response can make a sender/recipient version stale; fetch and explicitly reconcile the view. The final response for a recipient remains immutable even with the latest version. No patch endpoint bypasses these guards.

## Receipts and errors

A command returning HTTP 200 has a durable `Receipt`, with required fields `operation_id`, `status` accepted/rejected, `resource_id` UUID or null, `error` enum or null, `server_time`, `invitation_token` string or null. Acceptance means **server state mutation recorded**, never provider delivery. `resource_id` may be null for successful grant/block changes. The invitation token appears only for private issuance/replay while usable; other results use null. Tokens are not part of sync, alert or relationship views.

Rejected domain commands also return 200 + durable rejected receipt, enabling deterministic operation lookup. Envelope/auth/rate-gate/idempotency conflicts before execution return the strict `$defs.Error` shape `{ "error": "..." }`. A lost connection or 5xx without a receipt leaves outcome unknown. Infrastructure errors are not evidence that nothing happened.

| HTTP transport error | Error enum | Meaning / caller action |
|---|---|---|
| 400 | invalid_request | Schema/format/unknown field; fix locally, no automatic mutation |
| 401 | unauthenticated | Missing, expired, revoked or unverified session; authenticate |
| 404 | not_found | Missing or unauthorized resource; generic response; operation lookup is actor-scoped |
| 409 | conflict | Same op ID different envelope; never overwrite/reassign it |
| 410 | expired | Envelope outside first-attempt freshness window |
| 429 | rate_limited | Back off; do not make new IDs to bypass limits |

Domain receipt errors additionally include `forbidden`, `consent_required`, `terminal`, `limit_reached`, `reauthentication_required`. No response exposes email existence, database messages, token values or another account's record. Actual HTTP middleware/status mapping is deferred; tests call the reference boundary directly.

Operation deduplication is per account across devices, not per session. Use a canonical digest of the entire immutable envelope. The sender retries a **query**, not a new alert. Old receipts describe the original acceptance, so read current alert state as well. A terminal alert must never be reopened from an old accepted receipt.

## Views and synchronization

`Alert` separates state/version/deadline/closure and recipient facts. Sender sees their recipients; a recipient sees only their own row plus sender ID. Permission loss is returned generically as `access: unavailable` to the sender; affected recipients lose the alert view. `provider_accepted` is a simulated fact in this reference; `app_acknowledged`, `opened` and `response` are independent observations. There is no field named `delivered`, `audible` or `safe`.

`Sync` includes `cursor`, `full_snapshot: true`, `alerts`, `removed_ids`. Empty arrays are valid. Apply only to the matching account generation and only if newer. Replace the account cache atomically; absence and removals delete old detail. The reference cursor is process-global for deterministic tests; a real implementation must issue account-scoped cursors and bounded snapshots, plus full-reset handling after retention. Pagination/delta feeds are deliberately deferred until the local two-account trial sizes the problem. Do not silently interpret this full snapshot as a partial page.

`Relationships` lists only outgoing or intended incoming invitations and participant grants, with no bearer token, token digest or email. Internal invitation/grant states distinguish blocking and withdrawal; outgoing views redact those reasons to `unavailable`. Terminal invitation state does not establish a reverse grant. `Account` returns only the current user's UUID, display name and verified-email flag; no account search endpoint exists.

## Compatibility and conformance

Version is `/v1`, schema ID `urn:nidaa:shared-rules:v1`. Enum additions, required fields, nullability or semantics changes require coordinated contract revision and consumer tests; unknown fields fail closed. The fixture reference is the only adapter tested in this stage. Swift Codable types and provider transaction adapters must be derived/reviewed against this contract in the next stage. Runtime tests validate actual successful, rejected, empty and unauthorized results; no remote schema references or production credentials are used.

Not yet proven: real HTTP middleware, schema body-size enforcement, provider token verification, RLS, SQL transaction races, distributed abuse controls, encryption at rest, device token registration, APNs dispatch, backup restore or real-device behavior. These must not be inferred from schema/reference tests.
