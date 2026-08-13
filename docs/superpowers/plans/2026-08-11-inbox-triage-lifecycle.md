# Inbox Triage Lifecycle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Inbox classification persist an explicit disposition, defer review until the next local 09:00, sort by capture time, and recover Quick Add when the Inbox project is missing.

**Architecture:** Add a task-linked `inbox_triage_records` table and route all Inbox mutations through `ProjectBoardStore` so SQLite can update tasks, projects, and triage state atomically. `ProjectBoardViewModel` owns selection, feedback, and one-step Undo; SwiftUI renders the derived read model and refreshes deferred visibility once per minute while Inbox is visible.

**Tech Stack:** Swift 6, Foundation `Calendar`, SwiftUI, the existing SQLite migration/store layer, XCTest, AppleScript runtime smoke scripts.

**Design:** `docs/superpowers/specs/2026-08-11-inbox-triage-lifecycle-and-voice-playback-design.md`

**Implementation status (2026-08-11):** Tasks 1–7 and final automated validation are complete. The supported-matrix visual inspection remains a manual follow-up because this implementation turn validated the visible runtime path at the wide smoke size only.

---

## File map

- Create `Sources/SuisuiCore/WorkManagement/InboxTriage.swift`: Inbox disposition, record, action, mutation snapshot, and next-review calculation.
- Modify `Sources/SuisuiCore/Database/SQLiteDatabaseClient.swift`: migration `0035_create_inbox_triage_records` and safe backfill.
- Modify `Sources/SuisuiCore/WorkManagement/WorkManagementModels.swift`: expose immutable Task `createdAt`.
- Modify `Sources/SuisuiCore/WorkManagement/WorkManagementStore.swift`: Inbox state load, atomic create/classify/undo contracts.
- Modify `Sources/SuisuiCore/WorkManagement/WorkManagementSQLiteStore.swift`: SQLite implementations and `created_at` mapping.
- Modify `Sources/SuisuiCore/App/BoardOperationUndo.swift`: preserve Inbox triage mutations in the existing Edit-menu Undo stack.
- Modify `Sources/SuisuiCore/App/ProjectBoard.swift`: cache, filters, selection, feedback, Undo, and due-review refresh.
- Modify `Sources/SuisuiApp/Views/ProjectWorkflowInboxView.swift`: Quick Add route, state badges, created-at sorting, and periodic refresh.
- Modify `Sources/SuisuiApp/Resources/{en,ja}.lproj/Localizable.strings`: new status and error strings.
- Modify `Tests/SuisuiCoreTests/Support/LocalRuntimeTestDoubles.swift`: deterministic in-memory Inbox state behavior.
- Modify `Tests/SuisuiCoreTests/ProjectBoardStoreTests.swift`: domain, SQLite, ViewModel, migration, clock, and restart behavior.
- Modify `Tests/SuisuiCoreTests/AppExperienceSourceTests.swift`: UI and accessibility contracts.
- Modify `Tests/SuisuiCoreTests/ReleasePipelineTests.swift` and `script/check_runtime_inbox_triage_smoke.sh`: visible-app mutation and SQLite postconditions.

### Task 1: Define the Inbox triage domain and review clock

**Files:**
- Create: `Sources/SuisuiCore/WorkManagement/InboxTriage.swift`
- Test: `Tests/SuisuiCoreTests/ProjectBoardStoreTests.swift`

- [x] **Step 1: Write failing tests for disposition invariants and next local 09:00**

Add tests that construct valid records, reject an invalid `reviewAt` combination, and prove DST-safe scheduling:

```swift
func testInboxReviewLaterRequiresReviewAt() {
    XCTAssertThrowsError(try InboxTriageRecord(
        taskID: 42,
        disposition: .reviewLater,
        reviewAt: nil,
        updatedAt: "2026-08-11T00:00:00Z"
    ))
}

func testInboxReviewLaterDateIsNextLocalNineAcrossDST() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
    let reference = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-03-08T08:30:00Z"))

    let result = try InboxReviewClock.nextReviewDate(after: reference, calendar: calendar)

    XCTAssertEqual(ISO8601DateFormatter().string(from: result), "2026-03-09T16:00:00Z")
}
```

- [x] **Step 2: Run the focused tests and verify the red state**

Run:

```bash
swift test --filter ProjectBoardStoreTests.testInboxReviewLater
```

