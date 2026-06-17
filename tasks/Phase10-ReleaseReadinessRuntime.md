# Phase 10: Release Readiness Runtime

目的は、Phase 0-9 で作った foundation を「デモではなく、毎日起動して使えるプロダクト」に引き上げること。外部 SaaS 連携は除外し、ローカル永続データ、内蔵 CRUD、Keychain、AI BYOK、MCP registration の安全境界を実働化する。

## Product Bar

投資家 / VC 視点では、次の問いに答えられない状態を release ready と呼ばない。

- 初回起動後、ユーザーは 60 秒以内にタスクを作れるか。
- アプリを再起動しても Project / Task / settings / audit が失われないか。
- demo / fake / in-memory の成功に見える挙動が runtime に混ざっていないか。
- API key や token は SQLite、UserDefaults、log、screenshot に残らないか。
- 失敗時に「何を設定すれば動くか」がユーザーに伝わるか。
- 外部 SaaS なしでも、SoloPM 単体で task board + review execution の価値があるか。

## Scope

- Runtime dependency container
- SQLite-backed Project / Task / Knowledge / audit execution path
- Task / Project CRUD UI
- Keychain-backed AI provider setup
- Text-first Action Plan generation
- Optional recording flow with non-demo STT failure
- MCP registration connection test and tool catalog refresh
- Release readiness self-review

## Non-goals

- Google / Slack / Notion / GitHub などの外部 SaaS 連携
- MCP server の自動 install
- ユーザー承認なしの write 実行
- cloud-only storage
- fake data seed
- dangerous tool 実行

## Checklist

### P10-001: Runtime dependency audit

- [x] `Sources/` 内の demo / fake / in-memory / skeleton / placeholder を列挙する。
- [x] test-only fake と runtime fallback を分類する。
- [x] runtime に残っている fake 成功経路を P0 として切り出す。
- [x] 完了条件: release blocker が code path と task に紐づいている。

### P10-002: Durable app container

- [x] `SoloPMApp` 起動時に SQLite、Keychain、audit logger、ToolRegistry を 1 つの app container から生成する。
- [x] Project board と Review execution が同じ SQLite DB を使う。
- [x] DB open / migration 失敗時は in-memory fallback せず、明示的な error state を出す。
- [x] テスト: app factory が demo provider / in-memory DB fallback を runtime に入れないことを確認する。
- [x] 完了条件: review 実行で作った task が board に永続表示される。

### P10-003: Task CRUD completion

- [x] Task delete / archive の store API を追加する。
- [x] Board card / inspector から task を削除できる。
- [x] 削除前に確認し、取り消せないことを明示する。
- [x] テスト: create / read / update / delete が SQLite で通る。
- [x] 完了条件: task board が CRUD として閉じている。

### P10-004: Project CRUD completion

- [x] Sidebar から project を作成できる。
- [x] Project title を編集できる。
- [x] Project status / complete を編集できる。
- [x] active project に紐づく task 作成ができる。
- [x] テスト: project create / title update が board snapshot に反映される。
- [x] テスト: project complete が board snapshot に反映される。
- [x] 完了条件: Inbox だけでなくユーザーの project 管理ができる。

### P10-005: Keychain-backed settings

- [x] Settings で OpenAI API key を保存 / 削除できる。
- [x] key は Keychain のみに保存し、UserDefaults / SQLite へは保存しない。
- [x] workspace / notification 設定を UserDefaults に保存する。
- [x] AI provider / STT provider 選択を UserDefaults に保存する。
- [x] テスト: secret redaction、empty key delete、settings persistence を確認する。
- [x] 完了条件: LLM 実行が demo ではなく BYOK provider で動く。

### P10-006: Text-first Action Plan runtime

- [x] `DemoPlanningProvider` を runtime から削除する。
- [x] API key 未設定時は Generate Plan が設定誘導 error を返す。
- [x] LLM で生成された ActionPlan は既存 Review UI で承認して実行する。
- [x] テスト: missing key、provider error、valid plan -> review ready を確認する。
- [x] 完了条件: text input -> plan -> review -> execute -> persistent board が通る。

### P10-007: Recording without fake transcript

- [x] runtime の STT provider は固定 transcript / demo plan を返さない。
- [x] STT 未設定時は録音後に設定誘導 error を出す。
- [x] 可能なら OpenAI Transcribe BYOK adapter を追加する。
- [x] テスト: missing key / unavailable provider / recorded audio state reset を確認する。
- [x] 完了条件: Record が「動いているふり」をしない。

### P10-008: MCP settings live check

- [x] 登録済み MCP server の command validation を Settings から実行できる。
- [x] enabled server に対して initialize / tools/list を試せる。
- [x] tool catalog と audit history を Settings に表示する。
- [x] テスト: disabled、missing binary、invalid response、successful tools/list を確認する。
- [x] 完了条件: fake MCP server ではなく、ユーザー登録 server の接続可否が UI で分かる。

### P10-009: Release safety pass

- [x] `rg` で runtime source に demo / fake / in-memory fallback がないことを確認する。
- [x] `swift test`、`xcodebuild`、`./scripts/verify.sh`、`./script/build_and_run.sh --verify` を通す。
- [x] screenshot で empty state、CRUD、Settings error を確認する。
- [x] security pass で secret が DB / log / settings に保存されないことを確認する。
- [x] 完了条件: public alpha として「動くが外部連携は未対応」と正直に出せる。

