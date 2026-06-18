import Combine
import Foundation

public struct AppSettings: Codable, Equatable, Sendable {
    public var aiProvider: AIProvider
    public var sttProvider: STTProvider
    public var notificationsEnabled: Bool
    public var defaultWorkspacePath: String?
    public var timeZoneIdentifier: String
    public var geminiModelID: String?
    public var groqBaseURLString: String?
    public var openCodeExecutablePath: String?
    public var openCodeWorkspacePath: String?
    public var openCodeModelID: String?
    public var isOpenCodeLocalExecutionApproved: Bool

    private enum CodingKeys: String, CodingKey {
        case aiProvider
        case sttProvider
        case notificationsEnabled
        case defaultWorkspacePath
        case timeZoneIdentifier
        case geminiModelID
        case groqBaseURLString
        case openCodeExecutablePath
        case openCodeWorkspacePath
        case openCodeModelID
        case isOpenCodeLocalExecutionApproved
    }

    public init(
        aiProvider: AIProvider = .openaiResponses,
        sttProvider: STTProvider = .openAITranscribe,
        notificationsEnabled: Bool = false,
        defaultWorkspacePath: String? = nil,
        timeZoneIdentifier: String = TimeZone.current.identifier,
        geminiModelID: String? = nil,
        groqBaseURLString: String? = nil,
        openCodeExecutablePath: String? = nil,
        openCodeWorkspacePath: String? = nil,
        openCodeModelID: String? = nil,
        isOpenCodeLocalExecutionApproved: Bool = false
    ) {
        self.aiProvider = aiProvider
        self.sttProvider = sttProvider
        self.notificationsEnabled = notificationsEnabled
        self.defaultWorkspacePath = defaultWorkspacePath
        self.timeZoneIdentifier = timeZoneIdentifier
        self.geminiModelID = geminiModelID
        self.groqBaseURLString = groqBaseURLString
        self.openCodeExecutablePath = openCodeExecutablePath
        self.openCodeWorkspacePath = openCodeWorkspacePath
        self.openCodeModelID = openCodeModelID
        self.isOpenCodeLocalExecutionApproved = isOpenCodeLocalExecutionApproved
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.aiProvider = try container.decode(AIProvider.self, forKey: .aiProvider)
        self.sttProvider = try container.decode(STTProvider.self, forKey: .sttProvider)
        self.notificationsEnabled = try container.decode(Bool.self, forKey: .notificationsEnabled)
        self.defaultWorkspacePath = try container.decodeIfPresent(String.self, forKey: .defaultWorkspacePath)
        self.timeZoneIdentifier = try container.decode(String.self, forKey: .timeZoneIdentifier)
        self.geminiModelID = try container.decodeIfPresent(String.self, forKey: .geminiModelID)
        self.groqBaseURLString = try container.decodeIfPresent(String.self, forKey: .groqBaseURLString)
        self.openCodeExecutablePath = try container.decodeIfPresent(String.self, forKey: .openCodeExecutablePath)
        self.openCodeWorkspacePath = try container.decodeIfPresent(String.self, forKey: .openCodeWorkspacePath)
        self.openCodeModelID = try container.decodeIfPresent(String.self, forKey: .openCodeModelID)
        self.isOpenCodeLocalExecutionApproved = try container.decodeIfPresent(Bool.self, forKey: .isOpenCodeLocalExecutionApproved) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(aiProvider, forKey: .aiProvider)
        try container.encode(sttProvider, forKey: .sttProvider)
        try container.encode(notificationsEnabled, forKey: .notificationsEnabled)
        try container.encodeIfPresent(defaultWorkspacePath, forKey: .defaultWorkspacePath)
        try container.encode(timeZoneIdentifier, forKey: .timeZoneIdentifier)
        try container.encodeIfPresent(geminiModelID, forKey: .geminiModelID)
        try container.encodeIfPresent(groqBaseURLString, forKey: .groqBaseURLString)
        try container.encodeIfPresent(openCodeExecutablePath, forKey: .openCodeExecutablePath)
        try container.encodeIfPresent(openCodeWorkspacePath, forKey: .openCodeWorkspacePath)
        try container.encodeIfPresent(openCodeModelID, forKey: .openCodeModelID)
        try container.encode(isOpenCodeLocalExecutionApproved, forKey: .isOpenCodeLocalExecutionApproved)
    }

    public static let `default` = AppSettings()

