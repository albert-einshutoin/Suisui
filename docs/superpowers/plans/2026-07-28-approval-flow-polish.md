# Approval Flow Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** InboxからReview、Assistant Queueまで、対象・現在地・次の安全な操作を迷わず確認できるmacOS承認フローを実装する。

**Architecture:** 既存Store、`BoardRoute`、Assistant Queue State Machine、Execution Coordinatorは変更しない。Coreへ2つの純粋Presentation Policyを追加し、SwiftUIはその出力だけを描画する。英語と日本語のvisual evidenceはlocale別manifest・artifact root・AX receiptへ分離する。

**Tech Stack:** Swift 6、SwiftUI、Swift Package Manager、XCTest、SQLite fixture、macOS Accessibility API、Bash evidence scripts、JSON visual manifests。

---

## File and Ownership Map

### New focused files

- `Sources/SuisuiCore/App/AssistantQueueRowActionPresentation.swift`
  - Queue state/capabilityをPrimary / Secondary actionsへfail-closed変換する。
- `Tests/SuisuiCoreTests/AssistantQueueRowActionPresentationTests.swift`
  - 全state、capability、矛盾入力、順序をbehavioralに固定する。
- `Sources/SuisuiCore/App/ProjectBoardCompactNavigationPresentation.swift`
  - `BoardRoute`と既存Project / Smart Listから現在地labelとbadgeを導出する。
- `Tests/SuisuiCoreTests/ProjectBoardCompactNavigationPresentationTests.swift`
  - Review / Projectsの全route、ユーザー名、欠損ID、badgeを固定する。
- `docs/quality/visual-baseline-manifest-ja.json`
  - ja-JP専用のvisual baseline contextとrootを定義する。
- `Sources/SuisuiVisualFixtureSeeder/main.swift`
  - 隔離DBへ安全なQueue visual fixtureをproduction transition経由で投入する。
- `docs/release/evidence/ui-screenshots-ja/`
  - 日本語capture artifactを英語artifactから分離する。
- `docs/quality/visual-baselines-ja/`
  - 日本語baselineを英語baselineから分離する。

### Existing files modified by one task only

- `Sources/SuisuiApp/Views/ProjectWorkflowInboxView.swift`
- `Sources/SuisuiApp/Views/ProjectWorkflowAssistantQueueView.swift`
- `Sources/SuisuiApp/Views/ProjectBoardReviewHubView.swift`
- `Sources/SuisuiApp/Views/ProjectBoardProjectsHubView.swift`
- `Sources/SuisuiCore/App/AccessibilityFocusPathAudit.swift`
- `Tests/SuisuiCoreTests/AccessibilityFocusPathAuditTests.swift`
- `Tests/SuisuiCoreTests/SuisuiHarnessTests.swift`
- `script/check_pseudo_voiceover_paths.sh`
- `script/capture_ui_evidence.sh`
- `docs/quality/visual-baseline-manifest.json`
- `docs/quality/visual-baselines.md`

### Shared integration files owned by the root agent

- `Sources/SuisuiApp/Resources/en.lproj/Localizable.strings`
- `Sources/SuisuiApp/Resources/ja.lproj/Localizable.strings`
- `Tests/SuisuiCoreTests/AppExperienceSourceTests.swift`

`Tests/SuisuiCoreTests/AssistantQueueStoreTests.swift` belongs exclusively to
Task 1. `Tests/SuisuiCoreTests/ReleasePipelineTests.swift`,
`Tests/SuisuiCoreTests/UIGateScriptsTests.swift`, and
`Tests/SuisuiCoreTests/VisualEvidenceRuntimeContextTests.swift` belong
exclusively to Task 7.

Subagents must not edit the three root-owned shared integration files. The root
agent writes their RED contracts before dispatch and performs their final
integration after leaf tasks finish. Every worker stages only the files assigned
to that task, even though all workers share one worktree.

---

### Task 0: Root-Owned Shared RED Contracts

**Files (root agent only):**

- Modify: `Tests/SuisuiCoreTests/AppExperienceSourceTests.swift`
- Modify: `Sources/SuisuiApp/Resources/en.lproj/Localizable.strings`
- Modify: `Sources/SuisuiApp/Resources/ja.lproj/Localizable.strings`

- [ ] **Step 1: Add all failing cross-view source contracts**

The root agent adds the exact Inbox, Queue, and compact navigation source tests
defined in Tasks 3, 4, and 5 before dispatching those workers. Add localization
parity assertions for every new key listed across Tasks 3–5.

The source contracts must scope each assertion to the component or helper that
owns the behavior. In particular:

- Inbox checks the `manualSummary` task/capture condition as one expression,
  keeps selected title/detail AX ownership in the context child, and verifies
  the parent action group exposes no duplicate accessibility value;
- Queue separately extracts the row body, primary-action switch, and
  secondary-action switch, protects all six existing action identifiers, and
  requires destructive Reject to be the last secondary case;
- compact navigation extracts `compactNavigation` together with its
  `compactLabel` helper so an unused typed-presentation helper cannot satisfy
  the contract.

- [ ] **Step 2: Prove the source contracts are RED**

```bash
test "$(swift test list | rg -c 'testInboxActionPanelShowsSelectedContextWithoutDuplicatingVoiceMetadata')" -eq 1
test "$(swift test list | rg -c 'testAssistantQueueRowUsesStageSpecificPrimaryActionAndSecondaryMenu')" -eq 1
test "$(swift test list | rg -c 'testCompactHubLabelsUseTypedPresentationAndPreserveDestinationParity')" -eq 1
if swift test --filter testInboxActionPanelShowsSelectedContextWithoutDuplicatingVoiceMetadata; then
  echo "Expected Inbox source contract to fail before implementation" >&2
  exit 1
fi
if swift test --filter testAssistantQueueRowUsesStageSpecificPrimaryActionAndSecondaryMenu; then
  echo "Expected Queue source contract to fail before implementation" >&2
  exit 1
fi
if swift test --filter testCompactHubLabelsUseTypedPresentationAndPreserveDestinationParity; then
  echo "Expected compact navigation source contract to fail before implementation" >&2
  exit 1
fi
```

Read each failure and confirm it is caused by the absent approved behavior, not
by a compile error, test discovery failure, or unrelated regression.

- [ ] **Step 3: Add the approved English/Japanese strings**

Add these keys in both localizations:

```text
Selected Item
Select an Inbox item to classify.
Smart List Not Found
Transcript failed
Transcript pending
AI interpreted
More Assistant Queue actions
Choose Review destination.
Choose Project destination.
```

Use the exact Japanese values from Tasks 3–5. Localization is root-owned because
three leaf views consume the same files.

Count definitions with a line-oriented `.strings` parser that ignores comments
and permits whitespace before `=`. A raw `"key" =` substring count is not an
exact-once proof because it misses whitespace variants and can count comments.

- [ ] **Step 4: Keep shared edits unstaged during leaf implementation**

Do not let a worker include these files in a leaf commit. After Tasks 3–5 are
GREEN, the root agent stages the three files and commits them with the integrated
UI implementation:

```bash
git add \
  Tests/SuisuiCoreTests/AppExperienceSourceTests.swift \
  Sources/SuisuiApp/Resources/en.lproj/Localizable.strings \
  Sources/SuisuiApp/Resources/ja.lproj/Localizable.strings
git commit -m "test: define approval flow UI contracts"
```

---

### Task 1: Queue Action Presentation Policy

**Files:**

- Create: `Sources/SuisuiCore/App/AssistantQueueRowActionPresentation.swift`
- Create: `Tests/SuisuiCoreTests/AssistantQueueRowActionPresentationTests.swift`
- Modify: `Tests/SuisuiCoreTests/AssistantQueueStoreTests.swift`

- [ ] **Step 1: Write the failing state/capability tests**

Create `AssistantQueueRowActionPresentationTests` with the following public behavior:

