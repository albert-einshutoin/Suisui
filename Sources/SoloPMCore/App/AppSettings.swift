import Combine
import Foundation

public struct AppSettings: Codable, Equatable, Sendable {
    public var aiProvider: AIProvider
    public var sttProvider: STTProvider
    public var ttsProvider: TTSProvider
    public var notificationsEnabled: Bool
    public var isDeveloperModeEnabled: Bool
    public var defaultWorkspacePath: String?
    public var timeZoneIdentifier: String
    public var googleCalendarID: String
    public var geminiModelID: String?
    public var groqBaseURLString: String?
    public var whisperCppExecutablePath: String?
    public var kokoroExecutablePath: String?
    public var ttsLanguageCode: String
    public var ttsVoiceID: String
    public var openCodeExecutablePath: String?
    public var openCodeWorkspacePath: String?
    public var openCodeModelID: String?
    public var isOpenCodeLocalExecutionApproved: Bool
    public var isLowLatencyVoiceAgentModeEnabled: Bool
    public var isLowLatencyVoiceAgentAlwaysOnRecordingEnabled: Bool
    public var isLowLatencyVoiceAgentCloudFallbackEnabled: Bool
    public var isLowLatencyVoiceAgentCloudFallbackCostVisible: Bool
    public var taskAutoExecution: TaskAutoExecutionSettings
    public var managedAIBilling: ManagedAIBillingSettings

    private enum CodingKeys: String, CodingKey {
        case aiProvider
        case sttProvider
        case ttsProvider
        case notificationsEnabled
        case isDeveloperModeEnabled
        case defaultWorkspacePath
        case timeZoneIdentifier
        case googleCalendarID
        case geminiModelID
        case groqBaseURLString
        case whisperCppExecutablePath
        case kokoroExecutablePath
        case ttsLanguageCode
        case ttsVoiceID
        case openCodeExecutablePath
        case openCodeWorkspacePath
        case openCodeModelID
        case isOpenCodeLocalExecutionApproved
        case isLowLatencyVoiceAgentModeEnabled
        case isLowLatencyVoiceAgentAlwaysOnRecordingEnabled
        case isLowLatencyVoiceAgentCloudFallbackEnabled
        case isLowLatencyVoiceAgentCloudFallbackCostVisible
        case taskAutoExecution
        case managedAIBilling
    }