### P10-010: MCP test kit production isolation

- [x] `Sources/` に fake MCP server / fake transport helper が含まれていないことを regression test で確認する。
- [x] MCP fake server kit は `Tests/` 配下の test support に隔離する。
- [x] 既存 MCP client / settings / execution tests は test support 経由で維持する。
- [x] 完了条件: shipping module に MCP mock server 実装を含めず、ユーザー登録 server の live check だけを runtime path に残す。

### P10-011: Voice capture dependency injection hardening

- [x] `VoiceCaptureViewModel` が fake recorder / fake STT を default injection しないことを regression test で確認する。
- [x] Runtime app は `AVFoundationAudioRecorder` と Settings 由来 STT provider を明示注入する。
- [x] Unit tests は fake dependencies を明示的に渡す。
- [x] 完了条件: text / recording flow が依存未指定で fake 成功しない。

### P10-012: MCP secret resolver hardening

- [x] `MCPStdioServerLauncher` の default が `InMemorySecretStore` に依存しないことを regression test で確認する。
- [x] Secret が必要な MCP environment は Keychain-backed resolver を明示注入しない限り `missingSecret` にする。
- [x] Runtime app は `KeychainSecretStore` を使う `SecretStoreMCPEnvironmentResolver` を明示注入する。
- [x] 完了条件: MCP runtime path が in-memory secret fallback に依存しない。

### P10-013: MCP execution audit hardening

- [x] `ExternalMCPToolExecutor` が `InMemoryAuditLogger` を default injection しないことを regression test で確認する。
- [x] MCP tool execution は caller が audit logger を明示注入する。
- [x] 既存 tests は in-memory audit logger を test helper で明示注入する。
- [x] 完了条件: 外部 MCP call が永続監査なし default で成功しない API になる。

### P10-014: AI/STT secret store injection hardening

- [x] Chat Completions provider が `InMemorySecretStore` を default injection しないことを regression test で確認する。
- [x] OpenAI Transcribe provider が `InMemorySecretStore` を default injection しないことを regression test で確認する。
- [x] Runtime app は `KeychainSecretStore` を明示注入する。
- [x] Tests は `InMemorySecretStore` を明示注入する。
- [x] 完了条件: AI / STT provider が秘密情報 store 未指定で動作しない。

### P10-015: Shortcut client injection hardening

- [x] `ShortcutSettingsViewModel` が `InMemoryShortcutClient` を default injection しないことを regression test で確認する。
- [x] Tests は shortcut client を明示注入する。
- [x] 完了条件: runtime UI state が client 未指定で in-memory 成功しない。

### P10-016: ToolRegistry in-memory factory isolation

- [x] `Sources/` に `ToolRegistryFactory.inMemoryPhase2MVP` が含まれていないことを regression test で確認する。
- [x] In-memory ToolRegistry factory は `Tests/` 配下の test support に隔離する。
- [x] 既存 E2E-ish unit tests は test support factory 経由で維持する。
- [x] 完了条件: shipping module に in-memory CRUD / system client registry factory を含めない。

### P10-017: Fake voice/planning provider isolation

- [x] `Sources/` に `FakeAudioRecorder` / `FakeSTTProvider` / `FakeLLMProvider` が含まれていないことを regression test で確認する。
- [x] Voice / STT / LLM の fake 実装は `Tests/` 配下の test support に隔離する。
- [x] 既存 unit tests は test support の fake 実装を明示利用する。
- [x] 完了条件: shipping module の public API から fake voice/planning provider を除去する。

## PDCA Loop

各サイクルで以下を繰り返す。

1. Plan: P0 blocker を 1 つ選び、失敗テストを先に書く。
2. Do: 最小実装で runtime path を実働化する。
3. Check: unit test、build、手動起動、セキュリティ grep、VC 視点レビューを行う。
4. Act: release blocker が残る場合は task に戻し、同じコミットに押し込まず次の小粒度コミットへ分ける。

## Exit Gate

- [x] Runtime app path に demo success provider がない。
- [x] Project / Task の CRUD が UI から完結する。
- [x] Review execution は persistent board DB に書く。
- [x] AI key は Keychain に保存される。
- [x] API key 未設定時に fake plan が作られない。
- [x] 外部 SaaS なしで task board + text plan + review execution の価値が成立する。
- [x] リリース前検証コマンドが全て green。

## Implementation Notes

- Runtime composition は `Sources/SoloPMApp/SoloPMApp.swift` の `AppPreviewFactory` を廃止または改名して、preview ではなく production app container として扱う。
- SQLite path は `~/Library/Application Support/SoloPM/SoloPM.sqlite` を primary にする。
- API key は `KeychainSecretStore` を使い、UI 表示は saved / not configured の状態だけにする。
- 外部 SaaS connectors は Phase 10 の release path から外す。既存 protocol / fake tests は regression 用に残す。
- Core の fake / in-memory 型は unit test と preview fixture として残してよいが、runtime container からは参照しない。

## Verification

- `swift test`
- `xcodebuild -workspace .swiftpm/xcode/package.xcworkspace -scheme SoloPM -destination 'platform=macOS' build`
- `./scripts/verify.sh`
- `./script/build_and_run.sh --verify`
