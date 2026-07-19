import XCTest
@testable import SoloPMCore

/// Covers the onboarding "Learn Suisui" sample project creator against a temp
/// SQLite fixture: field mapping, idempotence, and the board-change signal.
final class FirstRunOnboardingSampleTests: XCTestCase {
    private struct FixedDateProvider: DateProvider {
        let now: Date
    }

    private final class NotificationCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var storage = 0

        var value: Int {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }

        func increment() {
            // NotificationCenter's observer is @Sendable and may change its
            // delivery queue later, so the test must not capture mutable state.
            lock.lock()
            defer { lock.unlock() }
            storage += 1
        }
    }

    // 2026-07-12T03:00:00Z == 12:00 JST, safely inside one Tokyo calendar day.
    private static let fixedNow = Date(timeIntervalSince1970: 1_783_825_200)
    private static let timeZoneIdentifier = "Asia/Tokyo"

    func testCreatesLearnSoloPMProjectWithSixTeachingTasks() throws {
        let connection = try migratedConnection()
        let projectStore = SQLiteProjectStore(connection: connection)
        let taskStore = SQLiteTaskStore(connection: connection)
        let defaults = try makeIsolatedDefaults()
        let creator = makeCreator(
            projectStore: projectStore,
            taskStore: taskStore,
            defaults: defaults,
            localize: { "JA:\($0)" }
        )

        let result = try XCTUnwrap(creator.createSampleProjectIfNeeded())

        // Localization runs at creation time through the injected closure.
        XCTAssertEqual(result.project.title, "JA:\(OnboardingSampleProjectDefinition.projectTitle)")
        XCTAssertEqual(result.project.sourceCommand, OnboardingSampleProjectDefinition.projectMarkerSourceCommand)
        XCTAssertEqual(result.tasks.count, 6)
        XCTAssertEqual(OnboardingSampleProjectDefinition.tasks.count, 6)

        for (task, definition) in zip(result.tasks, OnboardingSampleProjectDefinition.tasks) {
            XCTAssertEqual(task.projectID, result.project.id)
            XCTAssertEqual(task.title, "JA:\(definition.title)")
            XCTAssertEqual(task.detail, "JA:\(definition.detail)")
            XCTAssertEqual(task.priority, definition.priority?.rawValue)
            XCTAssertEqual(task.recurrence, definition.recurrence)
            XCTAssertEqual(task.status, "open")
            XCTAssertEqual(task.sourceCommand, OnboardingSampleProjectDefinition.projectMarkerSourceCommand)
        }

        // Mixed priorities, one weekly recurrence, one due today 18:00, one
        // due tomorrow — the concrete product contract from T-09.
        XCTAssertEqual(
            result.tasks.map(\.priority),
            ["high", "medium", "low", "medium", nil, nil]
        )
        XCTAssertEqual(result.tasks.map(\.recurrence), [nil, nil, nil, nil, nil, "weekly"])
        XCTAssertEqual(result.tasks[0].dueAt, expectedDueString(daysFromToday: 0, hour: 18, minute: 0))
        XCTAssertEqual(result.tasks[4].dueAt, expectedDueString(daysFromToday: 1, hour: 9, minute: 0))
        // The weekly task carries a due date because completion-driven
        // recurrence needs one to schedule the next occurrence.
        XCTAssertEqual(result.tasks[5].dueAt, expectedDueString(daysFromToday: 0, hour: 10, minute: 0))
        XCTAssertEqual(result.tasks.filter { $0.dueAt == nil }.count, 3)

        XCTAssertTrue(defaults.bool(forKey: OnboardingSampleProjectDefinition.createdDefaultsKey))
        XCTAssertEqual(try projectStore.list().count, 1)
        XCTAssertEqual(try taskStore.listAll().count, 6)
    }

    func testSecondCallIsANoOp() throws {
        let connection = try migratedConnection()
        let projectStore = SQLiteProjectStore(connection: connection)
        let taskStore = SQLiteTaskStore(connection: connection)
        let defaults = try makeIsolatedDefaults()
        let creator = makeCreator(projectStore: projectStore, taskStore: taskStore, defaults: defaults)

        XCTAssertNotNil(try creator.createSampleProjectIfNeeded())
        XCTAssertNil(try creator.createSampleProjectIfNeeded())

        XCTAssertEqual(try projectStore.list().count, 1)
        XCTAssertEqual(try taskStore.listAll().count, 6)
    }

    func testEnsureReturnsTheSameFirstLessonWithoutDuplicatingTheProject() throws {
        let connection = try migratedConnection()
        let projectStore = SQLiteProjectStore(connection: connection)
        let taskStore = SQLiteTaskStore(connection: connection)
        let creator = makeCreator(
            projectStore: projectStore,
            taskStore: taskStore,
            defaults: try makeIsolatedDefaults()
        )

        let first = try creator.ensureSampleProject()
        let repeated = try creator.ensureSampleProject()

        guard case .created = first else {
            return XCTFail("first ensure must create the teaching project")
        }
        guard case .existing = repeated else {
            return XCTFail("second ensure must reuse the teaching project")
        }
        XCTAssertEqual(repeated.project.id, first.project.id)
        XCTAssertEqual(repeated.firstLessonTaskID, first.firstLessonTaskID)
        XCTAssertEqual(try projectStore.list().count, 1)
        XCTAssertEqual(try taskStore.listAll().count, 6)
    }

    func testTaskBatchFailureRollsBackTheTeachingProjectAndCompletionFlag() throws {
        let connection = try migratedConnection()
        try connection.execute(
            """
            CREATE TRIGGER reject_onboarding_tasks
            BEFORE INSERT ON tasks
            WHEN NEW.source_command = 'onboarding-sample'
            BEGIN
                SELECT RAISE(ABORT, 'injected onboarding failure');
            END;
            """
        )
        let projectStore = SQLiteProjectStore(connection: connection)
        let taskStore = SQLiteTaskStore(connection: connection)
        let defaults = try makeIsolatedDefaults()
        let creator = makeCreator(projectStore: projectStore, taskStore: taskStore, defaults: defaults)

        XCTAssertThrowsError(try creator.ensureSampleProject())
        XCTAssertTrue(try projectStore.list(includeArchived: true).isEmpty)
        XCTAssertTrue(try taskStore.listAll().isEmpty)
        XCTAssertFalse(defaults.bool(forKey: OnboardingSampleProjectDefinition.createdDefaultsKey))

        try connection.execute("DROP TRIGGER reject_onboarding_tasks;")
        let recovered = try creator.ensureSampleProject()
        guard case .created = recovered else {
            return XCTFail("retry after rollback must create a complete teaching project")
        }
        XCTAssertEqual(try projectStore.list().count, 1)
        XCTAssertEqual(try taskStore.listAll().count, 6)
        XCTAssertTrue(defaults.bool(forKey: OnboardingSampleProjectDefinition.createdDefaultsKey))
    }

    func testExistingIncompleteMarkedProjectIsRebuiltBeforeRecordingCompletion() throws {
        let connection = try migratedConnection()
        let projectStore = SQLiteProjectStore(connection: connection)
        let taskStore = SQLiteTaskStore(connection: connection)
        let defaults = try makeIsolatedDefaults()
        let interruptedProject = try projectStore.create(
            title: "Learn Suisui",
            sourceCommand: OnboardingSampleProjectDefinition.projectMarkerSourceCommand
        )
        _ = try taskStore.create(
            title: OnboardingSampleProjectDefinition.tasks[0].title,
            projectID: interruptedProject.id,
            sourceCommand: OnboardingSampleProjectDefinition.projectMarkerSourceCommand
        )
        let creator = makeCreator(projectStore: projectStore, taskStore: taskStore, defaults: defaults)

        let result = try XCTUnwrap(creator.createSampleProjectIfNeeded())

        XCTAssertEqual(try projectStore.list().count, 1)
        XCTAssertNotEqual(result.project.id, interruptedProject.id)
        XCTAssertEqual(result.tasks.count, OnboardingSampleProjectDefinition.tasks.count)
        XCTAssertEqual(try taskStore.listAll().count, OnboardingSampleProjectDefinition.tasks.count)
        XCTAssertTrue(
            defaults.bool(forKey: OnboardingSampleProjectDefinition.createdDefaultsKey),
            "completion is recorded only after the full sample project exists"
        )
    }

    func testCreationPostsProjectBoardDidChangeNotification() throws {
        let connection = try migratedConnection()
        let notificationCenter = NotificationCenter()
        let creator = makeCreator(
            projectStore: SQLiteProjectStore(connection: connection),
            taskStore: SQLiteTaskStore(connection: connection),
            defaults: try makeIsolatedDefaults(),
            notificationCenter: notificationCenter
        )
        let didChange = expectation(
            forNotification: .soloPMProjectBoardDidChange,
            object: nil,
            notificationCenter: notificationCenter
        )

        XCTAssertNotNil(try creator.createSampleProjectIfNeeded())

        wait(for: [didChange], timeout: 1.0)
    }

    func testNoOpCallsDoNotPostNotifications() throws {
        let connection = try migratedConnection()
        let notificationCenter = NotificationCenter()
        let defaults = try makeIsolatedDefaults()
        defaults.set(true, forKey: OnboardingSampleProjectDefinition.createdDefaultsKey)
        let creator = makeCreator(
            projectStore: SQLiteProjectStore(connection: connection),
            taskStore: SQLiteTaskStore(connection: connection),
            defaults: defaults,
            notificationCenter: notificationCenter
        )
        let postCount = NotificationCounter()
        let token = notificationCenter.addObserver(
            forName: .soloPMProjectBoardDidChange,
            object: nil,
            queue: nil
        ) { _ in
            postCount.increment()
        }
        defer { notificationCenter.removeObserver(token) }

        XCTAssertNil(try creator.createSampleProjectIfNeeded())
        XCTAssertEqual(postCount.value, 0)
    }

    // MARK: - Fixture helpers

    private func makeCreator(
        projectStore: SQLiteProjectStore,
        taskStore: SQLiteTaskStore,
        defaults: UserDefaults,
        localize: @escaping @Sendable (String) -> String = { $0 },
        notificationCenter: NotificationCenter = NotificationCenter()
    ) -> OnboardingSampleProjectCreator {
        OnboardingSampleProjectCreator(
            projectStore: projectStore,
            taskStore: taskStore,
            defaults: defaults,
            dateProvider: FixedDateProvider(now: Self.fixedNow),
            timeZoneIdentifier: Self.timeZoneIdentifier,
            localize: localize,
            notificationCenter: notificationCenter
        )
    }

    private func expectedDueString(daysFromToday: Int, hour: Int, minute: Int) -> String? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: Self.timeZoneIdentifier) ?? .current
        let startOfDay = calendar.startOfDay(for: Self.fixedNow)
        guard let day = calendar.date(byAdding: .day, value: daysFromToday, to: startOfDay),
              let due = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) else {
            return nil
        }
        return ISO8601DateFormatter().string(from: due)
    }

    private func makeIsolatedDefaults() throws -> UserDefaults {
        let suiteName = "FirstRunOnboardingSampleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }

    private func migratedConnection() throws -> SQLiteConnection {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        return connection
    }
}
