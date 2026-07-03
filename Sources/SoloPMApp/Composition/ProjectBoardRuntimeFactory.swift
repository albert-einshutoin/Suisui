import Foundation
import SoloPMCore

extension AppRuntimeFactory {
    @MainActor
    static func makeProjectBoardViewModel() -> ProjectBoardViewModel {
        do {
            let connection = try migratedConnection()
            let projectBoardStore = SQLiteProjectBoardStore(connection: connection)
            let externalTaskLinkStore = SQLiteExternalTaskLinkStore(connection: connection)
            let assistantQueueStore = SQLiteAssistantQueueStore(connection: connection)
            let executionReceiptStore = try? makeExecutionReceiptStore()
            let secretStore = makeSecretStore()
            let entitlementStore = makeEntitlementStore(secretStore: secretStore)
            let googleCalendarSync = makeSettingsBackedGoogleCalendarSyncController(
                connection: connection,
                entitlementStore: entitlementStore,
                store: projectBoardStore,
                linkStore: externalTaskLinkStore,
                secretStore: secretStore
            )
            return ProjectBoardViewModel(
                store: projectBoardStore,
                inboxCaptureStore: SQLiteInboxCaptureStore(connection: connection),
                assistantQueueStore: assistantQueueStore,
                assistantQueueExecutionCoordinator: makeAssistantQueueExecutionCoordinator(
                    connection: connection,
                    assistantQueueStore: assistantQueueStore,
                    executionReceiptStore: executionReceiptStore
                ),
                executionReceiptStore: executionReceiptStore,
                missedTaskReviewStateStore: SQLiteMissedTaskReviewStateStore(connection: connection),
                missedTaskFollowUpNotificationClient: UserNotificationsNotificationClient(),
                externalTaskLinkStore: externalTaskLinkStore,
                googleCalendarSync: googleCalendarSync,
                onChange: postProjectBoardDidChange
            )
        } catch {
            return ProjectBoardViewModel(store: UnavailableProjectBoardStore(error: error))
        }
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
            let auditLogger = try makeAuditLogger()
            let registry = try makeRuntimeToolRegistry(connection: connection, auditLogger: auditLogger)
            return AssistantQueueExecutionCoordinator(
                queueStore: assistantQueueStore,
                executor: ActionExecutor(registry: registry, auditLogger: auditLogger),
                executionReceiptStore: executionReceiptStore,
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
