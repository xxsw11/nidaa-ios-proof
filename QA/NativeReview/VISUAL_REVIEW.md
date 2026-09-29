# Original screenshot review

The staged acceptance-image ledger at `work/native-acceptance-inspected-images/provenance.json` contains 27 inspected images: 15 earlier historical images, three from 0432, three from d050, and six from the current e6b7 source. The six current images are three MOCK originals inspected by both reviewers, one additional pre-transition XXXL MOCK original inspected by the parent reviewer, and two native Settings toggle crops inspected by the parent reviewer. Hashes identify the actual original or previously privacy-redacted bytes. These are staged files, not a claim that a v02 delivery package already exists. Existing historical files remain unchanged. Each source-specific section retains its own outcome and limits; current MOCK has a logout-navigation failure and the safe journey images do not override it.

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

## Historical full observed surfaces and 9127 images

Three full redacted picker captures at4bb8b12 and three at053de1c were inspected with complete sanitized AX trees, followed by two available full captures at9494c13. They show the keyboard before the Passwords tap, its disappearance while the NIDAA form remains visible, and its return where a failure capture exists. No stable saved-account list or personal-account prompt was observed. The missing9494 failure capture is not invented.

At9127b89, all four encrypted images below were decrypted, opened, inspected for secrets and admitted to the staged inspection ledger. The full screen is preserved, with documented privacy masks on the three picker images; the full Settings image is an inspected unmodified original. Raw encrypted bundles and logs do not enter delivery.

| Inspected image | Actual observation | Limit |
|---|---|---|
| `9127b89-autofill-native-provider-settings-screen.png` | Global AutoFill and Passwords provider visibly On | AX did not expose the provider toggle value; this visual observation closes that uncertainty only |
| `9127b89-autofill-native-picker-full-screen-redacted-before-tap.png` | Empty NIDAA form, keyboard and Passwords accessory | Before system transition; not successful selection |
| `9127b89-autofill-native-picker-full-screen-redacted-after-tap.png` | Keyboard hidden, blank NIDAA form remains, no stable chooser | Exact observed moment; system log is needed to diagnose the transient service |
| `9127b89-autofill-native-picker-full-screen-redacted-selection-failure.png` | Keyboard/accessory returns; no saved credential inserted | Saved-selection test failed, not skipped |

Three original MOCK images from the same frozen source were also opened: directional consent, unknown outcome, and human response with the case still open. Their Arabic controls are readable in the captured viewport; the unknown outcome stays explicit and a human response does not automatically close the case. These are MOCK interface observations, not native real-backend reception or APNs evidence. All 15 initial historical images contain only fictional demonstration information or sanitized empty/system surfaces; none contains an account password or verification token. These remain historical evidence, not images from the current 0432 source.


## Historical 0432 MOCK originals

Three original 1206 × 2622 PNGs were opened and inspected by the UI reviewer and re-viewed by the parent reviewer. Source: `0432a8b58953dfd1e2cc85667d29a1881a6b8672`, tree `05d6318b61883155058a4f1192189a2c25a917c6`, run `36581107824`, attempt 1, artifact `11040382694` (`nidaa-simulator-47-1-integration`). The downloaded artifact SHA-256 was verified as `f3cf1b8b467a35adf60fe9d7cd2eaab3bd5755c101b281d4710e861a40ffc373`. The matching source record and all eight MOCK test cases passed, with zero failures or skips; Debug and Release succeeded. See `evidence/unified-0432a8b/mock.json`. The historical 710 MOCK failure remains recorded separately and is not replaced by this pass.

| Current inspected image | Original XCTest export | Actual observation |
|---|---|---|
| `0432a8b-integration-mock-03-directional-consent.png` | `A685F2B4-74A8-4421-B5A6-D80F7D0BF2FC.png` | Readable Arabic RTL consent toggle and explicit acceptance; direction is stated and the account is marked fictional. |
| `0432a8b-integration-mock-06-unknown-outcome.png` | `2CE57370-90C6-4D5B-B625-F91A738E8F5E.png` | Unknown outcome is explicit, lookup uses the existing operation, and a new send remains disabled. |
| `0432a8b-integration-mock-08-human-response-keeps-case-open.png` | `F34195B2-1CA1-49C7-9964-2EEBE7648134.png` | Fictional Sami/Sara labels; simulated service acceptance, application acknowledgment, opening, and human response remain distinct. The case remains active. |

