import XCTest
import UIKit

/// Native input coverage with AutoFill ON. Networking is explicitly MOCK here;
/// saved-credential selection is a separate, not yet verified scenario.
final class AutoFillUITests: IntegrationTestCase {
    private var pickerQueryDiagnosticsActive = false
    private var pickerSnapshotFailures = 0
    private var pickerCompleteSnapshotsWithoutIdentity = 0
    private var pickerIdentitiesObserved = 0

    override func tearDownWithError() throws {
        // Emit final counters once even after an ordinary assertion abort;
        // no further UI query is needed. A killed runner cannot run teardown.
        if pickerQueryDiagnosticsActive {
            let state = ["snapshotFailures": pickerSnapshotFailures,
                         "completeSnapshotsWithoutIdentity": pickerCompleteSnapshotsWithoutIdentity,
                         "identitiesObserved": pickerIdentitiesObserved]
            if let data = try? JSONSerialization.data(withJSONObject: state, options: [.sortedKeys]),
               let text = String(data: data, encoding: .utf8) {
                let attachment = XCTAttachment(string: text)
                attachment.name = "autofill-native-picker-query-state"
                attachment.lifetime = .keepAlways; add(attachment)
            }
        }
        try super.tearDownWithError()
    }

    func testSavedCredentialSelection() throws {
        // Only a new disposable Simulator. Password values are never read,
        // copied, attached, published, or sent to a server. Raw typing events
        // stay private; the native form receives a fresh local-only UUID secret.
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
        recordEarlyPasswordsEntry(passwords: passwords, springboard: springboard)
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

        let websiteLabels = ["Website or Label", "Website or App", "Website", "website", "example.com", "App or Website"]
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
        let passwordField = labeledRowTextField("Password", in: passwords)
        recordNativeFormReadiness(phase: "before_password", website: website, username: username,
                                  passwordField: passwordField, save: save, site: site, email: email)
        XCTAssertTrue(website.value as? String == site, "Fictional website input did not match")
        XCTAssertTrue(username.value as? String == email, "Fictional username input did not match")
        guard passwordField.exists, passwordField.isHittable else {
            XCTFail("Unique native Password row field unavailable"); return
        }
        // No assumption that this Simulator supplied a generated password.
        // Never inspect its value, select/copy it, or capture this native row.
        passwordField.tap()
        passwordField.typeText(UUID().uuidString)
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: save)
        let formReady = XCTWaiter.wait(for: [enabled], timeout: 5)
        recordNativeFormReadiness(phase: "after_password", website: website, username: username,
                                  passwordField: passwordField, save: save, site: site, email: email)
        XCTAssertEqual(formReady, .completed)
        save.tap()
        let saved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: header)
        XCTAssertEqual(XCTWaiter.wait(for: [saved], timeout: 8), .completed)
        passwords.terminate()
        // Verify persistence through the actual native list, without opening
        // credential details, copying a secret, or seeding the keychain.
        passwords.launch()
        var allListOpened = false
        let allButton = passwords.buttons.matching(NSPredicate(format: "label == %@ OR label BEGINSWITH %@", "All", "All,")).firstMatch
        let allRow = passwords.cells.containing(.staticText, identifier: "All").firstMatch
        let allText = passwords.staticTexts["All"].firstMatch
        let homeReady = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            allButton.exists || allRow.exists || allText.exists
                || self.nativeFixtureIdentityTarget(in: passwords, email: email, site: site) != nil
        }, object: nil)
        _ = XCTWaiter.wait(for: [homeReady], timeout: 8)
        for target in [allButton, allRow, allText] where target.exists && target.isHittable {
            target.tap(); allListOpened = true; break
        }
        let persisted = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.nativeFixtureIdentityTarget(in: passwords, email: email, site: site) != nil
        }, object: nil)
        let persistedEntryFound = XCTWaiter.wait(for: [persisted], timeout: 8) == .completed
        attachDiagnosticBooleans(["allListOpened": allListOpened, "persistedEntryFound": persistedEntryFound,
                                  "passwordsForeground": passwords.state == .runningForeground], name: "autofill-saved-entry-persistence")
        if !persistedEntryFound { recordKnownSystemControls(in: passwords, stage: "saved-entry-persistence") }
        passwords.terminate()
        guard persistedEntryFound else {
            XCTFail("Fictional saved identity did not persist in the native Passwords list after relaunch"); return
        }

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
        // The keyboard can exist before its Passwords accessory appears. The
        // observed fdab801 failure recorded that button after an early fallback.
        if !pickerButton.waitForExistence(timeout: 8) {
            // The public edit menu is also a user-initiated AutoFill route; no
            // clipboard, keychain injection or credential text typing is used.
            emailField.press(forDuration: 1)
            // Some native edit menus expose Passwords directly. Only open an
            // AutoFill submenu when the actual Passwords control is still absent.
            if !pickerButton.waitForExistence(timeout: 3) {
                let autoFill = namedButton(["AutoFill", "تعبئة تلقائية", "تعبئة تلقائية…"], in: app)
                guard autoFill.waitForExistence(timeout: 5), autoFill.isHittable else {
                    recordKnownSystemControls(in: app, stage: "autofill-launch")
                    XCTFail("Native AutoFill entry control unavailable"); return
                }
                autoFill.tap()
            }
            pickerButton = namedButton(passwordLabels, in: app)
        }
        let pickerReady = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND hittable == true"), object: pickerButton)
        guard XCTWaiter.wait(for: [pickerReady], timeout: 5) == .completed else {
            recordKnownSystemControls(in: app, stage: "password-picker-launch")
            XCTFail("Native Passwords picker control unavailable"); return
        }
        pickerQueryDiagnosticsActive = true
        recordFullPickerDiagnostic(phase: "before_tap", app: nativeApp, springboard: springboard, passwords: passwords)
        pickerButton.tap()
        guard emitPickerMatchRequest() else { return }
        recordFullPickerDiagnostic(phase: "after_tap", app: nativeApp, springboard: springboard, passwords: passwords)
        // The picker can appear asynchronously, with the fictional identity in
        // different native roles. Rebuild candidates on every bounded poll;
        // never commit early to an absent static-text query. Do not relaunch
        // Passwords: include that surface only if the system foregrounded it.
        func pickerSurfaces() -> [XCUIApplication] {
            var surfaces = [nativeApp, springboard]
            if passwords.state == .runningForeground { surfaces.append(passwords) }
            return surfaces
        }
        var otherPasswords: XCUIElement?
        let routeReady = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            for surface in pickerSurfaces() {
                if self.savedIdentityTarget(in: surface, email: email, site: site) != nil { return true }
                if let other = self.snapshotObservedButton(["Other Passwords", "Other Passwords…", "كلمات سر أخرى", "كلمات مرور أخرى"], in: surface) {
                    otherPasswords = other; return true
                }
            }
            return false
        }, object: nil)
        _ = XCTWaiter.wait(for: [routeReady], timeout: 8)
        try skipOnlyObservedPersonalRequirement(in: pickerSurfaces())
        if let otherPasswords, otherPasswords.exists && otherPasswords.isHittable { otherPasswords.tap() }
        var selectedTarget: XCUIElement?
        let selectionReady = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            for surface in pickerSurfaces() {
                if let target = self.savedIdentityTarget(in: surface, email: email, site: site) {
                    selectedTarget = target; return true
                }
            }
            return false
        }, object: nil)
        let selectionResult = XCTWaiter.wait(for: [selectionReady], timeout: 8)
        recordPickerState(app: nativeApp, springboard: springboard, passwords: passwords, email: email, site: site)
        recordPickerHeader()
        guard selectionResult == .completed, let selectedTarget else {
            recordFullPickerDiagnostic(phase: "selection_failure", app: nativeApp, springboard: springboard, passwords: passwords)
            try skipOnlyObservedPersonalRequirement(in: pickerSurfaces())
            recordKnownSystemControls(in: nativeApp, stage: "saved-account-selection-app")
            recordKnownSystemControls(in: springboard, stage: "saved-account-selection-springboard")
            if passwords.state == .runningForeground {
                recordKnownSystemControls(in: passwords, stage: "saved-account-selection-passwords")
            }
            XCTFail("Fictional saved account not found in native picker"); return
        }
        let selectedRole = Int(selectedTarget.elementType.rawValue)
        let selectedLabel = selectedTarget.label
        let selectedLabelContainsEmail = selectedLabel.contains(email)
        let selectedLabelContainsSite = selectedLabel.contains(site)
        let selectedLabelEqualsEmail = selectedLabel == email
        let selectedLabelEqualsSite = selectedLabel == site
        recordFullPickerDiagnostic(phase: "before_selection", app: nativeApp, springboard: springboard, passwords: passwords)
        selectedTarget.tap()
        let emailFilled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", email), object: emailField)
        let emailFillResult = XCTWaiter.wait(for: [emailFilled], timeout: 8)
        let emailFieldExists = emailField.exists
        // Only this fictional email is inspected. Never inspect a password
        // field value or attach any label/value string from the native picker.
        let emailValue = emailFieldExists ? emailField.value as? String : nil
        let signup = app.buttons["integrationSignup"]
        let selectionState: [String: Any] = [
            "selectedRole": selectedRole,
            "selectedLabelContainsEmail": selectedLabelContainsEmail,
            "selectedLabelContainsSite": selectedLabelContainsSite,
            "selectedLabelEqualsEmail": selectedLabelEqualsEmail,
            "selectedLabelEqualsSite": selectedLabelEqualsSite,
            "emailFieldExists": emailFieldExists,
            "emailMatchesExpected": emailFieldExists && emailValue == email,
            "emailBlank": emailFieldExists && (emailValue.map { $0.isEmpty || $0 == emailField.placeholderValue } ?? false),
            "signupEnabled": signup.exists && signup.isEnabled
        ]
        if let data = try? JSONSerialization.data(withJSONObject: selectionState, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            let attachment = XCTAttachment(string: text)
            attachment.name = "autofill-native-selection-state"
            attachment.lifetime = .keepAlways; add(attachment)
        }
        recordFullPickerDiagnostic(phase: "after_fill_wait", app: nativeApp, springboard: springboard, passwords: passwords)
        XCTAssertEqual(emailFillResult, .completed)
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
    private func attachDiagnosticBooleans(_ report: [String: Bool], name: String) {
        guard let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return }
        let evidence = XCTAttachment(string: text)
        evidence.name = name; evidence.lifetime = .keepAlways; add(evidence)
    }
    override func inspectAutoFillProviderFixture(in settings: XCUIApplication) throws {
        // The base fixture has just verified AutoFill ON on this exact native
        // page. Do not relaunch, navigate or terminate Settings from this hook.
        // PRIVATE ONLY: the delivery script encrypts this original full screen;
        // it is excluded from the public screenshot allowlist.
        let privateScreen = XCTAttachment(screenshot: settings.screenshot())
        privateScreen.name = "autofill-native-provider-settings-screen"
        privateScreen.lifetime = .keepAlways; add(privateScreen)
        let global = settings.switches["AutoFillToggle"].firstMatch
        let providerSwitch = settings.switches.matching(NSPredicate(format: "label == %@ OR identifier == %@", "Passwords", "Passwords")).firstMatch
        let providerCell = settings.cells.containing(.staticText, identifier: "Passwords").firstMatch
        let providerButton = settings.buttons["Passwords"].firstMatch
        let providerText = settings.staticTexts["Passwords"].firstMatch
        let visibleGlobal = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND hittable == true"), object: global)
        _ = XCTWaiter.wait(for: [visibleGlobal], timeout: 5)
        // A containing cell can be an entire section. Only infer a switch from
        // a single bounded provider row; never use the section's global toggle.
        let providerRowSwitch: XCUIElement
        if providerCell.exists, providerCell.frame.height <= 120, providerCell.switches.count == 1 {
            providerRowSwitch = providerCell.switches.firstMatch
        } else {
            providerRowSwitch = settings.switches["NIDAA-absent-provider-row-switch"]
        }
        func state(_ control: XCUIElement) -> (known: Bool, enabled: Bool) {
            guard control.exists, let value = (control.value as? String)?.lowercased() else { return (false, false) }
            if value == "1" || value == "on" { return (true, true) }
            if value == "0" || value == "off" { return (true, false) }
            return (false, false)
        }
        let globalState = state(global)
        let providerState = state(providerSwitch.exists ? providerSwitch : providerRowSwitch)
        attachDiagnosticBooleans(["globalEnabledKnown": globalState.known, "globalEnabled": globalState.enabled,
            "providerControlObserved": providerSwitch.exists || providerCell.exists || providerButton.exists || providerText.exists,
            "providerEnabledKnown": providerState.known, "providerEnabled": providerState.enabled], name: "autofill-native-provider-state")
        let windowFrame = settings.windows.firstMatch.frame
        let runnerFrame = UIScreen.main.bounds
        func coordinates(_ frame: CGRect) -> [CGFloat] { [frame.minX, frame.minY, frame.width, frame.height] }
        let candidates: [(String, XCUIElement, Bool)] = [
            ("global_switch", global, true), ("provider_switch", providerSwitch, true),
            ("provider_cell", providerCell, false), ("provider_button", providerButton, false),
            ("provider_text", providerText, false), ("provider_row_switch", providerRowSwitch, true)]
        let rows: [[String: Any]] = candidates.map { name, element, isSwitch in
            let exists = element.exists
            let frame = exists ? element.frame : .zero
            let value = isSwitch ? state(element) : (known: false, enabled: false)
            return ["control": name, "exists": exists, "hittable": exists && element.isHittable,
                    "selected": exists && element.isSelected, "frame": coordinates(frame),
                    "runnerContains": exists && runnerFrame.contains(frame),
                    "windowContains": exists && windowFrame.contains(frame),
                    "sizeEligible": exists && frame.height > 0 && frame.height <= 120 && frame.width > 0,
                    "valueKnown": value.known, "enabled": value.enabled]
        }
        let geometry: [String: Any] = ["runnerFrame": coordinates(runnerFrame), "windowFrame": coordinates(windowFrame), "rows": rows]
        if let data = try? JSONSerialization.data(withJSONObject: geometry, options: [.sortedKeys]), let text = String(data: data, encoding: .utf8) {
            let evidence = XCTAttachment(string: text)
            evidence.name = "autofill-native-provider-geometry"
            evidence.lifetime = .keepAlways; add(evidence)
        }
        func attachRow(_ row: XCUIElement, name: String) -> Bool {
            guard settings.state == .runningForeground, row.exists else { return false }
            let frame = row.frame
            // Only the fresh Simulator's named settings controls; never a full
            // Settings screen, Apple account header or credential detail. A
            // visible label need not be independently tappable to be captured.
            guard frame.height > 0, frame.height <= 120, frame.width > 0,
                  windowFrame.contains(frame) else { return false }
            let image = XCTAttachment(screenshot: row.screenshot())
            image.name = name; image.lifetime = .keepAlways; add(image)
            return true
        }
        _ = attachRow(global, name: "autofill-native-provider-global-toggle")
        for row in [providerSwitch, providerRowSwitch, providerCell, providerButton, providerText] {
            if attachRow(row, name: "autofill-native-provider-row") { break }
        }
    }
    private func pickerDiagnosticAllowedStrings() -> Set<String> {
        ["", "[redacted]", "Passwords", "Password", "Password AutoFill", "AutoFill Password", "Fill Password", "Use Password", "Use This Password",
         "AutoFill", "AutoFill…", "Other Passwords", "Other Passwords…", "Open Passwords", "Search", "Search Passwords",
         "Allow", "Don’t Allow", "Don't Allow", "Continue", "Cancel", "Done", "Close", "Back", "Save", "New Password",
         "User Name", "Username", "Website or Label", "Website or App", "Notes", "All", "Passkeys", "Codes", "Deleted",
         "Sign In to iCloud", "Sign in to your Apple Account", "Set Up a Passcode", "Enter iPhone Passcode", "Use Passcode",
         "Face ID", "Touch ID", "Authentication Required", "Unlock Passwords", "Select All", "Select", "Paste", "Copy", "Cut",
         "كلمات السر", "كلمات المرور", "تعبئة كلمات السر", "تعبئة تلقائية", "تعبئة تلقائية…", "كلمات سر أخرى", "كلمات مرور أخرى",
         "استخدام كلمة السر", "استخدام كلمة المرور", "استخدام كلمة السر هذه", "استخدام كلمة المرور هذه", "تعبئة كلمة السر", "تعبئة كلمة المرور",
         "بحث", "إلغاء", "تم", "متابعة", "السماح", "عدم السماح", "فتح كلمات السر", "تسجيل الدخول إلى iCloud", "إدخال رمز دخول iPhone",
         "NIDAA", "نداء", "تجربة الربط المحلي", "MOCK · محاكاة واجهة فقط", "حساب خيالي مستقل", "البريد الإلكتروني", "كلمة المرور",
         "تسجيل الدخول", "إنشاء حساب تجريبي", "طلب استعادة كلمة المرور", "لديّ رمز تحقق أو استعادة", "إغلاق", "إظهار كلمة المرور", "إخفاء كلمة المرور",
         "الحسابات والنتائج التالية خيالية داخل الواجهة. لا يثبت هذا اختبارًا من المحاكي إلى الخادم.",
         "الإرسال مزيف للاختبار · APNs غير مفعّل · لا إشعار أو صوت على هاتف.",
         "استخدم بريدًا ينتهي بـ ‎.invalid. التحقق يصل إلى صندوق محلي معزول؛ لا تستخدم بيانات شخصية.",
         "integrationEmail", "integrationPassword", "integrationPasswordVisibility", "integrationPasswordPaste", "integrationLogin",
         "integrationSignup", "integrationRecover", "integrationExistingToken", "integrationKeyboardDone", "integrationMockBanner"]
    }
    private func recordFullPickerDiagnostic(phase: String, app: XCUIApplication, springboard: XCUIApplication, passwords: XCUIApplication) {
        // Only the disposable fixture is inspected. No .value or debugDescription
        // is read from snapshots. Unknown labels/identifiers are never attached.
        let allowed = pickerDiagnosticAllowedStrings()
        let passwordsForeground = passwords.state == .runningForeground
        let newPasswordFormClosed = !passwordsForeground || !passwords.navigationBars["New Password"].exists
        let email = app.textFields["integrationEmail"]
        let emailBlank = email.exists && ((email.value as? String) == email.placeholderValue || (email.value as? String) == "")
        var surfaces: [(String, XCUIApplication)] = [("app", app), ("springboard", springboard)]
        if passwordsForeground { surfaces.append(("passwords", passwords)) }
        var nodes: [[String: Any]] = []
        var masks: [CGRect] = []
        var complete = true
        var truncated = false
        func visit(_ snapshot: XCUIElementSnapshot, surface: String, parent: Int, depth: Int) {
            guard nodes.count < 2000, depth < 50 else { truncated = true; return }
            let frame = snapshot.frame
            guard [frame.minX, frame.minY, frame.width, frame.height].allSatisfy({ $0.isFinite }) else {
                complete = false; return
            }
            let index = nodes.count
            let label = snapshot.label
            let identifier = snapshot.identifier
            let children = snapshot.children
            let role = snapshot.elementType
            let editable = role == .textField || role == .secureTextField || role == .textView
            let unknownText = !label.isEmpty && !allowed.contains(label)
            if editable || (unknownText && (children.isEmpty || role == .staticText || role == .button || role == .cell)) {
                masks.append(frame.insetBy(dx: -4, dy: -4))
            }
            nodes.append(["surface": surface, "node": index, "parent": parent,
                "role": Int(role.rawValue), "frame": [frame.minX, frame.minY, frame.width, frame.height],
                "label": allowed.contains(label) ? label : "[redacted]",
                "identifier": allowed.contains(identifier) ? identifier : "[redacted]"])
            for child in children { visit(child, surface: surface, parent: index, depth: depth + 1) }
        }
        for (name, surface) in surfaces {
            do { visit(try surface.snapshot(), surface: name, parent: -1, depth: 0) }
            catch { complete = false } // Never attach an error that may contain an unsanitized snapshot.
        }
        let report: [String: Any] = ["phase": phase, "newPasswordFormClosed": newPasswordFormClosed,
            "emailBlank": emailBlank, "snapshotsComplete": complete, "truncated": truncated,
            "maskCount": masks.count, "nodes": nodes]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]), let text = String(data: data, encoding: .utf8) {
            let evidence = XCTAttachment(string: text)
            evidence.name = "autofill-native-picker-accessibility-tree"
            evidence.lifetime = .keepAlways; add(evidence)
        }
        // Full screen, runner-private only. Snapshot masks are not atomic with a
        // changing screen. Neither raw nor encrypted images may be uploaded;
        // only the strictly validated fixed-schema JSON is exportable.
        guard newPasswordFormClosed, emailBlank, complete, !truncated else { return }
        let original = XCUIScreen.main.screenshot().image
        guard let pixels = original.cgImage else { return }
        let screen = UIScreen.main.bounds
        guard screen.width > 0, screen.height > 0 else { return }
        let size = CGSize(width: CGFloat(pixels.width), height: CGFloat(pixels.height))
        let scaleX = size.width / screen.width
        let scaleY = size.height / screen.height
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1; format.opaque = true
        let redacted = UIGraphicsImageRenderer(size: size, format: format).image { context in
            original.draw(in: CGRect(origin: .zero, size: size))
            UIColor.black.setFill()
            for mask in masks {
                let visible = mask.intersection(screen)
                guard !visible.isNull, !visible.isEmpty else { continue }
                context.fill(CGRect(x: (visible.minX - screen.minX) * scaleX, y: (visible.minY - screen.minY) * scaleY,
                                    width: visible.width * scaleX, height: visible.height * scaleY))
            }
        }
        let evidence = XCTAttachment(image: redacted)
        evidence.name = "autofill-native-picker-full-screen-redacted-" + phase.replacingOccurrences(of: "_", with: "-")
        evidence.lifetime = .keepAlways; add(evidence)
    }
    // Preserve the previously exercised native Passwords fixture selector.
    // Snapshot-gated selection is restricted to the subsequent picker stage.
    private func nativeFixtureIdentityTarget(in surface: XCUIApplication, email: String, site: String) -> XCUIElement? {
        let identity = NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@", email, site)
        let candidates = surface.buttons.matching(identity).allElementsBoundByIndex
            + surface.cells.matching(identity).allElementsBoundByIndex
            + surface.cells.containing(.staticText, identifier: email).allElementsBoundByIndex
            + surface.cells.containing(.staticText, identifier: site).allElementsBoundByIndex
            + surface.staticTexts.matching(identity).allElementsBoundByIndex
        return candidates.first { $0.exists && $0.isHittable }
    }
    private func savedIdentityTarget(in surface: XCUIApplication, email: String, site: String) -> XCUIElement? {
        guard let nodes = pickerSnapshotNodes(in: surface) else { return nil }
        let roles: [XCUIElement.ElementType] = [.button, .cell, .staticText]
        func isIdentity(_ label: String) -> Bool { label.contains(email) || label.contains(site) }
        let direct = nodes.filter { roles.contains($0.elementType) && isIdentity($0.label) }
        var cellDescendantLabels: [String] = []
        var seenDescendantLabels = Set<String>()
        func collectIdentityStaticTexts(_ node: XCUIElementSnapshot) {
            if node.elementType == .staticText, isIdentity(node.label),
               seenDescendantLabels.insert(node.label).inserted {
                cellDescendantLabels.append(node.label)
            }
            for child in node.children { collectIdentityStaticTexts(child) }
        }
        // Snapshot traversal above already proved the full tree is bounded.
        // Preserve unlabeled tappable cells whose identity text is not tappable.
        for cell in nodes where cell.elementType == .cell {
            for child in cell.children { collectIdentityStaticTexts(child) }
        }
        if pickerQueryDiagnosticsActive {
            if direct.isEmpty && cellDescendantLabels.isEmpty { pickerCompleteSnapshotsWithoutIdentity += 1 }
            else { pickerIdentitiesObserved += 1 }
        }
        func firstHittable(_ query: XCUIElementQuery) -> XCUIElement? {
            for target in query.allElementsBoundByIndex {
                if target.exists && target.isHittable { return target }
            }
            return nil
        }
        // Keep button -> cell -> static-text priority. Only resolve queries
        // supported by an observed role/label or cell/descendant relationship.
        for role in roles {
            var checkedLabels = Set<String>()
            for observed in direct where observed.elementType == role {
                guard checkedLabels.insert(observed.label).inserted else { continue }
                let query = surface.descendants(matching: role).matching(NSPredicate(format: "label == %@", observed.label))
                if let target = firstHittable(query) { return target }
            }
            if role == .cell {
                for label in cellDescendantLabels {
                    if let target = firstHittable(surface.cells.containing(.staticText, identifier: label)) { return target }
                }
            }
        }
        return nil
    }

    private func snapshotObservedButton(_ labels: [String], in surface: XCUIApplication) -> XCUIElement? {
        guard let nodes = pickerSnapshotNodes(in: surface) else { return nil }
        for label in labels where nodes.contains(where: { $0.elementType == .button && ($0.label == label || $0.identifier == label) }) {
            let button = surface.buttons.matching(NSPredicate(format: "label == %@ OR identifier == %@", label, label)).firstMatch
            if button.exists && button.isHittable { return button }
        }
        return nil
    }

    private func pickerSnapshotNodes(in surface: XCUIApplication) -> [XCUIElementSnapshot]? {
        var nodes: [XCUIElementSnapshot] = []
        var complete = true
        func visit(_ node: XCUIElementSnapshot, depth: Int) {
            guard complete else { return }
            guard depth < 50, nodes.count < 2000 else { complete = false; return }
            nodes.append(node)
            for child in node.children { visit(child, depth: depth + 1) }
        }
        do { visit(try surface.snapshot(), depth: 0) }
        catch { complete = false }
        guard complete else {
            if pickerQueryDiagnosticsActive { pickerSnapshotFailures += 1 }
            return nil
        }
        return nodes
    }
    private func recordPickerState(app: XCUIApplication, springboard: XCUIApplication, passwords: XCUIApplication, email: String, site: String) {
        let passwordsForeground = passwords.state == .runningForeground
        let report: [String: Bool] = [
            "appForeground": app.state == .runningForeground,
            "springboardForeground": springboard.state == .runningForeground,
            "passwordsForeground": passwordsForeground,
            "appSavedIdentityVisible": savedIdentityTarget(in: app, email: email, site: site) != nil,
            "springboardSavedIdentityVisible": savedIdentityTarget(in: springboard, email: email, site: site) != nil,
            "passwordsSavedIdentityVisible": passwordsForeground && savedIdentityTarget(in: passwords, email: email, site: site) != nil]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]), let text = String(data: data, encoding: .utf8) {
            let evidence = XCTAttachment(string: text)
            evidence.name = "autofill-native-picker-state"
            evidence.lifetime = .keepAlways; add(evidence)
        }
    }
    private func recordPickerHeader() {
        // Export only the original top <=120 points, never picker rows or the
        // native Password field. The full screen image is not attached.
        let image = XCUIScreen.main.screenshot().image
        guard let pixels = image.cgImage else { return }
        let screenWidth = UIScreen.main.bounds.width
        guard screenWidth > 0 else { return }
        let height = min(CGFloat(pixels.height), 120 * CGFloat(pixels.width) / screenWidth)
        let rect = CGRect(x: 0, y: 0, width: CGFloat(pixels.width), height: height).integral
        guard let crop = pixels.cropping(to: rect) else { return }
        let evidence = XCTAttachment(image: UIImage(cgImage: crop))
        evidence.name = "autofill-native-picker-header-crop"
        evidence.lifetime = .keepAlways; add(evidence)
    }
    private func labeledRowTextField(_ label: String, in surface: XCUIApplication) -> XCUIElement {
        let row = surface.cells.containing(.staticText, identifier: label).firstMatch
        if row.exists && row.textFields.count == 1 { return row.textFields.firstMatch }
        if row.exists && row.textViews.count == 1 { return row.textViews.firstMatch }
        let aliases = label == "User Name" ? [label, "Username"] : [label]
        let direct = surface.textFields.matching(NSPredicate(format: "label IN %@ OR placeholderValue IN %@", aliases, aliases)).firstMatch
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
    private func recordNativeFormReadiness(phase: String, website: XCUIElement, username: XCUIElement,
                                           passwordField: XCUIElement, save: XCUIElement, site: String, email: String) {
        let found = passwordField.exists
        let report: [String: Any] = ["phase": phase,
            "websiteMatches": website.exists && website.value as? String == site,
            "usernameMatches": username.exists && username.value as? String == email,
            "passwordFieldFound": found, "passwordFieldHittable": found && passwordField.isHittable,
            "saveEnabled": save.exists && save.isEnabled]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]), let text = String(data: data, encoding: .utf8) {
            let evidence = XCTAttachment(string: text)
            evidence.name = "autofill-native-form-readiness"
            evidence.lifetime = .keepAlways; add(evidence)
        }
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
        let labels = ["Website or Label", "Website or App", "Website", "App or Website", "User Name", "Username", "Password", "Notes", "Save", "Done", "Cancel", "New Password", "All", "Search", "No Passwords", "example.com", "Passwords", "Password AutoFill", "AutoFill", "Other Passwords", "Other Passwords…", "كلمات السر", "كلمات المرور", "تعبئة تلقائية", "كلمات سر أخرى"]
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

