import Foundation

extension ProjectBoardViewModel {

    static func developmentAutomationProgress(
        projectID: Int64,
        taskID: Int64?,
        branchName: String?,
        receipts: [ExecutionReceipt],
        queueHandoff: ProjectDevelopmentAutomationQueueHandoff?,
        blockingReason: String?
    ) -> ProjectDevelopmentAutomationProgress {
        let prepareReceipt = latestDevelopmentAutomationReceipt(
            toolName: ActionTool.developmentPreparePullRequestWorkflow.rawValue,
            receipts: receipts
        )
        let repositoryCreateReceipt = latestDevelopmentAutomationReceipt(
            toolName: ActionTool.developmentRepositoryCreateFile.rawValue,
            receipts: receipts
        )
        let repositoryUpdateReceipt = latestDevelopmentAutomationReceipt(
            toolName: ActionTool.developmentRepositoryUpdateFile.rawValue,
            receipts: receipts
        )
        let repositoryEditReceipt = [repositoryCreateReceipt, repositoryUpdateReceipt]
            .compactMap { $0 }
            .sorted { $0.createdAt > $1.createdAt }
            .first
        let verificationReceipt = latestDevelopmentAutomationReceipt(
            toolName: ActionTool.developmentRunVerification.rawValue,
            receipts: receipts
        )
        let commitReceipt = latestDevelopmentAutomationReceipt(
            toolName: ActionTool.developmentCommitChanges.rawValue,
            receipts: receipts
        )
        let pushReceipt = latestDevelopmentAutomationReceipt(
            toolName: ActionTool.developmentPushBranch.rawValue,
            receipts: receipts
        )
        let pullRequestReceipt = latestDevelopmentAutomationReceipt(
            toolName: ActionTool.developmentCreatePullRequest.rawValue,
            receipts: receipts
        )
        let reviewReceipt = latestDevelopmentAutomationReceipt(
            toolName: ActionTool.developmentReviewPullRequestGate.rawValue,
            receipts: receipts
        )
        let mergeReceipt = latestDevelopmentAutomationReceipt(
            toolName: ActionTool.developmentMergePullRequest.rawValue,
            receipts: receipts
        )

        let successfulPrepareReceipt = prepareReceipt?.status == .succeeded ? prepareReceipt : nil
        let successfulRepositoryEditReceipt = repositoryEditReceipt?.status == .succeeded ? repositoryEditReceipt : nil
        let successfulVerificationReceipt = verificationReceipt?.status == .succeeded ? verificationReceipt : nil
        let successfulCommitReceipt = commitReceipt?.status == .succeeded ? commitReceipt : nil
        let successfulPushReceipt = pushReceipt?.status == .succeeded ? pushReceipt : nil
        let successfulPullRequestReceipt = pullRequestReceipt?.status == .succeeded ? pullRequestReceipt : nil
        let successfulReviewReceipt = reviewReceipt?.status == .succeeded ? reviewReceipt : nil
        let successfulMergeReceipt = mergeReceipt?.status == .succeeded ? mergeReceipt : nil
        let pullRequestURL = developmentAutomationReferenceID(
            kind: .pullRequest,
            receipts: [successfulPullRequestReceipt, successfulReviewReceipt, successfulMergeReceipt].compactMap { $0 }
        )
        let baseBranch = developmentAutomationReferenceID(
            kind: .developmentBaseBranch,
            receipts: [successfulPullRequestReceipt, successfulReviewReceipt, successfulMergeReceipt].compactMap { $0 }
        )
        let latestCommitOID = developmentAutomationReferenceID(
            kind: .developmentCommit,
            receipts: [
                successfulMergeReceipt,
                successfulReviewReceipt,
                successfulPullRequestReceipt,
                successfulPushReceipt,
                successfulCommitReceipt
            ].compactMap { $0 }
        )
        let hasLaterThanVerificationEvidence = successfulCommitReceipt != nil
            || successfulPushReceipt != nil
            || successfulPullRequestReceipt != nil
            || successfulReviewReceipt != nil
            || successfulMergeReceipt != nil
        let hasLaterThanRepositoryEditEvidence = successfulVerificationReceipt != nil
            || hasLaterThanVerificationEvidence
        let hasLaterThanCommitEvidence = successfulPushReceipt != nil
            || successfulPullRequestReceipt != nil
            || successfulReviewReceipt != nil
            || successfulMergeReceipt != nil
        let canQueueRepositoryEdit = successfulPrepareReceipt != nil
            && repositoryEditReceipt == nil
            && !hasLaterThanRepositoryEditEvidence
        let canQueueVerification = successfulPrepareReceipt != nil
            && successfulRepositoryEditReceipt != nil
            && verificationReceipt == nil
            && !hasLaterThanVerificationEvidence
        let canQueueCommit = successfulVerificationReceipt != nil
            && commitReceipt == nil
            && !hasLaterThanCommitEvidence
        let canQueuePush = successfulCommitReceipt != nil
            && pushReceipt == nil
            && successfulPullRequestReceipt == nil
            && successfulReviewReceipt == nil
            && successfulMergeReceipt == nil
        let canQueuePullRequestCreation = successfulPushReceipt != nil
            && pullRequestReceipt == nil
            && successfulReviewReceipt == nil
            && successfulMergeReceipt == nil
        let hasReviewEvidence = successfulReviewReceipt != nil
        let hasMergeEvidence = successfulMergeReceipt != nil
        let canQueueReview = successfulPullRequestReceipt != nil
            && pullRequestURL != nil
            && baseBranch != nil
            && !hasReviewEvidence
            && !hasMergeEvidence
        let canQueueMerge = hasReviewEvidence
            && pullRequestURL != nil
            && baseBranch != nil
            && !hasMergeEvidence
        let progressBlockingReason = blockingReason
            ?? developmentAutomationProgressBlockingReason(
                prepareReceipt: prepareReceipt,
                repositoryEditReceipt: repositoryEditReceipt,
                verificationReceipt: verificationReceipt,
                commitReceipt: commitReceipt,
                pushReceipt: pushReceipt,
                pullRequestReceipt: pullRequestReceipt,
                reviewReceipt: reviewReceipt,
                mergeReceipt: mergeReceipt,
                pullRequestURL: pullRequestURL,
                baseBranch: baseBranch
            )
        let nextApproval = developmentAutomationNextApproval(
            prepareReceipt: prepareReceipt,
            repositoryEditReceipt: repositoryEditReceipt,
            verificationReceipt: verificationReceipt,
            commitReceipt: commitReceipt,
            pushReceipt: pushReceipt,
            pullRequestReceipt: pullRequestReceipt,
            reviewReceipt: reviewReceipt,
            mergeReceipt: mergeReceipt,
            successfulPrepareReceipt: successfulPrepareReceipt,
            successfulRepositoryEditReceipt: successfulRepositoryEditReceipt,
            successfulVerificationReceipt: successfulVerificationReceipt,
            successfulCommitReceipt: successfulCommitReceipt,
            canQueueRepositoryEdit: canQueueRepositoryEdit,
            canQueueVerification: canQueueVerification,
            canQueueCommit: canQueueCommit,
            canQueuePush: canQueuePush,
            canQueuePullRequestCreation: canQueuePullRequestCreation,
            canQueueReview: canQueueReview,
            canQueueMerge: canQueueMerge,
            blockingReason: blockingReason
        )
        let approvalPreview = developmentAutomationApprovalPreview(
            branchName: branchName,
            latestCommitOID: latestCommitOID,
            pullRequestURL: pullRequestURL,
            baseBranch: baseBranch
        )

        return ProjectDevelopmentAutomationProgress(
            projectID: projectID,
            taskID: taskID,
            branchName: branchName,
            pullRequestURL: pullRequestURL,
            baseBranch: baseBranch,
            latestCommitOID: latestCommitOID,
            stages: [
                developmentAutomationProgressStage(
                    id: "branch-prepared",
                    title: String(localized: "Branch prepared"),
                    receipt: prepareReceipt
                ),
                developmentAutomationProgressStage(
                    id: "repository-edited",
                    title: String(localized: "Repository edit"),
                    receipt: repositoryEditReceipt,
                    readyWhenMissing: canQueueRepositoryEdit
                ),
                developmentAutomationProgressStage(
                    id: "verification-run",
                    title: String(localized: "Verification run"),
                    receipt: verificationReceipt,
                    readyWhenMissing: canQueueVerification
                ),
                developmentAutomationProgressStage(
                    id: "commit-created",
                    title: String(localized: "Commit created"),
                    receipt: commitReceipt,
                    readyWhenMissing: canQueueCommit
                ),
                developmentAutomationProgressStage(
                    id: "branch-pushed",
                    title: String(localized: "Branch pushed"),
                    receipt: pushReceipt,
                    readyWhenMissing: canQueuePush
                ),
                developmentAutomationProgressStage(
                    id: "pull-request-created",
                    title: String(localized: "Pull request created"),
                    receipt: pullRequestReceipt
                ),
                developmentAutomationProgressStage(
                    id: "pull-request-reviewed",
                    title: String(localized: "Pull request review gate"),
                    receipt: reviewReceipt,
                    readyWhenMissing: canQueueReview
                ),
                developmentAutomationProgressStage(
                    id: "pull-request-merged",
                    title: String(localized: "Pull request merge gate"),
                    receipt: mergeReceipt,
                    readyWhenMissing: canQueueMerge
                )
            ],
            canQueueRepositoryEditReview: canQueueRepositoryEdit,
            canQueueVerificationReview: canQueueVerification,
            canQueueCommitReview: canQueueCommit,
            canQueueBranchPushReview: canQueuePush,
            canQueuePullRequestCreationReview: canQueuePullRequestCreation,
            canQueuePullRequestReviewGate: canQueueReview,
            canQueuePullRequestMergeGate: canQueueMerge,
            blockingReason: progressBlockingReason,
            nextApproval: nextApproval,
            approvalPreview: approvalPreview,
            queueHandoff: queueHandoff
        )
    }

