# Inbox Triage Lifecycle and Voice Playback Design

**Date:** 2026-08-11  
**Status:** Approved for implementation planning  
**Scope:** Inbox triage lifecycle correctness and persistent local voice playback  
**Reference UI:** `ui-samples/02_inbox.png`

## 1. Goal

Inboxを「入力を一時的に受け取り、内容を確認して次の扱いを決める処理キュー」として完成させる。

この設計の完了状態は次のとおり。

- `Make Task` は対象をInbox内の処理済みTaskへ変更し、通常の未処理一覧から除外する。
- `Review Later` はTaskの締切を変更せず、翌日午前9時まで対象を未処理一覧から隠す。
- `Newest First` / `Oldest First` はTask IDではなくInboxへ取り込まれた日時を基準にする。
- Inboxプロジェクトが存在しない場合もQuick Addが自動復旧して保存できる。
- Voice captureの録音を永続保存し、再生、一時停止、シーク、進捗、実波形を提供する。
- すべての分類操作、Undo、アプリ再起動、音声ファイル失敗時にデータ整合性と利用可能なTranscriptを維持する。

## 2. Non-goals

次は今回追加しない。

- 複数録音を一覧・切替するUI
- 音声の編集、トリミング、再生速度変更
- 波形データのSQLite永続化
- クラウドへの音声保存
- `Review Later` の任意日時選択
- AIによる分類先の自動決定
- Inbox以外のTask状態モデルの再設計
- サイドバー構成の変更

## 3. Existing Constraints

- Taskは必ずProjectに所属し、Inbox自体も通常のProjectとして保存される。
- `tasks` テーブルにはすでに `created_at` と `updated_at` が存在するが、`ProjectBoardTask` は `created_at` を公開していない。
- Voice captureは `inbox_capture_records` に保存されるが、録音パスは現在一時ディレクトリを参照している。
- `InboxCaptureClassificationStatus` はVoice captureだけに存在するため、Manual captureを含むInbox全体の処理状態の真実源にはできない。
- Taskの `dueAt` は締切であり、再確認日時として流用しない。
- Work Managementが状態遷移と永続化を所有し、SwiftUIはViewModelのread modelと操作だけを利用する。
- 現行の分類後自動選択、単一ステップUndo、通常のBoard Undoは維持する。

## 4. Chosen Architecture

Inbox固有状態をTaskと1対1で保存する `inbox_triage_records` を追加する。Taskの汎用列へInbox専用状態を追加せず、Voice captureの分類状態にも依存しない。

取り込み日時は重複保存しない。既存の `tasks.created_at` を `ProjectBoardTask.createdAt` としてread modelへ公開し、Inboxの並び替えに利用する。

### 4.1 Domain types

```swift
public enum InboxTriageDisposition: String, Codable, Equatable, Sendable {
    case unprocessed
    case task
    case scheduled
    case reviewLater = "review_later"
    case project
}

public struct InboxTriageRecord: Equatable, Sendable {
    public var taskID: Int64
    public var disposition: InboxTriageDisposition
    public var reviewAt: String?
    public var updatedAt: String
}

public enum InboxTriageAction: Equatable, Sendable {
    case makeTask
    case makeProject
    case scheduleToday
    case reviewLater
}
```

`reviewAt` は `reviewLater` の場合だけ値を持つ。ドメイン初期化とSQLite CHECK制約の両方でこの不変条件を守る。

### 4.2 SQLite schema

```sql
CREATE TABLE IF NOT EXISTS inbox_triage_records (
    task_id INTEGER PRIMARY KEY NOT NULL,
    disposition TEXT NOT NULL
        CHECK(disposition IN ('unprocessed', 'task', 'scheduled', 'review_later', 'project')),
    review_at TEXT,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK(
        (disposition = 'review_later' AND review_at IS NOT NULL)
        OR
        (disposition != 'review_later' AND review_at IS NULL)
    ),
    FOREIGN KEY(task_id) REFERENCES tasks(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_inbox_triage_disposition_review
ON inbox_triage_records(disposition, review_at);
```

新しいmigrationは既存の `CoreMigrations.current` に追加し、繰り返し実行しても同じ結果になるようにする。

### 4.3 Existing data backfill

