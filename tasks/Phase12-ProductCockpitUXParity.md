# Phase 12: Product Cockpit UX Parity

目的は、現在の Project Board / Voice Command / Settings / MCP / Sync / Privacy の実装済み機能を保持したまま、`ui-samples/01.png` から `ui-samples/07.png` で示された日次運用、Inbox分類、Project俯瞰、Schedule、Done分析、Settings連携の不足を実装タスクへ分解すること。

このPhaseは「見た目を似せる」ためのUI作業ではない。Suisuiの強みである local-first、BYOK、Keychain、approval-first、MCP safety boundary、Free local-only / Pro gate を崩さず、個人PMが毎日開く cockpit として画面の役割を再整理する。

## Current Function Preservation

既存画面の機能は削らない。

| 既存画面 | 保持する機能 |
| --- | --- |
| Project Board | SidebarのInbox / Today / Projects、Board / List / Overview、Task作成、Task status移動、drag/drop、Inspector編集、Project完了/Archive/Delete、Artifact link CRUD、Terminal panel、Import/Export、Voice Command入口、Settings入口 |
| Inbox | Quick Add、未処理task表示、Make Task、Make Project、Schedule Today、Review Later、Undo、次item自動選択、row完了toggle |
| Today | due/overdue表示、focus suggestion、30分time block、row完了toggle、Task inspector接続 |
| Project Detail | Progress、Task snapshot、Artifacts、Timeline、Local Suggestions、Board/List切替 |
| Voice Command | Text command、Record/Stop、STT、Action Plan生成、Review Execute導線、Planning audit |
| Settings | Overview / Appearance / AI / MCP / Sync / Privacy tab、Provider readiness、Keychain保存、MCP server登録/接続確認/Tool permission/Audit、Sync gate、Pro value row、Privacy/Watcher |
| Menu Bar | Project Board入口、Voice Command入口、Quick Add、summary表示 |

## Screen Role Architecture

| 画面 | 役割 | 主な成功体験 | 避けること |
| --- | --- | --- | --- |
| Menu Bar Quick Add | 画面遷移なしの最速capture | 2クリック以内でInboxへ保存される | 詳細編集やAI判断を詰め込まない |
| Inbox | 未整理入力のtriage queue | 音声/手入力/AI解釈を1件ずつ整理し、次itemへ進める | Project作業や分析を混ぜない |
| Today | 今日実行する仕事のcockpit | 今日やる順番、理由、時間枠が1画面で分かる | 長期Project分析を混ぜない |
| Projects | 複数Projectのportfolio overview | リスク、進捗、次アクションを横断比較できる | 個別タスク編集を主目的にしない |
| Project Detail | 1Projectの実行管理 | Task、Artifact、Timeline、Milestone、AI提案を同一文脈で扱う | 全Project横断の分析を混ぜない |
| Schedule | 時間割とCalendar適用前確認 | 未スケジュール作業を時間枠へ配置し、外部Calendarへ出す前に確認できる | 自動確定や外部削除をしない |
| Done | 振り返りと継続利用の分析 | 完了実績、傾向、streak、次週改善が分かる | vanity metricだけを表示しない |
| Voice Command | 自然文/音声からAction Planを作る実行前review | 曖昧な入力を構造化し、承認前に安全に確認できる | Inboxの恒久保存場所にしない |
| Settings | 接続、課金境界、プライバシー、provider設定 | 接続状態と次に必要な操作が分かる | 作業画面の中に設定UIを重複させない |

## Click Budget