    private static func developmentAutomationApprovalPreview(
        branchName: String?,
        latestCommitOID: String?,
        pullRequestURL: String?,
        baseBranch: String?
    ) -> ProjectDevelopmentAutomationApprovalPreview? {
        var rows: [ProjectDevelopmentAutomationApprovalPreviewRow] = []
        if let branchName {
            rows.append(ProjectDevelopmentAutomationApprovalPreviewRow(
                id: "branch",
                label: String(localized: "Branch"),
                value: sanitizedDevelopmentAutomationReviewText(branchName)
            ))
        }
        if let latestCommitOID {
            rows.append(ProjectDevelopmentAutomationApprovalPreviewRow(
                id: "latest-commit",
                label: String(localized: "Latest Commit"),
                value: sanitizedDevelopmentAutomationReviewText(latestCommitOID)
            ))
        }
        if let pullRequestURL {
            rows.append(ProjectDevelopmentAutomationApprovalPreviewRow(
                id: "pull-request",
                label: String(localized: "Pull Request"),
                value: sanitizedDevelopmentAutomationReviewText(pullRequestURL)
            ))
        }
        if let baseBranch {
            rows.append(ProjectDevelopmentAutomationApprovalPreviewRow(
                id: "base-branch",
                label: String(localized: "Base Branch"),
                value: sanitizedDevelopmentAutomationReviewText(baseBranch)
            ))
        }
        guard !rows.isEmpty else {
            return nil
        }
        return ProjectDevelopmentAutomationApprovalPreview(
            title: String(localized: "Approval Preview"),
            rows: rows
        )
    }

