import Foundation
import Auth
#if canImport(Security)
import Security
#endif

public protocol ClientStorage: Sendable {
    func get(_ key: String) throws -> Data?
    func set(_ key: String, data: Data) throws
    func remove(_ key: String) throws
    func removeAll() throws
}

/// Explicitly ephemeral test storage; never the Apple live-client default.
public final class MemoryClientStorage: ClientStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    public init() {}
    public func get(_ key: String) throws -> Data? { lock.withLock { values[key] } }
    public func set(_ key: String, data: Data) throws { lock.withLock { values[key] = data } }
    public func remove(_ key: String) throws { _ = lock.withLock { values.removeValue(forKey: key) } }
    public func removeAll() throws { lock.withLock { values.removeAll() } }
}

#if canImport(Security)
public final class KeychainClientStorage: ClientStorage, @unchecked Sendable {
    private let service: String
    public init(service: String = "com.nidaa.integration.private") { self.service = service }
    private func query(_ key: String? = nil) -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrSynchronizable as String: false]
        if let key { q[kSecAttrAccount as String] = key }
        return q
    }
    public func get(_ key: String) throws -> Data? {
        var q = query(key); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = value as? Data else { throw ClientError.storageUnavailable }
        return data
    }
    public func set(_ key: String, data: Data) throws {
        let q = query(key)
        let attrs: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(q as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            let result = SecItemAdd(q.merging(attrs) { _, new in new } as CFDictionary, nil)
            guard result == errSecSuccess else { throw ClientError.storageUnavailable }
        } else if status != errSecSuccess { throw ClientError.storageUnavailable }
    }
    public func remove(_ key: String) throws {
        let status = SecItemDelete(query(key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw ClientError.storageUnavailable }
    }
    public func removeAll() throws {
        let status = SecItemDelete(query() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw ClientError.storageUnavailable }
    }
}
#endif

/// A single secure value per environment avoids clearing another environment's sessions.
final class ScopedStorage: ClientStorage, @unchecked Sendable {
    let base: any ClientStorage
    let scope: String
    private let lock = NSLock()
    init(base: any ClientStorage, scope: String) { self.base = base; self.scope = "environment." + scope }
    private func values() throws -> [String: Data] {
        guard let data = try base.get(scope) else { return [:] }
        return try JSONDecoder().decode([String: Data].self, from: data)
    }
    func get(_ key: String) throws -> Data? { try lock.withLock { try values()[key] } }
    func set(_ key: String, data: Data) throws { try lock.withLock { var v = try values(); v[key] = data; try base.set(scope, data: JSONEncoder().encode(v)) } }
    func remove(_ key: String) throws { try lock.withLock { var v = try values(); v.removeValue(forKey: key); try base.set(scope, data: JSONEncoder().encode(v)) } }
    func removeAll() throws { try lock.withLock { try base.remove(scope) } }
    func clearAuth() throws { try lock.withLock { let v = try values().filter { !$0.key.hasPrefix("auth.") }; try base.set(scope, data: JSONEncoder().encode(v)) } }
}

/// Invalidation blocks late official-SDK callbacks from persisting a previous session.
final class GuardedAuthStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var active = true
    private let storage: ScopedStorage
    init(storage: ScopedStorage) { self.storage = storage }
    func invalidate() { lock.withLock { active = false } }
    func store(key: String, value: Data) throws { try lock.withLock { guard active else { throw ClientError.staleGeneration }; try storage.set("auth." + key, data: value) } }
    func retrieve(key: String) throws -> Data? { try lock.withLock { guard active else { return nil }; return try storage.get("auth." + key) } }
    func remove(key: String) throws { try lock.withLock { guard active else { return }; try storage.remove("auth." + key) } }
}
