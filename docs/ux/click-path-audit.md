# SoloPM クリック導線監査

作成日: 2026-06-19

対象: 現在の SwiftUI 実装である `SoloPMApp.swift`, `ProjectBoardView.swift`, `ProjectWorkflowViews.swift`, `SettingsView.swift`, `MenuBarPanel.swift`, `VoiceCaptureView.swift` の主要操作。

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
| Project Board | 起動時のメインwindow、menu barの `Project Board` | SidebarにInbox、Today、Projectsが固定表示され、Project overview/board/list、task composer、inspectorを扱う主要画面。 |
| Voice Command | board toolbarの `Voice Command`、menu barの `Voice Command` | CaptureとAI action reviewの導線がある。現状ではInboxの代替に近い。 |
| Settings | macOS app menuの `Settings...`、`Command+,`、macOS Settings scene | 先頭のStatus OverviewでAI Provider、MCP、Sync、Privacyを確認でき、続くSettings Overview Pro Value rowでSync/MCPの有料価値とFree/local-only/fail-closed境界が分かる。ThemeはSettings内のAppearance tabに集約する。 |
| Inbox | sidebarの `Inbox` | 未処理taskを実データから表示し、Task化、Project化、今日へ予定、後で確認を選択中itemへ1クリックで適用できる。 |
| Today | sidebarの `Today` | due/overdueの未完了taskを実データから表示し、overdue/today件数、local focus suggestion、30分単位のtime block、task inspectorへつながる。 |
| Project Detail | sidebarの個別project row | 1Projectの実行管理としてOverview / Board / List、Task、Artifact、Timeline、Milestone、Local Suggestionsを扱う。 |

## Phase 14 access-flow map (2026-07-03)

Phase 14 product review maps each major user goal as `app launch -> entry point -> screen/state -> action -> result/approval`. This separates user-visible reachability, runtime/AX reachability, and manual-only release evidence.

| User goal | Access flow | Current reachability | Follow-up / PR |
| --- | --- | --- | --- |
| Project Board work | app launch -> Project Board -> sidebar `Projects` / project row -> Overview / Board / List -> inspector/details | Reachable. Current screenshots show the board, cards, inspector, and project overview as coherent first-run work surfaces. | Existing Phase 12 evidence |
| Inbox triage | app launch -> sidebar `Inbox` -> capture or select item -> `Make Task` / `Make Project` / `Schedule Today` / `Review Later` -> optional Undo | Reachable. Runtime Inbox triage smoke covers mutation and undo path. | Existing runtime smoke |
| Today planning | app launch -> sidebar `Today` -> Daily Planning Review / command area / review rail -> Focus / Schedule Block / Reminder Draft | Reachable. Runtime Today completion smoke covers Today rail, local schedule draft, reminder draft, and visible completion. | Existing runtime smoke |
| Schedule Calendar apply | app launch -> sidebar `Schedule` -> `Generate Draft` -> `Queue Calendar Apply` -> Assistant Queue approval | Reachable but previously hard to follow because draft generation and Calendar apply were separated vertically. | #209 / PR #217 |
| Done recovery/follow-up | app launch -> sidebar `Done` -> completed task row -> `Follow Up` / `Reopen` | Reachable but row/action relationship was weak on wide windows. | #210 / PR #215 |
| Settings Google Calendar destination | app launch -> `Settings...` / `Command+,` -> `Sync` -> Google Calendar save flow -> `Save Calendar` -> `Check Readiness` | Source identifiers existed, but runtime AX proof was unstable until the save-flow group and settings smoke were hardened. | #208 / PR #218 |
| Voice Command planning or capture | app launch -> Voice Command -> record or type -> `Save to Inbox` / `Generate Plan` -> Inbox or Assistant Queue review | Reachable, but the empty initial state did not explain record/type -> inbox/plan -> approval. | #211 / PR #216 |
| Launch readiness proof | developer/release -> `./script/build_and_run.sh --verify` -> Project Board visible-window proof | Required for release evidence, but default timeout could false-block cold SwiftUI launch. | #212 / PR #214 |

