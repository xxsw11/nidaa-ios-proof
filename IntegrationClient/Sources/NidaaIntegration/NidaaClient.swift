import Foundation
import Auth
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public actor NidaaClient: NidaaClientProtocol {
    public let environment: TrialEnvironment
    private let storage: ScopedStorage
    private let transport: any HTTPTransport
    private let now: @Sendable () -> Date
    private var authStorage: GuardedAuthStorage
    private var auth: AuthClient
    private var snapshot = ClientSnapshot()
    private var submitting = false

    public init(environment: TrialEnvironment, storage: any ClientStorage, transport: any HTTPTransport = URLSessionTransport(), now: @escaping @Sendable () -> Date = { Date() }) {
        self.environment = environment; self.transport = transport; self.now = now
        let scoped = ScopedStorage(base: storage, scope: environment.id)
        self.storage = scoped
        let guarded = GuardedAuthStorage(storage: scoped)
        authStorage = guarded
        auth = Self.makeAuth(environment: environment, storage: guarded, transport: transport)
    }

    #if canImport(Security)
    public static func live(environment: TrialEnvironment) throws -> NidaaClient {
        NidaaClient(environment: environment, storage: KeychainClientStorage())
    }
    #endif

    private static func makeAuth(environment: TrialEnvironment, storage: GuardedAuthStorage, transport: any HTTPTransport) -> AuthClient {
        AuthClient(url: environment.url("auth/v1"), headers: [:], flowType: .implicit,
                   redirectToURL: environment.url("verified"), storageKey: "nidaa-auth-session",
                   localStorage: storage, logger: nil, fetch: { request in
            guard let url = request.url, environment.permits(url) else { throw ClientError.invalidEnvironment }
            let result = try await transport.send(request)
            guard let response = HTTPURLResponse(url: url, statusCode: result.status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"]) else { throw ClientError.invalidResponse }
            return (result.body, response)
        }, autoRefreshToken: false, emitLocalSessionAsInitialSession: true)
    }

    private func check(_ generation: Int) throws {
        guard generation == snapshot.generation else { throw ClientError.staleGeneration }
    }
    private func rotateAuth(clearAll: Bool) throws {
        authStorage.invalidate()
        snapshot = ClientSnapshot(generation: snapshot.generation + 1)
        submitting = false
        do { if clearAll { try storage.removeAll() } else { try storage.clearAuth() } }
        catch { throw ClientError.storageUnavailable }
        let fresh = GuardedAuthStorage(storage: storage)
        authStorage = fresh
        auth = Self.makeAuth(environment: environment, storage: fresh, transport: transport)
    }
    private func safeAuthError(_ error: any Error) -> ClientError {
        if let e = error as? ClientError {
            return e == .unauthenticated ? rejectSession() : e
        }
        if let e = error as? AuthError,
           ["session_not_found", "session_expired", "refresh_token_not_found", "refresh_token_already_used", "user_banned", "user_not_found"].contains(e.errorCode.rawValue) {
            return rejectSession()
        }
        if error is URLError { return .connectionFailed }
        return .server("authentication_failed")
    }
    private func rejectSession() -> ClientError {
        // A rejected provider/domain session cannot retain an authenticated cache.
        // Preserve the account-scoped uncertain receipt for explicit reauthentication.
        // rotateAuth invalidates callbacks and clears memory before any storage write.
        try? rotateAuth(clearAll: false)
        return .unauthenticated
    }

    public func signup(email: String, password: String) async throws {
        try rotateAuth(clearAll: false)
        let generation = snapshot.generation, client = auth
        do { _ = try await client.signUp(email: email, password: password); try check(generation) }
        catch { try check(generation); throw safeAuthError(error) }
    }

    public func signIn(email: String, password: String) async throws -> Account {
        try rotateAuth(clearAll: false)
        let generation = snapshot.generation, client = auth
        do {
            let session = try await client.signIn(email: email, password: password)
            try check(generation)
            return try await adopt(accessToken: session.accessToken, generation: generation)
        } catch { try check(generation); throw safeAuthError(error) }
    }

    public func verify(tokenHash: String, kind: VerificationKind = .signup) async throws -> Account {
        // Verification/recovery can authenticate a different account. Invalidate
        // older auth/domain callbacks before the SDK starts that transition.
        try rotateAuth(clearAll: false)
        let generation = snapshot.generation, client = auth
        do {
            _ = try await client.verifyOTP(tokenHash: tokenHash, type: kind == .signup ? .signup : .recovery)
            try check(generation)
            let session = try await client.session
            try check(generation)
            return try await adopt(accessToken: session.accessToken, generation: generation)
        } catch { try check(generation); throw safeAuthError(error) }
    }

    public func recover(email: String) async throws {
        let generation = snapshot.generation, client = auth
        do { try await client.resetPasswordForEmail(email); try check(generation) }
        catch { try check(generation); throw safeAuthError(error) }
    }

    public func updatePassword(_ password: String) async throws {
        let generation = snapshot.generation, client = auth
        do { _ = try await client.update(user: UserAttributes(password: password)); try check(generation) }
        catch { try check(generation); throw safeAuthError(error) }
    }

    public func refreshSession() async throws -> Account {
        let generation = snapshot.generation, client = auth
        do {
            let session = try await client.refreshSession()
            try check(generation)
            return try await adopt(accessToken: session.accessToken, generation: generation)
        } catch { try check(generation); throw safeAuthError(error) }
    }

    public func restoreSession() async throws -> Account? {
        let generation = snapshot.generation, client = auth
        guard client.currentSession != nil else { return nil }
        do {
            let session = try await client.session
            try check(generation)
            return try await adopt(accessToken: session.accessToken, generation: generation)
        } catch { try check(generation); throw safeAuthError(error) }
    }

    private func adopt(accessToken: String, generation: Int) async throws -> Account {
        let result = try await request(path: "v1/me", token: accessToken)
        try check(generation)
        let account: Account = try decode(result)
        guard account.emailVerified else { throw ClientError.unauthenticated }
        if let current = snapshot.account, current.userID != account.userID {
            // A refresh/restore may not silently change the established identity.
            try rotateAuth(clearAll: true)
            throw ClientError.staleGeneration
        }
        do {
            if let ownerData = try storage.get("owner"), let prior = String(data: ownerData, encoding: .utf8), prior != account.userID.uuidString {
                try storage.remove("pending." + prior)
            }
            let pending: PendingOperation?
            if let data = try storage.get(pendingKey(account.userID)) {
                let restored = try JSONDecoder().decode(PendingOperation.self, from: data)
                guard restored.accountID == account.userID, restored.environmentID == environment.id else { throw ClientError.storageUnavailable }
                pending = restored
            } else { pending = nil }
            try storage.set("owner", data: Data(account.userID.uuidString.utf8))
            // Publish identity only after its durable uncertain-operation state validates.
            snapshot.account = account
            snapshot.pending = pending
        } catch { throw ClientError.storageUnavailable }
        return account
    }

    private func token(generation: Int) async throws -> String {
        guard snapshot.account != nil else { throw ClientError.unauthenticated }
        let client = auth
        do {
            let session = try await client.session
            try check(generation)
            return session.accessToken
        } catch { try check(generation); throw safeAuthError(error) }
    }

    private func request(path: String, token: String, method: String = "GET", body: Data? = nil) async throws -> HTTPResult {
        var request = URLRequest(url: environment.url(path))
        request.httpMethod = method; request.httpBody = body
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        return try await transport.send(request)
    }
    private func decode<T: Decodable>(_ response: HTTPResult) throws -> T {
        guard response.status == 200 else { throw responseError(response) }
        do { return try JSONDecoder().decode(T.self, from: response.body) }
        catch { throw ClientError.invalidResponse }
    }
    private func responseError(_ result: HTTPResult) -> ClientError {
        if result.status == 401 { return .unauthenticated }
        struct ErrorBody: Decodable { let error: String }
        let allowed: Set<String> = ["invalid_request","unauthenticated","not_found","forbidden","conflict","expired","rate_limited","consent_required","terminal","limit_reached","reauthentication_required"]
        if let body = try? JSONDecoder().decode(ErrorBody.self, from: result.body), allowed.contains(body.error) { return .server(body.error) }
        return .connectionFailed
    }
    private func authenticatedDecode<T: Decodable>(_ response: HTTPResult) throws -> T {
        do { return try decode(response) }
        catch { throw safeAuthError(error) }
    }

    private func pendingKey(_ id: UUID) -> String { "pending." + id.uuidString }
    private func savePending(_ pending: PendingOperation) throws {
        do { try storage.set(pendingKey(pending.accountID), data: JSONEncoder().encode(pending)); snapshot.pending = pending }
        catch { throw ClientError.storageUnavailable }
    }
    private func clearPending() throws {
        guard let account = snapshot.account else { return }
        do { try storage.remove(pendingKey(account.userID)); snapshot.pending = nil }
        catch { throw ClientError.storageUnavailable }
    }

    /// No network call. UI can stage an offline intent and explicitly display never sent.
    @discardableResult
    public func stage(_ envelope: CommandEnvelope) throws -> PendingOperation {
        guard let account = snapshot.account else { throw ClientError.unauthenticated }
        if let existing = snapshot.pending {
            guard existing.envelope == envelope else { throw ClientError.pendingUnresolved }
            return existing
        }
        let pending = PendingOperation(accountID: account.userID, environmentID: environment.id, envelope: envelope, state: .neverSent)
        try savePending(pending)
        return pending
    }

    /// One explicit HTTP attempt only. Reconnect and lookup never call this method.
    public func execute(_ envelope: CommandEnvelope) async throws -> Receipt {
        guard !submitting else { throw ClientError.pendingUnresolved }
        var pending = try stage(envelope)
        guard pending.state == .neverSent else { throw ClientError.pendingUnresolved }
        let age = Int(now().timeIntervalSince1970) - envelope.issuedAt
        guard (0...60).contains(age) else { throw ClientError.neverSent }
        let generation = snapshot.generation
        submitting = true
        defer { if generation == snapshot.generation { submitting = false } }
        let accessToken: String
        do { accessToken = try await token(generation: generation); try check(generation) }
        catch { try check(generation); throw ClientError.neverSent }
        let body = try JSONEncoder().encode(envelope)
        guard body.count <= 16384 else { throw ClientError.neverSent }
        pending.state = .outcomeUnknown
        try savePending(pending) // Durable BEFORE any POST reaches the transport.
        let response: HTTPResult
        do { response = try await request(path: "v1/commands", token: accessToken, method: "POST", body: body) }
        catch { try check(generation); throw ClientError.outcomeUnknown(envelope.operationID) }
        try check(generation)
        if response.status == 200 {
            let receipt: Receipt
            do { receipt = try decode(response) }
            catch { throw ClientError.outcomeUnknown(envelope.operationID) }
            guard receipt.operationID == envelope.operationID, ["accepted","rejected"].contains(receipt.status) else { throw ClientError.outcomeUnknown(envelope.operationID) }
            try clearPending()
            if envelope.command == "delete_account", receipt.status == "accepted" { try rotateAuth(clearAll: true) }
            return receipt
        }
        // A strict boundary rejection is known for this attempt; infrastructure and
        // conflict responses remain unknown because an older receipt may exist.
        if [400,401,410,429].contains(response.status) {
            try clearPending()
            throw safeAuthError(responseError(response))
        }
        throw ClientError.outcomeUnknown(envelope.operationID)
    }

    public func lookupOperation(_ id: UUID) async throws -> Receipt {
        let generation = snapshot.generation
        let accessToken = try await token(generation: generation)
        let result: HTTPResult
        do { result = try await request(path: "v1/operations/" + id.uuidString.lowercased(), token: accessToken) }
        catch { try check(generation); throw ClientError.connectionFailed }
        try check(generation)
        let receipt: Receipt = try authenticatedDecode(result)
        guard receipt.operationID == id, ["accepted", "rejected"].contains(receipt.status) else { throw ClientError.invalidResponse }
        return receipt
    }

    public func alert(_ id: UUID) async throws -> SharedAlert {
        let generation = snapshot.generation
        let accessToken = try await token(generation: generation)
        let result: HTTPResult
        do { result = try await request(path: "v1/alerts/" + id.uuidString.lowercased(), token: accessToken) }
        catch { try check(generation); throw ClientError.connectionFailed }
        try check(generation)
        let alert: SharedAlert = try authenticatedDecode(result)
        guard alert.alertID == id else { throw ClientError.invalidResponse }
        return alert
    }

    public func queryPending() async throws -> Receipt? {
        guard let pending = snapshot.pending, pending.state == .outcomeUnknown else { return nil }
        let generation = snapshot.generation
        do {
            let receipt = try await lookupOperation(pending.envelope.operationID)
            try check(generation)
            try clearPending()
            if pending.envelope.command == "delete_account", receipt.status == "accepted" { try rotateAuth(clearAll: true) }
            return receipt
        } catch ClientError.server("not_found") { try check(generation); return nil }
    }

    public func discardUnsent() throws {
        guard snapshot.pending?.state != .outcomeUnknown else { throw ClientError.pendingUnresolved }
        try clearPending()
    }
    public func pendingOperation() -> PendingOperation? { snapshot.pending }
    public func currentSnapshot() -> ClientSnapshot { snapshot }

    public func synchronize() async throws -> ClientSnapshot {
        let generation = snapshot.generation
        let accessToken = try await token(generation: generation)
        let syncResult: HTTPResult, relationshipsResult: HTTPResult
        do {
            syncResult = try await request(path: "v1/sync", token: accessToken)
            try check(generation)
            relationshipsResult = try await request(path: "v1/relationships", token: accessToken)
        } catch { try check(generation); throw safeAuthError(error) }
        try check(generation)
        let sync: SyncSnapshot = try authenticatedDecode(syncResult)
        let relationships: Relationships = try authenticatedDecode(relationshipsResult)
        guard sync.fullSnapshot else { throw ClientError.invalidResponse }
        if sync.cursor > snapshot.cursor {
            snapshot.alerts = sync.alerts.filter { !sync.removedIDs.contains($0.alertID) }
            snapshot.cursor = sync.cursor
            snapshot.relationships = relationships
        }
        return snapshot
    }

    public func logout(allDevices: Bool = false) async -> LogoutResult {
        let accessToken = auth.currentSession?.accessToken
        // Local wipe and callback barrier happen before the first network suspension.
        do { try rotateAuth(clearAll: true) }
        catch { return LogoutResult(serverRevoked: false) }
        guard let accessToken else { return LogoutResult(serverRevoked: true) }
        do {
            let response = try await request(path: allDevices ? "v1/session/revoke-all" : "v1/session/logout", token: accessToken, method: "POST", body: Data("{}".utf8))
            return LogoutResult(serverRevoked: response.status == 204)
        } catch { return LogoutResult(serverRevoked: false) }
    }
}
