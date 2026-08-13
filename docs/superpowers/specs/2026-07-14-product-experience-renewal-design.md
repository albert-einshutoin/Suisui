# Suisui Product Experience Renewal Design

- Date: 2026-07-14
- Status: superseded by the implemented design system documented in `docs/ux/design-system.md`
- Source baseline: `main` at `48358d029eb4a6862063443943a5b392398ff275`
- Tracking: #11, #211, #244, #289, #291-#304

## 1. Objective

Suisuiを、初めて使う人には迷いが少なく、必要になれば高度なAI承認実行、計画、連携、自動化まで扱えるmacOSプロダクトへ刷新する。

完成状態では、日常導線を `Today`、`Inbox`、`Projects`、`Review` の4領域に絞る。既存の高度機能は削除せず、文脈、badge、メニュー、Review内section、Command Paletteから必要なときだけ見せる。視覚面は「Calm Signal Desk」を採用し、ネイティブなmacOS構造の上にSuisui固有の静かなSignal表現を作る。

## 2. Chosen Approach

### 採用: 垂直スライスによる段階移行

既存の安全境界を保ち、次の順で移行する。

1. 品質検査を複数ファイル移動に耐えられる形へ変更する。
2. 型付きroute、scene identity、旧保存値の互換変換を導入する。
3. 4領域IAとReview hubへ移行する。
4. Inspector、Toolbar、Today、Settings、Voiceを各feature単位で刷新する。
5. semantic design tokenを各surfaceへ段階適用する。
6. 体験先行Onboardingへ切り替える。
7. ViewとViewModelを、今回触る責務から段階的に分割する。
8. 通常製品routeのruntime、visual、performance、VoiceOver証跡を更新する。

### 不採用

- 巨大Viewを最初に全面rewriteする方式: UX変更、状態所有、永続化、品質検査の回帰原因を分離できない。
- 見た目だけを変更する方式: 入口の多さ、CTA競合、警告壁、window routingの問題を残す。

## 3. Non-Negotiable Invariants

- Calendar、Reminder、Automation、connector write、local shell実行はapproval-firstを維持する。
- Inbox capture、Project/Task CRUD、Undo、execution receipt、redactionを失わない。
- Voice shortcut一回で録音、AI生成、外部writeを自動開始しない。
- 旧destination保存値、通知、Voice deep link、test fixtureを新routeへ安全に移行できる。
- SQLite schemaと外部連携portを今回のUI移行の都合で変更しない。
- macOS 14を最低対応のまま維持する。新しいLiquid Glass APIはavailability分岐し、macOS 14では標準Toolbar/Materialへfallbackする。
- Light、Dark、System、英語、日本語、960/1024/1180/1440幅、keyboard、VoiceOver、Reduce Motionで成立させる。
- recovery UIの成功を通常製品UIの成功として扱わない。
- routing、scene identity、cache/invalidation、presentation policyには「なぜこの境界なのか」をコメントで残す。
- test double、fixture、実ユーザーデータ、secretをproduction sourceやvisual/runtime artifactへ混入させない。

## 4. Navigation and Scene Architecture

### 4.1 Typed route

既存の `ProjectBoardSidebarDestination` は即時削除せず、旧保存値とのcompatibility codecとして残す。新しい画面状態は次の型で表す。

```swift
enum BoardPrimaryDestination: String, CaseIterable, Sendable {
    case today
    case inbox
    case projects
    case review
}

enum ReviewRoute: String, CaseIterable, Sendable {
    case schedule
    case completed
    case automationActivity
    case assistantQueue
}

enum BoardRoute: Equatable, Sendable {
    case primary(BoardPrimaryDestination)
    case project(Int64)
    case smartList(String)
    case review(ReviewRoute)
}

struct ProjectBoardSceneRoute: Equatable, Sendable {
    var destination: BoardRoute
    var inspector: InspectorRoute?
}
```

