# Visual Baselines

SoloPM uses visual baselines as semantic release evidence, not pixel-perfect snapshots. macOS rendering, display scale, and font rasterization can differ between machines, so the gate focuses on black screens, empty captures, low information images, wrong window size, theme drift, and AX frame overlap.

## Scope

The source of truth is `docs/quality/visual-baseline-manifest.json`.

| Screen | Required Themes | Viewport | Evidence |
| --- | --- | --- | --- |
| Project Board | Light / Dark / System | 1560x860 | sidebar, task cards, project header, inspector |
| Inbox | Light / Dark / System | 1560x860 | inbox list and selected intake context |
| Today | Light / Dark / System | 1560x860 | due work, schedule blocks, recommended next step |
| Inbox Voice | Light / Dark | 1560x860 | voice capture metadata, transcript context, interpretation state |
| Projects Overview | Light / Dark | 1560x860 | portfolio cards, progress, risk, next due, selected summary |
| Schedule | Light / Dark | 1560x860 | schedule cockpit, unscheduled tasks, review-only calendar draft |
| Done | Light / Dark | 1560x860 | completion analytics, history, reopen affordance |
| Settings Overview | Light / Dark / System | 1200x720 | overview navigation and account-free local state |
| Settings Integrations | Light / Dark | 1200x720 | provider, TTS/STT, Calendar/Reminder, Sync, Privacy, Data Location status |
| Settings Appearance | Light / Dark / System | 1200x720 | theme picker and contrast controls |
| MCP Settings | Light / Dark / System | 1200x720 | registered MCP rows without secrets |
| Voice Command | Light / Dark / System | 1560x860 | command entry, local interpretation, approval boundary |

## Tolerances

The gate uses semantic tolerances:

- Minimum bytes, width, and height reject tiny or wrong-window captures.
- Luminance range and color bucket count reject black, blank, and low information images.
- Pixel-perfect equality is not required and must not be the only pass/fail signal.
- AX frame checks remain required because image comparison alone cannot reliably prove controls are not overlapping.

## Capture Contract

Run `script/capture_ui_evidence.sh --doctor` before writing release evidence. Normal capture fixes the main app viewport with `SOLOPM_VISUAL_BASELINE_VIEWPORT` and settings windows with `SOLOPM_SETTINGS_VISUAL_BASELINE_VIEWPORT`, then writes screenshot evidence under `docs/release/evidence/ui-screenshots`.

Capture target validation runs before every product screenshot. The script waits for the destination-specific AX identifier and seeded screen text, such as `project-board-detail` plus `Launch Readiness` for Project Board or `voice-command-root` plus `Voice Command` for Voice Command, before it calls `screencapture`. This keeps a visually valid but semantically wrong screen, such as Today saved as Project Board, from becoming release evidence.

The capture script also records the Light/Dark/System visual baseline manifest path and viewport contract in generated evidence so reviewers know which product screens were targeted.

Secret input screens are excluded from the default visual baseline manifest. Only masked SecureField state may be captured if a future release needs a secret-entry screenshot. API keys and provider tokens are not read, written, logged, rendered, or captured unmasked.

## Update Flow

Normal `script/check_visual_regression_smoke.sh` runs do not overwrite baselines. In other words, a default visual smoke run does not overwrite baselines. Baseline updates require an intentional command:

```bash
script/check_visual_regression_smoke.sh --update-baselines --allow-update
```

Use the explicit paired form `--update-baselines --allow-update`; `--update-baselines` by itself is rejected.

Baseline update PRs must attach before/after artifact evidence and explain the product reason for the visual change. Do not use baseline updates to hide black screens, missing content, low contrast, AX frame overlap, or incorrect window captures.
