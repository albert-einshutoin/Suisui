# Done Analytics Screenshot Evidence

Generated with `script/capture_ui_evidence.sh --done-analytics`.
This targeted evidence covers issue #10 Done analytics light/dark closeout without rewriting the full release screenshot set.

- Generated at: `2026-08-21T17:07:34Z`
- Source commit: `224c4681`
- Screen Recording preflight: `script/capture_ui_evidence.sh --doctor`
- Target markers: `done-workflow`, `done-completion-heatmap`, `done-productivity-insight`, `done-local-rule-insight`

## Done Analytics

- Light: `docs/release/evidence/ui-screenshots-ja/done-light.png`
- Dark: `docs/release/evidence/ui-screenshots-ja/done-dark.png`

## Guardrails

- The Done dashboard is seeded from local ProjectBoard completion history in an isolated SQLite database.
- Opening Done analytics does not enqueue or execute external writes.
- API keys, provider tokens, OAuth tokens, calendar contents, and customer file contents are not captured.
- The app runs with `SUISUI_DISABLE_KEYCHAIN_SECRET_STORE=1`, an isolated HOME, and a seeded SQLite database.
