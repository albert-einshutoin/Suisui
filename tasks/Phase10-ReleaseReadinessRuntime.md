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
- [x] Project を archive して active board / menu summary / deadline summary から外せる。
- [x] active project に紐づく task 作成ができる。
- [x] テスト: project create / title update が board snapshot に反映される。
- [x] テスト: project complete が board snapshot に反映される。
- [x] テスト: project archive は active snapshot から消えるが既存 row / task は保持される。
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

### P10-018: Infrastructure test double isolation

- [x] `Sources/` に `FakeFileMonitorClient` / `StaticPermissionManager` / `StaticMenuBarSummaryProvider` / `StaticTool` が含まれていないことを regression test で確認する。
- [x] File monitor / permissions / menu summary / closure tool の test double は `Tests/` 配下へ隔離する。
- [x] 既存 unit tests は test support の test double を明示利用する。
- [x] 完了条件: shipping module の public API から infrastructure test doubles を除去する。

### P10-019: Local in-memory CRUD/system client isolation

- [x] `Sources/` に local CRUD / system client 用 `InMemory*` 実装が含まれていないことを regression test で確認する。
- [x] `InMemoryProjectBoardStore` / `InMemoryDailyCheckStateStore` / `InMemoryLaunchAtLoginClient` は `Tests/` 配下の test support に隔離する。
- [x] `InMemoryNotificationClient` / `InMemoryCalendarClient` / `InMemoryReminderClient` / `InMemoryMailDraftClient` は `Tests/` 配下の test support に隔離する。
- [x] 完了条件: shipping module の local CRUD/system integration public API から in-memory success path を除去する。

### P10-020: Security/audit/MCP in-memory store isolation

- [x] `Sources/` に `InMemorySecretStore` / `InMemoryAuditLogger` / `InMemoryMCPServerRegistrationStore` が含まれていないことを regression test で確認する。
- [x] Secret / audit / MCP registration の in-memory 実装は `Tests/` 配下の test support に隔離する。
- [x] `Tests/Manual` は shipping module に依存しない private manual double で検証を維持する。
- [x] 完了条件: shipping module の secret / audit / MCP registration public API から in-memory success path を除去する。

### P10-021: Shortcut in-memory client isolation

- [x] `Sources/` に `InMemoryShortcutClient` が含まれていないことを regression test で確認する。
- [x] Shortcut の in-memory 実装は `Tests/` 配下の test support に隔離する。
- [x] 既存 shortcut unit tests は test support の client を明示利用する。
- [x] 完了条件: shipping module の shortcut API から in-memory success path を除去する。

### P10-022: Knowledge test double isolation

- [x] `Sources/` に `StaticEmbeddingProvider` / `StaticKnowledgeTextSearch` / `InMemoryKnowledgeVectorIndex` / `InMemoryWeKnoraClient` が含まれていないことを regression test で確認する。
- [x] Knowledge retrieval / embedding / WeKnora の test double は `Tests/` 配下の test support に隔離する。
- [x] 実働側には `LocalHashEmbeddingProvider` / `SQLiteKnowledgeVectorIndex` / `SQLiteKnowledgeFrameStore` を残す。
- [x] 完了条件: shipping module の Knowledge public API から static / in-memory success path を除去する。

### P10-023: Release-ready STT provider surface

- [x] release-ready STT provider は実装済みの `OpenAITranscribeProvider` のみに制限する。
- [x] Settings UI は `STTProvider.releaseReadyCases` のみを表示し、未実装 provider を選択肢に出さない。
- [x] 既存 UserDefaults 由来の未実装 STT 設定は runtime 起動時に `openAITranscribe` へ正規化する。
- [x] 完了条件: shipping app に未実装 STT provider skeleton を含めず、使えない音声 provider を選ばせない。

### P10-024: Project board narrow-window resilience

- [x] ProjectBoard header が狭い window で横潰れしないよう `ViewThatFits` で縦配置へ fallback する。
- [x] Project / Task の長い title、detail、due label は省略表示し、hover で全文確認できる。
- [x] Task metadata は横幅不足時に縦配置へ fallback する。
- [x] Kanban board は長い task list と狭い window で縦横にスクロールでき、scroll indicator を表示する。
- [x] 完了条件: ProjectBoard の長文・狭幅 regression を source test で検知できる。

### P10-025: SaaS connector test double isolation

