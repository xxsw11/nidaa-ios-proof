# Original screenshot review

Reviewed original exported PNGs from run36513217922 and run36513218045, attempt1, source3759e291e963dced98b41d6d04102f0ac56dd4e7. These are failed-candidate observations, not successful journey evidence. File hashes and original XCTest export names are in the corresponding evidence/result.json and delivered Screenshots/provenance.json. Images were viewed, not inferred from filenames or generated as previews.

| Original named attachment | Observed result | Limit |
|---|---|---|
| disposable-simulator-autofill-passwords-and-passkeys-on | Native Settings switch visibly green/On; matches setup assertion. | Enables the fixture; does not establish saved-credential selection. |
| integration-mock-01-auth-rtl | Dark Arabic account form, visible MOCK explanation, empty credential field and separate eye/paste buttons. No overlap in the visible viewport. | Before input; cannot establish draft retention or keyboard behavior. |
| integration-mock-09-large-arabic-auth | Accessibility XXXL text wraps within the card; heading and MOCK explanation remain readable. | Initial scroll position contains explanation only; credential controls below the viewport still need journey verification. |
| integration-mock-autofill-enabled-recovery-complete-mock | Arabic account card after recovery/password update, empty password field and readable controls. | This one test passed; network is MOCK. The naturally scrolled top edge is not a claim that the full screen is visible. |
| autofill-saved-credential-availability-screen | Disposable Passwords app shows its Notifications onboarding and Continue button. | This is not an iCloud/passcode requirement. The next candidate advances this observed step before determining availability. |

No published image contains an entered account password, local verification/invitation token or session credential. These historical visibility images show only the hidden never-authenticated demonstration. The separately inspected d6 visible demonstration crop is recorded below; it contains no credential ever used to authenticate. Raw typing logs, automatic failure captures and video remain excluded. This visual review is limited to inspected originals, not a formal accessibility or comprehensive leakage audit.

## Follow-up original observation at aff2323

Run36514868231 attempt1 original `autofill-saved-credential-availability-screen` (SHA256 `60c7a7a6a7037e747036223ce7e58adad6b48d7d98da6df537b1c292e2c83430`) was inspected. The disposable Passwords application is at its empty main list, with All/Passkeys/Codes/Deleted counts0 and a New Password button. No personal account requirement is shown. At that checkpoint saved selection was not established; the earlier onboarding did not prove an environment blocker.

## Passing functional AutoFill candidate031ffd5

All7 original allowlisted images from run36516431533 attempt1 were inspected. Settings remains visibly On. Registration and recovery reach the Arabic account card with submitted credential fields cleared; visible controls do not overlap. The XXXL form retains distinct credential/eye/paste controls and wraps the action labels; the viewport is deliberately scrolled. The secure-only crop and masked final field show no readable entered content, so they are not used to infer visible-text contrast. The later d6 test captures only the never-authenticated demonstration after the exact-value assertion; its visible-state inspection is recorded below. The native New Password header shows Cancel/title/Save without publishing its generated password; its fixed label/type inventory is retained separately. The empty Passwords main list is available without an account prompt. Saved selection is still not established by these images.

## MOCK integration originals at031ffd5

All10 named integration images in artifact11011816081 (run36516431563 attempt1) were opened and inspected. Normal Arabic account/verification, directional consent, explicit confirmation, outgoing alert, unknown outcome, device acknowledgment and human response are readable with separate actions in the visible viewport. Cleared or secure fields expose no entered credentials. Acknowledgment explicitly remains separate from human response; the response screenshot still shows an active case. XXXL wraps the title/card and consent label across lines without overlap; the acceptance action extends below the viewport and requires scrolling. The large-text journey later failed during navigation, so these screenshots do not certify full navigation or logout. Original image hashes/export IDs are in evidence/integration-031ffd5/result.json and the delivery screenshot provenance.

## Inspected d6 originals and current limits

The parent reviewer inspected the following original exports at `d6f65ec253f6345e6ae2e368c4b2b8d7baf88681`. Original filenames, hashes and run associations are retained in the workspace inspection ledger `work/native-review-inspected-images/provenance.json`; this records actual viewing, not inferred content.

| Original export | Observed content | Evidence limit |
|---|---|---|
| `4742EE91-FC20-4A45-BB81-4A900C63C7E2.png` and `7E0D9263-6AD7-4E9D-8882-02E29AD3F259.png` | MOCK Arabic authentication and consent originals; full accept/decline buttons are visible without overlap | Run36519447184 passed all8 integration tests, including logout. This is MOCK UI, not real backend reception. |
| `C391655A-60AD-411B-9E0E-F82E9F4F042B.png` (`16-large-text-selection`) | Title and explanation fill the XXXL viewport; recipients are below it; no visible overlap | Explains why waiting for switch hittability before scrolling failed in local-a. The later6a601cbe scroll-fix pass is documented separately below. Local-b passed8/8; local-a passed8/9. |
| `2637FD00-5C8C-4A51-9982-21E153B5195D.png` | White `DEM…` on black in the visible never-authenticated demonstration field; horizontal clipping is consistent with a single-line field | Exact full-value assertion passed; this crop establishes visible text contrast only for the displayed portion. It is not an account password or proof of saved-credential selection. |

The demonstration crop SHA-256 is `b8c966841f6bd73d9790aff812652f84e2093a9c5e71af1bd5b307cd3cc80f46`. All three functional AutoFill cases passed in run36519447212; saved selection failed safe field discovery without an observed personal requirement. Subsequent678d70b and6a601cbe images and outcomes are documented below. No successful native real-backend E2E is claimed.

## Native blank identity crop at678d70b

Original833A1ED9-B20C-44DA-B9B6-23C027713E06.png from run36521436098 attempt1 was viewed. SHA25648e0da69edbf60a3a8e59e718fedae8b1d46f6c51b8dcfa19ab4d66fd5ac332f. It shows the empty **Website or Label** field with a caret and the Passwords icon; the crop ends before the generated-password row and contains no entered credential. It establishes the visible native placeholder, not a successful save or selection. Safe numeric role geometry independently reports both identity fields found.

## Passing XXXL local action at6a601cb

OriginalAFA9368F-5BD7-4E41-AADD-32C76374271F.png from run36522014170 attempt1 was viewed. The settled Arabic XXXL review screen shows the yellow explicit one-time confirmation and the separate cancel button fully visible, with readable wrapped labels and no visible overlap. It is scrolled past preceding explanatory text, not a full-page capture. The actual targeted test subsequently tapped confirmation and retained the alert identifier. This1/1 pass closes the d6 offscreen-readiness failure; it is local simulation with simulated device authentication, not a backend or physical-device result.

## Unresolved saved selection at9a507fe

Original9A479C67-18ED-411D-9050-0500413245AD.png from run36525193498 attempt1 was opened and inspected. SHA256ef9b9fdeb7a3224e30c77eb1f02963a7e27f8fab0d88afc5b14e0ea4e6364e60. The top120-point crop shows the Arabic NIDAA integration-sheet title and yellow Close action. It contains no entered credential. It shows no native picker header within that crop, but does not establish the rest of the screen or picker absence. Selection failed at line147; neither a saved-selection pass nor a personal-account requirement is established.
