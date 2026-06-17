# Phase 4: Deadline Watcher

目的は、SoloPM の差別化である「納期まで見張る」体験を成立させること。Project / Task / Artifact の状態をローカルで監視し、期限前と期限超過を落ち着いた頻度で通知する。

## Scope

- Deadline scan
- Overdue scan
- Daily check
- Notification scheduling
- Menu bar summaries
- File update monitoring

## Non-goals

- Cloud sync
- チーム通知
- Slack / Gmail 自動通知
- AI による自動延期
- 危険操作

## Checklist

### P4-001: Clock abstraction

- [x] `Clock` / `DateProvider` を作り、現在時刻を injectable にする。
- [x] timezone は Settings の値を使う。
- [x] テスト: fixed clock で今日、明日、期限超過の判定を安定させる。
- [x] 完了条件: 日付ロジックが実行日によって flaky にならない。

### P4-002: Deadline query service

- [x] `DeadlineQueryService` を作り、今日、明日、3日以内、1週間以内、期限超過を返す。
- [x] Project と Task を統合した summary model を作る。
- [x] 完了済み task / completed project は通知対象から外す。
- [x] テスト: 境界日、timezone、completed exclusion を確認する。
- [x] 完了条件: MenuBar と Notification scheduler が同じ query を使う。

### P4-003: DeadlineRule model

- [x] `DeadlineRule` table を作る。
- [x] `T-14`、`T-7`、`T-3`、`T-1`、`day_of`、`overdue_daily`、`custom` を表現する。
- [x] projectId / taskId のどちらにも紐付けられるようにする。
- [x] テスト: rule から notifyAt を計算する logic を確認する。
- [x] 完了条件: ActionPlan の notification rule を永続化できる。

### P4-004: Notification scheduling service

- [x] DeadlineRule から UserNotifications request を作る service を実装する。
- [x] 同じ rule の重複予約を防ぐ idempotency key を決める。
- [x] 通知文面は title、未完了数、次の候補 task を短く含める。
- [x] 次の候補 task は未完了タスクの due date / priority から deterministic に選び、MVP では LLM 生成しない。
- [x] テスト: duplicate schedule、past date skip、permission denied を fake client で確認する。
- [x] テスト: 同じ入力なら同じ通知文面になることを fixed clock と fixture で確認する。
- [x] 完了条件: 通知が過剰に増えない。

### P4-005: Overdue checker

- [x] overdue project / task を検出する。
- [x] overdue_daily は 1 日 1 回までに制限する。
- [x] ユーザーが完了 / 延期 / mute したものは再通知しない。
- [x] テスト: daily throttle、muted exclusion、completed exclusion を確認する。
- [x] 完了条件: 期限超過を見逃さず、通知疲れも起こしにくい。

### P4-006: Daily check runner

- [x] SMAppService / login item で日次 check を起動する方針を実装する。
- [x] アプリ起動時にも missed check を補完する。
- [x] check result を audit log に残す。
- [x] テスト: lastRunAt に応じて check が走る / 走らないを確認する。
- [ ] 手動確認: login item 設定をオン / オフできる。
- [ ] 完了条件: アプリを毎日開かなくても締切監視が動く設計になる。

### P4-007: Menu bar summaries

- [x] Today、Overdue、This Week、Recent Projects の summary を ViewModel に出す。
- [x] 件数が 0 の場合の calm な空状態を作る。
- [x] overdue は視認性を上げるが、過度に警告色を使わない。
- [x] テスト: summary ordering、empty state、overdue count を確認する。
- [ ] 手動確認: メニューバー上で一覧が読みやすい。
- [x] 完了条件: アプリを開いた瞬間に今日の状態が分かる。

### P4-008: Artifact monitoring foundation

- [ ] Artifact table に expected path、created state、lastModifiedAt を持たせる。
- [ ] FSEvents adapter を `FileMonitorClient` の背後に置く。
- [ ] MVP ではユーザーが選択した workspace 配下だけ監視する。
- [ ] テスト: fake file monitor で update event と stale detection を確認する。
- [ ] 完了条件: 長期間更新なし通知の基礎ができる。

### P4-009: Stale artifact detection

- [ ] 成果物未作成、未更新、期限前未完成を検出する。
- [ ] 通知対象にする条件を DeadlineRule と紐付ける。
- [ ] ファイル内容はユーザー承認なしに LLM へ送らない。
- [ ] テスト: missing file、stale file、recently updated を確認する。
- [ ] 完了条件: 成果物の進捗をローカル metadata だけで判断できる。

### P4-010: Watcher audit and diagnostics

- [ ] scan 件数、通知予定件数、skip 理由、error を audit log に残す。
- [ ] Debug view で last check、next check、permission state を確認できるようにする。
- [ ] テスト: failed scan がアプリ全体を落とさないことを確認する。
- [ ] 完了条件: 通知されない問題を調査できる。

## Exit Gate

- [x] 今日、今週、期限超過の summary が menu bar に出る。
- [x] DeadlineRule に基づき通知予約できる。
- [x] overdue_daily が過剰通知しない。
- [ ] file monitoring は許可された workspace に限定されている。
- [x] 日付ロジックは fixed clock で test されている。
