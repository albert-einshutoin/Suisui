# SoloPM Development Tasks

このディレクトリは [docs/tech_stack.md](../docs/tech_stack.md) を実装計画に落としたものです。各 Phase は、そのまま GitHub Issue / Pull Request に分解できる粒度を目標にします。

Phase ファイルは Epic / Issue seed として扱います。実装に入る前に、各 `Pn-xxx` を下の `推奨 Issue Format` へ展開し、対象ファイル、実装手順、テスト、非対象を明記してください。Phase ファイルだけで判断に迷う場合は、実装で補完せず、Issue か Phase 文書を先に更新します。

## Phase Map

| Phase | 目的 | 成果物 |
|---|---|---|
| [Phase 0: Skeleton](./Phase0-Skeleton.md) | macOS SwiftUI アプリの土台 | MenuBarExtra、Settings、SQLite、Keychain、Shortcut |
| [Phase 1: Voice to Action Plan](./Phase1-VoiceToActionPlan.md) | 入力を Action Plan に変換 | STT 抽象化、LLM adapter、JSON schema、validation |
| [Phase 2: Built-in Tools](./Phase2-BuiltInTools.md) | 内蔵 Tool Registry を作る | Project / Task / Calendar / Reminder / Notification / File / Knowledge |
| [Phase 3: Review & Execute](./Phase3-ReviewAndExecute.md) | 実行前確認と承認実行 | Review UI、編集、承認、実行ログ、rollback metadata |
| [Phase 4: Deadline Watcher](./Phase4-DeadlineWatcher.md) | 締切監視を成立させる | overdue scan、daily check、通知予約、menu bar summary |
| [Phase 5: Packaging](./Phase5-Packaging.md) | alpha 配布可能にする | signing、notarization、Sparkle、release checklist |
| [Phase 6: Developer Mode](./Phase6-DeveloperMode.md) | 開発者向け連携 | Git read-only scan、GitHub Issue、CLI、README 生成 |
| [Phase 7: External MCP](./Phase7-ExternalMCP.md) | 外部 MCP 対応 | stdio client、permission UI、execution log、custom registration |
| [Phase 8: SaaS Connectors](./Phase8-SaaSConnectors.md) | 外部 SaaS 連携 | Google Calendar、Gmail Draft、Slack、Drive、Notion |
| [Phase 9: Knowledge Advanced](./Phase9-KnowledgeAdvanced.md) | Knowledge 高度化 | sqlite-vec、local embeddings、project memory、WeKnora connector |
| [Phase 10: Release Readiness Runtime](./Phase10-ReleaseReadinessRuntime.md) | モックを外し実働 MVP にする | 永続 DB、Keychain、CRUD、実行導線、投資家視点セルフレビュー |
| [Phase 11: Provider Sync UX Productization](./Phase11-ProviderSyncUXProductization.md) | Provider/同期/UXを製品化する | MCP仕様準拠、主要LLM provider、有料同期ゲート、競合/UX監査 |
| [Phase 12: Product Cockpit UX Parity](./Phase12-ProductCockpitUXParity.md) | ui-samplesとの差分を日次運用cockpitへ落とす | Inbox音声triage、Schedule、Projects俯瞰、Done分析、Settings連携 |
| [Phase 13: Multiplatform Automation](./Phase13-MultiplatformAutomation.md) | iOS / Web / macOS で使える会話ベースのタスク管理&自動化へ拡張する | Cloud Sync、Cloud Relay、Hosted MCP、docs-scoped automation、Harness |
| [Phase 14: Quality Regression Hardening](./Phase14-QualityRegressionHardening.md) | レイアウト崩れ、クリックパス、アクセシビリティ、永続化、セキュリティのテスト漏れを体系的に潰す | Layout stability smoke、visual regression、runtime AX、quality status report |
| [Phase 15: Product-Out Release Candidate](./Phase15-ProductOutReleaseCandidate.md) | 実装済み機能をrelease candidateとして閉じ、手動/実機/外部依存の残blockerを製品判断に落とす | Current manual evidence、Gemini live smoke、Keychain prompt hardening、signed/notarized artifact、release readiness green |
| [Phase 16: Public Alpha Launch Operations](./Phase16-PublicAlphaLaunchOperations.md) | 初回ユーザーが迷わず使い始め、問題報告できるPublic Alpha導線を作る | first-run onboarding、permission education、public alpha checklist、feedback intake、support runbook |
| [Phase 17: Post-Launch Learning Loop](./Phase17-PostLaunchLearningLoop.md) | Product-out後の利用実態、障害、要望を次の開発へ戻す運用を固める | crash/error triage、usage feedback、roadmap、OSS contribution、release cadence |

Issue起票時は [Product-Out Issue Seeds](./ProductOut-IssueSeeds.md) を入口にし、Phase15-17の `P15-xxx` / `P16-xxx` / `P17-xxx` を1 Issue単位へ展開する。

## 開発原則

### Gitflow

- `main` は常にリリース可能な状態に保つ。
- `develop` は次リリースの統合ブランチにする。
- 作業ブランチは `feature/phaseN-short-name`、修正は `fix/phaseN-short-name`、ドキュメントは `docs/phaseN-short-name` とする。
- 原則として 1 タスク 1 PR。複数タスクをまとめる場合は、同じ責務境界かつレビューが容易な範囲に限る。
- Phase 完了時は `release/vX.Y.Z-alpha.N` を切り、動作確認後に `main` へ merge して tag を打つ。
- `main` への直接 push は禁止。PR にはテスト結果、手動確認結果、残リスクを書く。