- [x] 外部連携はリリース対象外だが、production module に public fake / in-memory connector client を残さない。
- [x] SaaS connector の in-memory metadata store、fake clients、static health client を test support へ移す。
- [x] Core の SaaS connector protocol / policy / approval 境界は production source に残す。
- [x] 完了条件: runtime source に SaaS connector test double が混入したら source test で失敗する。

### P10-026: Release environment blocker preflight

- [x] Developer ID identity、notary profile、signed app、Gatekeeper、staple、clean-env/manual login-item gate を一箇所で検査する script を追加する。
- [x] preflight は秘密情報を表示せず、未完了 gate を `BLOCKER` として返す。
- [x] release checklist に preflight の実行順と manual release evidence を追加する。
- [x] 完了条件: 外部資格情報や別ユーザー確認が未完了のまま release 完了扱いにならない。

### P10-027: Voice review narrow-window resilience

- [x] Voice Command window は Review panel 表示時も下部操作が切れないよう outer scroll を持つ。
- [x] Action Review header は summary / approval / risk badge が狭幅で縦配置へ fallback する。
- [x] Action row は tool label / status が狭幅で縦配置へ fallback し、長文 title は hover で全文確認できる。
- [x] 完了条件: Review UI の狭幅・長文 regression を source test で検知できる。

### P10-028: Release readiness report

- [x] runtime mock / fake scan、Phase checklist、release environment preflight を 1 コマンドで集約する。
- [x] `tasks/README.md` のテンプレート用 unchecked 項目は release blocker から除外する。
- [x] report は残 gate がある間は `NOT READY` と exit 2 を返す。
- [x] 完了条件: VC / investor 目線の残 blocker を毎回同じ出力で確認できる。

### P10-029: Manual release evidence gate

- [x] clean 環境起動と login item toggle を一時的な env ではなく、ignored local evidence file で検証する。
- [x] `packaging/release-evidence.example.json` には秘密情報を入れず、repo には template だけを置く。
- [x] `verify_release_environment.sh` は `manualChecks.cleanEnvironmentLaunch` と `manualChecks.loginItemToggle` が true でない限り release ready にしない。
- [x] release evidence の version / build number / app bundle path が release metadata と一致しない場合は blocker にする。
- [x] 完了条件: 人間の手動確認 gate を機械的な release report で再確認できる。

### P10-030: CLI / app executable product collision

- [x] case-insensitive macOS filesystem 上で `SoloPM` app product と CLI product が同じ build output を上書きしないことを regression test で確認する。
- [x] CLI product を `solopm-cli` にし、`SoloPM` GUI app binary と明確に分離する。
- [x] `solopm-cli --help` が usage を出して exit 0 になる。
- [x] 完了条件: app build 後に CLI を build しても、またはその逆でも GUI / CLI の binary が取り違えられない。

### P10-031: Project archive release hardening

- [x] `SQLiteProjectStore.archive` は row を削除せず `status = archived` にする。
- [x] default project list / ProjectBoard snapshot / MenuBar recent projects は archived project を表示しない。
- [x] archived project とその task deadline は due query / deadline summary / overdue check から除外する。
- [x] completed task は due query から除外し、`task.list_due` が完了済み作業を再提示しない。
- [x] ProjectBoard UI は destructive confirmation 付きで `Archive Project` を実行できる。
- [x] archive 後に active project が 0 件なら fresh `Inbox` を作り、初回利用導線を切らさない。
- [x] 完了条件: 不要 project を安全に active board から外せ、通知や menu summary に古い project が残らない。

### P10-032: Archived project restore path

- [x] `SQLiteProjectStore.restore` は archived project を `active` に戻し、active list へ再表示する。
- [x] `ProjectBoardStore.loadSnapshot(includeArchived:)` で archived project を明示的に表示できる。
- [x] ProjectBoard sidebar から `Show Archived` を切り替えられる。
- [x] archived project は active board 上で read-only placeholder を表示し、復元前の task 編集や新規 task 作成を促さない。
- [x] ProjectBoard header から `Restore Project` を実行できる。
- [x] 完了条件: archive は不可逆な削除に見えず、ユーザーがアプリ内で復旧できる。

### P10-033: CLI local read runtime

