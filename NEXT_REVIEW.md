# Next review — isolated two-account integration trial

Updated 2026-09-28. Identity/consent/synchronization design is proposed on `codex/identity-consent-sync-design`. **Review its new PR; do not merge automatically.** Prior stabilization was merged at `a1ffbec01bd7cc39409bbd740639606fe2f29e39`; preserve its application behavior and historical evidence.

The exact next step after review is a separate **local Supabase CLI + PostgreSQL/Auth integration harness**, with fake email and fake notification handoff. Check container availability and loopback port bindings first. No hosted project, production keys, paid plan or real email/push is needed or authorized by this plan. The current stage stops at design, reference tests and recommendation.

1. Review [decisions](Docs/IdentitySync/DESIGN.md), [API](Docs/IdentitySync/API.md) and [comparison](Docs/IdentitySync/PROVIDERS.md). Resolve provisional TTL/retry/recovery/retention/jurisdiction choices; accept or revise the contract before adapters.
2. On a new branch, pin local provider versions and bind to loopback. Route authentication email exclusively into a local capture sink; disable external email/APNs egress. Use fictional A/Sami, B/Sara, C/Noor and two B sessions.
3. Implement SQL schema, deny-by-default RLS and scoped command functions/API against the canonical schema. Map verified provider subjects to immutable UUIDs. Validate email verification, auth time and revocation on every read/mutation; keep administrative secrets in the local server environment.
4. Implement database operation receipts and a transactional outbox. Race withdrawal/block/deletion against command execution and worker authorization using separate database connections. Test rollback, duplicate operations, provider-timeout uncertainty, immutable deadlines, two-device conflicting responses and all unauthorized C paths.
5. Replace fixture auth with the local provider adapter. Test registration, verification, recovery, logout, revoke-all, email change and deletion. A client boolean never satisfies server reauthentication. Delayed provider cleanup must not bypass immediate domain revocation.
6. Connect two isolated script clients first; add a Simulator Swift adapter only after contract conformance. Prove account cache separation, lost-response lookup, no automatic reconnect dispatch, full-reset sync and deletion tombstones. Preserve the current demonstration UI until these pass.
7. Implement retention sweeps, log redaction, secret storage and a restore drill with deletion-ledger replay. Test target/IP invitation abuse limits and 16 KiB body limits. Document local-stack limitations.
8. Run existing Python/Swift tests, plus relevant UI tests when an application adapter is added. Open a review PR with actual logs; keep external services disabled.

Acceptance gate: two test participants authenticate through the local provider and deliberately accept a directional invitation; C cannot access/mutate their data; shared transaction/synchronization rules pass over real local HTTP/database boundaries. This is still not proof of APNs delivery or physical-device behavior.

Deferred: hosted provider/region, cost approval, production email, APNs credentials, a physical iPhone and testing window, Critical Alerts approval. No Apple devices are available; physical reception remains deferred without blocking local design/integration. Obtain specific device/window authorization before physical-phone notifications or audio. Never request secret keys or passwords in conversation.
