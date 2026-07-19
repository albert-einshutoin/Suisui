# P0 Workflow Screenshot Evidence

Generated with `script/capture_ui_evidence.sh --p0-workflows`.
This targeted evidence covers the Personal MVP Inbox and Today closeout paths without rewriting the full release screenshot set.

- Generated at: `2026-07-02T14:45:10Z`
- Source commit: `2c63eeec`
- Screen Recording preflight: `script/capture_ui_evidence.sh --doctor`

## Inbox

- Light: `docs/release/evidence/ui-screenshots/inbox-light.png`
- Dark: `docs/release/evidence/ui-screenshots/inbox-dark.png`
- System: `docs/release/evidence/ui-screenshots/inbox-system.png`

## Today

- Light: `docs/release/evidence/ui-screenshots/today-light.png`
- Dark: `docs/release/evidence/ui-screenshots/today-dark.png`
- System: `docs/release/evidence/ui-screenshots/today-system.png`

## Inbox Voice Detail

- Light: `docs/release/evidence/ui-screenshots/inbox-voice-light.png`
- Dark: `docs/release/evidence/ui-screenshots/inbox-voice-dark.png`

## Guardrails

- API keys, provider tokens, OAuth tokens, calendar contents, and customer file contents are not captured.
- The app runs with `SUISUI_DISABLE_KEYCHAIN_SECRET_STORE=1`, an isolated HOME, and a seeded SQLite database.
- The P0 workflow capture uses `SUISUI_LAUNCH_RECOVERY_MODE=1` so evidence targets Today and Inbox workflow rails directly.
