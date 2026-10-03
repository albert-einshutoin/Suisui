import Foundation
import CryptoKit

extension ProjectBoardViewModel {

    static let developmentAutomationAllowedFileOperations = ["create", "read", "update"]
    static let defaultDevelopmentPullRequestBaseBranch = "main"

    static let developmentAutomationLifecycleToolNames = [
        ActionTool.developmentPreparePullRequestWorkflow.rawValue,
        ActionTool.developmentRepositoryListFiles.rawValue,
        ActionTool.developmentRepositoryReadFile.rawValue,
        ActionTool.developmentRepositoryCreateFile.rawValue,
        ActionTool.developmentRepositoryUpdateFile.rawValue,
        ActionTool.developmentRunVerification.rawValue,
        ActionTool.developmentCommitChanges.rawValue,
        ActionTool.developmentPushBranch.rawValue,
        ActionTool.developmentCreatePullRequest.rawValue,
        ActionTool.developmentReviewPullRequestGate.rawValue,
        ActionTool.developmentMergePullRequest.rawValue
    ]

    static let developmentAutomationApprovalBoundaryLabel = "Branch preparation starts here; file edits, verification, commit, push, pull request, review, and merge each stay behind explicit approval gates."

    static func developmentAutomationQueueReason(project: ProjectBoardProject) -> String {
        String(
            format: String(localized: "Development branch automation is ready for %@."),
            sanitizedDevelopmentAutomationReviewText(project.title)
        )
    }

    static func developmentAutomationPushQueueReason(project: ProjectBoardProject) -> String {
        String(
            format: String(localized: "Development branch push needs review for %@."),
            sanitizedDevelopmentAutomationReviewText(project.title)
        )
    }

    static func developmentVerificationQueueReason(project: ProjectBoardProject) -> String {
        String(
            format: String(localized: "Development verification needs review for %@."),
            sanitizedDevelopmentAutomationReviewText(project.title)
        )
    }

    static func developmentRepositoryEditQueueReason(project: ProjectBoardProject) -> String {
        String(
            format: String(localized: "Development repository edit needs review for %@."),
            sanitizedDevelopmentAutomationReviewText(project.title)
        )
    }

    static func developmentCommitQueueReason(project: ProjectBoardProject) -> String {
        String(
            format: String(localized: "Development commit needs reviewed files and message for %@."),
            sanitizedDevelopmentAutomationReviewText(project.title)
        )
    }

    static func developmentPullRequestCreationQueueReason(project: ProjectBoardProject) -> String {
        String(
            format: String(localized: "Development pull request creation needs base, title, and body review for %@."),
            sanitizedDevelopmentAutomationReviewText(project.title)
        )
    }

    static func developmentPullRequestLifecycleQueueReason(
        project: ProjectBoardProject,
        operation: SyncDevelopmentPullRequestOperation
    ) -> String {
        String(
            format: String(localized: "Development pull request %@ gate needs review for %@."),
            developmentPullRequestLifecycleOperationLabel(for: operation),
            sanitizedDevelopmentAutomationReviewText(project.title)
        )
    }

    static func developmentPullRequestLifecycleQueuedMessage(
        for operation: SyncDevelopmentPullRequestOperation
    ) -> String {
        switch operation {
        case .reviewGate:
            return String(localized: "Queued development pull request review gate for approval.")
        case .merge:
            return String(localized: "Queued development pull request merge gate for approval.")
        }
    }

    static func developmentPullRequestLifecycleAlreadyQueuedMessage(
        for operation: SyncDevelopmentPullRequestOperation
    ) -> String {
        switch operation {
        case .reviewGate:
            return String(localized: "Development pull request review gate is already in Assistant Queue.")
        case .merge:
            return String(localized: "Development pull request merge gate is already in Assistant Queue.")
        }
    }

    static func developmentPullRequestLifecycleToolName(
        for operation: SyncDevelopmentPullRequestOperation
    ) -> String {
        switch operation {
        case .reviewGate:
            return ActionTool.developmentReviewPullRequestGate.rawValue
        case .merge:
            return ActionTool.developmentMergePullRequest.rawValue
        }
    }

    private static func developmentPullRequestLifecycleOperationID(
        for operation: SyncDevelopmentPullRequestOperation
    ) -> String {
        switch operation {
        case .reviewGate:
            return "review"
        case .merge:
            return "merge"
        }
    }

    private static func developmentPullRequestLifecycleOperationLabel(
        for operation: SyncDevelopmentPullRequestOperation
    ) -> String {
        switch operation {
        case .reviewGate:
            return String(localized: "review")
        case .merge:
            return String(localized: "merge")
        }
    }

