# SoloPM Tech Stack

Last updated: 2026-06-17  
Verified against public docs: 2026-06-17  
Target: macOS native app / local-first / BYOK / voice-first personal PM

---

## 0. 最新性チェック結果

結論として、前回の技術選定は **MVPとしては概ね最新かつ妥当**。ただし、2026年6月時点では以下のアップデートを反映する。

| 領域 | 旧方針 | 最新チェック後の判断 |
|---|---|---|
| Swift / Xcode | Swift 6 | **Xcode 26.5 stable + Swift 6 language mode / Swift compiler 6.3** を基準にする。Swift standalone toolchain は 6.3.2 が最新安定。Xcode 27 beta / Swift 6.4 は検証 branch 扱い |
| STT | whisper.cpp first | **SpeechAnalyzer / WhisperKit / whisper.cpp の3段構え**に変更。macOS 26+ では SpeechAnalyzer、Swift-native OSS では WhisperKit、低レイヤー/広互換では whisper.cpp |
| TTS | macOS 標準 TTS | そのまま採用。MVPでは AVSpeechSynthesizer が最軽量・低コスト |
| LLM API | OpenAI-compatible adapter | **OpenAI Responses API adapter first** に更新。OpenAI-compatible Chat Completions は OpenRouter / Ollama fallback として維持 |
| MCP | 2025-03-26 transport前提 | **MCP spec 2025-11-25** を基準にする。stdio / Streamable HTTP は維持。外部MCPは後続 |
| Knowledge | SQLite + FTS5 | そのまま採用。sqlite-vec はまだ later/experimental 扱い |
| Apple on-device LLM | 未記載 | **Foundation Models framework** を later に追加。macOS 26+ / Apple Intelligence availability 依存のためMVPコアにはしない |
| 配布 | Developer ID + Sparkle | そのまま採用。Xcode 27 beta / macOS 27 beta は本番基準にしない |

### Stable baseline

MVPの本番開発基準は以下。

```text
Build toolchain:
  Xcode 26.5 stable
  Swift language mode: Swift 6
  Swift compiler: Swift 6.3

Standalone Swift toolchain / CLI検証:
  Swift 6.3.2

Beta検証 branch:
  Xcode 27 beta
  Swift 6.4
  macOS 27 SDK
```

Xcode 27 beta / Swift 6.4 は最新ではあるが、MVP本番基準にしない。利用する場合は `beta/apple-intelligence` のような別branchで、Foundation Models / SpeechAnalyzer / LanguageModel protocol などの検証に限定する。


---

## 1. 技術選定の結論

SoloPM の MVP は、**Swift ネイティブ + OS ネイティブ機能 + 軽量 OSS** を中心に構成する。

目的は、AI エージェント基盤を大きく作ることではなく、以下の体験を最短で成立させること。

```text
話す
↓
STT
↓
LLM が Action Plan に構造化
↓
確認
↓
内蔵ツール / MCP 互換ツールで実行
↓
タスク・予定・通知・成果物を作成
↓
納期監視
```

MVP の基本方針は以下。

| 方針 | 判断 |
|---|---|
| Mac アプリ本体 | Xcode 26.5 stable + Swift 6 language mode + SwiftUI |
| AI 推論 | ユーザー BYOK。OpenAI Responses API adapter を先に実装し、OpenAI-compatible fallback を持つ |
| STT | SpeechAnalyzer / WhisperKit / whisper.cpp の3段構え |
| TTS | MVP は macOS 標準 TTS を使う |
| MCP | MVP は Swift 内蔵 Tool Registry。外部 MCP は MCP spec 2025-11-25 / stdio から後続対応 |
| DB | SQLite + FTS5 |
| Knowledge | 本格 RAG ではなく Knowledge Frame + FTS5 |
| ベクトル検索 | MVP では不要。後続で sqlite-vec を検討 |
| 通知 | UserNotifications |
| Calendar / Reminders | EventKit |
| API Key | macOS Keychain |
| ファイル監視 | FSEvents |
| 常駐 / 起動 | MenuBarExtra + SMAppService |
| 配布 | Developer ID + Notarization + Sparkle |

