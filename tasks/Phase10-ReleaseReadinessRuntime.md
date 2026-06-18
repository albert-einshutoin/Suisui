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
- [x] Board card を context menu / drag and drop で列移動でき、SQLite の task status に永続化される。
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
- [x] MCP lifecycle test 用 `RecordingMCPServerProcess` は `Tests/` 配下の test support に隔離する。
- [x] `ToolExecutionContext` は execution source を必須引数にし、developer harness / test 扱いを shipping enum に残さない。
- [x] 監査ログの serialized arguments は `apiKey=` などの secret-like field を値パターンに依存せず redaction する。
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

### P10-039: MCP execution process cleanup hardening

- [x] `ExternalMCPToolExecutor` は `NoopMCPProcessController` を default injection せず、process cleanup controller を caller に明示注入させる。
- [x] production source から no-op / recording MCP process controller を削除し、timeout 時の kill path が無効化されたまま成功しない API にする。
- [x] unit tests は test support の `RecordingMCPProcessController` を明示利用し、timeout failure が process cleanup request を出すことを維持する。
- [x] 完了条件: 外部 MCP tool call は監査 logger と実 process cleanup controller の両方を明示しない限り runtime API として構成できない。

### P10-040: Release evidence fail-fast hardening

- [x] `create_release_evidence.sh` は manual check flag を true にする場合、`--manual-environment` を必須にする。
- [x] manual release evidence は packaged artifact checksum が無い状態では作成できない。
- [x] 完了条件: clean environment / login item の手動確認は、署名・公証後に生成された配布 artifact と確認環境が結び付かない限り証跡として保存されない。

### P10-041: Release package notarization gate

- [x] `package_release.sh` は既定で signed app だけでなく stapled / Gatekeeper accepted app を要求する。
- [x] 開発機の packaging smoke は `SOLOPM_REQUIRE_SIGNED_PACKAGE=0` と `SOLOPM_REQUIRE_NOTARIZED_PACKAGE=0` の両方を明示した場合だけ通せる。
- [x] 完了条件: public alpha 用 DMG / ZIP は notarization / stapler / Gatekeeper validation を通った app bundle からだけ作成される。

### P10-042: Release evidence artifact binding hardening

- [x] `create_release_evidence.sh` は manual check flag の有無に関わらず、packaged artifact checksum が無い状態では evidence を作成しない。
- [x] `release.artifactPath` / `release.artifactSha256` に `missing-release-artifact` sentinel が入った JSON をローカル証跡として残さない。
- [x] `create_release_evidence.sh` は package evidence manifest を読み、signed / notarized gate と manifest `artifactPath` が checksum と一致する artifact だけを証跡化する。
- [x] `verify_release_environment.sh` も package evidence manifest を読み、手書き evidence / smoke artifact / artifactPath 欠落 manifest のすり抜けを blocker にする。
- [x] 完了条件: release evidence は必ず `package_release.sh` が signed / notarized gate 有効で作った artifact checksum に紐づく。

### P10-043: Release source tree hygiene gate

- [x] `.gitignore` はローカル UI QA artifact と macOS metadata を ignore し、スクリーンショットや Finder metadata を release branch に混ぜない。
- [x] `verify_release_environment.sh` は git checkout 上で tracked file に未コミット変更がある場合、release blocker にする。
- [x] 完了条件: release preflight は ignore 済み local artifact では止まらず、source code / release script / task doc の未コミット変更だけを release 前に止める。

### P10-044: Developer ID signature identity binding

- [x] `verify_release_environment.sh` は `codesign --verify` だけでなく、`codesign -dv --verbose=4` の Authority chain に設定済み Developer ID identity が含まれることを確認する。
- [x] ad-hoc 署名や別 identity で署名された app bundle は Gatekeeper / notarization の前に release blocker にする。
- [x] 完了条件: release owner が意図した Developer ID identity で署名された bundle だけが public alpha packaging evidence へ進める。

### P10-045: Hardened runtime signature gate

- [x] `verify_release_environment.sh` は `codesign -dv --verbose=4` の `flags` に hardened runtime が含まれることを確認する。
- [x] ad-hoc / non-runtime signature は notarization submit 前に release blocker にする。
- [x] 完了条件: public alpha 用 app bundle は Developer ID identity と hardened runtime の両方を満たした署名だけを release path として扱う。

