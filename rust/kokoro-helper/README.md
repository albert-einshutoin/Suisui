# Suisui Kokoro helper PoC

事前生成した Kokoro v1.0 token 列から音声を実推論する Rust/ONNX の検証用 CLI です。本番 Swift 経路には未接続です。

利用者が [Kokoro-82M v1.0 ONNX 資産](https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX)（`.onnx` と英語 voice の `.bin`）を明示取得して、絶対パスで渡します。実行中にネットワーク取得はしません。モデルと voice はこのリポジトリへ追加しません。

```sh
cargo run --release --locked -- \
  --model /absolute/model.onnx \
  --voices /absolute/voices \
  --tokens-file /absolute/tokens.txt \
  --language en \
  --voice af_heart \
  --output /absolute/speech.wav
```

`tokens.txt` は空白区切りの10進 token IDで、先頭と末尾に `0` を置きます。例: `0 50 83 54 156 57 135 0`。token化とG2PはこのPoCの境界外です。モデル、voice、token vocabularyの版は利用者が一致させます。

推論には permissive license の `ort` を直接使います。G2P実装や辞書を依存グラフへ含めず、実行中のネットワーク取得や外部プロセス起動もしません。

No-Go: 日本語 G2P/音声品質の同等性は未検証のため、`--language ja` は明示的に拒否します。本番接続には、アプリ側token化境界、日本語パリティ、署名・notarization、実機 latency とメモリ、依存更新が必要です。

```sh
cargo fmt --check
cargo test --locked --all-targets --all-features
cargo clippy --locked --all-targets --all-features -- -D warnings
```
