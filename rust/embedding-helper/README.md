# Suisui local embedding helper PoC

ローカルの **UserDefined** ONNX 埋め込みモデルだけを one-shot で実推論する source-only PoC です。Swift 本番経路、アプリ bundle、release には未接続です。実行中にモデルを取得しません。本文は argv、stdout、stderr、エラーに出力せず、指定した JSON ファイルだけへ書き込みます。

```sh
cargo run --release --locked -- \
  --model-dir /absolute/model-directory \
  --text-file /absolute/input.txt \
  --output /absolute/embedding.json
```

`--model-dir` は symlink ではない非空の通常ファイル `model.onnx`、`tokenizer.json`、`config.json`、`special_tokens_map.json`、`tokenizer_config.json` の5件を直下に必須とします。5件の合計は400 MiB以下、入力は UTF-8・空でなく64 KiB以下、すべての指定パスは絶対パスです。既存の出力は上書きせず、同じディレクトリで `create_new` temporary file を `fsync` し、macOS の `renameatx_np(RENAME_EXCL)` で atomic no-replace rename します。

出力JSONは `schemaVersion: 1`、`providerID: "local-fastembed"`、`dimensions: 384`、および384件の finite `values` だけを持ちます。`dimensions` と `values` の長さが384以外なら拒否します。

実装は固定した `fastembed 5.17.4` の `default-features = false` を使い、Hugging Face Hub / 組込みモデル取得 feature を有効にしていません。`TextEmbedding::try_new_from_user_defined` と `Pooling::Mean` だけで初期化します。fastembed の後段 L2 正規化も同ライブラリの標準挙動です。

`ort-download-binaries-rustls-tls` は実推論のために有効です。これは **Cargo build 時** に対応する ONNX Runtime の事前ビルド binary を Rustls TLS で取得して link する feature であり、オフライン build では既存の `ORT_LIB_PATH` 等を与えない限り失敗します。これはモデル取得ではなく、runtime でのネットワーク通信も発生しません。依存の provenance / license は crates.io package metadata と `Cargo.lock` で固定し、`fastembed` は Apache-2.0、`ort` は MIT OR Apache-2.0 です。導入判断前に lockfile を用いて全 transitive dependency を組織の license scanner で再確認してください。

2026-08-14 の `cargo audit` は脆弱性ではなく `RUSTSEC-2024-0436`（`fastembed -> tokenizers -> paste 1.0.15` が unmaintained）を1件警告しました。固定した fastembed 5.17.4 の依存グラフに由来するため、このPoCでは抑止せず、production Go 条件では upstream 更新または明示的な security approval を必須とします。

実モデル smoke は、モデル配布元の license を確認し、checksum を固定してから実行します。

```sh
shasum -a 256 /absolute/model-directory/model.onnx
cargo run --release --locked -- \
  --model-dir /absolute/model-directory \
  --text-file /absolute/input.txt \
  --output /absolute/embedding.json
```

小さな deterministic fixture は同梱せず、テストでは注入 engine により `input -> finite vector -> atomic JSON` 契約と CLI の本文非露出・64 KiB 境界を検証します。実モデルの日本語・多言語品質は未判定です。production 接続の Go 条件は、モデル license、checksum、対象言語の retrieval eval、メモリ/latency benchmark、実機 bundle/signing 検証です。

```sh
cargo fmt --check
cargo test --locked --all-targets --all-features
cargo clippy --locked --all-targets --all-features -- -D warnings
```
