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
- [x] Settings から複数の MCP server 登録を選択し、新規登録ドラフトを作成して既存登録を落とさず保存できる。
- [x] MCP server の環境変数は `NAME=keychain:<secret_key>` 形式で編集し、SQLite には raw secret ではなく Keychain 参照だけを保存する。
- [x] Settings から MCP 用の任意 Keychain secret を保存 / 削除でき、secret value は UserDefaults / SQLite / 画面ステータスに表示しない。
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
- [x] `script/check_automated_release_preflight.sh` で CI、SQLite CRUD、runtime accessible CRUD、Xcode build、visible-window launch、runtime AX、MCP compliance を一括検証できる。
- [x] `SOLOPM_AUTOMATED_PREFLIGHT_EVIDENCE_FILE=.tmp/automated-release-preflight-$(git rev-parse --short HEAD).md ./script/check_automated_release_preflight.sh` で、自動proof gateのpass結果をレビュー可能なMarkdown証跡として保存できる。
- [x] 自動proof証跡は clean tracked source tree でのみ生成し、未コミット差分を含む曖昧な証跡を拒否する。
- [x] `./script/release_readiness_report.sh` は、`.tmp/automated-release-preflight-<commit>.md` が存在する場合に同一commitのclean-tree自動proof証跡を自動検出し、CI / SQLite CRUD / runtime accessible CRUD / Xcode / launch / runtime AXのskip blockerを解除できる。
- [x] 自動proof証跡の再利用時は generator、UTC timestamp、source commit、App名、Xcode workspace / scheme / configuration / destination、manual evidence境界文言を検証し、別appや別build文脈の証跡流用を拒否する。
- [x] VoiceOver / competitor hands-on の手動証跡は `Source commit` を記録し、`Status: passed` の場合は現在の git commit と一致しない証跡をrelease blockerにする。
- [x] competitor benchmark の `Source commit` も `Status: passed` の competitor hands-on 証跡と同じrelease候補commitであることをrelease blockerにする。
- [x] `release_readiness_report.sh` は CI、SQLite CRUD、runtime accessible CRUD、Xcode build、visible-window launch、runtime AX をskipしたままrelease readyにしない。
- [x] `SOLOPM_AUTOMATED_PROOF_GATES=1 ./script/release_readiness_report.sh` で自動proof gateをまとめてfinal report内に含められる。
- [x] 自動 preflight は manual VoiceOver、competitor hands-on、signing / notarization / Sparkle / Gatekeeper evidence を完了扱いにしない。
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
- [x] `verify_appcast.sh` は appcast が指す ZIP artifact、`.sha256`、`.package-evidence.json` が同じ release directory にあり、signed / notarized gate 有効の package evidence と一致することを検証する。
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

### P10-079: Daily check audit failure visibility

- [x] `SafeDailyCheckRunner` は失敗監査の write failure を `try?` で捨てない。
- [x] `DailyCheckRunner` は skip / run result の audit write failure を throw で実行結果に混ぜず、`DailyCheckRunResult.auditErrorMessage` に残す。
- [x] scan failure と audit failure が別々に戻ることを unit test で確認する。
- [x] 完了条件: daily deadline check の実行結果と監査欠落が同じ `failed` に丸め込まれない。

### P10-080: Review action button errors are visible

- [x] `ActionReviewPanel` は approve / execute の失敗を `try?` で握りつぶさない。
- [x] `ReviewSessionViewModel` は UI 操作用の approve / execute wrapper で失敗を `errorMessage` に残す。
- [x] execute preflight failure と success-after-stale-error を unit test で固定する。
- [x] 完了条件: ボタン操作が失敗した場合、ユーザーが原因を画面上で確認できる。

### P10-081: Notification failure persistence is not silent

- [x] `NotificationTool` は notification client failure 後の `notification_requests` failure-state 永続化失敗を `try?` で捨てない。
- [x] permission denied と SQLite update failure の両方が `ToolExecutionError` message に残ることを unit test で確認する。
- [x] 既存の permission denied path は `failed` request として永続化されることを維持する。
- [x] 完了条件: 通知作成が失敗したのに request が `pending` のまま残る場合、ユーザーに永続化不整合が見える。

### P10-082: Voice planning requires runtime audit logging

- [x] `makeVoiceCaptureViewModel()` は `try? makeAuditLogger()` で planning audit unavailable を握りつぶさない。
- [x] audit logger / local data store が開けない場合は `VoiceCaptureViewModel.runtimeValidationMessage` で plan generation を止める。
- [x] draft edit / Clear で runtime validation failure が消えないことを unit test で確認する。
- [x] 完了条件: AI 計画生成が監査なし runtime path で成功しない。

### P10-083: CLI status counts fail fast

- [x] `solopm-cli status` の SQLite `COUNT(*)` decode は欠落 / 不正値を `0` に丸めない。
- [x] `SoloPMCLIReadOnlyReporter.parseCountValue` は missing count と invalid count を `LocalStoreDecodingError` として返す。
- [x] 完了条件: CLI が壊れた集計値を「データなし」と誤表示しない。

### P10-084: Planning prompt schema fallback removal

- [x] `PlanningPromptBuilder` は `ActionPlanSchema.loadString()` failure を簡易 fallback contract に丸めない。
- [x] Default prompt は packaged `action-plan.schema.json` を `loadDefault()` で明示 load する。
- [x] OpenAI Responses / Chat Completions providers は schema load failure を plan generation failure として返す。
- [x] 完了条件: AI planning prompt が完全な ActionPlan schema なしに成功しない。

### P10-085: External MCP audit metadata uses verified descriptor

- [x] `ExternalMCPToolExecutor` は audit metadata 作成時に `try? registry.descriptor` で risk を `unknown` に丸めない。
- [x] 実行前に取得した `ExternalMCPToolDescriptor` を started / succeeded / failed audit metadata へ渡す。
- [x] external MCP read execution audit に `risk=read` が残ることを unit test で確認する。
- [x] 完了条件: MCP 実行ログが tool permission metadata を欠落させず、レビュー可能な監査証跡になる。

### P10-086: Secret redaction regex failures are not silent

- [x] `DeveloperSecretRedactor` は redaction 実行ごとに `try? NSRegularExpression` で invalid pattern を skip しない。
- [x] secret redaction patterns は `CompiledPattern` として初期化時に検証済み regex を保持する。
- [x] runtime source regression test と既存 draft redaction test で secret leak 防止を確認する。
- [x] 完了条件: redaction pattern の破損が secret を無検知で通す成功 path にならない。

### P10-087: Local store array encoding failures are not silent

- [x] `SQL.jsonArray` は `Project.tags` / `KnowledgeFrame.triggers` の encode failure を `[]` に丸めない。
- [x] `SQLiteProjectStore.create` と `SQLiteKnowledgeFrameStore.create/update` は throwing `jsonArray` を呼び出し、失敗を CRUD caller へ返す。
- [x] source regression test、`LocalStoreTests`、`ProjectTaskKnowledgeToolTests` で既存CRUD動作を確認する。
- [x] 完了条件: 永続化前の配列エンコード異常が、タグ/トリガー消失として成功扱いにならない。

### P10-088: Review unavailable-tool registry does not drop registration failures

- [x] `unavailableReviewRegistry` は `try? target.register` で fallback tool registration failure を捨てない。
- [x] fallback tool registration failure は `try!` でクラッシュさせず、runtime validation message に登録失敗 tool を含める。
- [x] `ReviewSessionViewModelTests` で runtime validation message による execution block を維持する。
- [x] 完了条件: review runtime unavailable 時に、必要な unavailable tool が静かに欠落しない。

### P10-089: Notification listing does not report missing callback as empty

- [x] `UserNotificationsNotificationClient.listScheduled()` は pending request callback が値を返さない場合に `[]` を返さない。
- [x] `guard let pendingRequests` で取得不能を `ToolClientError.invalidRequest` として返す。
- [x] source regression test、notification tool tests、daily check runner tests で既存通知フローを確認する。
- [x] 完了条件: 通知一覧の取得異常が「通知なし」と誤表示されない。

### P10-090: Tool argument arrays reject invalid element types