    static func developmentPullRequestLifecycleSummary(
        operation: SyncDevelopmentPullRequestOperation,
        pullRequestURL: String,
        branchName: String,
        baseBranch: String
    ) -> String {
        let action: String
        switch operation {
        case .reviewGate:
            action = "Review CI, review decision, unresolved threads, and mergeability before merge approval."
        case .merge:
            action = "Merge only after the review gate passes and execution rechecks the approved head commit."
        }
        return sanitizedDevelopmentAutomationReviewText(
            "Project development PR \(developmentPullRequestLifecycleOperationID(for: operation)): \(pullRequestURL) head \(branchName) into \(baseBranch). \(action)"
        )
    }

    static func developmentPullRequestTitle(
        project: ProjectBoardProject,
        task: ProjectBoardTask
    ) -> String {
        let taskTitle = sanitizedSingleLineDevelopmentAutomationText(task.title, fallback: "task \(task.id)")
        return truncatedPullRequestTitle("Suisui: \(taskTitle)")
    }

    static func developmentPullRequestBody(
        project: ProjectBoardProject,
        task: ProjectBoardTask,
        branchName: String,
        baseBranch: String
    ) -> String {
        let projectTitle = sanitizedSingleLineDevelopmentAutomationText(project.title, fallback: "project \(project.id)")
        let taskTitle = sanitizedSingleLineDevelopmentAutomationText(task.title, fallback: "task \(task.id)")
        return """
        ## Summary
        - Prepare \(taskTitle) for \(projectTitle).

        ## Pull Request
        - Base branch: \(baseBranch)
        - Head branch: \(branchName)

        ## Review
        - Created from Suisui development automation after separate branch preparation, verification, commit, and push gates.
        - Review CI, code review, and merge readiness before merging.
        """
    }

    private static func sanitizedSingleLineDevelopmentAutomationText(_ text: String, fallback: String) -> String {
        let sanitized = sanitizedDevelopmentAutomationReviewText(text)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return sanitized.isEmpty ? fallback : sanitized
    }