---

## 2. 選定原則

### 2.1 OS ネイティブを優先する

SoloPM は Mac 用アプリなので、macOS が既に持つ機能を最大限使う。

理由はコスト・安定性・配布サイズ・ユーザー信頼のすべてに効くため。

| 領域 | OS ネイティブ採用 | コストメリット |
|---|---|---|
| 通知 | UserNotifications | 通知サーバー不要 |
| カレンダー | EventKit | Google API なしでも予定作成可能 |
| リマインダー | EventKit | タスク DB を一から作り込まずに Apple Reminders 連携可能 |
| API Key | Keychain | 自前の秘密情報管理サーバー不要 |
| TTS | AVSpeechSynthesizer | TTS API コスト不要 |
| ファイル監視 | FSEvents | 常時ポーリング不要 |
| 起動時常駐 | SMAppService | 外部 daemon 管理不要 |
| メニューバー常駐 | MenuBarExtra | Electron/Tauri を避けられる |
| STT | SpeechAnalyzer later | macOS 26+ で追加STTコストを抑えられる |
| 軽量LLM | Foundation Models later | macOS 26+ で一部推論コストを抑えられる |

### 2.2 OSS は「高機能」より「小さくて組み込みやすい」を優先する

MVP で使う OSS は、以下の条件を満たすものに絞る。

```text
- Mac アプリに同梱しやすい
- サーバー不要
- 依存が少ない
- ライセンスが商用利用しやすい
- ユーザーのローカルデータを外に出さない
- 壊れてもプロダクト全体が止まらない
```

### 2.3 AI API コストは持たない

AI モデルは BYOK を前提にする。

```text
OpenAI API Key
OpenRouter API Key
Ollama local endpoint
Anthropic API Key later
Gemini API Key later
```

SoloPM 側が AI 推論コストを抱えないことで、Obsidian 型の無料・支援・高度機能課金モデルと相性が良くなる。

### 2.4 MVP では Agentic Search / 本格 RAG を避ける

MVP の価値は RAG 基盤ではなく、**音声から仕事データを作ること**。

そのため最初は以下で十分。

```text
Knowledge Frame
+ SQLite FTS5
+ LLM に必要な Frame だけ渡す
```

本格 RAG、WeKnora、OpenSearch、pgvector、Agentic Search は後続。

---

## 3. MVP アーキテクチャ

```text
SoloPM.app
├─ SwiftUI App
│  ├─ Menu Bar Panel
│  ├─ Voice Capture Overlay
│  ├─ Action Review Screen
│  ├─ Today / Projects / Settings
│  └─ Knowledge Frames Editor
│
├─ Core
│  ├─ STT Orchestrator
│  ├─ LLM Action Planner
│  ├─ Tool Registry
│  ├─ Permission Manager
│  ├─ Scheduler
│  ├─ Overdue Checker
│  └─ Audit Logger
│
├─ Built-in Tools
│  ├─ project.create / update / list
│  ├─ task.create / bulk_create / complete
│  ├─ calendar.create_event
│  ├─ reminders.create / bulk_create
│  ├─ notification.schedule / overdue_rule
│  ├─ filesystem.create_artifact
│  ├─ knowledge.search_frame
│  └─ maildraft.create_text
│
├─ Storage
│  ├─ SQLite
│  ├─ FTS5
│  ├─ Markdown / YAML Knowledge Frames
│  ├─ JSONL audit logs
│  └─ Keychain secrets
│
├─ Native macOS APIs
│  ├─ EventKit
│  ├─ UserNotifications
│  ├─ Keychain Services
│  ├─ AVFoundation / AVFAudio
│  ├─ FSEvents
│  ├─ Security-scoped Bookmarks
│  └─ SMAppService
│
└─ Optional / Later
   ├─ External MCP stdio client
   ├─ sqlite-vec
   ├─ fastembed-rs / MLX Swift
   ├─ GitHub / Gmail / Slack / Google Calendar
   └─ Sync / Publish service
```

---

## 4. 言語・アプリ基盤

