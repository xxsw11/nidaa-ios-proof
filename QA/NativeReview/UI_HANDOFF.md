# Native review UI handoff

No native tests ran on this Windows workstation. Cloud source `031ffd5f5177b41fa2717409ac15a7e50ad8b4fa` produced the results below. Candidate `d6f65ec253f6345e6ae2e368c4b2b8d7baf88681` is pending cloud validation. Parent task owns workflows, evidence and publication; source alone is not a passing test.

## Changes and evidence boundaries

- The existing eight MOCK UI scenarios and authorization assertions are retained; their input/scroll fixtures have been updated. Their shared fixture now verifies **AutoFill On**, through native Settings on a freshly created `NIDAA-Disposable-*` Simulator only. A failure to establish On fails setup; no disabling fallback exists.
- Password entry uses one native `UITextField` throughout visibility changes, preserving the draft and selection. It keeps appropriate password/new-password semantics, secure entry by default, ASCII-capable keyboard, Dynamic Type, and explicit native Done. Tokens remain secure and cannot be revealed. Password visibility resets when the app becomes inactive or the field disappears. Arabic labels and RTL form layout remain; ASCII credentials have LTR input.
- User-initiated native `PasteButton` supports paste into credentials and tokens. The test runner supplies only fictional test data through the disposable Simulator pasteboard. This is input delivery through the real UI, not account authentication or backend state injection. Pasteboard items expire after a minute and are cleared in teardown. They are not cleared before the asynchronous paste transfer can finish.
- Live UI startup uses `-nidaa-integration-live-ui`; its default client is real, with optional `NIDAA_LIVE_BASE_URL` accepted only in Debug Simulator and still validated by `TrialEnvironment`. The normal manual integration route remains `http://127.0.0.1:55421`.
- `-nidaa-integration-simulated-device-auth` enables only the deliberate local-device verification prompt, visibly labeled on screen and compiled only for Debug Simulator. It does not mock Supabase Auth, account identity, network, database, consent, or responses. A separate confirmation remains mandatory after this simulated device verification.