- [x] `ToolArguments` の string array / object array getter は `compactMap` で不正要素を捨てない。
- [x] `project.create` の `tags`、`frame.create/update` の `triggers`、`task.bulk_create` の `tasks`、`reminders.bulk_create` の `reminders` は不正要素で validation failure を返す。
- [x] project / task / knowledge / reminder の regression tests で partial row / partial reminder が作られないことを確認する。
- [x] 完了条件: CRUD / reminder bulk 入力の壊れた配列が、要素欠落または部分実行として成功扱いにならない。

### P10-091: Board shows unassigned persistent tasks

- [x] `SQLiteProjectBoardStore` は `projectID == nil` の永続タスクを `compactMap` で Board から落とさない。
- [x] 未紐付けタスクが存在する場合は active `Inbox` project を確保し、その Inbox カラムに表示する。
- [x] `ProjectBoardStoreTests` で CLI / AI 経由など Board UI 外で作られたタスクが Inbox に出ることを確認する。
- [x] 完了条件: ローカルDBに存在するタスクが、project 未指定という理由だけでタスク管理UIから消えない。

### P10-092: Deadline rules do not disappear when persisted rows are corrupt

- [x] `SQLiteDeadlineRuleStore` は `deadline_rules` の decode に `compactMap` を使って破損行を捨てない。
- [x] `list` / `list(for:)` / `get` は不正な `kind`、target、date を `LocalStoreDecodingError` として呼び出し元へ返す。
- [x] `DeadlineRuleStoreTests` で破損した rule が「0件」や「not found」ではなく decode failure になることを確認する。
- [x] 完了条件: 期限通知の rule 設定が、DB上の不正値によって静かに消えたように見えない。

### P10-093: Deadline summaries include board date-only due dates

- [x] `DeadlineQueryService` は `project.deadline` / `task.due_at` の decode に `compactMap` を使って不正日付を捨てない。
- [x] Board UI で保存される `YYYY-MM-DD` の date-only due date を、設定タイムゾーンの開始日として扱う。
- [x] 不正な project deadline / task due date は `LocalStoreDecodingError.invalidDate` として呼び出し元へ返す。
- [x] 完了条件: Board で登録した日付だけのタスクが、期限サマリー・メニューバー・期限通知の候補から消えない。

### P10-094: Board drag/drop rejects invalid task payloads atomically

- [x] `ProjectBoardView` は drop payload を `compactMap(Int64.init)` で部分的に捨てて移動しない。
- [x] `ProjectBoardViewModel.moveDroppedTasks` は payload 全体を先に検証し、不正IDがあれば valid ID も含めて移動しない。
- [x] 成功時は drop されたタスクを移動し、`onChange` は一度だけ通知する。
- [x] 完了条件: Drag/drop の壊れた payload によって、ユーザーの意図と違う一部タスクだけが移動しない。

### P10-095: Unassigned board tasks can be moved after Inbox fallback

- [x] `SQLiteProjectBoardStore.loadSnapshot` で Inbox に見せた `project_id == nil` タスクを、移動時にも拒否しない。
- [x] `moveTask` は未紐付けタスクを active Inbox に永続的に割り当ててから status を更新する。
- [x] `ProjectBoardStoreTests` で未紐付けタスクの move が `project_id` を Inbox に保存することを確認する。
- [x] 完了条件: CLI / AI / 外部経路で作られた未紐付けタスクを、Board UI 上で普通のタスクとして移動できる。

### P10-096: Artifact deadline detection uses board date-only deadlines

- [x] `ArtifactProgressDetector` は task due date / project deadline の parse failure を `nil` に丸めない。
- [x] Board UI と同じ `YYYY-MM-DD` date-only deadline を、タイムゾーン付きで incomplete-before-deadline 判定に使う。
- [x] 不正な task due date は `LocalStoreDecodingError.invalidDate` として検出を止める。
- [x] 完了条件: Boardで日付だけを入れたタスクの成果物未作成が、期限前チェックから消えない。

### P10-097: MCP tool schemas fail fast when malformed

- [x] `MCPToolDefinition.parse` は `inputSchema` が object でない tools/list response を default schema に丸めない。
- [x] `inputSchema.required` に string 以外が含まれる場合は、壊れた tool schema として tools/list を失敗させる。
- [x] Catalog summary も不正 schema を `No arguments` や部分的な required list として正常表示しない。
- [x] 完了条件: 壊れた MCP tool schema を信用して、UI や実行前レビューが安全そうに表示されない。

### P10-098: Knowledge embedding does not ship OpenAI-labeled local fallback

- [x] `BYOKOpenAIEmbeddingProvider` のような、API key の存在だけで local hash embedding を OpenAI BYOK 成功に見せる provider を Sources から除去する。
- [x] Release path では外部 embedding 連携を除外し、local-only hash embedding は `local_hash` として明示する。
- [x] Source regression test で `BYOKOpenAIEmbeddingProvider` / `openai_byok_fallback` の復活を検出する。
- [x] 完了条件: ユーザーや投資家に、外部AI embedding が実働しているように誤解される mock 成功経路を出荷しない。

### P10-099: Board task priority corruption is not defaulted

- [x] `ProjectTaskPriority.normalized` は不正な永続 priority を `.medium` に丸めない。
- [x] Board snapshot load は `tasks.priority` の破損を `LocalStoreDecodingError.invalidEnum` として返す。
- [x] 未設定 priority のみ、既存仕様どおり `.medium` として扱う。
- [x] 完了条件: DB破損や外部経路由来の不正 priority が、UI上で正常な Medium priority に見えない。

### P10-100: FSEvents monitor reports malformed callback payloads

- [x] `FSEventsFileMonitorClient` は callback の path payload cast 失敗や event count 不整合を空イベントに丸めない。
- [x] 不整合時は `eventPayloadMismatch` を queue し、次の `nextEvent()` で呼び出し側へ error として返す。
- [x] Source regression test で `compactMap` による部分 drop の復活を検出する。
- [x] 完了条件: ファイル監視の OS callback 異常で成果物更新が「何も起きなかった」ように見えない。

### P10-101: Disabled mail draft client fails closed

- [x] Runtime の `UnavailableMailDraftClient` は draft 作成だけを fail closed にし、未対応 list 操作を空配列成功として返さない。
- [x] `MailDraftClient` protocol から未使用の `listDrafts` 要求を外し、runtime に「メール下書きが0件」と見える mock 的 read path を残さない。
- [x] Source regression test で `UnavailableMailDraftClient` と `MailDraftClient` に空成功 list path が復活しないことを確認する。
- [x] 完了条件: 外部メール連携を除外した release runtime が、メール下書き連携の未対応状態を正常な空状態として誤表示しない。

### P10-102: MCP audit load failure is visible

- [x] `externalMCPAuditRows()` の catch で `[]` を返す silent fallback をやめ、audit load result と error message を分ける。
- [x] `ExternalMCPSettingsViewModel` は `auditRows` と `auditErrorMessage` を別状態で保持し、空履歴と読込失敗を区別する。
- [x] Settings の MCP Audit セクションは audit 読込失敗を warning として表示し、「No external calls recorded」と誤表示しない。
- [x] unit / source regression test で audit load failure が空履歴に丸められないことを確認する。
- [x] 完了条件: MCP 監査ログが壊れている、または開けない状態を、履歴がないだけの正常状態として出荷しない。

### P10-103: Hybrid knowledge search does not hide broken embeddings behind FTS

- [x] `HybridKnowledgeRetriever` は hybrid / vector mode の query embedding 次元不一致を FTS-only 成功に丸めない。
- [x] `KnowledgeVectorIndex.search` の既存次元検証を必ず通し、`KnowledgeVectorIndexError.dimensionMismatch` を caller へ返す。
- [x] `KnowledgeAdvancedTests` で FTS hit がある場合でも query embedding 破損が search failure になることを確認する。
- [x] 完了条件: semantic search が壊れている状態を、通常の全文検索結果だけで成功したように見せない。

### P10-104: External MCP audit history requires verified metadata

