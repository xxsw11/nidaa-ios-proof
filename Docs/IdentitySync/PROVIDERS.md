# Provider comparison and recommendation

Official-source review: **2026-09-28**. Prices in USD, excluding tax; plan terms, regional prices and quotas can change. No account was created, product purchased or provider connected. The following is an engineering recommendation for a local trial, not a promise of availability for emergencies.

## Recommendation

Use **Supabase Auth + PostgreSQL behind a narrow transactional command service** for the next isolated local trial. Keep authentication, database and notification adapters replaceable. Use the Swift SDK for established authentication, not unrestricted direct client writes to shared alert/grant tables. RLS is defense in depth; the command service owns consent checks, versions, operation receipts and outbox transactions. PostgreSQL's relational constraints fit directional grants and multi-recipient atomic actions. This is an inference from the requirements and provider capabilities, not a benchmark result.

Keep the current local SwiftUI experience untouched until that trial proves the shared rules. First run a local stack, fake mail sink and fake notification worker; no hosted service is needed for that gate. Supabase local development requires its CLI and a Docker-compatible runtime. Bind services to loopback; do not expose the local stack publicly. [Official local setup](https://supabase.com/docs/guides/local-development).

Firebase remains credible if its operational tooling is preferred, but NIDAA must bypass automatic offline mutation behavior for urgent commands. A custom backend provides more deployment control at materially greater security and operational responsibility.

## Engineering comparison

| Topic | Supabase | Firebase | Simple custom backend |
|---|---|---|---|
| Swift and auth | Official Swift client; established email OTP/magic links, confirmed email, session refresh | Official Apple SDK; verified email-link authentication | Swift URLSession for API; established OIDC client such as AppAuth, hosted identity provider or Keycloak |
| Authorization | PostgreSQL RLS plus privileged, scoped transaction endpoints; never ship service-role key | Security Rules for client access; server IAM/admin SDK bypasses Rules, so command service independently authorizes | Implement endpoint authorization and SQL policies; no automatic safety from using OIDC |
| Transactions | Relational constraints, unique operation keys and SQL transactions | Firestore atomic transactions; callbacks may retry, so no provider send inside callback | PostgreSQL transactions and transactional outbox; operator owns retries/migrations |
| Sync | Realtime can signal invalidation; fetch authoritative account views; explicit offline policy | Realtime listeners and native offline cache; automatic write synchronization/last-write-wins conflicts with this alert policy | Build authenticated polling/change feed; most work but precise control |
| Local tests | CLI/container stack for Auth/Postgres/RLS/Functions; next stage, not run here | Emulator Suite for Auth/Firestore/Functions/Rules; emulator coverage differs from hosted services | Containers for Postgres/Keycloak/API plus fake mail/push; operator assembles harness |
| Data location | Choose specific primary project region; review Auth/logs/backups/subprocessors too | Configure each product's region separately; Firestore region is not all-project residency | Choose infrastructure region and backup destinations; residency still requires operator/vendor review |
| Backups | Free requires own export process; Pro daily backups; PITR paid | Scheduled Firestore backup/restore and PITR require billing; configure schedules/retention | SQL dumps or base backup/WAL; schedule, encrypt, monitor and restore-test yourself |
| Portability | PostgreSQL export and open-source/self-hostable stack; auth/session/realtime adapters still require migration | SDK, Rules, Firestore data/query model and event code create migration work; export is not a drop-in SQL schema | SQL + OIDC + HTTP boundaries travel more easily; hosting/operations remain your responsibility |

Capabilities above are supported by [Supabase Auth](https://supabase.com/docs/guides/auth), [Swift OTP](https://supabase.com/docs/reference/swift/auth-signinwithotp), [Supabase RLS](https://supabase.com/docs/guides/database/postgres/row-level-security), [Firebase Apple email-link auth](https://firebase.google.com/docs/auth/ios/email-link-auth), [Firestore transactions](https://firebase.google.com/docs/firestore/manage-data/transactions), [AppAuth iOS](https://github.com/openid/AppAuth-iOS), and [Keycloak](https://www.keycloak.org/).

Firestore automatically synchronizes cached writes when connectivity returns; concurrent changes to a document can use last-write-wins. Its transactions fail offline. NIDAA should therefore send urgent mutations only through an explicit online command endpoint with operation receipts, regardless of chosen provider. [Offline behavior](https://firebase.google.com/docs/firestore/manage-data/enable-offline), [transactions](https://firebase.google.com/docs/firestore/manage-data/transactions).

Firebase's current Apple email-link guidance uses the newer Hosting-based flow; legacy SDK flows relying on Dynamic Links are deprecated. Do not copy an old tutorial into the trial. [Current Apple email-link guide](https://firebase.google.com/docs/auth/ios/email-link-auth).

Supabase project region selection governs primary data location, not complete regulatory compliance. Its reviewed list includes Frankfurt but does not list a Saudi region. Firebase locations vary by product. Do not assume a Riyadh user's data stays in Saudi Arabia, or select a region without reviewing the required jurisdiction. [Supabase regions](https://supabase.com/docs/guides/platform/regions), [Firestore locations](https://firebase.google.com/docs/firestore/locations), [Firebase product locations](https://firebase.google.com/docs/projects/locations).

## Cost components — do not combine “free auth” with “free app”

| Component | Supabase | Firebase | Custom backend |
|---|---|---|---|
| Authentication | Free: 50,000 MAU. Pro: 100,000 included, then listed $0.00325/MAU. Email delivery separate. | Basic non-phone authentication listed at no cost; Identity Platform has its own quotas/pricing, including 50,000 MAU allowance. Phone/SMS charged and deferred. | OIDC provider charges or self-hosted Keycloak compute/operations; email delivery separate |
| Database/storage/egress | Free: 500 MB DB, 1 GB file storage, 5 GB egress. Pro from $25/month, first project included; additional projects from $10/month. | Firestore one free database/project: 1 GiB data, 50,000 reads/day, 20,000 writes/day, 20,000 deletes/day, 10 GiB monthly outbound. Paid usage depends on operation type/location. | Compute/managed DB, disk/IO, backups and egress; no universal free tier or honest fixed quote without a host/region/workload |
| Backend/functions/sync | Function, realtime and compute quotas/overages are separate dimensions of the plan | Cloud Functions/Cloud Run and networking are distinct billable infrastructure; verify billing requirements before deployment | API/worker hosting, queue, monitoring, maintenance and security updates; labor is not free |
| Notifications | APNs integration and worker/egress costs are not included as a NIDAA delivery guarantee | FCM listed at no cost; Apple delivery still uses APNs and needs Apple configuration | APNs worker/credentials/egress/monitoring; Apple developer/signing prerequisites separately verified before device trial |
| Backups/recovery | Free no automatic backups. Pro daily backups retained seven days; PITR is extra, advertised from $100/month | Backup storage, restore, PITR and TTL deletes require billing; not included in Firestore free quota | Backup storage, recovery capacity, encryption keys and restore drills budgeted separately |

Sources for quoted plan/allowance figures: [Supabase pricing](https://supabase.com/pricing), [Supabase billing dimensions](https://supabase.com/docs/guides/platform/billing-on-supabase), [Firebase pricing](https://firebase.google.com/pricing), [Firestore pricing](https://firebase.google.com/docs/firestore/pricing). No claim of zero total production cost is made. Even a small app may incur email, worker, monitoring, backup or paid-plan charges before exhausting database quotas.

Supabase's free projects may pause after one week of inactivity; free automatic backup and uptime guarantees are absent. A free plan is useful for disposable experiments, not evidence of emergency-service reliability. The built-in email service has low rate limits (documented two email sends/hour for relevant built-in delivery), so a production email provider/configuration and its costs must be evaluated separately. [Pricing](https://supabase.com/pricing), [Auth rate limits](https://supabase.com/docs/guides/auth/rate-limits).

For a custom option, propose a small command API + PostgreSQL + established OIDC/Keycloak, not a homemade auth server. No hosting quote is invented: provisionally estimate from chosen-region DB/API instance-hours + storage + egress + email + backup + monitoring, then validate with a workload. PostgreSQL supports SQL dumps, filesystem backups and continuous archiving; owning these does not prove they restore correctly. [PostgreSQL backup options](https://www.postgresql.org/docs/current/backup.html), [Keycloak administration](https://www.keycloak.org/docs/latest/server_admin/).

## Backup, session and migration gates

- Supabase: test session-row revocation checks, RLS with anon/user/service contexts, serialized consent/outbox mutations and restore/deletion replay. Review backup scope rather than assuming file storage is included. [Sessions](https://supabase.com/docs/guides/auth/sessions), [backups](https://supabase.com/docs/guides/platform/backups), [self-hosting](https://supabase.com/docs/guides/self-hosting).
- Firebase: enable revocation-aware token verification, explicit deny rules in emulator configuration, backend authorization and transactional command endpoints; never treat offline write success as server acceptance. [Session revocation](https://firebase.google.com/docs/auth/admin/manage-sessions), [Rules emulator tests](https://firebase.google.com/docs/firestore/security/test-rules-emulator), [Emulator Suite](https://firebase.google.com/docs/emulator-suite).
- Firestore backup retention is configurable up to 14 weeks; the NIDAA proposal is a separate maximum of 35 days that must actually be configured and tested. [Backup schedule documentation](https://firebase.google.com/docs/firestore/backups).
- Keep internal UUIDs, command schema and domain event semantics provider-neutral. Porting identity requires explicit issuer/subject remapping, session invalidation and verified account linking; never migrate by matching display names. Do not assume export migrates passwordless sessions or policies.

Decision gate: implement only the isolated local Supabase trial after review of this PR. Reconsider Firebase/custom if required jurisdiction, operational ownership, abuse controls or restore guarantees cannot be met. No new paid service or deployment is authorized by this recommendation.
