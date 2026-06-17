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

- [ ] MCP spec 2025-11-25 を基準に client interface を設計する。
- [ ] stdio transport を最初の transport にする。
- [ ] Streamable HTTP は後続に残す。
- [ ] テスト: fake MCP server で initialize、tools/list、tools/call を確認する。
- [ ] 完了条件: 内蔵 Tool と外部 MCP Tool を registry 上で区別できる。

### P7-002: MCP server registration

- [ ] command、args、env、working directory、display name を登録できる UI を作る。
- [ ] env に secret を直接書かせず、Keychain reference を使う設計にする。
- [ ] registration は disabled default にする。
- [ ] テスト: invalid command、missing binary、disabled server を確認する。
- [ ] 完了条件: ユーザーが意図した server だけ起動できる。

### P7-003: Tool permission mapping

- [ ] 外部 MCP tool を `Read`、`Draft`、`Write with approval`、`Dangerous` に分類する。
- [ ] 分類不能な tool は default で disabled にする。
- [ ] tool description と schema を UI で確認できるようにする。
- [ ] テスト: unknown risk tool が実行不可になることを確認する。
- [ ] 完了条件: 外部 tool でも SoloPM の safety model が壊れない。

### P7-004: MCP execution preview

- [ ] 外部 MCP call は実行前に server、tool、args、risk を表示する。
- [ ] args の secret redaction を行う。
- [ ] Write 系は Review UI の承認 flow を必ず通す。
- [ ] テスト: approval なし write MCP call が拒否されることを確認する。
- [ ] 完了条件: 内蔵 Tool と同じ確認体験になる。

### P7-005: Process lifecycle and timeout

- [ ] MCP server process の起動、health check、timeout、shutdown を管理する。
- [ ] hung process は kill し、audit log に残す。
- [ ] stdout / stderr logging は secret redaction する。
- [ ] テスト: timeout、crash、invalid JSON-RPC response を fake server で確認する。
- [ ] 完了条件: 外部 process の失敗でアプリ全体が落ちない。

### P7-006: MCP audit log

- [ ] server name、tool name、risk、approval、duration、result、error を記録する。
- [ ] args は summary 化し、secret を残さない。
- [ ] ユーザーが後から external call の履歴を確認できる画面を作る。
- [ ] テスト: success / failure / timeout / redaction を確認する。
- [ ] 完了条件: 外部 MCP の実行責任を追跡できる。

### P7-007: External MCP test kit

- [ ] development 用 fake MCP server を用意する。
- [ ] read tool、write tool、danger tool、slow tool、invalid response tool を持たせる。
- [ ] CI で MCP client regression test を走らせる。
- [ ] 完了条件: 実外部 server なしで安全境界を検証できる。

## Exit Gate

- [ ] stdio MCP server を登録、起動、tools/list、tools/call できる。
- [ ] 分類不能 / dangerous tool は実行不可。
- [ ] Write tool は approval 必須。
- [ ] timeout / crash でアプリが落ちない。
- [ ] MCP 実行履歴が audit log に残る。
