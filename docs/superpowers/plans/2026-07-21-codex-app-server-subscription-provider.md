# Codex App Server Subscription Provider Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 各ユーザーのMac上でCodex App Serverを起動し、Codex管理のChatGPTログインとユーザー自身のCodex利用枠を使って、Suisuiの音声タスク支援用Action Planを安全に生成できるようにする。

**Architecture:** `codexLocal`をOpenAI API key providerとは別のmacOSローカルproviderとして追加し、Suisuiは`codex app-server --listen stdio://`のJSON-RPCだけを扱う。ChatGPT OAuth token、refresh token、`~/.codex/auth.json`には触れず、認証・保存・更新をCodexへ委譲する。初期リリースはexperimental capabilityを有効にせず、Action Plan生成専用のephemeral thread、read-only sandbox、approval policy `never`に固定する。SuisuiのTool実行は従来どおりAction Plan、Assistant Queue、Review、Execution Receipt境界で行う。

**Tech Stack:** Swift 6、Foundation `Process` / `Pipe`、Swift Concurrency、JSON-RPC 2.0、XCTest、Codex CLI App Server、既存`LLMProvider` / `ActionPlanResponseParser` / `AssistantQueueCostPreview` / `ExecutionReceipt`。

---

## 調査結論と採用境界

### 結論: 条件付きで実現可能

- Codex App Serverの公開APIは`account/login/start`に`type: "chatgpt"`を持ち、ブラウザ認証URLを返す。
- `chatgpt`認証ではCodexがOAuth tokenを永続化し、refreshも担当する。Suisuiはtokenを受け取らない。
- `account/read`は`type: "chatgpt"`、メール、`planType`を返し、`account/rateLimits/read`と通知で利用枠を確認できる。
- ChatGPTへログインしたCodexの利用は、そのユーザー／workspaceのCodex共通利用枠・クレジットを消費する。
- したがって、各ユーザーのMac・OSユーザーコンテキストでローカルapp-serverを起動する構成なら、各ユーザー自身の契約を利用できる。
- app-serverはcommand/file editを含むcoding agent surfaceでもある。標準の音声タスク支援へ採用するには、組み込みtoolをturn開始前に無効化できることを互換性spikeで証明する必要がある。
- Enterprise向けclientはCompliance Logs上の`clientInfo.name`識別が必要になるため、一般提供前にOpenAIへSuisui client名の登録可否を確認する。

### 禁止する構成

- Suisui cloudがユーザーのChatGPT tokenを預かって代理実行する。
- `~/.codex/auth.json`を読み、tokenをSuisui Keychain、SQLite、UserDefaults、sync payloadへ複製する。
- 内部専用の`chatgptAuthTokens`モードを使う。
- ChatGPT契約をOpenAI API creditとして扱う、またはOpenAI Responses APIへtokenを転用する。
- 複数のOSユーザー、Suisuiユーザー、workspaceで1つのapp-server processまたは認証状態を共有する。
- MacがofflineのときにWeb/iOSからSuisui cloud経由でユーザー契約を使えるように見せる。

### Product GO / NO-GO gate

`codexLocal`をSettingsの選択肢へ出す前に、以下をすべて満たす。

1. 対応するCodex CLI最低versionで、`account/read`、`account/login/start`、`model/list`、`thread/start`、`turn/start`がfixtureとlive smokeの両方で成立する。
2. Suisui parent processが`auth.json`を直接openしていないことをruntime testで確認する。認証を所有するCodex child processのアクセスは想定内としてPIDを区別する。
3. `chatgptAuthTokens`をproduction enum/APIから表現不能にする。
4. Action Plan生成中にcommand、file change、permission requestが来た場合、承認せずturnを中断してfail closedにする。
5. Receiptが`userProviderBilled`を示し、Suisui managed costと合算しない。
6. Enterprise/Business workspaceでCodex Localが管理者により無効な場合、再ログインloopではなくworkspace policyエラーを表示する。
7. 組み込みshell/file/web/MCP toolをturn開始前に無効化できることをadversarial promptで証明する。できない場合はSettings一般提供をNO-GOとし、Developer Modeの明示的なcoding workflowだけへscopeを縮小する。
8. Enterprise対応を表明する前に、`clientInfo.name = "suisui"`をOpenAIのknown clientsへ登録する手続きを完了するか、未登録clientとしてCompliance Logs上の制約を製品文書へ明示する。

## File Structure

### New production files

- `Sources/SuisuiCore/Planning/CodexAppServerProtocol.swift`: 安定利用するJSON-RPC request/response/notificationとdomain型だけを定義する。
- `Sources/SuisuiCore/Planning/CodexAppServerTransport.swift`: app-server stdio transport protocol、macOS `Process`実装、request correlation、notification stream、shutdownを担当する。
- `Sources/SuisuiCore/Planning/CodexAppServerAccountClient.swift`: initialize、account read/login/logout、rate limit、model listを型付きAPIにする。
- `Sources/SuisuiCore/Planning/CodexAppServerProvider.swift`: ephemeral thread/turnをAction Plan生成へ変換する`StreamingLLMProvider`。
- `Sources/SuisuiCore/Planning/CodexAppServerRuntimeConfiguration.swift`: executable absolute path、version、opt-inをAppKit非依存で検証する。
- `Sources/SuisuiApp/Composition/CodexAppServerRuntimeFactory.swift`: 実行ファイル検出、version gate、production transport/client/provider組み立てを行う。
- `Sources/SuisuiApp/Views/CodexAccountSettingsView.swift`: 接続状態、契約種別、ログイン、ログアウト、利用枠、課金境界を表示する。
- `docs/adr/0011-codex-app-server-user-subscription-boundary.md`: user-local subscription providerとAPI/BYOK/managed providerを分離する決定を残す。
- `script/check_codex_app_server_smoke.sh`: opt-in live smoke。secretを出さずinitialize/account/model/thread/turnを検証する。
- `Tests/Fixtures/CodexAppServer/v0.144.1/`: tokenを含まないJSONL fixture。

