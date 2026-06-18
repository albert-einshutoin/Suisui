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
RELEASE_DIR="$DIST_DIR/releases"
SMOKE_RELEASE_DIR="$DIST_DIR/package-smoke"
STAGING_DIR="$DIST_DIR/package-staging"
ARTIFACT_BASENAME="$APP_NAME-$MARKETING_VERSION+$CURRENT_PROJECT_VERSION"
DMG_PATH="$RELEASE_DIR/$ARTIFACT_BASENAME.dmg"
ZIP_PATH="$RELEASE_DIR/$ARTIFACT_BASENAME.zip"
PACKAGE_CREATED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

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

if [[ "$REQUIRE_SIGNED_PACKAGE" == "1" ]]; then
  codesign --verify --strict --deep --verbose=2 "$APP_BUNDLE"
fi

if [[ "$REQUIRE_NOTARIZED_PACKAGE" == "1" ]]; then
  xcrun stapler validate "$APP_BUNDLE"
  spctl -a -vv "$APP_BUNDLE"
fi

if [[ "$REQUIRE_SIGNED_PACKAGE" == "0" || "$REQUIRE_NOTARIZED_PACKAGE" == "0" ]]; then
  RELEASE_DIR="$SMOKE_RELEASE_DIR"
  DMG_PATH="$RELEASE_DIR/$ARTIFACT_BASENAME.dmg"
  ZIP_PATH="$RELEASE_DIR/$ARTIFACT_BASENAME.zip"
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

  {
    printf '{\n'
    printf '  "package": {\n'
    printf '    "artifactPath": "%s",\n' "$(json_escape "$artifact_relative_path")"
    printf '    "format": "%s",\n' "$(json_escape "$package_format")"
    printf '    "createdAt": "%s",\n' "$PACKAGE_CREATED_AT"
    printf '    "signedPackageRequired": %s,\n' "$([[ "$REQUIRE_SIGNED_PACKAGE" == "1" ]] && printf true || printf false)"
    printf '    "notarizedPackageRequired": %s\n' "$([[ "$REQUIRE_NOTARIZED_PACKAGE" == "1" ]] && printf true || printf false)"
    printf '  }\n'
    printf '}\n'
  } >"$manifest_path"
}

create_checksum() {
  local artifact_path="$1"
  shasum -a 256 "$artifact_path" >"$artifact_path.sha256"
}

if [[ "$PACKAGE_FORMAT" == "dmg" || "$PACKAGE_FORMAT" == "all" ]]; then
  cp -R "$APP_BUNDLE" "$STAGING_DIR/"
  ln -s /Applications "$STAGING_DIR/Applications"
  hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"
  create_checksum "$DMG_PATH"
  create_package_evidence "$DMG_PATH" "dmg"
fi

if [[ "$PACKAGE_FORMAT" == "zip" || "$PACKAGE_FORMAT" == "all" ]]; then
  ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"
  create_checksum "$ZIP_PATH"
  create_package_evidence "$ZIP_PATH" "zip"
fi

echo "Release artifacts:"
find "$RELEASE_DIR" -maxdepth 1 -type f -print | sort