Expected: compilation fails because `InboxTriageRecord` and `InboxReviewClock` do not exist.

- [x] **Step 3: Add the minimal domain types**

Create the focused file with these contracts:

```swift
import Foundation

public enum InboxTriageDisposition: String, Codable, Equatable, Sendable {
    case unprocessed
    case task
    case scheduled
    case reviewLater = "review_later"
    case project
}

public enum InboxTriageError: Error, Equatable, Sendable {
    case missingReviewDate
    case unexpectedReviewDate
    case reviewDateUnavailable
}

public struct InboxTriageRecord: Equatable, Sendable {
    public var taskID: Int64
    public var disposition: InboxTriageDisposition
    public var reviewAt: String?
    public var updatedAt: String

    public init(
        taskID: Int64,
        disposition: InboxTriageDisposition,
        reviewAt: String?,
        updatedAt: String
    ) throws {
        guard disposition == .reviewLater ? reviewAt != nil : reviewAt == nil else {
            throw disposition == .reviewLater
                ? InboxTriageError.missingReviewDate
                : InboxTriageError.unexpectedReviewDate
        }
        self.taskID = taskID
        self.disposition = disposition
        self.reviewAt = reviewAt
        self.updatedAt = updatedAt
    }
}

public enum InboxTriageAction: Equatable, Sendable {
    case makeTask
    case makeProject
    case scheduleToday
    case reviewLater
    case complete
    case reopen
}

public enum InboxReviewClock {
    public static func nextReviewDate(after referenceDate: Date, calendar: Calendar) throws -> Date {
        let start = calendar.startOfDay(for: referenceDate)
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: start),
              let review = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) else {
            throw InboxTriageError.reviewDateUnavailable
        }
        return review
    }
}
```

- [x] **Step 4: Re-run the focused tests**

Run: `swift test --filter ProjectBoardStoreTests.testInboxReviewLater`
Expected: both tests pass.

- [x] **Step 5: Commit the domain slice**

```bash
git add Sources/SuisuiCore/WorkManagement/InboxTriage.swift Tests/SuisuiCoreTests/ProjectBoardStoreTests.swift
git commit -m "feat(inbox): define triage disposition and review clock"
```

### Task 2: Add the SQLite state table and expose Task creation time

**Files:**
- Modify: `Sources/SuisuiCore/Database/SQLiteDatabaseClient.swift`
- Modify: `Sources/SuisuiCore/WorkManagement/WorkManagementModels.swift`
- Modify: `Sources/SuisuiCore/WorkManagement/WorkManagementSQLiteStore.swift`
- Test: `Tests/SuisuiCoreTests/ProjectBoardStoreTests.swift`

- [x] **Step 1: Write migration and model mapping tests**

Add tests that migrate a database containing an Inbox Task, assert the backfilled state, run migrations again, and load `createdAt`:

```swift
func testInboxTriageMigrationBackfillsWithoutHidingUndatedTasks() throws {
    let connection = try makeMigratedConnection(through: "0034_mark_conversation_origin_queue_items")
    let project = try SQLiteProjectStore(connection: connection).create(
        title: "Inbox", tags: ["local"], sourceCommand: "test"
    )
    let task = try SQLiteTaskStore(connection: connection).create(
        title: "Legacy capture", projectID: project.id, dueAt: nil,
        priority: "medium", sourceCommand: "test", status: "backlog"
    )

    try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
    try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)

    let row = try XCTUnwrap(connection.queryRows(
        "SELECT disposition, review_at FROM inbox_triage_records WHERE task_id = ?;",
        parameters: [.integer(task.id)]
    ).first)
    XCTAssertEqual(row["disposition"], "unprocessed")
    XCTAssertNil(row["review_at"])
}

func testSQLiteProjectBoardTaskExposesStableCreatedAt() throws {
    let store = try makeStore()
    let task = try store.createInboxTask(title: "Captured once")
    XCTAssertNotNil(task.createdAt)
}
```

- [x] **Step 2: Run the tests and verify failure**

Run:

```bash
swift test --filter ProjectBoardStoreTests.testInboxTriageMigration
swift test --filter ProjectBoardStoreTests.testSQLiteProjectBoardTaskExposesStableCreatedAt
```

Expected: the table does not exist and `ProjectBoardTask` has no `createdAt` property.

- [x] **Step 3: Add migration `0035_create_inbox_triage_records`**

Append a migration containing the schema and backfill from the approved design:

