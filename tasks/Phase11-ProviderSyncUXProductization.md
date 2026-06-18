# Phase 11: Provider Sync UX Productization

目的は、SoloPM を「ローカルで動くタスクアプリ」から、主要LLM provider、MCP仕様準拠、有料同期ゲート、競合水準の操作感まで含めたプロダクトに引き上げること。外部SaaS連携は引き続き本Phaseの非対象だが、LLM通信と有料同期の機能境界は実装する。

## Product Bar

- ユーザーは初回起動から2クリック以内でタスク作成に到達できるか。
- タスクのステータス変更はドラッグ1回、またはカード上の前後移動ボタン1回で完了するか。
- AI provider、MCP、同期の状態は Settings で「接続済み / 未設定 / 有料プランが必要 / 失敗」が区別できるか。
- Freeユーザーが同期を押しても、外部通信やデータアップロードが走らず、Pro gateで止まるか。
- Pro同期の実装が未構成の場合、mock successではなく「同期バックエンド未構成」と表示されるか。
- MCPは公式仕様に対して、実装済み範囲と未対応範囲がテストと証跡で説明できるか。
- 競合の便利機能を足すだけでなく、SoloPMの強みである local-first / BYOK / approval-first が崩れていないか。

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
- [x] `resources/list` / `prompts/list` は未対応としてUIとdocsで明示し、対応済みのように表示しない。
- [x] 完了条件: 仕様の「実装済み」「未対応」「後続」の境界が投資家/OSS contributorに説明できる。

## P11-002: MCP Inspector and external fixture evidence

- [x] 公式 MCP Inspector を使った手動/自動 smoke 手順を `script/verify_mcp_compliance.sh` にまとめる。
- [x] smoke対象は production source にfake serverを入れず、`Tests/Support` か `fixtures/mcp/` の検証用stdio serverに隔離する。
- [x] `initialize -> tools/list -> tools/call` の成功ログを `docs/release/evidence/mcp-inspector.md` に記録する。
- [x] malformed JSON-RPC、mismatched id、invalid schema、timeout の失敗ログも証跡に含める。
- [x] Settings の Check Connection は Inspector結果と同じfailure taxonomyを表示する。
- [x] 完了条件: MCP互換性が「テストでなんとなく通る」ではなく、公式ツールで再現可能な証跡になる。

## P11-003: MCP permission and paid boundary review

- [x] 外部MCP tool permissionを `read` / `draft` / `writeWithApproval` / `dangerous` / `disabled` のまま維持し、unknownはdisabledに倒す。
- [x] Pro限定MCP機能を追加する場合、Freeでは登録保存は可能でも実行はentitlement gateで止めるか、登録自体をPro gateで止めるかをADRにする。
- [x] Write系MCPはユーザー承認なしで `tools/call` へ到達しないことを regression test で固定する。
- [x] MCP audit metadataに server id、tool name、permission、approval、duration、redacted arguments が必ず残ることを再確認する。
- [x] 完了条件: 有料機能化しても、危険な外部実行が課金状態だけで自動許可されない。

## P11-010: LLM provider catalog contract

- [x] `LLMProviderID` / Settings provider listを更新し、`openaiResponses`、`claudeMessages`、`geminiDirect`、`geminiOpenAICompatible`、`groqOpenAICompatible`、`opencodeLocal`、`openRouterCompatible`、`ollamaCompatible` を区別する。
- [x] 未実装providerはSettingsに選択肢として出さない。表示する場合は `Not available in this build` として保存不可にする。
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
- [x] SoloPMは `~/.local/share/opencode/auth.json` を読まない。ユーザーが選んだ `opencode` executableとworkspaceだけを使う。
- [x] subprocess実行はtimeout、stderr redaction、working directory validation、user approvalを必須にする。
- [x] OpenCode outputはAction Plan JSONのみ受け入れ、自然文だけの応答は実行しない。
- [x] 完了条件: 開発者はOpenCode資産を使えるが、SoloPMが勝手に認証情報を吸い上げない。

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
- [x] Pro未構成では「Sync backend is not configured」と表示し、成功バッジを出さない。
- [x] `ui-samples/07.png` の設定密度を参考に、AI Provider / MCP / Sync / Privacy が一画面で状態確認できるよう整理する。
- [x] Settings詳細FormをOverview / AI / MCP / Sync / Privacyのtabへ分割し、Status確認・Theme変更・provider設定・MCP登録・Sync gate・Privacy設定の到達先を明確にする。
- [x] AI tabのprovider詳細fieldは選択中providerだけを表示し、非選択providerのAPI key、model、local executable欄を同時表示しない。
- [x] 完了条件: ユーザーは自分のデータが同期されているか、なぜ同期できないかを1画面で理解できる。

