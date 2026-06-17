# Phase 6: Developer Mode

目的は、個人開発者 / OSS 作者向けに SoloPM の価値を強めること。Git や GitHub を扱うが、最初は read-only と approval-first を徹底する。

## Scope

- Git read-only scan
- GitHub Issue creation with approval
- codebase-memory-mcp optional integration
- README / release note / changelog generation
- CLI

## Non-goals

- Git push
- branch delete
- PR merge
- GitHub write without approval
- repository 全体の無許可 scan

## Checklist

### P6-001: Developer Mode setting

- [x] Developer Mode を明示的な opt-in にする。
- [x] 有効化時に Git / GitHub / codebase scan の権限説明を表示する。
- [x] workspace はユーザーが選択した directory に限定する。
- [x] テスト: opt-in なしでは developer tools が registry に出ないことを確認する。
- [x] 完了条件: 一般ユーザーに不要な機能が前面に出ない。

実装メモ:
- `DeveloperModeSettings` は `isEnabled` と `workspaceRoot` と capability set を分離し、disabled では permission disclosure も tool registry も空にする。
- `ToolRegistryFactory.developerMode` は opt-in かつ workspace 選択済みの場合だけ developer tools を登録する。

### P6-002: Git read-only scan

- [x] `git.status`、`git.branch`、`git.log_summary`、`git.diff_summary` の read-only tool を作る。
- [x] shell 実行は allowlist command に限定する。
- [x] `git push`、`reset --hard`、`checkout --` など destructive command は実装しない。
- [x] テスト: fake command runner で status parse、non-git directory、command failure を確認する。
- [x] 完了条件: Git 状態を読み取れるが変更はできない。

実装メモ:
- `GitReadOnlyCommandPolicy` は `status --short --branch`、`branch --show-current`、bounded `log --oneline -n`、`diff --stat` だけを許可する。
- `GitReadOnlyClient` は workspace directory の存在確認、allowlist 検査、非 0 exit の error 化を行う。
- `GitReadOnlyTool` は `.read` permission のみで、write / branch mutation / remote mutation は登録しない。

### P6-003: GitHub Issue creation

- [x] `github.issue.create_draft` と `github.issue.create_with_approval` を分ける。
- [x] token は Keychain に保存する。
- [x] repo、title、body、labels、assignees を Review UI で確認する。
- [x] テスト: approval なし create が拒否されることを確認する。
- [x] 完了条件: GitHub への write は必ず明示承認を通る。

実装メモ:
- `GitHubIssueCreationService` は draft 作成では token を読まず、`createWithApproval` の承認後に `SecretStore.githubToken` から読み出す。
- 現時点は client protocol 境界まで。実 GitHub API write adapter は UI approval flow と合わせて後続実装する。

### P6-004: README / release note generation

- [x] local Git 状態、commits、tasks をもとに draft text を生成する。
- [x] 生成物は file write ではなく draft preview から開始する。
- [x] 既存 README 上書きは禁止し、提案 diff または新規 draft file にする。
- [x] テスト: generated draft に secret が含まれないことを確認する。
- [x] 完了条件: OSS 作者の日常作業を安全に補助できる。

実装メモ:
- `DeveloperDraftGenerator` は `README.draft.md` / `RELEASE_NOTES.draft.md` の preview-only policy を返すだけで、ファイル書き込みはしない。
- GitHub/OpenAI/token/password 系の secret redaction を draft 生成時に通す。

### P6-005: CLI foundation

- [x] `solopm-cli` CLI の command scope を決める。
- [x] 最初は `status`、`tasks due`、`plan validate`、`frames search` など read / local 操作に限定する。
- [x] app DB との接続方法を決める。
- [x] テスト: CLI argument parse と exit code を確認する。
- [x] 完了条件: GUI なしでも主要な local 状態を確認できる。

実装メモ:
- SwiftPM product `solopm-cli` / target `SoloPMCLI` を追加した。
- `status`、`tasks due`、`frames search` は app default SQLite DB を read-only で開き、Project / Task / Knowledge Frame の実データを表示する。
- app DB は GUI と共有する `SoloPMAppDatabaseLocation.defaultDatabaseURL(createDirectory: false)` に固定し、DB が無い初回状態ではファイルを作らず `database: missing` を返す。
- `plan validate <path>` は `ActionPlanValidator` を使い、write 系 command は parser で受け付けない。

### P6-006: codebase-memory optional integration

- [x] codebase-memory-mcp は optional connector として扱う。
- [x] 接続前に送信される文脈を preview する。
- [x] MVP の Knowledge Frame と責務を混ぜない。
- [x] テスト: connector disabled 時に planning が失敗しないことを確認する。
- [x] 完了条件: 外部記憶連携がなくても SoloPM が成立する。

実装メモ:
- `CodebaseMemoryPlanningIntegration` は disabled / preview-only / enabled-with-approval を分ける。
- disabled または未承認では planning request をそのまま返し、connector を呼ばない。
- 外部 connector の検索結果は明示的に `codebase-memory:` prefix の candidate として扱う。

## Exit Gate

- [x] Developer Mode は opt-in。
- [x] Git 操作は read-only。
- [x] GitHub write は approval 必須。
- [x] CLI は local / read 系から開始している。
- [x] OSS 作者向け workflow の sample がある。

OSS 作者向け sample workflow:
1. Developer Mode を有効化し、対象 repository directory を workspace として選択する。
2. `git.status` / `git.diff_summary` / `git.log_summary` で local state を読み取る。
3. `DeveloperDraftGenerator` で README / release note draft を preview し、secret redaction report を確認する。
4. 必要な issue は `github.issue.create_draft` で Review UI に出し、明示承認後に `github.issue.create_with_approval` を通す。
5. GUI が不要な確認は `solopm-cli status` / `solopm-cli plan validate <path>` から read-only に実行する。
