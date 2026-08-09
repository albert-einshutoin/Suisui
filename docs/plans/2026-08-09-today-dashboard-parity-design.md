# Todayダッシュボード `today.png` 準拠設計

- 状態: 承認済み
- 承認日: 2026-08-09
- 対象: Suisui macOS版のTodayメインコンテンツ
- 基準画像: [`ui-samples/today.png`](../../ui-samples/today.png)
- 設計基準コミット: `bd46eff315b3b48eae6db4c5e03a12e84dd29380`（PR #438マージ後の`origin/main`）

## 1. 背景

PR #438で`today.png`を基準にしたサイドバーは導入済みだが、Todayのメインコンテンツは従来のアクション中心の縦型画面を維持している。そのため、基準画像にある次の情報構造と機能が不足している。

- 日付・個人向け挨拶・天気をまとめたヘッダー
- 3件のおすすめアクション
- 時刻、プロジェクト、優先度を一覧できる「今日やること」
- 今週の予定
- レビュー依頼と外部連携の変更をまとめた「要確認」
- 今日の予定負荷を時間で示すワークロード
- 再起動後も復元できるFocusタイマー
- 文脈に沿ったSuisui Assistantの提案

本設計はサイドバーを再設計せず、メインコンテンツを`today.png`の情報階層と視覚密度へ合わせる。

## 2. ゴール

1. 1448×1086の広い画面で、`today.png`と同じ読み順・領域構成・情報密度を実現する。
2. 小さい画面では横スクロールを発生させず、右レールのコンポーネントをメインコンテンツ下部へ移動する。
3. 既存のToday、Schedule、Assistant QueueのRead Modelを真実のデータ源として再利用し、ストアを二重化しない。
4. WeatherKit、Google Calendar、Slackの情報を、権限・プライバシー・レート制限を守って読み取り専用で表示する。
5. Focusタイマーをローカル状態として実装し、タスク状態や外部サービスを暗黙に変更しない。
6. 表示名を初回オンボーディングで尋ね、Settingsから後で変更できるようにする。
7. 日本語・英語のどちらでもプロダクト名を`Suisui`のまま表示する。

## 3. 非ゴール

- PR #438で導入されたサイドバーの再構成
- ユーザーが並べ替えられる汎用ウィジェット基盤
- TodayからGoogle CalendarやSlackへ書き込む機能
- Focus完了時のタスク自動完了・ステータス自動変更
- FocusタイマーによるCalendarブロックの自動作成
- 外部サービスの全メッセージ本文や全イベント詳細のローカル保存
- AI応答を待たなければ表示できないおすすめ生成
- `Suisui`を「すいすい」へ翻訳すること

## 4. 確定したプロダクト判断

| 項目 | 決定 |
|---|---|
| 機能範囲 | レイアウトだけでなくWeatherと外部更新を含む完全機能を目指す |
| 導入順 | Dashboard → Focus/Workload → Weather → Calendar/Slackの4段階 |
| Wideレイアウト | `today.png`に忠実な主領域＋右レール |
| Compactレイアウト | 右レールをメイン末尾へ移動し、横スクロールを出さない |
| 天気位置 | Core Locationの明示許可＋手動都市のフォールバック |
| 天気プロバイダー | WeatherKit |
| 外部更新 | Calendar変更とSlack未読・mentionの読み取り専用表示 |
| Focus | 25/50/90分とカスタム、停止・再開・終了、再起動復元 |
| 表示名 | Settingsの任意項目。初回オンボーディングでも入力・保存 |
| Workload | 今日の予定ブロック時間 ÷ 1日の作業容量（初期値8時間） |
| アーキテクチャ | 既存Read Modelを純粋なToday専用Snapshotへ薄く集約 |

## 5. 画面構成

### 5.1 Wide

標準サイドバーを含むウインドウがおおむね1280pt以上で、主領域の最低幅と右レールを同時に確保できる場合に使用する。

