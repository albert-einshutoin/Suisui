# Suisui クリック導線監査

作成日: 2026-06-19

対象: 現在の SwiftUI 実装である `SuisuiApp.swift`, `ProjectBoardView.swift`, `ProjectWorkflow*View.swift`, `SettingsView.swift`, `MenuBarPanel.swift`, `VoiceCaptureView.swift` の主要操作。

## 目標

| 操作 | 目標 |
| --- | --- |
| Task作成 | 目的の画面が見えてから2クリック以内 |
| Taskステータス変更 | 1回のドラッグ、またはカード上の1ボタン |
| Project作成 | 2クリック以内 |
| Provider設定 | Settingsを開いてから2クリック以内 |
| MCP接続確認 | Settingsを開いてから2クリック以内。MCP tabはOverviewの `Show advanced settings` toggleをONにすると表示され、ON後の導線は従来通り。 |
| Sync状態確認 | Settingsを開いてから1クリック以内。Sync tabはOverviewの `Show advanced settings` toggleをONにすると表示され、ON後の導線は従来通り。 |

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
| 選択中MCP serverの接続確認 | Settings -> server rowの `Check` | 2 | Pass | 各server rowにEnabled/Disabled、接続結果、protocol versionを表示する。MCP/Sync tabはOverviewの `Show advanced settings` toggleをONにすると表示される。ON後の導線は従来通り。 |
| 別MCP serverの接続確認 | Settings -> 対象server rowの `Check` | 2 | Pass | Picker切替を不要にし、rowのCheckで対象serverを選択して接続確認できる。MCP/Sync tabはOverviewの `Show advanced settings` toggleをONにすると表示される。ON後の導線は従来通り。 |
| MCP実行境界確認 | Settings -> MCP tab | 1 | Pass | MCP paid execution boundary rowで、登録/接続確認はFreeでも可能、tools/callはProかつentitlement/policy/approval必須だと分かる。 |
| Sync状態確認 | Settings -> Status Overviewを見る | 1 | Pass | Planと状態がSettings先頭で分かる。Sync tabではpaid value rowがPro価値、Freeのlocal-only境界、backend未構成状態をtoggle前に示す。MCP/Sync tabはOverviewの `Show advanced settings` toggleをONにすると表示される。ON後の導線は従来通り。 |
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
| Task card metadata stripはhosted runtimeで改善済み | Task card metadata strip はstatus / priorityとdue / recurrenceを最大2行の意味的なTextへ統合する。drag affordanceは右上の固定サイズiconとして残り、Open task領域とstatus move controlsから分離済み。 | Done | Hosted Light/Dark/Systemスクリーンショットで、選択カードを含めtitle、状態、優先度、期限、drag affordanceが欠落・重複しないことを確認する。 |
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

主な回帰テストは `Tests/SuisuiCoreTests/AppExperienceSourceTests.swift`、`Tests/SuisuiCoreTests/ProjectBoardStoreTests.swift`、`Tests/SuisuiCoreTests/ExternalMCPTests.swift`、`Tests/SuisuiCoreTests/SyncEntitlementTests.swift` に固定する。

