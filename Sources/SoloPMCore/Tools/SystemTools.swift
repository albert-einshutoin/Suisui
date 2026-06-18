import Foundation

public struct NotificationTool: Tool {
    public let name: ActionTool
    public let description: String
    public let inputSchema: ToolInputSchema
    public let permissionLevel: ToolPermissionLevel
    private let client: any NotificationClient
    private let requestStore: SQLiteNotificationRequestStore?

    public init(name: ActionTool, client: any NotificationClient, requestStore: SQLiteNotificationRequestStore? = nil) {
        self.name = name
        self.description = name.rawValue
        self.inputSchema = NotificationTool.schema(for: name)
        self.permissionLevel = name.defaultRiskLevel >= .write ? .writeWithApproval : .read
        self.client = client
        self.requestStore = requestStore
    }

    public func execute(arguments: [String: JSONValue], context: ToolExecutionContext) throws -> ToolResult {
        try enforcePermission(context: context)
        try validateRequiredArguments(arguments)

        let args = ToolArguments(arguments, tool: name)
        do {
            switch name {
            case .notificationSchedule:
                return try schedule(
                    NotificationDraft(
                        title: try args.requiredString("title"),
                        body: args.optionalString("body"),
                        scheduledAt: try args.requiredString("scheduledAt"),
                        identifierHint: args.optionalString("id")
                    )
                )
            case .notificationScheduleRelative:
                let offsetSeconds = try args.requiredInt64("offsetSeconds")
                guard offsetSeconds > 0 else {
                    throw ToolExecutionError.validationFailed(name, "offsetSeconds must be greater than 0.")
                }
                let offset = TimeInterval(offsetSeconds)
                let scheduledAt = ISO8601DateFormatter().string(from: context.now.addingTimeInterval(offset))
                return try schedule(NotificationDraft(title: try args.requiredString("title"), body: args.optionalString("body"), scheduledAt: scheduledAt))
            case .notificationScheduleOverdueRule:
                let taskID = try args.requiredInt64("taskId")
                let title = args.optionalString("title") ?? "Task \(taskID) is overdue"
                return try schedule(NotificationDraft(title: title, body: args.optionalString("body"), scheduledAt: "overdue-rule:task-\(taskID)"))
            case .notificationCancel:
                let id = try args.requiredString("id")
                try client.cancel(id: id)
                return ToolResult(tool: name, status: .succeeded, summary: "Canceled notification \(id)", output: ["notificationId": .string(id)])
            case .notificationList:
                let records = try client.listScheduled()
                return ToolResult(tool: name, status: .succeeded, summary: "\(records.count) notifications", output: ["count": .number(Double(records.count))])
            default:
                throw ToolExecutionError.executionFailed(name, "Unsupported notification tool.")
            }
        } catch let error as ToolClientError {
            throw ToolExecutionError.executionFailed(name, error.message)
        }
    }

    private func schedule(_ draft: NotificationDraft) throws -> ToolResult {
        let requestID = draft.identifierHint ?? "notification-request-\(UUID().uuidString)"
        try requestStore?.createPending(requestID: requestID, title: draft.title, scheduledAt: draft.scheduledAt)

        do {
            let record = try client.schedule(draft)
            try requestStore?.markScheduled(requestID: requestID, externalNotificationID: record.id)
            return scheduledResult(record)
        } catch let error as ToolClientError {
            if case .permissionDenied = error {
                try markRequestFailedOrThrow(requestID: requestID, reason: error.message)
            }
            throw error
        } catch {
            try markRequestFailedOrThrow(requestID: requestID, reason: String(describing: error))
            throw error
        }
    }

    private func markRequestFailedOrThrow(requestID: String, reason: String) throws {
        guard let requestStore else {
            return
        }

        do {
            _ = try requestStore.markFailed(requestID: requestID, reason: reason)
        } catch {
            throw ToolExecutionError.executionFailed(
                name,
                "\(reason) Failed to persist notification failure state: \(String(describing: error))"
            )
        }
    }

    private func scheduledResult(_ record: NotificationRecord) -> ToolResult {
        ToolResult(
            tool: name,
            status: .succeeded,
            summary: "Scheduled notification \(record.title)",
            output: ["notificationId": .string(record.id)],
            rollbackMetadata: ["notificationId": .string(record.id)],
            compensationHint: "Cancel notification \(record.id) if the plan is rolled back."
        )
    }

