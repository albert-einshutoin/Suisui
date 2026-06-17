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

- [ ] Developer Mode を明示的な opt-in にする。
- [ ] 有効化時に Git / GitHub / codebase scan の権限説明を表示する。
- [ ] workspace はユーザーが選択した directory に限定する。
- [ ] テスト: opt-in なしでは developer tools が registry に出ないことを確認する。
- [ ] 完了条件: 一般ユーザーに不要な機能が前面に出ない。

### P6-002: Git read-only scan

- [ ] `git.status`、`git.branch`、`git.log_summary`、`git.diff_summary` の read-only tool を作る。
- [ ] shell 実行は allowlist command に限定する。
- [ ] `git push`、`reset --hard`、`checkout --` など destructive command は実装しない。
- [ ] テスト: fake command runner で status parse、non-git directory、command failure を確認する。
- [ ] 完了条件: Git 状態を読み取れるが変更はできない。

### P6-003: GitHub Issue creation

- [ ] `github.issue.create_draft` と `github.issue.create_with_approval` を分ける。
- [ ] token は Keychain に保存する。
- [ ] repo、title、body、labels、assignees を Review UI で確認する。
- [ ] テスト: approval なし create が拒否されることを確認する。
- [ ] 完了条件: GitHub への write は必ず明示承認を通る。

### P6-004: README / release note generation

- [ ] local Git 状態、commits、tasks をもとに draft text を生成する。
- [ ] 生成物は file write ではなく draft preview から開始する。
- [ ] 既存 README 上書きは禁止し、提案 diff または新規 draft file にする。
- [ ] テスト: generated draft に secret が含まれないことを確認する。
- [ ] 完了条件: OSS 作者の日常作業を安全に補助できる。

### P6-005: CLI foundation

- [ ] `solopm` CLI の command scope を決める。
- [ ] 最初は `status`、`tasks due`、`plan validate`、`frames search` など read / local 操作に限定する。
- [ ] app DB との接続方法を決める。
- [ ] テスト: CLI argument parse と exit code を確認する。
- [ ] 完了条件: GUI なしでも主要な local 状態を確認できる。

### P6-006: codebase-memory optional integration

- [ ] codebase-memory-mcp は optional connector として扱う。
- [ ] 接続前に送信される文脈を preview する。
- [ ] MVP の Knowledge Frame と責務を混ぜない。
- [ ] テスト: connector disabled 時に planning が失敗しないことを確認する。
- [ ] 完了条件: 外部記憶連携がなくても SoloPM が成立する。

## Exit Gate

- [ ] Developer Mode は opt-in。
- [ ] Git 操作は read-only。
- [ ] GitHub write は approval 必須。
- [ ] CLI は local / read 系から開始している。
- [ ] OSS 作者向け workflow の sample がある。
