# Phase 1: Voice to Action Plan

目的は、ユーザー入力を安全な `ActionPlan` に変換すること。Phase 1 では実データへの書き込みは行わず、音声 / テキスト入力、LLM adapter、schema validation、確認前の plan 生成までに限定する。

## Scope

- Audio recording
- STT provider abstraction
- Transcript edit UI
- OpenAI Responses API adapter
- OpenAI-compatible fallback adapter
- Action Plan JSON schema
- Validation

## Non-goals

- Calendar / Reminders / Notifications への実書き込み
- Tool execution
- 外部 MCP
- 常時 listening
- メール送信や Slack 投稿

## Checklist

### P1-001: ActionPlan domain model

- [x] `ActionPlan`、`Action`、`ActionType`、`RiskLevel`、`ApprovalRequirement` を定義する。
- [x] 日時は string 直書きで広げず、`DateExpression` と resolved date を分ける。
- [x] `riskLevel` は `read`、`draft`、`write`、`danger` を表現する。
- [x] テスト: `write` action は `requiresApproval = true` になることを確認する。
- [x] テスト: `danger` action は MVP では validation error になることを確認する。
- [x] 完了条件: LLM の出力に依存しない pure Swift model になっている。

### P1-002: ActionPlan JSON Schema

- [x] `ActionPlan` の JSON Schema を `Resources/Schemas` などに置く。
- [x] required fields、enum、date-time / date の扱いを明記する。
- [x] `additionalProperties` を原則 false にする。
- [x] テスト: valid sample、missing required、unknown action、danger action の fixtures を作る。
- [x] 完了条件: LLM から返った JSON を実行前に必ず validation できる。

### P1-003: Prompt template for planning

- [x] system prompt に Suisui の役割、MVP の禁止操作、ActionPlan schema を含める。
- [x] user input、timezone、current date、available tools、Knowledge Frame candidates を分けて渡す設計にする。
- [x] 曖昧な日時は勝手に確定せず `requiresUserConfirmation` にする。
- [x] テスト: prompt builder が current date と timezone を含むことを確認する。
- [x] 完了条件: prompt が provider 非依存で再利用できる。

### P1-004: LLMProvider protocol

- [x] `LLMProvider` protocol を作る。
- [x] 入力は `PlanningRequest`、出力は raw text ではなく `PlanningResponse` にする。
- [x] provider error は auth、rate limit、network、invalid response、unknown に分類する。
- [x] test 用 `FakeLLMProvider` を作る。
- [x] テスト: provider error が UI 表示用 error に変換されることを確認する。
- [x] 完了条件: OpenAI 以外の provider を後で追加できる。

### P1-005: OpenAI Responses API adapter

- [x] Keychain から API Key を読む境界を `SecretStore` 経由にする。
- [x] Responses API adapter を `LLMProvider` に適合させる。
- [x] timeout、retry なし / ありの方針を ADR に残す。
- [x] secret、prompt 全文、個人ファイル内容を不用意にログ出力しない。
- [x] テスト: URLRequest builder を unit test し、Authorization header の redaction を確認する。
- [x] 完了条件: network 呼び出しは integration smoke に分離され、unit test は fake で通る。

### P1-006: OpenAI-compatible fallback adapter

- [x] OpenRouter / Ollama を想定した Chat Completions compatible adapter を作る。
- [x] base URL、model、API Key 必須有無を Settings から渡せる設計にする。
- [x] OpenAI Responses adapter と同じ `ActionPlan` validation path を通す。
- [x] テスト: request body の provider 差分を unit test する。
- [x] 完了条件: provider を切り替えても UI と Core が変わらない。

### P1-007: STTProvider abstraction

- [x] `STTProvider` protocol を作る。
- [x] `transcribe(audio:)`、availability、model status、permission requirement を表現する。
- [x] `AppleSpeechAnalyzerProvider`、`WhisperKitProvider`、`WhisperCppProvider`、`OpenAITranscribeProvider` の skeleton を作る。
- [x] テスト: availability に応じて Settings の provider 候補が変わることを確認する。
- [x] 完了条件: どの STT を使っても transcript edit UI に同じ形で渡せる。

### P1-008: Audio recording foundation

- [x] `AudioRecorder` protocol を作る。
- [x] AVFoundation / AVFAudio adapter を用意する。
- [x] microphone permission がない場合は録音開始しない。
- [x] 録音中、停止、失敗、保存済み temporary file の state を定義する。
- [x] テスト: fake recorder で state transition を unit test する。
- [x] 手動確認: Record / Stop の明示操作で録音 placeholder が動く。
- [x] 完了条件: 常時録音を入れず、明示操作だけで録音する。

### P1-009: Voice Capture Overlay

- [x] shortcut から overlay を開く。
- [x] 録音状態、文字起こし中、transcript edit、plan generation loading、error を表示する。
- [x] transcript は実行前に必ず編集可能にする。
- [x] テスト: ViewModel で録音開始、停止、transcript 反映、LLM 実行の state transition を確認する。
- [x] 手動確認: 音声なしでもテキスト入力 fallback で plan generation へ進める。
- [x] 完了条件: 音声失敗時にテキスト入力へ落ちられる。

### P1-010: ActionPlan validation pipeline

- [x] LLM response を parse する。
- [x] JSON Schema validation を実行する。
- [x] domain validation を実行する。
- [x] warning、blocking error、requires confirmation を分ける。
- [x] テスト: 曖昧な日付、未知 tool、danger action、不正 JSON、空 actions を fixtures で確認する。
- [x] 完了条件: invalid plan は Phase 2 の Tool Registry に到達しない。

### P1-011: Planning audit log

- [x] 入力テキスト、provider、plan summary、validation result を audit log に残す。
- [x] API Key、Authorization header、raw secret は必ず redaction する。
- [x] ユーザーが明示許可していないローカルファイル内容をログに含めない。
- [x] テスト: redaction と validation failure logging を確認する。
- [x] 完了条件: 問題調査に必要な情報は残しつつ秘密情報を残さない。

## Exit Gate

- [x] テキスト入力から valid `ActionPlan` を生成できる。
- [x] 音声入力は provider abstraction と overlay まで接続されている。
- [x] invalid / dangerous plan は拒否される。
- [x] LLM provider を fake に差し替えた unit test がある。
- [x] 実データへの書き込みはまだ発生しない。