## P11-030: UX click-path audit

- [x] `docs/ux/click-path-audit.md` を作り、Inbox、Today、Projects、Project Detail、Settings、Review Executeの主要操作をクリック数で棚卸しする。
- [x] 目標: タスク作成は2クリック以内、タスクステータス変更はドラッグ1回またはカードボタン1回、Project作成は2クリック以内。
- [x] 目標: Provider設定はSettingsを開いて2クリック以内、MCP接続確認はSettingsを開いて2クリック以内、Sync状態確認はSettingsを開いて1クリック以内。
- [x] 複数MCP serverの接続確認をPicker切替ではなくserver row上の `Check` から実行できるようにし、rowごとにEnabled/Disabledと接続結果を表示する。
- [x] クリック数だけでなく、次に何をすればよいかが画面上の主要ボタン/状態で分かるかを記録する。
- [x] 完了条件: UI改善が感覚論ではなく、導線コストとしてレビューできる。

## P11-031: Board and inspector UX upgrade

- [ ] `ui-samples/01.png`、`03.png`、`04.png` を基準に、左サイドバー、中央ボード/リスト、右インスペクタの情報密度を見直す。
- [x] Task cardの選択領域を `Open task` のキーボードフォーカス可能なButtonにし、status移動コントロールとdrag affordanceが同じアクセシビリティ要素に潰れないよう分離する。
- [x] Project Detailではタスク一覧、成果物、タイムライン、AI提案をタブまたはセクションとして整理する。
- [ ] Task cardはタイトル、状態、優先度、期限、ドラッグ affordance が重ならず表示されることをスクリーンショットで確認する。
- [x] 右インスペクタは選択中タスク/プロジェクトの編集、削除、AI提案の適用を一箇所に集約する。
  - [x] 選択中Taskの編集、削除、Local suggestion適用はTask inspectorに集約する。
  - [x] 選択中Projectの編集、削除、Local suggestion適用を右インスペクタに統合する。
  - [x] Task / Project inspector はcompact summaryで状態、優先度、期限、件数を先頭表示し、詳細Formの前に文脈が分かる。
- [ ] 完了条件: Notion的な柔軟さ、Linear的な速度、Todoist的な即時入力のうち、SoloPMに必要な部分だけが実装される。

## P11-032: Today and Inbox workflow

- [x] `ui-samples/01.png` / `02.png` を基準に、TodayとInboxの情報設計を分ける。
- [x] Inboxは未処理入力の分類、Task化、Project化、Schedule化、後で確認の4アクションを1クリックで選べるようにする。
- [x] Inbox分類後は成功状態、Undo、次のInbox item自動選択を出し、連続triageで迷子にならない。
- [x] Todayは今日やるタスク、期限、AI提案、時間ブロックを同一画面で確認できるようにする。
- [x] 音声入力後に自動で謎の固定タスクが入らないことをregression testで維持する。
- [x] 完了条件: ユーザーが「どこに入ったか分からない」状態にならない。

## P11-033: Keyboard and accessibility pass

- [x] `Command+N` は選択中ProjectにTask追加、`Command+Shift+N` はProject追加、`Command+,` はSettingsに割り当てる。
- [x] Drag操作の代替として、カード上のMoveボタンとcontext menuを維持する。
- [x] Task / Project inspector は `Command+S` で保存、`Command+Return` で提案適用、`Command+Delete` で削除確認を開ける。
- [ ] VoiceOver label、focus order、button help、destructive confirmationを確認する。
  - [x] Task card、column add、status move controlにVoiceOver label/helpを付け、delete/archiveのconfirmationをsource testで固定する。
  - [x] Task card本体のOpen Detailsとstatus move controlsを別フォーカス対象に分け、支援技術で移動ボタンがカード要約に埋もれないことをsource testで固定する。
  - [x] Sidebar -> board detail -> task card -> inspector edit/save/delete のsource-level focus anchorsを固定する。
  - [ ] 実機VoiceOverでProject board -> card -> inspectorのfocus orderを確認する。