```swift
import XCTest
@testable import SuisuiCore

final class AssistantQueueRowActionPresentationTests: XCTestCase {
    func testWaitingReviewUsesApproveAsPrimaryAndOrdersReviewActions() {
        let presentation = AssistantQueueRowActionPresentation.make(
            for: makeRow(
                state: .waitingReview,
                canApprove: true,
                canDefer: true,
                canEdit: true,
                canReject: true
            )
        )

        XCTAssertEqual(presentation.primaryAction, .approve)
        XCTAssertEqual(presentation.secondaryActions, [.edit, .defer, .reject])
    }

    func testApprovedUsesRunAsPrimaryWithoutApprove() {
        let presentation = AssistantQueueRowActionPresentation.make(
            for: makeRow(
                state: .approved,
                canRun: true,
                canDefer: true,
                canEdit: true,
                canReject: true
            )
        )

        XCTAssertEqual(presentation.primaryAction, .run)
        XCTAssertEqual(presentation.secondaryActions, [.edit, .defer, .reject])
    }

    func testFailedUsesReopenAsPrimary() {
        let presentation = AssistantQueueRowActionPresentation.make(
            for: makeRow(state: .failed, canRetry: true)
        )

        XCTAssertEqual(presentation.primaryAction, .reopen)
        XCTAssertTrue(presentation.secondaryActions.isEmpty)
    }

    func testRunningHidesRejectBecauseRejectDoesNotCancelExecution() {
        let presentation = AssistantQueueRowActionPresentation.make(
            for: makeRow(state: .running, canReject: true)
        )

        XCTAssertNil(presentation.primaryAction)
        XCTAssertTrue(presentation.secondaryActions.isEmpty)
    }

    func testEveryStateAndSingleCapabilityCombinationIsExplicit() {
        for state in AssistantQueueState.allCases {
            for capability in TestCapability.allCases {
                let presentation = AssistantQueueRowActionPresentation.make(
                    for: makeRow(state: state, enabling: capability)
                )
                let expected = expectedSingleCapabilityPresentation(
                    state: state,
                    capability: capability
                )

                XCTAssertEqual(
                    presentation.primaryAction,
                    expected.primary,
                    "Primary mismatch for \(state) / \(capability)"
                )
                XCTAssertEqual(
                    presentation.secondaryActions,
                    expected.secondary,
                    "Secondary mismatch for \(state) / \(capability)"
                )
            }
        }
    }

    func testEveryStateHasDeterministicMaximumPresentation() {
        let cases: [(AssistantQueueState, AssistantQueueRowActionPresentation.Action?, [AssistantQueueRowActionPresentation.Action])] = [
            (.captured, .approve, [.edit, .defer, .reject]),
            (.interpreted, .approve, [.edit, .defer, .reject]),
            (.drafted, .approve, [.edit, .defer, .reject]),
            (.waitingReview, .approve, [.edit, .defer, .reject]),
            (.approved, .run, [.edit, .defer, .reject]),
            (.running, nil, []),
            (.blocked, nil, [.reject]),
            (.done, nil, []),
            (.failed, .reopen, []),
            (.rejected, nil, []),
            (.deferred, .approve, [.edit, .reject])
        ]

        for (state, primary, secondary) in cases {
            let presentation = AssistantQueueRowActionPresentation.make(
                for: maximumLegalRow(state: state)
            )
            XCTAssertEqual(presentation.primaryAction, primary, "Primary mismatch for \(state)")
            XCTAssertEqual(presentation.secondaryActions, secondary, "Secondary mismatch for \(state)")
        }
    }

    private func makeRow(
        id: String = "queue-row",
        state: AssistantQueueState,
        canApprove: Bool = false,
        canRun: Bool = false,
        canDefer: Bool = false,
        canEdit: Bool = false,
        canRetry: Bool = false,
        canReject: Bool = false
    ) -> AssistantQueueReadModelRow {
        AssistantQueueReadModelRow(
            id: id,
            state: state,
            stateLabel: state.rawValue,
            riskLabel: "Write",
            title: "Create launch task",
            redactedSummary: "Create launch task",
            sourcePreview: nil,
            reviewReason: "Review generated work.",
            capabilityLabels: [],
            blockingReason: nil,
            canApprove: canApprove,
            canRun: canRun,
            canDefer: canDefer,
            canEdit: canEdit,
            canRetry: canRetry,
            canReject: canReject
        )
    }

    private enum TestCapability: CaseIterable {
        case approve, run, reopen, edit
        case `defer`
        case reject
    }

    private func makeRow(
        state: AssistantQueueState,
        enabling capability: TestCapability
    ) -> AssistantQueueReadModelRow {
        makeRow(
            state: state,
            canApprove: capability == .approve,
            canRun: capability == .run,
            canDefer: capability == .defer,
            canEdit: capability == .edit,
            canRetry: capability == .reopen,
            canReject: capability == .reject
        )
    }

    private func expectedSingleCapabilityPresentation(
        state: AssistantQueueState,
        capability: TestCapability
    ) -> (
        primary: AssistantQueueRowActionPresentation.Action?,
        secondary: [AssistantQueueRowActionPresentation.Action]
    ) {
        switch (state, capability) {
        case (.captured, .approve), (.interpreted, .approve),
             (.drafted, .approve), (.waitingReview, .approve),
             (.deferred, .approve):
            return (.approve, [])
        case (.approved, .run):
            return (.run, [])
        case (.failed, .reopen):
            return (.reopen, [])
        case (.captured, .edit), (.interpreted, .edit),
             (.drafted, .edit), (.waitingReview, .edit),
             (.approved, .edit), (.deferred, .edit):
            return (nil, [.edit])
        case (.captured, .defer), (.interpreted, .defer),
             (.drafted, .defer), (.waitingReview, .defer),
             (.approved, .defer):
            return (nil, [.defer])
        case (.captured, .reject), (.interpreted, .reject),
             (.drafted, .reject), (.waitingReview, .reject),
             (.approved, .reject), (.blocked, .reject),
             (.deferred, .reject):
            return (nil, [.reject])
        default:
            // Includes running/reject: the underlying capability exists, but
            // the UI intentionally exposes no false cancellation affordance.
            return (nil, [])
        }
    }

    private func maximumLegalRow(state: AssistantQueueState) -> AssistantQueueReadModelRow {
        switch state {
        case .captured, .interpreted, .drafted, .waitingReview:
            return makeRow(state: state, canApprove: true, canDefer: true, canEdit: true, canReject: true)
        case .approved:
            return makeRow(state: state, canRun: true, canDefer: true, canEdit: true, canReject: true)
        case .running:
            return makeRow(state: state, canReject: true)
        case .blocked:
            return makeRow(state: state, canReject: true)
        case .done, .rejected:
            return makeRow(state: state)
        case .failed:
            return makeRow(state: state, canRetry: true)
        case .deferred:
            return makeRow(state: state, canApprove: true, canEdit: true, canReject: true)
        }
    }
    }
```

The “maximum” row is derived from the existing production read-model
capabilities, not from a synthetic all-true row. In particular:

- `.blocked` currently permits Reject only;
- `.failed` currently permits Reopen only;
- `.deferred` currently permits Approve, Edit, and Reject but not Defer.

This is how the approved design phrase “許可済み” is applied. The presentation
must not broaden Store capabilities or redesign the state machine.

- [ ] **Step 2: Verify RED and reject a zero-test success**

Run:

```bash
test "$(rg -c 'final class AssistantQueueRowActionPresentationTests' Tests/SuisuiCoreTests/AssistantQueueRowActionPresentationTests.swift)" -eq 1
if swift test --filter AssistantQueueRowActionPresentationTests; then
  echo "Expected Queue presentation tests to fail before implementation" >&2
  exit 1
fi
```

Expected: compile failure because `AssistantQueueRowActionPresentation` does not exist. A zero-test success is not acceptable.

- [ ] **Step 3: Implement the pure policy**

Create:

```swift
public struct AssistantQueueRowActionPresentation: Equatable, Sendable {
    public enum Action: Hashable, Sendable {
        case approve
        case run
        case reopen
        case edit
        case `defer`
        case reject
    }

    public let primaryAction: Action?
    public let secondaryActions: [Action]

    private init(primaryAction: Action?, secondaryActions: [Action]) {
        self.primaryAction = primaryAction
        self.secondaryActions = secondaryActions
    }

    public static func make(for row: AssistantQueueReadModelRow) -> Self {
        let capabilities = capabilityActions(for: row)
        let allowed = allowedActions(for: row.state)

        // State and read-model capabilities are checked together so a future
        // or internally inconsistent row cannot expose approval or execution.
        guard capabilities.isSubset(of: allowed) else {
            return Self(primaryAction: nil, secondaryActions: [])
        }

        // Reject currently changes Queue state but does not cancel an in-flight
        // coordinator. Hiding every action avoids presenting false cancellation.
        guard row.state != .running else {
            return Self(primaryAction: nil, secondaryActions: [])
        }

        let primaryCandidates = [Action.approve, .run, .reopen]
            .filter(capabilities.contains)
        guard primaryCandidates.count <= 1 else {
            return Self(primaryAction: nil, secondaryActions: [])
        }

        return Self(
            primaryAction: primaryCandidates.first,
            secondaryActions: [Action.edit, .defer, .reject]
                .filter(capabilities.contains)
        )
    }

    private static func capabilityActions(for row: AssistantQueueReadModelRow) -> Set<Action> {
        var actions = Set<Action>()
        if row.canApprove { actions.insert(.approve) }
        if row.canRun { actions.insert(.run) }
        if row.canRetry { actions.insert(.reopen) }
        if row.canEdit { actions.insert(.edit) }
        if row.canDefer { actions.insert(.defer) }
        if row.canReject { actions.insert(.reject) }
        return actions
    }

    private static func allowedActions(for state: AssistantQueueState) -> Set<Action> {
        switch state {
        case .captured, .interpreted, .drafted, .waitingReview:
            [.approve, .edit, .defer, .reject]
        case .approved:
            [.run, .edit, .defer, .reject]
        case .running:
            [.reject]
        case .blocked:
            [.reject]
        case .failed:
            [.reopen]
        case .deferred:
            [.approve, .edit, .reject]
        case .done, .rejected:
            []
        }
    }
}
```

