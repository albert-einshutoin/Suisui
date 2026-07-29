# UI Screenshot Evidence

Generated with `script/capture_ui_evidence.sh`.

- Generated at: `2026-07-29T18:14:04Z`
- Source commit: `87ceaf30`
- App bundle: `dist/Suisui.app`
- Visual baseline manifest: `docs/quality/visual-baseline-manifest-ja.json`
- Viewport contract: `SUISUI_VISUAL_BASELINE_VIEWPORT=1024x676`, `SUISUI_SETTINGS_VISUAL_BASELINE_VIEWPORT=720x676`, `SUISUI_VOICE_COMMAND_VISUAL_BASELINE_VIEWPORT=760x640`
- Runtime context: locale `ja-JP`, timezone `UTC`, reference instant `2026-07-10T12:00:00Z`
- Launch mode: normal `ProjectBoardView` route with explicit selected destination; recovery flags are excluded from release evidence.
- Data isolation: isolated temporary HOME via `HOME` and `CFFIXED_USER_HOME`
- Seed data: local `Launch Readiness` project with planned, in-progress, blocked, Inbox voice, Schedule, Done analytics, milestone, completed project, deterministic MCP registration rows, and production-model Assistant Queue review fixtures
- Scope: Project board sidebar, task cards, Inbox voice detail, Today cockpit, Projects overview, Schedule cockpit, Schedule workload dashboard, Done analytics, Assistant Queue approval states, Settings integrations, Settings Appearance Theme picker, and Settings MCP server list across Light/Dark/System
- Capture contract: Light/Dark/System visual baseline manifest fixes product screen targets, viewport, semantic tolerances, and AX frame audit requirements.
- Manual review: passed for Project Board sidebar/cards/inspector, Inbox voice detail, Today cockpit, Projects overview, Schedule cockpit, Schedule workload dashboard, Done analytics, Settings integrations, Settings Appearance Theme picker, Settings MCP server rows, and Light/Dark/System contrast

## Screenshots

- Light: `docs/release/evidence/ui-screenshots-ja/project-board-light.png`
- Dark: `docs/release/evidence/ui-screenshots-ja/project-board-dark.png`
- System: `docs/release/evidence/ui-screenshots-ja/project-board-system.png`
- Settings Overview Light: `docs/release/evidence/ui-screenshots-ja/settings-overview-light.png`
- Settings Overview Dark: `docs/release/evidence/ui-screenshots-ja/settings-overview-dark.png`
- Settings Appearance Light: `docs/release/evidence/ui-screenshots-ja/settings-appearance-light.png`
- Settings Appearance Dark: `docs/release/evidence/ui-screenshots-ja/settings-appearance-dark.png`
- MCP Settings Light: `docs/release/evidence/ui-screenshots-ja/settings-mcp-light.png`
- MCP Settings Dark: `docs/release/evidence/ui-screenshots-ja/settings-mcp-dark.png`
- Inbox Voice Light: `docs/release/evidence/ui-screenshots-ja/inbox-voice-light.png`
- Inbox Voice Dark: `docs/release/evidence/ui-screenshots-ja/inbox-voice-dark.png`
- Projects Overview Light: `docs/release/evidence/ui-screenshots-ja/projects-overview-light.png`
- Projects Overview Dark: `docs/release/evidence/ui-screenshots-ja/projects-overview-dark.png`
- Schedule Light: `docs/release/evidence/ui-screenshots-ja/schedule-light.png`
- Schedule Dark: `docs/release/evidence/ui-screenshots-ja/schedule-dark.png`
- Schedule Workload Light: `docs/release/evidence/ui-screenshots-ja/schedule-workload-light.png`
- Schedule Workload Dark: `docs/release/evidence/ui-screenshots-ja/schedule-workload-dark.png`
- Done Light: `docs/release/evidence/ui-screenshots-ja/done-light.png`
- Done Dark: `docs/release/evidence/ui-screenshots-ja/done-dark.png`
- Settings Integrations Light: `docs/release/evidence/ui-screenshots-ja/settings-integrations-light.png`
- Settings Integrations Dark: `docs/release/evidence/ui-screenshots-ja/settings-integrations-dark.png`
- Assistant Queue Waiting Review Light: `docs/release/evidence/ui-screenshots-ja/assistant-queue-waiting-review-light.png`
- Assistant Queue Waiting Review Dark: `docs/release/evidence/ui-screenshots-ja/assistant-queue-waiting-review-dark.png`
- Assistant Queue Approved Light: `docs/release/evidence/ui-screenshots-ja/assistant-queue-approved-light.png`
- Assistant Queue Approved Dark: `docs/release/evidence/ui-screenshots-ja/assistant-queue-approved-dark.png`
- Assistant Queue Failed Light: `docs/release/evidence/ui-screenshots-ja/assistant-queue-failed-light.png`
- Assistant Queue Failed Dark: `docs/release/evidence/ui-screenshots-ja/assistant-queue-failed-dark.png`