- [x] `solopm-cli status` は app default SQLite DB を read-only で開き、active / archived project、open / due task、Knowledge Frame 数を実データから出す。
- [x] `solopm-cli tasks due` は completed task と archived project 配下 task を除外し、期限到来 task だけを表示する。
- [x] `solopm-cli frames search <query>` は `SQLiteKnowledgeFrameStore.search` を使い、FTS の実検索結果を表示する。
- [x] app DB が無い場合は SQLite ファイルを作らず `database: missing` を返す。
- [x] GUI と CLI は `SoloPMAppDatabaseLocation` で同じ app default DB path を共有し、path drift を防ぐ。
- [x] release readiness report の runtime scan は `Sources/SoloPMCLI` と `skeleton` / `placeholder` marker も対象にする。
- [x] 完了条件: CLI が demo 表示ではなく、GUI と同じ local persistent data を安全に読み取れる。

### P10-034: Release readiness truthfulness

- [x] runtime validation と distribution release gate を Exit Gate で分けて表記する。
- [x] `./script/release_readiness_report.sh` が Developer ID signing / notarization / manual evidence の未完了を blocker として出すことを確認する。
- [x] runtime mock scan は green でも、署名・notary・manual evidence が未完了なら release ready と表現しない。
- [x] 完了条件: VC / investor 向けの進捗説明で「動く runtime」と「配布可能 release」の差分を隠さない。

### P10-035: Release evidence generator

- [x] `script/create_release_evidence.sh` は `packaging/app_metadata.env` から version / build number / app bundle path を生成する。
- [x] package artifact の `.sha256` から `release.artifactPath` と `release.artifactSha256` を生成する。
- [x] manual check flags は明示 option が指定された場合だけ true にする。
- [x] manual check flags が true の場合、`manualChecks.environment` を preflight で必須にする。
- [x] `verify_release_environment.sh` は evidence の artifact SHA-256 と package checksum の一致を検査する。
- [x] 完了条件: release owner が手書き JSON で build metadata / checksum を間違えにくい。

### P10-036: Completed project task consistency

- [x] `ProjectBoardStore.completeProject` は project を completed にするだけでなく、配下の open task を Done column に移す。
- [x] completed project に新しい open task を追加した場合は project を active に戻し、状態の意味を壊さない。
- [x] archived project への task 作成は UI / store / tool path で拒否し、hidden work を作らない。
- [x] `task.list_due` / CLI due / open count / deadline summary は completed project 配下 task を active workload として扱わない。
- [x] `project.complete` tool は task store を必須にし、voice / review 経由でも ProjectBoard と同じ完了 semantics にする。
- [x] 完了条件: UI、CLI、review tool、deadline query のすべてで completed / archived project の task 状態が一貫する。

### P10-037: SQLite MCP registration persistence

- [x] `CoreMigrations.current` に `mcp_server_registrations` table を追加し、MCP server 登録を SQLite に永続化する。
- [x] runtime の `ExternalMCPSettingsViewModel` は `UserDefaultsMCPServerRegistrationStore` ではなく `SQLiteMCPServerRegistrationStore` を使う。
- [x] 未使用の `UserDefaultsMCPServerRegistrationStore` を production source から削除し、再導入を regression test で検知する。
- [x] `environment_json` は Keychain reference だけを保存し、raw provider token / GitHub token を DB に入れない。
- [x] display name / command / arguments / working directory に quote を含むユーザー入力でも保存と復元が壊れない。
- [x] 完了条件: MCP registration が app restart 後も残り、外部連携なしの release path に UserDefaults / in-memory success path が混ざらない。

### P10-038: MCP registration CRUD delete path

- [x] `SQLiteMCPServerRegistrationStore` は file-backed SQLite を再オープンしても登録を復元できることを regression test で確認する。
- [x] `ExternalMCPSettingsViewModel` に登録削除 API を追加し、保存済み MCP registration を空配列として永続削除できる。
- [x] Settings の External MCP セクションに Delete button を追加し、不要または壊れた登録を blank 保存で残さず消せる。
- [x] 完了条件: MCP registration は create / update / delete が runtime UI と永続 store の両方で成立する。

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
- [x] runtime 検証コマンドは green。
- [ ] Developer ID signing、notarization、Gatekeeper、clean environment、login item manual evidence が揃い、`./script/release_readiness_report.sh` が green。

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
- `swift build --product solopm-cli && .build/debug/solopm-cli --help`
- `SOLOPM_RELEASE_PREFLIGHT_ONLINE=1 ./script/verify_release_environment.sh` (Developer ID / notary / `packaging/release-evidence.json` が揃った release machine で green にする。開発機では blocker 出力を確認する。)
- `./script/release_readiness_report.sh` (全 release gate が揃うまでは `NOT READY` と blocker を返す。)
