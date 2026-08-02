# Today Sidebar Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `ui-samples/today.png`に合わせたブランド付き7項目サイドバーと3つのクイックアクションを、既存Suisuiの型付きroute・承認境界・アクセシビリティを維持して実装する。

**Architecture:** Coreへ純粋なsidebar presentation policyを追加し、7項目の順序・SF Symbols・route/action種別・routeからの選択解決を一か所で管理する。SwiftUI sidebarはそのpolicyを描画し、ProjectBoardViewからcommand palette、Voice Command、Settings、Inbox focus、Schedule draftの既存handlerを注入する。

**Tech Stack:** Swift 6、SwiftUI、AppKit、Swift Package Manager、XCTest、macOS Accessibility、Suisui visual evidence scripts

---

## File Structure

### Create

- `Sources/SuisuiCore/App/ProjectBoardSidebarPresentation.swift`
  - 7項目と3 quick actionsの型、順序、label、SF Symbol、behavior、selected-row解決を所有する。
- `Tests/SuisuiCoreTests/ProjectBoardSidebarPresentationTests.swift`
  - presentation policyをSwiftUIなしで網羅する。
- `docs/superpowers/plans/2026-08-02-today-sidebar-parity.md`
  - 本計画。

### Modify

- `Sources/SuisuiApp/Views/ProjectBoardSidebarView.swift`
  - app brand、Search、7 rows、selected styling、counts、quick actionsを描画する。
- `Sources/SuisuiApp/Views/ProjectBoardView.swift`
  - sidebarへ既存機能のhandlerを注入し、Inbox focus intentとSchedule draft作成を所有する。
- `Sources/SuisuiApp/Views/ProjectWorkflowInboxView.swift`
  - Add Task quick actionをInbox quick-add fieldのfocusへ一度だけ消費する。
- `Sources/SuisuiApp/Resources/en.lproj/Localizable.strings`
  - 新しいvisible / AX文字列の英語source entriesを追加する。
- `Sources/SuisuiApp/Resources/ja.lproj/Localizable.strings`
  - 同じkeyの日本語訳を追加する。
- `Tests/SuisuiCoreTests/AppExperienceSourceTests.swift`
  - 古い4-row source contractを、4 primary routesを維持した7 visible rows contractへ移行する。
- `script/check_layout_stability_smoke.sh`
  - Review row前提のclick pathをSchedule / Completed rowsへ移行する。
- `script/check_release_launch_performance_smoke.sh`
  - Review destination benchmarkをSchedule destination benchmarkへ移行する。
- `script/check_runtime_today_production_route_smoke.sh`
  - routeごとのsidebar markerを新しいIAへ更新する。
- `Tests/SuisuiCoreTests/ReleasePipelineTests.swift`
  - 上記script contractの期待値を更新する。
- `docs/superpowers/specs/2026-08-02-today-sidebar-parity-design.md`
  - 実装完了時にstatusと検証結果を追記する。
- `docs/quality/visual-baseline-manifest.json`
- `docs/quality/visual-baseline-manifest-ja.json`
- `docs/quality/visual-baseline-manifest-apple-virtual.json`
- `docs/quality/visual-baseline-manifest-ja-apple-virtual.json`
- `docs/quality/visual-baselines/`
- `docs/quality/visual-baselines-ja/`
- `docs/quality/visual-baselines-apple-virtual/`
- `docs/quality/visual-baselines-ja-apple-virtual/`
  - source commitを固定した後、各manifestの`project-board`と`today` artifactだけを更新する。

## Task 1: Pure Sidebar Presentation Policy

**Files:**
- Create: `Sources/SuisuiCore/App/ProjectBoardSidebarPresentation.swift`
- Create: `Tests/SuisuiCoreTests/ProjectBoardSidebarPresentationTests.swift`

- [x] **Step 1: Write failing ordering and semantics tests**

