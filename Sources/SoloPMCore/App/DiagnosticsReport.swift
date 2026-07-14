import Foundation

/// Inputs for the diagnostics report. Every value is injected as an already
/// non-sensitive scalar so the builder physically cannot reach API keys,
/// task/knowledge/plan content, voice transcripts, or audit log rows.
public struct DiagnosticsReportInput: Equatable, Sendable {
    public var appVersion: String
    public var appBuild: String
    public var macOSVersion: String
    /// Kind of the selected AI provider (for example "OpenAI Responses").
    /// Never an API key, base URL credential, or model prompt.
    public var aiProviderKind: String
    public var notificationsEnabled: Bool
    public var quietHoursSummary: String
    public var deadlineReminderLeadTimeLabel: String
    public var openTaskCount: Int?
    public var completedTaskCountLast7Days: Int?
    public var projectCount: Int?
    public var watcherLastCheck: String?
    public var watcherNextCheck: String?
    public var generatedAt: Date

    public init(
        appVersion: String,
        appBuild: String,
        macOSVersion: String,
        aiProviderKind: String,
        notificationsEnabled: Bool,
        quietHoursSummary: String,
        deadlineReminderLeadTimeLabel: String,
        openTaskCount: Int? = nil,
        completedTaskCountLast7Days: Int? = nil,
        projectCount: Int? = nil,
        watcherLastCheck: String? = nil,
        watcherNextCheck: String? = nil,
        generatedAt: Date = Date()
    ) {
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.macOSVersion = macOSVersion
        self.aiProviderKind = aiProviderKind
        self.notificationsEnabled = notificationsEnabled
        self.quietHoursSummary = quietHoursSummary
        self.deadlineReminderLeadTimeLabel = deadlineReminderLeadTimeLabel
        self.openTaskCount = openTaskCount
        self.completedTaskCountLast7Days = completedTaskCountLast7Days
        self.projectCount = projectCount
        self.watcherLastCheck = watcherLastCheck
        self.watcherNextCheck = watcherNextCheck
        self.generatedAt = generatedAt
    }
}

extension DiagnosticsReportInput {
    /// Maps persisted app settings into report fields. Only the selected
    /// provider KIND and the non-secret notification preferences are read;
    /// Keychain-backed secrets are never touched by this mapping, and no other
    /// settings field (paths, endpoints, model IDs) is copied into the report.
    public init(
        settings: AppSettings,
        appVersion: String,
        appBuild: String,
        macOSVersion: String,
        openTaskCount: Int? = nil,
        completedTaskCountLast7Days: Int? = nil,
        projectCount: Int? = nil,
        watcherLastCheck: String? = nil,
        watcherNextCheck: String? = nil,
        generatedAt: Date = Date()
    ) {
        let quietHours = settings.notificationPreferences.quietHours.normalized
        let quietHoursSummary: String
        if quietHours.enabled {
            quietHoursSummary = "enabled ("
                + Self.minuteOfDayLabel(quietHours.startMinuteOfDay)
                + " - "
                + Self.minuteOfDayLabel(quietHours.endMinuteOfDay)
                + ")"
        } else {
            quietHoursSummary = "disabled"
        }
        self.init(
            appVersion: appVersion,
            appBuild: appBuild,
            macOSVersion: macOSVersion,
            aiProviderKind: settings.aiProvider.displayName,
            notificationsEnabled: settings.notificationsEnabled,
            quietHoursSummary: quietHoursSummary,
            deadlineReminderLeadTimeLabel: settings.notificationPreferences.deadlineReminderLeadTime.label,
            openTaskCount: openTaskCount,
            completedTaskCountLast7Days: completedTaskCountLast7Days,
            projectCount: projectCount,
            watcherLastCheck: watcherLastCheck,
            watcherNextCheck: watcherNextCheck,
            generatedAt: generatedAt
        )
    }

    static func minuteOfDayLabel(_ minuteOfDay: Int) -> String {
        String(format: "%02d:%02d", minuteOfDay / 60, minuteOfDay % 60)
    }
}

/// Produces the plain-text diagnostics report exported from
/// Settings > Privacy. The report is metadata-only: a fixed header states
/// what is deliberately excluded so support recipients can verify the
/// boundary without trusting the exporter.
public struct DiagnosticsReportBuilder: Sendable {
    /// Fixed header block. Kept as one constant so tests can pin the privacy
    /// contract and localized UI copy cannot drift it.
    public static let privacyHeader = """
    SoloPM Diagnostics Report
    =========================

    This report contains configuration metadata and counts only.
    It deliberately does NOT include:
    - API keys or any Keychain-stored secret
    - Task, project, or knowledge frame content
    - Action plan content
    - Voice transcripts or recorded audio
    - Audit log entries (the audit log stores plan content, so it is excluded entirely)
    """

    public init() {}

    public func makeReport(input: DiagnosticsReportInput) -> String {
        let iso8601Formatter = ISO8601DateFormatter()
        iso8601Formatter.formatOptions = [.withInternetDateTime]

        var lines: [String] = []
        lines.append(Self.privacyHeader)
        lines.append("")
        lines.append("Generated at: \(iso8601Formatter.string(from: input.generatedAt))")
        lines.append("")
        lines.append("[Environment]")
        lines.append("App version: \(input.appVersion) (\(input.appBuild))")
        lines.append("macOS: \(input.macOSVersion)")
        lines.append("")
        lines.append("[AI Provider]")
        lines.append("Selected provider kind: \(input.aiProviderKind)")
        lines.append("API key material: excluded")
        lines.append("")
        lines.append("[Notifications]")
        lines.append("Notifications enabled: \(input.notificationsEnabled ? "yes" : "no")")
        lines.append("Quiet hours: \(input.quietHoursSummary)")
        lines.append("Deadline reminder lead time: \(input.deadlineReminderLeadTimeLabel)")
        lines.append("")
        lines.append("[Local Data (counts only)]")
        lines.append("Open tasks: \(countLabel(input.openTaskCount))")
        lines.append("Tasks completed in the last 7 days: \(countLabel(input.completedTaskCountLast7Days))")
        lines.append("Projects: \(countLabel(input.projectCount))")
        lines.append("")
        lines.append("[Deadline Watcher]")
        lines.append("Last check: \(input.watcherLastCheck ?? "unavailable")")
        lines.append("Next check: \(input.watcherNextCheck ?? "unavailable")")
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private func countLabel(_ count: Int?) -> String {
        guard let count else {
            return "unavailable"
        }
        return String(count)
    }
}