### Existing files to modify

- `Sources/SuisuiCore/Planning/LLMProviderCatalog.swift`: `codexLocal`とauth/execution/billing/capability metadataを追加する。
- `Sources/SuisuiCore/Planning/LLMProvider.swift`: app-server固有エラーを既存user-facing taxonomyへ安全に写像する。
- `Sources/SuisuiCore/App/AppSettings.swift`: executable path、model、opt-in、typed readiness/account snapshotを追加する。
- `Sources/SuisuiCore/App/AssistantQueue.swift`: Codex subscriptionのcost previewを`userProviderBilled`として生成する。
- `Sources/SuisuiCore/App/ExecutionReceipt.swift`: provider-billed sourceを曖昧な文字列ではなく型で保持する。
- `Sources/SuisuiApp/Composition/VoiceRuntimeFactory.swift`: `.codexLocal`を専用factoryへ委譲する。
- `Sources/SuisuiApp/Views/SettingsFeatureViews.swift`: selected provider fieldsとして`CodexAccountSettingsView`を表示する。
- `Sources/SuisuiApp/Resources/en.lproj/Localizable.strings`: Codex接続・課金・失敗表示を追加する。
- `Sources/SuisuiApp/Resources/ja.lproj/Localizable.strings`: 同じkeyの日本語を追加する。
- `tasks/Phase11-ProviderSyncUXProductization.md`: `P11-016 Codex App Server user-subscription provider`を追加する。
- `docs/product/ai-billing-model.md`: ChatGPT Codex枠、BYOK API、Suisui managed billingの違いを追記する。
- `docs/security/threat-model.md`: auth store非アクセス、subprocess、stdio spoofing、workspace境界を追記する。
- `docs/release/privacy-security.md`: diagnostics/sync/receiptにtokenが入らない検証を追記する。

### New tests

- `Tests/SuisuiCoreTests/CodexAppServerProtocolTests.swift`
- `Tests/SuisuiCoreTests/CodexAppServerTransportTests.swift`
- `Tests/SuisuiCoreTests/CodexAppServerAccountClientTests.swift`
- `Tests/SuisuiCoreTests/CodexAppServerProviderTests.swift`
- `Tests/SuisuiCoreTests/CodexAppServerRuntimeConfigurationTests.swift`
- `Tests/SuisuiCoreTests/CodexAppServerRuntimeFactorySourceTests.swift`
- `Tests/SuisuiCoreTests/CodexAccountSettingsSourceTests.swift`
- `Tests/SuisuiCoreTests/CodexSubscriptionReceiptTests.swift`
- `Tests/SuisuiCoreTests/CodexAppServerSecurityTests.swift`

## Phase A: 公開契約とprovider境界

### Task 1: P11-016 Provider capability contractとADR

**Files:**
- Modify: `Sources/SuisuiCore/Planning/LLMProviderCatalog.swift`
- Modify: `Tests/SuisuiCoreTests/LLMProviderCatalogTests.swift`
- Create: `docs/adr/0011-codex-app-server-user-subscription-boundary.md`
- Modify: `tasks/Phase11-ProviderSyncUXProductization.md`

- [ ] **Step 1: catalogの失敗テストを書く**

```swift
func testCodexLocalDeclaresUserSubscriptionAndMacLocalBoundary() {
    let entry = LLMProviderCatalog.entry(for: .codexLocal)
    XCTAssertEqual(entry.authMode, .providerManagedSubscription)
    XCTAssertEqual(entry.executionLocation, .userMac)
    XCTAssertEqual(entry.billingMode, .userProviderBilled)
    XCTAssertEqual(entry.requestFamily, .codexAppServer)
    XCTAssertNil(entry.apiKeySecretKey)
    XCTAssertTrue(entry.requiresExplicitLocalExecutionApproval)
    XCTAssertFalse(entry.isAvailableInCurrentBuild)
}
```

- [ ] **Step 2: REDを確認する**

Run: `swift test --filter LLMProviderCatalogTests`

Expected: FAIL because `codexLocal`とcapability metadataが存在しない。

- [ ] **Step 3: 最小のtyped capabilityを追加する**

```swift
public enum LLMProviderAuthMode: String, Codable, Sendable {
    case apiKey
    case providerManagedSubscription
    case localProviderStore
    case none
}

public enum LLMProviderExecutionLocation: String, Codable, Sendable {
    case userMac
    case providerCloud
}

public enum LLMProviderBillingMode: String, Codable, Sendable {
    case suisuiManaged
    case userProviderBilled
    case localOnly
}
```

`LLMProviderID.codexLocal`と`LLMRequestFamily.codexAppServer`を追加する。entryは最初`isAvailableInCurrentBuild: false`とし、Phase DのGO gateを通るまでSettingsに出さない。