### P10-046: Release app bundle metadata gate

- [x] `verify_release_environment.sh` は `dist/SoloPM.app/Contents/Info.plist` の `CFBundleIdentifier` / `CFBundleShortVersionString` / `CFBundleVersion` を `packaging/app_metadata.env` と照合する。
- [x] stale build や別 bundle identifier の app bundle は package evidence / manual evidence に進む前に release blocker にする。
- [x] 完了条件: release package は app metadata と一致する app bundle からだけ作成される。

### P10-047: Developer ID identity format gate

- [x] `sign_app.sh` は `SOLOPM_SIGNING_IDENTITY` が `Developer ID Application:` で始まらない場合、codesign 実行前に失敗する。
- [x] `verify_release_environment.sh` は Apple Development / Mac Developer など release 不可の identity を release blocker にする。
- [x] 完了条件: public alpha release path は Apple Developer ID distribution identity 以外の signing identity を受け付けない。

### P10-048: Release artifact checksum disambiguation

- [x] `verify_release_environment.sh` は `dist/releases` に同一 version/build の `.sha256` が複数ある場合、自動選択せず release blocker にする。
- [x] 複数 package artifact を作った場合は `SOLOPM_RELEASE_ARTIFACT_SHA256_FILE` で証跡対象を明示する。
- [x] 完了条件: release evidence / manual evidence は曖昧な DMG/ZIP 自動選択ではなく、明示された package checksum に紐づく。

### P10-049: Release app entitlements gate

- [x] `verify_release_environment.sh` は signed app から `codesign -d --entitlements :-` で entitlements を読み、`packaging/SoloPM.entitlements` と照合する。
- [x] 現在の空 entitlements は signed app の空 entitlements として扱い、将来 entitlement を追加した場合は mismatch を release blocker にする。
- [x] 完了条件: public alpha 用 app bundle は repository の entitlements manifest と一致した署名だけを release path として扱う。

### P10-050: Signing setup Developer ID gate

- [x] `verify_signing_setup.sh` は configured identity が `Developer ID Application:` で始まらない場合、keychain lookup 前に失敗する。
- [x] `sign_app.sh` / `verify_release_environment.sh` / `verify_signing_setup.sh` の Developer ID 条件を揃える。
- [x] 完了条件: release operator は Apple Development / Mac Developer identity を setup check green と誤認しない。

### P10-051: Notarization submit signature gate

- [x] `notarize_app.sh` は notary submit 前に app bundle の signature details を読み、Developer ID Application 署名でない場合は失敗する。
- [x] `notarize_app.sh` は hardened runtime flag がない app bundle を notary submit 前に失敗させる。
- [x] 完了条件: release operator は notarization 前に署名種別 / hardened runtime 不備をローカルで検出できる。

### P10-052: Notarization setup verifier

- [x] `verify_notarization_setup.sh` は notarization docs / env example / script の存在と実行権限を確認する。
- [x] `SOLOPM_RELEASE_PREFLIGHT_ONLINE=1` の場合は `xcrun notarytool history --keychain-profile` で configured notary profile を検証する。
- [x] 完了条件: release operator は notary submit 前に Keychain profile 設定不備を単独コマンドで確認できる。

### P10-053: Release evidence signing context binding

- [x] `create_release_evidence.sh` は `SOLOPM_SIGNING_IDENTITY` / `SOLOPM_NOTARY_PROFILE` がない状態で成功証跡を作らない。
- [x] release evidence は `release.signingIdentity` / `release.notaryProfile` を記録するが、credential secret は保存しない。
- [x] `verify_release_environment.sh` は evidence の signing identity / notary profile が現在の release machine 設定と一致することを照合する。
- [x] `create_release_evidence.sh` は missing / invalid な release Sparkle config がある状態で成功証跡を書かない。
- [x] release evidence は `release.sparkleFeedURL` / `release.appcastPath` を記録し、final preflight で現在の release config と照合する。
- [x] manual release evidence は release machine launch、checksum、clean DMG install、Applications install、Gatekeeper、login item、Sparkle metadata を個別 boolean として記録し、final preflight で全て true を要求する。
- [x] `verify_release_environment.sh` は release app bundle の executable、Resources、action-plan schema、Sparkle.framework、Updater.app が欠けていないことを検証する。
- [x] 完了条件: manual release evidence は artifact checksum だけでなく、配布署名 context と Sparkle update context にも紐づく。

