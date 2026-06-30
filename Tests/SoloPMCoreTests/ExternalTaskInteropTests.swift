import XCTest
@testable import SoloPMCore

final class ExternalTaskInteropTests: XCTestCase {
    func testPortableTaskExportRoundTripsProjectsAndTasksAsJSON() throws {
        let store = InMemoryProjectBoardStore(snapshot: ProjectBoardSnapshot(projects: [
            makeProject(
                id: 10,
                title: "Launch",
                tasks: [
                    ProjectBoardTask(
                        id: 100,
                        projectID: 10,
                        title: "Write launch notes",
                        detail: "Include import/export scope.",
                        status: .inProgress,
                        priority: .high,
                        dueAt: "2026-07-01"
                    )
                ]
            )
        ]))
        let service = TaskInteropExportService(store: store)

        let document = try service.exportDocument(exportedAt: Date(timeIntervalSince1970: 1_800_000_000))
        let json = try service.exportJSON(exportedAt: Date(timeIntervalSince1970: 1_800_000_000))
        let decoded = try TaskInteropDocument.decode(json)

        XCTAssertEqual(document.schemaVersion, 1)
        XCTAssertEqual(document.projects.map(\.title), ["Launch"])
        XCTAssertEqual(document.tasks.map(\.title), ["Write launch notes"])
        XCTAssertEqual(document.tasks.first?.status, .inProgress)
        XCTAssertEqual(document.tasks.first?.priority, .high)
        XCTAssertEqual(decoded, document)
    }

    func testTaskImportCreatesProjectsTasksAndExternalLinksIdempotently() throws {
        let store = InMemoryProjectBoardStore()
        let linkStore = InMemoryExternalTaskLinkStore()
        let service = ExternalTaskImportService(store: store, linkStore: linkStore)
        let item = ExternalTaskImportItem(
            source: .todoist,
            externalID: "todoist-task-1",
            projectTitle: "Imported",
            title: "Imported task",
            detail: "From Todoist",
            status: .planned,
            priority: .high,
            dueAt: "2026-07-03"
        )

        let firstResult = try service.importItems([item])
        let secondResult = try service.importItems([item])
        let snapshot = try store.loadSnapshot(includeArchived: true)

        XCTAssertEqual(firstResult.createdProjectCount, 1)
        XCTAssertEqual(firstResult.createdTaskCount, 1)
        XCTAssertEqual(firstResult.skippedDuplicateCount, 0)
        XCTAssertEqual(secondResult.createdProjectCount, 0)
        XCTAssertEqual(secondResult.createdTaskCount, 0)
        XCTAssertEqual(secondResult.skippedDuplicateCount, 1)
        XCTAssertEqual(snapshot.projects.first { $0.title == "Imported" }?.tasks.map(\.title), ["Imported task"])
        XCTAssertEqual(try linkStore.link(providerID: ExternalTaskSource.todoist.rawValue, externalID: "todoist-task-1")?.title, "Imported task")
    }

    func testPortableTaskDocumentImportCreatesEmptyProjectsAndSkipsRepeatedTasks() throws {
        let store = InMemoryProjectBoardStore()
        let linkStore = InMemoryExternalTaskLinkStore()
        let service = TaskInteropDocumentImportService(store: store, linkStore: linkStore)
        let document = TaskInteropDocument(
            exportedAt: Date(timeIntervalSince1970: 1_800_000_001),
            projects: [
                TaskInteropProject(localID: 12, title: "Imported Empty Project", status: "active")
            ],
            tasks: [
                TaskInteropTask(
                    localID: 22,
                    localProjectID: 12,
                    projectTitle: "Imported Empty Project",
                    title: "Round-trip task",
                    detail: "From exported JSON",
                    status: .planned,
                    priority: .high,
                    dueAt: "2026-07-08"
                )
            ]
        )

        let firstResult = try service.importDocument(document)
        let secondResult = try service.importDocument(document)
        let importedProject = try XCTUnwrap(try store.loadSnapshot(includeArchived: true).projects.first { $0.title == "Imported Empty Project" })

        XCTAssertEqual(firstResult.createdProjectCount, 1)
        XCTAssertEqual(firstResult.createdTaskCount, 1)
        XCTAssertEqual(firstResult.skippedDuplicateCount, 0)
        XCTAssertEqual(secondResult.createdProjectCount, 0)
        XCTAssertEqual(secondResult.createdTaskCount, 0)
        XCTAssertEqual(secondResult.skippedDuplicateCount, 1)
        XCTAssertEqual(importedProject.tasks.map(\.title), ["Round-trip task"])
    }