    private static func truncatedPullRequestTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 200 else {
            return trimmed
        }
        return String(trimmed.prefix(197)) + "..."
    }

    static func sanitizedDevelopmentAutomationReviewText(_ text: String) -> String {
        let redacted = ExecutionReceiptRedactor().redact(text.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !redacted.isEmpty else {
            return String(localized: "Development branch automation")
        }
        let maxLength = 500
        guard redacted.count > maxLength else {
            return redacted
        }
        return "\(redacted.prefix(maxLength))..."
    }

    private static func developmentRepositoryEditLineCount(_ contents: String) -> Int {
        // Treat a final newline as file formatting, not an extra blank line, so
        // the preview matches how users normally describe source-file edits.
        let newlineCount = contents.reduce(into: 0) { count, character in
            if character.isNewline {
                count += 1
            }
        }
        return max(1, 1 + newlineCount - (contents.last?.isNewline == true ? 1 : 0))
    }

    static func developmentRepositoryEditContentSummary(_ contents: String) -> String {
        let lineCount = developmentRepositoryEditLineCount(contents)
        let byteCount = contents.utf8.count
        if lineCount == 1 {
            return String(format: String(localized: "%d line / %d bytes"), lineCount, byteCount)
        }
        return String(format: String(localized: "%d lines / %d bytes"), lineCount, byteCount)
    }

    static func developmentRepositoryEditReviewedLineSummary(_ contents: String) -> String {
        String(format: String(localized: "Reviewed replacement lines: %d"), developmentRepositoryEditLineCount(contents))
    }

    static func developmentRepositoryEditReviewedReplacementPreview(
        operation: ProjectDevelopmentRepositoryEditOperation,
        relativePath: String,
        contents: String
    ) -> String {
        // Preview must not read the user's repository before approval, so avoid
        // add/delete counts that would imply Suisui compared against existing content.
        let sanitizedPath = sanitizedDevelopmentAutomationReviewText(relativePath)
        let lineCount = developmentRepositoryEditLineCount(contents)
        switch operation {
        case .create:
            return String(
                format: String(localized: "Create replacement: %@ (reviewed lines: %d)"),
                sanitizedPath,
                lineCount
            )
        case .update:
            return String(
                format: String(localized: "Update replacement: %@ (reviewed lines: %d)"),
                sanitizedPath,
                lineCount
            )
        }
    }

    static func developmentRepositoryEditContentDigest(_ contents: String) -> String {
        let digest = SHA256.hash(data: Data(contents.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return String(digest.prefix(12))
    }

    static let developmentAutomationReviewSteps = [
        "Create a reviewable local branch inside the approved project directory.",
        "Use project-scoped create/read/update file operations; delete is not available.",
        "ReviewSession validates the saved project directory again before branch creation.",
        "Run verification before commit, push, or pull request creation.",
        "Require explicit approval before git push and GitHub pull request creation.",
        "Use review and merge gates before marking the pull request complete."
    ]

    static func developmentAutomationProjectRecord(from project: ProjectBoardProject) -> ProjectRecord {
        ProjectRecord(
            id: project.id,
            title: project.title,
            status: project.status
        )
    }

    static func developmentAutomationTaskRecord(from task: ProjectBoardTask) -> TaskRecord {
        TaskRecord(
            id: task.id,
            projectID: task.projectID,
            title: task.title,
            status: task.status.rawValue,
            dueAt: task.dueAt,
            completedAt: task.completedAt,
            priority: task.priority.rawValue,
            sourceCommand: nil,
            detail: task.detail,
            updatedAt: task.updatedAt
        )
    }

    static func developmentAutomationPlanDigest(
        projectID: Int64,
        taskID: Int64,
        branchName: String
    ) -> String {
        let input = "\(projectID):\(taskID):\(branchName)"
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    static func validatedDevelopmentCommitRelativePaths(from text: String) throws -> [String] {
        let rawPaths = text
            .components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !rawPaths.isEmpty else {
            throw DevelopmentCommitWorkflowError.noRelativePaths
        }

        var seen: Set<String> = []
        var relativePaths: [String] = []
        for rawPath in rawPaths {
            let relativePath = try DevelopmentRepositoryFilePathPolicy.validatedRelativePath(rawPath)
            guard seen.insert(relativePath).inserted else {
                continue
            }
            relativePaths.append(relativePath)
        }

        guard !relativePaths.isEmpty else {
            throw DevelopmentCommitWorkflowError.noRelativePaths
        }
        return relativePaths
    }

    static func developmentVerificationPlanDigest(
        projectID: Int64,
        taskID: Int64,
        branchName: String,
        commandID: String
    ) -> String {
        developmentReviewedInputDigest([String(projectID), String(taskID), branchName, commandID])
    }

    static func developmentRepositoryEditPlanDigest(
        projectID: Int64,
        taskID: Int64,
        branchName: String,
        operation: ProjectDevelopmentRepositoryEditOperation,
        relativePath: String,
        contents: String,
        expectedSHA256: String?
    ) -> String {
        developmentReviewedInputDigest(
            [String(projectID), String(taskID), branchName, operation.rawValue, relativePath, contents, expectedSHA256 ?? ""]
        )
    }

    static func developmentCommitPlanDigest(
        projectID: Int64,
        taskID: Int64,
        branchName: String,
        relativePaths: [String],
        commitMessage: String
    ) -> String {
        developmentReviewedInputDigest([String(projectID), String(taskID), branchName, commitMessage] + relativePaths)
    }

    static func developmentPullRequestCreationPlanDigest(
        projectID: Int64,
        taskID: Int64,
        branchName: String,
        expectedHeadOID: String,
        baseBranch: String,
        title: String,
        body: String
    ) -> String {
        // Approval identity must change when any reviewed PR field changes; otherwise
        // Assistant Queue's duplicate protection can preserve an approval for stale text.
        developmentReviewedInputDigest([String(projectID), String(taskID), branchName, expectedHeadOID, baseBranch, title, body])
    }

    private static func developmentReviewedInputDigest(_ parts: [String]) -> String {
        let input = parts
            .map { "\($0.utf8.count):\($0)" }
            .joined(separator: "|")
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    static func developmentPullRequestLifecycleRequestID(
        projectID: Int64,
        taskID: Int64,
        operation: SyncDevelopmentPullRequestOperation,
        pullRequestURL: String,
        branchName: String,
        baseBranch: String
    ) -> String {
        // Review and merge are separate approval surfaces. Include every reviewed
        // PR identity field so Assistant Queue cannot reuse approval after edits.
        let parts = [
            String(projectID),
            String(taskID),
            operation.rawValue,
            pullRequestURL,
            branchName,
            baseBranch
        ]
        let input = parts
            .map { "\($0.utf8.count):\($0)" }
            .joined(separator: "|")
        let digest = SHA256.hash(data: Data(input.utf8))
            .prefix(8)
            .map { String(format: "%02x", $0) }
            .joined()
        return "project-development-pr-\(developmentPullRequestLifecycleOperationID(for: operation)):\(projectID):\(taskID):\(digest)"
    }
}
