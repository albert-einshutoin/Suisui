# UI Screenshot Evidence

Generated with `script/capture_ui_evidence.sh`.

- App bundle: `dist/SoloPM.app`
- Data isolation: isolated temporary HOME via `HOME` and `CFFIXED_USER_HOME`
- Seed data: local `Launch Readiness` project with planned, in-progress, and blocked task cards
- Scope: Project board sidebar, task cards, and right inspector across Light/Dark/System

## Screenshots

- Light: `docs/release/evidence/ui-screenshots/project-board-light.png`
- Dark: `docs/release/evidence/ui-screenshots/project-board-dark.png`
- System: `docs/release/evidence/ui-screenshots/project-board-system.png`

## Notes

- The script seeds only deterministic local Project/Task data into the isolated SQLite database.
- API keys and provider tokens are not read, written, logged, or rendered.
- The capture host must grant Screen Recording permission to the terminal/Codex app; otherwise the script fails before treating screenshots as evidence.
- VoiceOver focus order still requires a manual assistive-technology pass.
