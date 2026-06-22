# Accessibility Focus Paths

Status: Phase 14 automated preflight contract

Manual VoiceOver is still required for release evidence. This file defines the source/runtime focus paths that must pass before the manual screen-reader pass starts.

## Task Lifecycle And Execution

The task path covers create, edit, status execution, automation review, approved local execution, and delete confirmation.

| Step | AX identifier | Expected role | Required behavior |
| --- | --- | --- | --- |
| Project navigation | `project-board-sidebar` | outline | User can choose Inbox, Today, Projects, or a concrete project before entering detail. |
| Project detail | `project-board-detail` | group | The selected project board or workflow region is reachable after navigation. |
| Add task | `project-header-add-task` | button | Opens the inline task composer. |
| Task title | `inline-task-title` | text field | Accepts the task title. |
| Create task | `inline-task-create` | button | Creates the task in the local SoloPM database. |
| Open task | `task-card-open-details` | button | Opens the task inspector without requiring pointer drag. |
| Save edit | `task-inspector-save` | button | Saves task title, detail, status, priority, and due date. |
| Status controls | `task-status-move-controls` | group | Exposes status movement controls such as `task-status-move-in_progress`. |
| Review automation | `task-auto-execution-review` | button | Builds a review-only LLM plan for the selected task. |
| Run approved plan | `task-auto-execution-run-plan` | button | Starts only the reviewed local task step after explicit user activation. |
| Delete task | `task-inspector-delete` | button | Opens a destructive confirmation instead of deleting immediately. |
| Confirm delete | `task-inspector-delete-confirmation-confirm` | button | Confirms the destructive delete path. |

## Automation Boundary

- Task automation ranks tasks by priority and due date, but defaults to disabled.
- When enabled, the LLM request is review-only and excludes project/task delete tools.
- The first approved local execution step may move a task into active work. External writes, completion, and destructive actions remain separate reviewed actions.
- Runtime AX checks can verify labels, help text, and confirmation anchors, but the real VoiceOver pass still records concrete observations in `docs/release/evidence/accessibility-voiceover.md`.

## Source Owners

- Pure logic: `AccessibilityFocusPathAudit`
- Runtime AX smoke: `script/check_accessibility_preflight.sh --runtime`
- Pseudo VoiceOver source contract: `script/check_pseudo_voiceover_paths.sh`
- Manual release evidence: `script/create_voiceover_evidence.sh`
