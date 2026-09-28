import Foundation

public enum AlertAction: Equatable, Sendable { case retry, addRecipient(UUID) }
public struct AlertActionDetails: Equatable, Sendable {
    public let alertID: UUID
    public let action: AlertAction
    public let recipients: [TrustedContact]
    public let existingProgress: [RecipientProgress]
    public let attempts: Int
    public let expiresAt: Date
}
public struct AlertActionGate: Sendable {
    private var details: AlertActionDetails?
    private var issuedAt: Date?
    public init() {}
    public mutating func invalidate() { details = nil; issuedAt = nil }
    public mutating func authorize(success: Bool, details: AlertActionDetails, at now: Date) {
        invalidate(); if success { self.details = details; issuedAt = now }
    }
    public func permits(_ details: AlertActionDetails, at now: Date) -> Bool {
        guard let issuedAt else { return false }
        return self.details == details && now >= issuedAt && now.timeIntervalSince(issuedAt) < 15 && now < details.expiresAt
    }
    public mutating func consume(_ details: AlertActionDetails, at now: Date) throws {
        let allowed = permits(details, at: now); invalidate()
        guard allowed else { throw SimulationError.authenticationRequired }
    }
}
