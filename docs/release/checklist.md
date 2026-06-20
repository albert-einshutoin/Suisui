# Release Checklist

This checklist is the single runbook for reproducing a SoloPM public alpha release.

## Preconditions

- Release branch is cut from `develop`.
- `security find-identity -p codesigning -v` shows a Developer ID Application identity.
- `packaging/signing.env` exists only on the release machine.
- `packaging/notarization.env` exists only on the release machine.
- `packaging/release-evidence.json` exists only on the release machine after manual checks.
- Sparkle private key exists in Keychain.
- `SOLOPM_SPARKLE_FEED_URL` is a production HTTPS appcast URL, and `SOLOPM_SPARKLE_PUBLIC_ED_KEY` is set for release builds.

## Order

1. test

```bash
swift test
./scripts/ci.sh
```

2. build

```bash
SOLOPM_BUILD_CONFIGURATION=release ./script/build_and_run.sh --build-only
SOLOPM_BUILD_CONFIGURATION=release ./script/build_and_run.sh --verify
```

`--verify` must report a visible Project Board window, not only a running process.

3. sign

```bash
./script/verify_signing_setup.sh
./script/sign_app.sh
```

4. notarize

```bash
SOLOPM_RELEASE_PREFLIGHT_ONLINE=1 ./script/verify_notarization_setup.sh
./script/notarize_app.sh
```

5. package

```bash
SOLOPM_PACKAGE_FORMAT=all ./script/package_release.sh
```

6. checksum

```bash
cat dist/releases/*.sha256
```

7. appcast

`SOLOPM_SPARKLE_DOWNLOAD_URL_PREFIX` は environment か `packaging/sparkle.env` に production HTTPS artifact URL prefix を設定する。

```bash
SOLOPM_REQUIRE_RELEASE_APPCAST=1 ./script/generate_appcast.sh
SOLOPM_REQUIRE_RELEASE_APPCAST=1 ./script/verify_appcast.sh dist/releases/appcast.xml
```

8. manual release evidence

```bash
./script/prepare_release_manual_helpers.sh
./script/prepare_release_machine_evidence.sh
source packaging/app_metadata.env
export SOLOPM_RELEASE_ARTIFACT_SHA256_FILE="dist/releases/$APP_NAME-$MARKETING_VERSION+$CURRENT_PROJECT_VERSION.dmg.sha256"
./script/create_release_evidence.sh
```

After any source commit changes, run `./script/prepare_release_manual_helpers.sh` before recording manual evidence. It regenerates the VoiceOver pending preview/launch env/command, competitor hands-on pending evidence, competitor benchmark pending worksheet, competitor hands-on worksheet/command, and release-machine worksheet/command for the current source commit without writing passed evidence. Use the lane-specific preparation scripts when you are iterating on one helper, but use the wrapper when the release action summary reports stale or missing manual helpers. Manual Review Helper Freshness verifies `.tmp/voiceover-review/launch.env` contains `SOLOPM_VOICEOVER_REVIEW_SOURCE_COMMIT` for the current source commit and a concrete `SOLOPM_VOICEOVER_REVIEW_PROJECT_ID`. After committing source changes, `./script/prepare_release_manual_helpers.sh --prune-stale` removes ignored pending previews for older source commits and legacy default preview files while keeping the current helper files and without writing passed evidence.
The manual helper wrapper itself requires a clean tracked source tree before regenerating pending previews or command files, so commit or revert tracked changes before preparing manual review helpers for a release candidate.
The preparation script writes `.tmp/release-machine/release-machine-worksheet.md` and `.tmp/release-machine/create-release-evidence-command.sh`. Fill the worksheet while performing the release-machine checks, then run the generated command only after replacing every placeholder with concrete observations from the signed, notarized, stapled release artifact.
The generated release evidence command requires a clean tracked source tree, pins the source commit it was created for, and exits before writing evidence if the worktree is dirty or has moved to another commit. Rerun `./script/prepare_release_manual_helpers.sh` after any source commit changes so release evidence, package evidence, and manual worksheet observations stay bound to the same release candidate.
The generated release-machine command requires `packaging/signing.env`, `packaging/notarization.env`, and `packaging/sparkle.env` to exist on the release machine and sources them before validating or writing release evidence.
The generated release-machine command runs signing, online notarization profile, and release Sparkle setup verifiers before `create_release_evidence.sh --validate-only`.
Run the generated release-machine `--validate-only` command first; it performs the same release evidence validation without writing `packaging/release-evidence.json`. Only run the generated `--force` write command after validation succeeds and every signed/notarized release-machine manual check is complete.
The generated release-machine command reruns `SOLOPM_RELEASE_PREFLIGHT_ONLINE=1 ./script/verify_release_environment.sh` after writing release evidence, so the operator sees the final release-machine gate result before returning to `release_readiness_report.sh`.
Direct manual evidence scripts also require a clean tracked source tree before writing passed evidence. This applies to `./script/create_release_evidence.sh`, `./script/create_voiceover_evidence.sh --passed`, and `./script/create_competitor_hands_on_evidence.sh --passed`, even when the generated worksheet command is bypassed.
Passed VoiceOver and competitor hands-on evidence must include the generator provenance line (`Generated by: script/create_voiceover_evidence.sh` or `Generated by: script/create_competitor_hands_on_evidence.sh`). `release_readiness_report.sh` rejects hand-written `Status: passed` manual evidence without that marker, even when the other context fields look complete.
Passed VoiceOver evidence must also identify the actual macOS version used for the manual pass. `macOS unknown`, `macOS version`, placeholders, samples, examples, or replacement text are rejected before evidence is written and remain release blockers if found in tracked evidence.
Release-machine evidence must also include generator provenance. `./script/create_release_evidence.sh` writes `generator.name: script/create_release_evidence.sh`, and `verify_release_environment.sh` rejects hand-written `packaging/release-evidence.json` files without that canonical generator field.

