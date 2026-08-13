# Suisui Product Experience Renewal Implementation Plan

> **Status:** Historical implementation plan. The live design-system contract
> is `docs/ux/design-system.md`; do not reintroduce tokens listed only here.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the approved four-destination, progressive, accessible, native macOS Suisui experience without regressing approval-first execution, local-first data, undo, receipts, or existing deep links.

**Architecture:** Introduce relocation-safe source contracts and a typed scene route before changing navigation. Migrate one vertical product slice at a time, preserve legacy route codecs and `ProjectBoardViewModel` as compatibility facades, and finish by requiring normal-route runtime, visual, performance, security, and fresh accessibility evidence.

**Tech Stack:** Swift 6, SwiftUI/macOS 14+, AppKit adapters where system APIs require them, Swift Package Manager, XCTest, SQLite, shell-based AX/runtime/visual gates, GitHub Actions.

**Approved design:** `docs/superpowers/specs/2026-07-14-product-experience-renewal-design.md`

---

## File Ownership Map

### New core files

- `Sources/SuisuiCore/App/ProjectBoardRoute.swift`: typed primary/review/project/smart-list routes and legacy codec.
- `Sources/SuisuiCore/App/ProjectBoardSceneNavigation.swift`: pure scene routing reducer and exact-target request model.
- `Sources/SuisuiCore/App/InspectorPresentationPolicy.swift`: width- and intent-based inspector policy.
- `Sources/SuisuiCore/App/TodayPrimaryActionPresentation.swift`: one-primary-action decision.
- `Sources/SuisuiCore/App/SettingsReadinessPresentation.swift`: neutral/ready/action/blocked readiness classification.
- `Sources/SuisuiCore/App/TaskDueDateFieldState.swift`: localized date edit/clear/validation state.
- `Sources/SuisuiCore/App/ProjectBoardErrorPresentation.swift`: fatal versus recoverable error classification.
- `Sources/SuisuiCore/App/OnboardingExperience.swift`: experience-first onboarding path and target route.

### New app files

- `Sources/SuisuiApp/Views/ProjectBoardSidebarView.swift`: four primary destinations and nested project/filter rows.
- `Sources/SuisuiApp/Views/ProjectBoardProjectsHubView.swift`: portfolio, project, smart-list, completed, and archived project navigation.
- `Sources/SuisuiApp/Views/ProjectBoardReviewHubView.swift`: schedule/completed/automation/queue sections.
- `Sources/SuisuiApp/Views/ProjectWorkflowAutomationActivityView.swift`: AI usage, receipts, and execution activity separated from completed work.
- `Sources/SuisuiApp/Views/ProjectBoardToolbarContent.swift`: native contextual toolbar content.
- `Sources/SuisuiApp/Views/SettingsStatusOverviewView.swift`: progressive readiness groups.
- `Sources/SuisuiApp/Adapters/SystemShortcutClient.swift`: process-wide Option+Space registration.
- `Sources/SuisuiApp/Composition/ProjectBoardSceneCoordinator.swift`: exact owned scene/window routing.
- `Sources/SuisuiApp/Views/ProjectBoardInspectors.swift`: task/project inspector leaf views.
- `Sources/SuisuiApp/Views/ProjectBoardDetailViews.swift`: portfolio/project/kanban leaf views.
- `Sources/SuisuiApp/Views/SettingsFeatureViews.swift`: extracted Settings tab surfaces.

### Existing roots retained as owners

- `Sources/SuisuiApp/Views/ProjectBoardView.swift`: scene state, `NavigationSplitView`, sheet/overlay composition.
- `Sources/SuisuiApp/Views/SettingsView.swift`: Settings state object ownership and tab coordination.
- `Sources/SuisuiCore/App/ProjectBoard.swift`: compatibility facade during feature-scoped migration.

---

### Task 1: Make source and accessibility contracts relocation-safe

**Files:**
- Modify: `Tests/SuisuiCoreTests/AppExperienceSourceTests.swift`
- Modify: `Tests/SuisuiCoreTests/ArchitectureBoundaryTests.swift`
- Modify: `Tests/SuisuiCoreTests/ReleasePipelineTests.swift`
- Modify: `script/check_accessibility_preflight.sh`

- [ ] **Step 1: Add a failing aggregate-source contract**

Add a helper that reads every production Swift file whose basename starts with `ProjectBoard`, `ProjectWorkflow`, or `TaskInspector`, then assert that required AX anchors are found in the aggregate instead of one physical file.

```swift
private func readProjectBoardSurfaceSources() throws -> String {
    let views = packageRoot.appendingPathComponent("Sources/SuisuiApp/Views")
    let names = try FileManager.default.contentsOfDirectory(atPath: views.path)
        .filter {
            ($0.hasPrefix("ProjectBoard") || $0.hasPrefix("ProjectWorkflow") || $0.hasPrefix("TaskInspector"))
                && $0.hasSuffix(".swift")
        }
        .sorted()
    return try names.map { name in
        try String(contentsOf: views.appendingPathComponent(name), encoding: .utf8)
    }.joined(separator: "\n")
}
```

- [ ] **Step 2: Run the focused contracts and verify RED**

Run:

```bash
swift test --filter AppExperienceSourceTests
swift test --filter ArchitectureBoundaryTests
swift test --filter ReleasePipelineTests
```

Expected: at least one assertion still requires `ProjectBoardView.swift`-local declarations or the shell script still rejects moved anchors.

- [ ] **Step 3: Change all feature-anchor checks to aggregate sources**

Keep explicit file assertions only for actual ownership rules. Change `check_accessibility_preflight.sh` to accept a logical surface and search the matching file set:

```bash
project_board_sources=(
  Sources/SuisuiApp/Views/ProjectBoard*.swift
  Sources/SuisuiApp/Views/ProjectWorkflow*.swift
  Sources/SuisuiApp/Views/TaskInspector*.swift
)
```

Do not reduce the existing anchor count or approval-boundary checks.

- [ ] **Step 4: Verify GREEN**

Run:

```bash
swift test --filter AppExperienceSourceTests
swift test --filter ArchitectureBoundaryTests
swift test --filter ReleasePipelineTests
./script/check_accessibility_preflight.sh --source-only
```

Expected: all pass with the same or greater source-anchor coverage.

- [ ] **Step 5: Commit**

```bash
git add Tests/SuisuiCoreTests/AppExperienceSourceTests.swift Tests/SuisuiCoreTests/ArchitectureBoundaryTests.swift Tests/SuisuiCoreTests/ReleasePipelineTests.swift script/check_accessibility_preflight.sh
git commit -m "test: make UI contracts relocation safe"
```

### Task 2: Add typed Board routes and legacy migration

**Files:**
- Create: `Sources/SuisuiCore/App/ProjectBoardRoute.swift`
- Modify: `Sources/SuisuiCore/App/ProjectBoardSelectionPersistence.swift`
- Create: `Tests/SuisuiCoreTests/ProjectBoardRouteTests.swift`
- Modify: `Tests/SuisuiCoreTests/ProjectBoardSelectionPersistenceTests.swift`

- [ ] **Step 1: Write failing route and migration tests**

