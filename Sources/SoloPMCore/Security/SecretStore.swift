import Foundation

public struct SecretKey: Codable, Hashable, Equatable, Sendable {
    public var rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public static let openAIAPIKey = SecretKey("openai_api_key")
    public static let openRouterAPIKey = SecretKey("openrouter_api_key")
    public static let githubToken = SecretKey("github_token")
}

public protocol SecretStore: Sendable {
    func save(_ value: String, for key: SecretKey) throws
    func read(_ key: SecretKey) throws -> String?
    func delete(_ key: SecretKey) throws
}

public enum SecretStoreError: Error, Equatable {
    case encodingFailed
    case unexpectedStatus(Int32)
}

public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private var values: [SecretKey: String]
    private let lock = NSLock()

    public init(values: [SecretKey: String] = [:]) {
        self.values = values
    }

    public func save(_ value: String, for key: SecretKey) throws {
        lock.lock()
        defer { lock.unlock() }
        values[key] = value
    }

    public func read(_ key: SecretKey) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }

    public func delete(_ key: SecretKey) throws {
        lock.lock()
        defer { lock.unlock() }
        values.removeValue(forKey: key)
    }
}