| 機能 | 目標クリック数 | 入口 | 補足 |
| --- | ---: | --- | --- |
| Menu Bar Quick Add | 2 | menu bar icon -> Quick Add -> Add | 既存を維持 |
| Inbox quick add | 2 | sidebar Inbox -> Quick Add | 既存を維持 |
| Voice memo capture to Inbox | 3 | sidebar Inbox -> Record -> Stop | 文字起こし後はInbox itemとして残す |
| Inbox item分類 | 2 | item選択 -> action | 既存を維持し、音声itemにも適用 |
| Today確認 | 1 | sidebar Today | 既存を維持 |
| Today focus開始 | 2 | Today -> Start Focus | time block / recommended taskから開始 |
| Today blockをScheduleへ送る | 2 | Today -> Schedule Draft | 外部Calendarへは送らずdraft化 |
| Projects一覧確認 | 1 | sidebar Projectsまたはtoolbar segment | 新規画面 |
| Project作成 | 1 | sidebar Add Project | 既存を維持 |
| Project詳細確認 | 1 | project row | 既存を維持 |
| Project risk / next action確認 | 1 | Projects一覧またはProject Overview | card上で見える |
| Task作成 | 2 | Project -> Add Task -> Add | 既存を維持 |
| Task status移動 | 1または1 drag | card button / drag | 既存を維持 |
| Schedule確認 | 1 | sidebar Schedule | 新規画面 |
| 未スケジュールtask配置 | 2 | task row -> time slot | dragの場合は1 drag |
| Calendar適用 | 3 | schedule draft -> Apply -> confirm | approval-firstのため確認必須 |
| Done確認 | 1 | sidebar Done | 新規画面 |
| 完了task再オープン | 2 | Done row -> Reopen | 破壊的ではないが履歴文脈を保つ |
| Settings状態確認 | 1 | Command+, | 既存を維持 |
| Provider設定 | 2-3 | Settings AI | 既存を維持 |
| MCP接続確認 | 2 | Settings MCP -> Check | 既存を維持 |
| Sync状態確認 | 1 | Settings Overview | 既存を維持 |
| Calendar / Reminder接続状態確認 | 1 | Settings Overview / Integrations | 新規status tile |
| Data location確認 | 1 | Settings Privacy | default pathを見える化 |

## Sample Gap Matrix

| Sample | 画面 | サンプルにあるが不足しているもの | 優先度 |
| --- | --- | --- | --- |
| `ui-samples/01.png` | Today | 上部AI入力、提案チップ、右詳細のサブタスク/リマインダー/AI提案、focus開始導線 | P1 |
| `ui-samples/02.png` | Inbox | 音声波形/録音item、文字起こし、AI自動解釈、音声itemの分類、メモ追記 | P0 |
| `ui-samples/03.png` | Projects | Project portfolioカード、進捗bar、リスク/health、次期限、最近更新、選択Project summary | P1 |
| `ui-samples/04.png` | Project Detail | Milestone、成果物の状態操作、Gantt風7日Timeline、右AI assistant、Project question入力 | P1 |
| `ui-samples/05.png` | Schedule | 週カレンダー、未スケジュールtask、AI schedule draft、集中度予測、Calendar適用前確認 | P0 |
| `ui-samples/06.png` | Done | 完了統計、streak、heatmap、時間帯/曜日分析、完了task履歴、AI振り返り | P2 |
| `ui-samples/07.png` | Settings | TTS、Calendar/Reminder接続UI、Data location picker、STT provider状態、通知詳細、連携status overview | P1 |

## P12-001: Inbox voice memo item model

### Context

`ui-samples/02.png` はInboxを「未整理入力の保管場所」として扱い、音声入力、文字起こし、自動解釈、分類を同じ画面で完結している。現行は `Voice Command` が別windowで、録音後の内容はAction Plan生成に寄っており、Inboxの永続itemとして扱う体験が弱い。

### Scope

- 対象: `Sources/SuisuiCore/Voice`, `Sources/SuisuiCore/App/ProjectBoard.swift`, `Sources/SuisuiApp/Views/ProjectWorkflowInboxView.swift`, `Sources/SuisuiApp/SuisuiApp.swift`
- `ProjectBoardTask` へ音声capture由来の表示metadataを追加するか、Inbox専用の `InboxCaptureRecord` を追加する。
- 録音ファイルpath、duration、transcript、AI解釈summary、source kindを扱う。
- 音声ファイルはApplication Support配下に保存し、API keyやtranscriptをログに出さない。

### Where To Improve

- Inbox footerの分類actionは維持し、選択中itemの右/下 detail panel に音声情報を表示する。
- `Voice Command` はAction Plan生成専用として残し、Inboxからの音声captureは「保存して後で分類」を主導線にする。

### How To Improve

- Coreに永続modelとstore protocolを先に追加する。
- STT成功時はtranscriptをInbox item detailとして保存する。
- STT失敗時も録音itemは残し、再文字起こしactionを出す。
- AI自動解釈は任意で、失敗しても分類操作をブロックしない。

