import Foundation

public struct AppSettings: Equatable, Sendable {
    public var aiProvider: AIProvider
    public var sttProvider: STTProvider
    public var notificationsEnabled: Bool
    public var defaultWorkspacePath: String?
    public var timeZoneIdentifier: String

    public init(
        aiProvider: AIProvider = .openAIResponses,
        sttProvider: STTProvider = .localWhisperKit,
        notificationsEnabled: Bool = false,
        defaultWorkspacePath: String? = nil,
        timeZoneIdentifier: String = TimeZone.current.identifier
    ) {
        self.aiProvider = aiProvider
        self.sttProvider = sttProvider
        self.notificationsEnabled = notificationsEnabled
        self.defaultWorkspacePath = defaultWorkspacePath
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    public static let `default` = AppSettings()

    public func validate() -> [ValidationIssue] {
        var issues: [ValidationIssue] = []

        if TimeZone(identifier: timeZoneIdentifier) == nil {
            issues.append(
                ValidationIssue(
                    field: "timeZoneIdentifier",
                    message: "Unknown time zone identifier.",
                    severity: .error
                )
            )
        }

        if let defaultWorkspacePath, defaultWorkspacePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(
                ValidationIssue(
                    field: "defaultWorkspacePath",
                    message: "Default workspace path cannot be blank.",
                    severity: .error
                )
            )
        }

        return issues
    }
}

public enum AIProvider: String, CaseIterable, Equatable, Sendable {
    case openAIResponses
    case openAICompatible
    case openRouter
    case ollama

    public var displayName: String {
        switch self {
        case .openAIResponses:
            "OpenAI Responses"
        case .openAICompatible:
            "OpenAI-compatible"
        case .openRouter:
            "OpenRouter"
        case .ollama:
            "Ollama"
        }
    }
}

public enum STTProvider: String, CaseIterable, Equatable, Sendable {
    case appleSpeechAnalyzer
    case localWhisperKit
    case localWhisperCpp
    case openAITranscribe

    public var displayName: String {
        switch self {
        case .appleSpeechAnalyzer:
            "Apple SpeechAnalyzer"
        case .localWhisperKit:
            "WhisperKit"
        case .localWhisperCpp:
            "whisper.cpp"
        case .openAITranscribe:
            "OpenAI Transcribe"
        }
    }
}

public struct ValidationIssue: Equatable, Sendable {
    public var field: String
    public var message: String
    public var severity: ValidationSeverity

    public init(field: String, message: String, severity: ValidationSeverity) {
        self.field = field
        self.message = message
        self.severity = severity
    }
}

public enum ValidationSeverity: String, Equatable, Sendable {
    case warning
    case error
}

