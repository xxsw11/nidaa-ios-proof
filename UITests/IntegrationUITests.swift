import XCTest

/// Explicit MOCK UI coverage. Real Swift-to-Auth/PostgreSQL evidence is a separate
/// Linux integration runner; these screenshots never claim Simulator/server E2E.
final class IntegrationUITests: XCTestCase {
    private var app: XCUIApplication!
    private static var autoFillFixtureAttempted = false
    private static var autoFillFixtureConfigured = false
    private enum FixtureError: Error { case setupFailed(String) }
    override func setUpWithError() throws {
        continueAfterFailure = false
        guard !Self.autoFillFixtureConfigured else { return }
        guard !Self.autoFillFixtureAttempted else {
            throw FixtureError.setupFailed("Disposable Simulator AutoFill setup failed earlier; not retrying or running with an unverified fixture")
        }
        Self.autoFillFixtureAttempted = true
        try configureDisposableSimulatorAutoFill()
        // Only mark the fixture ready after the actual native switch is read off.
        Self.autoFillFixtureConfigured = true
    }
    private func configureDisposableSimulatorAutoFill() throws {
        #if targetEnvironment(simulator)
        guard ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"]?.hasPrefix("NIDAA-Disposable-") == true else {
            throw FixtureError.setupFailed("AutoFill fixture requires the disposable Simulator created by Scripts/ci_simulator.sh")
        }
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        defer { settings.terminate() }
        do {
            settings.launch()
            guard settings.navigationBars.firstMatch.waitForExistence(timeout: 12) else {
                throw FixtureError.setupFailed("Native Settings did not open")
            }
            try openSettingsRow("General", in: settings)
            try openSettingsRow("AutoFill & Passwords", in: settings)
            let toggle = settings.switches["AutoFill Passwords and Passkeys"].firstMatch
            guard toggle.waitForExistence(timeout: 6) else {
                throw FixtureError.setupFailed("AutoFill Passwords and Passkeys switch missing")
            }
            let initial = (toggle.value as? String)?.lowercased()
            guard initial == "0" || initial == "1" || initial == "off" || initial == "on" else {
                throw FixtureError.setupFailed("AutoFill switch state could not be verified")
            }
            if initial == "1" || initial == "on" {
                guard toggle.isHittable else { throw FixtureError.setupFailed("AutoFill switch is not accessible") }
                toggle.tap()
            }
            let isOff = XCTNSPredicateExpectation(predicate: NSPredicate { object, _ in
                guard let element = object as? XCUIElement, let value = element.value as? String else { return false }
                return value == "0" || value.lowercased() == "off"
            }, object: toggle)
            guard XCTWaiter.wait(for: [isOff], timeout: 5) == .completed else {
                throw FixtureError.setupFailed("AutoFill remained enabled; manual-typing fixture is not ready")
            }
            let attachment = XCTAttachment(screenshot: toggle.screenshot())
            attachment.name = "disposable-simulator-autofill-passwords-and-passkeys-off"
            attachment.lifetime = .keepAlways
            add(attachment)
        } catch {
            // This runs before the NIDAA app is initialized, so preserve separate
            // fixture evidence instead of relying on the app's tearDown capture.
            if settings.state == .runningForeground {
                let attachment = XCTAttachment(screenshot: settings.screenshot())
                attachment.name = "disposable-simulator-autofill-fixture-failure"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
            throw error
        }
        #else
        throw FixtureError.setupFailed("Settings fixture is restricted to iOS Simulator; physical-device settings must not be changed")
        #endif
    }
    private func openSettingsRow(_ title: String, in settings: XCUIApplication) throws {
        for _ in 0..<8 {
            let button = settings.buttons[title].firstMatch
            let cell = settings.cells.containing(.staticText, identifier: title).firstMatch
            let text = settings.staticTexts[title].firstMatch
            let target = button.exists ? button : (cell.exists ? cell : text)
            if target.exists && target.isHittable { target.tap(); return }
            let scroll: XCUIElement
            if settings.scrollViews.firstMatch.exists { scroll = settings.scrollViews.firstMatch }
            else if settings.tables.firstMatch.exists { scroll = settings.tables.firstMatch }
            else if settings.collectionViews.firstMatch.exists { scroll = settings.collectionViews.firstMatch }
            else { throw FixtureError.setupFailed("Native Settings scroll container missing") }
            if target.exists && target.frame.midY < settings.windows.firstMatch.frame.midY { scroll.swipeDown() }
            else { scroll.swipeUp() }
        }
        throw FixtureError.setupFailed("Native Settings row unavailable after bounded discovery: " + title)
    }
    override func tearDownWithError() throws {
        if (testRun?.failureCount ?? 0) > 0, let app, app.state == .runningForeground {
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "integration-mock-failure"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
    private func launch(extra: [String] = [], large: Bool = false) {
        app = XCUIApplication()
        app.launchArguments = ["-nidaa-ui-testing", "-reset-demo", "-nidaa-integration-mock", "-AppleLanguages", "(ar)", "-AppleLocale", "ar_SA"] + extra
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        XCTAssertTrue(app.staticTexts["integrationMode"].waitForExistence(timeout: 12))
        XCTAssertTrue(app.staticTexts["integrationMode"].label.contains("MOCK"))
    }
    private func reveal(_ element: XCUIElement) {
        guard element.waitForExistence(timeout: 8) else {
            XCTFail("Missing control: \(element.identifier)"); return
        }
        let containingScroll = app.scrollViews.containing(.any, identifier: element.identifier).firstMatch
        let scroll = containingScroll.exists ? containingScroll : app.scrollViews.firstMatch
        guard scroll.exists else { XCTFail("No scroll container for: \(element.identifier)"); return }
        for _ in 0..<10 {
            if element.isHittable { return }
            let viewport = scroll.frame.intersection(app.windows.firstMatch.frame)
            guard !viewport.isNull, viewport.height > 80 else {
                XCTFail("Invalid viewport for: \(element.identifier)"); return
            }
            // Use geometry, not a fixed search order: controls above the viewport
            // require a downward drag; controls below it require an upward drag.
            let above = element.frame.midY < viewport.midY
            let x = viewport.midX
            let upper = viewport.minY + viewport.height * 0.25
            let lower = viewport.minY + viewport.height * 0.75
            drag(from: CGPoint(x: x, y: above ? upper : lower), to: CGPoint(x: x, y: above ? lower : upper))
        }
        // Identifiers and geometry only. Never include field values, labels,
        // accessibility dumps, credentials or invitation/verification tokens.
        XCTFail("Control not hittable after 10 directed scrolls: \(element.identifier); frame=\(element.frame); scroll=\(scroll.frame)")
    }
    private func drag(from start: CGPoint, to end: CGPoint) {
        let origin = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
        origin.withOffset(CGVector(dx: start.x, dy: start.y))
            .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: end.x, dy: end.y)))
    }
    private func dismissKeyboard(after element: XCUIElement) {
        guard app.keyboards.firstMatch.exists else { return }
        let done = app.buttons["integrationKeyboardDone"]
        guard done.waitForExistence(timeout: 5), done.isHittable else {
            XCTFail("Keyboard Done control missing after: \(element.identifier)"); return
        }
        done.tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.keyboards.firstMatch)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 3), .completed,
                       "Keyboard did not dismiss after: \(element.identifier)")
    }
    private func tap(_ id: String) {
        let element = app.buttons[id].firstMatch
        reveal(element)
        guard element.isEnabled else { XCTFail("Control is disabled: \(id)"); return }
        element.tap()
    }
    private func fill(_ id: String, _ value: String, secure: Bool = false) {
        let element = secure ? app.secureTextFields[id] : app.textFields[id]
        reveal(element); element.tap(); element.typeText(value)
        let beforeDone = id == "integrationPassword" ? authDraftReadiness() : nil
        dismissKeyboard(after: element)
        if let beforeDone {
            let attachment = XCTAttachment(string: "before_keyboard_done: \(beforeDone)\nafter_keyboard_done: \(authDraftReadiness())")
            attachment.name = "integration-mock-draft-readiness"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
    private func authDraftReadiness() -> String {
        let login = app.buttons["integrationLogin"]
        let signup = app.buttons["integrationSignup"]
        let busy = app.descendants(matching: .any).matching(identifier: "integrationBusy").firstMatch
        let loginExists = login.exists, signupExists = signup.exists
        // UI booleans only: no secure-field value, character count or text dump.
        return "login_exists=\(loginExists), login_enabled=\(loginExists && login.isEnabled), signup_exists=\(signupExists), signup_enabled=\(signupExists && signup.isEnabled), busy=\(busy.exists)"
    }
    private func shot(_ name: String) {
        let item = XCTAttachment(screenshot: app.screenshot()); item.name = "integration-mock-" + name; item.lifetime = .keepAlways; add(item)
    }
    private func login() {
        fill("integrationEmail", "sara@example.invalid")
        XCTAssertEqual(app.textFields["integrationEmail"].value as? String, "sara@example.invalid", "Fictional email draft changed")
        fill("integrationPassword", "Fictional-Only-29!", secure: true)
        XCTAssertEqual(app.textFields["integrationEmail"].value as? String, "sara@example.invalid", "Fictional email changed while entering password")
        // Signup requires at least eight password characters. This checks draft
        // retention without reading or logging a secure field's value.
        XCTAssertTrue(app.buttons["integrationSignup"].isEnabled, "Password draft did not survive keyboard dismissal")
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
