import Foundation

public struct ProjectTool: Tool {
    public let name: ActionTool
    public let description: String
    public let inputSchema: ToolInputSchema
    public let permissionLevel: ToolPermissionLevel
    private let store: SQLiteProjectStore
    private let taskStore: SQLiteTaskStore?

    public init(name: ActionTool, store: SQLiteProjectStore, taskStore: SQLiteTaskStore? = nil) {
        self.name = name
        self.description = name.rawValue
        self.inputSchema = ProjectTool.schema(for: name)
        self.permissionLevel = name.defaultRiskLevel >= .write ? .writeWithApproval : .read
        self.store = store
        self.taskStore = taskStore
    }

    public func execute(arguments: [String: JSONValue], context: ToolExecutionContext) throws -> ToolResult {
        try enforcePermission(context: context)
        try validateRequiredArguments(arguments)

        let args = ToolArguments(arguments, tool: name)
        switch name {
        case .projectCreate:
            let record = try store.create(
                title: try args.requiredTrimmedString("title"),
                priority: try args.optionalTrimmedString("priority"),
                deadline: try args.optionalTrimmedString("deadline"),
                workspacePath: try args.optionalTrimmedString("workspacePath"),
                tags: try args.trimmedStringArray("tags"),
                sourceCommand: try args.optionalTrimmedString("sourceCommand")
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
            let record = try store.updateFields(
                id: try args.requiredInt64("id"),
                title: try args.optionalTrimmedString("title"),
                status: try args.optionalTrimmedString("status"),
                priority: try args.nullableTrimmedString("priority"),
                deadline: try args.nullableTrimmedString("deadline"),
                workspacePath: try args.nullableTrimmedString("workspacePath"),
                tags: try args.nullableTrimmedStringArray("tags")
            )
            return ToolResult(tool: name, status: .succeeded, summary: "Updated project \(record.title)", output: ["projectId": .number(Double(record.id))])
        case .projectComplete:
            guard let taskStore else {
                throw ToolExecutionError.executionFailed(name, "Task store is required to complete project tasks.")
            }
            let record = try store.complete(id: try args.requiredInt64("id"), taskStore: taskStore)
            return ToolResult(tool: name, status: .succeeded, summary: "Completed project \(record.title)", output: ["projectId": .number(Double(record.id))])
        case .projectDelete:
            let deletion = try store.delete(id: try args.requiredInt64("id"))
            return ToolResult(
                tool: name,
                status: .succeeded,
                summary: "Deleted project \(deletion.project.title)",
                output: [
                    "projectId": .number(Double(deletion.project.id)),
                    "deletedTaskCount": .number(Double(deletion.deletedTaskCount)),
                    "deletedCalendarLinkCount": .number(Double(deletion.deletedCalendarLinkCount)),
                    "deletedReminderLinkCount": .number(Double(deletion.deletedReminderLinkCount)),
                    "deletedDeadlineRuleCount": .number(Double(deletion.deletedDeadlineRuleCount)),
                    "deletedArtifactCount": .number(Double(deletion.deletedArtifactCount))
                ]
            )
        case .projectGet:
            let record = try store.get(id: try args.requiredInt64("id"))
            return ToolResult(tool: name, status: .succeeded, summary: record.title, output: record.output)
        case .projectList:
            let records = try store.list()
            return ToolResult(
                tool: name,
                status: .succeeded,
                summary: "\(records.count) projects",
                output: [
                    "count": .number(Double(records.count)),
                    "projects": .array(records.map { .object($0.output) })
                ]
            )
        default:
            throw ToolExecutionError.executionFailed(name, "Unsupported project tool.")
        }
    }

    private static func schema(for name: ActionTool) -> ToolInputSchema {
        switch name {
        case .projectCreate:
            ToolInputSchema(
                required: ["title"],
                properties: ["title": "string", "priority": "string", "deadline": "string", "workspacePath": "string", "tags": "array", "sourceCommand": "string"],
                nonBlank: ["priority", "deadline", "workspacePath", "sourceCommand"]
            )
        case .projectUpdate:
            ToolInputSchema(
                required: ["id"],
                properties: ["id": "integer", "title": "string", "status": "string", "priority": "string|null", "deadline": "string|null", "workspacePath": "string|null", "tags": "array|null"],
                nonBlank: ["title", "status", "priority", "deadline", "workspacePath"]
            )
        case .projectGet, .projectComplete, .projectDelete:
            ToolInputSchema(required: ["id"], properties: ["id": "integer"])
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
    private let projectStore: SQLiteProjectStore?

    public init(name: ActionTool, store: SQLiteTaskStore, projectStore: SQLiteProjectStore? = nil) {
        self.name = name
        self.description = name.rawValue
        self.inputSchema = TaskTool.schema(for: name)
        self.permissionLevel = name.defaultRiskLevel >= .write ? .writeWithApproval : .read
        self.store = store
        self.projectStore = projectStore
    }

    public func execute(arguments: [String: JSONValue], context: ToolExecutionContext) throws -> ToolResult {
        try enforcePermission(context: context)
        try validateRequiredArguments(arguments)

        let args = ToolArguments(arguments, tool: name)
        switch name {
        case .taskCreate:
            let projectID = try args.optionalInt64("projectId")
            try prepareProjectForTaskMutation(projectID: projectID, status: "open")
            let record = try store.create(
                title: try args.requiredTrimmedString("title"),
                projectID: projectID,
                dueAt: try args.optionalTrimmedString("dueAt"),
                priority: try args.optionalTrimmedString("priority"),
                sourceCommand: try args.optionalTrimmedString("sourceCommand"),
                detail: try args.optionalTrimmedString("detail")
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
            let taskObjects = try args.objectArray("tasks")
            guard !taskObjects.isEmpty else {
                throw ToolExecutionError.validationFailed(name, "tasks must contain at least one task.")
            }
            let drafts = try taskObjects.map { taskObject in
                let taskArgs = ToolArguments(taskObject, tool: name)
                return TaskCreateDraft(
                    title: try taskArgs.requiredTrimmedString("title"),
                    projectID: try taskArgs.optionalInt64("projectId"),
                    dueAt: try taskArgs.optionalTrimmedString("dueAt"),
                    priority: try taskArgs.optionalTrimmedString("priority"),
                    sourceCommand: try taskArgs.optionalTrimmedString("sourceCommand"),
                    detail: try taskArgs.optionalTrimmedString("detail")
                )
            }
            try drafts.forEach { try rejectArchivedProject(projectID: $0.projectID) }
            try drafts.forEach { try reopenCompletedProjectIfNeeded(projectID: $0.projectID, status: $0.status) }
            let created = try store.createMany(drafts).map { JSONValue.number(Double($0.id)) }
            return ToolResult(tool: name, status: .succeeded, summary: "Created \(created.count) tasks", output: ["taskIds": .array(created)])
        case .taskGet:
            let record = try store.get(id: try args.requiredInt64("id"))
            return ToolResult(tool: name, status: .succeeded, summary: record.title, output: record.output)
        case .taskUpdate:
            let taskID = try args.requiredInt64("id")
            let current = try store.get(id: taskID)
            let nextStatus = try args.optionalTrimmedString("status") ?? current.status
            let projectIDUpdate = try args.nullableInt64("projectId")
            let nextProjectID = projectIDUpdate.applying(to: current.projectID)
            try prepareProjectForTaskMutation(projectID: nextProjectID, status: nextStatus)
            let record = try store.updateFields(
                id: taskID,
                title: try args.optionalTrimmedString("title"),
                status: nextStatus,
                detail: try args.nullableTrimmedString("detail"),
                dueAt: try args.nullableTrimmedString("dueAt"),
                priority: try args.nullableTrimmedString("priority"),
                projectID: projectIDUpdate
            )
            return ToolResult(tool: name, status: .succeeded, summary: "Updated task \(record.title)", output: ["taskId": .number(Double(record.id))])
        case .taskComplete:
            let record = try store.update(id: try args.requiredInt64("id"), status: "completed")
            return ToolResult(tool: name, status: .succeeded, summary: "Completed task \(record.title)", output: ["taskId": .number(Double(record.id))])
        case .taskDelete:
            let taskID = try args.requiredInt64("id")
            let deletion = try store.delete(id: taskID)
            return ToolResult(
                tool: name,
                status: .succeeded,
                summary: "Deleted task \(deletion.task.title)",
                output: [
                    "taskId": .number(Double(deletion.task.id)),
                    "deletedCalendarLinkCount": .number(Double(deletion.deletedCalendarLinkCount)),
                    "deletedReminderLinkCount": .number(Double(deletion.deletedReminderLinkCount)),
                    "deletedDeadlineRuleCount": .number(Double(deletion.deletedDeadlineRuleCount)),
                    "deletedArtifactCount": .number(Double(deletion.deletedArtifactCount))
                ]
            )
        case .taskListDue:
            let tasks = try store.listDue(onOrBefore: try args.optionalString("cutoff") ?? ISO8601DateFormatter().string(from: context.now))
            return ToolResult(
                tool: name,
                status: .succeeded,
                summary: "\(tasks.count) due tasks",
                output: [
                    "count": .number(Double(tasks.count)),
                    "tasks": .array(tasks.map { .object($0.output) })
                ]
            )
        case .taskListOverdue:
            let tasks = try store.listOverdue(before: try args.optionalString("cutoff") ?? ISO8601DateFormatter().string(from: context.now))
            return ToolResult(
                tool: name,
                status: .succeeded,
                summary: "\(tasks.count) overdue tasks",
                output: [
                    "count": .number(Double(tasks.count)),
                    "tasks": .array(tasks.map { .object($0.output) })
                ]
            )
        default:
            throw ToolExecutionError.executionFailed(name, "Unsupported task tool.")
        }
    }

    private func prepareProjectForTaskMutation(projectID: Int64?, status: String) throws {
        try rejectArchivedProject(projectID: projectID)
        try reopenCompletedProjectIfNeeded(projectID: projectID, status: status)
    }

    private func rejectArchivedProject(projectID: Int64?) throws {
        guard let projectID else {
            return
        }
        guard let projectStore else {
            throw ToolExecutionError.executionFailed(name, "Project store is required to validate project task mutations.")
        }

        let project = try projectStore.get(id: projectID)
        if project.status == "archived" {
            throw ToolExecutionError.validationFailed(name, "Restore the project before adding tasks.")
        }
    }

    private func reopenCompletedProjectIfNeeded(projectID: Int64?, status: String) throws {
        guard let projectID else {
            return
        }
        guard let projectStore else {
            throw ToolExecutionError.executionFailed(name, "Project store is required to validate project task mutations.")
        }

        let normalizedStatus = try StoreFieldValidation.taskStatus(status, tool: name)
        let project = try projectStore.get(id: projectID)
        if project.status == "completed", normalizedStatus != "completed" {
            _ = try projectStore.restore(id: projectID)
        }
    }

    private static func schema(for name: ActionTool) -> ToolInputSchema {
        switch name {
        case .taskCreate:
            ToolInputSchema(
                required: ["title"],
                properties: ["title": "string", "projectId": "integer", "detail": "string", "dueAt": "string", "priority": "string", "sourceCommand": "string"],
                nonBlank: ["detail", "dueAt", "priority", "sourceCommand"]
            )
        case .taskBulkCreate:
            ToolInputSchema(
                required: ["tasks"],
                properties: ["tasks": "array"],
                arrayItems: [
                    "tasks": ToolInputSchema(
                        required: ["title"],
                        properties: ["title": "string", "projectId": "integer", "detail": "string", "dueAt": "string", "priority": "string", "sourceCommand": "string"],
                        nonBlank: ["detail", "dueAt", "priority", "sourceCommand"]
                    )
                ]
            )
        case .taskGet, .taskDelete:
            ToolInputSchema(required: ["id"], properties: ["id": "integer"])
        case .taskUpdate:
            ToolInputSchema(
                required: ["id"],
                properties: ["id": "integer", "title": "string", "projectId": "integer|null", "status": "string", "detail": "string|null", "dueAt": "string|null", "priority": "string|null"],
                nonBlank: ["title", "status", "detail", "dueAt", "priority"]
            )
        case .taskComplete:
            ToolInputSchema(required: ["id"], properties: ["id": "integer"])
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
            let frame = try store.create(name: try args.requiredTrimmedString("name"), body: try args.requiredString("body"), triggers: try args.trimmedStringArray("triggers"))
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
                name: try args.optionalTrimmedString("name"),
                body: try args.optionalNonBlankString("body"),
                triggers: try args.optionalTrimmedStringArray("triggers")
            )
            return ToolResult(tool: name, status: .succeeded, summary: "Updated frame \(frame.name)", output: ["frameId": .number(Double(frame.id))])
        case .frameDelete:
            let frameID = try args.requiredInt64("id")
            let frame = try store.get(id: frameID)
            try store.delete(id: frameID)
            return ToolResult(tool: name, status: .succeeded, summary: "Deleted frame \(frame.name)", output: ["frameId": .number(Double(frame.id))])
        case .frameGet:
            let frame = try store.get(id: try args.requiredInt64("id"))
            return ToolResult(tool: name, status: .succeeded, summary: frame.name, output: frame.output)
        case .frameList:
            let frames = try store.list()
            return ToolResult(
                tool: name,
                status: .succeeded,
                summary: "\(frames.count) frames",
                output: [
                    "count": .number(Double(frames.count)),
                    "frames": .array(frames.map { .object($0.output) })
                ]
            )
        case .frameSearch:
            let frames = try store.search(query: try args.requiredTrimmedString("query"))
            return ToolResult(
                tool: name,
                status: .succeeded,
                summary: "\(frames.count) matching frames",
                output: [
                    "count": .number(Double(frames.count)),
                    "frames": .array(frames.map { .object($0.output) })
                ]
            )
        default:
            throw ToolExecutionError.executionFailed(name, "Unsupported knowledge frame tool.")
        }
    }

    private static func schema(for name: ActionTool) -> ToolInputSchema {
        switch name {
        case .frameCreate:
            ToolInputSchema(required: ["name", "body"], properties: ["name": "string", "body": "string", "triggers": "array"])
        case .frameUpdate:
            ToolInputSchema(
                required: ["id"],
                properties: ["id": "integer", "name": "string", "body": "string", "triggers": "array"],
                nonBlank: ["name", "body"]
            )
        case .frameGet:
            ToolInputSchema(required: ["id"], properties: ["id": "integer"])
        case .frameDelete:
            ToolInputSchema(required: ["id"], properties: ["id": "integer"])
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
        notificationRequestStore: SQLiteNotificationRequestStore? = nil,
        calendarLinkStore: SQLiteCalendarLinkStore? = nil,
        reminderLinkStore: SQLiteReminderLinkStore? = nil,
        artifactStore: SQLiteArtifactStore? = nil,
        auditLogger: (any AuditLogger)? = nil
    ) throws -> ToolRegistry {
        var tools = phase2CoreTools(projectStore: projectStore, taskStore: taskStore, knowledgeStore: knowledgeStore)
        let systemTools: [any Tool] = [
            NotificationTool(name: .notificationSchedule, client: notificationClient, requestStore: notificationRequestStore),
            NotificationTool(name: .notificationScheduleRelative, client: notificationClient, requestStore: notificationRequestStore),
            NotificationTool(name: .notificationScheduleOverdueRule, client: notificationClient, requestStore: notificationRequestStore),
            NotificationTool(name: .notificationCancel, client: notificationClient, requestStore: notificationRequestStore),
            NotificationTool(name: .notificationList, client: notificationClient),
            CalendarTool(name: .calendarCreateEvent, client: calendarClient, linkStore: calendarLinkStore),
            CalendarTool(name: .calendarCreateDeadline, client: calendarClient, linkStore: calendarLinkStore),
            CalendarTool(name: .calendarCreateWorkBlock, client: calendarClient, linkStore: calendarLinkStore),
            ReminderTool(name: .remindersCreate, client: reminderClient, linkStore: reminderLinkStore),
            ReminderTool(name: .remindersBulkCreate, client: reminderClient, linkStore: reminderLinkStore),
            ReminderTool(name: .remindersMarkComplete, client: reminderClient, linkStore: reminderLinkStore),
            FileSystemTool(name: .filesystemCreateDirectory, client: fileAccessClient),
            FileSystemTool(name: .filesystemCreateMarkdownFile, client: fileAccessClient, artifactStore: artifactStore),
            FileSystemTool(name: .filesystemCreateArtifactsFromFrame, client: fileAccessClient, artifactStore: artifactStore),
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
            ProjectTool(name: .projectCreate, store: projectStore, taskStore: taskStore),
            ProjectTool(name: .projectUpdate, store: projectStore, taskStore: taskStore),
            ProjectTool(name: .projectList, store: projectStore, taskStore: taskStore),
            ProjectTool(name: .projectGet, store: projectStore, taskStore: taskStore),
            ProjectTool(name: .projectComplete, store: projectStore, taskStore: taskStore),
            ProjectTool(name: .projectDelete, store: projectStore, taskStore: taskStore),
            TaskTool(name: .taskCreate, store: taskStore, projectStore: projectStore),
            TaskTool(name: .taskBulkCreate, store: taskStore, projectStore: projectStore),
            TaskTool(name: .taskGet, store: taskStore, projectStore: projectStore),
            TaskTool(name: .taskUpdate, store: taskStore, projectStore: projectStore),
            TaskTool(name: .taskComplete, store: taskStore),
            TaskTool(name: .taskDelete, store: taskStore),
            TaskTool(name: .taskListDue, store: taskStore),
            TaskTool(name: .taskListOverdue, store: taskStore),
            KnowledgeFrameTool(name: .frameSearch, store: knowledgeStore),
            KnowledgeFrameTool(name: .frameList, store: knowledgeStore),
            KnowledgeFrameTool(name: .frameGet, store: knowledgeStore),
            KnowledgeFrameTool(name: .frameCreate, store: knowledgeStore),
            KnowledgeFrameTool(name: .frameUpdate, store: knowledgeStore),
            KnowledgeFrameTool(name: .frameDelete, store: knowledgeStore)
        ]
    }
}

private extension ProjectRecord {
    var output: [String: JSONValue] {
        var values: [String: JSONValue] = [
            "id": .number(Double(id)),
            "title": .string(title),
            "status": .string(status),
            "tags": JSONValueFactory.strings(tags)
        ]
        if let priority {
            values["priority"] = .string(priority)
        }
        if let deadline {
            values["deadline"] = .string(deadline)
        }
        if let workspacePath {
            values["workspacePath"] = .string(workspacePath)
        }
        return values
    }
}

private extension TaskRecord {
    var output: [String: JSONValue] {
        var values: [String: JSONValue] = [
            "id": .number(Double(id)),
            "title": .string(title),
            "status": .string(status)
        ]
        if let projectID {
            values["projectId"] = .number(Double(projectID))
        }
        if let detail {
            values["detail"] = .string(detail)
        }
        if let dueAt {
            values["dueAt"] = .string(dueAt)
        }
        if let priority {
            values["priority"] = .string(priority)
        }
        return values
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