```swift
func testLegacyWorkflowDestinationsMigrateIntoFourPrimaryAreas() {
    XCTAssertEqual(ProjectBoardRouteCodec.route(from: "today", availableProjectIDs: []), .primary(.today))
    XCTAssertEqual(ProjectBoardRouteCodec.route(from: "inbox", availableProjectIDs: []), .primary(.inbox))
    XCTAssertEqual(ProjectBoardRouteCodec.route(from: "schedule", availableProjectIDs: []), .review(.schedule))
    XCTAssertEqual(ProjectBoardRouteCodec.route(from: "done", availableProjectIDs: []), .review(.completed))
    XCTAssertEqual(ProjectBoardRouteCodec.route(from: "assistant-queue", availableProjectIDs: []), .review(.assistantQueue))
    XCTAssertEqual(ProjectBoardRouteCodec.route(from: "catch-up", availableProjectIDs: []), .primary(.today))
}

func testMissingProjectFallsBackToToday() {
    XCTAssertEqual(ProjectBoardRouteCodec.route(from: "project:42", availableProjectIDs: [41]), .primary(.today))
}
```

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter ProjectBoardRouteTests`

Expected: compile failure because `BoardRoute` and `ProjectBoardRouteCodec` do not exist.

- [ ] **Step 3: Implement the typed route and compatibility codec**

```swift
public enum BoardPrimaryDestination: String, CaseIterable, Hashable, Sendable {
    case today, inbox, projects, review
}

public enum ReviewRoute: String, CaseIterable, Hashable, Sendable {
    case schedule, completed, automationActivity, assistantQueue
}

public enum BoardRoute: Hashable, Sendable {
    case primary(BoardPrimaryDestination)
    case project(Int64)
    case smartList(String)
    case review(ReviewRoute)
}

public enum ProjectBoardRouteCodec {
    public static func route(from rawValue: String, availableProjectIDs: Set<Int64>) -> BoardRoute
    public static func rawValue(for route: BoardRoute) -> String
}
```

The codec must preserve old raw values for environment fixtures while emitting stable new values: `primary:review`, `review:schedule`, `review:completed`, `review:automation`, and `review:assistant-queue`.

- [ ] **Step 4: Verify round trips and old persistence**

Run:

```bash
swift test --filter ProjectBoardRouteTests
swift test --filter ProjectBoardSelectionPersistenceTests
```

Expected: all old raw-value tests and all new migration tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/SuisuiCore/App/ProjectBoardRoute.swift Sources/SuisuiCore/App/ProjectBoardSelectionPersistence.swift Tests/SuisuiCoreTests/ProjectBoardRouteTests.swift Tests/SuisuiCoreTests/ProjectBoardSelectionPersistenceTests.swift
git commit -m "feat: add typed board route migration"
```

### Task 3: Introduce exact scene navigation and restoration

**Files:**
- Create: `Sources/SuisuiCore/App/ProjectBoardSceneNavigation.swift`
- Create: `Sources/SuisuiApp/Composition/ProjectBoardSceneCoordinator.swift`
- Modify: `Sources/SuisuiApp/SuisuiApp.swift`
- Modify: `Sources/SuisuiApp/Views/ProjectBoardView.swift`
- Create: `Tests/SuisuiCoreTests/ProjectBoardSceneNavigationTests.swift`
- Modify: `Tests/SuisuiCoreTests/LaunchExperienceTests.swift`

- [ ] **Step 1: Write failing reducer tests**

```swift
func testOnlyMatchingSceneConsumesTargetedRequest() {
    let target = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
    let request = ProjectBoardOpenRequest(id: UUID(), targetSceneID: target, route: .review(.assistantQueue))
    XCTAssertNil(ProjectBoardSceneNavigation.route(for: request, sceneID: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!))
    XCTAssertEqual(ProjectBoardSceneNavigation.route(for: request, sceneID: target), .review(.assistantQueue))
}
```

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter ProjectBoardSceneNavigationTests`

Expected: compile failure for the missing request/reducer types.

- [ ] **Step 3: Implement immutable requests and one app-level coordinator**

```swift
public struct ProjectBoardOpenRequest: Equatable, Sendable {
    public let id: UUID
    public let targetSceneID: UUID?
    public let route: BoardRoute

    public init(id: UUID = UUID(), targetSceneID: UUID?, route: BoardRoute) {
        self.id = id
        self.targetSceneID = targetSceneID
        self.route = route
    }
}

public enum ProjectBoardSceneNavigation {
    public static func route(for request: ProjectBoardOpenRequest, sceneID: UUID) -> BoardRoute? {
        guard request.targetSceneID == nil || request.targetSceneID == sceneID else { return nil }
        return request.route
    }
}
```

Use `@SceneStorage` for each window's encoded route and keep `@AppStorage` only as the initial route for a new window. The coordinator deduplicates request IDs so multiple windows do not consume one request.

- [ ] **Step 4: Verify routing and launch behavior**

Run:

```bash
swift test --filter ProjectBoardSceneNavigationTests
swift test --filter LaunchExperienceTests
./script/build_and_run.sh --verify
```

Expected: unit tests pass and one visible Project Board owns each request.

- [ ] **Step 5: Commit**

```bash
git add Sources/SuisuiCore/App/ProjectBoardSceneNavigation.swift Sources/SuisuiApp/Composition/ProjectBoardSceneCoordinator.swift Sources/SuisuiApp/SuisuiApp.swift Sources/SuisuiApp/Views/ProjectBoardView.swift Tests/SuisuiCoreTests/ProjectBoardSceneNavigationTests.swift Tests/SuisuiCoreTests/LaunchExperienceTests.swift
git commit -m "feat: route board requests to exact scenes"
```

### Task 4: Replace the sidebar with four primary destinations and add Review

**Files:**
- Create: `Sources/SuisuiApp/Views/ProjectBoardSidebarView.swift`
- Create: `Sources/SuisuiApp/Views/ProjectBoardProjectsHubView.swift`
- Create: `Sources/SuisuiApp/Views/ProjectBoardReviewHubView.swift`
- Create: `Sources/SuisuiApp/Views/ProjectWorkflowAutomationActivityView.swift`
- Modify: `Sources/SuisuiApp/Views/ProjectBoardView.swift`
- Modify: `Sources/SuisuiApp/Views/ProjectWorkflowScheduleView.swift`
- Modify: `Sources/SuisuiApp/Views/ProjectWorkflowDoneView.swift`
- Create: `Tests/SuisuiCoreTests/ProjectBoardPrimaryNavigationTests.swift`
- Modify: `Tests/SuisuiCoreTests/AppExperienceSourceTests.swift`

- [ ] **Step 1: Write failing navigation contracts**

```swift
func testPrimaryDestinationsAreFourStableItems() {
    XCTAssertEqual(BoardPrimaryDestination.allCases, [.today, .inbox, .projects, .review])
}