## 4.1 採用: Xcode 26.5 stable + Swift 6 language mode + SwiftUI

SoloPM は macOS 専用であり、Apple Calendar、Apple Reminders、通知、Keychain、音声、ファイル権限に深く触るため、SwiftUI ネイティブが最も軽い。

2026年6月時点では、**本番MVPは Xcode 26.5 stable / Swift compiler 6.3 / Swift 6 language mode** を基準にする。Swift単体ツールチェーンやCLI検証では Swift 6.3.2 も使用可能。Xcode 27 beta / Swift 6.4 は最新だが beta のため本番基準から外す。

| 項目 | 採用 |
|---|---|
| 言語 | Swift 6 language mode / Swift compiler 6.3 |
| UI | SwiftUI |
| メニューバー | MenuBarExtra |
| 一部低レイヤー | 必要に応じて AppKit / CoreServices |
| パッケージ管理 | Swift Package Manager |
| Build toolchain | Xcode 26.5 stable |
| Beta検証 | Xcode 27 beta / Swift 6.4 / macOS 27 SDK |

### 不採用: Electron

Electron は Web UI とマルチプラットフォームには強いが、SoloPM の MVP では避ける。

理由:

```text
- 配布サイズが大きい
- メニューバー常駐アプリとして過剰
- macOS 権限・Calendar・Reminders・Keychain 連携が遠回り
- OS ネイティブ体験が弱くなる
```

### 不採用: Tauri

Tauri は Electron より軽いが、MVP では SwiftUI の方が良い。

理由:

```text
- Mac 専用なら WebView を挟む必要がない
- Calendar / Reminders / Notifications / Keychain が Swift から素直
- Rust core を先に作ると基盤開発に寄りすぎる
```

### Rust の扱い

MVP では Rust は必須ではない。

ただし、後続の Developer Mode では採用余地がある。

```text
- CLI
- Git scan
- 大量ファイル scan
- 外部 MCP server
- codebase-memory 連携
- ローカル embedding
```

---

## 5. STT

## 5.1 採用: SpeechAnalyzer / WhisperKit / whisper.cpp

MVP の STT は、1つに固定せず **Provider方式** にする。

```text
STTProvider
├─ AppleSpeechAnalyzerProvider   macOS 26+ / availability check必須
├─ WhisperKitProvider            Swift-native OSS / Apple Silicon向き
├─ WhisperCppProvider            C/C++ / 広互換 / 低レイヤー制御
└─ OpenAITranscribeProvider      BYOK cloud fallback
```

### 推奨順

| 優先 | STT | 判断 |
|---:|---|---|
| 1 | Apple SpeechAnalyzer | OSネイティブ。macOS 26+で使える場合は最小依存・追加APIコストなし |
| 2 | WhisperKit / Argmax OSS Swift | Swift-nativeで組み込みやすい。リアルタイム、word timestamp、VADなどを扱いやすい |
| 3 | whisper.cpp | 依存が少なく、Mac Intel/Apple Silicon/他OSまで広く扱える。Core ML/Metal対応が強い |
| 4 | OpenAI Speech to Text | BYOKユーザー向けの精度/利便性 fallback |

### MVP方針

```text
- Push-to-talk を基本にする
- 常時録音は MVP ではやらない
- SpeechAnalyzer は availability check して使える時だけ有効化
- WhisperKit / whisper.cpp のどちらかを最初のOSS実装にする
- 巨大モデルはアプリ本体に同梱しない
- 初回起動時にモデルを選択してダウンロード
```

### 選定メモ

- SwiftUIアプリに最短で組み込むなら **WhisperKit** が有力。
- クロスプラットフォーム性・C API・将来のCLI共用を重視するなら **whisper.cpp** が有力。
- 最新のOSネイティブ・ゼロ追加コストを狙うなら **SpeechAnalyzer** を条件付きで使う。

### コストメリット

ローカル STT により、毎回の文字起こし API コストをゼロにできる。音声ベースアプリは STT 呼び出し頻度が高くなるため、クラウド専用にすると利用量に比例してコストが増える。MVPではローカルをデフォルトにする。

## 5.2 Optional: OpenAI Speech to Text / Realtime STT