active/archivedを問わず、タイトルが大文字小文字を無視して `Inbox` と一致するProject配下の既存Taskへ状態を作る。

| Existing Task | Backfilled disposition |
|---|---|
| `status == done` | `task` |
| `due_at != NULL` | `scheduled` |
| その他 | `unprocessed` |

過去の `Make Task` と本当の未処理Taskは現在のDBから判別できない。期限なし・未完了Taskは安全側で `unprocessed` とし、移行によって利用者の項目を不可視にしない。

stateが欠落したTaskを読み込んだ場合も同じ規則で導出し、次のInbox mutationで永続stateをself-healする。migration未適用や部分的な旧データでもInbox全体を利用不能にしない。

## 5. Persistence Boundary and Atomicity

既存の `ProjectBoardStore` にInbox専用操作を追加する。

```swift
func performInboxTriage(
    taskID: Int64,
    action: InboxTriageAction,
    referenceDate: Date
) throws -> InboxTriageMutation
```

SQLite実装はTask更新、Project作成・移動、`inbox_triage_records` 更新を同一SQLite transaction内で実行する。ViewModelやViewがTask storeとInbox state storeを順番に更新してはならない。

`InboxTriageMutation` は次を返す。

- 更新後Task
- 操作前Task snapshot
- 操作前Inbox state
- 作成したProject ID（Make Projectのみ）
- Undoに必要なVoice capture再リンク情報

`ProjectBoardViewModel` の責務は次に限定する。

- 操作要求
- 成功・失敗feedback
- 次の表示可能Taskの選択
- 単一ステップのInbox Undo保持
- load後のread model更新
- `onChange` 通知

mutation失敗時は選択、Task、Project、Inbox state、memo draftを変更しない。

## 6. Inbox State Transitions

| User action | Task mutation | New disposition | Unprocessed visibility |
|---|---|---|---|
| Quick Add | `backlog`, no due date | `unprocessed` | Visible |
| Make Task | Preserve content, priority and due date | `task` | Hidden |
| Schedule Today | `planned`, `dueAt = referenceDate` | `scheduled` | Hidden |
| Review Later | Preserve Task due date and status | `reviewLater`, next day 09:00 | Hidden until due |
| Make Project | Create Project, move Task, set `planned` | `project` | Hidden because Task left Inbox |
| Complete | Set `done`; if unprocessed, finalize as Task | `task` | Hidden |
| Reopen | Set `planned` | Preserve `task` | Hidden |
| Delete | Delete Task | Cascade delete | Hidden |
| Undo | Restore Task, Project, Voice link and state | Previous value | Previous value |

### 6.1 Make Task

`Make Task` はProjectを新規作成せず、TaskをInbox内に残したまま `task` へ変更する。通常の `Unprocessed` 一覧から消え、`All` では履歴として確認できる。

### 6.2 Review Later

操作時点のローカルCalendarで翌日の午前9時を計算し、ISO 8601の絶対時刻として `review_at` に保存する。24時間の秒数加算は使わず、Calendar APIでDSTを処理する。

- アプリ終了中に時刻を過ぎた場合、次回load時に表示する。
- Inboxを開いたままの場合、1分間隔で再評価し、遅くとも1分以内に表示する。
- 到達後もstateは `reviewLater` のまま保持する。
- もう一度 `Review Later` を実行すると、その操作日の翌日9時へ更新する。
- Taskの `dueAt` は変更しない。

## 7. Inbox Read Model and UI Rules

初期filterを `All` から `Unprocessed` へ変更する。

### 7.1 Filters

- `Unprocessed`: `unprocessed`、または `reviewLater` かつ `reviewAt <= now`
- `All`: Inbox Project内の全Task。既存のShow Done設定を適用する。
- `Voice`: Voice captureを持つInbox Task。処理状態は問わない。
- `AI Suggested`: transcription成功かつinterpretationを持つInbox Task。処理状態は問わない。
- `Manual`: Voice captureを持たないInbox Task。処理状態は問わない。

Source filterでReview Later中の項目が表示された場合は、「明日 9:00 に再確認」などの状態badgeを表示する。

### 7.2 Sorting

- `Newest First`: `createdAt` 降順、同値ならID降順
- `Oldest First`: `createdAt` 昇順、同値ならID昇順
- `Title`: `localizedStandardCompare`、同値ならID昇順