    private static func developmentAutomationNextApproval(
        prepareReceipt: ExecutionReceipt?,
        repositoryEditReceipt: ExecutionReceipt?,
        verificationReceipt: ExecutionReceipt?,
        commitReceipt: ExecutionReceipt?,
        pushReceipt: ExecutionReceipt?,
        pullRequestReceipt: ExecutionReceipt?,
        reviewReceipt: ExecutionReceipt?,
        mergeReceipt: ExecutionReceipt?,
        successfulPrepareReceipt: ExecutionReceipt?,
        successfulRepositoryEditReceipt: ExecutionReceipt?,
        successfulVerificationReceipt: ExecutionReceipt?,
        successfulCommitReceipt: ExecutionReceipt?,
        canQueueRepositoryEdit: Bool,
        canQueueVerification: Bool,
        canQueueCommit: Bool,
        canQueuePush: Bool,
        canQueuePullRequestCreation: Bool,
        canQueueReview: Bool,
        canQueueMerge: Bool,
        blockingReason: String?
    ) -> ProjectDevelopmentAutomationNextApproval? {
        // Resume guidance must come from persisted receipts, not transient UI state,
        // so a reopened project still points users toward review and merge instead of leaving PRs behind.
        if let blockingReason {
            return ProjectDevelopmentAutomationNextApproval(
                id: "setup-required",
                title: String(localized: "Resolve development automation setup"),
                detail: blockingReason
            )
        }

        if mergeReceipt?.status == .succeeded {
            return ProjectDevelopmentAutomationNextApproval(
                id: "lifecycle-complete",
                title: String(localized: "Pull request lifecycle complete"),
                detail: String(localized: "The merge receipt is complete; no PR lifecycle approval is pending.")
            )
        }

        if let failedApproval = failedDevelopmentAutomationNextApproval(
            prepareReceipt: prepareReceipt,
            repositoryEditReceipt: repositoryEditReceipt,
            verificationReceipt: verificationReceipt,
            commitReceipt: commitReceipt,
            pushReceipt: pushReceipt,
            pullRequestReceipt: pullRequestReceipt,
            reviewReceipt: reviewReceipt,
            mergeReceipt: mergeReceipt
        ) {
            return failedApproval
        }

        if canQueueMerge {
            return ProjectDevelopmentAutomationNextApproval(
                id: "pull-request-merge",
                title: String(localized: "Queue pull request merge gate"),
                detail: String(localized: "Use the review gate receipt to queue the final merge approval.")
            )
        }

        if canQueueReview {
            return ProjectDevelopmentAutomationNextApproval(
                id: "pull-request-review",
                title: String(localized: "Queue pull request review gate"),
                detail: String(localized: "Use the PR creation receipt to queue CI, thread, and mergeability checks before merge.")
            )
        }

        if canQueuePush {
            return ProjectDevelopmentAutomationNextApproval(
                id: "branch-push",
                title: String(localized: "Queue branch push review"),
                detail: String(localized: "Push is a separate external write approval after verification and commit evidence exists.")
            )
        }

        if canQueueCommit {
            return ProjectDevelopmentAutomationNextApproval(
                id: "commit-changes",
                title: String(localized: "Queue commit review"),
                detail: String(localized: "Use the verification receipt to review the exact file list and commit message before creating a local commit.")
            )
        }

        if canQueueVerification {
            return ProjectDevelopmentAutomationNextApproval(
                id: "verification-run",
                title: String(localized: "Queue verification review"),
                detail: String(localized: "Use the repository edit receipt to run a local verification command before commit or push.")
            )
        }

        if canQueueRepositoryEdit {
            return ProjectDevelopmentAutomationNextApproval(
                id: "repository-edit",
                title: String(localized: "Queue repository edit review"),
                detail: String(localized: "Review the scoped create or update file operation before verification runs.")
            )
        }

        if canQueuePullRequestCreation {
            return ProjectDevelopmentAutomationNextApproval(
                id: "pull-request-create",
                title: String(localized: "Queue pull request creation review"),
                detail: String(localized: "Review base branch, title, and body before queueing GitHub pull request creation.")
            )
        }

        if pushReceipt == nil, successfulPrepareReceipt != nil {
            if successfulRepositoryEditReceipt == nil {
                return ProjectDevelopmentAutomationNextApproval(
                    id: "repository-edit-pending",
                    title: String(localized: "Wait for repository edit receipt"),
                    detail: String(localized: "The branch is prepared; wait for repository edit evidence before queueing verification.")
                )
            }
            if successfulVerificationReceipt == nil {
                return ProjectDevelopmentAutomationNextApproval(
                    id: "verification-pending",
                    title: String(localized: "Wait for verification receipt"),
                    detail: String(localized: "The branch is prepared; wait for verification evidence before queueing commit or push.")
                )
            }
            if successfulCommitReceipt == nil {
                return ProjectDevelopmentAutomationNextApproval(
                    id: "commit-pending",
                    title: String(localized: "Wait for commit receipt"),
                    detail: String(localized: "Verification is complete; wait for local commit evidence before queueing push.")
                )
            }
            return ProjectDevelopmentAutomationNextApproval(
                id: "branch-push",
                title: String(localized: "Queue branch push review"),
                detail: String(localized: "Push is a separate external write approval after branch preparation evidence exists.")
            )
        }

        if prepareReceipt == nil {
            return ProjectDevelopmentAutomationNextApproval(
                id: "branch-prepare",
                title: String(localized: "Queue branch automation"),
                detail: String(localized: "Start with the Assistant Queue branch preparation approval before any git mutation runs.")
            )
        }

        return ProjectDevelopmentAutomationNextApproval(
            id: "receipt-pending",
            title: String(localized: "Wait for execution receipt"),
            detail: String(localized: "The current development approval is still waiting for execution evidence before the next approval can be queued.")
        )
    }

