import Foundation

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
    public var weatherLocationPreference: WeatherLocationPreference
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
        case weatherLocationPreference
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
        weatherLocationPreference: WeatherLocationPreference = .unset,
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
        self.weatherLocationPreference = weatherLocationPreference.normalized
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

    /// Source-compatible initializer retained for clients built against the
    /// pre-Today settings surface. New Today preferences intentionally use
    /// their canonical defaults when callers do not provide them.
    @_disfavoredOverload
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
        isLowLatencyVoiceAgentModeEnabled: Bool = false,
        isLowLatencyVoiceAgentAlwaysOnRecordingEnabled: Bool = false,
        isLowLatencyVoiceAgentCloudFallbackEnabled: Bool = false,
        isLowLatencyVoiceAgentCloudFallbackCostVisible: Bool = false,
        taskAutoExecution: TaskAutoExecutionSettings = .default,
        managedAIBilling: ManagedAIBillingSettings = .default
    ) {
        self.init(
            aiProvider: aiProvider,
            sttProvider: sttProvider,
            ttsProvider: ttsProvider,
            sttRoutingPreference: sttRoutingPreference,
            ttsRoutingPreference: ttsRoutingPreference,
            notificationsEnabled: notificationsEnabled,
            notificationPreferences: notificationPreferences,
            isDeveloperModeEnabled: isDeveloperModeEnabled,
            defaultWorkspacePath: defaultWorkspacePath,
            profileDisplayName: nil,
            dailyWorkCapacityMinutes: 480,
            weatherLocationPreference: .unset,
            timeZoneIdentifier: timeZoneIdentifier,
            googleCalendarID: googleCalendarID,
            geminiModelID: geminiModelID,
            groqBaseURLString: groqBaseURLString,
            whisperCppExecutablePath: whisperCppExecutablePath,
            kokoroExecutablePath: kokoroExecutablePath,
            ttsLanguageCode: ttsLanguageCode,
            ttsVoiceID: ttsVoiceID,
            openCodeExecutablePath: openCodeExecutablePath,
            openCodeWorkspacePath: openCodeWorkspacePath,
            openCodeModelID: openCodeModelID,
            isOpenCodeLocalExecutionApproved: isOpenCodeLocalExecutionApproved,
            codexExecutablePath: codexExecutablePath,
            codexModelID: codexModelID,
            isCodexLocalExecutionApproved: isCodexLocalExecutionApproved,
            approvedCodexExecutable: approvedCodexExecutable,
            isLowLatencyVoiceAgentModeEnabled: isLowLatencyVoiceAgentModeEnabled,
            isLowLatencyVoiceAgentAlwaysOnRecordingEnabled: isLowLatencyVoiceAgentAlwaysOnRecordingEnabled,
            isLowLatencyVoiceAgentCloudFallbackEnabled: isLowLatencyVoiceAgentCloudFallbackEnabled,
            isLowLatencyVoiceAgentCloudFallbackCostVisible: isLowLatencyVoiceAgentCloudFallbackCostVisible,
            taskAutoExecution: taskAutoExecution,
            managedAIBilling: managedAIBilling
        )
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
        self.weatherLocationPreference = (try? container.decodeIfPresent(WeatherLocationPreference.self, forKey: .weatherLocationPreference)) ?? .unset
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
        try container.encode(weatherLocationPreference.normalized, forKey: .weatherLocationPreference)
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
        copy.weatherLocationPreference = copy.weatherLocationPreference.normalized
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
        // Kokoro reserves both `a` (American) and `b` (British) for English voices.
        let expectedPrefixes = normalizedTTSLanguageCode(languageCode) == "ja" ? ["j"] : ["a", "b"]
        return expectedPrefixes.contains { normalized.hasPrefix($0) }
            ? normalized
            : defaultTTSVoiceID(for: languageCode)
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