import Foundation
import XCTest
import LocalAuthentication

/// Diagnostic-branch only. Append to the existing UI-test source file so the
/// proven Xcode UI runner executes this without a separate observer app.
/// Host variables TEST_RUNNER_NIDAA_BIOMETRY_* arrive here without TEST_RUNNER_.
/// This records availability; an XCTest pass is not biometric authentication
/// or evidence that Password AutoFill succeeded.
final class BiometryCapabilityUITests: XCTestCase {
    func testObserveBiometry() {
        #if targetEnvironment(simulator)
        let environment = ProcessInfo.processInfo.environment
        guard let phase = environment["NIDAA_BIOMETRY_PHASE"],
              phase == "before" || phase == "after" else {
            XCTFail("Missing or invalid biometry diagnostic phase")
            return
        }
        guard let nonce = environment["NIDAA_BIOMETRY_NONCE"],
              nonce.utf8.count == 32,
              nonce.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else {
            XCTFail("Missing or invalid biometry diagnostic nonce")
            return
        }
        guard let owned = environment["NIDAA_BIOMETRY_OWNED_UDID"],
              UUID(uuidString: owned) != nil,
              environment["SIMULATOR_UDID"] == owned else {
            // Never include either device identifier in an assertion message.
            XCTFail("Biometry diagnostic does not match the owned Simulator")
            return
        }

        guard let usageDescription = Bundle.main.object(forInfoDictionaryKey: "NSFaceIDUsageDescription") as? String,
              !usageDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            XCTFail("Biometry diagnostic runner is missing its Face ID usage description")
            return
        }
        let context = LAContext()
        defer { context.invalidate() }
        var error: NSError?
        let available = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        let observation: [String: Any] = [
            "schemaVersion": 1,
            "phase": phase,
            "nonce": nonce,
            "policy": 1,
            "canEvaluate": available,
            "laErrorCode": error?.code ?? 0,
            "errorIsLocalAuthentication": error == nil || error?.domain == LAError.errorDomain,
            "biometryType": context.biometryType.rawValue,
            "authenticationPromptRequested": false
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: observation, options: [.sortedKeys])
            var output = Data("NIDAA_BIOMETRY_OBSERVATION:".utf8)
            output.append(data)
            output.append(10)
            // One complete parser record. The nonce is a nonsecret freshness
            // marker; the host validates and strips it before public export.
            // No device ID, localized error, credentials or app data is emitted.
            FileHandle.standardOutput.write(output)
            guard let line = String(data: output, encoding: .utf8) else {
                XCTFail("Biometry diagnostic record could not be encoded")
                return
            }
            let attachment = XCTAttachment(string: line)
            attachment.name = "nidaa-biometry-observation-" + phase
            attachment.lifetime = .keepAlways
            add(attachment)
        } catch {
            XCTFail("Biometry diagnostic record could not be serialized")
        }
        #else
        XCTFail("Biometry diagnostic requires the owned disposable Simulator")
        #endif
    }
}