func testReviewContainsEveryFormerWorkflowDestination() {
    XCTAssertEqual(Set(ReviewRoute.allCases), [.schedule, .completed, .automationActivity, .assistantQueue])
}
```

Change source contracts so the top-level sidebar must expose exactly `sidebar-destination-today`, `sidebar-destination-inbox`, `sidebar-destination-projects`, and `sidebar-destination-review`.

- [ ] **Step 2: Run and verify RED**

Run:

```bash
swift test --filter ProjectBoardPrimaryNavigationTests
swift test --filter AppExperienceSourceTests
```

Expected: old sidebar exposure assertions fail until the four-area view is installed.

- [ ] **Step 3: Implement sidebar and Review hub**

`ProjectBoardSidebarView` accepts immutable counts and a current route binding. `ProjectBoardProjectsHubView` owns portfolio, active/completed/archived project rows and Smart List filters. `ProjectBoardReviewHubView` uses native section navigation for `ReviewRoute` and composes Schedule, Completed, Automation Activity, and Assistant Queue without changing mutation APIs. Move AI usage, receipt history, and execution activity out of Done into `ProjectWorkflowAutomationActivityView`; keep completion metrics and recap in Done.

Catch Up is rendered inside Today only when its count is greater than zero. Assistant Queue count is a non-color-only Review badge.

- [ ] **Step 4: Verify features remain reachable**

Run:

```bash
swift test --filter ProjectBoardPrimaryNavigationTests
swift test --filter AppExperienceSourceTests
swift test --filter ProjectBoardSelectionPersistenceTests
./script/check_accessibility_preflight.sh --source-only
```

Expected: four-area contracts pass, old route migration passes, and no AX anchor is lost.

- [ ] **Step 5: Commit**

```bash
git add Sources/SuisuiApp/Views/ProjectBoardSidebarView.swift Sources/SuisuiApp/Views/ProjectBoardProjectsHubView.swift Sources/SuisuiApp/Views/ProjectBoardReviewHubView.swift Sources/SuisuiApp/Views/ProjectWorkflowAutomationActivityView.swift Sources/SuisuiApp/Views/ProjectBoardView.swift Sources/SuisuiApp/Views/ProjectWorkflowScheduleView.swift Sources/SuisuiApp/Views/ProjectWorkflowDoneView.swift Tests/SuisuiCoreTests/ProjectBoardPrimaryNavigationTests.swift Tests/SuisuiCoreTests/AppExperienceSourceTests.swift
git commit -m "feat: introduce four-area board navigation"
```

### Task 5: Make Inspector presentation responsive and intentional

**Files:**
- Create: `Sources/SuisuiCore/App/InspectorPresentationPolicy.swift`
- Modify: `Sources/SuisuiApp/Views/ProjectBoardView.swift`
- Create: `Tests/SuisuiCoreTests/InspectorPresentationPolicyTests.swift`
- Modify: `Tests/SuisuiCoreTests/AppExperienceSourceTests.swift`
- Modify: `script/check_layout_stability_smoke.sh`

- [ ] **Step 1: Write failing width-policy tests**

```swift
func testCompactWindowsStartClosedAndRequireExplicitOpen() {
    XCTAssertFalse(InspectorPresentationPolicy.shouldPresent(windowWidth: 1_024, route: .primary(.projects), hasSelection: true, userRequested: false))
    XCTAssertTrue(InspectorPresentationPolicy.shouldPresent(windowWidth: 1_024, route: .project(42), hasSelection: true, userRequested: true))
}

func testWideWindowsMayRestoreUserIntent() {
    XCTAssertTrue(InspectorPresentationPolicy.shouldPresent(windowWidth: 1_180, route: .project(42), hasSelection: true, userRequested: true))
}
```

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter InspectorPresentationPolicyTests`

Expected: compile failure because the policy does not exist.

- [ ] **Step 3: Implement the pure policy and scene-local intent**

```swift
public enum InspectorPresentationPolicy {
    public static let compactWidth: CGFloat = 1_024

    public static func shouldPresent(
        windowWidth: CGFloat,
        route: BoardRoute,
        hasSelection: Bool,
        userRequested: Bool
    ) -> Bool {
        guard hasSelection, userRequested else { return false }
        if windowWidth <= compactWidth { return true }
        return route != .primary(.today) && route != .primary(.inbox)
    }
}
```

Store `userRequestedInspector` per scene. Resizing narrow may hide the side Inspector without resetting the request; do not auto-open it merely because a row selection changed.

- [ ] **Step 4: Verify policy and layout**

Run:

```bash
swift test --filter InspectorPresentationPolicyTests
swift test --filter AppExperienceSourceTests
SUISUI_LAYOUT_STABILITY_OUTPUT_DIR="$PWD/.tmp/layout-product-renewal" ./script/check_layout_stability_smoke.sh
```

Expected: 960/1024 start without an Inspector, explicit open works, and measured frame delta remains 0px after stabilization.

- [ ] **Step 5: Commit**

```bash
git add Sources/SuisuiCore/App/InspectorPresentationPolicy.swift Sources/SuisuiApp/Views/ProjectBoardView.swift Tests/SuisuiCoreTests/InspectorPresentationPolicyTests.swift Tests/SuisuiCoreTests/AppExperienceSourceTests.swift script/check_layout_stability_smoke.sh
git commit -m "feat: make board inspector adaptive"
```

### Task 6: Replace custom header chrome with a native toolbar

**Files:**
- Create: `Sources/SuisuiApp/Views/ProjectBoardToolbarContent.swift`
- Modify: `Sources/SuisuiApp/Views/ProjectBoardView.swift`
- Modify: `Sources/SuisuiApp/SuisuiApp.swift`
- Modify: `Sources/SuisuiCore/App/ProjectBoardToolbarLayoutPolicy.swift`
- Modify: `Tests/SuisuiCoreTests/ProjectBoardToolbarLayoutPolicyTests.swift`
- Modify: `Tests/SuisuiCoreTests/AppExperienceSourceTests.swift`
- Modify: `script/check_project_board_header_layout_smoke.sh`

- [ ] **Step 1: Replace old-header tests with native-toolbar tests**

```swift
func testContextualToolbarGroupsPrimaryAndOverflowActions() {
    XCTAssertEqual(ProjectBoardToolbarContext.project.hasPrimaryVoiceAction, true)
    XCTAssertEqual(ProjectBoardToolbarContext.today.showsDeveloperTerminal, false)
    XCTAssertEqual(ProjectBoardToolbarContext.developerProject.showsDeveloperTerminal, true)
}
```

The source contract must reject `.frame(height: 44)` plus `.background(.bar)` in the Project Board root and require `.toolbar` composition.

- [ ] **Step 2: Run and verify RED**

Run:

```bash
swift test --filter ProjectBoardToolbarLayoutPolicyTests
swift test --filter AppExperienceSourceTests
```

Expected: old custom-header implementation violates the new contract.

- [ ] **Step 3: Implement native toolbar content**

Create `ProjectBoardToolbarContext` as an Equatable core value and `ProjectBoardToolbarContent` as a SwiftUI `ToolbarContent`. Keep Voice and context primary actions visible; place integrations, automation, Settings, and Developer Terminal in semantic groups/overflow. Use availability checks for macOS 26-only grouping APIs and standard toolbar items on macOS 14.

Remove the custom `.bar` surface and preserve keyboard/menu access in `SuisuiApp.Commands`.

- [ ] **Step 4: Verify native chrome**

Run:

```bash
swift test --filter ProjectBoardToolbarLayoutPolicyTests
swift test --filter AppExperienceSourceTests
./script/check_project_board_header_layout_smoke.sh
./script/build_and_run.sh --verify
```

Expected: one native chrome layer, no clipping at minimum width, and all utility actions remain reachable.

- [ ] **Step 5: Commit**

```bash
git add Sources/SuisuiApp/Views/ProjectBoardToolbarContent.swift Sources/SuisuiApp/Views/ProjectBoardView.swift Sources/SuisuiApp/SuisuiApp.swift Sources/SuisuiCore/App/ProjectBoardToolbarLayoutPolicy.swift Tests/SuisuiCoreTests/ProjectBoardToolbarLayoutPolicyTests.swift Tests/SuisuiCoreTests/AppExperienceSourceTests.swift script/check_project_board_header_layout_smoke.sh
git commit -m "feat: adopt native project board toolbar"
```

### Task 7: Establish one Today primary action and contextual Catch Up

**Files:**
- Create: `Sources/SuisuiCore/App/TodayPrimaryActionPresentation.swift`
- Modify: `Sources/SuisuiApp/Views/ProjectWorkflowTodayView.swift`
- Modify: `Sources/SuisuiCore/App/ProjectBoard.swift`
- Create: `Tests/SuisuiCoreTests/TodayPrimaryActionPresentationTests.swift`
- Modify: `Tests/SuisuiCoreTests/AppExperienceSourceTests.swift`
- Modify: `script/check_runtime_today_complete_smoke.sh`

- [ ] **Step 1: Write failing presentation-policy tests**

