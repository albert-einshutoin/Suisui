# Accessibility Focus Paths

Status: Phase 14 automated preflight contract

Manual VoiceOver is still required for release evidence. This file defines the source/runtime focus paths that must pass before the manual screen-reader pass starts.

## Task Lifecycle And Execution

The task path covers task listing, create, content entry, edit, status execution, automation review, approved local content execution, task delete confirmation, project completion, and project delete cascade confirmation.

| Step | AX identifier | Expected role | Required behavior |
| --- | --- | --- | --- |
| Project navigation | `project-board-sidebar` | outline | User can choose Inbox, Today, Projects, or a concrete project before entering detail. |
| Project detail | `project-board-detail` | group | The selected project board or workflow region is reachable after navigation. |
| Task list | `project-task-list` | group | Lists the selected project's current tasks before the user creates, edits, executes, or deletes task content. |
| Add task | `project-header-add-task` | button | Opens the inline task composer. |
| Task title | `inline-task-title` | text field | Accepts the task title. |
| Task detail | `inline-task-detail` | text area | Accepts the task body/detail that later becomes execution context. |
| Create task | `inline-task-create` | button | Creates the task in the local Suisui database. |
| Review task automation | `project-board-task-auto-execution-review` | button | Prepares review-only task automation from the configured priority, due-date, cadence, and daily budget settings. |
| Open task | `task-card-open-details` | button | Opens the task inspector without requiring pointer drag. |
| Inspector title | `task-inspector-title` | text field | Edits the selected task title before execution review. |
| Inspector detail | `task-inspector-detail` | text area | Edits the selected task detail/body before execution review. |
| Save edit | `task-inspector-save` | button | Saves task title, detail, status, priority, and due date. |
| Status controls | `task-status-move-controls` | group | Exposes the status movement region. |
| Move to In Progress | `task-status-move-in_progress-<taskID>` | button | Proves at least one concrete status move button is present, labeled with its target status, and reachable after task edits. |
| Review automation | `task-auto-execution-review` | button | Prepares review-only local automation for the selected task. |
| Run approved plan | `task-auto-execution-run-plan` | button | Starts only the reviewed local task step after explicit user activation and leaves a task-detail execution note plus a redacted execution receipt. |
| Delete task | `task-inspector-delete` | button | Opens a destructive confirmation instead of deleting immediately. |
| Cancel delete | `task-inspector-delete-confirmation-cancel` | button | Cancels the destructive delete confirmation and returns to the inspector without mutating local data. |
| Confirm delete | `task-inspector-delete-confirmation-confirm` | button | Confirms the destructive delete path. |
| Complete project | `project-inspector-complete` | button | Completes the selected project through the inspector, matching the runtime CRUD smoke. |
| Delete project | `project-inspector-delete` | button | Opens a destructive confirmation before removing the project and its local task records. |
| Cancel project delete | `project-inspector-delete-confirmation-cancel` | button | Cancels the project delete confirmation and returns to the project inspector without mutating local data. |
| Confirm project delete | `project-inspector-delete-confirmation-confirm` | button | Confirms the project delete path that runtime smoke verifies as a task cascade delete. |

## Today Cockpit

The actionable Today path covers the `ui-samples/01.png` inspired cockpit: opening Today, hearing one recommendation, activating one prominent primary action, capturing a local command, opening secondary planning actions, seeing the persistent assistant rail, and reaching the rail's schedule draft, edit, subtask draft, and reminder draft actions. This automated path is not release evidence by itself; it prevents source/runtime regressions before the manual Today VoiceOver pass and fresh screenshots are captured.

