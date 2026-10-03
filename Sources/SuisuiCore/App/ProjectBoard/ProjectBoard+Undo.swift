import Foundation

extension ProjectBoardViewModel {

    public var canUndoBoardOperation: Bool {
        !boardOperationUndo.isEmpty
    }

    /// Applies the most recent board-operation undo entry (⌘Z / Edit menu).
    ///
    /// Undo only calls existing store APIs and never re-runs completion side
    /// effects, so reverting a recurrence completion cannot regenerate another
    /// occurrence. The applied entry is removed only on success; a failed undo
    /// keeps the stack intact so the user can retry after fixing the cause.
    public func undoLastBoardOperation() {
        guard let entry = boardOperationUndo.last else {
            return
        }

        do {
            let feedbackMessage: String
            var restoredSelection: (projectID: Int64, taskID: Int64)?
            switch entry {
            case .restoreTask(let snapshot):
                let restored = try restoreDeletedTask(
                    snapshot: snapshot,
                    triageRecord: nil,
                    captures: []
                )
                restoredSelection = (restored.projectID, restored.id)
                feedbackMessage = String(localized: "Undo: restored the deleted task.")
            case .restoreTaskWithCaptures(let snapshot, let captures):
                let restored = try restoreDeletedTask(
                    snapshot: snapshot,
                    triageRecord: nil,
                    captures: captures
                )
                restoredSelection = (restored.projectID, restored.id)
                feedbackMessage = String(localized: "Undo: restored the deleted task and voice memo.")
            case .restoreInboxTask(let snapshot, let triageRecord, let captures):
                let restored = try restoreDeletedTask(
                    snapshot: snapshot,
                    triageRecord: triageRecord,
                    captures: captures
                )
                restoredSelection = (restored.projectID, restored.id)
                feedbackMessage = captures.isEmpty
                    ? String(localized: "Undo: restored the deleted task.")
                    : String(localized: "Undo: restored the deleted task and voice memo.")
            case .revertStatus(let snapshot):
                let reverted = try store.applyTaskUndoSnapshot(snapshot)
                restoredSelection = (reverted.projectID, reverted.id)
                feedbackMessage = String(localized: "Undo: moved the task back.")
            case .revertFields(let snapshot):
                let reverted = try store.applyTaskUndoSnapshot(snapshot)
                restoredSelection = (reverted.projectID, reverted.id)
                feedbackMessage = String(localized: "Undo: restored the task details.")
            case .undoCompletion(let snapshot, let regenerated):
                let reverted = try undoCompletionOperation(snapshot: snapshot, regenerated: regenerated)
                restoredSelection = (reverted.projectID, reverted.id)
                feedbackMessage = String(localized: "Undo: reopened the completed task.")
            case .revertInboxTriage(let mutation, let regenerated):
                let reverted = try undoInboxTriageOperation(mutation: mutation, regenerated: regenerated)
                restoredSelection = (reverted.projectID, reverted.id)
                feedbackMessage = String(localized: "Undo: restored the Inbox item.")
            case .revertStatusBatch(let snapshots, let regenerated):
                for regeneratedTask in regenerated where isRegeneratedTaskUntouched(regeneratedTask) {
                    try store.deleteTask(id: regeneratedTask.id)
                }
                for snapshot in snapshots {
                    _ = try store.applyTaskUndoSnapshot(snapshot)
                }
                restoredSelection = snapshots.last.map { ($0.projectID, $0.id) }
                feedbackMessage = String(format: String(localized: "Undo: moved %d tasks back."), snapshots.count)
            }
            boardOperationUndo.pop()
            load()
            if let restoredSelection {
                selectedProjectID = restoredSelection.projectID
                selectedTaskID = restoredSelection.taskID
            }
            showBoardUndoFeedback(feedbackMessage)
            clearErrorAfterSuccessfulLoad()
            onChange()
        } catch ProjectBoardStoreError.archivedProjectCannotAcceptTasks {
            recordOperationFailure("Restore the project before undoing this change.")
        } catch {
            recordOperationFailure(LocalWorkspaceFailureMessage.message(for: error))
        }
    }

