#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPARKLE_ENV_FILE="$ROOT_DIR/packaging/sparkle.env"

if [[ "${SUISUI_LOAD_LOCAL_RELEASE_CONFIG:-1}" == "1" && -f "$SPARKLE_ENV_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$SPARKLE_ENV_FILE"
fi

BUILD_CONFIGURATION="${SUISUI_BUILD_CONFIGURATION:-debug}"
SPARKLE_FEED_URL="${SUISUI_SPARKLE_FEED_URL:-${SPARKLE_FEED_URL:-}}"
SPARKLE_PUBLIC_ED_KEY="${SUISUI_SPARKLE_PUBLIC_ED_KEY:-${SPARKLE_PUBLIC_ED_KEY:-}}"

case "$BUILD_CONFIGURATION" in
  debug|release)
    ;;
  *)
    echo "SUISUI_BUILD_CONFIGURATION must be debug or release" >&2
    exit 2
    ;;
esac

if [[ -n "$SPARKLE_FEED_URL" && -z "$SPARKLE_PUBLIC_ED_KEY" ]]; then
  echo "SUISUI_SPARKLE_PUBLIC_ED_KEY is required when SUISUI_SPARKLE_FEED_URL is set" >&2
  exit 2
fi

if [[ -z "$SPARKLE_FEED_URL" && -n "$SPARKLE_PUBLIC_ED_KEY" ]]; then
  echo "SUISUI_SPARKLE_FEED_URL is required when SUISUI_SPARKLE_PUBLIC_ED_KEY is set" >&2
  exit 2
fi

if [[ "$BUILD_CONFIGURATION" == "release" ]]; then
  if [[ -z "$SPARKLE_FEED_URL" ]]; then
    echo "SUISUI_SPARKLE_FEED_URL is required for release builds" >&2
    exit 2
  fi

  if [[ -z "$SPARKLE_PUBLIC_ED_KEY" ]]; then
    echo "SUISUI_SPARKLE_PUBLIC_ED_KEY is required for release builds" >&2
    exit 2
  fi

  case "$SPARKLE_PUBLIC_ED_KEY" in
    base64-public-key-from-generate_keys|"<public key from generate_keys>")
      echo "SUISUI_SPARKLE_PUBLIC_ED_KEY must not use a placeholder key for release builds" >&2
      exit 2
      ;;
  esac

  if ! [[ "$SPARKLE_PUBLIC_ED_KEY" =~ ^[A-Za-z0-9+/=]{32,}$ ]]; then
    echo "SUISUI_SPARKLE_PUBLIC_ED_KEY must be a base64 EdDSA public key for release builds" >&2
    exit 2
  fi

  case "$SPARKLE_FEED_URL" in
    https://*)
      ;;
    *)
      echo "SUISUI_SPARKLE_FEED_URL must use https for release builds" >&2
      exit 2
      ;;
  esac

  case "$SPARKLE_FEED_URL" in
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
      echo "SUISUI_SPARKLE_FEED_URL must not use placeholder or local domains for release builds" >&2
      exit 2
      ;;
  esac
fi

if [[ "${SUISUI_SPARKLE_CONFIG_QUIET:-0}" != "1" ]]; then
  echo "Sparkle release config is valid."
fi
