#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
METADATA_FILE="$ROOT_DIR/packaging/app_metadata.env"
ENTITLEMENTS_FILE="$ROOT_DIR/packaging/Suisui.entitlements"
PLIST_BUDDY="/usr/libexec/PlistBuddy"

# shellcheck source=/dev/null
source "$METADATA_FILE"

INFO_PLIST="$ROOT_DIR/dist/$APP_NAME.app/Contents/Info.plist"

read_key() {
  "$PLIST_BUDDY" -c "Print :$1" "$INFO_PLIST"
}

build_bundle() {
  local configuration="$1"
  SUISUI_BUILD_CONFIGURATION="$configuration" "$ROOT_DIR/script/build_and_run.sh" --build-only >/dev/null
}

assert_eq() {
  local actual="$1"
  local expected="$2"
  local label="$3"

  if [[ "$actual" != "$expected" ]]; then
    echo "$label mismatch: expected '$expected', got '$actual'" >&2
    exit 1
  fi
}

assert_metadata_matches() {
  local label="$1"
  local icon_file

  assert_eq "$(read_key CFBundleExecutable)" "$APP_NAME" "$label CFBundleExecutable"
  assert_eq "$(read_key CFBundleIdentifier)" "$BUNDLE_IDENTIFIER" "$label CFBundleIdentifier"
  assert_eq "$(read_key CFBundleName)" "$APP_NAME" "$label CFBundleName"
  assert_eq "$(read_key CFBundleDisplayName)" "$APP_NAME" "$label CFBundleDisplayName"
  assert_eq "$(read_key CFBundlePackageType)" "APPL" "$label CFBundlePackageType"
  assert_eq "$(read_key CFBundleShortVersionString)" "$MARKETING_VERSION" "$label CFBundleShortVersionString"
  assert_eq "$(read_key CFBundleVersion)" "$CURRENT_PROJECT_VERSION" "$label CFBundleVersion"
  assert_eq "$(read_key LSApplicationCategoryType)" "$APP_CATEGORY" "$label LSApplicationCategoryType"
  assert_eq "$(read_key LSMinimumSystemVersion)" "$MIN_SYSTEM_VERSION" "$label LSMinimumSystemVersion"
  assert_eq "$(read_key NSHumanReadableCopyright)" "$COPYRIGHT" "$label NSHumanReadableCopyright"
  icon_file="$(read_key CFBundleIconFile)"
  assert_eq "$icon_file" "Suisui.icns" "$label CFBundleIconFile"
  if [[ ! -s "$ROOT_DIR/dist/$APP_NAME.app/Contents/Resources/$icon_file" ]]; then
    echo "$label missing bundled app icon: Contents/Resources/$icon_file" >&2
    exit 1
  fi
}

build_bundle debug
DEBUG_BUNDLE_ID="$(read_key CFBundleIdentifier)"
DEBUG_VERSION="$(read_key CFBundleShortVersionString)"
DEBUG_BUILD="$(read_key CFBundleVersion)"
DEBUG_CATEGORY="$(read_key LSApplicationCategoryType)"
assert_metadata_matches "debug"

build_bundle release
assert_metadata_matches "release"
assert_eq "$(read_key CFBundleIdentifier)" "$DEBUG_BUNDLE_ID" "Debug/Release CFBundleIdentifier"
assert_eq "$(read_key CFBundleShortVersionString)" "$DEBUG_VERSION" "Debug/Release CFBundleShortVersionString"
assert_eq "$(read_key CFBundleVersion)" "$DEBUG_BUILD" "Debug/Release CFBundleVersion"
assert_eq "$(read_key LSApplicationCategoryType)" "$DEBUG_CATEGORY" "Debug/Release LSApplicationCategoryType"

plutil -lint "$ENTITLEMENTS_FILE" >/dev/null
ENTITLEMENT_KEY_COUNT="$("$PLIST_BUDDY" -c "Print" "$ENTITLEMENTS_FILE" | sed -n '/=/p' | wc -l | tr -d ' ')"
assert_eq "$ENTITLEMENT_KEY_COUNT" "1" "entitlement key count"
assert_eq \
  "$("$PLIST_BUDDY" -c "Print :com.apple.security.device.audio-input" "$ENTITLEMENTS_FILE")" \
  "true" \
  "audio-input entitlement"

echo "Bundle metadata verified for debug and release."