- [x] `ExternalMCPAuditHistory.rows` は `risk` / `approval` の欠落を `unknown` に丸めない。
- [x] MCP audit metadata 欠落は `ExternalMCPAuditHistoryError.missingMetadata` として caller へ返す。
- [x] Settings の MCP Audit 読込は metadata decode failure を空履歴ではなく warning path に流す。
- [x] 完了条件: MCP監査履歴が権限リスクや承認状態を欠いたまま、正常な外部呼び出し履歴として表示されない。

### P10-105: External MCP audit arguments are explicit and required

- [x] `ExternalMCPToolExecutor` は引数なし実行を空文字ではなく `No arguments` として監査metadataに残す。
- [x] `ExternalMCPAuditHistory.rows` は `arguments` metadata 欠落/空文字を blank summary に丸めない。
- [x] `ExternalMCPTests` で引数なし監査と arguments metadata 欠落の両方を固定する。
- [x] 完了条件: MCP外部呼び出しの監査履歴で、引数なしと監査欠落が同じ空表示に見えない。

### P10-106: External MCP audit identity metadata is required

- [x] `ExternalMCPAuditHistory.rows` は `server_name` 欠落を `External MCP` に丸めない。
- [x] `ExternalMCPAuditHistory.rows` は `tool_name` 欠落を `AuditEvent.action` に丸めない。
- [x] `ExternalMCPTests` で server / tool identity metadata 欠落が audit history decode failure になることを確認する。
- [x] 完了条件: MCP外部呼び出しの監査履歴で、どのserver/toolか不明な履歴が正常な履歴として表示されない。

### P10-107: External MCP terminal audit history requires duration and error metadata

- [x] `ExternalMCPAuditHistory.rows` は `succeeded` / `failed` の `duration_ms` 欠落を空 duration に丸めない。
- [x] failed event の `error` 欠落を blank error summary に丸めない。
- [x] started event は実行開始証跡として duration / error なしを許可する。
- [x] 完了条件: MCP外部呼び出しの終端履歴が、所要時間や失敗理由を欠いたまま正常な監査履歴として表示されない。

### P10-108: Menu bar summary load failure is not rendered as empty state

- [x] `MenuBarSummaryController` は初回読込失敗時に空 summary の `No deadlines need attention` を表示用 empty state として返さない。
- [x] Menu bar UI は `viewModel.emptyStateLabel` を直接読まず、controller の error-aware empty state を使う。
- [x] `MenuBarSummaryViewModelTests` と `AppExperienceSourceTests` で読込失敗と UI wiring の regression を固定する。
- [x] 完了条件: DB / local store が開けない状態を、締切がない正常状態として menu bar に表示しない。

### P10-109: Watcher diagnostics load failure is visible in Settings

- [x] `WatcherDiagnosticsSnapshot` は permission status だけでなく diagnostics load failure message を保持できる。
- [x] Runtime factory は local daily-check state store を開けない場合、Last / Next の空表示だけに丸めず warning message を返す。
- [x] Settings の Watcher section は `watcherDiagnosticsSnapshot.errorMessage` を警告として表示する。
- [x] 完了条件: daily check state / local DB が読めない状態を、まだ一度もチェックしていないだけの正常状態として表示しない。

### P10-110: Project board load failure is not rendered as no projects

- [x] `ProjectBoardViewModel` は load failure 中に empty project state を表示してよいかを error-aware に判定する。
- [x] Project Board detail は DB / local store の読込失敗時に `Project Board Unavailable` を表示し、`No Projects` に丸めない。
- [x] `ProjectBoardStoreTests` と `AppExperienceSourceTests` で load failure と UI state ordering の regression を固定する。
- [x] 完了条件: CRUD の永続DBが開けない状態を、単にプロジェクトが未作成な正常状態として表示しない。

### P10-111: API key save does not hide Keychain status refresh failure

- [x] `AppSettingsViewModel` は API key 保存 / 削除後の Keychain status refresh 成否を判定する。
- [x] status refresh が失敗した場合、`Unavailable` と error message を残し、成功メッセージで上書きしない。
- [x] OpenAI / OpenRouter の両方で保存後 status refresh failure の regression test を追加する。
- [x] 完了条件: API key が保存できたように見えても、直後に Keychain から状態確認できない場合は成功扱いしない。

### P10-112: Project board appearance and mouse-driven status movement polish

- [x] `System` / `Light` / `Dark` の永続 appearance preference は Settings の Appearance セクションに集約する。
- [x] Task card はマウス操作で前後ステータスへ移動でき、別カラムへの drag and drop でも SQLite の task status を更新する。
- [x] `ui-samples/` の方向性に合わせ、Kanban column / task card は system-adaptive material、ステータス色、安定幅、drag handle、drop target affordance を持つ。
- [x] `AppExperienceSourceTests` と `ProjectBoardStoreTests` で Settings-only appearance selection、mouse move controls、drag payload validation、adaptive card styling の regression を固定する。
- [x] 完了条件: ライト/ダークどちらでもタスクの状態変更がポインタ操作だけで直感的に完了する。

### P10-113: OAuth refresh token removal failures are fail-closed

- [x] `KeychainOAuthCredentialStore.saveTokens` は refresh token なしの保存時に、古い refresh token 削除失敗を `try?` で握りつぶさない。
- [x] refresh token 削除に失敗した場合、新しい access token / metadata を保存せず、既存 credential を壊さない。
- [x] `SaaSConnectorTests` で削除失敗時の throw、既存 access token、既存 refresh token、既存 metadata の保持を確認する。
- [x] 完了条件: 外部連携が release scope 外でも、Keychain に古い refresh token を残したまま「refresh なし credential」として成功表示しない。

### P10-114: Review execution blocks unavailable tools before execution

- [x] `ToolRegistry.validate(action:)` は active registry に tool が存在しない場合、空の validation result ではなく action-level issue を返す。
- [x] `ActionExecutor` は registry 欠落を tool 実行後の failure ではなく preflight validation failure として止める。
- [x] `ToolRegistryTests` と `ActionExecutorTests` で unavailable tool が review 前に検出されることを固定する。
- [x] 完了条件: runtime registry が壊れている状態で、Review UI が入力問題なし / 実行可能に見えない。

### P10-115: Tool integer identifiers are not truncated from fractional JSON numbers

- [x] `ToolArguments.optionalInt64` は JSON number / string の ID を整数として厳密に検証し、小数や不正文字列を missing 扱いにしない。
- [x] Project / Task / Calendar / Reminder / Notification / Knowledge tool schema は ID、duration、offset など整数フィールドを `integer` として review preflight で検出する。
- [x] `ToolArgumentsTests` と `ToolRegistryTests` で fractional number が mutation 前に validation failure になることを固定する。
- [x] 完了条件: LLM が `1.9` のような値を返しても `1` に丸めて別 Project / Task / Frame を更新しない。

### P10-116: Invalid task status does not partially reopen completed projects

- [x] `task.update` は completed project の復元前に status を `StoreFieldValidation.taskStatus` で検証する。
- [x] 不正 status で task 更新が失敗した場合、task row だけでなく project status も変更しない。
- [x] `ProjectTaskKnowledgeToolTests` で invalid status が completed project を active に戻さないことを固定する。
- [x] 完了条件: Review 実行で不正な task status が混ざっても、失敗した action が project 状態だけを部分変更しない。

### P10-117: Optional string tool arguments fail closed on wrong JSON types

- [x] `ToolArguments.optionalString` は値が存在するのに string でない場合、missing 扱いにせず validation failure を返す。
- [x] Notification / Calendar / Reminder / File / Mail / Task tool の optional string call site は `try` で型不一致を caller へ返す。
- [x] `ToolArgumentsTests` と `ProjectTaskKnowledgeToolTests` で non-string optional field が永続 row 作成前に拒否されることを固定する。
- [x] 完了条件: LLM / MCP / JSON 経由の number や object が `dueAt` / `body` / `notes` などの任意文字列フィールドで silently dropped されない。

### P10-118: Trimmed string array arguments reject blank elements

- [x] `ToolArguments.trimmedStringArray` / `optionalTrimmedStringArray` は空白要素を filter で落とさず validation failure にする。
- [x] `project.create` の `tags` と `frame.update` の `triggers` は blank element を含む入力で永続 row / 既存 row を部分更新しない。
- [x] `ToolArgumentsTests` と `ProjectTaskKnowledgeToolTests` で blank array element が silently dropped されないことを固定する。
- [x] 完了条件: LLM / MCP / JSON 経由の tags / triggers が空白要素を含んでも、一部欠落の成功として保存されない。

