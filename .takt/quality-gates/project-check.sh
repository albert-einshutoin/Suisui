#!/usr/bin/env bash
set -euo pipefail

MODE="${TAKT_LOOP_GATE_MODE:-standard}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

case "$MODE" in
  standard|full) ;;
  *)
    printf 'unsupported TAKT_LOOP_GATE_MODE: %s\n' "$MODE" >&2
    exit 2
    ;;
esac

run() {
  printf '\n==> %s\n' "$*"
  "$@"
}

cd "$ROOT_DIR"

# Keep TAKT aligned with the repository's documented CI entrypoints so an
# automated fix cannot pass a weaker, automation-only verification path.
run git diff --check
run ./script/check_takt_configuration.sh
run ./scripts/ci.sh swiftpm
run ./script/check_security_regressions.sh

if [[ "$MODE" == "full" ]]; then
  run swift test
fi
