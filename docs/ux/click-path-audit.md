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
| Project Board | 起動時のメインwindow、menu barの `Project Board`、board toolbar | SidebarにInbox、Today、Projectsが固定表示され、Project overview/board/list、task composer、inspector、Settings入口がある主要画面。 |
| Voice Command | board toolbarの `Voice Command`、menu barの `Voice Command` | CaptureとAI action reviewの導線がある。現状ではInboxの代替に近い。 |
| Settings | board toolbarのgear、menu barのgear、macOS Settings scene | 先頭のStatus OverviewでAI Provider、MCP、Sync、Privacyを確認できる。詳細設定は下のFormに並ぶ。 |
| Inbox | sidebarの `Inbox` | 未処理taskを実データから表示し、Task化、Project化、今日へ予定、後で確認を選択中itemへ1クリックで適用できる。 |
| Today | sidebarの `Today` | due/overdueの未完了taskを実データから表示し、overdue/today件数、local focus suggestion、30分単位のtime block、task inspectorへつながる。 |

## クリック数

| 操作 | 導線 | クリック数 | 判定 | メモ |
| --- | --- | ---: | --- | --- |
| menu barからProject Boardを開く | menu bar icon -> `Project Board` | 2 | Pass | 通常起動ではProject Boardが最初に出るため、起動後は0クリック。 |
| Project作成 | sidebarの `Add Project` | 1 | Pass | 速い。作成直後にtitle編集が明確である状態は維持したい。 |
| Project選択 | sidebar project row | 1 | Pass | ネイティブsidebar listで繰り返し操作に向いている。 |
| Project overview確認 | sidebar project row -> `Overview` | 1-2 | Pass | 初期表示またはView segmentで、進捗、Task snapshot、実artifact、Timeline、Local suggestionを同一画面で確認できる。 |
| Project artifact確認 | Project overview -> `Artifacts` section | 1-2 | Pass | SQLite `artifacts` のproject/task linkだけを表示し、未連携時はno tracked artifactsとして扱う。 |
| Inbox確認 | sidebar `Inbox` | 1 | Pass | Capture先が見える。選択中itemは右inspectorで編集できる。 |
| Inbox item分類 | item選択 -> `Make Task` / `Make Project` / `Schedule Today` / `Review Later` | 2 | Pass | 分類action自体は1クリック。選択済みなら即実行され、store mutationを通る。 |
| Today確認 | sidebar `Today` | 1 | Pass | 今日以前の未完了task、期限内訳、local focus suggestion、time blockがproject横断で見える。 |
| 選択中ProjectにTask作成 | headerの `Add Task` -> 入力 -> `Add` | 2 | Pass | 目標達成。columnの `+` と空columnの追加導線も2クリック。 |
| 別ProjectにTask作成 | sidebar project -> `Add Task` -> 入力 -> `Add` | 3 | Watch | 目的地変更があるため許容。ただしInbox capture用途では重い。 |
| Taskを隣のstatusへ移動 | cardのchevron left/right | 1 | Pass | 目標達成。ドラッグしないユーザーにも分かりやすい。 |
| Taskを任意のstatusへ移動 | cardを対象columnへドラッグ | 1 drag | Pass | drag affordanceとdrop target表示がある。 |
| context menuでTask移動 | card右クリック -> `Move To` -> status | 3 | Watch | 補助導線としては有効だが主導線ではない。 |
| Task詳細編集 | cardの `Open task` 領域 -> inspector編集 -> `Save Changes` | 2 | Pass | カード選択はtap gestureだけに依存せず、キーボードフォーカス可能なButtonになっている。Edit / Fields / Suggestion / Save / Danger Zoneで分かれる。 |
| Task提案適用 | card選択 -> inspector `Apply Suggestion` | 2 | Pass | statusを進めるだけのlocal suggestionは外部LLMなしで実mutationを通る。 |
| Task削除 | card選択 -> `Delete Task` -> confirm | 3 | Pass | 破壊的操作なので確認があるのは妥当。 |
| Project詳細編集 | sidebar project row -> inspector編集 -> `Save Project` | 2 | Pass | Project選択時に右inspectorが開き、title編集、status、task/artifact概要を一箇所で扱える。 |
| Project提案適用 | sidebar project row -> inspector `Apply Suggestion` | 2 | Pass | 空Projectのfirst task作成、全Task完了Projectのcomplete、注目Taskを開く導線を外部LLMなしで実行する。 |
| Project完了 | Project inspector -> `Complete Project` | 2 | Pass | headerから削除し、選択中Projectの操作をinspectorに集約した。 |
| Project archive/delete | Project inspector -> action -> confirm | 3 | Pass | 破壊的操作なので確認があるのは妥当。 |
| boardからSettingsを開く | toolbar gear | 1 | Pass | menu barからも2クリックで開ける。 |
| Theme変更 | Settings -> `Theme` segment | 2 | Pass | ThemeはSettingsに集約済み。 |
| AI Provider状態確認 | Settings -> Status Overviewを見る | 1 | Pass | 現在のproviderと認証/承認状態は先頭で分かる。 |
| AI Provider変更 | Settings -> provider picker -> provider | 2 | Pass | Provider選択時に自動保存されるため、保存ボタンを探す必要がない。追加設定が必要なproviderは既存validationで理由を出す。 |
| Provider API key保存 | Settings -> API key field -> save key | 3 | Watch | 初期設定としては許容だが、provider別の状態表示が密すぎる。 |
| OpenCode Local設定 | Settings -> executable/workspace/model入力 -> approval toggle -> save | 5+ | Watch | 複数fieldが必要な設定だが、validation状態はもっと明確に出すべき。 |
| 選択中MCP serverの接続確認 | Settings -> server rowの `Check` | 2 | Pass | 各server rowにEnabled/Disabled、接続結果、protocol versionを表示する。 |
| 別MCP serverの接続確認 | Settings -> 対象server rowの `Check` | 2 | Pass | Picker切替を不要にし、rowのCheckで対象serverを選択して接続確認できる。 |
| Sync状態確認 | Settings -> Status Overviewを見る | 1 | Pass | Planと状態がSettings先頭で分かる。詳細な対象dataはSync sectionに残る。 |
| Free userでSync開始 | Settings -> `External Sync` toggle | 2 | Pass | network前にupgrade gateで止まる。 |
| text commandからplan生成 | Voice Command -> 入力 -> `Generate Plan` | 2 | Pass | 生成後にreview panelが同じ画面へ出る。 |
| 録音からplan生成 | Voice Command -> `Record` -> `Stop` -> `Generate Plan` | 4 | Watch | 音声captureとしては自然だが、Inbox代替としては重い。 |
| Review実行 | `Approve` -> `Execute` | 2 | Pass | write actionは承認必須。approval不要なら1クリックで実行できる。 |