```sql
CREATE TABLE IF NOT EXISTS inbox_triage_records (
    task_id INTEGER PRIMARY KEY NOT NULL,
    disposition TEXT NOT NULL
        CHECK(disposition IN ('unprocessed', 'task', 'scheduled', 'review_later', 'project')),
    review_at TEXT,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK(
        (disposition = 'review_later' AND review_at IS NOT NULL)
        OR (disposition != 'review_later' AND review_at IS NULL)
    ),
    FOREIGN KEY(task_id) REFERENCES tasks(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_inbox_triage_disposition_review
ON inbox_triage_records(disposition, review_at);

INSERT OR IGNORE INTO inbox_triage_records(task_id, disposition, review_at, updated_at)
SELECT tasks.id,
       CASE
           WHEN tasks.status = 'done' THEN 'task'
           WHEN tasks.due_at IS NOT NULL THEN 'scheduled'
           ELSE 'unprocessed'
       END,
       NULL,
       COALESCE(tasks.updated_at, CURRENT_TIMESTAMP)
FROM tasks
JOIN projects ON projects.id = tasks.project_id
WHERE LOWER(projects.title) = 'inbox';
```

- [x] **Step 4: Add `createdAt` with a defaulted initializer argument**

Add `public var createdAt: String?`, accept `createdAt: String? = nil` immediately before `updatedAt`, and map `record.createdAt` in `makeBoardTask`. Preserve `createdAt` in in-memory task copies and Undo snapshots rather than stamping a new value.

```swift
public var createdAt: String?
public var updatedAt: String?
```

- [x] **Step 5: Run migration and model tests**

Run:

```bash
swift test --filter ProjectBoardStoreTests.testInboxTriageMigration
swift test --filter ProjectBoardStoreTests.testSQLiteProjectBoardTaskExposesStableCreatedAt
```

Expected: PASS with an idempotent backfill and non-empty creation timestamp.

- [x] **Step 6: Commit the persistence foundation**

```bash
git add Sources/SuisuiCore/Database/SQLiteDatabaseClient.swift Sources/SuisuiCore/WorkManagement/WorkManagementModels.swift Sources/SuisuiCore/WorkManagement/WorkManagementSQLiteStore.swift Tests/SuisuiCoreTests/ProjectBoardStoreTests.swift
git commit -m "feat(inbox): persist triage state and capture time"
```

### Task 3: Implement atomic Inbox store operations

**Files:**
- Modify: `Sources/SuisuiCore/WorkManagement/InboxTriage.swift`
- Modify: `Sources/SuisuiCore/WorkManagement/WorkManagementStore.swift`
- Modify: `Sources/SuisuiCore/WorkManagement/WorkManagementSQLiteStore.swift`
- Test: `Tests/SuisuiCoreTests/ProjectBoardStoreTests.swift`

- [x] **Step 1: Write failing atomicity and restart tests**

Add tests for Make Task, Review Later, Make Project, Schedule Today, completion, reopening, Undo, and a trigger-induced state write failure:

```swift
func testSQLiteInboxMakeTaskAndUndoAreAtomicAcrossRestart() throws {
    let store = try makeStore()
    let task = try store.createInboxTask(title: "Classify me")

    let mutation = try store.performInboxTriage(
        taskID: task.id, action: .makeTask,
        referenceDate: try isoDate("2026-08-11T01:00:00Z"),
        calendar: utcCalendar()
    )
    XCTAssertEqual(try store.loadInboxTriageRecords(taskIDs: [task.id])[task.id]?.disposition, .task)

    _ = try store.undoInboxTriage(mutation)
    let reopened = try makeStore(at: storePath)
    XCTAssertEqual(try reopened.loadInboxTriageRecords(taskIDs: [task.id])[task.id]?.disposition, .unprocessed)
}

func testSQLiteInboxTriageRollsBackTaskWhenStateWriteFails() throws {
    let store = try makeStore()
    let task = try store.createInboxTask(title: "Keep original")
    try storeConnection.execute("""
        CREATE TRIGGER fail_inbox_state BEFORE UPDATE ON inbox_triage_records
        BEGIN SELECT RAISE(ABORT, 'forced inbox state failure'); END;
        """)

    XCTAssertThrowsError(try store.performInboxTriage(
        taskID: task.id, action: .scheduleToday,
        referenceDate: try isoDate("2026-08-11T01:00:00Z"),
        calendar: utcCalendar()
    ))
    XCTAssertNil(try store.loadSnapshot().projects.flatMap(\.tasks).first { $0.id == task.id }?.dueAt)
}
```