### P10-119: MCP stdio malformed responses are reported as invalid protocol responses

- [x] `MCPStdioTransport` は stdout の malformed JSON-RPC line を generic transport failure に丸めず、`MCPClientError.invalidResponse` として返す。
- [x] raw response / DecodingError の詳細は UI や audit metadata に流さず、ユーザー登録 MCP server の protocol 不正として切り分ける。
- [x] 実プロセス stdio script を使う `ExternalMCPTests` で malformed JSON 応答の分類を固定する。
- [x] 完了条件: 外部連携を release scope から外していても、ユーザーが登録した MCP server の壊れた応答を通信障害や空の tool list と誤認しない。

### P10-120: Action plan schema must load from packaged resources only

- [x] `ActionPlanSchema.loadData()` は bundle / SwiftPM resource に action-plan schema がない場合、source tree の `Resources` へ fallback しない。
- [x] `PlanningPromptBuilder.loadDefault()` は packaged schema が欠落していれば明示的に失敗し、開発 checkout 上だけ成功する状態を作らない。
- [x] `ActionPlanSchemaTests` / `PlanningPromptBuilderTests` / `AppExperienceSourceTests` で packaged schema load と source-tree fallback absence を固定する。
- [x] 完了条件: 配布 app bundle の resource packaging 不備が、開発環境の source tree によって隠れない。

### P10-121: MCP tool call `isError` must be boolean when present

- [x] `MCPClient.callTool` は `tools/call` response の `result.isError` が存在する場合、boolean 以外を `false` に丸めない。
- [x] `result.isError` 欠落時だけ MCP 互換の default として `false` を使う。
- [x] `ExternalMCPTests` で string `isError` が `MCPClientError.invalidResponse` になることを固定する。
- [x] 完了条件: ユーザー登録 MCP server の壊れた error flag を成功結果として audit / review path に流さない。

### P10-122: MCP text content must not drop wrong JSON types

- [x] `MCPContentItem.parse` は content `text` が存在する場合、string 以外を `nil` に丸めない。
- [x] `text` 欠落時だけ optional content として扱い、型不一致は `MCPClientError.invalidResponse` にする。
- [x] `ExternalMCPTests` で number `text` が invalid response になることを固定する。
- [x] 完了条件: MCP tool の壊れた出力本文が空本文として review / audit path に流れない。

### P10-123: MCP tool metadata must not hide wrong JSON types

- [x] `MCPToolDefinition.parse` は tool `description` が存在する場合、string 以外を空文字に丸めない。
- [x] `MCPToolDefinition.parse` は tool `title` が存在する場合、string 以外を `nil` に丸めない。
- [x] `description` / `title` 欠落時だけ MCP 互換の optional metadata として扱い、型不一致は `MCPClientError.invalidResponse` にする。
- [x] `ExternalMCPTests` で number `description` と array `title` が invalid response になることを固定する。
- [x] 完了条件: ユーザー登録 MCP server の壊れた tool metadata を空説明 / name fallback として catalog や review UI に表示しない。

### P10-124: MCP initialize server identity metadata must be typed

- [x] `MCPClient.initialize` は `result.serverInfo` が存在する場合、object 以外を無視して接続成功扱いにしない。
- [x] `result.serverInfo.name` が存在する場合、string 以外を `nil` に丸めない。
- [x] `serverInfo` / `serverInfo.name` 欠落時だけ MCP 互換の optional metadata として扱い、型不一致は `MCPClientError.invalidResponse` にする。
- [x] `ExternalMCPTests` で string `serverInfo` と number `serverInfo.name` が invalid response になることを固定する。
- [x] 完了条件: ユーザー登録 MCP server の壊れた initialize identity metadata を正常接続として扱わない。

### P10-125: Settings-only theme switching and mouse drag affordances stay discoverable

- [x] Project Board の左サイドバーと右上ヘッダーから appearance / Settings control を削除し、Theme 変更は Settings 画面の `Theme` picker だけにする。
- [x] MenuBarPanel の右上 Settings gear も削除し、Settings への導線は macOS app menu の `Settings...` / `Command+,` に集約する。
- [x] Scene-level `.preferredColorScheme(effectiveAppearancePreference.colorScheme)` と Settings の同じ `@AppStorage` key を使い、通常画面ごとにテーマ状態が分岐しない。UI evidence capture時だけ `SOLOPM_APPEARANCE_PREFERENCE` でLight/Dark/Systemを明示できる。
- [x] Kanban task card の drag operation は raw payload 文字列ではなく、タスクカードとして認識できる preview を表示する。
- [x] `AppExperienceSourceTests` で Project Board 内に appearance control が残らず、Settings にだけ Theme picker があることを固定する。
- [x] 完了条件: `ui-samples/` の3ペインUIに近い導線で、Board は作業操作に集中し、Light/Dark切替は Settings から一貫して変更できる。

### P10-126: Knowledge vector provider identity must be valid before persistence

- [x] `SQLiteKnowledgeVectorIndex.upsert` は blank `providerID` を `knowledge_frame_vectors` に保存しない。
- [x] `KnowledgeVectorIndexError.invalidProviderID` を追加し、保存時点で provider identity の欠落を fail fast にする。
- [x] test support の in-memory vector index も同じ provider identity validation を使い、unit test と runtime の不変条件を分岐させない。
- [x] `KnowledgeAdvancedTests` で blank provider ID が保存前に拒否され、vector row が残らないことを固定する。
- [x] 完了条件: ローカルKnowledge retrieval が匿名/出所不明のembedding vectorを保存して、後続の検索や説明で壊れる状態を作らない。

### P10-127: SQLite foreign keys must be enforced in runtime connections

- [x] `SQLiteConnection` は open 直後に `PRAGMA foreign_keys = ON` を有効化し、schema の `FOREIGN KEY` を実際に強制する。
- [x] `DatabaseMigrationTests` で orphan child row が SQLite に保存されないことを固定する。
- [x] `KnowledgeAdvancedTests` で存在しない `knowledge_frames.id` への vector upsert が `knowledge_frame_vectors` に孤立rowを残さないことを固定する。
- [x] 既存の Project / Task / Knowledge CRUD test が FK 有効化後も green であることを確認する。
- [x] 完了条件: ローカルDBの参照整合性がDDL上の飾りではなく、runtime connectionで強制される。

### P10-128: Knowledge frame CRUD must update FTS atomically

- [x] `SQLiteKnowledgeFrameStore.create` は `knowledge_frames` と `knowledge_frames_fts` の insert を同一 transaction にする。
- [x] `SQLiteKnowledgeFrameStore.update` は FTS delete、base row update、FTS insert を同一 transaction にする。
- [x] `SQLiteKnowledgeFrameStore.delete` は FTS delete と base row delete を同一 transaction にする。
- [x] `LocalStoreTests` で FTS write failure、base update failure、base delete failure のいずれでも base row と検索 index が片方だけ更新されないことを固定する。
- [x] 完了条件: Knowledge CRUD の途中失敗で、実データと検索結果が分岐したまま残らない。

### P10-129: OpenAI Responses output_text must not be silently dropped

- [x] `OpenAIResponsesOutputTextExtractor` は `output_text` content に `text` が欠落している場合、`compactMap` で捨てて別の content だけを成功扱いにしない。
- [x] `OpenAIResponsesProviderTests` で欠損 `output_text` と正常 `output_text` が混在する response が `LLMProviderError.invalidResponse` になることを固定する。
- [x] OpenAI Responses / Chat Completions / ActionPlan parser の focused tests が green であることを確認する。
- [x] 完了条件: LLM provider の壊れた response chunk が action plan 生成の成功経路に紛れ込まない。

### P10-130: OpenAI Responses message items must not be silently dropped

- [x] `OpenAIResponsesOutputTextExtractor` は `message` output item に `content` が欠落している場合、reasoning item と同じ扱いで捨てない。
- [x] `OpenAIResponsesOutputItem` は `type` を decode し、`message` item の content 欠損だけを `LLMProviderError.invalidResponse` として分類する。
- [x] `OpenAIResponsesProviderTests` で欠損 `message.content` と正常 message が混在する response が成功扱いにならないことを固定する。
- [x] 完了条件: OpenAI Responses の壊れた message item が、別の正常 chunk によって隠れない。

