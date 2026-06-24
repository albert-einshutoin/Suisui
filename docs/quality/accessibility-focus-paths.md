# Accessibility Focus Paths

Status: Phase 14 automated preflight contract

Manual VoiceOver is still required for release evidence. This file defines the source/runtime focus paths that must pass before the manual screen-reader pass starts.

## Task Lifecycle And Execution

The task path covers create, content entry, edit, status execution, automation review, approved local content execution, and delete confirmation.

| Step | AX identifier | Expected role | Required behavior |
| --- | --- | --- | --- |
| Project navigation | `project-board-sidebar` | outline | User can choose Inbox, Today, Projects, or a concrete project before entering detail. |
| Project detail | `project-board-detail` | group | The selected project board or workflow region is reachable after navigation. |
| Add task | `project-header-add-task` | button | Opens the inline task composer. |
| Task title | `inline-task-title` | text field | Accepts the task title. |
| Task detail | `inline-task-detail` | text area | Accepts the task body/detail that later becomes execution context. |
| Create task | `inline-task-create` | button | Creates the task in the local SoloPM database. |
| Review task automation | `project-board-task-auto-execution-review` | button | Builds a review-only LLM plan from the configured priority, due-date, cadence, and daily budget settings. |
| Open task | `task-card-open-details` | button | Opens the task inspector without requiring pointer drag. |
| Inspector title | `task-inspector-title` | text field | Edits the selected task title before execution review. |
| Inspector detail | `task-inspector-detail` | text area | Edits the selected task detail/body before execution review. |
| Save edit | `task-inspector-save` | button | Saves task title, detail, status, priority, and due date. |
| Status controls | `task-status-move-controls` | group | Exposes the status movement region. |
| Move to In Progress | `task-status-move-in_progress-<taskID>` | button | Proves at least one concrete status move button is present, labeled with its target status, and reachable after task edits. |
| Review automation | `task-auto-execution-review` | button | Builds a review-only LLM plan for the selected task. |
| Run approved plan | `task-auto-execution-run-plan` | button | Starts only the reviewed local task step after explicit user activation and leaves a task-detail execution note plus a redacted execution receipt. |
| Delete task | `task-inspector-delete` | button | Opens a destructive confirmation instead of deleting immediately. |
| Cancel delete | `task-inspector-delete-confirmation-cancel` | button | Cancels the destructive delete confirmation and returns to the inspector without mutating local data. |
| Confirm delete | `task-inspector-delete-confirmation-confirm` | button | Confirms the destructive delete path. |

## Automation Boundary

- Task automation ranks tasks by priority and due date, but defaults to disabled.
- When enabled, the LLM request is review-only and excludes project/task delete tools.
- The first approved local execution step may move a task into active work and records a redacted receipt with task identity, priority, due date, review reason, and before/after status. External writes, completion, and destructive actions remain separate reviewed actions.
- Runtime AX checks can verify labels, help text, and confirmation anchors, but the real VoiceOver pass still records concrete observations in `docs/release/evidence/accessibility-voiceover.md`.

## Runtime Smoke To Manual Worksheet Mapping

| Runtime AX smoke marker | Manual worksheet field | What the manual pass must still prove |
| --- | --- | --- |
| `unlabeledButtons=0` | No unlabeled primary CRUD controls | No focused primary button is announced as empty or ambiguous. |
| `genericButtons=0` | No unlabeled primary CRUD controls | No primary action is exposed only as a generic button without help or child text. |
| `crudSignals=8/8` | Save Changes, Delete Task confirmation, No unlabeled primary CRUD controls | Add Task, Open task, status movement, local suggestion apply, task Save, selected-task automation review, approved execution, and Delete Task entry points are visible to AX. |
| `buttonA11ySignals=8/8` | No unlabeled primary CRUD controls | Primary task lifecycle buttons retain a concrete label, visible text, help, or child text. |
| `screenSignals=4/4` | Project navigation | Inbox, Today, Settings, and Voice Command entry points are present before manual navigation starts. |
| `focusPathSignals=6/6` | Project navigation, Project board detail, Open task, Inline Task Composer, Status controls, Task inspector | The automated focus anchors exist in lifecycle order; manual VoiceOver still verifies final spoken announcements and keyboard traversal. |