    private static func failedDevelopmentAutomationNextApproval(
        prepareReceipt: ExecutionReceipt?,
        repositoryEditReceipt: ExecutionReceipt?,
        verificationReceipt: ExecutionReceipt?,
        commitReceipt: ExecutionReceipt?,
        pushReceipt: ExecutionReceipt?,
        pullRequestReceipt: ExecutionReceipt?,
        reviewReceipt: ExecutionReceipt?,
        mergeReceipt: ExecutionReceipt?
    ) -> ProjectDevelopmentAutomationNextApproval? {
        let candidates: [(ExecutionReceipt?, String)] = [
            (mergeReceipt, String(localized: "Review failed pull request merge")),
            (reviewReceipt, String(localized: "Review failed pull request gate")),
            (pullRequestReceipt, String(localized: "Review failed pull request creation")),
            (pushReceipt, String(localized: "Review failed branch push")),
            (commitReceipt, String(localized: "Review failed commit")),
            (verificationReceipt, String(localized: "Review failed verification")),
            (repositoryEditReceipt, String(localized: "Review failed repository edit")),
            (prepareReceipt, String(localized: "Review failed branch preparation"))
        ]
        let failedReceipt: (id: String, title: String)? = candidates.compactMap { candidate -> (id: String, title: String)? in
            let (receipt, title) = candidate
            guard let receipt,
                  receipt.status == .failed || receipt.status == .canceled else {
                return nil
            }
            return (id: receipt.id, title: title)
        }.first

        guard let failedReceipt else {
            return nil
        }

        return ProjectDevelopmentAutomationNextApproval(
            id: "receipt-failed-\(failedReceipt.id)",
            title: failedReceipt.title,
            detail: String(localized: "Resolve the failed execution receipt before queueing the next development approval.")
        )
    }

