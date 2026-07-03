# Accessibility Identifier Guidelines

Status: Phase 14 source contract

SoloPM uses accessibility identifiers as stable test and assistive-technology anchors. They are not user-facing copy, and they must stay predictable across localization, theme, and data changes.

## Naming Contract

Use the `screen-area-action` shape for static controls:

- `project-board-add-project`
- `project-header-add-task`
- `task-inspector-save`
- `settings-task-auto-execution-toggle`
- `settings-task-auto-execution-urgent-cooldown`

Use a dynamic suffix only when multiple peer elements are rendered from data:

- `sidebar-destination-<destination>`
- `project-sidebar-row-<projectID>`
- `workflow-task-row-<taskID>`
- `workflow-task-completion-<taskID>`
- `task-status-move-<status>-<taskID>`

The suffix must be a stable internal ID or enum raw value. Do not encode user-provided content, secrets, or filesystem paths in an accessibility identifier.

## Screen Prefixes

- `project-board`: top-level board, toolbar, sidebar, and shared project board actions.
- `project-header`: selected project header and project-scoped actions.
- `project-inspector`: project editing and destructive confirmation controls.
- `task-inspector`: task editing, automation review, execution, and destructive confirmation controls.
- `inline-task`: inline task creation fields and actions.
- `inbox`: inbox capture, classification, and undo controls.
- `today`: today planning, recommendation, and time-block controls.
- `settings`: settings tabs, fields, save controls, and task automation settings.
- `menu-bar`: menu bar quick capture and settings links.

## Required for new interactive components

Every new button, menu item, input, picker, destructive confirmation, repeated row, and automation execution control needs:

- an accessibility identifier following the naming contract,
- an accessibility label or visible text that remains useful in VoiceOver,
- a help or hint when the action writes data, starts automation, or changes external state,
- a source or runtime test when the control is part of create, edit, delete, execution, settings, or release evidence workflows.

Prefer adding identifiers at the component boundary instead of wrapping parent containers. Container identifiers are useful for focus regions, but they do not replace identifiers on concrete controls that mutate state.
