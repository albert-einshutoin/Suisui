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
env -u SUISUI_CI_VISUAL_GATE_LOCALE ./scripts/ci.sh ui-visual
./scripts/ci.sh ui-performance
