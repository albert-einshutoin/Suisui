# P0 Workflow Screenshot Evidence

Generated with `script/capture_ui_evidence.sh --p0-workflows`.
This targeted evidence covers the Personal MVP Inbox and Today closeout paths without rewriting the full release screenshot set.

- Generated at: `2026-08-12T06:36:26Z`
- Source commit: `97771f52`
- Locales: `en-US`, `ja-JP`
- Screen Recording preflight: `script/capture_ui_evidence.sh --doctor`

## Inbox

- Light: `docs/release/evidence/ui-screenshots/inbox-light.png`
- Dark: `docs/release/evidence/ui-screenshots/inbox-dark.png`
- System: `docs/release/evidence/ui-screenshots/inbox-system.png`
- Japanese light: `docs/release/evidence/ui-screenshots-ja/inbox-light.png`
- Japanese dark: `docs/release/evidence/ui-screenshots-ja/inbox-dark.png`
- Japanese system: `docs/release/evidence/ui-screenshots-ja/inbox-system.png`

## Today

- Light: `docs/release/evidence/ui-screenshots/today-light.png`
- Dark: `docs/release/evidence/ui-screenshots/today-dark.png`
- System: `docs/release/evidence/ui-screenshots/today-system.png`
- Japanese light: `docs/release/evidence/ui-screenshots-ja/today-light.png`
- Japanese dark: `docs/release/evidence/ui-screenshots-ja/today-dark.png`
- Japanese system: `docs/release/evidence/ui-screenshots-ja/today-system.png`

## Inbox Voice Detail

- Light: `docs/release/evidence/ui-screenshots/inbox-voice-light.png`
- Dark: `docs/release/evidence/ui-screenshots/inbox-voice-dark.png`
- Japanese light: `docs/release/evidence/ui-screenshots-ja/inbox-voice-light.png`
- Japanese dark: `docs/release/evidence/ui-screenshots-ja/inbox-voice-dark.png`

## Guardrails

- API keys, provider tokens, OAuth tokens, calendar contents, and customer file contents are not captured.
- The app runs with `SUISUI_DISABLE_KEYCHAIN_SECRET_STORE=1`, an isolated HOME, and a seeded SQLite database.
- The P0 workflow capture uses the normal `ProjectBoardView` route with explicit Today and Inbox selected destinations.
