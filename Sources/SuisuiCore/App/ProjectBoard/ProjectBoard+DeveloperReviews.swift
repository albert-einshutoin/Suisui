import Foundation
import CryptoKit

extension ProjectBoardViewModel {
    public func developmentAutomationReadiness(
        for project: ProjectBoardProject,
        task: ProjectBoardTask?
    ) -> ProjectDevelopmentAutomationReadiness {
        let allowedFileOperations = Self.developmentAutomationAllowedFileOperations
        let reviewSteps = Self.developmentAutomationReviewSteps
        let lifecycleToolNames = Self.developmentAutomationLifecycleToolNames
        let approvalBoundaryLabel = Self.developmentAutomationApprovalBoundaryLabel
        let toolName = "development.pr_workflow.prepare"

        func blocked(_ reason: String) -> ProjectDevelopmentAutomationReadiness {
            ProjectDevelopmentAutomationReadiness(
                projectID: project.id,
                taskID: task?.id,
                isReady: false,
                statusLabel: "Needs setup",
                blockingReason: reason,
                workspaceDisplayName: project.workspaceDisplayName,
                branchNamePreview: nil,
                allowedFileOperations: allowedFileOperations,
                reviewSteps: reviewSteps,
                lifecycleToolNames: lifecycleToolNames,
                approvalBoundaryLabel: approvalBoundaryLabel,
                toolName: toolName
            )
        }

        guard !project.isArchived, !project.isCompleted else {
            return blocked("Restore the project before starting development automation.")
        }

        guard project.hasWorkspaceDirectory else {
            return blocked("Choose a project directory before starting development automation.")
        }
        guard project.hasWorkspaceBookmark else {
            return blocked("Choose the project directory again before starting branch automation.")
        }

        guard let task,
              task.projectID == project.id,
              task.status != .done,
              task.status != .blocked else {
            return blocked("Select an open development task before starting branch automation.")
        }

        let projectRecord = Self.developmentAutomationProjectRecord(from: project)
        let taskRecord = Self.developmentAutomationTaskRecord(from: task)

        // This preview deliberately reuses the write workflow's branch policy while avoiding
        // any git side effects; branch creation, push, PR creation, review, and merge stay approval-gated.
        let branchNamePreview = DevelopmentBranchNamePolicy.deterministicBranchName(
            project: projectRecord,
            task: taskRecord
        )

        return ProjectDevelopmentAutomationReadiness(
            projectID: project.id,
            taskID: task.id,
            isReady: true,
            statusLabel: "Ready for approval review",
            blockingReason: nil,
            workspaceDisplayName: project.workspaceDisplayName,
            branchNamePreview: branchNamePreview,
            allowedFileOperations: allowedFileOperations,
            reviewSteps: reviewSteps,
            lifecycleToolNames: lifecycleToolNames,
            approvalBoundaryLabel: approvalBoundaryLabel,
            toolName: toolName
        )
    }

    @discardableResult
    public func prepareDevelopmentAutomationReview(
        for project: ProjectBoardProject,
        task: ProjectBoardTask?
    ) -> ActionPlan? {
        let readiness = developmentAutomationReadiness(for: project, task: task)
        guard readiness.isReady,
              let task,
              let branchName = readiness.branchNamePreview else {
            developmentAutomationReviewPlan = nil
            todayCommandFeedback = readiness.blockingReason
            integrationStatusMessage = nil
            return nil
        }

        let plan = ActionPlan(
            id: "development-pr-prepare:\(project.id):\(task.id):\(Self.developmentAutomationPlanDigest(projectID: project.id, taskID: task.id, branchName: branchName))",
            userInput: "Prepare a reviewable development branch for \(task.title).",
            summary: "Prepare reviewable branch \(branchName) for \(task.title).",
            actions: [
                PlanAction(
                    id: "development-pr-prepare",
                    tool: .developmentPreparePullRequestWorkflow,
                    arguments: [
                        "projectId": .number(Double(project.id)),
                        "taskId": .number(Double(task.id)),
                        "branchName": .string(branchName)
                    ],
                    riskLevel: .write,
                    requiresUserConfirmation: true
                )
            ],
            riskLevel: .write,
            requiresApproval: true
        )
        // Store only the review plan, not an execution result. The actual git
        // branch operation remains behind ReviewSession approval and runtime
        // workspace validation so a stale bookmark cannot mutate the repo from this panel.
        developmentAutomationReviewPlan = plan
        integrationStatusMessage = "Development branch automation is ready for review."
        todayCommandFeedback = nil
        recordOperationFailure(nil)
        return plan
    }

    public func clearDevelopmentAutomationReviewPlan() {
        developmentAutomationReviewPlan = nil
    }

    @discardableResult
    public func enqueueDevelopmentAutomationReview(
        for project: ProjectBoardProject,
        task: ProjectBoardTask?
    ) -> Bool {
        guard let assistantQueueStore else {
            assistantQueueSnapshot = .empty
            assistantQueueSelectedItemIDs = []
            recordOperationFailure(String(localized: "Assistant Queue is unavailable in this build."))
            integrationStatusMessage = nil
            return false
        }
        guard var plan = prepareDevelopmentAutomationReview(for: project, task: task) else {
            return false
        }

        let validator = ActionPlanValidator()
        let validation = validator.validate(plan)
        guard validation.isValid else {
            recordOperationFailure(String(localized: "Development automation generated an invalid action plan."))
            integrationStatusMessage = nil
            return false
        }

        plan.userInput = Self.sanitizedDevelopmentAutomationReviewText(plan.userInput)
        plan.summary = Self.sanitizedDevelopmentAutomationReviewText(plan.summary)
        let persistedValidation = validator.validate(plan)
        guard persistedValidation.isValid else {
            recordOperationFailure(String(localized: "Development automation generated an invalid action plan."))
            integrationStatusMessage = nil
            return false
        }

        let item = AssistantQueueAdapter.makeItem(
            actionPlan: plan,
            sourceTranscript: plan.userInput,
            interpretationSummary: plan.summary,
            reason: Self.developmentAutomationQueueReason(project: project),
            costPreview: .localOnly()
        )

        do {
            if try assistantQueueStore.insertIfAbsent(item) != nil {
                focusAssistantQueueItem(id: item.id)
                recordOperationFailure(nil)
                integrationStatusMessage = String(localized: "Queued development automation for approval.")
                todayCommandFeedback = nil
                onChange()
                return true
            }

            focusAssistantQueueItem(id: item.id)
            recordOperationFailure(nil)
            integrationStatusMessage = String(localized: "Development automation is already in Assistant Queue.")
            todayCommandFeedback = nil
            return true
        } catch {
            _ = refreshAssistantQueueSnapshot()
            recordOperationFailure(AssistantQueueStoreError.userMessage(for: error))
            integrationStatusMessage = nil
            return false
        }
    }