```swift
@testable import SuisuiCore
import XCTest

final class ProjectBoardSidebarPresentationTests: XCTestCase {
    func testItemsMatchApprovedSevenItemOrderAndSymbols() {
        XCTAssertEqual(
            ProjectBoardSidebarPresentation.items,
            [
                .init(id: .inbox, title: "Inbox", systemImage: "tray", behavior: .route(.primary(.inbox))),
                .init(id: .today, title: "Today", systemImage: "sun.max", behavior: .route(.primary(.today))),
                .init(id: .projects, title: "Projects", systemImage: "folder", behavior: .route(.primary(.projects))),
                .init(id: .schedule, title: "Schedule", systemImage: "calendar", behavior: .route(.review(.schedule))),
                .init(id: .completed, title: "Completed", systemImage: "checkmark.circle", behavior: .route(.review(.completed))),
                .init(id: .voiceCommand, title: "Voice Command", systemImage: "mic", behavior: .openVoiceCommand),
                .init(id: .settings, title: "Settings", systemImage: "gearshape", behavior: .openSettings),
            ]
        )
    }

    func testQuickActionsMatchApprovedOrderAndSymbols() {
        XCTAssertEqual(
            ProjectBoardSidebarQuickAction.allCases,
            [.addTask, .addByVoice, .blockTime]
        )
        XCTAssertEqual(ProjectBoardSidebarQuickAction.addTask.systemImage, "plus.circle")
        XCTAssertEqual(ProjectBoardSidebarQuickAction.addByVoice.systemImage, "mic.circle")
        XCTAssertEqual(ProjectBoardSidebarQuickAction.blockTime.systemImage, "calendar.badge.clock")
    }

    func testRouteSelectionMapsOnlyOwnedDestinations() {
        XCTAssertEqual(ProjectBoardSidebarPresentation.selectedItemID(for: .primary(.inbox)), .inbox)
        XCTAssertEqual(ProjectBoardSidebarPresentation.selectedItemID(for: .primary(.today)), .today)
        XCTAssertEqual(ProjectBoardSidebarPresentation.selectedItemID(for: .primary(.projects)), .projects)
        XCTAssertEqual(ProjectBoardSidebarPresentation.selectedItemID(for: .project(42)), .projects)
        XCTAssertEqual(ProjectBoardSidebarPresentation.selectedItemID(for: .smartList("urgent")), .projects)
        XCTAssertEqual(ProjectBoardSidebarPresentation.selectedItemID(for: .review(.schedule)), .schedule)
        XCTAssertEqual(ProjectBoardSidebarPresentation.selectedItemID(for: .review(.completed)), .completed)
    }

    func testUnrepresentedReviewRoutesFailClosedWithoutSelection() {
        XCTAssertNil(ProjectBoardSidebarPresentation.selectedItemID(for: .primary(.review)))
        XCTAssertNil(ProjectBoardSidebarPresentation.selectedItemID(for: .review(.automationActivity)))
        XCTAssertNil(ProjectBoardSidebarPresentation.selectedItemID(for: .review(.assistantQueue)))
    }
}
```

- [x] **Step 2: Run the tests and verify the new types are missing**

Run:

```bash
swift test --filter ProjectBoardSidebarPresentationTests
```

Expected: FAIL with `cannot find 'ProjectBoardSidebarPresentation' in scope`.

- [x] **Step 3: Add the minimal presentation types**

```swift
import Foundation

public enum ProjectBoardSidebarItemID: String, CaseIterable, Hashable, Sendable {
    case inbox
    case today
    case projects
    case schedule
    case completed
    case voiceCommand
    case settings
}

public enum ProjectBoardSidebarItemBehavior: Equatable, Sendable {
    case route(BoardRoute)
    case openVoiceCommand
    case openSettings
}

public struct ProjectBoardSidebarItemPresentation: Equatable, Sendable {
    public let id: ProjectBoardSidebarItemID
    public let title: String
    public let systemImage: String
    public let behavior: ProjectBoardSidebarItemBehavior

    public init(
        id: ProjectBoardSidebarItemID,
        title: String,
        systemImage: String,
        behavior: ProjectBoardSidebarItemBehavior
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.behavior = behavior
    }
}

public enum ProjectBoardSidebarQuickAction: String, CaseIterable, Hashable, Sendable {
    case addTask
    case addByVoice
    case blockTime

    public var title: String {
        switch self {
        case .addTask: "Add Task"
        case .addByVoice: "Add by Voice"
        case .blockTime: "Block Time"
        }
    }

    public var systemImage: String {
        switch self {
        case .addTask: "plus.circle"
        case .addByVoice: "mic.circle"
        case .blockTime: "calendar.badge.clock"
        }
    }
}

public enum ProjectBoardSidebarPresentation {
    public static let items: [ProjectBoardSidebarItemPresentation] = [
        .init(id: .inbox, title: "Inbox", systemImage: "tray", behavior: .route(.primary(.inbox))),
        .init(id: .today, title: "Today", systemImage: "sun.max", behavior: .route(.primary(.today))),
        .init(id: .projects, title: "Projects", systemImage: "folder", behavior: .route(.primary(.projects))),
        .init(id: .schedule, title: "Schedule", systemImage: "calendar", behavior: .route(.review(.schedule))),
        .init(id: .completed, title: "Completed", systemImage: "checkmark.circle", behavior: .route(.review(.completed))),
        .init(id: .voiceCommand, title: "Voice Command", systemImage: "mic", behavior: .openVoiceCommand),
        .init(id: .settings, title: "Settings", systemImage: "gearshape", behavior: .openSettings),
    ]

    public static func selectedItemID(for route: BoardRoute) -> ProjectBoardSidebarItemID? {
        switch route {
        case .primary(.inbox): .inbox
        case .primary(.today): .today
        case .primary(.projects), .project, .smartList: .projects
        case .review(.schedule): .schedule
        case .review(.completed): .completed
        case .primary(.review), .review(.automationActivity), .review(.assistantQueue):
            // Unrepresented routes must not make another row claim a false current location.
            nil
        }
    }
}
```

- [x] **Step 4: Run focused Core tests**

Run:

```bash
swift test --filter ProjectBoardSidebarPresentationTests
```

Expected: PASS, 4 tests, 0 failures.

- [x] **Step 5: Commit the pure policy**

```bash
git add Sources/SuisuiCore/App/ProjectBoardSidebarPresentation.swift Tests/SuisuiCoreTests/ProjectBoardSidebarPresentationTests.swift
git commit -m "feat: define today sidebar presentation"
```

## Task 2: Branded Seven-Item SwiftUI Sidebar

**Files:**
- Modify: `Sources/SuisuiApp/Views/ProjectBoardSidebarView.swift`
- Modify: `Tests/SuisuiCoreTests/AppExperienceSourceTests.swift`

