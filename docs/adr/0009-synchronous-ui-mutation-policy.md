# ADR 0009: Synchronous UI Mutation Policy

Date: 2026-06-23
Status: Accepted

## Context

Suisui の Project Board は SwiftUI の `NavigationSplitView`、AppKit `NSToolbar`、inspector、theme switching、project selection が同じ画面で同時に動く。状態変更の直後に SwiftUI state mutation、AppKit layout pass、animation、view update が別タイミングで走ると、最終状態は正しくても一瞬だけ header、sidebar、detail、inspector がずれる。

Phase 14 の layout stability smoke は `t=0ms` の即時サンプルも見るため、遅延補正で最終状態だけ合わせる実装はプロダクト品質として扱わない。UI PR で判断を迷わないように、同期扱いにする操作と、例外的に遅延してよい境界を ADR と source invariant で固定する。

## Decision

Layout-sensitive operation は、ユーザー操作と同じ同期境界で state / AppKit object mutation を完了させる。SwiftUI hosted view tree 全体の size fitting は重いため、同期境界では dirty mark に留める。

- Sidebar toggle は `Transaction.disablesAnimations = true` を設定した最小 scope の `withTransaction` に閉じる。
- toolbar display mode は AppKit 側で即時に正規化し、content view に dirty mark だけ付ける。ProjectBoardToolbarLayoutBridgeView does not call `layoutSubtreeIfNeeded` or `displayIfNeeded` because packaged app launch samples showed full Project Board size fitting can monopolize the main thread before the window is AX-visible.
- split view visibility は sidebar toggle と同じ transaction に含め、`DispatchQueue.main.asyncAfter` へ逃がさない。
- theme switching は Settings の state と persisted preference の更新に限定し、layout correction のための timer を置かない。
- inspector open/close は binding の同期更新として扱い、開閉直後の位置補正を遅延しない。
- project selection は detail source の切替として同期更新し、header / detail / inspector frame を runtime smoke で検証する。

禁止 pattern:

- UI layout correction のために `DispatchQueue.main.asyncAfter` を追加する。
- UI layout correction のために `Timer` retry を追加する。
- layout-sensitive state mutation を `withAnimation`、暗黙 animation、または animation が有効な広い transaction に含める。
- AppKit interop を View 全体へ散らし、どの bridge が layout pass を持つか分からない状態にする。

許容する例外:

- `layout-attachment-delay:` コメントがあり、initial AppKit toolbar attachment gap のように SwiftUI がまだ AppKit object を持っていない初期化境界に限る。
- 例外は bounded retry にし、user-triggered display-mode/sidebar changes mutate the toolbar synchronously without forcing a full view-tree layout であることをコメントと `AppExperienceSourceTests` で固定する。
- 例外は runtime smoke を緑にするための隠れ retry ではなく、AppKit object が存在しない期間だけを吸収する。

SwiftUI state mutationは最小scopeのtransactionに閉じる。AppKit interopはProjectBoardToolbarLayoutBridgeView のような局所 bridge に置き、View tree の通常 rendering と責務を混ぜない。

## Options Considered

### Ban Every Asynchronous UI Callback

- Pros: ルールが単純で、遅延補正が増えにくい。
- Cons: SwiftUI representable が AppKit toolbar をまだ受け取っていない初期 attachment gap まで表現できず、起動直後の legitimate retry も禁止してしまう。

### Allow Delayed Correction With Runtime Smoke

- Pros: 実装は速い。
- Cons: 最終状態だけ合う実装を許し、`t=0ms` の崩れを再発させる。PR review で同じ判断を繰り返す。

### Synchronous By Default With Marked Attachment Exceptions

- Pros: ユーザー操作直後の崩れを防ぎつつ、SwiftUI / AppKit の初期 attachment gap だけを明示的に扱える。source invariant と runtime smoke の責務が一致する。
- Cons: 例外コメントとテスト更新が必要で、UI bridge 変更時のレビュー負荷が少し上がる。

## Consequences

- Positive: 新しいUI PRが同期/非同期の判断基準を参照できる。
- Positive: 遅延補正が便利な逃げ道として増えない。
- Positive: Layout stability smokeとsource invariantが同じpolicyを守る。
- Negative: AppKit bridge を変更するPRでは、bounded attachment exception か同期 pass のどちらかを明示する必要がある。
- Follow-up: P14-007 以降の寸法/overlap guard でも、このADRを参照して magic delay ではなく frame rule と runtime evidence で検出する。

## Links

- Related task: tasks/Phase14-QualityRegressionHardening.md
- Related implementation: Sources/SuisuiApp/Views/ProjectBoardView.swift
- Related tests: Tests/SuisuiCoreTests/AppExperienceSourceTests.swift
- Related runtime smoke: script/check_layout_stability_smoke.sh
- Related runtime smoke: script/check_project_board_header_layout_smoke.sh
