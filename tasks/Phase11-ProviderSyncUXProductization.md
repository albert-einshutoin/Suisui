# Phase 11: Provider Sync UX Productization

目的は、Suisui を「ローカルで動くタスクアプリ」から、主要LLM provider、MCP仕様準拠、有料同期ゲート、競合水準の操作感まで含めたプロダクトに引き上げること。外部SaaS連携は引き続き本Phaseの非対象だが、LLM通信と有料同期の機能境界は実装する。

## Product Bar

- ユーザーは初回起動から2クリック以内でタスク作成に到達できるか。
- タスクのステータス変更はドラッグ1回、またはカード上の前後移動ボタン1回で完了するか。
- AI provider、MCP、同期の状態は Settings で「接続済み / 未設定 / 有料プランが必要 / 失敗」が区別できるか。
- Freeユーザーが同期を押しても、外部通信やデータアップロードが走らず、Pro gateで止まるか。
- Pro同期の実装が未構成の場合、mock successではなく「同期バックエンド未構成」と表示されるか。
- MCPは公式仕様に対して、実装済み範囲と未対応範囲がテストと証跡で説明できるか。
- 競合の便利機能を足すだけでなく、Suisuiの強みである local-first / BYOK / approval-first が崩れていないか。

## Scope

- MCP spec 2025-11-25 の client compliance audit
- LLM provider拡張: OpenAI、Gemini、Claude、OpenCode、Groq を主対象にする
- 有料同期の entitlement gate、UI、domain model
- `ui-samples/` を基準にした Projects / Today / Inbox / Settings のUX評価
- Notion、Todoist、Linear、Motion の競合ベンチマーク

## Non-Goals

- Google / Slack / GitHub / Notion など外部SaaSの実データ同期
- 決済providerの本番接続
- Proユーザー向けクラウド同期バックエンド本体
- MCP server marketplace
- Team workspace / shared project

## P11-001: MCP 2025-11-25 compliance matrix

- [x] `docs/mcp-compliance.md` を作り、MCP spec 2025-11-25 のLifecycle、Tools、Resources、Prompts、Transportsごとに実装状態を表にする。
- [x] `MCPClient.initialize()` が最初のrequestとして送られることを `ExternalMCPTests` で固定する。
- [x] `notifications/initialized` が `initialize` 成功後にだけ送られることをテストする。
- [x] `protocolVersion` は `2025-11-25` を提示し、serverが返したversionを監査/Settings表示へ残す。
- [x] `tools/list` responseの `name` / `title` / `description` / `inputSchema` 型不一致を fail fast する既存テストを compliance matrix にリンクする。
- [x] MCP推奨のtool name範囲をSuisuiの安全境界として実装し、1-128文字のASCII英数字/underscore/hyphen/dot以外はfail fastする。
- [x] paginated `tools/list` 全体で重複tool nameを拒否し、Settings catalog / audit / approval policyが同名toolで上書きされないようにする。
- [x] `tools/list` の `nextCursor` paginationを追跡し、複数ページのtool catalogを途中で切らず、malformed / repeated cursorをfail fastする。
- [x] `initialize` result の `capabilities` / `serverInfo.name` / `serverInfo.version` を必須として検証し、不完全なserverには `notifications/initialized` を送らない。
- [x] `tools/list` の `inputSchema` 欠落、root `type != object`、unsupported `$schema` dialect、非object property schemaを拒否し、MCP 2025-11-25のJSON Schema 2020-12 / draft-07境界をrelease subsetとして固定する。
- [x] `tools/list` の `outputSchema` をrelease subsetとしてparse/validateし、`tools/call` 成功時は object `structuredContent` の必須fieldとprimitive typeを検証してからsuccess auditへ進む。`isError = true` のtool実行エラーはLLMが自己修正できるactionable resultとしてschema検証をskipする。
- [x] `resources/list` / `prompts/list` は未対応としてUIとdocsで明示し、対応済みのように表示しない。
- [x] `2026-07-28` draft / release-candidate の per-request protocol metadata と `server/discover` は今回のrelease target外として、`docs/mcp-compliance.md` と `docs/release/evidence/mcp-inspector.md` に明記する。
- [x] `2026-07-28` RCは `initialize` / `notifications/initialized` / protocol-level sessionを外し、per-request `_meta`、required `server/discover`、tools/list `ttlMs` / `cacheScope` を含むため、Suisui public alphaのstable stdio Tools subsetとは別boundaryとして証跡化する。
- [x] `MCPClient.initialize()` は server が draft `2026-07-28` を返した場合、generic unsupportedではなくstable `2025-11-25` stdio Tools subsetだけをpublic alpha対応範囲として案内し、draft metadata / `server/discover` を対応済みに見せない。
- [x] MCP evidence は公式latest entrypoint、latest確認日、公式stable latest `2025-11-25`、公式stable source URL、`2026-07-28` release-candidate source URL / final予定日の境界を明記しない限りrelease readyにしない。
- [x] MCP evidence はEnterprise-Managed Authorization extensionがstableであることをwatchlistに入れ、remote authorizationはpublic alpha対象外と明記しない限りrelease readyにしない。
- [x] 完了条件: 仕様の「実装済み」「未対応」「後続」の境界が投資家/OSS contributorに説明できる。

