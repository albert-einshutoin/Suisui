# Architecture Decision Records

SoloPM の重要な技術判断は ADR としてこのディレクトリに記録します。

## Naming

```text
NNNN-short-title.md
```

例:

```text
0001-database-primary-log-store.md
0002-global-shortcut-library.md
```

## Status

- `Proposed`: 提案中
- `Accepted`: 採用済み
- `Superseded`: 後続 ADR に置き換え済み

## Rules

- 1 ADR には 1 つの判断だけを書く。
- 採用案だけでなく、比較した不採用案も書く。
- 判断を変える場合は既存 ADR を大きく書き換えず、新しい ADR を追加して `Superseded by` を明記する。
- Phase / Issue / PR から関連 ADR へリンクする。