    private static func developmentAutomationProgressStage(
        id: String,
        title: String,
        receipt: ExecutionReceipt?,
        readyWhenMissing: Bool = false
    ) -> ProjectDevelopmentAutomationProgressStage {
        let status: ProjectDevelopmentAutomationProgressStageStatus
        if let receipt {
            switch receipt.status {
            case .succeeded:
                status = .succeeded
            case .failed, .canceled:
                status = .failed
            case .running, .notStarted, .skipped:
                status = .waiting
            }
        } else {
            status = readyWhenMissing ? .ready : .waiting
        }

        return ProjectDevelopmentAutomationProgressStage(
            id: id,
            title: title,
            status: status,
            detail: receipt.map { summarizedDevelopmentAutomationReceipt($0) }
        )
    }

    private static func summarizedDevelopmentAutomationReceipt(_ receipt: ExecutionReceipt) -> String {
        let summary = sanitizedDevelopmentAutomationReviewText(receipt.outputSummary)
        guard summary.count > 180 else {
            return summary
        }
        return "\(summary.prefix(177))..."
    }

    static func developmentAutomationQueueHandoff(
        from row: AssistantQueueReadModelRow
    ) -> ProjectDevelopmentAutomationQueueHandoff {
        ProjectDevelopmentAutomationQueueHandoff(
            id: row.id,
            state: row.state,
            stateLabel: row.stateLabel,
            title: row.title,
            reviewReason: row.reviewReason,
            capabilityLabels: row.capabilityLabels,
            latestReceiptStatusLabel: row.latestReceipt?.statusLabel,
            canApprove: row.canApprove,
            canRun: row.canRun
        )
    }

