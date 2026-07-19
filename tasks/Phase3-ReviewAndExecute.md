# Phase 3: Review & Execute

目的は、LLM が生成した ActionPlan をユーザーが理解、編集、承認してから実行できるようにすること。Suisui の信頼性はこの Phase で決まるため、確認 UI と実行安全性を最優先にする。

## Scope

- Action Review Screen
- Action ごとの編集
- 個別 enable / disable
- Approval flow
- Execution orchestration
- Execution log
- Rollback metadata

## Non-goals

- 自動実行
- Dangerous operation
- メール送信 / Slack 投稿
- 複雑な undo 実装
- 外部 MCP

## Checklist

### P3-001: Review state model

- [x] `ReviewSession`、`ReviewActionItem`、`ApprovalState` を定義する。
- [x] original plan と user-edited plan を分けて保持する。
- [x] action ごとの enabled / disabled を持たせる。
- [x] テスト: action disable、edit、reset、approval state transition を確認する。
- [x] 完了条件: View が直接 ActionPlan を mutate しない。

### P3-002: Action Review Screen layout

- [x] summary、risk level、作成予定一覧、必要権限、実行先を表示する。
- [x] Project、Task、Calendar、Reminder、Notification、File、Knowledge の action type ごとに読みやすく表示する。
- [x] empty / invalid / loading / error state を用意する。
- [x] UI テストまたは ViewModel test で各 state を確認する。
- [x] 手動確認: 長いタイトル、長いタスク一覧、狭い window で崩れない。
- [x] 完了条件: ユーザーが何が作られるかを実行前に判断できる。

確認メモ: 2026-06-18 に `CFFIXED_USER_HOME` で一時 Application Support を使い、長い project title と 18 件の長文 task を入れた `dist/Suisui.app` を 640x440 window で確認した。長文 card は省略 / hover 表示になり、board は縦横スクロール可能で、操作部品の重なりは見えない。Core の `argumentDisplaySummary` は title を優先表示し、長文・大量 field を省略しつつ full text を hover で確認できる。Voice / Review 画面も scrollable にし、Review header / action row は `ViewThatFits` で縦 fallback できる。

### P3-003: Action edit forms

- [x] action type ごとに編集可能 field を限定する。
- [x] 日時、title、body、workspace path、notification rule の validation を即時表示する。
- [x] 編集で schema 不一致になった場合は実行ボタンを disabled にする。
- [x] テスト: invalid edit が execution に進まないことを確認する。
- [x] 完了条件: LLM 出力の誤りをユーザーが修正できる。

### P3-004: Approval requirement UI

- [x] Write action が含まれる場合は明示的な承認操作を要求する。
- [x] Dangerous action が含まれる場合は実行不可として表示する。
- [x] 権限不足の場合は該当 action を disabled にし、Settings 導線を出す。
- [x] テスト: write without approval、danger present、permission denied の UI state を確認する。
- [x] 完了条件: 誤実行を防ぐ UI state が Core policy と一致している。

### P3-005: Execution orchestrator

- [x] `ActionExecutor` を作り、ReviewSession から enabled action のみ実行する。
- [x] Tool Registry を通して action を順番に実行する。
- [x] project.create の結果 id を後続 task.create に渡す依存解決を実装する。
- [x] 一部失敗時の扱いを `continue` / `stop` / `retryable` で整理する。
- [x] テスト: dependent action、partial failure、unknown tool、approval missing を確認する。
- [x] 完了条件: UI から直接 Tool を呼ばず、実行経路が一箇所に集約されている。

### P3-006: Execution progress UI

- [x] 実行中 action、成功、失敗、skip を表示する。
- [x] 実行中は二重実行を防ぐ。
- [x] 失敗時は retry 可能な action と不可の action を分ける。
- [x] テスト: executing state 中に再実行できないことを確認する。
- [x] 手動確認: fake executor で成功 / 失敗 / 部分成功を確認する。
- [x] 完了条件: ユーザーが結果を理解し、次に何をすべきか分かる。

### P3-007: Rollback metadata

- [x] 実行結果に created project id、task id、calendar event id、reminder id、notification id、file path を記録する。
- [x] MVP では自動 rollback しない。削除や上書きは禁止のため、metadata の保存に留める。
- [x] rollback 可能性は tool result に `compensationHint` として残す。
- [x] テスト: successful tool result が rollback metadata を持つことを確認する。
- [x] 完了条件: 後続で undo / cleanup を作れるだけの情報がある。

### P3-008: Execution audit log

- [x] ReviewSession 作成、編集、承認、実行開始、各 tool result、完了を audit log に残す。
- [x] ユーザーが無効化した action も skipped として記録する。
- [x] テスト: approved execution と canceled session の audit event を確認する。
- [x] 完了条件: ユーザー確認を経たことがログで追える。

### P3-009: End-to-end fake flow

- [x] Fake STT、Fake LLM、Fake ToolRegistry で `text input -> plan -> review -> execute` を通す。
- [x] 実 OS 連携なしで E2E smoke test を組む。
- [x] sample command は docs の QZT 記事公開ケースを使う。
- [x] 完了条件: CI 上で主要 UX flow の regression を検知できる。

## Exit Gate

- [x] ActionPlan を Review UI で確認、編集、承認できる。
- [x] 承認なし write action は実行できない。
- [x] fake tool で E2E flow が通る。
- [x] 実行ログと rollback metadata が残る。
- [x] Dangerous operation は UI / Core の両方で拒否される。
