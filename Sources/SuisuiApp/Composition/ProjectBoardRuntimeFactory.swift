import Foundation
import SuisuiCore

enum ProjectBoardRuntimeBundle: @unchecked Sendable {
    case available(
        connection: SQLiteConnection,
        projectBoardStore: SQLiteProjectBoardStore,
        externalTaskLinkStore: SQLiteExternalTaskLinkStore,
        assistantQueueStore: SQLiteAssistantQueueStore,
        executionReceiptStore: (any ExecutionReceiptStore)?,
        googleCalendarSyncStatus: GoogleCalendarRuntimeSyncStatus
    )
    case unavailable(Error)
}

extension AppRuntimeFactory {
    static func prepareProjectBoardRuntimeBundle() async -> ProjectBoardRuntimeBundle {
        await Task.detached(priority: .userInitiated) {
            // SQLite open can block on external volumes and mounted app
            // launches. Build the runtime bundle off-main, then hand it to the
            // MainActor-only view model before any UI reads from the connection.
            let signposter = LaunchPerformanceSignposts.signposter
            let launchState = signposter.beginInterval("LaunchToRuntimeBundle")
            defer {
                signposter.endInterval("LaunchToRuntimeBundle", launchState)
            }
            return makeProjectBoardRuntimeBundle()
        }.value
    }

    static func makeProjectBoardRuntimeBundle() -> ProjectBoardRuntimeBundle {
        let signposter = LaunchPerformanceSignposts.signposter
        let migrateState = signposter.beginInterval("DatabaseOpenMigrate")
        do {
            let connection = try migratedConnection()
            signposter.endInterval("DatabaseOpenMigrate", migrateState)
            return .available(
                connection: connection,
                projectBoardStore: SQLiteProjectBoardStore(connection: connection),
                externalTaskLinkStore: SQLiteExternalTaskLinkStore(connection: connection),
                assistantQueueStore: SQLiteAssistantQueueStore(connection: connection),
                executionReceiptStore: try? makeExecutionReceiptStore(),
                googleCalendarSyncStatus: makeGoogleCalendarRuntimeSyncStatus(connection: connection)
            )
        } catch {
            signposter.endInterval("DatabaseOpenMigrate", migrateState)
            return .unavailable(error)
        }
    }

    @MainActor
    static func makeProjectBoardViewModel() -> ProjectBoardViewModel {
        makeProjectBoardViewModel(runtime: makeProjectBoardRuntimeBundle())
    }

    @MainActor
    static func makeProjectBoardViewModel(runtime: ProjectBoardRuntimeBundle) -> ProjectBoardViewModel {
        switch runtime {
        case let .available(connection, projectBoardStore, externalTaskLinkStore, assistantQueueStore, executionReceiptStore, googleCalendarSyncStatus):
            return ProjectBoardViewModel(
                store: projectBoardStore,
                inboxCaptureStore: SQLiteInboxCaptureStore(connection: connection),
                assistantQueueStore: assistantQueueStore,
                assistantQueueExecutionCoordinatorFactory: {
                    makeAssistantQueueExecutionCoordinator(
                        connection: connection,
                        assistantQueueStore: assistantQueueStore,
                        executionReceiptStore: executionReceiptStore
                    )
                },
                executionReceiptStore: executionReceiptStore,
                missedTaskReviewStateStore: SQLiteMissedTaskReviewStateStore(connection: connection),
                missedTaskFollowUpNotificationClient: UserNotificationsNotificationClient(),
                externalTaskLinkStore: externalTaskLinkStore,
                initialGoogleCalendarSyncStatus: googleCalendarSyncStatus,
                googleCalendarSyncFactory: {
                    guard isGoogleCalendarRuntimeEnabled() else {
                        return nil
                    }
                    let secretStore = makeSecretStore()
                    return makeSettingsBackedGoogleCalendarSyncController(
                        connection: connection,
                        entitlementStore: makeEntitlementStore(secretStore: secretStore),
                        store: projectBoardStore,
                        linkStore: externalTaskLinkStore,
                        secretStore: secretStore
                    )
                },
                onChange: postProjectBoardDidChange
            )
        case let .unavailable(error):
            return ProjectBoardViewModel(store: UnavailableProjectBoardStore(error: error))
        }
    }

    @MainActor
    static func makeLaunchVisibleProjectBoardViewModel() -> ProjectBoardViewModel {
        makeProjectBoardViewModel(runtime: makeProjectBoardRuntimeBundle())
    }

