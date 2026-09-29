import XCTest
import UIKit

/// Native input coverage with AutoFill ON. Networking is explicitly MOCK here;
/// saved-credential selection is a separate, not yet verified scenario.
final class AutoFillUITests: IntegrationTestCase {
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
                || self.savedIdentityTarget(in: passwords, email: email, site: site) != nil
        }, object: nil)
        _ = XCTWaiter.wait(for: [homeReady], timeout: 8)
        for target in [allButton, allRow, allText] where target.exists && target.isHittable {
            target.tap(); allListOpened = true; break
        }
        let persisted = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.savedIdentityTarget(in: passwords, email: email, site: site) != nil
        }, object: nil)
        let persistedEntryFound = XCTWaiter.wait(for: [persisted], timeout: 8) == .completed
        attachDiagnosticBooleans(["allListOpened": allListOpened, "persistedEntryFound": persistedEntryFound,
                                  "passwordsForeground": passwords.state == .runningForeground], name: "autofill-saved-entry-persistence")
        if !persistedEntryFound { recordKnownSystemControls(in: passwords, stage: "saved-entry-persistence") }
        passwords.terminate()
        // Inspect provider configuration even if persistence failed, preserving
        // both independent pieces of setup evidence before the explicit failure.
        try recordNativeProviderConfiguration()
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
        recordFullPickerDiagnostic(phase: "before_tap", app: nativeApp, springboard: springboard, passwords: passwords)
        pickerButton.tap()
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
                let other = self.namedButton(["Other Passwords", "Other Passwords…", "كلمات سر أخرى", "كلمات مرور أخرى"], in: surface)
                if other.exists && other.isHittable { otherPasswords = other; return true }
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
        selectedTarget.tap()
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
    private func attachDiagnosticBooleans(_ report: [String: Bool], name: String) {
        guard let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return }
        let evidence = XCTAttachment(string: text)
        evidence.name = name; evidence.lifetime = .keepAlways; add(evidence)
    }
    private func recordNativeProviderConfiguration() throws {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        settings.launch()
        defer { settings.terminate() }
        let global = settings.switches["AutoFillToggle"].firstMatch
        // Settings may restore its last visited page after termination.
        if !global.waitForExistence(timeout: 3) {
            if !settings.navigationBars["General"].exists { try openSettingsRow("General", in: settings) }
            try openSettingsRow("AutoFill & Passwords", in: settings)
        }
        _ = global.waitForExistence(timeout: 5)
        let providerSwitch = settings.switches.matching(NSPredicate(format: "label == %@ OR identifier == %@", "Passwords", "Passwords")).firstMatch
        let providerCell = settings.cells.containing(.staticText, identifier: "Passwords").firstMatch
        let providerButton = settings.buttons["Passwords"].firstMatch
        let providerText = settings.staticTexts["Passwords"].firstMatch
        func state(_ control: XCUIElement) -> (known: Bool, enabled: Bool) {
            guard control.exists, let value = (control.value as? String)?.lowercased() else { return (false, false) }
            if value == "1" || value == "on" { return (true, true) }
            if value == "0" || value == "off" { return (true, false) }
            return (false, false)
        }
        let globalState = state(global)
        let providerState = state(providerSwitch)
        attachDiagnosticBooleans(["globalEnabledKnown": globalState.known, "globalEnabled": globalState.enabled,
            "providerControlObserved": providerSwitch.exists || providerCell.exists || providerButton.exists || providerText.exists,
            "providerEnabledKnown": providerState.known, "providerEnabled": providerState.enabled], name: "autofill-native-provider-state")
        func attachRow(_ row: XCUIElement, name: String) {
            guard row.exists, row.isHittable else { return }
            let frame = row.frame
            // Only the fresh Simulator's named settings controls; never a full
            // Settings screen, Apple account header or credential detail.
            guard frame.height > 0, frame.height <= 120, frame.width > 0,
                  UIScreen.main.bounds.contains(frame) else { return }
            let image = XCTAttachment(screenshot: row.screenshot())
            image.name = name; image.lifetime = .keepAlways; add(image)
        }
        attachRow(global, name: "autofill-native-provider-global-toggle")
        for row in [providerSwitch, providerCell, providerButton, providerText] where row.exists && row.isHittable {
            attachRow(row, name: "autofill-native-provider-row"); break
        }
    }
    private func pickerDiagnosticAllowedStrings() -> Set<String> {
        ["", "[redacted]", "Passwords", "Password", "Password AutoFill", "AutoFill Password", "Fill Password",
         "AutoFill", "AutoFill…", "Other Passwords", "Other Passwords…", "Open Passwords", "Search", "Search Passwords",
         "Allow", "Don’t Allow", "Don't Allow", "Continue", "Cancel", "Done", "Close", "Back", "Save", "New Password",
         "User Name", "Username", "Website or Label", "Website or App", "Notes", "All", "Passkeys", "Codes", "Deleted",
         "Sign In to iCloud", "Sign in to your Apple Account", "Set Up a Passcode", "Enter iPhone Passcode", "Use Passcode",
         "Face ID", "Touch ID", "Authentication Required", "Unlock Passwords", "Select All", "Select", "Paste", "Copy", "Cut",
         "كلمات السر", "كلمات المرور", "تعبئة كلمات السر", "تعبئة تلقائية", "تعبئة تلقائية…", "كلمات سر أخرى", "كلمات مرور أخرى",
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
        // Full screen, retaining native layout. Export is fail-closed; redact all
        // editable rectangles plus every non-whitelisted text-bearing leaf/row.
        // These opaque masks are diagnostic redactions, not product screenshots.
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
    private func savedIdentityTarget(in surface: XCUIApplication, email: String, site: String) -> XCUIElement? {
        let identity = NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@", email, site)
        let candidates = surface.buttons.matching(identity).allElementsBoundByIndex
            + surface.cells.matching(identity).allElementsBoundByIndex
            + surface.cells.containing(.staticText, identifier: email).allElementsBoundByIndex
            + surface.cells.containing(.staticText, identifier: site).allElementsBoundByIndex
            + surface.staticTexts.matching(identity).allElementsBoundByIndex
        return candidates.first { $0.exists && $0.isHittable }
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