### P10-131: Chat completions blank choice content must not be silently dropped

- [x] `ChatCompletionsOutputTextExtractor` は空白だけの `message.content` が含まれる choice を別 choice の正常 content で隠さない。
- [x] `ChatCompletionsCompatibleProviderTests` で空白 content と正常 content が混在する response が `LLMProviderError.invalidResponse` になることを固定する。
- [x] OpenAI Responses / Chat Completions / ActionPlan parser の focused tests が green であることを確認する。
- [x] 完了条件: Chat Completions 互換 provider の壊れた response choice が action plan 生成の成功経路に紛れ込まない。

### P10-132: LLM provider response decode failures are user-facing invalid responses

- [x] OpenAI Responses の success HTTP body が期待 schema と違う場合、raw `DecodingError` ではなく `LLMProviderError.invalidResponse` を返す。
- [x] Chat Completions 互換 provider の success HTTP body が期待 schema と違う場合、raw `DecodingError` ではなく `LLMProviderError.invalidResponse` を返す。
- [x] Provider tests で schema mismatch が low-level decode error として UI / caller に漏れないことを固定する。
- [x] 完了条件: 壊れた LLM provider 応答がユーザーに実装内部の decode failure として露出せず、復旧可能な provider invalid response として扱われる。

### P10-133: BYOK providers reject malformed stored API keys before network or file IO

- [x] OpenAI Responses provider は Keychain 由来 API key に内部 whitespace / newline がある場合、HTTP request を作る前に失敗する。
- [x] Chat Completions 互換 provider は OpenRouter / OpenAI-compatible API key に内部 whitespace / newline がある場合、HTTP request を作る前に失敗する。
- [x] OpenAI Transcribe provider は内部 whitespace 入り API key を音声ファイル読み込み前に拒否する。
- [x] 共通 validator を使い、Settings 保存時 validation と runtime provider validation の条件を分岐させない。
- [x] 完了条件: 過去バージョンや破損 Keychain 値が残っていても、secret を malformed Authorization header や transcript request に流さない。

### P10-134: Settings does not show malformed stored API keys as configured

- [x] `AppSettingsViewModel.refreshOpenAIAPIKeyStatus()` は Keychain に内部 whitespace 入り key が残っている場合、`Configured` ではなく `Invalid` を表示する。
- [x] `AppSettingsViewModel.refreshOpenRouterAPIKeyStatus()` は Keychain に内部 whitespace 入り key が残っている場合、`Configured` ではなく `Invalid` を表示する。
- [x] UI error message は秘密値を含めず、Settings で再入力すべきことを伝える。
- [x] Settings 保存時 validation と runtime provider validation と同じ `APIKeyValidator` を status refresh でも使う。
- [x] 完了条件: 破損 Keychain 値が残っていても、ユーザーが「設定済み」と誤認して AI / STT 実行に進まない。

### P10-135: Kanban drag uses a task-specific transfer payload

- [x] Board card の drag payload は plain text `String` ではなく、SoloPM task 専用の `Transferable` payload にする。
- [x] Drop target は typed payload から task ID を取り出し、既存の ViewModel validation 経由で status を永続化する。
- [x] 旧 raw string validation は regression と defensive path として残し、不正 payload の部分移動を防ぐ。
- [x] `AppExperienceSourceTests` と `ProjectBoardStoreTests` で typed drag payload と mouse-driven status move を固定する。
- [x] 完了条件: 他アプリやテキスト入力由来の偶然の文字列 drop と、SoloPM task card drag operation を UI / code 上で分離する。

### P10-136: MCP registration store failures do not erase the visible server

- [x] `ExternalMCPSettingsViewModel.refresh()` は MCP registration store の decode / load failure 時に、現在表示中の registration を blank に戻さない。
- [x] MCP registration load failure は `decodingFailed` などの内部 enum 名ではなく、local database から読み込めないことを UI に表示する。
- [x] MCP registration save / delete failure は `encodingFailed` などの内部 enum 名ではなく、local database に保存できないことを UI に表示する。
- [x] `ExternalMCPTests` で load failure 時の表示保持と save failure 時の user-facing error を固定する。
- [x] 完了条件: SQLite 側の破損や保存失敗が起きても、ユーザーが登録済み MCP server を「消えた」と誤認せず、復旧すべき local data 問題として扱える。

### P10-137: Audited tool arguments are redacted before persistence

- [x] `AuditedTool` は caller が `RedactingAuditLogger` を明示注入しなくても、監査 metadata に入れる `arguments` を `DeveloperSecretRedactor` に通す。
- [x] `apiKey` / `token` / `password` / `secret` などの sensitive key は値の形式に関係なく argument summary 作成時点で置換する。
- [x] Tool の result summary / error message も監査 metadata に入れる前に redaction する。
- [x] Assignment redaction は `apiKey=...` の値だけを隠し、後続の安全な audit field を巻き込んで消さない。
- [x] `SystemToolTests` で non-redacting logger でも API key が監査ログに残らないことを固定する。
- [x] `DraftGenerationTests` で assignment redaction の境界を固定する。
- [x] 完了条件: 内蔵 CRUD / tool execution の audit path が logger 構成ミスで provider token や API key を SQLite audit log に保存しない。

### P10-138: Review executor audit metadata is redacted before persistence

- [x] `ActionExecutor` は tool success の `summary` を audit metadata に入れる前に `DeveloperSecretRedactor` に通す。
- [x] `ActionExecutor` は tool failure の `error` を audit metadata に入れる前に `DeveloperSecretRedactor` に通す。
- [x] caller が `RedactingAuditLogger` を明示注入しない test logger でも、provider token / API key が action execution audit に残らないことを固定する。
- [x] `ActionExecutorTests` で success summary と failure error の両方を regression test にする。
- [x] 完了条件: Review execution の永続 audit path が logger 構成ミスで tool result / error 由来の secret を SQLite audit log に保存しない。

### P10-139: External MCP argument redaction does not depend on value shape

- [x] `ExternalMCPToolExecutor.preview` の argument summary は `apiKey` / `api-key` / `token` / `password` / `secret` などの sensitive key を値の形式とキー表記揺れに関係なく置換する。
- [x] `ExternalMCPToolExecutor.call` の audit metadata も同じ key-based redaction を通す。
- [x] Safe field は残し、MCP tool call の監査ログが完全にデバッグ不能な文字列にならないようにする。
- [x] `ExternalMCPTests` で空白を含む壊れた secret 値が preview / audit log の両方に残らないことを固定する。
- [x] 完了条件: ユーザー登録 MCP server への tool arguments が壊れた provider token / API key を含み、キーが camelCase / kebab-case で揺れても、MCP preview / SQLite audit log に保存しない。

### P10-140: Release readiness scan must fail closed when runtime source paths are missing

- [x] `release_readiness_report.sh` は runtime source directory が欠けている場合、`rg` の error を「検出なし」と扱わず blocker にする。
- [x] `Sources/SoloPMCore` / `Sources/SoloPMApp` / `Sources/SoloPMCLI` の固定 scan path が壊れたら `READY` を出さない。
- [x] `ReleasePipelineTests` で一時 release root に runtime source 欠落 fixture を作り、missing source で non-zero exit になることを固定する。
- [x] 完了条件: runtime mock/fake scan の対象ディレクトリが typo / move / delete で欠けた状態を release ready と誤判定しない。

### P10-141: Runtime marker scan command errors are release blockers

- [x] `release_readiness_report.sh` は `rg` exit code `0` / `1` / その他を分け、scan error を marker なしとして扱わない。
- [x] `rg` が権限・I/O・内部エラーで失敗した場合は scan output を表示し、`runtime mock/fake scan failed` blocker を出す。
- [x] `ReleasePipelineTests` で fake `rg` を `PATH` に差し込み、scan command error で release report が non-zero になることを固定する。
- [x] 完了条件: runtime source scan が実行不能な状態で `READY` を出さず、リリース前に検出可能な blocker として残す。