    static func developmentAutomationExpectedQueueToolNames(
        receipts: [ExecutionReceipt]
    ) -> Set<String> {
        let prepareReceipt = latestDevelopmentAutomationReceipt(
            toolName: ActionTool.developmentPreparePullRequestWorkflow.rawValue,
            receipts: receipts
        )
        let repositoryCreateReceipt = latestDevelopmentAutomationReceipt(
            toolName: ActionTool.developmentRepositoryCreateFile.rawValue,
            receipts: receipts
        )
        let repositoryUpdateReceipt = latestDevelopmentAutomationReceipt(
            toolName: ActionTool.developmentRepositoryUpdateFile.rawValue,
            receipts: receipts
        )
        let repositoryEditReceipt = [repositoryCreateReceipt, repositoryUpdateReceipt]
            .compactMap { $0 }
            .sorted { $0.createdAt > $1.createdAt }
            .first
        let verificationReceipt = latestDevelopmentAutomationReceipt(
            toolName: ActionTool.developmentRunVerification.rawValue,
            receipts: receipts
        )
        let commitReceipt = latestDevelopmentAutomationReceipt(
            toolName: ActionTool.developmentCommitChanges.rawValue,
            receipts: receipts
        )
        let pushReceipt = latestDevelopmentAutomationReceipt(
            toolName: ActionTool.developmentPushBranch.rawValue,
            receipts: receipts
        )
        let pullRequestReceipt = latestDevelopmentAutomationReceipt(
            toolName: ActionTool.developmentCreatePullRequest.rawValue,
            receipts: receipts
        )
        let reviewReceipt = latestDevelopmentAutomationReceipt(
            toolName: ActionTool.developmentReviewPullRequestGate.rawValue,
            receipts: receipts
        )
        let mergeReceipt = latestDevelopmentAutomationReceipt(
            toolName: ActionTool.developmentMergePullRequest.rawValue,
            receipts: receipts
        )

        if mergeReceipt?.status == .succeeded {
            return []
        }

        if let failedReceipt = [
            mergeReceipt,
            reviewReceipt,
            pullRequestReceipt,
            pushReceipt,
            commitReceipt,
            verificationReceipt,
            repositoryEditReceipt,
            prepareReceipt
        ].compactMap({ $0 }).first(where: { receipt in
            receipt.status == .failed || receipt.status == .canceled
        }) {
            return failedReceipt.primaryToolName.map { [$0] } ?? Set(failedReceipt.actions.map(\.toolName))
        }

        let successfulPrepareReceipt = prepareReceipt?.status == .succeeded ? prepareReceipt : nil
        let successfulRepositoryEditReceipt = repositoryEditReceipt?.status == .succeeded ? repositoryEditReceipt : nil
        let successfulVerificationReceipt = verificationReceipt?.status == .succeeded ? verificationReceipt : nil
        let successfulCommitReceipt = commitReceipt?.status == .succeeded ? commitReceipt : nil
        let successfulPushReceipt = pushReceipt?.status == .succeeded ? pushReceipt : nil
        let successfulPullRequestReceipt = pullRequestReceipt?.status == .succeeded ? pullRequestReceipt : nil
        let successfulReviewReceipt = reviewReceipt?.status == .succeeded ? reviewReceipt : nil

        if successfulPrepareReceipt == nil {
            return [ActionTool.developmentPreparePullRequestWorkflow.rawValue]
        }
        if successfulRepositoryEditReceipt == nil {
            return [
                ActionTool.developmentRepositoryCreateFile.rawValue,
                ActionTool.developmentRepositoryUpdateFile.rawValue
            ]
        }
        if successfulVerificationReceipt == nil {
            return [ActionTool.developmentRunVerification.rawValue]
        }
        if successfulCommitReceipt == nil {
            return [ActionTool.developmentCommitChanges.rawValue]
        }
        if successfulPushReceipt == nil {
            return [ActionTool.developmentPushBranch.rawValue]
        }
        if successfulPullRequestReceipt == nil {
            return [ActionTool.developmentCreatePullRequest.rawValue]
        }
        if successfulReviewReceipt == nil {
            return [ActionTool.developmentReviewPullRequestGate.rawValue]
        }
        return [ActionTool.developmentMergePullRequest.rawValue]
    }

