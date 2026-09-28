import XCTest

/// Explicit MOCK UI coverage. Real Swift-to-Auth/PostgreSQL evidence is a separate
/// Linux integration runner; these screenshots never claim Simulator/server E2E.
final class IntegrationUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false }
    private func launch(extra: [String] = [], large: Bool = false) {
        app = XCUIApplication()
        app.launchArguments = ["-nidaa-ui-testing", "-reset-demo", "-nidaa-integration-mock", "-AppleLanguages", "(ar)", "-AppleLocale", "ar_SA"] + extra
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        XCTAssertTrue(app.staticTexts["integrationMode"].waitForExistence(timeout: 12))
        XCTAssertTrue(app.staticTexts["integrationMode"].label.contains("MOCK"))
    }
    private func reveal(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 8))
        for _ in 0..<12 { if element.isHittable { return }; app.swipeUp() }
        for _ in 0..<16 { if element.isHittable { return }; app.swipeDown() }
        XCTAssertTrue(element.isHittable)
    }
    private func tap(_ id: String) { let element = app.buttons[id].firstMatch; reveal(element); element.tap() }
    private func fill(_ id: String, _ value: String, secure: Bool = false) {
        let element = secure ? app.secureTextFields[id] : app.textFields[id]
        reveal(element); element.tap(); element.typeText(value)
        app.swipeUp()
    }
    private func shot(_ name: String) {
        let item = XCTAttachment(screenshot: app.screenshot()); item.name = "integration-mock-" + name; item.lifetime = .keepAlways; add(item)
    }
    private func login() {
        fill("integrationEmail", "sara@example.invalid")
        fill("integrationPassword", "Fictional-Only-29!", secure: true)
        tap("integrationLogin")
        XCTAssertTrue(app.buttons["integrationAccountTab"].waitForExistence(timeout: 8))
    }
    private func selectRecipient() {
        tap("integrationAlertsTab")
        let toggle = app.switches["integrationSelect-00000000-0000-4000-8000-000000000002"]
        reveal(toggle); toggle.tap()
    }
    private func authorize() {
        tap("integrationPrepareCreate")
        let button = app.alerts.buttons["محاكاة النجاح"]
        XCTAssertTrue(button.waitForExistence(timeout: 5)); button.tap()
        XCTAssertTrue(app.buttons["integrationConfirm"].waitForExistence(timeout: 5))
    }
    func testRegistrationRequiresExplicitVerification() {
        launch(); shot("01-auth-rtl")
        fill("integrationEmail", "sara@example.invalid")
        fill("integrationPassword", "Fictional-Only-29!", secure: true)
        tap("integrationSignup")
        XCTAssertTrue(app.staticTexts["integrationAwaitingVerification"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["integrationAccountTab"].exists)
        reveal(app.staticTexts["integrationAwaitingVerification"]); shot("02-awaiting-verification")
        fill("integrationVerificationToken", "MOCK-LOCAL-VERIFICATION", secure: true)
        tap("integrationVerify")
        XCTAssertTrue(app.buttons["integrationAccountTab"].waitForExistence(timeout: 5))
    }
    func testInvitationRequiresDirectionalConsent() {
        launch(); login(); tap("integrationContactsTab")
        let accept = app.buttons["integrationAcceptInvite"]
        reveal(accept); XCTAssertFalse(accept.isEnabled)
        fill("integrationInviteToken", "MOCK-ONLY-FICTIONAL-INVITATION-TOKEN", secure: true)
        reveal(accept); XCTAssertFalse(accept.isEnabled)
        let consent = app.switches["integrationConsentToggle"]; reveal(consent); consent.tap()
        XCTAssertTrue(accept.isEnabled); shot("03-directional-consent")
        accept.tap()
        XCTAssertTrue(app.staticTexts["integrationMessage"].exists)
    }
    func testFreshAuthenticationAndConfirmationNeverAutoSend() {
        launch(); login(); selectRecipient(); tap("integrationPrepareCreate")
        let fail = app.alerts.buttons["محاكاة الفشل"]
        XCTAssertTrue(fail.waitForExistence(timeout: 5)); fail.tap()
        XCTAssertFalse(app.buttons["integrationConfirm"].exists)
        XCTAssertTrue(app.staticTexts["integrationEmptyAlerts"].exists)
        authorize(); reveal(app.buttons["integrationConfirm"]); shot("04-explicit-confirmation")
        tap("integrationCancelConfirm")
        XCTAssertTrue(app.staticTexts["integrationEmptyAlerts"].exists)
        authorize(); tap("integrationConfirm")
        XCTAssertTrue(app.staticTexts["integrationAlertState"].waitForExistence(timeout: 5))
        reveal(app.staticTexts["integrationHumanResponse"].firstMatch); shot("05-shared-outgoing")
        XCTAssertTrue(app.staticTexts["integrationHumanResponse"].firstMatch.label.contains("لا توجد"))
    }
    func testSelectionChangeInvalidatesConfirmation() {
        launch(); login(); selectRecipient(); authorize()
        let toggle = app.switches["integrationSelect-00000000-0000-4000-8000-000000000002"]
        reveal(toggle); toggle.tap()
        XCTAssertFalse(app.buttons["integrationConfirm"].exists)
        XCTAssertTrue(app.staticTexts["integrationEmptyAlerts"].exists)
    }
    func testBackgroundInvalidatesConfirmation() {
        launch(); login(); selectRecipient(); authorize()
        XCUIDevice.shared.press(.home)
        app.activate()
        if !app.buttons["integrationAlertsTab"].exists {
            app.tabBars.buttons["الإعدادات"].tap(); tap("integrationSettings")
        }
        XCTAssertFalse(app.buttons["integrationConfirm"].exists)
        tap("integrationAlertsTab")
        XCTAssertTrue(app.staticTexts["integrationEmptyAlerts"].exists)
    }
    func testUnknownOutcomeQueriesOriginalOperation() {
        launch(extra: ["-nidaa-integration-unknown"]); login(); selectRecipient(); authorize(); tap("integrationConfirm")
        XCTAssertTrue(app.buttons["integrationLookup"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["integrationPrepareCreate"].isEnabled)
        reveal(app.buttons["integrationLookup"]); shot("06-unknown-outcome")
        tap("integrationLookup")
        XCTAssertTrue(app.staticTexts["integrationAlertState"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts.matching(identifier: "integrationAlertState").count, 1)
        XCTAssertFalse(app.buttons["integrationLookup"].exists)
    }
    func testDeviceAcknowledgementDoesNotBecomeHumanResponse() {
        launch(extra: ["-nidaa-integration-incoming"]); login(); tap("integrationAlertsTab")
        tap("integrationAcknowledge"); tap("integrationOpenAlert")
        XCTAssertTrue(app.buttons["integrationRespond"].exists)
        reveal(app.staticTexts["integrationHumanResponse"].firstMatch)
        XCTAssertTrue(app.staticTexts["integrationHumanResponse"].firstMatch.label.contains("لا توجد")); shot("07-acknowledged-not-responded")
        tap("integrationRespond")
        XCTAssertFalse(app.buttons["integrationDeclineResponse"].exists)
        XCTAssertTrue(app.staticTexts["integrationHumanResponse"].firstMatch.label.contains("سأتولى"))
        XCTAssertEqual(app.staticTexts["integrationAlertState"].firstMatch.label, "نداء نشط")
        shot("08-human-response-keeps-case-open")
    }
    func testLargeArabicLayoutAndLogoutIsolation() {
        launch(large: true); shot("09-large-arabic-auth"); login(); tap("integrationContactsTab")
        reveal(app.buttons["integrationAcceptInvite"]); shot("10-large-arabic-consent")
        tap("integrationAccountTab"); tap("integrationLogout")
        XCTAssertTrue(app.buttons["integrationLogin"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["integrationAlertsTab"].exists)
        XCTAssertFalse(app.staticTexts["integrationAlertState"].exists)
    }
}