    public init(
        aiProvider: AIProvider = .openaiResponses,
        sttProvider: STTProvider = .openAITranscribe,
        ttsProvider: TTSProvider = .localKokoro,
        notificationsEnabled: Bool = false,
        isDeveloperModeEnabled: Bool = false,
        defaultWorkspacePath: String? = nil,
        timeZoneIdentifier: String = TimeZone.current.identifier,
        googleCalendarID: String = "primary",
        geminiModelID: String? = nil,
        groqBaseURLString: String? = nil,
        whisperCppExecutablePath: String? = nil,
        kokoroExecutablePath: String? = nil,
        ttsLanguageCode: String = "en",
        ttsVoiceID: String = "af_heart",
        openCodeExecutablePath: String? = nil,
        openCodeWorkspacePath: String? = nil,
        openCodeModelID: String? = nil,
        isOpenCodeLocalExecutionApproved: Bool = false,
        // Realtime voice is privacy- and cost-sensitive, so all recording and
        // paid/cloud escalation paths start as explicit opt-ins.
        isLowLatencyVoiceAgentModeEnabled: Bool = false,
        isLowLatencyVoiceAgentAlwaysOnRecordingEnabled: Bool = false,
        isLowLatencyVoiceAgentCloudFallbackEnabled: Bool = false,
        isLowLatencyVoiceAgentCloudFallbackCostVisible: Bool = false,
        taskAutoExecution: TaskAutoExecutionSettings = .default,
        managedAIBilling: ManagedAIBillingSettings = .default
    ) {
        self.aiProvider = aiProvider
        self.sttProvider = sttProvider
        self.ttsProvider = ttsProvider
        self.notificationsEnabled = notificationsEnabled
        self.isDeveloperModeEnabled = isDeveloperModeEnabled
        self.defaultWorkspacePath = defaultWorkspacePath
        self.timeZoneIdentifier = timeZoneIdentifier
        self.googleCalendarID = googleCalendarID
        self.geminiModelID = geminiModelID
        self.groqBaseURLString = groqBaseURLString
        self.whisperCppExecutablePath = whisperCppExecutablePath
        self.kokoroExecutablePath = kokoroExecutablePath
        self.ttsLanguageCode = ttsLanguageCode
        self.ttsVoiceID = ttsVoiceID
        self.openCodeExecutablePath = openCodeExecutablePath
        self.openCodeWorkspacePath = openCodeWorkspacePath
        self.openCodeModelID = openCodeModelID
        self.isOpenCodeLocalExecutionApproved = isOpenCodeLocalExecutionApproved
        self.isLowLatencyVoiceAgentModeEnabled = isLowLatencyVoiceAgentModeEnabled
        self.isLowLatencyVoiceAgentAlwaysOnRecordingEnabled = isLowLatencyVoiceAgentAlwaysOnRecordingEnabled
        self.isLowLatencyVoiceAgentCloudFallbackEnabled = isLowLatencyVoiceAgentCloudFallbackEnabled
        self.isLowLatencyVoiceAgentCloudFallbackCostVisible = isLowLatencyVoiceAgentCloudFallbackCostVisible
        self.taskAutoExecution = taskAutoExecution
        self.managedAIBilling = managedAIBilling
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.aiProvider = try container.decode(AIProvider.self, forKey: .aiProvider)
        self.sttProvider = try container.decode(STTProvider.self, forKey: .sttProvider)
        self.ttsProvider = try container.decodeIfPresent(TTSProvider.self, forKey: .ttsProvider) ?? .localKokoro
        self.notificationsEnabled = try container.decode(Bool.self, forKey: .notificationsEnabled)
        self.isDeveloperModeEnabled = try container.decodeIfPresent(Bool.self, forKey: .isDeveloperModeEnabled) ?? false
        self.defaultWorkspacePath = try container.decodeIfPresent(String.self, forKey: .defaultWorkspacePath)
        self.timeZoneIdentifier = try container.decode(String.self, forKey: .timeZoneIdentifier)
        self.googleCalendarID = try container.decodeIfPresent(String.self, forKey: .googleCalendarID) ?? "primary"
        self.geminiModelID = try container.decodeIfPresent(String.self, forKey: .geminiModelID)
        self.groqBaseURLString = try container.decodeIfPresent(String.self, forKey: .groqBaseURLString)
        self.whisperCppExecutablePath = try container.decodeIfPresent(String.self, forKey: .whisperCppExecutablePath)
        self.kokoroExecutablePath = try container.decodeIfPresent(String.self, forKey: .kokoroExecutablePath)
        self.ttsLanguageCode = try container.decodeIfPresent(String.self, forKey: .ttsLanguageCode) ?? "en"
        self.ttsVoiceID = try container.decodeIfPresent(String.self, forKey: .ttsVoiceID) ?? "af_heart"
        self.openCodeExecutablePath = try container.decodeIfPresent(String.self, forKey: .openCodeExecutablePath)
        self.openCodeWorkspacePath = try container.decodeIfPresent(String.self, forKey: .openCodeWorkspacePath)
        self.openCodeModelID = try container.decodeIfPresent(String.self, forKey: .openCodeModelID)
        self.isOpenCodeLocalExecutionApproved = try container.decodeIfPresent(Bool.self, forKey: .isOpenCodeLocalExecutionApproved) ?? false
        self.isLowLatencyVoiceAgentModeEnabled = try container.decodeIfPresent(Bool.self, forKey: .isLowLatencyVoiceAgentModeEnabled) ?? false
        self.isLowLatencyVoiceAgentAlwaysOnRecordingEnabled = try container.decodeIfPresent(Bool.self, forKey: .isLowLatencyVoiceAgentAlwaysOnRecordingEnabled) ?? false
        self.isLowLatencyVoiceAgentCloudFallbackEnabled = try container.decodeIfPresent(Bool.self, forKey: .isLowLatencyVoiceAgentCloudFallbackEnabled) ?? false
        self.isLowLatencyVoiceAgentCloudFallbackCostVisible = try container.decodeIfPresent(Bool.self, forKey: .isLowLatencyVoiceAgentCloudFallbackCostVisible) ?? false
        self.taskAutoExecution = try container.decodeIfPresent(TaskAutoExecutionSettings.self, forKey: .taskAutoExecution) ?? .default
        self.managedAIBilling = try container.decodeIfPresent(ManagedAIBillingSettings.self, forKey: .managedAIBilling) ?? .default
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(aiProvider, forKey: .aiProvider)
        try container.encode(sttProvider, forKey: .sttProvider)
        try container.encode(ttsProvider, forKey: .ttsProvider)
        try container.encode(notificationsEnabled, forKey: .notificationsEnabled)
        try container.encode(isDeveloperModeEnabled, forKey: .isDeveloperModeEnabled)
        try container.encodeIfPresent(defaultWorkspacePath, forKey: .defaultWorkspacePath)
        try container.encode(timeZoneIdentifier, forKey: .timeZoneIdentifier)
        try container.encode(googleCalendarID, forKey: .googleCalendarID)
        try container.encodeIfPresent(geminiModelID, forKey: .geminiModelID)
        try container.encodeIfPresent(groqBaseURLString, forKey: .groqBaseURLString)
        try container.encodeIfPresent(whisperCppExecutablePath, forKey: .whisperCppExecutablePath)
        try container.encodeIfPresent(kokoroExecutablePath, forKey: .kokoroExecutablePath)
        try container.encode(ttsLanguageCode, forKey: .ttsLanguageCode)
        try container.encode(ttsVoiceID, forKey: .ttsVoiceID)
        try container.encodeIfPresent(openCodeExecutablePath, forKey: .openCodeExecutablePath)
        try container.encodeIfPresent(openCodeWorkspacePath, forKey: .openCodeWorkspacePath)
        try container.encodeIfPresent(openCodeModelID, forKey: .openCodeModelID)
        try container.encode(isOpenCodeLocalExecutionApproved, forKey: .isOpenCodeLocalExecutionApproved)
        try container.encode(isLowLatencyVoiceAgentModeEnabled, forKey: .isLowLatencyVoiceAgentModeEnabled)
        try container.encode(isLowLatencyVoiceAgentAlwaysOnRecordingEnabled, forKey: .isLowLatencyVoiceAgentAlwaysOnRecordingEnabled)
        try container.encode(isLowLatencyVoiceAgentCloudFallbackEnabled, forKey: .isLowLatencyVoiceAgentCloudFallbackEnabled)
        try container.encode(isLowLatencyVoiceAgentCloudFallbackCostVisible, forKey: .isLowLatencyVoiceAgentCloudFallbackCostVisible)
        try container.encode(taskAutoExecution, forKey: .taskAutoExecution)
        try container.encode(managedAIBilling, forKey: .managedAIBilling)
    }

    public static let `default` = AppSettings()

