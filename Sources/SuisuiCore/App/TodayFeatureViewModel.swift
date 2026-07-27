import Combine
import Foundation

private struct TodayFeatureReadState: Equatable {
    let snapshot: TodayWorkflowSnapshot
    let catchUpCount: Int
    let missedTaskReview: MissedTaskReviewSummary
    let projectTitlesByTaskID: [Int64: String]
}

public struct TodayFeatureState: Equatable {
    public var snapshot: TodayWorkflowSnapshot
    public var catchUpCount: Int
    public var missedTaskReview: MissedTaskReviewSummary
    public var projectTitlesByTaskID: [Int64: String]
    public var showsCompletedWorkflowTasks: Bool
    public var selectedTaskID: Int64?
    public var commandFeedback: String?
    public var scheduleDraft: TodayScheduleDraft?
    public var dailyPlanningReview: DailyPlanningReview?
    /// Work that is stopped because someone else owes something. Today is the
    /// only surface a solo user opens daily, so this is where a wait has to
    /// become visible.
    public var waitingTasks: [ProjectBoardTask]
}

@MainActor
public final class TodayFeatureViewModel: ObservableObject {
    @Published public private(set) var state: TodayFeatureState

    public var snapshot: TodayWorkflowSnapshot { state.snapshot }
    public var catchUpCount: Int { state.catchUpCount }
    public var missedTaskReview: MissedTaskReviewSummary { state.missedTaskReview }
    public var projectTitlesByTaskID: [Int64: String] { state.projectTitlesByTaskID }
    public var showsCompletedWorkflowTasks: Bool { state.showsCompletedWorkflowTasks }
    public var selectedTaskID: Int64? { state.selectedTaskID }
    public var commandFeedback: String? { state.commandFeedback }
    public var scheduleDraft: TodayScheduleDraft? { state.scheduleDraft }
    public var dailyPlanningReview: DailyPlanningReview? { state.dailyPlanningReview }
    public var waitingTasks: [ProjectBoardTask] { state.waitingTasks }

    private let board: ProjectBoardViewModel
    private var observations: Set<AnyCancellable> = []
    private var featureActionDepth = 0
    private var hasScheduledSynchronization = false