```text
┌──────────────────────────────────────────────────────────────────┐
│ 今日  2026年8月9日                                                │
├──────────────────────────────────────────────────────────────────┤
│ おはようございます、山田さん。                     ☀ 23℃ 渋谷区 │
│ 今日の概要                                                       │
├────────────────────────────────────────────┬─────────────────────┤
│ おすすめ × 3                               │ 今日のワークロード   │
├────────────────────────────────────────────┤                     │
│ 今日やること                               ├─────────────────────┤
│                                            │ フォーカスタイム     │
├──────────────────────┬─────────────────────┤                     │
│ 今週の予定           │ 要確認              ├─────────────────────┤
│                      │ - レビュー依頼       │ Suisui Assistant     │
│                      │ - 外部連携の変更     │                     │
└──────────────────────┴─────────────────────┴─────────────────────┘
```

- 主領域は可変幅、右レールは280〜320ptを目安とする。
- 主領域は最低720ptを確保する。
- 右レールとの間隔は既存デザイントークンを使い、独自の固定値を散在させない。
- 実装上はウインドウ幅そのものではなく、Today詳細領域で「主領域720pt＋間隔＋右レール280pt」が収まるかを測る。これによりサイドバー幅変更時も破綻しない。

### 5.2 Compact

右レールまで同時に表示できない場合、順序を次のように変更する。

1. ヘッダー
2. おすすめ
3. 今日やること
4. 今週の予定
5. 要確認
6. 今日のワークロード
7. フォーカスタイム
8. Suisui Assistant

- おおむね900〜1279ptのウインドウでは、下部へ移動した右レールカードを横並びにできる場合は横並びにする。
- それより狭い場合は1列に積む。
- タスク一覧はWideの表からCompactの折り返し可能なカード行へ切り替える。
- どの幅でもコンテンツ領域の横スクロールを許可しない。
- キーボードとVoiceOverの移動順は、再配置後の視覚順と一致させる。

### 5.3 `today.png`との意図的な差分

- WeatherKitの規約に従い、天気の詳細表示にApple Weatherの帰属と法的リンクを追加する。
- データ未設定、拒否、オフライン、レート制限の状態を隠さず、カード内状態として表示する。
- Dynamic Type、キーボード、VoiceOver、Reduce Motionに対応するため、固定ピクセルだけに依存しない。

## 6. 情報設計

### 6.1 ヘッダー

表示内容:

- 「今日」とローカライズ済みの日付
- 時刻帯に応じた挨拶
- 任意の表示名
- 今日のタスク件数と予定件数を用いた短い概要
- 現在天気、気温、位置ラベル

表示名が空の場合は、句読点が不自然にならない名前なしの挨拶へ切り替える。表示名は前後空白を除去し、空文字を有効な名前として保存しない。

### 6.2 おすすめ

おすすめはネットワークAIへ依存せず、既存データから最大3件を決定論的に生成する。

候補の優先順:

1. 期限・優先度・現在時刻から選ばれた最優先タスクのFocus開始
2. 未確認のレビュー依頼またはCatch Up
3. 未配置の高優先度タスクをScheduleへ配置
4. 長い連続予定の間に休憩を提案
5. Todayが空の場合のタスク追加

同一入力から同一順序を返し、文言や順位のテストを安定させる。Suisui Assistantの提案は別カードで扱い、おすすめ3件の初期表示をブロックしない。

### 6.3 今日やること

1行に次を表示する。

- 完了トグル
- タスク名
- プロジェクトまたはタグ
- 優先度
- 予定時刻
- Focus開始または詳細表示アクション

Wideでは列を揃え、Compactではタスク名を主情報、プロジェクト・優先度・時刻を副情報として折り返す。既存のタスク完了、選択、Schedule下書き、Reminder下書きのActionは`TodayFeatureViewModel`経由を維持する。

### 6.4 今週の予定

既存`ProjectBoardScheduleReadModel.weeklyCockpit`をToday向けに投影し、日付ごとに予定時刻、タイトル、長さを表示する。「すべての予定を表示」はScheduleへ遷移し、Today内で別の予定ストアを持たない。