| 導線 | クリック数上の改善 | 実装 | 回帰テスト |
| --- | --- | --- | --- |
| Project作成 / Project選択 / Project inspector | sidebarから1クリックでProjectを作成・選択し、右inspectorで編集、完了、archive、deleteを完結する。 | `Sources/SuisuiApp/Views/ProjectBoardView.swift`, `Sources/SuisuiCore/App/ProjectBoard.swift` | `AppExperienceSourceTests.testProjectBoardExposesPrimaryCRUDKeyboardShortcuts`, `ProjectBoardStoreTests.testDeleteProjectRemovesProjectAndTasksFromPersistentBoard` |
| Task作成 / Task編集 / Task削除 | 選択中Projectのheaderまたはcolumnから2クリックでTaskを追加し、card -> inspectorで編集・削除を完結する。 | `Sources/SuisuiApp/Views/ProjectBoardView.swift`, `Sources/SuisuiCore/App/ProjectBoard.swift` | `ProjectBoardStoreTests.testCreateTaskPersistsRequestedColumnMetadataAndDetail`, `ProjectBoardStoreTests.testUpdateTaskMovesCardAcrossColumnsAndUpdatesMetadata`, `ProjectBoardStoreTests.testDeleteTaskRemovesCardFromPersistentSnapshot` |
| Inline Task Composer accessibility | Inline Task Composerはtitle/detail/priority/due/create/cancelにaccessibility anchorsを持ち、Command+Returnで作成、Escapeでキャンセルできる。 | `Sources/SuisuiApp/Views/ProjectBoardView.swift` | `AppExperienceSourceTests.testInlineTaskComposerExposesKeyboardAndVoiceOverCreateAnchors` |
| Task status移動 | card上のchevronで1クリック移動、またはdrag/dropで任意statusへ移動する。 | `Sources/SuisuiApp/Views/ProjectBoardView.swift`, `Sources/SuisuiCore/App/ProjectBoard.swift` | `AppExperienceSourceTests.testKanbanTaskCardsExposeMouseDrivenStatusMoveControls`, `AppExperienceSourceTests.testKanbanCardsUseTaskComponentDragPreview`, `ProjectBoardStoreTests.testProjectBoardViewModelMovesDroppedTaskAndNotifiesOnce` |
| Task card metadata strip | titleとdrag affordanceを分離し、status / priorityとdue / recurrenceを最大2行の意味的なTextとして狭いcolumnでも読み切れるようにする。 | `Sources/SuisuiApp/Views/ProjectBoardDetailViews.swift` | `AppExperienceSourceTests.testTaskCardsUseSampleInspiredNonOverlappingMetadataStrip`, `ProjectBoardMetadataLayoutSourceTests` |
| Project Add Task visibility | Overview/Headerの `Add Task` はBoardへ切り替えてBacklog composerを表示し、入力欄が見えない状態を作らない。 | `Sources/SuisuiApp/Views/ProjectBoardView.swift` | `AppExperienceSourceTests.testProjectAddTaskFromOverviewOpensVisibleBoardComposer` |
| Project artifact CRUD | Project OverviewのArtifacts panelからexpected artifactを2クリックで追加し、artifact rowから1クリックでlocal linkを削除する。どちらもlocal SQLite snapshotへ即反映し、実ファイルは削除しない。 | `Sources/SuisuiApp/Views/ProjectBoardView.swift`, `Sources/SuisuiCore/App/ProjectBoard.swift`, `Sources/SuisuiCore/Artifacts/ArtifactMonitoring.swift` | `ProjectBoardStoreTests.testCreateProjectArtifactPersistsExpectedArtifactInSnapshot`, `ProjectBoardStoreTests.testDeleteProjectArtifactRemovesLinkFromSnapshot`, `ProjectBoardStoreTests.testProjectBoardViewModelCreatesProjectArtifactAndNotifies`, `ProjectBoardStoreTests.testProjectBoardViewModelDeletesProjectArtifactAndNotifies` |
| Project Overview accessibility | Task snapshot、Local Suggestions、ArtifactsのCRUD入口にaccessibility identifier / label / hintを付け、Overviewからも支援技術でtask open、task create、suggestion open/unblock、artifact track/removeへ入れる。 | `Sources/SuisuiApp/Views/ProjectBoardView.swift` | `AppExperienceSourceTests.testProjectOverviewActionsAreAccessibleCrudEntryPoints` |
| Review Execute artifact作成 | Action Planのfilesystem artifact作成が `projectId` / `taskId` を持つ場合、作成ファイルと同時にlocal SQLite artifact linkを作り、Project OverviewのArtifactsへ戻す。 | `Sources/SuisuiCore/Tools/SystemTools.swift`, `Sources/SuisuiCore/Tools/SystemToolClients.swift`, `Sources/SuisuiApp/Composition/RuntimeToolCompositionFactory.swift` | `SystemToolTests.testFileSystemToolPersistsCreatedArtifactLinkWhenProjectIDIsProvided`, `AppExperienceSourceTests.testRuntimeAppCompositionDoesNotUseDemoOrInMemorySuccessPath` |
| Inbox capture / triage | MenuBar Quick AddまたはInbox headerから実タスクを作り、item選択後にMake Task、Make Project、Schedule Today、Review Laterを1クリックで実mutationへ送る。 | `Sources/SuisuiApp/Views/MenuBarPanel.swift`, `Sources/SuisuiApp/Views/ProjectWorkflowInboxView.swift`, `Sources/SuisuiApp/Views/ProjectWorkflowSharedViews.swift`, `Sources/SuisuiCore/App/ProjectBoard.swift` | `AppExperienceSourceTests.testMenuBarPanelProvidesFastInboxCaptureWithRuntimeBoardViewModel`, `ProjectBoardStoreTests.testProjectBoardViewModelQuickCapturesInboxTaskAndNotifies`, `ProjectBoardStoreTests.testProjectBoardViewModelQuickCapturePersistsToSQLiteInbox`, `ProjectBoardStoreTests.testProjectBoardViewModelInboxClassificationShowsFeedbackAdvancesSelectionAndUndo`, `ProjectBoardStoreTests.testSQLiteBoardStorePersistsInboxClassificationUndo` |
| Today planning | sidebarから1クリックでdue/overdue、focus suggestion、time blockを確認する。 | `Sources/SuisuiApp/Views/ProjectWorkflowTodayView.swift`, `Sources/SuisuiCore/App/ProjectBoard.swift` | `AppExperienceSourceTests.testTodayWorkflowShowsRecommendationDueCountsAndTimeBlocks`, `ProjectBoardStoreTests.testProjectBoardViewModelBuildsDeterministicTodayPlanWithTimeBlocks` |
| Settings overview / Theme | macOS app menuまたは`Command+,`からSettingsを開き、Status OverviewはOverview tab、Theme segmentはAppearance tabへ集約する。Project Boardのサイドバー下/右上とMenuBarPanel右上にはTheme/Settings controlを置かない。 | `Sources/SuisuiApp/SuisuiApp.swift`, `Sources/SuisuiApp/Composition/SettingsRuntimeFactory.swift`, `Sources/SuisuiApp/Views/SettingsView.swift` | `AppExperienceSourceTests.testSettingsSurfaceStartsWithStatusOverviewForCoreOperationalAreas`, `AppExperienceSourceTests.testAppearanceSelectionIsConfiguredOnlyFromSettings`, `AppExperienceSourceTests.testProjectBoardSidebarAndToolbarDoNotHostThemeControls`, `AppExperienceSourceTests.testMenuBarPanelDoesNotHostSettingsOrThemeControls` |
| AI Provider readiness row | Provider picker直下に選択中providerの状態、smoke readiness、次の操作を表示し、API keyやlocal executionの不足を詳細field前に分かるようにする。 | `Sources/SuisuiApp/Views/SettingsView.swift` | `AppExperienceSourceTests.testAISettingsTabShowsSelectedProviderReadinessBeforeProviderFields` |
| AI Provider readiness summary | AI tab内に全providerの状態を短いsummaryとして表示し、provider切替なしでKeychain/API/local executionの不足を把握できるようにする。 | `Sources/SuisuiApp/Views/SettingsView.swift`, `Sources/SuisuiCore/App/AppSettings.swift` | `AppExperienceSourceTests.testAISettingsTabShowsSelectedProviderReadinessBeforeProviderFields`, `AppSettingsTests.testAppSettingsViewModelBuildsProviderReadinessRowsWithoutSecrets` |
| AI provider設定 | provider pickerの選択を自動保存し、選択中providerのfieldだけを表示する。 | `Sources/SuisuiApp/Views/SettingsView.swift`, `Sources/SuisuiCore/App/AppSettings.swift`, `Sources/SuisuiCore/App/LLMProviderCatalog.swift` | `AppExperienceSourceTests.testAISettingsTabShowsOnlySelectedProviderFields`, `AppSettingsTests.testAppSettingsViewModelPersistsProviderSelectionWhenSelected` |
| MCP接続確認 | Settings内のserver rowから対象serverを2クリックでCheckし、Picker切替を不要にする。 | `Sources/SuisuiApp/Views/SettingsView.swift`, `Sources/SuisuiCore/ExternalMCP/MCPRegistration.swift` | `AppExperienceSourceTests.testSettingsSurfaceShowsInlineMCPServerRowsWithCheckActions`, `ExternalMCPTests.testExternalMCPSettingsViewModelChecksSpecificRegistrationFromInlineRow` |
| MCP paid execution boundary row | 登録編集前にPro実行価値、Freeで可能な登録/接続確認、tools/call前のentitlement/approval/policy境界を表示し、課金状態が危険toolを自動許可しないことを示す。 | `Sources/SuisuiApp/Views/SettingsView.swift`, `Sources/SuisuiCore/ExternalMCP/MCPExecution.swift` | `AppExperienceSourceTests.testMCPSettingsTabSurfacesPaidExecutionBoundaryBeforeRegistrationEditing`, `ExternalMCPTests.testExternalMCPExecutionRequiresPaidEntitlementBeforeToolCall`, `ExternalMCPTests.testPaidEntitlementDoesNotBypassDangerousOrApprovalGuards` |
| Sync gate | Free userはExternal Sync開始前にdomain層で止め、Proでもbackend未構成ならtoggleをdisabledにしてmock successにしない。backend設定済みのnetwork failureは`Failed`とLast Attemptを残し、`Ready`へ戻して成功のように見せない。 | `Sources/SuisuiApp/Views/SettingsView.swift`, `Sources/SuisuiCore/App/SyncService.swift`, `Sources/SuisuiCore/App/Entitlements.swift` | `AppExperienceSourceTests.testSettingsSurfaceShowsSyncGateWithoutMockSuccessPath`, `SyncEntitlementTests.testSyncServiceFreeStartFailsBeforeNetworkClientIsReached`, `SyncEntitlementTests.testSyncServiceProWithoutBackendDoesNotReturnMockSuccess`, `SyncEntitlementTests.testSyncSettingsViewModelAllowsProToggleOnlyWhenBackendIsConfigured`, `SyncEntitlementTests.testSyncServiceConfiguredBackendRecordsNetworkFailureInsteadOfReturningReady`, `SyncEntitlementTests.testSyncSettingsViewModelShowsFailedStateAfterNetworkFailure` |
| Sync paid value row | Sync toggle前にPro価値、Freeのlocal-only境界、backend未構成時のno-upload状態を表示し、有料機能がdisabled toggleだけに見えないようにする。 | `Sources/SuisuiApp/Views/SettingsView.swift` | `AppExperienceSourceTests.testSyncSettingsTabSurfacesPaidValueAndLocalBoundaryBeforeToggle` |

