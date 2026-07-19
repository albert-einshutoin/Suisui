# Phase 0: Skeleton

目的は、Suisui を macOS SwiftUI アプリとして継続開発できる土台に乗せること。AI や音声の本実装には入らず、アプリ構造、設定、永続化、秘密情報、ショートカットの境界を先に固める。

## Scope

- SwiftUI macOS app
- MenuBarExtra
- Settings window
- SQLite setup
- Keychain wrapper
- Global shortcut
- 最小限の CI / test baseline
- root project docs baseline
- ADR workflow

## Non-goals

- STT の本実装
- LLM API 呼び出し
- Calendar / Reminders への書き込み
- 外部 MCP
- 配布 signing / notarization

## Checklist

### P0-001: リポジトリと GitHub Flow の初期化

- [x] `git init` し、`main` と短命 feature branch の運用方針を root `README.md` に書く。
- [x] `.gitignore` を追加し、Xcode、SwiftPM、DerivedData、`.DS_Store`、local secret を除外する。
- [x] `docs/` と `tasks/` を追跡対象にし、実装前の設計資産として扱う。
- [x] `feature/phase0-skeleton` で初期実装を開始できる状態にする。
- [x] テスト: `git status --short` で不要ファイルが出ないことを確認する。
- [x] 完了条件: 新規開発者が clone 後に branch 方針を理解できる。

### P0-002: Xcode project / Swift package の作成

- [x] macOS SwiftUI app を作成する。
- [x] Swift language mode を Swift 6 にする。
- [x] deployment target は ADR に残す。SpeechAnalyzer / FoundationModels は availability check 前提にする。
- [x] `SuisuiApp`、`Core`、`Storage`、`Integrations`、`DesignSystem`、`TestingSupport` の責務境界を作る。
- [x] テスト: 空の unit test target が実行できることを確認する。
- [x] 完了条件: `xcodebuild test` または `swift test` の baseline が通る。

### P0-003: App entry と MenuBarExtra の最小実装

- [x] `SuisuiApp` の entry point を作る。
- [x] MenuBarExtra にアプリ名、Today summary placeholder、Voice Command placeholder、Settings 導線を出す。
- [x] View に business logic を置かず、表示用 state は ViewModel から受ける。
- [x] テスト: Menu bar summary 用 ViewModel の初期状態を unit test する。
- [x] 手動確認: アプリ起動時に menu bar item が表示される。
- [x] 完了条件: メニューバーから Settings を開ける。

### P0-004: Settings window skeleton

- [x] Settings window に AI Provider、API Key、STT、通知、保存先、Shortcut、Privacy のセクションを作る。
- [x] 各セクションは未実装状態でも disabled / placeholder を明示する。
- [x] 設定値は domain model `AppSettings` に集約する。
- [x] テスト: `AppSettings` の default 値と validation を unit test する。
- [x] 完了条件: 設定画面を開閉しても state が壊れない。

### P0-005: SQLite bootstrap

- [x] `DatabaseClient` protocol を作る。
- [x] internal `sqlite3` adapter を実装し、SQLite 接続を adapter に閉じ込める。GRDB.swift は ADR 0007 に従い later 再評価にする。
- [x] migration runner を作り、`schema_migrations` 相当の履歴を保持する。
- [x] Phase 0 では `settings` と `audit_logs` の最小 table だけ作る。
- [x] テスト: in-memory SQLite で migration が idempotent に通ることを確認する。
- [x] 完了条件: DB path を固定せず、test / app で差し替え可能。

### P0-006: Keychain wrapper

- [x] `SecretStore` protocol を作る。
- [x] Keychain Services adapter を実装する。
- [x] test 用 `InMemorySecretStore` を作る。
- [x] API Key は保存、読み取り、削除だけを提供し、一覧表示では値を返さない。
- [x] テスト: 保存、上書き、削除、未登録時の挙動を fake で先に確認する。
- [x] セキュリティ確認: API Key を logs、SQLite、UserDefaults に書かない。
- [x] 完了条件: Settings から secret を保存する UI に後で接続できる。

