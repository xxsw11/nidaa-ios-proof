import XCTest
import UIKit

/// Native input coverage with AutoFill ON. Networking is explicitly MOCK here;
/// saved-credential selection is a separate, not yet verified scenario.
final class AutoFillUITests: IntegrationTestCase {
    func testSavedCredentialEnvironmentProbe() throws {
        // Inspect only the disposable Simulator; never request an Apple account.
        let passwords = XCUIApplication(bundleIdentifier: "com.apple.Passwords")
        passwords.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        passwords.launch()
        defer { passwords.terminate() }
        // Original 3759 evidence reached a second onboarding page, Passwords App
        // Notifications. Finish bounded onboarding and decline the system prompt.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for _ in 0..<4 {
            let deny = springboard.alerts.buttons["Don’t Allow"].firstMatch
            let asciiDeny = springboard.alerts.buttons["Don't Allow"].firstMatch
            if deny.exists && deny.isHittable { deny.tap(); continue }
            if asciiDeny.exists && asciiDeny.isHittable { asciiDeny.tap(); continue }
            let next = passwords.buttons["Continue"].firstMatch
            guard next.waitForExistence(timeout: 3), next.isHittable else { break }
            next.tap()
        }
        let candidates = ["Set Up a Passcode", "Turn On iCloud Keychain", "No Passwords", "Welcome to Passwords", "Passwords Are Locked", "Passwords App Notifications", "All", "New Password"]
        let observed = candidates.filter { passwords.staticTexts[$0].exists || passwords.buttons[$0].exists }
        let note = observed.isEmpty
            ? "No recognized saved-credential setup state was established by the bounded disposable Simulator probe."
            : "Observed disposable Passwords UI: " + observed.joined(separator: ", ") + "."
        // This is a newly created disposable Simulator with no personal account
        // or saved credentials. Inspect the original setup screen before deciding
        // whether a local fictional saved credential can be exercised next.
        let screen = XCTAttachment(screenshot: passwords.screenshot())
        screen.name = "autofill-saved-credential-availability-screen"
        screen.lifetime = .keepAlways
        add(screen)
        let newPassword = passwords.buttons["New Password"].firstMatch
        if newPassword.exists && newPassword.isHittable {
            newPassword.tap()
            let formHeader = passwords.navigationBars["New Password"].firstMatch
            XCTAssertTrue(formHeader.waitForExistence(timeout: 5))
            // The form may propose a plaintext generated password before typing.
            // Retain only the original navigation controls crop, never its fields.
            let formScreen = XCTAttachment(screenshot: formHeader.screenshot())
            formScreen.name = "autofill-saved-credential-new-password-controls-header"
            formScreen.lifetime = .keepAlways
            add(formScreen)
            // This is before typing or saving. Capture only field labels/types,
            // never values (the system may propose a generated password).
            let knownLabels = ["Website", "User Name", "Username", "Password", "Notes", "Save", "Done", "Cancel", "New Password", "example.com"]
            let controls = knownLabels.flatMap { label -> [String] in
                var matches: [String] = []
                if passwords.textFields[label].exists { matches.append("textField:" + label) }
                if passwords.secureTextFields[label].exists { matches.append("secureTextField:" + label) }
                if passwords.buttons[label].exists { matches.append("button:" + label) }
                if passwords.staticTexts[label].exists { matches.append("staticText:" + label) }
                return matches
            }
            let inventory = XCTAttachment(string: "Observed new-password form controls (no values): " + controls.joined(separator: ", "))
            inventory.name = "autofill-saved-credential-form-controls"
            inventory.lifetime = .keepAlways
            add(inventory)
        }
        let item = XCTAttachment(string: note + " Saved-credential selection has not executed; manual input/PasteButton tests do not establish AutoFill selection.")
        item.name = "autofill-saved-credential-availability"
        item.lifetime = .keepAlways
        add(item)
        throw XCTSkip(note + " Saved-credential selection remains not tested; no personal account or passcode was requested.")
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
        XCTAssertTrue(app.keyboards.firstMatch.exists, "Visibility must preserve keyboard focus")
        tap("integrationPasswordVisibility")
        XCTAssertTrue(app.secureTextFields["integrationPassword"].exists)
        dismissKeyboard(after: field)
        // Publish only the hidden state; raw recordings are private and discarded.
        shot("autofill-enabled-large-rtl-hidden-demonstration")
    }
}
