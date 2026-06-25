# Phase 15: Product-Out Release Candidate

目的は、Phase14で固めた品質基盤の上に、SoloPMを「実装はあるがまだ出せない」状態から「release candidateとして外部ユーザーに渡せる」状態へ閉じること。ここでは新機能を大きく増やさず、既存の主要価値である VoiceOver-aware task listing、review-before-execution、document-scoped automation、LLM provider planning、local-first storage、release packaging を、実機証跡と失敗時の判断基準まで含めて製品判定できる形にする。

このPhaseのゴールは、開発者の手元でだけ動くことではない。release-candidate source commit、manual evidence、Gemini free-tier live smoke、Keychain access prompt、signed, notarized, stapled artifact、Sparkle metadata、public alpha scopeがすべて同じリリース候補を指し、`release_readiness_report.sh` が green になる状態を作る。

## Product Bar

- VoiceOverの主導線として、Project Boardでタスク列挙 -> 作成 -> 内容編集 -> status move -> automation review -> approved execution -> delete confirmation -> project completion/delete cascade が現在のrelease-candidate source commitで確認されている。
- Gemini free-tier live smoke は、API keyが設定済みで無料枠内に収まる時だけ実行し、quota、503、network、未設定の場合は明示的なskip reasonを残す。skipをfake successにしない。
- Keychain access prompt は、SoloPM起動後の通常操作で毎回出ない。必要な初回承認、provider key保存、Google OAuthなどの明示的な認証操作と、不要な再認証プロンプトを区別できる。
- manual VoiceOver、competitor hands-on、release machine evidence は、現在のrelease-candidate source commitに紐づき、古い証跡やpending templateでrelease判定しない。
- release artifact は signed, notarized, stapled の状態で、clean install、Gatekeeper、Launch at Login、Sparkle appcast metadataまで検証されている。
- README、public alpha notes、privacy/security、release checklist、known limitationsが、実装済み機能と非対象を過不足なく説明している。

## Non-Goals

- Public Alpha後の利用分析基盤やサポート運用全体はPhase16/17へ回す。
- 新しいSaaS本番同期やチーム機能をrelease candidateの必須機能にしない。
- GeminiやGoogle APIの有料枠を使い切るような負荷テストはしない。
- 手動VoiceOverやGatekeeper確認を自動化済みと偽らない。
- Keychainに保存するsecretをUserDefaults、SQLite、ログ、release evidenceへ複製しない。

## Priority Model

| Priority | 判断基準 | 対象 |
| --- | --- | --- |
| High | release candidateを出すと即ユーザー影響がある、または証跡なしでship判定できないもの | P15-001, P15-002, P15-003, P15-004, P15-005 |
| Middle | release notes、known limitations、support handoffなど製品判断を明確にするもの | P15-006, P15-007 |
| Low | Phase16/17へ渡す改善候補の整理 | P15-008 |

着手順は High -> Middle -> Low とする。Highがgreenになるまで、大きなUI redesignや新規connector追加は行わない。

## P15-001: Release candidate source lock and product-out gap ledger

Priority: High

### Context

現在の証跡は複数のscript、manual worksheet、quality status、release readinessに分かれている。release candidateを判断するには、どのcommitを製品候補として扱うか、何がgreenで何がmanual blockerかを1か所で追える必要がある。

### Scope

- 対象: `script/release_readiness_report.sh`, `script/quality_status_report.sh`, `docs/release/checklist.md`, `docs/release/manual-unblockers.md`
- release-candidate source commit、automated preflight evidence、manual evidence、release-machine evidence、known limitationsを対応付ける。
- Product-out gap ledgerを作り、blocker / accepted risk / deferred improvementを分ける。

### Tests First

- [ ] `ReleasePipelineTests` に、release readiness reportがrelease-candidate source commitとHEAD-only docs/test commitを区別するテストを追加する。
- [ ] gap ledgerに `blocker`, `accepted risk`, `deferred` の分類がない場合に失敗するsource testを追加する。
- [ ] stale manual evidence、pending template、異なるsource commitの証跡がrelease ready扱いにならないことをfixtureで固定する。