| Step | AX identifier | Expected role | Required behavior |
| --- | --- | --- | --- |
| Open Today | `sidebar-destination-today` | button | User can move from navigation into the Today cockpit. |
| Today region | `today-workflow` | group | The Today surface is exposed as the selected workflow. |
| Briefing panel | `today-briefing-panel` | group | The recommendation, primary action, command input, secondary actions, and flow strip are reachable before the rail. |
| Focus recommendation | `today-focus-recommendation` | group | Announces the recommended task and reason, or the empty-state “No focus task” summary, before an action. |
| Primary action | `today-primary-action` | button | Exposes exactly one prominent action: start the recommended focus, add valid command text to Inbox when no recommendation exists, or prepare an empty Today task draft. |
| Command field | `today-command-capture-field` | text field | Captures new local work without changing existing task status. |
| Add command | `today-command-add` | button | Explicitly sends valid command text into local Inbox while the recommended focus remains the primary action. |
| Secondary actions | `today-secondary-actions-menu` | button | Opens task-draft, planning, alternative focus, schedule-draft, and completed-task display actions without competing with the single primary action. |
| Flow strip | `today-flow-strip` | group | Shows due/overdue counts and local time-block planning state. |
| Assistant rail | `today-assistant-rail` | group | Persistent right/bottom rail is reachable for selected or recommended Today work. |
| Next action | `today-rail-next-action` | group | Announces what to do next and why. |
| Task detail | `today-rail-task-detail` | group | Exposes project, status, priority, due date, notes, subtasks, and reminder summary. |
| Rail actions | `today-rail-actions-menu` | button | Groups the selected task's local schedule, edit, subtask, and approval-gated reminder actions after the primary focus action. |
| Rail schedule draft | `today-rail-schedule-block` | button | Creates a local schedule draft without writing Calendar. |
| Rail edit | `today-rail-edit-task` | button | Opens the selected task in the inspector for manual edits. |
| Rail subtask draft | `today-rail-add-subtask` | button | Prefills a local subtask draft. |
| Rail reminder draft | `today-rail-reminder-draft` | button | Prefills a reminder draft while preserving approval-gated external writes. |

`AccessibilityFocusPathRequirement.todayCockpit` is the seeded/actionable path. It assumes a recommended or selected Today task exists, so `today-primary-action` starts that focus and `today-rail-actions-menu` exposes the task-specific draft actions. `AccessibilityFocusPathRequirement.todayEmptyCockpit` covers the 0-task state: Today navigation, the “No focus task” `today-focus-recommendation`, the task-preparation `today-primary-action`, command field, `today-secondary-actions-menu`, flow landmark, and assistant rail empty detail must remain reachable without requiring `today-command-add` or the task-specific `today-rail-actions-menu`.

## Manual P0 cockpit observations

The manual release worksheet must also capture the P0 workflow cockpits that are not represented by the general task lifecycle fields.

| Manual worksheet field | Source issue | Required behavior |
| --- | --- | --- |
| Inbox voice triage | `#5 Inbox: match rich voice intake and triage detail from ui-samples/02` | The selected voice intake detail announces transcript, interpretation, source metadata, memo editing, and the make-task, schedule, review-later, and project-conversion triage actions in the Inbox rail without forcing unrelated inspector navigation. |
| Today rail actions | `#6 Today: add persistent assistant rail and next-action cockpit` | Today announces recommendation -> one primary focus action -> command capture -> secondary actions -> flow -> rail context -> task actions menu; the menu then exposes schedule draft, edit, subtask draft, and approval-gated reminder draft actions. |

## Automation Boundary

- Task automation ranks tasks by priority and due date, but defaults to disabled.
- When enabled, the LLM request is review-only and excludes project/task delete tools.
- The first approved local execution step may move a task into active work and records a redacted receipt with task identity, priority, due date, review reason, and before/after status. External writes, completion, and destructive actions remain separate reviewed actions.
- Runtime AX checks can verify labels, help text, and confirmation anchors, but the real VoiceOver pass still records concrete observations in `docs/release/evidence/accessibility-voiceover.md`.

## Voice Task Conversation Workspace