Verified SHA-256 hashes of the inspected image bytes:

- `0432a8b-integration-mock-03-directional-consent.png`: `0d23ca06fc13a2c5157851745cc566545bc9c6e3265e2519c10ec75dc9e21f6e`.
- `0432a8b-integration-mock-06-unknown-outcome.png`: `c8fe1701d2a13abcd7edc60dea2a3d81bb133364304d18823d3757da7d76269b`.
- `0432a8b-integration-mock-08-human-response-keeps-case-open.png`: `048850d1872bf5af3a30fffd277bef4aae6b511ce7c46488e3d6eba5e60c221a`.

No entered password, verification token, invitation token, or session credential was visible in these originals. The controls are readable in their captured viewports; this does not establish unseen content or a complete accessibility audit. These are MOCK interface observations, not real backend reception, APNs delivery, or physical-device validation.

The three 0432 entries were appended to the ledger; all 15 historical image files and their existing provenance entries were preserved. Later saved-picker diagnostics, including `4c473ee` and `8d`, export sanitized JSON only. No new saved-picker screenshot or visual success is claimed from those runs.


## Historical d050 MOCK observations and failed suite

Source `d0502cb75f032b0771d3a3f6ed048807b32a8b2b`, run `36588386114`, attempt 1, artifact `11043289396`, verified artifact SHA-256 `2e93252efe8dd28e2b5e44eb410da98b8dce39bb05ab91c8413efdb65ac5aa0f`: three original consent/unknown-outcome/human-response images were opened and inspected. They preserve readable Arabic RTL controls, explicit directional consent, same-operation lookup with creation disabled, and an active case after human response. All three individual tests passed. The suite result was **7 passed, 1 failed, 0 skipped**; the large-Arabic logout journey failed when the target disappeared after a drag. Its actual failure screenshot was not part of the safe export and was not inspected. Neither these images nor earlier passing runs establish that logout succeeded.

## Current e6b7 original observations

Source `e6b7ffdbd76ba44c576078eebb07bd6614fa8844`, tree `51ec15ee4644aac9f4c9d1ae05c592ac48709b0f`. The UI reviewer opened the three original MOCK PNGs from run `36592111986`, attempt 1, artifact `11044574162`; verified artifact SHA-256 `28bbfa8aeb477a5fb8e31d62cc6470638efdc4fff24733ccd292fd762fb1b8ec`. The same three individual consent/unknown-outcome/human-response tests passed, with the observed controls and state distinctions described above. No entered credential or token was visible.

The current MOCK suite is **7 passed, 1 failed, 0 skipped**, with Release successful. Large-Arabic logout exhausted the existing ten-drag bound at `IntegrationTestSupport.swift:230`. Safe presence telemetry records the target absent after one drag while the app remained foreground and the scroll/window remained present. This proves that the recovery branch was exercised, but it did not recover the control or complete logout. Only the initial offscreen target geometry was available; the cause of its continued absence is unresolved. The actual failure screenshot was not exported or inspected. See `evidence/unified-e6b7ffd/mock.json`; these inspected successful subjourney images are not a full-suite pass or a failure-screen reconstruction.

The parent reviewer also opened the original global AutoFill and Passwords-provider toggle crops from run `36592112080`, attempt 1, artifact `11045490449`; verified artifact SHA-256 `7e80f7a469431c67dfa0d0e8f574b806534fec0091ba8b0fb9ddebca7396abca`. Both toggles are visibly green/On. These are crops verifying native settings only, not full-screen captures or evidence of saved selection. The independently measured saved-selection result belongs to its JSON test record; no saved-picker image is invented.

### Original image provenance added after 0432

