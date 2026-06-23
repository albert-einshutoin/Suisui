import Foundation

public enum TaskAutoExecutionMode: String, Codable, CaseIterable, Equatable, Sendable {
    case reviewOnly

    public var label: String {
        switch self {
        case .reviewOnly:
            "Review before execution"
        }
    }
}

public enum TaskAutoExecutionCadence: String, Codable, CaseIterable, Equatable, Sendable {
    case manual
    case hourly
    case daily

    public var label: String {
        switch self {
        case .manual:
            "Manual review"
        case .hourly:
            "Hourly review"
        case .daily:
            "Daily review"
        }
    }

    var minimumInterval: TimeInterval? {
        switch self {
        case .manual:
            nil
        case .hourly:
            60 * 60
        case .daily:
            24 * 60 * 60
        }
    }
}

public struct TaskAutoExecutionSettings: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var mode: TaskAutoExecutionMode
    public var cadence: TaskAutoExecutionCadence
    public var maxTasksPerRun: Int
    public var dailyLLMCallLimit: Int
    public var lookaheadHours: Int
    public var urgentReviewCooldownMinutes: Int

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case mode
        case cadence
        case maxTasksPerRun
        case dailyLLMCallLimit
        case lookaheadHours
        case urgentReviewCooldownMinutes
    }

    public init(
        isEnabled: Bool = false,
        mode: TaskAutoExecutionMode = .reviewOnly,
        cadence: TaskAutoExecutionCadence = .manual,
        maxTasksPerRun: Int = 3,
        dailyLLMCallLimit: Int = 6,
        lookaheadHours: Int = 48,
        urgentReviewCooldownMinutes: Int = 60
    ) {
        self.isEnabled = isEnabled
        self.mode = mode
        self.cadence = cadence
        self.maxTasksPerRun = maxTasksPerRun
        self.dailyLLMCallLimit = dailyLLMCallLimit
        self.lookaheadHours = lookaheadHours
        self.urgentReviewCooldownMinutes = urgentReviewCooldownMinutes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        self.mode = try container.decode(TaskAutoExecutionMode.self, forKey: .mode)
        self.cadence = try container.decode(TaskAutoExecutionCadence.self, forKey: .cadence)
        self.maxTasksPerRun = try container.decode(Int.self, forKey: .maxTasksPerRun)
        self.dailyLLMCallLimit = try container.decode(Int.self, forKey: .dailyLLMCallLimit)
        self.lookaheadHours = try container.decode(Int.self, forKey: .lookaheadHours)
        self.urgentReviewCooldownMinutes = try container.decodeIfPresent(Int.self, forKey: .urgentReviewCooldownMinutes) ?? 60
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(mode, forKey: .mode)
        try container.encode(cadence, forKey: .cadence)
        try container.encode(maxTasksPerRun, forKey: .maxTasksPerRun)
        try container.encode(dailyLLMCallLimit, forKey: .dailyLLMCallLimit)
        try container.encode(lookaheadHours, forKey: .lookaheadHours)
        try container.encode(urgentReviewCooldownMinutes, forKey: .urgentReviewCooldownMinutes)
    }

    public static let `default` = TaskAutoExecutionSettings()

    public var normalized: TaskAutoExecutionSettings {
        var copy = self
        copy.maxTasksPerRun = min(max(copy.maxTasksPerRun, 1), 10)
        copy.dailyLLMCallLimit = min(max(copy.dailyLLMCallLimit, 1), 48)
        copy.lookaheadHours = min(max(copy.lookaheadHours, 1), 24 * 30)
        copy.urgentReviewCooldownMinutes = min(max(copy.urgentReviewCooldownMinutes, 5), 24 * 60)
        return copy
    }

    public func validationIssues() -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        if maxTasksPerRun < 1 || maxTasksPerRun > 10 {
            issues.append(ValidationIssue(field: "taskAutoExecution.maxTasksPerRun", message: "Task automation must review between 1 and 10 tasks per run.", severity: .error))
        }
        if dailyLLMCallLimit < 1 || dailyLLMCallLimit > 48 {
            issues.append(ValidationIssue(field: "taskAutoExecution.dailyLLMCallLimit", message: "Task automation daily LLM call limit must be between 1 and 48.", severity: .error))
        }
        if lookaheadHours < 1 || lookaheadHours > 24 * 30 {
            issues.append(ValidationIssue(field: "taskAutoExecution.lookaheadHours", message: "Task automation lookahead must be between 1 hour and 30 days.", severity: .error))
        }
        if urgentReviewCooldownMinutes < 5 || urgentReviewCooldownMinutes > 24 * 60 {
            issues.append(ValidationIssue(field: "taskAutoExecution.urgentReviewCooldownMinutes", message: "Urgent task automation cooldown must be between 5 minutes and 24 hours.", severity: .error))
        }
        return issues
    }
}

