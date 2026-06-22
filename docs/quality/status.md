# SoloPM Quality Status

Generated at: 2026-06-22T23:01:02Z
Source commit: 12c18db

## Summary

- Phase14 completion: 113/183 checked, 70 remaining (`tasks/Phase14-QualityRegressionHardening.md`)
- Open risk items: 4 (`docs/quality/regression-risk-map.md`)
- Manual-only risk items: 3 (`docs/quality/regression-risk-map.md`)
- Automated preflight evidence: `missing .tmp/automated-release-preflight-12c18db.md`

## Unfinished Phase14 Items

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
- `SOLOPM_AUTOMATED_PREFLIGHT_EVIDENCE_FILE=.tmp/automated-release-preflight-12c18db.md ./script/check_automated_release_preflight.sh`
- `SOLOPM_AUTOMATED_PREFLIGHT_EVIDENCE_FILE=.tmp/automated-release-preflight-12c18db.md ./script/release_readiness_report.sh`

## Notes

- This dashboard is a quality triage aid, not release evidence.
- Manual VoiceOver, competitor hands-on, and release-machine evidence remain separate release gates.
- Secret-like values are redacted before writing this report.