- `d0502cb-integration-mock-03-directional-consent.png` — original export `E5922B16-BB24-4791-8DBC-4A964BAF42E7.png`, run `36588386114`, artifact `11043289396`; image SHA-256 `c8e1e1d933eb4883e388be707ef26641fc2de43df10b20d1e094a09ca6053e15`.
- `d0502cb-integration-mock-06-unknown-outcome.png` — original export `648341E3-85B2-46FE-8065-4304D6E59143.png`, run `36588386114`, artifact `11043289396`; image SHA-256 `9c7bce662c14d9d4ad671eb1ee06ab2cbc053546e8d91c9939e07bc82e087ed4`.
- `d0502cb-integration-mock-08-human-response-keeps-case-open.png` — original export `C25C7868-7D6C-464D-A439-E7615F0C8499.png`, run `36588386114`, artifact `11043289396`; image SHA-256 `9f8ab1dc7f44b3603ff31a07a26359d59069b3db6a3eed58d6c0e46618f66ded`.
- `e6b7ffd-disposable-simulator-autofill-passwords-and-passkeys-on.png` — original export `6123981E-374B-4293-9C10-C2D2E8E21FB6.png`, run `36592112080`, artifact `11045490449`; image SHA-256 `ad349b1f6fe49b49c07c2fbf94fbe8a2177d769bfd05b615f1c425d57a82e9ec`.
- `e6b7ffd-autofill-native-provider-row.png` — original export `AD4A716F-8B49-4E05-A842-DBAF4C2DC810.png`, run `36592112080`, artifact `11045490449`; image SHA-256 `f0d12dfedb507db96d0f35b2e36d088f5b095d6600849328f9481b61904aaa8b`.
- `e6b7ffd-integration-mock-03-directional-consent.png` — original export `62C9F9D1-F15F-4FDA-BE02-4A87767F6681.png`, run `36592111986`, artifact `11044574162`; image SHA-256 `c2ce00dbe8508424f20b5cd9bd5a14c45c7ca52cc2c045a81f65b8fde15cd71e`.
- `e6b7ffd-integration-mock-06-unknown-outcome.png` — original export `4EF6FA55-6652-478B-B129-846F246326EE.png`, run `36592111986`, artifact `11044574162`; image SHA-256 `6436e2eaed0c08a7d46a8242a727be830117f457a80e9b78d47f9de63fea35dd`.
- `e6b7ffd-integration-mock-08-human-response-keeps-case-open.png` — original export `854737A6-5C2B-43CF-9415-9DB1EAD518E1.png`, run `36592111986`, artifact `11044574162`; image SHA-256 `73d259fa70b99a9d0df9dbf14622363cfbd531762b7e00451279c3369f3b4a6c`.

All 27 ledger entries represent images actually inspected by the identified reviewer. The preceding 21 files and entries were preserved when the six e6 images were added. Raw XCTest logs, automatic failure screenshots and recordings are not included. The review establishes only the visible portions of these originals, not physical-device behavior, APNs delivery, native real-backend E2E or a comprehensive accessibility audit.


The parent reviewer additionally inspected `e6b7ffd-integration-mock-10-large-arabic-consent.png`, original export `6EC48400-3212-4D01-826B-6ED7ABE06744.png`, SHA-256 `572fc6be7f87c2e57c8fff14f512817109ac55a17f36f0ba10bc1bc8fd12bd7c`, from the same e6 MOCK run/artifact above. It shows the large-Arabic failing test **before** navigation to account/logout: a wrapped consent label, empty token placeholder, switch Off and disabled acceptance action partly visible at the bottom. The consent heading is clipped at the top by the current scroll position. No secret is visible. This original is not the failure moment or the logout screen and does not establish why the later target disappeared. The prior 26 files and entries were preserved when this image was appended.


The later navigation diagnostics `af8019cc9d8237fd83c9c4e942cf5779257db21a` (run36596361949) and `2580c228e7f4844485fb10e147be8634619827cb` (run36620786727) each passed eight MOCK cases without reproducing the missing-target condition. Their inspected evidence for navigation is structured, sanitized checkpoint data, not newly admitted screenshots. The first2580 checkpoint intentionally has no snapshot and cannot establish absence. No image was added from either diagnostic: this visual ledger remains **27 inspected images**, and neither diagnostic erases the frozen e6 large-Arabic/logout failure or proves its cause.