    private static func schema(for name: ActionTool) -> ToolInputSchema {
        switch name {
        case .notificationSchedule:
            ToolInputSchema(required: ["title", "scheduledAt"], properties: ["title": "string", "body": "string", "scheduledAt": "string", "id": "string"])
        case .notificationScheduleRelative:
            ToolInputSchema(required: ["title", "offsetSeconds"], properties: ["title": "string", "body": "string", "offsetSeconds": "number"])
        case .notificationScheduleOverdueRule:
            ToolInputSchema(required: ["taskId"], properties: ["taskId": "number", "title": "string", "body": "string"])
        case .notificationCancel:
            ToolInputSchema(required: ["id"], properties: ["id": "string"])
        default:
            ToolInputSchema()
        }
    }
}

public struct CalendarTool: Tool {
    public let name: ActionTool
    public let description: String
    public let inputSchema: ToolInputSchema
    public let permissionLevel: ToolPermissionLevel
    private let client: any CalendarClient
    private let linkStore: SQLiteCalendarLinkStore?

    public init(name: ActionTool, client: any CalendarClient, linkStore: SQLiteCalendarLinkStore? = nil) {
        self.name = name
        self.description = name.rawValue
        self.inputSchema = CalendarTool.schema(for: name)
        self.permissionLevel = .writeWithApproval
        self.client = client
        self.linkStore = linkStore
    }

    public func execute(arguments: [String: JSONValue], context: ToolExecutionContext) throws -> ToolResult {
        try enforcePermission(context: context)
        try validateRequiredArguments(arguments)

        let args = ToolArguments(arguments, tool: name)
        do {
            let draft: CalendarEventDraft
            switch name {
            case .calendarCreateEvent:
                draft = try makeEventDraft(args: args)
            case .calendarCreateDeadline:
                let dueDate = try args.requiredString("dueDate")
                draft = CalendarEventDraft(title: try args.requiredString("title"), startAt: dueDate, endAt: dueDate, isAllDay: true, notes: args.optionalString("notes"))
            case .calendarCreateWorkBlock:
                let startAt = try args.requiredString("startAt")
                let start = try ToolDateParser.date(from: startAt, tool: name)
                let durationMinutes = try args.requiredInt64("durationMinutes")
                guard durationMinutes > 0 else {
                    throw ToolExecutionError.validationFailed(name, "durationMinutes must be greater than 0.")
                }
                let duration = TimeInterval(durationMinutes * 60)
                let endAt = ISO8601DateFormatter().string(from: start.addingTimeInterval(duration))
                draft = CalendarEventDraft(title: try args.requiredString("title"), startAt: startAt, endAt: endAt, notes: args.optionalString("notes"))
            default:
                throw ToolExecutionError.executionFailed(name, "Unsupported calendar tool.")
            }

            let record = try client.createEvent(draft)
            try linkCalendarEventIfNeeded(record: record, args: args)
            return ToolResult(
                tool: name,
                status: .succeeded,
                summary: "Created calendar event \(record.draft.title)",
                output: ["eventId": .string(record.id)],
                rollbackMetadata: ["eventId": .string(record.id)]
            )
        } catch let error as ToolClientError {
            throw ToolExecutionError.executionFailed(name, error.message)
        }
    }

    private func linkCalendarEventIfNeeded(record: CalendarEventRecord, args: ToolArguments) throws {
        let projectID = args.optionalInt64("projectId")
        let taskID = args.optionalInt64("taskId")
        guard projectID != nil || taskID != nil else {
            return
        }

        try linkStore?.link(eventID: record.id, projectID: projectID, taskID: taskID, title: record.draft.title)
    }

    private func makeEventDraft(args: ToolArguments) throws -> CalendarEventDraft {
        let startAt = try args.requiredString("startAt")
        let endAt = try args.requiredString("endAt")
        let start = try ToolDateParser.date(from: startAt, tool: name)
        let end = try ToolDateParser.date(from: endAt, tool: name)
        guard start < end else {
            throw ToolExecutionError.validationFailed(name, "startAt must be before endAt.")
        }

        return CalendarEventDraft(title: try args.requiredString("title"), startAt: startAt, endAt: endAt, notes: args.optionalString("notes"))
    }