### P10-141b: Future phase planning is not a current release blocker

- [x] `release_readiness_report.sh` は `Phase12+` の future planning を現在リリースの blocker にしない。
- [x] release checklist scan は Phase0〜Phase11 の現在 release gate に限定する。
- [x] `ReleasePipelineTests` で Phase11 までに限定されることを固定する。
- [x] Phase checklist blocker はファイル名と行番号を出し、未完了gateの場所を追えるようにする。
- [x] 完了条件: 次フェーズの未完了計画を追加しても、現在リリースの `NOT READY` 理由が水増しされない。

### P10-141c: Release environment preflight next actions are explicit

- [x] `release_readiness_report.sh` は `verify_release_environment.sh` が失敗した場合、release machineで揃えるべき `packaging/signing.env`、`packaging/notarization.env`、production Sparkle feed/key、signed/notarized app、appcast、`packaging/release-evidence.json` を `NEXT:` として表示する。
- [x] `ReleasePipelineTests` で preflight failure fixture を作り、Developer ID signing blocker と release-machine next action が同時に出ることを固定する。
- [x] 完了条件: Developer ID / notarization / Sparkle / evidence の外部条件が未完了な場合でも、次に実施すべきrelease checklist手順がreport内で分かる。

### P10-142: Manual release environment evidence must be concrete

- [x] `create_release_evidence.sh` は manual check flag がある場合、空白だけの `--manual-environment` を拒否する。
- [x] `create_release_evidence.sh` は `macOS version, hardware, clean user/install notes` などの template / placeholder 文言を release evidence として保存しない。
- [x] `verify_release_environment.sh` は手書き evidence の `manualChecks.environment` も同じ concrete 判定で検査する。
- [x] `ReleasePipelineTests` で blank / template manual environment の生成拒否と preflight 拒否を固定する。
- [x] 完了条件: clean environment / login item の manual evidence が、テンプレートをそのままコピーしただけの証跡で release ready にならない。

### P10-143: Manual release review metadata must identify the reviewer

- [x] `create_release_evidence.sh` は `--checked-by` が空白の場合、release evidence を作成しない。
- [x] `create_release_evidence.sh` は `--note` が空白の場合、review note を保存しない。
- [x] `verify_release_environment.sh` は hand-written evidence の `review.checkedBy` / `review.checkedAt` 欠落を blocker にする。
- [x] `ReleasePipelineTests` で blank reviewer、blank note、missing review metadata を固定する。
- [x] 完了条件: release evidence が「誰がいつ確認したか」を欠いた状態で release ready にならない。

### P10-144: Release evidence must be bound to the packaged source commit

- [x] `package_release.sh` は artifact ごとの package evidence manifest に current git commit を記録する。
- [x] `create_release_evidence.sh` は release evidence に current git commit を記録し、package evidence の git commit と一致しない場合は evidence を作らない。
- [x] `verify_release_environment.sh` は release evidence / package evidence の git commit が current checkout と一致しない場合、release blocker にする。
- [x] `ReleasePipelineTests` で stale package source commit と stale release source commit を固定する。
- [x] 完了条件: 古い artifact や別 revision の manual evidence が、現在の source checkout の release ready 証跡として扱われない。

### P10-145: Manual release evidence must include explicit review notes

- [x] `create_release_evidence.sh` は manual check flag が 1 つでも true の場合、少なくとも 1 つの明示的な `--note` を必須にする。
- [x] `verify_release_environment.sh` は hand-written release evidence の `review.notes` 欠落を blocker にする。
- [x] `ReleasePipelineTests` で manual flags without note と missing review notes evidence を固定する。
- [x] 完了条件: Gatekeeper / clean install / login item などの manual gate が、理由や判断根拠のない boilerplate review note だけで release ready にならない。

### P10-146: Secret redaction pattern initialization fails closed

- [x] `DeveloperSecretRedactor` は default pattern 初期化で `try! NSRegularExpression` を使わず、regex compile failure を runtime crash にしない。
- [x] invalid redaction pattern が混入した場合は入力本文を丸ごと `[REDACTED_SECRET]` に置き換え、secret leak より過剰秘匿を優先する。
- [x] `DraftGenerationTests` で壊れた regex pattern を注入し、fail-closed redaction と `redactor_initialization_failed` report を固定する。
- [x] source regression test で `try?` による silent skip と `try!` による crash path の復活を防ぐ。
- [x] 完了条件: secret redaction pattern の破損が、runtime crash または secret を無検知で通す成功 path にならない。

### P10-147: Audit metadata encoding does not fall back to empty JSON

- [x] `SQLiteAuditLogger.record` は metadata JSON の UTF-8 string 化に失敗した場合、`{}` へ置き換えず `DatabaseError.executeFailed` を投げる。
- [x] source regression test で `String(data: metadataData, encoding: .utf8) ?? "{}"` の復活を防ぐ。
- [x] 完了条件: audit metadata persistence が、encoding failure 時に監査 context を空 object として保存成功に見せない。

### P10-148: ActionPlan schema fallback only hides missing resources

- [x] `ActionPlanSchema.loadData()` は main bundle schema が `resourceNotFound` の場合だけ SwiftPM module resource へ fallback する。
- [x] main bundle schema が存在していて読み取り失敗した場合は、module resource で補わず元の error を返す。
- [x] `ActionPlanSchemaTests` で missing resource fallback と primary read error propagation を固定する。
- [x] source regression test で `try? loadData(bundle:)` による広すぎる fallback の復活を防ぐ。
- [x] 完了条件: app bundle の schema packaging / read failure が、dev module resource によって成功に見えない。

### P10-149: Knowledge vector JSON encoding does not fall back to empty vectors

- [x] `SQLiteKnowledgeVectorIndex.upsert` の vector JSON encoding は UTF-8 string 化失敗時に `[]` を保存せず、`DatabaseError.executeFailed` を返す。
- [x] source regression test で `String(data: data, encoding: .utf8) ?? "[]"` の復活を防ぐ。
- [x] 完了条件: embedding vector persistence が encoding failure 時に空ベクトル保存成功として見えない。

### P10-150: Manual release evidence rejects boilerplate review notes

- [x] `create_release_evidence.sh` は manual check flag が true の場合、`Manual checks completed` のような汎用 note を evidence として保存しない。
- [x] `verify_release_environment.sh` は hand-written release evidence の `review.notes` が汎用文だけの場合、release blocker にする。
- [x] `ReleasePipelineTests` で evidence generation と preflight の boilerplate note rejection を固定する。
- [x] 完了条件: Gatekeeper / clean install / login item の manual evidence が、具体的な検証内容を含まないレビュー文だけで release ready に見えない。

### P10-151: AI provider malformed HTTP error bodies stay actionable and redacted

- [x] OpenAI Responses / Chat Completions compatible provider は、HTTP error body が期待 JSON でない場合も `No error message` へ落とさず、短い redacted preview を返す。
- [x] malformed error body preview は `DeveloperSecretRedactor` を通し、API key / token 形式の値を出さない。
- [x] provider tests で malformed 500 response の status、request id、redaction、`No error message` 不使用を固定する。
- [x] source regression test で provider が `LLMHTTPErrorMessageExtractor` を使い続けることを確認する。
- [x] 完了条件: BYOK AI provider の upstream failure が、secret を漏らさず調査可能な runtime error として表示される。

### P10-152: Project board multi-card drag moves are atomic

- [x] Project board store に複数 task status move 用の `moveTasks` API を追加し、UI drag/drop が逐次 `moveTask` ループへ戻らないようにする。
- [x] SQLite implementation は複数 task move を1 transactionで実行し、途中失敗時に先行taskのstatus変更もrollbackする。
- [x] ViewModel tests で、複数drag/dropの2件目が失敗しても1件目だけ移動した永続状態を残さないことを固定する。
- [x] source regression test で `ProjectBoardViewModel.moveDroppedTasks` が atomic bulk API を使い続けることを確認する。
- [x] 完了条件: Notion / GitHub Projects 風の複数カード移動で、失敗時にUIとSQLite永続状態が分岐しない。

### P10-153: Task tool CRUD covers scheduling and detail metadata