    private static func makeAssistantQueueExecutionCoordinator(
        connection: SQLiteConnection,
        assistantQueueStore: any AssistantQueueStore,
        executionReceiptStore: (any ExecutionReceiptStore)?
    ) -> AssistantQueueExecutionCoordinator? {
        guard let executionReceiptStore else {
            return nil
        }
        do {
            // Queue execution shares the already-migrated board connection so
            // an explicit approval cannot open a second connection and rerun
            // migrations while the visible board still owns active statements.
            let auditLogger = RedactingAuditLogger(base: SQLiteAuditLogger(connection: connection))
            let registry = try makeRuntimeToolRegistry(connection: connection, auditLogger: auditLogger)
            let conversationStore = SQLiteVoiceTaskConversationStore(
                connection: connection
            )
            let taskStore = SQLiteTaskStore(connection: connection)
            return AssistantQueueExecutionCoordinator(
                queueStore: assistantQueueStore,
                executor: ActionExecutor(
                    registry: registry,
                    auditLogger: auditLogger,
                    replayStore: SQLiteApprovalReplayStore(connection: connection)
                ),
                executionReceiptStore: executionReceiptStore,
                conversationActionLinkStore: conversationStore,
                taskSnapshotFingerprintProvider: { taskID in
                    ConversationTaskSnapshotFingerprint.make(
                        try taskStore.get(id: taskID)
                    )
                },
                managedAIUsageLedgerStore: SQLiteManagedAIUsageLedgerStore(connection: connection),
                managedAIBillingSettingsProvider: { loadRuntimeAppSettings().managedAIBilling }
            )
        } catch {
            return nil
        }
    }
}

private struct UnavailableProjectBoardStore: ProjectBoardStore {
    let error: Error

    func loadSnapshot() throws -> ProjectBoardSnapshot {
        throw error
    }

    func loadSnapshot(includeArchived: Bool) throws -> ProjectBoardSnapshot {
        throw error
    }

    func createProject(title: String) throws -> ProjectBoardProject {
        throw error
    }

    func updateProject(id: Int64, title: String) throws -> ProjectBoardProject {
        throw error
    }

    func completeProject(id: Int64) throws -> ProjectBoardProject {
        throw error
    }

    func archiveProject(id: Int64) throws -> ProjectBoardProject {
        throw error
    }

    func restoreProject(id: Int64) throws -> ProjectBoardProject {
        throw error
    }

    func deleteProject(id: Int64) throws {
        throw error
    }

    func createTask(_ draft: ProjectBoardTaskDraft) throws -> ProjectBoardTask {
        throw error
    }

    func loadInboxTriageRecords(taskIDs: Set<Int64>) throws -> [Int64: InboxTriageRecord] {
        throw error
    }

    func createInboxTask(title: String) throws -> ProjectBoardTask {
        throw error
    }

    func performInboxTriage(
        taskID: Int64,
        action: InboxTriageAction,
        referenceDate: Date,
        calendar: Calendar
    ) throws -> InboxTriageMutation {
        throw error
    }

    func undoInboxTriage(_ mutation: InboxTriageMutation) throws -> ProjectBoardTask {
        throw error
    }

    func updateTask(id: Int64, _ draft: ProjectBoardTaskDraft) throws -> ProjectBoardTask {
        throw error
    }

    func moveTask(id: Int64, to status: ProjectTaskStatus) throws -> ProjectBoardTask {
        throw error
    }

    func moveTasks(ids: [Int64], to status: ProjectTaskStatus) throws -> [ProjectBoardTask] {
        throw error
    }

    func moveTasks(ids: [Int64], toProjectID projectID: Int64) throws -> [ProjectBoardTask] {
        throw error
    }

    func deleteTask(id: Int64) throws {
        throw error
    }

    func createProjectArtifact(projectID: Int64, expectedPath: String) throws -> ProjectBoardArtifact {
        throw error
    }

    func deleteProjectArtifact(id: Int64) throws {
        throw error
    }

    func createProjectMilestone(projectID: Int64, title: String, dueAt: String?) throws -> ProjectBoardMilestone {
        throw error
    }

    func updateProjectMilestone(id: Int64, title: String, dueAt: String?, isCompleted: Bool) throws -> ProjectBoardMilestone {
        throw error
    }

    func deleteProjectMilestone(id: Int64) throws {
        throw error
    }
}
