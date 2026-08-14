# Suisui Kokoro helper PoC

英語だけを実推論する Rust/ONNX の検証用 CLI です。本番 Swift 経路には未接続です。

利用者が [Kokoro-82M v1.0 ONNX 資産](https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX)（`.onnx` と英語 voice の `.bin`）を明示取得して、絶対パスで渡します。実行中にネットワーク取得はしません。モデルと voice はこのリポジトリへ追加しません。

```sh
KOKORO_ORT_PROVIDER=cpu cargo run --release --locked -- \
  --model /absolute/model.onnx \
  --voices /absolute/voices \
  --text-file /absolute/prompt.txt \
  --language en \
  --voice af_heart \
  --output /absolute/speech.wav
```

量子化モデルは CPU provider で測定します。自動選択された CoreML provider は初回検証で CPU より遅く、メモリ使用量も多かったため、本番の backend 選定は未確定です。

No-Go: 日本語 G2P/音声品質の同等性は未検証のため、`--language ja` は明示的に拒否します。本番接続には、日本語パリティ、署名・notarization、実機 latency とメモリ、依存更新が必要です。`cargo audit` は既知脆弱性を検出していませんが、間接依存の `bincode 2.0.1` に `RUSTSEC-2025-0141`（unmaintained）があるため、現状の依存グラフは本番利用しません。

```sh
cargo fmt --check
cargo test --locked
cargo clippy --locked -- -D warnings
```