Apple references: [Password AutoFill semantics](https://developer.apple.com/documentation/security/enabling-password-autofill-on-a-text-input-view), [secure text entry](https://developer.apple.com/documentation/uikit/uitextinputtraits/issecuretextentry), [ASCII-capable keyboard](https://developer.apple.com/documentation/uikit/uikeyboardtype/asciicapable), [native paste controls](https://developer.apple.com/documentation/uikit/uipastecontrol). The historical yellow system overlay and dropped Latin keystrokes motivated input review; the three functional AutoFill-On tests passed at 031, after separating credential and verification-token steps. This is evidence for the observed paths, not a general diagnosis of Apple internals; saved-credential selection remains separately pending.

## Suites

| Suite | Current recorded result | Boundary / next validation |
|---|---|---|
| `AutoFillUITests` at 031 | [Run36516431533](https://github.com/xxsw11/nidaa-ios-proof/actions/runs/36516431533): 3 functional passes, 1 availability skip; Debug/Release passed | Manual registration/navigation, paste/login/recovery and large RTL visibility; backend is MOCK |
| `IntegrationUITests` at 031 | [Run36516431563](https://github.com/xxsw11/nidaa-ios-proof/actions/runs/36516431563): 7/8 passed | Only `testLargeArabicLayoutAndLogoutIsolation` failed in shared scroll helper line150; 05ab0f stable-target correction pending |
| Local-b at 031 | Same run: 7/8 passed; deletion/disappearance and persisted deletion passed | Ahmad-receipt assertion failed in `testBothActionsBackgroundDuringAuthenticationAndConsentChanges`; stronger original-recipient preconditions in 05ab0f pending |
| Backend/client at 031 | [Run36516431478](https://github.com/xxsw11/nidaa-ios-proof/actions/runs/36516431478): 55 backend + 45 reference + 14 QA + 24 client tests and live SDK journey passed | Linux stack/SDK evidence, not native UI/backend E2E |
| `testSavedCredentialSelection` | Added in candidate d6f65ec; outcome pending | Actual creation/selection through disposable native Passwords/AutoFill, followed by MOCK login; replaces availability-only probe |
| `NativeIntegrationUITests` | Not executed: environment isolation gate failed before services | Both prepared journeys remain unverified against a native real backend |
| Physical notifications/device authentication | Deferred; no hardware | No Simulator or API result validates physical delivery or authentication hardware |

Candidate d6f65ec has no result claim here. Its saved-selection scenario requests no personal Apple account/passcode; a skip requires an observed native personal-account/passcode requirement. The 031 availability skip did not prove that saved credentials are unsupported. Manual typing while AutoFill is On is not successful saved-credential selection.

## Real journey and fixtures

The following are **prepared, unexecuted native UI/backend scenarios** because the isolation gate failed before service startup. One Simulator would be used **sequentially**, not for simultaneous reception. Fictional, uniquely named A/B accounts register through UI, obtain verification tokens from real local Mailpit using the test process only, and submit those tokens through the UI. A targets an invitation to B; its secret token is copied through UI, retained privately by the runner, then pasted by B. B explicitly accepts directional consent after fresh account sign-in. A performs local simulated device verification and separate confirmation. B fetches, acknowledges, opens, and responds through actual backend calls. A observes the response and explicitly resolves. The test restarts the app, checks resolved state, withdraws consent through B's UI, and verifies A cannot target B. Every logout checks removal of previous account navigation and alert display.

The second test uses separate fictional accounts and fixed loopback-only fault controls. It checks offline refresh/reconnect without command dispatch; a committed create whose response is dropped; persistence across app restart; lookup of the original operation without another command POST or another database alert; alert expiry; session revocation; and subsequent sign-in without reopening an expired alert. Fixture-based expiry/revocation are clearly separate from ordinary UI steps. No fixture inserts consent, a human response, or successful authentication.

Runtime contract:

- Real gateway `127.0.0.1:55421`; private fault proxy `127.0.0.1:55428`; Mailpit `127.0.0.1:55424`; fixture controller `127.0.0.1:55425`.
- `NIDAA_FIXTURE_CAPABILITY` is available only to the XCTest runner. It is never passed to the app or included in attachments.
- Control POST uses `X-NIDAA-Fixture`, fixed actions `offline`/`drop_next_command_reply`/`expire_alert`/`revoke`. GET state supplies nonsecret counters and chronological alert IDs. Tests compare command and alert count deltas across lost reply, restart and lookup.
- No public tunnel, hosted service, actual notification or audio. Fake handoff and API fetch do not prove APNs delivery.

## Evidence handling

Raw XCTest logs, xcresult bundles, screenshots on automatic failure, typing events and screen recordings can contain secrets even when application fields are masked. Keep them private and discard them after safe extraction; **do not upload raw artifacts**. The parent workflow must export only inspected, allowlisted screenshots and sanitized counts/status. New suites do not attach live failure screenshots. Explicit screenshots are taken after submitted fields are cleared or after returning a never-authenticated demonstration to hidden state. A separate visible field-only crop is permitted only after the value is asserted and guarded equal to DEMO-NOT-A-CREDENTIAL; that string is never submitted for authentication. Native screenshots use `integration-native-real-`; MOCK/AutoFill screenshots use `integration-mock-` and never claim real backend success. Saved-selection diagnostics export only fixed known control labels/types and observed personal-account/passcode requirements; generated password values are never read or exported.

Source checks cannot replace execution. The recorded 031 cloud results and unresolved failures remain source-bound; candidate d6f65ec results must be recorded separately with run, attempt and Simulator/runtime identity before a merge recommendation. No local Swift compilation, native real-backend E2E or physical-device validation is claimed. See [coverage and remaining gaps](COVERAGE.md).

Compiler checkpoint:05ab0f failed UI-test compilation before execution (optional application inferred inside an array); Release passed. Candidate d6f65ec guards the nonoptional application without changing assertions. Original reports are in evidence/compile-05ab0f and attempt-history.json. This is a test-source failure, not a runtime environment failure.
