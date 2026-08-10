# Today Focus and Workload Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the `6.5h / 8h` workload semantics and a restart-safe local Focus timer without changing task status or external calendars.

**Architecture:** Keep planned load as a pure projection of Schedule time blocks and the persisted daily capacity. Keep actual Focus time in a small local state machine with a wall-clock timestamp for restart recovery and a test-injected clock. The Today card sends only explicit local actions to `TodayFocusSessionStore`; it never calls ProjectBoard mutation for completion.

**Tech Stack:** Swift 6, Foundation `Date`/`Calendar`, SwiftUI, XCTest, `UserDefaultsAppSettingsStore`, a small Codable Focus record.

---

## File map

- Create: `Sources/SuisuiCore/App/FocusSession.swift` — state machine, record, persistence protocol, clock abstraction.
- Create: `Sources/SuisuiCore/App/TodayWorkloadSnapshot.swift` — planned minutes/category projection and capacity validation.
- Modify: `Sources/SuisuiCore/App/AppSettings.swift` — `dailyWorkCapacityMinutes` with 1–16 hour, 30-minute validation.
- Modify: `Sources/SuisuiCore/App/TodayDashboardSnapshot.swift` — consume the workload projection rather than recompute it in SwiftUI.
- Create: `Sources/SuisuiApp/Views/TodayFocusCard.swift` — timer controls and AX state.
- Modify: `Sources/SuisuiApp/Views/TodayDashboardRailView.swift` — replace the Phase 1 placeholder with the Focus card.
- Modify: `Sources/SuisuiApp/Views/SettingsFeatureViews.swift` and localized strings — capacity control.
- Create: `Tests/SuisuiCoreTests/FocusSessionTests.swift`.
- Create: `Tests/SuisuiCoreTests/TodayWorkloadSnapshotTests.swift`.
- Modify: `Tests/SuisuiCoreTests/AppSettingsTests.swift`.

### Task 1: Lock the capacity and workload rules with tests

- [ ] **Step 1: Add failing capacity Codable/normalization tests to `AppSettingsTests.swift`.** Cover default `480`, legacy JSON without the key, 30-minute values, below-minimum and above-maximum values.

```swift
func testDailyWorkCapacityDefaultsToEightHoursAndClampsInvalidValues() throws {
    XCTAssertEqual(AppSettings.default.dailyWorkCapacityMinutes, 480)
    XCTAssertEqual(AppSettings(dailyWorkCapacityMinutes: 0).normalizedForRuntime.dailyWorkCapacityMinutes, 30)
    XCTAssertEqual(AppSettings(dailyWorkCapacityMinutes: 24 * 60).normalizedForRuntime.dailyWorkCapacityMinutes, 16 * 60)
}
```

- [ ] **Step 2: Add failing `TodayWorkloadSnapshotTests.swift`.** Use explicit task time blocks and assert category minutes, total minutes, capacity, ratio, and over-capacity flag. A scheduled block with no parseable duration must contribute zero and be reported through the builder's non-secret diagnostic field, not guessed.
- [ ] **Step 3: Run focused tests and verify compile failures.**

```bash
swift test --filter SuisuiCoreTests.AppSettingsTests/testDailyWorkCapacityDefaultsToEightHoursAndClampsInvalidValues
swift test --filter SuisuiCoreTests.TodayWorkloadSnapshotTests
```

Expected: missing property/type failures.

### Task 2: Implement validated capacity and pure workload projection

- [ ] **Step 1: Add `dailyWorkCapacityMinutes` to `AppSettings` with CodingKeys, legacy decode default, encode, and `normalizedForRuntime`.** Reuse the existing `validate()` path so Settings Save reports a user-facing error instead of silently accepting invalid data.
- [ ] **Step 2: Add `TodayWorkloadSnapshot` with these fields:** `scheduledMinutes`, `focusTaskBlockMinutes`, `plannedMinutes`, `capacityMinutes`, `ratio`, `isOverCapacity`, and category labels for the ring legend.
- [ ] **Step 3: Implement duration parsing from `TodayTimeBlock.startAt`/`endAt`.** Parse through the existing timestamp utilities; if either endpoint is missing or reversed, return zero and append a stable diagnostic enum such as `.unparseableBlock(id:)`. Never infer a duration from task title or current time.
- [ ] **Step 4: Add tests for 0h/8h, exact 8h, 9h/8h, mixed categories, and malformed blocks.**
- [ ] **Step 5: Update `TodayDashboardSnapshotBuilder` to consume `TodayWorkloadSnapshot`.** Remove any direct minute calculation from view code.
- [ ] **Step 6: Run the focused tests and commit.**

```bash
swift test --filter SuisuiCoreTests.TodayWorkloadSnapshotTests
swift test --filter SuisuiCoreTests.AppSettingsTests
git add Sources/SuisuiCore/App/AppSettings.swift Sources/SuisuiCore/App/TodayWorkloadSnapshot.swift Sources/SuisuiCore/App/TodayDashboardSnapshot.swift Tests/SuisuiCoreTests/AppSettingsTests.swift Tests/SuisuiCoreTests/TodayWorkloadSnapshotTests.swift
git diff --cached --check
git commit -m "feat: add Today workload capacity projection"
```