    @MainActor
    func testProjectBoardViewModelExportsAndImportsPortableTaskJSONForAppFileActions() throws {
        var changeCount = 0
        let sourceStore = InMemoryProjectBoardStore(snapshot: ProjectBoardSnapshot(projects: [
            makeProject(
                id: 10,
                title: "Exported Project",
                tasks: [
                    ProjectBoardTask(
                        id: 100,
                        projectID: 10,
                        title: "Task from file",
                        detail: "Portable JSON",
                        status: .planned,
                        priority: .high,
                        dueAt: "2026-07-09"
                    )
                ]
            )
        ]))
        let sourceViewModel = ProjectBoardViewModel(store: sourceStore)
        sourceViewModel.load()
        let exportedJSON = try XCTUnwrap(sourceViewModel.exportTaskInteropJSON(exportedAt: Date(timeIntervalSince1970: 1_800_000_002)))

        let targetStore = InMemoryProjectBoardStore()
        let targetViewModel = ProjectBoardViewModel(
            store: targetStore,
            externalTaskLinkStore: InMemoryExternalTaskLinkStore(),
            onChange: { changeCount += 1 }
        )

        let result = try XCTUnwrap(targetViewModel.importTaskInteropJSON(exportedJSON))

        XCTAssertEqual(result.createdTaskCount, 1)
        XCTAssertEqual(changeCount, 1)
        XCTAssertEqual(targetViewModel.snapshot.projects.first { $0.title == "Exported Project" }?.tasks.map(\.title), ["Task from file"])
        XCTAssertEqual(targetViewModel.integrationStatusMessage, "Imported 1 task from JSON.")
    }

    func testGoogleCalendarTaskSyncRequiresProBeforeCreatingEventsAndLinksDueTasks() throws {
        let store = InMemoryProjectBoardStore(snapshot: ProjectBoardSnapshot(projects: [
            makeProject(
                id: 42,
                title: "Launch",
                tasks: [
                    ProjectBoardTask(id: 1, projectID: 42, title: "Due task", detail: "Schedule me", status: .planned, priority: .high, dueAt: "2026-07-04"),
                    ProjectBoardTask(id: 2, projectID: 42, title: "No due date", detail: "", status: .planned, priority: .medium, dueAt: nil),
                    ProjectBoardTask(id: 3, projectID: 42, title: "Done task", detail: "", status: .done, priority: .medium, dueAt: "2026-07-05")
                ]
            )
        ]))
        let linkStore = InMemoryExternalTaskLinkStore()
        let calendarSink = RecordingExternalCalendarEventSink()
        let freeService = GoogleCalendarTaskSyncService(
            entitlementStore: StaticEntitlementStore(plan: .free),
            store: store,
            linkStore: linkStore,
            calendarSink: calendarSink,
            calendarID: "primary",
            timeZoneIdentifier: "Asia/Tokyo"
        )

        XCTAssertThrowsError(try freeService.syncDueTasks(context: approvedContext())) { error in
            XCTAssertEqual(error as? SyncServiceError, .upgradeRequired(requiredPlan: .pro))
        }
        XCTAssertEqual(calendarSink.createdDrafts.count, 0)

        let syncPlanService = GoogleCalendarTaskSyncService(
            entitlementStore: StaticEntitlementStore(plan: .sync),
            store: store,
            linkStore: linkStore,
            calendarSink: calendarSink,
            calendarID: "primary",
            timeZoneIdentifier: "Asia/Tokyo"
        )

        XCTAssertThrowsError(try syncPlanService.syncDueTasks(context: approvedContext())) { error in
            XCTAssertEqual(error as? SyncServiceError, .upgradeRequired(requiredPlan: .pro))
        }
        XCTAssertEqual(calendarSink.createdDrafts.count, 0)

        let proService = GoogleCalendarTaskSyncService(
            entitlementStore: StaticEntitlementStore(plan: .pro),
            store: store,
            linkStore: linkStore,
            calendarSink: calendarSink,
            calendarID: "primary",
            timeZoneIdentifier: "Asia/Tokyo"
        )

        XCTAssertThrowsError(try proService.syncDueTasks(context: ToolExecutionContext(source: .reviewUI))) { error in
            XCTAssertEqual(error as? GoogleCalendarRuntimeSyncError, .approvalRequired)
        }
        XCTAssertEqual(calendarSink.createdDrafts.count, 0)

        let result = try proService.syncDueTasks(context: approvedContext())
        let secondResult = try proService.syncDueTasks(context: approvedContext())

        XCTAssertEqual(result.createdEventCount, 1)
        XCTAssertEqual(result.skippedAlreadyLinkedCount, 0)
        XCTAssertEqual(secondResult.createdEventCount, 0)
        XCTAssertEqual(secondResult.skippedAlreadyLinkedCount, 1)
        XCTAssertEqual(calendarSink.createdDrafts.map(\.title), ["Due task"])
        XCTAssertEqual(calendarSink.createdDrafts.first?.isAllDay, true)
        XCTAssertEqual(try linkStore.link(providerID: ExternalTaskSource.googleCalendar.rawValue, taskID: 1)?.externalID, "calendar-event-1")
    }

