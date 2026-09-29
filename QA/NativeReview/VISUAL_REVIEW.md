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