- [x] **Step 1: Replace the obsolete four-row source test with a failing approved-layout contract**

Replace `testProjectBoardPrimaryNavigationUsesExactlyFourTopLevelRows` with:

```swift
func testProjectBoardSidebarMatchesApprovedTodaySampleStructure() throws {
    let source = try readPackageFile("Sources/SuisuiApp/Views/ProjectBoardSidebarView.swift")
    let orderedMarkers = [
        "sidebar-destination-inbox",
        "sidebar-destination-today",
        "sidebar-destination-projects",
        "sidebar-destination-schedule",
        "sidebar-destination-completed",
        "sidebar-action-voice-command",
        "sidebar-action-settings",
    ]
    let ranges = try orderedMarkers.map { marker in
        try XCTUnwrap(source.range(of: marker), "Missing \(marker)")
    }
    for pair in zip(ranges, ranges.dropFirst()) {
        XCTAssertLessThan(pair.0.lowerBound, pair.1.lowerBound)
    }
    XCTAssertTrue(source.contains("NSApplication.shared.applicationIconImage"))
    XCTAssertTrue(
        FileManager.default.fileExists(
            atPath: packageRoot().appendingPathComponent("packaging/Suisui-AppIcon-1024.png").path
        )
    )
    XCTAssertTrue(source.contains("sidebar-open-search"))
    XCTAssertTrue(source.contains("sidebar-quick-add-task"))
    XCTAssertTrue(source.contains("sidebar-quick-add-by-voice"))
    XCTAssertTrue(source.contains("sidebar-quick-block-time"))
    XCTAssertFalse(source.contains("sidebar-destination-review"))
}
```

Update the other sidebar-specific assertions in the same test file so they expect Inbox → Today → Projects → Schedule → Completed and continue to assert that Catch Up and Assistant Queue are not top-level rows.

Apply these exact contract changes as part of the same edit:

```swift
// testProjectBoardPromotesInboxAndTodayAsFirstClassDestinations
XCTAssertTrue(source.contains("sidebar-destination-schedule"))
XCTAssertTrue(source.contains("sidebar-destination-completed"))
XCTAssertFalse(source.contains("sidebar-destination-review"))

// renamed testSidebarShowsApprovedDestinationsInSampleOrder
let inboxRow = try XCTUnwrap(sidebarSource.range(of: "sidebar-destination-inbox"))
let todayRow = try XCTUnwrap(sidebarSource.range(of: "sidebar-destination-today"))
let projectsRow = try XCTUnwrap(sidebarSource.range(of: "sidebar-destination-projects"))
let scheduleRow = try XCTUnwrap(sidebarSource.range(of: "sidebar-destination-schedule"))
let completedRow = try XCTUnwrap(sidebarSource.range(of: "sidebar-destination-completed"))
XCTAssertLessThan(inboxRow.lowerBound, todayRow.lowerBound)
XCTAssertLessThan(todayRow.lowerBound, projectsRow.lowerBound)
XCTAssertLessThan(projectsRow.lowerBound, scheduleRow.lowerBound)
XCTAssertLessThan(scheduleRow.lowerBound, completedRow.lowerBound)

// testProjectBoardVoiceOverFocusPathIsSourceAnchored
XCTAssertTrue(boardSource.contains("sidebar-destination-schedule"))
XCTAssertTrue(boardSource.contains("sidebar-destination-completed"))
XCTAssertFalse(boardSource.contains("sidebar-destination-review"))
```

- [x] **Step 2: Run the source contract and verify it fails against the old List**

Run:

```bash
swift test --filter AppExperienceSourceTests/testProjectBoardSidebarMatchesApprovedTodaySampleStructure
```

Expected: FAIL because `sidebar-destination-schedule` and the branded quick actions do not exist.

- [x] **Step 3: Expand counts and handler inputs**

Change the sidebar inputs to:

```swift
struct ProjectBoardSidebarCounts: Equatable {
    let today: Int
    let inbox: Int
    let projects: Int
    let schedule: Int
    let completed: Int

    func count(for itemID: ProjectBoardSidebarItemID) -> Int? {
        switch itemID {
        case .today: today
        case .inbox: inbox
        case .projects: projects
        case .schedule: schedule
        case .completed: completed
        case .voiceCommand, .settings: nil
        }
    }
}

struct ProjectBoardSidebarView: View {
    @Binding var route: BoardRoute
    let counts: ProjectBoardSidebarCounts
    let onOpenSearch: () -> Void
    let onOpenVoiceCommand: () -> Void
    let onOpenSettings: () -> Void
    let onAddTask: () -> Void
    let onAddByVoice: () -> Void
    let onBlockTime: () -> Void
}
```

- [x] **Step 4: Replace the List body with the approved hierarchy**

Add `import AppKit`, use `NSApplication.shared.applicationIconImage` for the real installed app icon, and render the body in this order:

