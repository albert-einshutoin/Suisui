# SoloPM Quality Status

Generated at: 2026-06-22T23:14:57Z
Source commit: db8c079

## Summary

- Phase14 completion: 125/183 checked, 58 remaining (`tasks/Phase14-QualityRegressionHardening.md`)
- Open risk items: 4 (`docs/quality/regression-risk-map.md`)
- Manual-only risk items: 3 (`docs/quality/regression-risk-map.md`)
- Automated preflight evidence: `missing .tmp/automated-release-preflight-db8c079.md`

## Unfinished Phase14 Items

- [ ] tasks/Phase14-QualityRegressionHardening.md:435:- [ ] Repair可能なものはaudit logに残す。
- [ ] tasks/Phase14-QualityRegressionHardening.md:463:- [ ] secret-like patternがtest fixture、screenshot metadata、release evidenceに出たら失敗するscanを追加する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:464:- [ ] Runtime smoke artifact directoryが `.gitignore` 対象であることをテストする。
- [ ] tasks/Phase14-QualityRegressionHardening.md:465:- [ ] Keychain referenceとraw secretの区別をsource testで固定する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:469:- [ ] `script/check_security_regressions.sh` を作るか既存security grepへ統合する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:470:- [ ] `sk-`, OAuth token風文字列、notary password、MCP token、filesystem pathの扱いを分類する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:471:- [ ] Smoke scriptsはartifactにredaction済みsummaryだけを書く。
- [ ] tasks/Phase14-QualityRegressionHardening.md:472:- [ ] Screenshotは必要最小限にし、secret入力画面を撮る場合はmask状態を検証する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:476:- [ ] テスト追加が秘密情報漏洩riskを増やさない。
- [ ] tasks/Phase14-QualityRegressionHardening.md:477:- [ ] Runtime smoke artifactはtracked sourceへ混ざらない。
- [ ] tasks/Phase14-QualityRegressionHardening.md:478:- [ ] 失敗ログにAPI key/provider token/OAuth token/MCP secretが出ない。
- [ ] tasks/Phase14-QualityRegressionHardening.md:500:- [ ] `scripts/ci.sh` が軽量PR gateと重いruntime gateを混同しないことをsource testで固定する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:501:- [ ] `release_readiness_report.sh` がlayout stability smokeの結果を取り込めることをテストする。
- [ ] tasks/Phase14-QualityRegressionHardening.md:502:- [ ] Flake quarantine listが空でない場合、owner/reason/expiryが必要なことをテストする。
- [ ] tasks/Phase14-QualityRegressionHardening.md:506:- [ ] `docs/quality/test-triage.md` にfailure categoryを書く。
- [ ] tasks/Phase14-QualityRegressionHardening.md:507:- [ ] `docs/quality/flake-quarantine.md` を作り、期限付きでしかskipできない運用にする。
- [ ] tasks/Phase14-QualityRegressionHardening.md:508:- [ ] `scripts/ci.sh` はunit/sourceを必須、runtime/visualは明示フラグで実行する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:509:- [ ] `release_readiness_report.sh` はruntime/visual/manual evidenceを集約する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:510:- [ ] 失敗時は最小再現コマンドをaction summaryに出す。
- [ ] tasks/Phase14-QualityRegressionHardening.md:514:- [ ] PRでは速いテストで明確に落ちる。
- [ ] tasks/Phase14-QualityRegressionHardening.md:515:- [ ] UI/release前にはruntime/visual gateが実行できる。
- [ ] tasks/Phase14-QualityRegressionHardening.md:516:- [ ] フレークを無期限skipできない。
- [ ] tasks/Phase14-QualityRegressionHardening.md:517:- [ ] 失敗分類がbuild / assertion / crash / timing / environment / manual gateに分かれる。
- [ ] tasks/Phase14-QualityRegressionHardening.md:539:- [ ] Manual evidenceにfailure noteがある場合、linked regression testまたはfollow-up issueが必要なことをreportで検出する。
- [ ] tasks/Phase14-QualityRegressionHardening.md:545:- [ ] VoiceOverで見つかったlabel/focus問題はAX/source testへ戻す。
- [ ] tasks/Phase14-QualityRegressionHardening.md:546:- [ ] Gatekeeper/clean environmentで見つかった起動問題はpackaging/preflight testへ戻す。
- [ ] tasks/Phase14-QualityRegressionHardening.md:547:- [ ] Competitor hands-onで見つかったUX差分はPhase taskまたはproduct docへ戻す。
- [ ] tasks/Phase14-QualityRegressionHardening.md:552:- [ ] 手動確認で見つかった問題が、次回以降の自動検出対象になる。
- [ ] tasks/Phase14-QualityRegressionHardening.md:553:- [ ] manual-only gateとautomation-backlogが混ざらない。
- [ ] tasks/Phase14-QualityRegressionHardening.md:554:- [ ] release前に未処理manual findingが見える。

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
- `SOLOPM_AUTOMATED_PREFLIGHT_EVIDENCE_FILE=.tmp/automated-release-preflight-db8c079.md ./script/check_automated_release_preflight.sh`
- `SOLOPM_AUTOMATED_PREFLIGHT_EVIDENCE_FILE=.tmp/automated-release-preflight-db8c079.md ./script/release_readiness_report.sh`

## Notes

- This dashboard is a quality triage aid, not release evidence.
- Manual VoiceOver, competitor hands-on, and release-machine evidence remain separate release gates.
- Secret-like values are redacted before writing this report.