ユーザーが BYOK で高精度 STT を使いたい場合に備え、OpenAI の transcription 系モデルをオプションとして用意する。

使い分け:

| STT | 位置づけ |
|---|---|
| SpeechAnalyzer / WhisperKit / whisper.cpp | デフォルト。無料・ローカル・プライバシー重視 |
| OpenAI gpt-4o-mini-transcribe | 軽量クラウド STT |
| OpenAI gpt-4o-transcribe | 高精度クラウド STT |
| Realtime STT | 後続。会話型 UI が必要になったら検討 |

---

## 6. TTS

## 6.1 採用: macOS 標準 TTS

MVP の TTS は `AVSpeechSynthesizer` を使う。

用途は以下に限定する。

```text
- 「3件の期限超過があります」
- 「今日のタスクを作成しました」
- 「予定をカレンダーに追加しました」
```

長文会話や自然な感情表現は MVP では不要。

### コストメリット

macOS 標準 TTS を使うことで、TTS API コスト、モデル同梱、推論処理、音声モデル管理を避けられる。

## 6.2 Later: Kokoro / OpenAI TTS

高品質読み上げが必要になったら、次を検討する。

| 候補 | 判断 |
|---|---|
| Kokoro | 軽量 open-weight TTS。後続で検証 |
| OpenAI gpt-4o-mini-tts | BYOK オプションとして追加可能 |
| ElevenLabs 等 | MVP では不要 |

MVP では TTS に時間を使わない。

---

## 7. LLM 接続

## 7.1 採用: OpenAI Responses API adapter first

最初は **OpenAI Responses API adapter** を作る。OpenAI公式は新規プロジェクトではChat CompletionsよりResponses APIを推奨しているため、Action Plan生成・Structured Outputs・将来のremote MCP/agentic primitivesに備える。OpenAI-compatible Chat CompletionsはOpenRouter/Ollama互換のfallbackとして維持する。

```text
LLMProvider
├─ OpenAIResponsesAdapter
├─ OpenAICompatibleChatAdapter
│  ├─ OpenRouterAdapter
│  └─ OllamaAdapter
├─ AnthropicAdapter later
└─ GeminiAdapter later
```

優先順位:

| 優先度 | Provider | 理由 |
|---|---|---|
| P0 | OpenAI Responses API | 最初の基準実装にする |
| P1 | OpenRouter | 複数モデル選択とコスト最適化 |
| P1 | Ollama | ローカル LLM 対応 |
| P2 | Anthropic | Claude ユーザー対応 |
| P2 | Gemini | Google ecosystem 対応 |
| P2 | Apple Foundation Models | macOS 26+ / Apple Intelligence利用可能時のOSネイティブ推論。MVPコアではなく実験的に使う |

### 7.1.1 Later: Apple Foundation Models framework

Apple Foundation Models は、macOS 26+ でオンデバイスLLMにSwift APIからアクセスできるため、SoloPMの「ローカル・低コスト」思想と相性が良い。ただし、Apple Intelligence availability、OS version、端末条件に依存するため、MVPの必須LLMにはしない。

使いどころ:

```text
- 短いAction Planの下書き
- タスク名の整形
- Knowledge Frame候補の分類
- 通知文の短文生成
```

使わないところ:

```text
- 重要な複雑推論
- 長い企画書/メール文生成
- 外部連携を伴う危険な実行判断
```

## 7.2 Tool Calling に依存しすぎない

MVP では、各社の function calling / tool calling 方言に依存しすぎない。

LLM には **Action Plan JSON** を生成させる。

```json
{
  "summary": "QZT記事公開プロジェクトを作成します",
  "actions": [
    {
      "tool": "project.create",
      "args": {
        "title": "QZT記事公開",
        "deadline": "2026-06-30"
      }
    },
    {
      "tool": "task.bulk_create",
      "args": {
        "items": [
          { "title": "構成案作成", "due": "2026-06-20" },
          { "title": "初稿作成", "due": "2026-06-24" }
        ]
      }
    },
    {
      "tool": "notification.schedule",
      "args": {
        "rules": ["T-7", "T-3", "T-1", "overdue_daily"]
      }
    }
  ]
}
```

