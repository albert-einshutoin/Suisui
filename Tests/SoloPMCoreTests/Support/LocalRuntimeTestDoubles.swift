import Foundation
@testable import SoloPMCore

final class InMemoryProjectBoardStore: ProjectBoardStore, @unchecked Sendable {
    private var snapshot: ProjectBoardSnapshot
    private var nextTaskID: Int64

    init(snapshot: ProjectBoardSnapshot = ProjectBoardSnapshot(projects: [
        ProjectBoardProject(
            id: 1,
            title: "Inbox",
            status: "active",
            subtitle: "0 open / 0 total",
            columns: ProjectTaskStatus.allCases.map { ProjectBoardColumn(status: $0, tasks: []) }
        )
    ])) {
        self.snapshot = snapshot
        self.nextTaskID = snapshot.projects.flatMap(\.tasks).map(\.id).max().map { $0 + 1 } ?? 1
    }

    func loadSnapshot() throws -> ProjectBoardSnapshot {
        snapshot
    }

    func loadSnapshot(includeArchived: Bool) throws -> ProjectBoardSnapshot {
        if includeArchived {
            return snapshot
        }

        return ProjectBoardSnapshot(projects: snapshot.projects.filter { !$0.isArchived })
    }

    @discardableResult
    func createProject(title: String) throws -> ProjectBoardProject {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else {
            throw ProjectBoardStoreError.emptyProjectTitle
        }

        let nextID = snapshot.projects.map(\.id).max().map { $0 + 1 } ?? 1
        let project = ProjectBoardProject(
            id: nextID,
            title: normalizedTitle,
            status: "active",
            subtitle: "0 open / 0 total",
            columns: ProjectTaskStatus.allCases.map { ProjectBoardColumn(status: $0, tasks: []) }
        )
        snapshot.projects.insert(project, at: 0)
        return project
    }

    @discardableResult
    func updateProject(id: Int64, title: String) throws -> ProjectBoardProject {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else {
            throw ProjectBoardStoreError.emptyProjectTitle
        }
        guard let projectIndex = snapshot.projects.firstIndex(where: { $0.id == id }) else {
            throw DatabaseError.stepFailed("Project \(id) was not found.")
        }

        snapshot.projects[projectIndex].title = normalizedTitle
        return snapshot.projects[projectIndex]
    }

    @discardableResult
    func completeProject(id: Int64) throws -> ProjectBoardProject {
        guard let projectIndex = snapshot.projects.firstIndex(where: { $0.id == id }) else {
            throw DatabaseError.stepFailed("Project \(id) was not found.")
        }

        snapshot.projects[projectIndex].status = "completed"
        var completedTasks = snapshot.projects[projectIndex].tasks.map { task in
            ProjectBoardTask(
                id: task.id,
                projectID: task.projectID,
                title: task.title,
                detail: task.detail,
                status: .done,
                priority: task.priority,
                dueAt: task.dueAt
            )
        }
        completedTasks.sort { $0.id > $1.id }
        for columnIndex in snapshot.projects[projectIndex].columns.indices {
            snapshot.projects[projectIndex].columns[columnIndex].tasks.removeAll()
        }
        if let doneIndex = snapshot.projects[projectIndex].columns.firstIndex(where: { $0.status == .done }) {
            snapshot.projects[projectIndex].columns[doneIndex].tasks = completedTasks
        }
        refreshProjectSubtitle(at: projectIndex)
        return snapshot.projects[projectIndex]
    }

    @discardableResult
    func archiveProject(id: Int64) throws -> ProjectBoardProject {
        guard let projectIndex = snapshot.projects.firstIndex(where: { $0.id == id }) else {
            throw DatabaseError.stepFailed("Project \(id) was not found.")
        }

        snapshot.projects[projectIndex].status = "archived"
        let archivedProject = snapshot.projects[projectIndex]
        if snapshot.projects.allSatisfy(\.isArchived) {
            _ = try createProject(title: "Inbox")
        }
        return archivedProject
    }

    @discardableResult
    func restoreProject(id: Int64) throws -> ProjectBoardProject {
        guard let projectIndex = snapshot.projects.firstIndex(where: { $0.id == id }) else {
            throw DatabaseError.stepFailed("Project \(id) was not found.")
        }

        snapshot.projects[projectIndex].status = "active"
        return snapshot.projects[projectIndex]
    }

    func deleteProject(id: Int64) throws {
        guard snapshot.projects.contains(where: { $0.id == id }) else {
            throw DatabaseError.stepFailed("Project \(id) was not found.")
        }

        snapshot.projects.removeAll { $0.id == id }
        if snapshot.projects.isEmpty || snapshot.projects.allSatisfy(\.isArchived) {
            _ = try createProject(title: "Inbox")
        }
    }

    @discardableResult
    func createTask(_ draft: ProjectBoardTaskDraft) throws -> ProjectBoardTask {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            throw ProjectBoardStoreError.emptyTitle
        }
        try prepareProjectForTaskMutation(projectID: draft.projectID, taskStatus: draft.status)