`@AppStorage` は新規windowの初期route、`@SceneStorage` はwindowごとの現在routeを所有する。Voice、Command Palette、通知、Menu Bar、削除後fallbackは一つのroute reducerを通す。

### 4.2 Legacy migration

| 旧destination | 新route |
| --- | --- |
| `today` | `.primary(.today)` |
| `inbox` | `.primary(.inbox)` |
| `projects` | `.primary(.projects)` |
| `assistant-queue` | `.review(.assistantQueue)` |
| `catch-up` | `.primary(.today)` + Catch Up section focus |
| `schedule` | `.review(.schedule)` |
| `done` | `.review(.completed)` |
| project/smart list | 対応するtyped route。対象消失時はToday |

不明なraw value、削除済みProject/Task/Smart Listは `.primary(.today)` へ安全にfallbackする。

### 4.3 Four primary destinations

Sidebarの常時表示は次の4件だけにする。

- Today: 今日の仕事。Catch Upは未処理があるときだけ内部sectionとして表示する。
- Inbox: captureとtriage。
- Projects: portfolio、各project、Smart Lists、Completed/Archived project。
- Review: Schedule、Completed work、Automation Activity、Assistant Queue。

Reviewは既存機能を削除する統合ではない。旧destinationをReviewのsectionとして保ち、各機能へ最大2操作で到達できるようにする。Assistant Queueの要対応件数はReview badgeで表す。

### Acceptance

- Sidebarのトップレベルが4件で順序が安定している。
- Sidebar rowはnative source-listで、leading icon 1個、title 1行、任意のsecondary 1行以内。
- Catch Up 0件時は場所を取らない。
- Smart ListsはProjects内filterとして到達できる。
- Menu Bar、通知、Voice、Command Paletteの既存導線が正しいwindowの正しいrouteへ到達する。
- 複数Project Board windowが同じopen requestを重複処理しない。
- windowごとのroute、selection、Inspector stateが混線しない。

## 5. Today Experience

### 5.1 One primary action

pure presentation policy `TodayPrimaryActionPresentation` を導入する。

優先規則:

1. 推奨タスクあり: `Start Focus`
2. 推奨タスクなし、command入力あり: `Add to Inbox`
3. タスクなし、入力なし: `Add a task for today`
4. 実行可能な主操作がない状態: primary actionを表示せず理由を示す

最初のviewportに `.borderedProminent` は最大1個とする。`today-start-focus`、rail内Focus、AI suggestion内Focusを同時表示しない。Read Aloud、Edit、Subtask、Reminder Draft、Schedule Draft、Show Done、Optimize Flowは二次操作またはcontext menuへ移す。

### 5.2 Contextual Catch Up

期限超過、未処理Inbox、承認待ちなど、実際に追いつく対象がある場合だけToday内へCatch Up sectionを出す。0件時はsection自体を隠す。表示理由と次の1操作を明示する。

### Acceptance

- empty、normal、draft、focusの全状態で主CTAは0または1個。
- 推奨対象、理由、主CTAがスクロールせず読める。
- Focus開始だけでtask status、Calendar、Reminderを書き換えない。
- AX順序が見出し、推奨対象、理由、主CTA、二次操作となる。
- unrelatedなMCP、Receipt、Automation更新でToday全体を再publishしない。
- Today CPU convergenceと日本語1024px表示がruntimeで成立する。

## 6. Review Hub

Reviewには `Schedule`、`Completed`、`Automation Activity`、`Assistant Queue` のsection navigationを置く。

- Schedule: mini calendar、選択日agenda、workload、draftを一つの流れに統合する。同じ情報を重複表示しない。
- Completed: 完了実績とrecapを中心にする。
- Automation Activity: AI usage、receipt、実行履歴をCompletedから分離する。
- Assistant Queue: Approve/Defer/Reject/Runとreceiptを維持する。

外部writeやexecutionの承認境界、DB postcondition、receipt生成は既存と同じである。

## 7. Voice Experience

