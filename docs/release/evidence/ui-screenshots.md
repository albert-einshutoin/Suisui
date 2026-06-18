# UI Screenshot Evidence

Status: pending. The checked-in release tree does not currently contain valid screenshot PNG evidence.

Run `script/capture_ui_evidence.sh` on a host with Screen Recording permission to generate this manifest and the PNG files below.

- App bundle: `dist/SoloPM.app`
- Data isolation: isolated temporary HOME via `HOME` and `CFFIXED_USER_HOME`
- Seed data: local `Launch Readiness` project with planned, in-progress, and blocked task cards
- Scope: Project board sidebar, task cards, and right inspector across Light/Dark/System

## Expected Screenshots

- Light: `docs/release/evidence/ui-screenshots/project-board-light.png`
- Dark: `docs/release/evidence/ui-screenshots/project-board-dark.png`
- System: `docs/release/evidence/ui-screenshots/project-board-system.png`

## Notes

- The script seeds only deterministic local Project/Task data into the isolated SQLite database.
- API keys and provider tokens are not read, written, logged, or rendered.
- The capture host must grant Screen Recording permission to the terminal/Codex app and return visible pixels; locked or headless sessions that capture black frames are rejected before treating screenshots as evidence.
- VoiceOver focus order still requires a manual assistive-technology pass.
