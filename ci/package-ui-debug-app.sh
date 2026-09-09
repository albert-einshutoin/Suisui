#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source packaging/app_metadata.env
# The successful parent gate already built this app. Never relabel a stale or
# dirty build with the current commit when publishing it to another runner.
app="dist/$APP_NAME.app"
commit="$(git rev-parse HEAD)"
[[ -z "$(git status --porcelain --untracked-files=normal)" ]] || { echo "BLOCKER: dirty checkout" >&2; exit 1; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print :SuisuiSourceCommit' "$app/Contents/Info.plist")" == "$commit" ]] || { echo "BLOCKER: stale parent app" >&2; exit 1; }
args=(--arch arm64 --cache-path "$ROOT_DIR/.build/swiftpm-cache" --manifest-cache local --scratch-path "$ROOT_DIR/.build/app-package")
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT_DIR/.build/module-cache"
swift build "${args[@]}" --product SuisuiVisualFixtureSeeder
bin="$(swift build "${args[@]}" --show-bin-path)"
./script/relink_normalized_swiftpm_product.sh "$ROOT_DIR/.build/app-package" "$bin" debug SuisuiVisualFixtureSeeder
# Bundle.main then resolves the same portable Core resources as the app.
cp "$bin/SuisuiVisualFixtureSeeder" "$app/Contents/MacOS/SuisuiVisualFixtureSeeder"
codesign --force --deep --sign - "$app"
codesign --verify --deep --strict "$app"
artifact=.tmp/ui-debug-app
mkdir -p "$artifact"
COPYFILE_DISABLE=1 /usr/bin/tar -czf "$artifact/$APP_NAME.app.tar.gz" -C dist "$APP_NAME.app"
sha="$(shasum -a 256 "$artifact/$APP_NAME.app.tar.gz" | awk '{print $1}')"
printf 'format_version=1\nsource_commit=%s\nbuild_configuration=debug\narchive_sha256=%s\n' "$commit" "$sha" > "$artifact/manifest.env"
# Keep rejection behavior executable on the producer before uploading.
./ci/check-ui-debug-artifact.sh