Voiceを次の2モードに明確に分ける。

- Record once: 大きな主マイク。録音、transcription、reviewの一回入力。
- Hands-free mode: 高度な連続認識。provider/cost/privacyの境界を説明し、二次操作として置く。

空白のみを含む入力では Save to Inbox、Ask、Generate Planを無効にする。Generate Planのsource of truthは `viewModel.canGeneratePlan` とし、disabled理由をvisible text、help、AX hintで一致させる。example chipは入力だけ行い、自動実行しない。

生成結果の近くにPreview、Retry、Approve、Defer、Rejectを置く。Approve後はReviewのAssistant Queueへ対象item付きでdeep linkする。Runは明示的な別操作のまま維持する。

### Global shortcut

Option+Spaceはprocess-wideに一度だけ登録するproduction adapterをApp targetへ置く。登録済み、未登録、競合、利用不可を型で表示し、失敗時は `Shift+Command+V` のin-app fallbackを示す。既存Voice windowがあれば新規生成せずactivateする。

### Acceptance

- empty/whitespace/recording/transcribing/listening状態でGenerate Planが誤って有効にならない。
- Record onceとHands-freeがvisible labelとVoiceOverで区別できる。
- Inbox、plan preview、Assistant Queueの行き先を実行前に理解できる。
- shortcut登録は重複せず、解除後はhandlerが発火しない。
- shortcut競合をfakeのRegistered表示へ変換しない。
- 複数windowでVoice requestとReview deep linkが一度だけ処理される。
- shortcutから録音、AI、外部writeを自動開始しない。

## 8. Settings Readiness

readinessを次の意味で型付けする。

```swift
enum SettingsReadinessState: Equatable, Sendable {
    case ready
    case setupWhenNeeded
    case checking
    case needsAction
    case blocked
    case unsupported
}
```

Overviewの表示順:

1. Ready now
2. Set up when used
3. Needs attention
4. Advanced（高度設定ON時のみ）

各rowは状態、説明、typed next actionを持つ。通常の未設定やpermission未要求はneutralな `Set up when used` とし、実障害だけをattention/dangerにする。lazy未読込を `Unavailable` と表示しない。

Google Calendar OAuth、AI provider Keychain/API key、notification、Calendar/Reminder permission、STT/TTS、MCP、Sync、Privacy、Data Locationを意味上分離する。Advanced OFF時にMCP、Sync、managed billing、Pro Valueの警告を通常readinessへ混ぜない。

### Acceptance

- 初期Overviewが警告壁にならず、利用可能な機能を先に示す。
- 全rowに直接actionまたは「今は操作不要」の理由がある。
- actionから対象tab/sectionへ直接移動できる。
- unsupported、unchecked、temporarily failed、blockedを区別する。
- check failureはredactedで再試行できる。
- Settingsを開くだけで重いMCP/Sync dependencyを生成しない。
- secretやtokenをUI、log、diagnosticsへ露出しない。

## 9. Native Toolbar and Adaptive Inspector

### 9.1 Toolbar

独自44pt `projectBoardHeaderBar` と `.background(.bar)` を削除し、標準 `.toolbar`、Commands、overflow menuへ移行する。

- Voice: 主要capture entryとしてtoolbarに置ける。
- Search/Command Palette: hierarchy全体に作用する入口。
- Integrations/Automation: 現在のcontextで必要な場合だけ、またはoverflow。
- Settings: app commandを主入口とする。
- Terminal: Developer Modeのoverflowだけに表示する。
- Inspector toggle: selectionがある場合に表示する。

macOS 26では意味のあるgroupingに `ToolbarSpacer` 等をavailability付きで利用できる。macOS 14では標準toolbarで同じ機能を維持する。Liquid Glassはtoolbar/sidebar/control層だけに使い、content cardへ全面適用しない。

### 9.2 Inspector policy

pure policy `InspectorPresentationPolicy` を導入する。