### Screen Design

- Inbox header: Quick Add text field、Record button、filter segmented control。
- Center list: source icon、title/transcript preview、created time、classification status。
- Detail panel: waveform placeholder、duration、transcript、AI interpretation、memo field、classification action buttons。

### UX

- ユーザーは録音後に「どこへ行ったか」を探さない。録音停止後、Inbox先頭にitemが残る。
- 文字起こし中はitem row上にprogressを出し、画面遷移しない。
- 分類後は既存のUndo/next selectionを音声itemにも適用する。

### Click Path

| 操作 | クリック数 |
| --- | ---: |
| Inboxを開く | 1 |
| 録音開始からInbox保存 | 2: Record -> Stop |
| 保存済み音声itemを分類 | 2: item -> action |
| 文字起こし再実行 | 2: item -> Retry Transcription |

### Tests First

- [x] `ProjectBoardStoreTests` または新規 `InboxCaptureStoreTests` に音声capture保存/読込/削除を追加する。
- [x] STT失敗時も録音itemが残ることをfakeで固定する。
- [x] Inbox分類後のUndo/next selectionが音声itemでも維持されることをテストする。
- [x] transcriptやfile pathがplanning audit / error logへ漏れないことをsecurity testで確認する。

### Acceptance Criteria

- [x] 録音itemがInboxに永続化される。
- [x] transcript、duration、source kind、classification statusがUIに出る。
- [x] 既存の手入力Inbox分類機能が退行しない。
- [x] `Voice Command` のAction Plan生成導線が残る。

### Non-goals

- 音声波形の高精度描画。
- 外部クラウドへの音声同期。
- 自動でTask/Projectへ確定する処理。

## P12-002: Inbox triage filters and interpretation detail

### Context

`ui-samples/02.png` は「すべて / 音声 / AI提案 / 手動追加 / 未整理」のfilterで連続triageを支えている。現行Inboxは未処理task一覧と分類actionはあるが、sourceや解釈状態で絞り込めない。

### Scope

- 対象: `ProjectWorkflowInboxView.swift`, `ProjectBoardViewModel`, Inbox capture model。
- Inbox item source、interpretation status、classification statusをqueryできるようにする。
- 既存のTask化/Project化/Schedule Today/Review Laterを維持する。

### Where To Improve

- Inbox listの上部にsegmented filterを置く。
- 選択中itemのdetail panelにAI解釈結果とmemoを置く。

### How To Improve

- Filter stateはViewに持ち、永続化はしない。
- Store queryはまず全件loadで十分。件数が増えたらdomain queryへ切り出す。
- AI解釈はAction Planとは分離し、分類候補を表示するだけにする。

### Screen Design

- Header: title、count、Quick Add、Record。
- Filter row: All / Voice / AI Suggested / Manual / Unprocessed。
- List: rowにsource badge、confidence、age。
- Detail: Transcript、Interpretation、Memo、Actions。

### UX

- Inboxは「次に処理すべき未整理item」を先頭に出す。
- Filterを切り替えても選択中itemが消える場合は、次の該当itemを自動選択する。
- `Review Later` はitemを消さず、later bucketへ移す。

### Click Path

| 操作 | クリック数 |
| --- | ---: |
| 未整理だけを見る | 2: Inbox -> Unprocessed |
| 音声だけを見る | 2: Inbox -> Voice |
| 選択itemにmemo追記 | 2: item -> memo field |
| AI解釈からTask化 | 2: item -> Make Task |

### Tests First

- [x] filter別に件数と表示対象が変わるViewModel test。
- [x] filter後のselection fallback test。
- [x] AI解釈が未生成でも分類actionがdisabledにならないtest。

### Acceptance Criteria

- [x] 5種類のfilterでInbox itemを絞れる。
- [x] detail panelでtranscript / interpretation / memoを確認できる。
- [x] 既存Inbox quick addと分類actionが同じクリック数で使える。

### Non-goals

- 複数item一括分類。
- LLMによる自動確定。

## P12-003: Today command cockpit

### Context

`ui-samples/01.png` はTodayを単なる期限一覧ではなく、今日やる順番、AI提案、時間ブロック、詳細確認をまとめた画面として描いている。現行Todayはdue/overdue、focus suggestion、time blockがあるが、上部command入力、提案チップ、focus開始、Schedule draftへの接続が不足している。

