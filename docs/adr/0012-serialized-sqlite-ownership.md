# ADR 0012: Serialized SQLite Ownership

Date: 2026-07-24
Status: Accepted

## Context

Suisui の複数 window、menu bar、deadline watcher、voice、automation は、同じ
SQLite database と、場合によっては同じ `sqlite3` handle を共有する。従来は
Store ごとの `NSLock` に依存していたため、Store A の transaction 中に Store B
が同じ handle を使い、`BEGIN` / `COMMIT` 境界へ別処理が混入できた。また、
接続ごとの WAL、busy timeout、synchronous policy が未定義で、別接続の短時間
競合が即座に `database is locked` として利用者へ露出していた。

pointer-backed `SQLiteRow` も public API だったため、finalize 後の statement を
参照する値を query closure 外へ返せた。さらに dictionary row は SQL `NULL` を
空文字列へ変換していた。

## Decision

MVP の SQLite ownership を次の二層で固定する。

1. `SQLiteConnection` は一つの `sqlite3` handle を所有し、recursive connection
   lock で prepare、bind、step、row decode、transaction を直列化する。
2. async 呼び出し元は `SQLiteDatabaseWorker` actor を ownership boundary として
   使用する。worker transaction は cancellation を commit 前に確認する。

transaction lock は closure 全体を保持する。nested transaction は暗黙に混ぜず
`DatabaseError.nestedTransaction` で拒否する。migration も同じ transaction API
を使い、runtime store を公開する前に完了させる。

file-backed writable connection は open 時に次を設定し、読み戻して検証する。

- `foreign_keys = ON`
- `journal_mode = WAL`
- `busy_timeout = 250ms`
- `synchronous = NORMAL`
- `temp_store = MEMORY`
- `wal_autocheckpoint = 1000 pages`

250ms を超える競合は `DatabaseError.busyTimeout` として分類する。短い writer
競合は SQLite の busy handler で待ち、同一 handle の競合は connection lock で
防ぐ。

row API は statement pointer を持たない `SQLiteMaterializedRow` /
`SQLiteCell` に統一する。pointer-backed decoder と generic query closure は
削除し、statement の有効期間内に全 cell を materialize する。storage class
mismatch と duplicate column alias は fail closed にする。`NULL`、空 text、
empty blob、integer、real は別の cell として保持する。

## Options Considered

### Actor へ全 Store を一括移行

- Pros: Swift concurrency だけで ownership を表現できる。
- Cons: 同期 Store を使う多数の view model、tool、watcher を一度に async 化し、
  product change と infrastructure rewrite が結合する。

### Store ごとの lock を継続

- Pros: 変更が少ない。
- Cons: 同じ connection を共有する別 Store 間の transaction 混入を防げず、
  ownership rule が型にも connection にも存在しない。

### Connection serialization + actor facade

- Pros: 現在の同期 Store を安全に保ちながら、read model から段階的に actor へ
  移行できる。transaction boundary と row lifetime を adapter 内で強制できる。
- Cons: 移行期間中は connection の `@unchecked Sendable` を、内部 lock の
  invariant とテストで正当化する必要がある。

## Consequences

- Positive: 同一 handle の操作と transaction は Store 境界を越えて直列化される。
- Positive: file database は WAL と bounded busy wait を一貫して使う。
- Positive: cancellation、nested transaction、busy timeout、row type mismatch
  が分類可能になる。
- Positive: public row は statement finalize 後も安全で、SQL `NULL` を失わない。
- Negative: 既存の同期 Store は直ちには async API にならない。
- Negative: 250ms を超える外部 writer は retry ではなく明示エラーになる。
- Follow-up: board snapshot、menu bar、settings readiness の順で
  `SQLiteDatabaseWorker` へ移行し、main actor 上の同期 I/O を削減する。
- Follow-up: read 負荷の実測で必要になった場合のみ bounded read-only pool を
  別 ADR で検討する。

## Links

- Related issues: #348, #349
- Supersedes the ownership assumptions in:
  `docs/architecture/main-thread-database-plan.md`
- Related implementation:
  `Sources/SuisuiCore/Database/SQLiteDatabaseClient.swift`