- 960〜1024: 初期closed。明示的なEdit/Open Detailsだけで開く。
- 1180以上: selectionとscene stateに応じてside Inspectorを表示可能。
- Today/Inbox: workflow contentを優先し、Inspectorは明示操作だけで開く。
- narrowへresizeした場合はcontentを潰さず閉じる。再度wideにしても勝手に再openしない。

### Acceptance

- window上部のchromeがnative toolbar 1層だけ。
- 960pxと日本語でclippingや二重toolbarがない。
- utilityへ2操作以内で到達できる。
- workflow主CTAがapp utilityより強く見える。
- compact初期表示でInspectorが開かない。
- close後に別task選択だけで勝手に再表示しない。
- stale selection、削除済み対象、別windowのInspector stateを表示しない。
- VoiceOver focusが閉じたInspectorへ入らない。
- resizeでframe jump、horizontal clipping、不意なwindow resizeがない。

## 10. Calm Signal Desk Design System

独自性は全面glassやdecorative gradientではなく、「AIが静かに次の仕事を知らせるSignal」で作る。

### Semantic tokens

- `SuisuiBrand`: adaptive Solo Blue、Signal Amber。semantic tintだけに使う。
- `SuisuiTypography`: pageTitle、sectionTitle、body、metadata、compactLabel。
- `SuisuiSurface`: canvas、groupedContent、elevatedSelection、assistantSignal。
- `SuisuiBorder`: subtle、selected、attention、danger。
- `SuisuiMotion`: quick、standard、emphasis、Reduce Motion fallback。
- `SuisuiIconMetrics`: compact、standard、feature。
- `SuisuiControlDensity`: compact、standard、prominent。

### Rules

- native sidebar、toolbar、Form、Inspectorをcustom skin化しない。
- contentは読みやすいsolid/adaptive surfaceを使い、glassを重ねない。
- statusは色だけでなくicon、text、shapeを併用する。
- primary action、assistant signal、selection、readinessで同じ意味を同じ表現にする。
- raw status color、匿名radius、匿名card fillの新規追加をsource guardで防ぐ。
- Reduce Motionでは装飾animationを停止する。
- brand色だけでselectionやerrorを表さない。
- 本文の可読性を優先し、個性的な書体は見出しへ限定する。

## 11. Experience-First Onboarding

既存のtransactional/idempotentなLearn Suisui生成処理を再利用し、初回の既定導線を設定先行から価値体験先行へ変える。

1. Welcome
   - Primary: `Try Suisui now`
   - Secondary: `Set up AI first`
   - `Skip` を維持
2. Try Suisui
   - Learn Suisuiを作成
   - 新4領域のTodayまたはProjectsへroute
   - 最初の一つのtask操作を案内
3. Contextual setup
   - AI、microphone、Calendarは実際に使う直前に案内
4. Settingsから `Run Setup Again` を維持

### Acceptance

- API keyやpermissionなしでも60秒以内にProject/Task操作を体験できる。
- ユーザーが選ぶ前にOS permission promptを出さない。
- Learn Suisuiを重複作成せず、途中失敗時に不完全Projectを残さない。
- lesson文言が最終4領域、Toolbar、shortcutと一致する。
- AI未設定でもInbox、Project、Today、Undoを学べる。
- global shortcut未登録時にOption+Spaceを登録済みとして教えない。
- tourを閉じても通常データや設定を失わない。
- Settingsから再実行でき、多windowでも一つのsheetだけを表示する。

## 12. Error, Date, Localization, Accessibility

### Recoverable errors

load不能などwindow全体を使えないfatal errorと、save/check/provider失敗などのrecoverable errorをpresentation policyで分ける。recoverable errorでは現在のboard/task contextを残し、該当操作の近くにredacted messageとRetryを出す。

### Due date

Task editorの自由入力保存を、DatePicker、clear action、locale/timezoneを扱うtyped field stateへ置換する。invalid値ではDBを更新せず、修正方法をinline表示する。

### Localization

