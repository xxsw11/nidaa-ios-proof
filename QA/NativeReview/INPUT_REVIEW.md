# Native input and regression review — verification in progress

## Large Arabic navigation fixture

At031ffd5, 7/8 MOCK integration cases passed. `testLargeArabicLayoutAndLogoutIsolation` reached and captured the XXXL consent form, then failed at `IntegrationTestSupport.swift:150` while resolving the scroll-container frame. All eight password readiness records passed their native/binding gates. The retained scroll query was selected by a descendant identifier and could stop matching after that target moved out of the accessibility hierarchy. This is a source-supported query-lifetime hypothesis, not a proven application layout defect or a reason to remove the logout assertion.

Candidate05ab0f selects the visible form scroll surface by stable index, excludes small input scroll views, guards existence and records only fixed control identifiers and numeric geometry on failure. It retains ten directed drags, checks the result after the final drag, and preserves all logout/account-isolation assertions. Execution is required before this candidate is called fixed.

## Enabled-input failure

Sources3759e29 andaff2323 actually enabled the native AutoFill Passwords and Passkeys switch on a newly created disposable iOS18.5 Simulator. Paste/login/recovery passed, but manual account-password entry left registration disabled; visibility of the never-authenticated `DEMO-NOT-A-CREDENTIAL` string did not equal the complete demonstration. The original failed assertions, source locations and run/attempt reports are preserved. Source preparation and Release compilation did not close these failures.

Minimal reproduction: launch Arabic/RTL MOCK integration with AutoFill On, manually enter the fictional email and a password using the UI test's keyboard input, dismiss the keyboard, then inspect the existing registration validation gate. For visibility, enter only the never-authenticated demonstration, refocus the same native field and toggle visibility. Do not submit or publish a displayed account credential.

Theaff2323 candidate avoided reassigning AutoFill traits on every update and captured the bound draft before a secure-visibility transition. It did **not** fix the observed failure. Fixed boolean diagnostics show that the native field and binding were already below the existing validation threshold before keyboard Done. The native responder and ASCII keyboard trait were present, but fewer editing-change events arrived. This narrows the failure; it does not establish whether the system input mode, AutoFill form interpretation or test interaction is responsible. Diagnostic records contain no entered text or lengths.

Candidate031ffd5 separates the password/username step from the one-time-token step. An explicit existing-token action and return action preserve verification after a restart, and clear old sensitive drafts. Tests retain the previous input/visibility assertions and additionally require that password/token fields are never mounted together. Native input-language/key-presence booleans and a crop of only the secure never-authenticated demonstration field provide bounded diagnosis. At031ffd5, run36516431533 attempt1 passed all3 functional AutoFill-On tests with Debug/Release success. Native and bound drafts remain complete enough for validation before/after Done, the exact never-authenticated demonstration survives visibility changes, and focus is retained. This verifies the step-isolation fix for the observed path; it is not a general diagnosis of Apple internals. Saved-credential selection remains separate and is being implemented against the observed native form.

## Saved credential selection

The3759 Passwords probe reached notification onboarding; that did not prove an iCloud requirement or an unsupported environment. Theaff2323 probe completed onboarding, declined notification permission and reached the empty Passwords main list with New Password available. The031 candidate inspects only known field labels/types and a navigation-bar crop before entering any data. A generated password can appear automatically, so full new-entry-form screenshots are excluded.

Follow Apple's documented [iOS18 password creation path](https://support.apple.com/guide/iphone/create-a-password-for-a-website-or-app-iph4ebb320ea/18.0/ios/18.0) and [user-selected saved-password workflow](https://support.apple.com/en-am/guide/iphone/iphf9219d8c9/ios) when the actual controls are established. Selecting Other Passwords is distinct from automatic associated-domain matching; this trial adds no associated-domain entitlement or personal Apple account. A manual/PasteButton pass cannot establish saved-credential selection.

## Contact-deletion test synchronization

At3759e29, local-b repeated the unchanged app/test source and failed `testContactAddEditDeleteAndBlock` at the immediate row-absence assertion after confirmation (7/8 passed). The log records the confirmation tap followed immediately by the accessibility snapshot. The store removes the contact and saves synchronously on the main actor; sheet dismissal and published accessibility state settle separately. No product deletion defect is established by that one snapshot.

The031 candidate retains the absence assertion, adds a bounded predicate wait for the actual row to disappear, rejects a storage-error message, and relaunches without reset. It then verifies that Sara remains absent while Ahmad and the newly created Noor remain. It introduces no blind sleep, retry loop, application bypass or removed assertion. At031ffd5, the deletion/disappearance and non-reset persistence checks passed. Local-b still failed a different test (7/8 overall); this does not make the whole shard green.

## Sara-only alert fixture verification

At031ffd5, `testBothActionsBackgroundDuringAuthenticationAndConsentChanges` failed at the later `receipt-Ahmad` absence assertion (then line157), after the first block/retry scenario. The original job log records that `confirmAction` remained absent and `attemptCount` remained 1. This failure is not evidence that authentication approved a changed action. `prepareAction()` and its consent-change fixture do not add recipients; the alert's original recipient set had not been asserted by the test.

`sendToSara()` previously tapped Ahmad's selection immediately after opening the sheet, without checking switch readiness, state change or the resulting original recipient set. The bounded correction waits for the observed switch to be enabled, hittable and selected, taps exactly once, requires its value to become 0 while Sara remains 1, and asserts Sara present/Ahmad absent on the newly created alert before any follow-up action. The later authorization, attempt-count and recipient-absence assertions remain. There is no retry or product change. This closes a fixture-verification gap; the precise cause of the old switch interaction is not proven by the log, and actual cloud execution is still required.