- [ ] **Step 4: ADRとPhase taskを記載する**

ADRには採用案、API key providerへ統合する案、token抽出案、cloud relay案の4案を比較し、token抽出とcloud relayをRejectedにする。Phase taskの完了条件は本計画のProduct GO gate 6項目をそのまま含める。

- [ ] **Step 5: GREENを確認する**

Run: `swift test --filter LLMProviderCatalogTests`

Expected: PASS。全provider IDにentryがあり、既存provider metadataも明示される。

- [ ] **Step 6: commitする**

```bash
git add Sources/SuisuiCore/Planning/LLMProviderCatalog.swift Tests/SuisuiCoreTests/LLMProviderCatalogTests.swift docs/adr/0011-codex-app-server-user-subscription-boundary.md tasks/Phase11-ProviderSyncUXProductization.md
git commit -m "feat: define Codex subscription provider boundary"
```

### Task 2: 安定JSON-RPC subsetとfixture契約

**Files:**
- Create: `Sources/SuisuiCore/Planning/CodexAppServerProtocol.swift`
- Create: `Tests/SuisuiCoreTests/CodexAppServerProtocolTests.swift`
- Create: `Tests/Fixtures/CodexAppServer/v0.144.1/account-read-chatgpt.json`
- Create: `Tests/Fixtures/CodexAppServer/v0.144.1/login-start-chatgpt.json`
- Create: `Tests/Fixtures/CodexAppServer/v0.144.1/turn-success.jsonl`
- Create: `Tests/Fixtures/CodexAppServer/v0.144.1/turn-approval-request.jsonl`
- Create: `Tests/Fixtures/CodexAppServer/v0.144.1/usage-limit.jsonl`

- [ ] **Step 1: decode/encodeの失敗テストを書く**

```swift
func testChatGPTAccountFixtureDecodesWithoutCredentials() throws {
    let response = try fixtureDecoder.decode(
        CodexAccountReadResponse.self,
        from: fixtureData("account-read-chatgpt.json")
    )
    XCTAssertEqual(response.account, .chatGPT(email: "user@example.com", plan: .plus))
    XCTAssertFalse(String(decoding: fixtureData("account-read-chatgpt.json"), as: UTF8.self).contains("accessToken"))
}

func testInternalTokenInjectionModeCannotBeEncoded() {
    XCTAssertEqual(Set(CodexLoginKind.allCases), [.chatGPTBrowser, .chatGPTDeviceCode])
}
```

- [ ] **Step 2: REDを確認する**

Run: `swift test --filter CodexAppServerProtocolTests`

Expected: FAIL because protocol型とfixtureがない。

- [ ] **Step 3: 使用するsubsetだけを型定義する**

```swift
public enum CodexLoginKind: String, CaseIterable, Codable, Hashable, Sendable {
    case chatGPTBrowser = "chatgpt"
    case chatGPTDeviceCode = "chatgptDeviceCode"
}

public enum CodexPlanType: String, Codable, Sendable {
    case free, go, plus, pro, prolite, team
    case selfServeBusinessUsageBased = "self_serve_business_usage_based"
    case business
    case enterpriseCBPUsageBased = "enterprise_cbp_usage_based"
    case enterprise, edu, unknown
}

public enum CodexAppServerMethod {
    public static let initialize = "initialize"
    public static let accountRead = "account/read"
    public static let accountLoginStart = "account/login/start"
    public static let accountLoginCancel = "account/login/cancel"
    public static let accountLogout = "account/logout"
    public static let accountRateLimitsRead = "account/rateLimits/read"
    public static let modelList = "model/list"
    public static let threadStart = "thread/start"
    public static let turnStart = "turn/start"
    public static let turnInterrupt = "turn/interrupt"
}
```

Request IDは`Int64`、unknown notificationはignore、既知methodのmalformed payloadはfail closedとする。access token、refresh token、API keyを表すpropertyをproduction型へ追加しない。

- [ ] **Step 4: fixtureを固定する**

fixtureはローカル`codex app-server generate-json-schema --experimental`で確認したv0.144.1 shapeからsecret-free最小payloadを作る。`turn-approval-request.jsonl`には`item/commandExecution/requestApproval`を含め、providerが拒否する回帰に使う。

- [ ] **Step 5: GREENとsecret scanを確認する**

Run: `swift test --filter CodexAppServerProtocolTests`

Run: `if rg -n 'accessToken|refreshToken|sk-[A-Za-z0-9]' Tests/Fixtures/CodexAppServer; then exit 1; fi`

Expected: tests PASS、secret scanは0件。

- [ ] **Step 6: commitする**

```bash
git add Sources/SuisuiCore/Planning/CodexAppServerProtocol.swift Tests/SuisuiCoreTests/CodexAppServerProtocolTests.swift Tests/Fixtures/CodexAppServer
git commit -m "feat: define Codex app server protocol subset"
```

## Phase B: ローカルprocessとユーザー認証

### Task 3: actor-based stdio transport

**Files:**
- Create: `Sources/SuisuiCore/Planning/CodexAppServerTransport.swift`
- Create: `Tests/SuisuiCoreTests/CodexAppServerTransportTests.swift`

- [ ] **Step 1: lifecycleとconcurrencyの失敗テストを書く**

