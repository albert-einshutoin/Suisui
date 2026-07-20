import Foundation
import SuisuiCore
import SwiftUI

func localizedDisplay(_ key: String) -> String {
    if let preference = AppLanguagePreference.environmentOverride
        ?? AppLanguagePreference(rawValue: UserDefaults.standard.string(forKey: AppLanguagePreference.storageKey) ?? ""),
       preference != .system,
       let localizationPath = Bundle.main.path(forResource: preference.localeIdentifier, ofType: "lproj"),
       let localizationBundle = Bundle(path: localizationPath) {
        // Dynamic status strings do not inherit SwiftUI's environment locale.
        // Resolve them from the same explicit app preference so visible text,
        // help, and accessibility values cannot drift to the system language.
        return localizationBundle.localizedString(forKey: key, value: key, table: nil)
    }
    return String(localized: String.LocalizationValue(key))
}

func localizedDisplay(_ formatKey: String, _ arguments: CVarArg...) -> String {
    String(format: localizedDisplay(formatKey), arguments: arguments)
}

func localizedTaskCount(_ count: Int) -> String {
    localizedDisplay(count == 1 ? "%d task" : "%d tasks", count)
}

func localizedInboxCaptureSource(_ source: InboxCaptureSourceKind) -> String {
    switch source {
    case .voiceMemo:
        localizedDisplay("Voice memo")
    }
}

func localizedInboxCaptureClassification(_ status: InboxCaptureClassificationStatus) -> String {
    switch status {
    case .unclassified:
        localizedDisplay("Unclassified")
    case .classified:
        localizedDisplay("Classified")
    case .dismissed:
        localizedDisplay("Dismissed")
    }
}

func localizedInboxCaptureTranscription(_ status: InboxCaptureTranscriptionStatus) -> String {
    switch status {
    case .pending:
        localizedDisplay("Pending")
    case .succeeded:
        localizedDisplay("Succeeded")
    case .failed:
        localizedDisplay("Failed")
    }
}

func localizedInboxCaptureDuration(_ durationSeconds: Double) -> String {
    localizedDisplay("%d sec", Int(durationSeconds.rounded()))
}

func localizedRiskLevel(_ riskLevel: RiskLevel) -> String {
    switch riskLevel {
    case .read:
        localizedDisplay("Read only")
    case .draft:
        localizedDisplay("Draft")
    case .write:
        localizedDisplay("Write")
    case .danger:
        localizedDisplay("Dangerous")
    }
}

func localizedActionTool(_ tool: ActionTool) -> String {
    switch tool {
    case .projectCreate: localizedDisplay("Create project")
    case .projectUpdate: localizedDisplay("Update project")
    case .projectList: localizedDisplay("List projects")
    case .projectGet: localizedDisplay("View project")
    case .projectComplete: localizedDisplay("Complete project")
    case .projectDelete: localizedDisplay("Delete project")
    case .taskCreate: localizedDisplay("Create task")
    case .taskBulkCreate: localizedDisplay("Create multiple tasks")
    case .taskList: localizedDisplay("List tasks")
    case .taskGet: localizedDisplay("View task")
    case .taskUpdate: localizedDisplay("Update task")
    case .taskComplete: localizedDisplay("Complete task")
    case .taskDelete: localizedDisplay("Delete task")
    case .taskListDue: localizedDisplay("List due tasks")
    case .taskListOverdue: localizedDisplay("List overdue tasks")
    case .notificationSchedule: localizedDisplay("Schedule notification")
    case .notificationScheduleRelative: localizedDisplay("Schedule relative notification")
    case .notificationScheduleOverdueRule: localizedDisplay("Schedule overdue reminder")
    case .notificationCancel: localizedDisplay("Cancel notification")
    case .notificationList: localizedDisplay("List notifications")
    case .calendarCreateEvent: localizedDisplay("Create calendar event")
    case .calendarCreateDeadline: localizedDisplay("Create deadline event")
    case .calendarCreateWorkBlock: localizedDisplay("Create work block")
    case .remindersCreate: localizedDisplay("Create reminder")
    case .remindersBulkCreate: localizedDisplay("Create multiple reminders")
    case .remindersMarkComplete: localizedDisplay("Complete reminder")
    case .filesystemCreateDirectory: localizedDisplay("Create folder")
    case .filesystemCreateMarkdownFile: localizedDisplay("Create Markdown file")
    case .filesystemCreateArtifactsFromFrame: localizedDisplay("Create files from frame")
    case .filesystemScanProjectArtifacts: localizedDisplay("Scan project files")
    case .frameSearch: localizedDisplay("Search frames")
    case .frameList: localizedDisplay("List frames")
    case .frameGet: localizedDisplay("View frame")
    case .frameCreate: localizedDisplay("Create frame")
    case .frameUpdate: localizedDisplay("Update frame")
    case .frameDelete: localizedDisplay("Delete frame")
    case .mailDraftCreateText: localizedDisplay("Create mail draft")
    case .gitStatus: localizedDisplay("Check Git status")
    case .gitBranch: localizedDisplay("View Git branch")
    case .gitLogSummary: localizedDisplay("Summarize Git history")
    case .gitDiffSummary: localizedDisplay("Summarize Git changes")
    case .developmentPreparePullRequestWorkflow: localizedDisplay("Prepare pull request")
    case .developmentCommitChanges: localizedDisplay("Commit changes")
    case .developmentPushBranch: localizedDisplay("Push branch")
    case .developmentCreatePullRequest: localizedDisplay("Create pull request")
    case .developmentReviewPullRequestGate: localizedDisplay("Review pull request")
    case .developmentMergePullRequest: localizedDisplay("Merge pull request")
    case .developmentRepositoryListFiles: localizedDisplay("List repository files")
    case .developmentRepositoryReadFile: localizedDisplay("Read repository file")
    case .developmentRepositoryCreateFile: localizedDisplay("Create repository file")
    case .developmentRepositoryUpdateFile: localizedDisplay("Update repository file")
    case .developmentRunVerification: localizedDisplay("Run verification")
    }
}

func localizedSettingsDisplay(_ value: String) -> String {
    let smokePrefix = "Smoke: "
    if value.hasPrefix(smokePrefix) {
        let status = String(value.dropFirst(smokePrefix.count))
        return localizedDisplay("Smoke: %@", localizedSettingsDisplay(status))
    }
    return localizedDisplay(value)
}
