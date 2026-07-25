# ADR 0013: Voice Task Conversation Memory Boundary

Date: 2026-07-25
Status: Accepted

## Context

Suisui の既存 `ConversationTaskIntent` と `ClarificationSession` は、一回の音声入力を
Action Planへ変換するためのIntentと不足slotを表現する。一方、複数turnにまたがる
会話では、現在選択中のProject/Task、短期的な指示語候補、ユーザーが確定した目的や
制約、Action Plan・Assistant Queue・Execution Receiptとの因果関係を再開後も扱う
必要がある。

raw transcript、Providerの推論、ユーザーが確認した事実を一つの会話履歴として保存
すると、保持期間の長いTask文脈へ音声の言い間違いや秘密を暗黙にコピーする。また、
Provider固有の会話履歴をsource of truthにすると、Provider変更、削除、同期、監査の
境界がSuisuiのTask domainではなく外部サービスへ移る。

## Decision

会話メモリを次の独立したPure Swift root typeへ分ける。

1. `VoiceTaskConversationSession` は会話のlifecycleと再開に必要な最小のactive
   Project/Task、短いresume summaryだけを持つ。
2. `VoiceTaskConversationTurn` はraw transcriptとuser-confirmed textを別fieldで
   持つ。confirmed textが空のturnは作れない。
3. `ConversationReference` はstable target ID、source turn、候補順序とその
   fingerprint、expiryを持つ。期限切れ候補は解決に利用できない。
4. `TaskContextFact` はkind、scope、state、source turn、confidence、author、
   supersessionを持つ。confidenceは有限な`0.0...1.0`に限定し、supersession cycle
   を拒否する。
5. `ConversationActionLink` はreview済みfingerprintとAction Plan、Queue、Task、
   ReceiptのIDを結び、会話から実行結果までの因果関係を保持する。

raw transcriptから`TaskContextFact.value`への自動コピーは行わない。Factは明示的な
変換・確認処理で新規作成し、`userExplicit`と`providerInferred`をauthorで区別する。
この分離により、transcript/session/factの保持・訂正・削除を独立させ、TaskやReceipt
を会話削除へ暗黙にcascadeしない。

root typeのstateとidentityは外部から直接変更できない。Session遷移とvalidationを
method/initializerへ集約し、`Codable` decodeでも同じvalidationを通す。永続化形式と
SQLite schemaは後続Issueで定義する。

## Options Considered

### transcriptの配列をSessionへ保存する

- Pros: 実装が単純で、会話画面をそのまま再現しやすい。
- Cons: raw音声由来データと確認済みTask文脈の寿命が結合し、推測や秘密を長期記憶へ
  混入しやすい。参照解決と監査も自由文の再解釈へ依存する。

### Providerのconversation/thread IDをsource of truthにする

- Pros: Providerの会話継続機能を再利用できる。
- Cons: Provider変更やoffline利用で再現できず、Suisuiの承認・Receipt・削除境界を
  強制できない。Provider側の保持期間と利用規約にも依存する。

### confirmed Factだけを保存してTurnを持たない

- Pros: 保存量とprivacy exposureを最小化できる。
- Cons: Factの出典、訂正、参照候補の順序、Action Planとの因果関係を説明できない。

### typed Session、Turn、Reference、Fact、Action Linkを分離する

- Pros: 各データのprovenance、保持期間、不変条件を型で表現し、ProviderとUIに依存
  しない後続Store/resolver契約を作れる。
- Cons: migration、retention、UIで複数rootを整合させる必要がある。

## Consequences

- Positive: raw transcript、確認済みFact、実行証跡を別の寿命で保持・削除できる。
- Positive: 古い指示語候補、範囲外confidence、循環supersession、不正なSession遷移
  をdomain境界でfail closedにできる。
- Positive: Provider変更後もTask/Project/Action Plan/ReceiptをSuisuiのsource of
  truthとして継続できる。
- Negative: 会話全文の再生はtyped Factだけでは行えず、Turn retention policyが別途
  必要になる。
- Negative: 後続Storeは複数root間のtransaction整合性を保証する必要がある。
- Follow-up: #330でSQLite schema、migration、transactional storeを実装する。
- Follow-up: #331でexpiryとordering fingerprintを使う決定論的resolverを実装する。
- Follow-up: #337でtranscript、Session、Factそれぞれの訂正・forgettingを実装する。

## Links

- Parent roadmap: #328
- Implements: #329
- Related: #21, #22, #321
- Existing Provider boundary ADR: `docs/adr/0011-codex-app-server-user-subscription-boundary.md`
