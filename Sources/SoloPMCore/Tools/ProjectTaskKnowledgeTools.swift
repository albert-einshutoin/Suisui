import Foundation

public struct ProjectTool: Tool {
    public let name: ActionTool
    public let description: String
    public let inputSchema: ToolInputSchema
    public let permissionLevel: ToolPermissionLevel
    private let store: SQLiteProjectStore

    public init(name: ActionTool, store: SQLiteProjectStore) {
        self.name = name
        self.description = name.rawValue
        self.inputSchema = ProjectTool.schema(for: name)
        self.permissionLevel = name.defaultRiskLevel >= .write ? .writeWithApproval : .read
        self.store = store
    }

    public func execute(arguments: [String: JSONValue], context: ToolExecutionContext) throws -> ToolResult {
        try enforcePermission(context: context)
        try validateRequiredArguments(arguments)

        let args = ToolArguments(arguments, tool: name)
        switch name {
        case .projectCreate:
            let record = try store.create(
                title: try args.requiredString("title"),
                priority: args.optionalString("priority"),
                deadline: args.optionalString("deadline"),
                workspacePath: args.optionalString("workspacePath"),
                tags: args.stringArray("tags"),
                sourceCommand: args.optionalString("sourceCommand")
            )
            return ToolResult(
                tool: name,
                status: .succeeded,
                summary: "Created project \(record.title)",
                output: ["projectId": .number(Double(record.id))],
                rollbackMetadata: ["projectId": .number(Double(record.id))],
                compensationHint: "Project can be completed or deleted by a future cleanup flow."
            )
        case .projectUpdate:
            let record = try store.update(
                id: try args.requiredInt64("id"),
                title: args.optionalString("title"),
                status: args.optionalString("status")
            )
            return ToolResult(tool: name, status: .succeeded, summary: "Updated project \(record.title)", output: ["projectId": .number(Double(record.id))])
        case .projectComplete:
            let record = try store.update(id: try args.requiredInt64("id"), status: "completed")
            return ToolResult(tool: name, status: .succeeded, summary: "Completed project \(record.title)", output: ["projectId": .number(Double(record.id))])
        case .projectGet:
            let record = try store.get(id: try args.requiredInt64("id"))
            return ToolResult(tool: name, status: .succeeded, summary: record.title, output: record.output)
        case .projectList:
            let records = try store.list()
            return ToolResult(tool: name, status: .succeeded, summary: "\(records.count) projects", output: ["count": .number(Double(records.count))])
        default:
            throw ToolExecutionError.executionFailed(name, "Unsupported project tool.")
        }
    }

    private static func schema(for name: ActionTool) -> ToolInputSchema {
        switch name {
        case .projectCreate:
            ToolInputSchema(required: ["title"], properties: ["title": "string", "deadline": "string", "workspacePath": "string", "tags": "array"])
        case .projectUpdate:
            ToolInputSchema(required: ["id"], properties: ["id": "number", "title": "string", "status": "string"])
        case .projectGet, .projectComplete:
            ToolInputSchema(required: ["id"], properties: ["id": "number"])
        default:
            ToolInputSchema()
        }
    }
}

public struct TaskTool: Tool {
    public let name: ActionTool
    public let description: String
    public let inputSchema: ToolInputSchema
    public let permissionLevel: ToolPermissionLevel
    private let store: SQLiteTaskStore

    public init(name: ActionTool, store: SQLiteTaskStore) {
        self.name = name
        self.description = name.rawValue
        self.inputSchema = TaskTool.schema(for: name)
        self.permissionLevel = name.defaultRiskLevel >= .write ? .writeWithApproval : .read
        self.store = store
    }