    @discardableResult
    public func prepareDevelopmentRepositoryEditReview(
        for project: ProjectBoardProject,
        task: ProjectBoardTask?,
        operation: ProjectDevelopmentRepositoryEditOperation,
        relativePath: String,
        contents: String,
        expectedSHA256: String?
    ) -> ActionPlan? {
        let readiness = developmentAutomationReadiness(for: project, task: task)
        guard readiness.isReady,
              let task,
              let branchName = readiness.branchNamePreview else {
            developmentAutomationReviewPlan = nil
            todayCommandFeedback = readiness.blockingReason
            integrationStatusMessage = nil
            return nil
        }

        let progress = developmentAutomationProgress(for: project, task: task)
        guard progress.canQueueRepositoryEditReview else {
            developmentAutomationReviewPlan = nil
            todayCommandFeedback = progress.nextApproval?.detail
                ?? String(localized: "Prepare the development branch before queueing repository edits.")
            integrationStatusMessage = nil
            return nil
        }

        do {
            let reviewedRelativePath = try DevelopmentRepositoryFilePathPolicy.validatedRelativePath(relativePath)
            try DevelopmentRepositoryFilePathPolicy.validateTextContent(contents)
            let redactor = DeveloperSecretRedactor()
            guard !DevelopmentRepositoryIndex.containsRepositoryCredential(
                contents,
                relativePath: reviewedRelativePath,
                redactor: redactor
            ) else {
                throw DevelopmentRepositoryFileError.secretLikeContent(
                    redactor.redact(contents).report.matchedPatternNames
                )
            }

            var arguments: [String: JSONValue] = [
                "projectId": .number(Double(project.id)),
                "taskId": .number(Double(task.id)),
                "branchName": .string(branchName),
                "relativePath": .string(reviewedRelativePath),
                "contents": .string(contents)
            ]
            let reviewedExpectedSHA256 = expectedSHA256?.trimmingCharacters(in: .whitespacesAndNewlines)
            if operation == .update {
                guard let reviewedExpectedSHA256, !reviewedExpectedSHA256.isEmpty else {
                    developmentAutomationReviewPlan = nil
                    todayCommandFeedback = String(localized: "Review the repository edit before queueing verification.")
                    recordOperationFailure(String(localized: "Expected SHA is required before queueing a repository update."))
                    integrationStatusMessage = nil
                    return nil
                }
                arguments["expectedSHA256"] = .string(
                    try DevelopmentRepositoryFilePathPolicy.validatedExpectedSHA256(reviewedExpectedSHA256)
                )
            }

            let plan = ActionPlan(
                id: "development-repository-edit:\(project.id):\(task.id):\(Self.developmentRepositoryEditPlanDigest(projectID: project.id, taskID: task.id, branchName: branchName, operation: operation, relativePath: reviewedRelativePath, contents: contents, expectedSHA256: reviewedExpectedSHA256))",
                userInput: "Review repository \(operation.rawValue) for \(task.title).",
                summary: "Review \(operation.rawValue) for \(reviewedRelativePath) on branch \(branchName) before verification. File contents stay redacted in receipts.",
                actions: [
                    PlanAction(
                        id: "development-repository-edit",
                        tool: operation.tool,
                        arguments: arguments,
                        riskLevel: .write,
                        requiresUserConfirmation: true
                    )
                ],
                riskLevel: .write,
                requiresApproval: true
            )
            // This review captures the exact relative path and content intended for
            // the approved workspace. Execution still revalidates the bookmark and
            // path, so stale UI state cannot write outside the user-approved repo.
            developmentAutomationReviewPlan = plan
            integrationStatusMessage = String(localized: "Development repository edit review is prepared.")
            todayCommandFeedback = nil
            recordOperationFailure(nil)
            return plan
        } catch let error as DevelopmentRepositoryFileError {
            developmentAutomationReviewPlan = nil
            todayCommandFeedback = String(localized: "Review the repository edit before queueing verification.")
            recordOperationFailure(Self.sanitizedDevelopmentAutomationReviewText(error.userMessage))
            integrationStatusMessage = nil
            return nil
        } catch {
            developmentAutomationReviewPlan = nil
            todayCommandFeedback = String(localized: "Review the repository edit before queueing verification.")
            recordOperationFailure(Self.sanitizedDevelopmentAutomationReviewText(String(describing: error)))
            integrationStatusMessage = nil
            return nil
        }
    }

