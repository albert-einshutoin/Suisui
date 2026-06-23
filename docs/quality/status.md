# SoloPM Quality Status

Generated at: 2026-06-23T10:53:16Z
Source commit: fa12243

## Summary

- Phase14 completion: 189/189 checked, 0 remaining (`tasks/Phase14-QualityRegressionHardening.md`)
- Open risk items: 0 (`docs/quality/regression-risk-map.md`)
- Manual-only risk items: 3 (`docs/quality/regression-risk-map.md`)
- Automated preflight evidence: current HEAD after a clean `./script/check_automated_release_preflight.sh` run (`.tmp/automated-release-preflight-$(git rev-parse --short HEAD).md`)

## Unfinished Phase14 Items

- [x] No unchecked Phase14 items found.

## Open Risk Items

- [x] No open risk markers found.

## Runtime / Visual / Manual Evidence

| Evidence | Status | Source commit |
| --- | --- | --- |
| `docs/release/evidence/ui-screenshots.md` | present | 805380b |
| `docs/release/evidence/mcp-inspector.md` | present | 7298e51 |
| `docs/release/evidence/accessibility-voiceover.md` | stale (passed; expected 805380b) | e488456 |
| `docs/release/evidence/competitor-hands-on.md` | pending | unknown |

## Gate Classification

| Gate | Layer | Status | Evidence / command | Next action |
| --- | --- | --- | --- | --- |
| Lightweight PR gate | source + build | available | `scripts/ci.sh` | Use as the default fast PR verifier; opt into runtime, visual, or release lanes with SOLOPM_CI_* flags. |
| Focused tests | source + unit | passed | `swift test --filter <suite>` | Run the three owner suites when touching UI contracts, release gates, or Project Board persistence. |
| Full test suite | unit + integration | passed | `swift test` | Run before closing the Phase14 exit gate. |
| Runtime smoke | runtime AX | passed | `script/check_runtime_accessible_crud_smoke.sh` | Run on a visible macOS session to cover CRUD, Inbox, Today, Settings, Voice Command, and layout stability. |
| Visual smoke | visual | passed | `script/check_visual_regression_smoke.sh` | Use screenshot doctor first, then compare Light/Dark/System evidence. |
| Manual evidence | manual | VoiceOver: stale (passed; expected 805380b); Competitor: pending | `docs/release/evidence/accessibility-voiceover.md` | Manual findings must link back through docs/quality/manual-to-automated-regression.md. |
| Release readiness handoff | release | available | `script/release_readiness_report.sh` | Run after quality gaps are classified; readiness remains the release gate, not this dashboard. |

## Next Quality Gaps

- [ ] Manual evidence status is VoiceOver=stale (passed; expected 805380b), Competitor=pending. Next: use `script/release_readiness_report.sh` for release evidence blockers and link any findings to regression coverage.

## Verification Commands

- `scripts/ci.sh`
- `swift test --filter AppExperienceSourceTests`
- `swift test --filter ReleasePipelineTests`
- `swift test --filter ProjectBoardStoreTests`
- `swift test`
- `bash -n script/check_project_board_header_layout_smoke.sh`
- `script/check_project_board_header_layout_smoke.sh`
- `script/check_layout_stability_smoke.sh`
- `script/check_runtime_accessible_crud_smoke.sh`
- `script/check_accessibility_preflight.sh --runtime`
- `script/capture_ui_evidence.sh --doctor`
- `script/check_visual_regression_smoke.sh`
- `script/check_security_regressions.sh`
- `script/quality_status_report.sh`
- `docs/quality/test-triage.md`
- `docs/quality/flake-quarantine.md`
- `./script/check_automated_release_preflight.sh`
- `SOLOPM_AUTOMATED_PREFLIGHT_EVIDENCE_FILE=.tmp/automated-release-preflight-$(git rev-parse --short HEAD).md ./script/release_readiness_report.sh`

## Notes

- This dashboard is a quality triage aid, not release evidence.
- Manual VoiceOver, competitor hands-on, and release-machine evidence remain separate release gates.
- Secret-like values are redacted before writing this report.
