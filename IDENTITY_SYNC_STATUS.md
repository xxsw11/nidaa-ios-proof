# Identity, consent and synchronization stage

Review date: 2026-09-28. Base: `a1ffbec01bd7cc39409bbd740639606fe2f29e39` on freshly inspected main. Branch: `codex/identity-consent-sync-design`. **Review only; do not merge automatically.**

Delivered design: [decisions/data model/permissions/state diagrams](Docs/IdentitySync/DESIGN.md), [API contract](Docs/IdentitySync/API.md), [official-source provider comparison](Docs/IdentitySync/PROVIDERS.md), [isolated reference model](SharedRules/README.md).

Recommendation: local Supabase Auth + PostgreSQL trial behind a transactional command boundary, with fake email/push adapters and no connection to the existing application yet. Provider selection remains revisable after local transaction/RLS/revocation tests.

## Evidence at preparation

Windows: 40 reference/contract tests and 13 existing Python tests passed before the final review additions. The cloud check will rerun the full reference suite and the existing 45 Swift core tests; final results will be recorded here before delivery. No cloud success is claimed by this preparation entry.

Existing application source, Swift core, UI tests, configuration and local persistence are preserved. The existing 17 UI tests and simulator Debug/Release build evidence remain the prior stage's results, not new network validation. Historical v06/v03 packages are unchanged.

## Proven boundaries and remaining work

The reference validates operation schemas and simulates directional consent, target-bound invitations, authorization, duplicate operations/events, offline uncertainty, expiry, response conflicts, queue rechecks, deletion and account isolation. It does not implement production authentication or prove actual communication between devices.

No real email/SMS/APNs, external provider account, deployment, purchase or physical-device test occurred. Physical iPhone notification reception is deferred because no Apple devices are available; this does not block this design stage. Sound, silent/Focus bypass and Critical Alerts remain unproven.

Database transactions/RLS, real session revocation, distributed abuse resistance, storage encryption, immutable backups and restore/deletion handling still require the isolated integration trial described in [NEXT_REVIEW.md](NEXT_REVIEW.md).
