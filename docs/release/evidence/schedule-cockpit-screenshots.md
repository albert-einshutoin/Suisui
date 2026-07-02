# Schedule Cockpit Screenshot Evidence

Generated with `script/capture_ui_evidence.sh --schedule-cockpit`.
This targeted evidence covers issue #9 Schedule cockpit light/dark closeout without rewriting the full release screenshot set.

- Generated at: `2026-07-02T10:52:53Z`
- Source commit: `a12afebb`
- Screen Recording preflight: `script/capture_ui_evidence.sh --doctor`
- Target markers: `schedule-workflow`, `schedule-week-grid`, `schedule-week-time-axis-grid`

## Schedule Cockpit

- Light: `docs/release/evidence/ui-screenshots/schedule-light.png`
- Dark: `docs/release/evidence/ui-screenshots/schedule-dark.png`

## Guardrails

- The cockpit is seeded from local ProjectBoard tasks in an isolated SQLite database.
- Opening the cockpit does not enqueue or execute external Calendar or Reminder writes.
- API keys, provider tokens, OAuth tokens, calendar contents, and customer file contents are not captured.
- The app runs with `SOLOPM_DISABLE_KEYCHAIN_SECRET_STORE=1`, an explicit isolated SQLite database, and env-driven Schedule selection.
