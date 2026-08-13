import Foundation

public enum DailyPlanningReviewPhase: String, Codable, Equatable, Sendable {
    case morning
    case midday
    case evening
}

public enum DailyPlanningReviewBoundary: String, Codable, Equatable, Sendable {
    case proposalOnly = "proposal_only"
}

public struct DailyPlanningFocusItem: Identifiable, Codable, Equatable, Sendable {
    public var id: Int64 { taskID }
    public var taskID: Int64
    public var title: String
    public var reason: String

    public init(taskID: Int64, title: String, reason: String) {
        self.taskID = taskID
        self.title = title
        self.reason = reason
    }
}

public struct DailyPlanningScheduleBlock: Identifiable, Codable, Equatable, Sendable {
    public var id: String { "\(taskID)-\(label)" }
    public var taskID: Int64
    public var title: String
    public var label: String

    public init(taskID: Int64, title: String, label: String) {
        self.taskID = taskID
        self.title = title
        self.label = label
    }
}

public struct DailyPlanningReview: Codable, Equatable, Sendable {
    public var sourceTranscript: String
    public var phase: DailyPlanningReviewPhase
    public var requestedMinutes: Int?
    public var headline: String
    public var spokenSummary: String
    public var overdueCount: Int
    public var dueTodayCount: Int
    public var inboxUntriagedCount: Int
    public var recommendedTaskID: Int64?
    public var focusItems: [DailyPlanningFocusItem]
    public var scheduleBlocks: [DailyPlanningScheduleBlock]
    public var reviewBoundary: DailyPlanningReviewBoundary

    public init(
        sourceTranscript: String,
        phase: DailyPlanningReviewPhase,
        requestedMinutes: Int?,
        headline: String,
        spokenSummary: String,
        overdueCount: Int,
        dueTodayCount: Int,
        inboxUntriagedCount: Int,
        recommendedTaskID: Int64?,
        focusItems: [DailyPlanningFocusItem],
        scheduleBlocks: [DailyPlanningScheduleBlock],
        reviewBoundary: DailyPlanningReviewBoundary = .proposalOnly
    ) {
        self.sourceTranscript = sourceTranscript
        self.phase = phase
        self.requestedMinutes = requestedMinutes
        self.headline = headline
        self.spokenSummary = spokenSummary
        self.overdueCount = overdueCount
        self.dueTodayCount = dueTodayCount
        self.inboxUntriagedCount = inboxUntriagedCount
        self.recommendedTaskID = recommendedTaskID
        self.focusItems = focusItems
        self.scheduleBlocks = scheduleBlocks
        self.reviewBoundary = reviewBoundary
    }
}

/// Defines the time boundaries shared by suggested work blocks and the daily
/// planning preview. Using elapsed time from the local hour preserves the
/// actual instant through daylight-saving folds and skips.
public enum DailyPlanningReviewRefreshSchedule {
    private static let slotDuration: TimeInterval = 30.0 * 60.0

    public static func roundedTimeBlockStart(from referenceDate: Date, calendar: Calendar) -> Date {
        guard let hourStart = calendar.dateInterval(of: .hour, for: referenceDate)?.start else {
            return referenceDate
        }

        let elapsed = referenceDate.timeIntervalSince(hourStart)
        let remainder = elapsed.truncatingRemainder(dividingBy: slotDuration)
        let roundedElapsed = remainder == 0 ? elapsed : elapsed + (slotDuration - remainder)
        return hourStart.addingTimeInterval(roundedElapsed)
    }

    /// Returns a future boundary even when `referenceDate` is already on one.
    /// This prevents a completed refresh from immediately scheduling itself again.
    public static func nextStrictBoundary(after referenceDate: Date, calendar: Calendar) -> Date {
        let rounded = roundedTimeBlockStart(from: referenceDate, calendar: calendar)
        return rounded > referenceDate
            ? rounded
            : rounded.addingTimeInterval(slotDuration)
    }
}

