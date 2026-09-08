import Foundation
import OSLog
import SuisuiCore

private let inboxAudioReconciliationLogger = Logger(
    subsystem: "dev.suisui.app",
    category: "inbox-audio"
)

private enum InboxAudioReconciliationGate {
    static let lock = NSLock()
    nonisolated(unsafe) static var hasAttempted = false
}

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
            let runtime = makeProjectBoardRuntimeBundle()
            if case let .available(connection, _, _, _, _, _) = runtime {
                reconcileManagedInboxAudioOnce(connection: connection)
            }
            return runtime
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
            let inboxCaptureStore = SQLiteInboxCaptureStore(connection: connection)
            return ProjectBoardViewModel(
                store: projectBoardStore,
                inboxCaptureStore: inboxCaptureStore,
                assistantQueueStore: assistantQueueStore,
                assistantQueueExecutionCoordinatorFactory: {
                    makeAssistantQueueExecutionCoordinator(
                        connection: connection,
                        assistantQueueStore: assistantQueueStore,
                        executionReceiptStore: executionReceiptStore
                    )
                },
                executionReceiptStore: executionReceiptStore,
                publicAlphaMeasurement: try? makePublicAlphaMeasurement(),
                missedTaskReviewStateStore: SQLiteMissedTaskReviewStateStore(connection: connection),
                missedTaskFollowUpNotificationClient: UserNotificationsNotificationClient(),
                externalTaskLinkStore: externalTaskLinkStore,
                externalScheduleEventSource: makeGoogleCalendarScheduleEventSource(connection: connection),
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

    /// Reconciles the managed audio directory before exposing Inbox audio.
    /// Legacy recorder paths are migrated only when they are app-owned temp
    /// files; unknown paths remain transcript-only instead of being copied.
    static func reconcileManagedInboxAudioOnce(connection: SQLiteConnection) {
        InboxAudioReconciliationGate.lock.lock()
        defer { InboxAudioReconciliationGate.lock.unlock() }
        guard InboxAudioReconciliationGate.hasAttempted == false else {
            return
        }
        // A failed maintenance attempt must not be retried for every recreated
        // window. Board and transcript reads remain available for this process.
        InboxAudioReconciliationGate.hasAttempted = true
        do {
            try reconcileManagedInboxAudio(
                captureStore: SQLiteInboxCaptureStore(connection: connection),
                audioStore: ManagedInboxAudioFileStore()
            )
        } catch {
            // Avoid logging an error description that could contain a private
            // recording path.
            inboxAudioReconciliationLogger.error(
                "Inbox audio reconciliation failed category=audio_reconciliation_failed"
            )
        }
    }

    static func reconcileManagedInboxAudio(
        captureStore: SQLiteInboxCaptureStore,
        audioStore: ManagedInboxAudioFileStore
    ) throws {
        for capture in try captureStore.listAll() {
            guard let managedURL = try audioStore.migrateLegacyRecordingIfNeeded(
                from: URL(fileURLWithPath: capture.audioFilePath)
            ) else {
                continue
            }
            guard managedURL.path != URL(fileURLWithPath: capture.audioFilePath).standardizedFileURL.path else {
                continue
            }

            do {
                _ = try captureStore.updateAudioFilePath(id: capture.id, audioFilePath: managedURL.path)
                try? FileManager.default.removeItem(atPath: capture.audioFilePath)
            } catch {
                // Do not leave a copied file behind when SQLite could not
                // commit the new path; the original row remains playable if
                // its temporary source is still present.
                audioStore.removeImportedRecording(at: managedURL)
            }
        }

        let referencedPaths = Set(try captureStore.listAll().map(\.audioFilePath))
        try audioStore.removeOrphanedRecordings(referencedPaths: referencedPaths)
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
