import Foundation
import XCTest
@testable import NidaaIntegration

final class ClientReviewRegressionTests: XCTestCase, @unchecked Sendable {
    private let endpoint = "http://127.0.0.1:55421"
    private func fixture(_ storage: MemoryClientStorage = MemoryClientStorage()) async throws -> (NidaaClient, TestTransport) {
        let transport = TestTransport()
        let client = NidaaClient(environment: try TrialEnvironment(baseURL: URL(string: endpoint)!), storage: storage, transport: transport)
        _ = try await client.signIn(email: "a@example.invalid", password: "fictional-test-password")
        return (client, transport)
    }
    private func command() -> CommandEnvelope { CommandEnvelope(command: "create_alert", payload: [:]) }

    func testUnrecognizedLookupStatusCannotReleaseUnknownOperation() async throws {
        let (client, transport) = try await fixture()
        let operation = command()
        await transport.commands(.failure)
        _ = try? await client.execute(operation)
        await transport.lookup(Receipt(operationID: operation.operationID, status: "processing", serverTime: operation.issuedAt))
        do { _ = try await client.queryPending(); XCTFail("nonterminal receipt cleared uncertain intent") }
        catch { XCTAssertEqual(error as? ClientError, .invalidResponse) }
        let pending = await client.pendingOperation()
        XCTAssertEqual(pending?.state, .outcomeUnknown)
        do { _ = try await client.execute(command()); XCTFail("replacement operation bypassed uncertainty") }
        catch { XCTAssertEqual(error as? ClientError, .pendingUnresolved) }
        let posts = await transport.count("/v1/commands")
        XCTAssertEqual(posts, 1)
    }

    func testCorruptPendingStorageCannotPublishAuthenticatedAccount() async throws {
        try await assertInvalidPending(Data("corrupt durable state".utf8))
    }

    func testMismatchedPendingOwnerCannotPublishAuthenticatedAccount() async throws {
        let mismatched = PendingOperation(accountID: fixtureB, environmentID: endpoint, envelope: command(), state: .outcomeUnknown)
        try await assertInvalidPending(JSONEncoder().encode(mismatched))
    }

    private func assertInvalidPending(_ data: Data) async throws {
        let storage = MemoryClientStorage()
        let scoped = ScopedStorage(base: storage, scope: endpoint)
        try scoped.set("owner", data: Data(fixtureA.uuidString.utf8))
        try scoped.set("pending." + fixtureA.uuidString, data: data)
        let transport = TestTransport()
        let client = NidaaClient(environment: try TrialEnvironment(baseURL: URL(string: endpoint)!), storage: storage, transport: transport)
        do { _ = try await client.signIn(email: "a@example.invalid", password: "fictional-test-password"); XCTFail("invalid durable state was accepted") }
        catch { XCTAssertEqual(error as? ClientError, .storageUnavailable) }
        let snapshot = await client.currentSnapshot()
        XCTAssertNil(snapshot.account)
        do { _ = try await client.execute(command()); XCTFail("failed session adoption permitted a mutation") }
        catch { XCTAssertEqual(error as? ClientError, .unauthenticated) }
        let posts = await transport.count("/v1/commands")
        XCTAssertEqual(posts, 0)
        XCTAssertEqual(try scoped.get("pending." + fixtureA.uuidString), data)
    }

    func testRevokedRefreshClearsCacheButRetainsUnknownForReauthentication() async throws {
        let (client, transport) = try await fixture()
        let operation = command()
        await transport.commands(.failure)
        _ = try? await client.execute(operation)
        await transport.rejectRefresh("refresh_token_not_found")
        do { _ = try await client.refreshSession(); XCTFail("revoked refresh succeeded") }
        catch { XCTAssertEqual(error as? ClientError, .unauthenticated) }
        let rejected = await client.currentSnapshot()
        XCTAssertNil(rejected.account)
        XCTAssertTrue(rejected.alerts.isEmpty)
        _ = try await client.signIn(email: "a@example.invalid", password: "fictional-test-password")
        let restored = await client.pendingOperation()
        XCTAssertEqual(restored?.envelope.operationID, operation.operationID)
        XCTAssertEqual(restored?.state, .outcomeUnknown)
    }

    func testDomainRevocationClearsPreviouslyFetchedAccountData() async throws {
        let (client, transport) = try await fixture()
        await transport.enqueue(SyncSnapshot(cursor: 1, alerts: [SharedAlert(alertID: fixtureAlert, senderID: fixtureA, expiresAt: Int(Date().timeIntervalSince1970)+60, recipients: [])]))
        _ = try await client.synchronize()
        await transport.rejectSynchronization()
        do { _ = try await client.synchronize(); XCTFail("revoked domain session synchronized") }
        catch { XCTAssertEqual(error as? ClientError, .unauthenticated) }
        let rejected = await client.currentSnapshot()
        XCTAssertNil(rejected.account)
        XCTAssertTrue(rejected.alerts.isEmpty)
        XCTAssertEqual(rejected.cursor, -1)
    }
}