- [ ] **Step 4: Add real read-model integration coverage**

In `AssistantQueueStoreTests`, add a transition test that asserts:

```swift
let waitingRow = try XCTUnwrap(
    AssistantQueueReadModel.snapshot(from: [waitingItem]).rows.first
)
XCTAssertEqual(
    AssistantQueueRowActionPresentation.make(for: waitingRow).primaryAction,
    .approve
)

let approved = try AssistantQueueStateMachine.approve(waitingItem, reviewerID: "local-user")
let approvedRow = try XCTUnwrap(
    AssistantQueueReadModel.snapshot(from: [approved]).rows.first
)
XCTAssertEqual(
    AssistantQueueRowActionPresentation.make(for: approvedRow).primaryAction,
    .run
)
```

Use existing `makeItem` and `makeCostPreview` fixtures so approval remains a real State Machine transition.

- [ ] **Step 5: Run GREEN tests**

Run:

```bash
test "$(swift test list | rg -c 'AssistantQueueRowActionPresentationTests')" -gt 0
swift test --filter AssistantQueueRowActionPresentationTests
swift test --filter AssistantQueueStoreTests
```

Expected: both suites pass and the new suite executes more than zero tests.

- [ ] **Step 6: Commit the policy**

```bash
git add Sources/SuisuiCore/App/AssistantQueueRowActionPresentation.swift \
  Tests/SuisuiCoreTests/AssistantQueueRowActionPresentationTests.swift \
  Tests/SuisuiCoreTests/AssistantQueueStoreTests.swift
git commit -m "feat: define staged assistant queue actions"
```

---

### Task 2: Compact Navigation Presentation Policy

**Files:**

- Create: `Sources/SuisuiCore/App/ProjectBoardCompactNavigationPresentation.swift`
- Create: `Tests/SuisuiCoreTests/ProjectBoardCompactNavigationPresentationTests.swift`

- [ ] **Step 1: Write failing route presentation tests**

The new tests must cover:

```swift
XCTAssertEqual(
    ProjectBoardCompactNavigationPresentation.review(
        route: .primary(.review),
        assistantQueueCount: 3
    ),
    .init(label: .localized("Review"))
)

XCTAssertEqual(
    ProjectBoardCompactNavigationPresentation.review(
        route: .review(.assistantQueue),
        assistantQueueCount: 3
    ),
    .init(label: .localized("Assistant Queue"), badgeCount: 3)
)

XCTAssertEqual(
    ProjectBoardCompactNavigationPresentation.projects(
        route: .project(42),
        projects: [project(id: 42, title: "Suisui Release")],
        smartLists: []
    ).label,
    .verbatim("Suisui Release")
)

XCTAssertEqual(
    ProjectBoardCompactNavigationPresentation.projects(
        route: .smartList("preset-overdue"),
        projects: [],
        smartLists: SmartList.presets
    ).label,
    .localized("Overdue")
)

XCTAssertEqual(
    ProjectBoardCompactNavigationPresentation.projects(
        route: .smartList("custom-1"),
        projects: [],
        smartLists: [
            SmartList(id: "custom-1", name: "重要な案件", criteria: SmartListCriteria())
        ]
    ).label,
    .verbatim("重要な案件")
)
```

Also assert missing Project → `.localized("Project Not Found")`, missing Smart List → `.localized("Smart List Not Found")`, non-Queue route → `badgeCount == nil`, and nonpositive Queue count → `badgeCount == nil`.

- [ ] **Step 2: Verify RED**

```bash
test "$(rg -c 'final class ProjectBoardCompactNavigationPresentationTests' Tests/SuisuiCoreTests/ProjectBoardCompactNavigationPresentationTests.swift)" -eq 1
if swift test --filter ProjectBoardCompactNavigationPresentationTests; then
  echo "Expected compact presentation tests to fail before implementation" >&2
  exit 1
fi
```

Expected: compile failure because the presentation type does not exist.

- [ ] **Step 3: Implement the typed presentation**

Create:

```swift
public struct ProjectBoardCompactNavigationPresentation: Equatable, Sendable {
    public enum Label: Equatable, Sendable {
        case localized(String)
        case verbatim(String)
    }

    public let label: Label
    public let badgeCount: Int?

    init(label: Label, badgeCount: Int? = nil) {
        self.label = label
        self.badgeCount = badgeCount
    }

    public static func review(route: BoardRoute, assistantQueueCount: Int) -> Self {
        switch route {
        case .primary(.review):
            return Self(label: .localized("Review"))
        case .review(let destination):
            switch destination {
            case .schedule:
                return Self(label: .localized("Schedule"))
            case .completed:
                return Self(label: .localized("Completed"))
            case .automationActivity:
                return Self(label: .localized("Automation Activity"))
            case .assistantQueue:
                return Self(
                    label: .localized("Assistant Queue"),
                    badgeCount: assistantQueueCount > 0 ? assistantQueueCount : nil
                )
            }
        case .primary, .project, .smartList:
            return Self(label: .localized("Review"))
        }
    }

    public static func projects(
        route: BoardRoute,
        projects: [ProjectBoardProject],
        smartLists: [SmartList]
    ) -> Self {
        switch route {
        case .primary(.projects):
            return Self(label: .localized("Portfolio"))
        case .project(let id):
            guard let project = projects.first(where: { $0.id == id }) else {
                return Self(label: .localized("Project Not Found"))
            }
            return Self(label: .verbatim(project.title))
        case .smartList(let id):
            guard let smartList = smartLists.first(where: { $0.id == id }) else {
                return Self(label: .localized("Smart List Not Found"))
            }
            return Self(
                label: smartList.isPreset
                    ? .localized(smartList.name)
                    : .verbatim(smartList.name)
            )
        case .primary, .review:
            return Self(label: .localized("Project Not Found"))
        }
    }
}
```

Keep the initializer internal so callers cannot bypass the route factories and
construct invalid badge or localization states. The inner `ReviewRoute` switch
must remain exhaustive without `default`; compare the explicit review fixture
keys with `ReviewRoute.allCases` so a future destination cannot silently fall
back to Review.

- [ ] **Step 4: Run GREEN tests**

```bash
test "$(swift test list | rg -c 'ProjectBoardCompactNavigationPresentationTests')" -gt 0
swift test --filter ProjectBoardCompactNavigationPresentationTests
swift test --filter ProjectBoardRouteTests
```

Expected: all tests pass.

- [ ] **Step 5: Commit the policy**

```bash
git add Sources/SuisuiCore/App/ProjectBoardCompactNavigationPresentation.swift \
  Tests/SuisuiCoreTests/ProjectBoardCompactNavigationPresentationTests.swift
git commit -m "feat: model compact navigation context"
```

---

### Task 3: Inbox Selected Item Context

**Files:**

- Modify: `Sources/SuisuiApp/Views/ProjectWorkflowInboxView.swift`
- Read only: root-owned localization files and `AppExperienceSourceTests.swift`

- [ ] **Step 1: Confirm the root-owned failing source contract**

The root agent adds this exact test in Task 0 before assigning the Inbox view.
The Inbox worker reads but must not edit the shared test file:

```swift
func testInboxActionPanelShowsSelectedContextWithoutDuplicatingVoiceMetadata() throws {
    let source = try readPackageFile("Sources/SuisuiApp/Views/ProjectWorkflowInboxView.swift")

    let context = try XCTUnwrap(source.range(of: "InboxSelectedItemContext("))
    let voice = try XCTUnwrap(source.range(of: "InboxVoiceIntakeDetail("))
    let actions = try XCTUnwrap(source.range(of: "LazyVGrid(columns: actionGridColumns"))
    XCTAssertLessThan(context.lowerBound, voice.lowerBound)
    XCTAssertLessThan(voice.lowerBound, actions.lowerBound)
    let contextCall = String(source[context.lowerBound..<voice.lowerBound])

    let contextDefinitionStart = try XCTUnwrap(
        source.range(of: "private struct InboxSelectedItemContext")
    )
    let contextDefinitionEnd = try XCTUnwrap(
        source.range(
            of: "private struct InboxVoiceIntakeDetail",
            range: contextDefinitionStart.upperBound..<source.endIndex
        )
    )
    let contextDefinition = String(
        source[contextDefinitionStart.lowerBound..<contextDefinitionEnd.lowerBound]
    )
    let actionPanelStart = try XCTUnwrap(
        source.range(of: "private struct InboxActionPanel")
    )
    let actionPanelEnd = try XCTUnwrap(
        source.range(
            of: "private var actionGridColumns",
            range: actionPanelStart.upperBound..<source.endIndex
        )
    )
    let actionPanel = String(
        source[actionPanelStart.lowerBound..<actionPanelEnd.lowerBound]
    )
    let selectionChangeStart = try XCTUnwrap(
        source.range(of: ".onChange(of: viewModel.selectedTaskID)")
    )
    let selectionChangeEnd = try XCTUnwrap(
        source.range(
            of: "private var mainSurface",
            range: selectionChangeStart.upperBound..<source.endIndex
        )
    )
    let selectionChange = String(
        source[selectionChangeStart.lowerBound..<selectionChangeEnd.lowerBound]
    )

    XCTAssertTrue(source.contains(".accessibilityIdentifier(\"inbox-selected-context\")"))
    XCTAssertTrue(source.contains("Select an Inbox item to classify."))
    XCTAssertTrue(contextDefinition.contains("lineLimit(2)"))
    XCTAssertTrue(contextDefinition.contains("lineLimit(3)"))
    XCTAssertTrue(contextDefinition.contains(".accessibilityElement(children: .combine)"))
    XCTAssertTrue(
        contextCall.contains(
            "manualSummary: task != nil && viewModel.selectedInboxCaptureRecords.isEmpty"
        )
    )
    XCTAssertTrue(
        actionPanel.contains(".accessibilityLabel(\"Inbox classification actions\")")
    )
    XCTAssertFalse(actionPanel.contains(".accessibilityValue("))
    XCTAssertTrue(
        selectionChange.contains(
            "let capture = viewModel.selectedInboxCaptureRecords.first"
        )
    )
    XCTAssertTrue(selectionChange.contains("voiceMemoCaptureID = capture?.id"))
    XCTAssertTrue(selectionChange.contains("voiceMemoDraft = capture?.memo ?? \"\""))
}
```

- [ ] **Step 2: Verify RED and method existence**

```bash
test "$(swift test list | rg -c 'testInboxActionPanelShowsSelectedContextWithoutDuplicatingVoiceMetadata')" -eq 1
if swift test --filter testInboxActionPanelShowsSelectedContextWithoutDuplicatingVoiceMetadata; then
  echo "Expected Inbox source contract to fail before implementation" >&2
  exit 1
fi
```

Expected: test failure because selected context and reset contract are absent.

- [ ] **Step 3: Add the selected context view**

Insert an App-private view:

```swift
private struct InboxSelectedItemContext: View {
    let task: ProjectBoardTask?
    let manualSummary: InboxTriageSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Selected Item")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if let task {
                Text(task.title)
                    .font(.headline)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                let detail = normalizedDetail(task.detail)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .help(detail)
                }

                if let manualSummary {
                    LabeledContent("Source") {
                        Text(LocalizedStringKey(manualSummary.sourceLabel))
                    }
                    LabeledContent("Interpretation") {
                        Text(LocalizedStringKey(manualSummary.interpretationLabel))
                    }
                    .font(.caption)
                }
            } else {
                Text("Select an Inbox item to classify.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inbox-selected-context")
    }

    private func normalizedDetail(_ detail: String) -> String {
        detail
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
```

Render it immediately after `Classify Selected Item`. Pass `manualSummary` only when a task exists and `viewModel.selectedInboxCaptureRecords.isEmpty`; keep `InboxVoiceIntakeDetail` as the only owner of voice Source / Interpretation.

- [ ] **Step 4: Remove duplicate parent AX metadata and reset memo state on selection**

The action panel AX value must contain selected title/detail only. Do not append transcript or interpretation owned by the child voice detail.

At the Inbox workflow root:

```swift
.onChange(of: viewModel.selectedTaskID) {
    let capture = viewModel.selectedInboxCaptureRecords.first
    voiceMemoCaptureID = capture?.id
    voiceMemoDraft = capture?.memo ?? ""
}
```

Hydrate instead of clearing unconditionally: SwiftUI may call the child
`capture.id` observer before the parent selection observer, so clearing in the
parent can erase the newly loaded saved memo and enable an accidental empty
save. Preserve the child reset by capture ID and every existing action
identifier/shortcut.

The selected context child is the only AX owner of title/detail. Keep the parent
action panel as a container with the generic `Inbox classification actions`
label, generic classification hint, and identifier; do not attach a duplicate
title/detail/voice accessibility value.

- [ ] **Step 5: Use the root-owned English and Japanese localization keys**

Task 0 adds:

```text
"Selected Item" = "Selected Item";
"Select an Inbox item to classify." = "Select an Inbox item to classify.";
"Transcript failed" = "Transcript failed";
"Transcript pending" = "Transcript pending";
"AI interpreted" = "AI interpreted";
```

and:

```text
"Selected Item" = "選択中の項目";
"Select an Inbox item to classify." = "分類する受信箱の項目を選択してください。";
"Transcript failed" = "文字起こしに失敗";
"Transcript pending" = "文字起こし待ち";
"AI interpreted" = "AI解釈済み";
```

Reuse existing Source、Interpretation、Manual、Voice、Unprocessed、Transcript ready.

- [ ] **Step 6: Run GREEN tests and build**

```bash
test "$(swift test list | rg -c 'testInboxActionPanelShowsSelectedContextWithoutDuplicatingVoiceMetadata')" -eq 1
swift test --filter testInboxActionPanelShowsSelectedContextWithoutDuplicatingVoiceMetadata
swift test --filter AppExperienceSourceTests
swift build --product Suisui
./script/check_runtime_inbox_triage_smoke.sh
```

Expected: focused and source suites pass, app builds, runtime triage smoke exits 0.

- [ ] **Step 7: Commit Inbox context**

```bash
git add Sources/SuisuiApp/Views/ProjectWorkflowInboxView.swift
git commit -m "feat: show selected inbox context"
```

---

### Task 4: Stage-Aware Assistant Queue Controls

**Files:**

- Modify: `Sources/SuisuiApp/Views/ProjectWorkflowAssistantQueueView.swift`
- Read only: root-owned localization files and `AppExperienceSourceTests.swift`

- [ ] **Step 1: Confirm the root-owned failing stage-aware contract**

The root agent replaces the obsolete contract with this exact test in Task 0.
The Queue worker reads but must not edit the shared test file:

```swift
func testAssistantQueueRowUsesStageSpecificPrimaryActionAndSecondaryMenu() throws {
    let source = try readPackageFile("Sources/SuisuiApp/Views/ProjectWorkflowAssistantQueueView.swift")

    XCTAssertTrue(source.contains("AssistantQueueRowActionPresentation.make(for: row)"))
    XCTAssertTrue(source.contains("assistant-queue-more-\\(row.id)"))
    XCTAssertTrue(source.contains("case .approve:"))
    XCTAssertTrue(source.contains("case .run:"))
    XCTAssertTrue(source.contains("case .reopen:"))
    let rejectCase = try XCTUnwrap(source.range(of: "case .reject:"))
    let destructiveButton = try XCTUnwrap(
        source.range(
            of: "Button(role: .destructive)",
            range: rejectCase.upperBound..<source.endIndex
        )
    )
    let rejectHandler = try XCTUnwrap(
        source.range(
            of: "viewModel.rejectAssistantQueueItem(id: row.id)",
            range: destructiveButton.upperBound..<source.endIndex
        )
    )
    XCTAssertLessThan(
        source.distance(from: rejectCase.lowerBound, to: rejectHandler.lowerBound),
        500
    )
    XCTAssertFalse(source.contains(".disabled(!row.canRun)"))
    XCTAssertFalse(source.contains(".disabled(!row.canApprove)"))
    XCTAssertFalse(source.contains(".disabled(!row.canRetry)"))
}
```

Update existing assertions that require all six buttons to exist simultaneously.

- [ ] **Step 2: Verify RED**

```bash
test "$(swift test list | rg -c 'testAssistantQueueRowUsesStageSpecificPrimaryActionAndSecondaryMenu')" -eq 1
if swift test --filter testAssistantQueueRowUsesStageSpecificPrimaryActionAndSecondaryMenu; then
  echo "Expected Queue source contract to fail before implementation" >&2
  exit 1
fi
```

Expected: failure because the old HStack still renders every disabled action.

- [ ] **Step 3: Add action rendering helpers**

Add:

