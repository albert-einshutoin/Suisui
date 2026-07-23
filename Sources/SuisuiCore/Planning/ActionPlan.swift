import Foundation

public struct ActionPlan: Codable, Equatable, Sendable {
    public var id: String
    public var userInput: String
    public var summary: String
    public var actions: [PlanAction]
    public var riskLevel: RiskLevel
    public var requiresApproval: Bool

    public init(
        id: String,
        userInput: String,
        summary: String,
        actions: [PlanAction],
        riskLevel: RiskLevel,
        requiresApproval: Bool
    ) {
        self.id = id
        self.userInput = userInput
        self.summary = summary
        self.actions = actions
        self.riskLevel = riskLevel
        self.requiresApproval = requiresApproval
    }
}

public typealias Action = PlanAction

public struct PlanAction: Codable, Equatable, Sendable {
    public var id: String
    public var tool: ActionTool
    public var arguments: [String: JSONValue]
    public var riskLevel: RiskLevel
    public var requiresUserConfirmation: Bool

    public init(
        id: String,
        tool: ActionTool,
        arguments: [String: JSONValue] = [:],
        riskLevel: RiskLevel? = nil,
        requiresUserConfirmation: Bool = false
    ) {
        self.id = id
        self.tool = tool
        self.arguments = arguments
        self.riskLevel = riskLevel ?? tool.defaultRiskLevel
        self.requiresUserConfirmation = requiresUserConfirmation
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case tool
        case arguments
        case riskLevel
        case requiresUserConfirmation
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        tool = try container.decode(ActionTool.self, forKey: .tool)
        arguments = try container.decodeIfPresent([String: JSONValue].self, forKey: .arguments) ?? [:]
        riskLevel = try container.decodeIfPresent(RiskLevel.self, forKey: .riskLevel) ?? tool.defaultRiskLevel
        requiresUserConfirmation = try container.decodeIfPresent(Bool.self, forKey: .requiresUserConfirmation) ?? false
    }
}

public extension PlanAction {
    var actionType: ActionType {
        tool.actionType
    }

    var approvalRequirement: ApprovalRequirement {
        if riskLevel == .danger {
            return .blocked
        }

        if riskLevel >= .write {
            return .explicitApproval
        }

        if requiresUserConfirmation {
            return .userConfirmation
        }

        return .none
    }
}

public enum ActionTool: String, Codable, CaseIterable, Equatable, Sendable {
    case projectCreate = "project.create"
    case projectUpdate = "project.update"
    case projectList = "project.list"
    case projectGet = "project.get"
    case projectComplete = "project.complete"
    case projectDelete = "project.delete"
    case taskCreate = "task.create"
    case taskBulkCreate = "task.bulk_create"
    case taskList = "task.list"
    case taskGet = "task.get"
    case taskUpdate = "task.update"
    case taskComplete = "task.complete"
    case taskDelete = "task.delete"
    case taskListDue = "task.list_due"
    case taskListOverdue = "task.list_overdue"
    case notificationSchedule = "notification.schedule"
    case notificationScheduleRelative = "notification.schedule_relative"
    case notificationScheduleOverdueRule = "notification.schedule_overdue_rule"
    case notificationCancel = "notification.cancel"
    case notificationList = "notification.list"
    case calendarCreateEvent = "calendar.create_event"
    case calendarCreateDeadline = "calendar.create_deadline"
    case calendarCreateWorkBlock = "calendar.create_work_block"
    case remindersCreate = "reminders.create"
    case remindersBulkCreate = "reminders.bulk_create"
    case remindersMarkComplete = "reminders.mark_complete"
    case filesystemCreateDirectory = "filesystem.create_directory"
    case filesystemCreateMarkdownFile = "filesystem.create_markdown_file"
    case filesystemCreateArtifactsFromFrame = "filesystem.create_artifacts_from_frame"
    case filesystemScanProjectArtifacts = "filesystem.scan_project_artifacts"
    case frameSearch = "frame.search"
    case frameList = "frame.list"
    case frameGet = "frame.get"
    case frameCreate = "frame.create"
    case frameUpdate = "frame.update"
    case frameDelete = "frame.delete"
    case mailDraftCreateText = "maildraft.create_text"
    case gitStatus = "git.status"
    case gitBranch = "git.branch"
    case gitLogSummary = "git.log_summary"
    case gitDiffSummary = "git.diff_summary"
    case developmentPreparePullRequestWorkflow = "development.pr_workflow.prepare"
    case developmentCommitChanges = "development.pr_workflow.commit"
    case developmentPushBranch = "development.pr_workflow.push"
    case developmentCreatePullRequest = "development.pr_workflow.create_pull_request"
    case developmentReviewPullRequestGate = "development.pr_workflow.review_gate"
    case developmentMergePullRequest = "development.pr_workflow.merge"
    case developmentRepositoryListFiles = "development.repository.list_files"
    case developmentRepositoryReadFile = "development.repository.read_file"
    case developmentRepositoryCreateFile = "development.repository.create_file"
    case developmentRepositoryUpdateFile = "development.repository.update_file"
    case developmentRunVerification = "development.verification.run"

