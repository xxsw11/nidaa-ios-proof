# Original Simulator screenshot review

Reviewed 2026-09-28. Source `5a4f418b81b54ed69757d342965100ecf41e8598`, [run 36454477295](https://github.com/xxsw11/nidaa-ios-proof/actions/runs/36454477295), attempt 1, integration job 109037470438. Artifact 10986730207 SHA-256: `a5315fedaae84deb8285f377d325335fedceeac9000db03a2a508562f09b8a53`.

All 11 original PNGs below were visually inspected. They are delivered unchanged in `Screenshots/`, with original export names and per-image hashes in `Screenshots/provenance.json`. Environment: iPhone 16 Pro Simulator, iOS 18.5 (22F77), Xcode 16.4 (16F6), macOS 15.7.9 (24G830). The integration UI is explicitly MOCK; these images do not establish real backend connectivity or physical-device behavior.

| Original delivered filename | Observed result |
|---|---|
| integration-mock-01-auth-rtl.png | Arabic RTL authentication card, prominent MOCK boundary, empty fields and disabled submission actions. |
| integration-mock-02-awaiting-verification.png | Explicit waiting-for-local-email-verification state, recovery switch and secure token entry; no actual token visible. |
| integration-mock-03-directional-consent.png | One-direction-only explanation, explicit consent toggle and acceptance action. |
| integration-mock-04-explicit-confirmation.png | Separate authentication and final confirmation/cancel controls; short confirmation validity explained. |
| integration-mock-05-shared-outgoing.png | Fictional Sara/Sami case remains active; fake handoff, receipt, opening and human response are distinct. |
| integration-mock-06-unknown-outcome.png | Unknown outcome is stated clearly; original operation lookup is offered and another creation is disabled. |
| integration-mock-07-acknowledged-not-responded.png | Receipt/opening are visible without claiming a human response. |
| integration-mock-08-human-response-keeps-case-open.png | Human assistance response is displayed while the incident remains active. |
| integration-mock-09-large-arabic-auth.png | Accessibility XXXL text wraps vertically within the scroll view without horizontal overlap; lower form controls require scrolling. |
| integration-mock-10-large-arabic-consent.png | Long consent label and action wrap inside the screen at maximum tested text size. |
| disposable-simulator-autofill-passwords-and-passkeys-off.png | Original native Settings switch attachment visibly shows AutoFill off on the owned disposable Simulator. |

The associated eight UI journeys passed, including scrolling to and operating the large-text controls. Screenshots capture scroll viewports, not entire pages: partly offscreen cards and absence of the top MOCK banner in some scrolled images are expected. No composite images or edited screenshots are used.

Body text and actions are legible in the inspected images. Empty-field placeholder text is dim against the dark background; contrast measurement and further visual polish remain follow-up work. Disabled controls are intentionally subdued. This inspection is not a formal accessibility or WCAG certification and does not establish VoiceOver coverage.

Credential entry was verified with native password AutoFill off. AutoFill-enabled behavior remains unproven; earlier attempts encountered the system strong-password cover. No physical-device setting was changed. The fixture and its limits are documented in `Integration/README.md` and the attempt history.
