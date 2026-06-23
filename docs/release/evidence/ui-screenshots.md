# UI Screenshot Evidence

Generated with `script/capture_ui_evidence.sh`.

- Generated at: `2026-06-23T19:59:04Z`
- Source commit: `cb25c42`
- App bundle: `dist/SoloPM.app`
- Visual baseline manifest: `docs/quality/visual-baseline-manifest.json`
- Viewport contract: `SOLOPM_VISUAL_BASELINE_VIEWPORT=1560x860`, `SOLOPM_SETTINGS_VISUAL_BASELINE_VIEWPORT=1200x720`
- Data isolation: isolated temporary HOME via `HOME` and `CFFIXED_USER_HOME`
- Seed data: local `Launch Readiness` project with planned, in-progress, blocked, Inbox voice, Schedule, Done analytics, milestone, completed project, and deterministic MCP registration rows
- Scope: Project board sidebar, task cards, Inbox voice detail, Projects overview, Schedule cockpit, Done analytics, Settings integrations, Settings Appearance Theme picker, and Settings MCP server list across Light/Dark/System
- Capture contract: Light/Dark/System visual baseline manifest fixes product screen targets, viewport, semantic tolerances, and AX frame audit requirements.
- Manual review: passed for Project Board sidebar/cards/inspector, Inbox voice detail, Projects overview, Schedule cockpit, Done analytics, Settings integrations, Settings Appearance Theme picker, Settings MCP server rows, and Light/Dark/System contrast

## Screenshots

- Light: `docs/release/evidence/ui-screenshots/project-board-light.png`
- Dark: `docs/release/evidence/ui-screenshots/project-board-dark.png`
- System: `docs/release/evidence/ui-screenshots/project-board-system.png`
- Settings Overview Light: `docs/release/evidence/ui-screenshots/settings-overview-light.png`
- Settings Overview Dark: `docs/release/evidence/ui-screenshots/settings-overview-dark.png`
- Settings Appearance Light: `docs/release/evidence/ui-screenshots/settings-appearance-light.png`
- Settings Appearance Dark: `docs/release/evidence/ui-screenshots/settings-appearance-dark.png`
- MCP Settings Light: `docs/release/evidence/ui-screenshots/settings-mcp-light.png`
- MCP Settings Dark: `docs/release/evidence/ui-screenshots/settings-mcp-dark.png`
- Inbox Voice Light: `docs/release/evidence/ui-screenshots/inbox-voice-light.png`
- Inbox Voice Dark: `docs/release/evidence/ui-screenshots/inbox-voice-dark.png`
- Projects Overview Light: `docs/release/evidence/ui-screenshots/projects-overview-light.png`
- Projects Overview Dark: `docs/release/evidence/ui-screenshots/projects-overview-dark.png`
- Schedule Light: `docs/release/evidence/ui-screenshots/schedule-light.png`
- Schedule Dark: `docs/release/evidence/ui-screenshots/schedule-dark.png`
- Done Light: `docs/release/evidence/ui-screenshots/done-light.png`
- Done Dark: `docs/release/evidence/ui-screenshots/done-dark.png`
- Settings Integrations Light: `docs/release/evidence/ui-screenshots/settings-integrations-light.png`
- Settings Integrations Dark: `docs/release/evidence/ui-screenshots/settings-integrations-dark.png`

## Visual Baseline Manifest Screenshots

- Project Board Light: `docs/release/evidence/ui-screenshots/project-board-light.png`
- Project Board Dark: `docs/release/evidence/ui-screenshots/project-board-dark.png`
- Project Board System: `docs/release/evidence/ui-screenshots/project-board-system.png`
- Inbox Light: `docs/release/evidence/ui-screenshots/inbox-light.png`
- Inbox Dark: `docs/release/evidence/ui-screenshots/inbox-dark.png`
- Inbox System: `docs/release/evidence/ui-screenshots/inbox-system.png`
- Today Light: `docs/release/evidence/ui-screenshots/today-light.png`
- Today Dark: `docs/release/evidence/ui-screenshots/today-dark.png`
- Today System: `docs/release/evidence/ui-screenshots/today-system.png`
- Settings Overview Light: `docs/release/evidence/ui-screenshots/settings-overview-light.png`
- Settings Overview Dark: `docs/release/evidence/ui-screenshots/settings-overview-dark.png`
- Settings Overview System: `docs/release/evidence/ui-screenshots/settings-overview-system.png`
- Settings Appearance Light: `docs/release/evidence/ui-screenshots/settings-appearance-light.png`
- Settings Appearance Dark: `docs/release/evidence/ui-screenshots/settings-appearance-dark.png`
- Settings Appearance System: `docs/release/evidence/ui-screenshots/settings-appearance-system.png`
- MCP Settings Light: `docs/release/evidence/ui-screenshots/settings-mcp-light.png`
- MCP Settings Dark: `docs/release/evidence/ui-screenshots/settings-mcp-dark.png`
- MCP Settings System: `docs/release/evidence/ui-screenshots/settings-mcp-system.png`
- Voice Command Light: `docs/release/evidence/ui-screenshots/voice-command-light.png`
- Voice Command Dark: `docs/release/evidence/ui-screenshots/voice-command-dark.png`
- Voice Command System: `docs/release/evidence/ui-screenshots/voice-command-system.png`

## Notes

- The script seeds only deterministic local Project/Task/MCP registration data into the isolated SQLite database.
- Secret input screens are excluded from the default visual baseline manifest.
- Only masked SecureField state may be captured if a future release needs a secret-entry screenshot.
- API keys and provider tokens are not read, written, logged, rendered, or captured unmasked.
- Run `script/capture_ui_evidence.sh --doctor` first to verify required commands and Screen Recording visible-pixel capture without writing release evidence.
- The capture host must grant Screen Recording permission through System Settings > Privacy & Security > Screen Recording / Screen & System Audio Recording to the terminal/Codex app; otherwise the script fails before treating screenshots as evidence.
- If capture still fails, rerun with `SOLOPM_UI_EVIDENCE_KEEP_HOME=1` to keep the isolated HOME for database and preference inspection.
- VoiceOver focus order still requires a manual assistive-technology pass.
