import XCTest
import UIKit

/// One disposable Simulator used sequentially. Real Auth/PostgreSQL/API/inbox;
/// only the separately labeled local-device-auth prompt is simulated.
final class NativeIntegrationUITests: IntegrationTestCase {
    private var fixture: NativeTrialFixture!
    private let password = "Native-Fictional-Only-29!"

    override func setUpWithError() throws {
        try super.setUpWithError()
        guard let capability = ProcessInfo.processInfo.environment["NIDAA_FIXTURE_CAPABILITY"], !capability.isEmpty else {
            throw NativeTrialFixture.Failure.unavailable
        }
        fixture = NativeTrialFixture(capability: capability)
    }
    override func tearDownWithError() throws {
        UIPasteboard.general.items = []
        try? fixture?.control(["action": "offline", "enabled": false])
        // No live failure screenshot or request/response bodies are attached.
        try super.tearDownWithError()
    }
    private func start() {
        launch(extra: ["-nidaa-integration-simulated-device-auth"], live: true)
        XCTAssertFalse(app.staticTexts["integrationMode"].label.contains("MOCK"))
        XCTAssertTrue(app.staticTexts["integrationSimulatedDeviceAuth"].exists)
    }
    private func account(_ prefix: String) -> String { prefix + "-" + UUID().uuidString.lowercased() + "@example.invalid" }
    private func register(_ email: String) throws {
        fill("integrationEmail", email)
        fill("integrationPassword", password, secure: true)
        tap("integrationSignup")
        XCTAssertTrue(app.staticTexts["integrationAwaitingVerification"].waitForExistence(timeout: 12))
        XCTAssertFalse(app.buttons["integrationAccountTab"].exists)
        let token = try fixture.verificationHash(email: email)
        paste("integrationVerificationToken", value: token)
        tap("integrationVerify")
        XCTAssertTrue(app.buttons["integrationAccountTab"].waitForExistence(timeout: 15))
    }
    private func signIn(_ email: String) {
        fill("integrationEmail", email)
        fill("integrationPassword", password, secure: true)
        XCTAssertTrue(app.buttons["integrationSignup"].isEnabled)
        tap("integrationLogin")
        XCTAssertTrue(app.buttons["integrationAccountTab"].waitForExistence(timeout: 15))
    }
    private func signOut() {
        tap("integrationAccountTab"); tap("integrationLogout")
        XCTAssertTrue(app.buttons["integrationLogin"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["integrationContactsTab"].exists)
        XCTAssertFalse(app.staticTexts["integrationAlertState"].exists)
        waitIdle()
    }
    private func connect(_ a: String, _ b: String) throws {
        try register(a); signOut(); try register(b); signOut(); signIn(a)
        tap("integrationContactsTab")
        fill("integrationInviteEmail", b)
        tap("integrationCreateInvite")
        XCTAssertTrue(app.buttons["integrationCopyInvite"].waitForExistence(timeout: 12))
        tap("integrationCopyInvite")
        guard let invitation = UIPasteboard.general.string, !invitation.isEmpty else { throw NativeTrialFixture.Failure.missingToken }
        UIPasteboard.general.items = []
        signOut(); signIn(b); tap("integrationContactsTab")
        paste("integrationInviteToken", value: invitation)
        XCTAssertFalse(app.buttons["integrationAcceptInvite"].isEnabled)
        let consent = app.switches["integrationConsentToggle"]
        reveal(consent); consent.tap()
        tap("integrationAcceptInvite")
        XCTAssertTrue(app.buttons["integrationWithdraw"].waitForExistence(timeout: 12), "Directional consent must exist after explicit acceptance")
        signOut(); signIn(a)
    }
    private func create() {
        tap("integrationAlertsTab")
        let recipient = app.switches.matching(NSPredicate(format: "identifier BEGINSWITH %@", "integrationSelect-")).firstMatch
        reveal(recipient); recipient.tap()
        authorize()
        XCTAssertFalse(app.staticTexts["integrationAlertState"].exists, "Local authentication alone must not create an alert")
        tap("integrationConfirm")
    }
    private func state(_ text: String) {
        let actual = app.staticTexts["integrationAlertState"].firstMatch
        XCTAssertTrue(actual.waitForExistence(timeout: 15))
        let match = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", text), object: actual)
        XCTAssertEqual(XCTWaiter.wait(for: [match], timeout: 15), .completed)
    }

    func testRealSequentialRegistrationConsentResponseResolveRestartAndWithdrawal() throws {
        start()
        let a = account("sara"), b = account("sami")
        try connect(a, b)
        create(); state("نداء نشط")
        XCTAssertEqual(app.staticTexts.matching(identifier: "integrationAlertState").count, 1)
        signOut(); signIn(b); tap("integrationAlertsTab")
        state("نداء نشط")
        tap("integrationAcknowledge"); waitIdle()
        tap("integrationOpenAlert"); waitIdle()
        XCTAssertTrue(app.staticTexts["integrationHumanResponse"].firstMatch.label.contains("لا توجد"))
        tap("integrationRespond"); waitIdle()
        XCTAssertTrue(app.staticTexts["integrationHumanResponse"].firstMatch.label.contains("سأتولى"))
        state("نداء نشط")
        signOut(); signIn(a); tap("integrationAlertsTab")
        XCTAssertTrue(app.staticTexts["integrationHumanResponse"].firstMatch.label.contains("سأتولى"))
        tap("integrationCloseAlert")
        let resolve = app.alerts.buttons["إنهاء الحالة"]
        XCTAssertTrue(resolve.waitForExistence(timeout: 5)); resolve.tap()
        state("انتهت بتأكيد صريح")
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["integrationAccountTab"].waitForExistence(timeout: 15))
        tap("integrationAlertsTab"); state("انتهت بتأكيد صريح")
        shot("native-real-sequential-resolved-after-restart")
        signOut(); signIn(b); tap("integrationContactsTab")
        tap("integrationWithdraw"); waitIdle()
        XCTAssertFalse(app.buttons["integrationWithdraw"].exists)
        signOut(); signIn(a); tap("integrationAlertsTab")
        XCTAssertEqual(app.switches.matching(NSPredicate(format: "identifier BEGINSWITH %@", "integrationSelect-")).count, 0)
        XCTAssertFalse(app.buttons["integrationPrepareCreate"].isEnabled)
        signOut()
    }

