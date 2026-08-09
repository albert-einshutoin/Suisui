import Combine
import Foundation

public extension Notification.Name {
    /// Invalidates in-memory Codex account and planning operations whenever
    /// the user changes the provider or the executable approval boundary.
    static let suisuiCodexExecutionApprovalDidChange = Notification.Name(
        "dev.suisui.codexExecutionApprovalDidChange"
    )
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var aiProvider: AIProvider
    public var sttProvider: STTProvider
    public var ttsProvider: TTSProvider
    public var sttRoutingPreference: VoiceRoutingPreference
    public var ttsRoutingPreference: VoiceRoutingPreference
    public var notificationsEnabled: Bool
    public var notificationPreferences: NotificationPreferences
    public var isDeveloperModeEnabled: Bool
    public var defaultWorkspacePath: String?
    public var profileDisplayName: String?
    public var dailyWorkCapacityMinutes: Int
    public var timeZoneIdentifier: String
    public var googleCalendarID: String
    public var geminiModelID: String?
    public var groqBaseURLString: String?
    public var whisperCppExecutablePath: String?
    public var kokoroExecutablePath: String?
    public var ttsLanguageCode: String
    public var ttsVoiceID: String
    // macOS and Kokoro use unrelated voice identifier namespaces. Persisting
    // them separately keeps a provider round trip from destroying the user's
    // installed System Speech voice selection.
    public var systemSpeechVoiceID: String? = nil
    public var openCodeExecutablePath: String?
    public var openCodeWorkspacePath: String?
    public var openCodeModelID: String?
    public var isOpenCodeLocalExecutionApproved: Bool
    public var codexExecutablePath: String?
    public var codexModelID: String?
    public var isCodexLocalExecutionApproved: Bool
    public var approvedCodexExecutable: ApprovedCodexExecutable?
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
        case sttRoutingPreference
        case ttsRoutingPreference
        case notificationsEnabled
        case notificationPreferences
        case isDeveloperModeEnabled
        case defaultWorkspacePath
        case profileDisplayName
        case dailyWorkCapacityMinutes
        case timeZoneIdentifier
        case googleCalendarID
        case geminiModelID
        case groqBaseURLString
        case whisperCppExecutablePath
        case kokoroExecutablePath
        case ttsLanguageCode
        case ttsVoiceID
        case systemSpeechVoiceID
        case openCodeExecutablePath
        case openCodeWorkspacePath
        case openCodeModelID
        case isOpenCodeLocalExecutionApproved
        case codexExecutablePath
        case codexModelID
        case isCodexLocalExecutionApproved
        case approvedCodexExecutable
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
        sttRoutingPreference: VoiceRoutingPreference = .appleFirst,
        ttsRoutingPreference: VoiceRoutingPreference = .appleFirst,
        notificationsEnabled: Bool = false,
        notificationPreferences: NotificationPreferences = .default,
        isDeveloperModeEnabled: Bool = false,
        defaultWorkspacePath: String? = nil,
        profileDisplayName: String? = nil,
        dailyWorkCapacityMinutes: Int = 480,
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
        codexExecutablePath: String? = nil,
        codexModelID: String? = nil,
        isCodexLocalExecutionApproved: Bool = false,
        approvedCodexExecutable: ApprovedCodexExecutable? = nil,
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
        self.sttRoutingPreference = sttRoutingPreference
        self.ttsRoutingPreference = ttsRoutingPreference
        self.notificationsEnabled = notificationsEnabled
        self.notificationPreferences = notificationPreferences
        self.isDeveloperModeEnabled = isDeveloperModeEnabled
        self.defaultWorkspacePath = defaultWorkspacePath
        self.profileDisplayName = profileDisplayName
        self.dailyWorkCapacityMinutes = dailyWorkCapacityMinutes
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
        self.codexExecutablePath = codexExecutablePath
        self.codexModelID = codexModelID
        self.isCodexLocalExecutionApproved = isCodexLocalExecutionApproved
        self.approvedCodexExecutable = approvedCodexExecutable
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
        if let rawSTTRoutingPreference = try container.decodeIfPresent(String.self, forKey: .sttRoutingPreference),
           let routingPreference = VoiceRoutingPreference(rawValue: rawSTTRoutingPreference) {
            self.sttRoutingPreference = routingPreference
        } else {
            self.sttRoutingPreference = .appleFirst
        }
        if let rawTTSRoutingPreference = try container.decodeIfPresent(String.self, forKey: .ttsRoutingPreference),
           let routingPreference = VoiceRoutingPreference(rawValue: rawTTSRoutingPreference) {
            self.ttsRoutingPreference = routingPreference
        } else {
            self.ttsRoutingPreference = .appleFirst
        }
        self.notificationsEnabled = try container.decode(Bool.self, forKey: .notificationsEnabled)
        // Settings saved before quiet hours and lead-time preferences existed
        // have no notificationPreferences key; decode to defaults.
        self.notificationPreferences = try container.decodeIfPresent(
            NotificationPreferences.self,
            forKey: .notificationPreferences
        ) ?? .default
        self.isDeveloperModeEnabled = try container.decodeIfPresent(Bool.self, forKey: .isDeveloperModeEnabled) ?? false
        self.defaultWorkspacePath = try container.decodeIfPresent(String.self, forKey: .defaultWorkspacePath)
        self.profileDisplayName = try container.decodeIfPresent(String.self, forKey: .profileDisplayName)
        self.dailyWorkCapacityMinutes = try container.decodeIfPresent(Int.self, forKey: .dailyWorkCapacityMinutes) ?? 480
        self.timeZoneIdentifier = try container.decode(String.self, forKey: .timeZoneIdentifier)
        self.googleCalendarID = try container.decodeIfPresent(String.self, forKey: .googleCalendarID) ?? "primary"
        self.geminiModelID = try container.decodeIfPresent(String.self, forKey: .geminiModelID)
        self.groqBaseURLString = try container.decodeIfPresent(String.self, forKey: .groqBaseURLString)
        self.whisperCppExecutablePath = try container.decodeIfPresent(String.self, forKey: .whisperCppExecutablePath)
        self.kokoroExecutablePath = try container.decodeIfPresent(String.self, forKey: .kokoroExecutablePath)
        self.ttsLanguageCode = try container.decodeIfPresent(String.self, forKey: .ttsLanguageCode) ?? "en"
        self.ttsVoiceID = try container.decodeIfPresent(String.self, forKey: .ttsVoiceID) ?? "af_heart"
        self.systemSpeechVoiceID = try container.decodeIfPresent(String.self, forKey: .systemSpeechVoiceID)
        self.openCodeExecutablePath = try container.decodeIfPresent(String.self, forKey: .openCodeExecutablePath)
        self.openCodeWorkspacePath = try container.decodeIfPresent(String.self, forKey: .openCodeWorkspacePath)
        self.openCodeModelID = try container.decodeIfPresent(String.self, forKey: .openCodeModelID)
        self.isOpenCodeLocalExecutionApproved = try container.decodeIfPresent(Bool.self, forKey: .isOpenCodeLocalExecutionApproved) ?? false
        self.codexExecutablePath = try container.decodeIfPresent(String.self, forKey: .codexExecutablePath)
        self.codexModelID = try container.decodeIfPresent(String.self, forKey: .codexModelID)
        self.approvedCodexExecutable = try container.decodeIfPresent(
            ApprovedCodexExecutable.self,
            forKey: .approvedCodexExecutable
        )
        // Settings created before approval identity binding fail closed and must
        // be explicitly re-approved by the user.
        self.isCodexLocalExecutionApproved = (
            try container.decodeIfPresent(Bool.self, forKey: .isCodexLocalExecutionApproved) ?? false
        ) && self.approvedCodexExecutable != nil
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
        try container.encode(sttRoutingPreference, forKey: .sttRoutingPreference)
        try container.encode(ttsRoutingPreference, forKey: .ttsRoutingPreference)
        try container.encode(notificationsEnabled, forKey: .notificationsEnabled)
        try container.encode(notificationPreferences, forKey: .notificationPreferences)
        try container.encode(isDeveloperModeEnabled, forKey: .isDeveloperModeEnabled)
        try container.encodeIfPresent(defaultWorkspacePath, forKey: .defaultWorkspacePath)
        try container.encodeIfPresent(profileDisplayName, forKey: .profileDisplayName)
        try container.encode(dailyWorkCapacityMinutes, forKey: .dailyWorkCapacityMinutes)
        try container.encode(timeZoneIdentifier, forKey: .timeZoneIdentifier)
        try container.encode(googleCalendarID, forKey: .googleCalendarID)
        try container.encodeIfPresent(geminiModelID, forKey: .geminiModelID)
        try container.encodeIfPresent(groqBaseURLString, forKey: .groqBaseURLString)
        try container.encodeIfPresent(whisperCppExecutablePath, forKey: .whisperCppExecutablePath)
        try container.encodeIfPresent(kokoroExecutablePath, forKey: .kokoroExecutablePath)
        try container.encode(ttsLanguageCode, forKey: .ttsLanguageCode)
        try container.encode(ttsVoiceID, forKey: .ttsVoiceID)
        try container.encodeIfPresent(systemSpeechVoiceID, forKey: .systemSpeechVoiceID)
        try container.encodeIfPresent(openCodeExecutablePath, forKey: .openCodeExecutablePath)
        try container.encodeIfPresent(openCodeWorkspacePath, forKey: .openCodeWorkspacePath)
        try container.encodeIfPresent(openCodeModelID, forKey: .openCodeModelID)
        try container.encode(isOpenCodeLocalExecutionApproved, forKey: .isOpenCodeLocalExecutionApproved)
        try container.encodeIfPresent(codexExecutablePath, forKey: .codexExecutablePath)
        try container.encodeIfPresent(codexModelID, forKey: .codexModelID)
        try container.encode(isCodexLocalExecutionApproved, forKey: .isCodexLocalExecutionApproved)
        try container.encodeIfPresent(approvedCodexExecutable, forKey: .approvedCodexExecutable)
        try container.encode(isLowLatencyVoiceAgentModeEnabled, forKey: .isLowLatencyVoiceAgentModeEnabled)
        try container.encode(isLowLatencyVoiceAgentAlwaysOnRecordingEnabled, forKey: .isLowLatencyVoiceAgentAlwaysOnRecordingEnabled)
        try container.encode(isLowLatencyVoiceAgentCloudFallbackEnabled, forKey: .isLowLatencyVoiceAgentCloudFallbackEnabled)
        try container.encode(isLowLatencyVoiceAgentCloudFallbackCostVisible, forKey: .isLowLatencyVoiceAgentCloudFallbackCostVisible)
        try container.encode(taskAutoExecution, forKey: .taskAutoExecution)
        try container.encode(managedAIBilling, forKey: .managedAIBilling)
    }

    public static let `default` = AppSettings()
    public static let minimumDailyWorkCapacityMinutes = 60
    public static let maximumDailyWorkCapacityMinutes = 16 * 60
    public static let dailyWorkCapacityStepMinutes = 30

    public static func normalizedDailyWorkCapacityMinutes(_ minutes: Int) -> Int {
        let bounded = min(max(minutes, minimumDailyWorkCapacityMinutes), maximumDailyWorkCapacityMinutes)
        return (bounded / dailyWorkCapacityStepMinutes) * dailyWorkCapacityStepMinutes
    }

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
        if let profileDisplayName = copy.profileDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines) {
            copy.profileDisplayName = profileDisplayName.isEmpty ? nil : String(profileDisplayName.prefix(80))
        }
        copy.dailyWorkCapacityMinutes = Self.normalizedDailyWorkCapacityMinutes(copy.dailyWorkCapacityMinutes)
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
        if let systemSpeechVoiceID = copy.systemSpeechVoiceID?.trimmingCharacters(in: .whitespacesAndNewlines) {
            copy.systemSpeechVoiceID = systemSpeechVoiceID.isEmpty ? nil : systemSpeechVoiceID
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
        if let codexExecutablePath = copy.codexExecutablePath?.trimmingCharacters(in: .whitespacesAndNewlines) {
            copy.codexExecutablePath = codexExecutablePath.isEmpty ? nil : codexExecutablePath
        }
        if copy.codexExecutablePath != copy.approvedCodexExecutable?.path ||
            copy.approvedCodexExecutable?.identity.hasContentIntegrityEvidence == false ||
            (
                copy.approvedCodexExecutable?.trustPolicy == .developerUnsignedAllowed &&
                !copy.isDeveloperModeEnabled
            ) {
            copy.isCodexLocalExecutionApproved = false
            copy.approvedCodexExecutable = nil
        }
        if let codexModelID = copy.codexModelID?.trimmingCharacters(in: .whitespacesAndNewlines) {
            copy.codexModelID = codexModelID.isEmpty ? nil : codexModelID
        }
        // Runtime starts low-latency listening only from an explicit user
        // action. Persisted or future always-on flags cannot make launch record.
        copy.isLowLatencyVoiceAgentAlwaysOnRecordingEnabled = false
        if !copy.isLowLatencyVoiceAgentCloudFallbackCostVisible {
            copy.isLowLatencyVoiceAgentCloudFallbackEnabled = false
        }
        copy.taskAutoExecution = copy.taskAutoExecution.normalized
        copy.managedAIBilling = copy.managedAIBilling.normalized
        copy.notificationPreferences.quietHours = copy.notificationPreferences.quietHours.normalized
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

        if !(Self.minimumDailyWorkCapacityMinutes...Self.maximumDailyWorkCapacityMinutes).contains(dailyWorkCapacityMinutes)
            || dailyWorkCapacityMinutes % Self.dailyWorkCapacityStepMinutes != 0 {
            issues.append(
                ValidationIssue(
                    field: "dailyWorkCapacityMinutes",
                    message: "Daily work capacity must be between 1 and 16 hours in 30-minute steps.",
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
        if aiProvider == .codexLocal {
            appendCodexLocalIssues(to: &issues)
        } else {
            appendOptionalCodexLocalIssues(to: &issues)
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

    public static func normalizedTTSVoiceID(
        _ voiceID: String,
        languageCode: String,
        provider: TTSProvider
    ) -> String {
        switch provider {
        case .systemSpeech:
            // AVSpeechSynthesisVoice identifiers are owned by macOS and do not
            // follow Kokoro's a/j naming convention. Preserve the installed
            // voice identifier verbatim after removing accidental edge space.
            return voiceID.trimmingCharacters(in: .whitespacesAndNewlines)
        case .localKokoro:
            return normalizedTTSVoiceID(voiceID, languageCode: languageCode)
        }
    }

    public var selectedTTSVoiceID: String {
        switch ttsProvider {
        case .systemSpeech:
            systemSpeechVoiceID ?? ""
        case .localKokoro:
            ttsVoiceID
        }
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
        // accidentally pointing Suisui at secrets that should stay in Keychain or provider-specific stores.
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

    private func appendCodexLocalIssues(to issues: inout [ValidationIssue]) {
        appendCodexExecutablePathIssue(to: &issues, isRequired: true)
        appendCodexModelIDIssue(to: &issues)
        if !isCodexLocalExecutionApproved || approvedCodexExecutable?.path != codexExecutablePath {
            issues.append(ValidationIssue(
                field: "isCodexLocalExecutionApproved",
                message: "Codex local execution requires approval bound to the selected executable.",
                severity: .error
            ))
        }
    }

    private func appendOptionalCodexLocalIssues(to issues: inout [ValidationIssue]) {
        appendCodexExecutablePathIssue(to: &issues, isRequired: false)
        appendCodexModelIDIssue(to: &issues)
    }

    private func appendCodexExecutablePathIssue(to issues: inout [ValidationIssue], isRequired: Bool) {
        let path = codexExecutablePath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !path.isEmpty else {
            if isRequired {
                issues.append(ValidationIssue(
                    field: "codexExecutablePath",
                    message: "Codex executable path is required.",
                    severity: .error
                ))
            }
            return
        }
        if path.hasSuffix("/auth.json") || path == "auth.json" {
            issues.append(ValidationIssue(
                field: "codexExecutablePath",
                message: "Codex executable path must not point to auth.json.",
                severity: .error
            ))
        } else if !NSString(string: path).isAbsolutePath {
            issues.append(ValidationIssue(
                field: "codexExecutablePath",
                message: "Codex executable path must be absolute.",
                severity: .error
            ))
        }
    }

    private func appendCodexModelIDIssue(to issues: inout [ValidationIssue]) {
        guard let modelID = codexModelID, !modelID.isEmpty,
              modelID.rangeOfCharacter(from: .whitespacesAndNewlines) != nil else { return }
        issues.append(ValidationIssue(
            field: "codexModelID",
            message: "Codex model id cannot contain whitespace.",
            severity: .error
        ))
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
        if ttsVoiceID != Self.normalizedTTSVoiceID(
            ttsVoiceID,
            languageCode: ttsLanguageCode,
            provider: ttsProvider
        ) {
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

    public static let releaseReadyCases: [STTProvider] = [
        .appleSpeechAnalyzer,
        .openAITranscribe,
        .localWhisperCpp
    ]

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
            "Apple Speech"
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

    public static let releaseReadyCases: [TTSProvider] = [.systemSpeech, .localKokoro]

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
            "Uses voices installed in macOS."
        case .localKokoro:
            "Install the Kokoro model and configure the executable in Settings."
        }
    }
}

public enum VoiceRoutingPreference: String, CaseIterable, Codable, Equatable, Sendable {
    case appleFirst
    case localFirst

    public var displayName: String {
        switch self {
        case .appleFirst:
            "Apple first"
        case .localFirst:
            "Local first"
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
    public static let suiteNameEnvironmentKey = "SUISUI_APP_SETTINGS_SUITE_NAME"

    public static func defaultUserDefaults(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> UserDefaults {
        // Runtime smoke tests need a disposable suite so settings assertions never
        // read or mutate the user's real Suisui preferences.
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
    public var readiness: AIProviderReadiness

    public var id: AIProvider { provider }

    public init(
        provider: AIProvider,
        statusLabel: String,
        detailLabel: String,
        nextActionLabel: String,
        isSelected: Bool,
        readiness: AIProviderReadiness = .unknown
    ) {
        self.provider = provider
        self.statusLabel = statusLabel
        self.detailLabel = detailLabel
        self.nextActionLabel = nextActionLabel
        self.isSelected = isSelected
        self.readiness = readiness
    }
}

public enum AIProviderReadiness: Equatable, Sendable {
    case unknown
    case checking
    case ready
    case needsAction(reason: String)
    case unavailable(reason: String)

    public var isReady: Bool {
        self == .ready
    }
}

/// Typed state for an API-key-backed provider, derived from `SecretStore` reads.
/// Display labels and the planning-readiness gate are both produced from this
/// state so localized text changes cannot silently flip planning readiness.
public enum ProviderAPIKeyReadinessState: Equatable, Sendable {
    case missing
    case configured
    case invalid
    case unavailable
}

/// `Sendable` snapshot of every provider key state, populated by a non-MainActor
/// reader so the MainActor can apply the typed state, the display label, and
/// the error message in one transaction once the read completes.
public struct ProviderSecretReadinessSnapshot: Equatable, Sendable {
    public var openAI: ProviderAPIKeyReadinessState
    public var openRouter: ProviderAPIKeyReadinessState
    public var anthropic: ProviderAPIKeyReadinessState
    public var gemini: ProviderAPIKeyReadinessState
    public var groq: ProviderAPIKeyReadinessState

    public init(
        openAI: ProviderAPIKeyReadinessState = .missing,
        openRouter: ProviderAPIKeyReadinessState = .missing,
        anthropic: ProviderAPIKeyReadinessState = .missing,
        gemini: ProviderAPIKeyReadinessState = .missing,
        groq: ProviderAPIKeyReadinessState = .missing
    ) {
        self.openAI = openAI
        self.openRouter = openRouter
        self.anthropic = anthropic
        self.gemini = gemini
        self.groq = groq
    }

    public static let empty = ProviderSecretReadinessSnapshot()

    /// All provider states keyed by provider. Used by the regression tests
    /// to iterate without naming each provider twice.
    public var allProviders: [(provider: AIProvider, state: ProviderAPIKeyReadinessState)] {
        [
            (.openaiResponses, openAI),
            (.openRouterCompatible, openRouter),
            (.claudeMessages, anthropic),
            (.geminiDirect, gemini),
            (.groqOpenAICompatible, groq)
        ]
    }

    public func state(for provider: AIProvider) -> ProviderAPIKeyReadinessState {
        switch provider {
        case .openaiResponses:
            return openAI
        case .openRouterCompatible:
            return openRouter
        case .claudeMessages:
            return anthropic
        case .geminiDirect:
            return gemini
        case .groqOpenAICompatible:
            return groq
        case .codexLocal, .opencodeLocal, .ollamaCompatible, .geminiOpenAICompatible:
            return .missing
        }
    }
}

/// Result of an off-MainActor Keychain read. The snapshot holds the typed
/// state for every provider — including providers whose `SecretStore.read`
/// threw. `failedProviders` lists every provider whose read raised, so the
/// MainActor can surface the matching error message without re-running the
/// read and so callers can distinguish Keychain-unavailable (.unavailable)
/// from key-not-yet-set (.missing).
public struct ProviderSecretReadinessReadResult: Equatable, Sendable {
    public var snapshot: ProviderSecretReadinessSnapshot
    public var failedProviders: Set<AIProvider>

    public init(
        snapshot: ProviderSecretReadinessSnapshot,
        failedProviders: Set<AIProvider> = []
    ) {
        self.snapshot = snapshot
        self.failedProviders = failedProviders
    }

    public var hasReadFailure: Bool { !failedProviders.isEmpty }
}

/// Port for reading the provider secret readiness snapshot off the MainActor.
/// Production uses a `KeychainBackedProviderSecretReadinessReader`; tests
/// substitute a blocking or scripted reader to exercise the async path.
public protocol ProviderSecretReadinessReading: Sendable {
    func readSnapshot() async -> ProviderSecretReadinessReadResult
}

/// Production reader that resolves every provider key by calling
/// `SecretStore.read` and `APIKeyValidator.normalize`. Because both inputs and
/// the snapshot are `Sendable`, the read runs on a detached background task
/// and never blocks the MainActor.
///
/// `try?` is **not** used: a `SecretStore.read` throw (Keychain access denied,
/// entitlement missing, etc.) must surface as `.unavailable`, not as
/// `.missing` from a `nil` value. Every per-provider read uses its own
/// `do/catch` so one failed provider cannot abort the whole snapshot.
public struct KeychainBackedProviderSecretReadinessReader: ProviderSecretReadinessReading, Sendable {
    public let secretStore: any SecretStore

    public init(secretStore: any SecretStore) {
        self.secretStore = secretStore
    }

    public func readSnapshot() async -> ProviderSecretReadinessReadResult {
        var snapshot = ProviderSecretReadinessSnapshot.empty
        var failed: Set<AIProvider> = []

        snapshot.openAI = readState(for: .openaiResponses, key: .openAIAPIKey, into: &failed)
        snapshot.openRouter = readState(for: .openRouterCompatible, key: .openRouterAPIKey, into: &failed)
        snapshot.anthropic = readState(for: .claudeMessages, key: .anthropicAPIKey, into: &failed)
        snapshot.gemini = readState(for: .geminiDirect, key: .geminiAPIKey, into: &failed)
        snapshot.groq = readState(for: .groqOpenAICompatible, key: .groqAPIKey, into: &failed)

        return ProviderSecretReadinessReadResult(snapshot: snapshot, failedProviders: failed)
    }

    /// Reads a single key, classifies the result, and records the provider in
    /// `failed` when the underlying `SecretStore.read` throws. Returning
    /// `.unavailable` here — never `.missing` — is what lets the MainActor
    /// distinguish Keychain failure from key-not-set.
    private func readState(
        for provider: AIProvider,
        key: SecretKey,
        into failed: inout Set<AIProvider>
    ) -> ProviderAPIKeyReadinessState {
        do {
            let value = try secretStore.read(key)
            return AppSettingsViewModel.classifyAPIKeyValue(value)
        } catch {
            failed.insert(provider)
            return .unavailable
        }
    }
}

/// Snapshot of the Ollama-compatible endpoint, derived from the injected health
/// checker. The status is the only source of truth for Ollama planning
/// readiness; display text is derived from it.
public enum OllamaEndpointHealth: Equatable, Sendable {
    case unknown
    case checking
    case ready
    case failure(reason: String)
}

/// Port for probing the local Ollama-compatible endpoint. Production
/// implementations issue an HTTP probe, tests substitute deterministic
/// results so the readiness gate can be exercised without a live server.
public protocol OllamaEndpointHealthChecking: Sendable {
    func currentStatus() async -> OllamaEndpointHealth
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

public enum AppleSpeechAuthorizationStatus: Equatable, Sendable {
    case notDetermined
    case denied
    case restricted
    case authorized
}

public struct AppleSpeechReadinessSnapshot: Equatable, Sendable {
    public var authorization: AppleSpeechAuthorizationStatus
    public var isRecognizerAvailable: Bool
    public var supportsOnDeviceRecognition: Bool

    public init(
        authorization: AppleSpeechAuthorizationStatus,
        isRecognizerAvailable: Bool,
        supportsOnDeviceRecognition: Bool
    ) {
        self.authorization = authorization
        self.isRecognizerAvailable = isRecognizerAvailable
        self.supportsOnDeviceRecognition = supportsOnDeviceRecognition
    }

    public static let permissionNotDetermined = AppleSpeechReadinessSnapshot(
        authorization: .notDetermined,
        isRecognizerAvailable: true,
        supportsOnDeviceRecognition: true
    )
}

public struct SystemSpeechVoiceOption: Identifiable, Equatable, Sendable {
    public var identifier: String
    public var name: String
    public var languageCode: String
    public var qualityLabel: String?

    public var id: String { identifier }

    public init(
        identifier: String,
        name: String,
        languageCode: String,
        qualityLabel: String? = nil
    ) {
        self.identifier = identifier
        self.name = name
        self.languageCode = languageCode
        self.qualityLabel = qualityLabel
    }

    public var displayLabel: String {
        if let qualityLabel, !qualityLabel.isEmpty {
            return "\(name) (\(languageCode), \(qualityLabel))"
        }
        return "\(name) (\(languageCode))"
    }

    public func matches(languageCode requestedLanguageCode: String) -> Bool {
        Self.baseLanguageCode(languageCode) == Self.baseLanguageCode(requestedLanguageCode)
    }

    private static func baseLanguageCode(_ languageCode: String) -> String {
        languageCode
            .replacingOccurrences(of: "_", with: "-")
            .split(separator: "-", maxSplits: 1)
            .first?
            .lowercased() ?? ""
    }
}

public struct SystemSpeechReadinessSnapshot: Equatable, Sendable {
    public var isAvailable: Bool
    public var isInventoryAuthoritative: Bool
    public var isInventoryPending: Bool
    public var voices: [SystemSpeechVoiceOption]

    public init(
        isAvailable: Bool,
        isInventoryAuthoritative: Bool,
        isInventoryPending: Bool = false,
        voices: [SystemSpeechVoiceOption]
    ) {
        self.isAvailable = isAvailable
        self.isInventoryAuthoritative = isInventoryAuthoritative
        self.isInventoryPending = isInventoryPending
        self.voices = voices
    }

    public static let pendingInventory = SystemSpeechReadinessSnapshot(
        isAvailable: false,
        isInventoryAuthoritative: false,
        isInventoryPending: true,
        voices: []
    )

    /// Preserves the public ViewModel initializer contract for non-AppKit
    /// consumers. The macOS composition root replaces this with an authoritative
    /// inventory before exposing System Speech readiness.
    public static let assumedAvailable = SystemSpeechReadinessSnapshot(
        isAvailable: true,
        isInventoryAuthoritative: false,
        voices: []
    )
}

@MainActor
public final class AppSettingsViewModel: ObservableObject {
    @Published public private(set) var settings: AppSettings
    @Published public private(set) var openAIAPIKeyInput: String
    @Published public private(set) var openAIAPIKeyStatusLabel: String
    @Published public private(set) var openAIAPIKeyReadinessState: ProviderAPIKeyReadinessState
    @Published public private(set) var openAIProviderSmokeStatusLabel: String
    @Published public private(set) var anthropicAPIKeyInput: String
    @Published public private(set) var anthropicAPIKeyStatusLabel: String
    @Published public private(set) var anthropicAPIKeyReadinessState: ProviderAPIKeyReadinessState
    @Published public private(set) var geminiAPIKeyInput: String
    @Published public private(set) var geminiAPIKeyStatusLabel: String
    @Published public private(set) var geminiAPIKeyReadinessState: ProviderAPIKeyReadinessState
    @Published public private(set) var geminiProviderSmokeStatusLabel: String
    @Published public private(set) var groqAPIKeyInput: String
    @Published public private(set) var groqAPIKeyStatusLabel: String
    @Published public private(set) var groqAPIKeyReadinessState: ProviderAPIKeyReadinessState
    @Published public private(set) var groqProviderSmokeStatusLabel: String
    @Published public private(set) var openRouterAPIKeyInput: String
    @Published public private(set) var openRouterAPIKeyStatusLabel: String
    @Published public private(set) var openRouterAPIKeyReadinessState: ProviderAPIKeyReadinessState
    @Published public private(set) var keychainSecretKeyInput: String
    @Published public private(set) var keychainSecretValueInput: String
    @Published public private(set) var keychainSecretStatusLabel: String
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var successMessage: String?
    @Published public private(set) var ollamaEndpointHealth: OllamaEndpointHealth
    @Published public private(set) var isRefreshingProviderReadiness: Bool
    @Published private var voiceModelStatusOverrides: [VoiceModelID: VoiceModelInstallStatus]
    @Published private var appleSpeechReadinessSnapshot: AppleSpeechReadinessSnapshot
    @Published private var systemSpeechReadinessSnapshot: SystemSpeechReadinessSnapshot

    private let settingsStore: any AppSettingsStore
    private let secretStore: any SecretStore
    private let voiceModelCatalog: VoiceModelCatalog
    private let voiceModelManager: any VoiceModelManaging
    private let ollamaHealthChecker: any OllamaEndpointHealthChecking
    private let secretReadinessReader: any ProviderSecretReadinessReading
    private let appleSpeechReadinessProvider: @Sendable () -> AppleSpeechReadinessSnapshot
    private let systemSpeechReadinessProvider: @Sendable () -> SystemSpeechReadinessSnapshot
    private var rejectedAIProvider: AIProvider?
    private static let settingsSaveFailureMessage = "App settings could not be saved."
    private static let apiKeySaveFailureMessage = "API key could not be saved to Keychain."
    private static let apiKeyDeleteFailureMessage = "API key could not be removed from Keychain."

    public convenience init(
        settingsStore: any AppSettingsStore,
        secretStore: any SecretStore,
        voiceModelCatalog: VoiceModelCatalog = .phase1Default,
        voiceModelManager: any VoiceModelManaging = VoiceModelManager(),
        ollamaHealthChecker: any OllamaEndpointHealthChecking = UncheckedOllamaEndpointHealthChecker(),
        secretReadinessReader: (any ProviderSecretReadinessReading)? = nil,
        refreshProviderSecretStatusesOnInit: Bool = true
    ) {
        self.init(
            settingsStore: settingsStore,
            secretStore: secretStore,
            voiceModelCatalog: voiceModelCatalog,
            voiceModelManager: voiceModelManager,
            ollamaHealthChecker: ollamaHealthChecker,
            secretReadinessReader: secretReadinessReader,
            appleSpeechReadinessProvider: { .permissionNotDetermined },
            refreshProviderSecretStatusesOnInit: refreshProviderSecretStatusesOnInit
        )
    }

    public convenience init(
        settingsStore: any AppSettingsStore,
        secretStore: any SecretStore,
        voiceModelCatalog: VoiceModelCatalog = .phase1Default,
        voiceModelManager: any VoiceModelManaging = VoiceModelManager(),
        ollamaHealthChecker: any OllamaEndpointHealthChecking = UncheckedOllamaEndpointHealthChecker(),
        secretReadinessReader: (any ProviderSecretReadinessReading)? = nil,
        appleSpeechReadinessProvider: @escaping @Sendable () -> AppleSpeechReadinessSnapshot,
        refreshProviderSecretStatusesOnInit: Bool = true
    ) {
        self.init(
            settingsStore: settingsStore,
            secretStore: secretStore,
            voiceModelCatalog: voiceModelCatalog,
            voiceModelManager: voiceModelManager,
            ollamaHealthChecker: ollamaHealthChecker,
            secretReadinessReader: secretReadinessReader,
            appleSpeechReadinessProvider: appleSpeechReadinessProvider,
            systemSpeechReadinessProvider: { .assumedAvailable },
            systemSpeechInventoryInitiallyPending: false,
            refreshProviderSecretStatusesOnInit: refreshProviderSecretStatusesOnInit
        )
    }

    public init(
        settingsStore: any AppSettingsStore,
        secretStore: any SecretStore,
        voiceModelCatalog: VoiceModelCatalog = .phase1Default,
        voiceModelManager: any VoiceModelManaging = VoiceModelManager(),
        ollamaHealthChecker: any OllamaEndpointHealthChecking = UncheckedOllamaEndpointHealthChecker(),
        secretReadinessReader: (any ProviderSecretReadinessReading)? = nil,
        appleSpeechReadinessProvider: @escaping @Sendable () -> AppleSpeechReadinessSnapshot,
        systemSpeechReadinessProvider: @escaping @Sendable () -> SystemSpeechReadinessSnapshot,
        systemSpeechInventoryInitiallyPending: Bool = true,
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
        self.ollamaHealthChecker = ollamaHealthChecker
        self.secretReadinessReader = secretReadinessReader
            ?? KeychainBackedProviderSecretReadinessReader(secretStore: secretStore)
        self.appleSpeechReadinessProvider = appleSpeechReadinessProvider
        // Framework voice inventories are intentionally not read during
        // `Suisui.init()`. Settings refreshes them on demand so Speech and
        // AVFoundation initialization stay off the launch-critical path.
        self.appleSpeechReadinessSnapshot = .permissionNotDetermined
        self.systemSpeechReadinessProvider = systemSpeechReadinessProvider
        self.systemSpeechReadinessSnapshot = systemSpeechInventoryInitiallyPending
            ? .pendingInventory
            : .assumedAvailable
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
        self.openAIAPIKeyReadinessState = .missing
        self.openAIProviderSmokeStatusLabel = "notConfigured"
        self.anthropicAPIKeyInput = ""
        self.anthropicAPIKeyStatusLabel = "Not configured"
        self.anthropicAPIKeyReadinessState = .missing
        self.geminiAPIKeyInput = ""
        self.geminiAPIKeyStatusLabel = "Not configured"
        self.geminiAPIKeyReadinessState = .missing
        self.geminiProviderSmokeStatusLabel = "notConfigured"
        self.groqAPIKeyInput = ""
        self.groqAPIKeyStatusLabel = "Not configured"
        self.groqAPIKeyReadinessState = .missing
        self.groqProviderSmokeStatusLabel = "notConfigured"
        self.openRouterAPIKeyInput = ""
        self.openRouterAPIKeyStatusLabel = "Not configured"
        self.openRouterAPIKeyReadinessState = .missing
        self.keychainSecretKeyInput = ""
        self.keychainSecretValueInput = ""
        self.keychainSecretStatusLabel = "Enter a secret key"
        self.errorMessage = initialErrorMessage
        self.successMessage = nil
        self.ollamaEndpointHealth = .unknown
        self.isRefreshingProviderReadiness = false
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

    /// Refreshes the Ollama probe off the MainActor and the provider Keychain
    /// reads on a detached background task. Publishes `.checking` state on the
    /// MainActor before any work so the onboarding sheet renders the spinner
    /// instead of a stale readiness state. The detached read returns a
    /// `Sendable` `ProviderSecretReadinessReadResult`; the MainActor applies
    /// the typed states, derived display labels, and error message in one
    /// transaction once the read finishes.
    public func refreshProviderReadiness() async {
        let previousOllama = ollamaEndpointHealth
        ollamaEndpointHealth = .checking
        isRefreshingProviderReadiness = true
        defer {
            if ollamaEndpointHealth == .checking {
                ollamaEndpointHealth = previousOllama
            }
            isRefreshingProviderReadiness = false
        }

        // The Ollama probe is already nonisolated and returns a Sendable enum;
        // awaiting it hands the MainActor off to other work, including the
        // detached Keychain read below.
        async let ollamaStatus: OllamaEndpointHealth = ollamaHealthChecker.currentStatus()
        async let secretResult: ProviderSecretReadinessReadResult = Task.detached(priority: .userInitiated) { [secretReadinessReader] in
            await secretReadinessReader.readSnapshot()
        }.value

        ollamaEndpointHealth = await ollamaStatus
        let resolvedSecret = await secretResult
        apply(secretResult: resolvedSecret)
    }

    /// Apply a `ProviderSecretReadinessReadResult` returned by the async read.
    /// The state is the **only** source of truth for planning readiness; the
    /// display label and smoke label are derived from the state so a copy
    /// change cannot flip the planning gate.
    private func apply(secretResult: ProviderSecretReadinessReadResult) {
        let snapshot = secretResult.snapshot
        openAIAPIKeyReadinessState = snapshot.openAI
        openAIAPIKeyStatusLabel = Self.statusLabel(for: snapshot.openAI)
        openAIProviderSmokeStatusLabel = Self.providerSmokeStatusLabel(for: snapshot.openAI)
        openRouterAPIKeyReadinessState = snapshot.openRouter
        openRouterAPIKeyStatusLabel = Self.statusLabel(for: snapshot.openRouter)
        anthropicAPIKeyReadinessState = snapshot.anthropic
        anthropicAPIKeyStatusLabel = Self.statusLabel(for: snapshot.anthropic)
        geminiAPIKeyReadinessState = snapshot.gemini
        geminiAPIKeyStatusLabel = Self.statusLabel(for: snapshot.gemini)
        geminiProviderSmokeStatusLabel = Self.providerSmokeStatusLabel(for: snapshot.gemini)
        groqAPIKeyReadinessState = snapshot.groq
        groqAPIKeyStatusLabel = Self.statusLabel(for: snapshot.groq)
        groqProviderSmokeStatusLabel = Self.providerSmokeStatusLabel(for: snapshot.groq)

        if secretResult.hasReadFailure {
            errorMessage = "API key status could not be read from Keychain."
            successMessage = nil
        }
    }

    /// Read the readiness state for the currently selected provider only. Used
    /// by the onboarding path to keep the wait short when only one provider
    /// is needed to decide whether to advance past the finish step.
    public func refreshSelectedProviderReadiness() async {
        isRefreshingProviderReadiness = true
        defer { isRefreshingProviderReadiness = false }
        let selected = settings.aiProvider
        guard let key = Self.secretKey(for: selected) else {
            // Non-API-key providers (OpenCode/Ollama) have no Keychain read.
            return
        }
        let state = await Task.detached(priority: .userInitiated) { [secretStore = self.secretStore, key] in
            do {
                return AppSettingsViewModel.classifyAPIKeyValue(try secretStore.read(key))
            } catch {
                return ProviderAPIKeyReadinessState.unavailable
            }
        }.value
        applySelectedProviderState(state, for: selected)
    }

    private func applySelectedProviderState(_ state: ProviderAPIKeyReadinessState, for provider: AIProvider) {
        switch provider {
        case .openaiResponses:
            openAIAPIKeyReadinessState = state
            openAIAPIKeyStatusLabel = Self.statusLabel(for: state)
            openAIProviderSmokeStatusLabel = Self.providerSmokeStatusLabel(for: state)
        case .openRouterCompatible:
            openRouterAPIKeyReadinessState = state
            openRouterAPIKeyStatusLabel = Self.statusLabel(for: state)
        case .claudeMessages:
            anthropicAPIKeyReadinessState = state
            anthropicAPIKeyStatusLabel = Self.statusLabel(for: state)
        case .geminiDirect:
            geminiAPIKeyReadinessState = state
            geminiAPIKeyStatusLabel = Self.statusLabel(for: state)
            geminiProviderSmokeStatusLabel = Self.providerSmokeStatusLabel(for: state)
        case .groqOpenAICompatible:
            groqAPIKeyReadinessState = state
            groqAPIKeyStatusLabel = Self.statusLabel(for: state)
            groqProviderSmokeStatusLabel = Self.providerSmokeStatusLabel(for: state)
        case .codexLocal, .opencodeLocal, .ollamaCompatible, .geminiOpenAICompatible:
            return
        }
    }

    nonisolated static func secretKey(for provider: AIProvider) -> SecretKey? {
        switch provider {
        case .openaiResponses:
            return .openAIAPIKey
        case .openRouterCompatible:
            return .openRouterAPIKey
        case .claudeMessages:
            return .anthropicAPIKey
        case .geminiDirect:
            return .geminiAPIKey
        case .groqOpenAICompatible:
            return .groqAPIKey
        case .codexLocal, .opencodeLocal, .ollamaCompatible, .geminiOpenAICompatible:
            return nil
        }
    }

    /// Test-only accessor that maps a SecretKey back to the typed readiness
    /// state for parity assertions between the sync and async refresh paths.
    /// Exposed as `internal` so the regression tests can verify the async
    /// reader no longer collapses a throwing Keychain into `.missing`.
    func readinessStateForAPIKeyReadinessTest(key: SecretKey) -> ProviderAPIKeyReadinessState {
        // `SecretKey` is an arbitrary-value struct, not an enum, so a
        // `default` clause is required to cover non-provider raw values.
        switch key {
        case .openAIAPIKey:
            return openAIAPIKeyReadinessState
        case .openRouterAPIKey:
            return openRouterAPIKeyReadinessState
        case .anthropicAPIKey:
            return anthropicAPIKeyReadinessState
        case .geminiAPIKey:
            return geminiAPIKeyReadinessState
        case .groqAPIKey:
            return groqAPIKeyReadinessState
        default:
            return .missing
        }
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

    public var selectableSystemSpeechVoices: [SystemSpeechVoiceOption] {
        systemSpeechReadinessSnapshot.voices
            .filter { $0.matches(languageCode: settings.ttsLanguageCode) }
            .sorted {
                if $0.name == $1.name {
                    return $0.identifier < $1.identifier
                }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
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

    public var selectedSTTProviderReadinessRow: STTProviderReadinessRow {
        switch settings.sttProvider {
        case .appleSpeechAnalyzer:
            return makeAppleSpeechReadinessRow()
        case .openAITranscribe:
            let isReady = openAIAPIKeyReadinessState == .configured
            return STTProviderReadinessRow(
                provider: .openAITranscribe,
                statusLabel: isReady ? "Ready" : Self.statusLabel(for: openAIAPIKeyReadinessState),
                detailLabel: isReady
                    ? "Uses the OpenAI transcription API."
                    : "Save a valid OpenAI API key in Keychain before recording.",
                nextActionLabel: isReady ? "Record a voice command" : "Configure OpenAI API key",
                isReady: isReady,
                isSelected: true
            )
        case .localWhisperCpp:
            return makeLocalSTTProviderReadinessRow()
        case .localWhisperKit:
            return STTProviderReadinessRow(
                provider: .localWhisperKit,
                statusLabel: "Unsupported",
                detailLabel: "WhisperKit is not available in this release.",
                nextActionLabel: "Select another provider",
                isReady: false,
                isSelected: true
            )
        }
    }

    private func makeAppleSpeechReadinessRow() -> STTProviderReadinessRow {
        let snapshot = appleSpeechReadinessSnapshot
        let statusLabel: String
        let detailLabel: String
        let nextActionLabel: String
        let isReady: Bool

        switch snapshot.authorization {
        case .notDetermined:
            statusLabel = "Permission required"
            detailLabel = "Allow Speech Recognition when recording the first voice command."
            nextActionLabel = "Record to request permission"
            isReady = false
        case .denied:
            statusLabel = "Permission denied"
            detailLabel = "Speech Recognition access is disabled for Suisui."
            nextActionLabel = "Open System Settings"
            isReady = false
        case .restricted:
            statusLabel = "Restricted"
            detailLabel = "Speech Recognition is blocked by a device or account restriction."
            nextActionLabel = "Select another provider"
            isReady = false
        case .authorized where !snapshot.supportsOnDeviceRecognition:
            statusLabel = "Unsupported"
            detailLabel = "On-device Apple Speech is unavailable for the current language."
            nextActionLabel = "Select another provider"
            isReady = false
        case .authorized where !snapshot.isRecognizerAvailable:
            statusLabel = "Unavailable"
            detailLabel = "Apple Speech is temporarily unavailable for the current language."
            nextActionLabel = "Try again later"
            isReady = false
        case .authorized:
            statusLabel = "Ready"
            detailLabel = "Uses on-device Apple Speech without an API key or model download."
            nextActionLabel = "Record a voice command"
            isReady = true
        }

        return STTProviderReadinessRow(
            provider: .appleSpeechAnalyzer,
            statusLabel: statusLabel,
            detailLabel: detailLabel,
            nextActionLabel: nextActionLabel,
            isReady: isReady,
            isSelected: true
        )
    }

    public func refreshAppleSpeechReadiness() {
        appleSpeechReadinessSnapshot = appleSpeechReadinessProvider()
    }

    public func refreshSystemSpeechReadiness() {
        systemSpeechReadinessSnapshot = systemSpeechReadinessProvider()
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
            isSelected: settings.aiProvider == provider,
            readiness: providerReadiness(for: provider)
        )
    }

    public func onboardingReadinessSnapshot(
        permissionSnapshot: PermissionSnapshot
    ) -> OnboardingReadinessSnapshot {
        OnboardingReadinessSnapshot.make(
            selectedProvider: settings.aiProvider,
            providerReadiness: providerReadiness(for: settings.aiProvider),
            permissions: permissionSnapshot
        )
    }

    private func makeTTSProviderReadinessRow(for provider: TTSProvider) -> TTSProviderReadinessRow {
        if provider == .systemSpeech {
            let snapshot = systemSpeechReadinessSnapshot
            if snapshot.isInventoryPending {
                return TTSProviderReadinessRow(
                    provider: provider,
                    statusLabel: "Checking",
                    detailLabel: "Loading installed macOS voices.",
                    nextActionLabel: "Wait for voice check",
                    isReady: false,
                    isSelected: settings.ttsProvider == provider
                )
            }
            guard snapshot.isInventoryAuthoritative else {
                return TTSProviderReadinessRow(
                    provider: provider,
                    statusLabel: "Ready",
                    detailLabel: "Uses an installed macOS voice without an API key or model download.",
                    nextActionLabel: "Test play",
                    isReady: true,
                    isSelected: settings.ttsProvider == provider
                )
            }
            guard snapshot.isAvailable else {
                return TTSProviderReadinessRow(
                    provider: provider,
                    statusLabel: "Unavailable",
                    detailLabel: "System Speech is unavailable on this Mac.",
                    nextActionLabel: "Select Local Kokoro",
                    isReady: false,
                    isSelected: settings.ttsProvider == provider
                )
            }
            guard !selectableSystemSpeechVoices.isEmpty else {
                return TTSProviderReadinessRow(
                    provider: provider,
                    statusLabel: "Voice unavailable",
                    detailLabel: "No installed macOS voice matches the selected language.",
                    nextActionLabel: "Install a matching macOS voice",
                    isReady: false,
                    isSelected: settings.ttsProvider == provider
                )
            }
            if let selectedVoiceID = settings.systemSpeechVoiceID,
               !selectableSystemSpeechVoices.contains(where: { $0.identifier == selectedVoiceID })
            {
                return TTSProviderReadinessRow(
                    provider: provider,
                    statusLabel: "Voice unavailable",
                    detailLabel: "The selected macOS voice is missing or does not match the selected language.",
                    nextActionLabel: "Select an installed voice",
                    isReady: false,
                    isSelected: settings.ttsProvider == provider
                )
            }
            return TTSProviderReadinessRow(
                provider: provider,
                statusLabel: "Ready",
                detailLabel: "Uses an installed macOS voice without an API key or model download.",
                nextActionLabel: "Test play",
                isReady: true,
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
                statusLabel: ttsModelStatusLabel(for: status),
                detailLabel: "\(model.displayName) - \(model.licenseName) - \(model.sourceURL.host ?? "unknown source")",
                nextActionLabel: ttsModelNextActionLabel(for: status),
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

    private func ttsModelStatusLabel(for status: VoiceModelInstallStatus) -> String {
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

    private func ttsModelNextActionLabel(for status: VoiceModelInstallStatus) -> String {
        switch status {
        case .downloading:
            "Wait for download"
        case .failed, .corrupted:
            "Retry Kokoro model"
        case .notInstalled, .installed:
            "Download Kokoro model"
        }
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

    public func setNotificationQuietHoursEnabled(_ isEnabled: Bool) {
        settings.notificationPreferences.quietHours.enabled = isEnabled
        clearMessages()
    }

    public func setNotificationQuietHoursStartMinuteOfDay(_ minuteOfDay: Int) {
        settings.notificationPreferences.quietHours.startMinuteOfDay = minuteOfDay
        settings.notificationPreferences.quietHours = settings.notificationPreferences.quietHours.normalized
        clearMessages()
    }

    public func setNotificationQuietHoursEndMinuteOfDay(_ minuteOfDay: Int) {
        settings.notificationPreferences.quietHours.endMinuteOfDay = minuteOfDay
        settings.notificationPreferences.quietHours = settings.notificationPreferences.quietHours.normalized
        clearMessages()
    }

    public func setDeadlineReminderLeadTime(_ leadTime: DeadlineReminderLeadTime) {
        settings.notificationPreferences.deadlineReminderLeadTime = leadTime
        clearMessages()
    }

    public func setRescheduleAvoidsWeekends(_ avoidsWeekends: Bool) {
        settings.notificationPreferences.avoidsWeekends = avoidsWeekends
        clearMessages()
    }

    public func setDeveloperModeEnabled(_ isEnabled: Bool) {
        if !isEnabled,
           settings.approvedCodexExecutable?.trustPolicy == .developerUnsignedAllowed {
            let previousSettings = settings
            settings.isDeveloperModeEnabled = false
            settings.isCodexLocalExecutionApproved = false
            settings.approvedCodexExecutable = nil
            do {
                // Developer Mode is part of the unsigned-executable trust
                // boundary, so disabling it must revoke persisted approval
                // before another window can launch the old executable.
                try settingsStore.save(settings)
                CodexExecutionApprovalChanges.invalidate()
            } catch {
                settings = previousSettings
                errorMessage = Self.settingsSaveFailureMessage
                successMessage = nil
                return
            }
            clearMessages()
            return
        }
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

        let previousProvider = settings.aiProvider
        settings.aiProvider = provider
        if provider == .opencodeLocal, settings.openCodeModelID == nil {
            settings.openCodeModelID = LLMProviderCatalog.entry(for: .opencodeLocal).defaultModelID
        }
        if previousProvider != provider,
           previousProvider == .codexLocal || provider == .codexLocal {
            CodexExecutionApprovalChanges.invalidate()
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
        if provider == .appleSpeechAnalyzer {
            refreshAppleSpeechReadiness()
        }
        clearMessages()
    }

    public func setSTTRoutingPreference(_ preference: VoiceRoutingPreference) {
        settings.sttRoutingPreference = preference
        clearMessages()
    }

    public func setTTSRoutingPreference(_ preference: VoiceRoutingPreference) {
        settings.ttsRoutingPreference = preference
        clearMessages()
    }

    public func setTTSProvider(_ provider: TTSProvider) {
        guard provider.isReleaseReady else {
            settings.ttsProvider = .localKokoro
            clearMessages()
            return
        }
        settings.ttsProvider = provider
        if provider == .systemSpeech {
            refreshSystemSpeechReadiness()
        }
        clearMessages()
    }

    public func setDefaultWorkspacePath(_ path: String) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.defaultWorkspacePath = trimmed.isEmpty ? nil : trimmed
        clearMessages()
    }

    public func setProfileDisplayName(_ name: String) {
        // Keep the editor draft verbatim so typing a space at the end does not
        // move the cursor or discard input before the user chooses Save.
        settings.profileDisplayName = name
        clearMessages()
    }

    public func setDailyWorkCapacityMinutes(_ minutes: Int) {
        settings.dailyWorkCapacityMinutes = minutes
        clearMessages()
    }

    /// Applies the onboarding draft only after the person continues, so a
    /// cancelled sheet cannot overwrite an existing profile or capacity.
    @discardableResult
    public func saveOnboardingTodayPreferences(_ preferences: OnboardingTodayPreferences) -> Bool {
        settings = preferences.applying(to: settings)
        saveSettings()
        return errorMessage == nil
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
            voiceID: settings.selectedTTSVoiceID
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
        // macOS voice identifiers include a concrete locale. Clearing the
        // selection prevents a language change from speaking with a stale
        // voice; System Speech will choose the installed default for the new
        // language until the user selects another voice.
        settings.systemSpeechVoiceID = nil
        clearMessages()
    }

    public func setTTSVoiceID(_ voiceID: String) {
        switch settings.ttsProvider {
        case .systemSpeech:
            let normalized = voiceID.trimmingCharacters(in: .whitespacesAndNewlines)
            settings.systemSpeechVoiceID = normalized.isEmpty ? nil : normalized
        case .localKokoro:
            settings.ttsVoiceID = AppSettings.normalizedTTSVoiceID(
                voiceID,
                languageCode: settings.ttsLanguageCode
            )
        }
        clearMessages()
    }

    public func setSystemSpeechVoiceID(_ voiceID: String?) {
        let normalized = voiceID?.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.systemSpeechVoiceID = normalized?.isEmpty == false ? normalized : nil
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

    public func setCodexExecutablePath(_ path: String) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextPath = trimmed.isEmpty ? nil : trimmed
        if settings.codexExecutablePath != nextPath {
            let previousSettings = settings
            settings.isCodexLocalExecutionApproved = false
            settings.approvedCodexExecutable = nil
            settings.codexExecutablePath = nextPath
            do {
                // Persist security-sensitive revocation immediately so an
                // already-open Voice window cannot reload stale approval.
                try settingsStore.save(settings)
                CodexExecutionApprovalChanges.invalidate()
            } catch {
                settings = previousSettings
                errorMessage = Self.settingsSaveFailureMessage
                successMessage = nil
                return
            }
        }
        clearMessages()
    }

    public func setCodexModelID(_ modelID: String) {
        let trimmed = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.codexModelID = trimmed.isEmpty ? nil : trimmed
        clearMessages()
    }

    public func setCodexLocalExecutionApproved(_ isApproved: Bool) {
        guard isApproved else {
            do {
                try disconnectCodexAndSave()
            } catch {
                errorMessage = Self.settingsSaveFailureMessage
                successMessage = nil
            }
            return
        }
        do {
            let path = settings.codexExecutablePath ?? ""
            settings.approvedCodexExecutable = try CodexAppServerRuntimeConfiguration.approve(
                executablePath: path,
                trustPolicy: settings.isDeveloperModeEnabled
                    ? .developerUnsignedAllowed
                    : .signedProduction
            )
            settings.isCodexLocalExecutionApproved = true
            CodexExecutionApprovalChanges.invalidate()
            clearMessages()
        } catch {
            settings.isCodexLocalExecutionApproved = false
            settings.approvedCodexExecutable = nil
            if let runtimeError = error as? CodexAppServerRuntimeConfigurationError,
               runtimeError == .validCodeSignatureRequired ||
               runtimeError == .unexpectedCodeSignature {
                errorMessage = "Normal mode requires the signed OpenAI Codex executable. Enable Developer Mode only to approve an unsigned or custom build."
            } else {
                errorMessage = "Select a valid executable Codex CLI file before approving local execution."
            }
            successMessage = nil
        }
    }

    public func disconnectCodexAndSave() throws {
        let previousSettings = settings
        settings.isCodexLocalExecutionApproved = false
        settings.approvedCodexExecutable = nil
        do {
            try settingsStore.save(settings)
        } catch {
            settings = previousSettings
            errorMessage = Self.settingsSaveFailureMessage
            successMessage = nil
            throw error
        }
        CodexExecutionApprovalChanges.invalidate()
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

        settings.profileDisplayName = settings.normalizedForRuntime.profileDisplayName
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
        let state = readAPIKeyReadinessStateSync(for: .openAIAPIKey)
        openAIAPIKeyReadinessState = state
        openAIAPIKeyStatusLabel = Self.statusLabel(for: state)
        openAIProviderSmokeStatusLabel = Self.providerSmokeStatusLabel(for: state)
        return finishApply(of: state, provider: .openaiResponses)
    }

    @discardableResult
    public func refreshOpenRouterAPIKeyStatus() -> Bool {
        let state = readAPIKeyReadinessStateSync(for: .openRouterAPIKey)
        openRouterAPIKeyReadinessState = state
        openRouterAPIKeyStatusLabel = Self.statusLabel(for: state)
        return finishApply(of: state, provider: .openRouterCompatible)
    }

    @discardableResult
    public func refreshAnthropicAPIKeyStatus() -> Bool {
        let state = readAPIKeyReadinessStateSync(for: .anthropicAPIKey)
        anthropicAPIKeyReadinessState = state
        anthropicAPIKeyStatusLabel = Self.statusLabel(for: state)
        return finishApply(of: state, provider: .claudeMessages)
    }

    @discardableResult
    public func refreshGeminiAPIKeyStatus() -> Bool {
        let state = readAPIKeyReadinessStateSync(for: .geminiAPIKey)
        geminiAPIKeyReadinessState = state
        geminiAPIKeyStatusLabel = Self.statusLabel(for: state)
        geminiProviderSmokeStatusLabel = Self.providerSmokeStatusLabel(for: state)
        return finishApply(of: state, provider: .geminiDirect)
    }

    @discardableResult
    public func refreshGroqAPIKeyStatus() -> Bool {
        let state = readAPIKeyReadinessStateSync(for: .groqAPIKey)
        groqAPIKeyReadinessState = state
        groqAPIKeyStatusLabel = Self.statusLabel(for: state)
        groqProviderSmokeStatusLabel = Self.providerSmokeStatusLabel(for: state)
        return finishApply(of: state, provider: .groqOpenAICompatible)
    }

    /// Surface a per-provider error/success message based on the typed state.
    /// The state itself is already the planning source of truth, so this
    /// helper only updates the user-facing banners.
    private func finishApply(of state: ProviderAPIKeyReadinessState, provider: AIProvider) -> Bool {
        switch state {
        case .unavailable:
            errorMessage = "API key status could not be read from Keychain."
            successMessage = nil
            return false
        case .invalid:
            reportInvalidStoredAPIKey()
            return false
        case .configured, .missing:
            return true
        }
    }

    /// Reads the SecretStore directly and returns the typed readiness state.
    /// This is the **only** path that produces a `ProviderAPIKeyReadinessState`
    /// value; display labels and `AIProviderReadiness` are derived from this
    /// state so copy changes can never flip the planning gate.
    ///
    /// The read is synchronous for legacy callers (Settings view model init)
    /// because `SecretStore.read` is sync. The onboarding path uses
    /// `readProviderSecretReadiness` to perform the same reads off the
    /// MainActor and apply the typed snapshot in one transaction.
    private func readAPIKeyReadinessStateSync(for key: SecretKey) -> ProviderAPIKeyReadinessState {
        do {
            let value = try secretStore.read(key)
            return Self.classifyAPIKeyValue(value)
        } catch {
            return .unavailable
        }
    }

    nonisolated static func classifyAPIKeyValue(_ value: String?) -> ProviderAPIKeyReadinessState {
        do {
            _ = try APIKeyValidator.normalize(value)
            return .configured
        } catch APIKeyValidationError.empty {
            return .missing
        } catch APIKeyValidationError.containsWhitespace {
            return .invalid
        } catch {
            return .unavailable
        }
    }

    nonisolated static func statusLabel(for state: ProviderAPIKeyReadinessState) -> String {
        switch state {
        case .configured:
            return "Configured"
        case .missing:
            return "Not configured"
        case .invalid:
            return "Invalid"
        case .unavailable:
            return "Unavailable"
        }
    }

    nonisolated static func providerSmokeStatusLabel(for state: ProviderAPIKeyReadinessState) -> String {
        switch state {
        case .configured:
            return "readyForManualSmoke"
        case .invalid:
            return "invalidConfiguration"
        case .unavailable:
            return "unavailable"
        case .missing:
            return "notConfigured"
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
            ? "Suisuiのローカル音声テストです。"
            : "Suisui local voice test is ready."
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
        case .codexLocal:
            if settings.codexExecutablePath == nil { return "Setup required" }
            return settings.isCodexLocalExecutionApproved ? "Ready to connect" : "Approval required"
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
            switch ollamaEndpointHealth {
            case .ready:
                return "Local server ready"
            case .checking:
                return "Checking server"
            case .unknown:
                return "Local"
            case let .failure(reason):
                return reason
            }
        }
    }

    private func providerReadiness(for provider: AIProvider) -> AIProviderReadiness {
        guard LLMProviderCatalog.isAvailableInCurrentBuild(provider) else {
            return .unavailable(reason: LLMProviderCatalog.entry(for: provider).unavailableReason ?? "Not available in this build.")
        }

        switch provider {
        case .codexLocal:
            if settings.codexExecutablePath == nil {
                return .needsAction(reason: "Set the absolute Codex executable path.")
            }
            if !settings.isCodexLocalExecutionApproved {
                return .needsAction(reason: "Review the local process boundary and approve execution.")
            }
            return .ready
        case .opencodeLocal:
            if settings.openCodeExecutablePath == nil {
                return .needsAction(reason: "Set the OpenCode executable path.")
            }
            if settings.openCodeWorkspacePath == nil {
                return .needsAction(reason: "Set the workspace path.")
            }
            if let modelID = settings.openCodeModelID?.trimmingCharacters(in: .whitespacesAndNewlines),
               !modelID.isEmpty {
                // Approval is the last required gate; model id is set above.
                if !settings.isOpenCodeLocalExecutionApproved {
                    return .needsAction(reason: "Review the local command and approve execution.")
                }
                return .ready
            }
            return .needsAction(reason: "Set the OpenCode model id.")
        case .ollamaCompatible:
            return ollamaReadiness()
        case .geminiOpenAICompatible:
            return .unavailable(reason: "Select an available provider.")
        case .openaiResponses:
            return apiKeyReadiness(for: openAIAPIKeyReadinessState)
        case .claudeMessages:
            return apiKeyReadiness(for: anthropicAPIKeyReadinessState)
        case .geminiDirect:
            return apiKeyReadiness(for: geminiAPIKeyReadinessState)
        case .groqOpenAICompatible:
            return apiKeyReadiness(for: groqAPIKeyReadinessState)
        case .openRouterCompatible:
            return apiKeyReadiness(for: openRouterAPIKeyReadinessState)
        }
    }

    private func apiKeyReadiness(for state: ProviderAPIKeyReadinessState) -> AIProviderReadiness {
        switch state {
        case .configured:
            return .ready
        case .invalid:
            return .needsAction(reason: "Re-enter the provider API key in Keychain.")
        case .unavailable:
            return .unavailable(reason: "Keychain access is unavailable.")
        case .missing:
            return .needsAction(reason: "Save the provider API key in Keychain.")
        }
    }

    private func ollamaReadiness() -> AIProviderReadiness {
        switch ollamaEndpointHealth {
        case .ready:
            return .ready
        case .checking:
            return .checking
        case .unknown:
            return .needsAction(reason: "Start the local Ollama-compatible server before planning.")
        case let .failure(reason):
            return .needsAction(reason: reason)
        }
    }

    private func providerReadinessDetailLabel(for provider: AIProvider) -> String {
        guard LLMProviderCatalog.isAvailableInCurrentBuild(provider) else {
            return LLMProviderCatalog.entry(for: provider).unavailableReason ?? "Not available in this build."
        }

        switch provider {
        case .codexLocal:
            return "Uses the current Mac user's Codex-managed ChatGPT login and subscription; Suisui never stores its tokens."
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
        case .codexLocal:
            if settings.codexExecutablePath == nil {
                return "Set the absolute Codex executable path."
            }
            if !settings.isCodexLocalExecutionApproved {
                return "Review the tool-free local process boundary and approve execution."
            }
            return "Generate a reviewed plan; sign in through Codex if prompted."
        case .opencodeLocal:
            if settings.openCodeExecutablePath == nil {
                return "Set the OpenCode executable path."
            }
            if settings.openCodeWorkspacePath == nil {
                return "Set the workspace path."
            }
            if let modelID = settings.openCodeModelID?.trimmingCharacters(in: .whitespacesAndNewlines),
               modelID.isEmpty {
                return "Set the OpenCode model id."
            }
            if !settings.isOpenCodeLocalExecutionApproved {
                return "Review the local command and approve execution."
            }
            return "Generate a reviewed plan when you are ready."
        case .ollamaCompatible:
            switch ollamaEndpointHealth {
            case .ready:
                return "Generate a reviewed plan or run a manual smoke check."
            case .checking:
                return "Checking the local Ollama-compatible server."
            case .unknown:
                return "Start the local Ollama-compatible server before planning."
            case let .failure(reason):
                return reason
            }
        case .geminiOpenAICompatible:
            return "Select an available provider."
        default:
            switch apiKeyReadinessState(for: provider) {
            case .configured:
                return "Generate a reviewed plan or run a manual smoke check."
            case .invalid:
                return "Re-enter the provider API key in Keychain."
            case .unavailable:
                return "Check Keychain access and reopen Settings."
            case .missing:
                return "Save the provider API key in Keychain."
            }
        }
    }

    private func apiKeyReadinessState(for provider: AIProvider) -> ProviderAPIKeyReadinessState {
        switch provider {
        case .openaiResponses:
            return openAIAPIKeyReadinessState
        case .claudeMessages:
            return anthropicAPIKeyReadinessState
        case .geminiDirect:
            return geminiAPIKeyReadinessState
        case .groqOpenAICompatible:
            return groqAPIKeyReadinessState
        case .openRouterCompatible:
            return openRouterAPIKeyReadinessState
        case .codexLocal, .opencodeLocal, .ollamaCompatible, .geminiOpenAICompatible:
            return .missing
        }
    }

    private var openCodeReadinessStatusLabel: String {
        if settings.openCodeExecutablePath == nil || settings.openCodeWorkspacePath == nil {
            return "Setup required"
        }
        if let modelID = settings.openCodeModelID?.trimmingCharacters(in: .whitespacesAndNewlines),
           modelID.isEmpty {
            return "Model id required"
        }
        if settings.openCodeModelID == nil {
            return "Model id required"
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
        if settings.openCodeModelID == nil
            || settings.openCodeModelID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            return "Model id is required."
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

/// Default `OllamaEndpointHealthChecking` that reports `.unknown` until the
/// app or tests inject a real probe. Keeping the default explicit prevents the
/// onboarding sheet from accidentally treating an unprobed endpoint as ready.
public struct UncheckedOllamaEndpointHealthChecker: OllamaEndpointHealthChecking, Sendable {
    public init() {}

    public func currentStatus() async -> OllamaEndpointHealth {
        .unknown
    }
}

/// Production `OllamaEndpointHealthChecking` that issues a HEAD-style probe to
/// the Ollama root URL. The probe times out quickly so onboarding readiness
/// never blocks the MainActor behind a slow local server.
public struct URLSessionOllamaEndpointHealthChecker: OllamaEndpointHealthChecking, Sendable {
    public let baseURL: URL?
    public let session: any OllamaHealthProbing
    public let timeout: TimeInterval

    public init(
        baseURL: URL? = LLMProviderCatalog.entry(for: .ollamaCompatible).baseURL,
        session: any OllamaHealthProbing = URLSessionOllamaHealthProbe(),
        timeout: TimeInterval = 1.5
    ) {
        self.baseURL = baseURL
        self.session = session
        self.timeout = timeout
    }

    public func currentStatus() async -> OllamaEndpointHealth {
        guard let baseURL else {
            return .unknown
        }
        do {
            let success = try await session.probe(
                url: baseURL,
                timeout: timeout
            )
            return success ? .ready : .failure(reason: "Local Ollama-compatible server did not respond.")
        } catch {
            return .failure(reason: "Local Ollama-compatible server is unreachable.")
        }
    }
}

/// Sendable HTTP probe abstraction so tests can drive the health checker
/// without standing up a real local server.
public protocol OllamaHealthProbing: Sendable {
    func probe(url: URL, timeout: TimeInterval) async throws -> Bool
}

public struct URLSessionOllamaHealthProbe: OllamaHealthProbing, Sendable {
    public init() {}

    public func probe(url: URL, timeout: TimeInterval) async throws -> Bool {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            return false
        }
        return (200..<500).contains(http.statusCode)
    }
}
