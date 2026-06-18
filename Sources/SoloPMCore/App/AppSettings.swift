import Combine
import Foundation

public struct AppSettings: Codable, Equatable, Sendable {
    public var aiProvider: AIProvider
    public var sttProvider: STTProvider
    public var notificationsEnabled: Bool
    public var defaultWorkspacePath: String?
    public var timeZoneIdentifier: String

    public init(
        aiProvider: AIProvider = .openAIResponses,
        sttProvider: STTProvider = .openAITranscribe,
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

    public var normalizedForRuntime: AppSettings {
        var copy = self
        if !copy.sttProvider.isReleaseReady {
            copy.sttProvider = .openAITranscribe
        }
        return copy
    }

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

public enum AIProvider: String, CaseIterable, Codable, Equatable, Sendable {
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

public enum STTProvider: String, CaseIterable, Codable, Equatable, Sendable {
    case appleSpeechAnalyzer
    case localWhisperKit
    case localWhisperCpp
    case openAITranscribe

    public static let releaseReadyCases: [STTProvider] = [.openAITranscribe]

    public var isReleaseReady: Bool {
        Self.releaseReadyCases.contains(self)
    }

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

public enum AppSettingsStoreError: Error, Equatable, Sendable {
    case encodingFailed
    case decodingFailed
}

public protocol AppSettingsStore: Sendable {
    func load() throws -> AppSettings
    func save(_ settings: AppSettings) throws
}

public final class UserDefaultsAppSettingsStore: AppSettingsStore, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard, key: String = "app.settings") {
        self.defaults = defaults
        self.key = key
    }

    public func load() throws -> AppSettings {
        lock.lock()
        defer { lock.unlock() }

        guard let data = defaults.data(forKey: key) else {
            return .default
        }

        do {
            return try JSONDecoder().decode(AppSettings.self, from: data)
        } catch {
            throw AppSettingsStoreError.decodingFailed
        }
    }

    public func save(_ settings: AppSettings) throws {
        lock.lock()
        defer { lock.unlock() }

        do {
            let data = try JSONEncoder().encode(settings)
            defaults.set(data, forKey: key)
        } catch {
            throw AppSettingsStoreError.encodingFailed
        }
    }
}

@MainActor
public final class AppSettingsViewModel: ObservableObject {
    @Published public private(set) var settings: AppSettings
    @Published public private(set) var openAIAPIKeyInput: String
    @Published public private(set) var openAIAPIKeyStatusLabel: String
    @Published public private(set) var openRouterAPIKeyInput: String
    @Published public private(set) var openRouterAPIKeyStatusLabel: String
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var successMessage: String?

    private let settingsStore: any AppSettingsStore
    private let secretStore: any SecretStore

    public init(settingsStore: any AppSettingsStore, secretStore: any SecretStore) {
        self.settingsStore = settingsStore
        self.secretStore = secretStore
        let loadedSettings: AppSettings
        let initialErrorMessage: String?
        do {
            loadedSettings = try settingsStore.load()
            initialErrorMessage = nil
        } catch {
            loadedSettings = .default
            initialErrorMessage = "App settings could not be loaded. Defaults are shown until settings are saved again."
        }
        self.settings = loadedSettings.normalizedForRuntime
        self.openAIAPIKeyInput = ""
        self.openAIAPIKeyStatusLabel = "Not configured"
        self.openRouterAPIKeyInput = ""
        self.openRouterAPIKeyStatusLabel = "Not configured"
        self.errorMessage = initialErrorMessage
        self.successMessage = nil
        refreshOpenAIAPIKeyStatus()
        refreshOpenRouterAPIKeyStatus()
    }

    public func setNotificationsEnabled(_ isEnabled: Bool) {
        settings.notificationsEnabled = isEnabled
        clearMessages()
    }

    public func setAIProvider(_ provider: AIProvider) {
        settings.aiProvider = provider
        clearMessages()
    }

    public func setSTTProvider(_ provider: STTProvider) {
        settings.sttProvider = provider.isReleaseReady ? provider : .openAITranscribe
        clearMessages()
    }

    public func setDefaultWorkspacePath(_ path: String) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.defaultWorkspacePath = trimmed.isEmpty ? nil : trimmed
        clearMessages()
    }

    public func updateOpenAIAPIKeyInput(_ value: String) {
        openAIAPIKeyInput = value
        clearMessages()
    }

    public func updateOpenRouterAPIKeyInput(_ value: String) {
        openRouterAPIKeyInput = value
        clearMessages()
    }

    public func saveSettings() {
        let issues = settings.validate().filter { $0.severity == .error }
        guard issues.isEmpty else {
            errorMessage = issues.map(\.message).joined(separator: " ")
            successMessage = nil
            return
        }

        do {
            try settingsStore.save(settings)
            errorMessage = nil
            successMessage = "Settings saved."
        } catch {
            errorMessage = String(describing: error)
            successMessage = nil
        }
    }

    public func saveOpenAIAPIKey() {
        let trimmed = openAIAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            deleteOpenAIAPIKey()
            return
        }
        guard validateAPIKey(trimmed) else {
            return
        }

        do {
            try secretStore.save(trimmed, for: .openAIAPIKey)
            openAIAPIKeyInput = ""
            guard refreshOpenAIAPIKeyStatus() else {
                return
            }
            errorMessage = nil
            successMessage = "API key saved to Keychain."
        } catch {
            errorMessage = String(describing: error)
            successMessage = nil
        }
    }