### Task 3: Write the Focus state-machine tests first

**Files:** Create `Tests/SuisuiCoreTests/FocusSessionTests.swift`.

- [ ] **Step 1: Define the test clock and in-memory persistence in the test file.** The clock returns a mutable `Date`; the persistence records every write so the test can assert no per-second writes.
- [ ] **Step 2: Add tests for every allowed transition.** `idle.start`, `running.pause`, `paused.resume`, `running.end`, and `running` reaching duration become `completed`; invalid transitions return an `Equatable` error.
- [ ] **Step 3: Add restart tests.** Persist a running record at `09:00`, recreate the store at `09:16:14`, and assert `elapsed == 16m14s`; persist a paused record and assert time does not grow while paused.
- [ ] **Step 4: Add safety tests.** A clock moving backwards contributes zero, a second task cannot replace an active task without an explicit `.replaceExisting` action, and no transition calls ProjectBoard or Calendar APIs.
- [ ] **Step 5: Run and confirm the expected missing-type failures.**

```bash
swift test --filter SuisuiCoreTests.FocusSessionTests
```

### Task 4: Implement FocusSession and transition persistence

**Files:** Create `Sources/SuisuiCore/App/FocusSession.swift`.

- [ ] **Step 1: Add `FocusSessionState` (`idle`, `running`, `paused`, `completed`) and `FocusSessionRecord: Codable, Equatable, Sendable`.** Store optional `taskID`, `durationSeconds`, `accumulatedSeconds`, `resumedAt`, and state.
- [ ] **Step 2: Add `FocusSessionClock` and `FocusSessionPersistence` protocols.** Production uses a wall-clock provider and a UserDefaults-backed record; tests inject the mutable clock and in-memory persistence.
- [ ] **Step 3: Implement `TodayFocusSessionStore`.** `start`, `pause`, `resume`, `end`, `tick`, and `restore` must be `@MainActor` observable actions. Persist only after a transition or when the session crosses `completed`; `tick` publishes derived remaining time without saving.
- [ ] **Step 4: Add an explicit replacement result.** Starting another task while running returns `.requiresReplacement(existingTaskID:)`; only a second call with confirmation ends the old session and starts the new one.
- [ ] **Step 5: Run all Focus tests and commit.**

```bash
swift test --filter SuisuiCoreTests.FocusSessionTests
git add Sources/SuisuiCore/App/FocusSession.swift Tests/SuisuiCoreTests/FocusSessionTests.swift
git diff --cached --check
git commit -m "feat: add restart-safe local Focus session"
```

### Task 5: Add the Focus and Workload cards

**Files:** Create `Sources/SuisuiApp/Views/TodayFocusCard.swift`; modify `Sources/SuisuiApp/Views/TodayDashboardRailView.swift`; modify settings views/localizations.

- [ ] **Step 1: Add the capacity control to Settings.** Use a `Stepper` or `Picker` bound to 30-minute values from 30 through 960; expose `settings-daily-work-capacity`; save through the existing Save Settings button.
- [ ] **Step 2: Implement `TodayWorkloadCard`.** Render a native circular progress shape, center text `planned / capacity`, the two category legend rows, and an over-capacity label/icon that is not color-only.
- [ ] **Step 3: Implement `TodayFocusCard`.** Render preset/custom duration selection, remaining time, current task title, Start/Pause/Resume/End, and a Deep Link to the task. Add `today-focus-card`, `today-focus-start`, `today-focus-pause`, `today-focus-resume`, and `today-focus-end` identifiers.
- [ ] **Step 4: Restore the store on `.task` and tick on a `ContinuousClock`/Task loop.** Cancel the loop on disappear; the persisted store remains the source for restart recovery.
- [ ] **Step 5: Assert in the view model/action layer that focus end never calls `toggleTaskCompletion`, Schedule, Reminder, or Google Calendar.** Add a regression test around the injected action closures.
- [ ] **Step 6: Run focused Core tests and build the app target.**

```bash
swift test --filter SuisuiCoreTests.FocusSessionTests
swift test --filter SuisuiCoreTests.TodayFeatureViewModelTests
swift build --product Suisui
```

- [ ] **Step 7: Commit the UI integration.**

```bash
git add Sources/SuisuiApp/Views/TodayFocusCard.swift Sources/SuisuiApp/Views/TodayDashboardRailView.swift Sources/SuisuiApp/Views/SettingsFeatureViews.swift Sources/SuisuiApp/Resources/en.lproj/Localizable.strings Sources/SuisuiApp/Resources/ja.lproj/Localizable.strings Tests/SuisuiCoreTests
git diff --cached --check
git commit -m "feat: add Today workload and Focus cards"
```

### Task 6: Focus/Workload verification

- [ ] **Step 1: Run the full Core suite.**

```bash
swift test
```

- [ ] **Step 2: Run `script/build_and_run.sh --verify` and manually verify 0h/8h, over-capacity, pause/resume, and restart restoration.**
- [ ] **Step 3: Capture the Workload and Focus AX subtree in the existing Today evidence before starting Plan 3.**