### 6.5 要確認

`today.png`に合わせ、1枚のカード内を次の2グループに分ける。

1. レビュー依頼
   - Assistant Queue
   - Daily Planning Review
   - Catch Up / Missed Task Review
2. 外部連携の変更
   - Google Calendarの追加・変更・取消件数
   - Slackの未読DM、選択会話の未読・自分宛mention

外部更新は概要と経過時間を表示し、詳細はGoogle CalendarまたはSlackを開く。Todayから承認、投稿、既読化、予定変更を行わない。

### 6.6 今日のワークロード

```text
plannedMinutes = scheduledMinutes + focusTaskBlockMinutes
capacityMinutes = Settingsの日次容量（既定480分）
ratio = plannedMinutes / capacityMinutes
```

- `scheduledMinutes`: 予定・会議の時間ブロック
- `focusTaskBlockMinutes`: タスクへ割り当てたFocus用時間ブロック
- Focusタイマーの実績時間は含めない
- 容量超過時も比率を切り捨てず、リングを満杯にして超過量を文言と警告アイコンで示す
- 予定がない場合は`0h / 8h`
- 容量はSettingsから1〜16時間、30分単位で変更可能にし、0分や負数を保存しない

外部Calendar読取が未導入の段階ではSuisuiのScheduleブロックだけで算出し、Calendar接続後は重複排除された外部予定を`scheduledMinutes`へ加える。SuisuiからGoogle Calendarへ同期した予定は、既存のidempotency対応またはイベント対応表で元のScheduleブロックと照合し、二重計上しない。対応を判定できない場合は、誤って負荷を増やさないよう外部予定側を集計から除外し、診断可能な非機密エラーとして扱う。

### 6.7 Focusタイマー

プリセットは25分、50分、90分と、1〜240分のカスタム時間を提供する。

```text
Idle → Running ⇄ Paused → Completed
  └────────── End ──────────→ Idle
```

永続レコード:

- 対象`taskID`（任意）
- 予定時間
- 停止までの累積経過時間
- 最後に開始・再開した日時
- 状態

設計ルール:

- 開始、一時停止、再開、終了、完了の遷移時だけ保存する。
- 画面の秒表示更新でストレージへ書き込まない。
- 再起動後のRunning復元は、保存日時と現在日時の差を累積時間へ加える。
- Macのスリープ時間も経過時間として扱う。
- システム時刻が過去へ戻った場合は負の差分を0へ丸める。
- 復元時に予定時間を超えていればCompletedとして表示する。
- 別タスクのセッション開始時は、既存セッションを終了する確認を出す。
- 完了してもタスク状態、Calendar、Reminderを変更しない。
- 通知権限や自動通知は本設計のスコープに含めない。

### 6.8 Suisui Assistant

既存のToday assistant contextを使い、短い提案と明示的なActionを表示する。自動実行や外部副作用は行わず、既存の承認・下書き境界を維持する。

## 7. データアーキテクチャ

### 7.1 原則

- `ProjectBoardDerivedReadModels`を真実のデータ源とする。
- Today専用の永続ストアへタスク・予定・レビューをコピーしない。
- ボード由来のSnapshot、ネットワーク由来のカード状態、秒単位のFocus状態を分離する。
- 1カードの更新でTodayルート全体を不必要に再構築しない。

### 7.2 ボード由来Snapshot

`TodayFeatureState`へ既存`ProjectBoardScheduleReadModel`を追加し、`TodayFeatureViewModel`の購読対象をTodayが実際に描画するSchedule値まで拡張する。

純粋な`TodayDashboardSnapshotBuilder`をSuisuiCoreへ追加する。

```swift
public struct TodayDashboardSnapshot: Equatable, Sendable {
    public var header: TodayDashboardHeaderSnapshot
    public var recommendations: [TodayRecommendation]
    public var tasks: [TodayTaskRowSnapshot]
    public var workload: TodayWorkloadSnapshot
    public var weeklySchedule: TodayWeeklyScheduleSnapshot
    public var review: TodayReviewSnapshot
    public var assistant: TodayAssistantRailContext
}
```