### Scope

- 対象: `ProjectWorkflowTodayView.swift`, `ProjectBoard.swift`, optional `TodayPlanService`。
- Today専用のcommand barとsuggestion chipsを追加する。
- 現行のdue/overdueとtime block生成は保持する。
- Schedule画面に渡すdraftを作るが、外部Calendar適用はP12-006で扱う。

### Where To Improve

- Today header直下に「何を進めますか」command barを置く。
- Existing `TodaySuggestionPanel` を summary / time blocks / action chips に分ける。

### How To Improve

- Command入力はまずlocal actionだけに限定する: create Inbox item、filter Today、open recommended task。
- AI提案chipはdeterministic ruleで作り、外部LLM未設定でも表示する。
- `Start Focus` はlocal stateで現在focus itemを示すだけにし、通知やCalendar更新をしない。

### Screen Design

- Top: command input、mic shortcut、suggestion chips。
- Center: Today task list、row completion、priority/due chips。
- Right/detail or bottom panel: selected task summary、subtasks placeholder、reminder status、local suggestions。
- Footer: Time Blocks、Schedule Draft action。

### UX

- 朝にTodayを開いたら、最初にやるtaskと理由が見える。
- 「今日やることを増やす」「今から集中する」「予定に並べる」が画面内で迷わない。
- 期限切れは怖がらせるだけでなく、次のactionに接続する。

### Click Path

| 操作 | クリック数 |
| --- | ---: |
| Todayを開く | 1 |
| 推奨taskを開く | 2: Today -> recommended task |
| Focus開始 | 2: Today -> Start Focus |
| Today commandでInbox追加 | 2: type -> Add |
| Time blockをSchedule draftへ送る | 2: block -> Schedule Draft |

### Tests First

- [x] Today commandからInbox itemを作るViewModel test。
- [x] recommendation chipがdue/priority/blockerに応じて安定順序になるtest。
- [x] Start FocusがDB task statusを勝手に変更しないtest。

### Acceptance Criteria

- [x] Today上部にcommand barとsuggestion chipsがある。
- [x] 現行Today list、counts、time blocks、row completionが残る。
- [x] Schedule draftへ渡すactionがある。
- [x] 外部Calendar通信は発生しない。

### Non-goals

- 自動スケジュール確定。
- Pomodoro timer本体。
- サブタスク永続modelの完成。

## P12-004: Projects portfolio overview

### Context

`ui-samples/03.png` はProjectsをportfolioとして見せ、進捗、期限、risk、AI health、最近更新をカードで比較できる。現行はsidebar project listと選択Project detailが中心で、横断比較が弱い。

### Scope

- 対象: `ProjectBoardView.swift`, `ProjectBoard.swift`。
- SidebarのProjects sectionは維持し、detail領域にProjects overview destinationを追加する。
- Project card summaryをdomain extensionまたはViewModelで算出する。

### Where To Improve

- Sidebarに `Projects` aggregate rowを追加するか、toolbar segmentでProjects overviewへ入る。
- 既存project row選択は個別Project detailとして残す。

### How To Improve

- Card summaryはlocal rulesで作る: progress、open/done/blocked、next due、risk reason、last updatedがなければrecent task idで代替。
- AI healthは外部LLMではなく `Local Health` として始める。
- Project cardから個別Project detailへ1クリックで入れる。

### Screen Design

- Header: Projects、filter chips All / Active / Overdue / Completed、sort menu。
- Main: responsive card grid。
- Card: title、status badge、progress bar、next due、task counts、risk summary、next action。
- Side/detail: selected card summary、risks、recent updates、Open Project button。

### UX

- ユーザーは「どのProjectが危ないか」を1画面で判断できる。
- Cardを開く前に、次にやるべきProjectが分かる。
- Project作成/選択/編集の既存導線を邪魔しない。

### Click Path

| 操作 | クリック数 |
| --- | ---: |
| Projects overviewを見る | 1 |
| Project detailへ入る | 2: Projects -> card |
| risk理由を見る | 1: card上に表示 |
| filterを切り替える | 2: Projects -> filter |
| Project作成 | 1: Add Project |

### Tests First