```swift
func testConcurrentRequestsAreCorrelatedByIDWhileNotificationsStream() async throws {
    let process = ScriptedCodexProcess(lines: [accountResponse, accountUpdatedNotification, modelResponse])
    let transport = CodexAppServerStdioTransport(process: process)
    async let account = transport.request(method: "account/read", params: .object([:]), timeout: 1)
    async let models = transport.request(method: "model/list", params: .object([:]), timeout: 1)
    XCTAssertEqual(try await account.id, 1)
    XCTAssertEqual(try await models.id, 2)
}
```

timeout、EOF、malformed JSON、duplicate response ID、stderr redaction、cancel時の`turn/interrupt`、graceful terminate後のkillを別testで固定する。

- [ ] **Step 2: REDを確認する**

Run: `swift test --filter CodexAppServerTransportTests`

Expected: FAIL because transportがない。

- [ ] **Step 3: transport protocolとactorを実装する**

```swift
public protocol CodexAppServerTransport: Sendable {
    func start() async throws
    func request(method: String, params: JSONValue?, timeout: TimeInterval) async throws -> CodexJSONRPCResponse
    func notify(method: String, params: JSONValue?) async throws
    func notifications() async -> AsyncStream<CodexJSONRPCNotification>
    func shutdown() async
}

public actor CodexAppServerStdioTransport: CodexAppServerTransport {
    // request counter、pending continuation、reader task、process lifecycleをactor内へ閉じ込める。
}
```

production起動は引数配列`["app-server", "--listen", "stdio://"]`を使い、shell文字列を実行しない。ユーザーのCodex configとの互換性を壊す`--strict-config`は付けない。環境変数は`PATH`、`HOME`、locale、Codexが必要とする標準変数のみallowlistで継承し、`OPENAI_API_KEY`、`CODEX_ACCESS_TOKEN`、SuisuiのKeychain値を渡さない。

- [ ] **Step 4: macOS以外をfail closedにする**

`#if os(iOS) || targetEnvironment(macCatalyst)`ではprocessを起動せず、`.localExecutionUnavailable`を返す。Web/iOSは既存connected-Mac queueへ委譲する。

- [ ] **Step 5: GREENを確認する**

Run: `swift test --filter CodexAppServerTransportTests`

Expected: PASS。並行request、notification、timeout、shutdownを含めてtask leakがない。

- [ ] **Step 6: commitする**

```bash
git add Sources/SuisuiCore/Planning/CodexAppServerTransport.swift Tests/SuisuiCoreTests/CodexAppServerTransportTests.swift
git commit -m "feat: add Codex app server stdio transport"
```

### Task 4: account client、login、rate limit readiness

**Files:**
- Create: `Sources/SuisuiCore/Planning/CodexAppServerAccountClient.swift`
- Create: `Tests/SuisuiCoreTests/CodexAppServerAccountClientTests.swift`

- [ ] **Step 1: account state machineの失敗テストを書く**

```swift
func testBrowserLoginReturnsOnlyURLAndCompletesFromNotification() async throws {
    let transport = RecordingCodexTransport(fixture: .browserLoginSuccess)
    let client = CodexAppServerAccountClient(transport: transport)
    let attempt = try await client.startLogin(.chatGPTBrowser)
    XCTAssertEqual(attempt.authorizationURL.host, "chatgpt.com")
    XCTAssertEqual(try await client.awaitLogin(id: attempt.id), .authenticated(plan: .plus))
    XCTAssertFalse(transport.encodedTraffic.contains("accessToken"))
}
```

cancel、logout、401 refresh、usage limit、workspace policy denial、unknown plan、stale login ID、rate-limit sparse update mergeを固定する。

- [ ] **Step 2: REDを確認する**

Run: `swift test --filter CodexAppServerAccountClientTests`

Expected: FAIL because account clientがない。

- [ ] **Step 3: typed account APIを実装する**

```swift
public protocol CodexAccountServicing: Sendable {
    func initialize(clientVersion: String) async throws
    func readAccount(refresh: Bool) async throws -> CodexAccountSnapshot
    func startLogin(_ kind: CodexLoginKind) async throws -> CodexLoginAttempt
    func cancelLogin(id: String) async throws
    func logout() async throws
    func readRateLimits() async throws -> CodexRateLimitSnapshot
    func listModels() async throws -> [CodexModel]
}
```

initializeは`clientInfo: { name: "suisui", title: "Suisui", version: <app version> }`を送り、experimental capabilityを要求しない。login completionは`account/login/completed`と`account/updated`の両方を受け、login ID一致を確認する。URL schemeは`https`、hostは`chatgpt.com`または`auth.openai.com`だけを許可する。account emailはUI表示専用で、audit/receiptへ保存しない。

- [ ] **Step 4: エラーをuser actionへ写像する**

```swift
public enum CodexAccountReadiness: Equatable, Sendable {
    case notInstalled
    case unsupportedVersion(installed: String, minimum: String)
    case signedOut
    case authenticating
    case ready(plan: CodexPlanType)
    case usageLimited(resetAt: Date?)
    case workspaceDisabled
    case unavailable(redactedReason: String)
}
```

`workspaceDisabled`は再ログインボタンではなく「workspace管理者へ確認」をnext actionにする。

- [ ] **Step 5: GREENを確認する**

Run: `swift test --filter CodexAppServerAccountClientTests`

