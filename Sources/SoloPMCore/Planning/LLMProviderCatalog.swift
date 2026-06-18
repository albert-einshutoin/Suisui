import Foundation

public enum LLMProviderID: String, CaseIterable, Codable, Equatable, Hashable, Sendable, Identifiable {
    case openaiResponses
    case claudeMessages
    case geminiDirect
    case geminiOpenAICompatible
    case groqOpenAICompatible
    case opencodeLocal
    case openRouterCompatible
    case ollamaCompatible

    public var id: LLMProviderID { self }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        if let providerID = Self(rawValue: rawValue) ?? Self.legacyProviderID(for: rawValue) {
            self = providerID
            return
        }

        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Unknown LLM provider id: \(rawValue)"
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var displayName: String {
        LLMProviderCatalog.entry(for: self).displayName
    }

    public var isAvailableInCurrentBuild: Bool {
        LLMProviderCatalog.entry(for: self).isAvailableInCurrentBuild
    }

    private static func legacyProviderID(for rawValue: String) -> LLMProviderID? {
        switch rawValue {
        case "openAIResponses", "openAICompatible":
            .openaiResponses
        case "openRouter":
            .openRouterCompatible
        case "ollama":
            .ollamaCompatible
        default:
            nil
        }
    }
}

public typealias AIProvider = LLMProviderID

public enum LLMRequestFamily: String, Codable, Equatable, Sendable {
    case openAIResponses
    case openAIChatCompletions
    case anthropicMessages
    case geminiGenerateContent
    case opencodeLocalCLI
}

public struct LLMProviderCatalogEntry: Identifiable, Equatable, Sendable {
    public var id: LLMProviderID
    public var displayName: String
    public var isAvailableInCurrentBuild: Bool
    public var unavailableReason: String?
    public var apiKeySecretKey: SecretKey?
    public var baseURL: URL?
    public var defaultModelID: String
    public var requestFamily: LLMRequestFamily
    public var supportsStreaming: Bool
    public var supportsStructuredOutput: Bool

    public init(
        id: LLMProviderID,
        displayName: String,
        isAvailableInCurrentBuild: Bool,
        unavailableReason: String? = nil,
        apiKeySecretKey: SecretKey?,
        baseURL: URL?,
        defaultModelID: String,
        requestFamily: LLMRequestFamily,
        supportsStreaming: Bool,
        supportsStructuredOutput: Bool
    ) {
        self.id = id
        self.displayName = displayName
        self.isAvailableInCurrentBuild = isAvailableInCurrentBuild
        self.unavailableReason = unavailableReason
        self.apiKeySecretKey = apiKeySecretKey
        self.baseURL = baseURL
        self.defaultModelID = defaultModelID
        self.requestFamily = requestFamily
        self.supportsStreaming = supportsStreaming
        self.supportsStructuredOutput = supportsStructuredOutput
    }
}

public enum LLMProviderCatalog {
    public static let defaultProviderID: LLMProviderID = .openaiResponses
    public static let unavailableReason = "Not available in this build"

    public static let allEntries: [LLMProviderCatalogEntry] = [
        LLMProviderCatalogEntry(
            id: .openaiResponses,
            displayName: "OpenAI Responses",
            isAvailableInCurrentBuild: true,
            apiKeySecretKey: .openAIAPIKey,
            baseURL: URL(string: "https://api.openai.com/v1")!,
            defaultModelID: "gpt-5.2",
            requestFamily: .openAIResponses,
            supportsStreaming: false,
            supportsStructuredOutput: true
        ),
        LLMProviderCatalogEntry(
            id: .claudeMessages,
            displayName: "Claude Messages",
            isAvailableInCurrentBuild: true,
            apiKeySecretKey: .anthropicAPIKey,
            baseURL: URL(string: "https://api.anthropic.com/v1")!,
            defaultModelID: "claude-opus-4-6",
            requestFamily: .anthropicMessages,
            supportsStreaming: true,
            supportsStructuredOutput: true
        ),
        LLMProviderCatalogEntry(
            id: .geminiDirect,
            displayName: "Gemini Direct",
            isAvailableInCurrentBuild: true,
            apiKeySecretKey: .geminiAPIKey,
            baseURL: URL(string: "https://generativelanguage.googleapis.com/v1beta")!,
            defaultModelID: "gemini-3.5-flash",
            requestFamily: .geminiGenerateContent,
            supportsStreaming: true,
            supportsStructuredOutput: true
        ),
        LLMProviderCatalogEntry(
            id: .geminiOpenAICompatible,
            displayName: "Gemini OpenAI-compatible",
            isAvailableInCurrentBuild: false,
            unavailableReason: unavailableReason,
            apiKeySecretKey: .geminiAPIKey,
            baseURL: URL(string: "https://generativelanguage.googleapis.com/v1beta/openai")!,
            defaultModelID: "gemini-3.5-flash",
            requestFamily: .openAIChatCompletions,
            supportsStreaming: true,
            supportsStructuredOutput: false
        ),
        LLMProviderCatalogEntry(
            id: .groqOpenAICompatible,
            displayName: "Groq OpenAI-compatible",
            isAvailableInCurrentBuild: true,
            apiKeySecretKey: .groqAPIKey,
            baseURL: URL(string: "https://api.groq.com/openai/v1")!,
            defaultModelID: "llama-3.3-70b-versatile",
            requestFamily: .openAIChatCompletions,
            supportsStreaming: true,
            supportsStructuredOutput: false
        ),
        LLMProviderCatalogEntry(
            id: .opencodeLocal,
            displayName: "OpenCode Local",
            isAvailableInCurrentBuild: true,
            apiKeySecretKey: nil,
            baseURL: nil,
            defaultModelID: "anthropic/claude-sonnet-4-5",
            requestFamily: .opencodeLocalCLI,
            supportsStreaming: false,
            supportsStructuredOutput: false
        ),
        LLMProviderCatalogEntry(
            id: .openRouterCompatible,
            displayName: "OpenRouter",
            isAvailableInCurrentBuild: true,
            apiKeySecretKey: .openRouterAPIKey,
            baseURL: URL(string: "https://openrouter.ai/api/v1")!,
            defaultModelID: "openai/gpt-latest",
            requestFamily: .openAIChatCompletions,
            supportsStreaming: false,
            supportsStructuredOutput: false
        ),
        LLMProviderCatalogEntry(
            id: .ollamaCompatible,
            displayName: "Ollama",
            isAvailableInCurrentBuild: true,
            apiKeySecretKey: nil,
            baseURL: URL(string: "http://localhost:11434/v1")!,
            defaultModelID: "llama3.2",
            requestFamily: .openAIChatCompletions,
            supportsStreaming: false,
            supportsStructuredOutput: false
        )
    ]

    public static var settingsSelectableIDs: [LLMProviderID] {
        allEntries.filter { $0.isAvailableInCurrentBuild }.map(\.id)
    }

    public static func entry(for id: LLMProviderID) -> LLMProviderCatalogEntry {
        guard let entry = entriesByID[id] else {
            preconditionFailure("Missing LLM provider catalog entry for \(id.rawValue).")
        }
        return entry
    }

    public static func isAvailableInCurrentBuild(_ id: LLMProviderID) -> Bool {
        entry(for: id).isAvailableInCurrentBuild
    }

    private static let entriesByID: [LLMProviderID: LLMProviderCatalogEntry] = Dictionary(
        uniqueKeysWithValues: allEntries.map { ($0.id, $0) }
    )
}
