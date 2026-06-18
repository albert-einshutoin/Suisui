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

public enum SecretKeyNameValidationError: Error, Equatable, Sendable {
    case empty
    case invalidCharacters
}

public enum SecretKeyNameValidator {
    public static func normalize(_ value: String?) throws -> String {
        guard let value else {
            throw SecretKeyNameValidationError.empty
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SecretKeyNameValidationError.empty
        }

        let allowedCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-.")
        guard trimmed.unicodeScalars.allSatisfy({ allowedCharacters.contains($0) }) else {
            throw SecretKeyNameValidationError.invalidCharacters
        }

        return trimmed
    }

    public static func isValid(_ value: String) -> Bool {
        do {
            _ = try normalize(value)
            return true
        } catch {
            return false
        }
    }
}
