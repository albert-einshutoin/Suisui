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
            timeZoneIdentifier: "Asia/Tokyo",
            idempotencyNamespace: "test-installation"
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
        XCTAssertEqual(calendarSink.createdDrafts.first?.startAt, "2026-07-04")
        XCTAssertEqual(calendarSink.createdDrafts.first?.endAt, "2026-07-05")
        XCTAssertEqual(calendarSink.createdDrafts.first?.idempotencyKey?.hasPrefix("solopm"), true)
        XCTAssertEqual(calendarSink.createdDrafts.first?.idempotencyKey?.count, 70)
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

    func testSettingsBackedGoogleCalendarSyncReloadsCalendarIDBeforeStatusAndWrites() throws {
        let settingsStore = MutableAppSettingsStore(settings: AppSettings(timeZoneIdentifier: "Asia/Tokyo", googleCalendarID: "primary"))
        let projectStore = InMemoryProjectBoardStore(snapshot: ProjectBoardSnapshot(projects: [
            makeProject(
                id: 10,
                title: "Launch",
                tasks: [
                    ProjectBoardTask(
                        id: 100,
                        projectID: 10,
                        title: "Send launch brief",
                        detail: "",
                        status: .planned,
                        priority: .medium,
                        dueAt: "2026-07-07"
                    )
                ]
            )
        ]))
        let linkStore = InMemoryExternalTaskLinkStore()
        let calendarSink = RecordingExternalCalendarEventSink()
        let credentialStore = MutableGoogleCalendarRuntimeCredentialStatusStore(status: GoogleCalendarRuntimeCredentialStatus(
            grantedScopes: [GoogleCalendarRuntimeCredentialStatus.eventsWriteScope],
            expiresAt: Date(timeIntervalSince1970: 1_800_001_000),
            hasRefreshToken: true
        ))
        let sync = SettingsBackedGoogleCalendarRuntimeSync(
            settingsStore: settingsStore,
            statusFactory: { settings, now in
                try GoogleCalendarRuntimeSyncReadiness.status(
                    entitlementStore: StaticEntitlementStore(plan: .pro),
                    credentialStatusStore: credentialStore,
                    configuration: GoogleCalendarRuntimeSyncConfiguration(
                        calendarID: settings.googleCalendarID,
                        timeZoneIdentifier: settings.timeZoneIdentifier
                    ),
                    isWriteRuntimeConfigured: true,
                    now: now
                )
            },
            syncFactory: { settings in
                let service = GoogleCalendarTaskSyncService(
                    entitlementStore: StaticEntitlementStore(plan: .pro),
                    store: projectStore,
                    linkStore: linkStore,
                    calendarSink: calendarSink,
                    calendarID: settings.googleCalendarID,
                    timeZoneIdentifier: settings.timeZoneIdentifier
                )
                return GoogleCalendarRuntimeSyncController(
                    entitlementStore: StaticEntitlementStore(plan: .pro),
                    credentialStatusStore: credentialStore,
                    configuration: GoogleCalendarRuntimeSyncConfiguration(
                        calendarID: settings.googleCalendarID,
                        timeZoneIdentifier: settings.timeZoneIdentifier
                    ),
                    taskSyncService: service
                )
            }
        )

        XCTAssertEqual(try sync.status(now: Date(timeIntervalSince1970: 1_800_000_000)).state, GoogleCalendarRuntimeSyncState.ready)

        try settingsStore.save(AppSettings(timeZoneIdentifier: "Asia/Tokyo", googleCalendarID: "team-calendar@example.com"))
        let result = try sync.syncDueTasks(context: approvedContext())

        XCTAssertEqual(result.createdEventCount, 1)
        XCTAssertEqual(calendarSink.createdRecords.map(\.calendarID), ["team-calendar@example.com"])

        try settingsStore.save(AppSettings(timeZoneIdentifier: "Asia/Tokyo", googleCalendarID: " \n "))
        XCTAssertEqual(try sync.status(now: Date(timeIntervalSince1970: 1_800_000_000)).state, GoogleCalendarRuntimeSyncState.invalidCalendarID)
        XCTAssertThrowsError(try sync.syncDueTasks(context: approvedContext())) { error in
            XCTAssertEqual(error as? GoogleCalendarRuntimeSyncError, .notReady(.invalidCalendarID))
        }
        XCTAssertEqual(calendarSink.createdRecords.map(\.calendarID), ["team-calendar@example.com"])
    }

    func testGoogleCalendarSettingsReadinessRowKeepsOAuthActionsSeparateFromAPIKeys() {
        let notChecked = GoogleCalendarSettingsReadinessRow(status: nil)
        XCTAssertEqual(notChecked.statusLabel, "Not checked")
        XCTAssertEqual(notChecked.detailLabel, "Check local OAuth, plan, and calendar readiness before syncing.")
        XCTAssertEqual(notChecked.nextActionLabel, "Check Status")
        XCTAssertFalse(notChecked.isReady)

        let upgradeRequired = GoogleCalendarSettingsReadinessRow(
            status: GoogleCalendarRuntimeSyncStatus(plan: .free, state: .upgradeRequired(requiredPlan: .pro))
        )
        XCTAssertEqual(upgradeRequired.statusLabel, "Upgrade required")
        XCTAssertEqual(upgradeRequired.nextActionLabel, "Upgrade to Pro before OAuth authorization")

        let disconnected = GoogleCalendarSettingsReadinessRow(
            status: GoogleCalendarRuntimeSyncStatus(plan: .pro, state: .oauthDisconnected)
        )
        XCTAssertEqual(disconnected.statusLabel, "OAuth required")
        XCTAssertEqual(disconnected.detailLabel, "Connect Google Calendar with OAuth before syncing due tasks.")
        XCTAssertEqual(disconnected.nextActionLabel, "Connect with OAuth authorization")
        XCTAssertEqual(disconnected.statusCheckActionLabel, "Check Status")
        XCTAssertEqual(disconnected.privacyBoundaryLabel, "Tokens stay in Keychain; Settings uses OAuth only.")
        XCTAssertFalse(disconnected.isReady)

        let ready = GoogleCalendarSettingsReadinessRow(
            status: GoogleCalendarRuntimeSyncStatus(plan: .pro, state: .ready)
        )
        XCTAssertEqual(ready.statusLabel, "Ready")
        XCTAssertEqual(ready.nextActionLabel, "Sync due tasks from Project Board")
        XCTAssertTrue(ready.isReady)

        let renderedLabels = [
            notChecked.statusLabel,
            notChecked.detailLabel,
            notChecked.nextActionLabel,
            upgradeRequired.statusLabel,
            upgradeRequired.detailLabel,
            upgradeRequired.nextActionLabel,
            disconnected.statusLabel,
            disconnected.detailLabel,
            disconnected.nextActionLabel,
            disconnected.statusCheckActionLabel,
            disconnected.privacyBoundaryLabel,
            ready.statusLabel,
            ready.detailLabel,
            ready.nextActionLabel
        ].joined(separator: "\n")
        XCTAssertFalse(renderedLabels.localizedCaseInsensitiveContains("api key"))
        XCTAssertFalse(renderedLabels.contains("calendar-access-token"))
        XCTAssertFalse(renderedLabels.contains("calendar-refresh-token"))
        XCTAssertFalse(renderedLabels.localizedCaseInsensitiveContains("bearer "))
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
            timeZoneIdentifier: "Asia/Tokyo",
            idempotencyNamespace: "test-installation"
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

    func testGoogleCalendarTaskSyncKeepsTimedEventsAndUsesStableIdempotencyKey() throws {
        let store = InMemoryProjectBoardStore(snapshot: ProjectBoardSnapshot(projects: [
            makeProject(
                id: 7,
                title: "Launch",
                tasks: [
                    ProjectBoardTask(
                        id: 12,
                        projectID: 7,
                        title: "Timed task",
                        detail: "",
                        status: .planned,
                        priority: .high,
                        dueAt: "2026-07-04T09:00:00+09:00"
                    )
                ]
            )
        ]))
        let calendarSink = RecordingExternalCalendarEventSink()
        let service = GoogleCalendarTaskSyncService(
            entitlementStore: StaticEntitlementStore(plan: .pro),
            store: store,
            linkStore: InMemoryExternalTaskLinkStore(),
            calendarSink: calendarSink,
            calendarID: "primary",
            timeZoneIdentifier: "Asia/Tokyo",
            idempotencyNamespace: "timed-installation"
        )

        _ = try service.syncDueTasks(context: approvedContext())

        let draft = try XCTUnwrap(calendarSink.createdDrafts.first)
        XCTAssertFalse(draft.isAllDay)
        XCTAssertEqual(draft.startAt, "2026-07-04T09:00:00+09:00")
        XCTAssertEqual(draft.endAt, "2026-07-04T09:00:00+09:00")
        XCTAssertEqual(draft.idempotencyKey?.hasPrefix("solopm"), true)
        XCTAssertEqual(draft.idempotencyKey?.count, 70)
    }

    func testGoogleCalendarTaskSyncRequiresNamespaceBeforeSendingStableIdempotencyKey() throws {
        let store = InMemoryProjectBoardStore(snapshot: ProjectBoardSnapshot(projects: [
            makeProject(
                id: 7,
                title: "Launch",
                tasks: [
                    ProjectBoardTask(id: 12, projectID: 7, title: "Due task", detail: "", status: .planned, priority: .high, dueAt: "2026-07-04")
                ]
            )
        ]))
        let calendarSink = RecordingExternalCalendarEventSink()
        let service = GoogleCalendarTaskSyncService(
            entitlementStore: StaticEntitlementStore(plan: .pro),
            store: store,
            linkStore: InMemoryExternalTaskLinkStore(),
            calendarSink: calendarSink,
            calendarID: "primary",
            timeZoneIdentifier: "Asia/Tokyo"
        )

        _ = try service.syncDueTasks(context: approvedContext())

        XCTAssertNil(calendarSink.createdDrafts.first?.idempotencyKey)
    }

    func testGoogleCalendarTaskSyncNamespacesStableIdempotencyKeys() throws {
        let project = makeProject(
            id: 7,
            title: "Launch",
            tasks: [
                ProjectBoardTask(id: 12, projectID: 7, title: "Due task", detail: "", status: .planned, priority: .high, dueAt: "2026-07-04")
            ]
        )
        let firstSink = RecordingExternalCalendarEventSink()
        let secondSink = RecordingExternalCalendarEventSink()

        _ = try GoogleCalendarTaskSyncService(
            entitlementStore: StaticEntitlementStore(plan: .pro),
            store: InMemoryProjectBoardStore(snapshot: ProjectBoardSnapshot(projects: [project])),
            linkStore: InMemoryExternalTaskLinkStore(),
            calendarSink: firstSink,
            calendarID: "primary",
            timeZoneIdentifier: "Asia/Tokyo",
            idempotencyNamespace: "installation-a"
        ).syncDueTasks(context: approvedContext())

        _ = try GoogleCalendarTaskSyncService(
            entitlementStore: StaticEntitlementStore(plan: .pro),
            store: InMemoryProjectBoardStore(snapshot: ProjectBoardSnapshot(projects: [project])),
            linkStore: InMemoryExternalTaskLinkStore(),
            calendarSink: secondSink,
            calendarID: "primary",
            timeZoneIdentifier: "Asia/Tokyo",
            idempotencyNamespace: "installation-b"
        ).syncDueTasks(context: approvedContext())

        let firstKey = try XCTUnwrap(firstSink.createdDrafts.first?.idempotencyKey)
        let secondKey = try XCTUnwrap(secondSink.createdDrafts.first?.idempotencyKey)

        XCTAssertNotEqual(firstKey, secondKey)
        XCTAssertFalse(firstKey.contains("installation-a"))
        XCTAssertFalse(firstKey.contains("Due task"))
    }

    func testGoogleCalendarTaskSyncRejectsInvalidDateOnlyDueAtBeforeExternalWrite() throws {
        let store = InMemoryProjectBoardStore(snapshot: ProjectBoardSnapshot(projects: [
            makeProject(
                id: 7,
                title: "Launch",
                tasks: [
                    ProjectBoardTask(id: 12, projectID: 7, title: "Invalid date", detail: "", status: .planned, priority: .high, dueAt: "2026-02-31")
                ]
            )
        ]))
        let calendarSink = RecordingExternalCalendarEventSink()
        let service = GoogleCalendarTaskSyncService(
            entitlementStore: StaticEntitlementStore(plan: .pro),
            store: store,
            linkStore: InMemoryExternalTaskLinkStore(),
            calendarSink: calendarSink,
            calendarID: "primary",
            timeZoneIdentifier: "Asia/Tokyo",
            idempotencyNamespace: "test-installation"
        )

        XCTAssertThrowsError(try service.syncDueTasks(context: approvedContext())) { error in
            XCTAssertEqual(error as? GoogleCalendarRuntimeSyncError, .invalidDueDate("2026-02-31"))
        }
        XCTAssertEqual(calendarSink.createdDrafts.count, 0)
    }

    func testGoogleCalendarTaskSyncUsesExclusiveAllDayEndAcrossCalendarBoundaries() throws {
        let store = InMemoryProjectBoardStore(snapshot: ProjectBoardSnapshot(projects: [
            makeProject(
                id: 7,
                title: "Launch",
                tasks: [
                    ProjectBoardTask(id: 12, projectID: 7, title: "Year end", detail: "", status: .planned, priority: .high, dueAt: "2026-12-31"),
                    ProjectBoardTask(id: 13, projectID: 7, title: "Leap day", detail: "", status: .planned, priority: .high, dueAt: "2028-02-29")
                ]
            )
        ]))
        let calendarSink = RecordingExternalCalendarEventSink()
        let service = GoogleCalendarTaskSyncService(
            entitlementStore: StaticEntitlementStore(plan: .pro),
            store: store,
            linkStore: InMemoryExternalTaskLinkStore(),
            calendarSink: calendarSink,
            calendarID: "primary",
            timeZoneIdentifier: "Asia/Tokyo",
            idempotencyNamespace: "test-installation"
        )

        _ = try service.syncDueTasks(context: approvedContext())

        XCTAssertEqual(calendarSink.createdDrafts.map(\.endAt), ["2027-01-01", "2028-03-01"])
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

private final class MutableAppSettingsStore: AppSettingsStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storedSettings: AppSettings

    init(settings: AppSettings) {
        self.storedSettings = settings
    }

    func load() throws -> AppSettings {
        lock.withLock { storedSettings }
    }

    func save(_ settings: AppSettings) throws {
        lock.withLock { storedSettings = settings }
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
    private var records: [ExternalCalendarEventRecord] = []

    var createdDrafts: [CalendarEventDraft] {
        lock.withLock { drafts }
    }

    var createdRecords: [ExternalCalendarEventRecord] {
        lock.withLock { records }
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
            let record = ExternalCalendarEventRecord(
                providerID: ExternalTaskSource.googleCalendar.rawValue,
                externalID: "calendar-event-\(nextID)",
                calendarID: calendarID,
                timeZoneIdentifier: timeZoneIdentifier,
                title: draft.title
            )
            records.append(record)
            return record
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
