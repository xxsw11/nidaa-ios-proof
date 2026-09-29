import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import NidaaIntegration

let fixtureA = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
let fixtureB = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
let fixtureAlert = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!

enum CommandBehavior: Sendable { case accepted, failure, malformed, wrongID, status(Int) }
struct RecordedRequest: Sendable {
    let method: String
    let path: String
    let envelope: CommandEnvelope?
}

/// Deterministic transport fixture, not provider or inter-device evidence.
actor TestTransport: HTTPTransport {
    private var history: [RecordedRequest] = []
    private var commandBehavior = CommandBehavior.accepted
    private var operation: Receipt?
    private var snapshots: [SyncSnapshot] = []
    private var pausePath: String?
    private var suspended: CheckedContinuation<HTTPResult, any Error>?
    private var suspendedResult: HTTPResult?
    private var failLogout = false
    private var refreshError: String?
    private var unauthorizedSync = false

    func commands(_ behavior: CommandBehavior) { commandBehavior = behavior }
    func lookup(_ receipt: Receipt?) { operation = receipt }
    func enqueue(_ snapshot: SyncSnapshot) { snapshots.append(snapshot) }
    func pauseNext(_ path: String) { pausePath = path }
    func logoutFails() { failLogout = true }
    func rejectRefresh(_ code: String) { refreshError = code }
    func rejectSynchronization() { unauthorizedSync = true }
    func isPaused() -> Bool { suspended != nil }
    func requests() -> [RecordedRequest] { history }
    func count(_ path: String) -> Int { history.filter { $0.path == path }.count }
    func release() {
        let continuation = suspended
        let response = suspendedResult
        suspended = nil; suspendedResult = nil
        if let response { continuation?.resume(returning: response) }
    }

    func send(_ request: URLRequest) async throws -> HTTPResult {
        let path = request.url?.path ?? ""
        let envelope = request.httpBody.flatMap { try? JSONDecoder().decode(CommandEnvelope.self, from: $0) }
        history.append(RecordedRequest(method: request.httpMethod ?? "GET", path: path, envelope: envelope))
        let response = try result(request, path: path, envelope: envelope)
        if pausePath == path {
            pausePath = nil
            return try await withCheckedThrowingContinuation { continuation in
                suspended = continuation; suspendedResult = response
            }
        }
        return response
    }

    private func result(_ request: URLRequest, path: String, envelope: CommandEnvelope?) throws -> HTTPResult {
        if path == "/auth/v1/token" || path == "/auth/v1/verify" {
            let body = request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
            if body["refresh_token"] != nil, let refreshError {
                guard request.value(forHTTPHeaderField: "X-Supabase-Api-Version") == "2024-01-01" else { throw ClientError.invalidResponse }
                return HTTPResult(status: 400, body: try JSONSerialization.data(withJSONObject: ["code":refreshError,"message":"Fictional revoked session"]), authAPIVersion: "2024-01-01")
            }
            let isB = (body["email"] as? String == "b@example.invalid") || (body["refresh_token"] as? String == "fixture-refresh-b") || (body["token_hash"] as? String == "fixture-verify-b")
            let id = isB ? fixtureB : fixtureA
            let label = isB ? "b" : "a"
            let value: [String: Any] = ["access_token":"fixture-access-"+label,
                "refresh_token":"fixture-refresh-"+label,"token_type":"bearer", "expires_in":3600,
                "expires_at":Int(Date().timeIntervalSince1970)+3600,
                "user":["id":id.uuidString,"app_metadata":[:],"user_metadata":[:],"aud":"authenticated",
                        "email":label+"@example.invalid","created_at":"2026-01-01T00:00:00Z",
                        "updated_at":"2026-01-01T00:00:00Z","email_confirmed_at":"2026-01-01T00:00:00Z","is_anonymous":false]]
            return HTTPResult(status: 200, body: try JSONSerialization.data(withJSONObject: value))
        }
        if path == "/v1/me" {
            let isB = request.value(forHTTPHeaderField: "Authorization")?.contains("fixture-access-b") == true
            return try encoded(Account(userID: isB ? fixtureB : fixtureA, displayName: isB ? "Sara" : "Sami"))
        }
        if path == "/v1/commands", let envelope {
            switch commandBehavior {
            case .failure: throw URLError(.networkConnectionLost)
            case .malformed: return HTTPResult(status: 200, body: Data("not a receipt".utf8))
            case .status(let status): return HTTPResult(status: status, body: Data("{\"error\":\"unavailable\"}".utf8))
            case .wrongID: return try encoded(Receipt(operationID: UUID(), status: "accepted", resourceID: fixtureAlert, serverTime: envelope.issuedAt))
            case .accepted: return try encoded(Receipt(operationID: envelope.operationID, status: "accepted", resourceID: fixtureAlert, serverTime: envelope.issuedAt))
            }
        }
        if path.hasPrefix("/v1/operations/") {
            if let operation { return try encoded(operation) }
            return HTTPResult(status: 404, body: Data("{\"error\":\"not_found\"}".utf8))
        }
        if path == "/v1/sync" {
            if unauthorizedSync { return HTTPResult(status: 401, body: Data("{\"error\":\"unauthenticated\"}".utf8)) }
            return try encoded(snapshots.isEmpty ? SyncSnapshot(cursor: 0) : snapshots.removeFirst())
        }
        if path == "/v1/relationships" { return try encoded(Relationships()) }
        if path == "/v1/session/logout" || path == "/v1/session/revoke-all" {
            if failLogout { throw URLError(.notConnectedToInternet) }
            return HTTPResult(status: 204, body: Data())
        }
        throw ClientError.invalidResponse
    }

    private func encoded<T: Encodable>(_ value: T) throws -> HTTPResult {
        HTTPResult(status: 200, body: try JSONEncoder().encode(value))
    }
}

final class FailingStorage: ClientStorage, @unchecked Sendable {
    private let lock = NSLock()
    private let base = MemoryClientStorage()
    private var fail = false
    func failWrites() { lock.withLock { fail = true } }
    func get(_ key: String) throws -> Data? { try base.get(key) }
    func set(_ key: String, data: Data) throws {
        if lock.withLock({ fail }) { throw ClientError.storageUnavailable }
        try base.set(key, data: data)
    }
    func remove(_ key: String) throws { try base.remove(key) }
    func removeAll() throws { try base.removeAll() }
}
