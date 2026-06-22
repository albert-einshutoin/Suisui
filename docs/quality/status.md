# SoloPM Quality Status

Generated at: 2026-06-22T23:39:13Z
Source commit: 0199644

## Summary

- Phase14 completion: 148/183 checked, 35 remaining (`tasks/Phase14-QualityRegressionHardening.md`)
- Open risk items: 3 (`docs/quality/regression-risk-map.md`)
- Manual-only risk items: 3 (`docs/quality/regression-risk-map.md`)
- Automated preflight evidence: `missing .tmp/automated-release-preflight-0199644.md`

## Unfinished Phase14 Items

- [ ] tasks/Phase14-QualityRegressionHardening.md:539:- [ ] Manual evidenceにfailure noteがある場合、linked regression testまたはfollow-up issueが必要なことをreportで検出する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:545:- [ ] VoiceOverで見つかったlabel/focus問題はAX/source testへ戻す。
- [ ] tasks/Phase14-QualityRegressionHardening.md:546:- [ ] Gatekeeper/clean environmentで見つかった起動問題はpackaging/preflight testへ戻す。
- [ ] tasks/Phase14-QualityRegressionHardening.md:547:- [ ] Competitor hands-onで見つかったUX差分はPhase taskまたはproduct docへ戻す。
- [ ] tasks/Phase14-QualityRegressionHardening.md:552:- [ ] 手動確認で見つかった問題が、次回以降の自動検出対象になる。
- [ ] tasks/Phase14-QualityRegressionHardening.md:553:- [ ] manual-only gateとautomation-backlogが混ざらない。
- [ ] tasks/Phase14-QualityRegressionHardening.md:554:- [ ] release前に未処理manual findingが見える。
- [ ] tasks/Phase14-QualityRegressionHardening.md:585:- [ ] `swift test`、focused tests、runtime smoke、visual smoke、manual evidenceの状態を分類する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:586:- [ ] `release_readiness_report.sh` から参照できるようにする。
- [ ] tasks/Phase14-QualityRegressionHardening.md:590:- [ ] 品質状態を1コマンドで確認できる。
- [ ] tasks/Phase14-QualityRegressionHardening.md:591:- [ ] 次に潰すべきテスト漏れが明確になる。
- [ ] tasks/Phase14-QualityRegressionHardening.md:592:- [ ] release readinessと重複せず、品質観点の補助reportとして使える。
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

## Open Risk Items

- [ ] docs/quality/regression-risk-map.md:92:  DB mutation に到達しないことの runtime smoke 拡張が未完了。 Coverage: open。
- [ ] docs/quality/regression-risk-map.md:95:  しないことの source test が未着手。 Coverage: open。 Follow-up: P14-010。
- [ ] docs/quality/regression-risk-map.md:98:  未着手。 Coverage: open。 Follow-up: P14-011。

## Runtime / Visual / Manual Evidence

| Evidence | Status | Source commit |
| --- | --- | --- |
| `docs/release/evidence/ui-screenshots.md` | present | e3886c6 |
| `docs/release/evidence/mcp-inspector.md` | present | 881b693 |
| `docs/release/evidence/accessibility-voiceover.md` | passed | e488456 |
| `docs/release/evidence/competitor-hands-on.md` | pending | unknown |

## Verification Commands

- `swift test --filter AppExperienceSourceTests`
- `swift test --filter ReleasePipelineTests`
- `swift test --filter ProjectBoardStoreTests`
- `script/check_layout_stability_smoke.sh`
- `script/check_runtime_accessible_crud_smoke.sh`
- `script/check_accessibility_preflight.sh --runtime`
- `script/capture_ui_evidence.sh --doctor`
- `script/check_visual_regression_smoke.sh`
- `docs/quality/test-triage.md`
- `docs/quality/flake-quarantine.md`
- `SOLOPM_AUTOMATED_PREFLIGHT_EVIDENCE_FILE=.tmp/automated-release-preflight-0199644.md ./script/check_automated_release_preflight.sh`
- `SOLOPM_AUTOMATED_PREFLIGHT_EVIDENCE_FILE=.tmp/automated-release-preflight-0199644.md ./script/release_readiness_report.sh`

## Notes

- This dashboard is a quality triage aid, not release evidence.
- Manual VoiceOver, competitor hands-on, and release-machine evidence remain separate release gates.
- Secret-like values are redacted before writing this report.