Run the evidence script after packaging and appcast generation so `release.version`, `release.buildNumber`, `release.appBundlePath`, `release.artifactSha256`, `release.signingIdentity`, `release.notaryProfile`, `release.sparkleFeedURL`, and `release.appcastPath` are bound to `packaging/app_metadata.env`, local release configuration, the generated checksum, and the release appcast. The script refuses missing or invalid release Sparkle config before writing evidence. After the Manual Checks below are complete, rerun it with:
The script also requires the matching `*.package-evidence.json` generated by `./script/package_release.sh`, the checksum file's release artifact file, and a release-mode-valid appcast; do not hand-write checksums, use `dist/package-smoke/` artifacts, or record evidence from an unsigned appcast.

```bash
source packaging/app_metadata.env
export SOLOPM_RELEASE_ARTIFACT_SHA256_FILE="dist/releases/$APP_NAME-$MARKETING_VERSION+$CURRENT_PROJECT_VERSION.dmg.sha256"
./script/create_release_evidence.sh \
  --validate-only \
  --release-machine-launch \
  --checksum-verification \
  --clean-dmg-install \
  --applications-folder-install \
  --gatekeeper-accepted \
  --clean-environment-launch \
  --login-item-toggle \
  --sparkle-appcast-metadata \
  --manual-environment "macOS version, hardware, clean user/install notes" \
  --checked-by "$USER" \
  --note "Verified release-machine launch from dist/SoloPM.app, checksum SHA-256, clean DMG install, Applications install, Gatekeeper acceptance, clean environment launch, login item toggle, and Sparkle appcast metadata on macOS 15.5 arm64 signed build."
./script/create_release_evidence.sh \
  --force \
  --release-machine-launch \
  --checksum-verification \
  --clean-dmg-install \
  --applications-folder-install \
  --gatekeeper-accepted \
  --clean-environment-launch \
  --login-item-toggle \
  --sparkle-appcast-metadata \
  --manual-environment "macOS version, hardware, clean user/install notes" \
  --checked-by "$USER" \
  --note "Verified release-machine launch from dist/SoloPM.app, checksum SHA-256, clean DMG install, Applications install, Gatekeeper acceptance, clean environment launch, login item toggle, and Sparkle appcast metadata on macOS 15.5 arm64 signed build."
```

