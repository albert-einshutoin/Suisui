#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
fixture="$(mktemp -d "$ROOT_DIR/.tmp/ui-debug-check.XXXXXX")"
trap 'rm -rf "$fixture"' EXIT
commit="$(git rev-parse HEAD)"
verifier=./script/verify_ui_performance_artifact.sh
"$verifier" .tmp/ui-debug-app "$fixture/accepted" Suisui "$commit" "$fixture/receipt" debug
app="$fixture/accepted/Suisui.app"
./script/verify_ui_debug_app.sh "$app"
# Exercise the portable Seeder away from its SwiftPM build directory.
"$app/Contents/MacOS/SuisuiVisualFixtureSeeder" --create-evidence-home --path "$fixture/home" --evidence-home-marker-token "$(uuidgen)" > "$fixture/seeder-home.txt"
if "$verifier" .tmp/ui-debug-app "$fixture/wrong-revision" Suisui 0000000000000000000000000000000000000000 "$fixture/rejected-receipt" debug; then
  echo 'BLOCKER: wrong revision accepted' >&2; exit 1
fi
if "$verifier" .tmp/ui-debug-app "$fixture/wrong-config" Suisui "$commit" "$fixture/rejected-receipt"; then
  echo 'BLOCKER: debug artifact accepted as release' >&2; exit 1
fi
if ./script/verify_ui_debug_app.sh "$app" invalid-fingerprint; then
  echo 'BLOCKER: wrong build fingerprint accepted' >&2; exit 1
fi
printf '\nmodified\n' >> "$app/Contents/MacOS/SuisuiVisualFixtureSeeder"
if ./script/verify_ui_debug_app.sh "$app"; then
  echo 'BLOCKER: modified Seeder accepted' >&2; exit 1
fi
printf 'OK: debug artifact portability and rejection checks passed\n'
