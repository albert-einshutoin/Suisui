# Mac用 音声ベースAIタスク・スケジュール管理アプリ 仕様書

作成日: 2026-06-16  
対象: Mac用アプリ / 個人プロジェクト管理 / 音声ファースト / 多数MCP内包 / BYOK型AI連携

---

## 1. プロダクト概要

### 仮称
- Suisui
- WorkPilot
- VoicePM
- PlanDock
- MCPilot

本仕様では仮称を **Suisui** とする。

### 一文コンセプト
**話すだけで、予定・タスク・通知・成果物を作成するMac常駐の個人用AI PMアプリ。**

### 価値仮説
個人開発者、企画職、PdM、副業ワーカー、ライター、研究者、登壇者などは、複数の個人プロジェクトを抱えながら、タスク分解、期日管理、通知設定、成果物作成、メール/連絡文作成を手作業で行っている。  
Suisuiは、音声入力からAIが意図を構造化し、MCP経由でMac上のカレンダー、リマインダー、通知、ファイル、Knowledge Frameなどを操作することで、作業の初動と納期管理を自動化する。

長期的には、Suisui は iOS / Web / macOS からアクセスできる会話ベースのタスク管理&自動化ツールへ拡張する。詳細は `docs/product/multiplatform-automation.md` を正とし、macOS alpha はその最初の実行面として扱う。

プロダクト順序は `docs/product/roadmap.md` を正とする。初期は個人向けの最小MVPとして、音声からタスク・予定・通知・承認待ちを作り、忘れを防ぐ local-first な voice-task loop を成立させる。その後のMVPで、Business向けの組織管理、KnowledgeBase/RAG、QZT evidence、Memory Pager、監査、課金を追加する。

### コア体験
```text
Option + Space
↓
「6月末までにQZTの記事を公開したい。いつもの技術記事フレームでタスクを作って、期限前と遅延時に通知して」
↓
AIが計画を生成
↓
確認画面
↓
Project / Task / Calendar / Reminder / Notification / Markdown files を作成
↓
期限前・期限超過を自動通知
```

---

## 2. ポジショニング

### ユーザーに見せる説明
**Suisuiは、Macに常駐する音声ファーストのAIタスク・スケジュール管理アプリです。話すだけでタスク、予定、通知、プロジェクト、成果物の下地を作成し、締切前や期限超過時に知らせてくれます。**

### 内部的な説明
STT → LLM → Intent Plan → MCP Host → Built-in MCP Servers → Data Creation という流れで、Mac上と外部サービス上の仕事データを作成・監視する。

### 競合との差別化
- 通常のタスク管理: ユーザーがタスクを手入力する
- AIスケジューラー: 入力済みタスクをカレンダーに配置する
- 音声入力アプリ: 音声をテキスト化する
- 汎用AIエージェント: 何でもできるが、納期・タスク・予定に特化していない

Suisuiは、**音声を仕事データへ変換し、納期まで監視する**ことに特化する。

---

## 3. BRD: Business Requirements Document

### 3.1 ビジネス目的
1. 個人プロジェクト管理における「タスク化・予定化・通知化」の摩擦を減らす。
2. Mac上で完結するlocal-firstなAI PM体験を提供する。
3. AI APIコストをプロダクト側で抱えず、ユーザーBYOK方式で低コストに運営する。
4. MCP内包アプリとして、将来的に外部連携やMCPマーケットプレイス展開へ拡張する。

### 3.2 対象ユーザー
#### Primary Persona: 個人開発者 / OSS作者
- GitHub、Markdown、ローカルディレクトリ、カレンダーを使う
- 技術記事、リリース、登壇、個人プロジェクトの締切がある
- 音声で雑に指示してタスク化したい

#### Secondary Persona: PdM / 企画職 / 副業ワーカー
- 企画書、プレゼン、提案書、MTG準備が多い
- 関係者連絡、期限、資料作成を忘れやすい
- カレンダー/リマインダー/メール下書きへの変換を自動化したい

#### Future Persona: チームリーダー / 小規模チーム
- 個人単位の延長で、チームプロジェクトのタスク・通知・連絡へ拡張したい