    static func developmentAutomationQueueItemMatches(
        _ item: AssistantQueueItem,
        projectID: Int64,
        taskID: Int64?,
        branchName: String,
        expectedToolNames: Set<String>
    ) -> Bool {
        switch item.payload {
        case .actionPlan(let plan):
            return developmentAutomationActionPlanMatches(
                plan,
                projectID: projectID,
                taskID: taskID,
                branchName: branchName,
                expectedToolNames: expectedToolNames
            )
        case .automationRequest(let request):
            return developmentAutomationRequestMatches(
                request,
                projectID: projectID,
                taskID: taskID,
                branchName: branchName,
                expectedToolNames: expectedToolNames
            )
        }
    }

    static func isDevelopmentAutomationQueueHandoffState(_ state: AssistantQueueState) -> Bool {
        switch state {
        case .done, .rejected:
            return false
        case .captured, .interpreted, .drafted, .waitingReview, .approved, .running, .blocked, .failed, .deferred:
            return true
        }
    }

    private static func developmentAutomationActionPlanMatches(
        _ plan: ActionPlan,
        projectID: Int64,
        taskID: Int64?,
        branchName: String,
        expectedToolNames: Set<String>
    ) -> Bool {
        plan.actions.contains { action in
            expectedToolNames.contains(action.tool.rawValue)
                && jsonNumber(action.arguments["projectId"], equals: projectID)
                && jsonString(action.arguments["branchName"], equals: branchName)
                && taskID.map { jsonNumber(action.arguments["taskId"], equals: $0) } ?? true
        }
    }

    private static func developmentAutomationRequestMatches(
        _ request: SyncAutomationRequestPayload,
        projectID: Int64,
        taskID: Int64?,
        branchName: String,
        expectedToolNames: Set<String>
    ) -> Bool {
        guard let toolName = request.toolName,
              expectedToolNames.contains(toolName),
              let pullRequest = request.developmentPullRequest,
              pullRequest.projectID == projectID,
              pullRequest.branchName == branchName else {
            return false
        }
        guard let expectedTaskID = taskID,
              let requestTaskID = pullRequest.taskID else {
            return true
        }
        return requestTaskID == expectedTaskID
    }

    private static func jsonNumber(_ value: JSONValue?, equals expected: Int64) -> Bool {
        guard case .number(let number) = value else {
            return false
        }
        return number == Double(expected)
    }

    private static func jsonString(_ value: JSONValue?, equals expected: String) -> Bool {
        guard case .string(let string) = value else {
            return false
        }
        return string == expected
    }

    private static func latestDevelopmentAutomationReceipt(
        toolName: String,
        receipts: [ExecutionReceipt]
    ) -> ExecutionReceipt? {
        receipts.first { receipt in
            receipt.primaryToolName == toolName
                || receipt.actions.contains { $0.toolName == toolName }
        }
    }

    private static func developmentAutomationReferenceID(
        kind: ExecutionReceiptReferenceKind,
        receipts: [ExecutionReceipt]
    ) -> String? {
        receipts
            .lazy
            .flatMap(\.references)
            .first { $0.kind == kind }?
            .id
    }

    static func developmentAutomationReceiptMatches(
        _ receipt: ExecutionReceipt,
        projectID: Int64,
        branchName: String
    ) -> Bool {
        let references = receipt.references
        return references.contains { $0.kind == .project && $0.id == String(projectID) }
            && references.contains { $0.kind == .developmentBranch && $0.id == branchName }
    }

