import XCTest
@testable import SuisuiCore

final class DiagnosticsReportTests: XCTestCase {
    func testReportContainsFixedPrivacyHeaderListingExclusions() {
        let report = DiagnosticsReportBuilder().makeReport(input: makeInput())

        XCTAssertTrue(report.hasPrefix("Suisui Diagnostics Report"))
        XCTAssertTrue(report.contains(DiagnosticsReportBuilder.privacyHeader))
        for exclusion in [
            "API keys or any Keychain-stored secret",
            "Task, project, or knowledge frame content",
            "Action plan content",
            "Voice transcripts or recorded audio",
            "Audit log entries (the audit log stores plan content, so it is excluded entirely)"
        ] {
            XCTAssertTrue(report.contains(exclusion), "privacy header must state exclusion: \(exclusion)")
        }
    }

    func testReportDoesNotContainKeyMaterialFromSettings() {
        var settings = AppSettings.default
        settings.aiProvider = .claudeMessages
        // Plant key-shaped material in settings fields the report must never
        // copy: only the provider KIND and notification preferences may flow
        // from settings into the report.
        settings.defaultWorkspacePath = "/Users/test/sk-live-super-secret-key"
        settings.whisperCppExecutablePath = "/opt/tools/sk-whisper-secret"

        let input = DiagnosticsReportInput(
            settings: settings,
            appVersion: "1.2.3",
            appBuild: "456",
            macOSVersion: "Version 15.5 (Build 24F74)"
        )
        let report = DiagnosticsReportBuilder().makeReport(input: input)

        XCTAssertFalse(report.contains("sk-live-super-secret-key"))
        XCTAssertFalse(report.contains("sk-whisper-secret"))
        XCTAssertFalse(report.contains("/Users/test"))
        XCTAssertFalse(report.contains("/opt/tools"))
        XCTAssertTrue(report.contains("Selected provider kind: \(AIProvider.claudeMessages.displayName)"))
        XCTAssertTrue(report.contains("API key material: excluded"))
    }

    func testReportRendersCountsAndWatcherChecks() {
        let input = makeInput(
            openTaskCount: 3,
            completedTaskCountLast7Days: 5,
            projectCount: 2,
            watcherLastCheck: "2026-07-11T09:00:00Z",
            watcherNextCheck: "2026-07-12T00:00:00Z"
        )
        let report = DiagnosticsReportBuilder().makeReport(input: input)

        XCTAssertTrue(report.contains("Open tasks: 3"))
        XCTAssertTrue(report.contains("Tasks completed in the last 7 days: 5"))
        XCTAssertTrue(report.contains("Projects: 2"))
        XCTAssertTrue(report.contains("Last check: 2026-07-11T09:00:00Z"))
        XCTAssertTrue(report.contains("Next check: 2026-07-12T00:00:00Z"))
    }

    func testReportMarksUnavailableCountsAndChecksInsteadOfGuessing() {
        let report = DiagnosticsReportBuilder().makeReport(input: makeInput())

        XCTAssertTrue(report.contains("Open tasks: unavailable"))
        XCTAssertTrue(report.contains("Tasks completed in the last 7 days: unavailable"))
        XCTAssertTrue(report.contains("Projects: unavailable"))
        XCTAssertTrue(report.contains("Last check: unavailable"))
        XCTAssertTrue(report.contains("Next check: unavailable"))
    }

    func testSettingsMappingRendersNotificationSummary() {
        var settings = AppSettings.default
        settings.notificationsEnabled = true
        settings.notificationPreferences.quietHours.enabled = true
        settings.notificationPreferences.quietHours.startMinuteOfDay = 22 * 60
        settings.notificationPreferences.quietHours.endMinuteOfDay = 8 * 60
        settings.notificationPreferences.deadlineReminderLeadTime = .oneHourBefore

        let input = DiagnosticsReportInput(
            settings: settings,
            appVersion: "1.0.0",
            appBuild: "1",
            macOSVersion: "macOS 15"
        )
        let report = DiagnosticsReportBuilder().makeReport(input: input)

        XCTAssertTrue(report.contains("Notifications enabled: yes"))
        XCTAssertTrue(report.contains("Quiet hours: enabled (22:00 - 08:00)"))
        XCTAssertTrue(report.contains("Deadline reminder lead time: 1 hour before"))
        XCTAssertTrue(report.contains("App version: 1.0.0 (1)"))
        XCTAssertTrue(report.contains("macOS: macOS 15"))
    }

    private func makeInput(
        openTaskCount: Int? = nil,
        completedTaskCountLast7Days: Int? = nil,
        projectCount: Int? = nil,
        watcherLastCheck: String? = nil,
        watcherNextCheck: String? = nil
    ) -> DiagnosticsReportInput {
        DiagnosticsReportInput(
            appVersion: "1.0.0",
            appBuild: "100",
            macOSVersion: "Version 15.5",
            aiProviderKind: "OpenAI Responses",
            notificationsEnabled: false,
            quietHoursSummary: "disabled",
            deadlineReminderLeadTimeLabel: "At due time",
            openTaskCount: openTaskCount,
            completedTaskCountLast7Days: completedTaskCountLast7Days,
            projectCount: projectCount,
            watcherLastCheck: watcherLastCheck,
            watcherNextCheck: watcherNextCheck,
            generatedAt: Date(timeIntervalSince1970: 0)
        )
    }
}