### 3.3 解決する課題
- タスク化する前に忘れる
- 締切をカレンダーや通知に登録し忘れる
- 作業開始が遅れる
- 成果物のファイル作成や雛形作成が面倒
- 期限超過に気づくのが遅い
- 過去の作業フレームを再利用できない
- AIチャットで計画を作っても、実際の予定・通知・ファイルに反映されない

### 3.4 成功指標
#### Activation
- 初回起動後、ユーザーが最初の音声コマンドを実行する
- 最初のプロジェクトが作成される
- Apple Calendar / Reminders / Notification のいずれかが接続される

#### Engagement
- 週あたりの音声コマンド数
- 作成されたタスク数
- 作成された通知数
- 期限超過検知数
- プロジェクトあたりの成果物作成数

#### Retention
- 7日後/30日後の継続利用
- 期限通知からの再訪率
- 「今日のタスク」閲覧頻度

#### Business
- Free → Pro転換率
- BYOK設定完了率
- Pro継続率
- サポート問い合わせ率

### 3.5 収益モデル
#### 推奨: BYOK + アプリ課金
AI API費用はユーザー負担。アプリは機能と利便性に課金する。

#### Pricing案
最新の価格案は `docs/product/pricing.md` を正とする。初期はローカルアプリを Free で広げ、クラウドコストと安全な遠隔実行が発生する Sync / Cloud Relay / Harness を有料化する。

| Plan | 価格案 | 内容 |
|---|---:|---|
| Free | 無料 | ローカル基本機能、BYOK、Suisui中継型ツール実行、MCP登録/診断 |
| Sync | $5/月 or $48/年 | iOS/Web/macOS デバイス間同期、E2EE、履歴、削除復元 |
| Pro | $10/月 or $96/年 | Sync、Cloud Relay、PC未起動時のタスク作成、Hosted MCP、docs-scoped automation、Suisui Harness |
| Team | 将来 | 共有プロジェクト、管理者機能、監査ログ、チーム連携 |

初期の訴求は **「Macが起動していなくてもタスクを作成できる」** を Pro の中核価値にする。

### 3.6 配布方針
- 初期: 公式サイト配布のMacアプリ
- 将来: App Store版、Setapp、開発者向けCLI版、MCP連携版

### 3.7 ビジネス上の前提
- ユーザーはAPIキーを設定する心理的ハードルを許容する
- Macユーザーはlocal-first/privacy-firstに価値を感じる
- 音声起点で予定・タスクを作る体験は十分に差別化できる
- MCPは内部実装として使い、ユーザー価値は「話すだけで仕事データ作成」として訴求する

### 3.8 主要リスク
| リスク | 影響 | 対策 |
|---|---|---|
| 機能肥大化 | MVPが完成しない | 初期はApple Calendar/Reminders/Notifications/Filesに限定 |
| BYOK設定が難しい | 初回離脱 | 初回ガイド、OpenRouter/Ollama対応、サンプルモード |
| 誤実行 | 信頼低下 | 実行前確認、権限レベル、監査ログ |
| MCPメンテ負荷 | 開発コスト増 | Built-in MCPを少数から開始 |
| 外部OAuth審査 | リリース遅延 | Gmail/Slack/Driveは後続扱い |
| 音声認識精度 | 体験劣化 | 手動編集、確認画面、テキスト入力併用 |

---

## 4. PRD: Product Requirements Document

### 4.1 プロダクトゴール
1. 音声から予定・タスク・通知を作成できる。
2. 個人プロジェクトを作成し、締切とマイルストーンを管理できる。
3. 期限前・期限超過を自動通知できる。
4. Knowledge Frameから作業雛形を作れる。
5. ローカルファイルとして成果物の下地を作れる。
6. 全操作はユーザー確認・権限管理・監査ログを通す。

### 4.2 MVPスコープ
#### Must Have
- Macメニューバー常駐
- グローバルショートカットで音声入力
- STTによる文字起こし
- LLMによる意図構造化
- 確認画面
- プロジェクト作成
- タスク作成
- Apple Calendar予定作成
- Apple Reminders作成
- macOS通知作成
- 期限前/期限超過通知
- Markdown成果物作成
- Knowledge Frameの手動登録・検索
- APIキー設定
- Keychain保存
- 操作ログ