    public func execute(arguments: [String: JSONValue], context: ToolExecutionContext) throws -> ToolResult {
        try enforcePermission(context: context)
        try validateRequiredArguments(arguments)

        let args = ToolArguments(arguments, tool: name)
        switch name {
        case .taskCreate:
            let record = try store.create(
                title: try args.requiredString("title"),
                projectID: args.optionalInt64("projectId"),
                dueAt: args.optionalString("dueAt"),
                priority: args.optionalString("priority"),
                sourceCommand: args.optionalString("sourceCommand")
            )
            return ToolResult(
                tool: name,
                status: .succeeded,
                summary: "Created task \(record.title)",
                output: ["taskId": .number(Double(record.id))],
                rollbackMetadata: ["taskId": .number(Double(record.id))],
                compensationHint: "Task can be completed or deleted by a future cleanup flow."
            )
        case .taskBulkCreate:
            let taskObjects = args.objectArray("tasks")
            guard !taskObjects.isEmpty else {
                throw ToolExecutionError.validationFailed(name, "tasks must contain at least one task.")
            }
            var created: [JSONValue] = []
            for taskObject in taskObjects {
                let taskArgs = ToolArguments(taskObject, tool: name)
                let record = try store.create(
                    title: try taskArgs.requiredString("title"),
                    projectID: taskArgs.optionalInt64("projectId"),
                    dueAt: taskArgs.optionalString("dueAt")
                )
                created.append(.number(Double(record.id)))
            }
            return ToolResult(tool: name, status: .succeeded, summary: "Created \(created.count) tasks", output: ["taskIds": .array(created)])
        case .taskUpdate:
            let record = try store.update(id: try args.requiredInt64("id"), title: args.optionalString("title"), status: args.optionalString("status"))
            return ToolResult(tool: name, status: .succeeded, summary: "Updated task \(record.title)", output: ["taskId": .number(Double(record.id))])
        case .taskComplete:
            let record = try store.update(id: try args.requiredInt64("id"), status: "completed")
            return ToolResult(tool: name, status: .succeeded, summary: "Completed task \(record.title)", output: ["taskId": .number(Double(record.id))])
        case .taskListDue:
            let tasks = try store.listDue(onOrBefore: args.optionalString("cutoff") ?? ISO8601DateFormatter().string(from: context.now))
            return ToolResult(tool: name, status: .succeeded, summary: "\(tasks.count) due tasks", output: ["count": .number(Double(tasks.count))])
        case .taskListOverdue:
            let tasks = try store.listOverdue(before: args.optionalString("cutoff") ?? ISO8601DateFormatter().string(from: context.now))
            return ToolResult(tool: name, status: .succeeded, summary: "\(tasks.count) overdue tasks", output: ["count": .number(Double(tasks.count))])
        default:
            throw ToolExecutionError.executionFailed(name, "Unsupported task tool.")
        }
    }

    private static func schema(for name: ActionTool) -> ToolInputSchema {
        switch name {
        case .taskCreate:
            ToolInputSchema(required: ["title"], properties: ["title": "string", "projectId": "number", "dueAt": "string"])
        case .taskBulkCreate:
            ToolInputSchema(required: ["tasks"], properties: ["tasks": "array"])
        case .taskUpdate:
            ToolInputSchema(required: ["id"], properties: ["id": "number", "title": "string", "status": "string"])
        case .taskComplete:
            ToolInputSchema(required: ["id"], properties: ["id": "number"])
        default:
            ToolInputSchema()
        }
    }
}

public struct KnowledgeFrameTool: Tool {
    public let name: ActionTool
    public let description: String
    public let inputSchema: ToolInputSchema
    public let permissionLevel: ToolPermissionLevel
    private let store: SQLiteKnowledgeFrameStore

    public init(name: ActionTool, store: SQLiteKnowledgeFrameStore) {
        self.name = name
        self.description = name.rawValue
        self.inputSchema = KnowledgeFrameTool.schema(for: name)
        self.permissionLevel = name.defaultRiskLevel >= .write ? .writeWithApproval : .read
        self.store = store
    }

    public func execute(arguments: [String: JSONValue], context: ToolExecutionContext) throws -> ToolResult {
        try enforcePermission(context: context)
        try validateRequiredArguments(arguments)

        let args = ToolArguments(arguments, tool: name)
        switch name {
        case .frameCreate:
            let frame = try store.create(name: try args.requiredString("name"), body: try args.requiredString("body"), triggers: args.stringArray("triggers"))
            return ToolResult(
                tool: name,
                status: .succeeded,
                summary: "Created frame \(frame.name)",
                output: ["frameId": .number(Double(frame.id))],
                rollbackMetadata: ["frameId": .number(Double(frame.id))]
            )
        case .frameUpdate:
            let frame = try store.update(
                id: try args.requiredInt64("id"),
                name: args.optionalString("name"),
                body: args.optionalString("body"),
                triggers: args.optionalStringArray("triggers")
            )
            return ToolResult(tool: name, status: .succeeded, summary: "Updated frame \(frame.name)", output: ["frameId": .number(Double(frame.id))])
        case .frameGet:
            let frame = try store.get(id: try args.requiredInt64("id"))
            return ToolResult(tool: name, status: .succeeded, summary: frame.name, output: frame.output)
        case .frameList:
            let frames = try store.list()
            return ToolResult(tool: name, status: .succeeded, summary: "\(frames.count) frames", output: ["count": .number(Double(frames.count))])
        case .frameSearch:
            let frames = try store.search(query: try args.requiredString("query"))
            return ToolResult(tool: name, status: .succeeded, summary: "\(frames.count) matching frames", output: ["count": .number(Double(frames.count))])
        default:
            throw ToolExecutionError.executionFailed(name, "Unsupported knowledge frame tool.")
        }
    }

