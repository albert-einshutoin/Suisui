# SoloPM Quality Status

Generated at: 2026-06-22T20:24:45Z
Source commit: ac59306

## Summary

- Phase14 completion: 64/183 checked, 119 remaining (`tasks/Phase14-QualityRegressionHardening.md`)
- Open risk items: 4 (`docs/quality/regression-risk-map.md`)
- Manual-only risk items: 3 (`docs/quality/regression-risk-map.md`)
- Automated preflight evidence: `missing .tmp/automated-release-preflight-ac59306.md`

## Unfinished Phase14 Items

- [ ] tasks/Phase14-QualityRegressionHardening.md:236:- [ ] smoke scriptが isolated `SOLOPM_DATABASE_PATH` を必須にしていることをsource testで固定する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:237:- [ ] 実行後のSQLite stateを確認し、UI操作だけ成功してDB未反映の場合に失敗するテストを追加する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:238:- [ ] click-pathごとに `PASS/FAIL/SKIP` ではなく、失敗理由と最後に見えたwindow情報を出すことをsource testで固定する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:242:- [ ] `project_task_crud`、`inbox_triage`、`today_complete`、`settings_save`、`voice_review` のscenarioに分ける。
- [ ] tasks/Phase14-QualityRegressionHardening.md:243:- [ ] 各scenarioはisolated DB seed -> app launch -> AX操作 -> DB/assertion -> artifact保存の順で実行する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:244:- [ ] destructive actionは必ずconfirmationを通ることを確認する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:245:- [ ] Settings保存ではKeychain secret値そのものをartifactへ出さない。
- [ ] tasks/Phase14-QualityRegressionHardening.md:246:- [ ] Voice CommandはAPI key未設定時にfake successへ倒れないことを確認する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:250:- [ ] Project / Task CRUDがUIから永続DBへ反映される。
- [ ] tasks/Phase14-QualityRegressionHardening.md:251:- [ ] Inbox item分類とUndoが実アプリで完走する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:252:- [ ] Today row completionがTask statusへ反映される。
- [ ] tasks/Phase14-QualityRegressionHardening.md:253:- [ ] Settings saveがUI stateとstore stateに反映される。
- [ ] tasks/Phase14-QualityRegressionHardening.md:254:- [ ] Voice Command review flowが承認前に止まり、audit logに残る。
- [ ] tasks/Phase14-QualityRegressionHardening.md:276:- [ ] UI layout correctionに `DispatchQueue.main.asyncAfter` やtimer retryを使う箇所が追加されたら失敗するsource testを追加する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:277:- [ ] layout-sensitive state mutationが `Transaction.disablesAnimations = true` または明示的な同期layout policyを持たない場合に検出するテストを追加する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:278:- [ ] AppKit bridgeが `layoutSubtreeIfNeeded` / `displayIfNeeded` の同期passを持つことを固定するテストを追加する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:282:- [ ] `docs/adr/NNNN-synchronous-ui-mutation-policy.md` を追加する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:283:- [ ] layout-sensitive operation一覧と禁止patternを定義する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:284:- [ ] SwiftUI state mutationは最小scopeのtransactionに閉じる。
- [ ] tasks/Phase14-QualityRegressionHardening.md:285:- [ ] AppKit interopは必要箇所だけに置き、View全体へ散らさない。
- [ ] tasks/Phase14-QualityRegressionHardening.md:286:- [ ] 遅延補正を使う場合はinitial attachmentなど例外理由をコメントとテストで固定する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:290:- [ ] 新しいUI PRが同期/非同期の判断基準を参照できる。
- [ ] tasks/Phase14-QualityRegressionHardening.md:291:- [ ] 遅延補正が便利な逃げ道として増えない。
- [ ] tasks/Phase14-QualityRegressionHardening.md:292:- [ ] Layout stability smokeとsource invariantが同じpolicyを守る。
- [ ] tasks/Phase14-QualityRegressionHardening.md:314:- [ ] 主要UI componentのmin/max frame指定が消えた場合に失敗するsource testを追加する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:315:- [ ] AX frameのoverlap検出をruntime smokeに追加する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:316:- [ ] 長い日本語/英語ラベル、空状態、エラー状態でbutton textがはみ出ないfixtureを追加する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:320:- [ ] `ProjectBoardLayoutMetrics` のような局所的metricsを作るか、既存DesignSystemへ追加する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:321:- [ ] magic numberを局所定数へ寄せ、なぜ固定するかコメントする。
- [ ] tasks/Phase14-QualityRegressionHardening.md:322:- [ ] ローカライズ文字列が長い場合はline limit、minimumScaleFactor、tooltip、label/hintのどれで処理するか決める。

## Open Risk Items

- [ ] docs/quality/regression-risk-map.md:92:  DB mutation に到達しないことの runtime smoke 拡張が未完了。 Coverage: open。
- [ ] docs/quality/regression-risk-map.md:95:  しないことの source test が未着手。 Coverage: open。 Follow-up: P14-010。
- [ ] docs/quality/regression-risk-map.md:98:  未着手。 Coverage: open。 Follow-up: P14-011。
- [ ] docs/quality/regression-risk-map.md:100:  `script/release_readiness_report.sh`) が未着手。 Coverage: open。

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
- `SOLOPM_AUTOMATED_PREFLIGHT_EVIDENCE_FILE=.tmp/automated-release-preflight-ac59306.md ./script/check_automated_release_preflight.sh`
- `SOLOPM_AUTOMATED_PREFLIGHT_EVIDENCE_FILE=.tmp/automated-release-preflight-ac59306.md ./script/release_readiness_report.sh`

## Notes

- This dashboard is a quality triage aid, not release evidence.
- Manual VoiceOver, competitor hands-on, and release-machine evidence remain separate release gates.
- Secret-like values are redacted before writing this report.