## プロダクトレビュー

Problem: Suisuiは実働するboardとlocal dataを持ったが、まだ日々のPM cockpitとしてはProject detailの文脈整理が弱かった。

User pull: Project overviewでTask、Artifact、Timeline、Local suggestionが同じ画面にまとまり、Project inspectorで編集、削除、提案適用まで同じ右側の操作面に揃った。

Retention hook: Todayは日次のdefault surfaceに近づき、Project overviewは週次/案件単位の確認面になった。次はkeyboard/focusとスクリーンショット検証を詰め、繰り返し操作の摩擦を減らす。

Monetization: Syncとadvanced MCPのgateは実装済み。Pro価値はSettings Overview Pro Value row、Sync paid value row、MCP paid execution boundary rowで、disabled toggleではなくstatus rowとして見える。

Risk: Artifact追加は絶対パスに限定してworkspace推測を避け、削除もDB linkだけに限定したため、local-firstの安全性は保てている。一方、相対パスやworkspace default連携はまだ未対応なので、次のUI作業はaccessibilityとvisual evidenceを優先する。

## 次の実装候補

1. P11-033: 実機VoiceOverでProject board -> card -> Inline Task Composer -> inspectorのfocus orderを確認する。
2. P11-040: Notion / Todoist / Linear / Motion の実操作メモを追加し、desk researchとの差分だけ更新する。
3. P5/P10: Developer ID signing / notarization / Sparkle appcast のrelease-machine gateを埋める。