Set manual check flags only for that signed and notarized build. Each flag maps to a Manual Checks bullet below; do not set a flag unless that exact check was performed on the same release artifact. Record the OS, hardware, install location, and clean user/profile details in `--manual-environment`.
Do not leave the template text in `--manual-environment`; `create_release_evidence.sh` and `verify_release_environment.sh` reject blank, placeholder, sample, example, todo, replace-style, or weak environment descriptions. Manual environment must include the macOS version, clean user or VM/install context, and hardware or CPU architecture.
Keep `--checked-by` and `--note` concrete as well; blank reviewer names, placeholder names such as "Reviewer Name", and placeholder role names such as "Release reviewer" or "Product reviewer" are rejected, as are blank review notes and boilerplate notes such as "Manual checks completed", so the evidence identifies who reviewed the release and why the checks were accepted; manual release flags require an explicit review note.
The evidence scripts reject manual flags whose `--note` does not mention the matching observed proof.
The source git commit is recorded in release evidence and checked against package evidence during final preflight, so regenerate the signed package and evidence after any source commit changes.
Use `packaging/release-evidence.example.json` only as the schema template; do not copy it as final evidence without running the script.

Manual flag evidence requirements:

| Flag | Required proof in `--note` |
| --- | --- |
| `--release-machine-launch` | Signed/notarized app opens from `dist/SoloPM.app` on the release machine. |
| `--checksum-verification` | `shasum -a 256` matches the generated `*.sha256` artifact. |
| `--clean-dmg-install` | DMG downloads and opens in a clean user or VM. |
| `--applications-folder-install` | App is dragged to `/Applications` and launches there. |
| `--gatekeeper-accepted` | `spctl`/Gatekeeper accepts the stapled app. |
| `--clean-environment-launch` | First launch succeeds in the clean user or VM. |
| `--login-item-toggle` | Settings toggles launch-at-login on and off in the signed app. |
| `--sparkle-appcast-metadata` | Release appcast metadata points to this version/build. |

The `--note` value must name the observed result for each true manual flag.

9. release environment preflight

```bash
source packaging/app_metadata.env
export SOLOPM_RELEASE_ARTIFACT_SHA256_FILE="dist/releases/$APP_NAME-$MARKETING_VERSION+$CURRENT_PROJECT_VERSION.dmg.sha256"
SOLOPM_RELEASE_PREFLIGHT_ONLINE=1 ./script/verify_release_environment.sh
```

10. MCP Inspector evidence

Regenerate the MCP stdio Tools evidence for this release candidate:

```bash
./script/verify_mcp_compliance.sh
```

Confirm `docs/release/evidence/mcp-inspector.md` includes:

- `- Source commit: \`<latest MCP runtime/fixture source commit>\``
- ``Stable baseline: `2025-11-25` ``
- ``Official stable latest: `2025-11-25` ``
- `Official latest source: https://modelcontextprotocol.io/specification`
- `Official GitHub releases source: https://github.com/modelcontextprotocol/modelcontextprotocol/releases`
- `Official GitHub release assertion: GitHub marks 2025-11-25 as Latest stable release and 2026-07-28 RC as Pre-release.`
- `Official versioning source: https://modelcontextprotocol.io/docs/learn/versioning`
- ``Official versioning assertion: current protocol version is `2025-11-25` ``
- `Official latest checked: 2026-06-20`
- `Official stable source: https://modelcontextprotocol.io/specification/2025-11-25`
- ``Draft watchlist: `2026-07-28` ``
- `Draft changelog source: https://modelcontextprotocol.io/specification/draft/changelog`
- ``Draft changelog assertion: changes are listed since `2025-11-25`; it is not the current release baseline. ``
- `tools/list` and `tools/call`
- malformed-json / mismatched-id / invalid-schema / timeout failure taxonomy

If `Sources/SoloPMCore/ExternalMCP`, `Sources/SoloPMApp/SoloPMApp.swift`, `fixtures/mcp`, or `Package.swift` changes after this evidence is generated, rerun `./script/verify_mcp_compliance.sh`; `release_readiness_report.sh` rejects MCP Inspector evidence whose `Source commit` no longer matches the current MCP runtime/fixture source commit.

SoloPM must not be described as a full MCP host for this release.

11. UI and accessibility evidence

Generate Light/Dark/System screenshots on a host with Screen Recording permission:

```bash
script/capture_ui_evidence.sh --doctor
script/capture_ui_evidence.sh
```

`docs/release/evidence/ui-screenshots.md` records the latest UI runtime source commit from `Sources/SoloPMApp`, `Sources/SoloPMCore`, and `Package.swift`; rerun `script/capture_ui_evidence.sh` after UI/runtime source changes so the release report cannot reuse stale screenshots.

