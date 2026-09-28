import Foundation
import XCTest
@testable import NidaaIntegration

final class ClientSafetyTests: XCTestCase, @unchecked Sendable {
    private let instant = Date(timeIntervalSince1970: 1_800_000_000)

    private func fixture(storage: any ClientStorage = MemoryClientStorage(), port: Int = 55421) async throws -> (NidaaClient, TestTransport) {
        let transport = TestTransport()
        let clock = instant
        let client = NidaaClient(environment: try TrialEnvironment(baseURL: URL(string: "http://127.0.0.1:\(port)")!),
                                storage: storage, transport: transport, now: { clock })
        _ = try await client.signIn(email: "a@example.invalid", password: "fictional-test-password")
        return (client, transport)
    }

    private func envelope(age: Int = 0) -> CommandEnvelope {
        CommandEnvelope(issuedAt: Int(instant.timeIntervalSince1970)-age, command: "create_alert",
                        payload: ["recipient_ids":.array([.string(fixtureB.uuidString)]),
                                  "expires_at":.integer(Int(instant.timeIntervalSince1970)+600)])
    }

    private func paused(_ transport: TestTransport) async throws {
        for _ in 0..<1_000 {
            if await transport.isPaused() { return }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("expected a suspended transport request")
        throw ClientError.invalidResponse
    }

    func testNeverSentDraftAndReconnectDoNotDispatch() async throws {
        let (client, transport) = try await fixture()
        let request = envelope()
        let staged = try await client.stage(request)
        XCTAssertEqual(staged.state, .neverSent)
        let result = try await client.queryPending()
        XCTAssertNil(result)
        _ = try await client.synchronize()
        let posts = await transport.count("/v1/commands")
        XCTAssertEqual(posts, 0)
        let pending = await client.pendingOperation()
        XCTAssertEqual(pending?.envelope, request)
    }

    func testStaleDraftRemainsNeverSentWithoutNetworkMutation() async throws {
        let (client, transport) = try await fixture()
        do { _ = try await client.execute(envelope(age: 61)); XCTFail("stale draft was sent") }
        catch { XCTAssertEqual(error as? ClientError, .neverSent) }
        let pending = await client.pendingOperation()
        XCTAssertEqual(pending?.state, .neverSent)
        let posts = await transport.count("/v1/commands")
        XCTAssertEqual(posts, 0)
    }

    func testSecurePendingWriteFailurePreventsPost() async throws {
        let storage = FailingStorage()
        let (client, transport) = try await fixture(storage: storage)
        let request = envelope()
        _ = try await client.stage(request)
        storage.failWrites()
        do { _ = try await client.execute(request); XCTFail("storage failure permitted a post") }
        catch { XCTAssertEqual(error as? ClientError, .storageUnavailable) }
        let posts = await transport.count("/v1/commands")
        XCTAssertEqual(posts, 0)
        let pending = await client.pendingOperation()
        XCTAssertEqual(pending?.state, .neverSent)
    }

    func testTransportFailureRetainsUnknownAndSameOperationLookupOnly() async throws {
        let (client, transport) = try await fixture()
        let request = envelope()
        await transport.commands(.failure)
        do { _ = try await client.execute(request); XCTFail("transport failure treated as success") }
        catch { XCTAssertEqual(error as? ClientError, .outcomeUnknown(request.operationID)) }
        let unknown = await client.pendingOperation()
        XCTAssertEqual(unknown?.state, .outcomeUnknown)
        XCTAssertEqual(unknown?.envelope, request)
        _ = try await client.synchronize()
        await transport.lookup(Receipt(operationID: request.operationID, status: "accepted", resourceID: fixtureAlert, serverTime: request.issuedAt))
        let receipt = try await client.queryPending()
        XCTAssertEqual(receipt?.operationID, request.operationID)
        let pending = await client.pendingOperation()
        XCTAssertNil(pending)
        let history = await transport.requests()
        XCTAssertEqual(history.filter { $0.path == "/v1/commands" }.count, 1)
        XCTAssertTrue(history.contains { $0.method == "GET" && $0.path == "/v1/operations/"+request.operationID.uuidString.lowercased() })
    }

    func testUnknownReceipt404CannotBecomeNeverSentOrBeDiscarded() async throws {
        let (client, transport) = try await fixture()
        await transport.commands(.failure)
        let request = envelope()
        _ = try? await client.execute(request)
        let query = try await client.queryPending()
        XCTAssertNil(query)
        let pending = await client.pendingOperation()
        XCTAssertEqual(pending?.state, .outcomeUnknown)
        do { try await client.discardUnsent(); XCTFail("uncertain operation was discarded") }
        catch { XCTAssertEqual(error as? ClientError, .pendingUnresolved) }
        do { _ = try await client.execute(envelope()); XCTFail("new operation bypassed uncertainty") }
        catch { XCTAssertEqual(error as? ClientError, .pendingUnresolved) }
        let posts = await transport.count("/v1/commands")
        XCTAssertEqual(posts, 1)
    }

    func testMalformedOrMismatchedReceiptStaysUnknown() async throws {
        for behavior in [CommandBehavior.malformed, .wrongID, .status(503)] {
            let (client, transport) = try await fixture()
            await transport.commands(behavior)
            let request = envelope()
            do { _ = try await client.execute(request); XCTFail("invalid receipt was trusted") }
            catch { XCTAssertEqual(error as? ClientError, .outcomeUnknown(request.operationID)) }
            let pending = await client.pendingOperation()
            XCTAssertEqual(pending?.state, .outcomeUnknown)
        }
    }

    func testUnknownStateSurvivesSameAccountReauthenticationWithoutResend() async throws {
        let (client, transport) = try await fixture()
        let request = envelope()
        await transport.commands(.failure)
        _ = try? await client.execute(request)
        _ = try await client.signIn(email: "a@example.invalid", password: "fictional-test-password")
        let pending = await client.pendingOperation()
        XCTAssertEqual(pending?.envelope, request)
        XCTAssertEqual(pending?.state, .outcomeUnknown)
        let posts = await transport.count("/v1/commands")
        XCTAssertEqual(posts, 1)
    }

    func testAccountSwitchClearsOtherAccountsPendingAndCachedDetails() async throws {
        let storage = MemoryClientStorage()
        let (client, transport) = try await fixture(storage: storage)
        await transport.enqueue(SyncSnapshot(cursor: 1, alerts: [alert()]))
        _ = try await client.synchronize()
        _ = try await client.stage(envelope())
        let account = try await client.signIn(email: "b@example.invalid", password: "fictional-test-password")
        XCTAssertEqual(account.userID, fixtureB)
        let state = await client.currentSnapshot()
        XCTAssertTrue(state.alerts.isEmpty)
        XCTAssertNil(state.pending)
        _ = try await client.signIn(email: "a@example.invalid", password: "fictional-test-password")
        let returned = await client.pendingOperation()
        XCTAssertNil(returned)
    }

    func testDelayedOldCommandResponseCannotMutateNewAccount() async throws {
        let (client, transport) = try await fixture()
        await transport.pauseNext("/v1/commands")
        let request = envelope()
        let old = Task { try await client.execute(request) }
        try await paused(transport)
        _ = try await client.signIn(email: "b@example.invalid", password: "fictional-test-password")
        await transport.release()
        do { _ = try await old.value; XCTFail("old response applied to new account") }
        catch { XCTAssertEqual(error as? ClientError, .staleGeneration) }
        let state = await client.currentSnapshot()
        XCTAssertEqual(state.account?.userID, fixtureB)
        XCTAssertNil(state.pending)
    }

    func testDelayedOldSyncCannotRepopulateAfterSameAccountRelogin() async throws {
        let (client, transport) = try await fixture()
        await transport.enqueue(SyncSnapshot(cursor: 99, alerts: [alert()]))
        await transport.pauseNext("/v1/sync")
        let old = Task { try await client.synchronize() }
        try await paused(transport)
        _ = await client.logout(allDevices: false)
        _ = try await client.signIn(email: "a@example.invalid", password: "fictional-test-password")
        await transport.release()
        do { _ = try await old.value; XCTFail("old sync was applied after relogin") }
        catch { XCTAssertEqual(error as? ClientError, .staleGeneration) }
        let state = await client.currentSnapshot()
        XCTAssertTrue(state.alerts.isEmpty)
        XCTAssertEqual(state.cursor, -1)
    }

    func testDelayedOldAuthCannotOverwriteNewSessionsStorage() async throws {
        let (client, transport) = try await fixture()
        await transport.pauseNext("/auth/v1/token")
        let old = Task { try await client.signIn(email: "a@example.invalid", password: "fictional-test-password") }
        try await paused(transport)
        _ = try await client.signIn(email: "b@example.invalid", password: "fictional-test-password")
        await transport.release()
        do { _ = try await old.value; XCTFail("old authentication replaced current account") }
        catch { XCTAssertEqual(error as? ClientError, .staleGeneration) }
        let refreshed = try await client.refreshSession()
        XCTAssertEqual(refreshed.userID, fixtureB)
    }

    func testVerificationAccountSwitchRejectsPreviousAccountsDelayedSync() async throws {
        let (client, transport) = try await fixture()
        await transport.enqueue(SyncSnapshot(cursor: 99, alerts: [alert()]))
        await transport.pauseNext("/v1/sync")
        let old = Task { try await client.synchronize() }
        try await paused(transport)
        let account = try await client.verify(tokenHash: "fixture-verify-b", kind: .signup)
        XCTAssertEqual(account.userID, fixtureB)
        await transport.release()
        do { _ = try await old.value; XCTFail("old account sync survived a verification account switch") }
        catch { XCTAssertEqual(error as? ClientError, .staleGeneration) }
        let state = await client.currentSnapshot()
        XCTAssertEqual(state.account?.userID, fixtureB)
        XCTAssertTrue(state.alerts.isEmpty)
    }

    func testOutOfOrderSnapshotCannotReopenTerminalAlert() async throws {
        let (client, transport) = try await fixture()
        await transport.enqueue(SyncSnapshot(cursor: 2, alerts: [alert(state: "resolved", version: 2)]))
        _ = try await client.synchronize()
        await transport.enqueue(SyncSnapshot(cursor: 1, alerts: [alert()]))
        let state = try await client.synchronize()
        XCTAssertEqual(state.cursor, 2)
        XCTAssertEqual(state.alerts.first?.state, "resolved")
    }

    func testTombstonesRemoveDetailsAndPartialSnapshotFailsClosed() async throws {
        let (client, transport) = try await fixture()
        await transport.enqueue(SyncSnapshot(cursor: 1, alerts: [alert()]))
        _ = try await client.synchronize()
        await transport.enqueue(SyncSnapshot(cursor: 2, removedIDs: [fixtureAlert]))
        let removed = try await client.synchronize()
        XCTAssertTrue(removed.alerts.isEmpty)
        await transport.enqueue(SyncSnapshot(cursor: 3, fullSnapshot: false, alerts: [alert()]))
        do { _ = try await client.synchronize(); XCTFail("partial snapshot was accepted as complete") }
        catch { XCTAssertEqual(error as? ClientError, .invalidResponse) }
        let state = await client.currentSnapshot()
        XCTAssertTrue(state.alerts.isEmpty)
        XCTAssertEqual(state.cursor, 2)
    }

    func testLogoutWipesBeforeAwaitingServerAndOfflineLogoutIsHonest() async throws {
        let (client, transport) = try await fixture()
        _ = try await client.stage(envelope())
        await transport.pauseNext("/v1/session/logout")
        let logout = Task { await client.logout(allDevices: false) }
        try await paused(transport)
        let state = await client.currentSnapshot()
        XCTAssertNil(state.account)
        XCTAssertNil(state.pending)
        XCTAssertTrue(state.alerts.isEmpty)
        await transport.release()
        let result = await logout.value
        XCTAssertTrue(result.serverRevoked)
        _ = try await client.signIn(email: "a@example.invalid", password: "fictional-test-password")
        await transport.logoutFails()
        let offline = await client.logout(allDevices: false)
        XCTAssertFalse(offline.serverRevoked)
        let offlineState = await client.currentSnapshot()
        XCTAssertNil(offlineState.account)
    }

    private func alert(state: String = "active", version: Int = 1) -> SharedAlert {
        SharedAlert(alertID: fixtureAlert, senderID: fixtureA, state: state, version: version,
                    expiresAt: Int(instant.timeIntervalSince1970)+600,
                    closedAt: state == "active" ? nil : Int(instant.timeIntervalSince1970),
                    recipients: [SharedRecipient(userID: fixtureB)])
    }
}
