# Visual Baselines

SoloPM uses visual baselines as semantic release evidence plus bounded raster comparison. macOS rendering, display scale, and font rasterization can differ between machines, so the gate keeps three separate checks: image health, raster diff, and a real runtime AX frame audit. None substitutes for another.

## Scope

The source of truth is `docs/quality/visual-baseline-manifest.json`.

| Screen | Required Themes | Viewport | Evidence |
| --- | --- | --- | --- |
| Project Board | Light / Dark / System | 1024x724 | sidebar, task cards, project header, inspector |
| Inbox | Light / Dark / System | 1024x724 | inbox list and selected intake context |
| Today | Light / Dark / System | 1024x724 | due work, schedule blocks, recommended next step |
| Inbox Voice | Light / Dark | 1024x724 | voice capture metadata, transcript context, interpretation state |
| Projects Overview | Light / Dark | 1024x724 | portfolio cards, progress, risk, next due, selected summary |
| Schedule | Light / Dark | 1024x724 | schedule cockpit, unscheduled tasks, review-only calendar draft |
| Schedule Workload | Light / Dark | 1024x724 | daily workload counts, attention banner, selected day detail |
| Done | Light / Dark | 1024x724 | completion analytics, history, reopen affordance |
| Settings Overview | Light / Dark / System | 720x676 | overview navigation and account-free local state |
| Settings Integrations | Light / Dark | 720x676 | provider, TTS/STT, Calendar/Reminder, Sync, Privacy, Data Location status |
| Settings Appearance | Light / Dark / System | 720x676 | theme picker and contrast controls |
| MCP Settings | Light / Dark / System | 720x676 | registered MCP rows without secrets or machine-local paths |
| Voice Command | Light / Dark / System | 760x640 | command entry, local interpretation, approval boundary |

## Tolerances

The gate uses semantic tolerances:

- Minimum bytes, width, and height reject tiny or wrong-window captures.
- Luminance range and color bucket count reject black, blank, and low information images.
- Raster comparison decodes both PNGs into canonical RGBA and compares the complete raster without resizing. A pixel changes when its largest RGB channel delta exceeds `0.10` (delta / 255). The defaults permit a changed-pixel ratio of at most `0.005` and mean absolute RGB error of at most `0.01`.
- Pixel-perfect equality is not required, but a broad visual change fails. Identical images pass.
- Exact raster equality is allowed only between themes of the same screen. Two different screen IDs with identical decoded rasters fail closed because that usually means the capture never reached the intended tab, selection, or scroll position.
- A screen or theme may override raster thresholds only with a nonblank `reason` in the manifest, so a looser exception remains reviewable.
- AX frame checks remain required because image comparison alone cannot reliably prove controls are not overlapping.

The manifest's `baselineContext` fixes the registered baseline source commit, `normalRoute`, locale, timezone, and reference instant. Its `sourceCommit` identifies the product source used to approve the stored baselines. A new normal capture may come from a later product commit, so its receipt records the current full product-source commit independently instead of copying the manifest's older baseline commit. Product source means the latest committed change anywhere under `Sources` or in `Package.swift`, including runtime modules that can affect visible UI; capture-script-only commits do not invalidate it or create a self-reference. Baseline sidecar metadata must match the full manifest context, appearance, and logical viewport. Logical viewport is the capture contract; it may differ from PNG raster dimensions, but current and baseline raster dimensions must exactly match each other.

When a repository uses squash merge, do not merge product-source changes and their final tracked evidence as one squash commit. Squashing rewrites the product source commit after the evidence was generated, which makes an otherwise valid baseline stale on `main`. Merge the product change first, then refresh the manifest, sidecar metadata, screenshot evidence, and other source-pinned release evidence in an evidence-only follow-up PR. That follow-up must not change `Sources` or `Package.swift`, so its own merge cannot move the product source commit again.

The main-window viewport is bounded to `1024x724`, the full visible frame available on the GitHub-hosted macOS GUI session used by the required visual lane. The 724-point frame preserves the product's 620-point minimum content area after the native titlebar and toolbar are included. This also makes compact-window layout behavior part of the canonical regression contract instead of approving a desktop-only viewport that CI cannot reproduce.

## AX audit receipt

For every screen/theme with `axFrameAudit` (or global `requiresAXFrameAudit`), the checker reads the default capture receipt at `.tmp/visual-ax-audit-receipt.json`. Use `--ax-audit-result <receipt.json>`, `SOLOPM_AX_AUDIT_RESULT`, or the capture-side `SOLOPM_VISUAL_AX_AUDIT_RESULT` to override it. The JSON receipt records `result`, the current product-source commit, route, actual configured runtime locale, timezone, reference instant, `createdAt`, and each screen's id, logical viewport, appearance, artifact, digest, actual window frame, target identifier, target frame, visible target frame, and status. The writer requires route, locale, timezone, and reference instant to match the manifest, but does not require the current receipt source commit to equal the registered baseline source commit during a normal comparison. The comparator independently validates those runtime fields and binds the receipt to the resolved current product-source commit. The receipt must be fresh, passed, complete, no more than 15 minutes old, and not more than 60 seconds in the future. `actualWindowFrame` must exactly equal the manifest viewport. At least one exact-ID AX target match must belong to the capture-owned PID, have a positive frame, and intersect the selected window and every ancestor scroll area by at least 44 points in each available dimension. SwiftUI may propagate one identifier to several generated AX elements; when that occurs, the audit deterministically records the candidate with the largest visible area. A fabricated, stale, screenshot-only, offscreen-target, or wrong-window receipt is a BLOCKER. The receipt is produced from successful live AX target/window capture, not a hand-authored JSON.