```swift
var body: some View {
    VStack(alignment: .leading, spacing: 12) {
        HStack(spacing: 10) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .accessibilityHidden(true)
            Text("Suisui")
                .font(.headline.weight(.semibold))
        }
        .padding(.horizontal, 10)

        Button(action: onOpenSearch) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .accessibilityHidden(true)
                Text("Search")
                Spacer(minLength: 8)
                Text("⌘K").foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("sidebar-open-search")
        .accessibilityHint("Opens the command palette.")

        ScrollView {
            LazyVStack(spacing: 3) {
                ForEach(ProjectBoardSidebarPresentation.items, id: \.id) { item in
                    sidebarRow(item)
                }
            }
        }

        Divider()
        VStack(spacing: 3) {
            quickActionRow(.addTask, identifier: "sidebar-quick-add-task", action: onAddTask)
            quickActionRow(.addByVoice, identifier: "sidebar-quick-add-by-voice", action: onAddByVoice)
            quickActionRow(.blockTime, identifier: "sidebar-quick-block-time", action: onBlockTime)
        }
    }
    .padding(10)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("project-board-sidebar")
    .accessibilityLabel("Project navigation")
    .accessibilityHint("Navigate work or open a quick action.")
}
```

Implement rows with the following functions. `.route` changes `route`; utilities call injected closures; selection comes only from `ProjectBoardSidebarPresentation.selectedItemID(for:)`:

```swift
private func sidebarRow(_ item: ProjectBoardSidebarItemPresentation) -> some View {
    let isSelected = ProjectBoardSidebarPresentation.selectedItemID(for: route) == item.id
    return Button {
        perform(item.behavior)
    } label: {
        HStack(spacing: 10) {
            Image(systemName: item.systemImage)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(LocalizedStringKey(item.title))
                .lineLimit(1)
            Spacer(minLength: 8)
            if let count = counts.count(for: item.id), count > 0 {
                Text(verbatim: "\(count)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
            }
        }
        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
        .padding(.horizontal, 10)
        .frame(height: 34)
        .contentShape(Rectangle())
        .background(
            isSelected ? Color.accentColor.opacity(0.14) : Color.clear,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text(LocalizedStringKey(item.title)))
    .accessibilityValue(countAccessibilityValue(for: item.id))
    .accessibilityAddTraits(isSelected ? .isSelected : [])
    .accessibilityIdentifier(identifier(for: item.id))
}

private func quickActionRow(
    _ quickAction: ProjectBoardSidebarQuickAction,
    identifier: String,
    action: @escaping () -> Void
) -> some View {
    Button(action: action) {
        Label(LocalizedStringKey(quickAction.title), systemImage: quickAction.systemImage)
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier(identifier)
}

private func perform(_ behavior: ProjectBoardSidebarItemBehavior) {
    switch behavior {
    case .route(let destination): route = destination
    case .openVoiceCommand: onOpenVoiceCommand()
    case .openSettings: onOpenSettings()
    }
}

private func countAccessibilityValue(for itemID: ProjectBoardSidebarItemID) -> String {
    guard let count = counts.count(for: itemID) else {
        return ""
    }
    guard count > 0 else {
        return switch itemID {
        case .inbox: localizedDisplay("No pending items")
        case .today: localizedDisplay("No items today")
        case .projects: localizedDisplay("No projects")
        case .schedule: localizedDisplay("No scheduled items")
        case .completed: localizedDisplay("No completed items")
        case .voiceCommand, .settings: ""
        }
    }
    return localizedCount(count, one: "%d item", other: "%d items")
}
```

The root hint describes the whole sidebar, so do not reuse it on each destination. Destination rows use the focused `Opens this section.` hint; otherwise VoiceOver repeats quick-action behavior for a simple navigation action. Zero-count values are item-specific because “no pending items” is accurate for Inbox but misleading for Today, Projects, Schedule, and Completed.

Use these stable identifiers:

```swift
private func identifier(for itemID: ProjectBoardSidebarItemID) -> String {
    switch itemID {
    case .inbox: "sidebar-destination-inbox"
    case .today: "sidebar-destination-today"
    case .projects: "sidebar-destination-projects"
    case .schedule: "sidebar-destination-schedule"
    case .completed: "sidebar-destination-completed"
    case .voiceCommand: "sidebar-action-voice-command"
    case .settings: "sidebar-action-settings"
    }
}
```

The row label must render `Image(systemName: item.systemImage)`, `Text(LocalizedStringKey(item.title))`, an optional positive count, and a rounded selected background. Add `.isSelected` only when `selectedItemID == item.id`; utility actions never receive selection.

- [x] **Step 5: Run the focused source and policy tests**

Run:

```bash
swift test --filter ProjectBoardSidebarPresentationTests
swift test --filter AppExperienceSourceTests/testProjectBoardSidebarMatchesApprovedTodaySampleStructure
```

Expected: both commands PASS.

- [x] **Step 6: Commit the visual hierarchy**

```bash
git add Sources/SuisuiApp/Views/ProjectBoardSidebarView.swift Tests/SuisuiCoreTests/AppExperienceSourceTests.swift
git commit -m "feat: render branded seven-item sidebar"
```

## Task 3: Wire Existing Product Behaviors and One-Shot Inbox Focus

**Files:**
- Modify: `Sources/SuisuiApp/Views/ProjectBoardView.swift`
- Modify: `Sources/SuisuiApp/Views/ProjectWorkflowInboxView.swift`
- Modify: `Tests/SuisuiCoreTests/AppExperienceSourceTests.swift`

- [x] **Step 1: Add failing source contracts for every handler boundary**

