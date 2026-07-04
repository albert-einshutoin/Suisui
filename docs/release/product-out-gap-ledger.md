# Product-Out Gap Ledger

This ledger tracks the five current product-out work lanes that must be closed before SoloPM can be treated as a public release candidate. It is not release evidence; use it to keep blockers, accepted risks, and deferred Phase16/17 work explicit while `script/release_readiness_report.sh` and the evidence files remain the source of truth.

## Release Candidate Context

- Release candidate source commit: use the latest `Source commit` and `Release-candidate product source commit` from the generated release action summary.
- Last observed local report: `./script/release_readiness_report.sh` returned `NOT READY`.
- Evidence rule: a lane cannot move from `Blocker` to `Accepted Risk` without a linked known limitation or support note.
- Handoff rule: a lane cannot move to `Deferred` without a concrete Phase16/17 handoff issue or task.

## Classification Legend

- Blocker: must be completed or consciously reclassified before public release.
- Accepted Risk: product can ship only if the user-facing limitation, support path, and owner are documented.
- Deferred: intentionally outside the release candidate and routed to Phase16/17 with a concrete follow-up.

## Current Lanes

| Lane | Issue | Classification | Owner | Reproduction / verifier | Next action | Known limitations link | Phase16/17 handoff |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Google Calendar live sync | [#3](https://github.com/albert-einshutoin/soloPM/issues/3), [#11](https://github.com/albert-einshutoin/soloPM/issues/11) | Blocker | Release owner | `SOLOPM_RUNTIME_SETTINGS_SAVE_TIMEOUT_SECONDS=90 ./script/check_runtime_settings_save_smoke.sh`, then `script/create_google_calendar_live_evidence.sh --validate-only` after a real Google OAuth connect/list/select/write pass | Capture credential-backed OAuth consent, calendar picker, saved calendar ID, approved event write evidence, duplicate-skip proof, and Keychain token-boundary notes with a test calendar. | `docs/release/public-alpha.md` if live sync is kept out of alpha | Phase16 connector reliability and sync onboarding if full Google production sync is deferred |
| Local OSS TTS packaged runtime | [#14](https://github.com/albert-einshutoin/soloPM/issues/14) | Blocker | Release owner | `SOLOPM_LOCAL_VOICE_EVIDENCE_FILE=docs/release/evidence/local-voice-runtime.md SOLOPM_STT_EXPECTED_TRANSCRIPT_CONTAINS="<expected words>" ./script/check_local_voice_runtime_smoke.sh` plus signed app Settings Test Play | Refresh current-source local voice evidence, capture Settings Test Play in the app, and prove no Kokoro or whisper model binary is committed or bundled. | `docs/voice-models.md` for model download/cache constraints | Phase16 first-run model install UX if bundled runtime packaging is deferred |
| Daily Planning VoiceOver closeout | [#23](https://github.com/albert-einshutoin/soloPM/issues/23) | Blocker | Accessibility reviewer | `./script/prepare_release_manual_helpers.sh`, `.tmp/voiceover-review/create-evidence-command.sh --validate-only`, then real VoiceOver pass | Complete manual VoiceOver notes for Inbox voice triage, Today rail actions, Daily Planning readout/drafts, task content execution, and destructive confirmation on the current release candidate. | `docs/release/public-alpha.md` if any spoken workflow remains manual-only | Phase16 onboarding and accessibility learning items for non-blocking UX improvements |
| Release machine signing, notarization, Sparkle | Phase15 P15-005 | Blocker | Release owner | `./script/check_release_machine_local_doctor.sh`, `./script/verify_release_environment.sh`, generated `.tmp/release-machine/create-release-evidence-command.sh --validate-only` | Configure local signing/notary/Sparkle env, build signed app, notarize, staple, verify Gatekeeper, generate appcast and `packaging/release-evidence.json`. | `docs/release/checklist.md` and `docs/release/privacy-security.md` | Phase16 release channel automation if manual packaging remains acceptable for alpha |
| UI evidence refresh | [#12](https://github.com/albert-einshutoin/soloPM/issues/12) | Blocker | UI reviewer | `script/capture_ui_evidence.sh --doctor`, then `script/capture_ui_evidence.sh`; verify with `./script/check_visual_regression_smoke.sh` | Refresh current-source Project Board, Inbox, Today, Schedule, Done, Settings, MCP, and Voice Command screenshots; convert any layout findings into focused tests. | `docs/release/public-alpha.md` if visual limitations are explicitly accepted | Phase17 post-launch UI refinement backlog for non-blocking polish |

## Accepted Risk Register

No lane is currently accepted as a release risk. Add a row only when the risk has all of the following: owner, user-facing known limitation, support response, and release decision date.

| Risk | Owner | Known limitations link | Support response | Decision date |
| --- | --- | --- | --- | --- |
| None | n/a | n/a | n/a | n/a |

## Deferred Register

No current blocker is deferred. Add a row only when the work is explicitly outside the release candidate and has a Phase16/17 handoff.

| Deferred item | Reason | Phase16/17 handoff | Owner |
| --- | --- | --- | --- |
| None | n/a | n/a | n/a |

## Update Rules

- Update this ledger after every release readiness run that changes blocker ownership or classification.
- Keep secrets, local absolute paths, OAuth tokens, Developer ID details, Sparkle private keys, and model file paths out of this file.
- Use `docs/quality/manual-to-automated-regression.md` when a manual pass finds a regression that should become a source, runtime, or visual test.
