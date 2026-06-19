#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
METADATA_FILE="$ROOT_DIR/packaging/app_metadata.env"
SPARKLE_ENV_FILE="$ROOT_DIR/packaging/sparkle.env"

export TMPDIR="${SOLOPM_TMPDIR:-$ROOT_DIR/.tmp/}"
export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-$ROOT_DIR/.build/module-cache}"
SWIFTPM_CACHE_PATH="${SOLOPM_SWIFTPM_CACHE_PATH:-$ROOT_DIR/.build/swiftpm-cache}"
mkdir -p "$TMPDIR" "$SWIFTPM_MODULECACHE_OVERRIDE" "$SWIFTPM_CACHE_PATH"
SWIFT_BUILD_ARGS=(
  --cache-path "$SWIFTPM_CACHE_PATH"
  --manifest-cache local
)

if [[ ! -f "$METADATA_FILE" ]]; then
  echo "missing metadata file: $METADATA_FILE" >&2
  exit 2
fi

# shellcheck source=/dev/null
source "$METADATA_FILE"

if [[ -f "$SPARKLE_ENV_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$SPARKLE_ENV_FILE"
fi

APP_NAME="${APP_NAME:?APP_NAME is required}"
BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER:?BUNDLE_IDENTIFIER is required}"
APP_CATEGORY="${APP_CATEGORY:?APP_CATEGORY is required}"
MARKETING_VERSION="${MARKETING_VERSION:?MARKETING_VERSION is required}"
CURRENT_PROJECT_VERSION="${CURRENT_PROJECT_VERSION:?CURRENT_PROJECT_VERSION is required}"
MIN_SYSTEM_VERSION="${MIN_SYSTEM_VERSION:?MIN_SYSTEM_VERSION is required}"
COPYRIGHT="${COPYRIGHT:?COPYRIGHT is required}"
BUILD_CONFIGURATION="${SOLOPM_BUILD_CONFIGURATION:-debug}"
SPARKLE_FEED_URL="${SOLOPM_SPARKLE_FEED_URL:-${SPARKLE_FEED_URL:-}}"
SPARKLE_PUBLIC_ED_KEY="${SOLOPM_SPARKLE_PUBLIC_ED_KEY:-${SPARKLE_PUBLIC_ED_KEY:-}}"

DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_FRAMEWORKS="$APP_CONTENTS/Frameworks"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

cd "$ROOT_DIR"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

SOLOPM_SPARKLE_CONFIG_QUIET=1 "$ROOT_DIR/script/validate_sparkle_release_config.sh"

case "$BUILD_CONFIGURATION" in
  debug)
    swift build "${SWIFT_BUILD_ARGS[@]}" --product "$APP_NAME"
    BUILD_DIR="$(swift build "${SWIFT_BUILD_ARGS[@]}" --show-bin-path)"
    ;;
  release)
    swift build "${SWIFT_BUILD_ARGS[@]}" -c release --product "$APP_NAME"
    BUILD_DIR="$(swift build "${SWIFT_BUILD_ARGS[@]}" -c release --show-bin-path)"
    ;;
  *)
    echo "SOLOPM_BUILD_CONFIGURATION must be debug or release" >&2
    exit 2
    ;;
esac

BUILD_BINARY="$BUILD_DIR/$APP_NAME"
RESOURCE_BUNDLE="$BUILD_DIR/SoloPM_SoloPMCore.bundle"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

if ! otool -l "$APP_BINARY" | grep -F "@executable_path/../Frameworks" >/dev/null; then
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_BINARY"
fi

if [[ -d "$RESOURCE_BUNDLE" ]]; then
  mkdir -p "$APP_RESOURCES"
  /usr/bin/ditto "$RESOURCE_BUNDLE" "$APP_RESOURCES"
fi

while IFS= read -r -d '' framework_path; do
  mkdir -p "$APP_FRAMEWORKS"
  /usr/bin/ditto "$framework_path" "$APP_FRAMEWORKS/$(basename "$framework_path")"
done < <(find "$BUILD_DIR" -maxdepth 1 -type d -name "*.framework" -print0)

while IFS= read -r -d '' dylib_path; do
  mkdir -p "$APP_FRAMEWORKS"
  /usr/bin/ditto "$dylib_path" "$APP_FRAMEWORKS/$(basename "$dylib_path")"
done < <(find "$BUILD_DIR" -maxdepth 1 -type f -name "*.dylib" -print0)

{
  printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>'
  printf '%s\n' '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
  printf '%s\n' '<plist version="1.0">'
  printf '%s\n' '<dict>'
  printf '%s\n' '  <key>CFBundleExecutable</key>'
  printf '  <string>%s</string>\n' "$APP_NAME"
  printf '%s\n' '  <key>CFBundleIdentifier</key>'
  printf '  <string>%s</string>\n' "$BUNDLE_IDENTIFIER"
  printf '%s\n' '  <key>CFBundleDisplayName</key>'
  printf '  <string>%s</string>\n' "$APP_NAME"
  printf '%s\n' '  <key>CFBundleName</key>'
  printf '  <string>%s</string>\n' "$APP_NAME"
  printf '%s\n' '  <key>CFBundlePackageType</key>'
  printf '%s\n' '  <string>APPL</string>'
  printf '%s\n' '  <key>CFBundleShortVersionString</key>'
  printf '  <string>%s</string>\n' "$MARKETING_VERSION"
  printf '%s\n' '  <key>CFBundleVersion</key>'
  printf '  <string>%s</string>\n' "$CURRENT_PROJECT_VERSION"
  printf '%s\n' '  <key>LSApplicationCategoryType</key>'
  printf '  <string>%s</string>\n' "$APP_CATEGORY"
  printf '%s\n' '  <key>LSMinimumSystemVersion</key>'
  printf '  <string>%s</string>\n' "$MIN_SYSTEM_VERSION"
  printf '%s\n' '  <key>NSPrincipalClass</key>'
  printf '%s\n' '  <string>NSApplication</string>'
  printf '%s\n' '  <key>NSQuitAlwaysKeepsWindows</key>'
  printf '%s\n' '  <false/>'
  printf '%s\n' '  <key>NSMicrophoneUsageDescription</key>'
  printf '%s\n' '  <string>SoloPM uses the microphone when you explicitly start voice capture.</string>'
  printf '%s\n' '  <key>NSHumanReadableCopyright</key>'
  printf '  <string>%s</string>\n' "$COPYRIGHT"
  printf '%s\n' '</dict>'
  printf '%s\n' '</plist>'
} >"$INFO_PLIST"

if [[ -n "$SPARKLE_FEED_URL" && -n "$SPARKLE_PUBLIC_ED_KEY" ]]; then
  /usr/libexec/PlistBuddy -c "Add :SUFeedURL string $SPARKLE_FEED_URL" "$INFO_PLIST"
  /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $SPARKLE_PUBLIC_ED_KEY" "$INFO_PLIST"
fi

if [[ "$BUILD_CONFIGURATION" == "debug" ]]; then
  codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null
fi

open_app() {
  /usr/bin/open -n -F "$APP_BUNDLE"
  /usr/bin/osascript -e "tell application \"$APP_NAME\" to activate" >/dev/null 2>&1 || true
}

case "$MODE" in
  --build-only|build)
    ;;
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_IDENTIFIER\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--build-only|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
