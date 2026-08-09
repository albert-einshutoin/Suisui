# Today Dashboard Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current action-centric Today surface with the approved `today.png` information hierarchy while preserving existing task actions and the PR #438 sidebar.

**Architecture:** Extend the existing `TodayFeatureViewModel` to publish the Schedule Read Model it already owns indirectly. Build an immutable `TodayDashboardSnapshot` in SuisuiCore, then pass explicit values and action closures into small SwiftUI views. The existing `ProjectWorkflowTodayView` remains the route-compatible entry point; it delegates rendering to the new dashboard components.

**Tech Stack:** Swift 6, SwiftUI, XCTest, existing `ProjectBoardDerivedReadModels`, existing visual evidence harness.

---

## File map

- Create: `Sources/SuisuiCore/App/TodayDashboardSnapshot.swift` — immutable UI projection types and pure builder.
- Modify: `Sources/SuisuiCore/App/TodayFeatureViewModel.swift` — expose `schedule` in `TodayFeatureState` and subscribe to the already-published derived read model.
- Create: `Tests/SuisuiCoreTests/TodayDashboardSnapshotTests.swift` — builder contracts and deterministic recommendation tests.
- Modify: `Tests/SuisuiCoreTests/TodayFeatureViewModelTests.swift` — schedule publication regression coverage.
- Modify: `Sources/SuisuiApp/Views/ProjectWorkflowTodayView.swift` — keep route/legacy focus handling, delegate body to `TodayDashboardView`.
- Create: `Sources/SuisuiApp/Views/TodayDashboardView.swift` — wide/compact root layout.
- Create: `Sources/SuisuiApp/Views/TodayDashboardHeaderView.swift` — greeting/date/weather placeholder and header AX boundary.
- Create: `Sources/SuisuiApp/Views/TodayDashboardCards.swift` — recommendation, schedule, and review card shells.
- Create: `Sources/SuisuiApp/Views/TodayDashboardTaskListView.swift` — wide table-like rows and compact card rows.
- Create: `Sources/SuisuiApp/Views/TodayDashboardRailView.swift` — workload/focus/assistant slots; Focus is a placeholder until Plan 2.
- Modify: `Sources/SuisuiApp/Views/ProjectWorkflowSharedViews.swift` only for shared task row primitives that are proven reusable by both Today and Inbox.
- Modify: `Sources/SuisuiApp/Resources/en.lproj/Localizable.strings` and `Sources/SuisuiApp/Resources/ja.lproj/Localizable.strings` for new visible labels; preserve `Suisui` spelling.

### Task 1: Lock the Snapshot contract with failing tests

**Files:** Create `Tests/SuisuiCoreTests/TodayDashboardSnapshotTests.swift`.

- [ ] **Step 1: Write the failing builder contract.** Use the existing public initializers for `ProjectBoardTask`, `TodayWorkflowPlan`, `TodayWorkflowSnapshot`, and `ProjectBoardScheduleReadModel` to assert that one task, one time block, a project title, and a daily capacity become stable Snapshot rows.

```swift
func testBuilderProjectsTodayAndScheduleIntoStableSnapshot() {
    let task = ProjectBoardTask(
        id: 1,
        projectID: 7,
        title: "Ship release",
        detail: "",
        status: .planned,
        priority: .high,
        dueAt: "2026-08-09T09:00:00Z"
    )
    let today = TodayWorkflowSnapshot(
        plan: TodayWorkflowPlan(
            tasks: [task], overdueCount: 0, dueTodayCount: 1,
            recommendedTask: task, recommendationReason: "High priority",
            timeBlocks: [TodayTimeBlock(label: "09:00", task: task)]
        ),
        assistantContext: TodayAssistantRailContext(
            source: .recommended, task: task, projectTitle: "Launch",
            nextActionTitle: "Start", nextActionReason: "High priority",
            nextBlockLabel: "09:00", notes: "", subtaskSummary: "0/0",
            reminderSummary: "None"
        ),
        recommendationChips: []
    )

    let result = TodayDashboardSnapshotBuilder.make(
        today: today,
        schedule: .empty,
        projectTitlesByTaskID: [1: "Launch"],
        displayName: "Yamada",
        dailyCapacityMinutes: 480,
        now: Date(timeIntervalSince1970: 1_754_726_400),
        calendar: Calendar(identifier: .gregorian)
    )

    XCTAssertEqual(result.tasks.map(\.title), ["Ship release"])
    XCTAssertEqual(result.tasks.first?.projectTitle, "Launch")
    XCTAssertEqual(result.workload.capacityMinutes, 480)
    XCTAssertEqual(result.header.displayName, "Yamada")
}
```