    public func developmentRepositoryEditPreview(
        for project: ProjectBoardProject,
        task: ProjectBoardTask?,
        operation: ProjectDevelopmentRepositoryEditOperation,
        relativePath: String,
        contents: String,
        expectedSHA256: String?
    ) -> ProjectDevelopmentAutomationApprovalPreview? {
        let readiness = developmentAutomationReadiness(for: project, task: task)
        guard readiness.isReady,
              let branchName = readiness.branchNamePreview else {
            return nil
        }

        do {
            let reviewedRelativePath = try DevelopmentRepositoryFilePathPolicy.validatedRelativePath(relativePath)
            try DevelopmentRepositoryFilePathPolicy.validateTextContent(contents)
            // Keep edit review aligned with repository indexing and direct reads:
            // shared redaction stays conservative, while safe Swift source shapes
            // are reopened only by the source-aware repository credential policy.
            guard !DevelopmentRepositoryIndex.containsRepositoryCredential(
                contents,
                relativePath: reviewedRelativePath,
                redactor: DeveloperSecretRedactor()
            ) else {
                return nil
            }

            var rows = [
                ProjectDevelopmentAutomationApprovalPreviewRow(
                    id: "operation",
                    label: String(localized: "Operation"),
                    value: operation.title
                ),
                ProjectDevelopmentAutomationApprovalPreviewRow(
                    id: "relative-path",
                    label: String(localized: "Relative Path"),
                    value: Self.sanitizedDevelopmentAutomationReviewText(reviewedRelativePath)
                ),
                ProjectDevelopmentAutomationApprovalPreviewRow(
                    id: "branch",
                    label: String(localized: "Branch"),
                    value: Self.sanitizedDevelopmentAutomationReviewText(branchName)
                ),
                ProjectDevelopmentAutomationApprovalPreviewRow(
                    id: "content-summary",
                    label: String(localized: "Content"),
                    value: Self.developmentRepositoryEditContentSummary(contents)
                ),
                ProjectDevelopmentAutomationApprovalPreviewRow(
                    id: "reviewed-change-scope",
                    label: String(localized: "Reviewed Change Scope"),
                    value: Self.developmentRepositoryEditReviewedLineSummary(contents)
                ),
                ProjectDevelopmentAutomationApprovalPreviewRow(
                    id: "reviewed-replacement",
                    label: String(localized: "Reviewed Replacement"),
                    value: Self.developmentRepositoryEditReviewedReplacementPreview(
                        operation: operation,
                        relativePath: reviewedRelativePath,
                        contents: contents
                    )
                ),
                ProjectDevelopmentAutomationApprovalPreviewRow(
                    id: "content-digest",
                    label: String(localized: "Content SHA-256"),
                    value: Self.developmentRepositoryEditContentDigest(contents)
                )
            ]

            if operation == .update {
                guard let reviewedExpectedSHA256 = expectedSHA256?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !reviewedExpectedSHA256.isEmpty else {
                    return nil
                }
                rows.append(ProjectDevelopmentAutomationApprovalPreviewRow(
                    id: "expected-sha",
                    label: String(localized: "Expected SHA"),
                    value: String(try DevelopmentRepositoryFilePathPolicy.validatedExpectedSHA256(reviewedExpectedSHA256).prefix(12))
                ))
            }

            // Review previews must help users distinguish edits without leaking the
            // content into receipt-like surfaces; the raw text remains only in the
            // dedicated editor until the user queues the approval-gated action.
            return ProjectDevelopmentAutomationApprovalPreview(
                title: String(localized: "Repository Edit Preview"),
                rows: rows
            )
        } catch {
            return nil
        }
    }

    @discardableResult
    public func enqueueDevelopmentRepositoryEditReview(
        for project: ProjectBoardProject,
        task: ProjectBoardTask?,
        operation: ProjectDevelopmentRepositoryEditOperation,
        relativePath: String,
        contents: String,
        expectedSHA256: String?
    ) -> Bool {
        guard let assistantQueueStore else {
            assistantQueueSnapshot = .empty
            assistantQueueSelectedItemIDs = []
            recordOperationFailure(String(localized: "Assistant Queue is unavailable in this build."))
            integrationStatusMessage = nil
            return false
        }
        guard var plan = prepareDevelopmentRepositoryEditReview(
            for: project,
            task: task,
            operation: operation,
            relativePath: relativePath,
            contents: contents,
            expectedSHA256: expectedSHA256
        ) else {
            return false
        }

        let validator = ActionPlanValidator()
        let validation = validator.validate(plan)
        guard validation.isValid else {
            recordOperationFailure(String(localized: "Development automation generated an invalid action plan."))
            integrationStatusMessage = nil
            return false
        }

        plan.userInput = Self.sanitizedDevelopmentAutomationReviewText(plan.userInput)
        plan.summary = Self.sanitizedDevelopmentAutomationReviewText(plan.summary)
        let persistedValidation = validator.validate(plan)
        guard persistedValidation.isValid else {
            recordOperationFailure(String(localized: "Development automation generated an invalid action plan."))
            integrationStatusMessage = nil
            return false
        }

        let item = AssistantQueueAdapter.makeItem(
            actionPlan: plan,
            sourceTranscript: plan.userInput,
            interpretationSummary: plan.summary,
            reason: Self.developmentRepositoryEditQueueReason(project: project),
            costPreview: .localOnly()
        )

        do {
            if try assistantQueueStore.insertIfAbsent(item) != nil {
                focusAssistantQueueItem(id: item.id)
                recordOperationFailure(nil)
                integrationStatusMessage = String(localized: "Queued development repository edit review for approval.")
                todayCommandFeedback = nil
                onChange()
                return true
            }

            focusAssistantQueueItem(id: item.id)
            recordOperationFailure(nil)
            integrationStatusMessage = String(localized: "Development repository edit review is already in Assistant Queue.")
            todayCommandFeedback = nil
            return true
        } catch {
            _ = refreshAssistantQueueSnapshot()
            recordOperationFailure(AssistantQueueStoreError.userMessage(for: error))
            integrationStatusMessage = nil
            return false
        }
    }