編集、memo保存、分類操作によって取り込み順は変わらない。

### 7.3 Selection and feedback

成功時は次の順序を守る。

1. persistence mutationを完了する。
2. snapshot/state cacheを再読込する。
3. 現在filterで次に表示可能なTaskを選択する。
4. feedbackとUndoを表示する。
5. 項目がなければ選択を解除し、空状態を表示する。

失敗時は選択と入力中stateを維持し、次のTaskへ進めない。エラーには絶対パス、SQLite文、内部provider情報を含めない。

## 8. Quick Add Recovery

Inbox Viewから既存Inbox IDを直接取得して `createTask` を呼ぶ経路を廃止し、`createInboxTask` を唯一の入口にする。

- active Inboxが存在すれば再利用する。
- 存在しなければInbox Projectを作成する。
- Taskと `unprocessed` stateを同一SQLite transactionで保存する。
- 空白titleは保存しない。
- 保存失敗時は入力内容とfocusを維持し、recoverable errorを表示する。
- 成功時だけ入力を消してcomposerを閉じる。

## 9. Persistent Voice Audio

### 9.1 File ownership

録音完了後、一時ファイルを次へ取り込む。

```text
Application Support/Suisui/InboxAudio/<UUID>.<validated-extension>
```

`InboxVoiceCaptureService` は `InboxAudioPersisting` を注入される。macOS実装の `ManagedInboxAudioFileStore` がディレクトリ作成、取り込み、削除、canonical path検証を担当する。

保存ファイル名にTask title、transcript、Project名など利用者由来の文字列を含めない。

### 9.2 Save compensation

ファイルシステムとSQLiteを単一transactionにはできないため、次の補償順序を固定する。

1. 音声取り込み失敗: Taskを作らない。
2. Task作成失敗: 取り込んだ音声を削除する。
3. Capture作成失敗: 作成したTaskと取り込んだ音声を削除する。
4. 補償削除失敗: 管理ディレクトリ内の孤立ファイルとして起動時cleanupへ委ねる。

途中まで成功した音声なしVoice Taskを残さない。

### 9.3 Legacy path migration

既存captureの初回アクセス時に次を行う。

- Suisui所有の一時ファイル名でファイルが存在する: 管理ディレクトリへ移動し、capture pathを更新する。
- ファイルが存在しない: `Recording unavailable` を表示する。
- 管理外パス: 再生も移動もせず、sanitized errorを表示する。

管理外の任意パスをDB値だけで読み込まない。

## 10. Playback and Waveform

現行の `SpeechAudioPlaying` はWAV/CAFの完了待ちpreview用で、一時停止、シーク、進捗、M4Aを扱わない。この契約を拡張せず、Inbox専用の小さな再生境界を追加する。

### 10.1 Playback controller

`InboxAudioPlaybackController` は `@MainActor` で次を公開する。

- playback state: idle / loading / playing / paused / failed
- current time
- duration
- play / pause / seek / stop
- sanitized visible error

macOS adapterはAVFoundationを使用する。選択Taskまたはcaptureが変わったとき、Viewが閉じたとき、別録音の再生を始めたときは以前の再生を停止してresourceを解放する。同時再生は選択中の1録音だけに限定する。

### 10.2 Waveform

`InboxAudioWaveformLoading` はAVFoundationでPCMをストリーミング読込し、64区間の正規化peak値を返す。

- 音声全体を一度にメモリへ展開しない。
- UI threadで解析しない。
- `captureID + file modification date` 単位でメモリcacheする。
- SQLiteへ波形を保存しない。
- 解析失敗時は固定波形を出さず、ネイティブ進捗barへfallbackする。

### 10.3 Playback UI

- 再生／一時停止button
- 実波形と再生済み範囲
- シーク可能なnative Slider
- 現在位置／全体時間
- visible failure reason

Space keyは再生controlにkeyboard focusがある場合だけ動作させ、Project Board全体のshortcutと競合させない。

### 10.4 Accessibility

- button labelを状態に応じて「録音を再生」「録音を一時停止」に変更する。
- Sliderは経過時間と全体時間をVoiceOverへ通知する。
- 波形そのものは装飾としてaccessibility treeから隠す。
- 失敗理由をvisible text、accessibility value、helpで一致させる。
- 再生失敗時もTranscript、AI Interpretation、memo操作を利用可能にする。