Expected: PASS。recorded trafficにcredential fieldがない。

- [ ] **Step 6: commitする**

```bash
git add Sources/SuisuiCore/Planning/CodexAppServerAccountClient.swift Tests/SuisuiCoreTests/CodexAppServerAccountClientTests.swift
git commit -m "feat: manage Codex ChatGPT account readiness"
```

## Phase C: 音声タスク支援用Action Plan adapter

### Task 5: tool-free ephemeral planning provider

**Files:**
- Create: `Sources/SuisuiCore/Planning/CodexAppServerProvider.swift`
- Create: `Tests/SuisuiCoreTests/CodexAppServerProviderTests.swift`
- Modify: `Sources/SuisuiCore/Planning/LLMProvider.swift`

- [ ] **Step 1: planning turnの失敗テストを書く**

```swift
func testGeneratePlanUsesStableEphemeralReadOnlyThread() async throws {
    let transport = RecordingCodexTransport(fixture: .validActionPlan)
    let provider = CodexAppServerProvider(transport: transport, account: ReadyCodexAccount())
    _ = try await provider.generatePlan(for: PlanningRequest(userInput: "明日14時に見積もり確認"))
    let start = try XCTUnwrap(transport.request(named: "thread/start"))
    XCTAssertEqual(start.params["ephemeral"], .bool(true))
    XCTAssertEqual(start.params["sandbox"], .string("read-only"))
    XCTAssertEqual(start.params["approvalPolicy"], .string("never"))
    XCTAssertNil(start.params["dynamicTools"])
    XCTAssertNil(start.params["environments"])
    XCTAssertNil(start.params["selectedCapabilityRoots"])
}
```

invalid Action Plan、partial stream、turn failure、usage limit、unauthorized、command approval request、file change approval request、timeout/cancelを固定する。

- [ ] **Step 2: REDを確認する**

Run: `swift test --filter CodexAppServerProviderTests`

Expected: FAIL because providerがない。

- [ ] **Step 3: provider contractを実装する**

```swift
public struct CodexAppServerProvider: StreamingLLMProvider {
    public let providerID = "codex.local"

    public func generatePlanStream(
        for request: PlanningRequest,
        onTextDelta: @escaping @Sendable (String) -> Void
    ) async throws -> PlanningResponse
}
```

処理順は`account/read -> model/list -> thread/start -> turn/start -> agentMessage/delta -> turn/completed`に固定する。promptは既存`PlanningPromptBuilder`を使い、最終textを既存`ActionPlanResponseParser`へ渡す。`item/commandExecution/requestApproval`、`item/fileChange/requestApproval`、`item/permissions/requestApproval`を1件でも受けたら明示的なdeny responseを返して`turn/interrupt`し、`.executionNotApproved`へ写像する。`item/started`または`item/completed`にcommand execution、file change、web search、MCP、dynamic toolが現れた場合もturnを失敗扱いにし、内容をAction Planとして採用しない。

- [ ] **Step 4: tool isolation compatibility spikeを実行する**

stable APIだけで組み込みshell/file/web/MCP toolをmodel-facing tool listから外せる設定を公式schemaとlive app-serverで確認する。空のscratch directory、`ephemeral: true`、`sandbox: "read-only"`、`approvalPolicy: "never"`を使い、「shellでpwdを実行」「HOMEのファイルを読む」「web検索」のadversarial promptを送る。experimentalな`environments`、`selectedCapabilityRoots`、`dynamicTools`は送らない。tool lifecycleが1件でも開始される場合、このTaskはGREENにせず、`.codexLocal`はDeveloper Mode限定へ設計変更する。

- [ ] **Step 5: retryとfallbackを禁止する**

401、usage limit、invalid responseでOpenAI API providerや別modelへsilent fallbackしない。`allowProviderModelFallback`はfalse、timeoutの自動再実行は0回とする。ユーザーがSettingsで明示的にproviderを切り替えるまで同じproviderを維持する。

- [ ] **Step 6: GREENを確認する**

Run: `swift test --filter CodexAppServerProviderTests`

Expected: PASS。危険なserver request fixtureはfail closedし、live compatibility spikeでtool lifecycleは0件になる。

- [ ] **Step 7: commitする**

```bash
git add Sources/SuisuiCore/Planning/CodexAppServerProvider.swift Sources/SuisuiCore/Planning/LLMProvider.swift Tests/SuisuiCoreTests/CodexAppServerProviderTests.swift
git commit -m "feat: generate action plans through Codex app server"
```

### Task 6: runtime factory、version gate、connected-Mac boundary

**Files:**
- Create: `Sources/SuisuiCore/Planning/CodexAppServerRuntimeConfiguration.swift`
- Create: `Sources/SuisuiApp/Composition/CodexAppServerRuntimeFactory.swift`
- Create: `Tests/SuisuiCoreTests/CodexAppServerRuntimeConfigurationTests.swift`
- Create: `Tests/SuisuiCoreTests/CodexAppServerRuntimeFactorySourceTests.swift`
- Modify: `Sources/SuisuiApp/Composition/VoiceRuntimeFactory.swift`
- Modify: `Sources/SuisuiCore/App/AppSettings.swift`
- Modify: `Tests/SuisuiCoreTests/WebAppMVPTests.swift`
- Modify: `Tests/SuisuiCoreTests/DocumentScopedAutomationTests.swift`

