# VoiceOver Accessibility Evidence

Status: pending

Do not set `Status: passed` until every item below is verified on the signed or release-candidate app.

## Release Candidate Context

- macOS version: macOS 26.5
- App build: `0.1.0 (1)`
- Bundle identifier: `dev.solopm.app`
- Checked by:
- Check date: 2026-06-19
- Evidence source: `dist/SoloPM.app manual VoiceOver pass`
- Accessibility environment:
- Runtime AX smoke: OK: runtime AX smoke visible, windows=1, window=1 name=SoloPM, buttons=28, textFields=1, staticTexts=24, unlabeledButtons=0, genericButtons=0

## Setup

1. Enable VoiceOver on macOS.
2. Launch `dist/SoloPM.app`.
3. Seed the Project Board with at least one active project and one task with a due date.
4. Open the Project Board window and keep the right inspector visible.
5. Run `./script/check_accessibility_preflight.sh --runtime` and paste the OK line into `Runtime AX smoke`.
6. Navigate using keyboard and VoiceOver commands before using the pointer.

## Required Focus Path

- [ ] Project navigation: select Inbox, Today, and one Project from the sidebar.
- [ ] Project board detail: confirm the selected project board is announced with project context.
- [ ] Open task: focus a task card and open details without relying on pointer-only drag.
- [ ] Inline Task Composer: create a task from a board column with title, detail, priority, due, Command+Return, and Escape paths.
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

1. Run this script with `--passed --checked-by NAME --confirm-manual-voiceover-pass` only after the manual pass.
2. Remove all `pending` and unchecked `[ ]` markers.
3. Rerun `./script/release_readiness_report.sh` and confirm the VoiceOver section is green.