static key parityだけでなく、dynamic status、placeholderの型と個数、4領域、Review section、Voice、Settings、Onboardingを英語/日本語で検証する。狭幅でtruncateする場合もhelp/AX valueから全文へ到達できるようにする。

### Accessibility

- icon-only buttonには具体的なlabel/helpを付ける。
- selection state、expanded/collapsed、disabled reasonをName/Role/Valueへ出す。
- focus orderを4領域、Review、Voice、Settings、Onboardingごとに定義する。
- destructive confirmはfocusを閉じ込め、Cancel後はtriggerへ戻す。
- statusを色だけで示さない。
- Reduce Motion時にdecorative transitionを停止する。
- minimum window、keyboard-only、VoiceOverで全主要操作へ到達できる。

## 13. Architecture Boundaries

### 13.1 Quality contract migration first

現行testとscriptは `ProjectBoardView.swift` の物理pathを強く固定している。View抽出前に次を行う。

- `AppExperienceSourceTests` にProject Board surface全体を読むhelperを作る。
- `ReleasePipelineTests` と `ArchitectureBoundaryTests` を複数ファイル対応にする。
- `check_accessibility_preflight.sh` を物理ファイル指定ではなくsurface/anchor集合で検査する。
- ファイル所有の検査と、機能アンカーの検査を分離する。
- 宣言順検査は同じ責務の同一ファイル内だけに限定する。

### 13.2 View extraction order

1. `ProjectBoardSidebarView.swift`
2. `ProjectBoardToolbarContent.swift`
3. `ProjectBoardReviewHubView.swift`
4. Project/Task Inspector leaf views
5. Project portfolio/detail/kanban leaf views
6. routing/interoperability bridge
7. Settings tab viewsとstatus components

ルート `ProjectBoardView` はstate owner、`NavigationSplitView`、sheet/overlay compositionへ縮小する。抽出先を不要にpublic化せずApp target内internalとする。

### 13.3 ViewModel migration

全187 APIを一括変更しない。まずTodayだけをfeature-scoped state/modelへ移す。

- Today ViewはToday stateだけをobserveする。
- store所有者は一つのまま維持する。
- mutation後はTodayとSidebar countだけを明示的にinvalidateする。
- 既存 `ProjectBoardViewModel` APIは互換facadeとして残す。
- extensionへの機械移動だけでprivate stateの可視性を広げない。

### Prohibited refactors

- Redux/TCA等の新規framework導入
- SwiftPM targetの追加や全面再分割
- `ObservableObject` から `@Observable` への全面置換
- workflowごとの独立store owner
- Core private依存の一括可視化
- `AnyView` や汎用Base Viewによる差分隠蔽
- UX、永続化、ViewModel分割を同一コミットで行うこと

## 14. TDD and Verification Matrix

| Slice | First RED | Runtime evidence | Completion evidence |
| --- | --- | --- | --- |
| Typed route/4 IA | route migration、4項目/順序source contract | 4領域en/ja、旧raw value起動 | unit + source + deep link + scene restore |
| Today CTA | `TodayPrimaryActionPolicyTests` | 各seedでenabled primary数が最大1 | Today complete + CPU convergence + visual |
| Review | old destinations→Review mapping | Schedule/Done/QueueをReview経由で操作 | DB postcondition、receipt、approval不変 |
| Voice | UI interaction policy empty=false | empty→入力後enabled、2 mode AX | provider call 0、review→queue |
| Settings | readiness presentation states | fresh install、ready/blocked/unsupported | action routing、redaction、visual |
| Toolbar | custom header不在、semantic item policy | 960/1024/1440 toolbar operation | clipping 0、macOS 14 fallback |
| Inspector | responsive policy | 4幅、open/close/restore | stale focusなし、layout stable |
| Design system | token/source guard | Light/Dark/System/Reduce Motion | reviewed live baselines |
| Onboarding | experience coordinator | fresh HOME、sample、skip、rerun、rollback | 60秒価値体験、SQLite postcondition |
| Error/date | fatal/recoverable、typed due state | injected save failure、en/ja date edit | context保持、DB非更新/更新/clear |
| Accessibility | focus path contracts | unlabeled/generic 0、focus markers | fresh manual VoiceOver evidence |
| Multiwindow/shortcut | coordinator + shortcut lifecycle | exact owned Voice/Board window | duplicate handler/window 0 |