理由:

```text
- OpenAI / OpenRouter / Ollama / Anthropic / Gemini の差分を吸収しやすい
- 実行前確認 UI と相性が良い
- 予期しない tool 実行を防ぎやすい
- JSON Schema で validation できる
```

---

## 8. MCP / Tool 実行基盤

## 8.1 MVP: Built-in Tool Registry

MVP では、MCP サーバーを大量に子プロセスとして起動するのではなく、Swift アプリ内に Tool Registry を作る。

```text
ToolRegistry
├─ ProjectTool
├─ TaskTool
├─ CalendarTool
├─ ReminderTool
├─ NotificationTool
├─ FileSystemTool
├─ KnowledgeFrameTool
└─ MailDraftTool
```

外部から見た schema は MCP tool に近い形にする。

```json
{
  "name": "calendar.create_event",
  "description": "Create a calendar event in Apple Calendar",
  "input_schema": {
    "type": "object",
    "properties": {
      "title": { "type": "string" },
      "start": { "type": "string", "format": "date-time" },
      "end": { "type": "string", "format": "date-time" }
    },
    "required": ["title", "start", "end"]
  }
}
```

## 8.2 Later: External MCP stdio client / MCP spec 2025-11-25

外部 MCP は後続で stdio から対応する。実装時は **MCP specification 2025-11-25** を基準にする。stdio と Streamable HTTP は継続して重要だが、古い 2025-03-26 固定で設計しない。

```text
External MCP
├─ github-mcp
├─ google-calendar-mcp
├─ gmail-mcp
├─ slack-mcp
├─ codebase-memory-mcp
└─ custom user MCP
```

段階的な対応:

| Phase | 対応 |
|---|---|
| MVP | Built-in Tool Registry only |
| v0.2 | 外部 MCP stdio 読み取り系 |
| v0.3 | 外部 MCP write with approval |
| v0.4 | Streamable HTTP MCP |

---

## 9. DB / Knowledge / 検索

## 9.1 採用: SQLite + GRDB.swift

ローカル DB は SQLite。Swift 側の wrapper は GRDB.swift を第一候補にする。

保存対象:

```text
projects
tasks
milestones
notifications
calendar_links
reminder_links
artifacts
knowledge_frames
action_plans
tool_invocations
audit_logs
settings
```

## 9.2 採用: SQLite FTS5

Knowledge Frame とタスク検索は FTS5 を使う。

MVP で検索するもの:

```text
- Knowledge Frame 名
- triggers
- default_tasks
- deadline_rules
- deliverables
- 過去プロジェクト名
- タスク名
```

## 9.3 Later: sqlite-vec

ベクトル検索が必要になったら `sqlite-vec` を検討する。

採用タイミング:

```text
- Knowledge Frame が増えすぎた
- 意味検索が必要になった
- 過去プロジェクトから似た構成を探したい
- 本格 RAG までは要らないが semantic retrieval は欲しい
```

MVP では入れない。

理由:

```text
- FTS5 + triggers で十分
- embedding 生成モデルが必要になる
- デバッグ難度が上がる
- 初期プロダクト価値に直結しない
```

## 9.4 Later: fastembed-rs / MLX Swift

ローカル embedding が必要になったら以下を検討する。

| 候補 | 位置づけ |
|---|---|
| fastembed-rs | Rust core / CLI / Developer Mode 向け |
| MLX Swift | Apple Silicon 向けのローカル ML 実験候補 |
| OpenAI embeddings | BYOK fallback |

MVP では不要。

---

## 10. OS ネイティブ機能

## 10.1 Menu Bar

採用:

```text
SwiftUI MenuBarExtra
```

用途:

```text
- 今日のタスク
- 期限超過
- 音声入力ボタン
- 直近の予定
- 設定への導線
```

## 10.2 Global Shortcut

採用候補:

```text
KeyboardShortcuts
```

用途:

```text
Option + Space
↓
Voice Capture Overlay
```

## 10.3 Calendar / Reminders

採用:

```text
EventKit
```

Built-in Tools:

```text
calendar.create_event
calendar.create_deadline
calendar.create_work_block
reminders.create
reminders.bulk_create
reminders.mark_complete
```

## 10.4 Notifications

採用:

```text
UserNotifications
```

Built-in Tools:

```text
notification.schedule
notification.schedule_relative
notification.schedule_overdue_rule
notification.cancel
notification.list
```

## 10.5 API Key / Secrets

採用:

```text
Keychain Services
```

保存対象:

```text
OpenAI API Key
OpenRouter API Key
Anthropic API Key later
Gemini API Key later
GitHub Token later
Google OAuth token later
```

## 10.6 File access

採用:

```text
Security-scoped Bookmarks
```

方針:

```text
- ユーザーが明示的に選んだフォルダだけ扱う
- アプリが勝手にホーム全体を scan しない
- 書き込み前に確認を出す
```

## 10.7 File monitoring

採用:

```text
FSEvents
```

用途:

```text
- 成果物ファイルの更新検知
- 期限前に未作成ファイルを通知
- 長期間更新されていない成果物を検知
```

## 10.8 Optional native AI APIs

採用候補:

```text
SpeechAnalyzer
FoundationModels
```

方針:

```text
- macOS 26+ で availability check して利用
- 使えない端末では WhisperKit / whisper.cpp / BYOK LLM に fallback
- MVPの必須依存にはしない
- コスト削減・プライバシー訴求・オフライン機能として後続で強化
```

## 10.9 Login item / daily check

採用:

```text
SMAppService
```

用途:

```text
- ログイン時起動
- 期限超過チェック
- 日次 scan
```

---

## 11. 音声 UI 方針

MVP は Push-to-talk。

```text
Option + Space
↓
録音開始
↓
話す
↓
文字起こし
↓
テキスト編集
↓
Action Plan 生成
↓
確認
↓
実行
```

常時 listening は MVP ではやらない。

理由:

```text
- プライバシー説明が重い
- バッテリー/CPU負荷が増える
- 誤作動が増える
- 許可取得が重くなる
```

---

## 12. セキュリティ / 実行安全性

## 12.1 実行レベル

| Level | 内容 | MVP |
|---|---|---|
| Read | 読み取り | 有効 |
| Draft | 下書き生成 | 有効 |
| Write with approval | 通知・予定・ファイル作成 | 有効 |
| Dangerous | 送信・削除・上書き・Git push | 無効 |

## 12.2 MVP で禁止すること

```text
- メール送信
- Slack 自動投稿
- ファイル削除
- 既存ファイル上書き
- Git push
- Calendar / Reminder の削除
- ユーザー許可なしの全フォルダ scan
```

## 12.3 Audit Log

全ての Action Plan と tool invocation はローカルに記録する。

```json
{
  "timestamp": "2026-06-17T12:00:00+09:00",
  "input": "6月末までにQZTの記事を公開したい",
  "provider": "openai",
  "actions": ["project.create", "task.bulk_create", "notification.schedule"],
  "status": "approved_and_executed"
}
```

---

## 13. 配布 / 更新 / ライセンス

## 13.1 配布

MVP は Mac App Store ではなく公式サイト配布を推奨。

採用:

```text
Developer ID signing
Notarization
DMG or ZIP distribution
```

理由:

```text
- 外部 MCP / subprocess と相性が良い
- BYOK 設定がしやすい
- Sparkle 更新が使いやすい
- Mac App Store の制約を避けられる
```

## 13.2 自動更新

採用:

```text
Sparkle
```

## 13.3 課金

Obsidian 型を前提にする。

```text
Free:
- ローカル基本機能
- BYOK
- Apple Calendar / Reminders / Notifications

Founder:
- 開発支援
- Early access
- Beta MCP packs

Personal Plus later:
- 高度な通知ルール
- カスタム MCP
- Developer Mode
- GitHub 連携
- CLI

Sync later:
- 複数デバイス同期
- E2E encryption
- version history
```

---

## 14. OSS 採用候補