## Phase 14 hard-to-access or unproven paths

| Path | Access issue found | Verification layer | Status |
| --- | --- | --- | --- |
| Settings Google Calendar save/readiness | Runtime Settings save path could hang or miss `settings-google-calendar-id-save`; duplicate generic Save Settings identifiers made AX targeting brittle. | source + runtime + security | Fixed in #208 / PR #218; `./script/check_runtime_settings_save_smoke.sh` proves isolated UserDefaults persistence without token or path leakage. |
| Schedule apply after draft generation | `Queue Calendar Apply` was below the cockpit flow, so users could generate a draft and lose the next approval step. | source + runtime schedule smoke + visual | Fixed in #209 / PR #217; apply approval stays next to the draft flow and still routes Calendar writes through Assistant Queue. |
| Done row recovery actions | `Follow Up` and `Reopen` were functionally present but visually detached from the completed task row on wide layouts. | source + visual | Fixed in #210 / PR #215; actions are attached to each completed row. |
| Voice Command first-run path | Empty state did not teach that users can record or type, then either save to Inbox or generate an approval-reviewed plan. | source + localization + visual; runtime voice smoke remains a follow-up for AX text submission | Improved in #211 / PR #216; initial state now explains examples, readiness, Inbox save, and plan generation. |
| Launch visible-window verifier | `build_and_run.sh --verify` could report a false blocker before the Project Board window appeared on a cold SwiftUI launch. | source + runtime verifier + security | Fixed in #212 / PR #214; default verify timeout now covers cold launch recovery. |

## クリック数