```swift
func testTodaySidebarQuickActionsUseExistingSafeFlows() throws {
    let board = try readPackageFile("Sources/SuisuiApp/Views/ProjectBoardView.swift")
    XCTAssertTrue(board.contains("schedule: sidebarMetrics.scheduleCount"))
    XCTAssertTrue(board.contains("completed: sidebarMetrics.doneCount"))
    XCTAssertTrue(board.contains("onOpenSearch: { isCommandPaletteVisible = true }"))
    XCTAssertTrue(board.contains("onOpenVoiceCommand: openVoiceCommandFromBoardContext"))
    XCTAssertTrue(board.contains("onAddByVoice: openVoiceCommandFromBoardContext"))
    XCTAssertTrue(board.contains("onOpenSettings: { openSettings() }"))
    XCTAssertTrue(board.contains("private func beginInboxQuickAddFromSidebar()"))
    XCTAssertTrue(board.contains("private func prepareScheduleDraftFromSidebar()"))

    let start = try XCTUnwrap(board.range(of: "private func prepareScheduleDraftFromSidebar()"))
    let end = try XCTUnwrap(
        board.range(of: "\n    private func", range: start.upperBound..<board.endIndex)
    )
    let block = String(board[start.lowerBound..<end.lowerBound])
    XCTAssertTrue(block.contains("navigateWithinScene(to: .review(.schedule))"))
    XCTAssertTrue(block.contains("viewModel.prepareScheduleDraft"))
    XCTAssertFalse(block.contains("applyScheduleDraftToCalendar"))
    XCTAssertFalse(block.contains("enqueueScheduleDraftCalendarApply"))
}

func testInboxQuickAddFocusIntentIsConsumed() throws {
    let source = try readPackageFile("Sources/SuisuiApp/Views/ProjectWorkflowInboxView.swift")
    XCTAssertTrue(source.contains("let requestsQuickAddFocus: Bool"))
    XCTAssertTrue(source.contains("let onQuickAddFocusConsumed: () -> Void"))
    XCTAssertTrue(source.contains("@FocusState private var isQuickAddFocused: Bool"))
    XCTAssertTrue(source.contains(".focused($isQuickAddFocused)"))
    XCTAssertTrue(source.contains("onQuickAddFocusConsumed()"))
}
```

- [x] **Step 2: Run and verify both contracts fail**

Run:

```bash
swift test --filter AppExperienceSourceTests/testTodaySidebarQuickActionsUseExistingSafeFlows
swift test --filter AppExperienceSourceTests/testInboxQuickAddFocusIntentIsConsumed
```

Expected: FAIL because no sidebar handlers or focus intent exist.

- [x] **Step 3: Wire counts and actions from ProjectBoardView**

Add:

```swift
@State private var requestsInboxQuickAddFocus = false
```

Pass counts and closures:

```swift
ProjectBoardSidebarView(
    route: boardRouteBinding,
    counts: ProjectBoardSidebarCounts(
        today: sidebarMetrics.todayCount,
        inbox: sidebarMetrics.inboxCount,
        projects: sidebarMetrics.projectsCount,
        schedule: sidebarMetrics.scheduleCount,
        completed: sidebarMetrics.doneCount
    ),
    onOpenSearch: { isCommandPaletteVisible = true },
    onOpenVoiceCommand: openVoiceCommandFromBoardContext,
    onOpenSettings: { openSettings() },
    onAddTask: beginInboxQuickAddFromSidebar,
    onAddByVoice: openVoiceCommandFromBoardContext,
    onBlockTime: prepareScheduleDraftFromSidebar
)
```

Add safe handlers:

```swift
private func beginInboxQuickAddFromSidebar() {
    requestsInboxQuickAddFocus = true
    navigateWithinScene(to: .primary(.inbox))
}

private func prepareScheduleDraftFromSidebar() {
    navigateWithinScene(to: .review(.schedule))
    _ = viewModel.prepareScheduleDraft(on: VisualEvidenceRuntimeContext.referenceDate())
}
```

Extract the toolbar's existing project/task scope bridge into `openVoiceCommandFromBoardContext()` and call that same helper from the toolbar, Voice Command row, and Add by Voice action. The helper must store `SuisuiVoiceConversationScopeBridge` context before `openWindow(id: "voice-capture")` so sidebar entry does not lose the selected task/project context.

The Block Time handler intentionally calls only the local draft API. Do not call `enqueueScheduleDraftCalendarApply` or `applyScheduleDraftToCalendar`.

- [x] **Step 4: Consume Inbox focus exactly once**

Change `InboxWorkflowView` inputs and field:

```swift
let requestsQuickAddFocus: Bool
let onQuickAddFocusConsumed: () -> Void
@FocusState private var isQuickAddFocused: Bool
```

Attach `.focused($isQuickAddFocused)` to `inbox-quick-add-title`. Add one helper and call it from both `.onAppear` and `.onChange(of: requestsQuickAddFocus)`:

```swift
private func consumeQuickAddFocusIfRequested() {
    guard requestsQuickAddFocus else { return }
    isQuickAddFocused = true
    onQuickAddFocusConsumed()
}
```

Construct Inbox from `ProjectBoardView` with:

```swift
InboxWorkflowView(
    viewModel: viewModel,
    selectInboxTask: selectInboxTask,
    requestsQuickAddFocus: requestsInboxQuickAddFocus,
    onQuickAddFocusConsumed: { requestsInboxQuickAddFocus = false }
)
```

- [x] **Step 5: Run focused tests and build the macOS target**

Run:

```bash
swift test --filter AppExperienceSourceTests/testTodaySidebarQuickActionsUseExistingSafeFlows
swift test --filter AppExperienceSourceTests/testInboxQuickAddFocusIntentIsConsumed
swift build --product Suisui
```

Expected: tests PASS and `Build complete!`.

- [x] **Step 6: Commit behavior wiring**

```bash
git add Sources/SuisuiApp/Views/ProjectBoardView.swift Sources/SuisuiApp/Views/ProjectWorkflowInboxView.swift Tests/SuisuiCoreTests/AppExperienceSourceTests.swift
git commit -m "feat: connect sidebar quick actions"
```

## Task 4: Localization and Accessibility Contract

**Files:**
- Modify: `Sources/SuisuiApp/Resources/en.lproj/Localizable.strings`
- Modify: `Sources/SuisuiApp/Resources/ja.lproj/Localizable.strings`
- Modify: `Tests/SuisuiCoreTests/AppExperienceSourceTests.swift`

- [x] **Step 1: Add a failing bilingual and AX source test**

```swift
func testTodaySidebarLabelsAreLocalizedAndAccessible() throws {
    let english = try readPackageFile("Sources/SuisuiApp/Resources/en.lproj/Localizable.strings")
    let japanese = try readPackageFile("Sources/SuisuiApp/Resources/ja.lproj/Localizable.strings")
    for key in [
        "Search", "Completed", "Add by Voice", "Block Time",
        "Navigate work or open a quick action.", "Opens this section.",
        "No items today", "No projects", "No scheduled items", "No completed items",
    ] {
        XCTAssertTrue(english.contains("\"\(key)\" ="), "Missing English \(key)")
        XCTAssertTrue(japanese.contains("\"\(key)\" ="), "Missing Japanese \(key)")
    }

    let sidebar = try readPackageFile("Sources/SuisuiApp/Views/ProjectBoardSidebarView.swift")
    XCTAssertTrue(sidebar.contains(".accessibilityHidden(true)"))
    XCTAssertTrue(sidebar.contains(".accessibilityAddTraits(isSelected ? .isSelected : [])"))
    XCTAssertTrue(sidebar.contains(".accessibilityIdentifier(identifier(for: item.id))"))
}
```

- [x] **Step 2: Run and verify missing localization entries fail**

Run:

```bash
swift test --filter AppExperienceSourceTests/testTodaySidebarLabelsAreLocalizedAndAccessible
```

Expected: FAIL on at least `Add by Voice` or `Navigate work or open a quick action.`.

- [x] **Step 3: Add matching localization entries**

English:

```text
"Search" = "Search";
"Completed" = "Completed";
"Add by Voice" = "Add by Voice";
"Block Time" = "Block Time";
"Navigate work or open a quick action." = "Navigate work or open a quick action.";
"Opens the command palette." = "Opens the command palette.";
"Opens this section." = "Opens this section.";
"Creates a local schedule draft without writing Calendar." = "Creates a local schedule draft without writing Calendar.";
"No items today" = "No items today";
"No projects" = "No projects";
"No scheduled items" = "No scheduled items";
"No completed items" = "No completed items";
```

Japanese:

```text
"Search" = "検索";
"Completed" = "完了";
"Add by Voice" = "音声で追加";
"Block Time" = "時間をブロック";
"Navigate work or open a quick action." = "作業画面へ移動するか、クイックアクションを開きます。";
"Opens the command palette." = "コマンドパレットを開きます。";
"Opens this section." = "このセクションを開きます。";
"Creates a local schedule draft without writing Calendar." = "カレンダーへ書き込まず、ローカルのスケジュール下書きを作成します。";
"No items today" = "今日の項目はありません";
"No projects" = "プロジェクトはありません";
"No scheduled items" = "予定項目はありません";
"No completed items" = "完了済みの項目はありません";
```

Apply `accessibilityLabel`, localized count value, help, and hint to every row. Keep every SF Symbol and the app icon hidden from VoiceOver so the Japanese label is read once. Scope the root, Search, destination, utility, and quick-action AX assertions to their source blocks, and require zero duplicate keys across both localization files.

- [x] **Step 4: Run the focused localization/AX test**

Run:

```bash
swift test --filter AppExperienceSourceTests/testTodaySidebarLabelsAreLocalizedAndAccessible
```

Expected: PASS.

- [x] **Step 5: Commit localization and AX semantics**

```bash
git add Sources/SuisuiApp/Resources/en.lproj/Localizable.strings Sources/SuisuiApp/Resources/ja.lproj/Localizable.strings Sources/SuisuiApp/Views/ProjectBoardSidebarView.swift Tests/SuisuiCoreTests/AppExperienceSourceTests.swift
git commit -m "feat: localize accessible sidebar actions"
```

## Task 5: Migrate Runtime and CI Navigation Contracts

**Files:**
- Modify: `script/check_layout_stability_smoke.sh`
- Modify: `script/check_release_launch_performance_smoke.sh`
- Modify: `script/check_runtime_today_production_route_smoke.sh`
- Modify: `Tests/SuisuiCoreTests/ReleasePipelineTests.swift`
- Modify: `Tests/SuisuiCoreTests/AppExperienceSourceTests.swift`

- [x] **Step 1: Change test expectations first**

Update the release/source tests to require:

