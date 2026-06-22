# SoloPM Quality Status

Generated at: 2026-06-22T17:19:01Z
Source commit: c462aa2

## Summary

- Phase14 completion: 36/181 checked, 145 remaining (`tasks/Phase14-QualityRegressionHardening.md`)
- Open risk items: 5 (`docs/quality/regression-risk-map.md`)
- Manual-only risk items: 3 (`docs/quality/regression-risk-map.md`)
- Automated preflight evidence: `missing .tmp/automated-release-preflight-c462aa2.md`

## Unfinished Phase14 Items

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
- [ ] tasks/Phase14-QualityRegressionHardening.md:201:- [ ] screenshot manifestをJSONまたはMarkdown tableで定義する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:202:- [ ] capture scriptでwindow sizeとthemeを固定する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:203:- [ ] perceptual hashまたは簡易histogramで黒画面/低情報量を検出する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:204:- [ ] 重なり検出はAX frameと併用し、画像比較だけにしない。
- [ ] tasks/Phase14-QualityRegressionHardening.md:205:- [ ] baseline update時はPRにbefore/after artifactを添付する運用にする。
- [ ] tasks/Phase14-QualityRegressionHardening.md:209:- [ ] Light/Dark/Systemで主要画面のスクリーンショット証跡が取れる。
- [ ] tasks/Phase14-QualityRegressionHardening.md:210:- [ ] 画像が空、黒、極端に小さい、対象windowでない場合に失敗する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:211:- [ ] baseline更新が意図的なデザイン変更としてレビューできる。
- [ ] tasks/Phase14-QualityRegressionHardening.md:212:- [ ] macOS rendering差で不必要にフレークしない許容差が文書化されている。
- [ ] tasks/Phase14-QualityRegressionHardening.md:234:- [ ] smoke scriptが isolated `SOLOPM_DATABASE_PATH` を必須にしていることをsource testで固定する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:235:- [ ] 実行後のSQLite stateを確認し、UI操作だけ成功してDB未反映の場合に失敗するテストを追加する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:236:- [ ] click-pathごとに `PASS/FAIL/SKIP` ではなく、失敗理由と最後に見えたwindow情報を出すことをsource testで固定する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:240:- [ ] `project_task_crud`、`inbox_triage`、`today_complete`、`settings_save`、`voice_review` のscenarioに分ける。

## Open Risk Items

- [ ] docs/quality/regression-risk-map.md:95:  の拡張が未着手。 Coverage: open。 Follow-up: P14-004, P14-008。
- [ ] docs/quality/regression-risk-map.md:97:  DB mutation に到達しないことの runtime smoke 拡張が未完了。 Coverage: open。
- [ ] docs/quality/regression-risk-map.md:100:  しないことの source test が未着手。 Coverage: open。 Follow-up: P14-010。
- [ ] docs/quality/regression-risk-map.md:103:  未着手。 Coverage: open。 Follow-up: P14-011。
- [ ] docs/quality/regression-risk-map.md:105:  `script/release_readiness_report.sh`) が未着手。 Coverage: open。

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
- `script/check_layout_stability_smoke.sh`
- `script/check_runtime_accessible_crud_smoke.sh`
- `script/check_accessibility_preflight.sh --runtime`
- `script/capture_ui_evidence.sh --doctor`
- `SOLOPM_AUTOMATED_PREFLIGHT_EVIDENCE_FILE=.tmp/automated-release-preflight-c462aa2.md ./script/check_automated_release_preflight.sh`
- `SOLOPM_AUTOMATED_PREFLIGHT_EVIDENCE_FILE=.tmp/automated-release-preflight-c462aa2.md ./script/release_readiness_report.sh`

## Notes

- This dashboard is a quality triage aid, not release evidence.
- Manual VoiceOver, competitor hands-on, and release-machine evidence remain separate release gates.
- Secret-like values are redacted before writing this report.