| 操作 | 導線 | クリック数 | 判定 | メモ |
| --- | --- | ---: | --- | --- |
| menu barからProject Boardを開く | menu bar icon -> `Project Board` | 2 | Pass | 通常起動ではProject Boardが最初に出るため、起動後は0クリック。 |
| menu bar Quick Add | menu bar icon -> `Quick Add`入力 -> `Add` | 2 | Pass | menu bar Quick AddからInboxへ0画面遷移で実タスクを作れる。Project Boardを開かなくてもlocal DBへ保存し、Board/MenuBar summaryへ変更通知する。 |
| Project作成 | sidebarの `Add Project` | 1 | Pass | 速い。作成直後にtitle編集が明確である状態は維持したい。 |
| Project選択 | sidebar project row | 1 | Pass | ネイティブsidebar listで繰り返し操作に向いている。 |
| Project overview確認 | sidebar project row -> `Overview` | 1-2 | Pass | 初期表示またはView segmentで、進捗、Task snapshot、実artifact、Timeline、Local suggestionを同一画面で確認できる。 |
| Project artifact確認 | Project overview -> `Artifacts` section | 1-2 | Pass | SQLite `artifacts` のproject/task linkを表示し、未連携時はno tracked artifactsとして扱う。 |
| Project artifact追加 | Project overview -> `Expected artifact path` -> `Track Artifact` | 2 | Pass | 絶対パスだけをexpected artifactとしてlocal SQLiteへ保存し、相対パスはworkspace未確定として保存しない。 |
| Project artifact削除 | Project overview -> Artifact row `Remove artifact link` | 1 | Pass | 実ファイルは削除せず、local SQLiteのartifact linkだけを削除する。存在しないlinkはmock successにしない。 |
| Inbox確認 | sidebar `Inbox` | 1 | Pass | Capture先が見える。選択中itemは右inspectorで編集できる。 |
| Inbox voice detail | sidebar `Inbox` -> item row | 2 | Pass | Seeded voice memo metadata、transcript、interpretation summaryをInbox内で確認できる。 |
| Inbox / Todayのrow完了toggle | workflow rowのcheckbox button | 1 | Pass | Inspectorを開かず、local SQLiteのTask statusをDone/Plannedへ実mutationする。 |
| Inbox item分類 | item選択 -> `Make Task` / `Make Project` / `Schedule Today` / `Review Later` | 2 | Pass | 分類action自体は1クリック。選択済みなら即実行され、store mutationを通る。 |
| Today確認 | sidebar `Today` | 1 | Pass | 今日以前の未完了task、期限内訳、local focus suggestion、time blockがproject横断で見える。 |
| Projects overview確認 | sidebar `Projects` | 1 | Pass | Project portfolio overviewで進捗、リスク、期限、次アクションを横断確認できる。 |
| Schedule確認 | sidebar `Schedule` | 1 | Pass | Unscheduled tasks、draft blocks、approval tokenをCalendar write前に確認できる。 |
| Done確認 | sidebar `Done` | 1 | Pass | completed_at履歴、完了Project、最近の完了taskを確認できる。 |
| 選択中ProjectにTask作成 | headerの `Add Task` -> 入力 -> `Add` | 2 | Pass | 目標達成。columnの `+` と空columnの追加導線も2クリック。 |
| 別ProjectにTask作成 | sidebar project -> `Add Task` -> 入力 -> `Add` | 3 | Pass | 目的地変更があるため3操作だが、`Add Task` はOverview/HeaderからでもBoardへ切り替えてinline composerを即表示するため、押下後に入力欄を探す必要はない。Inbox capture用途はmenu bar Quick Addを使う。 |
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
| Settingsを開く | macOS app menu `Settings...` または `Command+,` | 1 | Pass | Project BoardとMenuBarPanelの右上には置かず、作業画面内のTheme/Settings重複導線をなくす。 |
| Settings integrations確認 | Settings -> Status Overview | 1 | Pass | AI/STT/TTS/Calendar/Reminder/MCP/Sync/Privacy/Data Locationの状態をOverviewで確認できる。 |
| Theme変更 | Settings -> Appearance -> `Theme` segment | 2 | Pass | ThemeはSettingsのAppearance tabに集約済み。Project Boardのサイドバー下/右上にはTheme controlを置かない。 |
| AI Provider状態確認 | Settings -> Status OverviewまたはAI tabのProvider Readiness summaryを見る | 1 | Pass | 現在のproviderと認証/承認状態は先頭で分かり、AI tabでは全providerの設定状態をprovider切替なしで確認できる。 |
| AI Provider変更 | Settings -> provider picker -> provider | 2 | Pass | Provider選択時に自動保存されるため、保存ボタンを探す必要がない。AI Provider readiness rowで選択中providerの状態、smoke readiness、次の操作がすぐ分かる。 |
| Provider API key保存 | Settings -> API key field -> save key | 3 | Pass | 初期設定として3操作は残るが、readiness rowが「Keychainへ保存」「再入力」「manual smoke」の次操作を出すため迷子になりにくい。 |
| OpenCode Local設定 | Settings -> executable/workspace/model入力 -> approval toggle -> save | 5+ | Watch | 複数fieldが必要な設定だが、readiness rowが executable / workspace / approval の不足を先に示す。設定量自体はlocal subprocess providerの安全境界として許容する。 |
| 選択中MCP serverの接続確認 | Settings -> server rowの `Check` | 2 | Pass | 各server rowにEnabled/Disabled、接続結果、protocol versionを表示する。 |
| 別MCP serverの接続確認 | Settings -> 対象server rowの `Check` | 2 | Pass | Picker切替を不要にし、rowのCheckで対象serverを選択して接続確認できる。 |
| MCP実行境界確認 | Settings -> MCP tab | 1 | Pass | MCP paid execution boundary rowで、登録/接続確認はFreeでも可能、tools/callはProかつentitlement/policy/approval必須だと分かる。 |
| Sync状態確認 | Settings -> Status Overviewを見る | 1 | Pass | Planと状態がSettings先頭で分かる。Sync tabではpaid value rowがPro価値、Freeのlocal-only境界、backend未構成状態をtoggle前に示す。 |
| Pro価値確認 | Settings -> OverviewのPro Value rowを見る | 1 | Pass | Settings Overview Pro Value rowで、SyncとAdvanced MCP Executionの価値、Free/local-only、backend未構成、tools/call前のentitlement/policy/approval境界がタブ移動なしで分かる。 |
| Free userでSync開始 | Settings -> `External Sync` toggle | 2 | Pass | network前にupgrade gateで止まる。Free stays local / no data leaves this Mac の境界もtoggle前に見える。 |
| text commandからplan生成 | Voice Command -> 入力 -> `Generate Plan` | 2 | Pass | 生成後にreview panelが同じ画面へ出る。 |
| 録音からplan生成 | Voice Command -> `Record` -> `Stop` -> `Generate Plan` | 4 | Watch | 音声captureとしては自然だが、Inbox代替としては重い。 |
| Review実行 | `Approve` -> `Execute` | 2 | Pass | write actionは承認必須。approval不要なら1クリックで実行できる。 |

