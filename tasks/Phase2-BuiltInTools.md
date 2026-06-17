# Phase 2: Built-in Tools

目的は、MVP の実行先を外部 MCP ではなく Swift 内蔵 Tool Registry として実装すること。Tool は MCP 互換 schema を持つが、まずはアプリ内 protocol / adapter として堅牢に作る。

## Scope

- Tool Registry
- ProjectTool
- TaskTool
- NotificationTool
- CalendarTool
- ReminderTool
- FileSystemTool
- KnowledgeFrameTool
- MailDraftTool は draft-only の範囲で検討

## Non-goals

- 外部 MCP process 起動
- Gmail / Slack / GitHub への write
- dangerous operation
- Review UI からの実行
- ユーザー操作または LLM flow からの write tool 実行

## Checklist

### P2-001: Tool protocol と Tool Registry

- [x] `Tool` protocol を作り、name、description、input schema、risk level、execute を持たせる。
- [x] `ToolRegistry` に tool registration、lookup、schema list を実装する。
- [x] unknown tool は blocking error にする。
- [x] テスト: duplicate registration、unknown lookup、schema export を確認する。
- [x] 完了条件: Phase 1 の ActionPlan actions と registry が名前で接続できる。

### P2-002: Permission policy

- [x] Tool ごとの `Read`、`Draft`、`Write with approval`、`Dangerous` を定義する。
- [x] `Dangerous` は registration できても execute できない、または MVP では登録しない。
- [x] `Write with approval` は approval token なしでは失敗する。
- [x] Phase 2 中は write tool を unit test、integration smoke、明示的な developer harness からのみ実行できるようにし、ユーザー操作や LLM flow からは到達不能にする。
- [x] テスト: approval なし write action が拒否され audit log に残ることを確認する。
- [x] テスト: user-facing route から write tool が呼ばれないことを確認する。
- [x] 完了条件: LLM が write action を生成しても直接実行されない。

### P2-003: ProjectTool

- [x] `project.create`、`project.update`、`project.list`、`project.get`、`project.complete` の schema を定義する。
- [x] `projects` table migration を追加する。
- [x] title、status、priority、deadline、workspacePath、tags、sourceCommand を保存する。
- [x] テスト: create、required validation、deadline optional、list order を in-memory DB で確認する。
- [x] 完了条件: Project は DB に永続化され、audit log に tool invocation が残る。

### P2-004: TaskTool

- [x] `task.create`、`task.bulk_create`、`task.update`、`task.complete`、`task.list_due`、`task.list_overdue` の schema を定義する。
- [x] `tasks` table migration を追加する。
- [x] `projectId` は optional にし、Inbox task を許可する。
- [x] bulk create は一部失敗時の扱いを決め、transaction を使う。
- [x] テスト: bulk create、project 紐付け、due query、overdue query を確認する。
- [x] 完了条件: 今日 / 期限超過ビューの基礎 query が使える。

### P2-005: NotificationTool

- [x] `notification.schedule`、`notification.schedule_relative`、`notification.schedule_overdue_rule`、`notification.cancel`、`notification.list` の schema を定義する。
- [x] UserNotifications adapter を `NotificationClient` protocol の背後に置く。
- [x] notification request の id 命名規則を決める。
- [x] permission denied の場合は DB 上の予定状態を failed / pending にする。
- [x] テスト: fake client で schedule、relative rule、permission denied を確認する。
- [x] 完了条件: OS 通知は adapter 以外から直接呼ばれない。

### P2-006: CalendarTool

- [x] `calendar.create_event`、`calendar.create_deadline`、`calendar.create_work_block` の schema を定義する。
- [x] EventKit adapter を `CalendarClient` protocol の背後に置く。
- [x] timezone、all-day deadline、start/end validation を扱う。
- [x] `calendar_links` table を作り、外部 event id と Project / Task を紐付ける。
- [x] テスト: fake EventKit で all-day、invalid range、permission denied を確認する。
- [x] 完了条件: 実 Calendar 書き込みは approval 後にだけ呼べる設計になっている。

### P2-007: ReminderTool

- [x] `reminders.create`、`reminders.bulk_create`、`reminders.mark_complete` の schema を定義する。
- [x] EventKit Reminders adapter を `ReminderClient` protocol の背後に置く。
- [x] project 単位の reminder list 作成方針を決める。
- [x] `reminder_links` table を作る。
- [x] テスト: fake client で bulk create、list missing、permission denied を確認する。
- [x] 完了条件: Reminders と local task のリンクを追跡できる。

### P2-008: FileSystemTool

- [x] `filesystem.create_directory`、`filesystem.create_markdown_file`、`filesystem.create_artifacts_from_frame`、`filesystem.scan_project_artifacts` の schema を定義する。
- [x] Security-scoped Bookmark を使う境界を `FileAccessClient` に置く。
- [x] 既存ファイル上書きは禁止し、衝突時は alternative filename または blocking error にする。
- [x] テスト: temporary directory で create、existing file conflict、path traversal 拒否を確認する。
- [x] 完了条件: ユーザーが許可した workspace 配下以外には書き込まない。

### P2-009: KnowledgeFrameTool

- [x] `frame.search`、`frame.list`、`frame.get`、`frame.create`、`frame.update` の schema を定義する。
- [x] `knowledge_frames` table と FTS5 index を作る。
- [x] Frame body は Markdown / YAML text として保存できるようにする。
- [x] テスト: FTS search、trigger match、create/update index refresh を確認する。
- [x] 完了条件: Phase 1 の planning request に frame candidates を渡せる。

### P2-010: MailDraftTool draft-only

- [x] `maildraft.create_text` を draft risk として定義する。
- [x] MVP では送信、Gmail draft 作成、Apple Mail 自動送信はしない。
- [x] 生成文面は clipboard copy または mailto 起動候補までに留める。
- [x] テスト: send action が存在しないこと、draft text が audit log に適切に残ることを確認する。
- [x] 完了条件: メール送信の危険操作を追加せず、下書き文生成だけできる。

### P2-011: Tool invocation audit log

- [x] tool name、args summary、risk level、approval state、result、error を記録する。
- [x] file path、calendar title などは必要最小限にする。
- [x] secret や token は redaction する。
- [x] テスト: success、failure、approval missing、redaction を確認する。
- [x] 完了条件: 後から「何が作成されたか」を追える。

## Exit Gate

- [x] Built-in Tool Registry に MVP tool が登録されている。
- [x] 各 Tool に input schema、permission level、unit test がある。
- [x] Write tool は approval なしで実行できない。
- [x] Review UI 完成前の user-facing write execution route が存在しない。
- [x] Project / Task / Knowledge は SQLite と FTS5 で動く。
- [x] OS 連携は fake で test できる。