#### Should Have
- タスク一括生成
- 期限から逆算したマイルストーン生成
- 今日/今週/期限超過ビュー
- テキスト入力モード
- 生成計画の編集
- 通知ルールのカスタマイズ
- ローカルディレクトリ監視
- Gitステータスのread-only確認

#### Could Have
- GitHub Issue作成
- Google Calendar連携
- Gmail下書き作成
- Slack通知下書き
- Obsidian/Notion連携
- TTS読み上げ
- Ollama対応
- MCP追加プラグイン

#### Won't Have in MVP
- WeKnora内包
- 本格RAG基盤
- Agentic Search
- メール自動送信
- Slack自動投稿
- ファイル削除/上書きの自動実行
- チーム管理
- 管理者権限/RBAC
- Web同期

---

## 5. 機能要件

### FR-001: 初回オンボーディング
ユーザーは初回起動時に以下を設定できる。
- AI Provider
- API Key
- STT方式
- 通知許可
- Calendar/Reminders権限
- デフォルト保存先ディレクトリ
- タイムゾーン

受け入れ条件:
- API KeyはKeychainに保存される
- 権限未許可の場合は該当機能を無効化して案内する
- テストコマンドを実行できる

### FR-002: グローバル音声入力
ユーザーはショートカットで音声入力を開始できる。

入力例:
```text
来週金曜までに提案書を作るタスクを作って。3日前に通知して。
```

受け入れ条件:
- 音声がテキスト化される
- テキストは実行前に編集できる
- 失敗時はテキスト入力にフォールバックできる

### FR-003: 意図構造化
LLMはユーザー入力をAction Planへ変換する。

Action Plan例:
```json
{
  "summary": "QZT記事公開プロジェクトを作成",
  "actions": [
    {
      "type": "project.create",
      "title": "QZT記事公開",
      "deadline": "2026-06-30"
    },
    {
      "type": "task.bulk_create",
      "items": [
        {"title": "構成案作成", "due": "2026-06-20"},
        {"title": "初稿作成", "due": "2026-06-24"},
        {"title": "レビュー", "due": "2026-06-27"}
      ]
    },
    {
      "type": "notification.schedule",
      "rule": "T-7,T-3,T-1,overdue_daily"
    }
  ]
}
```

受け入れ条件:
- 曖昧な日時は確認画面で明示する
- 実行対象と作成データをユーザーに表示する
- 危険操作は自動実行されない

### FR-004: 実行前確認画面
Action Planを実行前に確認できる。

表示項目:
- 作成されるプロジェクト
- 作成されるタスク
- 作成される予定
- 作成される通知
- 作成されるファイル
- 必要な権限
- 実行先

受け入れ条件:
- ユーザーは個別に有効/無効を切り替えられる
- 実行前に日時・タイトル・本文を編集できる
- キャンセルできる

### FR-005: プロジェクト作成
ユーザーは音声またはテキストからプロジェクトを作成できる。

プロジェクト属性:
- title
- description
- deadline
- status
- priority
- tags
- workspace_path
- source_command
- created_at
- updated_at

### FR-006: タスク作成
タスクは単体または一括で作成できる。

タスク属性:
- title
- description
- due_at
- status
- priority
- project_id
- source
- external_ref
- reminder_rule

### FR-007: Apple Calendar連携
ユーザー許可後、予定を作成できる。

対応:
- 締切イベント
- 作業ブロック
- MTG準備予定
- レビュー予定

### FR-008: Apple Reminders連携
ユーザー許可後、リマインダーを作成できる。

対応:
- タスク単位のリマインダー
- プロジェクト単位のリスト作成
- 完了同期

### FR-009: macOS通知
アプリは期限前・期限超過通知を出せる。

通知種別:
- T-14
- T-7
- T-3
- T-1
- 当日
- 期限超過
- 長期間更新なし

### FR-010: 成果物ファイル作成
プロジェクトに紐づく成果物ファイルを作成できる。

例:
```text
/projects/qzt-article/
  outline.md
  article.md
  checklist.md
  references.md
  social-post.md
```

### FR-011: Knowledge Frame
過去の作業パターンやチェックリストをFrameとして保存できる。