## Keyboard (2026-07-07)

Project boardのkanban surfaceにフォーカスがあるとき(タスクカードをクリックすると自動でフォーカスされる)、次のショートカットが使える。テキスト入力中(inline task composer表示中、またはinspectorのfield編集中)はすべて無効になり、文字はそのまま入力欄へ渡る。

| Key | 操作 |
| --- | --- |
| `J` / `↓` | ボードの表示順(列の左→右、列内の上→下)で次のタスクを選択 |
| `K` / `↑` | 同じ表示順で前のタスクを選択 |
| `E` | 選択中タスクのtask inspectorを開く |
| `D` | 選択中タスクを完了にする(カードのstatus controlsと同じ`moveTask(.done)`経路。繰り返しタスクは次回occurrenceが作られる) |
| `1` / `2` / `3` | 選択中タスクの優先度をLow / Medium / Highに設定(既存の`updateSelectedTask`経路) |
| `⌘K` | コマンドパレット(destinations、projects、smart lists、Inboxへのタスク作成) |

順序ロジックは`ProjectBoardKeyboardNavigation`(SuisuiCore)にあり、`ProjectBoardKeyboardNavigationTests`で検証する。キーのUI配線自体はunit testでは検証できないため、ボードにフォーカスがある状態での手動確認を対象とする。

