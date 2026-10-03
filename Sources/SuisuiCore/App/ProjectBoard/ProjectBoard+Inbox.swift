import Foundation

extension ProjectBoardViewModel {

    public var selectedInboxCaptureRecords: [InboxCaptureRecord] {
        guard let selectedTaskID else {
            return []
        }

        return captureRecords(for: selectedTaskID, reportErrors: true)
    }

    @discardableResult
    public func updateSelectedInboxCaptureMemo(_ memo: String) -> InboxCaptureRecord? {
        guard let capture = selectedInboxCaptureRecords.first, let inboxCaptureStore else {
            recordOperationFailure("Inbox capture is no longer available.")
            return nil
        }

        do {
            let updated = try inboxCaptureStore.updateMemo(id: capture.id, memo: memo)
            replaceCachedCapture(updated)
            let taskTitle = selectedTask?.title ?? "selected Inbox item"
            inboxClassificationFeedback = InboxClassificationFeedback(
                message: String(format: String(localized: "Saved note for \"%@\"."), taskTitle),
                systemImage: "note.text",
                canUndo: false
            )
            recordOperationFailure(nil)
            onChange()
            return updated
        } catch {
            recordOperationFailure(InboxCaptureStoreError.userMessage(for: error))
            return nil
        }
    }

    public var filteredInboxTasks: [ProjectBoardTask] {
        inboxTasks.filter { task in
            matchesInboxTriageFilter(task, filter: inboxTriageFilter)
        }
    }

    public var inboxTasks: [ProjectBoardTask] {
        inboxProject?
            .tasks
            .filter { showsCompletedWorkflowTasks || $0.status != .done }
            .sorted { $0.id > $1.id } ?? []
    }

    public var completedInboxTaskCount: Int {
        inboxProject?.tasks.filter { $0.status == .done }.count ?? 0
    }

    public var inboxProject: ProjectBoardProject? {
        snapshot.projects
            .first { $0.title.caseInsensitiveCompare("Inbox") == .orderedSame && !$0.isArchived }
    }

    public func inboxTriageCount(for filter: InboxTriageFilter) -> Int {
        return inboxTasks.filter { task in
            matchesInboxTriageFilter(task, filter: filter)
        }.count
    }