Run the accessibility preflight before the manual VoiceOver pass. The source-only check is safe for CI/local review and verifies both accessibility anchors and primary CRUD keyboard shortcuts; the runtime check launches `dist/SoloPM.app` and requires macOS Accessibility permission for Terminal/Codex:

```bash
./script/check_accessibility_preflight.sh --source-only
./script/check_accessibility_preflight.sh --runtime
```

The runtime preflight is intentionally stricter than a process/window check: it scans visible windows by AX role and fails if the best release-candidate window has fewer than the minimum buttons, text fields, or static texts, if it exposes unlabeled AX buttons, if a button only reports the generic `button` label without help or child text, if the visible Project Board does not expose the expected primary CRUD button help signals as `crudSignals=8/8`, or if it does not expose the VoiceOver focus path signals as `focusPathSignals=6/6`. The focus path signals cover Project navigation, Project board detail, Open task, Inline Task Composer, Status controls, and Task inspector so a low-information AX tree is not enough evidence for the manual VoiceOver pass.

When reviewing a local release candidate in a visible macOS session, include the runtime AX smoke in the readiness report:

```bash
SOLOPM_ACCESSIBILITY_RUNTIME_PREFLIGHT=1 ./script/release_readiness_report.sh
```

Before claiming local CRUD is product-ready, run the runtime accessible CRUD smoke. It builds `dist/SoloPM.app`, launches it with an isolated `SOLOPM_DATABASE_PATH`, selects a seeded Project Board via `SOLOPM_PROJECT_BOARD_SELECTED_DESTINATION`, then uses macOS Accessibility to create, rename, complete, and delete a project; create, update, move, and directly delete a task; and verify project deletion removes a remaining task from SQLite:

```bash
./script/check_runtime_accessible_crud_smoke.sh
SOLOPM_RUNTIME_ACCESSIBLE_CRUD_SMOKE=1 ./script/release_readiness_report.sh
```

Prepare the manual VoiceOver candidate with deterministic local data before starting the screen-reader pass. This creates an isolated `.tmp/voiceover-review/SoloPM-voiceover-review.sqlite`, seeds `VoiceOver Review Project` with one task in each board column plus an accessibility evidence artifact link, prints the `SOLOPM_DATABASE_PATH` / `SOLOPM_PROJECT_BOARD_SELECTED_DESTINATION` launch command, and writes `.tmp/voiceover-review/create-evidence-command.sh` for the matching evidence step. Use `--no-launch` when you only want to inspect the generated database before opening the app:

```bash
./script/prepare_voiceover_review_candidate.sh --no-launch
./script/prepare_voiceover_review_candidate.sh
```

Replace every placeholder in that generated command with concrete observations from the manual pass before running it.
The generated VoiceOver evidence command requires a clean tracked source tree, pins the source commit it was created for, and exits before writing evidence if the worktree is dirty or has moved to another commit. The script also writes `.tmp/voiceover-review/accessibility-voiceover-pending-<commit>.md` so the reviewer can inspect the current release-candidate context without modifying tracked evidence. The generated `.tmp/voiceover-review/launch.env` records `SOLOPM_VOICEOVER_REVIEW_SOURCE_COMMIT` and `SOLOPM_VOICEOVER_REVIEW_PROJECT_ID` so manual reviewers can confirm the launched candidate matches the current source commit and seeded project. The generated evidence command reloads that `launch.env`, verifies the seeded candidate database and project id, launches the same candidate before runtime AX smoke capture, and blocks if the helper context is stale. Rerun `./script/prepare_release_manual_helpers.sh` after any source commit changes so the candidate database, release app, runtime AX smoke, and manual VoiceOver observations stay bound to the same release candidate.
Run the generated `--validate-only` command first; it performs the same passed-evidence validation without writing `docs/release/evidence/accessibility-voiceover.md`. Only run the generated `--passed` command after validation succeeds and the real manual VoiceOver pass is complete.

Then replace `docs/release/evidence/accessibility-voiceover.md` with the real VoiceOver pass for the same release-candidate app. The final file must use `Status: passed`, complete the release-candidate context fields, include the runtime AX smoke OK line with `unlabeledButtons=0`, `genericButtons=0`, `crudSignals=8/8`, and `focusPathSignals=6/6`, include the Project navigation -> Project board detail -> Open task -> Inline Task Composer -> Status controls -> Task inspector path, and remove all pending/template language.