## 11. Security and Cleanup

再生・削除・移行の前に次を検証する。

- canonical pathがInboxAudio管理root配下である。
- symlink解決後も管理root外へ出ない。
- regular fileである。
- AVFoundationがdecode可能である。
- user-facing error、audit、test artifactへ絶対パスを出さない。

明示的なTask/capture削除後は参照音声を削除する。起動時にはDBから参照されていない管理音声だけをcleanupする。管理root外のファイルは削除しない。

## 12. Error Handling

| Failure | Required behavior |
|---|---|
| Inbox state load failure | Taskを隠さずderived `unprocessed` として表示し、sanitized errorを出す |
| Triage mutation failure | Task、state、selection、memo draftを変更しない |
| Review clock refresh failure | 現在表示を維持し、次のloadで再評価する |
| Audio import failure | Task/captureを作らず、録音中stateを保持する |
| Audio missing | Playbackを無効化し、Transcriptを維持する |
| Unsafe audio path | Playback/deleteを拒否し、パスを表示しない |
| Audio decode failure | Playbackを停止し、再試行可能な表示を出す |
| Waveform failure | Playback可能ならprogress barへfallbackする |
| Compensation delete failure | 起動時orphan cleanupへ委ねる |

## 13. TDD Plan

実装は次の順序で、各段階をredからgreenへ進める。

1. `InboxTriageDisposition` とReview日時計算のunit tests
2. SQLite migration、CHECK/FK、backfill、idempotency tests
3. Storeの原子的mutationとfault-injection rollback tests
4. ViewModel filter、自動次選択、feedback、Undo、再起動tests
5. Quick AddによるInbox自動作成と失敗時draft保持tests
6. Inbox UI composition、状態badge、keyboard、accessibility source tests
7. managed audio import、unsafe path拒否、補償削除、orphan cleanup tests
8. fake playerを使ったplay/pause/seek/selection-change tests
9. 短い音声fixtureを使った64-bucket waveform tests
10. runtime Inbox triage smokeとSQLite事後条件
11. runtime voice playback smokeとAX事後条件

### 13.1 Required behavior matrix

最低限、次を自動テストする。

- Make Task後にUnprocessedから消え、Allには残る。
- Make TaskをUndoするとUnprocessedへ戻る。
- Review LaterはTaskのdueAtを変更しない。
- 8:59では非表示、9:00では表示される。
- DST境界でも翌日ローカル9:00になる。
- Schedule TodayとMake Projectの現行動作・Undoを維持する。
- migration後の既存期限なしTaskは不可視にならない。
- SQLite再起動後もdispositionとreviewAtが維持される。
- Inbox欠落時のQuick AddがInbox、Task、stateを一度だけ作る。
- 音声保存失敗時にTask、capture、管理音声の孤児が残らない。
- 管理root外・symlink escape・欠落音声を再生しない。
- 再生中の選択変更で停止する。
- waveform解析失敗時に偽波形を表示しない。
- Playback失敗時もTranscript、AI Interpretation、memoが操作可能である。

### 13.2 Required validation commands

```bash
swift test --filter InboxCaptureStoreTests
swift test --filter ProjectBoardStoreTests
swift test --filter AppExperienceSourceTests
swift test --filter ReleasePipelineTests
./script/check_runtime_inbox_triage_smoke.sh
./script/check_accessibility_preflight.sh --source-only
./script/check_accessibility_preflight.sh --runtime
./script/check_security_regressions.sh
swift test
git diff --check
```

Voice playback runtime smokeはIssue 2で追加し、実音声fixtureの再生開始、一時停止、シーク、選択変更時停止、missing-file表示を検証する。

Visual確認は英語・日本語、Light・Dark、横長・compactを対象とする。compactでは右railを一覧の下へ移動し、水平scrollを発生させない。

## 14. Implementation Boundaries

主な変更候補は次のとおり。実装計画では現在のファイル責務を再確認して最小の所有範囲へ確定する。

### Inbox lifecycle

