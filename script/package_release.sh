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
MARKETING_VERSION="${MARKETING_VERSION:?MARKETING_VERSION is required}"
CURRENT_PROJECT_VERSION="${CURRENT_PROJECT_VERSION:?CURRENT_PROJECT_VERSION is required}"
PACKAGE_FORMAT="${SOLOPM_PACKAGE_FORMAT:-dmg}"
REQUIRE_SIGNED_PACKAGE="${SOLOPM_REQUIRE_SIGNED_PACKAGE:-1}"
REQUIRE_NOTARIZED_PACKAGE="${SOLOPM_REQUIRE_NOTARIZED_PACKAGE:-1}"

DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
PACKAGE_APP_BUNDLE="$APP_BUNDLE"
RELEASE_DIR="$DIST_DIR/releases"
SMOKE_RELEASE_DIR="$DIST_DIR/package-smoke"
STAGING_DIR="$DIST_DIR/package-staging"
ARTIFACT_BASENAME="$APP_NAME-$MARKETING_VERSION+$CURRENT_PROJECT_VERSION"
DMG_PATH="$RELEASE_DIR/$ARTIFACT_BASENAME.dmg"
ZIP_PATH="$RELEASE_DIR/$ARTIFACT_BASENAME.zip"
PACKAGE_CREATED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

current_git_commit() {
  if command -v git >/dev/null 2>&1 && git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "$ROOT_DIR" rev-parse HEAD 2>/dev/null || true
  fi
}

SOURCE_GIT_COMMIT="$(current_git_commit)"

case "$PACKAGE_FORMAT" in
  dmg|zip|all)
    ;;
  *)
    echo "SOLOPM_PACKAGE_FORMAT must be dmg, zip, or all" >&2
    exit 2
    ;;
esac

case "$REQUIRE_SIGNED_PACKAGE" in
  0|1)
    ;;
  *)
    echo "SOLOPM_REQUIRE_SIGNED_PACKAGE must be 0 or 1" >&2
    exit 2
    ;;
esac

case "$REQUIRE_NOTARIZED_PACKAGE" in
  0|1)
    ;;
  *)
    echo "SOLOPM_REQUIRE_NOTARIZED_PACKAGE must be 0 or 1" >&2
    exit 2
    ;;
esac

if [[ ! -d "$APP_BUNDLE" ]]; then
  SOLOPM_BUILD_CONFIGURATION=release "$ROOT_DIR/script/build_and_run.sh" --build-only
fi

# Production gates always inspect the immutable signed source bundle. Unsigned
# smoke preparation happens later on a disposable copy so this script can never
# invalidate a Developer ID signature on dist/SoloPM.app.
if [[ "$REQUIRE_SIGNED_PACKAGE" == "1" ]]; then
  codesign --verify --strict --deep --verbose=2 "$APP_BUNDLE"
fi

if [[ "$REQUIRE_NOTARIZED_PACKAGE" == "1" ]]; then
  xcrun stapler validate "$APP_BUNDLE"
  spctl -a -vv "$APP_BUNDLE"
fi

SMOKE_APP_ROOT=""
cleanup_smoke_app() {
  if [[ -n "$SMOKE_APP_ROOT" ]]; then
    rm -rf "$SMOKE_APP_ROOT"
  fi
}
trap cleanup_smoke_app EXIT INT TERM

if [[ "$REQUIRE_SIGNED_PACKAGE" == "0" || "$REQUIRE_NOTARIZED_PACKAGE" == "0" ]]; then
  RELEASE_DIR="$SMOKE_RELEASE_DIR"
  DMG_PATH="$RELEASE_DIR/$ARTIFACT_BASENAME.dmg"
  ZIP_PATH="$RELEASE_DIR/$ARTIFACT_BASENAME.zip"
fi

if [[ "$REQUIRE_SIGNED_PACKAGE" == "0" ]]; then
  SMOKE_APP_ROOT="$(mktemp -d "$DIST_DIR/package-smoke-app.XXXXXX")"
  PACKAGE_APP_BUNDLE="$SMOKE_APP_ROOT/$APP_NAME.app"
  COPYFILE_DISABLE=1 ditto --norsrc --noextattr "$APP_BUNDLE" "$PACKAGE_APP_BUNDLE"
  "$ROOT_DIR/script/prepare_release_bundle.sh" "$PACKAGE_APP_BUNDLE"
fi

APP_BINARY="$PACKAGE_APP_BUNDLE/Contents/MacOS/$APP_NAME"
PREPARATION_MARKER="$PACKAGE_APP_BUNDLE/Contents/Resources/release-preparation.env"

"$ROOT_DIR/script/check_release_bundle_inventory.sh" "$PACKAGE_APP_BUNDLE"