Builder入力:

- `TodayWorkflowSnapshot`
- `ProjectBoardScheduleReadModel`
- `MissedTaskReviewSummary`
- Assistant Queue / Daily Planning Reviewの要約
- プロジェクトタイトル参照
- 表示名
- 日次作業容量
- `now`と`Calendar`

Builderは副作用を持たず、同じ入力に同じ出力を返す。時刻依存は`Date()`を内部で直接呼ばず、引数で受け取る。

### 7.3 独立状態

| 状態所有者 | 責務 | 永続化 |
|---|---|---|
| `TodayFeatureViewModel` | ボード由来Snapshotと既存Action | 既存ProjectBoardストア |
| `TodayFocusSessionStore` | Focus状態機械と復元 | 遷移時のみローカル保存 |
| `TodayWeatherModel` | 権限、取得中、成功、stale、失敗 | 最終成功結果の短期キャッシュ |
| `TodayExternalActivityModel` | Calendar/Slackの独立した読取状態を集約 | 同期カーソルと最小概要 |

`TodayExternalActivityModel`の内部ではCalendarとSlackに別々の状態、最終成功時刻、エラーを持たせる。一方が失敗しても、もう一方の成功値をstaleや失敗へ巻き込まない。

Weatherと外部更新は汎用`WidgetProvider`へ抽象化しない。テストで副作用を差し替えるための最小プロトコルだけを設ける。

### 7.4 View境界

```text
TodayDashboardView
├── TodayDashboardHeader
├── TodayRecommendationsSection
├── TodayTaskSection
├── TodayScheduleAndReviewSection
│   ├── TodayWeeklyScheduleCard
│   └── TodayReviewCard
│       └── TodayExternalActivityRows
└── TodayDashboardRail
    ├── TodayWorkloadCard
    ├── TodayFocusCard
    └── TodayAssistantCard
```

各Viewは値とAction closureを受け取り、ProjectBoard、Keychain、WeatherKit、外部HTTPクライアントへ直接アクセスしない。

## 8. Settingsとオンボーディング

### 8.1 新しい設定

- `profileDisplayName: String?`
- `dailyWorkCapacityMinutes: Int`（既定480）
- `weatherLocationPreference`
  - `.unset`
  - `.currentLocation`
  - `.manual(cityLabel, latitude, longitude)`

現在地モードでは取得した精密な位置履歴を保存しない。手動都市ではユーザーが選んだ都市ラベルと都市中心の座標だけを保存する。

### 8.2 フロー

既存の`FirstRunOnboardingStep`へ`todayPersonalization`を追加する。

```text
Welcome → Todayをパーソナライズ → AI設定 → 準備確認
```

- 表示名と天気位置はどちらも任意。
- 現在地を選んだ時点で、天気に使う理由を画面上に説明してCore Location権限を要求する。
- 手動都市を選んだ場合は位置権限を要求しない。
- `Try Suisui now`のサンプル作成経路でもPersonalizationを通る。
- `Skip Setup`はいつでも可能で、Todayは空設定の状態を正しく表示する。
- Settingsからオンボーディングを再実行した場合は保存値を初期表示し、明示保存まで変更しない。

Appleは位置情報を必要とする操作の直前に権限を要求することを推奨しているため、アプリ起動直後ではなく、Personalizationで「現在地を使用」を選んだ直後に要求する。