## P11-002: MCP Inspector and external fixture evidence

- [x] 公式 MCP Inspector を使った手動/自動 smoke 手順を `script/verify_mcp_compliance.sh` にまとめる。
- [x] smoke対象は production source にfake serverを入れず、`Tests/Support` か `fixtures/mcp/` の検証用stdio serverに隔離する。
- [x] `initialize -> tools/list -> tools/call` の成功ログを `docs/release/evidence/mcp-inspector.md` に記録する。
- [x] malformed JSON-RPC、mismatched id、invalid schema、timeout の失敗ログも証跡に含める。
- [x] `release_readiness_report.sh` は `docs/release/evidence/mcp-inspector.md` の安定版baseline、draft境界、Inspector成功ログ、failure taxonomyを検証し、欠落/不完全なMCP証跡をblockerにする。
- [x] MCP Inspector evidence は最新の MCP runtime / Settings surface / fixture source commit を記録し、`release_readiness_report.sh` は古い `Source commit` の証跡をblockerにする。
- [x] Settings の Check Connection は Inspector結果と同じfailure taxonomyを表示する。
- [x] 完了条件: MCP互換性が「テストでなんとなく通る」ではなく、公式ツールで再現可能な証跡になる。

## P11-003: MCP permission and paid boundary review

- [x] 外部MCP tool permissionを `read` / `draft` / `writeWithApproval` / `dangerous` / `disabled` のまま維持し、unknownはdisabledに倒す。
- [x] Pro限定MCP機能を追加する場合、Freeでは登録保存は可能でも実行はentitlement gateで止めるか、登録自体をPro gateで止めるかをADRにする。
- [x] MCP tabは登録編集前にPro実行価値、Freeで可能な登録/接続確認、tools/call前のentitlement/approval/policy境界を表示する。
- [x] `read` / `draft` / `writeWithApproval` の外部MCPはユーザー承認なしで `tools/call` へ到達しないことを regression test で固定する。
- [x] MCP audit metadataに server id、tool name、permission、approval、duration、redacted arguments が必ず残ることを再確認する。
- [x] MCP stdio登録の `command` 欄は実行ファイルだけを許可し、`node server.js` のような複合入力は保存前に `arguments` 欄へ分離する案内を出す。
- [x] 完了条件: 有料機能化しても、危険な外部実行が課金状態だけで自動許可されない。

## P11-010: LLM provider catalog contract

- [x] `LLMProviderID` / Settings provider listを更新し、`openaiResponses`、`claudeMessages`、`geminiDirect`、`geminiOpenAICompatible`、`groqOpenAICompatible`、`opencodeLocal`、`openRouterCompatible`、`ollamaCompatible` を区別する。
- [x] 未実装providerはSettingsに選択肢として出さない。表示する場合は `Not available in this build` として保存不可にする。
- [x] 未実装/非公開providerはsettings normalizationでもdefault providerへ黙って置き換えず、runtimeへ到達しても `UnavailableLLMProvider` でfail closedにする。
- [x] providerごとに Keychain secret key、base URL、model id、request family、streaming support、structured output supportを定義する。
- [x] API keyはproviderごとにKeychainへ分離保存し、UserDefaults / SQLite / logs / screenshotsに出さない。
- [x] 完了条件: provider追加時に「OpenAI互換だから同じ」で隠れた差分がUIや実行時エラーに漏れない。

## P11-011: OpenAI Responses as reference implementation

- [x] `OpenAIResponsesProvider` を reference adapter とし、Action Plan JSON schema validationを必ず通す。
- [x] Responses APIのsuccess schema mismatchは `LLMProviderError.invalidResponse` に統一する。
- [x] provider smokeはAPI key未設定なら skip ではなく `notConfigured` としてSettingsに表示する。
- [x] model id未設定時のdefaultをdocsに明記し、勝手に高額modelへ落ちない。
- [x] 完了条件: 他provider実装が参照できる一番堅いbaselineになる。

## P11-012: Claude Messages adapter

- [x] `ClaudeMessagesProvider` を追加し、Anthropic Messages APIの `POST /v1/messages` 形に合わせる。
- [x] system prompt、user prompt、max tokens、model id、JSON extractionをOpenAI Responses adapterと同じ `PlanningResponse` へ変換する。
- [x] Claude固有のtool use loopは本タスクでは実装せず、Action Plan生成だけに限定する。
- [x] HTTP error bodyをprovider名つきのuser-facing errorへ変換し、raw response bodyをログに残さない。
- [x] `ClaudeMessagesProviderTests` で正常/HTTP error/schema mismatch/空contentを固定する。
- [x] 完了条件: ClaudeユーザーがBYOKでAction Plan生成を実利用できる。

## P11-013: Gemini adapter

