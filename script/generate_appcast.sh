#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPARKLE_ENV_FILE="$ROOT_DIR/packaging/sparkle.env"

if [[ "${SUISUI_LOAD_LOCAL_RELEASE_CONFIG:-1}" == "1" && -f "$SPARKLE_ENV_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$SPARKLE_ENV_FILE"
fi

RELEASE_DIR="${SUISUI_SPARKLE_RELEASE_DIR:-$ROOT_DIR/dist/releases}"
DOWNLOAD_URL_PREFIX="${SUISUI_SPARKLE_DOWNLOAD_URL_PREFIX:-}"
SPARKLE_ACCOUNT="${SUISUI_SPARKLE_ACCOUNT:-}"
REQUIRE_SPARKLE_TOOLS="${SUISUI_REQUIRE_SPARKLE_TOOLS:-1}"
REQUIRE_RELEASE_APPCAST="${SUISUI_REQUIRE_RELEASE_APPCAST:-0}"
APPCAST_INPUT_DIR=""

cleanup() {
  if [[ -n "$APPCAST_INPUT_DIR" ]]; then
    rm -rf "$APPCAST_INPUT_DIR"
  fi
}
trap cleanup EXIT

case "$REQUIRE_SPARKLE_TOOLS" in
  0|1)
    ;;
  *)
    echo "SUISUI_REQUIRE_SPARKLE_TOOLS must be 0 or 1" >&2
    exit 2
    ;;
esac

case "$REQUIRE_RELEASE_APPCAST" in
  0|1)
    ;;
  *)
    echo "SUISUI_REQUIRE_RELEASE_APPCAST must be 0 or 1" >&2
    exit 2
    ;;
esac

if [[ "$REQUIRE_RELEASE_APPCAST" == "1" ]]; then
  if [[ -z "$DOWNLOAD_URL_PREFIX" ]]; then
    echo "SUISUI_SPARKLE_DOWNLOAD_URL_PREFIX is required for release appcast" >&2
    exit 2
  fi

  case "$DOWNLOAD_URL_PREFIX" in
    https://*)
      ;;
    *)
      echo "SUISUI_SPARKLE_DOWNLOAD_URL_PREFIX must use https for release appcast" >&2
      exit 2
      ;;
  esac

  case "$DOWNLOAD_URL_PREFIX" in
    https://example.com|https://example.com/*|\
    https://*.example.com|https://*.example.com/*|\
    https://example.org|https://example.org/*|\
    https://*.example.org|https://*.example.org/*|\
    https://example.net|https://example.net/*|\
    https://*.example.net|https://*.example.net/*|\
    https://*.invalid|https://*.invalid/*|\
    https://*.test|https://*.test/*|\
    https://localhost|https://localhost/*|\
    https://127.0.0.1|https://127.0.0.1/*|\
    https://0.0.0.0|https://0.0.0.0/*)
      echo "SUISUI_SPARKLE_DOWNLOAD_URL_PREFIX must not use placeholder or local domains for release appcast" >&2
      exit 2
      ;;
  esac

  if [[ "$REQUIRE_SPARKLE_TOOLS" != "1" ]]; then
    echo "SUISUI_REQUIRE_SPARKLE_TOOLS must be 1 for release appcast generation" >&2
    exit 2
  fi
fi

candidate_bin_dirs=()
if [[ -n "${SUISUI_SPARKLE_BIN_DIR:-}" ]]; then
  candidate_bin_dirs+=("$SUISUI_SPARKLE_BIN_DIR")
fi
candidate_bin_dirs+=(
  "$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin"
  "$ROOT_DIR/.build/artifacts/sparkle-project/Sparkle/bin"
)

GENERATE_APPCAST=""
for bin_dir in "${candidate_bin_dirs[@]}"; do
  if [[ -x "$bin_dir/generate_appcast" ]]; then
    GENERATE_APPCAST="$bin_dir/generate_appcast"
    break
  fi
done

if [[ -z "$GENERATE_APPCAST" ]]; then
  if [[ "$REQUIRE_SPARKLE_TOOLS" == "0" ]]; then
    echo "Sparkle generate_appcast tool was not found; skipped because SUISUI_REQUIRE_SPARKLE_TOOLS=0."
    exit 0
  fi

  echo "Sparkle generate_appcast tool was not found." >&2
  echo "Set SUISUI_SPARKLE_BIN_DIR to the Sparkle bin directory from the SwiftPM artifact." >&2
  exit 2
fi

if [[ ! -d "$RELEASE_DIR" ]]; then
  echo "missing release artifact directory: $RELEASE_DIR" >&2
  exit 2
fi

if ! find "$RELEASE_DIR" -maxdepth 1 -type f -name "*.zip" | grep -q .; then
  echo "no ZIP artifacts found in $RELEASE_DIR" >&2
  exit 2
fi

mkdir -p "$ROOT_DIR/.tmp"
APPCAST_INPUT_DIR="$(mktemp -d "$ROOT_DIR/.tmp/sparkle-appcast.XXXXXX")"
# Sparkle treats a DMG and ZIP with the same bundle version as duplicate
# updates. The DMG remains the user-facing download, while the appcast input is
# intentionally limited to ZIP updates and their sidecar evidence.
while IFS= read -r -d '' release_file; do
  cp -p "$release_file" "$APPCAST_INPUT_DIR/"
done < <(find "$RELEASE_DIR" -maxdepth 1 -type f \
  ! -name "*.dmg" \
  ! -name "*.dmg.*" \
  -print0)

if ! find "$APPCAST_INPUT_DIR" -maxdepth 1 -type f -name "*.zip" | grep -q .; then
  echo "no DMG or ZIP artifacts found in $RELEASE_DIR" >&2
  exit 2
fi

GENERATE_APPCAST_ARGS=()
if [[ -n "$SPARKLE_ACCOUNT" ]]; then
  GENERATE_APPCAST_ARGS+=(--account "$SPARKLE_ACCOUNT")
fi
if [[ -n "$DOWNLOAD_URL_PREFIX" ]]; then
  # Sparkle resolves archive names relative to this URL. A missing trailing
  # slash makes Foundation replace the final path component instead of
  # appending the ZIP filename.
  NORMALIZED_DOWNLOAD_URL_PREFIX="${DOWNLOAD_URL_PREFIX%/}/"
  GENERATE_APPCAST_ARGS+=(--download-url-prefix "$NORMALIZED_DOWNLOAD_URL_PREFIX")
fi
"$GENERATE_APPCAST" "${GENERATE_APPCAST_ARGS[@]}" "$APPCAST_INPUT_DIR"
if [[ ! -f "$APPCAST_INPUT_DIR/appcast.xml" ]]; then
  echo "Sparkle generate_appcast did not produce appcast.xml" >&2
  exit 2
fi
cp "$APPCAST_INPUT_DIR/appcast.xml" "$RELEASE_DIR/appcast.xml"
echo "Generated Sparkle appcast in $RELEASE_DIR."