- [ ] **Step 1: executable/version boundaryの失敗テストを書く**

```swift
func testFactoryRejectsRelativeOrOldCodexExecutable() throws {
    XCTAssertThrowsError(try CodexAppServerRuntimeConfiguration.validate(
        executablePath: "codex",
        reportedVersion: "0.120.0"
    ))
    XCTAssertNoThrow(try CodexAppServerRuntimeConfiguration.validate(
        executablePath: "/opt/homebrew/bin/codex",
        reportedVersion: "0.144.1"
    ))
}
```

missing file、directory、non-executable、symlink target change、version parse failure、iOS/Web requestのconnected Mac待ちを固定する。

- [ ] **Step 2: REDを確認する**

Run: `swift test --filter 'CodexAppServerRuntime(Configuration|FactorySource)Tests'`

Expected: FAIL because factory/settingsがない。

- [ ] **Step 3: settingsとfactoryを実装する**

```swift
public struct CodexLocalSettings: Codable, Equatable, Sendable {
    public var executablePath: String?
    public var modelID: String?
    public var isLocalExecutionApproved: Bool

    public static let `default` = CodexLocalSettings(
        executablePath: nil,
        modelID: nil,
        isLocalExecutionApproved: false
    )
}
```

初回は自動探索結果を表示候補にするだけで保存・起動しない。ユーザーが絶対pathを確認し、local execution toggleを有効にした後だけ起動する。factoryは`codex --version`を引数配列で実行し、support matrixの最低version以上か確認する。

path/version/approval判定は`CodexAppServerRuntimeConfiguration.validate`へ置き、App targetのfactoryはvalidated configurationを受けてtransport/account/providerを組み立てるだけにする。App targetはtest targetからimportできないため、この責務分離をsource contract testでも固定する。

- [ ] **Step 4: Voice runtimeとremote surfaceを接続する**

`.codexLocal`は`CodexAppServerRuntimeFactory`へ委譲する。Web/iOSからの要求はcloudで実行せず、既存の`.connectedMacRequired` capabilityを付けてqueueする。Mac offline時の表示は「接続中のMacが必要」であり「Codexに接続できない」へ丸めない。

- [ ] **Step 5: GREENを確認する**

Run: `swift test --filter 'CodexAppServerRuntime(Configuration|FactorySource)Tests'`

Run: `swift test --filter WebAppMVPTests`

Run: `swift test --filter DocumentScopedAutomationTests`

Expected: PASS。remote surfaceからapp-server processは起動されない。

- [ ] **Step 6: commitする**

```bash
git add Sources/SuisuiCore/Planning/CodexAppServerRuntimeConfiguration.swift Sources/SuisuiApp/Composition/CodexAppServerRuntimeFactory.swift Sources/SuisuiApp/Composition/VoiceRuntimeFactory.swift Sources/SuisuiCore/App/AppSettings.swift Tests/SuisuiCoreTests/CodexAppServerRuntimeConfigurationTests.swift Tests/SuisuiCoreTests/CodexAppServerRuntimeFactorySourceTests.swift Tests/SuisuiCoreTests/WebAppMVPTests.swift Tests/SuisuiCoreTests/DocumentScopedAutomationTests.swift
git commit -m "feat: compose user-local Codex runtime"
```

## Phase D: 課金表示、Settings、release gate

### Task 7: subscription usageとReceiptの分離

**Files:**
- Modify: `Sources/SuisuiCore/App/AssistantQueue.swift`
- Modify: `Sources/SuisuiCore/App/ExecutionReceipt.swift`
- Modify: `Sources/SuisuiCore/App/ExecutionUsageMeter.swift`
- Create: `Tests/SuisuiCoreTests/CodexSubscriptionReceiptTests.swift`
- Modify: `Tests/SuisuiCoreTests/CostPreviewTests.swift`
- Modify: `Tests/SuisuiCoreTests/ExecutionReceiptTests.swift`
- Modify: `docs/product/ai-billing-model.md`

- [ ] **Step 1: billing attributionの失敗テストを書く**

```swift
func testCodexSubscriptionUsageNeverCountsAsSuisuiManagedCost() {
    let preview = AssistantQueueCostPreview.userProviderBilled(
        provider: "codex.local",
        model: "gpt-5.6-terra",
        note: "Uses the signed-in user's ChatGPT Codex allowance."
    )
    XCTAssertEqual(preview.billingMode, .userProviderBilled)
    XCTAssertFalse(preview.allowsManagedLedgerCharge)
}
```

token usageあり／なし、rate limit reached、credits unavailable、receipt export、redaction、managed ledger aggregation除外、billing source fieldを持たないschema v1 Receiptの後方互換decodeを固定する。

- [ ] **Step 2: REDを確認する**

Run: `swift test --filter CodexSubscriptionReceiptTests`

Expected: FAIL because provider billing sourceが明示されていない。

- [ ] **Step 3: billing sourceを型付けする**

```swift
public enum ExecutionReceiptBillingSource: String, Codable, Sendable {
    case suisuiManaged = "suisui_managed"
    case userAPIKey = "user_api_key"
    case userChatGPTCodex = "user_chatgpt_codex"
    case localCompute = "local_compute"
    case unknown
}
```

Codex App Serverのtoken usageは`ExecutionReceiptUsage`へ記録するが、currency/costを推測しない。rate limit/creditsはaccount snapshotとしてSettingsへ表示し、Receiptへメールやworkspace IDを保存しない。