APP_BUNDLE_BYTES="$(find "$PACKAGE_APP_BUNDLE" -type f -exec stat -f '%z' {} + | awk '{ total += $1 } END { printf "%.0f", total }')"
APP_BINARY_BYTES="$(stat -f '%z' "$APP_BINARY")"
STRIP_MODE="unknown"
SPARKLE_PRUNE_MODE="unknown"
if [[ -f "$PREPARATION_MARKER" ]]; then
  STRIP_MODE="$(awk -F= '$1 == "STRIP_MODE" { print $2; exit }' "$PREPARATION_MARKER")"
  SPARKLE_PRUNE_MODE="$(awk -F= '$1 == "SPARKLE_PRUNE_MODE" { print $2; exit }' "$PREPARATION_MARKER")"
fi

if [[ "$STRIP_MODE" != "local-symbols-removed" ]]; then
  echo "release app was not stripped before signing; rebuild with ./script/sign_app.sh" >&2
  exit 2
fi
if [[ "$SPARKLE_PRUNE_MODE" != "development-assets-removed" ]]; then
  echo "Sparkle development assets were not pruned before signing; rebuild with ./script/sign_app.sh" >&2
  exit 2
fi

rm -rf "$RELEASE_DIR" "$STAGING_DIR"
mkdir -p "$RELEASE_DIR" "$STAGING_DIR"

json_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  printf "%s" "$value"
}

create_package_evidence() {
  local artifact_path="$1"
  local package_format="$2"
  local manifest_path="$artifact_path.package-evidence.json"
  local artifact_relative_path="${artifact_path#"$ROOT_DIR/"}"
  local artifact_bytes
  artifact_bytes="$(stat -f '%z' "$artifact_path")"

  {
    printf '{\n'
    printf '  "package": {\n'
    printf '    "artifactPath": "%s",\n' "$(json_escape "$artifact_relative_path")"
    printf '    "format": "%s",\n' "$(json_escape "$package_format")"
    printf '    "createdAt": "%s",\n' "$PACKAGE_CREATED_AT"
    printf '    "signedPackageRequired": %s,\n' "$([[ "$REQUIRE_SIGNED_PACKAGE" == "1" ]] && printf true || printf false)"
    printf '    "notarizedPackageRequired": %s,\n' "$([[ "$REQUIRE_NOTARIZED_PACKAGE" == "1" ]] && printf true || printf false)"
    printf '    "appBundleBytes": %s,\n' "$APP_BUNDLE_BYTES"
    printf '    "appBinaryBytes": %s,\n' "$APP_BINARY_BYTES"
    printf '    "artifactBytes": %s,\n' "$artifact_bytes"
    printf '    "stripMode": "%s",\n' "$(json_escape "$STRIP_MODE")"
    printf '    "sparklePruneMode": "%s"\n' "$(json_escape "$SPARKLE_PRUNE_MODE")"
    printf '  },\n'
    printf '  "source": {\n'
    printf '    "gitCommit": "%s"\n' "$(json_escape "$SOURCE_GIT_COMMIT")"
    printf '  }\n'
    printf '}\n'
  } >"$manifest_path"
}

create_checksum() {
  local artifact_path="$1"
  shasum -a 256 "$artifact_path" >"$artifact_path.sha256"
}

if [[ "$PACKAGE_FORMAT" == "dmg" || "$PACKAGE_FORMAT" == "all" ]]; then
  cp -R "$PACKAGE_APP_BUNDLE" "$STAGING_DIR/"
  ln -s /Applications "$STAGING_DIR/Applications"
  hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"
  if [[ "$REQUIRE_NOTARIZED_PACKAGE" == "1" ]]; then
    "$ROOT_DIR/script/notarize_release_dmg.sh" "$DMG_PATH"
    "$ROOT_DIR/script/verify_dmg_notarization_evidence.sh" "$DMG_PATH"
  fi
  "$ROOT_DIR/script/check_release_artifact_size.sh" "$DMG_PATH" "dmg"
  create_checksum "$DMG_PATH"
  create_package_evidence "$DMG_PATH" "dmg"
fi

if [[ "$PACKAGE_FORMAT" == "zip" || "$PACKAGE_FORMAT" == "all" ]]; then
  COPYFILE_DISABLE=1 ditto -c -k --keepParent --norsrc --noextattr "$PACKAGE_APP_BUNDLE" "$ZIP_PATH"
  "$ROOT_DIR/script/check_release_artifact_size.sh" "$ZIP_PATH" "zip"
  create_checksum "$ZIP_PATH"
  create_package_evidence "$ZIP_PATH" "zip"
fi

echo "Release artifacts:"
find "$RELEASE_DIR" -maxdepth 1 -type f -print | sort
