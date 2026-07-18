# UI Screenshot Evidence

Generated with `script/capture_ui_evidence.sh`.

- Generated at: `2026-07-18T12:27:47Z`
- Source commit: `14d1013d`
- App bundle: `dist/SoloPM.app`
- Visual baseline manifest: `docs/quality/visual-baseline-manifest.json`
- Viewport contract: `SOLOPM_VISUAL_BASELINE_VIEWPORT=1024x724`, `SOLOPM_SETTINGS_VISUAL_BASELINE_VIEWPORT=720x712`, `SOLOPM_VOICE_COMMAND_VISUAL_BASELINE_VIEWPORT=760x640`
- Runtime context: locale `en-US`, timezone `UTC`, reference instant `2026-07-10T12:00:00Z`
- Launch mode: normal `ProjectBoardView` route with explicit selected destination; recovery flags are excluded from release evidence.
- Data isolation: isolated temporary HOME via `HOME` and `CFFIXED_USER_HOME`
- Seed data: local `Launch Readiness` project with planned, in-progress, blocked, Inbox voice, Schedule, Done analytics, milestone, completed project, and deterministic MCP registration rows
- Scope: Project board sidebar, task cards, Inbox voice detail, Today cockpit, Projects overview, Schedule cockpit, Schedule workload dashboard, Done analytics, Settings integrations, Settings Appearance Theme picker, and Settings MCP server list across Light/Dark/System
- Capture contract: Light/Dark/System visual baseline manifest fixes product screen targets, viewport, semantic tolerances, and AX frame audit requirements.
- Manual review: passed for Project Board sidebar/cards/inspector, Inbox voice detail, Today cockpit, Projects overview, Schedule cockpit, Schedule workload dashboard, Done analytics, Settings integrations, Settings Appearance Theme picker, Settings MCP server rows, and Light/Dark/System contrast

## Screenshots

- Light: `.tmp/ci-artifacts/ui-visual/current/screenshots/project-board-light.png`
- Dark: `.tmp/ci-artifacts/ui-visual/current/screenshots/project-board-dark.png`
- System: `.tmp/ci-artifacts/ui-visual/current/screenshots/project-board-system.png`
- Settings Overview Light: `.tmp/ci-artifacts/ui-visual/current/screenshots/settings-overview-light.png`
- Settings Overview Dark: `.tmp/ci-artifacts/ui-visual/current/screenshots/settings-overview-dark.png`
- Settings Appearance Light: `.tmp/ci-artifacts/ui-visual/current/screenshots/settings-appearance-light.png`
- Settings Appearance Dark: `.tmp/ci-artifacts/ui-visual/current/screenshots/settings-appearance-dark.png`
- MCP Settings Light: `.tmp/ci-artifacts/ui-visual/current/screenshots/settings-mcp-light.png`
- MCP Settings Dark: `.tmp/ci-artifacts/ui-visual/current/screenshots/settings-mcp-dark.png`
- Inbox Voice Light: `.tmp/ci-artifacts/ui-visual/current/screenshots/inbox-voice-light.png`
- Inbox Voice Dark: `.tmp/ci-artifacts/ui-visual/current/screenshots/inbox-voice-dark.png`
- Projects Overview Light: `.tmp/ci-artifacts/ui-visual/current/screenshots/projects-overview-light.png`
- Projects Overview Dark: `.tmp/ci-artifacts/ui-visual/current/screenshots/projects-overview-dark.png`
- Schedule Light: `.tmp/ci-artifacts/ui-visual/current/screenshots/schedule-light.png`
- Schedule Dark: `.tmp/ci-artifacts/ui-visual/current/screenshots/schedule-dark.png`
- Schedule Workload Light: `.tmp/ci-artifacts/ui-visual/current/screenshots/schedule-workload-light.png`
- Schedule Workload Dark: `.tmp/ci-artifacts/ui-visual/current/screenshots/schedule-workload-dark.png`
- Done Light: `.tmp/ci-artifacts/ui-visual/current/screenshots/done-light.png`
- Done Dark: `.tmp/ci-artifacts/ui-visual/current/screenshots/done-dark.png`
- Settings Integrations Light: `.tmp/ci-artifacts/ui-visual/current/screenshots/settings-integrations-light.png`
- Settings Integrations Dark: `.tmp/ci-artifacts/ui-visual/current/screenshots/settings-integrations-dark.png`

