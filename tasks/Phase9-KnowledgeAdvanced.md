# Phase 9: Knowledge Advanced

目的は、MVP の Knowledge Frame + FTS5 を壊さずに、必要になった時だけ semantic retrieval、project memory、optional WeKnora connector を追加すること。検索の高度化は価値が見えてから入れる。

## Scope

- sqlite-vec
- Local embeddings
- Semantic frame retrieval
- Project memory
- Optional WeKnora connector
- Retrieval evaluation

## Non-goals

- MVP への本格 RAG 混入
- 常時 embedding 生成
- ユーザー許可なしのファイル内容送信
- WeKnora 内包
- Cloud-only knowledge store

## Checklist

### P9-001: Retrieval requirements review

- [ ] FTS5 で足りない具体ケースを集める。
- [ ] semantic retrieval が必要な query を fixtures にする。
- [ ] latency、storage、privacy、model size の制約を定義する。
- [ ] 完了条件: sqlite-vec 導入理由が実データで説明できる。

### P9-002: EmbeddingProvider abstraction

- [ ] `EmbeddingProvider` protocol を作る。
- [ ] local provider、OpenAI embeddings BYOK fallback、disabled provider を用意する。
- [ ] embedding 対象は user-approved Knowledge Frame に限定する。
- [ ] テスト: provider unavailable、dimension mismatch、redaction を確認する。
- [ ] 完了条件: embedding 生成を Knowledge core から差し替え可能にする。

### P9-003: sqlite-vec storage

- [ ] sqlite-vec 導入可否を検証する。
- [ ] vector table migration と versioning を作る。
- [ ] FTS5 index と vector index の整合性を保つ。
- [ ] テスト: create / update / delete で vector が同期されることを確認する。
- [ ] 完了条件: Knowledge Frame 更新時に検索 index が壊れない。

### P9-004: Hybrid retrieval

- [ ] FTS5 と vector search の score を統合する。
- [ ] semantic result だけで自動実行せず、候補として LLM prompt に渡す。
- [ ] topK、threshold、fallback を設定可能にする。
- [ ] テスト: exact match、semantic match、no match、low confidence を確認する。
- [ ] 完了条件: 検索精度向上が explainable である。

### P9-005: Project memory

- [ ] project completion、task patterns、deadline rules、artifact templates を memory candidate として抽出する。
- [ ] ユーザー承認後に Knowledge Frame 化する。
- [ ] 個人情報や秘密情報を含む候補を redaction する。
- [ ] テスト: approved candidate のみ保存されることを確認する。
- [ ] 完了条件: 過去作業を再利用できるが、勝手に記憶しない。

### P9-006: Optional WeKnora connector

- [ ] WeKnora は内包せず external connector として扱う。
- [ ] 送信される文脈を preview し、ユーザー承認を必須にする。
- [ ] Knowledge Frame / FTS5 の local path を primary に保つ。
- [ ] テスト: connector disabled、network failure、permission denied を確認する。
- [ ] 完了条件: WeKnora がなくても SoloPM の core value が成立する。

### P9-007: Retrieval evaluation harness

- [ ] query、expected frame、allowed alternatives の eval dataset を作る。
- [ ] FTS5 only、vector only、hybrid を比較する。
- [ ] latency と memory usage も記録する。
- [ ] 完了条件: 検索方式の変更が体感ではなくデータで判断できる。

## Exit Gate

- [ ] FTS5 で不足する実ケースがある。
- [ ] embedding は opt-in / local-first。
- [ ] vector index は FTS5 と整合する。
- [ ] retrieval eval で改善を確認できる。
- [ ] WeKnora は optional connector であり core dependency ではない。