```swift
private var actionPresentation: AssistantQueueRowActionPresentation {
    .make(for: row)
}

@ViewBuilder
private func primaryAction(_ action: AssistantQueueRowActionPresentation.Action) -> some View {
    switch action {
    case .approve:
        approveButton
    case .run:
        runButton
    case .reopen:
        reopenButton
    case .edit, .defer, .reject:
        EmptyView()
    }
}
```

Extract existing handlers, labels, help, hints, and identifiers into `approveButton`, `runButton`, `reopenButton`, `editButton`, `deferButton`, and `rejectButton`. Do not change ViewModel methods.

Render:

```swift
HStack(spacing: 8) {
    if let primary = actionPresentation.primaryAction {
        primaryAction(primary)
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
    }

    if !actionPresentation.secondaryActions.isEmpty {
        Menu {
            ForEach(actionPresentation.secondaryActions, id: \.self) { action in
                secondaryAction(action)
            }
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
        .controlSize(.small)
        .help("More Assistant Queue actions")
        .accessibilityIdentifier("assistant-queue-more-\(row.id)")
    }
}
```

Reject must be a separate `Button(role: .destructive)` and the last menu item.

- [ ] **Step 4: Implement keyboard and VoiceOver focus**

Add:

```swift
private enum ActionFocus: Hashable {
    case editReason
    case more
}

@FocusState private var keyboardActionFocus: ActionFocus?
@AccessibilityFocusState private var accessibilityActionFocus: ActionFocus?
```

Apply `.focused(..., equals: .editReason)` and `.accessibilityFocused(..., equals: .editReason)` to the review reason field. Apply the `.more` bindings to the More menu.

After Edit opens:

```swift
Task { @MainActor in
    await Task.yield()
    keyboardActionFocus = .editReason
    accessibilityActionFocus = .editReason
}
```

After successful Save or Cancel:

```swift
Task { @MainActor in
    await Task.yield()
    keyboardActionFocus = .more
    accessibilityActionFocus = .more
}
```

On Save failure, preserve the form and focus.

- [ ] **Step 5: Use the root-owned More localization**

Task 0 adds:

```text
"More Assistant Queue actions" = "More Assistant Queue actions";
```

and:

```text
"More Assistant Queue actions" = "Assistant Queueのその他の操作";
```

- [ ] **Step 6: Run UI and runtime tests**

```bash
test "$(swift test list | rg -c 'testAssistantQueueRowUsesStageSpecificPrimaryActionAndSecondaryMenu')" -eq 1
swift test --filter AssistantQueueRowActionPresentationTests
swift test --filter testAssistantQueueRowUsesStageSpecificPrimaryActionAndSecondaryMenu
swift test --filter AppExperienceSourceTests
swift build --product Suisui
./script/check_runtime_development_pr_smoke.sh
```

Expected: all pass; runtime still performs Approve → Run → receipt using fake Git/GitHub runners.

- [ ] **Step 7: Commit Queue UI**

```bash
git add Sources/SuisuiApp/Views/ProjectWorkflowAssistantQueueView.swift
git commit -m "feat: stage assistant queue controls"
```

---

### Task 5: Contextual Compact Navigation UI

**Files:**

- Modify: `Sources/SuisuiApp/Views/ProjectBoardReviewHubView.swift`
- Modify: `Sources/SuisuiApp/Views/ProjectBoardProjectsHubView.swift`
- Read only: root-owned localization files and `AppExperienceSourceTests.swift`

- [ ] **Step 1: Confirm the root-owned failing SwiftUI source contract**

The root agent adds this exact test in Task 0. The compact navigation worker
reads but must not edit the shared test file:

```swift
func testCompactHubLabelsUseTypedPresentationAndPreserveDestinationParity() throws {
    let review = try readPackageFile("Sources/SuisuiApp/Views/ProjectBoardReviewHubView.swift")
    let projects = try readPackageFile("Sources/SuisuiApp/Views/ProjectBoardProjectsHubView.swift")

    XCTAssertTrue(review.contains("ProjectBoardCompactNavigationPresentation.review("))
    XCTAssertTrue(projects.contains("ProjectBoardCompactNavigationPresentation.projects("))
    XCTAssertTrue(review.contains("case .localized"))
    XCTAssertTrue(projects.contains("case .verbatim"))
    XCTAssertFalse(review.contains("Label(\"Choose Review View\""))
    XCTAssertFalse(projects.contains("Label(\"Choose Project View\""))

    for identifier in [
        "review-hub-compact-destination-schedule",
        "review-hub-compact-destination-completed",
        "review-hub-compact-destination-automation-activity",
        "review-hub-compact-destination-assistant-queue"
    ] {
        XCTAssertTrue(review.contains(identifier))
    }
}
```

- [ ] **Step 2: Verify RED**

```bash
test "$(swift test list | rg -c 'testCompactHubLabelsUseTypedPresentationAndPreserveDestinationParity')" -eq 1
if swift test --filter testCompactHubLabelsUseTypedPresentationAndPreserveDestinationParity; then
  echo "Expected compact navigation source contract to fail before implementation" >&2
  exit 1
fi
```

Expected: failure because the labels remain fixed.

- [ ] **Step 3: Render the typed label in both hubs**

Use:

```swift
@ViewBuilder
private func compactLabel(
    _ presentation: ProjectBoardCompactNavigationPresentation
) -> some View {
    HStack(spacing: 6) {
        Image(systemName: "sidebar.left")
        switch presentation.label {
        case .localized(let key):
            Text(LocalizedStringKey(key))
        case .verbatim(let value):
            Text(verbatim: value)
        }
        if let count = presentation.badgeCount {
            Text("\(count)")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .accessibilityLabel(localizedCount(
                    count,
                    one: "%d item needs attention",
                    other: "%d items need attention"
                ))
        }
    }
}
```

Review obtains:

```swift
let presentation = ProjectBoardCompactNavigationPresentation.review(
    route: route,
    assistantQueueCount: assistantQueueCount
)
```

Projects obtains:

```swift
let presentation = ProjectBoardCompactNavigationPresentation.projects(
    route: route,
    projects: projects,
    smartLists: smartLists
)
```

Keep every existing menu destination, action, binding, and accessibility identifier.
Add `.help("Choose Review destination.")` to the Review Menu and
`.help("Choose Project destination.")` to the Projects Menu. The current label
explains location; the help still explains the control's action. The Queue
badge must expose the existing localized “items need attention” phrase instead
of an unexplained bare number.

- [ ] **Step 4: Use the root-owned missing-state localization**

Task 0 adds:

```text
"Smart List Not Found" = "Smart List Not Found";
"Choose Review destination." = "Choose Review destination.";
"Choose Project destination." = "Choose Project destination.";
```

and:

```text
"Smart List Not Found" = "スマートリストが見つかりません";
"Choose Review destination." = "レビューの移動先を選択します。";
"Choose Project destination." = "プロジェクトの移動先を選択します。";
```

Reuse existing Project Not Found and destination strings.

- [ ] **Step 5: Run GREEN tests and build**

```bash
test "$(swift test list | rg -c 'testCompactHubLabelsUseTypedPresentationAndPreserveDestinationParity')" -eq 1
swift test --filter ProjectBoardCompactNavigationPresentationTests
swift test --filter testCompactHubLabelsUseTypedPresentationAndPreserveDestinationParity
swift test --filter AppExperienceSourceTests
swift build --product Suisui
```

Expected: all pass.

- [ ] **Step 6: Commit compact navigation**

```bash
git add Sources/SuisuiApp/Views/ProjectBoardReviewHubView.swift \
  Sources/SuisuiApp/Views/ProjectBoardProjectsHubView.swift
git commit -m "feat: preserve compact navigation context"
```

---

### Task 6: Approval Flow Accessibility Contract

**Files:**

- Modify: `Sources/SuisuiCore/App/AccessibilityFocusPathAudit.swift`
- Modify: `Tests/SuisuiCoreTests/AccessibilityFocusPathAuditTests.swift`
- Modify: `Tests/SuisuiCoreTests/SuisuiHarnessTests.swift`
- Modify: `script/check_pseudo_voiceover_paths.sh`

- [ ] **Step 1: Write a failing approval-flow focus test**

Add:

