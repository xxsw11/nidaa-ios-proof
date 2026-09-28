import XCTest

final class LocalExperienceUITests: XCTestCase {
    var app: XCUIApplication!
    let sara = "00000000-0000-4000-8000-000000000001"
    override func setUpWithError() throws { continueAfterFailure = false }
    func launch(_ auth: String = "success", reset: Bool = true, large: Bool = false) {
        app = XCUIApplication();app.launchArguments = ["-nidaa-ui-testing", "-AppleLanguages", "(ar)", "-AppleLocale", "ar_SA"]
        if reset { app.launchArguments.append("-reset-demo") }
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launchEnvironment["NIDAA_TEST_AUTH"] = auth;app.launch()
        XCTAssertTrue(app.buttons["startAlert"].waitForExistence(timeout: 10))
    }
    func tap(_ id: String) {
        let element = app.buttons[id].firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 6),id)
        for _ in 0..<10 { if element.isHittable { break };app.swipeUp() }
        XCTAssertTrue(element.isHittable,id);element.tap()
    }
    func tab(_ name: String) { app.tabBars.buttons[name].tap() }
    func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot());attachment.name = name;attachment.lifetime = .keepAlways;add(attachment)
    }
    func begin() { tap("startAlert");tap("authenticateSend");XCTAssertTrue(app.buttons["confirmAlert"].waitForExistence(timeout: 6)) }
    func send() { begin();tap("confirmAlert");XCTAssertTrue(app.staticTexts["alertState"].waitForExistence(timeout: 6)) }
    func testCompleteLocalAlertJourney() {
        launch();shot("01-home");tap("startAlert");shot("02-selection");tap("authenticateSend");shot("03-confirmation");tap("confirmAlert");shot("04-outgoing")
        tap("receipt-"+sara);tap("openRecipient-"+sara);shot("05-incoming")
        XCTAssertTrue(app.buttons["acceptResponse"].exists);XCTAssertFalse(app.staticTexts["قبولك لا يغلق الحالة. أكمل المتابعة ثم أنهِ الحالة صراحةً."].exists)
        tap("incomingSilence");XCTAssertTrue(app.buttons["acceptResponse"].exists)
        tap("acceptResponse");shot("06-human-response");tap("incomingDetails");tap("resolveAlert");tap("confirmCloseAlert")
        XCTAssertTrue(app.staticTexts["انتهت الحالة بتأكيد صريح"].firstMatch.waitForExistence(timeout: 5));shot("07-resolved")
        tap("closeScreen");tab("السجل");shot("08-history")
        XCTAssertFalse(app.staticTexts["emptyHistory"].exists)
    }
    func testAuthenticationFailureAndCancellationNeverCreate() {
        for outcome in ["failure","cancel"] {
            launch(outcome);tap("startAlert");tap("authenticateSend")
            XCTAssertTrue(app.staticTexts["sendMessage"].waitForExistence(timeout: 5));XCTAssertFalse(app.buttons["confirmAlert"].exists)
            tap("closeScreen");tab("السجل");XCTAssertTrue(app.staticTexts["emptyHistory"].exists);app.terminate()
        }
    }
    func testBackgroundInvalidatesPendingAuthentication() {
        launch("delayed");tap("startAlert");tap("authenticateSend");XCUIDevice.shared.press(.home)
        sleep(5);app.activate();XCTAssertFalse(app.buttons["confirmAlert"].exists)
        tab("السجل");XCTAssertTrue(app.staticTexts["emptyHistory"].exists)
    }
    func testCancelConfirmationDoesNotCreate() {
        launch();begin();tap("cancelCompose");tab("السجل");XCTAssertTrue(app.staticTexts["emptyHistory"].exists)
    }
    func testContactAddEditDeleteAndBlock() {
        launch();tab("دائرتي");shot("09-trusted-circle");tap("addContact")
        app.textFields["contactName"].tap();app.textFields["contactName"].typeText("نور")
        tap("saveContact");XCTAssertTrue(app.staticTexts["نور"].firstMatch.waitForExistence(timeout: 5))
        // Newly added contacts remain pending and cannot be chosen to send.
        tab("الرئيسية");tap("startAlert");XCTAssertTrue(app.staticTexts["دعوة معلّقة · غير متاح للإرسال"].firstMatch.exists);tap("closeScreen")
        tab("دائرتي");tap("edit-"+sara);tap("blockContact");tab("الرئيسية");tap("startAlert")
        XCTAssertFalse(app.switches["select-"+sara].isEnabled);tap("closeScreen")
        tab("دائرتي");tap("edit-"+sara);tap("deleteContact");tap("confirmDelete")
        XCTAssertFalse(app.buttons["edit-"+sara].exists)
    }
    func testAppearancePersistsAndPoliciesAndReadinessOpen() {
        launch();tab("الإعدادات");tap("appearanceSettings");shot("10-appearance")
        let field = app.textFields["buttonHex"]
        for _ in 0..<8 { if field.isHittable { break };app.swipeUp() }
        field.tap()
        // Use text-field value deletion instead of localization-dependent Select All menus.
        let old = field.value as? String ?? "";field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue,count: old.count)+"#99CCFF")
        tap("saveAppearance");app.terminate();launch(reset: false);tab("الإعدادات");tap("appearanceSettings")
        XCTAssertEqual(app.textFields["buttonHex"].value as? String,"#99CCFF");tap("closeScreen")
        tap("terms");shot("11-terms");tap("closeScreen");tap("privacy");shot("12-privacy");tap("closeScreen")
        tap("settingsReadiness");shot("13-readiness");tap("closeScreen")
    }
    func testLockDoesNotSuppressIncomingButProtectsDetails() {
        launch();tap("lockApp");tap("lockedIncoming");shot("14-locked-incoming")
        XCTAssertTrue(app.staticTexts["تفاصيل محمية"].exists);XCTAssertFalse(app.buttons["acceptResponse"].exists)
        tap("incomingSilence");tap("unlockIncoming");XCTAssertTrue(app.buttons["acceptResponse"].waitForExistence(timeout: 5))
        tap("declineResponse");XCTAssertTrue(app.staticTexts["لا يستطيع الاستجابة"].firstMatch.exists)
    }
    func testLargeTextHomeAndSettingsRemainNavigable() {
        launch(large: true);shot("15-large-text-home");tap("startAlert");shot("16-large-text-selection");tap("closeScreen")
        tab("الإعدادات");shot("17-large-text-settings");tap("appearanceSettings");shot("18-large-text-appearance")
    }
}