### P10-054: Release appcast gate

- [x] `generate_appcast.sh` は release mode で `SOLOPM_SPARKLE_DOWNLOAD_URL_PREFIX` を必須にし、HTTPS 以外、予約ドメイン、ローカルドメインを拒否する。
- [x] `verify_appcast.sh` は release mode で `packaging/appcast.sample.xml`、placeholder signature、予約ドメイン、ローカルドメインを拒否する。
- [x] `verify_appcast.sh` は release mode で enclosure URL が `https://` でない appcast を拒否する。
- [x] `verify_appcast.sh` は release mode で `sparkle:edSignature` 欠落と `length="0"` enclosure を拒否する。
- [x] `verify_appcast.sh` は Sparkle `generate_appcast` が出力する element 形式の `sparkle:version` / `sparkle:shortVersionString` を受け入れ、metadata mismatch は明示エラーにする。
- [x] `verify_appcast.sh` は configured `SOLOPM_SPARKLE_DOWNLOAD_URL_PREFIX` と enclosure URL が一致しない appcast を拒否する。
- [x] release checklist は generated `dist/releases/appcast.xml` を `SOLOPM_REQUIRE_RELEASE_APPCAST=1` で検証する。
- [x] `create_release_evidence.sh` は release appcast verification が通らない状態では evidence を作成しない。
- [x] `verify_release_environment.sh` は generated release appcast が存在し、release mode の appcast verification を通ることを release blocker にする。
- [x] `verify_release_environment.sh` は appcast verification failure の具体理由を release blocker に含める。
- [x] 完了条件: sample appcast smoke を通しただけでは public alpha release ready にならない。

### P10-055: Release package and evidence checksum selection

- [x] release checklist は user download 用 DMG と Sparkle appcast 用 ZIP を `SOLOPM_PACKAGE_FORMAT=all` で同時生成する。
- [x] release evidence / final preflight は `SOLOPM_RELEASE_ARTIFACT_SHA256_FILE` で DMG checksum を明示し、複数 checksum の自動選択を避ける。
- [x] `create_release_evidence.sh` / `verify_release_environment.sh` は checksum file が指す release artifact file の存在と実 SHA-256 を検証し、手書き checksum だけでは evidence 作成 / release ready にしない。
- [x] 完了条件: checklist 通りに進めた場合、appcast 用 ZIP 不足や evidence checksum の曖昧選択で release が止まらない。

### P10-056: Release Sparkle feed gate

- [x] release build は `SOLOPM_SPARKLE_FEED_URL` と `SOLOPM_SPARKLE_PUBLIC_ED_KEY` が揃わない場合に Swift build 前に失敗する。
- [x] release build は Sparkle feed URL が HTTPS でない場合、または予約ドメイン / ローカルドメインの場合に失敗する。
- [x] release build と `verify_release_environment.sh` は placeholder Sparkle public key を release blocker にする。
- [x] release build と `verify_release_environment.sh` は base64 形状でない Sparkle public key を release blocker にする。
- [x] `verify_release_environment.sh` は signed app の `SUFeedURL` / `SUPublicEDKey` 欠落と placeholder feed URL を release blocker にする。
- [x] `verify_release_environment.sh` は signed app の `SUFeedURL` / `SUPublicEDKey` が local release config と一致しない場合に release blocker にする。
- [x] `packaging/sparkle.env.example` は release 用の `example.com` URL を含まず、production 値は local env または release machine の環境変数から与える。
- [x] 完了条件: public alpha release build に sample feed URL や Sparkle 無効状態が混入しない。

### P10-057: CRUD tool input normalization

- [x] `project.create` / `task.create` は title の前後空白を正規化して永続化する。
- [x] `project.update` / `task.update` は空白 title を拒否し、既存 row を壊さない。
- [x] `frame.update` は空白 body を拒否し、既存 Knowledge Frame を壊さない。
- [x] Review UI は CRUD update の空白任意フィールドを承認前に validation issue として表示し、実行ボタンを無効化する。
- [x] Review UI は `task.bulk_create` の配列内 title 欠落 / 空白も `tasks[n].title` として承認前に validation issue 化する。
- [x] `project.create` 直後の `task.bulk_create` は新規 project ID を各 task item に注入し、bulk task を project に紐付ける。
- [x] 完了条件: UI だけでなく review tool / AI plan 経由でも空白だけの project / task / knowledge data が永続化されない。

