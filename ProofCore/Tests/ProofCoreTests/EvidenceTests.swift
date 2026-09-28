import XCTest
@testable import ProofCore

final class EvidenceTests: XCTestCase {
    let t = Date(timeIntervalSince1970: 2_000_000_000)
    func make(_ kind: NotificationKind = .local) -> IncidentEvidence {
        IncidentEvidence(id: UUID(), kind: kind, expiresAt: t.addingTimeInterval(60))
    }
    func testWindowRejectsBlankAliasAndOverlongOrExpiredScope() {
        XCTAssertFalse(TestWindow(deviceAlias: " ", startsAt: t, endsAt: t.addingTimeInterval(60)).allows(at: t))
        XCTAssertFalse(TestWindow(deviceAlias: "TEST-PHONE", startsAt: t, endsAt: t.addingTimeInterval(7201)).allows(at: t))
        XCTAssertFalse(TestWindow(deviceAlias: "TEST-PHONE", startsAt: t, endsAt: t).allows(at: t))
    }
    func testScheduleMustRemainInsideConfirmedWindow() {
        let w = TestWindow(deviceAlias: "TEST-PHONE", startsAt: t, endsAt: t.addingTimeInterval(60))
        XCTAssertTrue(w.allows(at: t, scheduledFor: t.addingTimeInterval(15)))
        XCTAssertFalse(w.allows(at: t, scheduledFor: w.endsAt))
        XCTAssertFalse(w.allows(at: t.addingTimeInterval(-1)))
    }
    func testLocalScheduleIsNeitherProviderAcceptanceNorDeviceReceipt() {
        var e = make();e.recordLocalScheduling(at: t);e.recordProviderAcceptance(at: t)
        XCTAssertNotNil(e.locallyScheduledAt);XCTAssertNil(e.providerAcceptedAt)
        XCTAssertNil(e.observedAt);XCTAssertNil(e.humanRespondedAt)
    }
    func testProviderAcceptanceDoesNotProveDeviceReceipt() {
        var e = make(.remote);e.recordProviderAcceptance(at: t);e.recordLocalScheduling(at: t)
        XCTAssertNotNil(e.providerAcceptedAt);XCTAssertNil(e.locallyScheduledAt)
        XCTAssertNil(e.observedAt);XCTAssertNil(e.humanRespondedAt)
    }
    func testOpeningNotificationNeverAcceptsResponsibility() {
        var e = make(.remote);e.observe(.notificationOpened, at: t)
        XCTAssertNotNil(e.observedAt);XCTAssertNil(e.humanRespondedAt)
        XCTAssertNil(e.providerAcceptedAt)
    }
    func testResponseRequiresObservationAndAuthentication() {
        var e = make();XCTAssertFalse(e.respond(at: t, authenticated: true))
        e.observe(.foregroundCallback, at: t)
        XCTAssertFalse(e.respond(at: t, authenticated: false))
        XCTAssertTrue(e.respond(at: t, authenticated: true))
        XCTAssertFalse(e.respond(at: t, authenticated: true))
    }
    func testLateObservationIsRecordedButCannotReopenExpiredTest() {
        var e = make();e.observe(.notificationCenterInventory, at: t.addingTimeInterval(70))
        XCTAssertNotNil(e.observedAt)
        XCTAssertFalse(e.respond(at: t.addingTimeInterval(70), authenticated: true))
    }
    func testCancellationPreventsHumanResponseAndLateScheduling() {
        var e = make();e.cancel(at: t);e.observe(.notificationOpened, at: t)
        e.recordLocalScheduling(at: t)
        XCTAssertFalse(e.respond(at: t, authenticated: true));XCTAssertNil(e.locallyScheduledAt)
    }
    func testDuplicateObservationDoesNotResetFirstEvidence() {
        var e = make();e.observe(.foregroundCallback, at: t)
        e.observe(.notificationOpened, at: t.addingTimeInterval(10))
        XCTAssertEqual(e.observedAt, t);XCTAssertEqual(e.observation, .foregroundCallback)
    }
    func testEnvelopeRejectsUnmarkedMalformedAndMissingExpiration() {
        XCTAssertNil(ProofEnvelope.decode([:], kind: .remote))
        XCTAssertNil(ProofEnvelope.decode(["proof": ProofEnvelope.marker, "incident_id": "not-a-uuid", "expires_at": 1], kind: .remote))
        let input = ProofEnvelope(id: UUID(), kind: .remote, expiresAt: t)
        let output = ProofEnvelope.decode(input.userInfo, kind: .remote)
        XCTAssertEqual(output?.id, input.id);XCTAssertEqual(output?.expiresAt, t)
        XCTAssertEqual(output?.kind, .remote)
    }
}
