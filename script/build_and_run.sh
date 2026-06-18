#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
METADATA_FILE="$ROOT_DIR/packaging/app_metadata.env"
SPARKLE_ENV_FILE="$ROOT_DIR/packaging/sparkle.env"

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
    swift build --product "$APP_NAME"
    BUILD_DIR="$(swift build --show-bin-path)"
    ;;
  release)
    swift build -c release --product "$APP_NAME"
    BUILD_DIR="$(swift build -c release --show-bin-path)"
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

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_IDENTIFIER</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$MARKETING_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$CURRENT_PROJECT_VERSION</string>
  <key>LSApplicationCategoryType</key>
  <string>$APP_CATEGORY</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>SoloPM uses the microphone when you explicitly start voice capture.</string>
  <key>NSHumanReadableCopyright</key>
  <string>$COPYRIGHT</string>
</dict>
</plist>
PLIST

if [[ -n "$SPARKLE_FEED_URL" && -n "$SPARKLE_PUBLIC_ED_KEY" ]]; then
  /usr/libexec/PlistBuddy -c "Add :SUFeedURL string $SPARKLE_FEED_URL" "$INFO_PLIST"
  /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $SPARKLE_PUBLIC_ED_KEY" "$INFO_PLIST"
fi

if [[ "$BUILD_CONFIGURATION" == "debug" ]]; then
  codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null
fi

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
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