    public var defaultRiskLevel: RiskLevel {
        switch self {
        case .projectList,
             .projectGet,
             .taskList,
             .taskGet,
             .taskListDue,
             .taskListOverdue,
             .notificationList,
             .filesystemScanProjectArtifacts,
             .frameSearch,
             .frameList,
             .frameGet,
             .gitStatus,
             .gitBranch,
             .gitLogSummary,
             .gitDiffSummary,
             .developmentRepositoryListFiles,
             .developmentRepositoryReadFile:
            .read
        case .mailDraftCreateText:
            .draft
        case .projectCreate,
             .projectUpdate,
             .projectComplete,
             .projectDelete,
             .taskCreate,
             .taskBulkCreate,
             .taskUpdate,
             .taskComplete,
             .taskDelete,
             .notificationSchedule,
             .notificationScheduleRelative,
             .notificationScheduleOverdueRule,
             .notificationCancel,
             .calendarCreateEvent,
             .calendarCreateDeadline,
             .calendarCreateWorkBlock,
             .remindersCreate,
             .remindersBulkCreate,
             .remindersMarkComplete,
             .filesystemCreateDirectory,
             .filesystemCreateMarkdownFile,
             .filesystemCreateArtifactsFromFrame,
             .frameCreate,
             .frameUpdate,
             .frameDelete,
             .developmentPreparePullRequestWorkflow,
             .developmentCommitChanges,
             .developmentPushBranch,
             .developmentCreatePullRequest,
             .developmentReviewPullRequestGate,
             .developmentMergePullRequest,
             .developmentRepositoryCreateFile,
             .developmentRepositoryUpdateFile,
             .developmentRunVerification:
            .write
        }
    }

    public var actionType: ActionType {
        switch self {
        case .projectCreate, .projectUpdate, .projectList, .projectGet, .projectComplete, .projectDelete:
            .project
        case .taskCreate, .taskBulkCreate, .taskList, .taskGet, .taskUpdate, .taskComplete, .taskDelete, .taskListDue, .taskListOverdue:
            .task
        case .notificationSchedule, .notificationScheduleRelative, .notificationScheduleOverdueRule, .notificationCancel, .notificationList:
            .notification
        case .calendarCreateEvent, .calendarCreateDeadline, .calendarCreateWorkBlock:
            .calendar
        case .remindersCreate, .remindersBulkCreate, .remindersMarkComplete:
            .reminder
        case .filesystemCreateDirectory,
             .filesystemCreateMarkdownFile,
             .filesystemCreateArtifactsFromFrame,
             .filesystemScanProjectArtifacts:
            .filesystem
        case .frameSearch, .frameList, .frameGet, .frameCreate, .frameUpdate, .frameDelete:
            .knowledgeFrame
        case .mailDraftCreateText:
            .mailDraft
        case .gitStatus,
             .gitBranch,
             .gitLogSummary,
             .gitDiffSummary,
             .developmentPreparePullRequestWorkflow,
             .developmentCommitChanges,
             .developmentPushBranch,
             .developmentCreatePullRequest,
             .developmentReviewPullRequestGate,
             .developmentMergePullRequest,
             .developmentRepositoryListFiles,
             .developmentRepositoryReadFile,
             .developmentRepositoryCreateFile,
             .developmentRepositoryUpdateFile,
             .developmentRunVerification:
            .developer
        }
    }
}