## ギャップ

| ギャップ | ユーザー影響 | 優先度 | 必要な修正 |
| --- | --- | --- | --- |
| Inbox分類後のsuccess/undo/next selectionを実装済み | Project化、Schedule化、後で確認の実mutation後に結果メッセージ、直前操作のUndo、次のInbox item自動選択を出す。 | Done | 連続triageの実機操作で、Undo後の復元先と選択状態を確認する。 |
| Today time blockはlocal plan止まり | Today viewはdue/overdue task、local focus suggestion、30分time blockを表示できるが、Calendarへの適用や自動再配置はまだしない。 | P2 | Calendar連携をrelease scopeに入れる場合だけ、適用前確認つきのschedule actionを追加する。 |
| Task card metadata stripはsource-levelで改善済み | Task card metadata strip はstatus / priority / dueを固定寸法chipに分離し、狭いKanban列ではadaptive gridへ逃がす。drag affordanceは右上の固定サイズiconとして残り、Open task領域とstatus move controlsから分離済み。 | Done | 実機スクリーンショットでtitle、状態、優先度、期限、drag affordanceが重ならないことを確認する。 |
| Task card screenshot証跡は自動生成フローを追加済み | Task cardのtitle/status/priority/due/drag affordanceは実装済み。Light/Dark/System screenshot evidence scriptは追加済みで、一時HOME、seed済みProject board、window captureとして生成する。 | P1 | Screen Recording権限のある実機で生成PNGを目視し、崩れがあればUIを修正する。 |
| Inspector summaryはsource-levelで改善済み | Task / Project inspector はcompact summaryを先頭に追加済み。Taskはstatus/priority/due/project、Projectはstatus/open tasks/total tasks/artifactsを詳細Form前に表示し、右ペインを開いた直後の文脈把握を早くする。 | P2 | 実機スクリーンショットでsummary、編集field、danger actionが狭いinspector幅でも重ならないことを確認する。 |
| Settings詳細Formはtab分割済み | Settings詳細FormはOverview / AI / MCP / Sync / Privacyのtabへ分割済み。Status OverviewとThemeはOverview、provider詳細はAI、MCP登録/権限/auditはMCP、同期はSync、通知/起動/WatcherはPrivacyに分けた。 | P2 | 次の改善ではproviderごとのvalidation stateを短いstatus rowへ集約する。 |
| Provider詳細設定は選択中providerだけを表示するcompact panelへ分離済み | Provider pickerの下に選択中providerに必要なfieldだけを出すため、他providerのAPI key、model、local executableは同時表示されない。 | P2 | 次はproviderごとのvalidation stateを短いstatus rowへ集約する。 |
| MCP server別の接続状態証跡はsource test中心 | 複数server rowのinline statusとrow単位Checkは実装済みだが、実アプリで複数serverを並べたスクリーンショット証跡はまだ弱い。 | P1 | MCP server listを含むSettings screenshotをlight/darkで保存する。 |
| accessibility検証が未完了 | Task card、column add、status move、destructive confirmationのlabel/helpはsource testで固定し、Task cardのOpen Detailsとstatus move controlsも別フォーカス対象に分離した。Sidebar -> board detail -> task card -> inspectorのsource-level VoiceOver focus anchors are fixed。Task / Project inspectorのfield、提案適用、保存、complete、restore、archive、deleteはaccessibility identifier / hintを持ち、キーボードだけで実行できる。Light/Dark/System screenshot evidence scriptは追加済み。実機VoiceOver focus order確認は残る。 | P1 | VoiceOverでProject board -> card -> inspectorの順序を確認し、崩れを修正する。 |

