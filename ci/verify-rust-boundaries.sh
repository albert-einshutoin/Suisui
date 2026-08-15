#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REQUIRE_CARGO=0

case "${1:-}" in
  "") ;;
  --require-cargo) REQUIRE_CARGO=1 ;;
  *)
    echo "usage: $0 [--require-cargo]" >&2
    exit 2
    ;;
esac

if ! command -v cargo >/dev/null 2>&1; then
  if [[ "$REQUIRE_CARGO" == "1" ]]; then
    echo "BLOCKER: cargo is required for Rust boundary validation" >&2
    exit 1
  fi
  # Keep the Swift-only local full-validation contract usable on machines that
  # do not install Rust, while hosted validation requires Cargo explicitly.
  echo "INFO: cargo is unavailable; skipping Rust boundary validation locally"
  exit 0
fi

if ! command -v rustc >/dev/null 2>&1; then
  echo "BLOCKER: rustc is required for Rust boundary validation" >&2
  exit 1
fi

cd "$ROOT_DIR"
rustc --version
cargo --version

cargo fmt --manifest-path rust/kokoro-helper/Cargo.toml --check
cargo test --manifest-path rust/kokoro-helper/Cargo.toml --locked --all-targets --all-features
cargo clippy --manifest-path rust/kokoro-helper/Cargo.toml --locked --all-targets --all-features -- -D warnings
cargo fmt --manifest-path rust/embedding-helper/Cargo.toml --check
cargo test --manifest-path rust/embedding-helper/Cargo.toml --locked --all-targets --all-features
cargo clippy --manifest-path rust/embedding-helper/Cargo.toml --locked --all-targets --all-features -- -D warnings