## ギャップ

| ギャップ | ユーザー影響 | 優先度 | 必要な修正 |
| --- | --- | --- | --- |
| Inbox分類後のsuccess/undo/next selectionを実装済み | Project化、Schedule化、後で確認の実mutation後に結果メッセージ、直前操作のUndo、次のInbox item自動選択を出す。 | Done | 連続triageの実機操作で、Undo後の復元先と選択状態を確認する。 |
| Today time blockはlocal plan止まり | Today viewはdue/overdue task、local focus suggestion、30分time blockを表示できるが、Calendarへの適用や自動再配置はまだしない。 | P2 | Calendar連携をrelease scopeに入れる場合だけ、適用前確認つきのschedule actionを追加する。 |
| Task card metadata stripはsource-levelで改善済み | Task card metadata strip はstatus / priority / dueを固定寸法chipに分離し、狭いKanban列ではadaptive gridへ逃がす。drag affordanceは右上の固定サイズiconとして残り、Open task領域とstatus move controlsから分離済み。 | Done | Light/Dark/Systemスクリーンショットでtitle、状態、優先度、期限、drag affordanceが重ならないことを確認済み。 |
| Task card screenshot証跡は生成・目視確認済み | Task cardのtitle/status/priority/due/drag affordanceは実装済み。`docs/release/evidence/ui-screenshots/` のLight/Dark/System PNGで一時HOME、seed済みProject board、window captureの証跡を残した。 | Done | 以後のUI変更では `script/capture_ui_evidence.sh` を再実行し、生成PNGを目視確認する。 |
| Inspector summaryはsource-levelで改善済み | Task / Project inspector はcompact summaryを先頭に追加済み。Taskはstatus/priority/due/project、Projectはstatus/open tasks/total tasks/artifactsを詳細Form前に表示し、右ペインを開いた直後の文脈把握を早くする。 | Done | Light/Dark/Systemスクリーンショットでsummary、編集field、danger actionが狭いinspector幅でも重ならないことを確認済み。 |
| Settings詳細Formはtab分割済み | Settings詳細FormはOverview / Appearance / AI / MCP / Sync / Privacyのtabへ分割済み。Status OverviewはOverview、ThemeはAppearance、provider詳細はAI、MCP登録/権限/auditはMCP、同期はSync、通知/起動/WatcherはPrivacyに分けた。 | Done | `settings-appearance-light.png` / `settings-appearance-dark.png` とsource testでTheme pickerがSettings Appearanceに1箇所だけ存在し、Project Boardには重複Theme controlがないことを確認済み。 |
| Settings Overview Pro Value rowのスクリーンショット証跡は生成・目視確認済み | Settings OverviewはStatus Overview直下にPro Value rowを置き、Sync/MCPタブへ移動しなくても有料価値とFree/local-only/fail-closed境界を確認できる。`settings-overview-light.png` / `settings-overview-dark.png` でLight/Darkの表示崩れを確認する。 | Done | 以後のSettings Overview変更では `script/capture_ui_evidence.sh` を再実行し、Settings Overview PNGを目視確認する。 |
| Provider詳細設定は選択中providerだけを表示するcompact panelへ分離済み | Provider pickerの下に選択中providerに必要なfieldだけを出すため、他providerのAPI key、model、local executableは同時表示されない。AI Provider readiness summaryでは全providerのConfigured / Not configured / Local / Setup required / Approval requiredを短く見られる。 | Done | 未選択providerの状態確認にprovider切替は不要。 |
| MCP server別の接続状態証跡は生成・目視確認済み | 複数server rowのinline statusとrow単位Checkは実装済み。`settings-mcp-light.png` / `settings-mcp-dark.png` で複数server、Free MCP execution gate、row単位Check導線を確認済み。 | Done | 以後のSettings変更では `script/capture_ui_evidence.sh` を再実行し、Settings Appearance / MCP PNGを目視確認する。 |
| Phase 12 screenshot evidence | Inbox voice detail、Projects overview、Schedule cockpit、Done analytics、Settings integrationsを `inbox-voice-light.png`、`projects-overview-light.png`、`schedule-light.png`、`done-light.png`、`settings-integrations-light.png` と各Dark PNGで固定した。 | Done | Release evidence gateはこれらのPNGが欠けるとgreenにならない。 |
| accessibility検証が未完了 | Task card、column add、status move、destructive confirmationのlabel/helpはsource testで固定し、Task cardのOpen Detailsとstatus move controlsも別フォーカス対象に分離した。Sidebar -> board detail -> task card -> Inline Task Composer -> inspectorのsource-level VoiceOver focus anchors are fixed。Inline Task Composerはrelease VoiceOver証跡の必須focus pathにも含めた。Task / Project inspectorのfield、提案適用、保存、complete、restore、archive、deleteはaccessibility identifier / hintを持ち、キーボードだけで実行できる。Inbox / Todayのrow、Quick Add、分類action、Today summary、time blockにsource-level accessibility identifiers / hints / keyboard anchorsを追加済み。Project OverviewのTask snapshot、Local Suggestions、Artifactsはaccessibility identifier / label / hint付きのCRUD入口になっている。Light/Dark/System screenshot evidenceは生成・目視確認済み。実機VoiceOver focus order確認は残る。 | P1 | VoiceOverでProject board -> card -> Inline Task Composer -> inspectorの順序を確認し、崩れを修正する。 |