- [x] **Step 2: Run the tests and verify failure**

Run: `swift test --filter ProjectBoardStoreTests.testSQLiteInbox`
Expected: compile failures for the new store methods.

- [x] **Step 3: Add store contracts and mutation snapshot**

Add these requirements to `ProjectBoardStore`:

```swift
func loadInboxTriageRecords(taskIDs: Set<Int64>) throws -> [Int64: InboxTriageRecord]
func createInboxTask(title: String) throws -> ProjectBoardTask
func performInboxTriage(
    taskID: Int64,
    action: InboxTriageAction,
    referenceDate: Date,
    calendar: Calendar
) throws -> InboxTriageMutation
func undoInboxTriage(_ mutation: InboxTriageMutation) throws -> ProjectBoardTask
```

Define the mutation snapshot so test doubles and Undo use the same contract:

```swift
public struct InboxTriageMutation: Equatable, Sendable {
    public var originalTask: ProjectBoardTask
    public var originalRecord: InboxTriageRecord
    public var updatedTask: ProjectBoardTask
    public var createdProjectID: Int64?

    public init(
        originalTask: ProjectBoardTask,
        originalRecord: InboxTriageRecord,
        updatedTask: ProjectBoardTask,
        createdProjectID: Int64? = nil
    ) {
        self.originalTask = originalTask
        self.originalRecord = originalRecord
        self.updatedTask = updatedTask
        self.createdProjectID = createdProjectID
    }
}

extension ProjectBoardTask {
    func inboxDraft(
        projectID: Int64? = nil,
        status: ProjectTaskStatus? = nil,
        dueAt: String?? = nil
    ) -> ProjectBoardTaskDraft {
        ProjectBoardTaskDraft(
            projectID: projectID ?? self.projectID,
            title: title,
            detail: detail,
            status: status ?? self.status,
            priority: priority,
            dueAt: dueAt ?? self.dueAt,
            recurrence: recurrence
        )
    }
}
```

The double optional lets callers distinguish “preserve due date” from “clear due date”; only this focused helper uses it.

- [x] **Step 4: Implement SQLite state decoding and upsert**

Add private helpers that query only requested task IDs, validate raw enum/date values, and write through one UPSERT:

```sql
INSERT INTO inbox_triage_records(task_id, disposition, review_at, updated_at)
VALUES (?, ?, ?, CURRENT_TIMESTAMP)
ON CONFLICT(task_id) DO UPDATE SET
    disposition = excluded.disposition,
    review_at = excluded.review_at,
    updated_at = CURRENT_TIMESTAMP;
```

An absent record derives from Task state using the migration rules and is persisted by the next mutation.

- [x] **Step 5: Implement each action inside `connection.transaction`**

Use one transaction and the existing task/project stores:

```swift
return try connection.transaction {
    let originalTask = try currentBoardTask(id: taskID)
    let originalRecord = try inboxRecord(for: originalTask)
    switch action {
    case .makeTask:
        try upsertInboxRecord(taskID: taskID, disposition: .task, reviewAt: nil)
        return InboxTriageMutation(originalTask: originalTask, originalRecord: originalRecord, updatedTask: originalTask)
    case .scheduleToday:
        let updated = try updateTask(id: taskID, originalTask.inboxDraft(status: .planned, dueAt: .some(ISO8601DateFormatter().string(from: referenceDate))))
        try upsertInboxRecord(taskID: taskID, disposition: .scheduled, reviewAt: nil)
        return InboxTriageMutation(originalTask: originalTask, originalRecord: originalRecord, updatedTask: updated)
    case .reviewLater:
        let review = try InboxReviewClock.nextReviewDate(after: referenceDate, calendar: calendar)
        try upsertInboxRecord(taskID: taskID, disposition: .reviewLater, reviewAt: ISO8601DateFormatter().string(from: review))
        return InboxTriageMutation(originalTask: originalTask, originalRecord: originalRecord, updatedTask: originalTask)
    case .makeProject:
        let project = try createProject(title: originalTask.title)
        let updated = try updateTask(id: taskID, originalTask.inboxDraft(projectID: project.id, status: .planned))
        try upsertInboxRecord(taskID: taskID, disposition: .project, reviewAt: nil)
        return InboxTriageMutation(originalTask: originalTask, originalRecord: originalRecord, updatedTask: updated, createdProjectID: project.id)
    case .complete:
        let updated = try updateTask(id: taskID, originalTask.inboxDraft(status: .done))
        try upsertInboxRecord(taskID: taskID, disposition: .task, reviewAt: nil)
        return InboxTriageMutation(originalTask: originalTask, originalRecord: originalRecord, updatedTask: updated)
    case .reopen:
        let updated = try updateTask(id: taskID, originalTask.inboxDraft(status: .planned))
        try upsertInboxRecord(taskID: taskID, disposition: .task, reviewAt: nil)
        return InboxTriageMutation(originalTask: originalTask, originalRecord: originalRecord, updatedTask: updated)
    }
}
```