// DIAGNOSTIC BRANCH ONLY. Append this extension to AutoFillUITests.swift.
// Insert exactly once, before its first existing call to
// skipOnlyObservedPersonalRequirement(in: [passwords, springboard]):
// recordEarlyPasswordsEntry(passwords: passwords, springboard: springboard)
// The caller has not yet opened New Password or entered fixture credentials.
extension AutoFillUITests {
    private func recordEarlyPasswordsEntry(passwords: XCUIApplication, springboard: XCUIApplication) {
        let allowed = pickerDiagnosticAllowedStrings()
        var nodes: [[String: Any]] = []
        var complete = true
        var truncated = false
        func visit(_ snapshot: XCUIElementSnapshot, surface: String, parent: Int, depth: Int) {
            guard nodes.count < 2000, depth < 50 else { truncated = true; return }
            let frame = snapshot.frame
            guard [frame.minX, frame.minY, frame.width, frame.height].allSatisfy({ $0.isFinite }) else {
                complete = false; return
            }
            let index = nodes.count
            let label = snapshot.label
            let identifier = snapshot.identifier
            nodes.append([
                "surface": surface, "node": index, "parent": parent,
                "role": Int(snapshot.elementType.rawValue),
                "frame": [frame.minX, frame.minY, frame.width, frame.height],
                "label": allowed.contains(label) ? label : "[redacted]",
                "identifier": allowed.contains(identifier) ? identifier : "[redacted]"
            ])
            for child in snapshot.children { visit(child, surface: surface, parent: index, depth: depth + 1) }
        }
        for (name, surface) in [("passwords", passwords), ("springboard", springboard)] {
            do { visit(try surface.snapshot(), surface: name, parent: -1, depth: 0) }
            catch { complete = false } // No raw error or snapshot dump.
        }
        let report: [String: Any] = [
            "phase": "passwords_entry_after_onboarding",
            "passwordsForeground": passwords.state == .runningForeground,
            "springboardForeground": springboard.state == .runningForeground,
            "snapshotsComplete": complete, "truncated": truncated, "nodes": nodes
        ]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            let tree = XCTAttachment(string: text)
            tree.name = "autofill-passwords-entry-accessibility-tree"
            tree.lifetime = .keepAlways; add(tree)
        }
        // ORIGINAL FULL SCREEN, PRIVATE ONLY. The diagnostic driver keeps this
        // on the disposable runner; neither raw nor encrypted images are uploaded.
        // Snapshot collection can lag UI transitions, so no masking claim is
        // made. This runs before any fixture credential creation or entry.
        let screen = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screen.name = "autofill-passwords-entry-full-screen-private"
        screen.lifetime = .keepAlways; add(screen)
    }
}