Frame例:
```yaml
name: 技術記事フレーム
type: frame
triggers:
  - 技術記事
  - OSS紹介
  - README解説
deliverables:
  - outline.md
  - article.md
  - examples/
  - benchmark.md
  - social-post.md
default_tasks:
  - 読者定義
  - 構成案作成
  - 技術検証
  - 初稿作成
  - 図解作成
  - レビュー
  - 公開準備
deadline_rules:
  - T-14: 構成案がある
  - T-7: 初稿がある
  - T-3: レビュー依頼済み
  - T-1: 公開準備完了
```

### FR-012: 期限監視
アプリはローカルDB内のプロジェクト/タスクを定期チェックする。

検知:
- 今日締切
- 明日締切
- 3日以内
- 1週間以内
- 期限超過
- 未完了タスクあり
- 成果物未作成
- ファイル更新停止

### FR-013: メール下書き文生成
MVPでは外部送信せず、メール文面を生成し、コピーまたはmailto起動までに留める。

後続でGmail draft作成に対応する。

### FR-014: 操作ログ / 監査ログ
全てのAI実行はログに残る。

記録:
- 入力テキスト
- 生成Action Plan
- 実行MCP
- 実行結果
- エラー
- ユーザー承認状態

---

## 6. 非機能要件

### NFR-001: Privacy / Local-first
- API KeyはKeychainに保存
- ローカルファイル内容はユーザー承認なしに外部送信しない
- LLMに送る文脈は確認可能にする
- 操作ログはローカル保存

### NFR-002: Safety
- 書き込み操作は確認画面を必須にする
- 危険操作はMVPで実装しない
- 実行権限をRead/Draft/Write/Dangerに分類する

### NFR-003: Performance
- メニューバーUIは即時表示
- 音声入力から確認画面までの体感を軽くする
- ローカルDB操作はSQLiteで高速にする
- 外部連携は非同期にする

### NFR-004: Reliability
- LLM出力はJSON Schemaで検証する
- 実行失敗時はロールバックまたは再実行可能にする
- ネットワーク失敗時はローカルタスクとして保存する

### NFR-005: Extensibility
- MCP serverをモジュール化
- 外部MCP serverを後続で追加可能にする
- Action Planはツール依存ではなく抽象操作で表現する

---

## 7. MCP仕様

### 7.1 Built-in MCP Servers

| MCP Server | MVP | 説明 |
|---|---:|---|
| project-mcp | 必須 | プロジェクト作成・更新・一覧 |
| task-mcp | 必須 | タスク作成・更新・完了 |
| notification-mcp | 必須 | macOS通知作成・キャンセル |
| calendar-mcp | 必須 | Apple Calendar予定作成 |
| reminders-mcp | 必須 | Apple Reminders作成 |
| filesystem-mcp | 必須 | ディレクトリ/Markdown作成 |
| knowledge-frame-mcp | 必須 | Frame検索・作成・更新 |
| mail-draft-mcp | 推奨 | メール文面生成、コピー、mailto |
| git-mcp | 後続 | Git status/read-only scan |
| github-mcp | 後続 | Issue/PR/Release |
| google-calendar-mcp | 後続 | Google Calendar |
| gmail-mcp | 後続 | Gmail draft |
| slack-mcp | 後続 | Slack draft/post with approval |

### 7.2 Tool例

#### project-mcp
- project.create
- project.update
- project.list
- project.get
- project.complete

#### task-mcp
- task.create
- task.bulk_create
- task.update
- task.complete
- task.list_due
- task.list_overdue

#### notification-mcp
- notification.schedule
- notification.cancel
- notification.list
- notification.schedule_overdue_rule

#### filesystem-mcp
- filesystem.create_directory
- filesystem.create_markdown_file
- filesystem.create_artifacts_from_frame
- filesystem.scan_project_artifacts

#### knowledge-frame-mcp
- frame.search
- frame.list
- frame.get
- frame.create
- frame.update

---

## 8. データモデル

### Project
```ts
type Project = {
  id: string
  title: string
  description?: string
  status: 'active' | 'paused' | 'completed' | 'archived'
  priority: 'low' | 'medium' | 'high'
  deadline?: string
  workspacePath?: string
  tags: string[]
  sourceCommand?: string
  createdAt: string
  updatedAt: string
}
```