`ExecutionReceipt.billingSource`は新規Receiptで必須にする一方、既存schema v1 JSONのfield欠落は`.unknown`としてdecodeする。過去Receiptを読めなくする変更、または過去のprovider文字列から課金元を推測するmigrationは行わない。

- [ ] **Step 4: billing docsを更新する**

「ChatGPT Codex枠」「ユーザーAPI key」「Suisui managed」の3列比較を追加し、契約、資格情報の管理者、実行場所、上限、追加請求、offline可否を記載する。

- [ ] **Step 5: GREENを確認する**

Run: `swift test --filter CodexSubscriptionReceiptTests`

Run: `swift test --filter CostPreviewTests`

Run: `swift test --filter ExecutionReceiptTests`

Expected: PASS。managed totalにCodex subscription usageが入らない。

- [ ] **Step 6: commitする**

```bash
git add Sources/SuisuiCore/App/AssistantQueue.swift Sources/SuisuiCore/App/ExecutionReceipt.swift Sources/SuisuiCore/App/ExecutionUsageMeter.swift Tests/SuisuiCoreTests/CodexSubscriptionReceiptTests.swift Tests/SuisuiCoreTests/CostPreviewTests.swift Tests/SuisuiCoreTests/ExecutionReceiptTests.swift docs/product/ai-billing-model.md
git commit -m "feat: attribute Codex subscription usage"
```

### Task 8: Settings login UXとaccessibility

**Files:**
- Create: `Sources/SuisuiApp/Views/CodexAccountSettingsView.swift`
- Modify: `Sources/SuisuiApp/Views/SettingsFeatureViews.swift`
- Modify: `Sources/SuisuiCore/App/AppSettings.swift`
- Modify: `Sources/SuisuiApp/Resources/en.lproj/Localizable.strings`
- Modify: `Sources/SuisuiApp/Resources/ja.lproj/Localizable.strings`
- Create: `Tests/SuisuiCoreTests/CodexAccountSettingsSourceTests.swift`
- Modify: `Tests/SuisuiCoreTests/SettingsReadinessPresentationTests.swift`

- [ ] **Step 1: source/readinessの失敗テストを書く**

```swift
func testCodexSettingsExplainsCredentialAndBillingBoundary() throws {
    let source = try sourceText("Sources/SuisuiApp/Views/CodexAccountSettingsView.swift")
    XCTAssertTrue(source.contains("codex-account-sign-in"))
    XCTAssertTrue(source.contains("codex-account-sign-out"))
    XCTAssertTrue(source.contains("codex-account-usage"))
    XCTAssertTrue(source.contains("ChatGPT Codex allowance"))
    XCTAssertFalse(source.contains("accessToken"))
}
```

signed out、authenticating、ready、usage limited、workspace disabled、unsupported version、process failure、logout failureのpresentationを固定する。

- [ ] **Step 2: REDを確認する**

Run: `swift test --filter CodexAccountSettingsSourceTests`

Expected: FAIL because viewがない。

- [ ] **Step 3: ViewModel stateとUIを実装する**

画面順は「Codex executable」「Local execution approval」「Account」「Plan」「Usage」「Billing boundary」「Model」。Sign inは`authUrl`を`openURL`へ渡し、URLをログへ出さない。Sign outはdestructive confirmation後に`account/logout`を呼ぶ。

```swift
enum CodexAccountSettingsAction {
    case detectExecutable
    case approveLocalExecution(Bool)
    case signIn
    case cancelSignIn
    case refresh
    case signOut
}
```

- [ ] **Step 4: accessibilityを付与する**

sign-in、cancel、refresh、sign-out、usage状態へstable identifier、VoiceOver label、失敗時hintを付ける。色だけでready/limited/errorを区別しない。日本語では「ChatGPTのCodex利用枠を使用。OpenAI APIキー課金ではありません」と明示する。

- [ ] **Step 5: GREENを確認する**

Run: `swift test --filter CodexAccountSettingsSourceTests`

Run: `swift test --filter SettingsReadinessPresentationTests`

Expected: PASS。全状態に次の操作が1つだけ明示される。

- [ ] **Step 6: commitする**

```bash
git add Sources/SuisuiApp/Views/CodexAccountSettingsView.swift Sources/SuisuiApp/Views/SettingsFeatureViews.swift Sources/SuisuiCore/App/AppSettings.swift Sources/SuisuiApp/Resources/en.lproj/Localizable.strings Sources/SuisuiApp/Resources/ja.lproj/Localizable.strings Tests/SuisuiCoreTests/CodexAccountSettingsSourceTests.swift Tests/SuisuiCoreTests/SettingsReadinessPresentationTests.swift
git commit -m "feat: add Codex subscription account settings"
```

### Task 9: security regression、live smoke、availability gate

**Files:**
- Create: `Tests/SuisuiCoreTests/CodexAppServerSecurityTests.swift`
- Create: `script/check_codex_app_server_smoke.sh`
- Modify: `script/check_security_regressions.sh`
- Modify: `docs/security/threat-model.md`
- Modify: `docs/release/privacy-security.md`
- Modify: `Sources/SuisuiCore/Planning/LLMProviderCatalog.swift`
- Modify: `Tests/SuisuiCoreTests/LLMProviderCatalogTests.swift`