### P0-007: Global shortcut abstraction

- [x] `ShortcutClient` protocol を作る。
- [x] KeyboardShortcuts 導入可否を ADR に残す。
- [x] `Option + Space` を default 候補にするが、衝突時はユーザー変更できる設計にする。
- [x] テスト: shortcut registration state を ViewModel で unit test する。
- [x] 手動確認: `Option + Space` の local shortcut で Voice Capture Overlay 起動に接続できる。
- [x] 完了条件: Phase 1 の Voice Capture Overlay 起動に接続できる。

### P0-008: Permission Manager skeleton

- [x] `PermissionManager` を作り、Calendar、Reminders、Notifications、File Access、Microphone の状態を表現する。
- [x] `notDetermined`、`granted`、`denied`、`restricted` を UI が扱える enum にする。
- [x] 実 OS 権限要求はまだ薄い adapter に留める。
- [x] テスト: 権限状態に応じて Settings の表示文言と disabled 状態が変わることを確認する。
- [x] 完了条件: 各 Phase の adapter が同じ権限表現を再利用できる。

### P0-009: Audit logger skeleton

- [x] `AuditLogger` protocol を作る。
- [x] `AuditEvent` に timestamp、category、action、status、metadata を持たせる。
- [x] Phase 0 では JSONL または SQLite のどちらを primary にするか ADR に残す。
- [x] テスト: secret 値が metadata に含まれた場合に redaction されることを確認する。
- [x] 完了条件: Phase 1 以降の LLM / Tool 実行ログで再利用できる。

### P0-010: CI / local verification baseline

- [x] local verification command を README に書く。
- [x] GitHub Actions を使う場合は macOS runner で test を走らせる。
- [x] lint / format 方針を決める。導入しない理由を `CONTRIBUTING.md` に残す。
- [x] テスト: CI と local で同じ `./scripts/ci.sh` command が動くことを確認する。
- [x] 完了条件: 以後の PR が最低限の自動検証を持つ。

### P0-011: Project documentation baseline

- [x] root `README.md` を作り、Suisui の一文説明、MVP scope、開発開始手順、local verification command を書く。
- [x] `CONTRIBUTING.md` を作り、GitHub Flow、TDD、Issue 展開ルール、PR checklist を `tasks/README.md` へリンクする。
- [x] `SECURITY.md` を作り、API Key / token を Keychain に保存し、ログや DB に保存しない方針を書く。
- [x] root README から `docs/README.md`、`docs/tech_stack.md`、`tasks/README.md` へリンクする。
- [x] テスト: 新規 contributor が root README から設計、タスク、検証コマンドへ辿れることを確認する。
- [x] 完了条件: Phase 1 以降の PR が参照できる最低限の OSS 文書がある。

### P0-012: ADR workflow

- [x] `docs/adr/` を作成する。
- [x] ADR template を追加し、Context、Decision、Options considered、Consequences、Status を含める。
- [x] deployment target、KeyboardShortcuts 採用、audit log primary store、SQLite adapter 方針など Phase 0 の判断を ADR として記録する。
- [x] テスト: Phase 0 の判断が Issue / PR から ADR へリンクできることを確認する。
- [x] 完了条件: 技術判断が口頭や PR コメントだけに残らない。

## Exit Gate

- [x] アプリが起動し、MenuBarExtra と Settings window を開ける。
- [x] SQLite migration と Keychain wrapper の unit test がある。
- [x] macOS API は protocol / adapter 経由で差し替え可能。
- [x] API Key を安全に保存する境界ができている。
- [x] `main` へPRで戻せる GitHub Flow baseline がある。
- [x] root README / CONTRIBUTING / SECURITY の最小版がある。
- [x] ADR template と Phase 0 の主要判断 ADR がある。