```swift
func testRecommendedTaskWinsOverSecondaryActions() {
    let action = TodayPrimaryActionPresentation.make(recommendedTaskID: 42, recommendedTaskTitle: "Ship release", commandText: "", taskCount: 3)
    XCTAssertEqual(action, .startFocus(taskID: 42, title: "Ship release"))
}

func testCommandAndEmptyStatesHaveOneAction() {
    XCTAssertEqual(TodayPrimaryActionPresentation.make(recommendedTaskID: nil, recommendedTaskTitle: nil, commandText: "Capture notes", taskCount: 0), .addToInbox(text: "Capture notes"))
    XCTAssertEqual(TodayPrimaryActionPresentation.make(recommendedTaskID: nil, recommendedTaskTitle: nil, commandText: "", taskCount: 0), .addTaskForToday)
}
```

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter TodayPrimaryActionPresentationTests`

Expected: compile failure for the missing presentation enum.

- [ ] **Step 3: Implement pure action selection and simplify the view**

```swift
public enum TodayPrimaryActionPresentation: Equatable, Sendable {
    case startFocus(taskID: Int64, title: String)
    case addToInbox(text: String)
    case addTaskForToday

    public static func make(recommendedTaskID: Int64?, recommendedTaskTitle: String?, commandText: String, taskCount: Int) -> Self
}
```

Render exactly one `.borderedProminent` action. Move duplicate Focus, planning draft, optimize, read-aloud, and suggestion actions into secondary menus or contextual panels. Render Catch Up only when its actual count is positive.

- [ ] **Step 4: Verify Today behavior**

Run:

```bash
swift test --filter TodayPrimaryActionPresentationTests
swift test --filter AppExperienceSourceTests
./script/check_runtime_today_complete_smoke.sh
./script/check_runtime_today_production_route_smoke.sh
```

Expected: each seed state exposes zero or one enabled prominent action and Today CPU converges in English and Japanese.

- [ ] **Step 5: Commit**

```bash
git add Sources/SuisuiCore/App/TodayPrimaryActionPresentation.swift Sources/SuisuiApp/Views/ProjectWorkflowTodayView.swift Sources/SuisuiCore/App/ProjectBoard.swift Tests/SuisuiCoreTests/TodayPrimaryActionPresentationTests.swift Tests/SuisuiCoreTests/AppExperienceSourceTests.swift script/check_runtime_today_complete_smoke.sh
git commit -m "feat: focus Today on one primary action"
```

### Task 8: Make Settings readiness progressive and actionable

**Files:**
- Create: `Sources/SuisuiCore/App/SettingsReadinessPresentation.swift`
- Create: `Sources/SuisuiApp/Views/SettingsStatusOverviewView.swift`
- Modify: `Sources/SuisuiApp/Views/SettingsView.swift`
- Create: `Tests/SuisuiCoreTests/SettingsReadinessPresentationTests.swift`
- Modify: `Tests/SuisuiCoreTests/AppExperienceSourceTests.swift`
- Modify: `script/check_runtime_settings_save_smoke.sh`

- [ ] **Step 1: Write failing readiness classification tests**

```swift
func testOptionalUnconfiguredCapabilityIsNeutralUntilRequested() {
    let row = SettingsReadinessPresentation.optionalCapability(id: "mcp", title: "MCP", hasLoaded: false, failure: nil)
    XCTAssertEqual(row.state, .setupWhenNeeded)
    XCTAssertEqual(row.group, .setUpWhenUsed)
}

func testActualFailureNeedsAttention() {
    let row = SettingsReadinessPresentation.failedCapability(id: "calendar", title: "Calendar", redactedReason: "Authorization expired")
    XCTAssertEqual(row.state, .needsAction)
    XCTAssertEqual(row.group, .needsAttention)
}
```

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter SettingsReadinessPresentationTests`

Expected: compile failure because the presentation types do not exist.

- [ ] **Step 3: Implement typed readiness and grouped view**

```swift
public enum SettingsReadinessState: Equatable, Sendable {
    case ready, setupWhenNeeded, checking, needsAction, blocked, unsupported
}

public enum SettingsReadinessGroup: Int, CaseIterable, Sendable {
    case readyNow, setUpWhenUsed, needsAttention, advanced
}

public enum SettingsReadinessAction: Equatable, Sendable {
    case openAI
    case openPrivacy
    case showAdvanced
    case openMCP
    case openSync
    case retry(featureID: String)
}

public struct SettingsReadinessRow: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let state: SettingsReadinessState
    public let group: SettingsReadinessGroup
    public let action: SettingsReadinessAction?
}

public enum SettingsReadinessPresentation {
    public static func optionalCapability(id: String, title: String, hasLoaded: Bool, failure: String?) -> SettingsReadinessRow
    public static func failedCapability(id: String, title: String, redactedReason: String) -> SettingsReadinessRow
}
```

Replace the current `?? "Unavailable"` fallbacks with `.setupWhenNeeded`. Keep MCP/Sync lazy. Hide Advanced rows while Advanced is off. Route every actionable row directly to its tab/section.

- [ ] **Step 4: Verify Settings runtime and redaction**

Run:

```bash
swift test --filter SettingsReadinessPresentationTests
swift test --filter AppSettingsTests
swift test --filter AppExperienceSourceTests
./script/check_runtime_settings_save_smoke.sh
./script/check_security_regressions.sh
```

Expected: fresh settings show Ready/Set up groups without an orange warning wall; real failures remain actionable and redacted.

- [ ] **Step 5: Commit**

```bash
git add Sources/SuisuiCore/App/SettingsReadinessPresentation.swift Sources/SuisuiApp/Views/SettingsStatusOverviewView.swift Sources/SuisuiApp/Views/SettingsView.swift Tests/SuisuiCoreTests/SettingsReadinessPresentationTests.swift Tests/SuisuiCoreTests/AppExperienceSourceTests.swift script/check_runtime_settings_save_smoke.sh
git commit -m "feat: make Settings readiness progressive"
```

### Task 9: Make Voice empty state and capture modes truthful

**Files:**
- Modify: `Sources/SuisuiApp/Views/VoiceCaptureView.swift`
- Modify: `Sources/SuisuiCore/Voice/VoiceCaptureViewModel.swift`
- Modify: `Tests/SuisuiCoreTests/VoiceCaptureViewModelTests.swift`
- Modify: `Tests/SuisuiCoreTests/AppExperienceSourceTests.swift`
- Modify: `script/check_runtime_voice_review_smoke.sh`

- [ ] **Step 1: Write failing UI contract and interaction tests**

```swift
func testGeneratePlanRequiresAValidDraftInEveryIdleState() {
    let viewModel = makeViewModel()
    viewModel.updateDraftText("   \n")
    XCTAssertFalse(viewModel.canGeneratePlan)
    viewModel.updateDraftText("Plan the release")
    XCTAssertTrue(viewModel.canGeneratePlan)
}
```

Require the source to include `.disabled(!viewModel.canGeneratePlan ||` for the Generate Plan button and visible `Record once` / `Hands-free mode` labels.

- [ ] **Step 2: Run and verify RED**

Run:

```bash
swift test --filter VoiceCaptureViewModelTests
swift test --filter AppExperienceSourceTests
```

Expected: the view source contract fails because empty input is not part of the button's disabled condition.

- [ ] **Step 3: Use the ViewModel as the single readiness source**

Change the button gate to:

```swift
.disabled(
    !viewModel.canGeneratePlan
        || viewModel.phase == .generatingPlan
        || viewModel.phase == .recording
        || viewModel.phase == .transcribing
        || viewModel.isLowLatencyVoiceAgentListening
)
```

Label the hero control `Record once`. Rename the low-latency surface to `Hands-free mode`, add provider/privacy detail, and keep it secondary. Keep example chips input-only.

- [ ] **Step 4: Verify Voice runtime**

Run:

```bash
swift test --filter VoiceCaptureViewModelTests
swift test --filter AppExperienceSourceTests
./script/check_runtime_voice_review_smoke.sh
./script/check_accessibility_preflight.sh --source-only
```

Expected: whitespace keeps Generate Plan AXDisabled, valid input enables it, and plan review still reaches Assistant Queue without pre-approval writes.

- [ ] **Step 5: Commit**

```bash
git add Sources/SuisuiApp/Views/VoiceCaptureView.swift Sources/SuisuiCore/Voice/VoiceCaptureViewModel.swift Tests/SuisuiCoreTests/VoiceCaptureViewModelTests.swift Tests/SuisuiCoreTests/AppExperienceSourceTests.swift script/check_runtime_voice_review_smoke.sh
git commit -m "fix: make Voice actions and modes truthful"
```

### Task 10: Implement the process-wide global Voice shortcut

**Files:**
- Create: `Sources/SuisuiApp/Adapters/SystemShortcutClient.swift`
- Modify: `Sources/SuisuiCore/Shortcuts/ShortcutRegistration.swift`
- Modify: `Sources/SuisuiApp/SuisuiApp.swift`
- Modify: `Sources/SuisuiApp/Views/SettingsView.swift`
- Modify: `Sources/SuisuiApp/Views/MenuBarPanel.swift`
- Modify: `Tests/SuisuiCoreTests/ShortcutRegistrationTests.swift`
- Modify: `Tests/SuisuiCoreTests/LaunchExperienceTests.swift`
- Modify: `docs/adr/0003-global-shortcut-library.md`

- [ ] **Step 1: Write failing lifecycle tests**

```swift
func testRegisterIsIdempotentAndHandlerOpensOnce() async {
    let client = ShortcutTestClient()
    let model = ShortcutSettingsViewModel(client: client)
    await model.register()
    await model.register()
    client.trigger()
    XCTAssertEqual(client.registerCallCount, 1)
    XCTAssertEqual(client.handlerCallCount, 1)
}

func testConflictKeepsInAppFallbackVisible() async {
    let model = ShortcutSettingsViewModel(client: ShortcutTestClient(result: .conflict("Already in use")))
    await model.register()
    XCTAssertEqual(model.state.status, .conflict)
}
```

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter ShortcutRegistrationTests`

Expected: missing idempotent production lifecycle or state assertions fail.

- [ ] **Step 3: Implement the App-target adapter and app-level ownership**

Use Carbon `RegisterEventHotKey` behind `SystemShortcutClient` so the app listens only for Option+Space and does not require arbitrary keyboard monitoring. Store the registration token once at app composition scope, unregister on deinit/disable, and dispatch the handler to `MainActor` to activate the existing Voice window.

Settings displays Registered/Not registered/Conflict/Unavailable from `ShortcutRegistrationState`, plus `Shift+Command+V` fallback. Menu Bar no longer implies its local shortcut is global.

- [ ] **Step 4: Verify lifecycle and security**

Run:

```bash
swift test --filter ShortcutRegistrationTests
swift test --filter LaunchExperienceTests
swift test --filter AppExperienceSourceTests
./script/check_security_regressions.sh
```

Expected: duplicate registration and duplicate windows are impossible in unit/composition tests; no Input Monitoring entitlement is added.

- [ ] **Step 5: Commit**

```bash
git add Sources/SuisuiApp/Adapters/SystemShortcutClient.swift Sources/SuisuiCore/Shortcuts/ShortcutRegistration.swift Sources/SuisuiApp/SuisuiApp.swift Sources/SuisuiApp/Views/SettingsView.swift Sources/SuisuiApp/Views/MenuBarPanel.swift Tests/SuisuiCoreTests/ShortcutRegistrationTests.swift Tests/SuisuiCoreTests/LaunchExperienceTests.swift docs/adr/0003-global-shortcut-library.md
git commit -m "feat: register global Voice shortcut"
```

### Task 11: Expand the Calm Signal Desk semantic design system

**Files:**
- Modify: `Sources/SuisuiApp/Views/SuisuiDesignSystem.swift`
- Modify: `docs/ux/design-system.md`
- Create: `Tests/SuisuiCoreTests/SuisuiDesignTokenContractTests.swift`
- Modify: `Tests/SuisuiCoreTests/AppExperienceSourceTests.swift`

- [ ] **Step 1: Write failing token contracts**

```swift
func testDesignSystemDefinesEveryApprovedSemanticLayer() throws {
    let source = try readSource("Sources/SuisuiApp/Views/SuisuiDesignSystem.swift")
    for symbol in ["SuisuiBrand", "SuisuiTypography", "SuisuiSurface", "SuisuiBorder", "SuisuiMotion", "SuisuiIconMetrics", "SuisuiControlDensity"] {
        XCTAssertTrue(source.contains("enum \(symbol)"), "Missing \(symbol)")
    }
}
```

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter SuisuiDesignTokenContractTests`

Expected: missing semantic-layer assertions fail.

- [ ] **Step 3: Implement semantic tokens and modifiers**

Define adaptive brand colors through `Color(nsColor:)` or asset-backed semantic colors; typography as concrete SwiftUI `Font` values; surfaces as semantic `ShapeStyle`; borders, motion duration/animation with Reduce Motion fallback; and icon/control metrics. Add `soloAssistantSignal()` and keep `soloCard()` solid/adaptive.

Do not apply custom backgrounds to native sidebar, toolbar, Form, or Inspector roots. Add a source guard for new raw status colors/radii in migrated files.

- [ ] **Step 4: Verify tokens and both appearances**

Run:

```bash
swift test --filter SuisuiDesignTokenContractTests
swift test --filter AppExperienceSourceTests
swift build
```

Expected: contracts pass and the app builds for the macOS 14 deployment target.

- [ ] **Step 5: Commit**

```bash
git add Sources/SuisuiApp/Views/SuisuiDesignSystem.swift docs/ux/design-system.md Tests/SuisuiCoreTests/SuisuiDesignTokenContractTests.swift Tests/SuisuiCoreTests/AppExperienceSourceTests.swift
git commit -m "feat: expand semantic Suisui design tokens"
```

### Task 12: Migrate product surfaces to semantic styling and non-color cues

**Files:**
- Modify: `Sources/SuisuiApp/Views/ProjectWorkflowTodayView.swift`
- Modify: `Sources/SuisuiApp/Views/ProjectWorkflowScheduleView.swift`
- Modify: `Sources/SuisuiApp/Views/ProjectWorkflowDoneView.swift`
- Modify: `Sources/SuisuiApp/Views/ProjectBoardReviewHubView.swift`
- Modify: `Sources/SuisuiApp/Views/SettingsStatusOverviewView.swift`
- Modify: `Sources/SuisuiApp/Views/VoiceCaptureView.swift`
- Modify: `Tests/SuisuiCoreTests/AppExperienceSourceTests.swift`

- [ ] **Step 1: Add failing migrated-surface guards**