- [x] `script/capture_ui_evidence.sh` は一時HOME、seed済みProject board、Light/Dark/System切替、window captureを使う。
- [ ] Light/Dark/System切替後にカード、サイドバー、インスペクタのコントラストが破綻しないことをスクリーンショットで確認する。
- [ ] 完了条件: マウス、キーボード、支援技術のどれでも主要CRUDが完結する。

## P11-040: Competitor benchmark and feature fit

- [ ] Notion、Todoist、Linear、Motion を2-4時間で触り、SoloPMに関係する機能だけを `docs/product/competitor-benchmark.md` に記録する。
- [x] 公式docs/product pageベースの desk research を `docs/product/competitor-benchmark.md` に記録する。
- [x] Notion: 柔軟だが個人PM用途では構造化と運用設計が重い。SoloPMは「音声/AIで構造化済みのProject/Taskに落とす」ことで差別化する。
- [x] Todoist: 速いcaptureと今日の整理が強い。SoloPMはInbox/Todayの即時入力とAI分類を取り込む。
- [x] Linear: issue/project/cycleの速度とキーボード操作が強い。SoloPMは個人向けにstatus移動とProject進捗だけを取り込む。
- [x] Motion: AIスケジュールと自動調整が強いが、提案理由が見えないと不安になる。SoloPMは提案理由、適用前確認、local-firstを維持する。
- [x] 完了条件: 競合比較が機能一覧ではなく、ユーザーの困りごととSoloPMの採用/非採用判断に結びつく。

## P11-041: VC/investor-grade product review loop

- [x] 各実装サイクルで `Problem / User pull / Retention hook / Monetization / Risk` をセルフレビューする。
- [x] 「便利そう」だけの機能はIssue化せず、クリック数削減、継続利用、課金理由のどれに効くかを書く。
- [x] Pro機能はFree体験を壊さず、しかしProの価値がSettings/Sync/MCP画面で理解できるようにする。
- [x] OSSとして、BYOK provider追加、MCP compliance fixtures、local-first data modelを外部contributorが触れる形にする。
- [x] 完了条件: 実装完了だけでなく、投資判断の観点で「なぜ伸びるか / なぜ課金されるか」を説明できる。

## Exit Gate

- [x] `docs/mcp-compliance.md` が公式仕様と実装差分を説明している。
- [x] OpenAI / Claude / Gemini / Groq / OpenCode のprovider計画がSettingsとdomain modelに反映されている。
- [x] 実装済みprovider以外は保存不可または明確なunavailable表示になっている。
- [x] Freeユーザーは外部同期を開始できず、外部通信も発生しない。
- [x] Proユーザーでもsync backend未構成時はmock successにならない。
- [ ] UX click-path auditで主要操作のクリック数が記録され、改善PRと紐づいている。
- [ ] `ui-samples/` を参考にした画面密度・インスペクタ・Settingsの改善がスクリーンショットで検証されている。
- [x] 競合benchmarkから採用/非採用判断が残っている。
- [x] `swift test`、`./scripts/ci.sh`、`xcodebuild ... -scheme SoloPM build` がgreen。

## Source Notes

- MCP specification 2025-11-25: https://modelcontextprotocol.io/specification/2025-11-25
- MCP lifecycle: https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle
- MCP tools: https://modelcontextprotocol.io/specification/2025-11-25/server/tools
- MCP Inspector: https://modelcontextprotocol.io/docs/tools/inspector
- OpenAI API reference: https://developers.openai.com/api/reference/overview/
- Anthropic Messages API: https://docs.anthropic.com/en/api/messages
- Gemini API docs: https://ai.google.dev/gemini-api/docs
- Gemini OpenAI compatibility: https://ai.google.dev/gemini-api/docs/openai
- Groq OpenAI compatibility: https://console.groq.com/docs/openai
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