    private static func schema(for name: ActionTool) -> ToolInputSchema {
        switch name {
        case .calendarCreateEvent:
            ToolInputSchema(required: ["title", "startAt", "endAt"], properties: ["title": "string", "startAt": "string", "endAt": "string", "notes": "string", "projectId": "number", "taskId": "number"])
        case .calendarCreateDeadline:
            ToolInputSchema(required: ["title", "dueDate"], properties: ["title": "string", "dueDate": "string", "notes": "string", "projectId": "number", "taskId": "number"])
        case .calendarCreateWorkBlock:
            ToolInputSchema(required: ["title", "startAt", "durationMinutes"], properties: ["title": "string", "startAt": "string", "durationMinutes": "number", "notes": "string", "projectId": "number", "taskId": "number"])
        default:
            ToolInputSchema()
        }
    }
}

public struct ReminderTool: Tool {
    public let name: ActionTool
    public let description: String
    public let inputSchema: ToolInputSchema
    public let permissionLevel: ToolPermissionLevel
    private let client: any ReminderClient
    private let linkStore: SQLiteReminderLinkStore?

    public init(name: ActionTool, client: any ReminderClient, linkStore: SQLiteReminderLinkStore? = nil) {
        self.name = name
        self.description = name.rawValue
        self.inputSchema = ReminderTool.schema(for: name)
        self.permissionLevel = .writeWithApproval
        self.client = client
        self.linkStore = linkStore
    }

    public func execute(arguments: [String: JSONValue], context: ToolExecutionContext) throws -> ToolResult {
        try enforcePermission(context: context)
        try validateRequiredArguments(arguments)

        let args = ToolArguments(arguments, tool: name)
        do {
            switch name {
            case .remindersCreate:
                let record = try client.create(makeDraft(args))
                try linkReminderIfNeeded(record: record, args: args)
                return createdResult(record)
            case .remindersBulkCreate:
                let reminderObjects = try args.objectArray("reminders")
                guard !reminderObjects.isEmpty else {
                    throw ToolExecutionError.validationFailed(name, "reminders must contain at least one item.")
                }
                let perReminderArgs = reminderObjects.map { ToolArguments($0, tool: name) }
                let drafts = try perReminderArgs.map(makeDraft)
                let records = try drafts.map { try client.create($0) }
                for (record, reminderArgs) in zip(records, perReminderArgs) {
                    try linkReminderIfNeeded(record: record, args: reminderArgs)
                }
                return ToolResult(
                    tool: name,
                    status: .succeeded,
                    summary: "Created \(records.count) reminders",
                    output: ["reminderIds": JSONValueFactory.strings(records.map(\.id))]
                )
            case .remindersMarkComplete:
                let record = try client.markComplete(id: try args.requiredString("id"))
                return ToolResult(tool: name, status: .succeeded, summary: "Completed reminder \(record.title)", output: ["reminderId": .string(record.id)])
            default:
                throw ToolExecutionError.executionFailed(name, "Unsupported reminder tool.")
            }
        } catch let error as ToolClientError {
            throw ToolExecutionError.executionFailed(name, error.message)
        }
    }

    private func linkReminderIfNeeded(record: ReminderRecord, args: ToolArguments) throws {
        let projectID = args.optionalInt64("projectId")
        let taskID = args.optionalInt64("taskId")
        guard projectID != nil || taskID != nil else {
            return
        }

        try linkStore?.link(reminderID: record.id, projectID: projectID, taskID: taskID, title: record.title)
    }

    private func makeDraft(_ args: ToolArguments) throws -> ReminderDraft {
        ReminderDraft(title: try args.requiredString("title"), dueAt: args.optionalString("dueAt"), listName: args.optionalString("listName"))
    }

    private func createdResult(_ record: ReminderRecord) -> ToolResult {
        ToolResult(
            tool: name,
            status: .succeeded,
            summary: "Created reminder \(record.title)",
            output: ["reminderId": .string(record.id)],
            rollbackMetadata: ["reminderId": .string(record.id)]
        )
    }

    private static func schema(for name: ActionTool) -> ToolInputSchema {
        switch name {
        case .remindersCreate:
            ToolInputSchema(required: ["title"], properties: ["title": "string", "dueAt": "string", "listName": "string", "projectId": "number", "taskId": "number"])
        case .remindersBulkCreate:
            ToolInputSchema(required: ["reminders"], properties: ["reminders": "array"])
        case .remindersMarkComplete:
            ToolInputSchema(required: ["id"], properties: ["id": "string"])
        default:
            ToolInputSchema()
        }
    }
}

public struct FileSystemTool: Tool {
    public let name: ActionTool
    public let description: String
    public let inputSchema: ToolInputSchema
    public let permissionLevel: ToolPermissionLevel
    private let client: any FileAccessClient