    func testGoogleCalendarRuntimeReadinessSurfacesPlanOAuthScopeTokenAndCalendarStates() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let credentialStore = MutableGoogleCalendarRuntimeCredentialStatusStore()
        let controller = makeGoogleCalendarRuntimeSyncController(
            plan: .free,
            credentialStore: credentialStore,
            calendarID: "primary"
        )

        XCTAssertEqual(try controller.status(now: now).state, .upgradeRequired(requiredPlan: .pro))

        let proControllerWithoutCalendar = makeGoogleCalendarRuntimeSyncController(
            plan: .pro,
            credentialStore: credentialStore,
            calendarID: nil
        )
        XCTAssertEqual(try proControllerWithoutCalendar.status(now: now).state, .calendarNotConfigured)

        let proController = makeGoogleCalendarRuntimeSyncController(
            plan: .pro,
            credentialStore: credentialStore,
            calendarID: "primary"
        )
        XCTAssertEqual(try proController.status(now: now).state, .oauthDisconnected)

        credentialStore.status = GoogleCalendarRuntimeCredentialStatus(
            grantedScopes: ["https://www.googleapis.com/auth/calendar.readonly"],
            expiresAt: now.addingTimeInterval(600),
            hasRefreshToken: true
        )
        XCTAssertEqual(
            try proController.status(now: now).state,
            .missingRequiredScope(requiredScope: GoogleCalendarRuntimeCredentialStatus.eventsWriteScope)
        )

        credentialStore.status = GoogleCalendarRuntimeCredentialStatus(
            grantedScopes: [GoogleCalendarRuntimeCredentialStatus.eventsWriteScope],
            expiresAt: now.addingTimeInterval(-1),
            hasRefreshToken: false
        )
        XCTAssertEqual(try proController.status(now: now).state, .tokenExpiredWithoutRefresh)