For the listed files, reject newly introduced raw `.red`, `.orange`, `.green`, numeric `cornerRadius`, and anonymous grouped fills except an explicit legacy allowlist. Require status labels to include an icon and visible state text.

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter AppExperienceSourceTests`

Expected: current raw constants fail the narrowed migrated-surface contracts.

- [ ] **Step 3: Replace raw styling with semantic tokens**

Use `SuisuiTypography`, `SuisuiSurface`, `SuisuiBorder`, `SuisuiMotion`, and `SuisuiTone` consistently. Apply Signal Amber only to assistant attention, never to ordinary selection or decoration. Use icon + label + shape for attention/danger/positive states. Respect `accessibilityReduceMotion` for all new transitions.

- [ ] **Step 4: Verify build and accessibility source floor**

Run:

```bash
swift test --filter AppExperienceSourceTests
./script/check_accessibility_preflight.sh --source-only
swift build
```

Expected: no new raw styling violations, no lost AX anchors, and Light/Dark adaptive styles compile.

- [ ] **Step 5: Commit**

```bash
git add Sources/SuisuiApp/Views/ProjectWorkflowTodayView.swift Sources/SuisuiApp/Views/ProjectWorkflowScheduleView.swift Sources/SuisuiApp/Views/ProjectWorkflowDoneView.swift Sources/SuisuiApp/Views/ProjectBoardReviewHubView.swift Sources/SuisuiApp/Views/SettingsStatusOverviewView.swift Sources/SuisuiApp/Views/VoiceCaptureView.swift Tests/SuisuiCoreTests/AppExperienceSourceTests.swift
git commit -m "refactor: apply calm signal surface styling"
```

### Task 13: Keep recoverable failures inline and validate due dates

**Files:**
- Create: `Sources/SuisuiCore/App/ProjectBoardErrorPresentation.swift`
- Create: `Sources/SuisuiCore/App/TaskDueDateFieldState.swift`
- Modify: `Sources/SuisuiApp/Views/ProjectBoardView.swift`
- Create: `Tests/SuisuiCoreTests/ProjectBoardErrorPresentationTests.swift`
- Create: `Tests/SuisuiCoreTests/TaskDueDateFieldStateTests.swift`
- Modify: `script/check_runtime_accessible_crud_smoke.sh`

- [ ] **Step 1: Write failing error/date tests**

```swift
func testRecoverableSaveErrorKeepsContentVisible() {
    XCTAssertEqual(ProjectBoardErrorPresentation.classify(.saveFailed("Disk busy")), .inline(message: "Disk busy", canRetry: true))
}

func testDueDateCanBeSetAndClearedWithoutFreeFormParsing() {
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    XCTAssertEqual(TaskDueDateFieldState.value(date).persistedDate, date)
    XCTAssertNil(TaskDueDateFieldState.empty.persistedDate)
}
```

- [ ] **Step 2: Run and verify RED**

Run:

```bash
swift test --filter ProjectBoardErrorPresentationTests
swift test --filter TaskDueDateFieldStateTests
```

Expected: compile failures for both missing types.

- [ ] **Step 3: Implement typed policies and native date controls**

Fatal load failures may show `ContentUnavailableView`. Save/check/provider/mutation failures render an inline `Label`, redacted message, and Retry next to the originating control while keeping board content mounted.

Define the input failure vocabulary explicitly:

```swift
public enum ProjectBoardFailure: Equatable, Sendable {
    case initialLoadFailed(String)
    case saveFailed(String)
    case providerFailed(String)
    case readinessCheckFailed(String)
}

public enum ProjectBoardErrorPresentation: Equatable, Sendable {
    case fatal(message: String, canRetry: Bool)
    case inline(message: String, canRetry: Bool)

    public static func classify(_ failure: ProjectBoardFailure) -> Self
}

public enum TaskDueDateFieldState: Equatable, Sendable {
    case empty
    case value(Date)

    public var persistedDate: Date? {
        switch self {
        case .empty: nil
        case .value(let date): date
        }
    }
}
```

Use a `DatePicker` plus explicit `Clear due date`; persist only `Date?`. Do not parse inspector free-form text. Keep Quick Add natural-language parsing separate.

- [ ] **Step 4: Verify DB postconditions**

Run:

```bash
swift test --filter ProjectBoardErrorPresentationTests
swift test --filter TaskDueDateFieldStateTests
./script/check_runtime_accessible_crud_smoke.sh
```

Expected: injected recoverable failure leaves context visible; valid date and clear update SQLite; cancelled/invalid interaction does not mutate it.

- [ ] **Step 5: Commit**

```bash
git add Sources/SuisuiCore/App/ProjectBoardErrorPresentation.swift Sources/SuisuiCore/App/TaskDueDateFieldState.swift Sources/SuisuiApp/Views/ProjectBoardView.swift Tests/SuisuiCoreTests/ProjectBoardErrorPresentationTests.swift Tests/SuisuiCoreTests/TaskDueDateFieldStateTests.swift script/check_runtime_accessible_crud_smoke.sh
git commit -m "fix: keep board errors inline and dates valid"
```

### Task 14: Make onboarding experience-first

**Files:**
- Create: `Sources/SuisuiCore/App/OnboardingExperience.swift`
- Modify: `Sources/SuisuiCore/App/FirstRunOnboarding.swift`
- Modify: `Sources/SuisuiApp/Views/OnboardingWelcomeView.swift`
- Modify: `Sources/SuisuiApp/OnboardingSampleProjectFactory.swift`
- Modify: `Sources/SuisuiApp/SuisuiApp.swift`
- Create: `Tests/SuisuiCoreTests/OnboardingExperienceTests.swift`
- Modify: `Tests/SuisuiCoreTests/FirstRunOnboardingTests.swift`
- Modify: `Tests/SuisuiCoreTests/FirstRunOnboardingSampleTests.swift`
- Create: `script/check_runtime_onboarding_smoke.sh`

- [ ] **Step 1: Write failing first-value-path tests**

```swift
func testWelcomeDefaultsToLocalExperienceWithoutProviderOrPermissions() {
    let experience = OnboardingExperience.initial
    XCTAssertEqual(experience.primaryAction, .trySuisui)
    XCTAssertEqual(experience.secondaryAction, .setUpAI)
    XCTAssertEqual(experience.requestedPermissions, [])
}

func testLearnProjectRoutesToTodayAndIsIdempotent() {
    XCTAssertEqual(OnboardingExperience.learnProjectTargetRoute, .primary(.today))
}
```

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter OnboardingExperienceTests`

Expected: compile failure for the missing experience model.

- [ ] **Step 3: Implement Welcome → Try → contextual setup**

```swift
public struct OnboardingExperience: Equatable, Sendable {
    public enum Action: Equatable, Sendable { case trySuisui, setUpAI, skip }
    public static let initial = OnboardingExperience(primaryAction: .trySuisui, secondaryAction: .setUpAI, requestedPermissions: [])
    public static let learnProjectTargetRoute: BoardRoute = .primary(.today)
    public let primaryAction: Action
    public let secondaryAction: Action
    public let requestedPermissions: Set<AppPermission>
}
```

Reuse the existing transactional/idempotent six-task sample creator. After successful creation, route to Today and highlight the first lesson. Ask for AI/microphone/calendar only when the user chooses the corresponding capability. Keep Skip and Settings rerun.

- [ ] **Step 4: Verify onboarding and rollback**

Run:

```bash
swift test --filter OnboardingExperienceTests
swift test --filter FirstRunOnboardingTests
swift test --filter FirstRunOnboardingSampleTests
./script/check_runtime_onboarding_smoke.sh
```

Expected: fresh isolated HOME can create Learn Suisui, reach Today, complete one lesson, rerun without duplication, skip without data loss, and rollback an injected creation failure.

Make the new verifier executable before running it: `chmod +x script/check_runtime_onboarding_smoke.sh`.

- [ ] **Step 5: Commit**

```bash
git add Sources/SuisuiCore/App/OnboardingExperience.swift Sources/SuisuiCore/App/FirstRunOnboarding.swift Sources/SuisuiApp/Views/OnboardingWelcomeView.swift Sources/SuisuiApp/OnboardingSampleProjectFactory.swift Sources/SuisuiApp/SuisuiApp.swift Tests/SuisuiCoreTests/OnboardingExperienceTests.swift Tests/SuisuiCoreTests/FirstRunOnboardingTests.swift Tests/SuisuiCoreTests/FirstRunOnboardingSampleTests.swift script/check_runtime_onboarding_smoke.sh
git commit -m "feat: make onboarding experience first"
```

### Task 15: Split oversized leaf views while retaining root ownership

