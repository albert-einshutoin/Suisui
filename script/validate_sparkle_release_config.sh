#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPARKLE_ENV_FILE="$ROOT_DIR/packaging/sparkle.env"

if [[ -f "$SPARKLE_ENV_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$SPARKLE_ENV_FILE"
fi

BUILD_CONFIGURATION="${SOLOPM_BUILD_CONFIGURATION:-debug}"
SPARKLE_FEED_URL="${SOLOPM_SPARKLE_FEED_URL:-${SPARKLE_FEED_URL:-}}"
SPARKLE_PUBLIC_ED_KEY="${SOLOPM_SPARKLE_PUBLIC_ED_KEY:-${SPARKLE_PUBLIC_ED_KEY:-}}"

case "$BUILD_CONFIGURATION" in
  debug|release)
    ;;
  *)
    echo "SOLOPM_BUILD_CONFIGURATION must be debug or release" >&2
    exit 2
    ;;
esac

if [[ -n "$SPARKLE_FEED_URL" && -z "$SPARKLE_PUBLIC_ED_KEY" ]]; then
  echo "SOLOPM_SPARKLE_PUBLIC_ED_KEY is required when SOLOPM_SPARKLE_FEED_URL is set" >&2
  exit 2
fi

if [[ -z "$SPARKLE_FEED_URL" && -n "$SPARKLE_PUBLIC_ED_KEY" ]]; then
  echo "SOLOPM_SPARKLE_FEED_URL is required when SOLOPM_SPARKLE_PUBLIC_ED_KEY is set" >&2
  exit 2
fi

if [[ "$BUILD_CONFIGURATION" == "release" ]]; then
  if [[ -z "$SPARKLE_FEED_URL" ]]; then
    echo "SOLOPM_SPARKLE_FEED_URL is required for release builds" >&2
    exit 2
  fi

  if [[ -z "$SPARKLE_PUBLIC_ED_KEY" ]]; then
    echo "SOLOPM_SPARKLE_PUBLIC_ED_KEY is required for release builds" >&2
    exit 2
  fi

  case "$SPARKLE_PUBLIC_ED_KEY" in
    base64-public-key-from-generate_keys|"<public key from generate_keys>")
      echo "SOLOPM_SPARKLE_PUBLIC_ED_KEY must not use a placeholder key for release builds" >&2
      exit 2
      ;;
  esac

  if ! [[ "$SPARKLE_PUBLIC_ED_KEY" =~ ^[A-Za-z0-9+/=]{32,}$ ]]; then
    echo "SOLOPM_SPARKLE_PUBLIC_ED_KEY must be a base64 EdDSA public key for release builds" >&2
    exit 2
  fi

  case "$SPARKLE_FEED_URL" in
    https://*)
      ;;
    *)
      echo "SOLOPM_SPARKLE_FEED_URL must use https for release builds" >&2
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
      echo "SOLOPM_SPARKLE_FEED_URL must not use placeholder or local domains for release builds" >&2
      exit 2
      ;;
  esac
fi

if [[ "${SOLOPM_SPARKLE_CONFIG_QUIET:-0}" != "1" ]]; then
  echo "Sparkle release config is valid."
fi
