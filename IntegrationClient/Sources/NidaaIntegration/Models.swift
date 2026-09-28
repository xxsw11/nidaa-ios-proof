import Foundation

public enum JSONValue: Codable, Sendable, Equatable {
    case string(String), integer(Int), bool(Bool), array([JSONValue]), object([String: JSONValue]), null
    public init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Int.self) { self = .integer(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .integer(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
}

public struct CommandEnvelope: Codable, Sendable, Equatable {
    public let operationID: UUID
    public let issuedAt: Int
    public let command: String
    public let payload: [String: JSONValue]
    public init(operationID: UUID = UUID(), issuedAt: Int = Int(Date().timeIntervalSince1970), command: String, payload: [String: JSONValue]) {
        self.operationID = operationID; self.issuedAt = issuedAt; self.command = command; self.payload = payload
    }
    enum CodingKeys: String, CodingKey { case operationID = "operation_id", issuedAt = "issued_at", command, payload }
}

public struct Account: Codable, Sendable, Equatable {
    public var userID: UUID
    public var displayName: String
    public var emailVerified: Bool
    public init(userID: UUID, displayName: String, emailVerified: Bool = true) { self.userID = userID; self.displayName = displayName; self.emailVerified = emailVerified }
    enum CodingKeys: String, CodingKey { case userID = "user_id", displayName = "display_name", emailVerified = "email_verified" }
}

public struct Receipt: Codable, Sendable, Equatable {
    public var operationID: UUID
    public var status: String
    public var resourceID: UUID?
    public var error: String?
    public var serverTime: Int
    public var invitationToken: String?
    public init(operationID: UUID, status: String, resourceID: UUID? = nil, error: String? = nil, serverTime: Int, invitationToken: String? = nil) {
        self.operationID = operationID; self.status = status; self.resourceID = resourceID; self.error = error; self.serverTime = serverTime; self.invitationToken = invitationToken
    }
    enum CodingKeys: String, CodingKey { case operationID = "operation_id", status, resourceID = "resource_id", error, serverTime = "server_time", invitationToken = "invitation_token" }
}

public struct SharedRecipient: Codable, Sendable, Equatable {
    public var userID: UUID
    public var response: String
    public var responseVersion: Int
    public var access: String
    public var providerAccepted: Bool
    public var appAcknowledged: Bool
    public var opened: Bool
    public init(userID: UUID, response: String = "none", responseVersion: Int = 0, access: String = "active", providerAccepted: Bool = false, appAcknowledged: Bool = false, opened: Bool = false) {
        self.userID = userID; self.response = response; self.responseVersion = responseVersion; self.access = access; self.providerAccepted = providerAccepted; self.appAcknowledged = appAcknowledged; self.opened = opened
    }
    enum CodingKeys: String, CodingKey { case userID = "user_id", response, responseVersion = "response_version", access, providerAccepted = "provider_accepted", appAcknowledged = "app_acknowledged", opened }
}

public struct SharedAlert: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID { alertID }
    public var alertID: UUID
    public var senderID: UUID
    public var state: String
    public var version: Int
    public var expiresAt: Int
    public var closedAt: Int?
    public var recipients: [SharedRecipient]
    public init(alertID: UUID, senderID: UUID, state: String = "active", version: Int = 1, expiresAt: Int, closedAt: Int? = nil, recipients: [SharedRecipient]) {
        self.alertID = alertID; self.senderID = senderID; self.state = state; self.version = version; self.expiresAt = expiresAt; self.closedAt = closedAt; self.recipients = recipients
    }
    enum CodingKeys: String, CodingKey { case alertID = "alert_id", senderID = "sender_id", state, version, expiresAt = "expires_at", closedAt = "closed_at", recipients }
}

public struct Invitation: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID { invitationID }
    public var invitationID: UUID
    public var senderID: UUID
    public var direction: String
    public var state: String
    public var expiresAt: Int
    public init(invitationID: UUID, senderID: UUID, direction: String, state: String, expiresAt: Int) { self.invitationID = invitationID; self.senderID = senderID; self.direction = direction; self.state = state; self.expiresAt = expiresAt }
    enum CodingKeys: String, CodingKey { case invitationID = "invitation_id", senderID = "sender_id", direction, state, expiresAt = "expires_at" }
}

