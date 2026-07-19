#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_PNG="${1:-$ROOT_DIR/packaging/SoloPM-AppIcon-1024.png}"
OUTPUT_ICNS="${2:-$ROOT_DIR/packaging/SoloPM.icns}"
TMP_ROOT="${SOLOPM_TMP_ROOT:-$ROOT_DIR/.tmp}"

if [[ ! -f "$SOURCE_PNG" ]]; then
  printf 'missing app icon source: %s\n' "$SOURCE_PNG" >&2
  exit 2
fi

width="$(sips -g pixelWidth "$SOURCE_PNG" | awk '/pixelWidth:/ { print $2 }')"
height="$(sips -g pixelHeight "$SOURCE_PNG" | awk '/pixelHeight:/ { print $2 }')"
if [[ "$width" != 1024 || "$height" != 1024 ]]; then
  printf 'app icon source must be exactly 1024x1024 pixels: %s is %sx%s\n' "$SOURCE_PNG" "$width" "$height" >&2
  exit 2
fi

mkdir -p "$TMP_ROOT" "$(dirname "$OUTPUT_ICNS")"
ICON_TMP_ROOT="$(mktemp -d "$TMP_ROOT/solopm-app-icon.XXXXXX")"
ICONSET="$ICON_TMP_ROOT/SoloPM.iconset"
mkdir -p "$ICONSET"
trap 'rm -rf "$ICON_TMP_ROOT"' EXIT

# macOS consumes a multi-representation ICNS. Keeping every standard and Retina
# representation prevents the Dock and Finder from scaling one large raster at runtime.
sips -z 16 16 "$SOURCE_PNG" --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32 "$SOURCE_PNG" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$SOURCE_PNG" --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64 "$SOURCE_PNG" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$SOURCE_PNG" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256 "$SOURCE_PNG" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$SOURCE_PNG" --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512 "$SOURCE_PNG" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$SOURCE_PNG" --out "$ICONSET/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$SOURCE_PNG" --out "$ICONSET/icon_512x512@2x.png" >/dev/null

iconutil -c icns "$ICONSET" -o "$OUTPUT_ICNS"
printf 'App icon generated: %s\n' "$OUTPUT_ICNS"
