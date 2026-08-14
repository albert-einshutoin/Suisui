# Suisui の Codex 開発入口

このファイルはリポジトリ固有の作業入口であり、検証フレームワークの
複製ではない。実装前に変更範囲を確認し、既存の契約とコマンドを使う。

## 最初に読むもの

| 判断したいこと | 正本 |
| --- | --- |
| レイヤー境界・依存方向 | `ARCHITECTURE.md`、`docs/architecture/domain-boundaries.md` |
| 既存の設計判断 | `docs/adr/` |
| UI の完了条件 | `docs/quality/ui-done-criteria.md` |
| AX・Visual の詳細契約 | `docs/quality/accessibility-focus-paths.md`、`docs/quality/visual-baselines.md` |
| 影響分析と全件フォールバック | `docs/quality/selective-ci.md` |
| セキュリティ境界 | `docs/release/privacy-security.md`、`./script/check_security_regressions.sh` |

## 実装と検証

- Ponytail の最小実装を守る。既存の型、テスト、script、証跡を再利用し、
  要求されない抽象化・依存・別の quality runner を追加しない。
- TDD では、変更に最も近い失敗するテストまたは再現を先に置き、修正後に
  そのテストを実行する。影響を安全に限定できない場合は全件へ拡張する。
- 基本ゲートは `./scripts/ci.sh swiftpm`、`./script/build_and_run.sh --verify`、
  `./script/check_security_regressions.sh`。UI は
  `docs/quality/ui-done-criteria.md` の該当レーンを追加する。
- UI、永続化、権限、外部実行、秘密情報の変更は、境界をまたぐ前に
  `docs/architecture/domain-boundaries.md` を確認する。秘密値をログ、fixture、
  screenshot、コミットへ入れない。
- 意図、制約、または効率上の理由がコードだけから分からない business logic
  には、理由と安全上の境界を短いコメントで残す。
- 他者の未コミット変更や `outputs/` を revert・削除しない。担当外の差分は
  保持し、変更ファイルと実行コマンドを報告する。

## CI コマンド契約

| 目的 | コマンド |
| --- | --- |
| 完全検証（`ci`） | `./ci/run-all.sh` |
| 非 UI の完全検証 | `./ci/run-full.sh` |
| PR の変更影響検証（`ci-pr`） | `./ci/run-pr-ci.sh --base-revision origin/main --head-revision HEAD` |
| 計画確認（`ci-plan`） | `python3 ci/impact/analyze.py --repo . --base-revision origin/main --head-revision HEAD --config ci/config/impact.json --output .tmp/ci-impact/test-plan.json` |
| impact planner の検証 | `python3 -m unittest discover -s ci/tests -v` |
| Actions ローカル確認（`ci-act`） | 非対応。macOS hosted runner 固有のため GitHub Actions を正とする |
| セキュリティ | `./script/check_security_regressions.sh` |
| UI・AX | `docs/quality/ui-done-criteria.md` の該当レーン |

- `ci` は常に完全検証とし、変更範囲へ限定するのは `ci-pr` だけにする。
- `ci-pr` は判定失敗、未知パス、対象 0 件、delete、旧新 path を安全に解析
  できない rename/copy、CI・依存・build、security、DB・schema、public API・
  共有基盤の変更を完全検証へ昇格する。
- 完全検証 runner は impact planner とその設定に依存させない。選択テストの
  失敗はそのまま失敗とし、完全検証の成功で上書きしない。
- `act` は Linux 互換 workflow のローカル確認に限る。macOS runner、署名、
  notarization、Keychain、secret を含む完了判定は hosted CI を正とする。
