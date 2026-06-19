# UI Screenshot Evidence

Generated with `script/capture_ui_evidence.sh`.

- Generated at: `2026-06-19T01:37:09Z`
- App bundle: `dist/SoloPM.app`
- Data isolation: isolated temporary HOME via `HOME` and `CFFIXED_USER_HOME`
- Seed data: local `Launch Readiness` project with planned, in-progress, and blocked task cards plus deterministic MCP registration rows
- Scope: Project board sidebar, task cards, right inspector, Settings Overview Theme picker, and Settings MCP server list across Light/Dark/System
- Manual review: passed for Project Board sidebar/cards/inspector, Settings Overview Theme picker, Settings MCP server rows, and Light/Dark/System contrast

## Screenshots

- Light: `docs/release/evidence/ui-screenshots/project-board-light.png`
- Dark: `docs/release/evidence/ui-screenshots/project-board-dark.png`
- System: `docs/release/evidence/ui-screenshots/project-board-system.png`
- Settings Overview Light: `docs/release/evidence/ui-screenshots/settings-overview-light.png`
- Settings Overview Dark: `docs/release/evidence/ui-screenshots/settings-overview-dark.png`
- MCP Settings Light: `docs/release/evidence/ui-screenshots/settings-mcp-light.png`
- MCP Settings Dark: `docs/release/evidence/ui-screenshots/settings-mcp-dark.png`

## Notes

- The script seeds only deterministic local Project/Task/MCP registration data into the isolated SQLite database.
- API keys and provider tokens are not read, written, logged, or rendered.
- Run `script/capture_ui_evidence.sh --doctor` first to verify required commands and Screen Recording visible-pixel capture without writing release evidence.
- The capture host must grant Screen Recording permission through System Settings > Privacy & Security > Screen Recording / Screen & System Audio Recording to the terminal/Codex app; otherwise the script fails before treating screenshots as evidence.
- If capture still fails, rerun with `SOLOPM_UI_EVIDENCE_KEEP_HOME=1` to keep the isolated HOME for database and preference inspection.
- VoiceOver focus order still requires a manual assistive-technology pass.