    public var normalizedForRuntime: AppSettings {
        var copy = self
        if !LLMProviderCatalog.isAvailableInCurrentBuild(copy.aiProvider) {
            copy.aiProvider = LLMProviderCatalog.defaultProviderID
        }
        if !copy.sttProvider.isReleaseReady {
            copy.sttProvider = .openAITranscribe
        }
        if let geminiModelID = copy.geminiModelID?.trimmingCharacters(in: .whitespacesAndNewlines) {
            copy.geminiModelID = geminiModelID.isEmpty ? nil : geminiModelID
        }
        if let groqBaseURLString = copy.groqBaseURLString?.trimmingCharacters(in: .whitespacesAndNewlines) {
            copy.groqBaseURLString = groqBaseURLString.isEmpty ? nil : groqBaseURLString
        }
        if let openCodeExecutablePath = copy.openCodeExecutablePath?.trimmingCharacters(in: .whitespacesAndNewlines) {
            copy.openCodeExecutablePath = openCodeExecutablePath.isEmpty ? nil : openCodeExecutablePath
        }
        if let openCodeWorkspacePath = copy.openCodeWorkspacePath?.trimmingCharacters(in: .whitespacesAndNewlines) {
            copy.openCodeWorkspacePath = openCodeWorkspacePath.isEmpty ? nil : openCodeWorkspacePath
        }
        if let openCodeModelID = copy.openCodeModelID?.trimmingCharacters(in: .whitespacesAndNewlines) {
            copy.openCodeModelID = openCodeModelID.isEmpty ? nil : openCodeModelID
        }
        return copy
    }

    public func resolvedGroqBaseURL(defaultBaseURL: URL) -> URL {
        guard let groqBaseURLString = normalizedForRuntime.groqBaseURLString,
              let url = URL(string: groqBaseURLString),
              url.isHTTPSAPIBaseURL else {
            return defaultBaseURL
        }
        return url
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

        if !LLMProviderCatalog.isAvailableInCurrentBuild(aiProvider) {
            issues.append(
                ValidationIssue(
                    field: "aiProvider",
                    message: "\(aiProvider.displayName) is not available in this build.",
                    severity: .error
                )
            )
        }

        if let geminiModelID {
            let trimmedModelID = geminiModelID.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedModelID.isEmpty {
                issues.append(
                    ValidationIssue(
                        field: "geminiModelID",
                        message: "Gemini model id cannot be blank.",
                        severity: .error
                    )
                )
            } else if trimmedModelID.rangeOfCharacter(from: .whitespacesAndNewlines) != nil {
                issues.append(
                    ValidationIssue(
                        field: "geminiModelID",
                        message: "Gemini model id cannot contain whitespace.",
                        severity: .error
                    )
                )
            }
        }

        if let groqBaseURLString {
            let trimmedBaseURL = groqBaseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedBaseURL.isEmpty {
                issues.append(
                    ValidationIssue(
                        field: "groqBaseURLString",
                        message: "Groq base URL cannot be blank.",
                        severity: .error
                    )
                )
            } else if URL(string: trimmedBaseURL)?.isHTTPSAPIBaseURL != true {
                issues.append(
                    ValidationIssue(
                        field: "groqBaseURLString",
                        message: "Groq base URL must be an HTTPS URL with a host.",
                        severity: .error
                    )
                )
            }
        }

        if aiProvider == .opencodeLocal {
            appendOpenCodeLocalIssues(to: &issues)
        } else {
            appendOptionalOpenCodeLocalIssues(to: &issues)
        }

        return issues
    }

    private func appendOpenCodeLocalIssues(to issues: inout [ValidationIssue]) {
        appendOpenCodeExecutablePathIssue(to: &issues, isRequired: true)
        appendOpenCodeWorkspacePathIssue(to: &issues, isRequired: true)
        appendOpenCodeModelIDIssue(to: &issues, isRequired: true)
        if !isOpenCodeLocalExecutionApproved {
            issues.append(
                ValidationIssue(
                    field: "isOpenCodeLocalExecutionApproved",
                    message: "OpenCode local execution requires explicit approval.",
                    severity: .error
                )
            )
        }
    }

    private func appendOptionalOpenCodeLocalIssues(to issues: inout [ValidationIssue]) {
        appendOpenCodeExecutablePathIssue(to: &issues, isRequired: false)
        appendOpenCodeWorkspacePathIssue(to: &issues, isRequired: false)
        appendOpenCodeModelIDIssue(to: &issues, isRequired: false)
    }