    @discardableResult
    public func prepareDevelopmentVerificationReview(
        for project: ProjectBoardProject,
        task: ProjectBoardTask?,
        commandID: String = "git.diff_check"
    ) -> ActionPlan? {
        let readiness = developmentAutomationReadiness(for: project, task: task)
        guard readiness.isReady,
              let task,
              let branchName = readiness.branchNamePreview else {
            developmentAutomationReviewPlan = nil
            todayCommandFeedback = readiness.blockingReason
            integrationStatusMessage = nil
            return nil
        }

        let progress = developmentAutomationProgress(for: project, task: task)
        guard progress.canQueueVerificationReview else {
            developmentAutomationReviewPlan = nil
            todayCommandFeedback = progress.nextApproval?.detail
                ?? String(localized: "Prepare the development branch before queueing verification.")
            integrationStatusMessage = nil
            return nil
        }

        do {
            let command = try DevelopmentVerificationCommandPolicy.validated(commandID: commandID)
            let plan = ActionPlan(
                id: "development-verification:\(project.id):\(task.id):\(Self.developmentVerificationPlanDigest(projectID: project.id, taskID: task.id, branchName: branchName, commandID: command.id))",
                userInput: "Review local verification \(command.commandDisplay) for \(task.title).",
                summary: "Run \(command.commandDisplay) inside approved branch \(branchName) before commit, push, or pull request creation.",
                actions: [
                    PlanAction(
                        id: "development-verification",
                        tool: .developmentRunVerification,
                        arguments: [
                            "projectId": .number(Double(project.id)),
                            "taskId": .number(Double(task.id)),
                            "branchName": .string(branchName),
                            "commandId": .string(command.id)
                        ],
                        riskLevel: .write,
                        requiresUserConfirmation: true
                    )
                ],
                riskLevel: .write,
                requiresApproval: true
            )
            // Carry branchName in the reviewed arguments even though the tool only
            // executes projectId/commandId; receipts use it to resume the flow after relaunch.
            developmentAutomationReviewPlan = plan
            integrationStatusMessage = String(localized: "Development verification review is prepared.")
            todayCommandFeedback = nil
            recordOperationFailure(nil)
            return plan
        } catch let error as DevelopmentVerificationCommandError {
            developmentAutomationReviewPlan = nil
            todayCommandFeedback = String(localized: "Choose an approved verification command before queueing.")
            recordOperationFailure(Self.sanitizedDevelopmentAutomationReviewText(error.userMessage))
            integrationStatusMessage = nil
            return nil
        } catch {
            developmentAutomationReviewPlan = nil
            todayCommandFeedback = String(localized: "Choose an approved verification command before queueing.")
            recordOperationFailure(Self.sanitizedDevelopmentAutomationReviewText(String(describing: error)))
            integrationStatusMessage = nil
            return nil
        }
    }

    @discardableResult
    public func enqueueDevelopmentVerificationReview(
        for project: ProjectBoardProject,
        task: ProjectBoardTask?,
        commandID: String = "git.diff_check"
    ) -> Bool {
        guard let assistantQueueStore else {
            assistantQueueSnapshot = .empty
            assistantQueueSelectedItemIDs = []
            recordOperationFailure(String(localized: "Assistant Queue is unavailable in this build."))
            integrationStatusMessage = nil
            return false
        }
        guard var plan = prepareDevelopmentVerificationReview(for: project, task: task, commandID: commandID) else {
            return false
        }

        let validator = ActionPlanValidator()
        let validation = validator.validate(plan)
        guard validation.isValid else {
            recordOperationFailure(String(localized: "Development automation generated an invalid action plan."))
            integrationStatusMessage = nil
            return false
        }

        plan.userInput = Self.sanitizedDevelopmentAutomationReviewText(plan.userInput)
        plan.summary = Self.sanitizedDevelopmentAutomationReviewText(plan.summary)
        let persistedValidation = validator.validate(plan)
        guard persistedValidation.isValid else {
            recordOperationFailure(String(localized: "Development automation generated an invalid action plan."))
            integrationStatusMessage = nil
            return false
        }

        let item = AssistantQueueAdapter.makeItem(
            actionPlan: plan,
            sourceTranscript: plan.userInput,
            interpretationSummary: plan.summary,
            reason: Self.developmentVerificationQueueReason(project: project),
            costPreview: .localOnly()
        )

        do {
            if try assistantQueueStore.insertIfAbsent(item) != nil {
                focusAssistantQueueItem(id: item.id)
                recordOperationFailure(nil)
                integrationStatusMessage = String(localized: "Queued development verification review for approval.")
                todayCommandFeedback = nil
                onChange()
                return true
            }

            focusAssistantQueueItem(id: item.id)
            recordOperationFailure(nil)
            integrationStatusMessage = String(localized: "Development verification review is already in Assistant Queue.")
            todayCommandFeedback = nil
            return true
        } catch {
            _ = refreshAssistantQueueSnapshot()
            recordOperationFailure(AssistantQueueStoreError.userMessage(for: error))
            integrationStatusMessage = nil
            return false
        }
    }

    @discardableResult
    public func prepareDevelopmentCommitReview(
        for project: ProjectBoardProject,
        task: ProjectBoardTask?,
        relativePathsText: String,
        commitMessage: String
    ) -> ActionPlan? {
        let readiness = developmentAutomationReadiness(for: project, task: task)
        guard readiness.isReady,
              let task,
              let branchName = readiness.branchNamePreview else {
            developmentAutomationReviewPlan = nil
            todayCommandFeedback = readiness.blockingReason
            integrationStatusMessage = nil
            return nil
        }

        let progress = developmentAutomationProgress(for: project, task: task)
        guard progress.canQueueCommitReview else {
            developmentAutomationReviewPlan = nil
            todayCommandFeedback = progress.nextApproval?.detail
                ?? String(localized: "Run verification before queueing the commit review.")
            integrationStatusMessage = nil
            return nil
        }

        do {
            let relativePaths = try Self.validatedDevelopmentCommitRelativePaths(from: relativePathsText)
            let reviewedCommitMessage = try DevelopmentCommitGitCommandPolicy.validatedCommitMessage(
                commitMessage,
                redactor: DeveloperSecretRedactor()
            )
            let plan = ActionPlan(
                id: "development-commit:\(project.id):\(task.id):\(Self.developmentCommitPlanDigest(projectID: project.id, taskID: task.id, branchName: branchName, relativePaths: relativePaths, commitMessage: reviewedCommitMessage))",
                userInput: "Review local commit for \(task.title).",
                summary: "Commit \(relativePaths.joined(separator: ", ")) on branch \(branchName) after verification evidence. Push and pull request creation remain separate approvals.",
                actions: [
                    PlanAction(
                        id: "development-commit",
                        tool: .developmentCommitChanges,
                        arguments: [
                            "projectId": .number(Double(project.id)),
                            "taskId": .number(Double(task.id)),
                            "branchName": .string(branchName),
                            "relativePaths": JSONValueFactory.strings(relativePaths),
                            "commitMessage": .string(reviewedCommitMessage)
                        ],
                        riskLevel: .write,
                        requiresUserConfirmation: true
                    )
                ],
                riskLevel: .write,
                requiresApproval: true
            )
            // The commit gate records exactly the reviewed file list. The tool
            // re-reads each file and stages only this list so unrelated user edits
            // cannot be swept into the local commit.
            developmentAutomationReviewPlan = plan
            integrationStatusMessage = String(localized: "Development commit review is prepared.")
            todayCommandFeedback = nil
            recordOperationFailure(nil)
            return plan
        } catch let error as DevelopmentRepositoryFileError {
            developmentAutomationReviewPlan = nil
            todayCommandFeedback = String(localized: "Review the commit file paths before queueing.")
            recordOperationFailure(Self.sanitizedDevelopmentAutomationReviewText(error.userMessage))
            integrationStatusMessage = nil
            return nil
        } catch let error as DevelopmentCommitWorkflowError {
            developmentAutomationReviewPlan = nil
            todayCommandFeedback = String(localized: "Review the commit message and file paths before queueing.")
            recordOperationFailure(Self.sanitizedDevelopmentAutomationReviewText(error.userMessage))
            integrationStatusMessage = nil
            return nil
        } catch {
            developmentAutomationReviewPlan = nil
            todayCommandFeedback = String(localized: "Review the commit message and file paths before queueing.")
            recordOperationFailure(Self.sanitizedDevelopmentAutomationReviewText(String(describing: error)))
            integrationStatusMessage = nil
            return nil
        }
    }

