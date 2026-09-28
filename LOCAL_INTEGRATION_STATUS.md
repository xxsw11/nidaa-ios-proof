# Local integration trial — implemented and verified

Updated 2026-09-28. [Implementation PR #3](https://github.com/xxsw11/nidaa-ios-proof/pull/3) depends on the still-open [design PR #2](https://github.com/xxsw11/nidaa-ios-proof/pull/2). Neither is merged. Main remains `a1ffbec01bd7cc39409bbd740639606fe2f29e39`; the implementation is based on PR #2 head `ab479a345aa6f5c2a98a369a7f7ed23819957a48`.

## Actual results

| Check | Observed outcome | Evidence |
|---|---|---|
| Real GoTrue/Auth, HTTP and PostgreSQL | Passed: 47 integration tests | [Backend run 36434112612](https://github.com/xxsw11/nidaa-ios-proof/actions/runs/36434112612) |
| Real official Swift Auth client | Passed: verified A/B/C and independent B2 journey | Same isolated Linux run; 19 additional injected client unit tests passed |
| Existing reference and Python checks | Passed: 45 reference + 13 Python | Backend run and preserved logs |
| Swift core and client packages on macOS | Passed: 45 core + 19 client tests | [Native run](https://github.com/xxsw11/nidaa-ios-proof/actions/runs/36454477295) |
| Native UI regressions | Passed: 25 unique journeys (8 new + 17 existing), zero skips | Same run, split into 8/9/8 shards |
| Debug / Release | Both passed in all three Simulator jobs | Original native logs and summaries |
| Arabic RTL and accessibility text | Original new screenshots inspected | [Visual review](QA/LocalIntegration/VISUAL_REVIEW.md) |
| Simulator with real local backend | Not tested | Permitted fallback used: actual Swift client on Linux; mock UI separately on macOS |
| Physical iPhone, APNs, silent-mode bypass, Critical Alerts | Not tested / deferred | No Apple devices; no real notification/audio authorized or delivered |

The backend/Swift executable source was tested at `528b9535fbb7f1b229bb0efa0724572f7262cf6c`, then passed again at `ce9b78a6a3e9f53169822e109770d222481af4fd` ([repeat run](https://github.com/xxsw11/nidaa-ios-proof/actions/runs/36437636878)). The final native executable source is `5a4f418b81b54ed69757d342965100ecf41e8598`. [Exact backend/client source comparison](QA/LocalIntegration/backend-source-parity.json) confirms all 36 non-documentation integration files and the backend workflow match the repeated successful backend run. Later delivery changes only documentation, evidence and inventory; the delivery manifest records the exact final Git commit and every packaged file hash.

## Implemented behavior

The native gate combines passing integration/local-a artifacts from attempt 1 and passing local-b evidence from a same-source attempt 2 rerun. The initial local-b runner failed before UI execution; its original failure remains recorded. No code was changed for that rerun.

The isolated stack uses pinned Supabase Auth, PostgreSQL and Mailpit, with no external container route. A loopback-only host relay reaches a fixed internal gateway through Docker exec, without LAN publication or a public tunnel. Runtime credentials remain ignored and outside app/source/evidence. See [clean setup and lifecycle commands](Integration/README.md).

Actual signup, inbox verification, password login/recovery, refresh, current/all-session revocation, disabling and deletion are exercised. User journeys consume real local email messages rather than administrative verification. Server actors come from validated provider sessions, and recent authentication uses signed AMR evidence; token refresh and Face ID cannot renew it.

Directional consent, RLS, third-account denial, atomic state/receipts/outbox, duplicate/conflicting operation IDs, lost-response lookup, independent-session races, expiry/retry limits and worker crash/restart pass against the real service/database. The fake sink remains distinct from client acknowledgement, opening and human response. Acknowledgement never becomes a human response or closes an incident.

Retention and synchronization removals are tested. An actual isolated PostgreSQL backup/restore drill replays a separately newer deletion/revocation ledger before restored data is exposed. Tests do not establish production backup guarantees.

Debug adds a separate Arabic integration route with the official Swift Auth adapter and device-only Keychain storage. It preserves the default local experience and never uploads its history automatically. Account/environment isolation rejects delayed old-session results. Mutations retain unknown outcomes durably before posting, never automatically resend, and query the original operation. Sender actions require fresh local authentication and a separate short-lived confirmation. Logout hides account-specific UI before awaiting server revocation; uncertain revocation is explicitly reported. Release excludes the trial screens and Simulator mock authentication.

## Limits and review decisions

This is a local integration trial, not production approval. Database command decisions are deliberately serialized; snapshots are complete and bounded, without production-scale paging. Email/phone identity changes are disabled. Fake database delivery cannot demonstrate exactly-once external delivery. Restored previously revoked relationships require fresh consent conservatively. Ledger expiration awaits a verified backup inventory. Retention and limits are provisional product decisions, not legal requirements. [Decisions and official references](Integration/DECISIONS.md).

Simulator mock UI cannot prove native/backend connectivity, hardware biometrics or physical Keychain security. The actual Linux Swift journey proves the shared official Auth/network adapter against the stack, with isolated in-memory test sessions. No hosted Supabase project, public backend, external SMTP, APNs, store submission, purchase or merge occurred.

Manual credential entry is tested with password AutoFill verified off through native Settings on a newly created disposable Simulator. The CI script deletes only that owned device afterward. AutoFill-enabled entry remains unproven because Apple's strong-password cover blocked automated typing in previous attempts. This test fixture does not disable app security or change physical-device settings. See the original switch screenshot and setup instructions.

## Evidence and handoff

- [Backend evidence](QA/LocalIntegration/backend-528b953/README.md), [native evidence](QA/LocalIntegration/native-5a4f418/README.md), and [requirement mapping](QA/LocalIntegration/COVERAGE.md).
- [Attempt history](QA/LocalIntegration/attempt-history.json) preserves failed/cancelled runs and their causes; they are not counted as passes.
- Final review corrected parent accessibility IDs, form draft lifetime, credential/token keyboard selection, offscreen test discovery and immediate logout display clearing. All affected tests were rerun without removing authorization assertions.
- [Historical archive hashes](QA/LocalIntegration/preservation.json) confirm v06 and prior delivery archives are unchanged. Fictional demo identities are used throughout active source; runtime data, mailboxes, dumps and credentials are excluded.
- No user intervention is required for this completed trial. The exact next step is in [NEXT_REVIEW.md](NEXT_REVIEW.md).
