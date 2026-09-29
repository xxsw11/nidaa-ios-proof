# Native review UI handoff

Status at source handoff: **not executed on this Windows workstation**. Cloud compilation, execution and visual inspection must establish results; source alone is not evidence of a passing test. Parent task owns project wiring, workflows, native runtime and publication.

## Changes and evidence boundaries

- Existing eight MOCK UI test bodies and assertions are retained unchanged. Their shared fixture now verifies **AutoFill On**, through native Settings on a freshly created `NIDAA-Disposable-*` Simulator only. A failure to establish On fails setup; no disabling fallback exists.
- Password entry uses one native `UITextField` throughout visibility changes, preserving the draft and selection. It keeps appropriate password/new-password semantics, secure entry by default, ASCII-capable keyboard, Dynamic Type, and explicit native Done. Tokens remain secure and cannot be revealed. Password visibility resets when the app becomes inactive or the field disappears. Arabic labels and RTL form layout remain; ASCII credentials have LTR input.
- User-initiated native `PasteButton` supports paste into credentials and tokens. The test runner supplies only fictional test data through the disposable Simulator pasteboard. This is input delivery through the real UI, not account authentication or backend state injection. Pasteboard items expire after a minute and are cleared in teardown. They are not cleared before the asynchronous paste transfer can finish.
- Live UI startup uses `-nidaa-integration-live-ui`; its default client is real, with optional `NIDAA_LIVE_BASE_URL` accepted only in Debug Simulator and still validated by `TrialEnvironment`. The normal manual integration route remains `http://127.0.0.1:55421`.
- `-nidaa-integration-simulated-device-auth` enables only the deliberate local-device verification prompt, visibly labeled on screen and compiled only for Debug Simulator. It does not mock Supabase Auth, account identity, network, database, consent, or responses. A separate confirmation remains mandatory after this simulated device verification.

Apple references: [Password AutoFill semantics](https://developer.apple.com/documentation/security/enabling-password-autofill-on-a-text-input-view), [secure text entry](https://developer.apple.com/documentation/uikit/uitextinputtraits/issecuretextentry), [ASCII-capable keyboard](https://developer.apple.com/documentation/uikit/uikeyboardtype/asciicapable), [native paste controls](https://developer.apple.com/documentation/uikit/uipastecontrol). The historical yellow system overlay and dropped Latin keystrokes motivated input review; these new changes must be validated with AutoFill enabled and are not yet a proven fix.

## Suites

| Suite | Tests | What it establishes if passed | Current source-handoff status |
| --- | ---: | --- | --- |
| `IntegrationUITests` | 8 | Previous MOCK flow/gates/isolation/large RTL regressions, now with AutoFill enabled | Not executed |
| `AutoFillUITests` | 3 functional + 1 availability probe | Manual registration, field navigation, paste login, recovery/new password, visible/hidden noncredential demonstration in large RTL | Not executed |
| `NativeIntegrationUITests` | 2 | Real sequential UI-to-local-backend journey and separately identified failure fixtures | Not executed |
| Saved-credential selection | — | Actual selection of an existing system credential | Not tested; bounded native Passwords probe records the observed setup state, without assuming iCloud/passcode requirements |
| Physical notifications/device authentication | — | Real iPhone behavior | Deferred; no hardware and outside this native Simulator evidence |

The availability probe never requests a personal Apple account or passcode. It records recognized native setup state or explicitly says no recognized state was established, then reports saved-credential selection as skipped/not tested. Manual typing while AutoFill is On is not successful saved-credential AutoFill. Its source does not prove that saved credentials are unsupported.

## Real journey and fixtures

One Simulator is used **sequentially**, not for simultaneous reception. Fictional, uniquely named A/B accounts register through UI, obtain verification tokens from real local Mailpit using the test process only, and submit those tokens through the UI. A targets an invitation to B; its secret token is copied through UI, retained privately by the runner, then pasted by B. B explicitly accepts directional consent after fresh account sign-in. A performs local simulated device verification and separate confirmation. B fetches, acknowledges, opens, and responds through actual backend calls. A observes the response and explicitly resolves. The test restarts the app, checks resolved state, withdraws consent through B's UI, and verifies A cannot target B. Every logout checks removal of previous account navigation and alert display.

The second test uses separate fictional accounts and fixed loopback-only fault controls. It checks offline refresh/reconnect without command dispatch; a committed create whose response is dropped; persistence across app restart; lookup of the original operation without another command POST or another database alert; alert expiry; session revocation; and subsequent sign-in without reopening an expired alert. Fixture-based expiry/revocation are clearly separate from ordinary UI steps. No fixture inserts consent, a human response, or successful authentication.

Runtime contract:

- Real gateway `127.0.0.1:55421`; private fault proxy `127.0.0.1:55428`; Mailpit `127.0.0.1:55424`; fixture controller `127.0.0.1:55425`.
- `NIDAA_FIXTURE_CAPABILITY` is available only to the XCTest runner. It is never passed to the app or included in attachments.
- Control POST uses `X-NIDAA-Fixture`, fixed actions `offline`/`drop_next_command_reply`/`expire_alert`/`revoke`. GET state supplies nonsecret counters and chronological alert IDs. Tests compare command and alert count deltas across lost reply, restart and lookup.
- No public tunnel, hosted service, actual notification or audio. Fake handoff and API fetch do not prove APNs delivery.

## Evidence handling

Raw XCTest logs, xcresult bundles, screenshots on automatic failure, typing events and screen recordings can contain secrets even when application fields are masked. Keep them private and discard them after safe extraction; **do not upload raw artifacts**. The parent workflow must export only inspected, allowlisted screenshots and sanitized counts/status. New suites do not attach live failure screenshots. Explicit screenshots are taken after submitted fields are cleared or, for visibility, after returning a never-authenticated noncredential demonstration to hidden state. Native screenshots use `integration-native-real-`; MOCK/AutoFill screenshots use `integration-mock-` and never claim real backend success. The availability probe emits only a small allowlisted setup-state note.

Source checks completed here: original eight test bodies compared byte-for-byte after newline normalization and unchanged; `git diff --check` passed. No local Swift compilation or native UI execution is claimed. Cloud results must be tied to the eventual commit, run attempt and Simulator/runtime identity before merge recommendation.
