#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUST_MANIFEST="$ROOT_DIR/rust/kokoro-helper/Cargo.toml"

cd "$ROOT_DIR"

./ci/run-full.sh
cargo fmt --manifest-path "$RUST_MANIFEST" --check
cargo test --manifest-path "$RUST_MANIFEST" --locked --all-targets --all-features
cargo clippy --manifest-path "$RUST_MANIFEST" --locked --all-targets --all-features -- -D warnings
./scripts/ci.sh ui-runtime
for locale in en-US ja-JP; do
  SUISUI_CI_VISUAL_GATE_LOCALE="$locale" ./scripts/ci.sh ui-visual
done
./scripts/ci.sh ui-performance
