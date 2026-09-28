import Foundation

public enum ArchiveError: Error, Equatable { case unsupportedVersion, invalidData, unreadable, writeFailed, notLoaded }

/// Only domain data is Codable. Authentication and authorizations never enter this schema.
public struct AlertArchive: Codable, Equatable {
    public var schemaVersion: Int = 2
    public var contacts: [TrustedContact]
    public var alerts: [LocalAlert]
    public init(contacts: [TrustedContact], alerts: [LocalAlert]) { self.contacts = contacts; self.alerts = alerts }
    public static func decode(_ data: Data, legacyContacts: [TrustedContact]) throws -> Self {
        struct Header: Decodable { let schemaVersion: Int }
        struct V1: Decodable { let schemaVersion: Int; let alerts: [LocalAlert] }
        let decoder = JSONDecoder()
        let version = try decoder.decode(Header.self, from: data).schemaVersion
        let archive: Self
        switch version {
        case 1: archive = Self(contacts: legacyContacts, alerts: try decoder.decode(V1.self, from: data).alerts)
        case 2: archive = try decoder.decode(Self.self, from: data)
        default: throw ArchiveError.unsupportedVersion
        }
        try archive.validate(); return archive
    }
    public func validate() throws {
        guard schemaVersion == 2, Set(contacts.map(\.id)).count == contacts.count,
              Set(alerts.map(\.id)).count == alerts.count,
              contacts.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.name.count <= 40 }) else { throw ArchiveError.invalidData }
        for a in alerts {
            guard a.createdAt.timeIntervalSince1970.isFinite, a.expiresAt > a.createdAt,
                  a.expiresAt.timeIntervalSince1970.isFinite, a.attempts > 0, !a.recipients.isEmpty,
                  Set(a.recipients.map(\.id)).count == a.recipients.count,
                  Set(a.events.map(\.id)).count == a.events.count else { throw ArchiveError.invalidData }
        }
    }
}

public protocol ArchiveIO {
    func read() throws -> Data?
    /// Must leave the old complete file intact if replacement fails.
    func replace(with data: Data) throws
}

public struct FileArchiveIO: ArchiveIO {
    public let url: URL
    public init(directory: URL) { url = directory.appendingPathComponent("alerts.json") }
    public func read() throws -> Data? {
        do { return try Data(contentsOf: url) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return nil }
        // Permission/protection errors must never be treated as an empty archive.
    }
    public func replace(with data: Data) throws {
        var directory = url.deletingLastPathComponent()
        #if os(iOS)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.protectionKey: FileProtectionType.complete])
        #else
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #endif
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }
}

/// A failed load blocks writes, retaining the original bytes until an explicit reset or successful reload.
public final class AlertRepository {
    private let io: any ArchiveIO
    private var loaded = false
    public init(io: any ArchiveIO) { self.io = io }
    public func load(legacyContacts: [TrustedContact], at now: Date) throws -> LocalSimulation {
        loaded = false
        let data: Data?
        do { data = try io.read() } catch { throw ArchiveError.unreadable }
        let archive: AlertArchive
        do { archive = try data.map { try AlertArchive.decode($0, legacyContacts: legacyContacts) }
                ?? AlertArchive(contacts: legacyContacts, alerts: []) }
        catch let error as ArchiveError { throw error }
        catch { throw ArchiveError.invalidData }
        var simulation = LocalSimulation(contacts: archive.contacts, restoredAlerts: archive.alerts)
        simulation.tick(at: now)
        // Persist migration/expiry before publishing the restored state. No sends or retries occur.
        try write(AlertArchive(contacts: simulation.contacts, alerts: simulation.alerts))
        loaded = true; return simulation
    }
    public func save(_ simulation: LocalSimulation) throws {
        guard loaded else { throw ArchiveError.notLoaded }
        try write(AlertArchive(contacts: simulation.contacts, alerts: simulation.alerts))
    }
    public func reset() throws -> LocalSimulation {
        let clean = LocalSimulation()
        try write(AlertArchive(contacts: clean.contacts, alerts: []))
        loaded = true; return clean
    }
    private func write(_ archive: AlertArchive) throws {
        try archive.validate()
        let data = try JSONEncoder().encode(archive)
        do { try io.replace(with: data) } catch { throw ArchiveError.writeFailed }
    }
}