| 領域 | 候補 | MVP | メモ |
|---|---|---:|---|
| STT | SpeechAnalyzer | Conditional | macOS 26+ / availability check必須。OSネイティブSTT |
| STT | WhisperKit / Argmax OSS Swift | Yes候補 | Swift-native OSS STT。MVPの第一OSS候補 |
| STT | whisper.cpp | Yes候補 | 低依存・広互換・Core ML/Metal対応 |
| DB wrapper | GRDB.swift | Yes | SQLite を Swift で扱う |
| Global Shortcut | KeyboardShortcuts | Yes | ユーザー設定可能な hotkey |
| Updater | Sparkle | Yes | 公式サイト配布時の自動更新 |
| Vector search | sqlite-vec | Later | 小型 vector search。MVP では不要 |
| Embedding | fastembed-rs | Later | Rust core を入れる時に検討 |
| Apple Silicon ML | MLX Swift | Later | 実験・高機能版向け |
| TTS | Kokoro | Later | ローカル高品質 TTS 候補 |
| MCP | Swift MCP SDK | Later | 外部 MCP 対応を本格化する時。spec 2025-11-25基準 |
| On-device LLM | Foundation Models | Later | macOS 26+ / Apple Intelligence availability依存 |

---

## 15. コスト設計

## 15.1 変動費を持たない構成

| 領域 | 技術 | SoloPM 側コスト |
|---|---|---:|
| STT | SpeechAnalyzer / WhisperKit / whisper.cpp | 0 |
| TTS | macOS TTS | 0 |
| LLM | BYOK / Foundation Models later | 0〜ユーザー負担 |
| 通知 | UserNotifications | 0 |
| Calendar / Reminders | EventKit | 0 |
| DB | SQLite | 0 |
| Knowledge search | FTS5 | 0 |
| Update | Sparkle | ほぼ 0 |
| 配布 | 公式サイト | hosting 程度 |

## 15.2 コストが発生しうるもの

| 領域 | 発生タイミング | 対応 |
|---|---|---|
| モデル download bandwidth | whisper model 配布 | GitHub Releases / CDN / external model URL |
| Sync | 後続 | 有料サービス化 |
| Publish / Status Page | 後続 | 有料サービス化 |
| OAuth App 審査 | Gmail / Google 連携時 | 後続に回す |
| サポート | 商用利用 | Commercial Support |

---

## 16. MVP 実装順序

## Phase 0: Skeleton

```text
- SwiftUI app
- MenuBarExtra
- Settings window
- SQLite setup
- Keychain wrapper
- Global shortcut
```

## Phase 1: Voice to Action Plan

```text
- Audio recording
- SpeechAnalyzer / WhisperKit / whisper.cpp provider abstraction
- transcript edit UI
- OpenAI Responses API adapter
- OpenAI-compatible fallback adapter
- Action Plan JSON schema
- validation
```

## Phase 2: Built-in Tools

```text
- ProjectTool
- TaskTool
- NotificationTool
- CalendarTool
- ReminderTool
- FileSystemTool
- KnowledgeFrameTool
```

## Phase 3: Review & Execute

```text
- Action Review Screen
- partial edit
- approval
- execution log
- rollback metadata
```

## Phase 4: Deadline Watcher

```text
- deadline scan
- overdue scan
- daily check
- Notification scheduling
- menu bar summaries
```

## Phase 5: Packaging

```text
- Developer ID signing
- Notarization
- Sparkle update
- Founder license
- first public alpha
```

---

## 17. 後続で入れるもの

## v0.2 Developer Mode

```text
- Git read-only scan
- GitHub Issue 作成
- codebase-memory-mcp 任意連携
- README / release note / changelog 生成
- CLI
```

## v0.3 External MCP

```text
- External MCP stdio client
- MCP permission UI
- MCP execution log
- custom MCP registration
```

## v0.4 SaaS Connectors

```text
- Google Calendar
- Gmail Draft
- Slack Draft/Post with approval
- Google Drive
- Notion
```

## v0.5 Knowledge Advanced

```text
- sqlite-vec
- local embeddings
- semantic frame retrieval
- project memory
- optional WeKnora connector
```

