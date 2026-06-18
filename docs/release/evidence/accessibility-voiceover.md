# VoiceOver Accessibility Evidence

Status: pending. This file is a release evidence template until a real VoiceOver pass is performed on the signed or release-candidate app.

Run this pass on macOS with VoiceOver enabled, using a seeded Project Board that includes at least one active project and one task with a due date.

## Required Path

- Project navigation: select Inbox, Today, and one Project from the sidebar.
- Project board detail: confirm the selected project board is announced with context.
- Open task: focus a task card and open details without relying on pointer-only drag.
- Status controls: move focus to previous/next status controls and confirm button labels include target status.
- Task inspector: focus title, detail, status, priority, due, summary, save, suggestion, and danger actions.
- Save Changes: confirm keyboard activation reaches the local task save action.
- Delete Task confirmation: confirm destructive action opens confirmation before local deletion.

## Required Result Notes

- No keyboard trap: pending.
- No unlabeled primary CRUD controls: pending.

## Completion

Replace this template only after the pass is complete, remove all pending language, set `Status: passed`, and record the macOS version, app build, checked-by, and concrete notes.
