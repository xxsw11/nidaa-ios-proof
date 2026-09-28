import XCTest
@testable import ProofCore

private final class MemoryArchive: ArchiveIO {
    var data: Data?
    var failRead = false, failWrite = false
    func read() throws -> Data? { if failRead { throw ArchiveError.unreadable };return data }
    func replace(with data: Data) throws { if failWrite { throw ArchiveError.writeFailed };self.data = data }
}
final class StabilizationTests: XCTestCase {
    let t = Date(timeIntervalSince1970: 2_000_000_000)
    var sara: UUID { TrustedContact.samples[0].id }
    var ahmad: UUID { TrustedContact.samples[1].id }
    func model(both: Bool = false) throws -> LocalSimulation {
        var m = LocalSimulation(), gate = SendGate()
        let ids: Set<UUID> = both ? [sara, ahmad] : [sara]
        gate.authorize(success: true, recipients: ids, kind: .urgent, at: t)
        _ = try m.create(recipients: ids, kind: .urgent, gate: &gate, at: t);return m
    }
    func grant(_ m: LocalSimulation, action: AlertAction) throws -> (AlertActionDetails, AlertActionGate) {
        let d = try m.actionDetails(m.alerts[0].id, action: action, at: t)
        var g = AlertActionGate();g.authorize(success: true, details: d, at: t);return (d,g)
    }
    func testRoundTripPreservesCompleteEventHistoryAndDirection() throws {
        var m = try model(both: true);let id = m.alerts[0].id
        try m.transition(id,recipient: sara,to: .received,at: t.addingTimeInterval(1))
        try m.transition(id,recipient: sara,to: .opened,at: t.addingTimeInterval(2))
        try m.transition(id,recipient: sara,to: .responding,at: t.addingTimeInterval(3))
        m.silence(id,dismiss: true,at: t.addingTimeInterval(4))
        var (d,g) = try grant(m,action: .retry);try m.perform(d,gate: &g,at: t.addingTimeInterval(5))
        _ = try m.incoming(from: ahmad,at: t)
        let io = MemoryArchive(), repo = AlertRepository(io: MemoryArchive())
        _ = try repo.load(legacyContacts: [],at: t)
        let disk = AlertRepository(io: io);_ = try disk.load(legacyContacts: m.contacts,at: t);try disk.save(m)
        let restored = try AlertRepository(io: io).load(legacyContacts: [],at: t.addingTimeInterval(6))
        XCTAssertEqual(restored.alerts,m.alerts);XCTAssertEqual(restored.contacts,m.contacts)
    }
    func testExpiryOnRestoreDoesNotExtendOrRepeatEvents() throws {
        let m = try model(), io = MemoryArchive(), repo = AlertRepository(io: MemoryArchive())
        _ = try repo.load(legacyContacts: [],at: t)
        io.data = try JSONEncoder().encode(AlertArchive(contacts: m.contacts,alerts: m.alerts))
        let r = try AlertRepository(io: io).load(legacyContacts: [],at: t.addingTimeInterval(301))
        XCTAssertEqual(r.alerts[0].state,.expired);XCTAssertEqual(r.alerts[0].expiresAt,m.alerts[0].expiresAt)
        XCTAssertEqual(r.alerts[0].attempts,1)
        let again = try AlertRepository(io: io).load(legacyContacts: [],at: t.addingTimeInterval(400))
        XCTAssertEqual(r.alerts,again.alerts)
    }
    func testAllTerminalStatesStayTerminalAfterRestoreAndClockRollback() throws {
        for state in [LocalAlertState.cancelled,.resolved,.expired] {
            var m = try model();let id = m.alerts[0].id
            if state == .expired { m.tick(at: t.addingTimeInterval(301)) } else { try m.close(id,state: state,at: t) }
            let io = MemoryArchive();io.data = try JSONEncoder().encode(AlertArchive(contacts:m.contacts,alerts:m.alerts))
            let r = try AlertRepository(io:io).load(legacyContacts:[],at:t.addingTimeInterval(-100))
            XCTAssertEqual(r.alerts,m.alerts)
        }
    }
    func testCorruptAndFutureSchemaBlockSavesWithoutReplacingBytes() throws {
        for bytes in [Data("bad".utf8),Data("{\"schemaVersion\":99}".utf8)] {
            let io = MemoryArchive();io.data = bytes;let repo = AlertRepository(io:io)
            XCTAssertThrowsError(try repo.load(legacyContacts:[],at:t))
            XCTAssertThrowsError(try repo.save(LocalSimulation()));XCTAssertEqual(io.data,bytes)
        }
    }
    func testReadFailureIsNotMissingAndSaveFailureRetainsValidCopy() throws {
        let io = MemoryArchive(), m = try model();io.data = try JSONEncoder().encode(AlertArchive(contacts:m.contacts,alerts:m.alerts))
        let original = io.data;io.failRead = true;let repo = AlertRepository(io:io)
        XCTAssertThrowsError(try repo.load(legacyContacts:[],at:t));XCTAssertEqual(io.data,original)
        io.failRead = false;_ = try repo.load(legacyContacts:[],at:t);let valid = io.data
        io.failWrite = true;XCTAssertThrowsError(try repo.save(LocalSimulation()));XCTAssertEqual(io.data,valid)
        XCTAssertThrowsError(try repo.reset());XCTAssertEqual(io.data,valid)
    }
    func testExplicitResetRecoversCorruptionAndClearsPersistentHistory() throws {
        let io = MemoryArchive();io.data = Data("bad".utf8);let repo = AlertRepository(io:io)
        XCTAssertThrowsError(try repo.load(legacyContacts:[],at:t));_ = try repo.reset()
        let restored = try AlertRepository(io:io).load(legacyContacts:[],at:t)
        XCTAssertTrue(restored.alerts.isEmpty);XCTAssertEqual(restored.contacts,TrustedContact.samples)
    }
    func testVersionOneMigrationIsAtomicAndPreservesDeadlines() throws {
        let m = try model();let io = MemoryArchive()
        struct V1: Encodable { let schemaVersion = 1;let alerts:[LocalAlert] }
        io.data = try JSONEncoder().encode(V1(alerts:m.alerts));let old = io.data
        io.failWrite = true;XCTAssertThrowsError(try AlertRepository(io:io).load(legacyContacts:m.contacts,at:t))
        XCTAssertEqual(io.data,old);io.failWrite = false
        let r = try AlertRepository(io:io).load(legacyContacts:m.contacts,at:t)
        XCTAssertEqual(r.alerts,m.alerts);XCTAssertEqual(try JSONDecoder().decode(AlertArchive.self,from:XCTUnwrap(io.data)).schemaVersion,2)
    }
    func testRealFileIOAndSeparateTestDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let app = AlertRepository(io:FileArchiveIO(directory:root.appendingPathComponent("app")))
        let tests = AlertRepository(io:FileArchiveIO(directory:root.appendingPathComponent("tests")))
        _ = try app.load(legacyContacts:TrustedContact.samples,at:t);try app.save(model())
        _ = try tests.reset();XCTAssertTrue(try tests.load(legacyContacts:[],at:t).alerts.isEmpty)
        XCTAssertEqual(try app.load(legacyContacts:[],at:t).alerts.count,1)
    }
    func testAuthorizationNeverEncodedOrRestored() throws {
        var m = try model();let (d,_) = try grant(m,action:.retry)
        let bytes = try JSONEncoder().encode(AlertArchive(contacts:m.contacts,alerts:m.alerts))
        let json = String(decoding:bytes,as:UTF8.self)
        XCTAssertFalse(json.contains("issuedAt"));XCTAssertFalse(json.contains("authorization"))
        var fresh = AlertActionGate();XCTAssertThrowsError(try m.perform(d,gate:&fresh,at:t))
    }
    func testBothActionsRequireSuccessAndSingleUseBoundGrant() throws {
        for action in [AlertAction.retry,.addRecipient(ahmad)] {
            for success in [false,true] {
                var m = try model();let d = try m.actionDetails(m.alerts[0].id,action:action,at:t)
                var g = AlertActionGate();g.authorize(success:success,details:d,at:t)
                if success { try m.perform(d,gate:&g,at:t) } else { XCTAssertThrowsError(try m.perform(d,gate:&g,at:t)) }
                XCTAssertThrowsError(try m.perform(d,gate:&g,at:t))
            }
        }
    }
    func testGrantExpiryBackgroundAndMismatchedActionOrAlert() throws {
        for action in [AlertAction.retry,.addRecipient(ahmad)] {
            for delay in [-1.0,15,301] {
                var m = try model();var (d,g) = try grant(m,action:action)
                XCTAssertThrowsError(try m.perform(d,gate:&g,at:t.addingTimeInterval(delay)))
            }
            var m = try model();var (d,g) = try grant(m,action:action);g.invalidate()
            XCTAssertThrowsError(try m.perform(d,gate:&g,at:t))
            (d,g) = try grant(m,action:action)
            let other = try model();let wrong = try other.actionDetails(other.alerts[0].id,action:action,at:t)
            XCTAssertThrowsError(try m.perform(wrong,gate:&g,at:t))
        }
        var m = try model();var (_,g) = try grant(m,action:.retry)
        let otherAction = try m.actionDetails(m.alerts[0].id,action:.addRecipient(ahmad),at:t)
        XCTAssertThrowsError(try m.perform(otherAction,gate:&g,at:t))
    }
    func testDeletionBlockingConsentAndChangedDetailsRejectAuthenticatedAction() throws {
        for action in [AlertAction.retry,.addRecipient(ahmad)] {
            for change in ["delete","block","consent","rename"] {
                var m = try model();var (d,g) = try grant(m,action:action);var c = d.recipients[0]
                if change == "delete" { m.deleteContact(c.id) }
                else { if change == "block" { c.state = .blocked };if change == "consent" { c.allowsOutgoing = false };if change == "rename" { c.name = "نور" };try m.saveContact(c) }
                XCTAssertThrowsError(try m.perform(d,gate:&g,at:t));XCTAssertEqual(m.alerts[0].attempts,1)
            }
        }
    }
    func testRetryExcludesResponsesAndPreservesIdentityAndTimestamps() throws {
        var m = try model(both:true);let id = m.alerts[0].id
        try m.transition(id,recipient:sara,to:.received,at:t);try m.transition(id,recipient:sara,to:.responding,at:t)
        var (d,g) = try grant(m,action:.retry);XCTAssertEqual(d.recipients.map(\.id),[ahmad])
        let before = m.alerts[0];try m.perform(d,gate:&g,at:t)
        XCTAssertEqual(m.alerts[0].id,id);XCTAssertEqual(m.alerts[0].recipients,before.recipients);XCTAssertEqual(m.alerts[0].expiresAt,before.expiresAt)
        try m.transition(id,recipient:ahmad,to:.received,at:t);try m.transition(id,recipient:ahmad,to:.declined,at:t)
        XCTAssertThrowsError(try m.actionDetails(id,action:.retry,at:t))
    }
    func testAdditionPreservesExistingStateDeadlineAndAttempts() throws {
        var m = try model();let before = m.alerts[0];var (d,g) = try grant(m,action:.addRecipient(ahmad))
        try m.perform(d,gate:&g,at:t)
        XCTAssertEqual(m.alerts[0].recipients.first,before.recipients.first);XCTAssertEqual(m.alerts[0].expiresAt,before.expiresAt)
        XCTAssertEqual(m.alerts[0].attempts,before.attempts)
    }
}