    private func appendOpenCodeExecutablePathIssue(to issues: inout [ValidationIssue], isRequired: Bool) {
        let trimmed = openCodeExecutablePath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            if isRequired {
                issues.append(
                    ValidationIssue(
                        field: "openCodeExecutablePath",
                        message: "OpenCode executable path is required.",
                        severity: .error
                    )
                )
            }
            return
        }
        if trimmed.hasSuffix("/auth.json") || trimmed == "auth.json" {
            issues.append(
                ValidationIssue(
                    field: "openCodeExecutablePath",
                    message: "OpenCode executable path must not point to auth.json.",
                    severity: .error
                )
            )
        }
    }

    private func appendOpenCodeWorkspacePathIssue(to issues: inout [ValidationIssue], isRequired: Bool) {
        let trimmed = openCodeWorkspacePath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            if isRequired {
                issues.append(
                    ValidationIssue(
                        field: "openCodeWorkspacePath",
                        message: "OpenCode workspace path is required.",
                        severity: .error
                    )
                )
            }
            return
        }
    }

    private func appendOpenCodeModelIDIssue(to issues: inout [ValidationIssue], isRequired: Bool) {
        let trimmed = openCodeModelID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            if isRequired {
                issues.append(
                    ValidationIssue(
                        field: "openCodeModelID",
                        message: "OpenCode model id is required.",
                        severity: .error
                    )
                )
            }
            return
        }
        if trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) != nil {
            issues.append(
                ValidationIssue(
                    field: "openCodeModelID",
                    message: "OpenCode model id cannot contain whitespace.",
                    severity: .error
                )
            )
        }
    }
}

private extension URL {
    var isHTTPSAPIBaseURL: Bool {
        scheme?.lowercased() == "https" && host?.isEmpty == false
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
    @Published public private(set) var openAIProviderSmokeStatusLabel: String
    @Published public private(set) var anthropicAPIKeyInput: String
    @Published public private(set) var anthropicAPIKeyStatusLabel: String
    @Published public private(set) var geminiAPIKeyInput: String
    @Published public private(set) var geminiAPIKeyStatusLabel: String
    @Published public private(set) var geminiProviderSmokeStatusLabel: String
    @Published public private(set) var groqAPIKeyInput: String
    @Published public private(set) var groqAPIKeyStatusLabel: String
    @Published public private(set) var groqProviderSmokeStatusLabel: String
    @Published public private(set) var openRouterAPIKeyInput: String
    @Published public private(set) var openRouterAPIKeyStatusLabel: String
    @Published public private(set) var keychainSecretKeyInput: String
    @Published public private(set) var keychainSecretValueInput: String
    @Published public private(set) var keychainSecretStatusLabel: String
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var successMessage: String?

    private let settingsStore: any AppSettingsStore
    private let secretStore: any SecretStore
    private var rejectedAIProvider: AIProvider?

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
        self.openAIProviderSmokeStatusLabel = "notConfigured"
        self.anthropicAPIKeyInput = ""
        self.anthropicAPIKeyStatusLabel = "Not configured"
        self.geminiAPIKeyInput = ""
        self.geminiAPIKeyStatusLabel = "Not configured"
        self.geminiProviderSmokeStatusLabel = "notConfigured"
        self.groqAPIKeyInput = ""
        self.groqAPIKeyStatusLabel = "Not configured"
        self.groqProviderSmokeStatusLabel = "notConfigured"
        self.openRouterAPIKeyInput = ""
        self.openRouterAPIKeyStatusLabel = "Not configured"
        self.keychainSecretKeyInput = ""
        self.keychainSecretValueInput = ""
        self.keychainSecretStatusLabel = "Enter a secret key"
        self.errorMessage = initialErrorMessage
        self.successMessage = nil
        self.rejectedAIProvider = nil
        refreshOpenAIAPIKeyStatus()
        refreshAnthropicAPIKeyStatus()
        refreshGeminiAPIKeyStatus()
        refreshGroqAPIKeyStatus()
        refreshOpenRouterAPIKeyStatus()
    }

    public var selectableAIProviders: [AIProvider] {
        LLMProviderCatalog.settingsSelectableIDs
    }

    public func setNotificationsEnabled(_ isEnabled: Bool) {
        settings.notificationsEnabled = isEnabled
        clearMessages()
    }