- [x] Project summaryのprogress / risk / next due算出test。
- [x] Sidebarの既存project selectionが退行しないsource test。
- [x] Projects overview cardからProject detailへselectionが移るViewModel test。

### Acceptance Criteria

- [x] Projects overviewで複数Projectを比較できる。
- [x] 個別Project detail、Board/List/Overviewは残る。
- [x] risk/health表示はlocal ruleで説明可能。

### Non-goals

- Team member / owner管理。
- 外部SaaSのrecent updates同期。

## P12-005: Project detail milestones and assistant panel

### Context

`ui-samples/04.png` はProject detailにmilestone、成果物、7日timeline、右AI assistantを置いている。現行Project OverviewにはProgress、Tasks、Artifacts、Timeline、Local Suggestionsがあるが、Milestone概念と質問入力型assistantが不足している。

### Scope

- 対象: `ProjectBoardView.swift`, `ProjectBoard.swift`, optional new `Milestone` store。
- MilestoneはTaskとは別概念にするか、due date付きTask groupとして扱うかをADRまたはタスク内で決める。
- 初期実装はlocal milestone CRUDとProject Overview表示。

### Where To Improve

- Project DetailのOverviewにMilestones sectionを追加する。
- `Local Suggestions` を `Assistant` panelへ発展させるが、既存local suggestion actionは残す。

### How To Improve

- まずMilestone model/storeをTDDで追加する。
- Timelineはdue task + milestoneを同じ時系列に表示する。
- Assistant question inputは外部LLM未設定時にlocal answerを返し、LLMが必要な場合はVoice Command / Review flowに送る。

### Screen Design

- Header: title、progress、due/status badges、primary Add Task。
- Body tabs/sections: Tasks、Milestones、Artifacts、Timeline。
- Right inspector/assistant: next action、risk、ask field、suggested actions。

### UX

- Project detailは「このProjectを進めるための作戦室」になる。
- Milestoneで中間締切が見え、Artifactで成果物の有無が見える。
- Assistantは自動実行せず、提案とReview導線に留める。

### Click Path

| 操作 | クリック数 |
| --- | ---: |
| Project detailを見る | 1 |
| Milestone追加 | 2: Add Milestone -> Save |
| Artifact追加 | 2 | 既存を維持 |
| Assistantに質問 | 2: input -> Ask |
| 提案actionをReviewへ送る | 2: suggestion -> Review |

### Tests First

- [x] Milestone store CRUD test。
- [x] Project snapshotにmilestone summaryが含まれるtest。
- [x] Assistant local suggestionが外部LLMなしで表示されるtest。
- [x] Suggested actionが直接writeせずReviewへ進むtest。

### Acceptance Criteria

- [x] Project detailにMilestoneが表示/追加できる。
- [x] Timelineにmilestoneとdue taskが混在表示される。
- [x] 既存Task/Artifact/Local Suggestionsが削除されない。
- [x] Assistantはapproval-first境界を守る。

### Non-goals

- 複雑なGantt編集。
- 自動Project計画生成の即時実行。

## P12-006: Schedule planning cockpit

### Context

`ui-samples/05.png` はScheduleを週カレンダー、未スケジュールtask、AI提案、集中度予測、スマートリマインダーで構成している。現行はToday time blockがlocal plan止まりで、Schedule専用画面がない。

### Scope

- 対象: new `ScheduleWorkflowView`, `ProjectBoardView.swift`, `ExternalTaskInterop.swift`, `Deadline`。
- SidebarにSchedule destinationを追加する。
- Calendar適用はGoogle Calendar / EventKitに直接確定せず、approval付きdraftとして扱う。

### Where To Improve

- Todayのtime blocksをSchedule draftへ送れるようにする。
- Schedule画面で未スケジュールtaskと週gridを同時に見せる。

### How To Improve

- Coreに `ScheduleDraft`, `ScheduleBlock`, `UnscheduledTaskQuery` を追加する。
- Drag/dropまたはbuttonでtaskをtime slotへ配置する。
- Apply時はReview Executeまたは確認dialogを必須にする。
- Free/Pro/外部Calendar gateをSettingsのSync/Integration状態と矛盾させない。

### Screen Design