Voice CommandのConversationタブは、`voice-conversation-scope` → `voice-conversation-turn-list` → `voice-conversation-clarification`またはUnderstanding panel → `voice-conversation-queue-handoff` → `voice-conversation-composer`の順で移動する。Queue handoffは対象項目を既存の承認フローで開くだけで、会話画面から実行しない。

| Step | AX identifier | Required behavior |
| --- | --- | --- |
| Current scope | `voice-conversation-scope` | Project、Task、session stateを読み上げ、recordingやpausedを色だけに依存せず伝える。 |
| Confirmed turns | `voice-conversation-turn-list` | Providerの生出力ではなく、確認済み入力と短い構造化済み応答だけを時系列で読む。 |
| Clarification | `voice-conversation-clarification` | 不足情報が1件ある場合に先にフォーカスし、Task/Projectを変更せずキャンセルできる。 |
| Resolved target | `voice-conversation-resolved-target` | 解決した対象と理由をredacted textで読む。 |
| Proposal | `voice-conversation-proposal` | 変更案と承認要否を読み、直接実行の操作を持たない。 |
| Fact candidates | `voice-conversation-fact-candidates` | 候補の状態とsourceを読み、secret-like textを表示しない。 |
| Queue handoff | `voice-conversation-queue-handoff` | focused Assistant Queue itemへ移動し、既存approval flowへ委譲する。 |
| Composer | `voice-conversation-composer` | typed fallback、Record/Stop、clarification cancel、review送信へkeyboardで到達できる。 |

## Runtime Smoke To Manual Worksheet Mapping

| Runtime AX smoke marker | Manual worksheet field | What the manual pass must still prove |
| --- | --- | --- |
| `unlabeledButtons=0` | No unlabeled primary CRUD controls | No focused primary button is announced as empty or ambiguous. |
| `genericButtons=0` | No unlabeled primary CRUD controls | No primary action is exposed only as a generic button without help or child text. |
| `crudSignals=8/8` | Save Changes, Delete Task confirmation, No unlabeled primary CRUD controls | Add Task, Open task, status movement, local suggestion apply, task Save, selected-task automation review, approved execution, and Delete Task entry points are visible to AX. |
| `buttonA11ySignals=8/8` | No unlabeled primary CRUD controls | Primary task lifecycle buttons retain a concrete label, visible text, help, or child text. |
| `screenSignals=4/4` | Project navigation | Inbox, Today, Settings, and Voice Command entry points are present before manual navigation starts. |
| `focusPathSignals=6/6` | Project navigation, Project board detail, Open task, Inline Task Composer, Status controls, Task inspector | The automated focus anchors exist in lifecycle order; manual VoiceOver still verifies final spoken announcements and keyboard traversal. |
| `destructiveCancelSignals=1/1` | Delete Task confirmation, No keyboard trap | Cancel Delete Task is present after opening the destructive confirmation, and the manual pass still verifies it returns to the inspector without mutating local data. |

## MCP Pseudo VoiceOver Harness

`SuisuiHarnessAccessibilityAuditRunner` exposes this focus path as the `mcp-pseudo-voiceover-focus-path` harness scenario.

The harness emits one step per required AX identifier so task listing, create, edit, concrete status movement, automation review, approved execution, destructive task delete confirmation/cancel, project completion, and project delete cascade confirmation/cancel cannot pass as a single aggregate smoke result when one control is missing. Required lifecycle nodes must also have nonblank identifiers, nonblank labels, be enabled, be unique, and appear in the required traversal order; a visible but blank-id, blank-label, disabled, duplicated, or out-of-order button, field, group, or outline is treated as a failed path because keyboard and VoiceOver users cannot complete or understand the CRUD or execution step in sequence. The `task-status-move-controls` group is not enough by itself: the pseudo VoiceOver contract also requires a concrete `task-status-move-in_progress-<taskID>` button and records it against the stable `task-status-move-in_progress` prefix via `dynamicRequiredNodeIDPrefixes`, so the lifecycle proves an actual status move path without pretending repeated task-card controls have globally static identifiers. When the approved execution control is required, the harness also emits an `approved-execution-receipt` step so a visible Run approved plan button cannot pass unless the task execution leaves a redacted receipt.

