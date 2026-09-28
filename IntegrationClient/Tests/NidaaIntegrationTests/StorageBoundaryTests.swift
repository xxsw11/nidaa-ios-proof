import Foundation
import XCTest
@testable import NidaaIntegration

final class StorageBoundaryTests: XCTestCase {
    func testEnvironmentRejectsExternalCredentialsQueriesAndPaths() throws {
        for url in ["https://example.invalid", "http://192.168.1.10:55421", "http://user:password@127.0.0.1:55421",
                    "http://127.0.0.1:55421/path", "http://127.0.0.1:55421?x=1", "http://127.0.0.1:55421#fragment"] {
            XCTAssertThrowsError(try TrialEnvironment(baseURL: URL(string: url)!))
        }
        XCTAssertNoThrow(try TrialEnvironment(baseURL: URL(string: "http://127.0.0.1:55421")!))
    }

    func testClearingOneEnvironmentDoesNotClearAnotherEnvironment() throws {
        let base = MemoryClientStorage()
        let first = ScopedStorage(base: base, scope: "http://127.0.0.1:55421")
        let second = ScopedStorage(base: base, scope: "http://127.0.0.1:55422")
        try first.set("owner", data: Data("first fictional account".utf8))
        try second.set("owner", data: Data("second fictional account".utf8))
        try first.removeAll()
        XCTAssertNil(try first.get("owner"))
        XCTAssertEqual(try second.get("owner"), Data("second fictional account".utf8))
    }

    func testInvalidatedAuthCallbackCannotRecreateCredentials() throws {
        let storage = ScopedStorage(base: MemoryClientStorage(), scope: "test")
        let old = GuardedAuthStorage(storage: storage)
        try old.store(key: "session", value: Data("fictional old session".utf8))
        old.invalidate()
        try storage.removeAll()
        XCTAssertThrowsError(try old.store(key: "session", value: Data("fictional late session".utf8)))
        XCTAssertNil(try storage.get("auth.session"))
        XCTAssertNil(try old.retrieve(key: "session"))
    }

    func testClearingAuthPreservesUncertainPendingReceiptForReauthentication() throws {
        let storage = ScopedStorage(base: MemoryClientStorage(), scope: "test")
        let pending = PendingOperation(accountID: fixtureA, environmentID: "test",
            envelope: CommandEnvelope(issuedAt: 1_800_000_000, command: "delete_account", payload: [:]), state: .outcomeUnknown)
        try storage.set("pending", data: JSONEncoder().encode(pending))
        try storage.set("auth.session", data: Data("fictional session".utf8))
        try storage.clearAuth()
        XCTAssertNil(try storage.get("auth.session"))
        let data = try XCTUnwrap(try storage.get("pending"))
        let restored = try JSONDecoder().decode(PendingOperation.self, from: data)
        XCTAssertEqual(restored, pending)
    }
}