`scripts/ci.sh swiftpm` は全 `swift test` を含まないため、最終検証では必ず別途full suiteを実行する。現行 `ui-runtime` はProject/Task CRUD、layout、Today route中心であり、Inbox、Settings、Voice、Scheduleの個別smokeをrequired laneまたは独立required laneへ追加する。

## 15. Visual and Runtime Evidence

現行33枚だけではOnboarding、Review統合、日本語狭幅を証明できない。最終visual manifestへ次を追加する。

- Review: schedule/completed/automation/assistant queue
- Onboarding: welcome/learn/deferred setup
- Today、Review、Voice、Settingsの日本語1024px
- Inspector compact closed/explicit open
- Settings ready/setup/blocked
- Voice empty/plan review/hands-free

baseline更新はfeature実装と同じ意図のcommitで、capture、人間の画像レビュー、manifest/metadata更新を行う。system appearanceやWindowServer差とapp regressionをfailure categoryで分離する。

最終gate順:

1. 各focused testのRED→GREEN
2. `./scripts/ci.sh swiftpm`
3. `swift test`
4. `./script/check_security_regressions.sh`
5. `./scripts/ci.sh ui-runtime`
6. `./scripts/ci.sh ui-visual`
7. `./scripts/ci.sh ui-performance`
8. fresh manual VoiceOver
9. release readiness report

古いquality status、古いVoiceOver証跡、source string contractだけ、画像差分だけを完了証拠にしない。

## 16. Commit and Delivery Strategy

GitHub Flowのfeature branch上で、次の粒度を基本にコミットする。

1. test: make UI source contracts relocation-safe
2. feat: add typed board route and legacy migration
3. feat: introduce four-destination navigation and Review hub
4. feat: add adaptive inspector presentation policy
5. feat: replace custom header with native toolbar
6. feat: establish one Today primary action
7. feat: make Settings readiness progressive and actionable
8. fix: make Voice empty state and modes truthful
9. feat: add production global shortcut lifecycle
10. fix: route Voice requests to exact Project Board scene
11. feat: expand semantic Suisui design tokens
12. refactor: migrate feature surfaces and split leaf views
13. feat: make onboarding experience-first
14. fix: complete localization, due date, error, and accessibility paths
15. test: require complete runtime, visual, performance, and security evidence

各コミットは対応focused testを通す。baseline、generated evidence、release metadataは、そのsource commitと一致させる。PR本文には、変更理由、以前の状態、変更後、意思決定、旧機能保持、AX identifier移行、route migration、検証結果、残るmanual evidenceを記載する。

## 17. Completion Definition

以下をすべて満たした時だけ本設計を完了とする。

- 4領域IA、Review hub、Today主CTA、Voice、Settings、Toolbar、Inspector、Design System、Onboarding、Error/Date/Localization/Accessibilityが実装済み。
- 旧保存値、通知、Menu Bar、Voice、Command Palette、複数windowが新routeで正常動作する。
- approval-first、Undo、receipt、redaction、CRUDが回帰していない。
- macOS 14 fallbackと最新macOSのnative toolbar/materialが成立する。
- focused test、full `swift test`、security、runtime、visual、performanceがgreen。
- 通常製品routeの英語/日本語、minimum width、Light/Dark/Systemが実機確認済み。
- 最新source commitに対するmanual VoiceOver証跡がある。
- 未完了の署名、Notarization、外部credential、競合製品hands-onを実装完了と混同しない。
- セルフレビューとPRレビューの未解決指摘がない。