### Task
```ts
type Task = {
  id: string
  projectId?: string
  title: string
  description?: string
  status: 'todo' | 'doing' | 'done' | 'blocked'
  dueAt?: string
  priority: 'low' | 'medium' | 'high'
  externalRefs: ExternalRef[]
  createdAt: string
  updatedAt: string
}
```

### DeadlineRule
```ts
type DeadlineRule = {
  id: string
  projectId?: string
  taskId?: string
  ruleType: 'T-14' | 'T-7' | 'T-3' | 'T-1' | 'day_of' | 'overdue_daily' | 'custom'
  notifyAt?: string
  enabled: boolean
}
```

### KnowledgeFrame
```ts
type KnowledgeFrame = {
  id: string
  name: string
  type: 'frame' | 'checklist' | 'template' | 'deadline_rule'
  triggers: string[]
  body: string
  deliverables: string[]
  defaultTasks: string[]
  deadlineRules: string[]
  createdAt: string
  updatedAt: string
}
```

### ActionPlan
```ts
type ActionPlan = {
  id: string
  userInput: string
  summary: string
  actions: Action[]
  riskLevel: 'read' | 'draft' | 'write' | 'danger'
  requiresApproval: boolean
}
```

---

## 9. 画面 / ページ設計

### 9.1 Menu Bar Panel
目的: すぐに今日の状態を確認し、音声入力を開始する。

表示:
- Voice Commandボタン
- 今日のタスク
- 期限超過
- 今週の締切
- 最近のプロジェクト
- Quick Add

### 9.2 Voice Capture Overlay
目的: ショートカットから音声入力する。

表示:
- 録音状態
- 文字起こし中状態
- テキスト編集欄
- 実行ボタン
- キャンセル

### 9.3 Action Review Screen
目的: AIが作成する予定・タスク・通知・ファイルを確認する。

表示:
- AI summary
- 作成予定一覧
- 編集可能なタスク/予定/通知
- 実行先
- リスク表示
- 実行/キャンセル

### 9.4 Today Page
目的: 今日やるべきことに集中する。

表示:
- 今日締切
- 今日予定
- 期限超過
- 次にやるべきタスク
- AI提案

### 9.5 Projects Page
目的: 個人プロジェクト一覧。

表示:
- Active projects
- Deadline順
- 遅延あり
- タグフィルタ
- 新規作成

### 9.6 Project Detail Page
目的: プロジェクト単位の管理。

表示:
- 概要
- 締切
- 進捗
- タスク一覧
- マイルストーン
- 通知ルール
- 成果物ファイル
- 実行ログ

### 9.7 Tasks Page
目的: タスク全体管理。

表示:
- Inbox
- Today
- Upcoming
- Overdue
- Project別

### 9.8 Calendar / Deadlines Page
目的: 締切と予定を俯瞰する。

表示:
- 週/月ビュー
- 締切一覧
- 通知予定
- 期限超過

### 9.9 Knowledge Frames Page
目的: 作業フレームの登録・編集。

表示:
- フレーム一覧
- 検索
- YAML/Markdown編集
- 適用例

### 9.10 MCP / Integrations Page
目的: 内包MCPと外部連携の管理。

表示:
- 有効/無効
- 権限状態
- テスト実行
- ログ

### 9.11 Settings Page
目的: 基本設定。

表示:
- AI Provider
- API Key
- STT/TTS
- 通知設定
- デフォルト保存先
- グローバルショートカット
- Privacy
- Logs

---

## 10. UXフロー

### Flow A: 音声でタスク作成
```text
Shortcut → Voice Overlay → STT → Text Edit → LLM Plan → Review → Execute → Task/Reminder/Notification作成
```

### Flow B: プロジェクト作成
```text
Voice/Text → Deadline抽出 → Frame検索 → Tasks生成 → Artifacts生成 → Notifications生成 → Review → Execute
```

### Flow C: 期限超過通知
```text
Scheduler → DB scan → overdue検知 → Notification → User opens Today → AI suggests next step
```

### Flow D: Knowledge Frame適用
```text
User command → Frame search → Frame候補表示 → Apply → Task/Artifact生成
```