## 改善紐づけ

PR未作成のため、現時点ではcurrent branchの改善commitとsource testに紐づける。PR作成時はこの表をPR descriptionに転記する。

主な回帰テストは `Tests/SoloPMCoreTests/AppExperienceSourceTests.swift`、`Tests/SoloPMCoreTests/ProjectBoardStoreTests.swift`、`Tests/SoloPMCoreTests/ExternalMCPTests.swift`、`Tests/SoloPMCoreTests/SyncEntitlementTests.swift` に固定する。

| 導線 | クリック数上の改善 | 実装 | 回帰テスト |
| --- | --- | --- | --- |
| Project作成 / Project選択 / Project inspector | sidebarから1クリックでProjectを作成・選択し、右inspectorで編集、完了、archive、deleteを完結する。 | `Sources/SoloPMApp/Views/ProjectBoardView.swift`, `Sources/SoloPMCore/App/ProjectBoard.swift` | `AppExperienceSourceTests.testProjectBoardExposesPrimaryCRUDKeyboardShortcuts`, `ProjectBoardStoreTests.testDeleteProjectRemovesProjectAndTasksFromPersistentBoard` |
| Task作成 / Task編集 / Task削除 | 選択中Projectのheaderまたはcolumnから2クリックでTaskを追加し、card -> inspectorで編集・削除を完結する。 | `Sources/SoloPMApp/Views/ProjectBoardView.swift`, `Sources/SoloPMCore/App/ProjectBoard.swift` | `ProjectBoardStoreTests.testCreateTaskPersistsRequestedColumnMetadataAndDetail`, `ProjectBoardStoreTests.testUpdateTaskMovesCardAcrossColumnsAndUpdatesMetadata`, `ProjectBoardStoreTests.testDeleteTaskRemovesCardFromPersistentSnapshot` |
| Inline Task Composer accessibility | Inline Task Composerはtitle/detail/priority/due/create/cancelにaccessibility anchorsを持ち、Command+Returnで作成、Escapeでキャンセルできる。 | `Sources/SoloPMApp/Views/ProjectBoardView.swift` | `AppExperienceSourceTests.testInlineTaskComposerExposesKeyboardAndVoiceOverCreateAnchors` |
| Task status移動 | card上のchevronで1クリック移動、またはdrag/dropで任意statusへ移動する。 | `Sources/SoloPMApp/Views/ProjectBoardView.swift`, `Sources/SoloPMCore/App/ProjectBoard.swift` | `AppExperienceSourceTests.testKanbanTaskCardsExposeMouseDrivenStatusMoveControls`, `AppExperienceSourceTests.testKanbanCardsUseTaskComponentDragPreview`, `ProjectBoardStoreTests.testProjectBoardViewModelMovesDroppedTaskAndNotifiesOnce` |
| Task card metadata strip | title、status、priority、due、drag affordanceを分離し、狭いcolumnでも固定chipとadaptive gridで重なりにくくする。 | `Sources/SoloPMApp/Views/ProjectBoardView.swift` | `AppExperienceSourceTests.testTaskCardsUseSampleInspiredNonOverlappingMetadataStrip` |
| Project Add Task visibility | Overview/Headerの `Add Task` はBoardへ切り替えてBacklog composerを表示し、入力欄が見えない状態を作らない。 | `Sources/SoloPMApp/Views/ProjectBoardView.swift` | `AppExperienceSourceTests.testProjectAddTaskFromOverviewOpensVisibleBoardComposer` |
| Project artifact CRUD | Project OverviewのArtifacts panelからexpected artifactを2クリックで追加し、artifact rowから1クリックでlocal linkを削除する。どちらもlocal SQLite snapshotへ即反映し、実ファイルは削除しない。 | `Sources/SoloPMApp/Views/ProjectBoardView.swift`, `Sources/SoloPMCore/App/ProjectBoard.swift`, `Sources/SoloPMCore/Artifacts/ArtifactMonitoring.swift` | `ProjectBoardStoreTests.testCreateProjectArtifactPersistsExpectedArtifactInSnapshot`, `ProjectBoardStoreTests.testDeleteProjectArtifactRemovesLinkFromSnapshot`, `ProjectBoardStoreTests.testProjectBoardViewModelCreatesProjectArtifactAndNotifies`, `ProjectBoardStoreTests.testProjectBoardViewModelDeletesProjectArtifactAndNotifies` |
| Project Overview accessibility | Task snapshot、Local Suggestions、ArtifactsのCRUD入口にaccessibility identifier / label / hintを付け、Overviewからも支援技術でtask open、task create、suggestion open/unblock、artifact track/removeへ入れる。 | `Sources/SoloPMApp/Views/ProjectBoardView.swift` | `AppExperienceSourceTests.testProjectOverviewActionsAreAccessibleCrudEntryPoints` |
| Review Execute artifact作成 | Action Planのfilesystem artifact作成が `projectId` / `taskId` を持つ場合、作成ファイルと同時にlocal SQLite artifact linkを作り、Project OverviewのArtifactsへ戻す。 | `Sources/SoloPMCore/Tools/SystemTools.swift`, `Sources/SoloPMCore/Tools/SystemToolClients.swift`, `Sources/SoloPMApp/SoloPMApp.swift` | `SystemToolTests.testFileSystemToolPersistsCreatedArtifactLinkWhenProjectIDIsProvided`, `AppExperienceSourceTests.testRuntimeAppCompositionDoesNotUseDemoOrInMemorySuccessPath` |
| Inbox capture / triage | MenuBar Quick AddまたはInbox headerから実タスクを作り、item選択後にMake Task、Make Project、Schedule Today、Review Laterを1クリックで実mutationへ送る。 | `Sources/SoloPMApp/Views/MenuBarPanel.swift`, `Sources/SoloPMApp/Views/ProjectWorkflowViews.swift`, `Sources/SoloPMCore/App/ProjectBoard.swift` | `AppExperienceSourceTests.testMenuBarPanelProvidesFastInboxCaptureWithRuntimeBoardViewModel`, `ProjectBoardStoreTests.testProjectBoardViewModelQuickCapturesInboxTaskAndNotifies`, `ProjectBoardStoreTests.testProjectBoardViewModelQuickCapturePersistsToSQLiteInbox`, `ProjectBoardStoreTests.testProjectBoardViewModelInboxClassificationShowsFeedbackAdvancesSelectionAndUndo`, `ProjectBoardStoreTests.testSQLiteBoardStorePersistsInboxClassificationUndo` |
| Today planning | sidebarから1クリックでdue/overdue、focus suggestion、time blockを確認する。 | `Sources/SoloPMApp/Views/ProjectWorkflowViews.swift`, `Sources/SoloPMCore/App/ProjectBoard.swift` | `AppExperienceSourceTests.testTodayWorkflowShowsRecommendationDueCountsAndTimeBlocks`, `ProjectBoardStoreTests.testProjectBoardViewModelBuildsDeterministicTodayPlanWithTimeBlocks` |
| Settings overview / Theme | macOS app menuまたは`Command+,`からSettingsを開き、Status OverviewはOverview tab、Theme segmentはAppearance tabへ集約する。Project Boardのサイドバー下/右上とMenuBarPanel右上にはTheme/Settings controlを置かない。 | `Sources/SoloPMApp/SoloPMApp.swift`, `Sources/SoloPMApp/Views/SettingsView.swift` | `AppExperienceSourceTests.testSettingsSurfaceStartsWithStatusOverviewForCoreOperationalAreas`, `AppExperienceSourceTests.testAppearanceSelectionIsConfiguredOnlyFromSettings`, `AppExperienceSourceTests.testProjectBoardSidebarAndToolbarDoNotHostThemeControls`, `AppExperienceSourceTests.testMenuBarPanelDoesNotHostSettingsOrThemeControls` |
| AI Provider readiness row | Provider picker直下に選択中providerの状態、smoke readiness、次の操作を表示し、API keyやlocal executionの不足を詳細field前に分かるようにする。 | `Sources/SoloPMApp/Views/SettingsView.swift` | `AppExperienceSourceTests.testAISettingsTabShowsSelectedProviderReadinessBeforeProviderFields` |
| AI Provider readiness summary | AI tab内に全providerの状態を短いsummaryとして表示し、provider切替なしでKeychain/API/local executionの不足を把握できるようにする。 | `Sources/SoloPMApp/Views/SettingsView.swift`, `Sources/SoloPMCore/App/AppSettings.swift` | `AppExperienceSourceTests.testAISettingsTabShowsSelectedProviderReadinessBeforeProviderFields`, `AppSettingsTests.testAppSettingsViewModelBuildsProviderReadinessRowsWithoutSecrets` |
| AI provider設定 | provider pickerの選択を自動保存し、選択中providerのfieldだけを表示する。 | `Sources/SoloPMApp/Views/SettingsView.swift`, `Sources/SoloPMCore/App/AppSettings.swift`, `Sources/SoloPMCore/App/LLMProviderCatalog.swift` | `AppExperienceSourceTests.testAISettingsTabShowsOnlySelectedProviderFields`, `AppSettingsTests.testAppSettingsViewModelPersistsProviderSelectionWhenSelected` |
| MCP接続確認 | Settings内のserver rowから対象serverを2クリックでCheckし、Picker切替を不要にする。 | `Sources/SoloPMApp/Views/SettingsView.swift`, `Sources/SoloPMCore/ExternalMCP/MCPRegistration.swift` | `AppExperienceSourceTests.testSettingsSurfaceShowsInlineMCPServerRowsWithCheckActions`, `ExternalMCPTests.testExternalMCPSettingsViewModelChecksSpecificRegistrationFromInlineRow` |
| MCP paid execution boundary row | 登録編集前にPro実行価値、Freeで可能な登録/接続確認、tools/call前のentitlement/approval/policy境界を表示し、課金状態が危険toolを自動許可しないことを示す。 | `Sources/SoloPMApp/Views/SettingsView.swift`, `Sources/SoloPMCore/ExternalMCP/MCPExecution.swift` | `AppExperienceSourceTests.testMCPSettingsTabSurfacesPaidExecutionBoundaryBeforeRegistrationEditing`, `ExternalMCPTests.testExternalMCPExecutionRequiresPaidEntitlementBeforeToolCall`, `ExternalMCPTests.testPaidEntitlementDoesNotBypassDangerousOrApprovalGuards` |
| Sync gate | Free userはExternal Sync開始前にdomain層で止め、Proでもbackend未構成ならtoggleをdisabledにしてmock successにしない。backend設定済みのnetwork failureは`Failed`とLast Attemptを残し、`Ready`へ戻して成功のように見せない。 | `Sources/SoloPMApp/Views/SettingsView.swift`, `Sources/SoloPMCore/App/SyncService.swift`, `Sources/SoloPMCore/App/Entitlements.swift` | `AppExperienceSourceTests.testSettingsSurfaceShowsSyncGateWithoutMockSuccessPath`, `SyncEntitlementTests.testSyncServiceFreeStartFailsBeforeNetworkClientIsReached`, `SyncEntitlementTests.testSyncServiceProWithoutBackendDoesNotReturnMockSuccess`, `SyncEntitlementTests.testSyncSettingsViewModelAllowsProToggleOnlyWhenBackendIsConfigured`, `SyncEntitlementTests.testSyncServiceConfiguredBackendRecordsNetworkFailureInsteadOfReturningReady`, `SyncEntitlementTests.testSyncSettingsViewModelShowsFailedStateAfterNetworkFailure` |
| Sync paid value row | Sync toggle前にPro価値、Freeのlocal-only境界、backend未構成時のno-upload状態を表示し、有料機能がdisabled toggleだけに見えないようにする。 | `Sources/SoloPMApp/Views/SettingsView.swift` | `AppExperienceSourceTests.testSyncSettingsTabSurfacesPaidValueAndLocalBoundaryBeforeToggle` |