### Implementation Steps

- [ ] `docs/release/product-out-gap-ledger.md` を作成する。
- [ ] release readiness reportに、current HEAD、release-candidate source commit、automated evidence file、manual evidence filesを表示する。
- [ ] gapごとに owner、再現コマンド、判断日、次アクションを記録する。
- [ ] accepted riskは、ユーザー向けknown limitationsまたはsupport runbookへリンクする。
- [ ] deferred improvementはPhase16/17の具体タスクへリンクする。

### Acceptance Criteria

- [ ] どのcommitをPublic Alpha候補として出すかが明確。
- [ ] 未完了項目がblockerなのか、明示的なaccepted riskなのか、延期改善なのか分かる。
- [ ] stale evidenceやpending evidenceでrelease candidateが通らない。

### Non-goals

- release manager用のWeb dashboardを作らない。
- 判断なしにすべての未完了項目を許容riskへ落とさない。

## P15-002: Current manual VoiceOver release evidence closure

Priority: High

### Context

VoiceOverからのタスク列挙はSoloPMの主機能であり、擬似VoiceOverやAX smokeだけでは最終証跡にならない。実際のVoiceOverで、タスク一覧が最初の操作対象として理解でき、CRUD/実行/削除まで迷わず辿れる必要がある。

### Scope

- 対象: `docs/release/evidence/accessibility-voiceover.md`, `docs/quality/accessibility-focus-paths.md`, `script/prepare_voiceover_review_candidate.sh`, `script/create_voiceover_evidence.sh`
- VoiceOver worksheetに task listing を明示し、project-task-list -> selected task -> inspector -> execution receipt まで確認する。
- runtime AX smokeの `taskList` 契約とmanual worksheetの項目を対応付ける。

### Tests First

- [ ] `QualitySourceContractTests` に、VoiceOver worksheetが `task listing`, `project-task-list`, `taskList` を含むことを確認するテストを追加する。
- [ ] `ReleasePipelineTests` に、VoiceOver evidenceがrelease-candidate source commit不一致なら失敗するfixture testを追加する。
- [ ] manual noteが `OK`, `Verified`, `TBD` のようなplaceholderだけの場合に失敗するテストを追加する。

### Implementation Steps

- [ ] `script/prepare_voiceover_review_candidate.sh` のworksheetに、タスク列挙を最初の観測項目として追加する。
- [ ] VoiceOver evidence schemaに、task listing、create/edit/delete、approved execution receiptの具体メモを要求する。
- [ ] 実アプリでVoiceOverを有効化し、Project Boardのタスク一覧、カード、inline composer、status controls、task inspector、delete confirmation、execution receiptを確認する。
- [ ] validate-only -> write の順で evidence を更新する。
- [ ] 手動で見つかった問題は `docs/quality/manual-to-automated-regression.md` に戻し、source/runtime testを追加する。

### Acceptance Criteria

- [ ] `docs/release/evidence/accessibility-voiceover.md` がcurrent release-candidate source commitの `Status: passed` になっている。
- [ ] task listingがVoiceOverで認識できることが具体メモとして残っている。
- [ ] manual VoiceOverで見つかった問題が自動回帰へ戻されている。

### Non-goals

- VoiceOver操作そのものを完全自動化しない。
- 視覚的に見えるだけでVoiceOver通過扱いにしない。

## P15-003: Keychain access prompt hardening for provider keys and OAuth

Priority: High

### Context

SoloPM起動後の通常操作でmacOS側が毎回Keychain認証を求めると、製品として使い続けられない。これはGemini API key、OpenAI/Claude/Groq/OpenRouter key、Google OAuth token、MCP secretsなどのsecret取得経路で起きうる。初回保存や明示的な再認証は必要だが、タスク操作や画面遷移のたびにプロンプトが出る状態はblockerにする。

### Scope

