# SoloPM Quality Status

Generated at: 2026-06-22T21:48:09Z
Source commit: 07e7ec2

## Summary

- Phase14 completion: 87/183 checked, 96 remaining (`tasks/Phase14-QualityRegressionHardening.md`)
- Open risk items: 4 (`docs/quality/regression-risk-map.md`)
- Manual-only risk items: 3 (`docs/quality/regression-risk-map.md`)
- Automated preflight evidence: `missing .tmp/automated-release-preflight-07e7ec2.md`

## Unfinished Phase14 Items

- [ ] tasks/Phase14-QualityRegressionHardening.md:244:- [ ] destructive actionは必ずconfirmationを通ることを確認する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:314:- [ ] 主要UI componentのmin/max frame指定が消えた場合に失敗するsource testを追加する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:315:- [ ] AX frameのoverlap検出をruntime smokeに追加する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:316:- [ ] 長い日本語/英語ラベル、空状態、エラー状態でbutton textがはみ出ないfixtureを追加する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:320:- [ ] `ProjectBoardLayoutMetrics` のような局所的metricsを作るか、既存DesignSystemへ追加する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:321:- [ ] magic numberを局所定数へ寄せ、なぜ固定するかコメントする。
- [ ] tasks/Phase14-QualityRegressionHardening.md:322:- [ ] ローカライズ文字列が長い場合はline limit、minimumScaleFactor、tooltip、label/hintのどれで処理するか決める。
- [ ] tasks/Phase14-QualityRegressionHardening.md:323:- [ ] Runtime smokeで主要AX frameのoverlapとnegative sizeを検出する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:327:- [ ] Header、sidebar、detail、inspector、cardsの寸法ルールがコードとテストで固定されている。
- [ ] tasks/Phase14-QualityRegressionHardening.md:328:- [ ] 長いラベルやempty/error stateでUIが重ならない。
- [ ] tasks/Phase14-QualityRegressionHardening.md:329:- [ ] Magic numberの追加がレビューで見つけやすい。
- [ ] tasks/Phase14-QualityRegressionHardening.md:351:- [ ] LaunchExperienceTestsに「保存状態がwindow-lessでもProject Boardが見える」ことを維持するテストを追加または確認する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:353:- [ ] 前回選択Projectが削除済みの場合にsafe fallbackするテストを追加する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:358:- [ ] selected destinationをseed DBとenvで制御する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:359:- [ ] 削除済みselection、空DB、大量project、大量taskのfixtureを作る。
- [ ] tasks/Phase14-QualityRegressionHardening.md:360:- [ ] multi-windowが未対応の場合は、開けない/開いても独立stateになる境界をsource testで固定する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:364:- [ ] 空DB、通常DB、大量DBでProject Boardが起動する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:365:- [ ] 最小幅/標準幅/広幅でheaderとdetailが重ならない。
- [ ] tasks/Phase14-QualityRegressionHardening.md:366:- [ ] 保存済みselectionが壊れていても起動不能にならない。
- [ ] tasks/Phase14-QualityRegressionHardening.md:367:- [ ] 起動直後にwindowが見えない退行を検出できる。
- [ ] tasks/Phase14-QualityRegressionHardening.md:389:- [ ] 主要buttonがAX labelまたはhelpを失ったら失敗するruntime smokeを追加する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:390:- [ ] Keyboard shortcutがmenu commandまたはfocused actionに接続されていることをsource testで固定する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:391:- [ ] destructive confirmationが確認なしに実行できないことをruntime smokeで確認する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:396:- [ ] `check_accessibility_preflight.sh --runtime` の対象画面をInbox/Today/Settingsへ広げる。
- [ ] tasks/Phase14-QualityRegressionHardening.md:397:- [ ] UI component追加時のAX identifier命名規則を定義する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:398:- [ ] Manual VoiceOver worksheetとruntime AX smokeの項目を対応付ける。
- [ ] tasks/Phase14-QualityRegressionHardening.md:402:- [ ] Mouse、keyboard、VoiceOver前提のAX pathで主要CRUD入口が検出できる。
- [ ] tasks/Phase14-QualityRegressionHardening.md:403:- [ ] destructive actionはconfirmationを経由しないとDB mutationしない。
- [ ] tasks/Phase14-QualityRegressionHardening.md:404:- [ ] 手動VoiceOver前に明らかなlabel/focus漏れを自動検出できる。
- [ ] tasks/Phase14-QualityRegressionHardening.md:426:- [ ] 古いschemaから最新schemaへのmigration testを追加する。

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
- `SOLOPM_AUTOMATED_PREFLIGHT_EVIDENCE_FILE=.tmp/automated-release-preflight-07e7ec2.md ./script/check_automated_release_preflight.sh`
- `SOLOPM_AUTOMATED_PREFLIGHT_EVIDENCE_FILE=.tmp/automated-release-preflight-07e7ec2.md ./script/release_readiness_report.sh`

## Notes

- This dashboard is a quality triage aid, not release evidence.
- Manual VoiceOver, competitor hands-on, and release-machine evidence remain separate release gates.
- Secret-like values are redacted before writing this report.
