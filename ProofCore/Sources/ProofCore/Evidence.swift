import Foundation

public enum NotificationKind: String, Codable, Sendable { case local, remote }
public enum Observation: String, Codable, Sendable {
    case foregroundCallback, notificationOpened, notificationCenterInventory
}

/// A record of operator-confirmed scope, not an authentication or remote authorization mechanism.
public struct TestWindow: Equatable, Sendable {
    public let deviceAlias: String
    public let startsAt: Date
    public let endsAt: Date
    public init(deviceAlias: String, startsAt: Date, endsAt: Date) {
        self.deviceAlias = deviceAlias.trimmingCharacters(in: .whitespacesAndNewlines)
        self.startsAt = startsAt
        self.endsAt = endsAt
    }
    public func allows(at now: Date, scheduledFor: Date? = nil) -> Bool {
        let delivery = scheduledFor ?? now
        return !deviceAlias.isEmpty && endsAt > startsAt &&
            endsAt.timeIntervalSince(startsAt) <= 7200 &&
            now >= startsAt && now < endsAt && delivery >= now && delivery < endsAt
    }
}

/// Distinct facts. A callback is local evidence, not a server acknowledgment or proof of sound.
public struct IncidentEvidence: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let kind: NotificationKind
    public let expiresAt: Date
    public private(set) var locallyScheduledAt: Date?
    public private(set) var providerAcceptedAt: Date?
    public private(set) var observedAt: Date?
    public private(set) var observation: Observation?
    public private(set) var humanRespondedAt: Date?
    public private(set) var cancelledAt: Date?
    public init(id: UUID, kind: NotificationKind, expiresAt: Date) {
        self.id = id; self.kind = kind; self.expiresAt = expiresAt
    }
    public mutating func recordLocalScheduling(at now: Date) {
        guard kind == .local, now < expiresAt, cancelledAt == nil else { return }
        if locallyScheduledAt == nil { locallyScheduledAt = now }
    }
    /// Reserved for a verified provider adapter; the proof UI has no such connection.
    public mutating func recordProviderAcceptance(at now: Date) {
        guard kind == .remote, now < expiresAt, cancelledAt == nil else { return }
        if providerAcceptedAt == nil { providerAcceptedAt = now }
    }
    public mutating func observe(_ source: Observation, at now: Date) {
        if observedAt == nil { observedAt = now; observation = source }
    }
    @discardableResult public mutating func respond(at now: Date, authenticated: Bool) -> Bool {
        guard authenticated, observedAt != nil, now < expiresAt, cancelledAt == nil,
              humanRespondedAt == nil else { return false }
        humanRespondedAt = now; return true
    }
    public mutating func cancel(at now: Date) { if cancelledAt == nil { cancelledAt = now } }
}

public struct ProofEnvelope: Sendable {
    public static let marker = "nidaa-ios-proof-v01"
    public let id: UUID
    public let kind: NotificationKind
    public let expiresAt: Date
    public init(id: UUID, kind: NotificationKind, expiresAt: Date) {
        self.id = id; self.kind = kind; self.expiresAt = expiresAt
    }
    public var userInfo: [String: Any] {
        ["proof": Self.marker, "incident_id": id.uuidString,
         "expires_at": expiresAt.timeIntervalSince1970]
    }
    public static func decode(_ info: [AnyHashable: Any], kind: NotificationKind) -> Self? {
        guard info["proof"] as? String == marker,
              let raw = info["incident_id"] as? String, let id = UUID(uuidString: raw),
              let seconds = info["expires_at"] as? NSNumber,
              seconds.doubleValue.isFinite, seconds.doubleValue > 0 else { return nil }
        return Self(id: id, kind: kind, expiresAt: Date(timeIntervalSince1970: seconds.doubleValue))
    }
}
