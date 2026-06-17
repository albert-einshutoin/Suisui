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

- [x] FTS5 で足りない具体ケースを集める。
- [x] semantic retrieval が必要な query を fixtures にする。
- [x] latency、storage、privacy、model size の制約を定義する。
- [x] 完了条件: sqlite-vec 導入理由が実データで説明できる。

### P9-002: EmbeddingProvider abstraction

- [x] `EmbeddingProvider` protocol を作る。
- [x] local provider、OpenAI embeddings BYOK fallback、disabled provider を用意する。
- [x] embedding 対象は user-approved Knowledge Frame に限定する。
- [x] テスト: provider unavailable、dimension mismatch、redaction を確認する。
- [x] 完了条件: embedding 生成を Knowledge core から差し替え可能にする。

### P9-003: sqlite-vec storage

- [x] sqlite-vec 導入可否を検証する。
- [x] vector table migration と versioning を作る。
- [x] FTS5 index と vector index の整合性を保つ。
- [x] テスト: create / update / delete で vector が同期されることを確認する。
- [x] 完了条件: Knowledge Frame 更新時に検索 index が壊れない。

### P9-004: Hybrid retrieval

- [x] FTS5 と vector search の score を統合する。
- [x] semantic result だけで自動実行せず、候補として LLM prompt に渡す。
- [x] topK、threshold、fallback を設定可能にする。
- [x] テスト: exact match、semantic match、no match、low confidence を確認する。
- [x] 完了条件: 検索精度向上が explainable である。

### P9-005: Project memory

- [x] project completion、task patterns、deadline rules、artifact templates を memory candidate として抽出する。
- [x] ユーザー承認後に Knowledge Frame 化する。
- [x] 個人情報や秘密情報を含む候補を redaction する。
- [x] テスト: approved candidate のみ保存されることを確認する。
- [x] 完了条件: 過去作業を再利用できるが、勝手に記憶しない。

### P9-006: Optional WeKnora connector

- [x] WeKnora は内包せず external connector として扱う。
- [x] 送信される文脈を preview し、ユーザー承認を必須にする。
- [x] Knowledge Frame / FTS5 の local path を primary に保つ。
- [x] テスト: connector disabled、network failure、permission denied を確認する。
- [x] 完了条件: WeKnora がなくても SoloPM の core value が成立する。

### P9-007: Retrieval evaluation harness

- [x] query、expected frame、allowed alternatives の eval dataset を作る。
- [x] FTS5 only、vector only、hybrid を比較する。
- [x] latency と memory usage も記録する。
- [x] 完了条件: 検索方式の変更が体感ではなくデータで判断できる。

## Exit Gate

- [x] FTS5 で不足する実ケースがある。
- [x] embedding は opt-in / local-first。
- [x] vector index は FTS5 と整合する。
- [x] retrieval eval で改善を確認できる。
- [x] WeKnora は optional connector であり core dependency ではない。

## Implementation Notes

- 実装: `Sources/SoloPMCore/Knowledge/KnowledgeAdvanced.swift`
- テスト: `Tests/SoloPMCoreTests/KnowledgeAdvancedTests.swift`
- DB migration: `CoreMigrations.phase9` に `knowledge_frame_vectors` と `knowledge_retrieval_eval_runs` を追加する。
- sqlite-vec は capability として分離し、未導入環境でも JSON fallback vector table で local-first の検索実験を継続できる。
- embedding は `EmbeddingProvider` protocol で抽象化し、`DisabledEmbeddingProvider`、`LocalHashEmbeddingProvider`、BYOK OpenAI fallback wrapper を用意する。
- embedding 対象は `EmbeddingRequest.userApproved == true` の Knowledge Frame に限定する。
- hybrid retrieval は FTS5 / vector / hybrid を同一 harness で比較でき、結果には `fts` / `vector` の explanation を残す。
- project memory は completed project から candidate を抽出するが、承認済み candidate のみ Knowledge Frame として保存する。
- WeKnora は optional connector として preview + approval を必須にし、無効化 / network failure / permission denied を明示的に扱う。

## Verification

- `swift test --filter KnowledgeAdvancedTests`

## Links

- ADR: `docs/adr/0006-optional-connectors-and-knowledge-boundaries.md`