        let task = ProjectBoardTask(
            id: nextTaskID,
            projectID: draft.projectID,
            title: title,
            detail: draft.detail.trimmingCharacters(in: .whitespacesAndNewlines),
            status: draft.status,
            priority: draft.priority,
            dueAt: draft.dueAt
        )
        nextTaskID += 1
        upsert(task)
        return task
    }

    @discardableResult
    func updateTask(id: Int64, _ draft: ProjectBoardTaskDraft) throws -> ProjectBoardTask {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            throw ProjectBoardStoreError.emptyTitle
        }
        try prepareProjectForTaskMutation(projectID: draft.projectID, taskStatus: draft.status)

        let task = ProjectBoardTask(
            id: id,
            projectID: draft.projectID,
            title: title,
            detail: draft.detail.trimmingCharacters(in: .whitespacesAndNewlines),
            status: draft.status,
            priority: draft.priority,
            dueAt: draft.dueAt
        )
        upsert(task)
        return task
    }

    func moveTask(id: Int64, to status: ProjectTaskStatus) throws -> ProjectBoardTask {
        let task = try findTask(id: id)
        try prepareProjectForTaskMutation(projectID: task.projectID, taskStatus: status)
        let movedTask = ProjectBoardTask(
            id: task.id,
            projectID: task.projectID,
            title: task.title,
            detail: task.detail,
            status: status,
            priority: task.priority,
            dueAt: task.dueAt
        )
        upsert(movedTask)
        return movedTask
    }

    func moveTasks(ids: [Int64], to status: ProjectTaskStatus) throws -> [ProjectBoardTask] {
        let originalSnapshot = snapshot
        do {
            return try ids.map { try moveTask(id: $0, to: status) }
        } catch {
            snapshot = originalSnapshot
            throw error
        }
    }

    func deleteTask(id: Int64) throws {
        for projectIndex in snapshot.projects.indices {
            for columnIndex in snapshot.projects[projectIndex].columns.indices {
                snapshot.projects[projectIndex].columns[columnIndex].tasks.removeAll { $0.id == id }
            }
            refreshProjectSubtitle(at: projectIndex)
        }
    }

    private func upsert(_ task: ProjectBoardTask) {
        guard let projectIndex = snapshot.projects.firstIndex(where: { $0.id == task.projectID }) else {
            return
        }

        for existingProjectIndex in snapshot.projects.indices {
            for columnIndex in snapshot.projects[existingProjectIndex].columns.indices {
                snapshot.projects[existingProjectIndex].columns[columnIndex].tasks.removeAll { $0.id == task.id }
            }
            refreshProjectSubtitle(at: existingProjectIndex)
        }

        guard let columnIndex = snapshot.projects[projectIndex].columns.firstIndex(where: { $0.status == task.status }) else {
            return
        }

        snapshot.projects[projectIndex].columns[columnIndex].tasks.insert(task, at: 0)
        refreshProjectSubtitle(at: projectIndex)
    }

    private func findTask(id: Int64) throws -> ProjectBoardTask {
        for project in snapshot.projects {
            if let task = project.tasks.first(where: { $0.id == id }) {
                return task
            }
        }

        throw DatabaseError.stepFailed("Task \(id) was not found.")
    }

    private func prepareProjectForTaskMutation(projectID: Int64, taskStatus: ProjectTaskStatus) throws {
        guard let projectIndex = snapshot.projects.firstIndex(where: { $0.id == projectID }) else {
            throw DatabaseError.stepFailed("Project \(projectID) was not found.")
        }

        if snapshot.projects[projectIndex].isArchived {
            throw ProjectBoardStoreError.archivedProjectCannotAcceptTasks
        }

        if snapshot.projects[projectIndex].isCompleted, taskStatus != .done {
            snapshot.projects[projectIndex].status = "active"
        }
    }

    private func refreshProjectSubtitle(at projectIndex: Int) {
        let tasks = snapshot.projects[projectIndex].tasks
        let openCount = tasks.filter { $0.status != .done }.count
        snapshot.projects[projectIndex].subtitle = "\(openCount) open / \(tasks.count) total"
    }
}

final class InMemoryDailyCheckStateStore: DailyCheckStateStore, @unchecked Sendable {
    private var storedLastRunAt: Date?
    private let lock = NSLock()

    init(lastRunAt: Date? = nil) {
        self.storedLastRunAt = lastRunAt
    }

    func lastRunAt() throws -> Date? {
        lock.lock()
        defer { lock.unlock() }
        return storedLastRunAt
    }

    func recordRun(at date: Date) throws {
        lock.lock()
        defer { lock.unlock() }
        storedLastRunAt = date
    }
}

final class InMemoryLaunchAtLoginClient: LaunchAtLoginClient, @unchecked Sendable {
    private var isEnabled: Bool
    private let lock = NSLock()

    init(isEnabled: Bool = false) {
        self.isEnabled = isEnabled
    }