This receipt proves the intended capture landmark is materially visible; it is not a whole-screen sibling-overlap proof. Run `script/check_layout_stability_smoke.sh` for the separate overlap, clipping, and frame-jump gate.

## Capture Contract

Run `script/capture_ui_evidence.sh --doctor` before writing release evidence. The exact full capture command is `script/capture_ui_evidence.sh`; it writes screenshots under `docs/release/evidence/ui-screenshots` and the live AX receipt under `.tmp/visual-ax-audit-receipt.json`. Set `SOLOPM_VISUAL_AX_AUDIT_RESULT=/absolute/path/receipt.json` to override the receipt output. `SOLOPM_VISUAL_BASELINE_VIEWPORT`, `SOLOPM_SETTINGS_VISUAL_BASELINE_VIEWPORT`, `SOLOPM_VOICE_COMMAND_VISUAL_BASELINE_VIEWPORT`, `SOLOPM_UI_EVIDENCE_LOCALE=english|japanese`, and `SOLOPM_UI_EVIDENCE_TMPDIR` are the capture environment controls. Any mode that can write screenshots invalidates the previous receipt before its first capture. A new receipt is generated only after all 33 PNGs pass image health checks; doctor, dry-run, and partial modes do not claim one.

Canonical baselines use reference instant `2026-07-10T12:00:00Z` in timezone `UTC`. The capture script derives shell `today`, `tomorrow`, and `yesterday` fixtures from that instant and injects the same capture-only clock into SoloPM's Today, Schedule, Done, portfolio, and Smart List date-dependent UI. It also pins the product language, `AppleLanguages`, `AppleLocale`, and process `TZ`. These overrides are intentionally scoped to visual evidence environment keys; ordinary app launches leave them unset and continue to use the system clock, locale, and timezone.

Commit product-source changes before any full or partial capture. Mutating capture modes fail closed when `Sources` or `Package.swift` has staged, unstaged, or untracked changes, and there is no override. This keeps the receipt's full product `sourceCommit` tied to the binary that rendered the PNGs. Doctor reports dirty source as a blocker; dry-run remains non-mutating and reports what a real capture would block.

Capture target validation runs before every product screenshot. The script waits for the destination-specific AX identifier and seeded screen text, such as `project-board-detail` plus `Launch Readiness` for Project Board or `voice-command-root` plus `Voice Command` for Voice Command, before it calls `screencapture`. This keeps a visually valid but semantically wrong screen, such as Today saved as Project Board, from becoming release evidence.

Screen variants on the same route must also produce distinct visible states. Inbox Voice scrolls to its voice intake detail, Schedule and Schedule Workload scroll to their own AX landmarks, and Settings Integrations opens the real Sync tab. Adding a new same-route baseline requires an equally explicit state transition.

The capture script also records the Light/Dark/System visual baseline manifest path and viewport contract in generated evidence so reviewers know which product screens were targeted. The logical viewport describes the manifest contract and must equal `actualWindowFrame`; PNG raster dimensions may still differ because of display scale.

Secret input screens are excluded from the default visual baseline manifest. Only masked SecureField state may be captured if a future release needs a secret-entry screenshot. API keys and provider tokens are not read, written, logged, rendered, or captured unmasked.

## Update Flow

Normal `script/check_visual_regression_smoke.sh` runs do not overwrite baselines. In other words, a default visual smoke run does not overwrite baselines. They require each baseline PNG and adjacent `.metadata.json`; on a raster failure they write `baseline.png`, `current.png`, `diff.png`, and `metrics.json` under `--artifact-dir/<screen>/<theme>/` (or `SOLOPM_VISUAL_ARTIFACT_DIR`). Baseline files are never written in normal mode.

Baseline updates require an intentional command:

```bash
script/check_visual_regression_smoke.sh --update-baselines --allow-update
```

Use the explicit paired form `--update-baselines --allow-update`; `--update-baselines` by itself is rejected. Before an update, the manifest's registered baseline `sourceCommit` must be intentionally aligned with the current product-source commit recorded by the receipt. Update mode validates that alignment, every current image, and the AX receipt before staging all PNGs and metadata (`sourceCommit`, route, locale, timezone, reference instant, appearance, logical viewport, raster dimensions, and generation time), then atomically replaces the baseline directory. It never partially overwrites a baseline set.

Baseline update PRs must attach before/after artifact evidence and explain the product reason for the visual change. Do not use baseline updates to hide black screens, missing content, low contrast, AX frame overlap, or incorrect window captures.
