import XCTest

final class LocalExperienceUITests: XCTestCase {
    var app: XCUIApplication!
    let sara = "00000000-0000-4000-8000-000000000001"
    override func setUpWithError() throws { continueAfterFailure = false }
    func launch(_ auth: String = "success", reset: Bool = true, large: Bool = false, extra: [String] = [], environment: [String:String] = [:]) {
        app = XCUIApplication();app.launchArguments = ["-nidaa-ui-testing", "-AppleLanguages", "(ar)", "-AppleLocale", "ar_SA"]
        if reset { app.launchArguments.append("-reset-demo") }
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launchEnvironment["NIDAA_TEST_AUTH"] = auth
        app.launchArguments += extra
        for (key,value) in environment { app.launchEnvironment[key] = value };app.launch()
        XCTAssertTrue(app.buttons["startAlert"].waitForExistence(timeout: 10))
        if !extra.contains("-fail-read") && !extra.contains("-corrupt-archive") {
            XCTAssertFalse(app.staticTexts["storageIssue"].firstMatch.exists, "Unexpected storage failure at launch")
        }
    }
    func tap(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        let element = app.buttons[id].firstMatch
        // SwiftUI may omit an offscreen button from the accessibility snapshot.
        // Discover it by scrolling before asserting existence, including on sheets.
        _ = element.waitForExistence(timeout: 6)
        for _ in 0..<12 {
            if element.exists && element.isHittable { break }
            let containing = app.scrollViews.containing(.button, identifier: id).firstMatch
            let scroll = containing.exists ? containing : app.scrollViews.allElementsBoundByIndex.last(where: { $0.isHittable })
            if let scroll {
                // Short content gestures cannot skip a whole action row, and can
                // recover if a preceding gesture placed the target above the viewport.
                let towardTop = element.exists && element.frame.maxY < scroll.frame.minY
                let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: towardTop ? 0.35 : 0.7))
                let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: towardTop ? 0.7 : 0.35))
                start.press(forDuration: 0.05, thenDragTo: end)
            } else {
                app.swipeUp()
            }
        }
        XCTAssertTrue(element.exists, id, file: file, line: line)
        XCTAssertTrue(element.isHittable, id, file: file, line: line)
        element.tap()
    }
    func tab(_ name: String) { app.tabBars.buttons[name].tap() }
    func shot(_ name: String) {
        // Wait for the sheet presentation animation so evidence is a settled screen.
        sleep(1)
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
        XCTAssertTrue(app.staticTexts["انتهت الحالة بتأكيد صريح"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["detailMessage"].label,"انتهت الحالة بتأكيد صريح");shot("07-resolved")
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
        launch();tab("الإعدادات");shot("22-settings");tap("appearanceSettings");shot("10-appearance")
        let field = app.textFields["buttonHex"]
        for _ in 0..<8 { if field.isHittable { break };app.swipeUp() }
        field.tap()
        // Use text-field value deletion instead of localization-dependent Select All menus.
        let old = field.value as? String ?? "";field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue,count: old.count)+"#99CCFF")
        tap("saveAppearance");app.terminate();launch(reset: false);shot("20-custom-button-home");tab("الإعدادات");tap("appearanceSettings")
        XCTAssertEqual(app.textFields["buttonHex"].value as? String,"#99CCFF")
        app.segmentedControls.buttons["فاتح"].tap();shot("21-light-preview");tap("closeScreen")
        tap("terms");shot("11-terms");tap("closeScreen");tap("privacy");shot("12-privacy");tap("closeScreen")
        tap("settingsReadiness");shot("13-readiness");tap("closeScreen")
    }
    func testLockDoesNotSuppressIncomingButProtectsDetails() {
        launch();tap("lockApp");tap("lockedIncoming");shot("14-locked-incoming")
        XCTAssertTrue(app.staticTexts["تفاصيل محمية"].exists);XCTAssertFalse(app.buttons["acceptResponse"].exists)
        tap("incomingSilence");tap("unlockIncoming");XCTAssertTrue(app.buttons["acceptResponse"].waitForExistence(timeout: 5))
        tap("declineResponse");XCTAssertTrue(app.staticTexts["لا يستطيع الاستجابة"].firstMatch.exists)
    }
    var ahmad: String { "00000000-0000-4000-8000-000000000002" }
    func sendToSara() {
        tap("startAlert");app.switches["select-"+ahmad].tap();tap("authenticateSend");tap("confirmAlert")
        XCTAssertTrue(app.staticTexts["alertIdentifier"].waitForExistence(timeout:6))
    }
    func openSaved(_ id: String) { tab("السجل");tap("history-"+id);XCTAssertTrue(app.staticTexts["alertIdentifier"].waitForExistence(timeout:5)) }
    func chooseAction(_ add: Bool) { tap(add ? "alternative-"+ahmad : "retryAlert");XCTAssertTrue(app.buttons["authenticateAction"].waitForExistence(timeout:5)) }
    func testPersistentRestorationAndRetryKeepsResponse() {
        launch();send();let id = app.staticTexts["alertIdentifier"].label
        tap("receipt-"+sara);tap("openRecipient-"+sara);tap("acceptResponse");tap("incomingDetails");tap("silenceAlert")
        app.terminate();launch(reset:false);openSaved(id)
        XCTAssertEqual(app.staticTexts["alertIdentifier"].label,id)
        XCTAssertTrue(app.staticTexts["سأتولى الاستجابة"].exists)
        XCTAssertEqual(app.staticTexts["attemptCount"].value as? String,"1");shot("23-restored-alert")
        chooseAction(false)
        XCTAssertFalse(app.staticTexts["actionRecipient-"+sara].exists);XCTAssertTrue(app.staticTexts["actionRecipient-"+ahmad].exists)
        tap("authenticateAction");XCTAssertTrue(app.buttons["confirmAction"].waitForExistence(timeout:5));shot("24-retry-confirmation")
        app.buttons["confirmAction"].doubleTap()
        XCTAssertTrue(app.staticTexts["attemptCount"].waitForExistence(timeout:5));XCTAssertEqual(app.staticTexts["attemptCount"].value as? String,"2")
        XCTAssertEqual(app.staticTexts["alertIdentifier"].label,id);XCTAssertTrue(app.staticTexts["سأتولى الاستجابة"].exists)
        app.terminate();launch(reset:false);openSaved(id);XCTAssertEqual(app.staticTexts["attemptCount"].value as? String,"2")
    }
    func testAdditionRequiresConfirmationAndPersistsWithoutChangingIdentity() {
        launch();sendToSara();let id = app.staticTexts["alertIdentifier"].label
        chooseAction(true);tap("authenticateAction");shot("25-addition-confirmation");tap("confirmAction")
        XCTAssertTrue(app.buttons["receipt-"+ahmad].waitForExistence(timeout:5));XCTAssertEqual(app.staticTexts["attemptCount"].value as? String,"1")
        app.terminate();launch(reset:false);openSaved(id);XCTAssertTrue(app.buttons["receipt-"+ahmad].exists);shot("26-restored-addition")
    }
    func testBothActionsFailureCancellationAndRestartHaveNoAuthorization() {
        for add in [false,true] {
            for outcome in ["failure","cancel"] {
                launch(environment:["NIDAA_TEST_ACTION_AUTH":outcome]);sendToSara();chooseAction(add);tap("authenticateAction")
                XCTAssertTrue(app.staticTexts["actionMessage"].waitForExistence(timeout:5));XCTAssertFalse(app.buttons["confirmAction"].exists)
                tap("cancelAction");XCTAssertEqual(app.staticTexts["attemptCount"].value as? String,"1");XCTAssertFalse(app.buttons["receipt-"+ahmad].exists);app.terminate()
            }
            launch();sendToSara();let id = app.staticTexts["alertIdentifier"].label;chooseAction(add);tap("authenticateAction")
            XCTAssertTrue(app.buttons["confirmAction"].waitForExistence(timeout:5));app.terminate();launch(reset:false);openSaved(id);chooseAction(add)
            XCTAssertFalse(app.buttons["confirmAction"].exists);XCTAssertTrue(app.buttons["authenticateAction"].exists);app.terminate()
        }
    }
    func testBothActionsBackgroundDuringAuthenticationAndConsentChanges() {
        for add in [false,true] {
            launch(environment:["NIDAA_TEST_ACTION_AUTH":"delayed"]);sendToSara();let id = app.staticTexts["alertIdentifier"].label
            chooseAction(add);tap("authenticateAction");XCUIDevice.shared.press(.home);sleep(5);app.activate()
            XCTAssertFalse(app.buttons["confirmAction"].exists);openSaved(id);XCTAssertEqual(app.staticTexts["attemptCount"].value as? String,"1");app.terminate()
            for change in ["block","consent","delete"] {
                launch(environment:["NIDAA_TEST_ACTION_AUTH":"delayed","NIDAA_TEST_CHANGE":change]);sendToSara();let alertID = app.staticTexts["alertIdentifier"].label
                chooseAction(add);tap("authenticateAction");sleep(5);XCTAssertFalse(app.buttons["confirmAction"].exists)
                openSaved(alertID);XCTAssertEqual(app.staticTexts["attemptCount"].value as? String,"1");XCTAssertFalse(app.buttons["receipt-"+ahmad].exists);app.terminate()
            }
        }
    }
    func testExpiredAuthorizationAndTerminalRestoration() {
        launch();sendToSara();let id = app.staticTexts["alertIdentifier"].label;chooseAction(false);tap("authenticateAction")
        XCTAssertTrue(app.buttons["confirmAction"].waitForExistence(timeout:5));sleep(16)
        XCTAssertFalse(app.buttons["confirmAction"].exists);tap("cancelAction");XCTAssertEqual(app.staticTexts["attemptCount"].value as? String,"1")
        app.terminate();launch(reset:false,environment:["NIDAA_TEST_CLOCK":"301"]);openSaved(id)
        XCTAssertEqual(app.staticTexts["alertState"].label,"انتهت صلاحية النداء");XCTAssertFalse(app.buttons["retryAlert"].exists)
        XCTAssertFalse(app.staticTexts["لا استجابة مؤكدة خلال المهلة"].exists);shot("27-expired-on-restore")
        app.terminate();launch(reset:false);openSaved(id);XCTAssertEqual(app.staticTexts["alertState"].label,"انتهت صلاحية النداء")
        app.terminate();launch();sendToSara();let resolved = app.staticTexts["alertIdentifier"].label;tap("resolveAlert");tap("confirmCloseAlert")
        app.terminate();launch(reset:false);openSaved(resolved);XCTAssertEqual(app.staticTexts["alertState"].label,"انتهت الحالة بتأكيد صريح")
    }
    func testStorageFailuresAreVisibleAndRetainValidData() {
        launch();sendToSara();let id = app.staticTexts["alertIdentifier"].label;app.terminate()
        launch(reset:false,extra:["-fail-read"]);XCTAssertTrue(app.staticTexts["storageIssue"].firstMatch.exists);app.terminate()
        launch(reset:false);openSaved(id);app.terminate()
        launch(reset:false,extra:["-fail-write"]);openSaved(id);chooseAction(false);tap("authenticateAction");tap("confirmAction")
        XCTAssertTrue(app.staticTexts["storageIssue"].firstMatch.waitForExistence(timeout:5));shot("28-storage-failure")
        XCTAssertFalse(app.buttons["authenticateAction"].isEnabled);tap("cancelAction")
        XCTAssertEqual(app.staticTexts["attemptCount"].value as? String,"1");app.terminate()
        launch(reset:false);openSaved(id);XCTAssertEqual(app.staticTexts["attemptCount"].value as? String,"1")
    }
    func testCorruptionIsNotOverwrittenAndExplicitResetClearsHistory() {
        launch();sendToSara();app.terminate();launch(reset:false,extra:["-corrupt-archive"])
        XCTAssertTrue(app.staticTexts["storageIssue"].firstMatch.exists);tap("reloadStorage");XCTAssertTrue(app.staticTexts["storageIssue"].firstMatch.exists);shot("29-corrupt-storage")
        tab("الإعدادات");tap("resetDemo");tap("confirmReset");XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.staticTexts["storageIssue"].firstMatch)], timeout: 5), .completed)
        app.terminate();launch(reset:false);tab("السجل");XCTAssertTrue(app.staticTexts["emptyHistory"].exists);shot("30-reset-history")
    }
    func testLargeTextActionReviewRemainsUsable() {
        launch(large:true);sendToSara();chooseAction(true);tap("authenticateAction")
        let confirmation = app.buttons["confirmAction"]
        XCTAssertTrue(confirmation.waitForExistence(timeout:5))
        for _ in 0..<10 { if confirmation.isHittable { break };app.swipeUp() }
        for _ in 0..<4 { if confirmation.frame.maxY < app.frame.maxY - 40 { break };app.swipeUp() }
        shot("31-large-action-confirmation");tap("confirmAction")
        XCTAssertTrue(app.staticTexts["alertIdentifier"].exists)
    }
    func testApplicationAndUITestStorageAreIsolated() {
        launch();sendToSara();let id = app.staticTexts["alertIdentifier"].label;app.terminate()
        app.launchArguments = ["-AppleLanguages", "(ar)", "-AppleLocale", "ar_SA"]
        app.launchEnvironment = [:];app.launch()
        XCTAssertTrue(app.buttons["startAlert"].waitForExistence(timeout:10))
        tab("السجل");XCTAssertTrue(app.staticTexts["emptyHistory"].exists)
        app.terminate();launch(reset:false);openSaved(id)
        XCTAssertEqual(app.staticTexts["alertIdentifier"].label,id)
        tap("closeScreen");tab("الإعدادات");tap("resetDemo");tap("confirmReset")
        app.terminate();launch(reset:false);tab("السجل");XCTAssertTrue(app.staticTexts["emptyHistory"].exists)
    }
    func testLargeTextHomeAndSettingsRemainNavigable() {
        launch(large: true);shot("15-large-text-home")
        for _ in 0..<10 { if app.buttons["startAlert"].isHittable { break };app.swipeUp() }
        for _ in 0..<4 {
            if app.buttons["startAlert"].frame.maxY < app.tabBars.firstMatch.frame.minY - 8 { break }
            app.swipeUp()
        }
        shot("19-large-text-action");tap("startAlert");shot("16-large-text-selection");tap("closeScreen")
        tab("الإعدادات");shot("17-large-text-settings");tap("appearanceSettings");shot("18-large-text-appearance")
    }
}
