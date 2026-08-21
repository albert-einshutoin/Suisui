# Cockpit layout breakpoints

正本は `Sources/SuisuiCore/App/CockpitLayoutPolicy.swift`。この文書は索引であり、数値の変更は
ポリシーと `CockpitLayoutPolicyTests` を先に更新する。

## 判定単位

Split / stack は **ウィンドウ幅ではなく detail content 幅** で決める。

```
contentWidth = windowWidth - sidebarMaxWidth(240)
```

サイドバー非表示時は content = window 全体。AppKit が公開する content 幅を
`\.cockpitAuthoritativeContentWidth` 経由で渡し、GeometryReader の under-report
で誤って stack しない。

## ウィンドウ梯子

| 段 | Window (pt) | Content (pt) | 二次レール |
| --- | ---: | ---: | --- |
| 既定起動 | ≥1180 | ≥940 | 横並び（Schedule rail は拡張可） |
| 製品 / visual 正本 | **1024×676** | **784** | 横並び必須 |
| Split 下限 | ≈970 | **≥730** | 横並び |
| サポート最小 | **960** | **720** | **下へ stack** |
| 閾値未満 | — | ≤729 | 下へ stack |

狭いときは全デスクで二次レールを **省略せず下へ移す**（到達性を維持）。

## レール幅

| デスク | 幅 | 挙動 |
| --- | --- | --- |
| Today / Projects / Done / Voice Quick Command | 240 | 固定 |
| Inbox | 280 | 固定 |
| Settings Overview / AI | 280 | 固定 |
| Voice Conversation Understanding | 330 | 固定 |
| Schedule | 240→320 | content が 730 を超えると `0.12` で拡張、上限 320 |

## 実装メモ

- Split 時は primary に `minWidth: 0`、secondary に `layoutPriority(1)`（`CockpitSplitLayout`）。
- AppKit の content 幅があるときはそれを layout 幅に使い、起動デスク（≈940）は 784 に潰さない。
  authority が無いときだけ ideal 膨張を `standardContentWidth` で cap する。
- Visual evidence 実行中は GeometryReader 幅に関わらず 1024 契約の split を強制する。
- ADR 0009 の frame jump / overlap ゲートと併用する。visual 正本は引き続き 1024×676。