### TDD

- 先に失敗するテストを書く。UI だけの変更でも、ViewModel / reducer / validator / adapter fake のテストを先に置く。
- macOS API 直叩きのコードは薄い adapter に閉じ込め、Core は pure Swift と protocol でテストする。
- EventKit、UserNotifications、Keychain、FSEvents、LLM、STT は unit test で fake を使う。実 OS 連携は integration smoke test に分離する。
- Action Plan、Tool Registry、Permission、Audit Log は regression が致命的なので、正常系、失敗系、危険操作拒否のテストを必須にする。
- テスト名は `given_when_then` で意図が読めるようにする。

例:

```text
givenWriteActionWithoutApproval_whenExecute_thenRejectsAndLogsAuditEvent
givenAmbiguousDeadline_whenValidateActionPlan_thenRequiresUserConfirmation
```

### タスク粒度

- 1 タスクは 0.5 日から 1 日で終わる大きさにする。
- 1 タスクは 1 つの観測可能な成果物を持つ。例: `KeychainStore protocol と fake を追加する`。
- 1 タスクに UI、DB、外部 API、配布を混ぜない。混ざる場合は分割する。
- Phase ファイルの `Pn-xxx` は実装単位の候補であり、PR 着手前に Issue Format へ展開する。
- 展開後の Issue が 1 日を超える場合は、domain model、adapter、UI、test fixture などでさらに分割する。
- 各タスクには必ず以下を書く。
  - 背景: なぜ必要か
  - 対象: 触るモジュール / ファイル
  - 実装手順: 迷わず進めるための順序
  - テスト: 先に書くテスト
  - 完了条件: レビューで確認する観点
  - 非対象: 今回やらないこと

### ジュニアエンジニア向けの書き方

タスクは「何を作るか」だけでなく「どう安全に作るか」まで書く。

- domain model、protocol、adapter、UI のどこに置くかを明記する。
- fake / mock の作り方を明記する。
- エラー時の期待挙動を明記する。
- セキュリティ境界を明記する。
- 最低限の手動確認手順を書く。
- 実装判断に迷う箇所は ADR または TODO ではなく、タスク内の確認事項として残す。

### ADR

技術判断は `docs/adr/` に残します。

- ファイル名は `NNNN-short-title.md` とする。例: `0001-database-primary-log-store.md`
- 1 ADR には 1 つの判断だけを書く。
- `Status` は `Proposed`、`Accepted`、`Superseded` のいずれかにする。
- 採用案だけでなく、不採用案と理由も書く。
- Phase / Issue / PR から ADR を参照する。
- 判断が変わった場合は既存 ADR を破壊的に書き換えず、新しい ADR で supersede する。

## Architecture Rules

- SwiftUI View は薄く保つ。状態管理、validation、実行判断は ViewModel / Core に置く。
- `Core` は macOS framework に直接依存しない。OS 連携は adapter 経由にする。
- LLM 出力は直接実行しない。必ず `ActionPlan` と JSON Schema validation を通す。
- Tool 実行は `Read`、`Draft`、`Write with approval`、`Dangerous` に分類する。
- MVP で `Dangerous` は実装しない。送信、削除、上書き、Git push、自動投稿は禁止。
- API Key と token は Keychain に保存する。ログ、SQLite、UserDefaults に秘密情報を書かない。
- ユーザーが選択したディレクトリだけを Security-scoped Bookmark で扱う。
- 本格 RAG、Agentic Search、WeKnora 内包、外部 MCP は MVP のコアに入れない。

## Definition of Done

各 PR は以下を満たす。

- 対応タスクのチェックボックスが完了している。
- 失敗するテストから始め、最終的に unit test / integration smoke が通る。
- 追加した public API / domain model に最低限の説明がある。
- 危険操作の拒否、承認必須操作、audit log の観点を確認している。
- UI 変更はキーボード操作、VoiceOver label、空状態、エラー状態を確認している。
- 既存仕様とずれた場合は docs を更新している。
- セルフレビューで「責務が混ざっていないか」「MVP 外の実装を入れていないか」を確認している。

## PR Template

```markdown
## Summary
- 

## Linked Task
- tasks/PhaseN-*.md: Pn-xxx

## TDD
- [ ] 先に失敗するテストを追加した
- [ ] 正常系、失敗系、境界値を確認した
- [ ] macOS API は fake / adapter 経由でテストした

## Manual Verification
- 

## Safety / Privacy
- [ ] 秘密情報をログや DB に保存していない
- [ ] Write 操作は承認必須になっている
- [ ] Dangerous 操作を追加していない

## Self Review
- [ ] 責務境界が明確
- [ ] MVP 外の実装を混ぜていない
- [ ] ドキュメント更新が必要な箇所を確認した
```

## 推奨 Issue Format

```markdown
## Context

## Scope

## Non-goals

## Implementation Steps
- [ ] 

## Tests First
- [ ] 

## Acceptance Criteria
- [ ] 

## Review Focus
- 
```

## Phase Exit Gate

Phase を完了扱いにするには、その Phase の `Exit Gate` をすべて満たす。未完了項目がある場合は、次 Phase に進める理由と残リスクを PR / issue に明記する。