```swift
func testApprovalFlowRequiresInboxContextCompactNavigationAndQueueActions() {
    let nodes = [
        node("inbox-selected-context", role: .group, label: "Selected Item"),
        node("inbox-action-grid", role: .group, label: "Inbox classification actions"),
        node("review-hub-compact-navigation", role: .button, label: "Assistant Queue", help: "Choose Review destination."),
        node("projects-hub-compact-navigation", role: .button, label: "Suisui Release", help: "Choose Project destination."),
        node("assistant-queue-workflow", role: .group, label: "Assistant Queue"),
        node("assistant-queue-approve-visual-waiting", role: .button, label: "Approve", help: "Records approval without running."),
        node("assistant-queue-more-visual-waiting", role: .button, label: "More", help: "Opens secondary actions."),
        node("assistant-queue-edit-visual-waiting", role: .button, label: "Edit", help: "Edits review details."),
        node("assistant-queue-edit-reason-visual-waiting", role: .textField, label: "Review reason"),
        node("assistant-queue-edit-save-visual-waiting", role: .button, label: "Save", help: "Saves review edits."),
        node("assistant-queue-edit-cancel-visual-waiting", role: .button, label: "Cancel", help: "Discards review edits.")
    ]

    let result = AccessibilityFocusPathAudit().audit(
        nodes: nodes,
        requirements: .approvalFlowReview
    )

    XCTAssertTrue(result.findings.isEmpty, result.findings.map(\.message).joined(separator: "\n"))
}
```

In the same test method, audit separate approved and failed fixtures with
`.approvalFlowExecution` and `.approvalFlowRecovery`. Add separate failures for
missing stage-specific Primary, missing More/Edit path in review/execution,
and out-of-order nodes. A fixture must never be required to expose Approve,
Run, and Reopen simultaneously.

- [ ] **Step 2: Verify RED**

```bash
test "$(rg -c 'func testApprovalFlowRequiresInboxContextCompactNavigationAndQueueActions' Tests/SuisuiCoreTests/AccessibilityFocusPathAuditTests.swift)" -eq 1
if swift test --filter testApprovalFlowRequiresInboxContextCompactNavigationAndQueueActions; then
  echo "Expected approval-flow accessibility contract to fail before implementation" >&2
  exit 1
fi
```

Expected: compile failure because the three approval-flow requirements do not
exist.

- [ ] **Step 3: Add state-specific requirements**

```swift
private static let approvalFlowContextNodeIDs = [
    "inbox-selected-context",
    "inbox-action-grid",
    "review-hub-compact-navigation",
    "projects-hub-compact-navigation",
    "assistant-queue-workflow"
]

public static let approvalFlowReview = AccessibilityFocusPathRequirement(
    requiredNodeIDs: approvalFlowContextNodeIDs + [
        "assistant-queue-approve",
        "assistant-queue-more",
        "assistant-queue-edit",
        "assistant-queue-edit-reason",
        "assistant-queue-edit-save",
        "assistant-queue-edit-cancel"
    ],
    dynamicRequiredNodeIDPrefixes: [
        "assistant-queue-approve",
        "assistant-queue-more",
        "assistant-queue-edit",
        "assistant-queue-edit-reason",
        "assistant-queue-edit-save",
        "assistant-queue-edit-cancel"
    ]
)

public static let approvalFlowExecution = AccessibilityFocusPathRequirement(
    requiredNodeIDs: approvalFlowContextNodeIDs + [
        "assistant-queue-run",
        "assistant-queue-more",
        "assistant-queue-edit",
        "assistant-queue-edit-reason",
        "assistant-queue-edit-save",
        "assistant-queue-edit-cancel"
    ],
    dynamicRequiredNodeIDPrefixes: [
        "assistant-queue-run",
        "assistant-queue-more",
        "assistant-queue-edit",
        "assistant-queue-edit-reason",
        "assistant-queue-edit-save",
        "assistant-queue-edit-cancel"
    ]
)

public static let approvalFlowRecovery = AccessibilityFocusPathRequirement(
    // Failed rows have no current secondary capability in the production read
    // model, so recovery requires Reopen but not More.
    requiredNodeIDs: approvalFlowContextNodeIDs + [
        "assistant-queue-retry"
    ],
    dynamicRequiredNodeIDPrefixes: [
        "assistant-queue-retry"
    ]
)
```

The test suite must separately exercise Approve, Run, and Reopen variants
because a single runtime row never contains all three Primary actions.

- [ ] **Step 4: Extend pseudo VoiceOver marker enforcement**

Add approval-flow identifiers, `ProjectWorkflowInboxView.swift`, `ProjectWorkflowAssistantQueueView.swift`, `ProjectBoardReviewHubView.swift`, and `ProjectBoardProjectsHubView.swift` to `check_pseudo_voiceover_paths.sh`.

The success line becomes:

```bash
echo "OK: pseudo VoiceOver focus path contract covers task lifecycle, Today cockpit, and approval flow markers"
```

- [ ] **Step 5: Add harness coverage**

Use all three state-specific requirements in `SuisuiHarnessTests`. Prove the
review and execution fixtures pass, removing `assistant-queue-more-*` from
either produces `.missingRequiredNode`, and the recovery fixture passes without
a More menu.

- [ ] **Step 6: Run GREEN tests**

```bash
test "$(swift test list | rg -c 'testApprovalFlowRequiresInboxContextCompactNavigationAndQueueActions')" -eq 1
swift test --filter AccessibilityFocusPathAuditTests
swift test --filter SuisuiHarnessTests
./script/check_pseudo_voiceover_paths.sh --swift-test
```

Expected: all pass and the script prints the new approval-flow success line.

- [ ] **Step 7: Commit the accessibility contract**

```bash
git add Sources/SuisuiCore/App/AccessibilityFocusPathAudit.swift \
  Tests/SuisuiCoreTests/AccessibilityFocusPathAuditTests.swift \
  Tests/SuisuiCoreTests/SuisuiHarnessTests.swift \
  script/check_pseudo_voiceover_paths.sh
git commit -m "test: enforce approval flow accessibility"
```

---

### Task 7: Locale-Separated Visual Evidence

**Files:**

- Modify: `Package.swift`
- Create: `Sources/SuisuiVisualFixtureSeeder/main.swift`
- Modify: `script/capture_ui_evidence.sh`
- Modify: `docs/quality/visual-baseline-manifest.json`
- Create: `docs/quality/visual-baseline-manifest-ja.json`
- Modify: `docs/quality/visual-baselines.md`
- Modify: `Tests/SuisuiCoreTests/ReleasePipelineTests.swift`
- Modify: `Tests/SuisuiCoreTests/UIGateScriptsTests.swift`
- Modify: `Tests/SuisuiCoreTests/VisualEvidenceRuntimeContextTests.swift`
- Add: English/Japanese screenshot PNG and metadata under their separated roots

- [ ] **Step 1: Write failing manifest and capture tests**

Add these exact test methods:

```swift
func testCaptureUsesLocaleSpecificManifestOverrideWithoutMixingArtifacts() throws
func testCaptureRejectsSymlinkManifestBeforeInvalidatingReceipt() throws
func testJapaneseVisualManifestUsesJaContextAndSeparateRoots() throws
func testApprovalFlowScreensExistInBothLocaleManifests() throws
```

The assertions must require:

```swift
XCTAssertTrue(capture.contains(
    "VISUAL_BASELINE_MANIFEST=\"${SUISUI_VISUAL_BASELINE_MANIFEST:-$ROOT_DIR/docs/quality/visual-baseline-manifest.json}\""
))
XCTAssertEqual(jaContext["locale"] as? String, "ja-JP")
XCTAssertEqual(jaManifest["artifactRoot"] as? String, "docs/release/evidence/ui-screenshots-ja")
XCTAssertEqual(jaManifest["baselineRoot"] as? String, "docs/quality/visual-baselines-ja")
XCTAssertTrue(screenIDs.isSuperset(of: [
    "inbox",
    "inbox-voice",
    "projects-overview",
    "assistant-queue-waiting-review",
    "assistant-queue-approved",
    "assistant-queue-failed"
]))
```

- [ ] **Step 2: Verify RED**

```bash
swift test --filter testCaptureUsesLocaleSpecificManifestOverrideWithoutMixingArtifacts
swift test --filter testCaptureRejectsSymlinkManifestBeforeInvalidatingReceipt
swift test --filter testJapaneseVisualManifestUsesJaContextAndSeparateRoots
swift test --filter testApprovalFlowScreensExistInBothLocaleManifests
```

Expected: failures because override, Japanese manifest, and Queue screens are absent.

- [ ] **Step 3: Add fail-closed manifest override**

Change:

```bash
VISUAL_BASELINE_MANIFEST="${SUISUI_VISUAL_BASELINE_MANIFEST:-$ROOT_DIR/docs/quality/visual-baseline-manifest.json}"
```

After locale resolution, add a fail-closed manifest check that exits with
`BLOCKER` unless:

- manifest is a regular file under the repository;
- `baselineContext.locale == EVIDENCE_RECEIPT_LOCALE`;
- `artifactRoot == relative_path "$SCREENSHOT_DIR"`.

Do this before launching the app or deleting an existing AX receipt.