    func testRealSeparateFaultFixturesDoNotDuplicateOrReopen() throws {
        start()
        let a = account("noor"), b = account("sara")
        try connect(a, b)
        let baseline = try fixture.state()
        try fixture.control(["action": "offline", "enabled": true])
        tap("integrationRefresh"); waitIdle()
        XCTAssertTrue(app.staticTexts["integrationMessage"].label.contains("تعذر"))
        XCTAssertFalse(app.staticTexts["integrationAlertState"].exists)
        try fixture.control(["action": "offline", "enabled": false])
        tap("integrationRefresh"); waitIdle()
        let reconnected = try fixture.state()
        XCTAssertEqual(reconnected["command_posts"] as? Int, baseline["command_posts"] as? Int, "Reconnect must not dispatch commands")
        XCTAssertEqual(reconnected["alert_count"] as? Int, baseline["alert_count"] as? Int)
        try fixture.control(["action": "drop_next_command_reply"])
        create()
        XCTAssertTrue(app.buttons["integrationLookup"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["integrationPrepareCreate"].isEnabled)
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["integrationLookup"].waitForExistence(timeout: 15))
        tap("integrationLookup"); waitIdle(); tap("integrationAlertsTab")
        state("نداء نشط")
        XCTAssertEqual(app.staticTexts.matching(identifier: "integrationAlertState").count, 1)
        XCTAssertFalse(app.buttons["integrationLookup"].exists)
        let before = try fixture.state()
        XCTAssertEqual(before["command_posts"] as? Int, (baseline["command_posts"] as? Int).map { $0 + 1 }, "Lost reply and lookup must use exactly one command POST")
        XCTAssertEqual(before["alert_count"] as? Int, (baseline["alert_count"] as? Int).map { $0 + 1 }, "Lookup after restart must not duplicate server alerts")
        XCTAssertEqual(before["dropped_replies"] as? Int, (baseline["dropped_replies"] as? Int).map { $0 + 1 })
        guard let alertID = (before["alert_ids"] as? [String])?.last else { throw NativeTrialFixture.Failure.invalidResponse }
        try fixture.control(["action": "expire_alert", "alert_id": alertID])
        tap("integrationRefresh"); state("انتهت الصلاحية")
        XCTAssertFalse(app.buttons["integrationPrepareRetry"].exists)
        try fixture.control(["action": "revoke", "email": a])
        tap("integrationRefresh")
        XCTAssertTrue(app.buttons["integrationLogin"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["integrationAccountTab"].exists)
        XCTAssertFalse(app.staticTexts["integrationAlertState"].exists)
        signIn(a); tap("integrationAlertsTab"); state("انتهت الصلاحية")
        XCTAssertEqual(app.staticTexts.matching(identifier: "integrationAlertState").count, 1)
        signOut()
    }
}

/// Private test-process HTTP only: fixed loopback endpoints, no response bodies
/// in errors or attachments. Inbox links are parsed, never opened or followed.
private struct NativeTrialFixture {
    enum Failure: Error { case unavailable, invalidResponse, missingToken, inboxTimeout }
    let capability: String
    func control(_ payload: [String: Any]) throws {
        _ = try request(port: 55425, path: "control", payload: payload, authorized: true)
    }
    func state() throws -> [String: Any] { try request(port: 55425, path: "state", authorized: true) }
    func verificationHash(email: String) throws -> String {
        let deadline = Date().addingTimeInterval(25)
        while Date() < deadline {
            let listing = try request(port: 55424, path: "api/v1/messages")
            for message in listing["messages"] as? [[String: Any]] ?? [] {
                guard let id = message["ID"] as? String,
                      (message["To"] as? [[String: Any]] ?? []).contains(where: { ($0["Address"] as? String)?.lowercased() == email.lowercased() }) else { continue }
                let full = try request(port: 55424, path: "api/v1/message/" + id)
                let body = ((full["HTML"] as? String ?? "") + "\n" + (full["Text"] as? String ?? "")).replacingOccurrences(of: "&amp;", with: "&")
                let regex = try NSRegularExpression(pattern: "https?://[^\\s<>\"']+")
                for match in regex.matches(in: body, range: NSRange(body.startIndex..<body.endIndex, in: body)) {
                    guard let range = Range(match.range, in: body), let url = URLComponents(string: String(body[range])) else { continue }
                    let values = url.queryItems ?? []
                    if values.first(where: { $0.name == "type" })?.value == "signup",
                       let token = values.first(where: { $0.name == "token" || $0.name == "token_hash" })?.value, !token.isEmpty { return token }
                }
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        throw Failure.inboxTimeout
    }
    private func request(port: Int, path: String, payload: [String: Any]? = nil, authorized: Bool = false) throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/\(path)")!)
        request.timeoutInterval = 10
        if authorized { request.setValue(capability, forHTTPHeaderField: "X-NIDAA-Fixture") }
        if let payload {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        }
        let complete = XCTestExpectation(description: "Private loopback fixture request")
        var result: [String: Any]?
        URLSession.shared.dataTask(with: request) { data, response, _ in
            if let data, let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) {
                result = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            }
            complete.fulfill()
        }.resume()
        guard XCTWaiter.wait(for: [complete], timeout: 12) == .completed, let result else { throw Failure.invalidResponse }
        return result
    }
}
