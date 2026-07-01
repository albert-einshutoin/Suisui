# Schedule Workload Screenshot Evidence

Generated with `script/capture_ui_evidence.sh --schedule-workload`.
This targeted evidence covers the issue #1 calendar workload dashboard without rewriting the full release screenshot set.

- Generated at: `2026-07-01T16:56:42Z`
- Source commit: `9d900734`
- Screen Recording preflight: `script/capture_ui_evidence.sh --doctor`
- Target markers: `schedule-workflow`, `schedule-workload-dashboard`, `schedule-workload-attention-banner`, `schedule-workload-day-detail`

## Schedule Workload

- Light: `docs/release/evidence/ui-screenshots/schedule-workload-light.png`
- Dark: `docs/release/evidence/ui-screenshots/schedule-workload-dark.png`

## Guardrails

- The dashboard is seeded from local ProjectBoard tasks in an isolated SQLite database.
- Opening the workload dashboard does not enqueue or execute external Calendar writes.
- API keys, provider tokens, OAuth tokens, calendar contents, and customer file contents are not captured.
- The app runs with `SOLOPM_DISABLE_KEYCHAIN_SECRET_STORE=1`, an isolated HOME, and a seeded SQLite database.