public struct TaskAutoExecutionHistory: Equatable, Sendable {
    public var lastRunAt: Date?
    public var llmCallsToday: Int

    public init(lastRunAt: Date?, llmCallsToday: Int) {
        self.lastRunAt = lastRunAt
        self.llmCallsToday = llmCallsToday
    }

    public static let empty = TaskAutoExecutionHistory(lastRunAt: nil, llmCallsToday: 0)
}

public enum TaskAutoExecutionDecisionStatus: String, Codable, Equatable, Sendable {
    case disabled
    case throttled
    case budgetExhausted
    case noCandidates
    case readyForReview
}

public struct TaskAutoExecutionDecision: Equatable, Sendable {
    public var status: TaskAutoExecutionDecisionStatus
    public var selectedTasks: [ProjectBoardTask]
    public var reason: String
    public var llmCallBudgetRemaining: Int
    public var requiresUserApproval: Bool
    public var allowsDirectExecution: Bool

    public init(
        status: TaskAutoExecutionDecisionStatus,
        selectedTasks: [ProjectBoardTask],
        reason: String,
        llmCallBudgetRemaining: Int,
        requiresUserApproval: Bool,
        allowsDirectExecution: Bool
    ) {
        self.status = status
        self.selectedTasks = selectedTasks
        self.reason = reason
        self.llmCallBudgetRemaining = llmCallBudgetRemaining
        self.requiresUserApproval = requiresUserApproval
        self.allowsDirectExecution = allowsDirectExecution
    }

    public var shouldCallLLM: Bool {
        status == .readyForReview && !selectedTasks.isEmpty && llmCallBudgetRemaining > 0
    }
}

public struct TaskAutoExecutionPlanner: Sendable {
    public init() {}

