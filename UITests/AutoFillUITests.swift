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
        let continueButton = passwords.buttons["Continue"].firstMatch
        if continueButton.waitForExistence(timeout: 5), continueButton.isHittable { continueButton.tap() }
        let candidates = ["Set Up a Passcode", "Turn On iCloud Keychain", "No Passwords", "Welcome to Passwords", "Passwords Are Locked"]
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
        let item = XCTAttachment(string: note + " Saved-credential selection has not executed; manual input/PasteButton tests do not establish AutoFill selection.")
        item.name = "autofill-saved-credential-availability"
        item.lifetime = .keepAlways
        add(item)
        throw XCTSkip(note + " Saved-credential selection remains not tested; no personal account or passcode was requested.")
    }
    func testEnabledManualRegistrationAndFieldNavigation() {
        launch()
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