// DIAGNOSTIC BRANCH ONLY. Append this extension to AutoFillUITests.swift.
// In testSavedCredentialSelection, insert the following line immediately after
// the existing `pickerButton.tap()` and BEFORE recordFullPickerDiagnostic(after_tap):
//     guard emitPickerMatchRequest() else { return }
// Preserve all existing capture, query, selection, fill and login assertions.
// Host forwards TEST_RUNNER_NIDAA_PICKER_MATCH_NONCE and
// TEST_RUNNER_NIDAA_PICKER_MATCH_OWNED_UDID through xcodebuild's test-runner env.
// This is a one-time experimental request, NOT evidence of an exposed prompt or
// completed biometric action. The host report is authoritative about its action.
// There is no sleep, stdin, app-container/network handshake, or success bypass.
// Raw logs remain runner-private; only fixed validated reports may be exported.

extension AutoFillUITests {
    func emitPickerMatchRequest() -> Bool {
        #if targetEnvironment(simulator)
        let environment = ProcessInfo.processInfo.environment
        guard let nonce = environment["NIDAA_PICKER_MATCH_NONCE"],
              nonce.utf8.count == 32,
              nonce.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              let owned = environment["NIDAA_PICKER_MATCH_OWNED_UDID"],
              UUID(uuidString: owned) != nil,
              environment["SIMULATOR_UDID"] == owned,
              environment["SIMULATOR_DEVICE_NAME"]?.hasPrefix("NIDAA-Disposable-Biometry-") == true else {
            XCTFail("Matching Face diagnostic requires a fresh nonce and the exact owned disposable Simulator")
            return false
        }
        // Write directly to the stdout file descriptor: no stdio buffering and
        // no credential-bearing content. Host accepts one exact complete line.
        let line = "NIDAA_PICKER_MATCH_REQUEST:\(nonce):passwords_picker_tapped\n"
        FileHandle.standardOutput.write(Data(line.utf8))
        return true
        #else
        XCTFail("Matching Face diagnostic is restricted to the disposable Simulator")
        return false
        #endif
    }
}