    @discardableResult
    public func enqueueDevelopmentCommitReview(
        for project: ProjectBoardProject,
        task: ProjectBoardTask?,
        relativePathsText: String,
        commitMessage: String
    ) -> Bool {
        guard let assistantQueueStore else {
            assistantQueueSnapshot = .empty
            assistantQueueSelectedItemIDs = []
            recordOperationFailure(String(localized: "Assistant Queue is unavailable in this build."))
            integrationStatusMessage = nil
            return false
        }
        guard var plan = prepareDevelopmentCommitReview(
            for: project,
            task: task,
            relativePathsText: relativePathsText,
            commitMessage: commitMessage
        ) else {
            return false
        }

        let validator = ActionPlanValidator()
        let validation = validator.validate(plan)
        guard validation.isValid else {
            recordOperationFailure(String(localized: "Development automation generated an invalid action plan."))
            integrationStatusMessage = nil
            return false
        }

        plan.userInput = Self.sanitizedDevelopmentAutomationReviewText(plan.userInput)
        plan.summary = Self.sanitizedDevelopmentAutomationReviewText(plan.summary)
        let persistedValidation = validator.validate(plan)
        guard persistedValidation.isValid else {
            recordOperationFailure(String(localized: "Development automation generated an invalid action plan."))
            integrationStatusMessage = nil
            return false
        }

        let item = AssistantQueueAdapter.makeItem(
            actionPlan: plan,
            sourceTranscript: plan.userInput,
            interpretationSummary: plan.summary,
            reason: Self.developmentCommitQueueReason(project: project),
            costPreview: .localOnly()
        )

        do {
            if try assistantQueueStore.insertIfAbsent(item) != nil {
                focusAssistantQueueItem(id: item.id)
                recordOperationFailure(nil)
                integrationStatusMessage = String(localized: "Queued development commit review for approval.")
                todayCommandFeedback = nil
                onChange()
                return true
            }

            focusAssistantQueueItem(id: item.id)
            recordOperationFailure(nil)
            integrationStatusMessage = String(localized: "Development commit review is already in Assistant Queue.")
            todayCommandFeedback = nil
            return true
        } catch {
            _ = refreshAssistantQueueSnapshot()
            recordOperationFailure(AssistantQueueStoreError.userMessage(for: error))
            integrationStatusMessage = nil
            return false
        }
    }

    @discardableResult
    public func prepareDevelopmentPushReview(
        for project: ProjectBoardProject,
        task: ProjectBoardTask?
    ) -> ActionPlan? {
        let readiness = developmentAutomationReadiness(for: project, task: task)
        guard readiness.isReady,
              let task,
              let branchName = readiness.branchNamePreview else {
            developmentAutomationReviewPlan = nil
            todayCommandFeedback = readiness.blockingReason
            integrationStatusMessage = nil
            return nil
        }

        let progress = developmentAutomationProgress(for: project, task: task)
        guard progress.canQueueBranchPushReview,
              let expectedHeadOID = progress.latestCommitOID else {
            developmentAutomationReviewPlan = nil
            todayCommandFeedback = progress.nextApproval?.detail
                ?? String(localized: "Create the local commit before queueing the branch push.")
            integrationStatusMessage = nil
            return nil
        }

        let plan = ActionPlan(
            id: "development-pr-push:\(project.id):\(task.id):\(Self.developmentAutomationPlanDigest(projectID: project.id, taskID: task.id, branchName: "\(branchName):\(expectedHeadOID)"))",
            userInput: "Review development branch push \(branchName) for \(task.title).",
            summary: "Review branch \(branchName) push to origin for \(task.title). Execution rechecks the current branch, reviewed commit, clean workspace, and GitHub origin before push. Pull request creation requires a separate approval.",
            actions: [
                PlanAction(
                    id: "development-pr-push",
                    tool: .developmentPushBranch,
                    arguments: [
                        "projectId": .number(Double(project.id)),
                        "taskId": .number(Double(task.id)),
                        "branchName": .string(branchName),
                        "expectedHeadOID": .string(expectedHeadOID)
                    ],
                    riskLevel: .write,
                    requiresUserConfirmation: true
                )
            ],
            riskLevel: .write,
            requiresApproval: true
        )
        // Keep push separate from PR creation so a queued publish step cannot
        // silently escalate into a second external write after the user reviews
        // only the branch push boundary.
        developmentAutomationReviewPlan = plan
        integrationStatusMessage = "Development branch push review is prepared."
        todayCommandFeedback = nil
        recordOperationFailure(nil)
        return plan
    }

