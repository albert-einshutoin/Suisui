# Done Analytics Screenshot Evidence

Generated with `script/capture_ui_evidence.sh --done-analytics`.
This targeted evidence covers issue #10 Done analytics light/dark closeout without rewriting the full release screenshot set.

- Generated at: `2026-07-02T12:34:19Z`
- Source commit: `32fa827e`
- Screen Recording preflight: `script/capture_ui_evidence.sh --doctor`
- Target markers: `done-workflow`, `done-completion-heatmap`, `done-productivity-insight`, `done-local-rule-insight`

## Done Analytics

- Light: `docs/release/evidence/ui-screenshots/done-light.png`
- Dark: `docs/release/evidence/ui-screenshots/done-dark.png`

## Guardrails

- The Done dashboard is seeded from local ProjectBoard completion history in an isolated SQLite database.
- Opening Done analytics does not enqueue or execute external writes.
- API keys, provider tokens, OAuth tokens, calendar contents, and customer file contents are not captured.
- The app runs with `SOLOPM_DISABLE_KEYCHAIN_SECRET_STORE=1`, an isolated HOME, and a seeded SQLite database.