    public func setAIProvider(_ provider: AIProvider) {
        guard LLMProviderCatalog.isAvailableInCurrentBuild(provider) else {
            rejectedAIProvider = provider
            errorMessage = unavailableMessage(for: provider)
            successMessage = nil
            return
        }

        settings.aiProvider = provider
        if provider == .opencodeLocal, settings.openCodeModelID == nil {
            settings.openCodeModelID = LLMProviderCatalog.entry(for: .opencodeLocal).defaultModelID
        }
        clearMessages()
    }

    public func selectAIProviderAndSave(_ provider: AIProvider) {
        setAIProvider(provider)
        saveSettings()
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

    public func setGeminiModelID(_ modelID: String) {
        let trimmed = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.geminiModelID = trimmed.isEmpty ? nil : trimmed
        clearMessages()
    }

    public func setGroqBaseURLString(_ baseURLString: String) {
        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.groqBaseURLString = trimmed.isEmpty ? nil : trimmed
        clearMessages()
    }

    public func setOpenCodeExecutablePath(_ path: String) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.openCodeExecutablePath = trimmed.isEmpty ? nil : trimmed
        clearMessages()
    }

    public func setOpenCodeWorkspacePath(_ path: String) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.openCodeWorkspacePath = trimmed.isEmpty ? nil : trimmed
        clearMessages()
    }

    public func setOpenCodeModelID(_ modelID: String) {
        let trimmed = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.openCodeModelID = trimmed.isEmpty ? nil : trimmed
        clearMessages()
    }

    public func setOpenCodeLocalExecutionApproved(_ isApproved: Bool) {
        settings.isOpenCodeLocalExecutionApproved = isApproved
        clearMessages()
    }

    public func updateOpenAIAPIKeyInput(_ value: String) {
        openAIAPIKeyInput = value
        clearMessages()
    }

    public func updateAnthropicAPIKeyInput(_ value: String) {
        anthropicAPIKeyInput = value
        clearMessages()
    }

    public func updateGeminiAPIKeyInput(_ value: String) {
        geminiAPIKeyInput = value
        clearMessages()
    }

    public func updateGroqAPIKeyInput(_ value: String) {
        groqAPIKeyInput = value
        clearMessages()
    }

    public func updateOpenRouterAPIKeyInput(_ value: String) {
        openRouterAPIKeyInput = value
        clearMessages()
    }

    public func updateKeychainSecretKeyInput(_ value: String) {
        keychainSecretKeyInput = value
        refreshKeychainSecretStatus(reportEmptyAsError: false)
    }

    public func updateKeychainSecretValueInput(_ value: String) {
        keychainSecretValueInput = value
        clearMessages()
    }

    public func saveSettings() {
        if let rejectedAIProvider {
            errorMessage = unavailableMessage(for: rejectedAIProvider)
            successMessage = nil
            return
        }

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

    public func saveKeychainSecret() {
        guard let keyName = normalizedKeychainSecretKey(reportEmptyAsError: true) else {
            return
        }

        let value = keychainSecretValueInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            errorMessage = "Secret value is required."
            successMessage = nil
            return
        }

        do {
            try secretStore.save(value, for: SecretKey(keyName))
            keychainSecretKeyInput = keyName
            keychainSecretValueInput = ""
            guard refreshKeychainSecretStatus(reportEmptyAsError: true, clearMessagesOnSuccess: false) else {
                return
            }
            errorMessage = nil
            successMessage = "Secret saved to Keychain."
        } catch {
            errorMessage = "Secret could not be saved to Keychain."
            successMessage = nil
        }
    }

    public func deleteKeychainSecret() {
        guard let keyName = normalizedKeychainSecretKey(reportEmptyAsError: true) else {
            return
        }

        do {
            try secretStore.delete(SecretKey(keyName))
            keychainSecretKeyInput = keyName
            keychainSecretValueInput = ""
            guard refreshKeychainSecretStatus(reportEmptyAsError: true, clearMessagesOnSuccess: false) else {
                return
            }
            errorMessage = nil
            successMessage = "Secret removed."
        } catch {
            errorMessage = "Secret could not be removed from Keychain."
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

    public func saveAnthropicAPIKey() {
        let trimmed = anthropicAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            deleteAnthropicAPIKey()
            return
        }
        guard validateAPIKey(trimmed) else {
            return
        }

        do {
            try secretStore.save(trimmed, for: .anthropicAPIKey)
            anthropicAPIKeyInput = ""
            guard refreshAnthropicAPIKeyStatus() else {
                return
            }
            errorMessage = nil
            successMessage = "Anthropic API key saved to Keychain."
        } catch {
            errorMessage = String(describing: error)
            successMessage = nil
        }
    }

    public func saveGeminiAPIKey() {
        let trimmed = geminiAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            deleteGeminiAPIKey()
            return
        }
        guard validateAPIKey(trimmed) else {
            return
        }

        do {
            try secretStore.save(trimmed, for: .geminiAPIKey)
            geminiAPIKeyInput = ""
            guard refreshGeminiAPIKeyStatus() else {
                return
            }
            errorMessage = nil
            successMessage = "Gemini API key saved to Keychain."
        } catch {
            errorMessage = String(describing: error)
            successMessage = nil
        }
    }

    public func saveGroqAPIKey() {
        let trimmed = groqAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            deleteGroqAPIKey()
            return
        }
        guard validateAPIKey(trimmed) else {
            return
        }

        do {
            try secretStore.save(trimmed, for: .groqAPIKey)
            groqAPIKeyInput = ""
            guard refreshGroqAPIKeyStatus() else {
                return
            }
            errorMessage = nil
            successMessage = "Groq API key saved to Keychain."
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

    public func deleteAnthropicAPIKey() {
        do {
            try secretStore.delete(.anthropicAPIKey)
            anthropicAPIKeyInput = ""
            guard refreshAnthropicAPIKeyStatus() else {
                return
            }
            errorMessage = nil
            successMessage = "Anthropic API key removed."
        } catch {
            errorMessage = String(describing: error)
            successMessage = nil
        }
    }

    public func deleteGeminiAPIKey() {
        do {
            try secretStore.delete(.geminiAPIKey)
            geminiAPIKeyInput = ""
            guard refreshGeminiAPIKeyStatus() else {
                return
            }
            errorMessage = nil
            successMessage = "Gemini API key removed."
        } catch {
            errorMessage = String(describing: error)
            successMessage = nil
        }
    }

    public func deleteGroqAPIKey() {
        do {
            try secretStore.delete(.groqAPIKey)
            groqAPIKeyInput = ""
            guard refreshGroqAPIKeyStatus() else {
                return
            }
            errorMessage = nil
            successMessage = "Groq API key removed."
        } catch {
            errorMessage = String(describing: error)
            successMessage = nil
        }
    }

    @discardableResult
    public func refreshKeychainSecretStatus() -> Bool {
        refreshKeychainSecretStatus(reportEmptyAsError: false)
    }

    @discardableResult
    public func refreshOpenAIAPIKeyStatus() -> Bool {
        do {
            openAIAPIKeyStatusLabel = try apiKeyStatusLabel(for: .openAIAPIKey)
            openAIProviderSmokeStatusLabel = providerSmokeStatusLabel(forAPIKeyStatusLabel: openAIAPIKeyStatusLabel)
            if openAIAPIKeyStatusLabel == "Invalid" {
                reportInvalidStoredAPIKey()
                return false
            }
            return true
        } catch {
            openAIAPIKeyStatusLabel = "Unavailable"
            openAIProviderSmokeStatusLabel = "unavailable"
            errorMessage = "API key status could not be read from Keychain."
            successMessage = nil
            return false
        }
    }

    @discardableResult
    public func refreshOpenRouterAPIKeyStatus() -> Bool {
        do {
            openRouterAPIKeyStatusLabel = try apiKeyStatusLabel(for: .openRouterAPIKey)
            if openRouterAPIKeyStatusLabel == "Invalid" {
                reportInvalidStoredAPIKey()
                return false
            }
            return true
        } catch {
            openRouterAPIKeyStatusLabel = "Unavailable"
            errorMessage = "API key status could not be read from Keychain."
            successMessage = nil
            return false
        }
    }

    @discardableResult
    public func refreshAnthropicAPIKeyStatus() -> Bool {
        do {
            anthropicAPIKeyStatusLabel = try apiKeyStatusLabel(for: .anthropicAPIKey)
            if anthropicAPIKeyStatusLabel == "Invalid" {
                reportInvalidStoredAPIKey()
                return false
            }
            return true
        } catch {
            anthropicAPIKeyStatusLabel = "Unavailable"
            errorMessage = "API key status could not be read from Keychain."
            successMessage = nil
            return false
        }
    }

    @discardableResult
    public func refreshGeminiAPIKeyStatus() -> Bool {
        do {
            geminiAPIKeyStatusLabel = try apiKeyStatusLabel(for: .geminiAPIKey)
            geminiProviderSmokeStatusLabel = providerSmokeStatusLabel(forAPIKeyStatusLabel: geminiAPIKeyStatusLabel)
            if geminiAPIKeyStatusLabel == "Invalid" {
                reportInvalidStoredAPIKey()
                return false
            }
            return true
        } catch {
            geminiAPIKeyStatusLabel = "Unavailable"
            geminiProviderSmokeStatusLabel = "unavailable"
            errorMessage = "API key status could not be read from Keychain."
            successMessage = nil
            return false
        }
    }

    @discardableResult
    public func refreshGroqAPIKeyStatus() -> Bool {
        do {
            groqAPIKeyStatusLabel = try apiKeyStatusLabel(for: .groqAPIKey)
            groqProviderSmokeStatusLabel = providerSmokeStatusLabel(forAPIKeyStatusLabel: groqAPIKeyStatusLabel)
            if groqAPIKeyStatusLabel == "Invalid" {
                reportInvalidStoredAPIKey()
                return false
            }
            return true
        } catch {
            groqAPIKeyStatusLabel = "Unavailable"
            groqProviderSmokeStatusLabel = "unavailable"
            errorMessage = "API key status could not be read from Keychain."
            successMessage = nil
            return false
        }
    }

    private func clearMessages() {
        rejectedAIProvider = nil
        errorMessage = nil
        successMessage = nil
    }

    private func unavailableMessage(for provider: AIProvider) -> String {
        "\(provider.displayName) is not available in this build."
    }

    private func providerSmokeStatusLabel(forAPIKeyStatusLabel apiKeyStatusLabel: String) -> String {
        switch apiKeyStatusLabel {
        case "Configured":
            "readyForManualSmoke"
        case "Invalid":
            "invalidConfiguration"
        case "Unavailable":
            "unavailable"
        default:
            "notConfigured"
        }
    }

    @discardableResult
    private func refreshKeychainSecretStatus(
        reportEmptyAsError: Bool,
        clearMessagesOnSuccess: Bool = true
    ) -> Bool {
        guard let keyName = normalizedKeychainSecretKey(reportEmptyAsError: reportEmptyAsError) else {
            return false
        }

        do {
            let storedValue = try secretStore.read(SecretKey(keyName))?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if storedValue?.isEmpty != false {
                keychainSecretStatusLabel = "Not configured"
            } else {
                keychainSecretStatusLabel = "Configured"
            }
            if clearMessagesOnSuccess {
                clearMessages()
            }
            return true
        } catch {
            keychainSecretStatusLabel = "Unavailable"
            errorMessage = "Secret status could not be read from Keychain."
            successMessage = nil
            return false
        }
    }

    private func normalizedKeychainSecretKey(reportEmptyAsError: Bool) -> String? {
        do {
            return try SecretKeyNameValidator.normalize(keychainSecretKeyInput)
        } catch SecretKeyNameValidationError.empty {
            keychainSecretStatusLabel = "Enter a secret key"
            if reportEmptyAsError {
                errorMessage = "Secret key is required."
                successMessage = nil
            } else {
                clearMessages()
            }
            return nil
        } catch SecretKeyNameValidationError.invalidCharacters {
            keychainSecretStatusLabel = "Invalid key"
            errorMessage = "Secret key can contain letters, numbers, underscore, hyphen, or dot only."
            successMessage = nil
            return nil
        } catch {
            keychainSecretStatusLabel = "Invalid key"
            errorMessage = "Secret key is invalid."
            successMessage = nil
            return nil
        }
    }

    private func apiKeyStatusLabel(for key: SecretKey) throws -> String {
        do {
            _ = try APIKeyValidator.normalize(try secretStore.read(key))
            return "Configured"
        } catch APIKeyValidationError.empty {
            return "Not configured"
        } catch APIKeyValidationError.containsWhitespace {
            return "Invalid"
        }
    }

    private func reportInvalidStoredAPIKey() {
        errorMessage = "Stored API key is invalid. Re-enter it in Settings."
        successMessage = nil
    }

    private func validateAPIKey(_ apiKey: String) -> Bool {
        guard APIKeyValidator.isValid(apiKey) else {
            errorMessage = "API key cannot contain whitespace."
            successMessage = nil
            return false
        }

        return true
    }
}