    public init(name: ActionTool, client: any FileAccessClient) {
        self.name = name
        self.description = name.rawValue
        self.inputSchema = FileSystemTool.schema(for: name)
        self.permissionLevel = name.defaultRiskLevel >= .write ? .writeWithApproval : .read
        self.client = client
    }

    public func execute(arguments: [String: JSONValue], context: ToolExecutionContext) throws -> ToolResult {
        try enforcePermission(context: context)
        try validateRequiredArguments(arguments)

        let args = ToolArguments(arguments, tool: name)
        do {
            switch name {
            case .filesystemCreateDirectory:
                let artifact = try client.createDirectory(relativePath: try args.requiredString("relativePath"))
                return artifactResult(artifact, summary: "Created directory \(artifact.relativePath)")
            case .filesystemCreateMarkdownFile:
                let artifact = try client.createMarkdownFile(relativePath: try args.requiredString("relativePath"), contents: try args.requiredString("contents"))
                return artifactResult(artifact, summary: "Created file \(artifact.relativePath)")
            case .filesystemCreateArtifactsFromFrame:
                let directory = args.optionalString("directory") ?? "."
                let filename = "\(Self.slug(try args.requiredString("frameName"))).md"
                let relativePath = directory == "." ? filename : "\(directory)/\(filename)"
                let artifact = try client.createMarkdownFile(relativePath: relativePath, contents: try args.requiredString("body"))
                return artifactResult(artifact, summary: "Created frame artifact \(artifact.relativePath)")
            case .filesystemScanProjectArtifacts:
                let artifacts = try client.scan(relativePath: args.optionalString("relativePath") ?? ".")
                return ToolResult(tool: name, status: .succeeded, summary: "\(artifacts.count) artifacts", output: ["count": .number(Double(artifacts.count))])
            default:
                throw ToolExecutionError.executionFailed(name, "Unsupported filesystem tool.")
            }
        } catch let error as ToolClientError {
            throw ToolExecutionError.executionFailed(name, error.message)
        }
    }

    private func artifactResult(_ artifact: FileArtifact, summary: String) -> ToolResult {
        ToolResult(
            tool: name,
            status: .succeeded,
            summary: summary,
            output: ["relativePath": .string(artifact.relativePath)],
            rollbackMetadata: ["relativePath": .string(artifact.relativePath)]
        )
    }

    private static func schema(for name: ActionTool) -> ToolInputSchema {
        switch name {
        case .filesystemCreateDirectory:
            ToolInputSchema(required: ["relativePath"], properties: ["relativePath": "string"])
        case .filesystemCreateMarkdownFile:
            ToolInputSchema(required: ["relativePath", "contents"], properties: ["relativePath": "string", "contents": "string"])
        case .filesystemCreateArtifactsFromFrame:
            ToolInputSchema(required: ["frameName", "body"], properties: ["frameName": "string", "body": "string", "directory": "string"])
        case .filesystemScanProjectArtifacts:
            ToolInputSchema(required: [], properties: ["relativePath": "string"])
        default:
            ToolInputSchema()
        }
    }

    private static func slug(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let scalars = value.lowercased().unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let collapsed = String(scalars).split(separator: "-").joined(separator: "-")
        return collapsed.isEmpty ? "frame" : collapsed
    }
}

public struct MailDraftTool: Tool {
    public let name: ActionTool = .mailDraftCreateText
    public let description: String = "Create a local text-only email draft"
    public let inputSchema = ToolInputSchema(required: ["subject", "body"], properties: ["to": "string", "subject": "string", "body": "string"])
    public let permissionLevel: ToolPermissionLevel = .draft
    private let client: any MailDraftClient

    public init(client: any MailDraftClient) {
        self.client = client
    }

    public func execute(arguments: [String: JSONValue], context: ToolExecutionContext) throws -> ToolResult {
        try enforcePermission(context: context)
        try validateRequiredArguments(arguments)

        let args = ToolArguments(arguments, tool: name)
        let record = try client.createTextDraft(
            to: args.optionalString("to"),
            subject: try args.requiredString("subject"),
            body: try args.requiredString("body")
        )
        return ToolResult(tool: name, status: .succeeded, summary: "Created mail draft \(record.subject)", output: ["draftId": .string(record.id)])
    }
}

private enum ToolDateParser {
    static func date(from value: String, tool: ActionTool) throws -> Date {
        if let date = ISO8601DateFormatter().date(from: value) {
            return date
        }
        throw ToolExecutionError.validationFailed(tool, "Invalid ISO8601 date: \(value)")
    }
}