## 改善紐づけ

PR未作成のため、現時点ではcurrent branchの改善commitとsource testに紐づける。PR作成時はこの表をPR descriptionに転記する。

主な回帰テストは `Tests/SoloPMCoreTests/AppExperienceSourceTests.swift`、`Tests/SoloPMCoreTests/ProjectBoardStoreTests.swift`、`Tests/SoloPMCoreTests/ExternalMCPTests.swift`、`Tests/SoloPMCoreTests/SyncEntitlementTests.swift` に固定する。

| 導線 | クリック数上の改善 | 実装 | 回帰テスト |
| --- | --- | --- | --- |
| Project作成 / Project選択 / Project inspector | sidebarから1クリックでProjectを作成・選択し、右inspectorで編集、完了、archive、deleteを完結する。 | `Sources/SoloPMApp/Views/ProjectBoardView.swift`, `Sources/SoloPMCore/App/ProjectBoard.swift` | `AppExperienceSourceTests.testProjectBoardExposesPrimaryCRUDKeyboardShortcuts`, `ProjectBoardStoreTests.testDeleteProjectRemovesProjectAndTasksFromPersistentBoard` |
| Task作成 / Task編集 / Task削除 | 選択中Projectのheaderまたはcolumnから2クリックでTaskを追加し、card -> inspectorで編集・削除を完結する。 | `Sources/SoloPMApp/Views/ProjectBoardView.swift`, `Sources/SoloPMCore/App/ProjectBoard.swift` | `ProjectBoardStoreTests.testCreateTaskPersistsRequestedColumnMetadataAndDetail`, `ProjectBoardStoreTests.testUpdateTaskMovesCardAcrossColumnsAndUpdatesMetadata`, `ProjectBoardStoreTests.testDeleteTaskRemovesCardFromPersistentSnapshot` |
| Task status移動 | card上のchevronで1クリック移動、またはdrag/dropで任意statusへ移動する。 | `Sources/SoloPMApp/Views/ProjectBoardView.swift`, `Sources/SoloPMCore/App/ProjectBoard.swift` | `AppExperienceSourceTests.testKanbanTaskCardsExposeMouseDrivenStatusMoveControls`, `AppExperienceSourceTests.testKanbanCardsUseTaskComponentDragPreview`, `ProjectBoardStoreTests.testProjectBoardViewModelMovesDroppedTaskAndNotifiesOnce` |
| Task card metadata strip | title、status、priority、due、drag affordanceを分離し、狭いcolumnでも固定chipとadaptive gridで重なりにくくする。 | `Sources/SoloPMApp/Views/ProjectBoardView.swift` | `AppExperienceSourceTests.testTaskCardsUseSampleInspiredNonOverlappingMetadataStrip` |
| Inbox triage | item選択後にMake Task、Make Project、Schedule Today、Review Laterを1クリックで実mutationへ送る。 | `Sources/SoloPMApp/Views/ProjectWorkflowViews.swift`, `Sources/SoloPMCore/App/ProjectBoard.swift` | `ProjectBoardStoreTests.testProjectBoardViewModelInboxClassificationShowsFeedbackAdvancesSelectionAndUndo`, `ProjectBoardStoreTests.testSQLiteBoardStorePersistsInboxClassificationUndo` |
| Today planning | sidebarから1クリックでdue/overdue、focus suggestion、time blockを確認する。 | `Sources/SoloPMApp/Views/ProjectWorkflowViews.swift`, `Sources/SoloPMCore/App/ProjectBoard.swift` | `AppExperienceSourceTests.testTodayWorkflowShowsRecommendationDueCountsAndTimeBlocks`, `ProjectBoardStoreTests.testProjectBoardViewModelBuildsDeterministicTodayPlanWithTimeBlocks` |
| Settings overview / Theme | toolbar gearから1クリックでSettingsを開き、Status OverviewとTheme segmentをSettings内へ集約する。 | `Sources/SoloPMApp/SoloPMApp.swift` | `AppExperienceSourceTests.testSettingsSurfaceStartsWithStatusOverviewForCoreOperationalAreas`, `AppExperienceSourceTests.testAppearanceSelectionIsConfiguredOnlyFromSettings`, `AppExperienceSourceTests.testProjectBoardSidebarAndToolbarDoNotHostThemeControls` |
| AI provider設定 | provider pickerの選択を自動保存し、選択中providerのfieldだけを表示する。 | `Sources/SoloPMApp/SoloPMApp.swift`, `Sources/SoloPMCore/App/AppSettings.swift`, `Sources/SoloPMCore/App/LLMProviderCatalog.swift` | `AppExperienceSourceTests.testAISettingsTabShowsOnlySelectedProviderFields`, `AppSettingsTests.testAppSettingsViewModelPersistsProviderSelectionWhenSelected` |
| MCP接続確認 | Settings内のserver rowから対象serverを2クリックでCheckし、Picker切替を不要にする。 | `Sources/SoloPMApp/SoloPMApp.swift`, `Sources/SoloPMCore/ExternalMCP/MCPRegistration.swift` | `AppExperienceSourceTests.testSettingsSurfaceShowsInlineMCPServerRowsWithCheckActions`, `ExternalMCPTests.testExternalMCPSettingsViewModelChecksSpecificRegistrationFromInlineRow` |
| Sync gate | Free userはExternal Sync開始前にdomain層で止め、Proでもbackend未構成ならmock successにしない。 | `Sources/SoloPMApp/SoloPMApp.swift`, `Sources/SoloPMCore/App/SyncService.swift`, `Sources/SoloPMCore/App/Entitlements.swift` | `AppExperienceSourceTests.testSettingsSurfaceShowsSyncGateWithoutMockSuccessPath`, `SyncEntitlementTests.testSyncServiceFreeStartFailsBeforeNetworkClientIsReached`, `SyncEntitlementTests.testSyncServiceProWithoutBackendDoesNotReturnMockSuccess` |

