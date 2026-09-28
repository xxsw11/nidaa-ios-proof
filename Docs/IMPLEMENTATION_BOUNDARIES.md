# Implemented, simulated and untested

| Area | Implemented locally | Evidence boundary |
|---|---|---|
| Interface | Arabic RTL, four tabs, readiness, contacts, alert selection/confirmation, outgoing/incoming/history, settings and policies | Simulator screenshots and UI tests; not a physical-device accessibility audit |
| Contacts | Add/edit/delete, four invitation states, independent direction permissions, revoke/block | All consent/invitations are controlled demo data, not another person's authorization |
| Incident | One active outgoing ID, retry preserves ID/responses, receipt/open/human-response separated, explicit close/cancel, expiry/nonresponse, alternative contact | No service acceptance, remote device acknowledgment or actual responder |
| Authentication | Native LocalAuthentication service, new context and one-use bound confirmation, background invalidation, optional app lock | XCTest success/failure/cancellation is simulated in Debug Simulator; biometric hardware remains untested |
| Incoming while locked | Generic presentation with silence/dismiss; details and response require unlock | Local UI event, not APNs or a lock-screen system notification |
| Appearance | Dark/light/system, primary/button/background, isolated preview, save/cancel/default restore, contrast-correct text | Stored on this installation; active alert palette held stable |
| Persistence | Fictional contacts, appearance and lock preference | Session incidents/history are intentionally memory-only; process termination clears them |
| Permissions | Read actual notification settings; ask only when not determined; Settings route after decision | Permission does not prove delivery; no notification scheduled by this stage |
| Policies | Preliminary use/abuse/consent/privacy/deletion text matching current behavior | No final legal review, legal entity or compliance guarantee |
| Device capabilities | No new hardware capabilities asserted | APNs, audio, Focus, Bluetooth, low power, flashlight and Critical Alerts remain untested/not enabled |

Runtime notification registration/scheduling is guarded off in every configuration. No secrets, third-party SDK, backend, location, microphone, address-book import, phone call, real message, publication or official application is added.

Real-device tests retain their original statuses in QA/device-test-matrix.csv. They are deferred for lack of Apple devices, not a blocker for this local stage. Any later audio/notification test requires a specific authorized phone and testing window.