- [x] `GeminiDirectProvider` は Gemini API native endpointを使う。
- [x] 既存OpenAI互換clientを使う場合のみ `GeminiOpenAICompatibleProvider` を別IDとして用意し、direct providerと混ぜない。
- [x] GeminiのresponseからAction Plan JSON候補を抽出し、既存schema validationへ通す。
- [x] safety block / quota / invalid key / schema mismatch のエラー分類をテストする。
- [x] SettingsでGemini API key保存、接続確認、model id設定を実装する。
- [x] 完了条件: Google ecosystemユーザーがOpenAI keyなしで利用できる。

## P11-014: Groq OpenAI-compatible adapter

- [x] GroqはOpenAI-compatible providerとしてbase URLとrequest pathを明示設定する。
- [x] Groq固有のmodel id、rate limit、response schema mismatchを `ChatCompletionsCompatibleProviderTests` に追加する。
- [x] OpenAI-compatible汎用adapterにGroq専用defaultを混ぜず、provider presetで注入する。
- [x] SettingsはGroq API keyとbase URLをKeychain/設定に分離する。
- [x] 完了条件: 高速/低コストproviderとしてGroqを選べるが、OpenAI本体と認証/課金を混同しない。

## P11-015: OpenCode local provider integration

- [x] OpenCodeはクラウドAPI providerではなく、ローカル開発者向けの `opencodeLocal` adapterとして扱う。
- [x] Suisuiは `~/.local/share/opencode/auth.json` を読まない。ユーザーが選んだ `opencode` executableとworkspaceだけを使う。
- [x] subprocess実行はtimeout、stderr redaction、working directory validation、user approvalを必須にする。
- [x] OpenCode outputはAction Plan JSONのみ受け入れ、自然文だけの応答は実行しない。
- [x] 完了条件: 開発者はOpenCode資産を使えるが、Suisuiが勝手に認証情報を吸い上げない。

## P11-016: Codex App Server user-subscription provider

- [x] `codexLocal` をAPI key providerとは別の、Macローカル・Codex管理認証・ユーザーprovider課金として型定義する。
- [x] SuisuiがCodexのaccess token、refresh token、`~/.codex/auth.json`を読まない境界をADR 0011に固定する。
- [x] 対応最低versionで `account/read`、`account/login/start`、`model/list`、`thread/start`、`turn/start` がfixtureとlive smokeの両方で成立する。
- [x] Suisui parent processが`auth.json`を直接openせず、認証所有者であるCodex process treeだけがアクセスすることをschema v4 runtime evidenceで証明する。
- [x] 内部token注入modeをproduction型から表現不能にする。
- [x] command、file change、permission requestを承認せずturnをinterruptしてfail closedにする。
- [x] Receiptを`userProviderBilled`として記録し、Suisui managed costへ合算しない。
- [x] Codexがworkspace policyで無効な場合は、再ログインloopではなく管理者policyエラーを表示する。
- [x] shell、file、web、MCP toolをturn開始前に無効化し、adversarial promptとlive smokeでtool lifecycleが発生しないことを証明する。証明できないversionではSettings公開をNO-GOにする。
- [x] Enterprise対応を表明する前に`clientInfo.name = "suisui"`のknown-client登録、または未登録clientのCompliance Logs制約を製品文書へ明記する。Personal PreviewのGO gate外とし、Enterprise対応時の別release gateとして扱う。`docs/mcp-compliance.md`でPersonal Preview限定、Suisui固有のCompliance Logs識別を非対応、Enterpriseを別release gateとして明記済み。
- [x] 完了条件（Personal Preview）: Personal Preview対象のGO gateがすべてgreenになった場合だけSettingsへ表示し、ユーザー自身のCodex枠で音声タスクのAction Planを生成できる。

## P11-020: Subscription entitlement domain

- [x] `SubscriptionPlan` を `free` / `pro` / `founder` で定義し、local license / future billingの両方に対応できるdomain modelにする。
- [x] `EntitlementStore` protocolを作り、runtimeはKeychainまたはsigned local licenseから読み、testはfakeを使う。
- [x] `FeatureGate` に `externalSync`、`advancedMCPExecution`、`providerPresets` などを定義する。
- [x] FreeでPro機能を実行しようとした場合は、外部通信前に `EntitlementError.upgradeRequired` で止める。
- [x] 完了条件: UIの表示だけでなくdomain層で有料機能が実行不能になる。

## P11-021: Paid sync shell without mock success

- [x] `SyncService` は `status()`、`startSync()`、`stopSync()`、`exportDryRun()` を持つが、バックエンド未構成時は成功扱いしない。
- [x] Freeユーザーは `startSync()` が必ず `upgradeRequired` で失敗し、network clientへ到達しないことをテストする。
- [x] Proユーザーでもbackend endpoint未設定なら `syncBackendNotConfigured` を返す。
- [x] 同期対象はProject / Task / Settingsの分類だけ先に定義し、外部SaaS connectorとは分離する。
- [x] 完了条件: 有料同期の入口は存在するが、mock同期や空成功でリリース品質を偽らない。

## P11-022: Sync settings UI