## Visual Baseline Manifest Screenshots

- Project Board Light: `docs/release/evidence/ui-screenshots-ja/project-board-light.png`
- Project Board Dark: `docs/release/evidence/ui-screenshots-ja/project-board-dark.png`
- Project Board System: `docs/release/evidence/ui-screenshots-ja/project-board-system.png`
- Inbox Light: `docs/release/evidence/ui-screenshots-ja/inbox-light.png`
- Inbox Dark: `docs/release/evidence/ui-screenshots-ja/inbox-dark.png`
- Inbox System: `docs/release/evidence/ui-screenshots-ja/inbox-system.png`
- Today Light: `docs/release/evidence/ui-screenshots-ja/today-light.png`
- Today Dark: `docs/release/evidence/ui-screenshots-ja/today-dark.png`
- Today System: `docs/release/evidence/ui-screenshots-ja/today-system.png`
- Settings Overview Light: `docs/release/evidence/ui-screenshots-ja/settings-overview-light.png`
- Settings Overview Dark: `docs/release/evidence/ui-screenshots-ja/settings-overview-dark.png`
- Settings Overview System: `docs/release/evidence/ui-screenshots-ja/settings-overview-system.png`
- Settings Appearance Light: `docs/release/evidence/ui-screenshots-ja/settings-appearance-light.png`
- Settings Appearance Dark: `docs/release/evidence/ui-screenshots-ja/settings-appearance-dark.png`
- Settings Appearance System: `docs/release/evidence/ui-screenshots-ja/settings-appearance-system.png`
- MCP Settings Light: `docs/release/evidence/ui-screenshots-ja/settings-mcp-light.png`
- MCP Settings Dark: `docs/release/evidence/ui-screenshots-ja/settings-mcp-dark.png`
- MCP Settings System: `docs/release/evidence/ui-screenshots-ja/settings-mcp-system.png`
- Voice Command Light: `docs/release/evidence/ui-screenshots-ja/voice-command-light.png`
- Voice Command Dark: `docs/release/evidence/ui-screenshots-ja/voice-command-dark.png`
- Voice Command System: `docs/release/evidence/ui-screenshots-ja/voice-command-system.png`
- Schedule Workload Light: `docs/release/evidence/ui-screenshots-ja/schedule-workload-light.png`
- Schedule Workload Dark: `docs/release/evidence/ui-screenshots-ja/schedule-workload-dark.png`
- Assistant Queue Waiting Review Light: `docs/release/evidence/ui-screenshots-ja/assistant-queue-waiting-review-light.png`
- Assistant Queue Waiting Review Dark: `docs/release/evidence/ui-screenshots-ja/assistant-queue-waiting-review-dark.png`
- Assistant Queue Approved Light: `docs/release/evidence/ui-screenshots-ja/assistant-queue-approved-light.png`
- Assistant Queue Approved Dark: `docs/release/evidence/ui-screenshots-ja/assistant-queue-approved-dark.png`
- Assistant Queue Failed Light: `docs/release/evidence/ui-screenshots-ja/assistant-queue-failed-light.png`
- Assistant Queue Failed Dark: `docs/release/evidence/ui-screenshots-ja/assistant-queue-failed-dark.png`

## Notes

- The script seeds only deterministic local Project/Task/MCP registration data into the isolated SQLite database.
- Secret input screens are excluded from the default visual baseline manifest.
- Only masked SecureField state may be captured if a future release needs a secret-entry screenshot.
- API keys and provider tokens are not read, written, logged, rendered, or captured unmasked.
- Run `script/capture_ui_evidence.sh --doctor` first to verify required commands and Screen Recording visible-pixel capture without writing release evidence.
- The capture host must grant Screen Recording permission through System Settings > Privacy & Security > Screen Recording / Screen & System Audio Recording to the terminal/Codex app; otherwise the script fails before treating screenshots as evidence.
- If capture still fails, rerun with `SUISUI_UI_EVIDENCE_KEEP_HOME=1` to keep the isolated HOME for database and preference inspection.
- VoiceOver focus order still requires a manual assistive-technology pass.