struct DailyPlanningReviewTimeBlockKey: Hashable, Sendable {
    let year: Int
    let month: Int
    let day: Int
    let hour: Int
    let minute: Int
    let utcOffset: Int

    init(referenceDate: Date, calendar: Calendar) {
        let blockStart = DailyPlanningReviewRefreshSchedule.roundedTimeBlockStart(
            from: referenceDate,
            calendar: calendar
        )
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: blockStart)
        self.year = components.year ?? 0
        self.month = components.month ?? 0
        self.day = components.day ?? 0
        self.hour = components.hour ?? 0
        // Match the board's ceiling semantics: an exact boundary stays in its
        // own slot, while the next second moves to the next 30-minute preview.
        self.minute = components.minute ?? 0
        // Local wall-clock components alone collapse the two 01:30 values in a
        // fall-back fold. The offset keeps both instants distinct and also
        // records which side of a spring-forward skip produced this key.
        self.utcOffset = calendar.timeZone.secondsFromGMT(for: blockStart)
    }
}

struct DailyPlanningReviewPreviewCacheKey: Equatable, Sendable {
    let planningDayKey: PlanningDayKey
    let sourceRevision: UInt64
    let phase: DailyPlanningReviewPhase
    let timeBlock: DailyPlanningReviewTimeBlockKey

    init(
        planningDayKey: PlanningDayKey,
        sourceRevision: UInt64,
        referenceDate: Date,
        calendar: Calendar
    ) {
        self.planningDayKey = planningDayKey
        self.sourceRevision = sourceRevision
        self.phase = DailyPlanningReviewBuilder.phase(for: referenceDate, calendar: calendar)
        self.timeBlock = DailyPlanningReviewTimeBlockKey(
            referenceDate: referenceDate,
            calendar: calendar
        )
    }

    /// PII-free identity for runtime cache diagnostics. Hashing every temporal
    /// cache dimension distinguishes DST, calendar, timezone, and phase changes
    /// without publishing a user's timezone identifier. Source revision stays
    /// excluded so same-time mutation rebuilds remain visible to the smoke gate.
    var runtimeDiagnosticTemporalKey: String {
        var hasher = Hasher()
        hasher.combine(planningDayKey)
        hasher.combine(phase.rawValue)
        hasher.combine(timeBlock)
        return String(UInt(bitPattern: hasher.finalize()))
    }
}

struct DailyPlanningReviewPreviewCache {
    private var cachedKey: DailyPlanningReviewPreviewCacheKey?
    private var cachedReview: DailyPlanningReview?

    init() {
        self.cachedKey = nil
        self.cachedReview = nil
    }

    mutating func review(
        for key: DailyPlanningReviewPreviewCacheKey,
        build: () -> DailyPlanningReview
    ) -> DailyPlanningReview {
        if cachedKey == key, let cachedReview {
            return cachedReview
        }

        let review = build()
        cachedKey = key
        cachedReview = review
        return review
    }

    mutating func invalidate() {
        cachedKey = nil
        cachedReview = nil
    }
}

public enum DailyPlanningReviewBuilder {
    public static func review(
        transcript: String,
        plan: TodayWorkflowPlan,
        workload: DailyWorkloadOverview,
        referenceDate: Date,
        calendar: Calendar
    ) -> DailyPlanningReview {
        let phase = phase(for: referenceDate, calendar: calendar)
        let requestedMinutes = requestedMinutes(from: transcript)
        let blocks = selectedBlocks(from: plan.timeBlocks, requestedMinutes: requestedMinutes)
        let focusTasks = selectedFocusTasks(plan: plan, blocks: blocks)
        let focusItems = focusTasks.map { task in
            DailyPlanningFocusItem(
                taskID: task.id,
                title: task.title,
                reason: focusReason(for: task, plan: plan)
            )
        }
        let scheduleBlocks = blocks.map { block in
            DailyPlanningScheduleBlock(
                taskID: block.task.id,
                title: block.task.title,
                label: block.label
            )
        }

        return DailyPlanningReview(
            sourceTranscript: transcript,
            phase: phase,
            requestedMinutes: requestedMinutes,
            headline: headline(phase: phase, requestedMinutes: requestedMinutes, focusCount: focusItems.count),
            spokenSummary: spokenSummary(
                plan: plan,
                workload: workload,
                focusItems: focusItems,
                phase: phase
            ),
            overdueCount: plan.overdueCount,
            dueTodayCount: plan.dueTodayCount,
            inboxUntriagedCount: workload.inboxUntriagedCount,
            recommendedTaskID: plan.recommendedTask?.id,
            focusItems: focusItems,
            scheduleBlocks: scheduleBlocks
        )
    }

