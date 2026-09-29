# Original screenshot review

Reviewed original exported PNGs from run36513217922 and run36513218045, attempt1, source3759e291e963dced98b41d6d04102f0ac56dd4e7. These are failed-candidate observations, not successful journey evidence. File hashes and original XCTest export names are in the corresponding evidence/result.json and delivered Screenshots/provenance.json. Images were viewed, not inferred from filenames or generated as previews.

| Original named attachment | Observed result | Limit |
|---|---|---|
| disposable-simulator-autofill-passwords-and-passkeys-on | Native Settings switch visibly green/On; matches setup assertion. | Enables the fixture; does not establish saved-credential selection. |
| integration-mock-01-auth-rtl | Dark Arabic account form, visible MOCK explanation, empty credential field and separate eye/paste buttons. No overlap in the visible viewport. | Before input; cannot establish draft retention or keyboard behavior. |
| integration-mock-09-large-arabic-auth | Accessibility XXXL text wraps within the card; heading and MOCK explanation remain readable. | Initial scroll position contains explanation only; credential controls below the viewport still need journey verification. |
| integration-mock-autofill-enabled-recovery-complete-mock | Arabic account card after recovery/password update, empty password field and readable controls. | This one test passed; network is MOCK. The naturally scrolled top edge is not a claim that the full screen is visible. |
| autofill-saved-credential-availability-screen | Disposable Passwords app shows its Notifications onboarding and Continue button. | This is not an iCloud/passcode requirement. The next candidate advances this observed step before determining availability. |

No published image contains an entered account password, local verification/invitation token or session credential. The visibility test uses a never-authenticated demonstration and publishes only the hidden state. Raw typing logs, automatic failure captures and video remain excluded. This visual review is limited to inspected originals, not a formal accessibility or comprehensive leakage audit.

## Follow-up original observation at aff2323

Run36514868231 attempt1 original `autofill-saved-credential-availability-screen` (SHA256 `60c7a7a6a7037e747036223ce7e58adad6b48d7d98da6df537b1c292e2c83430`) was inspected. The disposable Passwords application is at its empty main list, with All/Passkeys/Codes/Deleted counts0 and a New Password button. No personal account requirement is shown. Saved-credential selection is therefore still pending further supported local interaction, not environment-blocked by the earlier onboarding.

## Passing functional AutoFill candidate031ffd5

All7 original allowlisted images from run36516431533 attempt1 were inspected. Settings remains visibly On. Registration and recovery reach the Arabic account card with submitted credential fields cleared; visible controls do not overlap. The XXXL form retains distinct credential/eye/paste controls and wraps the action labels; the viewport is deliberately scrolled. The secure-only crop and masked final field show no readable entered content, so they are not used to infer visible-text contrast. The next test captures only the never-authenticated demonstration after the existing exact-value assertion to inspect that separate state. The native New Password header shows Cancel/title/Save without publishing its generated password; its fixed label/type inventory is retained separately. The empty Passwords main list is available without an account prompt. Saved selection is still not established by these images.

## MOCK integration originals at031ffd5

All10 named integration images in artifact11011816081 (run36516431563 attempt1) were opened and inspected. Normal Arabic account/verification, directional consent, explicit confirmation, outgoing alert, unknown outcome, device acknowledgment and human response are readable with separate actions in the visible viewport. Cleared or secure fields expose no entered credentials. Acknowledgment explicitly remains separate from human response; the response screenshot still shows an active case. XXXL wraps the title/card and consent label across lines without overlap; the acceptance action extends below the viewport and requires scrolling. The large-text journey later failed during navigation, so these screenshots do not certify full navigation or logout. Original image hashes/export IDs are in evidence/integration-031ffd5/result.json and the delivery screenshot provenance.