- Left: mini calendar、agenda、unscheduled tasks。
- Center: week grid。
- Right: schedule suggestions、focus load、reminder draft、apply summary。
- Banner: external Calendar not connected / approval required / local-only。

### UX

- ユーザーは「今日やること」を「いつやるか」に変換できる。
- 自動配置はdraftとして見せ、確定前に理由と変更点を確認できる。
- CalendarやReminderへのwriteは必ず承認を挟む。

### Click Path

| 操作 | クリック数 |
| --- | ---: |
| Scheduleを開く | 1 |
| 未スケジュールtaskを見る | 1 |
| taskをslotへ置く | 1 drag または 2 clicks |
| AI schedule draft生成 | 2: Generate Draft -> Review |
| Calendar適用 | 3: Apply -> confirm -> Execute |
| Reminder draft作成 | 2: task -> Add Reminder Draft |

### Tests First

- [x] Unscheduled queryがdone/archived/completed projectを除外するtest。
- [x] ScheduleDraft生成がDBを書き換えないtest。
- [x] Apply前にapprovalが必須であるtest。
- [x] Calendar backend未設定時にmock successにならないtest。

### Acceptance Criteria

- [x] Schedule画面がSidebarから1クリックで開く。
- [x] Today time blockと未スケジュールtaskをSchedule draftへ渡せる。
- [x] 外部Calendar writeは承認前に実行されない。
- [x] 既存Todayのlocal time blockは残る。

### Non-goals

- Calendar deletion。
- 自動再配置のバックグラウンド実行。
- 複数Calendar双方向同期。

## P12-007: Done analytics and review

### Context

`ui-samples/06.png` はDoneを完了履歴、streak、heatmap、時間帯分析、AI insightsとして描いている。現行はtask/project completionはあるが、完了を振り返る画面がない。

### Scope

- 対象: `ProjectBoard.swift`, new analytics service, new `DoneWorkflowView`。
- SidebarにDone destinationを追加する。
- 完了日時が不足している場合はmigrationで `completed_at` を追加する。

### Where To Improve

- Completed task/projectを一覧で見られる画面を作る。
- 継続利用に効く指標を最小限で出す。

### How To Improve

- Domain first: completion records、daily counts、weekly counts、streak。
- UIは最初から派手なheatmapを作らず、grid summaryとrecent completed listを先に作る。
- AI insightはlocal ruleから始める。

### Screen Design

- Header: Done、this week count、streak、completion rate。
- Main: recent completed tasks/projects、weekly bar、year heatmap。
- Right: insights、productive day/time、reopen action。

### UX

- ユーザーは「何が進んだか」を確認し、次週の改善に接続できる。
- 完了taskは再オープンできるが、履歴が消えたように見せない。
- 数字だけでなく、次に改善する1つの提案を出す。

### Click Path

| 操作 | クリック数 |
| --- | ---: |
| Doneを開く | 1 |
| 最近完了したtaskを見る | 1 |
| 完了taskを再オープン | 2: row -> Reopen |
| 週別傾向を見る | 1 |
| insightからTodayへ戻る | 2: insight -> Today |

### Tests First

- [x] completed_at migration test。
- [x] Daily/weekly countとstreak算出test。
- [x] Reopen時にtask statusがplannedへ戻るがcompleted historyを保持するtest。
- [x] Done view source accessibility test。

### Acceptance Criteria

- [x] Done画面がSidebarから1クリックで開く。
- [x] 完了履歴と基本統計が見える。
- [x] 既存Done status columnやProject completionが退行しない。

### Non-goals

- クラウド分析。
- 個人情報を外部LLMへ送る分析。

## P12-008: Settings integrations surface

### Context

`ui-samples/07.png` はAI Provider、STT、TTS、通知、Calendar、Reminder、MCP、Privacy、data locationを1画面で扱う。現行SettingsはAI/MCP/Sync/Privacyの実装深度が高いが、TTSやCalendar/Reminder接続状態、data location pickerが弱い。

### Scope

- 対象: `SuisuiApp.swift`, `AppSettings.swift`, EventKit adapters, Deadline/Notification。
- Existing Settings tabsは保持し、OverviewにIntegration statusを追加する。
- TTSは最初はprovider設定UIだけにし、読み上げ実行は非対象にできる。

### Where To Improve