- 対象: `Sources/SoloPMApp`, `Sources/SoloPMCore`, Keychain adapter、AI provider settings、Google Calendar sync readiness、MCP credential storage
- Keychain read/writeの呼び出し頻度、access control、service/account命名、readiness cache、エラー表示を整理する。
- Google API keyではなくOAuth token/refresh tokenに対する認証導線かどうかをUI文言で区別する。

### Tests First

- [ ] Keychain fakeにread countを持たせ、通常のProject Board操作でprovider secret readが連続発火しないunit testを追加する。
- [ ] provider readiness表示がKeychainエラーをsecret値なしで表示するtestを追加する。
- [ ] Google CalendarはAPI keyではなくOAuth authorizationが必要であることをsource/doc testで固定する。
- [ ] Keychain prompt回避のためにsecretをUserDefaultsやSQLiteへcacheしないことをsecurity testで固定する。

### Implementation Steps

- [ ] Keychain adapterのservice/account命名を棚卸しし、providerごとに安定したitem identityを使う。
- [ ] 起動時や画面描画ごとのsecret readを避け、明示操作時またはprovider call直前に限定する。
- [ ] readiness cacheは「設定済みかどうか」「最後の検証結果」だけを保持し、secret値を保持しない。
- [ ] Keychain access denied、item missing、interaction not allowedを分けてUIに出す。
- [ ] Google連携の文言を「Google API key」ではなく「Google OAuth authorization」として説明する。
- [ ] 実機でSoloPM起動 -> Project Board操作 -> task list -> task edit -> automation reviewを行い、不要なKeychain promptが出ないことをmanual noteに残す。

### Acceptance Criteria

- [ ] 通常操作で毎回Keychain access promptが出ない。
- [ ] 初回保存、明示的なkey更新、OAuth再認証など必要な操作では安全に認証できる。
- [ ] secretはKeychain以外に複製されない。
- [ ] Google Calendarの認証境界がAPI keyとOAuthで混同されない。

### Non-goals

- macOS KeychainのシステムUIを無理にバイパスしない。
- OAuth本番connectorをこのタスクだけで完成させない。

## P15-004: Gemini free-tier live smoke and provider skip contract

Priority: High

### Context

ユーザーはGemini API keyを無料枠に制限しており、テストでは可能な範囲で使ってよい。ただし無料枠を浪費したり、外部障害をfalse failureにしたり、未設定をfake successにするのは避ける必要がある。

### Scope

- 対象: Gemini provider adapter、runtime VoiceOver/task-list smoke、provider smoke scripts、release evidence
- Gemini free-tier live smokeは、タスク列挙を主操作として短いpromptで実行する。
- provider未設定、quota exhausted、503 high demand、network offline、explicit skipを区別する。

### Tests First

- [ ] Gemini live smoke scriptが `SOLOPM_GEMINI_LIVE_SMOKE=1` のような明示フラグなしに外部callしないことをsource testで固定する。
- [ ] quota/network/503のskip reasonをrelease readinessがfake passではなくnon-blocking skipとして扱うfixture testを追加する。
- [ ] provider responseがtask listing action以外へ勝手にwrite actionを出した場合にreview-onlyで止まるtestを追加する。

### Implementation Steps

- [ ] Gemini API keyの取得はKeychainまたは明示env経由に限定し、ログへ出さない。
- [ ] live smoke promptは「現在のSoloPMタスクを列挙して、実行せず要約する」程度に抑える。
- [ ] timeout、retry回数、quota保護、token上限を固定する。
- [ ] 503やquota系はskip reasonをartifactに残し、その他のvalidation errorはfailにする。
- [ ] release readiness reportに、live smoke pass / skipped with reason / failedを分けて表示する。

### Acceptance Criteria

- [ ] Gemini keyが設定済みで無料枠内なら、実LLMを使ったタスク列挙smokeが実行できる。
- [ ] 未設定や一時的なprovider高負荷は理由付きskipになり、fake successにならない。
- [ ] LLM出力はreview-before-execution境界を越えて自動writeしない。

### Non-goals

- Gemini以外の全providerで同じlive smokeを同時実装しない。
- 有料負荷テストや大量token benchmarkをしない。