- [ ] **Step 2: Run the focused test and verify it fails because the Snapshot types do not exist.**

```bash
swift test --filter SuisuiCoreTests.TodayDashboardSnapshotTests/testBuilderProjectsTodayAndScheduleIntoStableSnapshot
```

Expected: compile failure naming `TodayDashboardSnapshotBuilder` or the missing Snapshot properties.

### Task 2: Implement the pure Snapshot and deterministic recommendations

**Files:** Create `Sources/SuisuiCore/App/TodayDashboardSnapshot.swift`; modify the test file from Task 1.

- [ ] **Step 1: Add the exact immutable value types used by the view.** Define `TodayDashboardHeaderSnapshot`, `TodayRecommendation`, `TodayTaskRowSnapshot`, `TodayWorkloadSnapshot`, `TodayWeeklyScheduleSnapshot`, `TodayReviewSnapshot`, and `TodayDashboardSnapshot` as `Equatable, Sendable` structs. Store task IDs, titles, project titles, priority labels, time labels, and existing review summaries; do not store a board reference.
- [ ] **Step 2: Add `TodayDashboardSnapshotBuilder.make(today:schedule:projectTitlesByTaskID:displayName:dailyCapacityMinutes:now:calendar:)`.** Copy task rows from `today.plan.tasks`, derive the three deterministic recommendation candidates from the existing recommendation chips/review/unscheduled data, and use `now`/`calendar` arguments for all date formatting.
- [ ] **Step 3: Add a zero-data contract.** `TodayWorkflowSnapshot` with no tasks and `ProjectBoardScheduleReadModel.empty` must produce an empty task array, `0` planned minutes, capacity `480`, a name-free header, and a non-error empty review.
- [ ] **Step 4: Add priority and fallback tests, then run the focused suite.** Assert that high priority/overdue tasks precede optional suggestions and that no network client is referenced by the builder.

```bash
swift test --filter SuisuiCoreTests.TodayDashboardSnapshotTests
```

Expected: PASS.

- [ ] **Step 5: Commit the Core projection.**

```bash
git add Sources/SuisuiCore/App/TodayDashboardSnapshot.swift Tests/SuisuiCoreTests/TodayDashboardSnapshotTests.swift
git diff --cached --check
git commit -m "feat: add Today dashboard snapshot projection"
```

### Task 3: Wire Schedule into TodayFeatureViewModel

**Files:** Modify `Sources/SuisuiCore/App/TodayFeatureViewModel.swift`; modify `Tests/SuisuiCoreTests/TodayFeatureViewModelTests.swift`.

- [ ] **Step 1: Add a failing publication test.** Create a board with a scheduled task, construct `TodayFeatureViewModel`, mutate the board through its existing schedule read-model path, and assert that `feature.state.schedule.weeklyCockpit` changes in one aggregate publication.
- [ ] **Step 2: Extend the private `TodayFeatureReadState` with `schedule: ProjectBoardScheduleReadModel`.** Include it in `Equatable` mapping and `makeState(from:)`.
- [ ] **Step 3: Keep the existing coalesced synchronization boundary.** Do not add a separate subscription for every schedule child; continue mapping `board.$derivedReadModels`, then publish one aggregate state after the main-queue turn.
- [ ] **Step 4: Run the existing and new focused tests.**

```bash
swift test --filter SuisuiCoreTests.TodayFeatureViewModelTests
```

Expected: PASS, including the existing “one aggregate feature change” tests.

- [ ] **Step 5: Commit the ViewModel wiring.**

```bash
git add Sources/SuisuiCore/App/TodayFeatureViewModel.swift Tests/SuisuiCoreTests/TodayFeatureViewModelTests.swift
git diff --cached --check
git commit -m "feat: publish schedule data to Today"
```

### Task 4: Add the optional display-name setting

**Files:** Modify `Sources/SuisuiCore/App/AppSettings.swift`; modify `Tests/SuisuiCoreTests/AppSettingsTests.swift`; modify `Sources/SuisuiApp/Views/SettingsFeatureViews.swift` and localized strings.