    public init(board: ProjectBoardViewModel) {
        self.board = board
        self.state = Self.makeState(from: board)

        // Today subscribes only to the state it renders. Automation, receipt,
        // MCP, and integration publications remain on the compatibility board
        // facade and cannot invalidate the Today root.
        board.$derivedReadModels
            .map { [weak board] readModels in
                TodayFeatureReadState(
                    snapshot: readModels.todayWorkflowSnapshot,
                    catchUpCount: readModels.sidebarMetrics.catchUpCount,
                    missedTaskReview: readModels.missedTaskReview,
                    projectTitlesByTaskID: Self.projectTitlesByTaskID(
                        todayTasks: readModels.todayWorkflowSnapshot.plan.tasks,
                        // ProjectBoard publishes the snapshot before rebuilding
                        // derived models. Reading it at this transaction boundary
                        // avoids publishing the intermediate old-model/new-snapshot pair.
                        projects: board?.snapshot.projects ?? []
                    )
                )
            }
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                self?.scheduleSynchronization()
            }
            .store(in: &observations)
        board.$showsCompletedWorkflowTasks
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                self?.scheduleSynchronization()
            }
            .store(in: &observations)
        board.$selectedTaskID
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                self?.scheduleSynchronization()
            }
            .store(in: &observations)
        board.$todayCommandFeedback
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                self?.scheduleSynchronization()
            }
            .store(in: &observations)
        board.$todayScheduleDraft
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                self?.scheduleSynchronization()
            }
            .store(in: &observations)
        board.$dailyPlanningReview
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                self?.scheduleSynchronization()
            }
            .store(in: &observations)
    }

    public func projectTitle(for task: ProjectBoardTask) -> String {
        projectTitlesByTaskID[task.id] ?? "Unknown Project"
    }

    public func startFocus(taskID: Int64) {
        performFeatureAction { board.startFocus(taskID: taskID) }
    }

    public func toggleTaskCompletion(id: Int64) {
        performFeatureAction { board.toggleTaskCompletion(id: id) }
    }

    public func selectTask(id: Int64) {
        performFeatureAction { board.selectedTaskID = id }
    }

    @discardableResult
    public func submitCommand(_ title: String) -> ProjectBoardTask? {
        performFeatureAction { board.submitTodayCommand(title) }
    }

    public func setShowsCompletedWorkflowTasks(_ isShown: Bool) {
        performFeatureAction { board.setShowsCompletedWorkflowTasks(isShown) }
    }

    @discardableResult
    public func prepareTodayScheduleDraft(prioritizing taskID: Int64? = nil) -> TodayScheduleDraft? {
        performFeatureAction { board.prepareTodayScheduleDraft(prioritizing: taskID) }
    }

    public func enqueueTodayReminderDraft(for taskID: Int64) {
        _ = performFeatureAction { board.enqueueTodayReminderDraft(for: taskID) }
    }

    public func enqueueDailyPlanningActionDraft(kind: DailyPlanningActionDraftKind) {
        _ = performFeatureAction { board.enqueueDailyPlanningActionDraft(kind: kind) }
    }

    public func completeMissedTask(id: Int64) {
        performFeatureAction { board.completeMissedTask(id: id) }
    }

    public func rescheduleMissedTaskForToday(id: Int64) {
        performFeatureAction { board.rescheduleMissedTaskForToday(id: id) }
    }

    public func deferMissedTaskForLater(id: Int64) {
        performFeatureAction { board.deferMissedTaskForLater(id: id) }
    }

    private func performFeatureAction<Result>(_ action: () -> Result) -> Result {
        featureActionDepth += 1
        defer {
            featureActionDepth -= 1
            if featureActionDepth == 0 {
                applyStateIfChanged(Self.makeState(from: board))
            }
        }
        return action()
    }

    private func scheduleSynchronization() {
        guard featureActionDepth == 0, !hasScheduledSynchronization else { return }
        hasScheduledSynchronization = true
        // ProjectBoard may publish several fields inside one synchronous
        // mutation. Read the facade once on the next main-queue turn so Today
        // never exposes an intermediate selection/read-model combination.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.hasScheduledSynchronization = false
            self.applyStateIfChanged(Self.makeState(from: self.board))
        }
    }

    private func applyStateIfChanged(_ nextState: TodayFeatureState) {
        guard nextState != state else { return }
        // One aggregate assignment gives SwiftUI one invalidation for one
        // logical Today change, even when several rendered fields changed.
        state = nextState
    }

    private static func makeState(from board: ProjectBoardViewModel) -> TodayFeatureState {
        let snapshot = board.derivedReadModels.todayWorkflowSnapshot
        return TodayFeatureState(
            snapshot: snapshot,
            catchUpCount: board.derivedReadModels.sidebarMetrics.catchUpCount,
            missedTaskReview: board.derivedReadModels.missedTaskReview,
            projectTitlesByTaskID: projectTitlesByTaskID(
                todayTasks: snapshot.plan.tasks,
                projects: board.snapshot.projects
            ),
            showsCompletedWorkflowTasks: board.showsCompletedWorkflowTasks,
            selectedTaskID: board.selectedTaskID,
            commandFeedback: board.todayCommandFeedback,
            scheduleDraft: board.todayScheduleDraft,
            dailyPlanningReview: board.dailyPlanningReview,
            waitingTasks: board.waitingTasks
        )
    }

    private static func projectTitlesByTaskID(
        todayTasks: [ProjectBoardTask],
        projects: [ProjectBoardProject]
    ) -> [Int64: String] {
        let titlesByProjectID = Dictionary(
            uniqueKeysWithValues: projects.map { ($0.id, $0.title) }
        )
        // Cache only titles rendered by Today. This keeps project renames
        // reactive without making the feature observe the full board facade.
        return Dictionary(uniqueKeysWithValues: todayTasks.map { task in
            (task.id, titlesByProjectID[task.projectID] ?? "Unknown Project")
        })
    }
}
