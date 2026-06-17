#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPARKLE_ENV_FILE="$ROOT_DIR/packaging/sparkle.env"

if [[ -f "$SPARKLE_ENV_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$SPARKLE_ENV_FILE"
fi

RELEASE_DIR="${SOLOPM_SPARKLE_RELEASE_DIR:-$ROOT_DIR/dist/releases}"
DOWNLOAD_URL_PREFIX="${SOLOPM_SPARKLE_DOWNLOAD_URL_PREFIX:-}"
REQUIRE_SPARKLE_TOOLS="${SOLOPM_REQUIRE_SPARKLE_TOOLS:-1}"

case "$REQUIRE_SPARKLE_TOOLS" in
  0|1)
    ;;
  *)
    echo "SOLOPM_REQUIRE_SPARKLE_TOOLS must be 0 or 1" >&2
    exit 2
    ;;
esac

candidate_bin_dirs=()
if [[ -n "${SOLOPM_SPARKLE_BIN_DIR:-}" ]]; then
  candidate_bin_dirs+=("$SOLOPM_SPARKLE_BIN_DIR")
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
    echo "Sparkle generate_appcast tool was not found; skipped because SOLOPM_REQUIRE_SPARKLE_TOOLS=0."
    exit 0
  fi

  echo "Sparkle generate_appcast tool was not found." >&2
  echo "Set SOLOPM_SPARKLE_BIN_DIR to the Sparkle bin directory from the SwiftPM artifact." >&2
  exit 2
fi

if [[ ! -d "$RELEASE_DIR" ]]; then
  echo "missing release artifact directory: $RELEASE_DIR" >&2
  exit 2
fi

if ! find "$RELEASE_DIR" -maxdepth 1 \( -name "*.dmg" -o -name "*.zip" \) | grep -q .; then
  echo "no DMG or ZIP artifacts found in $RELEASE_DIR" >&2
  exit 2
fi

if [[ -n "$DOWNLOAD_URL_PREFIX" ]]; then
  "$GENERATE_APPCAST" --download-url-prefix "$DOWNLOAD_URL_PREFIX" "$RELEASE_DIR"
else
  "$GENERATE_APPCAST" "$RELEASE_DIR"
fi
echo "Generated Sparkle appcast in $RELEASE_DIR."