### Smart Lists

Sidebarの`Smart Lists` sectionにpreset(`Due this week`、`High priority`、`Overdue`)と保存済みリストが並ぶ。`New Smart List…`でstatus/priority/due-within/overdue/検索テキストを組み合わせたフィルタを保存でき、選択するとboard detailに一致タスクのflat listが出る(Todayと同じrow componentを再利用)。選択は`selectedDestination`とは独立した`selectedSmartListID`で管理し、どちらか一方だけがアクティブになる。

## UX review fixes (2026-07-27)

Follow-up to a product-level UI/UX review. Findings are grouped by whether the
fix shipped in this pass.

### 修正済み

| 指摘 | 修正内容 | 実装 |
| --- | --- | --- |
| 承認面が `key: value` のJSONダンプだった | Plan引数を「ラベル: 値」の行として描画する。日付はロケール表示、内部IDは末尾へ降格。`riskLevel >= .write` は全項目を省略なしで表示する。全文は `accessibilityValue` にも載り、tooltipだけの経路ではなくなった。 | `Sources/SuisuiCore/Review/ReviewSession.swift`, `Sources/SuisuiApp/Views/ActionReviewPanel.swift`, `Sources/SuisuiApp/Views/VoiceCaptureView.swift` |
| 日付表示が面ごとに違い、生のISO文字列が露出していた | `SuisuiTimestampDisplay` に集約。`ProjectBoardTask.dueLabel` は表示用ラベルを返し、`dueAt` が保存値。Done の `2026-07-09T12:00:00Z` とScheduleの `"E d"` 固定パターンを廃止。 | `Sources/SuisuiCore/App/SuisuiTimestampDisplay.swift` ほか |
| 英語の複数形が壊れていた（`1 open tasks`） | `localizedCount(_:one:other:)` を追加し、主要サーフェスの可算名詞を単複2キーに分離。 | `Sources/SuisuiApp/LocalizedDisplay.swift` ほか |
| Todayに「次の一手」を指す面が4つあった | 内容が「他の候補はMoreにあります」だけの `TodayAISuggestionCard` を削除。焦点面はassistant railに一本化。 | `Sources/SuisuiApp/Views/ProjectWorkflowTodayView.swift` |
| Settings Overviewが状態名だけの折りたたみ2行だった | グループラベルに件数と対象名を表示し、`Needs Attention` は既定で展開。`needsAction` をグレーからattentionトーンへ。 | `Sources/SuisuiApp/Views/SettingsStatusOverviewView.swift` |
| `⌘1`–`⌘4` がInbox分類に割り当てられ、サイドバーにキーボード導線がなかった | `⌘1`–`⌘4` を Today / Inbox / Projects / Review に割り当て、分類は `⌃⌘1`–`⌃⌘4` へ移動（tooltipにキー表示）。 | `Sources/SuisuiApp/Views/ProjectBoardView.swift`, `Sources/SuisuiApp/Views/ProjectWorkflowInboxView.swift` |
| カードのタイトルが1行で切れ、説明文が3行取っていた | タイトルを3行 + `layoutPriority(1)`、説明を2行に。 | `Sources/SuisuiApp/Views/ProjectBoardDetailViews.swift` |
| Projects overviewが全カードに同じ判定ルール文を繰り返していた | ヘッダーの `info.circle` に1回だけ表示。 | `Sources/SuisuiApp/Views/ProjectBoardDetailViews.swift` |
| Assistant Queueが空でも `0 selected` と無効ボタンを表示していた | 行がない間はtriage/batchツールバーを出さない。 | `Sources/SuisuiApp/Views/ProjectWorkflowAssistantQueueView.swift` |
| 音声の信頼度を生の `%` で表示していた | 次の操作が変わる3段階（要確認 / ほぼ確実 / 明確に認識）へ。 | `Sources/SuisuiApp/Views/VoiceCaptureView.swift` |
| 通貨が `USD %.2f` 固定だった | `.formatted(.currency(code: "USD"))` へ。 | `Sources/SuisuiApp/Views/SettingsFeatureViews.swift` |
| Voice placeholderが存在しない場所「Assistant Queue」を案内していた | 「Review › Assistant Queue」と実際の導線名で表記。 | `Sources/SuisuiApp/Views/VoiceCaptureView.swift` |
| Localizable.strings に重複キーが78件あった | 値が同一の重複を削除（en 76件 / ja 59件）。 | `Sources/SuisuiApp/Resources/*.lproj/Localizable.strings` |

