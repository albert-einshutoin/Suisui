import Foundation

extension ProjectBoardViewModel {

    func todayTasks(
        on referenceDate: Date,
        calendar: Calendar,
        inputs: ProjectBoardDerivedReadModelInputs
    ) -> [ProjectBoardTask] {
        guard let endOfToday = calendar.dateInterval(of: .day, for: referenceDate)?.end else {
            return []
        }

        return inputs.visibleNonArchivedTasks
            .filter { task in
                LocalPlanningPolicy.dueDate(for: task.dueAt, calendar: calendar).map { $0 < endOfToday } == true
            }
            .sorted { lhs, rhs in
                switch (LocalPlanningPolicy.dueDate(for: lhs.dueAt, calendar: calendar), LocalPlanningPolicy.dueDate(for: rhs.dueAt, calendar: calendar)) {
                case let (lhsDate?, rhsDate?):
                    if lhsDate == rhsDate {
                        return lhs.id > rhs.id
                    }
                    return lhsDate < rhsDate
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return lhs.id > rhs.id
                }
            }
    }

    public func unscheduledScheduleTasks() -> [ProjectBoardTask] {
        let draftedTaskIDs = Set(scheduleDraft?.timeBlocks.map(\.task.id) ?? [])
        return unscheduledScheduleTasks(
            excludingTaskIDs: draftedTaskIDs,
            inputs: ProjectBoardDerivedReadModelInputs(
                snapshot: snapshot,
                showsCompletedWorkflowTasks: showsCompletedWorkflowTasks
            )
        )
    }

    func unscheduledScheduleTasks(excludingTaskIDs excludedTaskIDs: Set<Int64>) -> [ProjectBoardTask] {
        unscheduledScheduleTasks(
            excludingTaskIDs: excludedTaskIDs,
            inputs: ProjectBoardDerivedReadModelInputs(
                snapshot: snapshot,
                showsCompletedWorkflowTasks: showsCompletedWorkflowTasks
            )
        )
    }

    func unscheduledScheduleTasks(
        excludingTaskIDs excludedTaskIDs: Set<Int64>,
        inputs: ProjectBoardDerivedReadModelInputs
    ) -> [ProjectBoardTask] {
        inputs.committedActiveProjects
            .flatMap(\.tasks)
            .filter { task in
                task.status != .done && task.dueAt == nil && !excludedTaskIDs.contains(task.id)
            }
            .sorted { lhs, rhs in
                if lhs.priority.sortRank != rhs.priority.sortRank {
                    return lhs.priority.sortRank < rhs.priority.sortRank
                }
                return lhs.id > rhs.id
            }
    }

    public func dailyWorkloadOverview(
        around referenceDate: Date = Date(),
        calendar: Calendar = .current,
        visibleDayCount: Int = 7
    ) -> DailyWorkloadOverview {
        dailyWorkloadOverview(
            around: referenceDate,
            calendar: calendar,
            visibleDayCount: visibleDayCount,
            inputs: ProjectBoardDerivedReadModelInputs(
                snapshot: snapshot,
                showsCompletedWorkflowTasks: showsCompletedWorkflowTasks,
                inboxUntriagedCountOverride: inboxUnprocessedCount(at: referenceDate)
            )
        )
    }

    private func dailyWorkloadOverview(
        around referenceDate: Date,
        calendar: Calendar,
        visibleDayCount: Int = 7,
        inputs: ProjectBoardDerivedReadModelInputs
    ) -> DailyWorkloadOverview {
        DailyWorkloadDashboardBuilder.overview(
            committedProjects: inputs.committedActiveProjects,
            inboxUntriagedCount: inputs.inboxUntriagedCount,
            around: referenceDate,
            calendar: calendar,
            visibleDayCount: visibleDayCount
        )
    }