    private static func schema(for name: ActionTool) -> ToolInputSchema {
        switch name {
        case .frameCreate:
            ToolInputSchema(required: ["name", "body"], properties: ["name": "string", "body": "string", "triggers": "array"])
        case .frameUpdate:
            ToolInputSchema(required: ["id"], properties: ["id": "number", "name": "string", "body": "string", "triggers": "array"])
        case .frameGet:
            ToolInputSchema(required: ["id"], properties: ["id": "number"])
        case .frameSearch:
            ToolInputSchema(required: ["query"], properties: ["query": "string"])
        default:
            ToolInputSchema()
        }
    }
}

public extension ToolRegistry {
    static func phase2Core(
        projectStore: SQLiteProjectStore,
        taskStore: SQLiteTaskStore,
        knowledgeStore: SQLiteKnowledgeFrameStore
    ) throws -> ToolRegistry {
        try ToolRegistry(tools: phase2CoreTools(projectStore: projectStore, taskStore: taskStore, knowledgeStore: knowledgeStore))
    }

    static func phase2MVP(
        projectStore: SQLiteProjectStore,
        taskStore: SQLiteTaskStore,
        knowledgeStore: SQLiteKnowledgeFrameStore,
        notificationClient: any NotificationClient,
        calendarClient: any CalendarClient,
        reminderClient: any ReminderClient,
        fileAccessClient: any FileAccessClient,
        mailDraftClient: any MailDraftClient,
        auditLogger: (any AuditLogger)? = nil
    ) throws -> ToolRegistry {
        var tools = phase2CoreTools(projectStore: projectStore, taskStore: taskStore, knowledgeStore: knowledgeStore)
        let systemTools: [any Tool] = [
            NotificationTool(name: .notificationSchedule, client: notificationClient),
            NotificationTool(name: .notificationScheduleRelative, client: notificationClient),
            NotificationTool(name: .notificationScheduleOverdueRule, client: notificationClient),
            NotificationTool(name: .notificationCancel, client: notificationClient),
            NotificationTool(name: .notificationList, client: notificationClient),
            CalendarTool(name: .calendarCreateEvent, client: calendarClient),
            CalendarTool(name: .calendarCreateDeadline, client: calendarClient),
            CalendarTool(name: .calendarCreateWorkBlock, client: calendarClient),
            ReminderTool(name: .remindersCreate, client: reminderClient),
            ReminderTool(name: .remindersBulkCreate, client: reminderClient),
            ReminderTool(name: .remindersMarkComplete, client: reminderClient),
            FileSystemTool(name: .filesystemCreateDirectory, client: fileAccessClient),
            FileSystemTool(name: .filesystemCreateMarkdownFile, client: fileAccessClient),
            FileSystemTool(name: .filesystemCreateArtifactsFromFrame, client: fileAccessClient),
            FileSystemTool(name: .filesystemScanProjectArtifacts, client: fileAccessClient),
            MailDraftTool(client: mailDraftClient)
        ]
        tools.append(contentsOf: systemTools)

        if let auditLogger {
            tools = tools.map { AuditedTool(base: $0, logger: auditLogger) }
        }

        return try ToolRegistry(tools: tools)
    }

    private static func phase2CoreTools(
        projectStore: SQLiteProjectStore,
        taskStore: SQLiteTaskStore,
        knowledgeStore: SQLiteKnowledgeFrameStore
    ) -> [any Tool] {
        [
            ProjectTool(name: .projectCreate, store: projectStore),
            ProjectTool(name: .projectUpdate, store: projectStore),
            ProjectTool(name: .projectList, store: projectStore),
            ProjectTool(name: .projectGet, store: projectStore),
            ProjectTool(name: .projectComplete, store: projectStore),
            TaskTool(name: .taskCreate, store: taskStore),
            TaskTool(name: .taskBulkCreate, store: taskStore),
            TaskTool(name: .taskUpdate, store: taskStore),
            TaskTool(name: .taskComplete, store: taskStore),
            TaskTool(name: .taskListDue, store: taskStore),
            TaskTool(name: .taskListOverdue, store: taskStore),
            KnowledgeFrameTool(name: .frameSearch, store: knowledgeStore),
            KnowledgeFrameTool(name: .frameList, store: knowledgeStore),
            KnowledgeFrameTool(name: .frameGet, store: knowledgeStore),
            KnowledgeFrameTool(name: .frameCreate, store: knowledgeStore),
            KnowledgeFrameTool(name: .frameUpdate, store: knowledgeStore)
        ]
    }
}

private extension ProjectRecord {
    var output: [String: JSONValue] {
        [
            "id": .number(Double(id)),
            "title": .string(title),
            "status": .string(status)
        ]
    }
}

private extension KnowledgeFrameRecord {
    var output: [String: JSONValue] {
        [
            "id": .number(Double(id)),
            "name": .string(name),
            "body": .string(body),
            "triggers": JSONValueFactory.strings(triggers)
        ]
    }
}