**Files:**
- Create: `Sources/SuisuiApp/Views/ProjectBoardInspectors.swift`
- Create: `Sources/SuisuiApp/Views/ProjectBoardDetailViews.swift`
- Create: `Sources/SuisuiApp/Views/SettingsFeatureViews.swift`
- Modify: `Sources/SuisuiApp/Views/ProjectBoardView.swift`
- Modify: `Sources/SuisuiApp/Views/SettingsView.swift`
- Modify: `Tests/SuisuiCoreTests/ArchitectureBoundaryTests.swift`
- Modify: `Tests/SuisuiCoreTests/AppExperienceSourceTests.swift`

- [ ] **Step 1: Write failing ownership contracts**

Require `ProjectBoardView.swift` to own `@StateObject ProjectBoardViewModel`, `NavigationSplitView`, Inspector binding, and sheets, while rejecting embedded declarations for `TaskInspectorView`, `ProjectInspectorView`, project portfolio, and kanban leaf views. Require `SettingsView.swift` to own state objects and tab selection while leaf tab views live outside it.

- [ ] **Step 2: Run and verify RED**

Run:

```bash
swift test --filter ArchitectureBoundaryTests
swift test --filter AppExperienceSourceTests
```

Expected: monolithic files violate the new boundaries.

- [ ] **Step 3: Move leaf declarations without changing state ownership**

Pass immutable values, `Binding`, and explicit closures into extracted internal views. Do not make them public, add new stores, change SQLite ownership, or convert all observation APIs. Keep `ProjectBoardViewModel` as the compatibility facade; introduce Today feature-scoped observation only where Task 7 already needs it.

- [ ] **Step 4: Verify architecture and behavior**

Run:

```bash
swift test --filter ArchitectureBoundaryTests
swift test --filter AppExperienceSourceTests
swift test --filter ProjectBoardStoreTests
swift build
./script/check_runtime_accessible_crud_smoke.sh
```

Expected: extracted views compile, CRUD/approval/receipt behavior is unchanged, and source contracts no longer depend on one file.

- [ ] **Step 5: Commit**

```bash
git add Sources/SuisuiApp/Views/ProjectBoardInspectors.swift Sources/SuisuiApp/Views/ProjectBoardDetailViews.swift Sources/SuisuiApp/Views/SettingsFeatureViews.swift Sources/SuisuiApp/Views/ProjectBoardView.swift Sources/SuisuiApp/Views/SettingsView.swift Tests/SuisuiCoreTests/ArchitectureBoundaryTests.swift Tests/SuisuiCoreTests/AppExperienceSourceTests.swift
git commit -m "refactor: split board and Settings leaf views"
```

### Task 16: Isolate Today observation and invalidation

**Files:**
- Create: `Sources/SuisuiCore/App/TodayFeatureModel.swift`
- Modify: `Sources/SuisuiCore/App/ProjectBoard.swift`
- Modify: `Sources/SuisuiApp/Views/ProjectWorkflowTodayView.swift`
- Create: `Tests/SuisuiCoreTests/TodayFeatureModelTests.swift`
- Modify: `Tests/SuisuiCoreTests/ProjectBoardStoreTests.swift`
- Modify: `Tests/SuisuiCoreTests/ArchitectureBoundaryTests.swift`

- [ ] **Step 1: Write failing observation-boundary tests**

```swift
@MainActor
func testTodayPublishesOnceForTaskMutationAndNeverForUnrelatedReceiptRefresh() async {
    let harness = TodayFeatureModelHarness()
    var publications = 0
    let cancellable = harness.model.objectWillChange.sink { publications += 1 }
    await harness.mutateTask()
    XCTAssertEqual(publications, 1)
    await harness.refreshReceiptOnly()
    XCTAssertEqual(publications, 1)
    withExtendedLifetime(cancellable) {}
}
```

Add a source contract requiring `ProjectWorkflowTodayView` to observe `TodayFeatureModel` instead of the entire `ProjectBoardViewModel`.

- [ ] **Step 2: Run and verify RED**

Run:

```bash
swift test --filter TodayFeatureModelTests
swift test --filter ArchitectureBoundaryTests
```

Expected: compile failure for the missing feature model and an ownership failure in the Today view.

- [ ] **Step 3: Implement a feature-scoped state and closure-based actions**

```swift
public struct TodayFeatureState: Equatable, Sendable {
    public let snapshot: TodayWorkflowSnapshot
    public let showsCompletedTasks: Bool
    public let focusTaskID: Int64?
    public let sourceRevision: Int
}

public struct TodayFeatureActions: Sendable {
    public let submitCommand: @Sendable (String) async -> Void
    public let startFocus: @Sendable (Int64) async -> Void
    public let prepareScheduleDraft: @Sendable () async -> Void
}

@MainActor
public final class TodayFeatureModel: ObservableObject {
    @Published public private(set) var state: TodayFeatureState
    public let actions: TodayFeatureActions
}
```

Keep one Project Board store owner. `ProjectBoardViewModel` remains the compatibility facade and explicitly invalidates Today only after Today-relevant mutations. Receipt, MCP, and project-automation-only refreshes must not publish Today state.

- [ ] **Step 4: Verify observation and runtime performance**

Run:

```bash
swift test --filter TodayFeatureModelTests
swift test --filter ProjectBoardStoreTests
swift test --filter ArchitectureBoundaryTests
./script/check_runtime_today_production_route_smoke.sh
```

Expected: publication counts match the tests and normal Today reaches CPU convergence.

- [ ] **Step 5: Commit**

```bash
git add Sources/SuisuiCore/App/TodayFeatureModel.swift Sources/SuisuiCore/App/ProjectBoard.swift Sources/SuisuiApp/Views/ProjectWorkflowTodayView.swift Tests/SuisuiCoreTests/TodayFeatureModelTests.swift Tests/SuisuiCoreTests/ProjectBoardStoreTests.swift Tests/SuisuiCoreTests/ArchitectureBoundaryTests.swift
git commit -m "refactor: isolate Today feature observation"
```

### Task 17: Require complete product runtime and visual evidence

**Files:**
- Modify: `scripts/ci.sh`
- Modify: `.github/workflows/ci.yml`
- Modify: `script/check_ci_visual_gate.sh`
- Modify: `docs/quality/visual-baseline-manifest.json`
- Modify: `Tests/SuisuiCoreTests/CIGateWorkflowTests.swift`
- Modify: `Tests/SuisuiCoreTests/ReleasePipelineTests.swift`
- Modify: `docs/quality/regression-risk-map.md`

- [ ] **Step 1: Write failing workflow contracts**

Require the UI runtime lane to call Inbox triage, Settings save, Voice review, Schedule cockpit, onboarding, accessible CRUD, layout stability, and Today production-route smokes. Require UI visual/performance jobs on trusted PR branches, main, and release; every job must upload sanitized artifacts and distinguish runner capability, app regression, visual diff, and budget failure.

- [ ] **Step 2: Run and verify RED**

Run:

```bash
swift test --filter CIGateWorkflowTests
swift test --filter ReleasePipelineTests
```

Expected: current runtime lane omits the individual product smokes and current visual manifest omits new surfaces.

- [ ] **Step 3: Expand lanes and deterministic fixtures**

Update `run_runtime_gates` or split required lanes so each product smoke runs without real credentials. Before adding Settings/Voice/Schedule scripts, replace `pkill -x`/`pgrep -x` with owned launch PID and owned binary verification. Extend visual manifest with `appearance`, `locale`, `viewport`, `seedState`, and `axTargetIdentifier` per artifact, covering Review sections, Onboarding welcome/learn/deferred setup, Japanese 1024 Today/Review/Voice/Settings, compact Inspector, Settings readiness states, and Voice empty/review/hands-free states. Remove the hardcoded screenshot count of 33 and derive exact PNG/metadata/AX receipt counts from the manifest. Keep fork PRs secretless and never execute PR code through `pull_request_target`.