### P10-058: MCP argument text round-trip

- [x] Settings の MCP `Arguments` は単純な whitespace split ではなく、single quote / double quote / backslash を解釈する。
- [x] 空白入り path を含む MCP server 引数は 1 引数として保持され、SQLite registration に壊れた形で保存されない。
- [x] 無効な quote 入力では既存の arguments を壊さず、UI に validation error を出す。
- [x] Settings UI は保存済み arguments を quote 付き text として round-trip 表示する。
- [x] 完了条件: macOS の空白入り directory 配下に置いた stdio MCP server を UI から実用的に登録できる。

### P10-059: MCP registration data preservation

- [x] Settings の単一登録編集 UI は、既存 store に複数 MCP registration がある場合でも後続 registration を削除しない。
- [x] `save()` は現在編集中の registration id だけを差し替え、同じ store 内の他 registration の順序と内容を保持する。
- [x] `deleteRegistration()` は現在編集中の registration id だけを削除し、残りがあれば次の registration を表示する。
- [x] テスト: save / delete の両方で hidden registration が消えないことを確認する。
- [x] 完了条件: app update や将来の複数 MCP UI 追加時に、既存 SQLite registration を Settings 操作で失わない。

### P10-060: Keychain API key whitespace validation

- [x] OpenAI / OpenRouter API key 保存時は前後空白を trim し、内部 whitespace / newline を拒否する。
- [x] 無効な key は Keychain に保存せず、status を Configured にしない。
- [x] validation error は秘密値を含めない。
- [x] テスト: OpenAI / OpenRouter の whitespace 入り key が保存されないことを確認する。
- [x] 完了条件: API key 入力ミスで「設定済み」に見える偽状態を作らない。

### P10-061: SQLite CRUD store boundary validation

- [x] `SQLiteProjectStore` は title を trim して保存し、空白 title の create / update を拒否する。
- [x] `SQLiteTaskStore` は title を trim して保存し、単体 create / update / bulk create の空白 title を拒否する。
- [x] `SQLiteKnowledgeFrameStore` は name を trim して保存し、空白 name / body の create / update を拒否する。
- [x] bulk create で無効 task が混ざる場合は transaction rollback により途中 row を残さない。
- [x] テスト: LocalStoreTests で store 直下からの空白 project / task / knowledge data が永続化されないことを確認する。
- [x] 完了条件: UI / review tool 以外の Core API 利用経路でも空白だけの CRUD データが SQLite に入らない。

### P10-062: SQLite CRUD status canonicalization

- [x] `SQLiteProjectStore` は project status を `active` / `completed` / `archived` に限定する。
- [x] `SQLiteTaskStore` は task status を `open` / `backlog` / `planned` / `in_progress` / `blocked` / `completed` に canonicalize する。
- [x] task status alias の `todo` / `next` / `doing` / `active` / `done` / `closed` は既存 board semantics に合わせて保存値へ正規化する。
- [x] invalid status は既存 row を上書きせず validation error にする。
- [x] テスト: invalid project/task status が SQLite に永続化されず、既存 status が保持されることを確認する。
- [x] 完了条件: AI plan / CLI / OSS API 経由で未知 status が入り、board、deadline、CLI count の意味が壊れない。

### P10-063: External SaaS connector target isolation

- [x] Google / Gmail / Slack / Drive / Notion connector 実装を `SoloPMCore` から分離し、`SoloPMExternalConnectors` target に置く。
- [x] `SoloPM` app target と `SoloPMCLI` target は `SoloPMExternalConnectors` に依存しない。
- [x] Phase8 の connector tests は別 target を明示 import して継続検証する。
- [x] テスト: public alpha app target が external SaaS connector target を link しないことを確認する。
- [x] テスト: `Sources/SoloPMCore` に external SaaS connector symbols が残らないことを確認する。
- [x] 完了条件: 外部 SaaS 連携を除外した public alpha runtime に OAuth / Slack post / Notion write 実装が混ざらない。

### P10-064: MCP registration save-time validation

