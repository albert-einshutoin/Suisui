#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 4 ]]; then
  echo "usage: $0 <swiftpm-scratch-path> <product-directory> <configuration> <product-name>" >&2
  exit 2
fi

SCRATCH_PATH="${1%/}"
PRODUCT_DIRECTORY="${2%/}"
CONFIGURATION="$3"
PRODUCT_NAME="$4"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ACCESSOR_NORMALIZER="$ROOT_DIR/script/normalize_swiftpm_resource_accessors.sh"
MANIFEST_PREPARER="$ROOT_DIR/script/prepare_swiftpm_relink_manifest.sh"

if [[ ! -d "$SCRATCH_PATH" || -L "$SCRATCH_PATH" ||
      ! -d "$PRODUCT_DIRECTORY" || -L "$PRODUCT_DIRECTORY" ]]; then
  echo "BLOCKER: native SwiftPM build directories are unavailable" >&2
  exit 1
fi
if [[ "$CONFIGURATION" != "debug" && "$CONFIGURATION" != "release" ]]; then
  echo "BLOCKER: native SwiftPM relink configuration must be debug or release" >&2
  exit 2
fi
if [[ ! "$PRODUCT_NAME" =~ ^[A-Za-z0-9_]+$ ]]; then
  echo "BLOCKER: native SwiftPM relink product name is invalid" >&2
  exit 2
fi
if [[ ! -x "$ACCESSOR_NORMALIZER" || ! -x "$MANIFEST_PREPARER" ]]; then
  echo "BLOCKER: native SwiftPM relink helpers are unavailable" >&2
  exit 1
fi

PLAN="$SCRATCH_PATH/$CONFIGURATION.yaml"
TARGET_TRIPLE="$(basename "$(dirname "$PRODUCT_DIRECTORY")")"
if [[ ! "$TARGET_TRIPLE" =~ ^[A-Za-z0-9_-]+$ || "$(basename "$PRODUCT_DIRECTORY")" != "$CONFIGURATION" ]]; then
  echo "BLOCKER: native SwiftPM product directory does not match the requested configuration" >&2
  exit 1
fi
PRODUCT_BINARY="$PRODUCT_DIRECTORY/$PRODUCT_NAME"
if [[ ! -f "$PRODUCT_BINARY" || -L "$PRODUCT_BINARY" ]]; then
  echo "BLOCKER: native SwiftPM product binary is unavailable" >&2
  exit 1
fi

TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/suisui-swiftpm-relink.XXXXXX")"
trap '/bin/rm -rf "$TEMP_ROOT"' EXIT
STANDALONE_PLAN="$TEMP_ROOT/$CONFIGURATION.yaml"
RELINK_LOG="$TEMP_ROOT/relink.log"

"$ACCESSOR_NORMALIZER" "$PRODUCT_DIRECTORY"
"$MANIFEST_PREPARER" "$PLAN" "$STANDALONE_PLAN"

if ! SWIFT_BUILD_TOOL="$(/usr/bin/xcrun --find swift-build-tool 2>/dev/null)" ||
   [[ ! -x "$SWIFT_BUILD_TOOL" || -L "$SWIFT_BUILD_TOOL" ]]; then
  echo "BLOCKER: swift-build-tool is unavailable" >&2
  exit 1
fi
if ! ACTIVE_SDK_PATH="$(/usr/bin/xcrun --sdk macosx --show-sdk-path 2>/dev/null)" ||
   [[ ! -d "$ACTIVE_SDK_PATH" ]]; then
  echo "BLOCKER: active macOS SDK path is unavailable" >&2
  exit 1
fi

TARGET_NAME="$PRODUCT_NAME-$TARGET_TRIPLE-$CONFIGURATION.exe"
if ! SDKROOT="$ACTIVE_SDK_PATH" "$SWIFT_BUILD_TOOL" \
  -f "$STANDALONE_PLAN" --no-db "$TARGET_NAME" >"$RELINK_LOG" 2>&1; then
  echo "BLOCKER: normalized native SwiftPM product relink failed" >&2
  /usr/bin/tail -n 200 "$RELINK_LOG" >&2 || true
  exit 1
fi

for bundle_name in Suisui_Suisui.bundle Suisui_SuisuiCore.bundle SwiftTerm_SwiftTerm.bundle; do
  if /usr/bin/strings "$PRODUCT_BINARY" | /usr/bin/grep -F "$PRODUCT_DIRECTORY/$bundle_name" >/dev/null; then
    echo "BLOCKER: native SwiftPM product retains a machine-local resource fallback: $bundle_name" >&2
    exit 1
  fi
done

printf 'OK: relinked native SwiftPM product with portable resource accessors\n'