- [x] Settingsに `Sync` セクションを追加し、Plan、Status、Last attempt、Data included、Upgrade requiredを表示する。
- [x] Freeでは同期toggleをdisabledにし、押した時も外部通信を発火しない。
- [x] Pro未構成では「Sync backend is not configured」と表示し、同期toggleもdisabledにして成功バッジや空成功を出さない。
- [x] Pro + backend設定済みでもnetwork client失敗後は `Failed` とLast Attemptを表示し、`Ready` に戻して同期成功のように見せない。
- [x] `ui-samples/07.png` の設定密度を参考に、AI Provider / MCP / Sync / Privacy が一画面で状態確認できるよう整理する。
- [x] Settings詳細FormをOverview / Appearance / AI / MCP / Sync / Privacyのtabへ分割し、Status確認・Theme変更・provider設定・MCP登録・Sync gate・Privacy設定の到達先を明確にする。
- [x] AI tabのprovider詳細fieldは選択中providerだけを表示し、非選択providerのAPI key、model、local executable欄を同時表示しない。
- [x] AI tabはprovider picker直下に選択中providerの状態、smoke readiness、次の操作を表示し、詳細fieldを読む前に未設定理由が分かる。
- [x] Sync tabはtoggle前にPro価値、Freeのlocal-only境界、backend未構成時の次状態を表示し、課金価値がdisabled toggleだけに埋もれない。
- [x] Overview tabにPro Value rowを追加し、Sync/MCPタブを開く前に有料価値とFree/local-only/fail-closed境界が分かる。
- [x] 完了条件: ユーザーは自分のデータが同期されているか、なぜ同期できないかを1画面で理解できる。

## P11-030: UX click-path audit

- [x] `docs/ux/click-path-audit.md` を作り、Inbox、Today、Projects、Project Detail、Settings、Review Executeの主要操作をクリック数で棚卸しする。
- [x] 目標: タスク作成は2クリック以内、タスクステータス変更はドラッグ1回またはカードボタン1回、Project作成は2クリック以内。
- [x] 目標: Provider設定はSettingsを開いて2クリック以内、MCP接続確認はSettingsを開いて2クリック以内、Sync状態確認はSettingsを開いて1クリック以内。
- [x] 複数MCP serverの接続確認をPicker切替ではなくserver row上の `Check` から実行できるようにし、rowごとにEnabled/Disabledと接続結果を表示する。
- [x] AI tabはProvider Readiness summaryで全providerの設定状態をprovider切替なしに確認できる。
- [x] クリック数だけでなく、次に何をすればよいかが画面上の主要ボタン/状態で分かるかを記録する。
- [x] 完了条件: UI改善が感覚論ではなく、導線コストとしてレビューできる。

## P11-031: Board and inspector UX upgrade

- [x] `ui-samples/01.png`、`03.png`、`04.png` を基準に、左サイドバー、中央ボード/リスト、右インスペクタの情報密度を見直す。
- [x] Task cardの選択領域を `Open task` のキーボードフォーカス可能なButtonにし、status移動コントロールとdrag affordanceが同じアクセシビリティ要素に潰れないよう分離する。
- [x] Task card metadata strip はstatus / priorityとdue / recurrenceを最大2行の意味的なTextへ統合し、狭いKanban列・選択状態・Light/Dark/Systemでも文字が欠落しない表示にする。
- [x] Project Detailではタスク一覧、成果物、タイムライン、AI提案をタブまたはセクションとして整理する。
- [x] Project Overview / headerの `Add Task` は押下後にBoardへ切り替え、Backlogのinline composerを即表示する。Overview上で状態だけ変わり入力欄が見えない状態を残さない。
- [x] Task cardはタイトル、状態、優先度、期限、ドラッグ affordance が重ならず表示されることをスクリーンショットで確認する。
- [x] 右インスペクタは選択中タスク/プロジェクトの編集、削除、AI提案の適用を一箇所に集約する。
  - [x] 選択中Taskの編集、削除、Local suggestion適用はTask inspectorに集約する。
  - [x] 選択中Projectの編集、削除、Local suggestion適用を右インスペクタに統合する。
  - [x] Task / Project inspector はcompact summaryで状態、優先度、期限、件数を先頭表示し、詳細Formの前に文脈が分かる。
  - [x] Task単体削除はTask行だけでなく、紐づくCalendar link、Reminder link、Deadline rule、Artifactを同一transactionで削除し、削除件数をToolResultに返す。
  - [x] Task inspectorで期限を削除した場合、画面上のnil表示だけでなくSQLiteの `due_at` をNULLへ戻し、期限検索/CLI/deadline watcherに空文字の期限が再浮上しない。
  - [x] Project完了はProject status更新と子Task完了を同一transactionにし、Board操作/Action Plan Toolのどちらでも途中失敗時にProjectだけcompletedへ残らない。
  - [x] Project OverviewのArtifacts panelから絶対パスのexpected artifactを追加でき、Project snapshotへ即反映する。相対パスはworkspace未確定として保存せず、mock artifact rowを作らない。
  - [x] Project OverviewのArtifact行からlocal artifact linkを削除でき、実ファイルを削除せずSQLite snapshotだけを更新する。存在しないlink削除は成功扱いにせず、ユーザーへmissing stateを返す。
  - [x] Review Executeの `filesystem.create_markdown_file` / `filesystem.create_artifacts_from_frame` は `projectId` / `taskId` を受けた場合、作成ファイルをSQLite `artifacts` へ `created` linkとして保存し、Project Overviewへ実成果物として戻す。