`SuisuiHarnessScenario.requiredTaskLifecycleOperations` is the MCP/E2E lifecycle contract for this path. `task-mutation-flow` and `mcp-pseudo-voiceover-focus-path` must both cover `taskList`, `create`, `editContent`, `statusMove`, `automationReview`, `executeContent`, `approvedExecution`, `deleteConfirmation`, `projectCompletion`, and `projectDeleteCascade`. Delete confirmation, project cascade deletion, and approved execution stay out of hosted-MCP mutation payloads because the external relay is review-only; the harness still fails when those user-visible UI/AX paths are not represented.

`SuisuiHarnessTaskLifecycleOperation.requiredFocusNodeIDs` maps each lifecycle operation to the AX nodes that prove it, and `SuisuiHarnessScenario.requiredFocusNodeIDs(for:)` flattens those operation mappings back through the canonical VoiceOver traversal order from `AccessibilityFocusPathRequirement.taskLifecycleAndExecution`. This keeps the operation list, MCP/E2E harness, and pseudo VoiceOver path tied together: adding a lifecycle operation or AX node now requires an explicit mapping instead of relying on a prose checklist.

`SuisuiHarnessTodayCockpitOperation.requiredFocusNodeIDs` does the same for Today. `SuisuiHarnessScenario.requiredTodayCockpitOperations`, `SuisuiHarnessScenario.completeTodayCockpitOperations`, `SuisuiHarnessScenario.missingTodayCockpitOperations()`, and `SuisuiHarnessScenario.requiredTodayCockpitFocusNodeIDs(for:)` map `openToday`, `captureCommand`, `commonActions`, `focusSuggestions`, `localFocusAndPlanning`, `railContext`, and `railActions` back through `AccessibilityFocusPathRequirement.todayCockpit`, so the automated gate can prove the Today rail still exposes next action context and local draft actions before manual VoiceOver evidence is refreshed.

Approved execution evidence must be a redacted `ApprovedAutomationExecutionReceipt` with task identity, project identity, reviewed title, reviewed detail, before/after status, priority, due date, and review reason. `ProjectBoardViewModel.approvedAutomationExecutionReceipts` keeps a receipt history across a configured multi-task review so running one approved task cannot erase the remaining reviewed queue or leave later executions unproven. Missing receipts, missing receipt history, missing reviewed task content, or receipt fields that still contain secret-like content fail the pseudo VoiceOver run before manual evidence can be reused.

`script/check_pseudo_voiceover_paths.sh` is the cheap source-marker gate. Its marker list must include every `AccessibilityFocusPathRequirement.taskLifecycleAndExecution.requiredNodeIDs` entry and every `AccessibilityFocusPathRequirement.todayCockpit.requiredNodeIDs` entry, including task title/detail fields in the inline composer, inspector, and Today rail actions, so a release summary cannot claim create/edit or Today cockpit coverage while only checking the action buttons. Run `script/check_pseudo_voiceover_paths.sh --swift-test` before reusing this gate as release evidence support; the option also runs `swift test --filter AccessibilityFocusPathAuditTests` and `swift test --filter SuisuiHarnessTests` so the real focus-path audit and approved execution receipt logic are proven, not only present as strings.

## Source Owners

- Pure logic: `AccessibilityFocusPathAudit`
- MCP pseudo VoiceOver harness: `SuisuiHarnessAccessibilityAuditRunner`
- Runtime AX smoke: `script/check_accessibility_preflight.sh --runtime`
- Pseudo VoiceOver source contract: `script/check_pseudo_voiceover_paths.sh --swift-test`
- Manual release evidence: `script/create_voiceover_evidence.sh`
