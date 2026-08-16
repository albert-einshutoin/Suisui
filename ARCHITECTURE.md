# Suisui Architecture Index

このファイルは Codex 開発時の索引である。新しいアーキテクチャ規約を作らず、
詳細な判断はリンク先を正本として扱う。

## 境界

依存方向は `UI/platform surfaces -> domain view models/snapshots -> domain
services/ports -> infrastructure adapters`。UI は SQLite、Keychain、OAuth、
ネットワーク、EventKit の具体実装を直接所有せず、実行を伴う操作は review
before execution を維持する。例外と現行の所有範囲は
[`docs/architecture/domain-boundaries.md`](docs/architecture/domain-boundaries.md)
を参照する。

## 変更の入口

| 変更 | 先に確認する正本 | 最低限の裏付け |
| --- | --- | --- |
| SwiftUI、AppKit、導線、AX | `docs/adr/0009-synchronous-ui-mutation-policy.md`、`docs/quality/ui-done-criteria.md` | 該当する UI done gate |
| 永続化・main thread・SQLite | `docs/architecture/main-thread-database-plan.md`、ADR 0012 | 関連テストと security gate |
| 外部接続、同期、provider | `docs/architecture/suisui-paid-platform-assessment.md`、`docs/release/privacy-security.md` | approval / credential 境界のテスト |
| 既存判断の変更 | `docs/adr/` | ADR を更新または追加して理由を残す |

## 品質の入口

- 実装・全 SwiftPM: `./scripts/ci.sh swiftpm`
- 影響が不明なときの完全検証: `./ci/run-all.sh`
- runtime: `./scripts/ci.sh ui-runtime`
- visual / bilingual localization: `./scripts/ci.sh ui-visual`
- performance: `./scripts/ci.sh ui-performance`
- 詳細な選択基準と証跡の鮮度: `docs/quality/ui-done-criteria.md`

この索引は各機能の設計書を置き換えない。設計変更は、最も近い architecture
document または ADR を更新するまで完了としない。