参考: [Requesting authorization to use location services](https://developer.apple.com/documentation/corelocation/requesting-authorization-to-use-location-services)

## 9. WeatherKit

### 9.1 取得内容

- 現在の状態
- 現在気温
- 当日の最高・最低気温
- 取得日時
- 表示用の位置ラベル

### 9.2 状態

- 未設定
- 権限確認中
- 読み込み中
- 最新データ
- キャッシュ表示（stale）
- 拒否・制限
- 取得失敗

前回成功値がある場合は、再取得中や一時的な失敗でも値を残して最終更新時刻を表示する。成功から30分以内はfresh、それ以降はstaleとして明示する。キャッシュに精密座標を含めない。

### 9.3 帰属

WeatherKitを公開アプリで使用する場合は帰属が必須である。ヘッダーの天気操作から開く詳細表示に、Apple Weatherマーク、サービス名、法的帰属ページへのリンクを表示する。画面幅が狭くても帰属へ到達可能にする。

参考:

- [WeatherKit](https://developer.apple.com/documentation/weatherkit/)
- [WeatherAttribution](https://developer.apple.com/documentation/weatherkit/weatherattribution)
- [WeatherKit entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.weatherkit)

## 10. Google Calendar更新

### 10.1 OAuth

- 既存の`calendar.events`資格情報は読取権限の上位集合として再利用する。
- Todayから新規接続する場合は`calendar.events.readonly`だけを要求する。
- 後から書込同期を有効化する場合に限り、明示説明の上で`calendar.events`へ増分認可する。
- 資格情報メタデータへ付与済みscopeを保持し、読取と書込の可否を別々に判定する。
- access tokenとrefresh tokenはKeychainへ保存する。

Googleは必要最小限のOAuth scopeを選ぶことを推奨している。

参考: [Choose Google Calendar API scopes](https://developers.google.com/workspace/calendar/api/auth)

### 10.2 増分同期

- 選択Calendarごとに初回full syncを行い、`nextSyncToken`を保存する。
- 初回取得結果は基準として扱い、すべてを「新着」にしない。
- 2回目以降は`syncToken`で追加・変更・取消を取得する。
- ページング中は同一query条件を維持する。
- `410 Gone`では該当Calendarのカーソルとキャッシュを破棄して基準を再作成する。
- 再基準化でも既存予定を大量の更新として表示しない。

参考: [Synchronize resources efficiently](https://developers.google.com/workspace/calendar/api/guides/sync)

### 10.3 保持データ

- Calendar ID
- Event ID
- 件名
- 開始・終了
- 状態
- 更新日時
- Google Calendarリンク

説明、参加者、添付、会議URLは保持しない。変更履歴はCalendarごとに最大20件か7日間の短い方を上限とする。UIは件名一覧ではなく、`today.png`に合わせて「予定が2件更新されました」のような件数概要を基本とする。

## 11. Slack更新

既存のSlack実装は下書き・投稿側の抽象であり、Todayの読取には新しい読み取り専用クライアントが必要となる。

### 11.1 読取範囲

- 接続はTodayまたはSettingsから明示的に開始する。
- ユーザーが選択したDM・会話だけをallowlistへ保存する。
- 必要な会話種別に対応する`:read`と`:history` scopeだけを要求する。
- 現在ユーザーIDを取得し、選択会話内の`<@USER_ID>`を自分宛mentionとして数える。
- DMではSlackが返す未読情報を優先する。
- Channelで未読情報が利用できない場合は`last_read`以降の取得可能な履歴から数え、推定値であることをUIに明示する。
- `search:read`によるワークスペース全体検索は初期実装で要求しない。

### 11.2 更新頻度

- Today表示時の前面更新
- 前回成功から十分な時間が経過した場合の低頻度更新
- 明示的な手動更新
- 連続手動更新はクライアント側で抑制
- `429`と`Retry-After`を厳守

Slackは配布形態により`conversations.history`を1分1回へ制限するため、全会話の常時巡回は行わない。

参考:

- [conversations.history](https://docs.slack.dev/reference/methods/conversations.history/)
- [conversations.info](https://docs.slack.dev/reference/methods/conversations.info/)
- [Conversation object](https://docs.slack.dev/reference/objects/conversation-object/)

### 11.3 表示と保持

UIはサービス名、会話名、未読・mention件数、最終更新時刻、Deep Linkだけを表示する。メッセージ本文はmention判定中のメモリだけで扱い、永続化しない。保存する件数概要は会話ごとに最新1件だけとする。Todayから投稿、リアクション、既読マーク更新を行わない。

## 12. エラー処理

各カードは次の状態を独立表示する。

| 状態 | 表示 |
|---|---|
| 未設定 | 設定または接続へ進むCTA |
| 読み込み中 | 前回値を残した小さな進捗表示 |
| 最新 | データと最終更新時刻 |
| stale | 前回値、stale表記、再試行 |
| 正常なゼロ件 | 「更新はありません」などの空状態 |
| 失敗 | 要約エラーと再試行。Today全体は維持 |

安全側へ閉じるルール:

- 読取scopeが不足しても書込scopeを自動要求しない。
- 読取失敗時に別サービスやローカル推測へ黙って切り替えない。
- 失敗を正常なゼロ件として表示しない。
- 期限切れトークンをログへ出さない。
- 接続解除時はトークン、scopeメタデータ、同期カーソル、キャッシュを一括削除する。

## 13. セキュリティとプライバシー

- OAuth token、WeatherKit資格情報、ユーザー位置、外部本文をログ・診断レポートへ含めない。
- OAuth tokenはKeychain、非秘密の同期カーソルは既存SQLiteまたは専用メタデータストアへ保存する。
- 位置情報は天気取得にだけ使用し、履歴を作らない。
- Calendarは必要最小限のイベントフィールドだけを保持する。
- Slack本文を永続化せず、allowlist外の会話を取得しない。
- Deep LinkはGoogle CalendarとSlackの許可済みURL scheme/hostだけを開く。
- 外部レスポンス由来テキストはSwiftUIのTextとして扱い、コマンドやMarkdownとして実行しない。
- Todayの外部更新経路にPOST、PUT、PATCH、DELETEを持たせない。テストダブルで書込呼出ゼロを固定する。

## 14. アクセシビリティとローカライズ

- 色だけで優先度、超過、stale、失敗を伝えない。
- 推奨カードとタスク行には、表示内容を重複しすぎない単一のアクセシビリティ要約を付ける。
- キーボードフォーカス順を視覚順に固定する。
- Compact再配置後もFocus順を更新する。
- 装飾アイコンはVoiceOverから隠し、意味のあるWeatherや状態アイコンにはラベルを付ける。
- Reduce Motionではリングやカードの不要なアニメーションを抑制する。
- 文字拡大でカード高を固定せず、縦方向へ成長させる。
- 日付、時間、気温、時間数はLocaleとCalendarに従う。
- `Suisui`、`Suisui Assistant`、`Learn Suisui`は翻訳キーの値でも`Suisui`表記を維持する。

## 15. 導入フェーズ

### Phase 1: Dashboard foundation

- `TodayDashboardSnapshot`とBuilder
- Wide/Compactレイアウト
- ヘッダー、決定論的おすすめ、タスク、週間予定、要確認、Assistant
- 表示名Settingと挨拶
- 既存Today Actionの維持

完了条件:

- Snapshotの純粋単体テスト
- 1448×1086で基準画像と同じ領域構成
- 1024×676で横スクロールなし
- 全既存Swiftテスト通過

### Phase 2: Focus / Workload

- 日次容量Setting
- 予定時間集計とカテゴリ分解
- Focus状態機械、永続化、再起動復元

完了条件:

- Clockを注入した境界テスト
- スリープ相当、時刻逆行、再起動後完了のテスト
- Focus操作がタスク・Calendarを変更しないテスト

### Phase 3: Weather / Onboarding

- Personalization step
- Core Location許可と手動都市
- WeatherKit、キャッシュ、帰属

完了条件:

- 未決定、許可、拒否、制限、オフライン、staleのテスト
- 位置履歴と機密ログがないこと
- WeatherKit entitlementと配布設定のドキュメント

### Phase 4: Calendar / Slack feed

- Calendar read-only OAuthとscope昇格
- Calendar増分同期
- Slack read-only OAuth、allowlist、レート制御
- 要確認カードへの外部更新行

完了条件:

- Calendar初回基準、増分、ページング、410再基準化のテスト
- Slack scope、allowlist、mention、未読、429のテスト
- 書込API呼出ゼロの統合テスト
- 接続解除時の完全削除テスト

## 16. TDDと検証

各フェーズはRED → GREEN → REFACTORで進める。

### 16.1 単体テスト

- `TodayDashboardSnapshotBuilderTests`
- おすすめ順位とフォールバック
- Workload分数・容量超過・ゼロ容量防止
- Focus状態遷移・復元
- Onboarding遷移・スキップ・再実行
- Weather状態とキャッシュ
- Calendar同期カーソル
- Slack allowlist・mention・rate limit

### 16.2 統合テスト

- `ProjectBoardDerivedReadModels`更新からToday Snapshot反映まで
- Settings保存から挨拶・容量・位置設定反映まで
- Keychain接続・解除とメタデータ削除
- 外部読取クライアントが書込HTTP methodを生成しないこと

### 16.3 Visual evidence

最低限、次の組み合わせをCI evidenceとして保存する。

| サイズ | Appearance | Locale |
|---|---|---|
| 1448×1086 | Light / Dark / System | ja / en |
| 1024×676 | Light / Dark | ja / en |

UI evidence modeでは日付、タスク、天気、外部更新、Focus残時間を固定fixtureにし、動的データで差分が揺れないようにする。

確認項目:

- `today.png`と同じ主要領域、順序、比率
- 文字切れ、カード重なり、不要な横スクロールがない
- 右レールがCompactで下部へ移動する
- Light/Dark/Systemでsemantic colorが成立する
- キーボード、VoiceOver、Reduce Motion
- 全ロケールで`Suisui`表記を維持

### 16.4 最終ゲート

- focused tests
- 全Swiftテスト
- release build
- `script/build_and_run.sh --verify`による自動runtime smoke
- visual evidence
- アクセシビリティ確認
- secret・機密ログ・危険なURL処理のセキュリティレビュー
- Hosted CIの全check
- 未解決review threadが0件

自動runtime smokeは通常利用のdogfoodingとは区別し、必要に応じて手動操作確認も記録する。

## 17. OSSとして必要なドキュメント

- WeatherKit capabilityとentitlementの設定方法
- macOS位置情報usage description
- Google OAuth client、read-only scope、write scope昇格
- Slack app作成、必要scope、redirect URI、allowlist、rate limit
- 秘密値をコミットしない`.env.example`または設定例
- 外部サービス未設定でもTodayを利用できること
- プライバシー上保持する情報・保持しない情報

ローカルbrainstorming成果物である`.superpowers/`はリポジトリへ含めず、`.gitignore`で除外する。

## 18. 受け入れ基準

1. 1448×1086で、ヘッダー、おすすめ3件、今日やること、今週の予定、要確認、Workload、Focus、Suisui Assistantが`today.png`と同じ階層で表示される。
2. Compactでは右レールがメイン下部へ移動し、横スクロールがない。
3. 表示名は初回オンボーディングで保存でき、Settingsで変更でき、空の場合も自然な挨拶になる。
4. Workloadは予定時間と日次容量から算出し、Focus実績を混ぜない。
5. Focusは再起動後に復元し、完了してもタスクや外部サービスを変更しない。
6. Weatherは現在地または手動都市で動作し、拒否・オフラインでもToday全体を止めず、必要な帰属を表示する。
7. Calendarは初回基準と増分変更を区別し、Todayから書き込まない。
8. Slackはallowlist内だけを読み、投稿・既読化を行わず、レート制限に従う。
9. 外部サービスの失敗は該当カード内に限定され、失敗をゼロ件として隠さない。
10. OAuth token、位置履歴、外部本文がログや不要な永続ストレージへ残らない。
11. 日英、Light/Dark/System、キーボード、VoiceOverで利用できる。
12. プロダクト名が全表示で`Suisui`のまま維持される。