- [x] `ExternalMCPSettingsViewModel.save()` は store へ書く前に command / binary / working directory を検証する。
- [x] whitespace-only command は保存せず、Settings に `MCP command is required.` を返す。
- [x] 存在しない working directory は保存せず、Settings に対象 path を含むエラーを返す。
- [x] `MCPServerRegistrationValidator` は launch 前だけでなく save 前にも再利用できる単一の validation 境界にする。
- [x] テスト: invalid command / missing working directory が永続 store に入らないことを確認する。
- [x] 完了条件: MCP 設定が「保存成功に見えるが接続時に必ず失敗する」状態として残らない。

### P10-065: Review execution audit logger fail-closed

- [x] Runtime の `makeReviewSessionViewModel` は `try? makeAuditLogger()` で監査失敗を握りつぶさない。
- [x] audit logger または local data store を開けない場合、Review execution tools を unavailable registry に倒す。
- [x] UI には `Review execution tools are unavailable because audit logging or local data stores could not be opened.` を validation issue として出す。
- [x] テスト: Review runtime factory が audit logger を必須化してから write execution registry を構成することを確認する。
- [x] 完了条件: task/project/knowledge への write 実行が監査なしで成功しない。

### P10-066: SQLite JSON column fail-fast decoding

- [x] `projects.tags_json` の decode failure を `[]` として扱わず、読み込みエラーにする。
- [x] `knowledge_frames.triggers_json` の decode failure を `[]` として扱わず、読み込みエラーにする。
- [x] `LocalStoreDecodingError.invalidStringArray(column:)` で破損カラムを特定できるようにする。
- [x] テスト: corrupted tags / triggers JSON が Project / Knowledge read path で silent drop されないことを確認する。
- [x] 完了条件: DB 破損や migration bug が、UI/CLI 上でタグやトリガーの消失として見えない。

### P10-067: App settings load failure visibility

- [x] `AppSettingsViewModel` は settings store の decode failure を `try?` で握りつぶして無言で default に戻さない。
- [x] 壊れた `app.settings` を読み込んだ場合、default を表示しつつ `App settings could not be loaded. Defaults are shown until settings are saved again.` を出す。
- [x] テスト: corrupted UserDefaults settings が silent default fallback にならないことを確認する。
- [x] 完了条件: provider / workspace / notification 設定の破損が、ユーザーから見て設定消失のように見えない。

### P10-068: Keychain API key read failure visibility

- [x] `AppSettingsViewModel` は Keychain read failure を `try?` で握りつぶして `Not configured` にしない。
- [x] OpenAI / OpenRouter API key status は read failure 時に `Unavailable` を表示する。
- [x] UI には `API key status could not be read from Keychain.` を出す。
- [x] テスト: SecretStore read failure が未設定表示にならないことを確認する。
- [x] 完了条件: Keychain 障害や権限問題が API key 未設定として誤認されない。

### P10-069: Keychain save update-first hardening

- [x] `KeychainSecretStore.save` は既存 key の更新時に `SecItemUpdate` を先に試す。
- [x] `SecItemUpdate` が `errSecItemNotFound` の場合だけ `SecItemAdd` へ進む。
- [x] 既存 secret を `delete` してから `add` する実装をやめる。
- [x] テスト: update 成功時は add/delete が呼ばれず、missing item の場合だけ add されることを確認する。
- [x] 完了条件: API key 差し替え時に add path の失敗で既存 Keychain secret が失われない。

### P10-070: Runtime settings load failure visibility

- [x] `AppRuntimeFactory` は `UserDefaultsAppSettingsStore.load()` の失敗を `try?` で default に握りつぶさない。
- [x] Runtime settings load failure は専用 loader で扱い、default 使用時もユーザーに visible な failure message を残す。
- [x] Voice Command 起動時に設定破損がある場合、`Runtime app settings could not be loaded. Defaults are shown until settings are saved again.` を表示できる初期 phase にする。
- [x] テスト: runtime factory に silent default fallback が再導入されないことを確認する。
- [x] 完了条件: 設定破損が provider / STT 選択の意図しない default 化として隠れない。

### P10-071: SQLite CRUD row decode fail-fast fields