- [x] `task.create` / `task.bulk_create` は title だけでなく detail、dueAt、priority、projectId を SQLite task row に永続化する。
- [x] `task.update` は title / status だけでなく detail、dueAt、priority、projectId を更新できる。
- [x] Tool input schema は create / bulk_create / update の editable metadata を公開し、Review UI validation が unknown argument として落とさない。
- [x] focused tests で create、bulk create、update、schema export の metadata coverage を固定する。
- [x] 完了条件: AI-generated Action Plan からでも、UI task card と同じ主要メタデータを失わずCRUDできる。

### P10-154: Task tool CRUD can explicitly clear optional metadata

- [x] `task.update` は `projectId` / `detail` / `dueAt` / `priority` の `JSON null` を、未指定ではなく明示クリアとして扱う。
- [x] SQLite task store は nullable field update で unchanged / set / clear を区別し、既存の `update` 呼び出し互換を保つ。
- [x] Tool input schema は `integer|null` / `string|null` を表現し、Review UI validation が clear 操作を拒否しない。
- [x] `ProjectTaskKnowledgeToolTests` / `LocalStoreTests` / `ToolArgumentsTests` で null clear、schema、永続層、引数層の責務を固定する。
- [x] 完了条件: AI-generated Action Plan と Review UI から、タスクカードの主要メタデータを設定するだけでなく安全に削除できる。

### P10-155: Project tool CRUD covers editable metadata updates and clears

- [x] `project.update` は create で保存できる editable metadata のうち、`priority` / `deadline` / `workspacePath` / `tags` を更新できる。
- [x] `project.update` は `priority` / `deadline` / `workspacePath` の `JSON null` を `NULL` クリアとして扱い、`tags` の `JSON null` を空タグ配列として扱う。
- [x] SQLite project store は nullable field update で unchanged / set / clear を区別し、既存の `update` / `archive` / `restore` 呼び出し互換を保つ。
- [x] Tool input schema は `string|null` / `array|null` を表現し、Review UI validation が metadata update / clear 操作を拒否しない。
- [x] `sourceCommand` は作成時来歴として更新対象から外し、Review UI から provenance を上書きしない。
- [x] 完了条件: AI-generated Action Plan と Review UI から、Project の主要メタデータを作成後も編集・クリアできる。

### P10-156: Read tools return usable persisted records, not only counts

- [x] `project.list` は `count` に加えて、active project の `id` / `title` / `status` / metadata / tags を `projects` 配列で返す。
- [x] `task.listDue` / `task.listOverdue` は `count` に加えて、該当 task の `id` / `projectId` / `title` / `status` / detail / due / priority を `tasks` 配列で返す。
- [x] `frame.list` / `frame.search` は `count` に加えて、該当 frame の `id` / `name` / `body` / triggers を `frames` 配列で返す。
- [x] `sourceCommand` は来歴に秘密っぽい文字列が混ざる可能性があるため、一覧 output では返さない。
- [x] 既存互換のため `count` と summary は残し、Review / agent / CLI が詳細データを使える追加 output として返す。
- [x] `ProjectTaskKnowledgeToolTests` で Project / Task / Knowledge の read output が実永続データを含むことを固定する。
- [x] 完了条件: 外部連携なしでも、local SQLite の既存データをAI Reviewが再利用できる粒度で読み取れる。

### P10-157: Review tools expose local Task and Knowledge delete CRUD

- [x] `ActionTool` / packaged `action-plan.schema.json` に `task.get` / `task.delete` / `frame.delete` を追加し、schema と enum のズレを防ぐ。
- [x] `task.get` は read tool としてSQLite taskの `id` / `projectId` / `title` / `status` / detail / due / priority を返す。
- [x] `task.delete` は承認付き write tool としてSQLite task rowを削除し、UI-only delete pathに閉じない。
- [x] `frame.delete` は承認付き write tool としてKnowledge Frame本体とFTS indexを既存store transaction経由で削除する。
- [x] `ToolRegistry.phase2Core` は新しいTask/Knowledge CRUD toolsを登録し、Review executionで利用できる。
- [x] `ProjectTaskKnowledgeToolTests` / `ActionPlanDomainTests` / `ActionPlanSchemaTests` で read/write risk、schema、registry、永続削除を固定する。
- [x] 完了条件: 外部連携なしでも、AI ReviewからLocal Task / Knowledge FrameのCreate/Read/Update/Deleteが承認付きで成立する。

### P10-158: MCP registration store uses row-level local CRUD

- [x] `MCPServerRegistrationStore` は全件置換だけでなく `saveRegistration` / `deleteRegistration` を公開する。
- [x] `SQLiteMCPServerRegistrationStore.saveRegistration` は既存 `sort_order` を保持して1件upsertし、新規登録は末尾に追加する。
- [x] `SQLiteMCPServerRegistrationStore.deleteRegistration` は対象IDだけを削除し、存在しないIDはno-opとして扱う。
- [x] `ExternalMCPSettingsViewModel.save` / `deleteRegistration` は全件保存ではなく行単位CRUD APIを使う。
- [x] `ExternalMCPTests` でupsert、append、single delete、ViewModel経由保存/削除を固定する。
- [x] 完了条件: 外部MCPサーバに接続しなくても、ローカルSQLite上のMCP設定CRUDが行単位で実働し、他の登録を巻き込まない。

### P10-159: Project Board is visible on normal macOS launch

- [x] `script/build_and_run.sh --verify` は保存済みウィンドウ状態に引きずられず、Project Board を表示して起動確認できる。
- [x] generated `Info.plist` は `NSQuitAlwaysKeepsWindows=false` を持ち、macOS Resume が「ウィンドウなし」状態を復元しない。
- [x] `SoloPMAppDelegate` は通常起動時に regular app として activate し、ウィンドウが見えていない場合は `WindowGroup` の New Window action を送る。
- [x] Dock 再クリックなど `applicationShouldHandleReopen` で visible window がない場合も Project Board を復帰する。
- [x] `LaunchExperienceTests` で build script と AppDelegate の起動復帰契約を固定する。
- [x] 完了条件: ビルド成功後にプロセスだけ残り、ユーザーが Project Board を触れない状態で止まらない。

### P10-160: Project delete CRUD is real local data mutation

- [x] `ActionTool` / packaged `action-plan.schema.json` に `project.delete` を追加し、Project delete を承認付き write tool として扱う。
- [x] `SQLiteProjectStore.delete` は Project row だけでなく、関連 Task、CalendarLink、ReminderLink、DeadlineRule、Artifact を同一transactionで削除する。
- [x] `SQLiteProjectStore.delete` は `CoreMigrations.phase2` のように後続tableが存在しないDBでも失敗しない。
- [x] `ProjectTool(project.delete)` は削除件数を output に返し、Review execution からProject削除を実行できる。
- [x] Project Board UI は確認ダイアログつきの `Delete Project` を持ち、ViewModel経由で永続削除できる。
- [x] `LocalStoreTests` / `ProjectTaskKnowledgeToolTests` / `ProjectBoardStoreTests` / `ActionPlanDomainTests` / `ActionPlanSchemaTests` で永続削除、schema、risk、registry、UI ViewModelを固定する。
- [x] 完了条件: Project CRUD の delete がUI専用操作でもmockでもなく、ローカル永続DBに対する一貫したCRUDとして成立する。

### P10-161: Release readiness report writes the next operator actions