    public func saveOpenRouterAPIKey() {
        let trimmed = openRouterAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            deleteOpenRouterAPIKey()
            return
        }
        guard validateAPIKey(trimmed) else {
            return
        }

        do {
            try secretStore.save(trimmed, for: .openRouterAPIKey)
            openRouterAPIKeyInput = ""
            guard refreshOpenRouterAPIKeyStatus() else {
                return
            }
            errorMessage = nil
            successMessage = "OpenRouter API key saved to Keychain."
        } catch {
            errorMessage = String(describing: error)
            successMessage = nil
        }
    }

    public func deleteOpenAIAPIKey() {
        do {
            try secretStore.delete(.openAIAPIKey)
            openAIAPIKeyInput = ""
            guard refreshOpenAIAPIKeyStatus() else {
                return
            }
            errorMessage = nil
            successMessage = "API key removed."
        } catch {
            errorMessage = String(describing: error)
            successMessage = nil
        }
    }

    public func deleteOpenRouterAPIKey() {
        do {
            try secretStore.delete(.openRouterAPIKey)
            openRouterAPIKeyInput = ""
            guard refreshOpenRouterAPIKeyStatus() else {
                return
            }
            errorMessage = nil
            successMessage = "OpenRouter API key removed."
        } catch {
            errorMessage = String(describing: error)
            successMessage = nil
        }
    }

    @discardableResult
    public func refreshOpenAIAPIKeyStatus() -> Bool {
        do {
            let stored = try secretStore.read(.openAIAPIKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
            openAIAPIKeyStatusLabel = stored?.isEmpty == false ? "Configured" : "Not configured"
            return true
        } catch {
            openAIAPIKeyStatusLabel = "Unavailable"
            errorMessage = "API key status could not be read from Keychain."
            successMessage = nil
            return false
        }
    }

    @discardableResult
    public func refreshOpenRouterAPIKeyStatus() -> Bool {
        do {
            let stored = try secretStore.read(.openRouterAPIKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
            openRouterAPIKeyStatusLabel = stored?.isEmpty == false ? "Configured" : "Not configured"
            return true
        } catch {
            openRouterAPIKeyStatusLabel = "Unavailable"
            errorMessage = "API key status could not be read from Keychain."
            successMessage = nil
            return false
        }
    }

    private func clearMessages() {
        errorMessage = nil
        successMessage = nil
    }

    private func validateAPIKey(_ apiKey: String) -> Bool {
        guard apiKey.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            errorMessage = "API key cannot contain whitespace."
            successMessage = nil
            return false
        }

        return true
    }
}
