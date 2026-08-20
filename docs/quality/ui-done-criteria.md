# UI 完了条件

UI の完了は画面が表示されることではない。変更した user-visible contract に
対応する既存ゲートが通り、必要な人手確認が記録されて初めて完了とする。
source-only test、runtime、visual、手動確認は互いの代替ではない。
`./script/check_security_regressions.sh` が失敗した状態も完了扱いにしない。

## 変更別の必須証跡

| 変更範囲 | 必須の既存コマンドまたは証跡 | 完了条件 |
| --- | --- | --- |
| 通常導線、起動、CRUD、状態遷移 | `./script/build_and_run.sh --verify`、`./scripts/ci.sh ui-runtime` | exact PID の通常 route で対象操作と画面が通る。 |
| button、keyboard、focus、AX label / hint / identifier | `./script/check_accessibility_preflight.sh --source-only`、`./script/check_pseudo_voiceover_paths.sh --swift-test`、必要時 `./script/check_accessibility_preflight.sh --runtime` | source と runtime の両方で到達可能で、既存 focus path を壊さない。 |
| 文言、日付表示、locale 依存のレイアウト | `swift test --filter PublicBrandSurfaceTests`、必要時 `swift test --filter ProjectBoardMetadataLayoutSourceTests`、`./scripts/ci.sh ui-visual` | `en-US` と `ja-JP` の独立 capture が通り、片方の locale をもう片方の根拠にしない。 |
| 色、余白、階層、画面状態、theme | `./scripts/ci.sh ui-visual` | live AX frame audit と raster baseline が通る。baseline 更新は `docs/quality/visual-baselines.md` の意図的な update flow に従い、差分の製品理由をレビューできる形で残す。 |
| sidebar、toolbar、detail、inspector、window サイズ、表示モード | `./script/check_layout_stability_smoke.sh`、`./script/check_project_board_header_layout_smoke.sh`、または両方を完全実行する `SUISUI_CI_COMPLETE_RUNTIME=1 ./scripts/ci.sh ui-runtime` | overlap、clipping、frame jump を許容せず、ADR 0009 の同期 mutation 契約を守る。 |
| 起動、large board、検索、queue、同期など性能影響 | `./scripts/ci.sh ui-performance`、規模依存なら `./script/check_performance_stress_suite.sh` | `docs/quality/performance-budget.md` の既存 budget を超えない。budget を緩めて失敗を隠さない。 |
| release candidate の操作感、VoiceOver の読み上げ、keyboard traversal | 実機の手動 VoiceOver pass と `docs/release/evidence/accessibility-voiceover.md`。記録には `./script/create_voiceover_evidence.sh --passed ... --confirm-manual-voiceover-pass` を使う。 | 実際の reviewer が pass を確認する。自動出力、過去の証跡、または screenshot だけで手動確認済みにしない。 |

画面の追加・画面状態の大きな変更で release evidence を更新する場合は、先に
`./script/capture_ui_evidence.sh --doctor` を通し、完全 capture と baseline の
更新規約は `docs/quality/visual-baselines.md` に従う。通常の regression run は
baseline を書き換えない。

## fail-closed と完全検証

次のいずれかなら「該当なし」や狭い test selector で完了にしない。

- 変更影響を安全に説明できない、rename / delete / 共通 script / build / DB /
  security 境界を含む。
- selector が空、未知、不正、実行 0 件、または解析に失敗した。
- runtime AX marker、画面 selector、capture target、または required locale が
  取得できない。
- visual / VoiceOver の証跡が現在の source、locale、route、または release
  candidate に対して stale である。

完全検証は次を実行する。GUI / Accessibility capability がない環境で UI lane を
実行できない場合は、成功扱いにせず blocker として記録する。

```bash
./ci/run-all.sh
```

GitHub-hosted macOSの1024x676 UI laneは短縮証跡であり、wide layoutを含む完全検証の代替にはしない。

`docs/quality/selective-ci.md` の原則どおり、明示的な安全判定がある時だけ
selective validation を使う。失敗・手動レビューの所見は
`docs/quality/manual-to-automated-regression.md` に従い、次回を防ぐ source、
runtime、visual、または focused test へ接続してから閉じる。
