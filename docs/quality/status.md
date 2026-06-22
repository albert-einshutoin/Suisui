# SoloPM Quality Status

Generated at: 2026-06-22T22:12:32Z
Source commit: 6953ae8

## Summary

- Phase14 completion: 100/183 checked, 83 remaining (`tasks/Phase14-QualityRegressionHardening.md`)
- Open risk items: 4 (`docs/quality/regression-risk-map.md`)
- Manual-only risk items: 3 (`docs/quality/regression-risk-map.md`)
- Automated preflight evidence: `missing .tmp/automated-release-preflight-6953ae8.md`

## Unfinished Phase14 Items

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
- [ ] tasks/Phase14-QualityRegressionHardening.md:396:- [ ] `check_accessibility_preflight.sh --runtime` の対象画面をInbox/Today/Settingsへ広げる。
- [ ] tasks/Phase14-QualityRegressionHardening.md:397:- [ ] UI component追加時のAX identifier命名規則を定義する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:398:- [ ] Manual VoiceOver worksheetとruntime AX smokeの項目を対応付ける。
- [ ] tasks/Phase14-QualityRegressionHardening.md:402:- [ ] Mouse、keyboard、VoiceOver前提のAX pathで主要CRUD入口が検出できる。
- [ ] tasks/Phase14-QualityRegressionHardening.md:404:- [ ] 手動VoiceOver前に明らかなlabel/focus漏れを自動検出できる。
- [ ] tasks/Phase14-QualityRegressionHardening.md:426:- [ ] 古いschemaから最新schemaへのmigration testを追加する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:427:- [ ] invalid JSON / blank string / unknown enum / dangling foreign keyをfail-closedまたはsafe fallbackするテストを追加する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:428:- [ ] UI ViewModelが破損recordを受け取ってもProject Board全体をUnavailableにしないテストを追加する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:432:- [ ] Migration fixture DBを `.tmp` ではなく test resource として最小化して持つ。
- [ ] tasks/Phase14-QualityRegressionHardening.md:433:- [ ] 破損データの扱いを「表示除外」「repair candidate」「blocking error」に分類する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:434:- [ ] Store layerでvalidationし、Viewでad hoc parseしない。
- [ ] tasks/Phase14-QualityRegressionHardening.md:435:- [ ] Repair可能なものはaudit logに残す。
- [ ] tasks/Phase14-QualityRegressionHardening.md:439:- [ ] 既存ユーザーDBのshape差分でアプリが起動不能になりにくい。
- [ ] tasks/Phase14-QualityRegressionHardening.md:440:- [ ] 破損recordがある場合も、原因と対象がユーザー/ログに安全に見える。
- [ ] tasks/Phase14-QualityRegressionHardening.md:441:- [ ] 秘密情報やraw DB contentをerror messageへ出さない。
- [ ] tasks/Phase14-QualityRegressionHardening.md:463:- [ ] secret-like patternがtest fixture、screenshot metadata、release evidenceに出たら失敗するscanを追加する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:464:- [ ] Runtime smoke artifact directoryが `.gitignore` 対象であることをテストする。
- [ ] tasks/Phase14-QualityRegressionHardening.md:465:- [ ] Keychain referenceとraw secretの区別をsource testで固定する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:469:- [ ] `script/check_security_regressions.sh` を作るか既存security grepへ統合する。

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
- `SOLOPM_AUTOMATED_PREFLIGHT_EVIDENCE_FILE=.tmp/automated-release-preflight-6953ae8.md ./script/check_automated_release_preflight.sh`
- `SOLOPM_AUTOMATED_PREFLIGHT_EVIDENCE_FILE=.tmp/automated-release-preflight-6953ae8.md ./script/release_readiness_report.sh`

## Notes

- This dashboard is a quality triage aid, not release evidence.
- Manual VoiceOver, competitor hands-on, and release-machine evidence remain separate release gates.
- Secret-like values are redacted before writing this report.