Use the generator to avoid stale bundle/build metadata:

Each focus-path note must name the concrete VoiceOver observation, control, or focus transition that was checked. Boilerplate notes such as `Verified.`, `Passed.`, `OK`, or `No issues` are rejected by both the generator and `release_readiness_report.sh`.

```bash
./script/create_voiceover_evidence.sh --pending
./script/create_voiceover_evidence.sh --validate-only \
  --checked-by "Reviewer Name" \
  --accessibility-environment "VoiceOver/keyboard/device details used for the manual pass" \
  --capture-runtime-ax-smoke \
  --project-navigation-note "Concrete VoiceOver observation for sidebar Inbox, Today, and Project navigation." \
  --project-board-detail-note "Concrete VoiceOver observation for selected project board context." \
  --open-task-note "Concrete VoiceOver observation for opening task details without pointer drag." \
  --inline-task-composer-note "Concrete VoiceOver observation for title/detail/priority/due/create/cancel paths." \
  --status-controls-note "Concrete VoiceOver observation for previous/next status move controls." \
  --task-inspector-note "Concrete VoiceOver observation for task inspector fields and actions." \
  --save-changes-note "Concrete VoiceOver observation for local task save activation." \
  --delete-confirmation-note "Concrete VoiceOver observation for destructive confirmation and cancel." \
  --no-keyboard-trap-note "Concrete VoiceOver observation that focus can leave every primary region." \
  --no-unlabeled-crud-note "Concrete VoiceOver observation that primary CRUD controls have labels or help." \
  --confirm-manual-voiceover-pass
./script/create_voiceover_evidence.sh --passed \
  --checked-by "Reviewer Name" \
  --accessibility-environment "VoiceOver/keyboard/device details used for the manual pass" \
  --capture-runtime-ax-smoke \
  --project-navigation-note "Concrete VoiceOver observation for sidebar Inbox, Today, and Project navigation." \
  --project-board-detail-note "Concrete VoiceOver observation for selected project board context." \
  --open-task-note "Concrete VoiceOver observation for opening task details without pointer drag." \
  --inline-task-composer-note "Concrete VoiceOver observation for title/detail/priority/due/create/cancel paths." \
  --status-controls-note "Concrete VoiceOver observation for previous/next status move controls." \
  --task-inspector-note "Concrete VoiceOver observation for task inspector fields and actions." \
  --save-changes-note "Concrete VoiceOver observation for local task save activation." \
  --delete-confirmation-note "Concrete VoiceOver observation for destructive confirmation and cancel." \
  --no-keyboard-trap-note "Concrete VoiceOver observation that focus can leave every primary region." \
  --no-unlabeled-crud-note "Concrete VoiceOver observation that primary CRUD controls have labels or help." \
  --confirm-manual-voiceover-pass
```

Use `--runtime-ax-smoke-note "OK: runtime AX smoke visible, ..."` only when the runtime AX smoke was already captured from the same release-candidate app. Prefer `--capture-runtime-ax-smoke` during the manual pass so the generator copies the OK line directly from `./script/check_accessibility_preflight.sh --runtime --skip-launch` without carrying stale counts into the evidence.

12. Competitor hands-on evidence

Before checking the Phase 11 competitor benchmark item, replace `docs/release/evidence/competitor-hands-on.md` with the real 2-4 hour hands-on record. Update `docs/product/competitor-benchmark.md` from worksheet/desk research to hands-on findings before final release readiness. The final evidence file must use `Status: passed`, complete reviewer/date/source/environment context, include the Notion -> Todoist -> Linear -> Motion path, document the Ship / Defer / Reject Delta, and explicitly confirm that no external SaaS sync or team workflow was added to public alpha scope.

Update the benchmark document from worksheet/desk research to hands-on findings before final release readiness. The release report rejects `docs/product/competitor-benchmark.md` while it still says the work is not a full hands-on trial record, still contains the release-candidate worksheet, or lacks a `## Hands-On Findings` section covering Notion, Todoist, Linear, Motion, and Ship / Defer / Reject.

Use the generator so pending evidence or a review worksheet cannot be mistaken for a pass. The passed generator writes both `docs/release/evidence/competitor-hands-on.md` and `docs/product/competitor-benchmark.md`, so the release report cannot be unblocked by updating only one of the two artifacts.

