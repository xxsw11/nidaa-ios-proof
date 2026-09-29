import XCTest
import UIKit

/// Native input coverage with AutoFill ON. Networking is explicitly MOCK here;
/// saved-credential selection is a separate, not yet verified scenario.
final class AutoFillUITests: IntegrationTestCase {
    func testSavedCredentialSelection() throws {
        // Only a new disposable Simulator. The generated system password is
        // never read, changed, copied, published, or sent to a server.
        let passwords = XCUIApplication(bundleIdentifier: "com.apple.Passwords")
        passwords.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        passwords.launch()
        defer { passwords.terminate() }
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for _ in 0..<4 {
            let deny = namedButton(["Don’t Allow", "Don't Allow"], in: springboard)
            if deny.exists && deny.isHittable { deny.tap(); continue }
            let next = passwords.buttons["Continue"].firstMatch
            guard next.waitForExistence(timeout: 3), next.isHittable else { break }
            next.tap()
        }
        try skipOnlyObservedPersonalRequirement(in: [passwords, springboard])
        let create = passwords.buttons["New Password"].firstMatch
        guard create.waitForExistence(timeout: 5), create.isHittable else {
            recordKnownSystemControls(in: passwords, stage: "passwords-home")
            XCTFail("Native New Password control unavailable"); return
        }
        create.tap()
        let header = passwords.navigationBars["New Password"].firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        let headerImage = XCTAttachment(screenshot: header.screenshot())
        headerImage.name = "autofill-saved-credential-new-password-controls-header"
        headerImage.lifetime = .keepAlways; add(headerImage)
        recordKnownSystemControls(in: passwords, stage: "new-password-form")

        let websiteLabels = ["Website or App", "Website", "website", "example.com", "App or Website"]
        let namedWebsite = passwords.textFields.matching(NSPredicate(format: "label IN %@ OR placeholderValue IN %@ OR identifier IN %@", websiteLabels, websiteLabels, websiteLabels)).firstMatch
        let website = namedWebsite.exists ? namedWebsite : websiteFieldAboveUsername(in: passwords, header: header)
        let username = labeledRowTextField("User Name", in: passwords)
        recordEmptyFormGeometry(in: passwords, header: header, website: website, username: username)
        guard website.exists && website.isHittable, username.exists && username.isHittable else {
            XCTFail("Native fictional website/username fields could not be identified safely"); return
        }
        let site = "nidaa-autofill.example.invalid"
        let email = "sara-autofill@example.invalid"
        website.tap(); website.typeText(site)
        username.tap(); username.typeText(email)
        let save = passwords.buttons["Save"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: save)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed)
        save.tap()
        let saved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: header)
        XCTAssertEqual(XCTWaiter.wait(for: [saved], timeout: 8), .completed)
        passwords.terminate()

        launch()
        guard let nativeApp = app else { XCTFail("NIDAA launch fixture is missing"); return }
        let emailField = app.textFields["integrationEmail"]
        reveal(emailField)
        XCTAssertEqual(emailField.value as? String, emailField.placeholderValue)
        XCTAssertFalse(app.buttons["integrationSignup"].isEnabled)
        emailField.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 8))
        let passwordLabels = ["Passwords", "Password AutoFill", "AutoFill Password", "كلمات السر", "كلمات المرور", "تعبئة كلمات السر"]
        var pickerButton = namedButton(passwordLabels, in: app)
        if !pickerButton.exists {
            // The public edit menu is also a user-initiated AutoFill route; no
            // clipboard, keychain injection or credential text typing is used.
            emailField.press(forDuration: 1)
            let autoFill = namedButton(["AutoFill", "تعبئة تلقائية", "تعبئة تلقائية…"], in: app)
            guard autoFill.waitForExistence(timeout: 5), autoFill.isHittable else {
                recordKnownSystemControls(in: app, stage: "autofill-launch")
                XCTFail("Native AutoFill entry control unavailable"); return
            }
            autoFill.tap()
            pickerButton = namedButton(passwordLabels, in: app)
        }
        guard pickerButton.waitForExistence(timeout: 5), pickerButton.isHittable else {
            recordKnownSystemControls(in: app, stage: "password-picker-launch")
            XCTFail("Native Passwords picker control unavailable"); return
        }
        pickerButton.tap()
        try skipOnlyObservedPersonalRequirement(in: [nativeApp, springboard])
        for surface in [nativeApp, springboard] {
            let other = namedButton(["Other Passwords", "Other Passwords…", "كلمات سر أخرى", "كلمات مرور أخرى"], in: surface)
            if other.exists && other.isHittable { other.tap(); break }
        }
        var selected = false
        for surface in [nativeApp, springboard] {
            // Select only the unique fictional account by its nonsecret identity.
            let row = surface.cells.containing(.staticText, identifier: email).firstMatch
            let button = surface.buttons.matching(NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@", email, site)).firstMatch
            let text = surface.staticTexts[email].firstMatch
            let target = row.exists ? row : (button.exists ? button : text)
            if target.waitForExistence(timeout: 5), target.isHittable { target.tap(); selected = true; break }
        }
        guard selected else {
            try skipOnlyObservedPersonalRequirement(in: [nativeApp, springboard])
            recordKnownSystemControls(in: app, stage: "saved-account-selection")
            XCTFail("Fictional saved account not found in native picker"); return
        }
        let emailFilled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", email), object: emailField)
        XCTAssertEqual(XCTWaiter.wait(for: [emailFilled], timeout: 8), .completed)
        let passwordFilled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: app.buttons["integrationSignup"])
        XCTAssertEqual(XCTWaiter.wait(for: [passwordFilled], timeout: 8), .completed, "Saved password did not fill the real validation gate")
        dismissKeyboard(after: emailField)
        tap("integrationLogin")
        XCTAssertTrue(app.buttons["integrationAccountTab"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.secureTextFields["integrationPassword"].exists)
        shot("autofill-saved-credential-selected-mock-login")
    }

    private func namedButton(_ names: [String], in surface: XCUIApplication) -> XCUIElement {
        surface.buttons.matching(NSPredicate(format: "label IN %@ OR identifier IN %@", names, names)).firstMatch
    }
    private func labeledRowTextField(_ label: String, in surface: XCUIApplication) -> XCUIElement {
        let row = surface.cells.containing(.staticText, identifier: label).firstMatch
        if row.exists && row.textFields.count == 1 { return row.textFields.firstMatch }
        if row.exists && row.textViews.count == 1 { return row.textViews.firstMatch }
        let direct = surface.textFields.matching(NSPredicate(format: "label IN %@ OR placeholderValue IN %@", [label, "Username"], [label, "Username"])).firstMatch
        if direct.exists { return direct }
        let title = surface.staticTexts[label].firstMatch
        if title.exists {
            let editable = surface.textFields.allElementsBoundByIndex + surface.textViews.allElementsBoundByIndex
            let sameRow = editable.filter {
                abs($0.frame.midY - title.frame.midY) < max(title.frame.height, 22)
            }
            if sameRow.count == 1 { return sameRow[0] }
        }
        return direct // Absent sentinel; caller fails without guessing a field.
    }
    private func websiteFieldAboveUsername(in surface: XCUIApplication, header: XCUIElement) -> XCUIElement {
        let usernameLabel = surface.staticTexts["User Name"].firstMatch
        let passwordLabel = surface.staticTexts["Password"].firstMatch
        let absent = surface.textFields["NIDAA-absent-native-website-control"]
        guard usernameLabel.exists, passwordLabel.exists,
              usernameLabel.frame.maxY < passwordLabel.frame.minY else { return absent }
        // The observed native form has a User Name row followed by Password.
        // Resolve only a UNIQUE editable site field above User Name and below
        // the form header. Never choose by array index or enter the password row.
        let editable = surface.textFields.allElementsBoundByIndex + surface.textViews.allElementsBoundByIndex
        let candidates = editable.filter {
            $0.exists && $0.isHittable && $0.frame.minY >= header.frame.maxY
                && $0.frame.maxY < usernameLabel.frame.minY
        }
        return candidates.count == 1 ? candidates[0] : absent
    }
    private func recordEmptyFormGeometry(in surface: XCUIApplication, header: XCUIElement, website: XCUIElement, username: XCUIElement) {
        // Fixed role names, numeric frames and booleans only. No labels,
        // placeholders, identifiers, field values or system-generated password.
        var records: [[String: Any]] = []
        for (role, elements) in [("textField", surface.textFields.allElementsBoundByIndex),
                                 ("secureTextField", surface.secureTextFields.allElementsBoundByIndex),
                                 ("textView", surface.textViews.allElementsBoundByIndex)] {
            for field in elements where field.exists {
                let f = field.frame
                records.append(["role": role, "frame": [f.minX, f.minY, f.width, f.height], "hittable": field.isHittable])
            }
        }
        let userLabel = surface.staticTexts["User Name"].firstMatch
        let passwordLabel = surface.staticTexts["Password"].firstMatch
        let report: [String: Any] = ["websiteFound": website.exists, "usernameFound": username.exists,
            "userLabelFound": userLabel.exists, "passwordLabelFound": passwordLabel.exists, "controls": records]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]), let text = String(data: data, encoding: .utf8) {
            let evidence = XCTAttachment(string: text)
            evidence.name = "autofill-native-form-role-geometry"
            evidence.lifetime = .keepAlways; add(evidence)
        }
        // At this point no fixture text has been entered. Crop strictly above
        // Password, with an entire extra row-height margin; fail closed on any
        // unexpected layout. The generated password row is never captured.
        guard userLabel.exists, userLabel.isHittable, passwordLabel.exists, passwordLabel.isHittable,
              userLabel.frame.maxY < passwordLabel.frame.minY else { return }
        let window = surface.windows.firstMatch.frame
        let top = header.frame.maxY
        let bottom = min(userLabel.frame.maxY, passwordLabel.frame.minY - max(passwordLabel.frame.height, 44))
        guard top >= window.minY, bottom > top + 24, bottom < passwordLabel.frame.minY else { return }
        let shot = surface.screenshot().image
        guard let pixels = shot.cgImage else { return }
        let scale = CGFloat(pixels.width) / window.width
        let rect = CGRect(x: 0, y: (top - window.minY) * scale, width: CGFloat(pixels.width), height: (bottom - top) * scale).integral
        guard rect.maxY <= CGFloat(pixels.height), let crop = pixels.cropping(to: rect) else { return }
        let evidence = XCTAttachment(image: UIImage(cgImage: crop))
        evidence.name = "autofill-native-empty-identity-fields-crop"
        evidence.lifetime = .keepAlways; add(evidence)
    }
    private func skipOnlyObservedPersonalRequirement(in surfaces: [XCUIApplication]) throws {
        let requirements = ["Sign In to iCloud", "Sign in to your Apple Account", "Set Up a Passcode", "Enter iPhone Passcode", "تسجيل الدخول إلى iCloud", "إدخال رمز دخول iPhone"]
        for surface in surfaces {
            let observed = requirements.filter { surface.staticTexts[$0].exists || surface.buttons[$0].exists }
            if !observed.isEmpty {
                let note = "Observed personal-account/device-passcode requirement: " + observed.joined(separator: ", ")
                let evidence = XCTAttachment(string: note)
                evidence.name = "autofill-saved-credential-observed-requirement"
                evidence.lifetime = .keepAlways; add(evidence)
                throw XCTSkip(note)
            }
        }
    }
    private func recordKnownSystemControls(in surface: XCUIApplication, stage: String) {
        let labels = ["Website or App", "Website", "App or Website", "User Name", "Username", "Password", "Notes", "Save", "Done", "Cancel", "New Password", "example.com", "Passwords", "Password AutoFill", "AutoFill", "Other Passwords", "Other Passwords…", "كلمات السر", "كلمات المرور", "تعبئة تلقائية", "كلمات سر أخرى"]
        let controls = labels.flatMap { label -> [String] in
            var matches: [String] = []
            if surface.textFields[label].exists { matches.append("textField:" + label) }
            if surface.secureTextFields[label].exists { matches.append("secureTextField:" + label) }
            if surface.buttons[label].exists { matches.append("button:" + label) }
            if surface.staticTexts[label].exists { matches.append("staticText:" + label) }
            return matches
        }
        let inventory = XCTAttachment(string: "stage=" + stage + "; fixed controls (no values): " + controls.joined(separator: ", "))
        inventory.name = "autofill-saved-credential-form-controls-" + stage
        inventory.lifetime = .keepAlways; add(inventory)
    }
    func testEnabledManualRegistrationAndFieldNavigation() {
        launch()
        XCTAssertFalse(app.secureTextFields["integrationVerificationToken"].exists, "Credential and verification steps must not mount together")
        tap("integrationExistingToken")
        XCTAssertTrue(app.secureTextFields["integrationVerificationToken"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.secureTextFields["integrationPassword"].exists)
        tap("integrationBackToCredentials")
        XCTAssertTrue(app.secureTextFields["integrationPassword"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.secureTextFields["integrationVerificationToken"].exists)
        fill("integrationEmail", "sara@example.invalid")
        fill("integrationPassword", "Fictional-Only-29!", secure: true)
        XCTAssertTrue(app.buttons["integrationSignup"].isEnabled)
        let email = app.textFields["integrationEmail"]
        reveal(email); email.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        dismissKeyboard(after: email)
        XCTAssertTrue(app.buttons["integrationSignup"].isEnabled, "Navigating fields must retain the password")
        tap("integrationSignup")
        XCTAssertTrue(app.staticTexts["integrationAwaitingVerification"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.secureTextFields["integrationPassword"].exists)
        XCTAssertFalse(app.buttons["integrationAccountTab"].exists)
        fill("integrationVerificationToken", "MOCK-LOCAL-VERIFICATION", secure: true)
        tap("integrationVerify")
        XCTAssertTrue(app.buttons["integrationAccountTab"].waitForExistence(timeout: 8))
        shot("autofill-enabled-registration-complete-mock")
    }

    func testEnabledPasteLoginAndRecovery() {
        launch()
        fill("integrationEmail", "sara@example.invalid")
        paste("integrationPassword", value: "Fictional-Only-29!")
        XCTAssertTrue(app.buttons["integrationSignup"].isEnabled)
        tap("integrationLogin")
        XCTAssertTrue(app.buttons["integrationAccountTab"].waitForExistence(timeout: 8))
        tap("integrationLogout")
        waitIdle()
        fill("integrationEmail", "sara@example.invalid")
        tap("integrationRecover")
        XCTAssertTrue(app.staticTexts["integrationAwaitingVerification"].waitForExistence(timeout: 8))
        paste("integrationVerificationToken", value: "MOCK-RECOVERY-TOKEN")
        tap("integrationVerify")
        XCTAssertTrue(app.buttons["integrationAccountTab"].waitForExistence(timeout: 8))
        fill("integrationNewPassword", "Another-Fictional-42!", secure: true)
        tap("integrationUpdatePassword")
        waitIdle()
        XCTAssertTrue(app.staticTexts["integrationMessage"].label.contains("تحديث كلمة المرور"))
        shot("autofill-enabled-recovery-complete-mock")
    }

    func testEnabledVisibilityUsesOnlyNonCredentialDemonstration() {
        launch(large: true)
        XCTAssertFalse(app.secureTextFields["integrationVerificationToken"].exists)
        // This string is never used to authenticate, register or sent to a service.
        let demonstration = "DEMO-NOT-A-CREDENTIAL"
        fill("integrationPassword", demonstration, secure: true)
        let field = app.secureTextFields["integrationPassword"]
        reveal(field); field.tap()
        tap("integrationPasswordVisibility")
        XCTAssertTrue(app.textFields["integrationPassword"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["integrationPassword"].value as? String, demonstration)
        // This guard allows only the exact never-authenticated demonstration,
        // even if a future harness changes continueAfterFailure behavior.
        guard app.textFields["integrationPassword"].value as? String == demonstration else { return }
        let visibleCrop = XCTAttachment(screenshot: app.textFields["integrationPassword"].screenshot())
        visibleCrop.name = "autofill-noncredential-visible-field-crop"
        visibleCrop.lifetime = .keepAlways
        add(visibleCrop)
        XCTAssertTrue(app.keyboards.firstMatch.exists, "Visibility must preserve keyboard focus")
        tap("integrationPasswordVisibility")
        XCTAssertTrue(app.secureTextFields["integrationPassword"].exists)
        dismissKeyboard(after: field)
        // Publish only the hidden state; raw recordings are private and discarded.
        shot("autofill-enabled-large-rtl-hidden-demonstration")
    }
}
