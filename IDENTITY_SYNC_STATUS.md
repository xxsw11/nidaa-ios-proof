# Identity, consent and synchronization stage

Review date: 2026-09-28. Base: `a1ffbec01bd7cc39409bbd740639606fe2f29e39` on freshly inspected main. Branch: `codex/identity-consent-sync-design`. **Review only; do not merge automatically.**

Delivered design: [decisions/data model/permissions/state diagrams](Docs/IdentitySync/DESIGN.md), [API contract](Docs/IdentitySync/API.md), [official-source provider comparison](Docs/IdentitySync/PROVIDERS.md), [isolated reference model](SharedRules/README.md).

Recommendation: local Supabase Auth + PostgreSQL trial behind a transactional command boundary, with fake email/push adapters and no connection to the existing application yet. Provider selection remains revisable after local transaction/RLS/revocation tests.

## Actual final evidence

The tested reference/CI commit is `bcc5dceb4c576da91eefc55abf3e26ad026326b2`. [Cloud run 36387113684](https://github.com/xxsw11/nidaa-ios-proof/actions/runs/36387113684) passed on macOS-15: **45 reference/contract tests, 13 existing Python tests and 45 existing Swift core tests**, zero failures. Windows also passed 45 + 13 Python tests. Logs and machine-readable results are in [QA/IdentitySync](QA/IdentitySync/); see the [coverage and limitations](QA/IdentitySync/REVIEW.md).

The initial cloud run on `ce183b8ba8d509b0eabda67acc33653146ff649f` also passed 43 + 13 + 45 tests. Final review added consumed-token erasure and stale account-generation callback tests; the later run above is authoritative for final code. Any subsequent delivery commit is restricted to documentation/evidence; no further code changes are claimed as tested without rerunning.

[PR #2](https://github.com/xxsw11/nidaa-ios-proof/pull/2) is open for review and **not merged**. The branch does not enable automatic merge. No provider integration is enabled.

All 54 pre-existing files under App, ProofCore, Config, Xcode project, Scripts, UITests, QA and the native CI workflow match baseline content. Windows checkout newline conversions are recorded separately; source packages preserve the original repository bytes for unchanged files. The existing 17 UI tests and simulator Debug/Release build evidence remain the prior stage's results; they were not rerun for this isolated, non-UI design change. Historical v06/v03 archive SHA-256 hashes are unchanged.

## Proven boundaries and remaining work

The reference validates operation schemas and simulates directional consent, target-bound invitations, authorization, duplicate operations/events, offline uncertainty, expiry, response conflicts, queue rechecks, deletion and account isolation. It does not implement production authentication or prove actual communication between devices.

No real email/SMS/APNs, external provider account, deployment, purchase or physical-device test occurred. Physical iPhone notification reception is deferred because no Apple devices are available; this does not block this design stage. Sound, silent/Focus bypass and Critical Alerts remain unproven.

Database transactions/RLS, real session revocation, distributed abuse resistance, storage encryption, immutable backups and restore/deletion handling still require the isolated integration trial described in [NEXT_REVIEW.md](NEXT_REVIEW.md).
