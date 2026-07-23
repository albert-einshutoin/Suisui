import Foundation
import SuisuiCore

#if DEBUG
private struct RuntimeDevelopmentPRSmokeBookmarkResolver: ProjectWorkspaceBookmarkResolving {
    static let flagName = "SUISUI_RUNTIME_DEVELOPMENT_PR_SMOKE_BOOKMARK"
    static let markerPrefix = "suisui-runtime-development-pr-smoke:"

    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment[flagName] == "1"
    }

    func resolve(bookmarkData: Data) throws -> ProjectWorkspaceBookmarkResolution {
        if Self.isEnabled,
           let marker = String(data: bookmarkData, encoding: .utf8),
           marker.hasPrefix(Self.markerPrefix) {
            let path = String(marker.dropFirst(Self.markerPrefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard path.hasPrefix("/") else {
                throw DevelopmentPRWorkflowError.projectWorkspaceMustBeAbsolute
            }

            // Runtime UI smoke is launched from a shell-owned workspace, which cannot mint a
            // user-approved app-owned security scoped bookmark. This DEBUG-only
            // marker resolver preserves the production invariant that a bookmark field must
            // exist, while keeping release builds on the real security-scoped resolver.
            return ProjectWorkspaceBookmarkResolution(
                url: URL(fileURLWithPath: path, isDirectory: true).resolvingSymlinksInPath().standardizedFileURL,
                isStale: false,
                didStartAccessing: true,
                stopAccessing: {}
            )
        }

        // When the smoke drives the real NSOpenPanel path, the app stores a real
        // bookmark. Falling through keeps that production path under the same
        // execution resolver instead of accepting only the encoded smoke prefix.
        return try SecurityScopedProjectWorkspaceBookmarkResolver().resolve(bookmarkData: bookmarkData)
    }
}
#endif

extension AppRuntimeFactory {
    static func makeRuntimeToolRegistry(
        connection: SQLiteConnection,
        auditLogger: any AuditLogger
    ) throws -> ToolRegistry {
        let projectStore = SQLiteProjectStore(connection: connection)
        let taskStore = SQLiteTaskStore(connection: connection)
        let artifactStore = SQLiteArtifactStore(connection: connection)
        let sideEffectJournal = SQLiteExternalSideEffectJournal(connection: connection)
        try sideEffectJournal.recoverStartedAsUnknown(at: Date())
        let registry = try ToolRegistry.phase2MVP(
            projectStore: projectStore,
            taskStore: taskStore,
            knowledgeStore: SQLiteKnowledgeFrameStore(connection: connection),
            notificationClient: UserNotificationsNotificationClient(),
            calendarClient: EventKitCalendarClient(),
            reminderClient: EventKitReminderClient(),
            fileAccessClient: LocalFileAccessClient(workspaceRoot: try workspaceRootURL()),
            mailDraftClient: try makeMailDraftClient(),
            notificationRequestStore: SQLiteNotificationRequestStore(connection: connection),
            calendarLinkStore: SQLiteCalendarLinkStore(connection: connection),
            reminderLinkStore: SQLiteReminderLinkStore(connection: connection),
            artifactStore: artifactStore,
            sideEffectJournal: sideEffectJournal,
            auditLogger: auditLogger
        )
        // Queue execution bridges project-panel approvals to local GitHub Flow
        // tools only after each external write has its own reviewed ActionPlan.
        // Remote/cloud requests still enter as blocked review items instead of
        // reaching this local project-directory registry directly.
        let developmentBookmarkResolver = makeDevelopmentWorkspaceBookmarkResolver()
        try registry.register(AuditedTool(
            base: DevelopmentPRWorkflowTool(
                projectStore: projectStore,
                taskStore: taskStore,
                bookmarkResolver: developmentBookmarkResolver,
                requireBookmark: true
            ),
            logger: auditLogger
        ))
        try registry.register(AuditedTool(
            base: DevelopmentRepositoryFileTool(
                name: .developmentRepositoryListFiles,
                projectStore: projectStore,
                artifactStore: artifactStore,
                bookmarkResolver: developmentBookmarkResolver,
                requireBookmark: true
            ),
            logger: auditLogger
        ))
        try registry.register(AuditedTool(
            base: DevelopmentRepositoryFileTool(
                name: .developmentRepositoryReadFile,
                projectStore: projectStore,
                artifactStore: artifactStore,
                bookmarkResolver: developmentBookmarkResolver,
                requireBookmark: true
            ),
            logger: auditLogger
        ))
        try registry.register(AuditedTool(
            base: DevelopmentRepositoryFileTool(
                name: .developmentRepositoryCreateFile,
                projectStore: projectStore,
                artifactStore: artifactStore,
                bookmarkResolver: developmentBookmarkResolver,
                requireBookmark: true
            ),
            logger: auditLogger
        ))
        try registry.register(AuditedTool(
            base: DevelopmentRepositoryFileTool(
                name: .developmentRepositoryUpdateFile,
                projectStore: projectStore,
                artifactStore: artifactStore,
                bookmarkResolver: developmentBookmarkResolver,
                requireBookmark: true
            ),
            logger: auditLogger
        ))
        try registry.register(AuditedTool(
            base: DevelopmentVerificationCommandTool(
                projectStore: projectStore,
                bookmarkResolver: developmentBookmarkResolver,
                requireBookmark: true
            ),
            logger: auditLogger
        ))
        try registry.register(AuditedTool(
            base: DevelopmentCommitWorkflowTool(
                projectStore: projectStore,
                bookmarkResolver: developmentBookmarkResolver,
                requireBookmark: true
            ),
            logger: auditLogger
        ))
        try registry.register(AuditedTool(
            base: DevelopmentPushWorkflowTool(
                projectStore: projectStore,
                bookmarkResolver: developmentBookmarkResolver
            ),
            logger: auditLogger
        ))
        try registry.register(AuditedTool(
            base: DevelopmentPullRequestCreationTool(
                projectStore: projectStore,
                bookmarkResolver: developmentBookmarkResolver
            ),
            logger: auditLogger
        ))
        try registry.register(AuditedTool(
            base: DevelopmentPullRequestReviewGateTool(
                projectStore: projectStore,
                bookmarkResolver: developmentBookmarkResolver
            ),
            logger: auditLogger
        ))
        try registry.register(AuditedTool(
            base: DevelopmentPullRequestMergeTool(
                projectStore: projectStore,
                bookmarkResolver: developmentBookmarkResolver
            ),
            logger: auditLogger
        ))
        for requiredTool in [
            ActionTool.developmentPreparePullRequestWorkflow,
            .developmentRepositoryListFiles,
            .developmentRepositoryReadFile,
            .developmentRepositoryCreateFile,
            .developmentRepositoryUpdateFile,
            .developmentRunVerification,
            .developmentCommitChanges,
            .developmentPushBranch,
            .developmentCreatePullRequest,
            .developmentReviewPullRequestGate,
            .developmentMergePullRequest
        ] {
            guard registry.contains(requiredTool) else {
                throw ToolExecutionError.unknownTool(requiredTool)
            }
        }
        return registry
    }

    static func makeDevelopmentWorkspaceBookmarkResolver() -> any ProjectWorkspaceBookmarkResolving {
#if DEBUG
        if RuntimeDevelopmentPRSmokeBookmarkResolver.isEnabled {
            return RuntimeDevelopmentPRSmokeBookmarkResolver()
        }
#endif
        return SecurityScopedProjectWorkspaceBookmarkResolver()
    }

    @MainActor
    static func makeReviewSessionViewModel(plan: ActionPlan) -> ReviewSessionViewModel {
        let runtime: (
            logger: (any AuditLogger)?,
            receiptStore: (any ExecutionReceiptStore)?,
            registry: ToolRegistry,
            replayStore: any ApprovalReplayStore,
            reviewRuntimeValidationMessage: String?
        ) = {
            do {
                let auditLogger = try makeAuditLogger()
                let connection = try migratedConnection()
                let projectStore = SQLiteProjectStore(connection: connection)
                let taskStore = SQLiteTaskStore(connection: connection)
                let artifactStore = SQLiteArtifactStore(connection: connection)
                let sideEffectJournal = SQLiteExternalSideEffectJournal(connection: connection)
                try sideEffectJournal.recoverStartedAsUnknown(at: Date())
                let registry = try ToolRegistry.phase2MVP(
                    projectStore: projectStore,
                    taskStore: taskStore,
                    knowledgeStore: SQLiteKnowledgeFrameStore(connection: connection),
                    notificationClient: UserNotificationsNotificationClient(),
                    calendarClient: EventKitCalendarClient(),
                    reminderClient: EventKitReminderClient(),
                    fileAccessClient: LocalFileAccessClient(workspaceRoot: try workspaceRootURL()),
                    mailDraftClient: try makeMailDraftClient(),
                    notificationRequestStore: SQLiteNotificationRequestStore(connection: connection),
                    calendarLinkStore: SQLiteCalendarLinkStore(connection: connection),
                    reminderLinkStore: SQLiteReminderLinkStore(connection: connection),
                    artifactStore: artifactStore,
                    sideEffectJournal: sideEffectJournal,
                    auditLogger: auditLogger
                )
                try registry.register(AuditedTool(
                    base: DevelopmentPRWorkflowTool(
                        projectStore: projectStore,
                        taskStore: taskStore,
                        requireBookmark: true
                    ),
                    logger: auditLogger
                ))
                // Register only local, approval-gated development tools here. The broader
                // developer-mode factory also exposes push and GitHub PR creation, which
                // must stay outside the app ReviewSession runtime until those gates have
                // separate product review and merge readiness checks.
                try registry.register(AuditedTool(
                    base: DevelopmentRepositoryFileTool(
                        name: .developmentRepositoryListFiles,
                        projectStore: projectStore,
                        artifactStore: artifactStore,
                        requireBookmark: true
                    ),
                    logger: auditLogger
                ))
                try registry.register(AuditedTool(
                    base: DevelopmentRepositoryFileTool(
                        name: .developmentRepositoryReadFile,
                        projectStore: projectStore,
                        artifactStore: artifactStore,
                        requireBookmark: true
                    ),
                    logger: auditLogger
                ))
                try registry.register(AuditedTool(
                    base: DevelopmentRepositoryFileTool(
                        name: .developmentRepositoryCreateFile,
                        projectStore: projectStore,
                        artifactStore: artifactStore,
                        requireBookmark: true
                    ),
                    logger: auditLogger
                ))
                try registry.register(AuditedTool(
                    base: DevelopmentRepositoryFileTool(
                        name: .developmentRepositoryUpdateFile,
                        projectStore: projectStore,
                        artifactStore: artifactStore,
                        requireBookmark: true
                    ),
                    logger: auditLogger
                ))
                try registry.register(AuditedTool(
                    base: DevelopmentVerificationCommandTool(
                        projectStore: projectStore,
                        requireBookmark: true
                    ),
                    logger: auditLogger
                ))
                try registry.register(AuditedTool(
                    base: DevelopmentCommitWorkflowTool(
                        projectStore: projectStore,
                        requireBookmark: true
                    ),
                    logger: auditLogger
                ))
                let receiptStore = try makeExecutionReceiptStore()
                return (
                    auditLogger,
                    receiptStore,
                    registry,
                    SQLiteApprovalReplayStore(connection: connection),
                    nil
                )
            } catch {
                let baseMessage = "Review execution tools are unavailable because audit logging or local data stores could not be opened."
                let unavailableRegistry = unavailableReviewRegistry(for: plan, message: baseMessage)
                return (
                    nil,
                    nil,
                    unavailableRegistry.registry,
                    ProcessLocalApprovalReplayStore(),
                    unavailableRegistry.message
                )
            }
        }()

        return ReviewSessionViewModel(
            plan: plan,
            executor: ActionExecutor(
                registry: runtime.registry,
                auditLogger: runtime.logger,
                replayStore: runtime.replayStore
            ),
            auditLogger: runtime.logger,
            executionReceiptStore: runtime.receiptStore,
            runtimeValidationMessage: runtime.reviewRuntimeValidationMessage
        )
    }

    static func workspaceRootURL() throws -> URL {
        let directory = try applicationSupportDirectoryURL().appendingPathComponent("Workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func unavailableReviewRegistry(for plan: ActionPlan, message: String) -> UnavailableReviewRegistryResult {
        let target = ToolRegistry()
        var registeredTools: [ActionTool] = []
        var registrationFailures: [String] = []
        for action in plan.actions where !registeredTools.contains(action.tool) {
            do {
                try target.register(UnavailableReviewTool(name: action.tool, message: message))
                registeredTools.append(action.tool)
            } catch {
                registrationFailures.append(action.tool.rawValue)
            }
        }
        let finalMessage: String
        if registrationFailures.isEmpty {
            finalMessage = message
        } else {
            finalMessage = "\(message) Fallback unavailable tools could not be registered: \(registrationFailures.joined(separator: ", "))."
        }
        return UnavailableReviewRegistryResult(registry: target, message: finalMessage)
    }
}

private struct UnavailableReviewRegistryResult {
    let registry: ToolRegistry
    let message: String
}

private struct UnavailableReviewTool: Tool {
    let name: ActionTool
    let message: String
    let description = "Unavailable review execution tool."
    let inputSchema = ToolInputSchema(additionalProperties: true)
    let permissionLevel: ToolPermissionLevel = .read

    func execute(arguments: [String: JSONValue], context: ToolExecutionContext) throws -> ToolResult {
        throw ToolExecutionError.executionFailed(name, message)
    }
}