public enum ActionType: String, Codable, CaseIterable, Equatable, Sendable {
    case project
    case task
    case notification
    case calendar
    case reminder
    case filesystem
    case knowledgeFrame
    case mailDraft
    case developer
}

public extension ActionTool {
    static var defaultPlanningTools: [ActionTool] {
        allCases.filter { $0.actionType != .developer }
    }

    static var developerModePlanningTools: [ActionTool] {
        [
            .gitStatus,
            .gitBranch,
            .gitLogSummary,
            .gitDiffSummary,
            .developmentPreparePullRequestWorkflow,
            .developmentCommitChanges,
            .developmentPushBranch,
            .developmentCreatePullRequest,
            .developmentReviewPullRequestGate,
            .developmentMergePullRequest,
            .developmentRepositoryListFiles,
            .developmentRepositoryReadFile,
            .developmentRepositoryCreateFile,
            .developmentRepositoryUpdateFile,
            .developmentRunVerification
        ]
    }
}

public enum ApprovalRequirement: String, Codable, Comparable, Equatable, Sendable {
    case none
    case userConfirmation
    case explicitApproval
    case blocked

    private var rank: Int {
        switch self {
        case .none:
            0
        case .userConfirmation:
            1
        case .explicitApproval:
            2
        case .blocked:
            3
        }
    }

    public static func < (lhs: ApprovalRequirement, rhs: ApprovalRequirement) -> Bool {
        lhs.rank < rhs.rank
    }
}

public struct DateExpression: Codable, Equatable, Sendable {
    public var rawValue: String
    public var resolvedDate: Date?
    public var timeZoneIdentifier: String?

    public init(rawValue: String, resolvedDate: Date? = nil, timeZoneIdentifier: String? = nil) {
        self.rawValue = rawValue
        self.resolvedDate = resolvedDate
        self.timeZoneIdentifier = timeZoneIdentifier
    }
}

public extension ActionPlan {
    var approvalRequirement: ApprovalRequirement {
        actions.map(\.approvalRequirement).max() ?? .none
    }
}

public enum RiskLevel: String, Codable, CaseIterable, Comparable, Equatable, Sendable {
    case read
    case draft
    case write
    case danger

    private var rank: Int {
        switch self {
        case .read:
            0
        case .draft:
            1
        case .write:
            2
        case .danger:
            3
        }
    }

    public static func < (lhs: RiskLevel, rhs: RiskLevel) -> Bool {
        lhs.rank < rhs.rank
    }
}

public enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null
    case actionOutput(ActionOutputReference)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            if value.count == 3,
               value["$type"] == .string("actionOutput"),
               case .string(let actionID)? = value["actionID"],
               case .string(let key)? = value["key"] {
                self = .actionOutput(ActionOutputReference(actionID: actionID, key: key))
            } else {
                self = .object(value)
            }
        } else {
            self = .array(try container.decode([JSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        case .actionOutput(let reference):
            try container.encode(reference.canonicalObject)
        }
    }
}

private extension ActionOutputReference {
    var canonicalObject: [String: JSONValue] {
        [
            "$type": .string("actionOutput"),
            "actionID": .string(actionID),
            "key": .string(key)
        ]
    }
}