- [x] 完了条件: Notion的な柔軟さ、Linear的な速度、Todoist的な即時入力のうち、Suisuiに必要な部分だけが実装される。

## P11-032: Today and Inbox workflow

- [x] `ui-samples/01.png` / `02.png` を基準に、TodayとInboxの情報設計を分ける。
- [x] Inboxは未処理入力の分類、Task化、Project化、Schedule化、後で確認の4アクションを1クリックで選べるようにする。
- [x] Inbox分類後は成功状態、Undo、次のInbox item自動選択を出し、連続triageで迷子にならない。
- [x] Todayは今日やるタスク、期限、AI提案、時間ブロックを同一画面で確認できるようにする。
- [x] Inbox / Today workflowのrow完了toggleを追加し、選択済みinspectorを開かずにlocal SQLite task statusをDoneへ移せる。
- [x] MenuBarExtraにQuick Addを追加し、Project Boardを開かずにInboxへローカルTaskを作れる。
- [x] 音声入力後に自動で謎の固定タスクが入らないことをregression testで維持する。
- [x] 完了条件: ユーザーが「どこに入ったか分からない」状態にならない。

## P11-033: Keyboard and accessibility pass

- [x] `Command+N` は選択中ProjectにTask追加、`Command+Shift+N` はProject追加、`Command+,` はProject Board toolbarではなくmacOS app menuのSettingsに割り当てる。
- [x] Drag操作の代替として、カード上のMoveボタンとcontext menuを維持する。
- [x] Task / Project inspector は `Command+S` で保存、`Command+Return` で提案適用、`Command+Delete` で削除確認を開ける。
- [ ] VoiceOver label、focus order、button help、destructive confirmationを確認する。
  - [x] Task card、column add、status move controlにVoiceOver label/helpを付け、delete/archiveのconfirmationをsource testで固定する。
  - [x] Task card本体のOpen Detailsとstatus move controlsを別フォーカス対象に分け、支援技術で移動ボタンがカード要約に埋もれないことをsource testで固定する。
  - [x] Sidebar -> board detail -> task card -> inspector edit/save/delete のsource-level focus anchorsを固定する。
  - [x] Task / Project inspector のfield、提案適用、save、complete、restore、archive、deleteにaccessibility identifier / hintを付け、主要CRUDと提案操作が支援技術で追えることをsource testで固定する。
  - [x] Inline Task Composerにtitle/detail/priority/due/create/cancelのaccessibility identifier / hintとCommand+Return/Escapeを付ける。
  - [x] Inbox / Today workflowのrow、Quick Add、分類action、Today summary、time blockにsource-level accessibility identifiers / hints / keyboard anchorsを付ける。
  - [x] Project OverviewのTask snapshot、Local Suggestions、Artifactsにaccessibility identifier / label / hintを付け、Overviewからも支援技術で主要CRUDへ入れる。
  - [x] `release_readiness_report.sh` は `docs/release/evidence/accessibility-voiceover.md` の `Status: passed` と必須focus path markerを検証し、pending証跡をblockerにする。
  - [x] `release_readiness_report.sh` とVoiceOver証跡generatorはInline Task Composerの作成/cancel導線を必須focus pathに含める。
  - [x] `release_readiness_report.sh` はVoiceOver証跡のrelease-candidate context空欄/テンプレート値をblockerにする。
  - [x] `docs/release/evidence/accessibility-voiceover.md` は実機確認者がmacOS/build/checked-by/failure notesを埋められる形にする。
  - [x] `script/create_voiceover_evidence.sh` はpending worksheetとpassed evidenceをmetadata付きで生成し、実機確認フラグなしのpassed証跡作成を拒否する。
  - [x] VoiceOver証跡はVoiceOver/keyboard/deviceの実環境contextがない場合release readyにしない。
  - [x] `script/check_accessibility_preflight.sh` はsource-level accessibility anchorsを確認し、任意のruntime AX smokeで手動VoiceOver前の崩れを検出できる。
  - [x] `script/check_accessibility_preflight.sh` はTask inspectorのdetail/status/priority/due/suggestion/save/deleteとProject inspectorのtitle/suggestion/save/complete/restore/archive/deleteを必須anchorとして監視する。
  - [x] `script/check_accessibility_preflight.sh` はProject OverviewのTask snapshot、Local Suggestions、Artifactsの支援技術CRUD入口もsource anchorとして監視する。
  - [x] `script/check_accessibility_preflight.sh` は主要CRUDのkeyboard shortcutsをsource anchorとして監視する。
  - [x] `script/check_accessibility_preflight.sh --runtime` は見えているrelease候補windowのunlabeled AX buttonsとhelp/child textなしgeneric `button` labelをblockerにする。
  - [x] `script/check_accessibility_preflight.sh --runtime` はProject Board上のAdd Task、タスク詳細オープン、ステータス移動、ローカル提案適用、自動化レビュー、承認済み実行、Save、DeleteのAX identifier/help signalsを `crudSignals=8/8` としてblocker化する。
  - [x] `script/check_accessibility_preflight.sh --runtime` はProject navigation -> Project board detail -> Open task -> Inline Task Composer -> Status controls -> Task inspector のAX identifier/help signalsを `focusPathSignals=6/6` としてblocker化する。
  - [x] `script/check_accessibility_preflight.sh --runtime` はDelete Task確認を開き、Cancel Delete TaskのAX identifier/help signalを `destructiveCancelSignals=1/1` としてblocker化する。
  - [x] `script/check_runtime_accessible_crud_smoke.sh` は隔離 `SUISUI_DATABASE_PATH` と `SUISUI_PROJECT_BOARD_SELECTED_DESTINATION` を使い、実アプリのAccessibility操作でProjectの作成、リネーム保存、完了、削除、Task作成、Task更新、Task status移動、Task直接削除、Project削除時のTask cascade削除がSQLiteに反映されることを検証する。
  - [x] VoiceOver passed evidence は同じrelease候補で実行したruntime AX smoke OK行、`unlabeledButtons=0`、`genericButtons=0`、`crudSignals=8/8`、`focusPathSignals=6/6`、`destructiveCancelSignals=1/1` を含まない場合release readyにしない。
  - [x] `script/create_voiceover_evidence.sh --capture-runtime-ax-smoke` は手動VoiceOver証跡の作成時に同じrelease候補のruntime AX smoke OK行を自動取得し、古いコピー済みcountsでrelease readyを偽らない。
  - [x] `script/prepare_voiceover_review_candidate.sh` は隔離DBにVoiceOver確認用Project/各StatusのTask/Artifactをseedし、`SUISUI_PROJECT_BOARD_SELECTED_DESTINATION` 付きで同じrelease候補を開ける。
  - [x] `script/prepare_voiceover_review_candidate.sh` は `.tmp/voiceover-review/create-evidence-command.sh` を生成し、同じ候補DB/Project IDを使った手動VoiceOver証跡コマンドをoperatorがplaceholder置換して実行できる。
  - [x] `script/prepare_voiceover_review_candidate.sh` pins `.tmp/voiceover-review/create-evidence-command.sh` to a clean tracked source tree and the release-candidate source commit it was generated for, and the generated command exits before writing evidence if the release candidate tree is dirty or the commit has changed.
  - [x] `script/prepare_voiceover_review_candidate.sh` writes `.tmp/voiceover-review/accessibility-voiceover-pending-<commit>.md` with the current release-candidate `Source commit` without modifying tracked evidence.
  - [x] Direct `script/create_voiceover_evidence.sh --pending` defaults to `.tmp/voiceover-review/accessibility-voiceover-pending-<commit>.md` and does not modify tracked VoiceOver release evidence unless `--output` explicitly points there.
  - [x] `script/prepare_voiceover_review_candidate.sh` writes `.tmp/voiceover-review/launch.env` with `SUISUI_VOICEOVER_REVIEW_SOURCE_COMMIT` and `SUISUI_VOICEOVER_REVIEW_PROJECT_ID` so manual reviewers do not launch stale VoiceOver candidates.
  - [x] Generated VoiceOver evidence command reloads `.tmp/voiceover-review/launch.env`, verifies the seeded candidate database/project id, and launches the same candidate before runtime AX smoke capture.
  - [x] Generated VoiceOver evidence command verifies `.tmp/voiceover-review/voiceover-worksheet.md` is current, marked completed, filled, and free of pending/unchecked markers before validate-only or passed evidence.
  - [x] Generated VoiceOver evidence command reads the completed worksheet values directly into `script/create_voiceover_evidence.sh`, so the reviewer does not duplicate focus notes in command-line placeholders.
  - [x] Generated VoiceOver evidence command rejects boilerplate worksheet values such as `TBD`, `Verified`, `OK`, or `No issues`; each required worksheet field must contain concrete VoiceOver observations.
  - [x] VoiceOver evidence generator and generated worksheet command require a Task content execution observation proving approved execution records the reviewed task title and detail in the redacted receipt, and reject notes that only prove the Run approved plan control was reachable.
  - [x] VoiceOver review candidate seeds a dedicated approved execution receipt task so manual reviewers can prove the reviewed title/detail is announced from `approved-execution-receipt`.
  - [x] `release_readiness_report.sh` also rejects passed VoiceOver evidence when the Task content execution note does not prove the redacted receipt includes the reviewed title and detail.
  - [x] `release_readiness_report.sh` rejects `Status: passed` VoiceOver evidence that does not include `Generated by: script/create_voiceover_evidence.sh`.
  - [x] `script/create_voiceover_evidence.sh --validate-only` validates the filled manual command without writing tracked evidence.
  - [x] Generated `.tmp/voiceover-review/create-evidence-command.sh --validate-only` exits after validation without writing tracked VoiceOver evidence.
  - [ ] 実機VoiceOverでProject board -> card -> Inline Task Composer -> inspectorのfocus orderを確認する。
