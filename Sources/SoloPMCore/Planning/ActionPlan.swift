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
    case taskCreate = "task.create"
    case taskBulkCreate = "task.bulk_create"
    case taskListDue = "task.list_due"
    case notificationSchedule = "notification.schedule"
    case calendarCreateEvent = "calendar.create_event"
    case remindersCreate = "reminders.create"
    case filesystemCreateDirectory = "filesystem.create_directory"
    case filesystemCreateMarkdownFile = "filesystem.create_markdown_file"
    case frameSearch = "frame.search"
    case mailDraftCreateText = "maildraft.create_text"

    public var defaultRiskLevel: RiskLevel {
        switch self {
        case .projectList, .taskListDue, .frameSearch:
            .read
        case .mailDraftCreateText:
            .draft
        case .projectCreate,
             .projectUpdate,
             .taskCreate,
             .taskBulkCreate,
             .notificationSchedule,
             .calendarCreateEvent,
             .remindersCreate,
             .filesystemCreateDirectory,
             .filesystemCreateMarkdownFile:
            .write
        }
    }

    public var actionType: ActionType {
        switch self {
        case .projectCreate, .projectUpdate, .projectList:
            .project
        case .taskCreate, .taskBulkCreate, .taskListDue:
            .task
        case .notificationSchedule:
            .notification
        case .calendarCreateEvent:
            .calendar
        case .remindersCreate:
            .reminder
        case .filesystemCreateDirectory, .filesystemCreateMarkdownFile:
            .filesystem
        case .frameSearch:
            .knowledgeFrame
        case .mailDraftCreateText:
            .mailDraft
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
            self = .object(value)
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
        }
    }
}