- Overview status tilesに Calendar / Reminder / STT / TTS / Data Location を足す。
- Privacy tabのWorkspace text fieldを安全なdirectory pickerへ発展させる。
- AI tabのSTT provider表示を実装済みprovider境界と合わせる。

### How To Improve

- Calendar/Reminderはpermission status、connected status、last checkを表示する。
- Data location変更はSecurity-scoped bookmark設計を先に決める。
- TTSは `notConfigured` / `notSupportedInThisRelease` を明示し、使えるように見せない。

### Screen Design

- Overview: AI Provider、STT、TTS、Calendar、Reminder、MCP、Sync、Privacy tiles。
- AI tab: LLM provider、STT provider、TTS placeholder。
- Integrations or Privacy tab: Calendar/Reminder permission, notification, data location.
- MCP tab: 既存server rowsを維持。

### UX

- ユーザーはSettingsを開いた瞬間に「何が使えるか / 何が未設定か / 何が未対応か」を理解できる。
- 未対応機能はdisabledでも理由を表示し、mock successにしない。
- 秘密情報やpathは必要以上に表示しない。

### Click Path

| 操作 | クリック数 |
| --- | ---: |
| Settings overviewを見る | 1 |
| Calendar状態確認 | 1 |
| Reminder状態確認 | 1 |
| Data location確認 | 1 |
| Data location変更 | 3: Choose -> select folder -> Save |
| STT provider確認 | 2: Settings -> AI |
| TTS未対応理由確認 | 1-2 |

### Tests First

- [x] Settings source testでOverview tilesが表示されることを固定する。
- [x] Data location validation test。
- [x] Calendar/Reminder permission status mapping test。
- [x] TTSが未実装時に選択可能に見えないtest。

### Acceptance Criteria

- [x] Settings Overviewで連携状態が一覧できる。
- [x] Calendar/Reminder/TTSの未対応や未設定が明確に出る。
- [x] API keyやtokenはKeychainのままで、UserDefaults/SQLite/logへ漏れない。
- [x] 既存AI/MCP/Sync/Privacy tabsが退行しない。

### Non-goals

- TTS実行。
- Calendar/Reminderの双方向同期。
- Settings内での課金購入flow。

## P12-009: Navigation and sidebar information architecture

### Context

Samples全体では、Inbox、Today、Projects、Schedule、Done、Settingsが明確に分かれている。現行SidebarはInbox、Today、Projects配下の個別Projectだけで、ScheduleとDoneがない。

### Scope

- 対象: `ProjectBoardSidebarView.swift`, `ProjectBoardView.swift`。
- Sidebar destinationを Inbox / Today / Projects / Schedule / Done / Project(id) へ拡張する。
- 既存Project row selectionとProject Board detailを維持する。

### Where To Improve

- Sidebarの上部固定sectionに主要workflowを並べる。
- Projects aggregate rowと個別Project rowsを分ける。

### How To Improve

- Destination enum拡張をTDDで固定する。
- selection persistenceの互換性を保つ。未知raw valueはTodayへfallback。
- keyboard shortcutをCommand+1..5に割り当てる場合、既存Inbox classification shortcutと衝突しないようscopeを分ける。

### Screen Design

- Sidebar fixed: Inbox, Today, Projects, Schedule, Done。
- Sidebar Projects section: individual project rows。
- Footer: Show Archived, Add Project。

### UX

- 画面ごとの役割がnavigationに現れる。
- 個別ProjectとProjects一覧を混同しない。
- 既存ユーザーの選択復元が壊れない。

### Click Path

| 操作 | クリック数 |
| --- | ---: |
| Inbox / Today / Projects / Schedule / Doneへ移動 | 1 |
| 個別Projectへ移動 | 1 |
| Add Project | 1 |

### Tests First

- [x] destination raw value互換test。
- [x] Sidebar source test。
- [x] Command shortcut衝突がないことのsource test。

### Acceptance Criteria

- [x] 5つのworkflow画面がSidebarから1クリックで開く。
- [x] 既存Project rowsとAdd Projectが残る。
- [x] 既存selection persistenceが破綻しない。

### Non-goals

- Sidebarの完全カスタマイズ。
- Team workspace navigation。

## P12-010: Visual evidence and click-path audit refresh

### Context

