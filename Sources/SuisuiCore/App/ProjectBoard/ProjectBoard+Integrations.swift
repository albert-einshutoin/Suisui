import Foundation

extension ProjectBoardViewModel {

    public var canSyncGoogleCalendar: Bool {
        googleCalendarSyncStatus.canSync
    }

    public var googleCalendarSyncHelp: String {
        googleCalendarSyncStatus.detailLabel
    }

    public func refreshGoogleCalendarSyncStatus(now: Date = Date()) {
        // A synchronous user/approval refresh is newer than any detached
        // readiness read already in flight, so invalidate it before publishing.
        googleCalendarReadinessRefreshRevision &+= 1
        guard let googleCalendarSync = resolvedGoogleCalendarSync else {
            googleCalendarSyncStatus = .runtimeNotConfigured
            return
        }

        do {
            googleCalendarSyncStatus = try googleCalendarSync.status(now: now)
        } catch {
            let message = LocalWorkspaceFailureMessage.message(
                for: error,
                fallback: String(localized: "Google Calendar sync status is unavailable.")
            )
            googleCalendarSyncStatus = GoogleCalendarRuntimeSyncStatus(
                plan: googleCalendarSyncStatus.plan,
                state: .failed(message: message)
            )
            recordFailure(.readinessCheckFailed(message), retryAction: .load)
        }
    }

    /// Settings changes can require SQLite or Keychain-backed readiness reads.
    /// Keep that work away from Today rendering and publish only the completed
    /// status on the MainActor, ignoring older overlapping refreshes.
    public func refreshGoogleCalendarSyncStatusOffMain(
        now: Date = VisualEvidenceRuntimeContext.referenceDate()
    ) {
        guard let googleCalendarSync = resolvedGoogleCalendarSync else {
            googleCalendarSyncStatus = .runtimeNotConfigured
            return
        }
        googleCalendarReadinessRefreshRevision &+= 1
        let refreshRevision = googleCalendarReadinessRefreshRevision
        let fallback = String(localized: "Google Calendar sync status is unavailable.")

        Task { @MainActor [weak self] in
            let result = await Task.detached(priority: .utility) {
                do {
                    return GoogleCalendarReadinessRefreshResult.success(
                        try googleCalendarSync.status(now: now)
                    )
                } catch {
                    return .failure(
                        UserFacingErrorMessageSanitizer.message(from: error, fallback: fallback)
                    )
                }
            }.value
            guard let self, self.googleCalendarReadinessRefreshRevision == refreshRevision else {
                return
            }
            switch result {
            case let .success(status):
                self.googleCalendarSyncStatus = status
            case let .failure(message):
                self.googleCalendarSyncStatus = GoogleCalendarRuntimeSyncStatus(
                    plan: self.googleCalendarSyncStatus.plan,
                    state: .failed(message: message)
                )
                self.recordFailure(.readinessCheckFailed(message), retryAction: .load)
            }
        }
    }

    @discardableResult
    public func syncDueTasksToGoogleCalendar(approvalToken: String?) -> GoogleCalendarTaskSyncResult? {
        beginRecoverableOperation()
        refreshGoogleCalendarSyncStatus()
        guard let googleCalendarSync = resolvedGoogleCalendarSync else {
            recordFailure(
                .providerFailed(GoogleCalendarRuntimeSyncStatus.runtimeNotConfigured.detailLabel),
                retryAction: .syncGoogleCalendar(approvalToken: approvalToken)
            )
            return nil
        }
        guard googleCalendarSyncStatus.canSync else {
            recordFailure(
                .readinessCheckFailed(googleCalendarSyncStatus.detailLabel),
                retryAction: .syncGoogleCalendar(approvalToken: approvalToken)
            )
            return nil
        }
        guard let approvalToken,
              !approvalToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            recordFailure(
                .readinessCheckFailed(String(localized: "Google Calendar sync requires approval before writing events.")),
                retryAction: nil
            )
            return nil
        }