    @discardableResult
    public func enqueueDevelopmentPushReview(
        for project: ProjectBoardProject,
        task: ProjectBoardTask?
    ) -> Bool {
        guard let assistantQueueStore else {
            assistantQueueSnapshot = .empty
            assistantQueueSelectedItemIDs = []
            recordOperationFailure(String(localized: "Assistant Queue is unavailable in this build."))
            integrationStatusMessage = nil
            return false
        }
        guard var plan = prepareDevelopmentPushReview(for: project, task: task) else {
            return false
        }

        let validator = ActionPlanValidator()
        let validation = validator.validate(plan)
        guard validation.isValid else {
            recordOperationFailure(String(localized: "Development automation generated an invalid action plan."))
            integrationStatusMessage = nil
            return false
        }

        plan.userInput = Self.sanitizedDevelopmentAutomationReviewText(plan.userInput)
        plan.summary = Self.sanitizedDevelopmentAutomationReviewText(plan.summary)
        let persistedValidation = validator.validate(plan)
        guard persistedValidation.isValid else {
            recordOperationFailure(String(localized: "Development automation generated an invalid action plan."))
            integrationStatusMessage = nil
            return false
        }

        let item = AssistantQueueAdapter.makeItem(
            actionPlan: plan,
            sourceTranscript: plan.userInput,
            interpretationSummary: plan.summary,
            reason: Self.developmentAutomationPushQueueReason(project: project),
            costPreview: .localOnly()
        )

        do {
            if try assistantQueueStore.insertIfAbsent(item) != nil {
                focusAssistantQueueItem(id: item.id)
                recordOperationFailure(nil)
                integrationStatusMessage = String(localized: "Queued development branch push review for approval.")
                todayCommandFeedback = nil
                onChange()
                return true
            }

            focusAssistantQueueItem(id: item.id)
            recordOperationFailure(nil)
            integrationStatusMessage = String(localized: "Development branch push review is already in Assistant Queue.")
            todayCommandFeedback = nil
            return true
        } catch {
            _ = refreshAssistantQueueSnapshot()
            recordOperationFailure(AssistantQueueStoreError.userMessage(for: error))
            integrationStatusMessage = nil
            return false
        }
    }

    public func developmentPullRequestCreationDraft(
        for project: ProjectBoardProject,
        task: ProjectBoardTask?
    ) -> ProjectDevelopmentPullRequestCreationDraft? {
        let readiness = developmentAutomationReadiness(for: project, task: task)
        guard readiness.isReady,
              let task,
              let branchName = readiness.branchNamePreview else {
            return nil
        }

        let baseBranch = Self.defaultDevelopmentPullRequestBaseBranch
        return ProjectDevelopmentPullRequestCreationDraft(
            projectID: project.id,
            taskID: task.id,
            branchName: branchName,
            baseBranch: baseBranch,
            title: Self.developmentPullRequestTitle(project: project, task: task),
            body: Self.developmentPullRequestBody(
                project: project,
                task: task,
                branchName: branchName,
                baseBranch: baseBranch
            )
        )
    }

    @discardableResult
    public func prepareDevelopmentPullRequestCreationReview(
        for project: ProjectBoardProject,
        task: ProjectBoardTask?,
        baseBranch: String? = nil,
        title: String? = nil,
        body: String? = nil
    ) -> ActionPlan? {
        guard let draft = developmentPullRequestCreationDraft(for: project, task: task) else {
            let readiness = developmentAutomationReadiness(for: project, task: task)
            developmentAutomationReviewPlan = nil
            todayCommandFeedback = readiness.blockingReason
            integrationStatusMessage = nil
            return nil
        }

        let progress = developmentAutomationProgress(for: project, task: task)
        guard progress.canQueuePullRequestCreationReview,
              let expectedHeadOID = progress.latestCommitOID else {
            developmentAutomationReviewPlan = nil
            todayCommandFeedback = progress.nextApproval?.detail
                ?? String(localized: "Push the branch before queueing pull request creation.")
            integrationStatusMessage = nil
            return nil
        }

        do {
            let reviewedBaseBranch = try DevelopmentBranchNamePolicy.validated(
                (baseBranch ?? draft.baseBranch).trimmingCharacters(in: .whitespacesAndNewlines)
            )
            try DevelopmentGitHubPRCommandPolicy.validateBaseAndHead(
                baseBranch: reviewedBaseBranch,
                headBranch: draft.branchName
            )
            let reviewedTitle = try DevelopmentGitHubPRCommandPolicy.validatedPullRequestTitle(
                title ?? draft.title,
                redactor: DeveloperSecretRedactor()
            )
            let reviewedBody = try DevelopmentGitHubPRCommandPolicy.validatedPullRequestBody(
                body ?? draft.body,
                redactor: DeveloperSecretRedactor()
            )
            let reviewedExpectedHeadOID = try DevelopmentGitHubPRCommandPolicy.validatedHeadCommitOID(expectedHeadOID)

            let plan = ActionPlan(
                id: "development-pr-create:\(project.id):\(draft.taskID):\(Self.developmentPullRequestCreationPlanDigest(projectID: project.id, taskID: draft.taskID, branchName: draft.branchName, expectedHeadOID: reviewedExpectedHeadOID, baseBranch: reviewedBaseBranch, title: reviewedTitle, body: reviewedBody))",
                userInput: "Create a GitHub pull request for \(draft.branchName) after reviewing base branch, title, and body.",
                summary: "Create pull request from \(draft.branchName) at reviewed commit \(reviewedExpectedHeadOID) into \(reviewedBaseBranch). Base branch \(reviewedBaseBranch), title and body were reviewed before queueing. Execution rechecks the current branch, reviewed commit, clean workspace, and GitHub origin before creating the pull request.",
                actions: [
                    PlanAction(
                        id: "development-pr-create",
                        tool: .developmentCreatePullRequest,
                        arguments: [
                            "projectId": .number(Double(project.id)),
                            "taskId": .number(Double(draft.taskID)),
                            "branchName": .string(draft.branchName),
                            "expectedHeadOID": .string(reviewedExpectedHeadOID),
                            "baseBranch": .string(reviewedBaseBranch),
                            "title": .string(reviewedTitle),
                            "body": .string(reviewedBody)
                        ],
                        riskLevel: .write,
                        requiresUserConfirmation: true
                    )
                ],
                riskLevel: .write,
                requiresApproval: true
            )
            // PR creation is a second external write after push. Keeping a distinct
            // plan ID prevents an approved push queue item from being reused to create
            // a GitHub pull request with unreviewed base/title/body fields.
            developmentAutomationReviewPlan = plan
            integrationStatusMessage = String(localized: "Development pull request creation review is prepared.")
            todayCommandFeedback = nil
            recordOperationFailure(nil)
            return plan
        } catch let error as DevelopmentPRPublishWorkflowError {
            developmentAutomationReviewPlan = nil
            todayCommandFeedback = String(localized: "Review the pull request base branch, title, and body before queueing.")
            recordOperationFailure(Self.sanitizedDevelopmentAutomationReviewText(error.userMessage))
            integrationStatusMessage = nil
            return nil
        } catch {
            developmentAutomationReviewPlan = nil
            todayCommandFeedback = String(localized: "Review the pull request base branch, title, and body before queueing.")
            recordOperationFailure(Self.sanitizedDevelopmentAutomationReviewText(String(describing: error)))
            integrationStatusMessage = nil
            return nil
        }
    }