- [ ] **Step 1: Add failing Codable/default tests.** Decode a legacy settings JSON with no new keys and assert `profileDisplayName == nil`; encode/decode a trimmed name and assert it round-trips without adding secrets.
- [ ] **Step 2: Add `profileDisplayName: String?` to `AppSettings`, `CodingKeys`, `init`, `init(from:)`, and `encode(to:)`.** Normalize whitespace in `normalizedForRuntime`; convert empty input to `nil`; cap the stored display name at 80 user-perceived characters.
- [ ] **Step 3: Add `setProfileDisplayName(_:)` to `AppSettingsViewModel`.** Update only in-memory settings until the existing Save Settings action is used, matching other non-secret settings.
- [ ] **Step 4: Add the Settings text field with `settings-profile-display-name` and a clear accessibility hint.** Use `TextField`, not `SecureField`, and never include the value in diagnostics.
- [ ] **Step 5: Run focused settings tests and commit.**

```bash
swift test --filter SuisuiCoreTests.AppSettingsTests
git add Sources/SuisuiCore/App/AppSettings.swift Sources/SuisuiApp/Views/SettingsFeatureViews.swift Tests/SuisuiCoreTests/AppSettingsTests.swift Sources/SuisuiApp/Resources/en.lproj/Localizable.strings Sources/SuisuiApp/Resources/ja.lproj/Localizable.strings
git diff --cached --check
git commit -m "feat: persist optional Today display name"
```

### Task 5: Replace the Today root with the approved responsive composition

**Files:** Modify `Sources/SuisuiApp/Views/ProjectWorkflowTodayView.swift`; create the five `TodayDashboard*.swift` files listed above; modify `Tests/SuisuiCoreTests/AppExperienceSourceTests.swift` only when an existing source contract must move with the route.

- [ ] **Step 1: Preserve the `TodayWorkflowView` initializer and all existing callbacks.** Its body should construct the Snapshot from `TodayFeatureViewModel.state`, pass existing task/schedule/daily-review actions as closures, and retain catch-up focus restoration.
- [ ] **Step 2: Implement `TodayDashboardView` with width-fit policy.** Use a `GeometryReader` inside the detail area. Render the main column and rail together only when the measured width fits the primary minimum plus rail minimum; otherwise render a single vertical `ScrollView` with the rail after the main sections.
- [ ] **Step 3: Implement `TodayDashboardHeaderView`, `TodayRecommendationsSection`, `TodayTaskListView`, `TodayWeeklyScheduleCard`, `TodayReviewCard`, and `TodayDashboardRailView`.** Every root card must have a stable AX identifier and accept values/closures rather than a board view model.
- [ ] **Step 4: Keep the `today.png` order.** Header, three recommendation cards, Today task rows, two lower cards (weekly schedule and review/external rows), then Workload, Focus placeholder, and Suisui Assistant in the rail.
- [ ] **Step 5: Keep actions local and explicit.** Task completion calls `viewModel.toggleTaskCompletion`, task selection calls `viewModel.selectTask`, Schedule links use the existing route callback, and Assistant actions use existing draft/approval methods.
- [ ] **Step 6: Add a source-level regression test for `Suisui` spelling and required AX identifiers.** Do not use a screenshot test to prove semantics; assert identifiers and source contract separately.
- [ ] **Step 7: Build the app target and run Today-related tests.**

```bash
swift test --filter SuisuiCoreTests.AppExperienceSourceTests
swift build --product Suisui
```

- [ ] **Step 8: Commit the foundation UI.**

```bash
git add Sources/SuisuiApp/Views/ProjectWorkflowTodayView.swift Sources/SuisuiApp/Views/TodayDashboard*.swift Tests/SuisuiCoreTests/AppExperienceSourceTests.swift
git diff --cached --check
git commit -m "feat: align Today dashboard with today reference"
```

### Task 6: Foundation verification and handoff

- [ ] **Step 1: Run all Core tests and the runtime smoke.**

```bash
swift test
script/build_and_run.sh --verify
```

- [ ] **Step 2: Inspect the generated app manually at 1448×1086 and 1024×676.** Confirm the rail moves below the main content and no horizontal scroll appears.
- [ ] **Step 3: Run `git diff --check`, verify the worktree is clean, and record the commit SHAs before starting Plan 2.**
