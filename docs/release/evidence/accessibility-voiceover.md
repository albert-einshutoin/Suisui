# VoiceOver Accessibility Evidence

Status: pending

Do not set `Status: passed` until every item below is verified on the signed or release-candidate app.

## Release Candidate Context

- macOS version:
- App build:
- Bundle identifier: `dev.solopm.SoloPM`
- Checked by:
- Check date:
- Evidence source: signed or release-candidate `dist/SoloPM.app`

## Setup

1. Enable VoiceOver on macOS.
2. Launch `dist/SoloPM.app`.
3. Seed the Project Board with at least one active project and one task with a due date.
4. Open the Project Board window and keep the right inspector visible.
5. Navigate using keyboard and VoiceOver commands before using the pointer.

## Required Focus Path

- [ ] Project navigation: select Inbox, Today, and one Project from the sidebar.
- [ ] Project board detail: confirm the selected project board is announced with project context.
- [ ] Open task: focus a task card and open details without relying on pointer-only drag.
- [ ] Status controls: move focus to previous/next status controls and confirm button labels include target status.
- [ ] Task inspector: focus title, detail, status, priority, due, summary, save, suggestion, and danger actions.
- [ ] Save Changes: confirm keyboard activation reaches the local task save action.
- [ ] Delete Task confirmation: confirm destructive action opens confirmation before local deletion.
- [ ] No keyboard trap: confirm focus can leave sidebar, board, card controls, inspector fields, and confirmation dialogs.
- [ ] No unlabeled primary CRUD controls: confirm create, update, status move, complete/archive, and delete actions have labels or help.

## Failure Notes

- Blocker observed:
- Affected path:
- Follow-up source/test link:
- Fix owner:

## Completion Instructions

1. Replace `Status: pending` with `Status: passed`.
2. Remove all `pending` and unchecked `[ ]` markers.
3. Fill every Release Candidate Context field.
4. Keep concrete notes for any warning that was accepted for release.
5. Rerun `./script/release_readiness_report.sh` and confirm the VoiceOver section is green.