## プロダクトレビュー

Problem: SoloPMは実働するboardとlocal dataを持ったが、まだ日々のPM cockpitとしてはProject detailの文脈整理が弱かった。

User pull: Project overviewでTask、Artifact、Timeline、Local suggestionが同じ画面にまとまり、Project inspectorで編集、削除、提案適用まで同じ右側の操作面に揃った。

Retention hook: Todayは日次のdefault surfaceに近づき、Project overviewは週次/案件単位の確認面になった。次はkeyboard/focusとスクリーンショット検証を詰め、繰り返し操作の摩擦を減らす。

Monetization: Syncとadvanced MCPのgateは実装済みだが、価値がSettingsの中に埋もれている。Pro価値はdisabled toggleではなくstatus cardとして見える必要がある。

Risk: Artifact表示は実DB rowだけに限定したためmock感はないが、artifact作成/リンク導線はまだ薄い。次のUI作業は機能追加よりaccessibilityとvisual evidenceを優先する。

## 次の実装候補

1. P11-022: Settingsをcompact overviewに整理し、AI Provider / MCP / Sync / Privacyの状態を深いscrollなしで見えるようにする。
2. P11-031: Task cardのlight/darkスクリーンショット検証を完了する。
3. P11-033: keyboard shortcutとfocus orderをboard、inspector、review executionで検証する。