- [x] `script/capture_ui_evidence.sh` は一時HOME、seed済みProject board、Light/Dark/System切替、window captureを使う。
  - [x] `capture_ui_evidence.sh` はcapture前にappを前面化し、黒画面/低情報量PNGをrelease evidenceとして残さず失敗させる。
  - [x] `capture_ui_evidence.sh` はScreen Recording権限やwindow capture失敗時に、選択window情報と再実行手順を出す。
  - [x] `capture_ui_evidence.sh --doctor` はrelease evidenceを書かずにScreen Recordingの可視ピクセル取得を事前診断する。
  - [x] `capture_ui_evidence.sh` は撮影前にAX identifierとseed固有テキストで対象画面を検証し、Today等の誤画面スクショをrelease evidenceとして保存しない。
- [x] `release_readiness_report.sh` は `ui-screenshots.md` だけでなく Project Board Light/Dark/System、Settings Overview Light/Dark、Settings Appearance Light/Dark、MCP Settings Light/Dark PNG の存在、サイズ、寸法を検証し、欠落や小さすぎる画像をblockerにする。
- [x] Light/Dark/System切替後にカード、サイドバー、インスペクタのコントラストが破綻しないことをスクリーンショットで確認する。
- [ ] 完了条件: マウス、キーボード、支援技術のどれでも主要CRUDが完結する。