Running the pending generator also writes `.tmp/competitor-hands-on/hands-on-worksheet.md`, `.tmp/competitor-hands-on/competitor-benchmark-pending-<commit>.md`, and `.tmp/competitor-hands-on/create-evidence-command.sh`. Fill the worksheet during the hands-on pass, use the benchmark pending worksheet to keep Notion/Todoist/Linear/Motion findings and Ship/Defer/Reject decisions aligned, then use the generated command after the pass so the final evidence keeps the same output paths and required fields. Replace every placeholder in that generated command with concrete observations before running it; the script rejects the generated placeholders if they are not edited.
The generated competitor hands-on command requires a clean tracked source tree, pins the source commit it was created for, and exits before writing evidence if the worktree is dirty or has moved to another commit. Rerun `./script/prepare_release_manual_helpers.sh` after any source commit changes so the worksheet, evidence file, benchmark output, and release candidate stay aligned.
Run the generated competitor `--validate-only` command first; it performs the same passed-evidence validation without writing `docs/release/evidence/competitor-hands-on.md` or `docs/product/competitor-benchmark.md`. Only run the generated `--passed` command after validation succeeds and the real 2-4 hour hands-on pass is complete. The competitor passed command requires `--hands-on-duration` with a real 2-4 hour total and per-competitor timing.

Each competitor note and Ship / Defer / Reject delta must identify what was actually observed or decided during the hands-on pass. Boilerplate notes such as `Verified.`, `Passed.`, `OK`, `No issues`, or unedited `Concrete ... observation from the hands-on pass.` examples are rejected by both the generator and `release_readiness_report.sh`.

```bash
./script/create_competitor_hands_on_evidence.sh --pending
./script/create_competitor_hands_on_evidence.sh --validate-only \
  --checked-by "Reviewer Name" \
  --environment "macOS/browser versions, competitor app/account tiers, and whether any paid trial was used" \
  --hands-on-duration "2h 15m total: Notion 35m, Todoist 30m, Linear 35m, Motion 35m" \
  --notion-note "Concrete Notion observation from the hands-on pass." \
  --todoist-note "Concrete Todoist observation from the hands-on pass." \
  --linear-note "Concrete Linear observation from the hands-on pass." \
  --motion-note "Concrete Motion observation from the hands-on pass." \
  --ship "SoloPM public-alpha behavior to ship based on the benchmark." \
  --defer "Behavior to defer until stronger reliability or demand evidence exists." \
  --reject "Behavior to keep out of public alpha scope." \
  --benchmark-output docs/product/competitor-benchmark.md \
  --confirm-manual-hands-on
./script/create_competitor_hands_on_evidence.sh --passed \
  --checked-by "Reviewer Name" \
  --environment "macOS/browser versions, competitor app/account tiers, and whether any paid trial was used" \
  --hands-on-duration "2h 15m total: Notion 35m, Todoist 30m, Linear 35m, Motion 35m" \
  --notion-note "Concrete Notion observation from the hands-on pass." \
  --todoist-note "Concrete Todoist observation from the hands-on pass." \
  --linear-note "Concrete Linear observation from the hands-on pass." \
  --motion-note "Concrete Motion observation from the hands-on pass." \
  --ship "SoloPM public-alpha behavior to ship based on the benchmark." \
  --defer "Behavior to defer until stronger reliability or demand evidence exists." \
  --reject "Behavior to keep out of public alpha scope." \
  --benchmark-output docs/product/competitor-benchmark.md \
  --confirm-manual-hands-on
```

13. final readiness report

Run the automated local gate sweep first. It verifies CI, SQLite CRUD, runtime accessible CRUD, Xcode build, visible-window launch, runtime AX, and MCP compliance gates in one command. This automated sweep does not replace manual VoiceOver, competitor hands-on, signing, notarization, Sparkle, or Gatekeeper evidence.

The final readiness report treats skipped automated proof gates as blockers by default. Run the sweep command for a full local proof, point the report at a clean-tree automated preflight evidence file, or run the individual `SOLOPM_*_PREFLIGHT=1` / smoke flags below when narrowing failures. Do not claim release readiness from the default report output if CI, SQLite CRUD, runtime accessible CRUD, Xcode build, visible launch, or runtime AX were skipped.

Manual VoiceOver and competitor hands-on evidence record the current `Source commit`; rerun `./script/prepare_release_manual_helpers.sh` and then repeat the affected manual passes after code changes instead of reusing evidence from an older release candidate.