---

## 18. 最終採用スタック

```text
Language:
  Swift 6 language mode
  Swift compiler 6.3 via Xcode 26.5 stable
  Swift 6.3.2 for standalone toolchain / CLI checks

UI:
  SwiftUI
  MenuBarExtra
  AppKit where needed

STT:
  SpeechAnalyzer conditional
  WhisperKit / Argmax OSS Swift
  whisper.cpp
  OpenAI Speech to Text optional

TTS:
  AVSpeechSynthesizer
  OpenAI TTS / Kokoro later

LLM:
  OpenAI Responses API adapter first
  OpenAI-compatible Chat fallback
  OpenRouter / Ollama next
  Anthropic / Gemini later
  Foundation Models later

Tool Execution:
  Built-in Swift Tool Registry
  MCP-compatible schema
  External MCP stdio later
  MCP spec 2025-11-25 baseline

Storage:
  SQLite
  GRDB.swift
  FTS5
  Markdown / YAML Knowledge Frames

Vector / RAG:
  None in MVP
  sqlite-vec later
  fastembed-rs / MLX Swift later

macOS Native:
  EventKit
  UserNotifications
  Keychain Services
  Security-scoped Bookmarks
  FSEvents
  SMAppService
  AVFoundation / AVFAudio
  SpeechAnalyzer later
  Foundation Models later

Distribution:
  Developer ID
  Notarization
  Sparkle

Business:
  BYOK
  Obsidian-style Free + Founder + Support
  Sync / Publish later
```

---

## 19. 参考リンク

- SwiftUI MenuBarExtra: https://developer.apple.com/documentation/SwiftUI/MenuBarExtra
- EventKit: https://developer.apple.com/documentation/eventkit
- UserNotifications: https://developer.apple.com/documentation/usernotifications
- Keychain Services: https://developer.apple.com/documentation/security/keychain-services
- FSEvents: https://developer.apple.com/documentation/coreservices/file_system_events
- SMAppService: https://developer.apple.com/documentation/servicemanagement/smappservice
- Security-scoped Bookmarks: https://developer.apple.com/documentation/professional-video-applications/enabling-security-scoped-bookmark-and-url-access
- Notarization: https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution
- whisper.cpp: https://github.com/ggml-org/whisper.cpp
- MCP Transports: https://modelcontextprotocol.io/specification/2025-06-18/basic/transports
- MCP Swift SDK: https://github.com/modelcontextprotocol/swift-sdk
- SQLite FTS5: https://sqlite.org/fts5.html
- GRDB.swift: https://github.com/groue/GRDB.swift
- KeyboardShortcuts: https://github.com/sindresorhus/KeyboardShortcuts
- Sparkle: https://github.com/sparkle-project/Sparkle
- sqlite-vec: https://github.com/asg017/sqlite-vec
- fastembed-rs: https://github.com/Anush008/fastembed-rs
- MLX Swift: https://github.com/ml-explore/mlx-swift
- Kokoro: https://github.com/hexgrad/kokoro
- OpenAI Speech to Text: https://developers.openai.com/api/docs/guides/speech-to-text
- OpenAI TTS: https://developers.openai.com/api/docs/guides/text-to-speech
- OpenRouter: https://openrouter.ai/docs/quickstart
- Ollama OpenAI compatibility: https://docs.ollama.com/api/openai-compatibility
- Xcode releases: https://developer.apple.com/news/releases/
- Xcode system requirements: https://developer.apple.com/xcode/system-requirements/
- Swift 6.3.2 install: https://www.swift.org/install/macos/swiftly/
- Xcode 27 beta release notes: https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes
- Apple Foundation Models: https://developer.apple.com/documentation/foundationmodels/
- Apple SpeechAnalyzer: https://developer.apple.com/documentation/speech/speechanalyzer
- Argmax OSS Swift / WhisperKit: https://github.com/argmaxinc/argmax-oss-swift
- OpenAI Responses API migration: https://developers.openai.com/api/docs/guides/migrate-to-responses
- MCP specification 2025-11-25: https://modelcontextprotocol.io/specification/2025-11-25