    public func makeDecision(
        snapshot: ProjectBoardSnapshot,
        settings rawSettings: TaskAutoExecutionSettings,
        history: TaskAutoExecutionHistory,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> TaskAutoExecutionDecision {
        let settings = rawSettings.normalized
        let remainingBudget = max(settings.dailyLLMCallLimit - history.llmCallsToday, 0)

        guard settings.isEnabled else {
            return decision(.disabled, reason: "Task automation is disabled.", remainingBudget: remainingBudget)
        }
        guard remainingBudget > 0 else {
            return decision(.budgetExhausted, reason: "Daily LLM automation budget is exhausted.", remainingBudget: remainingBudget)
        }
        let candidates = rankedCandidates(
            from: snapshot,
            settings: settings,
            referenceDate: referenceDate,
            calendar: calendar
        )
        guard !candidates.isEmpty else {
            return decision(.noCandidates, reason: "No eligible tasks match the current priority and due-date window.", remainingBudget: remainingBudget)
        }
        let selectedCandidates: [ProjectBoardTask]
        if let minimumInterval = settings.cadence.minimumInterval,
           let lastRunAt = history.lastRunAt,
           referenceDate.timeIntervalSince(lastRunAt) < minimumInterval {
            let urgentCooldown = TimeInterval(settings.urgentReviewCooldownMinutes) * 60
            let urgentCandidates = candidates.filter {
                isUrgent(task: $0, referenceDate: referenceDate, calendar: calendar)
            }
            if urgentCooldown < minimumInterval, !urgentCandidates.isEmpty {
                guard referenceDate.timeIntervalSince(lastRunAt) >= urgentCooldown else {
                    return decision(.throttled, reason: "Urgent task automation cooldown has not elapsed.", remainingBudget: remainingBudget)
                }
                // Urgency override is intentionally narrow: it spends an extra
                // provider call only on overdue or due-today work instead of
                // dragging routine future tasks into the same LLM review.
                selectedCandidates = urgentCandidates
            } else {
                return decision(.throttled, reason: "Task automation cadence has not elapsed.", remainingBudget: remainingBudget)
            }
        } else {
            selectedCandidates = candidates
        }

        return TaskAutoExecutionDecision(
            status: .readyForReview,
            selectedTasks: Array(selectedCandidates.prefix(settings.maxTasksPerRun)),
            reason: "Eligible tasks are ready for review-only LLM planning.",
            llmCallBudgetRemaining: remainingBudget,
            requiresUserApproval: true,
            allowsDirectExecution: false
        )
    }

    private func decision(
        _ status: TaskAutoExecutionDecisionStatus,
        reason: String,
        remainingBudget: Int
    ) -> TaskAutoExecutionDecision {
        TaskAutoExecutionDecision(
            status: status,
            selectedTasks: [],
            reason: reason,
            llmCallBudgetRemaining: remainingBudget,
            requiresUserApproval: true,
            allowsDirectExecution: false
        )
    }

    private func rankedCandidates(
        from snapshot: ProjectBoardSnapshot,
        settings: TaskAutoExecutionSettings,
        referenceDate: Date,
        calendar: Calendar
    ) -> [ProjectBoardTask] {
        let lookaheadEnd = referenceDate.addingTimeInterval(TimeInterval(settings.lookaheadHours) * 60 * 60)

        return snapshot.projects
            // Review-only automation should never resurrect closed project work.
            // Stores normally provide active snapshots, but the pure policy stays
            // fail-closed for imported, synced, or test-built snapshots.
            .filter { !$0.isArchived && !$0.isCompleted }
            .flatMap(\.tasks)
            .filter { task in
                guard task.status != .done, task.status != .blocked else {
                    return false
                }
                if task.priority == .high, task.dueAt == nil {
                    return true
                }
                guard let dueDate = parsedDueDate(task.dueAt, calendar: calendar) else {
                    return false
                }
                return dueDate <= lookaheadEnd
            }
            .sorted { lhs, rhs in
                let lhsRank = rank(task: lhs, referenceDate: referenceDate, calendar: calendar)
                let rhsRank = rank(task: rhs, referenceDate: referenceDate, calendar: calendar)
                if lhsRank != rhsRank {
                    return isRank(lhsRank, orderedBefore: rhsRank)
                }
                return lhs.id > rhs.id
            }
    }

    private func rank(task: ProjectBoardTask, referenceDate: Date, calendar: Calendar) -> [Int] {
        let dueDate = parsedDueDate(task.dueAt, calendar: calendar)
        let dueBucket: Int
        if let dueDate, dueDate < startOfDay(for: referenceDate, calendar: calendar) {
            dueBucket = 0
        } else if let dueDate, dueDate < endOfDay(for: referenceDate, calendar: calendar) {
            dueBucket = 1
        } else if dueDate == nil && task.priority == .high {
            // High-priority undated work is intentionally kept with the future
            // review queue. Otherwise a low-priority task merely inside the
            // lookahead window can consume the LLM review budget first.
            dueBucket = 2
        } else if dueDate != nil {
            dueBucket = 2
        } else {
            dueBucket = 3
        }
        let dueTimestamp = dueDate.map { Int($0.timeIntervalSince1970) } ?? Int.max
        return [dueBucket, task.priority.executionSortRank, dueTimestamp]
    }

    private func isUrgent(task: ProjectBoardTask, referenceDate: Date, calendar: Calendar) -> Bool {
        guard let dueDate = parsedDueDate(task.dueAt, calendar: calendar) else {
            return false
        }
        return dueDate < endOfDay(for: referenceDate, calendar: calendar)
    }

    private func isRank(_ lhs: [Int], orderedBefore rhs: [Int]) -> Bool {
        for (lhsValue, rhsValue) in zip(lhs, rhs) {
            if lhsValue != rhsValue {
                return lhsValue < rhsValue
            }
        }
        return lhs.count < rhs.count
    }

    private func parsedDueDate(_ value: String?, calendar: Calendar) -> Date? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: value) {
            return date
        }