- [x] `release_readiness_report.sh` は `SOLOPM_RELEASE_ACTIONS_FILE` 指定時に残blockerのoperator action summaryを書き出す。
- [x] action summary は `Status`、UTC生成時刻、source commit、blocker group数、Automated Proof Gates、Manual VoiceOver、Competitor Hands-On、Release Machine の次アクションを含む。
- [x] action summary は `Source commit` と tracked source tree の clean / dirty / unavailable 状態を併記する。
- [x] action summary は今回の実行で発生した具体blockerを `Current Blocker Groups` のチェックリストとして列挙する。
- [x] action summary は `Operator Priority Queue` を `Current Blocker Groups` より前に出し、手動VoiceOver、競合hands-on、release-machineのどれを先に実施すれば何件のblockerを減らせるか、release-machine内の環境blocker件数、Phase routing対象の手動項目数を示す。
- [x] action summary は `Blocker Buckets` で Automated Proof Gates / Manual VoiceOver / Competitor Hands-On / Release Machine / Phase Checklist / Other の残件数を分類する。
- [x] action summary は `Release Environment Blockers` に `verify_release_environment.sh` の `BLOCKER:` 明細を相対パス化して列挙し、機密っぽい値を転記しない。
- [x] action summary は release environment blocker を Signing Configuration / Notarization / Sparkle / Appcast / Gatekeeper / Release Evidence / Source Hygiene / Local Inspection に分類し、release-machine作業の順序を読み取れるようにする。
- [x] action summary は clean-tree automated preflight evidence が有効な場合、accepted evidence、source commit、generated at、passed gatesを表示し、再実行指示だけを出さない。
- [x] action summary は Local Product Gate Status でcurrent commitのMCP/data/CRUD/local proofがgreenか、残りがmanual/release-machineかを明示する。
- [x] action summary は `Manual VoiceOver Blockers` と `Competitor Hands-On Blockers` に手動証跡の不足項目を分離表示し、手動作業を完了扱いにしない。
- [x] action summary は VoiceOver の `.tmp/voiceover-review/accessibility-voiceover-pending-<commit>.md` preview と `.tmp/voiceover-review/create-evidence-command.sh` を案内し、operatorがtracked evidenceを汚さずrelease候補contextを確認できるようにする。
- [x] action summary は VoiceOver / competitor hands-on の current `Source commit` に対応する pending evidence path も併記する。
- [x] action summary は VoiceOver / competitor hands-on の証跡生成コマンドを必須フラグ込みで表示し、placeholderを実測値に置き換える必要を明記する。
- [x] action summary は competitor hands-on の pending generator と `.tmp/competitor-hands-on/create-evidence-command.sh` を案内し、operatorがplaceholderを置換してからpassed証跡を作れるようにする。
- [x] action summary は VoiceOver / competitor hands-on / release-machine の生成済み証跡コマンドが clean tracked source tree と生成時 source commit にpinされ、source変更後は再生成が必要なことを表示する。
- [x] action summary は direct manual evidence scripts も clean tracked source tree を要求し、dirty tree 回避目的で生成済みコマンドを迂回しないよう表示する。
- [x] action summary は `Phase Checklist Items` に未チェックPhase項目のファイル名・行番号・本文を相対パスで列挙する。
- [x] action summary は未チェックの手動Phase項目を Manual VoiceOver / Competitor Hands-On / Release Machine / Login Item Manual Check / Manual Review に分類し、どの証跡経路で解消するかを示す。
- [x] action summary は Login Item Manual Check が残る場合、`create_release_evidence.sh` の `--login-item-toggle`、manual environment、review note を含む実行例を出し、単独checkboxではなく release artifact に紐づく evidence として扱う。
- [x] action summary は Login Item manual gate が残る場合、Operator Priority Queue に `--login-item-toggle` 付き release evidence command への導線を独立表示する。
- [x] action summary は Release Machine blocker が残る場合、署名、notarization、package、appcast、release evidence、final preflight の順序付きコマンドを出す。
- [x] `script/prepare_release_machine_evidence.sh` は `.tmp/release-machine/release-machine-worksheet.md` と `.tmp/release-machine/create-release-evidence-command.sh` を生成し、signed/notarized/stapled artifact上の手動release確認を証跡JSON作成前に整理できる。
- [x] `script/prepare_release_machine_evidence.sh` pins `.tmp/release-machine/create-release-evidence-command.sh` to a clean tracked source tree and the source commit it was generated for, and the generated command exits before writing evidence if the release candidate tree is dirty or the commit has changed.
- [x] `script/create_release_evidence.sh --validate-only` validates the filled release-machine command without writing `packaging/release-evidence.json`.
- [x] `.tmp/release-machine/create-release-evidence-command.sh` runs `SOLOPM_RELEASE_PREFLIGHT_ONLINE=1 ./script/verify_release_environment.sh` after writing release evidence so release-machine operators see the final gate before rerunning the readiness report.
- [x] action summary の Release Machine runbook は `.tmp/release-machine/create-release-evidence-command.sh` の編集・実行を direct `create_release_evidence.sh --force` fallback より先に表示し、generated validate-only stepを主導線にする。
- [x] Direct manual evidence scripts reject dirty tracked source trees before writing passed VoiceOver, competitor, or release-machine evidence.
- [x] action summary は release evidence ではなく、VoiceOver / competitor hands-on / signing / notarization / Sparkle / Gatekeeper を完了扱いにしないことを明記する。
- [x] action summary の VoiceOver / competitor hands-on の直接実行例は `--validate-only` を `--passed` より先に表示し、manual evidence を即書き込みしない導線にする。
- [x] action summary は generated VoiceOver / competitor / release-machine command が placeholder 未置換のままでは `--validate-only` でも失敗することを表示し、template command を evidence-ready に見せない。
- [x] `script/prepare_release_manual_helpers.sh` は current source commit の VoiceOver pending preview / command、competitor pending evidence、competitor benchmark pending worksheet、competitor worksheet / command、release-machine worksheet / command を一括再生成し、passed evidence を書かない。
- [x] `script/prepare_release_manual_helpers.sh` は tracked source tree がdirtyな場合、pending preview / command生成前に停止し、未コミット差分をcurrent commitのrelease candidateとして扱わない。
- [x] action summary の Manual Review Helper Freshness は stale/missing helper を見つけた場合、個別コマンドの羅列ではなく `./script/prepare_release_manual_helpers.sh` を次アクションとして提示する。
- [x] Manual Review Helper Freshness は command helper の `EXPECTED_SOURCE_COMMIT` 実代入だけを current commit pin として扱い、コメントや説明文に current commit が出るだけでは stale 扱いにする。
- [x] action summary は古い `.tmp/voiceover-review/*-pending-<old-commit>.md` / `.tmp/competitor-hands-on/*-pending-<old-commit>.md` を ignored stale preview として表示し、operatorが別release候補のcontextをtracked evidenceへ転記しないようにする。
- [x] `script/prepare_release_manual_helpers.sh --prune-stale` は current source commit のhelper再生成後、古いpending previewだけを削除し、passed evidenceを書かない。
- [x] `ReleasePipelineTests` と `docs/release/checklist.md` で operator action summary の生成導線を固定する。
- [x] 完了条件: `release_readiness_report.sh` が `NOT READY` のままでも、次に実行すべき手動・自動・release-machine作業が1ファイルに集約される。

### P10-162: Release CI preflight does not leave Swift temporary directories

- [x] `scripts/ci.sh` は `SOLOPM_CI_TMP_ROOT` / `SOLOPM_CI_TMPDIR` を使って SwiftPM の `TMPDIR` を release preflight 専用領域へ隔離する。
- [x] `scripts/ci.sh` は自分で作った `solopm-ci-tmp.*` を `EXIT INT TERM` trap で削除し、`swift test` が作る `TemporaryDirectory.*` を `.tmp` 直下に積み上げない。
- [x] `ReleasePipelineTests` で `TMPDIR` export が `swift test` より前に実行され、CI tmpdir cleanup が定義されていることを固定する。
- [x] 完了条件: automated release preflight を繰り返しても検証用 `.tmp` に不要な Swift temporary directory が蓄積せず、manual evidence / action summary の確認ノイズを増やさない。

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
- Runtime source の scan は `fixture` terminology も blocker とし、production API名では requirement/evaluation case など実運用品質の語彙を使う。

## Verification

- `swift test`
- `xcodebuild -workspace .swiftpm/xcode/package.xcworkspace -scheme SoloPM -destination 'platform=macOS' build`
- `./scripts/verify.sh`
- `./script/build_and_run.sh --verify`
- `swift build --product solopm-cli && .build/debug/solopm-cli --help`
- `SOLOPM_RELEASE_PREFLIGHT_ONLINE=1 ./script/verify_release_environment.sh` (Developer ID / notary / `packaging/release-evidence.json` が揃った release machine で green にする。開発機では blocker 出力を確認する。)
- `./script/release_readiness_report.sh` (全 release gate が揃うまでは `NOT READY` と blocker を返す。)