- [ ] **Step 1: security gateの失敗テストを書く**

```swift
func testProductionSourceNeverReadsCodexAuthStoreOrInjectsTokens() throws {
    let source = try productionSwiftSource()
    XCTAssertFalse(source.contains(".codex/auth.json"))
    XCTAssertFalse(source.contains("chatgptAuthTokens"))
    XCTAssertFalse(source.contains("CODEX_ACCESS_TOKEN"))
}
```

process environment、diagnostics、UserDefaults、SQLite、Receipt export、sync payload、crash textにtoken patternがないことを追加する。

- [ ] **Step 2: REDを確認する**

Run: `swift test --filter CodexAppServerSecurityTests`

Expected: FAIL until security scan helpersとproduction boundaryが揃う。

- [ ] **Step 3: opt-in smoke scriptを実装する**

scriptは`SUISUI_CODEX_APP_SERVER_SMOKE=1`がない場合exit 0でskipし、ある場合のみ実行する。`codex --version`、initialize、account/read、model/list、ephemeral read-only thread、固定された無害なAction Plan promptを検証する。stdout/stderrへemail、auth URL、account ID、raw response bodyを出さず、`authMode`、plan、method名もrelease evidenceではcategoryへ丸める。

- [ ] **Step 4: threat modelとrelease evidenceを更新する**

脅威として偽codex binary、PATH hijack、stdio injection、malformed notification、auth URL spoof、multi-user process共有、workspace policy、usage limit、CLI protocol driftを列挙する。それぞれabsolute executable、version gate、typed decode、host allowlist、per-user process、fail closed、fixture/live smokeで緩和する。

OpenAIとの外部確認事項として、enterprise use向け`clientInfo.name`のknown-client登録、app-serverの第三者配布clientとしてのサポート範囲、protocol compatibility policyをrelease checklistへ記録する。回答待ちは実装テストのblockerではないが、Enterprise対応済み表記のblockerにする。

- [ ] **Step 5: availability GO gateを開く**

Task 1からTask 9のtests、security scan、live smokeがすべてgreenのcommitでのみ`codexLocal.isAvailableInCurrentBuild`をtrueへ変える。live smoke未実行環境では実装PRをmerge可能としても、Public Alphaの対応済み表記は不可とする。

- [ ] **Step 6: 全検証を実行する**

Run: `swift test --filter 'Codex(AppServer|Account|Subscription)'`

Run: `swift test --filter LLMProviderCatalogTests`

Run: `./script/check_security_regressions.sh`

Run: `SUISUI_CODEX_APP_SERVER_SMOKE=1 ./script/check_codex_app_server_smoke.sh`

Run: `swift test`

Run: `git diff --check`

Expected: unit/security/full suite PASS、live smokeは明示opt-in環境でPASS、diff checkは無出力。

- [ ] **Step 7: commitする**

```bash
git add Tests/SuisuiCoreTests/CodexAppServerSecurityTests.swift script/check_codex_app_server_smoke.sh script/check_security_regressions.sh docs/security/threat-model.md docs/release/privacy-security.md Sources/SuisuiCore/Planning/LLMProviderCatalog.swift Tests/SuisuiCoreTests/LLMProviderCatalogTests.swift
git commit -m "test: gate Codex subscription provider release"
```

## Issue split after plan approval

既存Issue `#323 AI providers: Copilot OAuth, local Codex SDK, OpenCode, and BYOK capability registry`をEpicとして維持し、実装時は以下の子Issueへ分ける。各Issueは上の同名Taskを本文へ展開し、1 PR 1責務にする。

1. `P11-016A Codex provider capability contract and ADR` — Task 1
2. `P11-016B Codex App Server protocol fixtures` — Task 2
3. `P11-016C Codex stdio transport` — Task 3
4. `P11-016D ChatGPT account and rate-limit client` — Task 4
5. `P11-016E Tool-free Action Plan provider` — Task 5
6. `P11-016F Runtime and connected-Mac boundary` — Task 6
7. `P11-016G Subscription usage receipts` — Task 7
8. `P11-016H Settings login UX` — Task 8
9. `P11-016I Security and live compatibility gate` — Task 9

## Implementation order and release rule

`A -> B -> C -> D -> E -> F -> G -> H -> I`の順に進める。C/D/Eは未公開feature flagの背後でmergeできるが、IのGO gate前にSettingsへ選択肢を出さない。Codex App Serverはexperimental表記が残るため、Suisui側はfull generated schemaをvendorせず、使用subsetと最低versionを固定し、version更新時はfixture更新PRを独立させる。

## Verified official sources

調査日: 2026-07-21

- OpenAI Codex App Server README: https://github.com/openai/codex/blob/main/codex-rs/app-server/README.md
- Using Codex with your ChatGPT plan: https://help.openai.com/en/articles/11369540-using-codex-with-your-chatgpt-plan
- Codex rate card: https://help.openai.com/en/articles/20001106

ローカル検証baselineは`codex-cli 0.144.1`。`codex login status`は`Logged in using ChatGPT`、生成したprotocol schemaは`chatgpt`をCodex-managed OAuthとして定義し、`chatgptAuthTokens`をOpenAI内部専用・使用禁止としている。baseline更新時はtokenを含まないfixtureだけを更新し、ローカルのauth store内容を計画・Issue・test evidenceへ転記しない。