    fileprivate static func phase(for date: Date, calendar: Calendar) -> DailyPlanningReviewPhase {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 5..<12:
            return .morning
        case 12..<17:
            return .midday
        default:
            return .evening
        }
    }

    private static func requestedMinutes(from transcript: String) -> Int? {
        let patterns = [
            #"(\d{1,3})\s*分"#,
            #"(\d{1,3})\s*(?:minutes|minute|mins|min)\b"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let range = NSRange(transcript.startIndex..<transcript.endIndex, in: transcript)
            guard let match = regex.firstMatch(in: transcript, range: range),
                  let valueRange = Range(match.range(at: 1), in: transcript),
                  let minutes = Int(transcript[valueRange]) else {
                continue
            }
            return max(30, min(minutes, 240))
        }
        return nil
    }

    private static func selectedBlocks(
        from blocks: [TodayTimeBlock],
        requestedMinutes: Int?
    ) -> [TodayTimeBlock] {
        let requestedBlockCount = requestedMinutes.map { max(1, min(4, Int(ceil(Double($0) / 30.0)))) }
        return Array(blocks.prefix(requestedBlockCount ?? 3))
    }

    private static func selectedFocusTasks(
        plan: TodayWorkflowPlan,
        blocks: [TodayTimeBlock]
    ) -> [ProjectBoardTask] {
        let blockTasks = blocks.map(\.task)
        if !blockTasks.isEmpty {
            return blockTasks
        }
        return Array(plan.tasks.prefix(3))
    }

    private static func focusReason(for task: ProjectBoardTask, plan: TodayWorkflowPlan) -> String {
        if task.id == plan.recommendedTask?.id {
            return plan.recommendationReason
        }
        if task.status == .blocked {
            return "Blocked work should be unblocked before adding new scope."
        }
        if task.priority == .high {
            return "High-priority work protects today's plan."
        }
        return "Keeps today's due work moving."
    }

    private static func headline(
        phase: DailyPlanningReviewPhase,
        requestedMinutes: Int?,
        focusCount: Int
    ) -> String {
        let phaseLabel = switch phase {
        case .morning:
            "Morning"
        case .midday:
            "Midday"
        case .evening:
            "Evening"
        }
        if let requestedMinutes {
            return "\(phaseLabel) focus review: \(focusCount) tasks for \(requestedMinutes) minutes"
        }
        return "\(phaseLabel) daily planning review"
    }

    private static func spokenSummary(
        plan: TodayWorkflowPlan,
        workload: DailyWorkloadOverview,
        focusItems: [DailyPlanningFocusItem],
        phase: DailyPlanningReviewPhase
    ) -> String {
        let overdue = plan.overdueCount == 0
            ? "No overdue work"
            : "\(plan.overdueCount) overdue"
        let inbox = workload.inboxUntriagedCount == 0
            ? "no Inbox triage"
            : "\(workload.inboxUntriagedCount) Inbox"
        let focus = focusItems.first?.title ?? "capture the next task"
        let phaseAdvice = switch phase {
        case .morning:
            "Start with"
        case .midday:
            "Resume with"
        case .evening:
            "Finish with"
        }
        return "\(overdue), \(plan.dueTodayCount) due today, \(inbox). \(phaseAdvice) \(focus)."
    }
}
