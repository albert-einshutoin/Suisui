#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 1 ]]; then
  echo "usage: $0 <mach-o-binary>" >&2
  exit 2
fi

BINARY="$1"
if [[ ! -f "$BINARY" || -L "$BINARY" ]]; then
  echo "BLOCKER: linked macOS SDK verification binary is unavailable" >&2
  exit 1
fi

if ! ACTIVE_SDK_VERSION="$(/usr/bin/xcrun --sdk macosx --show-sdk-version 2>/dev/null)" ||
   [[ ! "$ACTIVE_SDK_VERSION" =~ ^[0-9]+([.][0-9]+){1,2}$ ]]; then
  echo "BLOCKER: active macOS SDK version is unavailable" >&2
  exit 1
fi
if ! BUILD_METADATA="$(/usr/bin/xcrun vtool -show-build "$BINARY" 2>/dev/null)"; then
  echo "BLOCKER: linked macOS SDK metadata is unavailable" >&2
  exit 1
fi

PLATFORM_COUNT="$(printf '%s\n' "$BUILD_METADATA" | /usr/bin/awk '$1 == "platform" && $2 == "MACOS" { count += 1 } END { print count + 0 }')"
LINKED_SDKS="$(printf '%s\n' "$BUILD_METADATA" | /usr/bin/awk '$1 == "sdk" { print $2 }')"
LINKED_SDK_COUNT="$(printf '%s\n' "$LINKED_SDKS" | /usr/bin/sed '/^$/d' | /usr/bin/wc -l | /usr/bin/tr -d '[:space:]')"
LINKED_SDK_VERSION="$(printf '%s\n' "$LINKED_SDKS" | /usr/bin/sed -n '1p')"

# SwiftUI chooses compatibility appearance from LC_BUILD_VERSION. Exact SDK
# equality prevents a fallback toolchain from silently switching every window
# back to the legacy title-bar and control rendering used by older SDKs.
if [[ "$PLATFORM_COUNT" != "1" || "$LINKED_SDK_COUNT" != "1" ||
      "$LINKED_SDK_VERSION" != "$ACTIVE_SDK_VERSION" ]]; then
  echo "BLOCKER: linked macOS SDK mismatch: expected '$ACTIVE_SDK_VERSION', got '${LINKED_SDK_VERSION:-missing}'" >&2
  exit 1
fi

printf "OK: executable is linked against the active macOS SDK (%s)\n" "$LINKED_SDK_VERSION"