    @discardableResult
    public func enqueueDevelopmentPullRequestCreationReview(
        for project: ProjectBoardProject,
        task: ProjectBoardTask?,
        baseBranch: String? = nil,
        title: String? = nil,
        body: String? = nil
    ) -> Bool {
        guard let assistantQueueStore else {
            assistantQueueSnapshot = .empty
            assistantQueueSelectedItemIDs = []
            recordOperationFailure(String(localized: "Assistant Queue is unavailable in this build."))
            integrationStatusMessage = nil
            return false
        }
        guard var plan = prepareDevelopmentPullRequestCreationReview(
            for: project,
            task: task,
            baseBranch: baseBranch,
            title: title,
            body: body
        ) else {
            return false
        }

        let validator = ActionPlanValidator()
        let validation = validator.validate(plan)
        guard validation.isValid else {
            recordOperationFailure(String(localized: "Development automation generated an invalid action plan."))
            integrationStatusMessage = nil
            return false
        }

        plan.userInput = Self.sanitizedDevelopmentAutomationReviewText(plan.userInput)
        plan.summary = Self.sanitizedDevelopmentAutomationReviewText(plan.summary)
        let persistedValidation = validator.validate(plan)
        guard persistedValidation.isValid else {
            recordOperationFailure(String(localized: "Development automation generated an invalid action plan."))
            integrationStatusMessage = nil
            return false
        }

        let item = AssistantQueueAdapter.makeItem(
            actionPlan: plan,
            sourceTranscript: plan.userInput,
            interpretationSummary: plan.summary,
            reason: Self.developmentPullRequestCreationQueueReason(project: project),
            costPreview: .localOnly()
        )

        do {
            if try assistantQueueStore.insertIfAbsent(item) != nil {
                focusAssistantQueueItem(id: item.id)
                recordOperationFailure(nil)
                integrationStatusMessage = String(localized: "Queued development pull request creation review for approval.")
                todayCommandFeedback = nil
                onChange()
                return true
            }

            focusAssistantQueueItem(id: item.id)
            recordOperationFailure(nil)
            integrationStatusMessage = String(localized: "Development pull request creation review is already in Assistant Queue.")
            todayCommandFeedback = nil
            return true
        } catch {
            _ = refreshAssistantQueueSnapshot()
            recordOperationFailure(AssistantQueueStoreError.userMessage(for: error))
            integrationStatusMessage = nil
            return false
        }
    }

    public func developmentAutomationProgress(
        for project: ProjectBoardProject,
        task: ProjectBoardTask?
    ) -> ProjectDevelopmentAutomationProgress {
        let readiness = developmentAutomationReadiness(for: project, task: task)
        guard readiness.isReady,
              let branchName = readiness.branchNamePreview else {
            return Self.developmentAutomationProgress(
                projectID: project.id,
                taskID: task?.id,
                branchName: readiness.branchNamePreview,
                receipts: [],
                queueHandoff: nil,
                blockingReason: readiness.blockingReason
            )
        }

        guard let executionReceiptStore else {
            return Self.developmentAutomationProgress(
                projectID: project.id,
                taskID: task?.id,
                branchName: branchName,
                receipts: [],
                queueHandoff: developmentAutomationQueueHandoff(
                    projectID: project.id,
                    taskID: task?.id,
                    branchName: branchName,
                    receipts: []
                ),
                blockingReason: String(localized: "Execution receipts are unavailable, so Suisui cannot confirm which development approval comes next.")
            )
        }

        do {
            let receipts = try executionReceiptStore.list(
                matching: ExecutionReceiptSearchFilter(
                    toolNames: Set(Self.developmentAutomationLifecycleToolNames),
                    visibleSurface: .projectDetail
                ),
                limit: 500
            ).filter { receipt in
                Self.developmentAutomationReceiptMatches(
                    receipt,
                    projectID: project.id,
                    branchName: branchName
                )
            }

            return Self.developmentAutomationProgress(
                projectID: project.id,
                taskID: task?.id,
                branchName: branchName,
                receipts: receipts,
                queueHandoff: developmentAutomationQueueHandoff(
                    projectID: project.id,
                    taskID: task?.id,
                    branchName: branchName,
                    receipts: receipts
                ),
                blockingReason: nil
            )
        } catch {
            return Self.developmentAutomationProgress(
                projectID: project.id,
                taskID: task?.id,
                branchName: branchName,
                receipts: [],
                queueHandoff: developmentAutomationQueueHandoff(
                    projectID: project.id,
                    taskID: task?.id,
                    branchName: branchName,
                    receipts: []
                ),
                blockingReason: String(localized: "Execution receipts could not be read, so Suisui cannot confirm which development approval comes next.")
            )
        }
    }

