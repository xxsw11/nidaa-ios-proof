import XCTest
import UIKit

/// Native AutoFill is ON for every integration suite, on a disposable Simulator only.
class IntegrationTestCase: XCTestCase {
    func waitIdle() {
        let idle = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.descendants(matching: .any).matching(identifier: "integrationBusy").firstMatch)
        XCTAssertEqual(XCTWaiter.wait(for: [idle], timeout: 15), .completed)
    }
    func paste(_ id: String, value: String) {
        // The runner and application share this disposable Simulator pasteboard.
        // Native PasteButton is the actual user-facing transfer, not an auth hook.
        UIPasteboard.general.setItems([["public.utf8-plain-text": value]], options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(60)])
        let pasteButton = app.buttons[id + "Paste"].firstMatch
        reveal(pasteButton)
        let available = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: pasteButton)
        XCTAssertEqual(XCTWaiter.wait(for: [available], timeout: 5), .completed, "Native PasteButton did not become available")
        tap(id + "Paste")
        // PasteButton loads item providers asynchronously; do not erase its
        // source before that transfer completes. Expiry/tearDown clear it.
        let validationControl = [
            "integrationPassword": "integrationSignup",
            "integrationNewPassword": "integrationUpdatePassword",
            "integrationVerificationToken": "integrationVerify",
            "integrationInviteToken": "integrationDeclineInvite"
        ][id]
        guard let validationControl else { XCTFail("Missing paste validation control"); return }
        // Observe only the existing validation gate, never a secure field value.
        // Callers keep their own assertions and explicit action/consent steps.
        let transferred = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: app.buttons[validationControl].firstMatch)
        XCTAssertEqual(XCTWaiter.wait(for: [transferred], timeout: 5), .completed, "Paste did not update the form validation gate")
    }
    var app: XCUIApplication!
    var isLive = false
    static var autoFillFixtureAttempted = false
    static var autoFillFixtureConfigured = false
    enum FixtureError: Error { case setupFailed(String) }
    override func setUpWithError() throws {
        continueAfterFailure = false
        guard !Self.autoFillFixtureConfigured else { return }
        guard !Self.autoFillFixtureAttempted else {
            throw FixtureError.setupFailed("Disposable Simulator AutoFill setup failed earlier; not retrying or running with an unverified enabled fixture")
        }
        Self.autoFillFixtureAttempted = true
        try configureDisposableSimulatorAutoFill()
        // Only mark the fixture ready after the actual native switch is read on.
        Self.autoFillFixtureConfigured = true
    }
    func configureDisposableSimulatorAutoFill() throws {
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
            let toggle = settings.switches["AutoFillToggle"].firstMatch
            guard toggle.waitForExistence(timeout: 6) else {
                throw FixtureError.setupFailed("AutoFill Passwords and Passkeys switch missing")
            }
            let initial = (toggle.value as? String)?.lowercased()
            guard initial == "0" || initial == "1" || initial == "off" || initial == "on" else {
                throw FixtureError.setupFailed("AutoFill switch state could not be verified")
            }
            if initial == "0" || initial == "off" {
                guard toggle.isHittable else { throw FixtureError.setupFailed("AutoFill switch is not accessible") }
                // Run 36449300225 exposed a row-wide switch frame; its midpoint
                // hits the label. English Settings places the native thumb at
                // the observed trailing edge. Verify On after this one tap.
                toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
            }
            let isOn = XCTNSPredicateExpectation(predicate: NSPredicate { object, _ in
                guard let element = object as? XCUIElement, let value = element.value as? String else { return false }
                return value == "1" || value.lowercased() == "on"
            }, object: toggle)
            guard XCTWaiter.wait(for: [isOn], timeout: 5) == .completed else {
                throw FixtureError.setupFailed("AutoFill remained disabled; enabled fixture is not ready")
            }
            let attachment = XCTAttachment(screenshot: toggle.screenshot())
            attachment.name = "disposable-simulator-autofill-passwords-and-passkeys-on"
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
    func openSettingsRow(_ title: String, in settings: XCUIApplication) throws {
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
        UIPasteboard.general.items = []
        if type(of: self) == IntegrationUITests.self, (testRun?.failureCount ?? 0) > 0, let app, app.state == .runningForeground {
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "integration-mock-failure"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
    func launch(extra: [String] = [], large: Bool = false, live: Bool = false) {
        isLive = live
        app = XCUIApplication()
        app.launchArguments = ["-nidaa-ui-testing", "-reset-demo", live ? "-nidaa-integration-live-ui" : "-nidaa-integration-mock", "-AppleLanguages", "(ar)", "-AppleLocale", "ar_SA"] + extra
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        if live { app.launchEnvironment["NIDAA_LIVE_BASE_URL"] = "http://127.0.0.1:55428" }
        app.launch()
        XCTAssertTrue(app.staticTexts["integrationMode"].waitForExistence(timeout: 12))
        XCTAssertEqual(app.staticTexts["integrationMode"].label.contains("MOCK"), !live)
    }
    func reveal(_ element: XCUIElement) {
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
    func drag(from start: CGPoint, to end: CGPoint) {
        let origin = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
        origin.withOffset(CGVector(dx: start.x, dy: start.y))
            .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: end.x, dy: end.y)))
    }
    func dismissKeyboard(after element: XCUIElement) {
        guard app.keyboards.firstMatch.exists else { return }
        let done = app.buttons["integrationKeyboardDone"].firstMatch
        guard done.waitForExistence(timeout: 5), done.isHittable else {
            XCTFail("Keyboard Done control missing after: \(element.identifier)"); return
        }
        done.tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.keyboards.firstMatch)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 8), .completed,
                       "Keyboard did not dismiss after: \(element.identifier)")
    }
    func tap(_ id: String) {
        let element = app.buttons[id].firstMatch
        reveal(element)
        guard element.isEnabled else { XCTFail("Control is disabled: \(id)"); return }
        element.tap()
    }
    func fill(_ id: String, _ value: String, secure: Bool = false) {
        let element = secure ? app.secureTextFields[id] : app.textFields[id]
        reveal(element); element.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 8), "Keyboard did not appear for input")
        element.typeText(value)
        if !isLive, id == "integrationPassword", value == "DEMO-NOT-A-CREDENTIAL" {
            // Only this never-authenticated demonstration may be captured, and
            // only the secure field crop. No full keyboard/form or real values.
            let fieldImage = XCTAttachment(screenshot: element.screenshot())
            fieldImage.name = "autofill-noncredential-secure-field-crop"
            fieldImage.lifetime = .keepAlways
            add(fieldImage)
        }
        let beforeDone = id == "integrationPassword" ? authDraftReadiness() : nil
        dismissKeyboard(after: element)
        if let beforeDone {
            let attachment = XCTAttachment(string: "before_keyboard_done: \(beforeDone)\nafter_keyboard_done: \(authDraftReadiness())")
            attachment.name = "integration-mock-draft-readiness"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
    func authDraftReadiness() -> String {
        let login = app.buttons["integrationLogin"]
        let signup = app.buttons["integrationSignup"]
        let busy = app.descendants(matching: .any).matching(identifier: "integrationBusy").firstMatch
        let loginExists = login.exists, signupExists = signup.exists
        // UI booleans only: no secure-field value, character count or text dump.
        let diagnostic = app.staticTexts["integrationPasswordDiagnostics"]
        let native = diagnostic.exists ? (diagnostic.value as? String ?? "unavailable") : "unavailable"
        let keyboard = app.keyboards.firstMatch
        let latinKeys = keyboard.keys["f"].exists || keyboard.keys["F"].exists
        let arabicKeys = keyboard.keys["ض"].exists
        let strongCover = app.descendants(matching: .any).matching(identifier: "Automatic Strong Password cover view text").firstMatch.exists
        return "login_exists=\(loginExists), login_enabled=\(loginExists && login.isEnabled), signup_exists=\(signupExists), signup_enabled=\(signupExists && signup.isEnabled), busy=\(busy.exists), latinKeys=\(latinKeys), arabicKeys=\(arabicKeys), strongCover=\(strongCover), native={\(native)}"
    }
    func shot(_ name: String) {
        let item = XCTAttachment(screenshot: app.screenshot()); item.name = (isLive ? "integration-native-real-" : "integration-mock-") + name; item.lifetime = .keepAlways; add(item)
    }
    func login() {
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
    func selectRecipient() {
        tap("integrationAlertsTab")
        let toggle = app.switches["integrationSelect-00000000-0000-4000-8000-000000000002"]
        reveal(toggle); toggle.tap()
    }
    func authorize() {
        tap("integrationPrepareCreate")
        let button = app.alerts.buttons["محاكاة النجاح"]
        XCTAssertTrue(button.waitForExistence(timeout: 5)); button.tap()
        XCTAssertTrue(app.buttons["integrationConfirm"].waitForExistence(timeout: 5))
    }
}
