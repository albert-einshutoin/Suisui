#!/usr/bin/env bash
set -euo pipefail

failure() {
  echo "failure_category=performance-artifact" >&2
  echo "failure_reason=$1" >&2
  exit 1
}

if [[ "$#" -ne 5 ]]; then
  failure "usage-invalid"
fi

ARTIFACT_DIRECTORY="$1"
DESTINATION_DIRECTORY="$2"
APP_NAME="$3"
EXPECTED_SOURCE_COMMIT="$4"
RECEIPT_DIRECTORY="$5"

if [[ ! "$APP_NAME" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ || "$APP_NAME" == "." || "$APP_NAME" == ".." ]]; then
  failure "app-name-invalid"
fi
if [[ ! "$EXPECTED_SOURCE_COMMIT" =~ ^[0-9a-f]{40}$ ]]; then
  failure "expected-source-commit-invalid"
fi
if [[ ! -d "$ARTIFACT_DIRECTORY" || -L "$ARTIFACT_DIRECTORY" ]]; then
  failure "artifact-directory-invalid"
fi

ARTIFACT_DIRECTORY="$(cd "$ARTIFACT_DIRECTORY" && pwd -P)"
ARCHIVE="$ARTIFACT_DIRECTORY/$APP_NAME.app.tar.gz"
MANIFEST="$ARTIFACT_DIRECTORY/manifest.env"
if [[ ! -f "$ARCHIVE" || -L "$ARCHIVE" || ! -f "$MANIFEST" || -L "$MANIFEST" ]]; then
  failure "artifact-files-invalid"
fi
if [[ "$(wc -l <"$MANIFEST" | tr -d ' ')" != "4" ]]; then
  failure "manifest-shape-invalid"
fi

manifest_value() {
  local key="$1"
  awk -F= -v key="$key" '
    $1 == key {
      count += 1
      if (NF == 2) value = $2
      else invalid = 1
    }
    END { if (count == 1 && !invalid) print value }
  ' "$MANIFEST"
}

FORMAT_VERSION="$(manifest_value format_version)"
SOURCE_COMMIT="$(manifest_value source_commit)"
BUILD_CONFIGURATION="$(manifest_value build_configuration)"
EXPECTED_SHA256="$(manifest_value archive_sha256)"
ACTUAL_SHA256="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"
if [[ "$FORMAT_VERSION" != "1" || ! "$SOURCE_COMMIT" =~ ^[0-9a-f]{40}$ ||
      "$SOURCE_COMMIT" != "$EXPECTED_SOURCE_COMMIT" || "$BUILD_CONFIGURATION" != "release" ||
      ! "$EXPECTED_SHA256" =~ ^[0-9a-f]{64}$ || "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]]; then
  failure "manifest-verification-failed"
fi

mkdir -p "$DESTINATION_DIRECTORY" "$RECEIPT_DIRECTORY"
if [[ -L "$DESTINATION_DIRECTORY" || -L "$RECEIPT_DIRECTORY" ]]; then
  failure "output-directory-invalid"
fi
DESTINATION_DIRECTORY="$(cd "$DESTINATION_DIRECTORY" && pwd -P)"
RECEIPT_DIRECTORY="$(cd "$RECEIPT_DIRECTORY" && pwd -P)"
DESTINATION_APP="$DESTINATION_DIRECTORY/$APP_NAME.app"
if [[ -e "$DESTINATION_APP" || -L "$DESTINATION_APP" ]]; then
  failure "destination-app-already-exists"
fi

STAGING_ROOT="$(mktemp -d "$DESTINATION_DIRECTORY/.ui-performance-verify.XXXXXX")"
cleanup() {
  rm -rf -- "$STAGING_ROOT"
}
trap cleanup EXIT

ARCHIVE_LIST="$STAGING_ROOT/archive-list.txt"
if ! /usr/bin/tar -tzf "$ARCHIVE" >"$ARCHIVE_LIST"; then
  failure "archive-list-failed"
fi
if ! awk -v root="$APP_NAME.app/" -v expected_binary="$APP_NAME.app/Contents/MacOS/$APP_NAME" '
  index($0, root) != 1 || $0 ~ /(^|\/)\.\.(\/|$)/ || $0 ~ /^\// { unsafe = 1 }
  $0 == expected_binary { binary_found = 1 }
  END { exit unsafe || !binary_found }
' "$ARCHIVE_LIST"; then
  failure "archive-entry-unsafe"
fi

EXTRACTED_ROOT="$STAGING_ROOT/extracted"
mkdir "$EXTRACTED_ROOT"
if ! /usr/bin/tar -xzf "$ARCHIVE" -C "$EXTRACTED_ROOT"; then
  failure "archive-extract-failed"
fi
EXTRACTED_APP="$EXTRACTED_ROOT/$APP_NAME.app"
EXTRACTED_BINARY="$EXTRACTED_APP/Contents/MacOS/$APP_NAME"
if [[ ! -d "$EXTRACTED_APP" || -L "$EXTRACTED_APP" ||
      ! -f "$EXTRACTED_BINARY" || -L "$EXTRACTED_BINARY" || ! -x "$EXTRACTED_BINARY" ]]; then
  failure "app-binary-invalid"
fi

# Framework bundles legitimately contain internal symlinks. Resolve every link
# after extraction and accept it only when the final target remains in this app.
while IFS= read -r -d '' link_path; do
  resolved_path="$(/bin/realpath "$link_path" 2>/dev/null)" || failure "app-symlink-invalid"
  case "$resolved_path" in
    "$EXTRACTED_APP"/*) ;;
    *) failure "app-symlink-escape" ;;
  esac
done < <(find "$EXTRACTED_APP" -type l -print0)

if [[ -n "$(find "$EXTRACTED_APP" ! -type d ! -type f ! -type l -print -quit)" ]]; then
  failure "app-special-file-invalid"
fi

VALIDATED_MANIFEST_RECEIPT="$RECEIPT_DIRECTORY/validated-artifact-manifest.env"
VERIFICATION_RECEIPT="$RECEIPT_DIRECTORY/artifact-verification.env"
if [[ -e "$VALIDATED_MANIFEST_RECEIPT" || -L "$VALIDATED_MANIFEST_RECEIPT" ||
      -e "$VERIFICATION_RECEIPT" || -L "$VERIFICATION_RECEIPT" ]]; then
  failure "verification-receipt-already-exists"
fi
mv "$EXTRACTED_APP" "$DESTINATION_APP"
cp "$MANIFEST" "$VALIDATED_MANIFEST_RECEIPT"
printf 'format_version=1\nverification=passed\nsource_commit=%s\nbuild_configuration=release\narchive_sha256=%s\n' \
  "$SOURCE_COMMIT" "$ACTUAL_SHA256" >"$VERIFICATION_RECEIPT"
printf 'OK: verified immutable release performance artifact\n'