## P11-040: Competitor benchmark and feature fit

- [ ] Notion、Todoist、Linear、Motion を2-4時間で触り、Suisuiに関係する機能だけを `docs/product/competitor-benchmark.md` に記録する。
- [x] 公式docs/product pageベースの desk research を `docs/product/competitor-benchmark.md` に記録する。
- [x] 実操作2-4時間で見るべき競合別クリックパス、測定項目、Suisui採用/非採用判断基準を `docs/product/competitor-benchmark.md` に記録する。
- [x] `script/create_competitor_hands_on_evidence.sh` と `release_readiness_report.sh` でpending/未チェックの競合hands-on証跡をrelease readyにしない。
- [x] `script/create_competitor_hands_on_evidence.sh --passed` は手動確認済みの具体メモから `docs/product/competitor-benchmark.md` の `## Hands-On Findings` も同時生成する。
- [x] 競合hands-on証跡はmacOS/browser/app version、account tier、paid trial有無を含む環境contextがない場合release readyにしない。
- [x] `script/create_competitor_hands_on_evidence.sh --pending` は `.tmp/competitor-hands-on/create-evidence-command.sh` を生成し、operatorがplaceholderを具体観測へ置換して同じoutput/benchmark pathでpassed証跡を作れる。
- [x] `script/create_competitor_hands_on_evidence.sh --pending` pins `.tmp/competitor-hands-on/create-evidence-command.sh` to a clean tracked source tree and the release-candidate source commit it was generated for, and the generated command exits before writing evidence if the release candidate tree is dirty or the commit has changed.
- [x] `script/create_competitor_hands_on_evidence.sh --pending` は `.tmp/competitor-hands-on/hands-on-worksheet.md` も生成し、2-4時間の手動レビュー中にcontext、クリックパス、測定、Ship/Defer/Rejectを取り漏らさない。
- [x] `script/create_competitor_hands_on_evidence.sh --pending` はデフォルトで `.tmp/competitor-hands-on/competitor-hands-on-pending-<commit>.md` と `.tmp/competitor-hands-on/competitor-benchmark-pending-<commit>.md` を生成し、tracked evidence / benchmarkをpending worksheetで汚さずfinal benchmark更新漏れを防ぐ。
- [x] `script/create_competitor_hands_on_evidence.sh --validate-only` validates the filled manual command without writing tracked evidence or benchmark findings.
- [x] Generated competitor hands-on evidence command verifies `.tmp/competitor-hands-on/hands-on-worksheet.md` and `.tmp/competitor-hands-on/competitor-benchmark-pending-<commit>.md` are current, marked completed, filled, and free of pending/unchecked markers before validation or passed evidence.
- [x] Generated competitor hands-on evidence command rejects boilerplate worksheet values such as `TBD`, `Verified`, `OK`, or `No issues`; each required worksheet field must contain concrete hands-on observations.
- [x] `release_readiness_report.sh` rejects `Status: passed` competitor hands-on evidence that does not include `Generated by: script/create_competitor_hands_on_evidence.sh`.
- [x] competitor hands-on passed evidence requires elapsed 2-4 hour timing with Notion/Todoist/Linear/Motion coverage.
- [x] action summary は VoiceOver の `.tmp/voiceover-review/accessibility-voiceover-pending-<commit>.md` preview、`.tmp/voiceover-review/voiceover-worksheet.md`、`.tmp/voiceover-review/create-evidence-command.sh` を案内し、operatorがtracked evidenceを汚さずrelease候補contextを確認できるようにする。
- [x] action summary は VoiceOver / competitor hands-on の current `Source commit` に対応する pending evidence path も併記し、operatorが実ファイル名を推測しなくてよい。
- [x] release action summary は competitor hands-on の pending generator と `.tmp/competitor-hands-on/create-evidence-command.sh` を先に案内し、手動証跡を未完了のまま明確に修復できる。
- [x] Notion: 柔軟だが個人PM用途では構造化と運用設計が重い。Suisuiは「音声/AIで構造化済みのProject/Taskに落とす」ことで差別化する。
- [x] Todoist: 速いcaptureと今日の整理が強い。SuisuiはInbox/Todayの即時入力とAI分類を取り込む。
- [x] Linear: issue/project/cycleの速度とキーボード操作が強い。Suisuiは個人向けにstatus移動とProject進捗だけを取り込む。
- [x] Motion: AIスケジュールと自動調整が強いが、提案理由が見えないと不安になる。Suisuiは提案理由、適用前確認、local-firstを維持する。
- [x] 完了条件: 競合比較が機能一覧ではなく、ユーザーの困りごととSuisuiの採用/非採用判断に結びつく。