- `Sources/SuisuiCore/Database/SQLiteDatabaseClient.swift`
- `Sources/SuisuiCore/WorkManagement/WorkManagementModels.swift`
- `Sources/SuisuiCore/WorkManagement/WorkManagementStore.swift`
- `Sources/SuisuiCore/WorkManagement/WorkManagementSQLiteStore.swift`
- `Sources/SuisuiCore/App/ProjectBoard.swift`
- `Sources/SuisuiApp/Views/ProjectWorkflowInboxView.swift`
- corresponding `SuisuiCoreTests`
- `script/check_runtime_inbox_triage_smoke.sh`

### Voice playback

- `Sources/SuisuiCore/Voice/InboxCapture.swift`
- new protocol-focused Core file only if `InboxCapture.swift` would grow further
- `Sources/SuisuiApp/Adapters/`
- `Sources/SuisuiApp/Composition/ProjectBoardRuntimeFactory.swift`
- `Sources/SuisuiApp/Views/ProjectWorkflowInboxView.swift`
- corresponding `SuisuiCoreTests`
- accessibility/security/runtime smoke scripts

No external packageを追加しない。Foundation、SQLite、AVFoundation、SwiftUIの既存境界を再利用する。

## 15. Issue Decomposition

関連するopen Issueを検索したが、この仕様と重複するIssueは存在しない。実装・reviewリスクが独立するため2件へ分ける。

### Issue 1: Fix Inbox triage lifecycle with explicit disposition and deferred review

**Type / labels:** `bug`, `priority:p1`, `mvp:personal`, `track:tasks`, `track:ui`

**Why:** 現在のMake Taskは未処理条件を変えず、Review Laterは期限を消すだけなので、操作成功表示と実際のInbox状態が一致しない。ID順sortとInbox欠落時の無反応も、処理キューとしての信頼性を下げる。

**Goal:** 明示的disposition、翌日9時のreviewAt、createdAt sort、Quick Add復旧、原子的Undoを実装し、未処理項目が操作どおりに移動することをSQLite再起動後まで保証する。

**Implementation:** Sections 4-8 and 12-14のInbox lifecycle部分に従う。

**Acceptance criteria:**

- Make Task後にUnprocessedから消え、Allに残る。
- Review LaterがdueAtを変更せず、翌日9時に再表示する。
- Newest/OldestがcreatedAtを使用する。
- Inbox欠落時もQuick Addが成功する。
- 4分類操作とUndoが原子的で、再起動後も一貫する。
- 既存データmigrationで期限なしTaskを隠さない。
- runtime smoke、AX、security、full testが通る。

### Issue 2: Add persistent and secure Inbox voice playback with real waveform

**Type / labels:** `enhancement`, `priority:p2`, `mvp:personal`, `track:voice`, `track:ui`

**Why:** 現在の録音パスは一時ファイルを参照し、Inboxの波形は固定表示で再生できない。分類前に元音声を確認できず、時間経過でファイルが失われる可能性がある。

**Goal:** 管理ディレクトリへの永続保存、安全なlegacy移行、play/pause/seek/progress、実波形、失敗fallback、VoiceOver操作を実装する。

**Implementation:** Sections 9-14のVoice playback部分に従う。

**Acceptance criteria:**

- 新規録音がApplication Support配下へ保存され、再起動後も再生できる。
- play/pause/seek/selection-change stopが動作する。
- 実音声から64区間の波形を生成する。
- unsafe/missing/undecodable fileを安全に拒否する。
- 保存失敗時にTask、capture、音声の孤児を残さない。
- 削除と起動時cleanupが管理root外へ触れない。
- Playback失敗時もTranscript、Interpretation、memoを利用できる。
- runtime playback smoke、AX、security、full testが通る。

Issue 2はIssue 1のUI完成を待たずCore/adapterを実装できるが、同じInbox Viewを編集するため、merge順はIssue 1を先にする。

## 16. Definition of Done

- 本設計の状態遷移と音声ライフサイクルが実装されている。
- Issueごとのacceptance criteriaが自動テストとruntime evidenceで確認されている。
- 既存Inbox、Voice Command、Today、Project、Schedule、Doneの回帰がない。
- 日本語・英語、Light・Dark、wide・compactで確認済み。
- VoiceOver、keyboard、error表示がvisible UIと一致している。
- 外部依存、秘密情報、絶対パス漏えい、管理外ファイル操作が追加されていない。
- `outputs/` を含むユーザー所有の未追跡ファイルへ触れていない。

