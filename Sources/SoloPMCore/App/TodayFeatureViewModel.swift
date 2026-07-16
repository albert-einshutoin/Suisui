import Combine
import Foundation

private struct TodayFeatureReadState: Equatable {
    let snapshot: TodayWorkflowSnapshot
    let catchUpCount: Int
    let missedTaskReview: MissedTaskReviewSummary
    let projectTitlesByTaskID: [Int64: String]
}

@MainActor
public final class TodayFeatureViewModel: ObservableObject {
    @Published public private(set) var snapshot: TodayWorkflowSnapshot
    @Published public private(set) var catchUpCount: Int
    @Published public private(set) var missedTaskReview: MissedTaskReviewSummary
    @Published public private(set) var projectTitlesByTaskID: [Int64: String]
    @Published public private(set) var showsCompletedWorkflowTasks: Bool
    @Published public private(set) var selectedTaskID: Int64?
    @Published public private(set) var commandFeedback: String?
    @Published public private(set) var scheduleDraft: TodayScheduleDraft?
    @Published public private(set) var dailyPlanningReview: DailyPlanningReview?

    private let board: ProjectBoardViewModel
    private var observations: Set<AnyCancellable> = []

    public init(board: ProjectBoardViewModel) {
        self.board = board
        self.snapshot = board.derivedReadModels.todayWorkflowSnapshot
        self.catchUpCount = board.derivedReadModels.sidebarMetrics.catchUpCount
        self.missedTaskReview = board.derivedReadModels.missedTaskReview
        self.projectTitlesByTaskID = Self.projectTitlesByTaskID(
            todayTasks: board.derivedReadModels.todayWorkflowSnapshot.plan.tasks,
            projects: board.snapshot.projects
        )
        self.showsCompletedWorkflowTasks = board.showsCompletedWorkflowTasks
        self.selectedTaskID = board.selectedTaskID
        self.commandFeedback = board.todayCommandFeedback
        self.scheduleDraft = board.todayScheduleDraft
        self.dailyPlanningReview = board.dailyPlanningReview

        // Today subscribes only to the state it renders. Automation, receipt,
        // MCP, and integration publications remain on the compatibility board
        // facade and cannot invalidate the Today root.
        board.$derivedReadModels
            .combineLatest(board.$snapshot)
            .map { readModels, boardSnapshot in
                TodayFeatureReadState(
                    snapshot: readModels.todayWorkflowSnapshot,
                    catchUpCount: readModels.sidebarMetrics.catchUpCount,
                    missedTaskReview: readModels.missedTaskReview,
                    projectTitlesByTaskID: Self.projectTitlesByTaskID(
                        todayTasks: readModels.todayWorkflowSnapshot.plan.tasks,
                        projects: boardSnapshot.projects
                    )
                )
            }
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] value in
                self?.snapshot = value.snapshot
                self?.catchUpCount = value.catchUpCount
                self?.missedTaskReview = value.missedTaskReview
                self?.projectTitlesByTaskID = value.projectTitlesByTaskID
            }
            .store(in: &observations)
        board.$showsCompletedWorkflowTasks
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] value in
                self?.showsCompletedWorkflowTasks = value
            }
            .store(in: &observations)
        board.$selectedTaskID
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] value in
                self?.selectedTaskID = value
            }
            .store(in: &observations)
        board.$todayCommandFeedback
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] value in
                self?.commandFeedback = value
            }
            .store(in: &observations)
        board.$todayScheduleDraft
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] value in
                self?.scheduleDraft = value
            }
            .store(in: &observations)
        board.$dailyPlanningReview
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] value in
                self?.dailyPlanningReview = value
            }
            .store(in: &observations)
    }

    public func projectTitle(for task: ProjectBoardTask) -> String {
        projectTitlesByTaskID[task.id] ?? "Unknown Project"
    }

    public func startFocus(taskID: Int64) {
        board.startFocus(taskID: taskID)
    }

    public func toggleTaskCompletion(id: Int64) {
        board.toggleTaskCompletion(id: id)
    }

    public func selectTask(id: Int64) {
        board.selectedTaskID = id
    }

    @discardableResult
    public func submitCommand(_ title: String) -> ProjectBoardTask? {
        board.submitTodayCommand(title)
    }

    public func setShowsCompletedWorkflowTasks(_ isShown: Bool) {
        board.setShowsCompletedWorkflowTasks(isShown)
    }

    @discardableResult
    public func prepareTodayScheduleDraft(prioritizing taskID: Int64? = nil) -> TodayScheduleDraft? {
        board.prepareTodayScheduleDraft(prioritizing: taskID)
    }

    public func enqueueTodayReminderDraft(for taskID: Int64) {
        board.enqueueTodayReminderDraft(for: taskID)
    }

    public func enqueueDailyPlanningActionDraft(kind: DailyPlanningActionDraftKind) {
        board.enqueueDailyPlanningActionDraft(kind: kind)
    }

    public func completeMissedTask(id: Int64) {
        board.completeMissedTask(id: id)
    }

    public func rescheduleMissedTaskForToday(id: Int64) {
        board.rescheduleMissedTaskForToday(id: id)
    }

    public func deferMissedTaskForLater(id: Int64) {
        board.deferMissedTaskForLater(id: id)
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