Use a focused private draft helper in `InboxTriage.swift`; do not duplicate field copying in four branches.

- [x] **Step 6: Implement Undo in one transaction**

Restore the original Task fields and state. For Make Project, recreate/relink behavior stays coordinated by the existing ViewModel capture path; delete the created Project only after the Task restore succeeds. On any failure, roll back the full SQLite mutation.

- [x] **Step 7: Re-run the atomicity tests**

Run: `swift test --filter ProjectBoardStoreTests.testSQLiteInbox`
Expected: all focused mutation, restart, and forced-failure tests pass.

- [x] **Step 8: Commit the atomic store slice**

```bash
git add Sources/SuisuiCore/WorkManagement/InboxTriage.swift Sources/SuisuiCore/WorkManagement/WorkManagementStore.swift Sources/SuisuiCore/WorkManagement/WorkManagementSQLiteStore.swift Tests/SuisuiCoreTests/ProjectBoardStoreTests.swift
git commit -m "feat(inbox): make triage mutations atomic"
```

### Task 4: Bring test doubles and failure stores onto the contract

**Files:**
- Modify: `Tests/SuisuiCoreTests/Support/LocalRuntimeTestDoubles.swift`
- Modify: `Tests/SuisuiCoreTests/ExternalTaskInteropTests.swift`
- Modify: `Tests/SuisuiCoreTests/ProjectBoardStoreTests.swift`
- Modify: `Sources/SuisuiApp/Composition/MenuBarRuntimeFactory.swift`
- Modify: `Sources/SuisuiApp/Composition/ProjectBoardRuntimeFactory.swift`

- [x] **Step 1: Run a build to list every missing conformance**

Run: `swift test --filter ProjectBoardStoreTests.testSQLiteInboxMakeTaskAndUndoAreAtomicAcrossRestart`
Expected: compiler lists the remaining `ProjectBoardStore` conformers.

- [x] **Step 2: Implement real in-memory semantics**

Add an `inboxRecordsByTaskID` dictionary to `InMemoryProjectBoardStore`. `createInboxTask`, `performInboxTriage` (including completion and reopening), and `undoInboxTriage` must copy the same state transitions as SQLite and restore the entire pre-mutation snapshot on thrown errors.

```swift
private var inboxRecordsByTaskID: [Int64: InboxTriageRecord] = [:]

func loadInboxTriageRecords(taskIDs: Set<Int64>) throws -> [Int64: InboxTriageRecord] {
    Dictionary(uniqueKeysWithValues: taskIDs.compactMap { id in
        inboxRecordsByTaskID[id].map { (id, $0) }
    })
}
```

- [x] **Step 3: Make counting/failing/unavailable stores explicit**

Counting stores delegate to their base store. Unavailable and always-failing stores throw their existing sanitized failure from all new mutation methods. Do not add a protocol default that silently performs a non-atomic classification.

- [x] **Step 4: Run the owning suites**

Run:

```bash
swift test --filter ProjectBoardStoreTests
swift test --filter ExternalTaskInteropTests
swift test --filter WorkManagementSourceContractTests
```

Expected: all pass with no missing conformances.

- [x] **Step 5: Commit test-double parity**

```bash
git add Tests/SuisuiCoreTests/Support/LocalRuntimeTestDoubles.swift Tests/SuisuiCoreTests/ExternalTaskInteropTests.swift Tests/SuisuiCoreTests/ProjectBoardStoreTests.swift Sources/SuisuiApp/Composition/MenuBarRuntimeFactory.swift Sources/SuisuiApp/Composition/ProjectBoardRuntimeFactory.swift
git commit -m "test(inbox): align stores with triage contract"
```