## P15-005: Release machine packaging, signing, notarization, and Sparkle proof

Priority: High

### Context

製品を外へ出すには、ローカルで起動するだけでは足りない。ユーザーがDMGを開き、Applicationsへ移動し、Gatekeeperに拒否されず、Sparkle更新情報が壊れていないことを証明する必要がある。

### Scope

- 対象: `script/check_release_machine_local_doctor.sh`, `script/sign_app.sh`, `script/notarize_app.sh`, `script/package_release.sh`, `script/generate_appcast.sh`, `script/verify_release_environment.sh`, `packaging/release-evidence.json`
- Developer ID署名、notarization、stapling、DMG、checksum、Sparkle appcast、clean installをrelease evidenceへまとめる。

### Tests First

- [ ] release evidenceがsigned/notarized/stapled artifactなしにpassedにならないfixture testを追加する。
- [ ] Sparkle feed URL/public key/download URL prefixがplaceholderなら失敗するtestを追加する。
- [ ] packaging evidenceのsource commit/build/version mismatchを検出するtestを追加する。

### Implementation Steps

- [ ] release machineでdoctorを実行し、missing credentialをsecretなしで確認する。
- [ ] release buildを作り、Developer ID署名とhardened runtimeを確認する。
- [ ] notarize -> staple -> validateを実行する。
- [ ] DMGとzipを作成し、checksumとpackage evidenceを生成する。
- [ ] Sparkle appcastを生成・検証する。
- [ ] clean userまたはclean environmentでGatekeeper、Launch at Login、first launchを確認する。
- [ ] `packaging/release-evidence.json` をvalidate-only後に生成する。

### Acceptance Criteria

- [ ] signed, notarized, stapled appがrelease evidenceに記録されている。
- [ ] DMG install、Gatekeeper、Sparkle appcast、checksumがcurrent candidateと一致している。
- [ ] release readinessがrelease machine blockersを残さずgreenになる。

### Non-goals

- Apple Developer credentialをrepoに入れない。
- Sparkle private keyをCIやログに出さない。

## P15-006: Product-out documentation truth sync

Priority: Middle

### Context

プロダクトアウト時に、READMEやPublic Alpha Notesが古いPhase 0-4前提のままだと、ユーザー期待と実装がずれる。実装済みの強み、制限、manual gate、privacy boundary、feedback方法を現在の製品状態へ揃える。

### Scope

- 対象: `README.md`, `docs/release/public-alpha.md`, `docs/product/role-and-strengths.md`, `docs/release/privacy-security.md`, `docs/release/checklist.md`
- 「できること」「明示承認が必要なこと」「まだできないこと」「有料/外部連携境界」を整理する。

### Tests First

- [ ] READMEとPublic Alpha Notesがtask listing、review-before-execution、document-scoped automation、VoiceOver-aware workflowを説明するsource testを追加する。
- [ ] Known Limitationsにmanual-only evidence、external SaaS本番同期、team workspace、hosted automationの制限が残っていることを確認するtestを追加する。
- [ ] docsにsecret-like valuesが入らないsecurity testを追加する。

### Implementation Steps

- [ ] READMEのMVP Scopeをcurrent product scopeへ更新する。
- [ ] Public Alpha NotesをPhase0-4 historical scopeとcurrent product-out scopeに分ける。
- [ ] Role and Strengthsに、VoiceOver task listing、local-first review、document deliverable harness、provider skip contractを反映する。
- [ ] Privacy/SecurityにKeychain、OAuth、LLM送信文脈、Gemini無料枠smokeの扱いを追記する。
- [ ] Release checklistに、manual evidenceとrelease machine evidenceの最終順序を追加する。

### Acceptance Criteria

- [ ] 初見ユーザーがSoloPMの価値、制限、導入方法をREADMEから理解できる。
- [ ] release operatorがどの証跡を更新すべきか迷わない。
- [ ] 実装されていないSaaS/Team/hosted automationを過剰に売らない。

### Non-goals