```bash
./script/check_automated_release_preflight.sh
export SOLOPM_AUTOMATED_PREFLIGHT_EVIDENCE_FILE=".tmp/automated-release-preflight-$(git rev-parse --short HEAD).md"
./script/check_automated_release_preflight.sh
```

Evidence-file mode requires a clean tracked source tree, so commit or discard tracked changes before producing release proof. The release readiness report auto-discovers `.tmp/automated-release-preflight-<commit>.md` for the current source commit when the environment variable is omitted.
When the final report reuses this evidence, it verifies the generator identity, UTC timestamp, source commit, clean-tree marker, app name, Xcode workspace/scheme/configuration/destination, every automated proof gate, and the manual-evidence boundary text.

```bash
source packaging/app_metadata.env
export SOLOPM_RELEASE_ARTIFACT_SHA256_FILE="dist/releases/$APP_NAME-$MARKETING_VERSION+$CURRENT_PROJECT_VERSION.dmg.sha256"
./script/release_readiness_report.sh
SOLOPM_RELEASE_ACTIONS_FILE=.tmp/release-actions.md ./script/release_readiness_report.sh
./script/release_readiness_report.sh # auto-discovers .tmp/automated-release-preflight-<commit>.md
SOLOPM_AUTOMATED_PREFLIGHT_EVIDENCE_FILE=".tmp/automated-release-preflight-$(git rev-parse --short HEAD).md" ./script/release_readiness_report.sh
SOLOPM_AUTOMATED_PROOF_GATES=1 ./script/release_readiness_report.sh
SOLOPM_RELEASE_CI_PREFLIGHT=1 ./script/release_readiness_report.sh
SOLOPM_LOCAL_CRUD_SMOKE=1 ./script/release_readiness_report.sh
SOLOPM_RUNTIME_ACCESSIBLE_CRUD_SMOKE=1 ./script/release_readiness_report.sh
SOLOPM_ACCESSIBILITY_RUNTIME_PREFLIGHT=1 ./script/release_readiness_report.sh
SOLOPM_RELEASE_XCODE_PREFLIGHT=1 ./script/release_readiness_report.sh
SOLOPM_BUILD_CONFIGURATION=release SOLOPM_RELEASE_LAUNCH_PREFLIGHT=1 ./script/release_readiness_report.sh
```