### Task 5: Route ProjectBoardViewModel through explicit triage state

**Files:**
- Modify: `Sources/SuisuiCore/App/BoardOperationUndo.swift`
- Modify: `Sources/SuisuiCore/App/ProjectBoard.swift`
- Test: `Tests/SuisuiCoreTests/ProjectBoardStoreTests.swift`
- Test: `Tests/SuisuiCoreTests/InboxCaptureStoreTests.swift`

- [x] **Step 1: Write failing ViewModel behavior tests**

Cover initial Unprocessed filter, Make Task visibility, Review Later 08:59/09:00, next selection, completion/reopening through Edit-menu Undo, direct triage Undo, and Voice capture relink:

```swift
@MainActor
func testMakeTaskLeavesInboxHistoryButAdvancesUnprocessedSelection() throws {
    let viewModel = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
    viewModel.load()
    let first = try XCTUnwrap(viewModel.createInboxTask(title: "First"))
    let second = try XCTUnwrap(viewModel.createInboxTask(title: "Second"))
    viewModel.selectedTaskID = second.id

    viewModel.markSelectedTaskAsTask()

    XCTAssertEqual(viewModel.inboxTriageFilter, .unprocessed)
    XCTAssertEqual(viewModel.filteredInboxTasks.map(\.id), [first.id])
    XCTAssertTrue(viewModel.inboxTasks.contains { $0.id == second.id })
    XCTAssertEqual(viewModel.selectedTaskID, first.id)
}
```

- [x] **Step 2: Run the ViewModel tests and verify failure**

Run: `swift test --filter ProjectBoardStoreTests.testMakeTaskLeavesInboxHistory`
Expected: Make Task still appears as unprocessed.

- [x] **Step 3: Cache triage records at load time**

Add `inboxTriageRecordsByTaskID` beside the existing capture cache. Refresh it from `store.loadInboxTriageRecords` during `load()`. If state loading fails, derive visible `unprocessed` records and publish a sanitized error without hiding Task rows.

- [x] **Step 4: Replace status/due-only filtering**

Define one business predicate and reuse it for rows, counts, sidebar count, and selection:

```swift
private func isInboxUnprocessed(_ task: ProjectBoardTask, at referenceDate: Date) -> Bool {
    let record = inboxTriageRecord(for: task)
    switch record.disposition {
    case .unprocessed:
        return task.status != .done
    case .reviewLater:
        guard task.status != .done else { return false }
        guard let rawReviewAt = record.reviewAt,
              let reviewAt = ISO8601DateFormatter().date(from: rawReviewAt) else {
            // Corrupt deferred metadata must not silently hide captured work.
            return true
        }
        return reviewAt <= referenceDate
    case .task, .scheduled, .project:
        return false
    }
}
```

Use explicit optional handling rather than comparing an optional Date directly in the final code.

- [x] **Step 5: Route four actions and Undo through the store**

Replace `applyInboxTaskUpdate` and the separate Project creation path with `performInboxTriage`. Preserve feedback strings and capture relinking. Store the returned mutation as the single Inbox Undo token.

- [x] **Step 6: Add deterministic deferred refresh**

Expose:

```swift
public func refreshInboxReviewAvailability(at referenceDate: Date = Date()) {
    inboxVisibilityReferenceDate = referenceDate
    ensureSelectedTaskIsVisibleInInboxFilter()
}
```

Tests pass fixed dates; no test sleeps or production global clock overrides are added.

- [x] **Step 7: Preserve Inbox state in completion/reopen Board Undo**

When `toggleTaskCompletion` targets an Inbox Task, call `performInboxTriage` with `.complete` or `.reopen` instead of updating only the Task row. Extend the existing Undo entry:

```swift
enum BoardOperationUndoEntry: Equatable, Sendable {
    // Existing cases remain unchanged.
    case revertInboxTriage(
        mutation: InboxTriageMutation,
        regenerated: ProjectBoardTask?
    )
}
```

After completing a recurring Task, detect the regenerated Task with the existing before/after ID diff and retain it in the entry. `undoLastBoardOperation()` first deletes that regenerated Task only when it is still untouched, then calls `store.undoInboxTriage(mutation)`. If either operation fails, keep the Undo entry so the user can retry; tests must prove the original disposition, status, and selection are restored together.

- [x] **Step 8: Run ViewModel and capture suites**