### 未修正（判断が必要）

| 指摘 | 未修正の理由 |
| --- | --- |
| Approve と Run が別ウィンドウ、かつAssistant QueueがReviewの2階層下 | 安全境界の設計判断。実行ゲートを音声ウィンドウへ広げるか、キューを横断パネルにするかはプロダクト側の合意が要る。 |
| ja catalog に値が食い違う重複キーが17件 | どちらの訳を採るかは翻訳判断。特に `"Suisui"` が `"すいすい"` に上書きされており（後勝ち）、製品名の表記方針を決める必要がある。対象キーは `Suisui` / `Welcome to Suisui` / `Add to Inbox` / `%d tasks` / `%d tokens` / `Reopen` / `Create task` / `Push branch` / `Create pull request` / `Review pull request` / `Merge pull request` ほか。 |
| Task card metadata chip が `maxWidth: .infinity` の塗りつぶしで入力欄に見える | `ProjectBoardMetadataLayoutSourceTests` が hosted visual runner での描画実績としてこの形を固定している。visual runnerを回せない環境では安全に変更できない。 |
| グローバルホットキーが ⌥Space 固定でリマップUIがない | ランチャーとの競合時に回避手段がないが、設定UI・永続化・競合検知を含む機能追加になるため別PR。 |
| 多カウント文字列（`%d tasks, %d open, %d done, …`）の複数形 | 主に分析系・AX文字列。2キー方式では組み合わせ爆発するため `.stringsdict` 導入時にまとめて対応する。 |

## 戦略レビュー反映 (2026-07-27, 第2弾)

事業戦略レポート（Evidence-backed Execution OS / Public Alpha 4週間で Design
Partner 20人）を基準に前回の指摘を組み替えた結果の修正。判断軸は「moatを可視化
しているか」と「20人が週次で残るか」の2点。

| 指摘 | 修正内容 | 実装 |
| --- | --- | --- |
| Done画面が habit metric（Streak / Heatmap / Best Day / Peak Time）を表示していた | 削除。「TaskをDone ≠ 約束を果たした」が製品の中核主張である以上、活動量スコアは誤ったメンタルモデルを毎日教育してしまう。完了件数のカウントは残す。 | `Sources/SuisuiApp/Views/ProjectWorkflowDoneView.swift` |
| Assistant Queue が Review hub の最後（Automation節）にあり、音声フローの終着点が最も遠かった | `Approve and Run` 節として先頭へ。承認後にRunへ到達できないと、撤退判断のデータ（「Outcomeまで追跡されない」）が導線起因なのか仮説否定なのか区別できなくなる。 | `Sources/SuisuiApp/Views/ProjectBoardReviewHubView.swift` |
| Receipt が「Automation Activity / Inspect AI usage」というIT管理者の言葉で埋まっていた | `Execution Record`（実行の記録）へ改名し `Work` 節へ。Evidence Provenance が moat なら、ユーザーの言葉で名乗る必要がある。 | `ProjectBoardReviewHubView.swift`, `ProjectWorkflowAutomationActivityView.swift` |
| Onboarding が `Capture → Today → Complete` を教えていた | `Promise → Review and Run → Deliver` へ。前者はレポート §4.1 が「コモディティ化リスク：非常に高い」と判定した機能そのもので、初回30秒で差別化を説明できていなかった。 | `Sources/SuisuiApp/Views/OnboardingWelcomeView.swift` |