- マーケティングサイト全体を作らない。
- 未実装機能をロードマップ以上に約束しない。

## P15-007: Release notes, known limitations, and rollback plan

Priority: Middle

### Context

Public Alphaでは、何ができるかだけでなく、既知の制限、回避策、rollback、support intakeを明確にする必要がある。alphaユーザーに未完成部分を隠すと、信頼を失う。

### Scope

- 対象: `CHANGELOG.md` または release notes doc、`docs/release/checklist.md`, `docs/release/public-alpha.md`
- 主要機能、breaking behavior、known limitations、rollback、feedback routeをまとめる。

### Tests First

- [ ] release notesにversion/build/source commit/known limitations/rollbackがない場合に失敗するtestを追加する。
- [ ] known limitationsがrelease readiness blockerと矛盾しないことをsource testで確認する。

### Implementation Steps

- [ ] release notes templateを作る。
- [ ] current alphaに含めるworkflowを3-5件へ絞る。
- [ ] known limitationsを、blockerではないaccepted riskに限定する。
- [ ] rollback手順とprevious buildへの戻し方を書く。
- [ ] feedback issue templateへリンクする。

### Acceptance Criteria

- [ ] release notesだけでalphaの期待値を合わせられる。
- [ ] rollback手順が存在する。
- [ ] known limitationsが実装状態と一致している。

### Non-goals

- すべての内部タスク履歴をrelease notesへ載せない。

## P15-008: Phase16/17 handoff backlog

Priority: Low

### Context

release candidate closure中に見つかった改善をその場で全部直そうとすると、製品アウトが止まる。Public Alphaに必要な導線と、post-launchで学習すべき項目へ分けて渡す。

### Scope

- 対象: `tasks/Phase16-PublicAlphaLaunchOperations.md`, `tasks/Phase17-PostLaunchLearningLoop.md`, gap ledger
- blockerではない改善をPhase16/17タスクへ紐づける。

### Tests First

- [ ] Product-out gap ledgerのdeferred itemがPhase16またはPhase17へリンクしていることをsource testで固定する。

### Implementation Steps

- [ ] Phase15中に出た改善案をPhase16/17の該当P番号へ割り当てる。
- [ ] 各改善に、なぜrelease blockerではないかを短く記録する。
- [ ] Public Alpha前にやるものと、Alpha後に学習して決めるものを分ける。

### Acceptance Criteria

- [ ] Product-out判断に不要な改善でPhase15が膨らまない。
- [ ] Deferred itemの次の置き場所が明確。

### Non-goals

- backlog groomingだけでrelease blockerを解消した扱いにしない。

## Verification

- [ ] `swift test --filter QualitySourceContractTests`
- [ ] `swift test --filter ReleasePipelineTests`
- [ ] `script/check_pseudo_voiceover_paths.sh --swift-test`
- [ ] `script/check_accessibility_preflight.sh --runtime`
- [ ] `script/check_runtime_accessible_crud_smoke.sh`
- [ ] `script/check_security_regressions.sh`
- [ ] `script/check_automated_release_preflight.sh`
- [ ] `SOLOPM_AUTOMATED_PREFLIGHT_EVIDENCE_FILE=.tmp/automated-release-preflight-$(git rev-parse --short HEAD).md ./script/release_readiness_report.sh`
- [ ] `swift test`

## Exit Gate

- [ ] release-candidate source commitが明確で、automated/manual/release-machine evidenceが同じ候補を指している。
- [ ] manual VoiceOver evidenceがcurrent release candidateでpassedになり、task listingを具体的に確認している。
- [ ] Gemini free-tier live smokeがpass、または理由付きskipとして記録されている。
- [ ] Keychain access promptが通常操作ごとに出ないことを実機で確認している。
- [ ] signed, notarized, stapled artifactとSparkle appcastが検証済み。
- [ ] README/Public Alpha/Privacy/Release Checklist/Release Notesが現在の製品状態と一致している。
- [ ] release readiness reportがgreen。
- [ ] `swift test` がgreen。
