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
