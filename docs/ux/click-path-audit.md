# SoloPM クリック導線監査

作成日: 2026-06-19

対象: 現在の SwiftUI 実装である `SoloPMApp.swift` と `ProjectBoardView.swift` の主要操作。

## 目標

| 操作 | 目標 |
| --- | --- |
| Task作成 | 目的の画面が見えてから2クリック以内 |
| Taskステータス変更 | 1回のドラッグ、またはカード上の1ボタン |
| Project作成 | 2クリック以内 |
| Provider設定 | Settingsを開いてから2クリック以内 |
| MCP接続確認 | Settingsを開いてから2クリック以内 |
| Sync状態確認 | Settingsを開いてから1クリック以内 |

クリック数はマウスクリックだけを数える。入力、ドラッグ距離、スクロール距離は別の操作負荷として記録する。

## 現在の導線

| 画面 | 入口 | 現状 |
| --- | --- | --- |
| Project Board | 起動時のメインwindow、menu barの `Project Board`、board toolbar | Project、board/list、task composer、inspector、Settings入口がある主要画面。 |
| Voice Command | board toolbarの `Voice Command`、menu barの `Voice Command` | CaptureとAI action reviewの導線がある。現状ではInboxの代替に近い。 |
| Settings | board toolbarのgear、menu barのgear、macOS Settings scene | 先頭のStatus OverviewでAI Provider、MCP、Sync、Privacyを確認できる。詳細設定は下のFormに並ぶ。 |
| Inbox | なし | 独立画面はない。Voice Commandでcaptureはできるが、triage queueはない。 |
| Today | menu bar summaryのみ | Todayの要約はあるが、今日やるTask一覧として操作できる画面はない。 |

## クリック数

| 操作 | 導線 | クリック数 | 判定 | メモ |
| --- | --- | ---: | --- | --- |
| menu barからProject Boardを開く | menu bar icon -> `Project Board` | 2 | Pass | 通常起動ではProject Boardが最初に出るため、起動後は0クリック。 |
| Project作成 | sidebarの `Add Project` | 1 | Pass | 速い。作成直後にtitle編集が明確である状態は維持したい。 |
| Project選択 | sidebar project row | 1 | Pass | ネイティブsidebar listで繰り返し操作に向いている。 |
| 選択中ProjectにTask作成 | headerの `Add Task` -> 入力 -> `Add` | 2 | Pass | 目標達成。columnの `+` と空columnの追加導線も2クリック。 |
| 別ProjectにTask作成 | sidebar project -> `Add Task` -> 入力 -> `Add` | 3 | Watch | 目的地変更があるため許容。ただしInbox capture用途では重い。 |
| Taskを隣のstatusへ移動 | cardのchevron left/right | 1 | Pass | 目標達成。ドラッグしないユーザーにも分かりやすい。 |
| Taskを任意のstatusへ移動 | cardを対象columnへドラッグ | 1 drag | Pass | drag affordanceとdrop target表示がある。 |
| context menuでTask移動 | card右クリック -> `Move To` -> status | 3 | Watch | 補助導線としては有効だが主導線ではない。 |
| Task詳細編集 | card選択 -> inspector編集 -> `Save Changes` | 2 | Pass | 選択後にinspectorが出るため発見可能。 |
| Task削除 | card選択 -> `Delete Task` -> confirm | 3 | Pass | 破壊的操作なので確認があるのは妥当。 |
| Project完了 | `Complete Project` | 1 | Pass | headerに見えている。 |
| Project archive/delete | header action -> confirm | 2 | Pass | 破壊的操作なので確認があるのは妥当。 |
| boardからSettingsを開く | toolbar gear | 1 | Pass | menu barからも2クリックで開ける。 |
| Theme変更 | Settings -> `Theme` segment | 2 | Pass | ThemeはSettingsに集約済み。 |
| AI Provider状態確認 | Settings -> Status Overviewを見る | 1 | Pass | 現在のproviderと認証/承認状態は先頭で分かる。 |
| AI Provider変更 | Settings -> provider picker -> provider | 2 | Pass | Provider選択時に自動保存されるため、保存ボタンを探す必要がない。追加設定が必要なproviderは既存validationで理由を出す。 |
| Provider API key保存 | Settings -> API key field -> save key | 3 | Watch | 初期設定としては許容だが、provider別の状態表示が密すぎる。 |
| OpenCode Local設定 | Settings -> executable/workspace/model入力 -> approval toggle -> save | 5+ | Watch | 複数fieldが必要な設定だが、validation状態はもっと明確に出すべき。 |
| 選択中MCP serverの接続確認 | Settings -> `Check Connection` | 2 | Pass | すでに対象serverが選ばれていれば目標達成。 |
| 別MCP serverの接続確認 | Settings -> server picker -> server -> `Check Connection` | 4 | Watch | server選択と接続状態をよりコンパクトにしたい。 |
| Sync状態確認 | Settings -> Status Overviewを見る | 1 | Pass | Planと状態がSettings先頭で分かる。詳細な対象dataはSync sectionに残る。 |
| Free userでSync開始 | Settings -> `External Sync` toggle | 2 | Pass | network前にupgrade gateで止まる。 |
| text commandからplan生成 | Voice Command -> 入力 -> `Generate Plan` | 2 | Pass | 生成後にreview panelが同じ画面へ出る。 |
| 録音からplan生成 | Voice Command -> `Record` -> `Stop` -> `Generate Plan` | 4 | Watch | 音声captureとしては自然だが、Inbox代替としては重い。 |
| Review実行 | `Approve` -> `Execute` | 2 | Pass | write actionは承認必須。approval不要なら1クリックで実行できる。 |