Implement that contract immediately after the `EVIDENCE_RECEIPT_LOCALE` mapping,
before the existing receipt invalidation block:

```bash
if [[ ! -f "$VISUAL_BASELINE_MANIFEST" || -L "$VISUAL_BASELINE_MANIFEST" ]]; then
  echo "BLOCKER: visual baseline manifest is not a regular file: $VISUAL_BASELINE_MANIFEST" >&2
  exit 1
fi

manifest_directory="$(cd "$(dirname "$VISUAL_BASELINE_MANIFEST")" && pwd -P)"
case "$manifest_directory/" in
  "$ROOT_DIR/"*) ;;
  *)
    echo "BLOCKER: visual baseline manifest must be stored under the repository" >&2
    exit 1
    ;;
esac

manifest_locale="$(
  /usr/bin/plutil -extract baselineContext.locale raw -o - "$VISUAL_BASELINE_MANIFEST"
)"
manifest_artifact_root="$(
  /usr/bin/plutil -extract artifactRoot raw -o - "$VISUAL_BASELINE_MANIFEST"
)"
case "$SCREENSHOT_DIR" in
  "$ROOT_DIR"/*) expected_artifact_root="${SCREENSHOT_DIR#"$ROOT_DIR/"}" ;;
  *) expected_artifact_root="$SCREENSHOT_DIR" ;;
esac

if [[ "$manifest_locale" != "$EVIDENCE_RECEIPT_LOCALE" ]]; then
  echo "BLOCKER: manifest locale $manifest_locale does not match runtime locale $EVIDENCE_RECEIPT_LOCALE" >&2
  exit 1
fi
if [[ "$manifest_artifact_root" != "$expected_artifact_root" ]]; then
  echo "BLOCKER: manifest artifactRoot $manifest_artifact_root does not match screenshot directory $expected_artifact_root" >&2
  exit 1
fi
```

Keep the repository-containment comment next to this check: evidence overrides are
accepted for locale separation, not for reading arbitrary manifests outside the
checkout. Rejecting a final-component symlink is required; resolving only the
parent directory is insufficient because an in-repository symlink could target
an external regular file. Add a script test that proves such a symlink fails
before the old AX receipt is deleted.

- [ ] **Step 4: Seed the three Queue visual states**

Extend the isolated evidence SQLite fixture with valid action-plan rows:

```text
visual-waiting  state=waitingReview  allowed cost preview  no approval
visual-approved state=approved       current fingerprint approval
visual-failed   state=failed         safe retryable payload and blocking reason
```

Never use dangerous payloads or external production connectors. The fixture IDs must remain stable so AX targets are:

```text
assistant-queue-row-visual-waiting
assistant-queue-row-visual-approved
assistant-queue-row-visual-failed
```

Add a development-only executable product and target:

```swift
.executable(
    name: "SuisuiVisualFixtureSeeder",
    targets: ["SuisuiVisualFixtureSeeder"]
)
```

```swift
.executableTarget(
    name: "SuisuiVisualFixtureSeeder",
    dependencies: ["SuisuiCore"]
)
```

`Sources/SuisuiVisualFixtureSeeder/main.swift` accepts exactly the
`--database "$DATABASE_PATH" --evidence-home "$EVIDENCE_HOME"` argument shape.
Resolve symlinks and standardize both URLs, then require the database URL to be
a descendant of the evidence-home URL. This is a development evidence tool; it
must reject every other argument and never accept connector credentials.

The seeder must:

1. create the Queue schema through the production SQLite migration path;
2. construct all three rows through `AssistantQueueItem` and
   `SQLiteAssistantQueueStore`, never by hand-writing approval JSON;
3. use the stable IDs above and the same inert plan shape for every row:

```swift
ActionPlan(
    id: "\(fixtureID)-plan",
    userInput: "Prepare local visual evidence",
    summary: "Prepare local visual evidence",
    actions: [
        PlanAction(
            id: "\(fixtureID)-action",
            tool: .taskCreate,
            arguments: [
                "title": .string("Review local visual evidence"),
                "detail": .string("Visual fixture only; no external connector is invoked.")
            ],
            riskLevel: .write
        )
    ],
    riskLevel: .write,
    requiresApproval: true
)
```

Create each waiting item with `AssistantQueueAdapter.makeItem`, replace its
generated ID with the stable fixture ID, and save it to
`SQLiteAssistantQueueStore(path:)`.

4. transition `visual-approved` with
   `AssistantQueueStateMachine.approve(_:reviewerID:)` so its approval
   fingerprint is current;
5. transition `visual-failed` through the complete production chain
   `approve → startRunning → markFailed(reason:)`, using
   `visual-evidence-simulated-failure` as the non-secret reason;
6. assert after seeding that the read models expose respectively `.approve`,
   `.run`, and `.reopen` as their primary actions.

The capture script calls:

```bash
swift build --product SuisuiVisualFixtureSeeder
visual_fixture_bin="$(swift build --show-bin-path)/SuisuiVisualFixtureSeeder"
"$visual_fixture_bin" \
  --database "$DATABASE_PATH" \
  --evidence-home "$EVIDENCE_HOME"
```

This avoids unsupported ad-hoc linking against `.build` and keeps the seeder in
the product-source commit recorded by visual evidence.

- [ ] **Step 5: Add capture targets and manifests**

Add Light/Dark artifacts for:

```json
[
  {
    "id": "assistant-queue-waiting-review",
    "viewport": {"width": 1024, "height": 676},
    "axTargetIdentifier": "assistant-queue-row-visual-waiting"
  },
  {
    "id": "assistant-queue-approved",
    "viewport": {"width": 1024, "height": 676},
    "axTargetIdentifier": "assistant-queue-row-visual-approved"
  },
  {
    "id": "assistant-queue-failed",
    "viewport": {"width": 1024, "height": 676},
    "axTargetIdentifier": "assistant-queue-row-visual-failed"
  }
]
```

Each capture requires `review-hub-compact-navigation`, `assistant-queue-workflow`, the state row, the state Primary identifier, and `assistant-queue-more-*` when secondary actions exist.

Copy the complete 39-screen manifest contract to the Japanese manifest, then
change artifact/baseline roots and locale. Also localize manifest OCR
expectations: keep the user-entered English line
`project board to task card to`, but replace `In Progress High` with
`進行中 高` and `Jul 10` with `7月10日`. Do not mix en-US and ja-JP artifacts
under one root, and do not retain English localized status/date expectations in
the ja-JP manifest.

- [ ] **Step 6: Run source and dry-run checks**

```bash
test "$(swift test list | rg -c 'testCaptureUsesLocaleSpecificManifestOverrideWithoutMixingArtifacts')" -eq 1
test "$(swift test list | rg -c 'testCaptureRejectsSymlinkManifestBeforeInvalidatingReceipt')" -eq 1
test "$(swift test list | rg -c 'testJapaneseVisualManifestUsesJaContextAndSeparateRoots')" -eq 1
test "$(swift test list | rg -c 'testApprovalFlowScreensExistInBothLocaleManifests')" -eq 1
swift test --filter testCaptureUsesLocaleSpecificManifestOverrideWithoutMixingArtifacts
swift test --filter testCaptureRejectsSymlinkManifestBeforeInvalidatingReceipt
swift test --filter testJapaneseVisualManifestUsesJaContextAndSeparateRoots
swift test --filter testApprovalFlowScreensExistInBothLocaleManifests
./script/capture_ui_evidence.sh --dry-run
```

Expected: tests pass and dry-run validates both manifest/capture contracts without product mutation.

- [ ] **Step 7: Commit source before live capture**

The capture script rejects dirty product sources. Commit the script, tests, and manifests before capture:

```bash
git add Package.swift \
  Sources/SuisuiVisualFixtureSeeder/main.swift \
  script/capture_ui_evidence.sh \
  docs/quality/visual-baseline-manifest.json \
  docs/quality/visual-baseline-manifest-ja.json \
  docs/quality/visual-baselines.md \
  Tests/SuisuiCoreTests/ReleasePipelineTests.swift \
  Tests/SuisuiCoreTests/UIGateScriptsTests.swift \
  Tests/SuisuiCoreTests/VisualEvidenceRuntimeContextTests.swift
git commit -m "test: add locale-separated approval visuals"
```

- [ ] **Step 8: Capture English and Japanese evidence**

Run English:

```bash
SUISUI_UI_EVIDENCE_LOCALE=english \
SUISUI_VISUAL_BASELINE_MANIFEST="$PWD/docs/quality/visual-baseline-manifest.json" \
SUISUI_UI_EVIDENCE_DIR="$PWD/docs/release/evidence/ui-screenshots" \
SUISUI_VISUAL_AX_AUDIT_RESULT="$PWD/.tmp/visual-ax-audit-receipt.json" \
./script/capture_ui_evidence.sh
```