```swift
XCTAssertTrue(script.contains("sidebar-destination-schedule"))
XCTAssertTrue(script.contains("sidebar-destination-completed"))
XCTAssertFalse(script.contains("sidebar-destination-review"))
XCTAssertTrue(script.contains("measure_destination \"destination-schedule\""))
```

For the normal route matrix, assert these exact entries:

```text
review|primary:review|sidebar-destination-schedule|review-hub
review-schedule|review:schedule|sidebar-destination-schedule|schedule-workflow
review-completed|review:completed|sidebar-destination-completed|done-workflow
review-automation|review:automation|sidebar-destination-schedule|automation-activity-workflow
review-assistant-queue|review:assistant-queue|sidebar-destination-schedule|assistant-queue-workflow
```

The marker on unrepresented Review routes proves the new sidebar exists; content markers continue to prove the actual active route. Do not add a false selected state to Schedule for Automation Activity or Assistant Queue.

- [x] **Step 2: Run the affected contracts and verify old Review markers fail**

Run:

```bash
swift test --filter ReleasePipelineTests
swift test --filter AppExperienceSourceTests
```

Expected: FAIL on `sidebar-destination-review` expectations before script migration.

- [x] **Step 3: Update layout stability destinations**

Replace the Review sidebar lane with Schedule and Completed lanes:

```bash
assert_sidebar_destination_window_size_stable "destination-schedule" "sidebar-destination-schedule" "Schedule" "schedule-workflow"
assert_sidebar_destination_window_size_stable "destination-completed" "sidebar-destination-completed" "Completed" "done-workflow"
assert_ax_destination_window_size_stable "destination-review-assistant-queue" "review-destination-assistant-queue" "assistant-queue-workflow"
```

Update the coordinate fallback cases to the final fixed row layout constants. Keep AXPress as the primary path; the fallback must target the center of the corresponding custom Button row, not the removed List offsets.

- [x] **Step 4: Update release performance navigation**

Rename the Review sample collection to Schedule and use:

```bash
measure_destination "destination-schedule" "$sample_index" "sidebar-destination-schedule" "Schedule" "schedule-workflow"
DESTINATION_SCHEDULE_SAMPLES+=("$LAST_DESTINATION_ELAPSED_MS")
measure_review_assistant_queue "$sample_index"
```

Record `destination-schedule` against the existing destination-switch budget. Preserve the separate Assistant Queue nested transition measurement.

- [x] **Step 5: Update the typed-route smoke matrix**

Use the exact matrix from Step 1. Keep content markers unchanged so a visible sidebar cannot make a wrong route pass.

- [x] **Step 6: Run source-level script contracts and shell syntax checks**

Run:

```bash
bash -n script/check_layout_stability_smoke.sh
bash -n script/check_release_launch_performance_smoke.sh
bash -n script/check_runtime_today_production_route_smoke.sh
swift test --filter ReleasePipelineTests
swift test --filter AppExperienceSourceTests
```

Expected: shell syntax checks exit 0; both XCTest suites PASS.

- [x] **Step 7: Commit the contract migration**

```bash
git add script/check_layout_stability_smoke.sh script/check_release_launch_performance_smoke.sh script/check_runtime_today_production_route_smoke.sh Tests/SuisuiCoreTests/ReleasePipelineTests.swift Tests/SuisuiCoreTests/AppExperienceSourceTests.swift
git commit -m "test: migrate sidebar runtime contracts"
```

## Task 6: Runtime AX and Interaction Verification

**Files:**
- Modify only if a verified runtime defect is found: files from Tasks 2–5

- [x] **Step 1: Build and launch the real app**

Run:

```bash
./script/build_and_run.sh --verify
```

Expected: app builds, launches, and the automated smoke exits successfully.

- [x] **Step 2: Exercise all sidebar actions in the running app**

Verify in order:

1. Inbox, Today, Projects, Schedule, Completed switch to their matching content.
2. Voice Command opens the existing Voice Command window without changing the selected Project Board route.
3. Settings opens the Settings scene without changing the selected Project Board route.
4. Add Task routes to Inbox and focuses `inbox-quick-add-title` once.
5. Add by Voice opens Voice Command.
6. Block Time routes to Schedule and creates a local visible draft.
7. Block Time does not create a Calendar event or enqueue Calendar apply.

- [x] **Step 3: Run layout and route smokes**

Run:

```bash
./script/check_runtime_today_production_route_smoke.sh
./script/check_layout_stability_smoke.sh
```

Expected: both report OK with Inbox, Today, Projects, Schedule, Completed and nested Review content reachable; no clipping or frame-jump blocker.

- [ ] **Step 4: Verify Japanese, keyboard, VoiceOver, and compact height**

Light、Dark、System、keyboard、direct AXPress、selected state、false selection、`1024x676` reachabilityは確認済み。Increase ContrastとReduce Motionは、process-local registration argumentsで`NSWorkspace`値を変更できなかったため`not_proven`のまま残す。詳細は`docs/release/evidence/today-sidebar-runtime-ax-receipt.json`を参照する。

At the canonical `1024x676` window verify:

- all 7 row labels and 3 quick actions are reachable;
- the app icon is visible and not read as a duplicate VoiceOver element;
- `⌘K` opens the same palette as Search;
- `⌘1`–`⌘4` retain their existing primary-route contract;
- selected state is announced for the five represented destination rows;
- Automation Activity and Assistant Queue show no false selected sidebar row;
- Light, Dark, System, Increase Contrast, and Reduce Motion remain legible.

