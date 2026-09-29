import XCTest

/// MOCK networking, actual native input with AutoFill enabled.
final class IntegrationUITests: IntegrationTestCase {
    func testRegistrationRequiresExplicitVerification() {
        launch(); shot("01-auth-rtl")
        fill("integrationEmail", "sara@example.invalid")
        XCTAssertEqual(app.textFields["integrationEmail"].value as? String, "sara@example.invalid", "Fictional email draft changed")
        fill("integrationPassword", "Fictional-Only-29!", secure: true)
        XCTAssertEqual(app.textFields["integrationEmail"].value as? String, "sara@example.invalid", "Fictional email changed while entering password")
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
        launch(extra: ["-nidaa-integration-delayed-logout"], large: true); shot("09-large-arabic-auth"); login(); tap("integrationContactsTab")
        reveal(app.buttons["integrationAcceptInvite"]); shot("10-large-arabic-consent")
        tap("integrationAccountTab"); tap("integrationLogout")
        let busy = app.descendants(matching: .any).matching(identifier: "integrationBusy").firstMatch
        XCTAssertTrue(busy.waitForExistence(timeout: 2), "Delayed logout must still be in progress")
        XCTAssertFalse(app.buttons["integrationAccountTab"].exists, "Old account display must disappear before revocation completes")
        XCTAssertFalse(app.buttons["integrationContactsTab"].exists, "Old contacts must disappear before revocation completes")
        XCTAssertTrue(app.buttons["integrationLogin"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["integrationAlertsTab"].exists)
        XCTAssertFalse(app.staticTexts["integrationAlertState"].exists)
        let completed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: busy)
        XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 12), .completed)
    }
}