Phase 12は画面役割を増やすため、実装後にスクリーンショット証跡とクリック導線監査を更新しないと、現行機能保持と新規画面の到達性を確認できない。

### Scope

- 対象: `script/capture_ui_evidence.sh`, `docs/release/evidence/ui-screenshots.md`, `docs/ux/click-path-audit.md`, `Tests/SuisuiCoreTests/AppExperienceSourceTests.swift`。
- 新規画面のLight/Dark/System screenshotを追加する。
- Click budgetをこのPhase文書から監査文書へ反映する。

### Where To Improve

- screenshot evidenceにInbox voice detail、Projects overview、Schedule、Done、Settings integrationsを追加する。
- click-path auditに新規画面のクリック数を追加する。

### How To Improve

- 既存capture scriptを拡張し、seed DBに音声item、milestone、schedule draft、completed historyを用意する。
- PNGが低情報量/黒画面でないことを現行と同じgateに通す。

### Screen Design

- Evidenceは実装確認用であり、アプリ画面には出さない。

### UX

- ContributorがUI変更の品質を画像とクリック数でレビューできる。
- Release readinessで「実装したが見えない」を防ぐ。

### Click Path

| 操作 | クリック数 |
| --- | ---: |
| 新規画面の証跡確認 | 0: generated artifact |
| click-path audit確認 | 0: docs |

### Tests First

- [x] screenshot listのsource/evidence test。
- [x] click-path auditが新規画面名とクリック数を含むtest。
- [x] capture scriptがseed DB不足時に失敗するtest。

### Acceptance Criteria

- [x] 新規主要画面のLight/Dark screenshotが残る。
- [x] `docs/ux/click-path-audit.md` にPhase 12画面のクリック数が反映される。
- [x] Release evidence gateが古い画面だけでgreenにならない。

### Non-goals

- 実機VoiceOver証跡の代替。
- 競合hands-on証跡の代替。

## Implementation Order

1. P12-009 Navigation skeletonを先に入れる。空画面でも役割と入口を固定する。
2. P12-001 / P12-002 Inbox voice triageを入れる。毎日のcapture体験に最も効く。
3. P12-006 Schedule cockpitを入れる。Today time blockを外部適用前draftへ接続する。
4. P12-004 / P12-005 Projects portfolioとProject detailを入れる。案件横断と個別実行を分ける。
5. P12-008 Settings integrationsを入れる。連携状態を見える化する。
6. P12-007 Done analyticsを入れる。継続利用と振り返りを足す。
7. P12-010 Evidence/audit refreshで画面品質とクリック数を固定する。

## Exit Gate

- [x] 現行Project Board / Inbox / Today / Voice Command / Settings / Menu Barの既存機能が退行していない。
- [x] `ui-samples/01.png` から `07.png` の不足が、実装済み、後続、非対象のいずれかで説明できる。
- [x] Inbox、Today、Projects、Project Detail、Schedule、Done、Settingsの画面役割がdocsとUIで一致している。
- [x] 主要機能のクリック数が `docs/ux/click-path-audit.md` に反映されている。
- [x] 新規UIはLight/Dark/System screenshotで重なり、空白、黒画面、低情報量を確認している。
- [x] API key、token、音声file path、transcript、Calendar/Reminder dataがログや不要なSQLite/UserDefaultsへ漏れていない。
- [x] 外部Calendar/Reminder/MCP/Sync writeはapproval/gateなしに実行されない。
- [x] `swift test --skip ReleasePipelineTests` と該当source/evidence testsがgreen。

## Self Review Checklist

- [x] 各PRは1画面または1domain modelに閉じ、UI、DB、外部API、release evidenceを不必要に混ぜていない。
- [x] 既存画面のクリック数を悪化させていない。悪化する場合は理由と代替shortcutを `docs/ux/click-path-audit.md` に書く。
- [x] 新規画面は空状態、エラー状態、未設定状態、Free/Pro gate状態を持つ。
- [x] 音声、transcript、Calendar/Reminder、API key、MCP environment referencesはログ、スクリーンショット、UserDefaultsへ漏れない。
- [x] AI/LLMが絡む提案は直接writeせず、Action Plan validationまたはapproval flowへ接続する。
- [x] OSS contributorがfake store / fake adapterでテストを書ける責務境界になっている。