    /// Returns the product-facing category used by the reference Inbox tabs.
    /// The mapping is derived from cached capture metadata so rendering the
    /// list does not perform a store read for every row.
    public func inboxReferenceCategory(for task: ProjectBoardTask) -> InboxReferenceCategory {
        let captures = captureRecords(for: task.id)
        let interpretation = captures
            .compactMap(\.interpretationSummary)
            .joined(separator: " ")
        let searchableText = [task.title, task.detail, interpretation]
            .joined(separator: " ")
            .lowercased()

        if Self.inboxNotificationKeywords.contains(where: searchableText.contains) {
            return .notification
        }
        if !interpretation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .proposal
        }
        return .task
    }

    public func inboxReferenceTasks(
        for filter: InboxReferenceFilter,
        unprocessedOnly: Bool = false,
        at referenceDate: Date? = nil
    ) -> [ProjectBoardTask] {
        let effectiveReferenceDate = referenceDate ?? inboxVisibilityReferenceDate ?? readModelNow()
        return inboxTasks.filter { task in
            guard !unprocessedOnly || isInboxUnprocessed(task, at: effectiveReferenceDate) else {
                return false
            }
            guard filter != .all else {
                return true
            }
            return inboxReferenceCategory(for: task) == filter.category
        }
    }

    public func inboxReferenceCount(for filter: InboxReferenceFilter) -> Int {
        inboxReferenceTasks(for: filter).count
    }

    private static let inboxNotificationKeywords = [
        "notification", "alert", "お知らせ", "通知", "アラート"
    ]

    public func inboxTriageSummary(for task: ProjectBoardTask) -> InboxTriageSummary {
        let captures = captureRecords(for: task.id)
        guard let capture = captures.first else {
            return InboxTriageSummary(
                sourceLabel: "Manual",
                // Disposition is rendered by the dedicated triage badge. The
                // source summary must stay about how the item arrived, or a
                // processed manual task appears contradictory as "Unprocessed".
                interpretationLabel: "Manual",
                systemImage: "square.and.pencil",
                tintName: "secondary",
                accessibilityValue: "Source: Manual, Interpretation: Manual"
            )
        }

        if capture.transcriptionStatus == .failed {
            return InboxTriageSummary(
                sourceLabel: "Voice",
                interpretationLabel: "Transcript failed",
                systemImage: "waveform.badge.exclamationmark",
                tintName: "red",
                accessibilityValue: "Source: Voice, Interpretation: Transcript failed"
            )
        }

        if capture.transcriptionStatus == .pending {
            return InboxTriageSummary(
                sourceLabel: "Voice",
                interpretationLabel: "Transcript pending",
                systemImage: "waveform",
                tintName: "secondary",
                accessibilityValue: "Source: Voice, Interpretation: Transcript pending"
            )
        }

        guard capture.interpretationSummary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return InboxTriageSummary(
                sourceLabel: "Voice",
                interpretationLabel: "Transcript ready",
                systemImage: "waveform",
                tintName: "blue",
                accessibilityValue: "Source: Voice, Interpretation: Transcript ready"
            )
        }

        let confidence = Self.inboxInterpretationConfidence(from: capture.memo)
        let confidenceValue = confidence.map { ", Confidence: \($0)" } ?? ""
        return InboxTriageSummary(
            sourceLabel: "Voice",
            interpretationLabel: "AI interpreted",
            systemImage: "sparkles",
            tintName: "blue",
            accessibilityValue: "Source: Voice, Interpretation: AI interpreted\(confidenceValue)"
        )
    }

    public func inboxTriageRecord(for task: ProjectBoardTask) -> InboxTriageRecord? {
        inboxTriageRecordsByTaskID[task.id]
    }

    public func setInboxTriageFilter(_ filter: InboxTriageFilter) {
        refreshInboxCaptureCacheForInbox()
        inboxTriageFilter = filter
        ensureSelectedTaskIsVisibleInInboxFilter()
    }

    /// Re-evaluates deferred Inbox items against a caller-provided local time.
    /// The UI invokes this on its minute boundary while tests inject exact
    /// values, avoiding sleeps and global clock overrides in business logic.
    public func refreshInboxReviewAvailability(at referenceDate: Date = Date()) {
        inboxVisibilityReferenceDate = referenceDate
        refreshDerivedReadModels(on: referenceDate, calendar: readModelCalendarProvider())
        ensureSelectedTaskIsVisibleInInboxFilter()
    }

    public func ensureSelectedInboxTaskIsVisible() {
        refreshInboxCaptureCacheForInbox()
        // Inbox actions and voice metadata are contextual; auto-selecting the
        // first visible item prevents a loaded Inbox from presenting disabled
        // classification controls with available work hidden in the list.
        ensureSelectedTaskIsVisibleInInboxFilter()
    }

    public func todayTasks(on referenceDate: Date = Date(), calendar: Calendar = .current) -> [ProjectBoardTask] {
        todayTasks(
            on: referenceDate,
            calendar: calendar,
            inputs: ProjectBoardDerivedReadModelInputs(
                snapshot: snapshot,
                showsCompletedWorkflowTasks: showsCompletedWorkflowTasks
            )
        )
    }

    public func markSelectedTaskAsTask() {
        guard let selectedTask else {
            return
        }

        performSelectedInboxTriage(
            action: .makeTask,
            feedback: InboxClassificationFeedback(
                message: String(format: String(localized: "Kept \"%@\" as a task."), selectedTask.title),
                systemImage: "checkmark.circle",
                canUndo: true
            )
        )
    }

    public func convertSelectedTaskToProject() {
        guard let selectedTask else {
            return
        }

        performSelectedInboxTriage(
            action: .makeProject,
            feedback: InboxClassificationFeedback(
                message: String(format: String(localized: "Created project \"%@\"."), selectedTask.title),
                systemImage: "folder.badge.plus",
                canUndo: true
            )
        )
    }

    public func scheduleSelectedTaskForToday(referenceDate: Date = Date()) {
        guard let selectedTask else {
            return
        }

        performSelectedInboxTriage(
            action: .scheduleToday,
            referenceDate: referenceDate,
            feedback: InboxClassificationFeedback(
                message: String(format: String(localized: "Scheduled \"%@\" for today."), selectedTask.title),
                systemImage: "calendar.badge.plus",
                canUndo: true
            )
        )
    }

    public func deferSelectedTaskForLater(referenceDate: Date = Date()) {
        guard let selectedTask else {
            return
        }

        performSelectedInboxTriage(
            action: .reviewLater,
            referenceDate: referenceDate,
            feedback: InboxClassificationFeedback(
                message: String(format: String(localized: "Deferred \"%@\" for later review."), selectedTask.title),
                systemImage: "clock",
                canUndo: true
            )
        )
    }

    @discardableResult
    public func applyInboxVoiceTriageCommand(
        _ command: InboxVoiceTriageCommand,
        referenceDate: Date = Date()
    ) -> Bool {
        switch command.action {
        case .selectNext:
            return selectNextInboxTaskFromVoiceTriage()
        case .undo:
            guard lastInboxClassificationUndo != nil else {
                recordOperationFailure("There is no Inbox voice triage action to undo.")
                return false
            }
            undoLastInboxClassification()
            return errorMessage == nil
        case .scheduleToday:
            guard let selectedTask = selectedInboxTaskForVoiceTriage() else {
                return false
            }
            scheduleSelectedTaskForToday(referenceDate: referenceDate)
            return snapshot.projects.flatMap(\.tasks).first { $0.id == selectedTask.id }?.dueAt != selectedTask.dueAt
                && errorMessage == nil
        case .reviewLater:
            guard let selectedTask = selectedInboxTaskForVoiceTriage() else {
                return false
            }
            deferSelectedTaskForLater(referenceDate: referenceDate)
            let record = inboxTriageRecordsByTaskID[selectedTask.id]
            return record?.disposition == .reviewLater && errorMessage == nil
        case .complete:
            guard let selectedTask = selectedInboxTaskForVoiceTriage() else {
                return false
            }
            performSelectedInboxTriage(
                action: .complete,
                feedback: InboxClassificationFeedback(
                    message: String(format: String(localized: "Completed \"%@\"."), selectedTask.title),
                    systemImage: "checkmark.circle.fill",
                    canUndo: true
                )
            )
            return snapshot.projects.flatMap(\.tasks).first { $0.id == selectedTask.id }?.status == .done
                && errorMessage == nil
        case .setPriority(let priority):
            guard let selectedTask = selectedInboxTaskForVoiceTriage() else {
                return false
            }
            applyInboxTaskUpdate(
                originalTask: selectedTask,
                draft: ProjectBoardTaskDraft(
                    projectID: selectedTask.projectID,
                    title: selectedTask.title,
                    detail: selectedTask.detail,
                    status: selectedTask.status,
                    priority: priority,
                    dueAt: selectedTask.dueAt,
                    recurrence: selectedTask.recurrence
                ),
                feedback: InboxClassificationFeedback(
                    message: String(format: String(localized: "Set \"%@\" to %@ priority."), selectedTask.title, priority.label),
                    systemImage: "flag",
                    canUndo: true
                )
            )
            return snapshot.projects.flatMap(\.tasks).first { $0.id == selectedTask.id }?.priority == priority
                && errorMessage == nil
        }
    }

    public func undoLastInboxClassification() {
        guard let undo = lastInboxClassificationUndo else {
            return
        }

        do {
            let restoredTask: ProjectBoardTask
            switch undo {
            case .restoreMutation(let mutation, let regenerated):
                restoredTask = try undoInboxTriageOperation(
                    mutation: mutation,
                    regenerated: regenerated
                )
            case .restoreTask(let originalTask):
                restoredTask = try store.updateTask(id: originalTask.id, originalTask.classificationDraft)
            case .restoreTaskAndDeleteProject(let originalTask, let createdProjectID):
                let recreatedTask = try store.createTask(originalTask.classificationDraft)
                // Project conversion deletes the original Inbox task with its
                // project. Move capture metadata first so voice memos keep their
                // transcript and retry state across Undo.
                _ = try inboxCaptureStore?.relinkCaptures(fromTaskID: originalTask.id, toTaskID: recreatedTask.id)
                do {
                    try store.deleteProject(id: createdProjectID)
                } catch {
                    try? store.deleteTask(id: recreatedTask.id)
                    throw error
                }
                restoredTask = recreatedTask
            }
            load()
            refreshDerivedReadModels(
                on: inboxVisibilityReferenceDate ?? readModelNow(),
                calendar: readModelCalendarProvider()
            )
            selectedProjectID = restoredTask.projectID
            selectedTaskID = restoredTask.id
            inboxClassificationFeedback = nil
            lastInboxClassificationUndo = nil
            clearErrorAfterSuccessfulLoad()
            onChange()
        } catch ProjectBoardStoreError.archivedProjectCannotAcceptTasks {
            recordOperationFailure("Restore the project before undoing the classification.")
        } catch ProjectBoardStoreError.emptyTitle {
            recordOperationFailure("Task title is required.")
        } catch {
            recordOperationFailure(LocalWorkspaceFailureMessage.message(for: error))
        }
    }

    private func performSelectedInboxTriage(
        action: InboxTriageAction,
        referenceDate: Date? = nil,
        feedback: InboxClassificationFeedback
    ) {
        guard let selectedTask else {
            return
        }

        do {
            let taskIDsBeforeMutation = visibleTaskIDsForUndoDiff()
            let mutation = try store.performInboxTriage(
                taskID: selectedTask.id,
                action: action,
                referenceDate: referenceDate ?? readModelNow(),
                calendar: readModelCalendarProvider()
            )
            let shouldAdvanceInboxSelection = inboxProject?.id == selectedTask.projectID
            load()
            refreshDerivedReadModels(
                on: inboxVisibilityReferenceDate ?? readModelNow(),
                calendar: readModelCalendarProvider()
            )
            let regenerated = regeneratedTasksAfterMutation(notIn: taskIDsBeforeMutation).first
            selectedProjectID = mutation.updatedTask.projectID
            selectedTaskID = mutation.updatedTask.id

            if shouldAdvanceInboxSelection,
               let nextInboxTask = filteredInboxTasks.first(where: { $0.id != selectedTask.id }) {
                selectedProjectID = nextInboxTask.projectID
                selectedTaskID = nextInboxTask.id
            }

            inboxClassificationFeedback = feedback
            lastInboxClassificationUndo = .restoreMutation(
                mutation: mutation,
                regenerated: regenerated
            )
            clearErrorAfterSuccessfulLoad()
            onChange()
        } catch ProjectBoardStoreError.archivedProjectCannotAcceptTasks {
            recordOperationFailure("Restore the project before editing tasks.")
        } catch ProjectBoardStoreError.emptyProjectTitle {
            recordOperationFailure("Project title is required.")
        } catch ProjectBoardStoreError.emptyTitle {
            recordOperationFailure("Task title is required.")
        } catch {
            recordOperationFailure(LocalWorkspaceFailureMessage.message(
                for: error,
                fallback: String(localized: "Inbox triage update failed.")
            ))
        }
    }

    private func applyInboxTaskUpdate(
        originalTask: ProjectBoardTask,
        draft: ProjectBoardTaskDraft,
        feedback: InboxClassificationFeedback
    ) {
        do {
            let updatedTask = try store.updateTask(id: originalTask.id, draft)
            finishInboxClassification(
                originalTask: originalTask,
                fallbackTask: updatedTask,
                feedback: feedback,
                undo: .restoreTask(originalTask: originalTask)
            )
            onChange()
        } catch ProjectBoardStoreError.archivedProjectCannotAcceptTasks {
            recordOperationFailure("Restore the project before editing tasks.")
        } catch ProjectBoardStoreError.emptyTitle {
            recordOperationFailure("Task title is required.")
        } catch {
            recordOperationFailure(LocalWorkspaceFailureMessage.message(for: error))
        }
    }

    private func finishInboxClassification(
        originalTask: ProjectBoardTask,
        fallbackTask: ProjectBoardTask,
        feedback: InboxClassificationFeedback,
        undo: InboxClassificationUndo
    ) {
        let shouldAdvanceInboxSelection = inboxProject?.id == originalTask.projectID
        load()
        selectedProjectID = fallbackTask.projectID
        selectedTaskID = fallbackTask.id

        if shouldAdvanceInboxSelection, let nextInboxTask = filteredInboxTasks.first(where: { $0.id != originalTask.id }) {
            selectedProjectID = nextInboxTask.projectID
            selectedTaskID = nextInboxTask.id
        }

        inboxClassificationFeedback = feedback
        lastInboxClassificationUndo = undo
        clearErrorAfterSuccessfulLoad()
    }

    private func ensureSelectedTaskIsVisibleInInboxFilter() {
        let visibleTasks = filteredInboxTasks
        guard let selectedTaskID else {
            if let first = visibleTasks.first {
                selectedProjectID = first.projectID
                self.selectedTaskID = first.id
            }
            return
        }

        guard !visibleTasks.contains(where: { $0.id == selectedTaskID }) else {
            return
        }

        selectedProjectID = visibleTasks.first?.projectID ?? inboxProject?.id
        self.selectedTaskID = visibleTasks.first?.id
    }

    private func selectedInboxTaskForVoiceTriage() -> ProjectBoardTask? {
        guard let selectedTask,
              inboxProject?.id == selectedTask.projectID,
              filteredInboxTasks.contains(where: { $0.id == selectedTask.id }) else {
            recordOperationFailure("Select an Inbox item before using voice triage.")
            return nil
        }
        return selectedTask
    }

    private func selectNextInboxTaskFromVoiceTriage() -> Bool {
        let visibleTasks = filteredInboxTasks
        guard let selectedTaskID,
              let currentIndex = visibleTasks.firstIndex(where: { $0.id == selectedTaskID }) else {
            recordOperationFailure("Select an Inbox item before using voice triage.")
            return false
        }

        let nextIndex = visibleTasks.index(after: currentIndex)
        guard nextIndex < visibleTasks.endIndex else {
            recordOperationFailure("There is no next Inbox item.")
            return false
        }

        let nextTask = visibleTasks[nextIndex]
        // Voice triage changes only local UI selection here. It deliberately
        // avoids store writes so "next" cannot accidentally mutate task data.
        selectedProjectID = nextTask.projectID
        self.selectedTaskID = nextTask.id
        inboxClassificationFeedback = InboxClassificationFeedback(
            message: String(format: String(localized: "Selected \"%@\"."), nextTask.title),
            systemImage: "arrow.down.circle",
            canUndo: false
        )
        recordOperationFailure(nil)
        return true
    }

    private func matchesInboxTriageFilter(_ task: ProjectBoardTask, filter: InboxTriageFilter) -> Bool {
        guard filter != .all else {
            return true
        }

        let captures = captureRecords(for: task.id)
        switch filter {
        case .all:
            return true
        case .voice:
            return captures.contains { $0.sourceKind == .voiceMemo }
        case .aiSuggested:
            return captures.contains {
                $0.transcriptionStatus == .succeeded
                    && $0.interpretationSummary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            }
        case .manual:
            return captures.isEmpty
        case .unprocessed:
            return isInboxUnprocessed(task, at: inboxVisibilityReferenceDate ?? readModelNow())
        }
    }

    private func isInboxUnprocessed(_ task: ProjectBoardTask, at referenceDate: Date) -> Bool {
        guard task.status != .done else {
            return false
        }

        let legacyDisposition: InboxTriageDisposition = task.dueAt == nil ? .unprocessed : .scheduled
        switch inboxTriageRecordsByTaskID[task.id]?.disposition ?? legacyDisposition {
        case .unprocessed:
            return true
        case .reviewLater:
            guard let rawReviewAt = inboxTriageRecordsByTaskID[task.id]?.reviewAt,
                  let reviewAt = ISO8601DateFormatter().date(from: rawReviewAt) else {
                // Corrupt deferred metadata must not silently hide captured work.
                return true
            }
            return reviewAt <= referenceDate
        case .task, .scheduled, .project:
            return false
        }
    }

    func inboxUnprocessedCount(at referenceDate: Date) -> Int {
        inboxTasks.reduce(into: 0) { count, task in
            if isInboxUnprocessed(task, at: referenceDate) {
                count += 1
            }
        }
    }

    private func captureRecords(for taskID: Int64, reportErrors: Bool = false) -> [InboxCaptureRecord] {
        if let records = inboxCaptureRecordsByTaskID[taskID] {
            return records
        }
        guard let inboxCaptureStore else {
            // Older test/runtime surfaces can instantiate the board without
            // capture metadata. Treat those items as manual captures so the
            // Inbox remains usable instead of hiding work behind a missing store.
            return []
        }

        do {
            let records = try inboxCaptureStore.list(taskID: taskID)
            inboxCaptureRecordsByTaskID[taskID] = records
            return records
        } catch {
            if reportErrors {
                recordOperationFailure(InboxCaptureStoreError.userMessage(for: error))
            }
            return []
        }
    }

    func refreshInboxCaptureCache(for snapshot: ProjectBoardSnapshot) -> String? {
        guard let inboxCaptureStore else {
            inboxCaptureRecordsByTaskID = [:]
            return nil
        }

        let taskIDs = Self.inboxTaskIDs(in: snapshot)
        do {
            inboxCaptureRecordsByTaskID = try inboxCaptureStore.list(taskIDs: taskIDs)
            return nil
        } catch {
            inboxCaptureRecordsByTaskID = Dictionary(uniqueKeysWithValues: taskIDs.map { ($0, [InboxCaptureRecord]()) })
            return InboxCaptureStoreError.userMessage(for: error)
        }
    }

    private func refreshInboxCaptureCacheForInbox() {
        if let errorMessage = refreshInboxCaptureCache(for: snapshot) {
            recordOperationFailure(errorMessage)
        }
    }

    func refreshInboxTriageCache(for snapshot: ProjectBoardSnapshot) -> String? {
        let taskIDs = Self.inboxTaskIDs(in: snapshot)
        guard !taskIDs.isEmpty else {
            inboxTriageRecordsByTaskID = [:]
            inboxTriageErrorMessage = nil
            return nil
        }
        do {
            inboxTriageRecordsByTaskID = try store.loadInboxTriageRecords(taskIDs: taskIDs)
            inboxTriageErrorMessage = nil
            return nil
        } catch {
            // Missing or temporarily unavailable metadata must not hide Inbox
            // rows. The filter derives a conservative legacy disposition from
            // each task until the next successful load.
            inboxTriageRecordsByTaskID = [:]
            let message = LocalWorkspaceFailureMessage.message(
                for: error,
                fallback: String(localized: "Inbox triage state unavailable.")
            )
            inboxTriageErrorMessage = message
            return message
        }
    }

    private static func inboxTaskIDs(in snapshot: ProjectBoardSnapshot) -> Set<Int64> {
        guard let inboxProject = snapshot.projects.first(where: {
            $0.title.caseInsensitiveCompare("Inbox") == .orderedSame && !$0.isArchived
        }) else {
            return []
        }
        return Set(inboxProject.tasks.map(\.id))
    }

    private func replaceCachedCapture(_ updated: InboxCaptureRecord) {
        var records = inboxCaptureRecordsByTaskID[updated.taskID] ?? []
        if let index = records.firstIndex(where: { $0.id == updated.id }) {
            records[index] = updated
        } else {
            records.insert(updated, at: 0)
        }
        inboxCaptureRecordsByTaskID[updated.taskID] = records.sorted { $0.id > $1.id }
    }

    private static func inboxInterpretationConfidence(from memo: String?) -> String? {
        guard let memo else {
            return nil
        }
        let prefix = "Confidence:"
        guard let range = memo.range(of: prefix, options: [.caseInsensitive]) else {
            return nil
        }
        let value = memo[range.upperBound...]
            .split(whereSeparator: { $0 == "," || $0 == "\n" })
            .first
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        return value?.isEmpty == false ? value : nil
    }
}
