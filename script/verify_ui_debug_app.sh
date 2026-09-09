#!/usr/bin/env bash
set -euo pipefail
# Recheck the sealed producer bundle before every reuse, including repeated
# Runtime launches. A requested prebuilt app never falls back to compilation.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
failure() { echo "BLOCKER: debug UI app validation failed: $1" >&2; exit 1; }
app="${1:?prebuilt app required}"
[[ -d "$app" && ! -L "$app" ]] || failure bundle
[[ -z "$(git -C "$ROOT_DIR" status --porcelain --untracked-files=normal)" ]] || failure dirty-checkout
plist="$app/Contents/Info.plist"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :SuisuiSourceCommit' "$plist")" == "$(git -C "$ROOT_DIR" rev-parse HEAD)" ]] || failure source-commit
[[ "$(/usr/libexec/PlistBuddy -c 'Print :SuisuiRuntimePolicy' "$plist")" == public-alpha ]] || failure runtime-policy
expected_fingerprint="${2:-$(printf 'schema=1\nruntime-policy=public-alpha\nbuild-configuration=debug\nrelease-purpose=distribution\nsparkle-feed=\nsparkle-key=\nlicense-key=\n' | shasum -a 256 | awk '{print $1}')}"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :SuisuiBuildConfigurationFingerprint' "$plist")" == "$expected_fingerprint" ]] || failure build-fingerprint
[[ -x "$app/Contents/MacOS/SuisuiVisualFixtureSeeder" && ! -L "$app/Contents/MacOS/SuisuiVisualFixtureSeeder" ]] || failure seeder
/usr/bin/codesign --verify --deep --strict "$app"