---

## 11. デザイン方針

### Design Principles
1. Mac-native: SwiftUIらしい軽量UI
2. Voice-first: 操作の起点はショートカットと音声
3. Review-before-write: AIが勝手に実行しない
4. Deadline-aware: 常に締切と遅延が見える
5. Local-first: ユーザーのMac上に仕事データを置く
6. Calm productivity: 通知はうるさすぎず、必要なタイミングに絞る

### Information Architecture
```text
Menu Bar
  ├─ Voice Command
  ├─ Today
  ├─ Projects
  ├─ Tasks
  ├─ Deadlines
  ├─ Knowledge Frames
  ├─ MCP / Integrations
  └─ Settings
```

### Tone
- 命令的ではなく、秘書/PMのように提案する
- 「未完了です」ではなく「次はこれを進めると良さそうです」
- 期限超過は明確に伝える

### 通知文例
```text
QZT記事公開が3日後です
未完了: 初稿作成、レビュー依頼
次のおすすめ: article.mdを開いて初稿を完成させる
```

```text
提案書作成が1日遅れています
今日やるなら: 章立て作成 → 初稿作成 の順がおすすめです
```

### ワイヤーフレーム: Menu Bar Panel
```text
┌──────────────────────────────┐
│ Suisui                       │
│ [🎙 話して追加]              │
├──────────────────────────────┤
│ Today                        │
│  □ QZT記事 初稿作成          │
│  □ 企画書レビュー            │
├──────────────────────────────┤
│ Overdue                      │
│  ⚠ 提案書作成 +1日           │
├──────────────────────────────┤
│ This Week                    │
│  6/20 登壇資料構成           │
│  6/23 QZT記事レビュー        │
├──────────────────────────────┤
│ Projects / Settings          │
└──────────────────────────────┘
```

### ワイヤーフレーム: Action Review
```text
┌────────────────────────────────────────┐
│ 作成前の確認                            │
├────────────────────────────────────────┤
│ 「QZT記事公開」プロジェクトを作成します │
│ 締切: 2026-06-30                        │
├────────────────────────────────────────┤
│ 作成されるもの                          │
│ ☑ Project: QZT記事公開                  │
│ ☑ Tasks: 8件                            │
│ ☑ Calendar: 締切イベント                │
│ ☑ Reminders: 8件                        │
│ ☑ Notifications: T-7/T-3/T-1/Overdue    │
│ ☑ Files: outline.md, article.md         │
├────────────────────────────────────────┤
│ [編集] [実行] [キャンセル]              │
└────────────────────────────────────────┘
```

---

## 12. 権限・安全設計

### Execution Levels
| Level | 内容 | 例 | MVP |
|---|---|---|---:|
| Read | 読み取り | タスク一覧、カレンダー参照 | ○ |
| Draft | 下書き | メール文、成果物草案 | ○ |
| Write | 書き込み | 通知作成、予定作成、ファイル作成 | ○、確認必須 |
| Danger | 危険操作 | 送信、削除、上書き、Git push | × |

### 確認必須操作
- Calendar作成
- Reminders作成
- 通知スケジュール作成
- ファイル作成
- メール下書き作成
- 外部サービスへの書き込み

### MVPで禁止する操作
- メール送信
- Slack自動投稿
- ファイル削除
- 既存ファイル上書き
- Git push
- Calendar/Reminder削除

---

## 13. 技術構成案

### 推奨アーキテクチャ
```text
SwiftUI Mac App
  ├─ Menu Bar UI
  ├─ Voice Overlay
  ├─ Review UI
  ├─ Settings UI
  ├─ Rust/TS Core
  │    ├─ Action Planner
  │    ├─ MCP Host
  │    ├─ Scheduler
  │    ├─ Local DB
  │    └─ Permission Layer
  ├─ Built-in MCP Servers
  ├─ STT Engine
  └─ Notification/Calendar/Reminder Adapters
```

### Core技術
| 領域 | 推奨 |
|---|---|
| Mac UI | SwiftUI |
| Core | Rust or TypeScript |
| DB | SQLite |
| API Key | macOS Keychain |
| STT | whisper.cpp or macOS Dictation-like integration |
| TTS | macOS built-in TTS initially |
| Notifications | UserNotifications |
| Calendar/Reminders | EventKit |
| MCP transport | stdio local first |
| Logs | SQLite + local JSONL |