## P11-041: VC/investor-grade product review loop

- [x] 各実装サイクルで `Problem / User pull / Retention hook / Monetization / Risk` をセルフレビューする。
- [x] 「便利そう」だけの機能はIssue化せず、クリック数削減、継続利用、課金理由のどれに効くかを書く。
- [x] Pro機能はFree体験を壊さず、しかしProの価値がSettings/Sync/MCP画面で理解できるようにする。
- [x] OSSとして、BYOK provider追加、MCP compliance fixtures、local-first data modelを外部contributorが触れる形にする。
- [x] Investor reviewはUI screenshot証跡をpassed local evidenceとして扱い、VoiceOver、競合hands-on、署名/Notarization/Sparkle/Gatekeeperを残release blockerとして分離する。
- [x] action summary は release-machine blocker が残る場合、秘密値を出さずに Developer ID identity、local env、signing/notary/Sparkle verifier、final preflight を確認する `Release Machine Local Doctor` を表示する。
- [x] 完了条件: 実装完了だけでなく、投資判断の観点で「なぜ伸びるか / なぜ課金されるか」を説明できる。

## Exit Gate

- [x] `docs/mcp-compliance.md` が公式仕様と実装差分を説明している。
- [x] OpenAI / Claude / Gemini / Groq / OpenCode のprovider計画がSettingsとdomain modelに反映されている。
- [x] 実装済みprovider以外は保存不可または明確なunavailable表示になっている。
- [x] Freeユーザーは外部同期を開始できず、外部通信も発生しない。
- [x] Proユーザーでもsync backend未構成時はmock successにならない。
- [x] UX click-path auditで主要操作のクリック数が記録され、改善PRと紐づいている。
  - [x] `docs/ux/click-path-audit.md` の改善紐づけ表で、PR未作成の現時点はcurrent branchの改善commit/source testに対応づけ、PR作成時にdescriptionへ転記する方針を明記する。
- [x] `ui-samples/` を参考にした画面密度・インスペクタ・Settingsの改善がスクリーンショットで検証されている。
- [x] 競合benchmarkから採用/非採用判断が残っている。
- [x] `swift test`、`./scripts/ci.sh`、`xcodebuild ... -scheme Suisui build` がgreen。

## Source Notes

- MCP specification 2025-11-25: https://modelcontextprotocol.io/specification/2025-11-25
- MCP lifecycle: https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle
- MCP tools: https://modelcontextprotocol.io/specification/2025-11-25/server/tools
- MCP Inspector: https://modelcontextprotocol.io/docs/tools/inspector
- OpenAI API reference: https://developers.openai.com/api/reference/overview/
- OpenAI models: https://developers.openai.com/api/docs/models
- Anthropic Messages API: https://docs.anthropic.com/en/api/messages
- Anthropic models overview: https://platform.claude.com/docs/en/about-claude/models/overview
- Gemini API docs: https://ai.google.dev/gemini-api/docs
- Gemini OpenAI compatibility: https://ai.google.dev/gemini-api/docs/openai
- Gemini 3.5 Flash model: https://ai.google.dev/gemini-api/docs/models/gemini-3.5-flash
- Groq OpenAI compatibility: https://console.groq.com/docs/openai
- Groq production models: https://console.groq.com/docs/models
- OpenCode providers: https://opencode.ai/docs/providers/
- Notion pricing/product AI: https://www.notion.com/pricing
- Todoist pricing/AI Assist: https://www.todoist.com/pricing
- Linear pricing/projects: https://linear.app/pricing
- Motion AI Project Manager: https://www.usemotion.com/features/ai-project-manager.html
- Notion Projects: https://www.notion.com/product/projects
- Todoist Quick Add: https://www.todoist.com/help/articles/use-task-quick-add-in-todoist-va4Lhpzz
- Todoist Board layout: https://www.todoist.com/help/articles/use-the-board-layout-in-todoist-AiAVsyEI
- Todoist Ramble: https://www.todoist.com/help/articles/dictate-to-add-tasks-with-ramble-P1Raq7vVF
- Linear Projects: https://linear.app/docs/projects
- Linear Triage: https://linear.app/docs/triage
- Motion AI Task Manager: https://www.usemotion.com/features/ai-task-manager