- [x] `ProjectRecord(row:)` は `id` / `title` / `status` を必須 decode し、欠落や不正 enum を正常レコードにしない。
- [x] `TaskRecord(row:)` は `id` / `project_id` / `title` / `status` を明示 decode し、不正 `project_id` を `nil` にしない。
- [x] `KnowledgeFrameRecord(row:)` は `id` / `name` / `body` を必須 decode し、空 frame を返さない。
- [x] `projects.tags_json` / `knowledge_frames.triggers_json` は欠落時も `[]` に丸めず decode error にする。
- [x] テスト: corrupted project status、corrupted task project_id、corrupted knowledge name が silent fallback されないことを確認する。
- [x] 完了条件: SQLite row 破損や migration bug が、空タイトル・ID 0・project link 消失・未知 status として UI/CLI に流れない。

### P10-072: System tool row decode fail-fast fields

- [x] `NotificationRequestRecord(row:)` は `id` / `request_id` / `status` / `title` / `scheduled_at` を必須 decode する。
- [x] `CalendarLinkRecord(row:)` は `id` / `event_id` を必須 decode し、不正 `project_id` / `task_id` を `nil` にしない。
- [x] `ReminderLinkRecord(row:)` は `id` / `reminder_id` を必須 decode し、不正 `project_id` / `task_id` を `nil` にしない。
- [x] テスト: corrupted notification title、corrupted calendar task_id、corrupted reminder project_id が silent fallback されないことを確認する。
- [x] 完了条件: notification / calendar / reminder の永続リンク破損が、空 request やリンク消失として UI/CLI に流れない。

### P10-073: Artifact monitoring row decode fail-fast fields

- [x] `ArtifactRecord(row:)` は `id` / `workspace_path` / `expected_path` / `created_state` を必須 decode する。
- [x] `project_id` / `task_id` の不正値を `nil` にせず decode error にする。
- [x] `last_modified_at` の不正日時を `nil` にせず decode error にする。
- [x] テスト: corrupted task_id、empty expected_path、corrupted last_modified_at が silent fallback されないことを確認する。
- [x] 完了条件: 成果物監視のリンクや更新日時破損が、missing/stale 判定の誤判定として流れない。

### P10-074: Audit log row decode fail-fast fields

- [x] `SQLiteAuditLogger.list()` は `timestamp` / `category` / `action` / `status` / `metadata_json` を必須 decode する。
- [x] 不正 `status` を `.failed` に丸めず decode error にする。
- [x] 不正 `timestamp` を Unix epoch に丸めず decode error にする。
- [x] 不正 `metadata_json` を `{}` に丸めず decode error にする。
- [x] 完了条件: 監査ログ破損が失敗イベントや空 metadata として隠れない。

### P10-075: Knowledge vector row decode fail-fast fields

- [x] `SQLiteKnowledgeVectorIndex` は `frame_id` / `dimensions` / `provider_id` / `vector_json` を必須 decode する。
- [x] 不正 `vector_json` を空 vector に丸めず decode error にする。
- [x] 空 `provider_id` を匿名 provider として検索結果に出さない。
- [x] `dimensions` と `vector_json` の配列長不整合を decode error にする。
- [x] 完了条件: 破損した embedding row が semantic search の ranking に静かに混ざらない。

### P10-076: Review audit failure visibility

- [x] `ReviewSessionViewModel` は review audit log の記録失敗を `try?` で捨てない。
- [x] edit / execute failure path で audit failure が `auditErrorMessage` に残ることを unit test で確認する。
- [x] Action Review UI は audit warning を通常の execution error とは別に表示する。
- [x] 完了条件: レビュー操作や実行の履歴欠落がユーザーから見えない状態で進行しない。

### P10-077: Action executor audit failure does not lose executed state

- [x] `ActionExecutor` は `execution.start` の audit failure は副作用前に block する。
- [x] tool 実行後の audit failure は throw で session result を失わず、`ReviewSession.auditErrorMessage` に残す。
- [x] `ReviewSessionViewModel` は executor 由来の audit warning を `auditErrorMessage` に反映する。
- [x] 完了条件: 実際には tool が成功したのに、audit write failure だけで UI 上の実行結果が消えない。

### P10-078: Voice planning audit failure does not lose generated plan

- [x] `VoiceCaptureViewModel` は planning audit completion failure を `try?` で捨てない。
- [x] LLM plan 生成後の audit failure は `planningResponse` と `reviewReady` を保持し、`auditErrorMessage` に warning を出す。
- [x] Voice Command UI は planning audit warning を通常 phase とは別に表示する。
- [x] 完了条件: 計画生成は成功したのに、audit write failure だけで Review へ進めなくなる状態を作らない。

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