## ギャップ

| ギャップ | ユーザー影響 | 優先度 | 必要な修正 |
| --- | --- | --- | --- |
| Inbox画面がない | 思いつきや音声入力の行き先が見えず、capture後に信頼を失いやすい。 | P0 | Inboxをfirst-class navigationにし、Task / Project / Schedule / Laterへ1クリックで分類できるようにする。 |
| Today作業画面がない | menu bar summaryは存在を知らせるだけで、今日の作業を進められない。 | P0 | Today viewを追加し、今日のTask、overdue、次のactionを表示する。 |
| Settings詳細Formが長い | Status Overviewで重要状態は見えるが、詳細設定はまだ縦に長い。 | P1 | General / AI / Sync / MCP / Privacy のtabまたは2カラムdetailsに分ける。 |
| Provider詳細設定が長い | provider切替は2クリックになったが、API key、model、local executableなどの詳細設定は同じAI section内に縦積みで残る。 | P1 | providerごとに必要なfieldだけをcompact panelへ出し、他providerのfieldは折りたたむ。 |
| MCP server切替時の接続確認が重い | 複数serverを持つユーザーが状態確認しづらい。 | P1 | MCP server listにinline statusとrow単位のcheck actionを置く。 |
| accessibility検証が未完了 | `Command+N`、`Command+Shift+N`、`Command+,` はあるが、VoiceOver focus orderとLight/Darkのスクリーンショット確認が残る。 | P1 | 支援技術とテーマ別コントラストを実機で確認し、崩れを修正する。 |

## プロダクトレビュー

Problem: SoloPMは実働するboardとlocal dataを持ったが、まだ日々のPM cockpitではなく「project board + settings panel」に近い。

User pull: 現時点で最も強い導線はProject単位のTask CRUD。弱い導線はcapture-to-triageで、InboxとTodayが見える行き先になっていない。

Retention hook: Todayを日次のdefault surfaceにする必要がある。今のままだとユーザーは毎回Projectを手動で探す必要がある。

Monetization: Syncとadvanced MCPのgateは実装済みだが、価値がSettingsの中に埋もれている。Pro価値はdisabled toggleではなくstatus cardとして見える必要がある。

Risk: Provider/MCP controlをこのまま増やすと、アプリが便利になる前に運用画面として重く見える。次のUI作業は機能追加より可視複雑性の削減を優先する。

## 次の実装候補

1. P11-022: Settingsをcompact overviewに整理し、AI Provider / MCP / Sync / Privacyの状態を深いscrollなしで見えるようにする。
2. P11-032: 外部連携を増やす前に、InboxとTodayをfirst-class destinationにする。
3. P11-033: keyboard shortcutとfocus orderをboard、inspector、review executionで検証する。
