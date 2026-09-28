import XCTest
@testable import ProofCore

final class SimulationTests: XCTestCase {
    let t = Date(timeIntervalSince1970: 2_000_000_000)
    var sara: UUID { TrustedContact.samples[0].id }
    var ahmad: UUID { TrustedContact.samples[1].id }
    func create(_ model: inout LocalSimulation, ids: Set<UUID>? = nil, at time: Date? = nil) throws -> UUID {
        let now = time ?? t, recipients = ids ?? [sara]
        var gate = SendGate();gate.authorize(success: true, recipients: recipients, kind: .urgent, at: now)
        return try model.create(recipients: recipients, kind: .urgent, gate: &gate, at: now)
    }
    func testCreationRequiresFreshAuthenticationNotAnUnlockedApp() {
        var model = LocalSimulation(), gate = SendGate()
        XCTAssertThrowsError(try model.create(recipients: [sara], kind: .urgent, gate: &gate, at: t))
        XCTAssertTrue(model.alerts.isEmpty)
    }
    func testFailureOrCancelledAuthenticationCreatesNothing() {
        var model = LocalSimulation(), gate = SendGate()
        gate.authorize(success: false, recipients: [sara], kind: .urgent, at: t)
        XCTAssertThrowsError(try model.create(recipients: [sara], kind: .urgent, gate: &gate, at: t))
        XCTAssertTrue(model.alerts.isEmpty)
    }
    func testBackgroundInvalidationAndExpiredGrantCannotCreate() {
        var model = LocalSimulation(), gate = SendGate()
        gate.authorize(success: true, recipients: [sara], kind: .urgent, at: t);gate.invalidate()
        XCTAssertThrowsError(try model.create(recipients: [sara], kind: .urgent, gate: &gate, at: t))
        gate.authorize(success: true, recipients: [sara], kind: .urgent, at: t)
        XCTAssertThrowsError(try model.create(recipients: [sara], kind: .urgent, gate: &gate, at: t.addingTimeInterval(15)))
    }
    func testChangedRecipientOrAssistanceInvalidatesGrant() {
        var model = LocalSimulation(), gate = SendGate()
        gate.authorize(success: true, recipients: [sara], kind: .urgent, at: t)
        XCTAssertThrowsError(try model.create(recipients: [ahmad], kind: .urgent, gate: &gate, at: t))
        gate.authorize(success: true, recipients: [sara], kind: .urgent, at: t)
        XCTAssertThrowsError(try model.create(recipients: [sara], kind: .call, gate: &gate, at: t))
    }
    func testOneUseGrantAndDuplicatePrevention() throws {
        var model = LocalSimulation(), gate = SendGate()
        gate.authorize(success: true, recipients: [sara], kind: .urgent, at: t)
        let id = try model.create(recipients: [sara], kind: .urgent, gate: &gate, at: t)
        XCTAssertThrowsError(try model.create(recipients: [sara], kind: .urgent, gate: &gate, at: t))
        XCTAssertEqual(try create(&model),id);XCTAssertEqual(model.alerts.count,1)
    }
    func testPendingDeclinedBlockedAndMissingConsentCannotSend() throws {
        for state in InvitationState.allCases {
            var model = LocalSimulation()
            var c = model.contacts[0];c.state = state;c.allowsOutgoing = false;try model.saveContact(c)
            XCTAssertThrowsError(try create(&model));XCTAssertTrue(model.alerts.isEmpty)
        }
    }
    func testRevocationAfterAuthenticationIsRechecked() throws {
        var model = LocalSimulation(), gate = SendGate()
        gate.authorize(success: true, recipients: [sara], kind: .urgent, at: t)
        var c = model.contacts[0];c.state = .blocked;try model.saveContact(c)
        XCTAssertFalse(model.contacts[0].allowsOutgoing);XCTAssertFalse(model.contacts[0].allowsIncoming)
        XCTAssertThrowsError(try model.create(recipients: [sara], kind: .urgent, gate: &gate, at: t))
    }
    func testDeleteContactPreventsLaterSendButRetainsSessionSnapshot() throws {
        var model = LocalSimulation();let id = try create(&model)
        model.deleteContact(sara)
        XCTAssertEqual(model.alerts[0].recipients[0].name,"سارة")
        XCTAssertThrowsError(try model.retry(id,at: t))
        XCTAssertThrowsError(try create(&model))
    }
    func testReceiptOpeningAndResponseAreDifferentTransitions() throws {
        var model = LocalSimulation();let id = try create(&model)
        XCTAssertThrowsError(try model.transition(id,recipient: sara,to: .responding,at: t))
        try model.transition(id,recipient: sara,to: .received,at: t)
        try model.transition(id,recipient: sara,to: .opened,at: t)
        XCTAssertNil(model.alerts[0].recipients[0].respondedAt)
        XCTAssertTrue(model.alerts[0].isActive)
        try model.transition(id,recipient: sara,to: .responding,at: t)
        XCTAssertTrue(model.alerts[0].isActive)
        XCTAssertThrowsError(try model.transition(id,recipient: sara,to: .opened,at: t))
    }
    func testDeclineDoesNotResolveAndAllowsConsentingAlternative() throws {
        var model = LocalSimulation();let id = try create(&model)
        try model.transition(id,recipient: sara,to: .received,at: t)
        try model.transition(id,recipient: sara,to: .declined,at: t)
        XCTAssertTrue(model.alerts[0].isActive)
        try model.addAlternative(id,contactID: ahmad,at: t)
        XCTAssertEqual(model.alerts[0].recipients.count,2)
        XCTAssertThrowsError(try model.addAlternative(id,contactID: ahmad,at: t))
        XCTAssertThrowsError(try model.addAlternative(id,contactID: TrustedContact.samples[2].id,at: t))
    }
    func testSilenceAndDismissDoNotRespondResolveOrDisableNonresponse() throws {
        var model = LocalSimulation();let id = try create(&model)
        model.silence(id,dismiss: true,at: t);model.tick(at: t.addingTimeInterval(26))
        XCTAssertTrue(model.alerts[0].isActive);XCTAssertTrue(model.alerts[0].nonresponse)
        XCTAssertNil(model.alerts[0].recipients[0].respondedAt)
        let events = model.alerts[0].events.count;model.tick(at: t.addingTimeInterval(27));XCTAssertEqual(model.alerts[0].events.count,events)
    }
    func testRetryKeepsIdentityAndResponse() throws {
        var model = LocalSimulation();let id = try create(&model)
        try model.transition(id,recipient: sara,to: .received,at: t)
        try model.transition(id,recipient: sara,to: .responding,at: t)
        try model.retry(id,at: t)
        XCTAssertEqual(model.alerts.count,1);XCTAssertEqual(model.alerts[0].id,id)
        XCTAssertEqual(model.alerts[0].recipients[0].stage,.responding)
    }
    func testExpiredCancelledAndResolvedStatesNeverReopen() throws {
        for state in [LocalAlertState.cancelled,.resolved,.expired] {
            var model = LocalSimulation();let id = try create(&model)
            if state == .expired { model.tick(at: t.addingTimeInterval(300)) } else { try model.close(id,state: state,at: t) }
            XCTAssertEqual(model.alerts[0].state,state)
            XCTAssertThrowsError(try model.retry(id,at: t.addingTimeInterval(301)))
            XCTAssertThrowsError(try model.transition(id,recipient: sara,to: .received,at: t.addingTimeInterval(301)))
        }
    }
    func testIncomingConsentIsIndependentAndOpeningDoesNotRespond() throws {
        var model = LocalSimulation();var c = model.contacts[0];c.allowsIncoming = false;try model.saveContact(c)
        XCTAssertThrowsError(try model.incoming(from: sara,at: t))
        c.allowsIncoming = true;try model.saveContact(c)
        let id = try model.incoming(from: sara,at: t);try model.transition(id,recipient: sara,to: .opened,at: t)
        XCTAssertNil(model.alerts[0].recipients[0].respondedAt)
        XCTAssertThrowsError(try model.close(id,state: .cancelled,at: t))
    }
    func testContactCRUDValidationAndNormalization() throws {
        var model = LocalSimulation();var c = TrustedContact(name: "  ليان  ")
        try model.saveContact(c);XCTAssertEqual(model.contacts.last?.name,"ليان")
        c.name = "نور";try model.saveContact(c);XCTAssertEqual(model.contacts.count,4)
        c.name = " ";XCTAssertThrowsError(try model.saveContact(c))
        model.deleteContact(c.id);XCTAssertEqual(model.contacts.count,3)
    }
}
final class AppearanceTests: XCTestCase {
    func testReadableInkAndAccentMeetThresholdAcrossColors() {
        for value in ["#000000","#FFFFFF","#777777","#FFDC38","#101110","#888888","#00FF00","#FF0000","#0000FF"] {
            let c = HexColor(value)!;XCTAssertGreaterThanOrEqual(c.contrast(c.readableInk),4.5)
            let p = Palette(primary: "#777777",button: value,background: value)
            XCTAssertGreaterThanOrEqual(c.contrast(p.accentInk),4.5)
        }
    }
    func testInvalidHexAndFutureSchemaAreRejected() {
        for v in ["#abc","red","#12345G","#12345678",""] { XCTAssertNil(HexColor(v)) }
        var p = AppearancePreferences();p.dark.button = "wrong";XCTAssertFalse(p.valid)
        p = .init();p.version = 99;XCTAssertFalse(p.valid)
    }
    func testAppearancePersistsAcrossRepositoryInstancesAndRestores() throws {
        let name = "nidaa.tests.\(UUID())", defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        var p = AppearancePreferences();p.dark.button = "#99CCFF";p.mode = .system
        try DemoPreferences(defaults: defaults).saveAppearance(p)
        XCTAssertEqual(DemoPreferences(defaults: defaults).loadAppearance(),p)
        try DemoPreferences(defaults: defaults).saveAppearance(.init())
        XCTAssertEqual(DemoPreferences(defaults: defaults).loadAppearance(),.init())
    }
    func testCorruptPersistenceFallsBackAndResetRemovesStoredContactsAndLock() throws {
        let name = "nidaa.tests.\(UUID())", defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let prefs = DemoPreferences(defaults: defaults)
        defaults.set(Data("broken".utf8),forKey: "nidaa.native.appearance")
        XCTAssertEqual(prefs.loadAppearance(),.init())
        try prefs.saveContacts([]);prefs.appLock = true
        XCTAssertTrue(DemoPreferences(defaults: defaults).loadContacts().isEmpty)
        prefs.reset();XCTAssertEqual(prefs.loadContacts(),TrustedContact.samples);XCTAssertFalse(prefs.appLock)
    }
    func testSystemAndIndependentPalettes() {
        var p = AppearancePreferences();p.mode = .system;p.light.background = "#FFFFFF"
        XCTAssertEqual(p.palette(systemDark: true),p.dark);XCTAssertEqual(p.palette(systemDark: false),p.light)
    }
}