### 未着手（意図的）

| 指摘 | 判断 |
| --- | --- |
| 「待ち」（誰の返事を待っているか）の可視化 | **最優先の欠落**。受託開発者にとって最頻の停止状態だが、Today にも Overdue にも Done にも出ない。`blocked` はステータス値のみで相手も期限も持てない。ただしDBマイグレーションを伴うため、ビルド検証できない状態では入れない。Public Alpha計測開始前に別PRで必要。 |
| 納品/検収の状態 | `ArtifactRecord` はファイル存在監視であり、送付・レビュー・修正・検収の状態を持たない。同上。 |
| 承認画面への Scope / Policy / 取り消し可否 の表示 | Action Authority の本体。#419 / #420 の実装待ち。 |
| DoneAnalyticsSummary の `streakDays` 等のモデルフィールド | UIからは外したがCore側は残置。削除は `ProjectBoard.swift` とテストに広く波及するため、ビルド検証できる環境で行う。 |
| ⌥Space のリマップUI | 設定UI・永続化・競合処理を含む機能追加。 |

### 計測上の注意

現行ビルドには Outcome を追跡する導線がないため、撤退条件「Task生成だけ使われ、
Outcomeまで追跡されない」は**仮説の正否にかかわらず必ず成立する**。4週間の計測を
始める前に、「待ち」または「納品/検収」のいずれかを押せるボタンとして実装する必要が
ある。

## Waiting-on 導線 (2026-07-27, 第3弾)

戦略レビューで「最優先の欠落」と判定した**「待ち」の可視化**を実装した。

### 問題

受託開発者にとって最頻の停止状態は「顧客の返事待ち」だが、これは製品上どこにも
出なかった。

- 自分の次のアクションではない → **Today に出ない**
- 期限超過ではない → **Overdue に出ない**
- 完了でもない → **Completed に出ない**

`blocked` はステータス値でしかなく、相手も待ち開始日も持てないため、「誰が・
どれだけの期間、何を滞留させているか」に答えられなかった。

### 実装

| 層 | 内容 |
| --- | --- |
| Schema | migration `0026_add_task_waiting_on`（`tasks.waiting_on` / `tasks.waiting_since` + 部分index） |
| Model | `ProjectBoardTask.waitingOn` / `.waitingSince` / `.isWaiting` / `.waitingDayCount(on:calendar:)` |
| Store | `ProjectBoardStore.setTaskWaiting(id:waitingOn:)`。`waiting_since` は待ち開始時のみ `COALESCE` で刻印し、無関係な保存で時計をリセットしない |
| ViewModel | `ProjectBoardViewModel.waitingTasks`（待ちが長い順）、`setTaskWaiting(taskID:waitingOn:)` |
| UI | Today の `TodayWaitingPanel`（相手・プロジェクト・経過日数、3日以上でattentionトーン）、Task inspector の `Waiting` セクション |

### 設計判断

- **`status` とは独立**にした。進行中でもレビュー待ちはあり得るし、`blocked` は
  相手のいない技術的ブロッカーを指すこともある。両者を同一視しない。
- **待ちの保存は Save Changes と分離**した。待ちの開始・解除は数秒の思いつきで
  起きるので、編集途中の他フィールドを巻き込んだり失ったりしてはいけない。
- **`waitingOn` は自由テキスト**。Person / Client エンティティはまだ存在せず、
  個人利用者の相手は多くの場合DBの行ではなく名前や社名である。
- **経過日数が不明なら何も言わない**。`waiting_since` が無い/壊れている場合は
  `nil` を返し、知らない期間をUIに主張させない。

### 計測上の注意（更新）

前回「Outcomeを追跡する導線がないため撤退条件が必ず成立する」と記録したが、
`Waiting on` の設定・解除は**押せるボタンとして存在するようになった**。4週間の
計測では、Task生成数だけでなく `setTaskWaiting` の利用と待ちの解除率を見ること。
納品/検収の状態は引き続き未実装。