    public var normalizedForRuntime: AppSettings {
        var copy = self
        if !copy.sttProvider.isReleaseReady {
            copy.sttProvider = .openAITranscribe
        }
        if !copy.ttsProvider.isReleaseReady {
            copy.ttsProvider = .localKokoro
        }
        if let geminiModelID = copy.geminiModelID?.trimmingCharacters(in: .whitespacesAndNewlines) {
            copy.geminiModelID = geminiModelID.isEmpty ? nil : geminiModelID
        }
        if let groqBaseURLString = copy.groqBaseURLString?.trimmingCharacters(in: .whitespacesAndNewlines) {
            copy.groqBaseURLString = groqBaseURLString.isEmpty ? nil : groqBaseURLString
        }
        // Google Calendar treats "primary" as the backward-compatible default,
        // while a user-entered blank must stay blank so runtime readiness can flag
        // the external write target instead of silently writing to the wrong calendar.
        copy.googleCalendarID = copy.googleCalendarID.trimmingCharacters(in: .whitespacesAndNewlines)
        if let whisperCppExecutablePath = copy.whisperCppExecutablePath?.trimmingCharacters(in: .whitespacesAndNewlines) {
            copy.whisperCppExecutablePath = whisperCppExecutablePath.isEmpty ? nil : whisperCppExecutablePath
        }
        if let kokoroExecutablePath = copy.kokoroExecutablePath?.trimmingCharacters(in: .whitespacesAndNewlines) {
            copy.kokoroExecutablePath = kokoroExecutablePath.isEmpty ? nil : kokoroExecutablePath
        }
        copy.ttsLanguageCode = Self.normalizedTTSLanguageCode(copy.ttsLanguageCode)
        copy.ttsVoiceID = Self.normalizedTTSVoiceID(copy.ttsVoiceID, languageCode: copy.ttsLanguageCode)
        if let openCodeExecutablePath = copy.openCodeExecutablePath?.trimmingCharacters(in: .whitespacesAndNewlines) {
            copy.openCodeExecutablePath = openCodeExecutablePath.isEmpty ? nil : openCodeExecutablePath
        }
        if let openCodeWorkspacePath = copy.openCodeWorkspacePath?.trimmingCharacters(in: .whitespacesAndNewlines) {
            copy.openCodeWorkspacePath = openCodeWorkspacePath.isEmpty ? nil : openCodeWorkspacePath
        }
        if let openCodeModelID = copy.openCodeModelID?.trimmingCharacters(in: .whitespacesAndNewlines) {
            copy.openCodeModelID = openCodeModelID.isEmpty ? nil : openCodeModelID
        }
        // Runtime starts low-latency listening only from an explicit user
        // action. Persisted or future always-on flags cannot make launch record.
        copy.isLowLatencyVoiceAgentAlwaysOnRecordingEnabled = false
        if !copy.isLowLatencyVoiceAgentCloudFallbackCostVisible {
            copy.isLowLatencyVoiceAgentCloudFallbackEnabled = false
        }
        copy.taskAutoExecution = copy.taskAutoExecution.normalized
        copy.managedAIBilling = copy.managedAIBilling.normalized
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

        if let defaultWorkspacePath {
            appendDefaultWorkspacePathIssue(defaultWorkspacePath, to: &issues)
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
        appendWhisperCppExecutablePathIssue(to: &issues, isRequired: sttProvider == .localWhisperCpp)
        appendKokoroExecutablePathIssue(to: &issues)
        appendTTSSelectionIssues(to: &issues)
        if isLowLatencyVoiceAgentCloudFallbackEnabled && !isLowLatencyVoiceAgentCloudFallbackCostVisible {
            issues.append(
                ValidationIssue(
                    field: "isLowLatencyVoiceAgentCloudFallbackEnabled",
                    message: "Low-latency cloud fallback requires visible cost disclosure.",
                    severity: .error
                )
            )
        }
        issues.append(contentsOf: taskAutoExecution.validationIssues())
        issues.append(contentsOf: managedAIBilling.validationIssues())

        return issues
    }

    public static func normalizedTTSLanguageCode(_ languageCode: String) -> String {
        let normalized = languageCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["ja", "en"].contains(normalized) ? normalized : "en"
    }

    public static func defaultTTSVoiceID(for languageCode: String) -> String {
        normalizedTTSLanguageCode(languageCode) == "ja" ? "jf_alpha" : "af_heart"
    }

    public static func normalizedTTSVoiceID(_ voiceID: String, languageCode: String) -> String {
        let normalized = voiceID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              normalized.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            return defaultTTSVoiceID(for: languageCode)
        }
        let expectedPrefix = normalizedTTSLanguageCode(languageCode) == "ja" ? "j" : "a"
        return normalized.hasPrefix(expectedPrefix) ? normalized : defaultTTSVoiceID(for: languageCode)
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

    private func appendDefaultWorkspacePathIssue(_ path: String, to issues: inout [ValidationIssue]) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            issues.append(
                ValidationIssue(
                    field: "defaultWorkspacePath",
                    message: "Default workspace path cannot be blank.",
                    severity: .error
                )
            )
            return
        }

        let expandedPath = NSString(string: trimmed).expandingTildeInPath
        guard NSString(string: expandedPath).isAbsolutePath else {
            issues.append(
                ValidationIssue(
                    field: "defaultWorkspacePath",
                    message: "Default workspace path must be an absolute directory path.",
                    severity: .error
                )
            )
            return
        }

