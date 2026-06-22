# SoloPM Quality Status

Generated at: 2026-06-22T23:59:10Z
Source commit: e9f9164

## Summary

- Phase14 completion: 160/183 checked, 23 remaining (`tasks/Phase14-QualityRegressionHardening.md`)
- Open risk items: 0 (`docs/quality/regression-risk-map.md`)
- Manual-only risk items: 3 (`docs/quality/regression-risk-map.md`)
- Automated preflight evidence: `missing .tmp/automated-release-preflight-e9f9164.md`

## Unfinished Phase14 Items

- [ ] tasks/Phase14-QualityRegressionHardening.md:603:- [ ] `swift test --filter AppExperienceSourceTests`
- [ ] tasks/Phase14-QualityRegressionHardening.md:604:- [ ] `swift test --filter ReleasePipelineTests`
- [ ] tasks/Phase14-QualityRegressionHardening.md:605:- [ ] `swift test --filter ProjectBoardStoreTests`
- [ ] tasks/Phase14-QualityRegressionHardening.md:606:- [ ] `swift test`
- [ ] tasks/Phase14-QualityRegressionHardening.md:607:- [ ] `bash -n script/check_project_board_header_layout_smoke.sh`
- [ ] tasks/Phase14-QualityRegressionHardening.md:608:- [ ] `script/check_project_board_header_layout_smoke.sh`
- [ ] tasks/Phase14-QualityRegressionHardening.md:609:- [ ] `script/check_layout_stability_smoke.sh`
- [ ] tasks/Phase14-QualityRegressionHardening.md:610:- [ ] `script/check_runtime_accessible_crud_smoke.sh`
- [ ] tasks/Phase14-QualityRegressionHardening.md:611:- [ ] `script/check_accessibility_preflight.sh --runtime`
- [ ] tasks/Phase14-QualityRegressionHardening.md:612:- [ ] `script/capture_ui_evidence.sh --doctor`
- [ ] tasks/Phase14-QualityRegressionHardening.md:613:- [ ] `script/check_visual_regression_smoke.sh`
- [ ] tasks/Phase14-QualityRegressionHardening.md:614:- [ ] `script/check_security_regressions.sh`
- [ ] tasks/Phase14-QualityRegressionHardening.md:615:- [ ] `script/quality_status_report.sh`
- [ ] tasks/Phase14-QualityRegressionHardening.md:619:- [ ] Risk mapが主要画面、主要状態変更、検証層、owner testを網羅している。
- [ ] tasks/Phase14-QualityRegressionHardening.md:620:- [ ] Project Boardのsidebar/header/detail/inspectorのlayout stability smokeが通る。
- [ ] tasks/Phase14-QualityRegressionHardening.md:621:- [ ] Sidebar toggle、toolbar display mode、window resize、theme switch、inspector open/closeの直後frame jumpを検出できる。
- [ ] tasks/Phase14-QualityRegressionHardening.md:622:- [ ] Runtime CRUD、Inbox、Today、Settings、Voice Commandの主要クリックパスがsmokeで検証される。
- [ ] tasks/Phase14-QualityRegressionHardening.md:623:- [ ] Visual screenshot smokeがLight/Dark/Systemの主要画面を検証し、黒画面/低情報量/対象window誤りを落とす。
- [ ] tasks/Phase14-QualityRegressionHardening.md:624:- [ ] Accessibility preflightが主要CRUDのlabel/help/focus/keyboard pathを検証する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:625:- [ ] Persistence/migration/security regression suiteが破損データとsecret leakageを検出する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:626:- [ ] Flake quarantineはowner、reason、expiryなしに追加できない。
- [ ] tasks/Phase14-QualityRegressionHardening.md:627:- [ ] Manual evidenceで見つかった問題を自動regressionへ戻す運用が文書化されている。
- [ ] tasks/Phase14-QualityRegressionHardening.md:629:- [ ] `swift test` がgreen。

## Open Risk Items

- [x] No open risk markers found.

## Runtime / Visual / Manual Evidence

| Evidence | Status | Source commit |
| --- | --- | --- |
| `docs/release/evidence/ui-screenshots.md` | present | e3886c6 |
| `docs/release/evidence/mcp-inspector.md` | present | 881b693 |
| `docs/release/evidence/accessibility-voiceover.md` | passed | e488456 |
| `docs/release/evidence/competitor-hands-on.md` | pending | unknown |

## Gate Classification

| Gate | Layer | Status | Evidence / command | Next action |
| --- | --- | --- | --- | --- |
| Lightweight PR gate | source + build | available | `scripts/ci.sh` | Use as the default fast PR verifier; opt into runtime, visual, or release lanes with SOLOPM_CI_* flags. |
| Focused tests | source + unit | pending | `swift test --filter <suite>` | Run the three owner suites when touching UI contracts, release gates, or Project Board persistence. |
| Full test suite | unit + integration | passed | `swift test` | Run before closing the Phase14 exit gate. |
| Runtime smoke | runtime AX | pending | `script/check_runtime_accessible_crud_smoke.sh` | Run on a visible macOS session to cover CRUD, Inbox, Today, Settings, Voice Command, and layout stability. |
| Visual smoke | visual | pending | `script/check_visual_regression_smoke.sh` | Use screenshot doctor first, then compare Light/Dark/System evidence. |
| Manual evidence | manual | VoiceOver: passed; Competitor: pending | `docs/release/evidence/accessibility-voiceover.md` | Manual findings must link back through docs/quality/manual-to-automated-regression.md. |
| Release readiness handoff | release | available | `script/release_readiness_report.sh` | Run after quality gaps are classified; readiness remains the release gate, not this dashboard. |

## Next Quality Gaps

Unchecked Phase14 items to close next:
- [ ] tasks/Phase14-QualityRegressionHardening.md:603:- [ ] `swift test --filter AppExperienceSourceTests`
- [ ] tasks/Phase14-QualityRegressionHardening.md:604:- [ ] `swift test --filter ReleasePipelineTests`
- [ ] tasks/Phase14-QualityRegressionHardening.md:605:- [ ] `swift test --filter ProjectBoardStoreTests`
- [ ] tasks/Phase14-QualityRegressionHardening.md:606:- [ ] `swift test`
- [ ] tasks/Phase14-QualityRegressionHardening.md:607:- [ ] `bash -n script/check_project_board_header_layout_smoke.sh`

- [ ] Manual evidence status is VoiceOver=passed, Competitor=pending. Next: use `script/release_readiness_report.sh` for release evidence blockers and link any findings to regression coverage.

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
- `SOLOPM_AUTOMATED_PREFLIGHT_EVIDENCE_FILE=.tmp/automated-release-preflight-e9f9164.md ./script/check_automated_release_preflight.sh`
- `SOLOPM_AUTOMATED_PREFLIGHT_EVIDENCE_FILE=.tmp/automated-release-preflight-e9f9164.md ./script/release_readiness_report.sh`

## Notes

- This dashboard is a quality triage aid, not release evidence.
- Manual VoiceOver, competitor hands-on, and release-machine evidence remain separate release gates.
- Secret-like values are redacted before writing this report.
