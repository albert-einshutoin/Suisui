# SoloPM Quality Status

Generated at: 2026-06-22T16:00:09Z
Source commit: 69cdaf8

## Summary

- Phase14 completion: 11/181 checked, 170 remaining (`tasks/Phase14-QualityRegressionHardening.md`)
- Open risk items: 6 (`docs/quality/regression-risk-map.md`)
- Manual-only risk items: 3 (`docs/quality/regression-risk-map.md`)
- Automated preflight evidence: `.tmp/automated-release-preflight-69cdaf8.md`

## Unfinished Phase14 Items

- [ ] tasks/Phase14-QualityRegressionHardening.md:70:- [ ] `AppExperienceSourceTests` に `docs/quality/regression-risk-map.md` の存在と主要画面の記載を確認するテストを追加する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:71:- [ ] risk map に Project Board header / sidebar / detail / inspector のlayout stability項目がない場合に失敗するテストを追加する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:72:- [ ] risk map に unit / source / runtime / visual / manual の検証層が対応付いていない場合に失敗するテストを追加する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:76:- [ ] `docs/quality/regression-risk-map.md` を作る。
- [ ] tasks/Phase14-QualityRegressionHardening.md:77:- [ ] 画面別に「主要操作」「状態変更」「壊れるとユーザーに見える症状」「検証層」「owner test」を記録する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:78:- [ ] 既存の `AppExperienceSourceTests` / release scripts / smoke scripts をrisk mapへ対応付ける。
- [ ] tasks/Phase14-QualityRegressionHardening.md:79:- [ ] 残る未検証riskを P14-002 以降のタスクへリンクする。
- [ ] tasks/Phase14-QualityRegressionHardening.md:83:- [ ] 主要画面ごとのテストカバレッジの穴が1ファイルで分かる。
- [ ] tasks/Phase14-QualityRegressionHardening.md:84:- [ ] UI PRのレビュー時に、追加/変更した画面のrisk map更新漏れを検出できる。
- [ ] tasks/Phase14-QualityRegressionHardening.md:85:- [ ] release前の残riskが自動化不足なのか、manual-only gateなのか分類されている。
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
- `SOLOPM_AUTOMATED_PREFLIGHT_EVIDENCE_FILE=.tmp/automated-release-preflight-69cdaf8.md ./script/check_automated_release_preflight.sh`
- `SOLOPM_AUTOMATED_PREFLIGHT_EVIDENCE_FILE=.tmp/automated-release-preflight-69cdaf8.md ./script/release_readiness_report.sh`

## Notes

- This dashboard is a quality triage aid, not release evidence.
- Manual VoiceOver, competitor hands-on, and release-machine evidence remain separate release gates.
- Secret-like values are redacted before writing this report.
