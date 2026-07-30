#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
METADATA_FILE="$ROOT_DIR/packaging/app_metadata.env"

if [[ ! -f "$METADATA_FILE" ]]; then
  echo "missing metadata file: $METADATA_FILE" >&2
  exit 2
fi

# shellcheck source=/dev/null
source "$METADATA_FILE"

APP_NAME="${APP_NAME:?APP_NAME is required}"
APP_BUNDLE="${1:-$ROOT_DIR/dist/$APP_NAME.app}"
APP_EXECUTABLE="$(plutil -extract CFBundleExecutable raw -o - "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || true)"
if [[ -z "$APP_EXECUTABLE" ]]; then
  if [[ -f "$APP_BUNDLE/Contents/MacOS/$APP_NAME" ]]; then
    APP_EXECUTABLE="$APP_NAME"
  else
    # Test/staging bundles may deliberately use a legacy bundle name without
    # an Info.plist. Falling back to that name keeps preparation independent
    # from the public brand while production still uses CFBundleExecutable.
    APP_EXECUTABLE="$(basename "$APP_BUNDLE" .app)"
  fi
fi
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_EXECUTABLE"
STRIP_TOOL="${SUISUI_STRIP_TOOL:-/usr/bin/strip}"
ENABLE_STRIP="${SUISUI_RELEASE_STRIP:-1}"
ENABLE_SPARKLE_PRUNE="${SUISUI_RELEASE_PRUNE_SPARKLE:-1}"
PREPARATION_MARKER="$APP_BUNDLE/Contents/Resources/release-preparation.env"

for value_name in ENABLE_STRIP ENABLE_SPARKLE_PRUNE; do
  value="${!value_name}"
  if [[ "$value" != "0" && "$value" != "1" ]]; then
    echo "${value_name} must be 0 or 1" >&2
    exit 2
  fi
done

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "missing app bundle: $APP_BUNDLE" >&2
  exit 2
fi

if [[ ! -x "$APP_BINARY" && ! -f "$APP_BINARY" ]]; then
  echo "missing app binary: $APP_BINARY" >&2
  exit 2
fi

if [[ "$ENABLE_STRIP" == "1" ]]; then
  if [[ ! -x "$STRIP_TOOL" ]]; then
    echo "strip tool is not executable: $STRIP_TOOL" >&2
    exit 2
  fi
  # Strip before any distribution signature. Mutating a signed Mach-O would
  # invalidate both Developer ID and notarization evidence.
  "$STRIP_TOOL" -x "$APP_BINARY"
  strip_mode="local-symbols-removed"
else
  strip_mode="disabled"
fi

sparkle_prune_mode="not-present"
sparkle_framework="$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
if [[ -d "$sparkle_framework" ]]; then
  sparkle_prune_mode="disabled"
  if [[ "$ENABLE_SPARKLE_PRUNE" == "1" ]]; then
    shopt -s nullglob
    prune_paths=(
      "$sparkle_framework/Headers"
      "$sparkle_framework/PrivateHeaders"
      "$sparkle_framework/Modules"
      "$sparkle_framework"/Versions/*/Headers
      "$sparkle_framework"/Versions/*/PrivateHeaders
      "$sparkle_framework"/Versions/*/Modules
    )
    rm -rf "${prune_paths[@]}"

    app_resources="$APP_BUNDLE/Contents/Resources"
    for sparkle_version in "$sparkle_framework"/Versions/*; do
      # Current is a symlink to the canonical version. Pruning only canonical
      # directories avoids traversing and mutating the same resources twice.
      [[ -L "$sparkle_version" ]] && continue
      for sparkle_locale in "$sparkle_version"/Resources/*.lproj; do
        locale_name="$(basename "$sparkle_locale")"
        if [[ "$locale_name" == "Base.lproj" ]]; then
          continue
        fi

        keep_locale=0
        for app_locale in "$app_resources"/*.lproj; do
          if [[ "$(basename "$app_locale")" == "$locale_name" ]]; then
            keep_locale=1
            break
          fi
        done
        if [[ "$keep_locale" == "0" ]]; then
          # Sparkle ships every supported translation, while Suisui currently
          # exposes only its bundled app locales. Removing unreachable updater
          # translations before signing keeps the update ZIP within its fixed
          # production budget without weakening the runtime or size gate.
          rm -rf "$sparkle_locale"
        fi
      done
    done
    shopt -u nullglob
    sparkle_prune_mode="development-assets-removed"
  fi

  for runtime_path in Resources Autoupdate Updater.app XPCServices; do
    if ! find "$sparkle_framework" -name "$runtime_path" -print -quit | grep -q .; then
      echo "Sparkle runtime component disappeared during pruning: $runtime_path" >&2
      exit 2
    fi
  done
fi

mkdir -p "$(dirname "$PREPARATION_MARKER")"
{
  printf 'STRIP_MODE=%s\n' "$strip_mode"
  printf 'SPARKLE_PRUNE_MODE=%s\n' "$sparkle_prune_mode"
} >"$PREPARATION_MARKER"

printf 'OK: release bundle prepared before signing (strip=%s sparkle=%s)\n' \
  "$strip_mode" "$sparkle_prune_mode"
