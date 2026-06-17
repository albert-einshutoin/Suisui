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

- [ ] `ActionPlan`、`Action`、`ActionType`、`RiskLevel`、`ApprovalRequirement` を定義する。
- [ ] 日時は string 直書きで広げず、`DateExpression` と resolved date を分ける。
- [ ] `riskLevel` は `read`、`draft`、`write`、`danger` を表現する。
- [ ] テスト: `write` action は `requiresApproval = true` になることを確認する。
- [ ] テスト: `danger` action は MVP では validation error になることを確認する。
- [ ] 完了条件: LLM の出力に依存しない pure Swift model になっている。

### P1-002: ActionPlan JSON Schema

- [ ] `ActionPlan` の JSON Schema を `Resources/Schemas` などに置く。
- [ ] required fields、enum、date-time / date の扱いを明記する。
- [ ] `additionalProperties` を原則 false にする。
- [ ] テスト: valid sample、missing required、unknown action、danger action の fixtures を作る。
- [ ] 完了条件: LLM から返った JSON を実行前に必ず validation できる。

### P1-003: Prompt template for planning

- [ ] system prompt に SoloPM の役割、MVP の禁止操作、ActionPlan schema を含める。
- [ ] user input、timezone、current date、available tools、Knowledge Frame candidates を分けて渡す設計にする。
- [ ] 曖昧な日時は勝手に確定せず `requiresUserConfirmation` にする。
- [ ] テスト: prompt builder が current date と timezone を含むことを確認する。
- [ ] 完了条件: prompt が provider 非依存で再利用できる。

### P1-004: LLMProvider protocol

- [ ] `LLMProvider` protocol を作る。
- [ ] 入力は `PlanningRequest`、出力は raw text ではなく `PlanningResponse` にする。
- [ ] provider error は auth、rate limit、network、invalid response、unknown に分類する。
- [ ] test 用 `FakeLLMProvider` を作る。
- [ ] テスト: provider error が UI 表示用 error に変換されることを確認する。
- [ ] 完了条件: OpenAI 以外の provider を後で追加できる。

### P1-005: OpenAI Responses API adapter

- [ ] Keychain から API Key を読む境界を `SecretStore` 経由にする。
- [ ] Responses API adapter を `LLMProvider` に適合させる。
- [ ] timeout、retry なし / ありの方針を ADR に残す。
- [ ] secret、prompt 全文、個人ファイル内容を不用意にログ出力しない。
- [ ] テスト: URLRequest builder を unit test し、Authorization header の redaction を確認する。
- [ ] 完了条件: network 呼び出しは integration smoke に分離され、unit test は fake で通る。

### P1-006: OpenAI-compatible fallback adapter

- [ ] OpenRouter / Ollama を想定した Chat Completions compatible adapter を作る。
- [ ] base URL、model、API Key 必須有無を Settings から渡せる設計にする。
- [ ] OpenAI Responses adapter と同じ `ActionPlan` validation path を通す。
- [ ] テスト: request body の provider 差分を unit test する。
- [ ] 完了条件: provider を切り替えても UI と Core が変わらない。

### P1-007: STTProvider abstraction

- [ ] `STTProvider` protocol を作る。
- [ ] `transcribe(audio:)`、availability、model status、permission requirement を表現する。
- [ ] `AppleSpeechAnalyzerProvider`、`WhisperKitProvider`、`WhisperCppProvider`、`OpenAITranscribeProvider` の skeleton を作る。
- [ ] テスト: availability に応じて Settings の provider 候補が変わることを確認する。
- [ ] 完了条件: どの STT を使っても transcript edit UI に同じ形で渡せる。

### P1-008: Audio recording foundation

- [ ] `AudioRecorder` protocol を作る。
- [ ] AVFoundation / AVFAudio adapter を用意する。
- [ ] microphone permission がない場合は録音開始しない。
- [ ] 録音中、停止、失敗、保存済み temporary file の state を定義する。
- [ ] テスト: fake recorder で state transition を unit test する。
- [ ] 手動確認: push-to-talk で録音 placeholder が動く。
- [ ] 完了条件: 常時録音を入れず、明示操作だけで録音する。

### P1-009: Voice Capture Overlay

- [ ] shortcut から overlay を開く。
- [ ] 録音状態、文字起こし中、transcript edit、plan generation loading、error を表示する。
- [ ] transcript は実行前に必ず編集可能にする。
- [ ] テスト: ViewModel で録音開始、停止、transcript 反映、LLM 実行の state transition を確認する。
- [ ] 手動確認: 音声なしでもテキスト入力 fallback で plan generation へ進める。
- [ ] 完了条件: 音声失敗時にテキスト入力へ落ちられる。

### P1-010: ActionPlan validation pipeline

- [ ] LLM response を parse する。
- [ ] JSON Schema validation を実行する。
- [ ] domain validation を実行する。
- [ ] warning、blocking error、requires confirmation を分ける。
- [ ] テスト: 曖昧な日付、未知 tool、danger action、不正 JSON、空 actions を fixtures で確認する。
- [ ] 完了条件: invalid plan は Phase 2 の Tool Registry に到達しない。

### P1-011: Planning audit log

- [ ] 入力テキスト、provider、plan summary、validation result を audit log に残す。
- [ ] API Key、Authorization header、raw secret は必ず redaction する。
- [ ] ユーザーが明示許可していないローカルファイル内容をログに含めない。
- [ ] テスト: redaction と validation failure logging を確認する。
- [ ] 完了条件: 問題調査に必要な情報は残しつつ秘密情報を残さない。

## Exit Gate

- [ ] テキスト入力から valid `ActionPlan` を生成できる。
- [ ] 音声入力は provider abstraction と overlay まで接続されている。
- [ ] invalid / dangerous plan は拒否される。
- [ ] LLM provider を fake に差し替えた unit test がある。
- [ ] 実データへの書き込みはまだ発生しない。