Run Japanese:

```bash
SUISUI_UI_EVIDENCE_LOCALE=japanese \
SUISUI_VISUAL_BASELINE_MANIFEST="$PWD/docs/quality/visual-baseline-manifest-ja.json" \
SUISUI_UI_EVIDENCE_DIR="$PWD/docs/release/evidence/ui-screenshots-ja" \
SUISUI_VISUAL_AX_AUDIT_RESULT="$PWD/.tmp/visual-ax-audit-receipt-ja.json" \
./script/capture_ui_evidence.sh
```

Expected: 39 PNG per locale, locale-matched AX receipts, no shared artifact path.

- [ ] **Step 9: Update and verify baselines**

Use explicit reviewed updates only:

```bash
./script/check_visual_regression_smoke.sh \
  --manifest docs/quality/visual-baseline-manifest.json \
  --screenshot-dir docs/release/evidence/ui-screenshots \
  --baseline-dir docs/quality/visual-baselines \
  --ax-audit-result .tmp/visual-ax-audit-receipt.json \
  --update-baselines --allow-update

./script/check_visual_regression_smoke.sh \
  --manifest docs/quality/visual-baseline-manifest-ja.json \
  --screenshot-dir docs/release/evidence/ui-screenshots-ja \
  --baseline-dir docs/quality/visual-baselines-ja \
  --ax-audit-result .tmp/visual-ax-audit-receipt-ja.json \
  --update-baselines --allow-update
```

Inspect before/after artifacts and every new PNG before committing.

- [ ] **Step 10: Commit reviewed evidence**

```bash
git add docs/release/evidence/ui-screenshots \
  docs/release/evidence/ui-screenshots-ja \
  docs/quality/visual-baselines \
  docs/quality/visual-baselines-ja \
  docs/quality/visual-baseline-manifest.json \
  docs/quality/visual-baseline-manifest-ja.json
git commit -m "test: record approval flow visual baselines"
```

If live capture is unavailable, do not create placeholder PNGs and do not mark this task complete. Record the exact AX/Screen Recording blocker separately.

---

### Task 8: Final Verification and Self-Review

**Files:**

- Modify only files required to fix findings from this task.

- [ ] **Step 1: Prove every new selector exists**

```bash
swift test list | tee .tmp/approval-flow-test-list.txt
for method in \
  AssistantQueueRowActionPresentationTests \
  ProjectBoardCompactNavigationPresentationTests \
  testAssistantQueueRowUsesStageSpecificPrimaryActionAndSecondaryMenu \
  testInboxActionPanelShowsSelectedContextWithoutDuplicatingVoiceMetadata \
  testCompactHubLabelsUseTypedPresentationAndPreserveDestinationParity \
  testApprovalFlowRequiresInboxContextCompactNavigationAndQueueActions \
  testCaptureUsesLocaleSpecificManifestOverrideWithoutMixingArtifacts \
  testCaptureRejectsSymlinkManifestBeforeInvalidatingReceipt \
  testJapaneseVisualManifestUsesJaContextAndSeparateRoots \
  testApprovalFlowScreensExistInBothLocaleManifests
do
  test "$(rg -c "$method" .tmp/approval-flow-test-list.txt)" -gt 0
done
```

Expected: every selector count is greater than zero.

- [ ] **Step 2: Run focused and integration tests**

```bash
swift test --filter AssistantQueueRowActionPresentationTests
swift test --filter ProjectBoardCompactNavigationPresentationTests
swift test --filter AppExperienceSourceTests
swift test --filter AccessibilityFocusPathAuditTests
swift test --filter AssistantQueueStoreTests
swift test --filter ProjectBoardStoreTests
swift test --filter SuisuiHarnessTests
```

Expected: all pass.

- [ ] **Step 3: Build the actual app and run runtime flows**

```bash
swift build --product Suisui
./script/check_runtime_inbox_triage_smoke.sh
./script/check_runtime_development_pr_smoke.sh
./script/check_accessibility_preflight.sh --source-only
./script/check_pseudo_voiceover_paths.sh --swift-test
```

Expected: build and every runtime/source gate pass.

- [ ] **Step 4: Run complete and security validation**

```bash
./script/run_complete_swiftpm_tests.sh
./script/check_security_regressions.sh
git diff --check
```

Expected: complete suite and security checks pass. A skipped or zero-test result is not success.

- [ ] **Step 5: Perform manual UX and accessibility review**

Verify:

- Inbox manual and voice items do not duplicate Source / Interpretation.
- Classification changes selection without retaining the previous memo.
- Review and Projects compact labels show the actual destination.
- Queue shows only Approve, Run, or Reopen as Primary.
- Running rows show no Reject or More.
- More → Edit focuses the reason field.
- Save / Cancel restores focus to More.
- English/Japanese and Light/Dark screenshots are readable at 1024×676.
- VoiceOver follows context → actions → Queue Primary → More/Edit.

- [ ] **Step 6: Run language-specific Swift review**

Use the Swift/macOS reviewer and security reviewer. Fix Important or higher findings, rerun affected focused tests, then rerun complete validation when the fix crosses a previously validated boundary.

- [ ] **Step 7: Commit review fixes separately**

```bash
git add \
  Sources/SuisuiCore/App/AssistantQueueRowActionPresentation.swift \
  Sources/SuisuiCore/App/ProjectBoardCompactNavigationPresentation.swift \
  Sources/SuisuiCore/App/AccessibilityFocusPathAudit.swift \
  Sources/SuisuiApp/Views/ProjectWorkflowInboxView.swift \
  Sources/SuisuiApp/Views/ProjectWorkflowAssistantQueueView.swift \
  Sources/SuisuiApp/Views/ProjectBoardReviewHubView.swift \
  Sources/SuisuiApp/Views/ProjectBoardProjectsHubView.swift \
  Sources/SuisuiApp/Resources/en.lproj/Localizable.strings \
  Sources/SuisuiApp/Resources/ja.lproj/Localizable.strings \
  Tests/SuisuiCoreTests/AssistantQueueRowActionPresentationTests.swift \
  Tests/SuisuiCoreTests/ProjectBoardCompactNavigationPresentationTests.swift \
  Tests/SuisuiCoreTests/AssistantQueueStoreTests.swift \
  Tests/SuisuiCoreTests/AccessibilityFocusPathAuditTests.swift \
  Tests/SuisuiCoreTests/SuisuiHarnessTests.swift \
  Tests/SuisuiCoreTests/AppExperienceSourceTests.swift \
  Tests/SuisuiCoreTests/ReleasePipelineTests.swift \
  Tests/SuisuiCoreTests/UIGateScriptsTests.swift \
  Tests/SuisuiCoreTests/VisualEvidenceRuntimeContextTests.swift \
  script/check_pseudo_voiceover_paths.sh \
  script/capture_ui_evidence.sh \
  Package.swift \
  Sources/SuisuiVisualFixtureSeeder/main.swift \
  docs/quality/visual-baseline-manifest.json \
  docs/quality/visual-baseline-manifest-ja.json \
  docs/quality/visual-baselines.md \
  docs/quality/visual-baselines \
  docs/quality/visual-baselines-ja \
  docs/release/evidence/ui-screenshots \
  docs/release/evidence/ui-screenshots-ja
git commit -m "fix: address approval flow review findings"
```

Skip this commit if there are no review fixes.

- [ ] **Step 8: Recapture and revalidate visual evidence after review**

After every review-fix commit, repeat both locale capture commands from Task 7.
Then run the non-mutating gates:

```bash
./script/check_visual_regression_smoke.sh \
  --manifest docs/quality/visual-baseline-manifest.json \
  --screenshot-dir docs/release/evidence/ui-screenshots \
  --baseline-dir docs/quality/visual-baselines \
  --ax-audit-result .tmp/visual-ax-audit-receipt.json

./script/check_visual_regression_smoke.sh \
  --manifest docs/quality/visual-baseline-manifest-ja.json \
  --screenshot-dir docs/release/evidence/ui-screenshots-ja \
  --baseline-dir docs/quality/visual-baselines-ja \
  --ax-audit-result .tmp/visual-ax-audit-receipt-ja.json
```

If an intentional reviewed source fix changes pixels, inspect the generated
diff artifacts, update only the affected locale baselines with
`--update-baselines --allow-update`, commit those evidence files as
`test: refresh approval flow visuals after review`, then rerun both commands
above without update flags. Stale source commits, AX receipts, or captures are
not completion.

- [ ] **Step 9: Confirm branch hygiene**

```bash
git status --short --branch
git log --oneline origin/main..HEAD
git diff --check origin/main...HEAD
```

Expected: clean worktree, only intentional fine-grained commits, no temporary output or secret artifact tracked.
