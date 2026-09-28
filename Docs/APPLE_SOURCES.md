# Official sources reviewed — 28 September 2026

Primary sources only for implementation decisions. Some Apple pages required JavaScript; current indexed Apple documentation supplied readable content. The Critical Alerts request form redirects to account sign-in, so its current fields were not inspected. No login or submission occurred.

| Area | Official source | Decision supported |
|---|---|---|
| Authentication | https://developer.apple.com/documentation/localauthentication/lapolicy/deviceownerauthentication | System biometrics or device passcode; no app-owned PIN |
| Face ID purpose | https://developer.apple.com/documentation/localauthentication/lacontext | NSFaceIDUsageDescription and policy availability checks |
| Local notifications | https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app | One system-scheduled request and explicit cancellation |
| Delegate lifecycle | https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/delegate | Install during app launch, before launch completes |
| Notification interaction | https://developer.apple.com/documentation/usernotifications/handling-notifications-and-notification-related-actions | Foreground presentation and opening are separate observations |
| APNs registration | https://developer.apple.com/documentation/usernotifications/registering-your-app-with-apns | Optional push entitlement, token callback and failure handling; no token caching |
| APNs transport | https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns | Development endpoint, alert push type, expiration and best-effort delivery |
| Provider response | https://developer.apple.com/documentation/usernotifications/handling-notification-responses-from-apns | Separate provider result and identifiers |
| Official test tool | https://developer.apple.com/documentation/usernotifications/testing-notifications-using-the-push-notification-console | Console instead of new third-party provider; delivery logs and retained test history |
| Console access | https://developer.apple.com/notifications/push-notifications-console/ | Developer Program account access; never assumed here |
| Critical entitlement | https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.usernotifications.critical-alerts | Apple-issued entitlement before requesting critical authorization |
| Critical permission | https://developer.apple.com/documentation/usernotifications/unauthorizationoptions/criticalalert | Critical-specific user permission and documented mute/DND behavior, not tested here |
| Entitlement requests | https://developer.apple.com/help/account/capabilities/capability-requests | Managed capability requires grant; authorized account role required |
| Device run | https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices | Real device, signing and platform support |
| Developer Mode | https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device | User-controlled device prerequisite |

The archived notification programming guide discusses force-quit behavior, but this proof does not use that as a substitute for a current device observation. It sends ordinary alert pushes, not background `content-available` pushes. No claim of bypassing system restrictions follows from successful compilation or receipt of a device token.
