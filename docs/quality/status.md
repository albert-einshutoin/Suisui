# SoloPM Quality Status

Generated at: 2026-06-22T16:12:20Z
Source commit: 8cc20f9

## Summary

- Phase14 completion: 21/181 checked, 160 remaining (`tasks/Phase14-QualityRegressionHardening.md`)
- Open risk items: 6 (`docs/quality/regression-risk-map.md`)
- Manual-only risk items: 3 (`docs/quality/regression-risk-map.md`)
- Automated preflight evidence: `.tmp/automated-release-preflight-8cc20f9.md`

## Unfinished Phase14 Items

- [ ] tasks/Phase14-QualityRegressionHardening.md:108:- [ ] `ReleasePipelineTests` にlayout stability scriptの存在、`t=0`即時サンプル、複数サンプル、frame delta thresholdをsource-levelで確認するテストを追加する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:109:- [ ] scriptが対象AX identifier不足をskipではなく失敗扱いにするテストを追加する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:110:- [ ] scriptが差分artifactを `.tmp/layout-stability/` に保存することを確認するテストを追加する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:114:- [ ] AX frame取得処理を reusable shell / AppleScript helper に分離する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:115:- [ ] `project-board-header-bar`, `project-board-detail`, `project-board-sidebar`, `project-board-inspector` を必須identifierにする。
- [ ] tasks/Phase14-QualityRegressionHardening.md:116:- [ ] クリック操作直後にframeを採取し、後続sampleと比較する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:117:- [ ] thresholdは基本 `0px`、OS差が出る箇所だけ `1px` tolerance を明示する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:118:- [ ] 失敗時は before / immediate / after のJSONとPNGを保存する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:119:- [ ] scriptの終了メッセージに、検証した遷移名と最大deltaを出す。
- [ ] tasks/Phase14-QualityRegressionHardening.md:123:- [ ] Sidebar toggle直後のheader / detail / inspector frame deltaを検出できる。
- [ ] tasks/Phase14-QualityRegressionHardening.md:124:- [ ] Toolbar display mode切替直後のheader action frame deltaを検出できる。
- [ ] tasks/Phase14-QualityRegressionHardening.md:125:- [ ] Window resize直後のoverlap / clipping / frame jumpを検出できる。
- [ ] tasks/Phase14-QualityRegressionHardening.md:126:- [ ] 失敗時にPR reviewerが再現コマンドとartifact pathを見て判断できる。
- [ ] tasks/Phase14-QualityRegressionHardening.md:148:- [ ] Header actionsがnative primary toolbar itemに戻ったら失敗するsource testを追加する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:149:- [ ] Sidebar toggleがanimation有効transactionへ戻ったら失敗するsource testを追加する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:150:- [ ] Header action groupが固定height / trailing alignment / stable AX identifierを失ったら失敗するsource testを追加する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:151:- [ ] Runtime smokeに以下の遷移を追加する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:161:- [ ] Project Boardの主要領域にAX identifierを追加または確認する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:162:- [ ] smoke scriptの操作を小さな関数に分け、各遷移後に `assert_layout_stable` を呼ぶ。
- [ ] tasks/Phase14-QualityRegressionHardening.md:163:- [ ] Header actionsがdetail column右端に収まることを、window右端ではなくdetail frame基準で判定する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:164:- [ ] Inspector表示時にheaderがinspector下へ潜らないことを確認する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:165:- [ ] Board/List/Overviewの切替でheader heightとtop offsetが変わらないことを確認する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:169:- [ ] Project Boardの主要状態遷移でheader / sidebar / detail / inspectorのframe jumpが検出される。
- [ ] tasks/Phase14-QualityRegressionHardening.md:170:- [ ] Header action controlsが常に同じ順序とAX identifierで取得できる。
- [ ] tasks/Phase14-QualityRegressionHardening.md:171:- [ ] Runtime smokeで失敗した時、どの遷移でどのframeがズレたか出力される。
- [ ] tasks/Phase14-QualityRegressionHardening.md:172:- [ ] Project Board UI変更PRはこのsuiteをfocused verifierとして使える。
- [ ] tasks/Phase14-QualityRegressionHardening.md:194:- [ ] `ReleasePipelineTests` にvisual baseline manifestの存在と対象画面リストを確認するテストを追加する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:195:- [ ] 画像が小さすぎる、黒画面、低情報量の場合にscriptが失敗するsource testを追加する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:196:- [ ] baseline更新には明示フラグが必要で、通常実行では上書きしないことをテストする。
- [ ] tasks/Phase14-QualityRegressionHardening.md:200:- [ ] `docs/quality/visual-baselines.md` に対象画面、viewport、theme、許容差、更新手順を書く。

## Open Risk Items

- [ ] docs/quality/regression-risk-map.md:93:  Coverage: open。 Follow-up: P14-008。
- [ ] docs/quality/regression-risk-map.md:98:  の拡張が未着手。 Coverage: open。 Follow-up: P14-004, P14-008。
- [ ] docs/quality/regression-risk-map.md:100:  DB mutation に到達しないことの runtime smoke 拡張が未完了。 Coverage: open。
- [ ] docs/quality/regression-risk-map.md:103:  しないことの source test が未着手。 Coverage: open。 Follow-up: P14-010。
- [ ] docs/quality/regression-risk-map.md:106:  未着手。 Coverage: open。 Follow-up: P14-011。
- [ ] docs/quality/regression-risk-map.md:108:  `script/release_readiness_report.sh`) が未着手。 Coverage: open。

## Runtime / Visual / Manual Evidence

| Evidence | Status | Source commit |
| --- | --- | --- |
| `docs/release/evidence/ui-screenshots.md` | present | db09ce0 |
| `docs/release/evidence/mcp-inspector.md` | present | 881b693 |
| `docs/release/evidence/accessibility-voiceover.md` | passed | e488456 |
| `docs/release/evidence/competitor-hands-on.md` | pending | unknown |

## Verification Commands

- `swift test --filter AppExperienceSourceTests`
- `swift test --filter ReleasePipelineTests`
- `swift test --filter ProjectBoardStoreTests`
- `script/check_runtime_accessible_crud_smoke.sh`
- `script/check_accessibility_preflight.sh --runtime`
- `script/capture_ui_evidence.sh --doctor`
- `SOLOPM_AUTOMATED_PREFLIGHT_EVIDENCE_FILE=.tmp/automated-release-preflight-8cc20f9.md ./script/check_automated_release_preflight.sh`
- `SOLOPM_AUTOMATED_PREFLIGHT_EVIDENCE_FILE=.tmp/automated-release-preflight-8cc20f9.md ./script/release_readiness_report.sh`

## Notes

- This dashboard is a quality triage aid, not release evidence.
- Manual VoiceOver, competitor hands-on, and release-machine evidence remain separate release gates.
- Secret-like values are redacted before writing this report.
