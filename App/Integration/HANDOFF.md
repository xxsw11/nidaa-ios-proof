# Local integration UI handoff

## Implemented

- Debug-only explicit Settings route; the default local experience is preserved. Release displays no route and compiles out integration screens/store. No notification, APNs, speaker or flashlight action was added.
- `ExperienceStore` owns one integration store/client for the app lifetime, avoiding separate in-flight clients writing the same Keychain when a sheet is reopened.
- Live mode fixes the endpoint to loopback `http://127.0.0.1:55421`; `NidaaClient.live` uses the official Auth SDK client and Keychain. Display snapshots are memory-only. No session/credential data is written to defaults or local demo archives.
- Arabic screens for registration, login, local-mail token verification, recovery/password change, session refresh/logout/global revocation and explicit account deletion.
- Directional invitation acceptance requires an explicit consent toggle. Create/cancel/decline/withdraw/block/unblock use server commands. Local-only clipboard copy expires after 60 seconds; the token itself is never displayed. Verification and invitation inputs are secure fields cleared on use/disappearance.
- Shared alert selection/create, fake-provider versus app acknowledgment versus human-response states, response/decline, explicit sender close, retry and add-recipient actions.
- Create/retry/add use `LocalAuthenticationService`, then a separate one-minute confirmation. Selection change, cancellation, section change, background and dismissal invalidate the gate. The system's temporary inactive state is not treated as background, allowing its authentication sheet to function. No Face ID result is sent as account identity.
- Unknown outcomes block all new domain commands and offer only a same-operation lookup. Never-sent records offer explicit cancellation. Reconnection/refresh does not dispatch. Expired identity hides prior account data and asks for login. Refresh tokens do not claim recent account authentication.
- Identity loss, new login and verification clear the prior invitation token, confirmation, selection and account display, and cancel local authorization. Pending operation persistence remains the client's responsibility and is restored only after the account is authenticated again. The startup banner describes local integration **mode**, without claiming a connection before a response. Uncertain logout explicitly avoids claiming either local credential erasure or server revocation.
- Existing typography/cards/palette, RTL inheritance, scrolling, Dynamic Type and vertical navigation at accessibility sizes.
- Newly required verification, post-authentication confirmation and unresolved-operation review steps scroll into view using stable anchors. Their appearance does not bypass authorization, explicit confirmation or the unresolved-operation barrier.
- The integration form uses the existing explicit Close control; downward form scrolling cannot dismiss its sheet. Card-level accessibility identifiers are omitted so SwiftUI preserves each action's own identifier. Test taps require enabled controls, and login tests check password draft retention through the existing signup-length gate without reading secure values.
- A visible Arabic keyboard Done control dismisses the keyboard without editing drafts; UI tests use that same control rather than keyboard gestures or inserted characters.
- Auth and consent draft cleanup belongs to the owning stable form container, rather than the last scrolling card. Keyboard or card visibility changes must not discard a draft; submission and leaving the entire form still clear sensitive values.
- Logout clears account-specific display before its first network await, then reports confirmed or uncertain server revocation. The existing large-text/logout UI test exercises a Debug Simulator-only delayed mock completion and asserts the old account and contact navigation are absent while logout remains in progress.

## Evidence boundary

`IntegrationUITests.swift` contains 8 UI tests and retained Arabic screenshots. Its `-nidaa-integration-mock` path is compiled only in Debug Simulator, explicitly labeled **MOCK · محاكاة واجهة فقط** on every screen and has no live network client. Mock device-authentication requires a visible, deliberate simulated result. These tests do not establish Simulator-to-backend E2E, real Face ID or a physical notification. The separate actual Swift integration runner and live backend suite provide their own evidence.

No Xcode is installed on this Windows workstation. Parent task owns cloud Debug/Release compilation, UI execution, screenshot inspection, project wiring and resulting fixes/status. Do not report the new UI tests as passed before those runs complete.

## Deliberate limitations

- This is a local trial surface, not a polished production contacts directory. The current server contract omits other accounts' display names, so live counterpart labels use a short account identifier; mock labels are fictional Sara/Sami/Noor.
- The inbox is accessed separately on the same host at `127.0.0.1:55424`. The app accepts the token from its verification URL without following arbitrary URLs or exposing an inbox API to the app.
- No hosted endpoint, public tunnel, automatic outbox dispatch, push permission flow or physical device test was enabled.