## プロダクトレビュー

Problem: SoloPMは実働するboardとlocal dataを持ったが、まだ日々のPM cockpitとしてはProject detailの文脈整理が弱かった。

User pull: Project overviewでTask、Artifact、Timeline、Local suggestionが同じ画面にまとまり、Project inspectorで編集、削除、提案適用まで同じ右側の操作面に揃った。

Retention hook: Todayは日次のdefault surfaceに近づき、Project overviewは週次/案件単位の確認面になった。次はkeyboard/focusとスクリーンショット検証を詰め、繰り返し操作の摩擦を減らす。

Monetization: Syncとadvanced MCPのgateは実装済み。Pro価値はSettings Overview Pro Value row、Sync paid value row、MCP paid execution boundary rowで、disabled toggleではなくstatus rowとして見える。

Risk: Artifact追加は絶対パスに限定してworkspace推測を避け、削除もDB linkだけに限定したため、local-firstの安全性は保てている。一方、相対パスやworkspace default連携はまだ未対応なので、次のUI作業はaccessibilityとvisual evidenceを優先する。

## 次の実装候補

1. P11-033: 実機VoiceOverでProject board -> card -> Inline Task Composer -> inspectorのfocus orderを確認する。
2. P11-040: Notion / Todoist / Linear / Motion の実操作メモを追加し、desk researchとの差分だけ更新する。
3. P5/P10: Developer ID signing / notarization / Sparkle appcast のrelease-machine gateを埋める。