        credentialStore.status = GoogleCalendarRuntimeCredentialStatus(
            grantedScopes: [GoogleCalendarRuntimeCredentialStatus.eventsWriteScope],
            expiresAt: now.addingTimeInterval(-1),
            hasRefreshToken: true
        )
        let readyStatus = try proController.status(now: now)
        XCTAssertEqual(readyStatus.state, .ready)
        XCTAssertTrue(readyStatus.canSync)
    }

    @MainActor
    func testProjectBoardViewModelGoogleCalendarSyncUsesReadinessAndApprovalGate() throws {
        let store = InMemoryProjectBoardStore(snapshot: ProjectBoardSnapshot(projects: [
            makeProject(
                id: 42,
                title: "Launch",
                tasks: [
                    ProjectBoardTask(id: 1, projectID: 42, title: "Due task", detail: "Schedule me", status: .planned, priority: .high, dueAt: "2026-07-04")
                ]
            )
        ]))
        let linkStore = InMemoryExternalTaskLinkStore()
        let calendarSink = RecordingExternalCalendarEventSink()
        let credentialStore = MutableGoogleCalendarRuntimeCredentialStatusStore(status: GoogleCalendarRuntimeCredentialStatus(
            grantedScopes: [GoogleCalendarRuntimeCredentialStatus.eventsWriteScope],
            expiresAt: Date(timeIntervalSince1970: 1_800_000_600),
            hasRefreshToken: false
        ))
        let service = GoogleCalendarTaskSyncService(
            entitlementStore: StaticEntitlementStore(plan: .pro),
            store: store,
            linkStore: linkStore,
            calendarSink: calendarSink,
            calendarID: "primary",
            timeZoneIdentifier: "Asia/Tokyo"
        )
        let controller = GoogleCalendarRuntimeSyncController(
            entitlementStore: StaticEntitlementStore(plan: .pro),
            credentialStatusStore: credentialStore,
            configuration: GoogleCalendarRuntimeSyncConfiguration(calendarID: "primary", timeZoneIdentifier: "Asia/Tokyo"),
            taskSyncService: service
        )
        let viewModel = ProjectBoardViewModel(
            store: store,
            externalTaskLinkStore: linkStore,
            googleCalendarSync: controller
        )
        viewModel.load()

        XCTAssertTrue(viewModel.canSyncGoogleCalendar)
        XCTAssertEqual(viewModel.googleCalendarSyncStatus.state, .ready)

        XCTAssertNil(viewModel.syncDueTasksToGoogleCalendar(approvalToken: nil))
        XCTAssertEqual(calendarSink.createdDrafts.count, 0)
        XCTAssertEqual(viewModel.errorMessage, "Google Calendar sync requires approval before writing events.")

        let result = try XCTUnwrap(viewModel.syncDueTasksToGoogleCalendar(approvalToken: "approved"))

        XCTAssertEqual(result.createdEventCount, 1)
        XCTAssertEqual(result.skippedAlreadyLinkedCount, 0)
        XCTAssertEqual(calendarSink.createdDrafts.map(\.title), ["Due task"])
        XCTAssertEqual(viewModel.integrationStatusMessage, "Created 1 Google Calendar event.")
        XCTAssertEqual(try linkStore.link(providerID: ExternalTaskSource.googleCalendar.rawValue, taskID: 1)?.externalID, "calendar-event-1")
    }

    private func makeProject(id: Int64, title: String, tasks: [ProjectBoardTask]) -> ProjectBoardProject {
        ProjectBoardProject(
            id: id,
            title: title,
            status: "active",
            subtitle: "\(tasks.filter { $0.status != .done }.count) open / \(tasks.count) total",
            columns: ProjectTaskStatus.allCases.map { status in
                ProjectBoardColumn(status: status, tasks: tasks.filter { $0.status == status })
            }
        )
    }

    private func approvedContext() -> ToolExecutionContext {
        ToolExecutionContext(
            approvalToken: ApprovalToken(id: "approval", sessionID: "session"),
            source: .developerTool
        )
    }

    private func makeGoogleCalendarRuntimeSyncController(
        plan: SubscriptionPlan,
        credentialStore: MutableGoogleCalendarRuntimeCredentialStatusStore,
        calendarID: String?
    ) -> GoogleCalendarRuntimeSyncController {
        let store = InMemoryProjectBoardStore()
        let linkStore = InMemoryExternalTaskLinkStore()
        let service = GoogleCalendarTaskSyncService(
            entitlementStore: StaticEntitlementStore(plan: plan),
            store: store,
            linkStore: linkStore,
            calendarSink: RecordingExternalCalendarEventSink(),
            calendarID: calendarID ?? "primary",
            timeZoneIdentifier: "Asia/Tokyo"
        )
        return GoogleCalendarRuntimeSyncController(
            entitlementStore: StaticEntitlementStore(plan: plan),
            credentialStatusStore: credentialStore,
            configuration: GoogleCalendarRuntimeSyncConfiguration(calendarID: calendarID, timeZoneIdentifier: "Asia/Tokyo"),
            taskSyncService: service
        )
    }
}

