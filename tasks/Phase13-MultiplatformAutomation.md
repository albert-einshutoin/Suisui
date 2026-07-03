# Phase 13: Multiplatform Automation

目的は、SoloPM を macOS-first の個人PMアプリから、iOS / Web / macOS で使える会話ベースのタスク管理&自動化ツールへ拡張するための実装計画を固定すること。既存の local-first、BYOK、approval-first、audit-first の境界は維持し、Cloud Sync / Cloud Relay / Hosted MCP / Harness を段階的に追加する。

参照: `docs/product/multiplatform-automation.md`

## Product Bar

- iOS、Web、macOS のどこからでもタスク一覧、作成、完了、ステータス変更、期日変更ができるか。
- 会話から生成された変更が、必ず Action Plan / pending action / audit log のいずれかに残るか。
- Mac が起動していなくても、Cloud Relay がタスク作成または pending action を受け付け、後から各デバイスへ同期できるか。
- App / Project docs をAIに渡す場合、ユーザーが対象ドキュメント、理由、変更内容、承認要否を確認できるか。
- Harness で provider prompt、task mutation、document-scoped automation、MCP compatibility を再現可能に検証できるか。

## Non-Goals

- 初期iOSで macOS と同等のローカルファイル自動生成を実装しない。
- 初期WebでOS固有のCalendar / Reminders / filesystem writeを直接実行しない。
- Cloud LLM が無制限にローカルデータを変更するモデルにしない。
- Team / RBAC / organization policy は personal cross-device sync が安定するまで実装しない。

## P13-001: Shared domain contract

- [x] Project / Task / Conversation / Document / ActionPlan / AutomationRequest / HarnessRun の同期対象モデルを定義する。
- [x] 既存SQLite schemaからSync API向けDTOへ変換するadapterを作る。
- [x] task status、due date、project assignment、priority、source command、audit metadataの互換性テストを追加する。
- [x] `ActionTool.taskUpdate` / `taskComplete` / task project move / due date update が platform-neutral に表現できることを確認する。
- [x] 完了条件: macOS local DBと将来のSync payloadで同じタスク変更を表現できる。

## P13-002: Conversation task operations

- [x] 会話入力から task list / create / update / complete / move / due-date change を生成する intent model を整理する。
- [x] LLM providerに依存しないAction Plan validationを通す。
- [x] 「タスクを列挙して」「これを進行中にして」「明日までにして」のような会話ケースをfixture化する。
- [x] write系はapproval policyを通し、read/list系は不要な承認を求めない。
- [x] 完了条件: 会話ベースでタスク列挙とステータス変更ができ、監査ログに残る。

## P13-003: Cloud Sync foundation

- [x] E2EE前提のsync ledger設計を作る。
- [x] Project / Task / safe Settings / Conversation metadata の同期対象と除外対象を明文化する。
- [x] Provider API key、MCP secret、OAuth token がplaintext sync対象に入らないテストを追加する。
- [x] offline create / update / conflict / deleted recovery のmerge policyを決める。
- [x] 完了条件: iOS/Web/macOSが共有する最小タスクデータを安全に同期できる設計になる。

## P13-004: iOS companion MVP

- [x] SwiftUI iOS targetのpackage/app構成を決める。
- [x] Sign in / entitlement restore / device registration flowを設計する。
- [x] Inbox / Today / Project task list / board-lite status controls を実装する。
- [x] 会話入力、音声入力、Shortcuts、Share Sheetの初期範囲を決める。
- [x] Pending action approval inboxを作る。
- [x] 完了条件: iOSからタスク作成、完了、ステータス変更、期日変更、承認ができる。

## P13-005: Web app MVP

- [x] Web frontend / backend boundaryを決める。
- [x] Task board / list / Project docs / conversation / automation reviewを実装する。
- [x] Account / billing / devices / relay tokens の管理画面を設計する。
- [x] Webから実行できないOS-bound actionを明示するUIを作る。
- [x] 完了条件: Webから基本タスク管理とCloud Relay管理ができる。

## P13-006: Cloud Relay and Hosted MCP

- [x] User-owned endpoint credential、token、revocation、rate limitを設計する。
- [x] `task_create`、`task_update`、`task_complete`、due-date update、project moveのHosted MCP schemaを定義する。
- [x] Mac未起動時は task または pending action としてsync ledgerへ保存する。
- [x] destructive / external write はpending approvalへ倒す。
- [x] audit logにsource client、tool name、arguments redaction、approval stateを残す。
- [x] 完了条件: 外部LLM/APIからMac未起動でもタスク作成でき、危険な操作は承認待ちになる。

## P13-007: Document-scoped automation

- [x] App docs / Project docs / Task artifacts / external sources のscope modelを作る。
- [x] AI requestごとに「参照したドキュメント」「理由」「提案変更」「承認要否」を表示する。
- [x] ドキュメントから準備タスク、成果物ドラフト、リリースノート、PR planを生成するtool flowを設計する。
- [x] embeddings / FTS / provider prompt context のどこで処理するかを選べるadapterにする。
- [x] 完了条件: 設定されたdocsだけをAIに渡し、成果物や事前準備タスクをreviewableに生成できる。

## P13-008: SoloPM Harness

- [x] Provider prompt regression、task mutation flow、document-scoped automation、MCP compatibilityのscenario schemaを作る。
- [x] Local harnessとCloud-triggered harnessを同じ結果形式にする。
- [x] 実行履歴、diff、失敗理由、redacted logsを保存する。
- [x] Sync / Pro planで履歴保持期間とstorage扱いを分ける。
- [x] 完了条件: 複数platform・複数providerでも自動化が壊れていないことを再現可能に検証できる。

## P13-009: Pricing and packaging update

- [x] `docs/product/pricing.md` に iOS/Web/macOS access、document-scoped automation、Harness retention のplan境界を反映する。
- [x] Free / Sync / Pro / Team のUI表現とFeatureGateを更新する。
- [x] Free usersがクラウド実行前に必ずupgrade gateで止まるテストを追加する。
- [x] 完了条件: 価格案と実装gateが矛盾しない。

## Verification

- [x] `swift test --filter SyncEntitlementTests`
- [x] `swift test --filter ProjectBoardStoreTests`
- [x] `swift test --filter GeminiDirectProviderTests`
- [x] Hosted MCP / Cloud Relay schema tests
- [x] iOS target build
- [x] Web app unit/e2e tests
- [x] Harness scenario smoke