        let url = URL(fileURLWithPath: expandedPath)
        let fileName = url.lastPathComponent.lowercased()
        let pathExtension = url.pathExtension.lowercased()
        let sensitiveNameSignals = ["credential", "credentials", "secret", "token", "api-key", "apikey", "auth"]
        let sensitiveFileNames = [".env", "credentials.json", "token.json", "auth.json"]
        // The data location is a workspace directory. Rejecting credential-like files prevents users from
        // accidentally pointing SoloPM at secrets that should stay in Keychain or provider-specific stores.
        if sensitiveFileNames.contains(fileName)
            || (!pathExtension.isEmpty && sensitiveNameSignals.contains { fileName.contains($0) }) {
            issues.append(
                ValidationIssue(
                    field: "defaultWorkspacePath",
                    message: "Default workspace path must not point to a credential or token file.",
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

    private func appendWhisperCppExecutablePathIssue(to issues: inout [ValidationIssue], isRequired: Bool) {
        let trimmed = whisperCppExecutablePath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            if isRequired {
                issues.append(
                    ValidationIssue(
                        field: "whisperCppExecutablePath",
                        message: "whisper.cpp executable path is required.",
                        severity: .error
                    )
                )
            }
            return
        }

        let expandedPath = NSString(string: trimmed).expandingTildeInPath
        guard NSString(string: expandedPath).isAbsolutePath else {
            issues.append(
                ValidationIssue(
                    field: "whisperCppExecutablePath",
                    message: "whisper.cpp executable path must be absolute.",
                    severity: .error
                )
            )
            return
        }

        let url = URL(fileURLWithPath: expandedPath)
        let fileName = url.lastPathComponent.lowercased()
        let sensitiveSignals = ["credential", "credentials", "secret", "token", "api-key", "apikey", "auth"]
        let sensitiveFileNames = [".env", "credentials.json", "token.json", "auth.json"]
        if sensitiveFileNames.contains(fileName)
            || sensitiveSignals.contains(where: { fileName.contains($0) }) {
            issues.append(
                ValidationIssue(
                    field: "whisperCppExecutablePath",
                    message: "whisper.cpp executable path must not point to a credential or token file.",
                    severity: .error
                )
            )
        }
    }

    private func appendKokoroExecutablePathIssue(to issues: inout [ValidationIssue]) {
        let trimmed = kokoroExecutablePath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            return
        }

        let expandedPath = NSString(string: trimmed).expandingTildeInPath
        guard NSString(string: expandedPath).isAbsolutePath else {
            issues.append(
                ValidationIssue(
                    field: "kokoroExecutablePath",
                    message: "Kokoro executable path must be absolute.",
                    severity: .error
                )
            )
            return
        }

        let url = URL(fileURLWithPath: expandedPath)
        let fileName = url.lastPathComponent.lowercased()
        let sensitiveSignals = ["credential", "credentials", "secret", "token", "api-key", "apikey", "auth"]
        let sensitiveFileNames = [".env", "credentials.json", "token.json", "auth.json"]
        if sensitiveFileNames.contains(fileName)
            || sensitiveSignals.contains(where: { fileName.contains($0) }) {
            issues.append(
                ValidationIssue(
                    field: "kokoroExecutablePath",
                    message: "Kokoro executable path must not point to a credential or token file.",
                    severity: .error
                )
            )
        }
    }

    private func appendTTSSelectionIssues(to issues: inout [ValidationIssue]) {
        if !ttsProvider.isReleaseReady {
            issues.append(
                ValidationIssue(
                    field: "ttsProvider",
                    message: "\(ttsProvider.displayName) is not available in this build.",
                    severity: .error
                )
            )
        }
        if ttsLanguageCode != Self.normalizedTTSLanguageCode(ttsLanguageCode) {
            issues.append(
                ValidationIssue(
                    field: "ttsLanguageCode",
                    message: "TTS language must be ja or en.",
                    severity: .error
                )
            )
        }
        if ttsVoiceID != Self.normalizedTTSVoiceID(ttsVoiceID, languageCode: ttsLanguageCode) {
            issues.append(
                ValidationIssue(
                    field: "ttsVoiceID",
                    message: "TTS voice must match the selected language.",
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

    public static let releaseReadyCases: [STTProvider] = [.openAITranscribe, .localWhisperCpp]

    public var isReleaseReady: Bool {
        Self.releaseReadyCases.contains(self)
    }

    public var providerID: STTProviderID {
        switch self {
        case .appleSpeechAnalyzer:
            .appleSpeechAnalyzer
        case .localWhisperKit:
            .whisperKit
        case .localWhisperCpp:
            .whisperCpp
        case .openAITranscribe:
            .openAITranscribe
        }
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

public enum TTSProvider: String, CaseIterable, Codable, Equatable, Sendable {
    case systemSpeech
    case localKokoro

    public static let releaseReadyCases: [TTSProvider] = [.localKokoro]

    public var isReleaseReady: Bool {
        Self.releaseReadyCases.contains(self)
    }

    public var displayName: String {
        switch self {
        case .systemSpeech:
            "System Speech"
        case .localKokoro:
            "Local Kokoro"
        }
    }

    public var unavailableReason: String {
        switch self {
        case .systemSpeech:
            "System Speech is kept only for legacy settings and is not product TTS."
        case .localKokoro:
            "Install the Kokoro model and configure the executable in Settings."
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
    public static let suiteNameEnvironmentKey = "SOLOPM_APP_SETTINGS_SUITE_NAME"

    public static func defaultUserDefaults(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> UserDefaults {
        // Runtime smoke tests need a disposable suite so settings assertions never
        // read or mutate the user's real SoloPM preferences.
        let suiteName = environment[suiteNameEnvironmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let suiteName, !suiteName.isEmpty, let defaults = UserDefaults(suiteName: suiteName) {
            return defaults
        }
        return .standard
    }

    private let defaults: UserDefaults
    private let key: String
    private let lock = NSLock()

    public init(defaults: UserDefaults? = nil, key: String = "app.settings") {
        self.defaults = defaults ?? Self.defaultUserDefaults()
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

public struct AIProviderReadinessRow: Identifiable, Equatable, Sendable {
    public var provider: AIProvider
    public var statusLabel: String
    public var detailLabel: String
    public var nextActionLabel: String
    public var isSelected: Bool

    public var id: AIProvider { provider }

    public init(
        provider: AIProvider,
        statusLabel: String,
        detailLabel: String,
        nextActionLabel: String,
        isSelected: Bool
    ) {
        self.provider = provider
        self.statusLabel = statusLabel
        self.detailLabel = detailLabel
        self.nextActionLabel = nextActionLabel
        self.isSelected = isSelected
    }
}

public struct TTSProviderReadinessRow: Identifiable, Equatable, Sendable {
    public var provider: TTSProvider
    public var statusLabel: String
    public var detailLabel: String
    public var nextActionLabel: String
    public var isReady: Bool
    public var isSelected: Bool

    public var id: TTSProvider { provider }

    public init(
        provider: TTSProvider,
        statusLabel: String,
        detailLabel: String,
        nextActionLabel: String,
        isReady: Bool,
        isSelected: Bool
    ) {
        self.provider = provider
        self.statusLabel = statusLabel
        self.detailLabel = detailLabel
        self.nextActionLabel = nextActionLabel
        self.isReady = isReady
        self.isSelected = isSelected
    }
}

public struct STTProviderReadinessRow: Identifiable, Equatable, Sendable {
    public var provider: STTProvider
    public var statusLabel: String
    public var detailLabel: String
    public var nextActionLabel: String
    public var isReady: Bool
    public var isSelected: Bool

    public var id: STTProvider { provider }

    public init(
        provider: STTProvider,
        statusLabel: String,
        detailLabel: String,
        nextActionLabel: String,
        isReady: Bool,
        isSelected: Bool
    ) {
        self.provider = provider
        self.statusLabel = statusLabel
        self.detailLabel = detailLabel
        self.nextActionLabel = nextActionLabel
        self.isReady = isReady
        self.isSelected = isSelected
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
    @Published private var voiceModelStatusOverrides: [VoiceModelID: VoiceModelInstallStatus]

    private let settingsStore: any AppSettingsStore
    private let secretStore: any SecretStore
    private let voiceModelCatalog: VoiceModelCatalog
    private let voiceModelManager: any VoiceModelManaging
    private var rejectedAIProvider: AIProvider?
    private static let settingsSaveFailureMessage = "App settings could not be saved."
    private static let apiKeySaveFailureMessage = "API key could not be saved to Keychain."
    private static let apiKeyDeleteFailureMessage = "API key could not be removed from Keychain."

    public init(
        settingsStore: any AppSettingsStore,
        secretStore: any SecretStore,
        voiceModelCatalog: VoiceModelCatalog = .phase1Default,
        voiceModelManager: any VoiceModelManaging = VoiceModelManager(),
        refreshProviderSecretStatusesOnInit: Bool = true
    ) {
        let initialVoiceModelStatuses = Dictionary(
            uniqueKeysWithValues: voiceModelCatalog.models.map { model in
                (model.id, voiceModelManager.status(for: model))
            }
        )
        self.settingsStore = settingsStore
        self.secretStore = secretStore
        self.voiceModelCatalog = voiceModelCatalog
        self.voiceModelManager = voiceModelManager
        let loadedSettings: AppSettings
        let initialErrorMessage: String?
        do {
            loadedSettings = try settingsStore.load()
            initialErrorMessage = nil
        } catch {
            loadedSettings = .default
            initialErrorMessage = "App settings could not be loaded. Defaults are shown until settings are saved again."
        }
        self.settings = Self.normalizedSettings(
            loadedSettings,
            voiceModelStatuses: initialVoiceModelStatuses,
            voiceModelCatalog: voiceModelCatalog
        )
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
        self.voiceModelStatusOverrides = initialVoiceModelStatuses
        self.rejectedAIProvider = nil
        if refreshProviderSecretStatusesOnInit {
            refreshProviderSecretStatuses()
        }
    }

    @discardableResult
    public func refreshProviderSecretStatuses() -> Bool {
        // Provider Keychain reads can prompt or block on first app launch. Keep
        // them explicit so the Project Board can publish a window before
        // Settings asks for provider readiness.
        let openAIStatus = refreshOpenAIAPIKeyStatus()
        let anthropicStatus = refreshAnthropicAPIKeyStatus()
        let geminiStatus = refreshGeminiAPIKeyStatus()
        let groqStatus = refreshGroqAPIKeyStatus()
        let openRouterStatus = refreshOpenRouterAPIKeyStatus()
        return openAIStatus
            && anthropicStatus
            && geminiStatus
            && groqStatus
            && openRouterStatus
    }

    public var selectableAIProviders: [AIProvider] {
        LLMProviderCatalog.settingsSelectableIDs
    }

    public var selectableSTTProviders: [STTProvider] {
        STTProvider.releaseReadyCases.filter { provider in
            provider != .localWhisperCpp || isLocalWhisperCppReady
        }
    }

    public var selectableTTSProviders: [TTSProvider] {
        TTSProvider.releaseReadyCases
    }

    public var providerReadinessRows: [AIProviderReadinessRow] {
        selectableAIProviders.map { providerReadinessRow(for: $0) }
    }

    public var ttsProviderReadinessRow: TTSProviderReadinessRow {
        makeTTSProviderReadinessRow(for: settings.ttsProvider)
    }

    public var localSTTProviderReadinessRow: STTProviderReadinessRow {
        makeLocalSTTProviderReadinessRow()
    }

    public var voiceModelReadinessRows: [VoiceModelReadinessRow] {
        voiceModelCatalog.models.map { model in
            VoiceModelReadinessRow(
                model: model,
                status: voiceModelStatusOverrides[model.id] ?? voiceModelManager.status(for: model)
            )
        }
    }

    public func installVoiceModel(_ modelID: VoiceModelID) async {
        guard let model = voiceModelCatalog.model(for: modelID) else {
            errorMessage = "Voice model is not registered."
            successMessage = nil
            return
        }

        voiceModelStatusOverrides[modelID] = .downloading
        clearMessages()
        do {
            _ = try await voiceModelManager.install(model)
            voiceModelStatusOverrides[modelID] = .installed
            normalizeSTTProviderSelection()
            successMessage = "Voice model is installed."
            errorMessage = nil
        } catch let error as VoiceModelManagerError {
            let message = error.userMessage
            voiceModelStatusOverrides[modelID] = .failed(message)
            errorMessage = message
            successMessage = nil
        } catch {
            let message = UserFacingErrorMessageSanitizer.message(from: error)
            voiceModelStatusOverrides[modelID] = .failed(message)
            errorMessage = message
            successMessage = nil
        }
    }

    public func removeVoiceModelFromCache(_ modelID: VoiceModelID) {
        guard let model = voiceModelCatalog.model(for: modelID) else {
            errorMessage = "Voice model is not registered."
            successMessage = nil
            return
        }

        do {
            try voiceModelManager.removeFromCache(model)
            voiceModelStatusOverrides[modelID] = .notInstalled
            normalizeSTTProviderSelection()
            successMessage = "Voice model cache entry was removed."
            errorMessage = nil
        } catch let error as VoiceModelManagerError {
            let message = error.userMessage
            voiceModelStatusOverrides[modelID] = .failed(message)
            errorMessage = message
            successMessage = nil
        } catch {
            let message = UserFacingErrorMessageSanitizer.message(from: error)
            voiceModelStatusOverrides[modelID] = .failed(message)
            errorMessage = message
            successMessage = nil
        }
    }

    public func providerReadinessRow(for provider: AIProvider) -> AIProviderReadinessRow {
        AIProviderReadinessRow(
            provider: provider,
            statusLabel: providerReadinessStatusLabel(for: provider),
            detailLabel: providerReadinessDetailLabel(for: provider),
            nextActionLabel: providerReadinessNextActionLabel(for: provider),
            isSelected: settings.aiProvider == provider
        )
    }

    private func makeTTSProviderReadinessRow(for provider: TTSProvider) -> TTSProviderReadinessRow {
        guard provider == .localKokoro else {
            return TTSProviderReadinessRow(
                provider: provider,
                statusLabel: "Unsupported",
                detailLabel: provider.unavailableReason,
                nextActionLabel: "Select Local Kokoro",
                isReady: false,
                isSelected: settings.ttsProvider == provider
            )
        }

        guard let model = voiceModelCatalog.model(for: .kokoro82M) else {
            return TTSProviderReadinessRow(
                provider: provider,
                statusLabel: "Model unavailable",
                detailLabel: "Kokoro model metadata is not registered.",
                nextActionLabel: "Update voice model catalog",
                isReady: false,
                isSelected: settings.ttsProvider == provider
            )
        }

        let status = voiceModelStatusOverrides[model.id] ?? voiceModelManager.status(for: model)
        guard status == .installed else {
            return TTSProviderReadinessRow(
                provider: provider,
                statusLabel: "Model not installed",
                detailLabel: "\(model.displayName) - \(model.licenseName) - \(model.sourceURL.host ?? "unknown source")",
                nextActionLabel: "Download Kokoro model",
                isReady: false,
                isSelected: settings.ttsProvider == provider
            )
        }

        guard Self.isKokoroExecutableReady(settings.kokoroExecutablePath) else {
            return TTSProviderReadinessRow(
                provider: provider,
                statusLabel: "Runtime pending",
                detailLabel: "Kokoro executable path is required for offline speech.",
                nextActionLabel: "Configure Kokoro executable",
                isReady: false,
                isSelected: settings.ttsProvider == provider
            )
        }

        return TTSProviderReadinessRow(
            provider: provider,
            statusLabel: "Ready",
            detailLabel: "\(settings.ttsLanguageCode.uppercased()) / \(settings.ttsVoiceID) short prompts",
            nextActionLabel: "Test play",
            isReady: true,
            isSelected: settings.ttsProvider == provider
        )
    }

    private func makeLocalSTTProviderReadinessRow() -> STTProviderReadinessRow {
        let provider = STTProvider.localWhisperCpp
        guard let model = voiceModelCatalog.model(for: .whisperCppTinyMultilingual) else {
            return STTProviderReadinessRow(
                provider: provider,
                statusLabel: "Model unavailable",
                detailLabel: "whisper.cpp model metadata is not registered.",
                nextActionLabel: "Update voice model catalog",
                isReady: false,
                isSelected: settings.sttProvider == provider
            )
        }

        let status = voiceModelStatusOverrides[model.id] ?? voiceModelManager.status(for: model)
        guard status == .installed else {
            return STTProviderReadinessRow(
                provider: provider,
                statusLabel: localSTTModelStatusLabel(for: status),
                detailLabel: "\(model.displayName) - \(model.licenseName) - \(model.sourceURL.host ?? "unknown source")",
                nextActionLabel: localSTTModelNextActionLabel(for: status),
                isReady: false,
                isSelected: settings.sttProvider == provider
            )
        }

        guard Self.isWhisperCppExecutableReady(settings.whisperCppExecutablePath) else {
            return STTProviderReadinessRow(
                provider: provider,
                statusLabel: "Runtime pending",
                detailLabel: "whisper.cpp executable path is required for offline speech to text.",
                nextActionLabel: "Configure whisper.cpp executable",
                isReady: false,
                isSelected: settings.sttProvider == provider
            )
        }

        return STTProviderReadinessRow(
            provider: provider,
            statusLabel: "Smoke pending",
            detailLabel: "Model and executable are ready; run the local voice runtime smoke before release closeout.",
            nextActionLabel: "Run local voice smoke",
            // Selection is allowed at this stage, but release readiness still
            // needs an explicit runtime smoke result tied to the current build.
            isReady: false,
            isSelected: settings.sttProvider == provider
        )
    }

    private func localSTTModelStatusLabel(for status: VoiceModelInstallStatus) -> String {
        switch status {
        case .downloading:
            "Downloading"
        case .failed:
            "Download failed"
        case .corrupted:
            "Needs reinstall"
        case .notInstalled, .installed:
            "Model not installed"
        }
    }

    private func localSTTModelNextActionLabel(for status: VoiceModelInstallStatus) -> String {
        switch status {
        case .downloading:
            "Wait for download"
        case .failed, .corrupted:
            "Retry whisper.cpp model"
        case .notInstalled, .installed:
            "Download whisper.cpp model"
        }
    }

    public func setNotificationsEnabled(_ isEnabled: Bool) {
        settings.notificationsEnabled = isEnabled
        clearMessages()
    }

    public func setDeveloperModeEnabled(_ isEnabled: Bool) {
        settings.isDeveloperModeEnabled = isEnabled
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
        guard provider.isReleaseReady else {
            settings.sttProvider = .openAITranscribe
            clearMessages()
            return
        }
        guard provider != .localWhisperCpp || isLocalWhisperCppReady else {
            settings.sttProvider = .openAITranscribe
            errorMessage = "Install the whisper.cpp model and configure the executable before selecting offline speech to text."
            successMessage = nil
            return
        }
        settings.sttProvider = provider
        clearMessages()
    }

    public func setTTSProvider(_ provider: TTSProvider) {
        guard provider.isReleaseReady else {
            settings.ttsProvider = .localKokoro
            clearMessages()
            return
        }
        settings.ttsProvider = provider
        clearMessages()
    }

    public func setDefaultWorkspacePath(_ path: String) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.defaultWorkspacePath = trimmed.isEmpty ? nil : trimmed
        clearMessages()
    }

    public func setGoogleCalendarID(_ calendarID: String) {
        settings.googleCalendarID = calendarID.trimmingCharacters(in: .whitespacesAndNewlines)
        clearMessages()
    }

    public func setTransientErrorMessage(_ message: String) {
        rejectedAIProvider = nil
        errorMessage = message
        successMessage = nil
    }

    public func testTTSPlayback(using previewer: any TextToSpeechPreviewing) async {
        let readinessRow = ttsProviderReadinessRow
        guard readinessRow.isReady else {
            rejectedAIProvider = nil
            errorMessage = "\(readinessRow.nextActionLabel) before test play."
            successMessage = nil
            return
        }

        let issues = settings.validate().filter { $0.severity == .error }
        guard issues.isEmpty else {
            rejectedAIProvider = nil
            errorMessage = issues.map(\.message).joined(separator: " ")
            successMessage = nil
            return
        }

        let request = TextToSpeechRequest(
            text: Self.ttsPreviewText(for: settings.ttsLanguageCode),
            languageCode: settings.ttsLanguageCode,
            voiceID: settings.ttsVoiceID
        )

        clearMessages()
        do {
            try await previewer.playPreview(request)
            errorMessage = nil
            successMessage = "TTS test play completed."
        } catch {
            errorMessage = "TTS test play failed. \(Self.sanitizedTTSPreviewFailureMessage(from: error))"
            successMessage = nil
        }
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

    public func setWhisperCppExecutablePath(_ path: String) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.whisperCppExecutablePath = trimmed.isEmpty ? nil : trimmed
        normalizeSTTProviderSelection()
        clearMessages()
    }

    public func setKokoroExecutablePath(_ path: String) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.kokoroExecutablePath = trimmed.isEmpty ? nil : trimmed
        clearMessages()
    }

    public func setTTSLanguageCode(_ languageCode: String) {
        let normalized = AppSettings.normalizedTTSLanguageCode(languageCode)
        settings.ttsLanguageCode = normalized
        settings.ttsVoiceID = AppSettings.normalizedTTSVoiceID(settings.ttsVoiceID, languageCode: normalized)
        clearMessages()
    }

    public func setTTSVoiceID(_ voiceID: String) {
        settings.ttsVoiceID = AppSettings.normalizedTTSVoiceID(voiceID, languageCode: settings.ttsLanguageCode)
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

    public func setLowLatencyVoiceAgentModeEnabled(_ isEnabled: Bool) {
        settings.isLowLatencyVoiceAgentModeEnabled = isEnabled
        clearMessages()
    }

    public func setLowLatencyVoiceAgentCloudFallbackCostVisible(_ isVisible: Bool) {
        settings.isLowLatencyVoiceAgentCloudFallbackCostVisible = isVisible
        if !isVisible {
            settings.isLowLatencyVoiceAgentCloudFallbackEnabled = false
        }
        clearMessages()
    }

    public func setLowLatencyVoiceAgentCloudFallbackEnabled(_ isEnabled: Bool) {
        settings.isLowLatencyVoiceAgentCloudFallbackEnabled = isEnabled
        clearMessages()
    }

    public func setTaskAutoExecutionEnabled(_ isEnabled: Bool) {
        settings.taskAutoExecution.isEnabled = isEnabled
        clearMessages()
    }

    public func setTaskAutoExecutionMode(_ mode: TaskAutoExecutionMode) {
        settings.taskAutoExecution.mode = mode
        clearMessages()
    }

    public func setTaskAutoExecutionCadence(_ cadence: TaskAutoExecutionCadence) {
        settings.taskAutoExecution.cadence = cadence
        clearMessages()
    }

    public func setTaskAutoExecutionMaxTasksPerRun(_ value: Int) {
        settings.taskAutoExecution.maxTasksPerRun = value
        clearMessages()
    }

    public func setTaskAutoExecutionDailyLLMCallLimit(_ value: Int) {
        settings.taskAutoExecution.dailyLLMCallLimit = value
        clearMessages()
    }

    public func setTaskAutoExecutionLookaheadHours(_ value: Int) {
        settings.taskAutoExecution.lookaheadHours = value
        clearMessages()
    }

    public func setTaskAutoExecutionUrgentReviewCooldownMinutes(_ value: Int) {
        settings.taskAutoExecution.urgentReviewCooldownMinutes = value
        clearMessages()
    }

    public func setManagedAIBillingEnabled(_ isEnabled: Bool) {
        settings.managedAIBilling.isEnabled = isEnabled
        clearMessages()
    }

    public func setManagedAIPerRunCapCents(_ value: Int?) {
        settings.managedAIBilling.perRunCapCents = value
        clearMessages()
    }

    public func setManagedAIDailyCapCents(_ value: Int?) {
        settings.managedAIBilling.dailyCapCents = value
        clearMessages()
    }

    public func setManagedAIMonthlyCapCents(_ value: Int?) {
        settings.managedAIBilling.monthlyCapCents = value
        clearMessages()
    }

    public func setManagedAIWorkspaceCapCents(_ value: Int?) {
        settings.managedAIBilling.workspaceCapCents = value
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
            errorMessage = Self.settingsSaveFailureMessage
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
            errorMessage = Self.apiKeySaveFailureMessage
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
            errorMessage = Self.apiKeySaveFailureMessage
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
            errorMessage = Self.apiKeySaveFailureMessage
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
            errorMessage = Self.apiKeySaveFailureMessage
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
            errorMessage = Self.apiKeySaveFailureMessage
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
            errorMessage = Self.apiKeyDeleteFailureMessage
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
            errorMessage = Self.apiKeyDeleteFailureMessage
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
            errorMessage = Self.apiKeyDeleteFailureMessage
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
            errorMessage = Self.apiKeyDeleteFailureMessage
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
            errorMessage = Self.apiKeyDeleteFailureMessage
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

    private static func normalizedSettings(
        _ settings: AppSettings,
        voiceModelStatuses: [VoiceModelID: VoiceModelInstallStatus],
        voiceModelCatalog: VoiceModelCatalog
    ) -> AppSettings {
        var normalized = settings.normalizedForRuntime
        if normalized.sttProvider == .localWhisperCpp,
           !isLocalWhisperCppReady(
                settings: normalized,
                voiceModelStatuses: voiceModelStatuses,
                voiceModelCatalog: voiceModelCatalog
           ) {
            normalized.sttProvider = .openAITranscribe
        }
        return normalized
    }

    private var isLocalWhisperCppReady: Bool {
        Self.isLocalWhisperCppReady(
            settings: settings,
            voiceModelStatuses: voiceModelStatusOverrides,
            voiceModelCatalog: voiceModelCatalog
        )
    }

    private static func isLocalWhisperCppReady(
        settings: AppSettings,
        voiceModelStatuses: [VoiceModelID: VoiceModelInstallStatus],
        voiceModelCatalog: VoiceModelCatalog
    ) -> Bool {
        guard isWhisperCppExecutableReady(settings.whisperCppExecutablePath),
              let model = voiceModelCatalog.model(for: .whisperCppTinyMultilingual),
              voiceModelStatuses[model.id] == .installed else {
            return false
        }
        return true
    }

    private static func isWhisperCppExecutableReady(_ path: String?) -> Bool {
        let trimmed = path?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            return false
        }

        let expandedPath = NSString(string: trimmed).expandingTildeInPath
        guard NSString(string: expandedPath).isAbsolutePath else {
            return false
        }

        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: expandedPath, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return false
        }
        return FileManager.default.isExecutableFile(atPath: expandedPath)
    }

    private static func isKokoroExecutableReady(_ path: String?) -> Bool {
        let trimmed = path?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            return false
        }

        let expandedPath = NSString(string: trimmed).expandingTildeInPath
        guard NSString(string: expandedPath).isAbsolutePath else {
            return false
        }

        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: expandedPath, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return false
        }
        return FileManager.default.isExecutableFile(atPath: expandedPath)
    }

    private func normalizeSTTProviderSelection() {
        if settings.sttProvider == .localWhisperCpp, !isLocalWhisperCppReady {
            settings.sttProvider = .openAITranscribe
        }
    }

    private func clearMessages() {
        rejectedAIProvider = nil
        errorMessage = nil
        successMessage = nil
    }

    private static func ttsPreviewText(for languageCode: String) -> String {
        AppSettings.normalizedTTSLanguageCode(languageCode) == "ja"
            ? "SoloPMのローカル音声テストです。"
            : "SoloPM local voice test is ready."
    }

    private static func sanitizedTTSPreviewFailureMessage(from error: Error) -> String {
        let rawMessage: String
        if let error = error as? TTSProviderError {
            rawMessage = error.userMessage
        } else if let error = error as? SpeechAudioPlaybackError {
            rawMessage = error.userMessage
        } else {
            rawMessage = UserFacingErrorMessageSanitizer.message(from: error)
        }
        let redactedSecrets = UserFacingErrorMessageSanitizer.message(
            from: rawMessage,
            fallback: "Playback failed."
        )
        return LocalPathRedactor.redact(redactedSecrets)
    }

    private func unavailableMessage(for provider: AIProvider) -> String {
        "\(provider.displayName) is not available in this build."
    }

    private func providerReadinessStatusLabel(for provider: AIProvider) -> String {
        guard LLMProviderCatalog.isAvailableInCurrentBuild(provider) else {
            return "Not available"
        }

        switch provider {
        case .openaiResponses:
            return openAIAPIKeyStatusLabel
        case .claudeMessages:
            return anthropicAPIKeyStatusLabel
        case .geminiDirect:
            return geminiAPIKeyStatusLabel
        case .geminiOpenAICompatible:
            return "Not available"
        case .groqOpenAICompatible:
            return groqAPIKeyStatusLabel
        case .opencodeLocal:
            return openCodeReadinessStatusLabel
        case .openRouterCompatible:
            return openRouterAPIKeyStatusLabel
        case .ollamaCompatible:
            return "Local"
        }
    }

    private func providerReadinessDetailLabel(for provider: AIProvider) -> String {
        guard LLMProviderCatalog.isAvailableInCurrentBuild(provider) else {
            return LLMProviderCatalog.entry(for: provider).unavailableReason ?? "Not available in this build."
        }

        switch provider {
        case .openaiResponses:
            return "Smoke: \(providerSmokeDisplayLabel(openAIProviderSmokeStatusLabel))"
        case .claudeMessages:
            return "Uses Anthropic Keychain secret with the Claude Messages runtime."
        case .geminiDirect:
            return "Smoke: \(providerSmokeDisplayLabel(geminiProviderSmokeStatusLabel))"
        case .geminiOpenAICompatible:
            return LLMProviderCatalog.entry(for: provider).unavailableReason ?? "Not available in this build."
        case .groqOpenAICompatible:
            return "Smoke: \(providerSmokeDisplayLabel(groqProviderSmokeStatusLabel))"
        case .opencodeLocal:
            return openCodeReadinessDetailLabel
        case .openRouterCompatible:
            return "Uses OpenRouter Keychain secret with an OpenAI-compatible runtime."
        case .ollamaCompatible:
            return "Local endpoint; API key is not required."
        }
    }

    private func providerReadinessNextActionLabel(for provider: AIProvider) -> String {
        guard LLMProviderCatalog.isAvailableInCurrentBuild(provider) else {
            return "Select an available provider."
        }

        switch provider {
        case .opencodeLocal:
            if settings.openCodeExecutablePath == nil {
                return "Set the OpenCode executable path."
            }
            if settings.openCodeWorkspacePath == nil {
                return "Set the workspace path."
            }
            if !settings.isOpenCodeLocalExecutionApproved {
                return "Review the local command and approve execution."
            }
            return "Generate a reviewed plan when you are ready."
        case .ollamaCompatible:
            return "Start the local Ollama-compatible server before planning."
        case .geminiOpenAICompatible:
            return "Select an available provider."
        default:
            switch providerReadinessStatusLabel(for: provider) {
            case "Configured":
                return "Generate a reviewed plan or run a manual smoke check."
            case "Invalid":
                return "Re-enter the provider API key in Keychain."
            case "Unavailable":
                return "Check Keychain access and reopen Settings."
            default:
                return "Save the provider API key in Keychain."
            }
        }
    }

    private var openCodeReadinessStatusLabel: String {
        if settings.openCodeExecutablePath == nil || settings.openCodeWorkspacePath == nil {
            return "Setup required"
        }
        return settings.isOpenCodeLocalExecutionApproved ? "Approved" : "Approval required"
    }

    private var openCodeReadinessDetailLabel: String {
        if settings.openCodeExecutablePath == nil {
            return "Executable path is required."
        }
        if settings.openCodeWorkspacePath == nil {
            return "Workspace path is required."
        }
        if !settings.isOpenCodeLocalExecutionApproved {
            return "Local execution approval is required."
        }
        return "Local execution is approved for the selected workspace."
    }

    private func providerSmokeDisplayLabel(_ rawLabel: String) -> String {
        switch rawLabel {
        case "readyForManualSmoke":
            return "Ready for manual smoke"
        case "notConfigured":
            return "Not configured"
        case "invalidConfiguration":
            return "Invalid configuration"
        case "unavailable":
            return "Unavailable"
        default:
            return rawLabel
        }
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