## Visual Baseline Manifest Screenshots

- Project Board Light: `.tmp/ci-artifacts/ui-visual/current/screenshots/project-board-light.png`
- Project Board Dark: `.tmp/ci-artifacts/ui-visual/current/screenshots/project-board-dark.png`
- Project Board System: `.tmp/ci-artifacts/ui-visual/current/screenshots/project-board-system.png`
- Inbox Light: `.tmp/ci-artifacts/ui-visual/current/screenshots/inbox-light.png`
- Inbox Dark: `.tmp/ci-artifacts/ui-visual/current/screenshots/inbox-dark.png`
- Inbox System: `.tmp/ci-artifacts/ui-visual/current/screenshots/inbox-system.png`
- Today Light: `.tmp/ci-artifacts/ui-visual/current/screenshots/today-light.png`
- Today Dark: `.tmp/ci-artifacts/ui-visual/current/screenshots/today-dark.png`
- Today System: `.tmp/ci-artifacts/ui-visual/current/screenshots/today-system.png`
- Settings Overview Light: `.tmp/ci-artifacts/ui-visual/current/screenshots/settings-overview-light.png`
- Settings Overview Dark: `.tmp/ci-artifacts/ui-visual/current/screenshots/settings-overview-dark.png`
- Settings Overview System: `.tmp/ci-artifacts/ui-visual/current/screenshots/settings-overview-system.png`
- Settings Appearance Light: `.tmp/ci-artifacts/ui-visual/current/screenshots/settings-appearance-light.png`
- Settings Appearance Dark: `.tmp/ci-artifacts/ui-visual/current/screenshots/settings-appearance-dark.png`
- Settings Appearance System: `.tmp/ci-artifacts/ui-visual/current/screenshots/settings-appearance-system.png`
- MCP Settings Light: `.tmp/ci-artifacts/ui-visual/current/screenshots/settings-mcp-light.png`
- MCP Settings Dark: `.tmp/ci-artifacts/ui-visual/current/screenshots/settings-mcp-dark.png`
- MCP Settings System: `.tmp/ci-artifacts/ui-visual/current/screenshots/settings-mcp-system.png`
- Voice Command Light: `.tmp/ci-artifacts/ui-visual/current/screenshots/voice-command-light.png`
- Voice Command Dark: `.tmp/ci-artifacts/ui-visual/current/screenshots/voice-command-dark.png`
- Voice Command System: `.tmp/ci-artifacts/ui-visual/current/screenshots/voice-command-system.png`
- Schedule Workload Light: `.tmp/ci-artifacts/ui-visual/current/screenshots/schedule-workload-light.png`
- Schedule Workload Dark: `.tmp/ci-artifacts/ui-visual/current/screenshots/schedule-workload-dark.png`

## Notes

- The script seeds only deterministic local Project/Task/MCP registration data into the isolated SQLite database.
- Secret input screens are excluded from the default visual baseline manifest.
- Only masked SecureField state may be captured if a future release needs a secret-entry screenshot.
- API keys and provider tokens are not read, written, logged, rendered, or captured unmasked.
- Run `script/capture_ui_evidence.sh --doctor` first to verify required commands and Screen Recording visible-pixel capture without writing release evidence.
- The capture host must grant Screen Recording permission through System Settings > Privacy & Security > Screen Recording / Screen & System Audio Recording to the terminal/Codex app; otherwise the script fails before treating screenshots as evidence.
- If capture still fails, rerun with `SOLOPM_UI_EVIDENCE_KEEP_HOME=1` to keep the isolated HOME for database and preference inspection.
- VoiceOver focus order still requires a manual assistive-technology pass.