    func status() -> LaunchAtLoginStatus {
        lock.lock()
        defer { lock.unlock() }
        return isEnabled ? .enabled : .disabled
    }

    func setEnabled(_ enabled: Bool) throws -> LaunchAtLoginStatus {
        lock.lock()
        defer { lock.unlock() }
        isEnabled = enabled
        return isEnabled ? .enabled : .disabled
    }
}

final class InMemoryNotificationClient: NotificationClient, @unchecked Sendable {
    private let authorizationStatus: ToolClientAuthorizationStatus
    private var records: [NotificationRecord]
    private var nextID: Int
    private let lock = NSLock()

    init(authorizationStatus: ToolClientAuthorizationStatus = .authorized) {
        self.authorizationStatus = authorizationStatus
        self.records = []
        self.nextID = 1
    }

    func schedule(_ draft: NotificationDraft) throws -> NotificationRecord {
        try ensureAuthorized()
        lock.lock()
        defer { lock.unlock() }

        let id = draft.identifierHint ?? "notification-\(nextID)"
        nextID += 1
        let record = NotificationRecord(id: id, title: draft.title, body: draft.body, scheduledAt: draft.scheduledAt)
        records.append(record)
        return record
    }

    func cancel(id: String) throws {
        try ensureAuthorized()
        lock.lock()
        defer { lock.unlock() }

        guard let index = records.firstIndex(where: { $0.id == id }) else {
            throw ToolClientError.notFound("Notification \(id) was not found.")
        }
        records.remove(at: index)
    }

    func listScheduled() throws -> [NotificationRecord] {
        lock.lock()
        defer { lock.unlock() }
        return records
    }

    private func ensureAuthorized() throws {
        guard authorizationStatus == .authorized else {
            throw ToolClientError.permissionDenied("Notification permission is denied.")
        }
    }
}

final class InMemoryCalendarClient: CalendarClient, @unchecked Sendable {
    private let authorizationStatus: ToolClientAuthorizationStatus
    private var records: [CalendarEventRecord]
    private var nextID: Int
    private let lock = NSLock()

    init(authorizationStatus: ToolClientAuthorizationStatus = .authorized) {
        self.authorizationStatus = authorizationStatus
        self.records = []
        self.nextID = 1
    }

    func createEvent(_ draft: CalendarEventDraft) throws -> CalendarEventRecord {
        try ensureAuthorized()
        lock.lock()
        defer { lock.unlock() }

        let record = CalendarEventRecord(id: "calendar-event-\(nextID)", draft: draft)
        nextID += 1
        records.append(record)
        return record
    }

    func listEvents() throws -> [CalendarEventRecord] {
        lock.lock()
        defer { lock.unlock() }
        return records
    }

    private func ensureAuthorized() throws {
        guard authorizationStatus == .authorized else {
            throw ToolClientError.permissionDenied("Calendar permission is denied.")
        }
    }
}

final class InMemoryReminderClient: ReminderClient, @unchecked Sendable {
    private let authorizationStatus: ToolClientAuthorizationStatus
    private var records: [ReminderRecord]
    private var nextID: Int
    private let lock = NSLock()

    init(authorizationStatus: ToolClientAuthorizationStatus = .authorized) {
        self.authorizationStatus = authorizationStatus
        self.records = []
        self.nextID = 1
    }

    func create(_ draft: ReminderDraft) throws -> ReminderRecord {
        try ensureAuthorized()
        lock.lock()
        defer { lock.unlock() }

        let record = ReminderRecord(
            id: "reminder-\(nextID)",
            title: draft.title,
            dueAt: draft.dueAt,
            listName: draft.listName,
            isCompleted: false
        )
        nextID += 1
        records.append(record)
        return record
    }

    func markComplete(id: String) throws -> ReminderRecord {
        try ensureAuthorized()
        lock.lock()
        defer { lock.unlock() }

        guard let index = records.firstIndex(where: { $0.id == id }) else {
            throw ToolClientError.notFound("Reminder \(id) was not found.")
        }
        records[index].isCompleted = true
        return records[index]
    }

    func list() throws -> [ReminderRecord] {
        lock.lock()
        defer { lock.unlock() }
        return records
    }

    private func ensureAuthorized() throws {
        guard authorizationStatus == .authorized else {
            throw ToolClientError.permissionDenied("Reminder permission is denied.")
        }
    }
}

final class InMemoryMailDraftClient: MailDraftClient, @unchecked Sendable {
    private var records: [MailDraftRecord]
    private var nextID: Int
    private let lock = NSLock()

    init() {
        self.records = []
        self.nextID = 1
    }

    func createTextDraft(to: String?, subject: String, body: String) throws -> MailDraftRecord {
        lock.lock()
        defer { lock.unlock() }

        let record = MailDraftRecord(id: "mail-draft-\(nextID)", to: to, subject: subject, body: body)
        nextID += 1
        records.append(record)
        return record
    }

    func listDrafts() throws -> [MailDraftRecord] {
        lock.lock()
        defer { lock.unlock() }
        return records
    }
}