The Operator Priority Queue appears before the full blocker list and shows the highest-impact manual lanes, the blocker count each lane can clear, the release-environment item count for the release-machine lane, the unchecked manual phase-item count for checklist routing, and the next command or generated helper to use. The action summary groups remaining blockers into Automated Proof Gates, Manual VoiceOver, Competitor Hands-On, Release Machine, Phase Checklist, and Other buckets. The action summary includes a Local Product Gate Status section so reviewers can distinguish current-commit local MCP/data/CRUD proof from manual and release-machine blockers. If a login item manual gate remains, the Operator Priority Queue also calls out the signed-app Launch at Login check and points to `--login-item-toggle` in `.tmp/release-machine/create-release-evidence-command.sh`. When valid clean-tree automated preflight evidence is supplied, the Automated Proof Gates section shows the accepted evidence file, source commit, generated timestamp, and passed gates instead of only telling the operator to rerun the sweep. Manual VoiceOver and competitor hands-on blockers are also split into dedicated sections so the operator can repair evidence without treating those manual gates as passed. The Phase Checklist section also routes unchecked manual gates to Manual VoiceOver, Competitor Hands-On, Release Machine, Login Item Manual Check, or Manual Review so the operator can match each checklist item to the correct evidence path. If a login item manual gate remains, the action summary includes the `create_release_evidence.sh` command with `--login-item-toggle`, concrete `--manual-environment`, `--checked-by`, and a review `--note`, making it clear that launch-at-login evidence is bound to the signed release artifact rather than a standalone checkbox. The Release Machine section includes `./script/prepare_release_machine_evidence.sh`, `.tmp/release-machine/release-machine-worksheet.md`, `.tmp/release-machine/create-release-evidence-command.sh`, and an ordered command block for local secret setup, signing validation, notarization validation, release packaging, appcast generation, release evidence, and final preflight, while still requiring placeholders to be replaced with production values and real observations. That command block now edits and runs the generated `.tmp/release-machine/create-release-evidence-command.sh` before showing the direct `create_release_evidence.sh --force` fallback, so operators keep the generated validate-only step and final online preflight as the primary path. The action summary includes a Manual Evidence Source Hygiene section explaining that direct passed evidence scripts also require a clean tracked source tree. It also reminds operators that release-machine evidence must include `generator.name: script/create_release_evidence.sh` and that hand-written `packaging/release-evidence.json` remains blocked. Generated manual/release command files must fail validate-only until every placeholder is replaced, so template commands cannot be treated as evidence-ready. The release environment section routes verifier blockers to Signing Configuration, Notarization, Sparkle / Appcast, Gatekeeper / Stapling, Release Evidence, Source Hygiene, or Local Inspection while still redacting sensitive-looking values. The manual evidence sections include full generator commands with every required flag, but the placeholders must be replaced with real observations before running them. The Manual Review Helper Freshness section uses `./script/prepare_release_manual_helpers.sh` to regenerate the VoiceOver, competitor, and release-machine helper files for the current source commit without writing passed evidence. Manual Review Helper Freshness verifies `.tmp/voiceover-review/launch.env` contains `SOLOPM_VOICEOVER_REVIEW_SOURCE_COMMIT` for the current source commit and a concrete `SOLOPM_VOICEOVER_REVIEW_PROJECT_ID`. If old `.tmp/voiceover-review/*-pending-<old-commit>.md` or `.tmp/competitor-hands-on/*-pending-<old-commit>.md` previews remain, or if legacy default `.tmp/competitor-hands-on/evidence.md` remains, the Ignored Stale Manual Helper Previews section lists them as ignored so operators do not copy stale release-candidate context into tracked evidence. `./script/prepare_release_manual_helpers.sh --prune-stale` removes ignored old pending previews and legacy default preview files after the current helpers are regenerated, and does not write passed evidence. The Manual VoiceOver section includes `.tmp/voiceover-review/accessibility-voiceover-pending-<commit>.md` and `.tmp/voiceover-review/create-evidence-command.sh` before the final passed command, so operators can inspect release-candidate context without modifying tracked evidence. The Competitor Hands-On section includes `./script/prepare_release_manual_helpers.sh`, `.tmp/competitor-hands-on/hands-on-worksheet.md`, `.tmp/competitor-hands-on/competitor-benchmark-pending-<commit>.md`, and `.tmp/competitor-hands-on/create-evidence-command.sh` before the final passed command, so operators have editable helper files without accidentally marking the manual gate passed. The action summary also expands those pending paths for the current `Source commit`, making the exact VoiceOver and competitor pending evidence filenames visible without mentally substituting `<commit>`. When release environment preflight fails, it also copies the concrete `BLOCKER:` lines from `verify_release_environment.sh` into a `Release Environment Blockers` section with repo-relative paths and without secret-like values.

14. tag

```bash
git tag -a v0.1.0-alpha.1 -m "SoloPM 0.1.0 alpha 1"
```

15. release notes

Use [public-alpha.md](public-alpha.md) as the base. Include artifact names, checksums, supported macOS version, Known Issues, and rollback instructions.

## Manual Checks

- Launch signed and notarized app on the release machine.
- Download DMG in a clean environment.
- Verify checksum.
- Drag app to Applications.
- Confirm Gatekeeper does not reject the app.
- Confirm Settings can toggle launch at login in the signed app.
- Confirm Sparkle local appcast metadata points to the new build.
- Confirm Light/Dark/System screenshots show sidebar, task cards, and right inspector without overlap.
- Confirm VoiceOver can follow Project navigation -> Project board detail -> Open task -> Inline Task Composer -> Status controls -> Task inspector without unlabeled primary CRUD controls or keyboard traps.
- Record the manual check results in `packaging/release-evidence.json`.

## Rollback

1. Remove the broken artifact from the release page.
2. Repoint appcast to the previous known-good item or remove the new item.
3. Publish a rollback note explaining the issue and the previous version.
4. Keep the failed notarization and appcast logs for diagnosis.
5. Open a `fix/phase5-release-rollback` branch if code or scripts need changes.

## Known Issues

- Developer ID Application certificate is required for final sign verification.
- Apple notary profile is required for notarization.
- Sparkle update archive signing requires the private EdDSA key in Keychain.
- External MCP, SaaS connectors, full RAG, and Team features are not included in alpha.
