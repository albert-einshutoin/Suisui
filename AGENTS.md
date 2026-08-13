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

## モデルとレビューの割り当て

| 役割 | モデル・reasoning | 担当 |
| --- | --- | --- |
| Sol | xhigh / max | 設計、難バグ、セキュリティ、DB、最終レビュー |
| Terra | high / xhigh | 通常実装、リファクタリング |
| Luna | high / max | 探索、定型修正、テスト、docs、並列調査 |

依頼されたモデルまたは reasoning が利用不能なら、黙って別モデル・別強度へ
代替しない。利用不能な役割、止まる作業、利用可能な選択肢を依頼者へ報告し、
明示的な指示を待つ。並列作業はファイル所有範囲を分け、各担当は他者の変更を
revert せず、実行した検証を返す。

## 完了と GitHub Flow

- 小さくレビュー可能なコミットにし、PR には変更理由、変更前後の振る舞い、
  検証結果、残る制約を記載する。
- PR 完了はローカル成功だけではない。要求された hosted CI、未解決 review、
  merge、配布確認まで live に確認する。
- merge 後に不要になった作業ブランチは、他者の利用を確認してから local と
  remote の両方を整理する。削除は明示的な対象確認後に行う。