- [ ] **Step 4: Verify all automated lanes**

Run:

```bash
./scripts/ci.sh swiftpm
swift test
./script/check_security_regressions.sh
./scripts/ci.sh ui-runtime
./scripts/ci.sh ui-visual
./scripts/ci.sh ui-performance
```

Expected: every command exits 0, runtime artifacts are sanitized, normal-route captures match reviewed baselines, and Today/launch budgets pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/ci.sh .github/workflows/ci.yml script/check_ci_visual_gate.sh docs/quality/visual-baseline-manifest.json Tests/SuisuiCoreTests/CIGateWorkflowTests.swift Tests/SuisuiCoreTests/ReleasePipelineTests.swift docs/quality/regression-risk-map.md docs/quality/visual-baselines
git commit -m "test: require complete product UI evidence"
```

### Task 18: Complete localization, focus accessibility, and manual evidence

**Files:**
- Modify: `Sources/SuisuiApp/Resources/en.lproj/Localizable.strings`
- Modify: `Sources/SuisuiApp/Resources/ja.lproj/Localizable.strings`
- Create: `Sources/SuisuiCore/App/AccessibilityFocusPathAudit.swift`
- Create: `Tests/SuisuiCoreTests/AccessibilityFocusPathAuditTests.swift`
- Modify: `script/check_accessibility_preflight.sh`
- Modify: `docs/release/evidence/accessibility-voiceover.md`
- Modify: `docs/quality/status.md`
- Modify: `docs/product/roadmap.md`
- Modify: `docs/ux/information-architecture.md`

- [ ] **Step 1: Add failing localization/fresh-evidence checks**

Add dynamic placeholder arity/type parity for the new route/readiness/Voice/Onboarding strings. Define an automated focus-path vocabulary and require every step to resolve to one AX identifier:

```swift
public enum AccessibilityFocusPath: String, CaseIterable, Sendable {
    case todayPrimaryAction
    case reviewAssistantQueue
    case voiceRecordOnce
    case voiceHandsFree
    case settingsReadiness
    case onboardingTrySuisui
    case inlineErrorRetry
    case taskDueDate
}

public enum AccessibilityFocusPathAudit {
    public static func requiredIdentifiers(for path: AccessibilityFocusPath) -> [String]
}
```

Require VoiceOver and quality evidence source commits to match the release-candidate source commit, and require focus notes for four primary areas, Review sections, both Voice modes, Settings groups, inline errors, due date, and onboarding.

- [ ] **Step 2: Run and verify RED**

Run:

```bash
swift test --filter AppExperienceSourceTests
swift test --filter AccessibilityFocusPathAuditTests
swift test --filter ReleasePipelineTests
./script/check_accessibility_preflight.sh --source-only
```

Expected: missing localized keys or stale evidence is reported explicitly.

- [ ] **Step 3: Finish localization and record fresh manual evidence**

Add English/Japanese keys with matching placeholders. Use the release helper to prepare a clean candidate, then run real VoiceOver through all required focus paths and generate evidence with `create_voiceover_evidence.sh --passed --capture-runtime-ax-smoke`. Record actual reviewer/date/source/environment and concrete observations; do not fabricate or reuse stale evidence.

Update IA, design, roadmap, and quality status to match the implemented product. Keep signing, notarization, credentials, and competitor hands-on as external blockers unless genuinely completed.

- [ ] **Step 4: Run final completion audit**

Run:

```bash
git diff --check
./scripts/ci.sh swiftpm
swift test
./script/check_security_regressions.sh
./scripts/ci.sh ui-runtime
./scripts/ci.sh ui-visual
./scripts/ci.sh ui-performance
./script/release_readiness_report.sh
git status --short --branch
```

Expected: all automatable gates pass; release readiness reports only genuinely external/manual blockers or `READY`; worktree is clean after evidence commits.

- [ ] **Step 5: Commit and push current evidence**

```bash
git add Sources/SuisuiApp/Resources/en.lproj/Localizable.strings Sources/SuisuiApp/Resources/ja.lproj/Localizable.strings Sources/SuisuiCore/App/AccessibilityFocusPathAudit.swift Tests/SuisuiCoreTests/AccessibilityFocusPathAuditTests.swift script/check_accessibility_preflight.sh docs/release/evidence/accessibility-voiceover.md docs/quality/status.md docs/product/roadmap.md docs/ux/information-architecture.md
git commit -m "docs: close product experience evidence"
git push -u origin feature/product-experience-renewal
```

### Task 19: Create the PR, require checks, merge, and clean branches

**External state:**
- GitHub PR from `feature/product-experience-renewal` to `main`
- GitHub branch protection for `main`
- Local and remote feature branch cleanup after merge

- [ ] **Step 1: Create a complete PR body and open the PR**

Use `apply_patch` to create `.tmp/product-experience-renewal-pr.md` with these populated sections and actual observed evidence: Why, Before, After, Architecture Decisions, Legacy Route Migration, Preserved Safety Boundaries, Accessibility Identifier Migration, Tests, Runtime, Visual, Performance, Security, Manual VoiceOver, Release-only Blockers. Do not leave bracketed values or unchecked boxes.

Run:

```bash
gh pr create --base main --head feature/product-experience-renewal --title "feat: renew Suisui product experience around four daily workflows" --body-file .tmp/product-experience-renewal-pr.md
```

Expected: a new open PR URL targeting `main`.

- [ ] **Step 2: Wait for all checks and resolve review threads**

Run:

```bash
gh pr checks --watch
gh pr view --json mergeable,mergeStateStatus,reviews,statusCheckRollup
```

Use GitHub GraphQL to confirm unresolved review thread count is zero. Fix valid findings with focused RED→GREEN commits and repeat all affected gates.

- [ ] **Step 3: Configure required main checks after all five names exist**

Apply branch protection with `strict=true`, `enforce_admins=true`, conversation resolution, and these contexts: `SwiftPM macOS`, `Quality Contracts`, `UI Runtime (production route)`, `UI Visual (live baseline)`, `UI Performance (production route)`. Set approving review count to `0` so a single-owner repository cannot self-deadlock; keep unresolved conversations blocking.

Run:

```bash
gh api --method PUT repos/albert-einshutoin/suisui/branches/main/protection --input - <<'JSON'
{
  "required_status_checks": {
    "strict": true,
    "contexts": [
      "SwiftPM macOS",
      "Quality Contracts",
      "UI Runtime (production route)",
      "UI Visual (live baseline)",
      "UI Performance (production route)"
    ]
  },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": false,
    "required_approving_review_count": 0,
    "require_last_push_approval": false
  },
  "restrictions": null,
  "required_conversation_resolution": true,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "block_creations": false,
  "required_linear_history": false,
  "lock_branch": false,
  "allow_fork_syncing": true
}
JSON
gh api repos/albert-einshutoin/suisui/branches/main/protection
```

Expected: the response contains the exact five required contexts, strict checks, admin enforcement, and conversation resolution.

- [ ] **Step 4: Merge only after the completion audit passes**

Run:

```bash
gh pr merge --merge --delete-branch
git switch main
git pull --ff-only
```

Expected: PR state `MERGED`, local `main` equals `origin/main`, and the remote feature branch is absent.

- [ ] **Step 5: Clean local/remote branch state and verify**

Run:

```bash
git branch -d feature/product-experience-renewal
git fetch --prune
git worktree prune
git status --short --branch
git ls-remote --heads origin feature/product-experience-renewal
```

Expected: local/remote feature branch absent, no stale worktree metadata, and clean `main` tracking `origin/main`.