    private static func developmentAutomationProgressBlockingReason(
        prepareReceipt: ExecutionReceipt?,
        repositoryEditReceipt: ExecutionReceipt?,
        verificationReceipt: ExecutionReceipt?,
        commitReceipt: ExecutionReceipt?,
        pushReceipt: ExecutionReceipt?,
        pullRequestReceipt: ExecutionReceipt?,
        reviewReceipt: ExecutionReceipt?,
        mergeReceipt: ExecutionReceipt?,
        pullRequestURL: String?,
        baseBranch: String?
    ) -> String? {
        if mergeReceipt?.status == .succeeded {
            return String(localized: "Pull request merge receipt is complete.")
        }
        if prepareReceipt == nil {
            return String(localized: "Queue branch preparation and wait for its execution receipt before verification.")
        }
        if prepareReceipt?.status == .failed || prepareReceipt?.status == .canceled {
            return String(localized: "Branch preparation failed. Review the execution receipt before queueing verification.")
        }
        let hasEvidenceAfterRepositoryEdit = verificationReceipt != nil
            || commitReceipt != nil
            || pushReceipt != nil
            || pullRequestReceipt != nil
            || reviewReceipt != nil
            || mergeReceipt != nil
        let hasEvidenceAfterVerification = commitReceipt != nil
            || pushReceipt != nil
            || pullRequestReceipt != nil
            || reviewReceipt != nil
            || mergeReceipt != nil
        let hasEvidenceAfterCommit = pushReceipt != nil
            || pullRequestReceipt != nil
            || reviewReceipt != nil
            || mergeReceipt != nil
        if repositoryEditReceipt == nil, !hasEvidenceAfterRepositoryEdit {
            return String(localized: "Queue a repository edit and wait for its execution receipt before verification.")
        }
        if repositoryEditReceipt?.status == .failed || repositoryEditReceipt?.status == .canceled {
            return String(localized: "Repository edit failed. Review the execution receipt before queueing verification.")
        }
        if verificationReceipt == nil, !hasEvidenceAfterVerification {
            return String(localized: "Run verification and wait for its execution receipt before commit.")
        }
        if verificationReceipt?.status == .failed || verificationReceipt?.status == .canceled {
            return String(localized: "Verification failed. Review the execution receipt before queueing commit.")
        }
        if commitReceipt == nil, !hasEvidenceAfterCommit {
            return String(localized: "Create the local commit and wait for its execution receipt before push.")
        }
        if commitReceipt?.status == .failed || commitReceipt?.status == .canceled {
            return String(localized: "Local commit failed. Review the execution receipt before queueing push.")
        }
        if pushReceipt == nil {
            return String(localized: "Push the branch and wait for its execution receipt before pull request creation.")
        }
        if pushReceipt?.status == .failed || pushReceipt?.status == .canceled {
            return String(localized: "Branch push failed. Review the execution receipt before queueing pull request creation.")
        }
        if pullRequestReceipt == nil {
            return String(localized: "Create the pull request and wait for its execution receipt before queueing review or merge.")
        }
        if pullRequestReceipt?.status == .failed || pullRequestReceipt?.status == .canceled {
            return String(localized: "Pull request creation failed. Review the execution receipt before queueing review or merge.")
        }
        if pullRequestURL == nil || baseBranch == nil {
            return String(localized: "Pull request receipt is missing URL or base branch evidence, so Suisui will not draft review or merge approval.")
        }
        if reviewReceipt?.status == .failed || reviewReceipt?.status == .canceled {
            return String(localized: "Pull request review gate failed. Resolve the receipt before queueing merge.")
        }
        if reviewReceipt == nil {
            return String(localized: "Pull request is ready for a review gate approval.")
        }
        return String(localized: "Pull request is ready for a merge gate approval.")
    }

    static func developmentPullRequestLifecycleMissingEvidenceMessage(
        for operation: SyncDevelopmentPullRequestOperation
    ) -> String {
        switch operation {
        case .reviewGate:
            return String(localized: "Create the pull request and wait for its receipt before queueing review.")
        case .merge:
            return String(localized: "Run the pull request review gate and wait for its receipt before queueing merge.")
        }
    }

    func task(id: Int64) -> ProjectBoardTask? {
        snapshot.projects
            .flatMap(\.tasks)
            .first { $0.id == id }
    }
}