        let dateFormatter = DateFormatter()
        dateFormatter.calendar = calendar
        dateFormatter.timeZone = calendar.timeZone
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd"
        return dateFormatter.date(from: value)
    }

    private func startOfDay(for date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .day, for: date)?.start ?? date
    }

    private func endOfDay(for date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .day, for: date)?.end ?? date
    }
}

public enum TaskAutoExecutionPlanningRequestError: Error, Equatable, Sendable {
    case noReviewableTasks
}

public struct TaskAutoExecutionPlanningRequestBuilder: Sendable {
    public init() {}

    public func makePlanningRequest(
        decision: TaskAutoExecutionDecision,
        settings: TaskAutoExecutionSettings,
        referenceDate: Date = Date(),
        timeZoneIdentifier: String = TimeZone.current.identifier
    ) throws -> PlanningRequest {
        guard decision.shouldCallLLM else {
            throw TaskAutoExecutionPlanningRequestError.noReviewableTasks
        }

        let calendar = reviewCalendar(timeZoneIdentifier: timeZoneIdentifier)
        let taskLines = decision.selectedTasks.map { task in
            let reason = selectionReason(for: task, referenceDate: referenceDate, calendar: calendar)
            return "- taskId=\(task.id); title=\(task.title); selectionReason=\(reason); priority=\(task.priority.rawValue); status=\(task.status.rawValue); dueAt=\(task.dueAt ?? "none"); detail=\(task.detail)"
        }.joined(separator: "\n")

        // Selection reasons make review-only automation auditable: the model can
        // explain priority/due-date tradeoffs without gaining direct mutation
        // authority over the user's local task database.
        let userInput = """
        Build a review-only SoloPM action plan for the selected tasks.
        Automation mode: \(settings.mode.rawValue); cadence: \(settings.cadence.rawValue); generatedAt: \(ISO8601DateFormatter().string(from: referenceDate)).
        Decision reason: \(decision.reason)
        Do not delete projects or tasks. Do not mark work completed unless the user approves the reviewed plan.
        Review these reasons before proposing any task update.
        Selected tasks:
        \(taskLines)
        """

        return PlanningRequest(
            userInput: userInput,
            currentDate: referenceDate,
            timeZoneIdentifier: timeZoneIdentifier,
            availableTools: [.taskGet, .taskList, .taskUpdate, .calendarCreateWorkBlock, .remindersCreate, .filesystemCreateMarkdownFile],
            knowledgeFrameCandidates: []
        )
    }

    private func selectionReason(for task: ProjectBoardTask, referenceDate: Date, calendar: Calendar) -> String {
        guard let dueDate = parsedDueDate(task.dueAt, calendar: calendar) else {
            if task.priority == .high {
                return "high priority without due date"
            }
            return "priority review candidate"
        }

        if dueDate < startOfDay(for: referenceDate, calendar: calendar) {
            let overdueDays = max(
                calendar.dateComponents(
                    [.day],
                    from: startOfDay(for: dueDate, calendar: calendar),
                    to: startOfDay(for: referenceDate, calendar: calendar)
                ).day ?? 1,
                1
            )
            let unit = overdueDays == 1 ? "day" : "days"
            return "overdue by \(overdueDays) \(unit)"
        }

        if dueDate < endOfDay(for: referenceDate, calendar: calendar) {
            return "due today"
        }

        let hoursUntilDue = max(Int(ceil(dueDate.timeIntervalSince(referenceDate) / 3_600)), 1)
        let unit = hoursUntilDue == 1 ? "hour" : "hours"
        return "due within \(hoursUntilDue) \(unit)"
    }

    private func reviewCalendar(timeZoneIdentifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        return calendar
    }

    private func parsedDueDate(_ value: String?, calendar: Calendar) -> Date? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: value) {
            return date
        }

        let dateFormatter = DateFormatter()
        dateFormatter.calendar = calendar
        dateFormatter.timeZone = calendar.timeZone
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd"
        return dateFormatter.date(from: value)
    }

    private func startOfDay(for date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .day, for: date)?.start ?? date
    }

    private func endOfDay(for date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .day, for: date)?.end ?? date
    }
}

private extension ProjectTaskPriority {
    var executionSortRank: Int {
        switch self {
        case .high:
            0
        case .medium:
            1
        case .low:
            2
        }
    }
}