Run:

```bash
swift test --filter ProjectBoardStoreTests
swift test --filter InboxCaptureStoreTests
```

Expected: classification, selection, Voice relink, restart, and Undo tests pass.

- [x] **Step 9: Commit ViewModel behavior**

```bash
git add Sources/SuisuiCore/App/BoardOperationUndo.swift Sources/SuisuiCore/App/ProjectBoard.swift Tests/SuisuiCoreTests/ProjectBoardStoreTests.swift Tests/SuisuiCoreTests/InboxCaptureStoreTests.swift
git commit -m "fix(inbox): honor persisted triage lifecycle"
```

### Task 6: Update Inbox UI, Quick Add, sorting, and deferred refresh

**Files:**
- Modify: `Sources/SuisuiApp/Views/ProjectWorkflowInboxView.swift`
- Modify: `Sources/SuisuiApp/Resources/en.lproj/Localizable.strings`
- Modify: `Sources/SuisuiApp/Resources/ja.lproj/Localizable.strings`
- Test: `Tests/SuisuiCoreTests/AppExperienceSourceTests.swift`

- [x] **Step 1: Write failing source contracts**

Assert Quick Add calls `createInboxTask`, sorting uses `createdAt`, state badges exist, and periodic refresh is scoped to Inbox:

```swift
func testInboxReferenceUIUsesPersistedTriageLifecycle() throws {
    let source = try readPackageFile("Sources/SuisuiApp/Views/ProjectWorkflowInboxView.swift")
    XCTAssertTrue(source.contains("viewModel.createInboxTask(title: title)"))
    XCTAssertTrue(source.contains("task.createdAt"))
    XCTAssertTrue(source.contains("viewModel.inboxTriageRecord(for:"))
    XCTAssertTrue(source.contains("viewModel.refreshInboxReviewAvailability(at:"))
}
```

- [x] **Step 2: Run the source test and verify failure**

Run: `swift test --filter AppExperienceSourceTests.testInboxReferenceUIUsesPersistedTriageLifecycle`
Expected: all four assertions fail.

- [x] **Step 3: Make Quick Add success-dependent**

Replace the direct Inbox-ID path:

```swift
private func addInboxTask() {
    let title = quickTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty else { return }
    guard viewModel.createInboxTask(title: title) != nil else {
        isQuickAddExpanded = true
        isQuickAddFocused = true
        return
    }
    quickTitle = ""
    isQuickAddExpanded = false
}
```

- [x] **Step 4: Sort by stable creation time**

Parse `createdAt` through the existing timestamp helper or one focused Core helper. Compare ID only when timestamps are equal or missing. Do not sort Voice rows by capture update/memo time.

- [x] **Step 5: Render disposition and review badges**

Keep source/interpretation labels and add one state badge derived from the ViewModel record. `reviewLater` displays the localized next-review day/time; `task` and `scheduled` are visible in All/source filters but not Unprocessed.

- [x] **Step 6: Add the one-minute visible refresh**

Use `TimelineView(.periodic(from: .now, by: 60))` around the Inbox workflow body and call `refreshInboxReviewAvailability(at:)` only when the emitted minute changes. Avoid a process-wide Timer or Store polling.

- [x] **Step 7: Add English and Japanese strings**

Add concrete translations for `Processed task`, `Scheduled`, `Review tomorrow at %@`, `Review due`, and the sanitized triage load/save errors.

- [x] **Step 8: Run UI and localization tests**

Run:

```bash
swift test --filter AppExperienceSourceTests.testInbox
swift test --filter LocalizationStaticTests
```

Expected: Inbox contracts and both locale tables pass.

- [x] **Step 9: Commit the UI slice**

```bash
git add Sources/SuisuiApp/Views/ProjectWorkflowInboxView.swift Sources/SuisuiApp/Resources/en.lproj/Localizable.strings Sources/SuisuiApp/Resources/ja.lproj/Localizable.strings Tests/SuisuiCoreTests/AppExperienceSourceTests.swift
git commit -m "feat(inbox): surface triage state and deferred review"
```

### Task 7: Strengthen runtime smoke and release contracts

**Files:**
- Modify: `script/check_runtime_inbox_triage_smoke.sh`
- Modify: `Tests/SuisuiCoreTests/ReleasePipelineTests.swift`

- [x] **Step 1: Write a failing script contract test**

Require the smoke to verify the new state table and stable due date:

```swift
func testRuntimeInboxTriageSmokeVerifiesDispositionAndReviewDate() throws {
    let script = try readPackageFile("script/check_runtime_inbox_triage_smoke.sh")
    XCTAssertTrue(script.contains("inbox_triage_records"))
    XCTAssertTrue(script.contains("disposition='task'"))
    XCTAssertTrue(script.contains("disposition='review_later'"))
    XCTAssertTrue(script.contains("review_at IS NOT NULL"))
    XCTAssertTrue(script.contains("due_at IS NULL"))
}
```

- [x] **Step 2: Run the contract test and verify failure**

Run: `swift test --filter ReleasePipelineTests.testRuntimeInboxTriageSmokeVerifiesDispositionAndReviewDate`
Expected: missing SQL assertions.

- [x] **Step 3: Update the visible-app smoke**

After clicking each existing AX action, query SQLite for:

- Make Task: `disposition='task'`, Task still belongs to Inbox.
- Schedule Today: `disposition='scheduled'`, status planned, due set.
- Review Later: `disposition='review_later'`, review set, original due remains NULL.
- Make Project: `disposition='project'`, Task moved to the created Project.
- Undo: original Task and `unprocessed` state restored.

Keep Quick Add expansion before locating the text field.

- [x] **Step 4: Run source contract and real runtime smoke**

Run:

```bash
swift test --filter ReleasePipelineTests.testRuntimeInboxTriageSmoke
./script/check_runtime_inbox_triage_smoke.sh
```

Expected: the visible app completes Quick Add, four classifications, and Undo; every SQLite postcondition is `1`.

- [x] **Step 5: Commit runtime evidence**

```bash
git add script/check_runtime_inbox_triage_smoke.sh Tests/SuisuiCoreTests/ReleasePipelineTests.swift
git commit -m "test(inbox): verify persisted triage lifecycle at runtime"
```

### Task 8: Final validation and self-review

**Files:**
- Review all files changed in Tasks 1-7.

- [x] **Step 1: Run focused suites**

```bash
swift test --filter InboxCaptureStoreTests
swift test --filter ProjectBoardStoreTests
swift test --filter AppExperienceSourceTests
swift test --filter ReleasePipelineTests
```

Expected: all pass.

- [x] **Step 2: Run accessibility and security gates**

```bash
./script/check_accessibility_preflight.sh --source-only
./script/check_security_regressions.sh
```

Expected: both print `OK` and exit 0.

- [x] **Step 3: Run full tests and build**

```bash
swift test
./script/build_and_run.sh --build-only
git diff --check
```

Expected: full suite and build pass; diff check is silent.

- [ ] **Step 4: Inspect UI in the supported matrix**

Capture Inbox in English/Japanese, Light/Dark, and wide/compact widths. Confirm the right rail moves below at compact width, no horizontal scrolling appears, Review Later badges remain readable, and the sidebar is unchanged.

- [x] **Step 5: Self-review business invariants**

Confirm one source of truth for disposition, no `dueAt` reuse for Review Later, no non-atomic SQLite production path, no hidden migrated Task, selection changes only after successful persistence, and comments explain the atomicity/backfill reasons.

- [x] **Step 6: Commit only if validation required a corrective diff**

```bash
git add Sources/SuisuiCore/WorkManagement/InboxTriage.swift Sources/SuisuiCore/Database/SQLiteDatabaseClient.swift Sources/SuisuiCore/WorkManagement/WorkManagementModels.swift Sources/SuisuiCore/WorkManagement/WorkManagementStore.swift Sources/SuisuiCore/WorkManagement/WorkManagementSQLiteStore.swift Sources/SuisuiCore/App/BoardOperationUndo.swift Sources/SuisuiCore/App/ProjectBoard.swift Sources/SuisuiApp/Views/ProjectWorkflowInboxView.swift Tests/SuisuiCoreTests/Support/LocalRuntimeTestDoubles.swift Tests/SuisuiCoreTests/ProjectBoardStoreTests.swift Tests/SuisuiCoreTests/InboxCaptureStoreTests.swift Tests/SuisuiCoreTests/AppExperienceSourceTests.swift Tests/SuisuiCoreTests/ReleasePipelineTests.swift script/check_runtime_inbox_triage_smoke.sh
git commit -m "fix(inbox): close triage validation gaps"
```

If no corrective diff exists, do not create an empty commit.