## MCP Pseudo VoiceOver Harness

`SoloPMHarnessAccessibilityAuditRunner` exposes this focus path as the `mcp-pseudo-voiceover-focus-path` harness scenario.

The harness emits one step per required AX identifier so create, edit, concrete status movement, automation review, approved execution, and destructive delete confirmation/cancel cannot pass as a single aggregate smoke result when one control is missing. Required lifecycle nodes must also have nonblank identifiers, nonblank labels, be enabled, be unique, and appear in the required traversal order; a visible but blank-id, blank-label, disabled, duplicated, or out-of-order button, field, group, or outline is treated as a failed path because keyboard and VoiceOver users cannot complete or understand the CRUD or execution step in sequence. The `task-status-move-controls` group is not enough by itself: the pseudo VoiceOver contract also requires a concrete `task-status-move-in_progress-<taskID>` button and records it against the stable `task-status-move-in_progress` prefix via `dynamicRequiredNodeIDPrefixes`, so the lifecycle proves an actual status move path without pretending repeated task-card controls have globally static identifiers. When the approved execution control is required, the harness also emits an `approved-execution-receipt` step so a visible Run approved plan button cannot pass unless the task execution leaves a redacted receipt.

`SoloPMHarnessScenario.requiredTaskLifecycleOperations` is the MCP/E2E lifecycle contract for this path. `task-mutation-flow` and `mcp-pseudo-voiceover-focus-path` must both cover `create`, `editContent`, `statusMove`, `automationReview`, `executeContent`, `approvedExecution`, and `deleteConfirmation`. Delete confirmation and approved execution stay out of hosted-MCP mutation payloads because the external relay is review-only; the harness still fails when those user-visible UI/AX paths are not represented.

`SoloPMHarnessTaskLifecycleOperation.requiredFocusNodeIDs` maps each lifecycle operation to the AX nodes that prove it, and `SoloPMHarnessScenario.requiredFocusNodeIDs(for:)` flattens those operation mappings back through the canonical VoiceOver traversal order from `AccessibilityFocusPathRequirement.taskLifecycleAndExecution`. This keeps the operation list, MCP/E2E harness, and pseudo VoiceOver path tied together: adding a lifecycle operation or AX node now requires an explicit mapping instead of relying on a prose checklist.

Approved execution evidence must be a redacted `ApprovedAutomationExecutionReceipt` with task identity, project identity, reviewed title, reviewed detail, before/after status, priority, due date, and review reason. `ProjectBoardViewModel.approvedAutomationExecutionReceipts` keeps a receipt history across a configured multi-task review so running one approved task cannot erase the remaining reviewed queue or leave later executions unproven. Missing receipts, missing receipt history, missing reviewed task content, or receipt fields that still contain secret-like content fail the pseudo VoiceOver run before manual evidence can be reused.

`script/check_pseudo_voiceover_paths.sh` is the cheap source-marker gate. Its marker list must include every `AccessibilityFocusPathRequirement.taskLifecycleAndExecution.requiredNodeIDs` entry, including task title/detail fields in the inline composer and inspector, so a release summary cannot claim create/edit coverage while only checking the action buttons. Run `script/check_pseudo_voiceover_paths.sh --swift-test` before reusing this gate as release evidence support; the option also runs `swift test --filter AccessibilityFocusPathAuditTests` and `swift test --filter SoloPMHarnessTests` so the real focus-path audit and approved execution receipt logic are proven, not only present as strings.

## Source Owners

- Pure logic: `AccessibilityFocusPathAudit`
- MCP pseudo VoiceOver harness: `SoloPMHarnessAccessibilityAuditRunner`
- Runtime AX smoke: `script/check_accessibility_preflight.sh --runtime`
- Pseudo VoiceOver source contract: `script/check_pseudo_voiceover_paths.sh --swift-test`
- Manual release evidence: `script/create_voiceover_evidence.sh`