        do {
            let approval = ApprovalToken(
                id: approvalToken,
                sessionID: "project-board-google-calendar-sync"
            )
            let context = ToolExecutionContext(
                authorization: try ToolActionAuthorization(
                    approval: approval,
                    actionID: "standalone",
                    tool: .calendarCreateEvent,
                    arguments: [:]
                ),
                source: .reviewUI
            )
            let result = try googleCalendarSync.syncDueTasks(context: context)
            integrationStatusMessage = Self.googleCalendarSyncStatusMessage(for: result)
            recordOperationFailure(nil)
            refreshGoogleCalendarSyncStatus()
            onChange()
            return result
        } catch GoogleCalendarRuntimeSyncError.approvalRequired {
            recordFailure(
                .readinessCheckFailed(String(localized: "Google Calendar sync requires approval before writing events.")),
                retryAction: nil
            )
            return nil
        } catch GoogleCalendarRuntimeSyncError.notReady(let state) {
            googleCalendarSyncStatus = GoogleCalendarRuntimeSyncStatus(plan: googleCalendarSyncStatus.plan, state: state)
            recordFailure(
                .readinessCheckFailed(googleCalendarSyncStatus.detailLabel),
                retryAction: .syncGoogleCalendar(approvalToken: approvalToken)
            )
            return nil
        } catch SyncServiceError.upgradeRequired(let requiredPlan) {
            googleCalendarSyncStatus = GoogleCalendarRuntimeSyncStatus(
                plan: googleCalendarSyncStatus.plan,
                state: .upgradeRequired(requiredPlan: requiredPlan)
            )
            recordFailure(
                .readinessCheckFailed(googleCalendarSyncStatus.detailLabel),
                retryAction: .syncGoogleCalendar(approvalToken: approvalToken)
            )
            return nil
        } catch {
            let message = LocalWorkspaceFailureMessage.message(
                for: error,
                fallback: String(localized: "Google Calendar sync failed.")
            )
            googleCalendarSyncStatus = GoogleCalendarRuntimeSyncStatus(
                plan: googleCalendarSyncStatus.plan,
                state: .failed(message: message)
            )
            recordFailure(
                .providerFailed(message),
                retryAction: .syncGoogleCalendar(approvalToken: approvalToken)
            )
            return nil
        }
    }

    public func exportTaskInteropJSON(exportedAt: Date = Date()) -> Data? {
        do {
            let data = try TaskInteropExportService(store: store).exportJSON(exportedAt: exportedAt)
            integrationStatusMessage = "Prepared task export JSON."
            recordOperationFailure(nil)
            return data
        } catch {
            recordOperationFailure(LocalWorkspaceFailureMessage.message(for: error))
            return nil
        }
    }

    @discardableResult
    public func importTaskInteropJSON(_ data: Data) -> ExternalTaskImportResult? {
        guard let externalTaskLinkStore else {
            recordOperationFailure("Task import is unavailable in this build.")
            return nil
        }

        do {
            let document = try TaskInteropDocument.decode(data)
            let result = try TaskInteropDocumentImportService(
                store: store,
                linkStore: externalTaskLinkStore
            ).importDocument(document)
            load()
            integrationStatusMessage = Self.importStatusMessage(for: result)
            clearErrorAfterSuccessfulLoad()
            onChange()
            return result
        } catch {
            recordOperationFailure(LocalWorkspaceFailureMessage.message(
                for: error,
                fallback: "Task import failed. Choose a Suisui task JSON export."
            ))
            return nil
        }
    }

    public func recordTaskInteropFileFailure(_ error: Error) {
        recordOperationFailure(LocalWorkspaceFailureMessage.message(
            for: error,
            fallback: "Task import/export failed."
        ))
    }

    public func recordTaskInteropExportCompleted() {
        integrationStatusMessage = String(localized: "Exported task JSON.")
        recordOperationFailure(nil)
    }

    private static func importStatusMessage(for result: ExternalTaskImportResult) -> String {
        let taskLabel = String(
            format: String(localized: result.createdTaskCount == 1 ? "%d task" : "%d tasks"),
            result.createdTaskCount
        )
        if result.skippedDuplicateCount > 0 {
            let skippedLabel = String(
                format: String(localized: result.skippedDuplicateCount == 1 ? "%d duplicate" : "%d duplicates"),
                result.skippedDuplicateCount
            )
            return String(
                format: String(localized: "Imported %@ from JSON. Skipped %@."),
                taskLabel,
                skippedLabel
            )
        }
        return String(format: String(localized: "Imported %@ from JSON."), taskLabel)
    }

    private static func googleCalendarSyncStatusMessage(for result: GoogleCalendarTaskSyncResult) -> String {
        let createdLabel = String(
            format: String(localized: result.createdEventCount == 1 ? "%d Google Calendar event" : "%d Google Calendar events"),
            result.createdEventCount
        )
        var sentences = [
            String(format: String(localized: "Created %@."), createdLabel)
        ]

        if result.skippedAlreadyLinkedCount > 0 {
            let skippedLabel = String(
                format: String(localized: result.skippedAlreadyLinkedCount == 1 ? "%d already-linked task" : "%d already-linked tasks"),
                result.skippedAlreadyLinkedCount
            )
            sentences.append(String(format: String(localized: "Skipped %@."), skippedLabel))
        }

        if result.deferredDueToRunLimitCount > 0 {
            let deferredLabel = String(
                format: String(localized: result.deferredDueToRunLimitCount == 1 ? "%d due task" : "%d due tasks"),
                result.deferredDueToRunLimitCount
            )
            sentences.append(String(format: String(localized: "Deferred %@."), deferredLabel))
        }

        if result.failedRetryableCount > 0 {
            let retryableLabel = String(
                format: String(localized: result.failedRetryableCount == 1 ? "%d retryable task" : "%d retryable tasks"),
                result.failedRetryableCount
            )
            sentences.append(String(format: String(localized: "Rate-limited %@."), retryableLabel))
        }

        if result.failedNonRetryableCount > 0 {
            let failedLabel = String(
                format: String(localized: result.failedNonRetryableCount == 1 ? "%d task" : "%d tasks"),
                result.failedNonRetryableCount
            )
            sentences.append(String(format: String(localized: "Failed %@."), failedLabel))
        }

        if result.hasMoreWork {
            sentences.append(String(localized: "More due tasks remain; run sync again after approval."))
        }

        return sentences.joined(separator: " ")
    }
}
