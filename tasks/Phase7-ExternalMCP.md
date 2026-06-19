# Phase 7: External MCP

目的は、内蔵 Tool Registry で固めた安全モデルを保ったまま、外部 MCP server を追加できるようにすること。MCP は便利だが実行境界が広がるため、permission、audit、timeout、UI preview を必須にする。

## Scope

- External MCP stdio client
- MCP spec 2025-11-25 baseline
- MCP permission UI
- MCP execution log
- Custom MCP registration

## Non-goals

- 外部 MCP の自動 install
- dangerous tool の自動実行
- remote MCP を MVP 同等に扱うこと
- ユーザー許可なしの credential 共有

## Checklist

### P7-001: MCP client architecture

- [x] MCP spec 2025-11-25 を基準に client interface を設計する。
- [x] stdio transport を最初の transport にする。
- [x] Streamable HTTP は後続に残す。
- [x] テスト: fake MCP server で initialize、tools/list、tools/call を確認する。
- [x] 完了条件: 内蔵 Tool と外部 MCP Tool を registry 上で区別できる。

実装メモ:
- `MCPClient` は `initialize`、`notifications/initialized`、`tools/list`、`tools/call` を JSON-RPC 2.0 model として扱う。
- `ExternalMCPToolExecutor.call` は実行 `tools/call` の前に `initialize -> notifications/initialized` を通すため、Settingsの接続確認とは別経路の実行でもMCP lifecycleを破らない。同じ `MCPClient` の再利用では初期化結果をcacheし、1セッション内で `initialize` を再送しない。
- `MCPProtocolVersion.v2025_11_25` を protocol negotiation の基準値にした。
- `MCPClientTransport` protocol で stdio transport を先に差し込める構成にし、Streamable HTTP は同じ protocol の後続 adapter として残した。
- `ToolOrigin.externalMCP` により、内蔵 `ActionTool` と外部 MCP tool を registry 上で区別する。

### P7-002: MCP server registration

- [x] command、args、env、working directory、display name を登録できる UI を作る。
- [x] env に secret を直接書かせず、Keychain reference を使う設計にする。
- [x] registration は disabled default にする。
- [x] テスト: invalid command、missing binary、disabled server を確認する。
- [x] 完了条件: ユーザーが意図した server だけ起動できる。

実装メモ:
- `MCPServerRegistration` は `command`、`arguments`、`environment`、`workingDirectory`、`displayName`、`isEnabled` を保持する。
- `MCPEnvironmentReference.keychain(SecretKey)` のみを許可し、raw secret string を registration に入れない。
- `MCPServerRegistrationDisplayModel` / `MCPEnvironmentDisplayRow` を Settings UI へ渡せる表示モデルとして追加した。
- `MCPStdioServerLauncher` は disabled server を起動前に拒否し、validator で command / binary availability を確認する。

### P7-003: Tool permission mapping

- [x] 外部 MCP tool を `Read`、`Draft`、`Write with approval`、`Dangerous` に分類する。
- [x] 分類不能な tool は default で disabled にする。
- [x] tool description と schema を UI で確認できるようにする。
- [x] テスト: unknown risk tool が実行不可になることを確認する。
- [x] 完了条件: 外部 tool でも SoloPM の safety model が壊れない。

実装メモ:
- `ExternalMCPToolClassifier` は explicit policy がない tool を `.disabled` に倒す。
- `ExternalMCPToolRegistry.assertExecutable` は disabled / dangerous / approval missing を実行前に止める。
- `ExternalMCPToolCatalogRow` は tool title、description、permission label、input schema summary を UI へ渡す。

### P7-004: MCP execution preview

- [x] 外部 MCP call は実行前に server、tool、args、risk を表示する。
- [x] args の secret redaction を行う。
- [x] Write 系は Review UI の承認 flow を必ず通す。
- [x] テスト: approval なし write MCP call が拒否されることを確認する。
- [x] 完了条件: 内蔵 Tool と同じ確認体験になる。

実装メモ:
- `ExternalMCPExecutionPreview` は server、tool、permission、schema、redacted args summary を保持する。
- `ExternalMCPToolExecutor.preview` と `call` の両方で `DeveloperSecretRedactor` を通す。
- `writeWithApproval` は `ToolExecutionContext.approvalToken` がない限り `approvalRequired` で拒否する。

### P7-005: Process lifecycle and timeout

- [x] MCP server process の起動、health check、timeout、shutdown を管理する。
- [x] hung process は kill し、audit log に残す。
- [x] stdout / stderr logging は secret redaction する。
- [x] テスト: timeout、crash、invalid JSON-RPC response を fake server で確認する。
- [x] 完了条件: 外部 process の失敗でアプリ全体が落ちない。

実装メモ:
- `MCPProcessLifecycleManager` は start / healthCheck / shutdown / killHungProcess を process protocol 越しに管理する。
- `ExternalMCPToolExecutor` は `MCPClientError.timeout` を検知して `MCPProcessController.kill` を呼び、audit failure に残す。
- stdout / stderr 由来の error summary は audit metadata に入る前に redaction する設計にした。
- invalid JSON-RPC response は `MCPClientError.invalidResponse` として扱い、例外でアプリ全体を落とさない。

### P7-006: MCP audit log

- [x] server name、tool name、risk、approval、duration、result、error を記録する。
- [x] args は summary 化し、secret を残さない。
- [x] ユーザーが後から external call の履歴を確認できる画面を作る。
- [x] テスト: success / failure / timeout / redaction を確認する。
- [x] 完了条件: 外部 MCP の実行責任を追跡できる。

実装メモ:
- audit category は `external_mcp` に固定し、started / succeeded / failed を記録する。
- metadata に server name、tool name、risk、approval、duration、result、error、redacted arguments を入れる。
- `ExternalMCPAuditHistory.rows` / `ExternalMCPAuditHistoryRow` を履歴画面用の表示モデルとして追加した。

### P7-007: External MCP test kit

- [x] development 用 fake MCP server を用意する。
- [x] read tool、write tool、danger tool、slow tool、invalid response tool を持たせる。
- [x] CI で MCP client regression test を走らせる。
- [x] 完了条件: 実外部 server なしで安全境界を検証できる。

実装メモ:
- `ExternalMCPTestKit` は read / write / dangerous / slow / invalid response tool definitions を返す。
- `RecordingMCPTransport` により、実外部 server なしで initialize、tools/list、tools/call、timeout、invalid response を回帰テストできる。
- `ExternalMCPTests` は SwiftPM test target に入っているため、通常の `swift test` で CI 回帰テストとして実行される。

## Exit Gate

- [x] stdio MCP server を登録、起動、tools/list、tools/call できる。
- [x] 分類不能 / dangerous tool は実行不可。
- [x] Write tool は approval 必須。
- [x] timeout / crash でアプリが落ちない。
- [x] MCP 実行履歴が audit log に残る。

検証:
- `swift test --filter ExternalMCPTests`