- [x] **Step 5: Route a verified defect back through its owning TDD task**

If Steps 1–4 reveal a defect, return to the owning task above, add its specified failing test, implement the smallest correction, rerun that task's commands, and use that task's exact `git add` file list. If no defect is found, continue without an empty commit.

## Task 7: Full Validation and Security Review

**Files:**
- No product files unless a failing check produces a reproducible defect with a new regression test.

- [x] **Step 1: Run the complete SwiftPM suite fail-closed**

Run:

```bash
./script/run_complete_swiftpm_tests.sh
```

Expected: discovered tests are nonzero, executed count matches the gate contract, skipped count remains within budget, exit 0.

- [x] **Step 2: Run security regression checks**

Run:

```bash
./script/check_security_regressions.sh
```

Expected: exit 0; no secret, unsafe Calendar write, injection, or path-safety regression.

- [x] **Step 3: Run the visual gate in comparison mode**

Run:

```bash
SUISUI_CI_VISUAL_GATE_LOCALE=en-US ./script/check_ci_visual_gate.sh
SUISUI_CI_VISUAL_GATE_LOCALE=ja-JP ./script/check_ci_visual_gate.sh
```

Expected before baseline refresh: the gate may report bounded raster mismatch for screens containing the intentionally changed sidebar, but must not report black image, missing AX target, wrong route, unsafe output, or unrelated-screen changes.

- [x] **Step 4: Self-review the complete source diff**

Run:

```bash
git diff --check origin/main...HEAD
git diff --stat origin/main...HEAD
git status --short
```

Review specifically:

- no second route state was introduced;
- utility actions never persist as destinations;
- Block Time uses only `prepareScheduleDraft`;
- SF Symbols exactly match the approved table;
- `.superpowers/`, `.tmp/`, build outputs, and local screenshots remain ignored;
- no unrelated refactor or generated file entered the diff.

## Task 8: Commit Source, Refresh Visual Evidence, and Close the Spec

**Files:**
- Modify: visual manifests, affected sidebar screenshot baselines and metadata
- Modify: `docs/superpowers/specs/2026-08-02-today-sidebar-parity-design.md`

- [x] **Step 1: Ensure all source changes are committed before capture**

Run:

```bash
git status --short
git log --oneline origin/main..HEAD
./script/capture_ui_evidence.sh --doctor
```

Expected: no uncommitted `Sources`, `Package.swift`, or capture-harness change; doctor reports the capture environment ready.

- [x] **Step 2: Capture complete English and Japanese evidence**

Run:

```bash
SUISUI_UI_EVIDENCE_LOCALE=english \
SUISUI_VISUAL_BASELINE_MANIFEST="$PWD/docs/quality/visual-baseline-manifest.json" \
SUISUI_UI_EVIDENCE_DIR="$PWD/docs/release/evidence/ui-screenshots" \
SUISUI_VISUAL_AX_AUDIT_RESULT="$PWD/.tmp/visual-ax-audit-receipt.json" \
./script/capture_ui_evidence.sh

SUISUI_UI_EVIDENCE_LOCALE=japanese \
SUISUI_VISUAL_BASELINE_MANIFEST="$PWD/docs/quality/visual-baseline-manifest-ja.json" \
SUISUI_UI_EVIDENCE_DIR="$PWD/docs/release/evidence/ui-screenshots-ja" \
SUISUI_VISUAL_AX_AUDIT_RESULT="$PWD/.tmp/visual-ax-audit-receipt-ja.json" \
./script/capture_ui_evidence.sh
```

Expected: 39 healthy screenshots per locale and passed live AX receipts.

- [x] **Step 3: Review before/after sidebar pixels and update only authenticated baselines**

Align each manifest `baselineContext.sourceCommit` to the committed product-source commit, then run the paired explicit update:

```bash
./script/check_visual_regression_smoke.sh --update-baselines --allow-update
```

Expected: only screens containing the changed Project Board sidebar receive raster/metadata changes; unrelated Settings and Voice Command baselines remain unchanged.

- [x] **Step 4: Run final visual comparison and full validation**

Run:

```bash
SUISUI_CI_VISUAL_GATE_LOCALE=en-US ./script/check_ci_visual_gate.sh
SUISUI_CI_VISUAL_GATE_LOCALE=ja-JP ./script/check_ci_visual_gate.sh
./script/run_complete_swiftpm_tests.sh
./script/check_security_regressions.sh
```

Expected: every command exits 0 with nonzero test execution and complete visual evidence.

- [x] **Step 5: Mark the approved design implemented with evidence**

Change the design status to `implemented and verified` and append the exact source commit, test command results, runtime AX result, visual gate result, and security result. Do not claim hosted CI or release completion from local evidence.

- [x] **Step 6: Commit authenticated evidence and documentation**

```bash
git add docs/quality docs/release/evidence docs/superpowers/specs/2026-08-02-today-sidebar-parity-design.md
git commit -m "test: refresh today sidebar visual evidence"
```

- [x] **Step 7: Final clean-tree review**

Run:

```bash
git status --short --branch
git log --oneline origin/main..HEAD
git diff --check origin/main...HEAD
```

Expected: clean worktree, small purpose-specific commits, and no ignored local preview artifacts in Git.