    private func restoreDeletedTask(
        snapshot: ProjectBoardTask,
        triageRecord: InboxTriageRecord?,
        captures: [InboxCaptureRecord]
    ) throws -> ProjectBoardTask {
        if let atomicStore = store as? any ProjectBoardDeleteUndoRestoring,
           triageRecord != nil || !captures.isEmpty {
            return try atomicStore.restoreDeletedTask(
                from: snapshot,
                triageRecord: triageRecord,
                captures: captures
            )
        }

        // Test doubles and non-SQLite integrations keep the additive fallback;
        // production SQLite uses the capability above because compensation
        // cannot provide an atomic retry guarantee after a storage failure.
        let restored: ProjectBoardTask
        if let triageRecord {
            restored = try store.undoInboxTriage(InboxTriageMutation(
                originalTask: snapshot,
                originalRecord: triageRecord,
                updatedTask: snapshot
            ))
        } else {
            restored = try store.restoreTask(from: snapshot)
        }
        var restoredCaptureIDs: [Int64] = []
        do {
            if !captures.isEmpty {
                guard let inboxCaptureStore else {
                    throw InboxCaptureStoreError.linkedTaskMissing
                }
                for capture in captures {
                    let restoredCapture = try inboxCaptureStore.createVoiceCapture(InboxVoiceCaptureDraft(
                        taskID: restored.id,
                        audioFilePath: capture.audioFilePath,
                        durationSeconds: capture.durationSeconds,
                        transcript: capture.transcript,
                        interpretationSummary: capture.interpretationSummary,
                        memo: capture.memo,
                        classificationStatus: capture.classificationStatus,
                        transcriptionStatus: capture.transcriptionStatus,
                        createdAt: capture.createdAt
                    ))
                    restoredCaptureIDs.append(restoredCapture.id)
                }
            }
            return restored
        } catch {
            // The recreated task has a new ID. Roll back every dependent row
            // so a failed capture restore can be retried as one Undo. Triage
            // restoration already shares the store's task transaction.
            for captureID in restoredCaptureIDs {
                try? inboxCaptureStore?.delete(id: captureID)
            }
            try? store.deleteTask(id: restored.id)
            throw error
        }
    }

    private func undoCompletionOperation(
        snapshot: ProjectBoardTask,
        regenerated: ProjectBoardTask?
    ) throws -> ProjectBoardTask {
        guard let regenerated, isRegeneratedTaskUntouched(regenerated) else {
            // Rule: when the regenerated next occurrence was already edited,
            // moved, or completed by the user (or no longer exists), keep it
            // and only restore the original task's previous open state.
            return try store.applyTaskUndoSnapshot(snapshot)
        }
        try store.deleteTask(id: regenerated.id)
        do {
            return try store.applyTaskUndoSnapshot(snapshot)
        } catch {
            // Keep the undo all-or-nothing in effect: if the original cannot
            // be restored, put the regenerated occurrence back instead of
            // leaving the recurrence chain half-applied.
            _ = try? store.restoreTask(from: regenerated)
            throw error
        }
    }

    func undoInboxTriageOperation(
        mutation: InboxTriageMutation,
        regenerated: ProjectBoardTask?
    ) throws -> ProjectBoardTask {
        let shouldRestoreRegenerated = regenerated.map(isRegeneratedTaskUntouched) == true
        if let regenerated, shouldRestoreRegenerated {
            try store.deleteTask(id: regenerated.id)
        }
        do {
            return try store.undoInboxTriage(mutation)
        } catch {
            // Keep the undo retryable and restore a deleted recurrence if the
            // disposition/task transaction cannot be applied.
            if let regenerated, shouldRestoreRegenerated {
                _ = try? store.restoreTask(from: regenerated)
            }
            throw error
        }
    }

    private func isRegeneratedTaskUntouched(_ regenerated: ProjectBoardTask) -> Bool {
        snapshot.projects.flatMap(\.tasks).first { $0.id == regenerated.id } == regenerated
    }

    func visibleTaskIDsForUndoDiff() -> Set<Int64> {
        Set(snapshot.projects.flatMap(\.tasks).map(\.id))
    }

    /// Tasks that appeared during the last mutation. Completion-driven
    /// recurrence is the only insert a status move can perform, so an ID diff
    /// against the pre-mutation snapshot identifies regenerated occurrences
    /// without changing the store's transactional completion entry points.
    func regeneratedTasksAfterMutation(notIn taskIDsBeforeMutation: Set<Int64>) -> [ProjectBoardTask] {
        snapshot.projects.flatMap(\.tasks).filter { !taskIDsBeforeMutation.contains($0.id) }
    }

    /// Shared undo recording for every status-move path (keyboard, card
    /// controls, Today completion toggle, and single or multi drag & drop).
    /// Must run after `load()` so the regenerated-occurrence diff sees the
    /// post-mutation snapshot.
    func recordStatusMoveUndo(
        previousTasks: [ProjectBoardTask],
        to status: ProjectTaskStatus,
        taskIDsBeforeMutation: Set<Int64>
    ) {
        let changedTasks = previousTasks.filter { $0.status != status }
        guard !changedTasks.isEmpty else {
            return
        }
        let regenerated = regeneratedTasksAfterMutation(notIn: taskIDsBeforeMutation)
        if changedTasks.count == 1, let original = changedTasks.first {
            if status == .done {
                boardOperationUndo.push(.undoCompletion(snapshot: original, regenerated: regenerated.first))
            } else {
                boardOperationUndo.push(.revertStatus(snapshot: original))
            }
        } else {
            boardOperationUndo.push(.revertStatusBatch(snapshots: changedTasks, regenerated: regenerated))
        }
    }

    private static let boardUndoFeedbackDismissDelay: Duration = .seconds(3)

    private func showBoardUndoFeedback(_ message: String) {
        boardUndoFeedbackClearTask?.cancel()
        boardUndoFeedback = message
        boardUndoFeedbackClearTask = Task { [weak self] in
            try? await Task.sleep(for: Self.boardUndoFeedbackDismissDelay)
            guard !Task.isCancelled else {
                return
            }
            self?.boardUndoFeedback = nil
        }
    }
}