---

## 14. リリースプラン

### Phase 0: Prototype
- テキスト入力
- LLM構造化
- ローカルDBへProject/Task作成
- 確認画面

### Phase 1: MVP
- メニューバーアプリ
- 音声入力
- Apple Calendar/Reminders
- macOS通知
- Knowledge Frame
- Markdown成果物作成
- 期限超過通知

### Phase 2: Developer Workflow
- Git read-only scan
- GitHub Issue作成
- Markdown/README生成
- CLI同梱

### Phase 3: External Connectors
- Google Calendar
- Gmail draft
- Slack draft/post with approval
- Google Drive
- Notion

### Phase 4: Advanced PM
- 成果物進捗監視
- プロジェクト健康度
- 繰り返しルール
- 複数AI Provider最適化
- 外部MCP追加

### Phase 5: Business Expansion
- Team plan
- Cloud sync
- Shared workspace
- MCP marketplace

---

## 15. 初期バックログ

### P0
- メニューバー常駐
- API Key設定
- 音声/テキスト入力
- LLM Action Plan生成
- Review画面
- Local Project DB
- Task作成
- macOS通知作成
- Apple Reminders作成
- Apple Calendar作成
- Deadline Watcher

### P1
- Knowledge Frame CRUD
- Frameからタスク生成
- Markdown成果物生成
- Today/Overdue/Projects画面
- 操作ログ
- テキスト編集

### P2
- Git scan
- GitHub Issue作成
- Google Calendar
- Mail draft
- Slack draft
- テンプレート共有

---

## 16. サンプルユースケース

### Use Case 1: 記事プロジェクト作成
入力:
```text
6月末までにQZTの記事を公開したい。技術記事フレームでタスクを作って、期限前に通知して。
```

作成:
- Project: QZT記事公開
- Tasks: 読者定義、構成案、技術検証、初稿、レビュー、公開準備
- Files: outline.md, article.md, references.md, social-post.md
- Calendar: 6/30 締切
- Reminders: 各タスク
- Notifications: T-7/T-3/T-1/overdue

### Use Case 2: MTG準備
入力:
```text
来週火曜の定例MTG、前日にアジェンダ確認、当日朝にリマインドして。
```

作成:
- Calendar eventまたは既存イベント紐付け
- Reminder: アジェンダ確認
- Notification: 前日/当日朝

### Use Case 3: メール下書き
入力:
```text
佐藤さんに資料レビュー依頼のメールを書いて。締切は金曜で、丁寧だけど短め。
```

作成:
- メール文面
- クリップボードコピー
- mailto起動
- 関連タスク作成

---

## 17. MVPの定義

初期MVPは、個人ユーザー向けの最小MVPとして成立させる。Business向けの組織、RBAC、KnowledgeBase本番連携、QZT evidence、Memory Pager、監査エクスポートは後続MVPの対象であり、初期MVPの完了条件にしない。

Personal MVPとして成立する条件:

1. ユーザーが音声で依頼できる
2. AIが予定・タスク・通知に構造化できる
3. 実行前に確認できる
4. Apple Calendar/Reminders/macOS通知に実データを作れる
5. 締切超過を検知して通知できる
6. Knowledge Frameからタスク雛形を作れる
7. Markdown成果物を作れる
8. 全ての操作がローカルに記録される

---

## 18. 一旦のプロダクト判断

初期プロダクトは以下に絞る。

**作るもの:**
Mac常駐の音声ベースAIタスク・スケジュール管理アプリ。

**やること:**
音声からProject/Task/Calendar/Reminder/Notification/Fileを作成し、期限前・期限超過を通知する。

**やらないこと:**
本格RAG、WeKnora内包、Agentic Search、チーム管理、Business管理画面、KnowledgeBase本番連携、QZT evidence storage、Memory Pager本番文脈生成、メール送信、Slack自動投稿、大量外部SaaS連携。

**勝ち筋:**
「AIタスク管理」ではなく、**話すだけで仕事データを作り、納期まで見張るMac用個人PM**として出す。