    func developmentAutomationQueueHandoff(
        projectID: Int64,
        taskID: Int64?,
        branchName: String,
        receipts: [ExecutionReceipt]
    ) -> ProjectDevelopmentAutomationQueueHandoff? {
        guard let assistantQueueStore else {
            return nil
        }

        do {
            let expectedToolNames = Self.developmentAutomationExpectedQueueToolNames(receipts: receipts)
            guard !expectedToolNames.isEmpty else {
                return nil
            }
            let matchingItems = try assistantQueueStore.list(filter: .all(limit: 500)).filter { item in
                Self.isDevelopmentAutomationQueueHandoffState(item.state)
                    && Self.developmentAutomationQueueItemMatches(
                        item,
                        projectID: projectID,
                        taskID: taskID,
                        branchName: branchName,
                        expectedToolNames: expectedToolNames
                    )
            }
            guard !matchingItems.isEmpty else {
                return nil
            }

            // Keep the project panel as a projection of Assistant Queue state.
            // The queue row remains the review surface of record, while this
            // handoff prevents users from losing the pending approval in project context.
            let snapshot = AssistantQueueReadModel.snapshot(
                from: matchingItems,
                receipts: receipts,
                viewFilter: .all,
                sort: .needsActionFirst,
                allItemsForCounts: matchingItems
            )
            let selectedRow = snapshot.rows.first { row in
                assistantQueueSelectedItemIDs.contains(row.id)
            }
            return (selectedRow ?? snapshot.rows.first).map(Self.developmentAutomationQueueHandoff)
        } catch {
            return nil
        }
    }

    @discardableResult
    public func enqueueDevelopmentPullRequestLifecycleReview(
        for project: ProjectBoardProject,
        task: ProjectBoardTask?,
        operation: SyncDevelopmentPullRequestOperation
    ) -> Bool {
        guard let assistantQueueStore else {
            assistantQueueSnapshot = .empty
            assistantQueueSelectedItemIDs = []
            recordOperationFailure(String(localized: "Assistant Queue is unavailable in this build."))
            integrationStatusMessage = nil
            return false
        }

        let readiness = developmentAutomationReadiness(for: project, task: task)
        guard readiness.isReady,
              let task,
              task.projectID == project.id else {
            developmentAutomationReviewPlan = nil
            todayCommandFeedback = readiness.blockingReason
            integrationStatusMessage = nil
            return false
        }

        let progress = developmentAutomationProgress(for: project, task: task)
        let canQueue = operation == .reviewGate
            ? progress.canQueuePullRequestReviewGate
            : progress.canQueuePullRequestMergeGate
        guard canQueue,
              let rawPullRequestURL = progress.pullRequestURL,
              let rawBranchName = progress.branchName,
              let rawBaseBranch = progress.baseBranch else {
            developmentAutomationReviewPlan = nil
            todayCommandFeedback = progress.blockingReason
                ?? Self.developmentPullRequestLifecycleMissingEvidenceMessage(for: operation)
            integrationStatusMessage = nil
            return false
        }

        do {
            let redactor = DeveloperSecretRedactor()
            let pullRequestURL = try DevelopmentGitHubPRCommandPolicy.validatedPullRequestURL(
                rawPullRequestURL.trimmingCharacters(in: .whitespacesAndNewlines),
                redactor: redactor
            )
            let branchName = try DevelopmentPublishGitCommandPolicy.validatedPublishHeadBranch(
                rawBranchName.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            let baseBranch = try DevelopmentBranchNamePolicy.validated(
                rawBaseBranch.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            try DevelopmentGitHubPRCommandPolicy.validateBaseAndHead(
                baseBranch: baseBranch,
                headBranch: branchName
            )

            let request = SyncAutomationRequestPayload(
                id: Self.developmentPullRequestLifecycleRequestID(
                    projectID: project.id,
                    taskID: task.id,
                    operation: operation,
                    pullRequestURL: pullRequestURL,
                    branchName: branchName,
                    baseBranch: baseBranch
                ),
                source: .localDatabase,
                approvalState: .pendingApproval,
                sourceClientID: "project-board",
                toolName: Self.developmentPullRequestLifecycleToolName(for: operation),
                redactedArgumentSummary: Self.developmentPullRequestLifecycleSummary(
                    operation: operation,
                    pullRequestURL: pullRequestURL,
                    branchName: branchName,
                    baseBranch: baseBranch
                ),
                developmentPullRequest: SyncDevelopmentPullRequestPayload(
                    projectID: project.id,
                    taskID: task.id,
                    operation: operation,
                    pullRequestURL: pullRequestURL,
                    branchName: branchName,
                    baseBranch: baseBranch
                )
            )

            var item = AssistantQueueAdapter.makeItem(automationRequest: request)
            item.reviewReason = Self.developmentPullRequestLifecycleQueueReason(
                project: project,
                operation: operation
            )

            do {
                if try assistantQueueStore.insertIfAbsent(item) != nil {
                    focusAssistantQueueItem(id: item.id)
                    recordOperationFailure(nil)
                    integrationStatusMessage = Self.developmentPullRequestLifecycleQueuedMessage(for: operation)
                    todayCommandFeedback = nil
                    onChange()
                    return true
                }

                focusAssistantQueueItem(id: item.id)
                recordOperationFailure(nil)
                integrationStatusMessage = Self.developmentPullRequestLifecycleAlreadyQueuedMessage(for: operation)
                todayCommandFeedback = nil
                return true
            } catch {
                _ = refreshAssistantQueueSnapshot()
                recordOperationFailure(AssistantQueueStoreError.userMessage(for: error))
                integrationStatusMessage = nil
                return false
            }
        } catch let error as DevelopmentPRPublishWorkflowError {
            developmentAutomationReviewPlan = nil
            todayCommandFeedback = String(localized: "Review the pull request execution receipt before queueing.")
            recordOperationFailure(Self.sanitizedDevelopmentAutomationReviewText(error.userMessage))
            integrationStatusMessage = nil
            return false
        } catch let error as DevelopmentPRWorkflowError {
            developmentAutomationReviewPlan = nil
            todayCommandFeedback = String(localized: "Review the pull request execution receipt before queueing.")
            recordOperationFailure(Self.sanitizedDevelopmentAutomationReviewText(error.userMessage))
            integrationStatusMessage = nil
            return false
        } catch {
            developmentAutomationReviewPlan = nil
            todayCommandFeedback = String(localized: "Review the pull request execution receipt before queueing.")
            recordOperationFailure(Self.sanitizedDevelopmentAutomationReviewText(String(describing: error)))
            integrationStatusMessage = nil
            return false
        }
    }
}