    public func weeklyScheduleCockpit(
        around referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> WeeklyScheduleCockpit {
        let workload = dailyWorkloadOverview(around: referenceDate, calendar: calendar)
        return WeeklyScheduleCockpitBuilder.cockpit(
            from: snapshot,
            workload: workload,
            scheduleDraft: scheduleDraft,
            around: referenceDate,
            calendar: calendar
        )
    }

    private func weeklyScheduleCockpit(
        around referenceDate: Date,
        calendar: Calendar,
        workload: DailyWorkloadOverview,
        inputs: ProjectBoardDerivedReadModelInputs
    ) -> WeeklyScheduleCockpit {
        WeeklyScheduleCockpitBuilder.cockpit(
            projectTitles: Dictionary(uniqueKeysWithValues: inputs.nonArchivedProjects.map { ($0.id, $0.title) }),
            completionHistoryTasks: inputs.committedActiveProjects.flatMap(\.tasks),
            workload: workload,
            scheduleDraft: scheduleDraft,
            around: referenceDate,
            calendar: calendar
        )
    }

    public func refreshDerivedReadModels() {
        rebuildDerivedReadModels(on: readModelNow(), calendar: readModelCalendarProvider())
    }

    public func refreshDerivedReadModels(on referenceDate: Date, calendar: Calendar = .current) {
        rebuildDerivedReadModels(on: referenceDate, calendar: calendar)
    }

    public func invalidateTodayWorkflowSnapshot(_ reason: TodaySnapshotInvalidationReason) {
        // A revision is cheaper and safer than attempting to diff every task:
        // all store mutations already pass through load(), while the day key
        // separately handles midnight, DST, timezone, and calendar changes.
        todaySnapshotSourceRevision &+= 1
        dailyPlanningReviewPreviewCache.invalidate()
    }

    public func refreshScheduleReadModel() {
        rebuildScheduleReadModel(around: readModelNow(), calendar: readModelCalendarProvider())
        refreshExternalScheduleEvents()
    }

    public func refreshScheduleReadModel(around referenceDate: Date, calendar: Calendar = .current) {
        rebuildScheduleReadModel(around: referenceDate, calendar: calendar)
        refreshExternalScheduleEvents(around: referenceDate, calendar: calendar)
    }

    public func refreshExternalScheduleEvents(
        around referenceDate: Date? = nil,
        calendar: Calendar? = nil,
        force: Bool = false
    ) {
        guard let externalScheduleEventSource else {
            externalScheduleEvents = []
            externalScheduleEventLoadState = .unavailable
            externalScheduleEventInterval = nil
            return
        }
        let resolvedCalendar = calendar ?? derivedReadModelCalendar
        let resolvedDate = referenceDate ?? derivedReadModelReferenceDate ?? readModelNow()
        guard let interval = resolvedCalendar.dateInterval(of: .weekOfYear, for: resolvedDate) else {
            externalScheduleEvents = []
            externalScheduleEventLoadState = .failed
            return
        }
        if force == false,
           interval == externalScheduleEventInterval,
           (externalScheduleEventLoadState == .loaded || externalScheduleEventLoadState == .loading) {
            return
        }

        externalScheduleEventRefreshRevision &+= 1
        let refreshRevision = externalScheduleEventRefreshRevision
        externalScheduleEventInterval = interval
        externalScheduleEventLoadState = .loading

        Task { @MainActor [weak self] in
            let result = await Task.detached(priority: .utility) {
                Result { try externalScheduleEventSource.listEvents(in: interval) }
            }.value
            guard let self, self.externalScheduleEventRefreshRevision == refreshRevision else { return }
            switch result {
            case let .success(events):
                self.externalScheduleEvents = events.sorted { $0.startAt < $1.startAt }
                self.externalScheduleEventLoadState = .loaded
            case .failure:
                // Calendar contents and provider errors remain transient and are never persisted or logged.
                self.externalScheduleEvents = []
                self.externalScheduleEventLoadState = .failed
            }
        }
    }

    func rebuildDerivedReadModels(on referenceDate: Date, calendar: Calendar) {
        let inputs = ProjectBoardDerivedReadModelInputs(
            snapshot: snapshot,
            showsCompletedWorkflowTasks: showsCompletedWorkflowTasks,
            inboxUntriagedCountOverride: inboxUnprocessedCount(at: referenceDate)
        )
        let todayPlan = todayPlan(on: referenceDate, calendar: calendar, inputs: inputs)
        let workloadOverview = dailyWorkloadOverview(
            around: referenceDate,
            calendar: calendar,
            inputs: inputs
        )
        let planningDayKey = PlanningDayKey(referenceDate: referenceDate, calendar: calendar)
        let dailyPlanningReviewPreview = makeCachedDailyPlanningReviewPreview(
            plan: todayPlan,
            workload: workloadOverview,
            referenceDate: referenceDate,
            calendar: calendar,
            planningDayKey: planningDayKey
        )
        let todayWorkflowSnapshot = todayWorkflowSnapshot(
            from: todayPlan,
            on: referenceDate,
            calendar: calendar,
            planningDayKey: planningDayKey,
            dailyPlanningReviewPreview: dailyPlanningReviewPreview
        )
        let scheduleReadModel = makeScheduleReadModel(
            around: referenceDate,
            calendar: calendar,
            workloadOverview: workloadOverview,
            inputs: inputs
        )
        let doneAnalytics = doneAnalytics(on: referenceDate, calendar: calendar, inputs: inputs)
        let portfolioSummaries = projectPortfolioSummaries(on: referenceDate, calendar: calendar, inputs: inputs)
        let missedReview = missedTaskReview(on: referenceDate, calendar: calendar, inputs: inputs)

        derivedReadModelReferenceDate = referenceDate
        derivedReadModelCalendar = calendar

        // SwiftUI body rendering reads this compact model so repeated sidebar and
        // workflow updates do not rescan every project/task or refresh local stores.
        derivedReadModels = ProjectBoardDerivedReadModels(
            sidebarMetrics: ProjectBoardSidebarMetrics(
                inboxCount: inputs.inboxUntriagedCount,
                todayCount: todayWorkflowSnapshot.plan.tasks.count,
                catchUpCount: missedReview.newlyMissedCount,
                scheduleCount: scheduleReadModel.unscheduledTasks.count,
                doneCount: doneAnalytics.completedTaskCount,
                projectsCount: portfolioSummaries.count
            ),
            todayWorkflowSnapshot: todayWorkflowSnapshot,
            schedule: scheduleReadModel,
            doneAnalytics: doneAnalytics,
            missedTaskReview: missedReview,
            projectPortfolioSummaries: portfolioSummaries,
            builtAt: referenceDate
        )
    }

    func rebuildScheduleReadModel(around referenceDate: Date, calendar: Calendar) {
        var nextReadModels = derivedReadModels
        let scheduleReadModel = makeScheduleReadModel(around: referenceDate, calendar: calendar)
        nextReadModels.schedule = scheduleReadModel
        nextReadModels.sidebarMetrics.scheduleCount = scheduleReadModel.unscheduledTasks.count
        derivedReadModels = nextReadModels
    }

    private func makeScheduleReadModel(
        around referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> ProjectBoardScheduleReadModel {
        makeScheduleReadModel(
            around: referenceDate,
            calendar: calendar,
            inputs: ProjectBoardDerivedReadModelInputs(
                snapshot: snapshot,
                showsCompletedWorkflowTasks: showsCompletedWorkflowTasks
            )
        )
    }

    private func makeScheduleReadModel(
        around referenceDate: Date,
        calendar: Calendar,
        inputs: ProjectBoardDerivedReadModelInputs
    ) -> ProjectBoardScheduleReadModel {
        let workloadOverview = dailyWorkloadOverview(around: referenceDate, calendar: calendar, inputs: inputs)
        return makeScheduleReadModel(
            around: referenceDate,
            calendar: calendar,
            workloadOverview: workloadOverview,
            inputs: inputs
        )
    }

    private func makeScheduleReadModel(
        around referenceDate: Date,
        calendar: Calendar,
        workloadOverview: DailyWorkloadOverview,
        inputs: ProjectBoardDerivedReadModelInputs
    ) -> ProjectBoardScheduleReadModel {
        let weeklyCockpit = weeklyScheduleCockpit(
            around: referenceDate,
            calendar: calendar,
            workload: workloadOverview,
            inputs: inputs
        )
        let draftedTaskIDs = Set(scheduleDraft?.timeBlocks.map(\.task.id) ?? [])
        return ProjectBoardScheduleReadModel(
            workloadOverview: workloadOverview,
            weeklyCockpit: weeklyCockpit,
            unscheduledTasks: unscheduledScheduleTasks(excludingTaskIDs: draftedTaskIDs, inputs: inputs)
        )
    }

    func refreshMissedTaskReviewReadModel(on referenceDate: Date? = nil) {
        let resolvedReferenceDate = referenceDate ?? derivedReadModelReferenceDate ?? readModelNow()
        let inputs = ProjectBoardDerivedReadModelInputs(
            snapshot: snapshot,
            showsCompletedWorkflowTasks: showsCompletedWorkflowTasks
        )
        let summary = missedTaskReview(
            on: resolvedReferenceDate,
            calendar: derivedReadModelCalendar,
            inputs: inputs
        )
        var nextReadModels = derivedReadModels
        nextReadModels.missedTaskReview = summary
        nextReadModels.sidebarMetrics.catchUpCount = summary.newlyMissedCount
        nextReadModels.builtAt = resolvedReferenceDate
        derivedReadModels = nextReadModels
        derivedReadModelReferenceDate = resolvedReferenceDate
    }

    func refreshTodayDerivedReadModelForSelectionChange() {
        guard let referenceDate = derivedReadModelReferenceDate else {
            return
        }

        // Selection and focus only change the assistant rail. Reusing the
        // existing plan, preview, and chips avoids flattening every project and
        // rebuilding the time-based review for each row selection on MainActor.
        var nextReadModels = derivedReadModels
        nextReadModels.todayWorkflowSnapshot.assistantContext = todayAssistantRailContext(
            plan: nextReadModels.todayWorkflowSnapshot.plan,
            referenceDate: referenceDate,
            calendar: derivedReadModelCalendar
        )
        derivedReadModels = nextReadModels
    }

    private func makeCachedDailyPlanningReviewPreview(
        plan: TodayWorkflowPlan,
        workload: DailyWorkloadOverview,
        referenceDate: Date,
        calendar: Calendar,
        planningDayKey: PlanningDayKey
    ) -> DailyPlanningReview {
        let cacheKey = DailyPlanningReviewPreviewCacheKey(
            planningDayKey: planningDayKey,
            sourceRevision: todaySnapshotSourceRevision,
            referenceDate: referenceDate,
            calendar: calendar
        )
        return dailyPlanningReviewPreviewCache.review(for: cacheKey) {
            // Cache at the derived-model boundary: task/project mutations and
            // date/calendar changes rebuild it, while rendering and selection
            // changes reuse the immutable value without doing board work.
            self.dailyPlanningReviewPreviewBuildCount += 1
            projectBoardRuntimeDiagnosticLogger.notice(
                "suisui.dailyPlanningPreview.buildCount=\(self.dailyPlanningReviewPreviewBuildCount, privacy: .public) temporalKey=\(cacheKey.runtimeDiagnosticTemporalKey, privacy: .public)"
            )
            return DailyPlanningReviewBuilder.review(
                transcript: "Today daily planning review",
                plan: plan,
                workload: workload,
                referenceDate: referenceDate,
                calendar: calendar
            )
        }
    }

    public func todayPlan(
        on referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> TodayWorkflowPlan {
        let tasks = todayTasks(on: referenceDate, calendar: calendar)
        return todayPlan(from: tasks, on: referenceDate, calendar: calendar)
    }

    func todayPlan(
        on referenceDate: Date,
        calendar: Calendar,
        inputs: ProjectBoardDerivedReadModelInputs
    ) -> TodayWorkflowPlan {
        let tasks = todayTasks(on: referenceDate, calendar: calendar, inputs: inputs)
        return todayPlan(from: tasks, on: referenceDate, calendar: calendar)
    }

    func todayPlan(
        from tasks: [ProjectBoardTask],
        on referenceDate: Date,
        calendar: Calendar
    ) -> TodayWorkflowPlan {
        let dayInterval = calendar.dateInterval(of: .day, for: referenceDate)
        let dayStart = dayInterval?.start ?? referenceDate
        let overdueCount = tasks.filter { task in
            LocalPlanningPolicy.dueDate(for: task.dueAt, calendar: calendar).map { $0 < dayStart } == true
        }.count
        let dueTodayCount = tasks.filter { task in
            guard let dayInterval, let dueDate = LocalPlanningPolicy.dueDate(for: task.dueAt, calendar: calendar) else {
                return false
            }
            return dueDate >= dayInterval.start && dueDate < dayInterval.end
        }.count
        let recommendedTask = LocalPlanningPolicy.recommendedTodayTask(from: tasks, on: referenceDate, calendar: calendar)

        return TodayWorkflowPlan(
            tasks: tasks,
            overdueCount: overdueCount,
            dueTodayCount: dueTodayCount,
            recommendedTask: recommendedTask,
            recommendationReason: LocalPlanningPolicy.recommendationReason(for: recommendedTask, on: referenceDate, calendar: calendar),
            timeBlocks: LocalPlanningPolicy.timeBlocks(for: LocalPlanningPolicy.orderedTimeBlockTasks(tasks, recommendedTask: recommendedTask), startingAt: referenceDate, calendar: calendar)
        )
    }

    public func todayWorkflowSnapshot(
        on referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> TodayWorkflowSnapshot {
        let plan = todayPlan(on: referenceDate, calendar: calendar)
        return todayWorkflowSnapshot(
            from: plan,
            on: referenceDate,
            calendar: calendar,
            planningDayKey: PlanningDayKey(referenceDate: referenceDate, calendar: calendar)
        )
    }

    func todayWorkflowSnapshot(
        on referenceDate: Date,
        calendar: Calendar,
        inputs: ProjectBoardDerivedReadModelInputs
    ) -> TodayWorkflowSnapshot {
        let plan = todayPlan(on: referenceDate, calendar: calendar, inputs: inputs)
        return todayWorkflowSnapshot(
            from: plan,
            on: referenceDate,
            calendar: calendar,
            planningDayKey: PlanningDayKey(referenceDate: referenceDate, calendar: calendar)
        )
    }

    func todayWorkflowSnapshot(
        from plan: TodayWorkflowPlan,
        on referenceDate: Date,
        calendar: Calendar,
        planningDayKey: PlanningDayKey,
        dailyPlanningReviewPreview: DailyPlanningReview? = nil
    ) -> TodayWorkflowSnapshot {
        return TodayWorkflowSnapshot(
            plan: plan,
            assistantContext: todayAssistantRailContext(
                plan: plan,
                referenceDate: referenceDate,
                calendar: calendar
            ),
            recommendationChips: todayRecommendationChips(
                from: plan.tasks,
                on: referenceDate,
                calendar: calendar
            ),
            planningDayKey: planningDayKey,
            dailyPlanningReviewPreview: dailyPlanningReviewPreview
        )
    }

    public func makeDailyPlanningReview(
        transcript: String,
        on referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> DailyPlanningReview {
        DailyPlanningReviewBuilder.review(
            transcript: transcript,
            plan: todayPlan(on: referenceDate, calendar: calendar),
            workload: dailyWorkloadOverview(around: referenceDate, calendar: calendar),
            referenceDate: referenceDate,
            calendar: calendar
        )
    }

    @discardableResult
    public func prepareDailyPlanningReview(
        transcript: String,
        on referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> DailyPlanningReview {
        let review = makeDailyPlanningReview(
            transcript: transcript,
            on: referenceDate,
            calendar: calendar
        )
        dailyPlanningReview = review
        todayCommandFeedback = String(localized: "Prepared daily planning review.")
        return review
    }

    @discardableResult
    public func ingestAssistantQueueAutomationRequests(from payload: SyncDomainPayload) -> Bool {
        ingestAssistantQueueAutomationRequests(payload.automationRequests)
    }

    public func projectPortfolioSummaries(
        on referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> [ProjectPortfolioSummary] {
        projectPortfolioSummaries(
            on: referenceDate,
            calendar: calendar,
            inputs: ProjectBoardDerivedReadModelInputs(
                snapshot: snapshot,
                showsCompletedWorkflowTasks: showsCompletedWorkflowTasks
            )
        )
    }

    func projectPortfolioSummaries(
        on referenceDate: Date,
        calendar: Calendar,
        inputs: ProjectBoardDerivedReadModelInputs
    ) -> [ProjectPortfolioSummary] {
        WorkManagementAnalyticsBuilder.projectPortfolioSummaries(
            projects: inputs.portfolioProjects,
            on: referenceDate,
            calendar: calendar
        )
    }

    public func doneAnalytics(
        on referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> DoneAnalyticsSummary {
        doneAnalytics(
            on: referenceDate,
            calendar: calendar,
            inputs: ProjectBoardDerivedReadModelInputs(
                snapshot: snapshot,
                showsCompletedWorkflowTasks: showsCompletedWorkflowTasks
            )
        )
    }

    func doneAnalytics(
        on referenceDate: Date,
        calendar: Calendar,
        inputs: ProjectBoardDerivedReadModelInputs
    ) -> DoneAnalyticsSummary {
        WorkManagementAnalyticsBuilder.doneAnalytics(
            completedProjects: inputs.completedProjects,
            tasks: inputs.nonArchivedTasks,
            on: referenceDate,
            calendar: calendar
        )
    }

    func refreshExecutionReceiptHistorySnapshot() {
        resetScopedExecutionReceiptHistorySnapshots()
        guard executionReceiptAuditSnapshotsLoaded else {
            return
        }
        refreshExecutionReceiptAuditSnapshots()
    }

    public func refreshExecutionReceiptAuditSnapshotsIfNeeded() {
        guard !executionReceiptAuditSnapshotsLoaded else {
            return
        }
        refreshExecutionReceiptAuditSnapshots()
    }

    public func refreshExecutionReceiptAuditSnapshots() {
        executionReceiptAuditSnapshotsLoaded = true
        refreshExecutionReceiptHistorySnapshot(for: snapshot)
    }

    func resetScopedExecutionReceiptHistorySnapshots() {
        executionReceiptHistorySnapshotsByTaskID = [:]
        executionReceiptHistorySnapshotsByProjectID = [:]
    }

    public func setExecutionReceiptHistorySearchText(_ text: String) {
        guard executionReceiptHistorySearchText != text else {
            return
        }
        executionReceiptHistorySearchText = text
        clearExecutionReceiptHistoryExport()
        executionReceiptAuditSnapshotsLoaded = true
        refreshGlobalExecutionReceiptHistorySnapshot()
    }

    public func setExecutionReceiptHistoryStatusFilter(_ status: ExecutionReceiptStatus?) {
        guard executionReceiptHistoryStatusFilter != status else {
            return
        }
        executionReceiptHistoryStatusFilter = status
        clearExecutionReceiptHistoryExport()
        executionReceiptAuditSnapshotsLoaded = true
        refreshGlobalExecutionReceiptHistorySnapshot()
    }

    public func setExecutionReceiptHistoryReferenceKindFilter(_ referenceKind: ExecutionReceiptReferenceKind?) {
        guard executionReceiptHistoryReferenceKindFilter != referenceKind else {
            return
        }
        executionReceiptHistoryReferenceKindFilter = referenceKind
        clearExecutionReceiptHistoryExport()
        executionReceiptAuditSnapshotsLoaded = true
        refreshGlobalExecutionReceiptHistorySnapshot()
    }

    public func prepareExecutionReceiptHistoryExport(exportedAt: Date = Date()) {
        do {
            if !executionReceiptAuditSnapshotsLoaded {
                refreshExecutionReceiptAuditSnapshots()
            }
            let data = try ExecutionReceiptHistoryExporter.exportJSON(
                snapshot: executionReceiptHistorySnapshot,
                exportedAt: exportedAt
            )
            executionReceiptHistoryExportData = data
            executionReceiptHistoryExportMessage = exportPreparedMessage(rowCount: executionReceiptHistorySnapshot.rows.count)
        } catch {
            executionReceiptHistoryExportData = nil
            executionReceiptHistoryExportMessage = String(localized: "Receipt export could not be prepared.")
        }
    }

    public func recordExecutionReceiptHistoryExportCompleted() {
        executionReceiptHistoryExportData = nil
        executionReceiptHistoryExportMessage = String(localized: "Saved redacted receipt export JSON.")
    }

    public func recordExecutionReceiptHistoryFileFailure(_ error: Error) {
        executionReceiptHistoryExportData = nil
        executionReceiptHistoryExportMessage = String(localized: "Receipt export could not be saved.")
    }

    private func clearExecutionReceiptHistoryExport() {
        executionReceiptHistoryExportData = nil
        executionReceiptHistoryExportMessage = nil
    }

    private func executionReceiptHistoryFilter() -> ExecutionReceiptSearchFilter {
        ExecutionReceiptSearchFilter(
            query: executionReceiptHistorySearchText,
            statuses: executionReceiptHistoryStatusFilter.map { Set([$0]) } ?? [],
            referenceKinds: executionReceiptHistoryReferenceKindFilter.map { Set([$0]) } ?? [],
            visibleSurface: .auditLog
        )
    }

    private func exportPreparedMessage(rowCount: Int) -> String {
        if rowCount == 1 {
            return String(format: String(localized: "Prepared %d redacted receipt export row."), rowCount)
        }
        return String(format: String(localized: "Prepared %d redacted receipt export rows."), rowCount)
    }

    private func refreshGlobalExecutionReceiptHistorySnapshot() {
        executionReceiptAuditSnapshotsLoaded = true
        guard let executionReceiptStore else {
            executionReceiptHistorySnapshot = .empty
            return
        }

        do {
            executionReceiptHistorySnapshot = try globalExecutionReceiptHistorySnapshot(store: executionReceiptStore)
        } catch {
            executionReceiptHistorySnapshot = ExecutionReceiptHistorySnapshot(
                rows: [],
                unavailableMessage: String(localized: "Execution receipts are unavailable.")
            )
        }
    }

    func globalExecutionReceiptHistorySnapshot(
        store: any ExecutionReceiptStore
    ) throws -> ExecutionReceiptHistorySnapshot {
        let receipts = try store.list(matching: executionReceiptHistoryFilter(), limit: 100)
        // Reconcile the already-loaded durable receipts after a crash between
        // execution and measurement. This does not scan any additional work.
        receipts.forEach { recordPublicAlphaExecution($0, isRecovery: true) }
        return ExecutionReceiptHistoryReadModel.snapshot(
            from: receipts,
            limit: 10
        )
    }
}
