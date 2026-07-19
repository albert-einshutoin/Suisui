import Foundation

#if canImport(Security)
import Security

protocol KeychainSecItemClient {
    func add(_ query: CFDictionary) -> OSStatus
    func update(_ query: CFDictionary, _ attributes: CFDictionary) -> OSStatus
    func copyMatching(_ query: CFDictionary, _ item: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus
    func delete(_ query: CFDictionary) -> OSStatus
}

private struct SystemKeychainSecItemClient: KeychainSecItemClient {
    func add(_ query: CFDictionary) -> OSStatus {
        SecItemAdd(query, nil)
    }

    func update(_ query: CFDictionary, _ attributes: CFDictionary) -> OSStatus {
        SecItemUpdate(query, attributes)
    }

    func copyMatching(_ query: CFDictionary, _ item: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
        SecItemCopyMatching(query, item)
    }

    func delete(_ query: CFDictionary) -> OSStatus {
        SecItemDelete(query)
    }
}

public final class KeychainSecretStore: SecretStore, @unchecked Sendable {
    private let service: String
    private let keychain: any KeychainSecItemClient
    private let cacheLock = NSLock()
    private var processCache: [SecretKey: String] = [:]

    public init(service: String = "dev.suisui.app") {
        self.service = service
        self.keychain = SystemKeychainSecItemClient()
    }

    init(service: String, keychain: any KeychainSecItemClient) {
        self.service = service
        self.keychain = keychain
    }

    public func save(_ value: String, for key: SecretKey) throws {
        guard let data = value.data(using: .utf8) else {
            throw SecretStoreError.encodingFailed
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = keychain.update(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            removeCachedValue(for: key)
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw SecretStoreError.unexpectedStatus(updateStatus)
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data

        let status = keychain.add(addQuery as CFDictionary)
        guard status == errSecSuccess else {
            throw SecretStoreError.unexpectedStatus(status)
        }
        removeCachedValue(for: key)
    }

    public func read(_ key: SecretKey) throws -> String? {
        if let cached = cachedValue(for: key) {
            return cached
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = keychain.copyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw SecretStoreError.unexpectedStatus(status)
        }

        guard let data = item as? Data else {
            return nil
        }

        let value = String(data: data, encoding: .utf8)
        if let value {
            cache(value, for: key)
        }
        return value
    }

    public func delete(_ key: SecretKey) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]

        let status = keychain.delete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecretStoreError.unexpectedStatus(status)
        }
        removeCachedValue(for: key)
    }

    private func cachedValue(for key: SecretKey) -> String? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return processCache[key]
    }

    private func cache(_ value: String, for key: SecretKey) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        // Keychain ACL prompts can repeat on debug/ad-hoc builds when the code requirement changes.
        // Cache only inside the current process so repeated provider actions do not prompt again,
        // while Keychain remains the sole durable store and save/delete force a verified readback.
        processCache[key] = value
    }

    private func removeCachedValue(for key: SecretKey) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        processCache.removeValue(forKey: key)
    }
}
#endif