private struct StaticEntitlementStore: EntitlementStore {
    var plan: SubscriptionPlan

    func snapshot() throws -> EntitlementSnapshot {
        EntitlementSnapshot(plan: plan, source: .localLicense)
    }
}

private final class MutableGoogleCalendarRuntimeCredentialStatusStore: GoogleCalendarRuntimeCredentialStatusStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storedStatus: GoogleCalendarRuntimeCredentialStatus?

    var status: GoogleCalendarRuntimeCredentialStatus? {
        get {
            lock.withLock { storedStatus }
        }
        set {
            lock.withLock { storedStatus = newValue }
        }
    }

    init(status: GoogleCalendarRuntimeCredentialStatus? = nil) {
        self.storedStatus = status
    }

    func loadGoogleCalendarCredentialStatus() throws -> GoogleCalendarRuntimeCredentialStatus? {
        lock.withLock { storedStatus }
    }
}

private final class InMemoryExternalTaskLinkStore: ExternalTaskLinkStore, @unchecked Sendable {
    private let lock = NSLock()
    private var records: [ExternalTaskLinkRecord] = []
    private var nextID: Int64 = 1

    func link(providerID: String, externalID: String, taskID: Int64, projectID: Int64?, title: String?) throws -> ExternalTaskLinkRecord {
        lock.withLock {
            if let existingIndex = records.firstIndex(where: { $0.providerID == providerID && $0.externalID == externalID }) {
                records[existingIndex].taskID = taskID
                records[existingIndex].projectID = projectID
                records[existingIndex].title = title
                return records[existingIndex]
            }

            let record = ExternalTaskLinkRecord(
                id: nextID,
                providerID: providerID,
                externalID: externalID,
                projectID: projectID,
                taskID: taskID,
                title: title
            )
            nextID += 1
            records.append(record)
            return record
        }
    }

    func link(providerID: String, externalID: String) throws -> ExternalTaskLinkRecord? {
        lock.withLock {
            records.first { $0.providerID == providerID && $0.externalID == externalID }
        }
    }

    func link(providerID: String, taskID: Int64) throws -> ExternalTaskLinkRecord? {
        lock.withLock {
            records.first { $0.providerID == providerID && $0.taskID == taskID }
        }
    }

    func list() throws -> [ExternalTaskLinkRecord] {
        lock.withLock { records }
    }
}

private final class RecordingExternalCalendarEventSink: ExternalCalendarEventSink, @unchecked Sendable {
    private let lock = NSLock()
    private var nextID = 1
    private var drafts: [CalendarEventDraft] = []

    var createdDrafts: [CalendarEventDraft] {
        lock.withLock { drafts }
    }

    func createEvent(
        _ draft: CalendarEventDraft,
        calendarID: String,
        timeZoneIdentifier: String,
        context: ToolExecutionContext
    ) throws -> ExternalCalendarEventRecord {
        lock.withLock {
            drafts.append(draft)
            defer { nextID += 1 }
            return ExternalCalendarEventRecord(
                providerID: ExternalTaskSource.googleCalendar.rawValue,
                externalID: "calendar-event-\(nextID)",
                calendarID: calendarID,
                timeZoneIdentifier: timeZoneIdentifier,
                title: draft.title
            )
        }
    }
}

private extension NSLock {
    func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}