public struct ConsentGrant: Codable, Sendable, Equatable {
    public var senderID: UUID
    public var recipientID: UUID
    public var state: String
    public init(senderID: UUID, recipientID: UUID, state: String) { self.senderID = senderID; self.recipientID = recipientID; self.state = state }
    enum CodingKeys: String, CodingKey { case senderID = "sender_id", recipientID = "recipient_id", state }
}

public struct Relationships: Codable, Sendable, Equatable {
    public var invitations: [Invitation]
    public var grants: [ConsentGrant]
    public init(invitations: [Invitation] = [], grants: [ConsentGrant] = []) { self.invitations = invitations; self.grants = grants }
}

public struct SyncSnapshot: Codable, Sendable, Equatable {
    public var cursor: Int
    public var fullSnapshot: Bool
    public var alerts: [SharedAlert]
    public var removedIDs: [UUID]
    public init(cursor: Int, fullSnapshot: Bool = true, alerts: [SharedAlert] = [], removedIDs: [UUID] = []) { self.cursor = cursor; self.fullSnapshot = fullSnapshot; self.alerts = alerts; self.removedIDs = removedIDs }
    enum CodingKeys: String, CodingKey { case cursor, fullSnapshot = "full_snapshot", alerts, removedIDs = "removed_ids" }
}

public enum PendingState: String, Codable, Sendable { case neverSent, outcomeUnknown }
public struct PendingOperation: Codable, Sendable, Equatable {
    public var accountID: UUID
    public var environmentID: String
    public var envelope: CommandEnvelope
    public var state: PendingState
    public init(accountID: UUID, environmentID: String, envelope: CommandEnvelope, state: PendingState) { self.accountID = accountID; self.environmentID = environmentID; self.envelope = envelope; self.state = state }
}
public struct ClientSnapshot: Sendable, Equatable {
    public var account: Account?
    public var alerts: [SharedAlert]
    public var relationships: Relationships
    public var cursor: Int
    public var generation: Int
    public var pending: PendingOperation?
    public init(account: Account? = nil, alerts: [SharedAlert] = [], relationships: Relationships = Relationships(), cursor: Int = -1, generation: Int = 0, pending: PendingOperation? = nil) { self.account = account; self.alerts = alerts; self.relationships = relationships; self.cursor = cursor; self.generation = generation; self.pending = pending }
}
public struct LogoutResult: Sendable, Equatable {
    public var serverRevoked: Bool
    public init(serverRevoked: Bool) { self.serverRevoked = serverRevoked }
}
public enum VerificationKind: Sendable { case signup, recovery }
public enum ClientError: Error, Sendable, Equatable {
    case invalidEnvironment, unauthenticated, staleGeneration, invalidResponse, storageUnavailable
    case server(String), connectionFailed, pendingUnresolved, operationConflict
    case neverSent, outcomeUnknown(UUID)
}

public protocol NidaaClientProtocol: Sendable {
    func signup(email: String, password: String) async throws
    func signIn(email: String, password: String) async throws -> Account
    func verify(tokenHash: String, kind: VerificationKind) async throws -> Account
    func recover(email: String) async throws
    func updatePassword(_ password: String) async throws
    func refreshSession() async throws -> Account
    func restoreSession() async throws -> Account?
    func logout(allDevices: Bool) async -> LogoutResult
    func execute(_ envelope: CommandEnvelope) async throws -> Receipt
    func lookupOperation(_ id: UUID) async throws -> Receipt
    func synchronize() async throws -> ClientSnapshot
    func currentSnapshot() async -> ClientSnapshot
    func pendingOperation() async -> PendingOperation?
    func queryPending() async throws -> Receipt?
    func discardUnsent() async throws
}
