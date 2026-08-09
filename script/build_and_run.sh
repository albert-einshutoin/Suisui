#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
METADATA_FILE="$ROOT_DIR/packaging/app_metadata.env"
SPARKLE_ENV_FILE="$ROOT_DIR/packaging/sparkle.env"

BUILD_AND_RUN_TMP_ROOT="${SUISUI_TMP_ROOT:-$ROOT_DIR/.tmp}"
BUILD_AND_RUN_TMPDIR_CREATED=0

mkdir -p "$BUILD_AND_RUN_TMP_ROOT"
if [[ -n "${SUISUI_TMPDIR:-}" ]]; then
  BUILD_AND_RUN_TMPDIR="${SUISUI_TMPDIR%/}"
else
  BUILD_AND_RUN_TMPDIR="$(mktemp -d "$BUILD_AND_RUN_TMP_ROOT/suisui-build-and-run-tmp.XXXXXX")"
  BUILD_AND_RUN_TMPDIR_CREATED=1
fi

export TMPDIR="$BUILD_AND_RUN_TMPDIR/"
export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-$ROOT_DIR/.build/module-cache}"
SWIFTPM_CACHE_PATH="${SUISUI_SWIFTPM_CACHE_PATH:-$ROOT_DIR/.build/swiftpm-cache}"
mkdir -p "$TMPDIR" "$SWIFTPM_MODULECACHE_OVERRIDE" "$SWIFTPM_CACHE_PATH"
SWIFT_BUILD_ARGS=(
  --cache-path "$SWIFTPM_CACHE_PATH"
  --manifest-cache local
)

if [[ ! -f "$METADATA_FILE" ]]; then
  echo "missing metadata file: $METADATA_FILE" >&2
  exit 2
fi

# shellcheck source=/dev/null
source "$METADATA_FILE"

if [[ "${SUISUI_LOAD_LOCAL_RELEASE_CONFIG:-1}" == "1" && -f "$SPARKLE_ENV_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$SPARKLE_ENV_FILE"
fi

APP_NAME="${APP_NAME:?APP_NAME is required}"
SWIFT_PRODUCT_NAME="${SWIFT_PRODUCT_NAME:-$APP_NAME}"
BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER:?BUNDLE_IDENTIFIER is required}"
APP_CATEGORY="${APP_CATEGORY:?APP_CATEGORY is required}"
MARKETING_VERSION="${MARKETING_VERSION:?MARKETING_VERSION is required}"
CURRENT_PROJECT_VERSION="${CURRENT_PROJECT_VERSION:?CURRENT_PROJECT_VERSION is required}"
MIN_SYSTEM_VERSION="${MIN_SYSTEM_VERSION:?MIN_SYSTEM_VERSION is required}"
COPYRIGHT="${COPYRIGHT:?COPYRIGHT is required}"
BUILD_CONFIGURATION="${SUISUI_BUILD_CONFIGURATION:-debug}"
RELEASE_BUILD_PURPOSE="${SUISUI_RELEASE_BUILD_PURPOSE:-distribution}"
RUNTIME_POLICY="${SUISUI_RUNTIME_POLICY:-public-alpha}"
SPARKLE_FEED_URL="${SUISUI_SPARKLE_FEED_URL:-${SPARKLE_FEED_URL:-}}"
SPARKLE_PUBLIC_ED_KEY="${SUISUI_SPARKLE_PUBLIC_ED_KEY:-${SPARKLE_PUBLIC_ED_KEY:-}}"
LOCAL_LICENSE_PUBLIC_KEY_BASE64="${SUISUI_LOCAL_LICENSE_PUBLIC_KEY_BASE64:-${SUISUI_LOCAL_LICENSE_PUBLIC_KEY:-}}"
case "$RUNTIME_POLICY" in
  public-alpha|development)
    ;;
  *)
    echo "BLOCKER: SUISUI_RUNTIME_POLICY must be public-alpha or development" >&2
    exit 2
    ;;
esac
# This digest deliberately describes only non-secret, path-independent build
# choices. Runtime evidence can compare it across builds of the same HEAD
# without serializing credentials or machine-local configuration.
BUILD_CONFIGURATION_FINGERPRINT="$(
  printf 'schema=1\nruntime-policy=%s\nbuild-configuration=%s\nrelease-purpose=%s\nsparkle-feed=%s\nsparkle-key=%s\nlicense-key=%s\n' \
    "$RUNTIME_POLICY" \
    "$BUILD_CONFIGURATION" \
    "$RELEASE_BUILD_PURPOSE" \
    "$SPARKLE_FEED_URL" \
    "$SPARKLE_PUBLIC_ED_KEY" \
    "$LOCAL_LICENSE_PUBLIC_KEY_BASE64" \
    | /usr/bin/shasum -a 256 \
    | awk '{print $1}'
)"
# SwiftUI cold launch can exceed 12s on release evidence machines; keep the
# default aligned with runtime smoke waits while
# preserving SUISUI_VERIFY_TIMEOUT_SECONDS for faster local overrides.
VERIFY_TIMEOUT_SECONDS="${SUISUI_VERIFY_TIMEOUT_SECONDS:-30}"
# Product markers identify the Project Board independently of its localized window title.
# Keep the optional name override for targeted diagnostics, while the release gate
# defaults to any visible window owned by the exact verification PID.
PROJECT_BOARD_WINDOW_NAME="${SUISUI_PROJECT_BOARD_WINDOW_NAME:-}"
AX_HELPERS="${AX_HELPERS:-$ROOT_DIR/script/ui_accessibility_smoke_helpers.sh}"
VERIFY_SYSTEM_TMP_ROOT="${SUISUI_VERIFY_SYSTEM_TMP_ROOT:-$(getconf DARWIN_USER_TEMP_DIR)}"
VERIFY_ROOT_CREATED=0
if [[ "$MODE" == "--verify" || "$MODE" == "verify" ]]; then
  mkdir -p "$VERIFY_SYSTEM_TMP_ROOT"
  VERIFY_ROOT="$(mktemp -d "${VERIFY_SYSTEM_TMP_ROOT%/}/suisui-verify.XXXXXX")"
  VERIFY_ROOT_CREATED=1
else
  VERIFY_ROOT="$BUILD_AND_RUN_TMPDIR/verify"
fi
VERIFY_HOME="$VERIFY_ROOT/home"
VERIFY_CFFIXED_USER_HOME="$VERIFY_ROOT/cfixed-user-home"
VERIFY_TMPDIR="$VERIFY_ROOT/tmp"
VERIFY_DATABASE_PATH="$VERIFY_ROOT/suisui.sqlite3"
VERIFY_SQLITE3="${SQLITE3:-sqlite3}"
VERIFY_APP_LAUNCHER_SOURCE="$ROOT_DIR/script/launch_macos_app.swift"
VERIFY_APP_LAUNCHER_EXECUTABLE="$VERIFY_ROOT/launch-macos-app"
BOOTSTRAP_LAUNCH_PID=""
BOOTSTRAP_APP_PID=""
APP_LAUNCH_PID=""
APP_PID=""
VERIFY_LAUNCH_PID=""
BUILD_AND_RUN_LOCK_DIR="$BUILD_AND_RUN_TMP_ROOT/build_and_run.lock"
BUILD_AND_RUN_LOCK_TIMEOUT_SECONDS="${SUISUI_BUILD_AND_RUN_LOCK_TIMEOUT_SECONDS:-120}"
BUILD_AND_RUN_LOCK_ACQUIRED=0

DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_FRAMEWORKS="$APP_CONTENTS/Frameworks"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
APP_LOCALIZATION_SOURCE="$ROOT_DIR/Sources/SuisuiApp/Resources"
APP_ICON_SOURCE="$ROOT_DIR/packaging/Suisui.icns"

if [[ ! -r "$AX_HELPERS" ]]; then
  echo "missing accessibility helpers: $AX_HELPERS" >&2
  exit 2
fi

# shellcheck source=/dev/null
source "$AX_HELPERS"

cd "$ROOT_DIR"

if [[ ! "$VERIFY_TIMEOUT_SECONDS" =~ ^[0-9]+$ || "$VERIFY_TIMEOUT_SECONDS" -lt 1 ]]; then
  echo "SUISUI_VERIFY_TIMEOUT_SECONDS must be a positive integer" >&2
  exit 2
fi

if [[ ! "$BUILD_AND_RUN_LOCK_TIMEOUT_SECONDS" =~ ^[0-9]+$ || "$BUILD_AND_RUN_LOCK_TIMEOUT_SECONDS" -lt 1 ]]; then
  echo "SUISUI_BUILD_AND_RUN_LOCK_TIMEOUT_SECONDS must be a positive integer" >&2
  exit 2
fi

release_build_and_run_lock() {
  if [[ "${BUILD_AND_RUN_LOCK_ACQUIRED:-0}" == "1" ]]; then
    rmdir "$BUILD_AND_RUN_LOCK_DIR" >/dev/null 2>&1 || true
    BUILD_AND_RUN_LOCK_ACQUIRED=0
  fi
}

cleanup_build_and_run_tmpdir() {
  if [[ "${BUILD_AND_RUN_TMPDIR_CREATED:-0}" == "1" ]]; then
    rm -rf "$BUILD_AND_RUN_TMPDIR"
    BUILD_AND_RUN_TMPDIR_CREATED=0
  fi
}

cleanup_verify_root() {
  if [[ "${VERIFY_ROOT_CREATED:-0}" != "1" ]]; then
    return 0
  fi
  case "$VERIFY_ROOT" in
    "${VERIFY_SYSTEM_TMP_ROOT%/}"/suisui-verify.*)
      rm -rf "$VERIFY_ROOT"
      VERIFY_ROOT_CREATED=0
      ;;
  esac
}

terminate_verify_app() {
  terminate_owned_verify_process "final" "${APP_LAUNCH_PID:-}" "${APP_PID:-}"
  terminate_owned_verify_process "bootstrap" "${BOOTSTRAP_LAUNCH_PID:-}" "${BOOTSTRAP_APP_PID:-}"
}

terminate_owned_verify_process() {
  local label="$1"
  local launch_pid="$2"
  local app_pid="$3"
  local deadline

  if [[ -z "$launch_pid" && -z "$app_pid" ]]; then
    return 0
  fi

  if [[ -n "$app_pid" ]] && ax_pid_is_owned_process "$APP_NAME" "$app_pid" "$APP_BINARY"; then
    kill "$app_pid" >/dev/null 2>&1 || true
    deadline=$((SECONDS + 3))
    while kill -0 "$app_pid" >/dev/null 2>&1 && [[ "$SECONDS" -lt "$deadline" ]]; do
      sleep 0.1
    done
    kill -9 "$app_pid" >/dev/null 2>&1 || true
  fi

  # `$!` belongs to the env launcher, not necessarily the app. It is still an
  # owned child of this shell, so reap it separately without using a global
  # name-based kill that could touch another Suisui process.
  if [[ -n "$launch_pid" && "$launch_pid" != "$app_pid" ]] && kill -0 "$launch_pid" >/dev/null 2>&1; then
    kill "$launch_pid" >/dev/null 2>&1 || true
    deadline=$((SECONDS + 3))
    while kill -0 "$launch_pid" >/dev/null 2>&1 && [[ "$SECONDS" -lt "$deadline" ]]; do
      sleep 0.1
    done
    kill -9 "$launch_pid" >/dev/null 2>&1 || true
  fi

  if [[ -n "$launch_pid" ]]; then
    wait "$launch_pid" >/dev/null 2>&1 || true
  fi
  printf "OK: Suisui %s process cleanup complete (launch_pid=%s app_pid=%s)\n" "$label" "${launch_pid:-none}" "${app_pid:-none}"
}

cleanup_build_and_run() {
  terminate_verify_app
  release_build_and_run_lock
  cleanup_verify_root
  cleanup_build_and_run_tmpdir
}

# BEGIN INTERACTIVE DIST APP OWNERSHIP HELPERS
dist_app_process_identity() {
  local app_pid="$1"
  local process_command
  local process_start

  [[ "$app_pid" =~ ^[0-9]+$ && "$app_pid" -gt 0 ]] || return 1
  process_command="$(ps -p "$app_pid" -o command= 2>/dev/null)" || return 1
  process_command="${process_command#"${process_command%%[![:space:]]*}"}"
  case "$process_command" in
    "$APP_BINARY"|"$APP_BINARY "*) ;;
    *) return 1 ;;
  esac

  # The start token prevents a PID reused after TERM from inheriting the
  # original process's bounded KILL fallback, even when the new process happens
  # to execute the same dist binary.
  process_start="$(ps -p "$app_pid" -o lstart= 2>/dev/null)" || return 1
  process_start="${process_start#"${process_start%%[![:space:]]*}"}"
  [[ -n "$process_start" ]] || return 1
  printf '%s\t%s\n' "$process_start" "$process_command"
}

dist_app_process_matches_identity() {
  local app_pid="$1"
  local expected_identity="$2"
  local current_identity

  current_identity="$(dist_app_process_identity "$app_pid")" || return 1
  [[ "$current_identity" == "$expected_identity" ]]
}

terminate_existing_dist_app_for_interactive_mode() {
  local app_pid
  local process_identity
  local deadline

  while IFS= read -r app_pid; do
    [[ -n "$app_pid" ]] || continue
    process_identity="$(dist_app_process_identity "$app_pid")" || continue

    # Recheck immediately before every signal. Name-only process discovery is
    # intentionally insufficient because another Suisui binary belongs to the
    # user, not to this dist rebuild.
    if ! dist_app_process_matches_identity "$app_pid" "$process_identity"; then
      continue
    fi
    kill -TERM "$app_pid" >/dev/null 2>&1 || true

    deadline=$((SECONDS + 3))
    while dist_app_process_matches_identity "$app_pid" "$process_identity" && [[ "$SECONDS" -lt "$deadline" ]]; do
      sleep 0.1
    done
    if dist_app_process_matches_identity "$app_pid" "$process_identity"; then
      kill -KILL "$app_pid" >/dev/null 2>&1 || true
    fi
  done < <(pgrep -x "$APP_NAME" 2>/dev/null || true)
}

stop_existing_dist_apps_for_mode() {
  case "$MODE" in
    run|--debug|debug|--logs|logs|--telemetry|telemetry)
      terminate_existing_dist_app_for_interactive_mode
      ;;
  esac
}
# END INTERACTIVE DIST APP OWNERSHIP HELPERS

copy_app_localizations() {
  if [[ ! -d "$APP_LOCALIZATION_SOURCE" ]]; then
    return
  fi

  mkdir -p "$APP_RESOURCES"
  while IFS= read -r -d '' localization_dir; do
    /usr/bin/ditto "$localization_dir" "$APP_RESOURCES/$(basename "$localization_dir")"
  done < <(find "$APP_LOCALIZATION_SOURCE" -maxdepth 1 -type d -name "*.lproj" -print0)
}

xml_escape() {
  local value="$1"
  value="${value//&/&amp;}"
  value="${value//</&lt;}"
  value="${value//>/&gt;}"
  value="${value//\"/&quot;}"
  value="${value//\'/&apos;}"
  printf '%s' "$value"
}

acquire_build_and_run_lock() {
  local deadline=$((SECONDS + BUILD_AND_RUN_LOCK_TIMEOUT_SECONDS))
  while ! mkdir "$BUILD_AND_RUN_LOCK_DIR" >/dev/null 2>&1; do
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      echo "BLOCKER: timed out waiting for build/run lock: $BUILD_AND_RUN_LOCK_DIR" >&2
      echo "NEXT: wait for the other Suisui build/run command to finish, or remove the lock only after confirming no build_and_run.sh process is active." >&2
      return 1
    fi
    sleep 1
  done
  BUILD_AND_RUN_LOCK_ACQUIRED=1
}

trap cleanup_build_and_run EXIT INT TERM

case "$RELEASE_BUILD_PURPOSE" in
  distribution)
    ;;
  performance)
    # Performance CI needs the optimized executable and real app bundle, but
    # must not fabricate production Sparkle credentials. Keep this exception
    # build-only so no runnable/package workflow can bypass distribution checks.
    if [[ "$BUILD_CONFIGURATION" != "release" || ( "$MODE" != "--build-only" && "$MODE" != "build" ) ]]; then
      echo "BLOCKER: release performance build purpose requires --build-only with release configuration" >&2
      exit 2
    fi
    ;;
  *)
    echo "BLOCKER: SUISUI_RELEASE_BUILD_PURPOSE must be distribution or performance" >&2
    exit 2
    ;;
esac

acquire_build_and_run_lock

stop_existing_dist_apps_for_mode

if [[ "$RELEASE_BUILD_PURPOSE" == "distribution" ]]; then
  SUISUI_SPARKLE_CONFIG_QUIET=1 "$ROOT_DIR/script/validate_sparkle_release_config.sh"
fi

case "$BUILD_CONFIGURATION" in
  debug)
    swift build "${SWIFT_BUILD_ARGS[@]}" --product "$SWIFT_PRODUCT_NAME"
    BUILD_DIR="$(swift build "${SWIFT_BUILD_ARGS[@]}" --show-bin-path)"
    ;;
  release)
    swift build "${SWIFT_BUILD_ARGS[@]}" -c release --product "$SWIFT_PRODUCT_NAME"
    BUILD_DIR="$(swift build "${SWIFT_BUILD_ARGS[@]}" -c release --show-bin-path)"
    ;;
  *)
    echo "SUISUI_BUILD_CONFIGURATION must be debug or release" >&2
    exit 2
    ;;
esac

BUILD_BINARY="$BUILD_DIR/$SWIFT_PRODUCT_NAME"
RESOURCE_BUNDLE="$BUILD_DIR/Suisui_SuisuiCore.bundle"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

if ! otool -l "$APP_BINARY" | grep -F "@executable_path/../Frameworks" >/dev/null; then
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_BINARY"
fi

if [[ -d "$RESOURCE_BUNDLE" ]]; then
  mkdir -p "$APP_RESOURCES"
  /usr/bin/ditto "$RESOURCE_BUNDLE" "$APP_RESOURCES"
fi

copy_app_localizations

if [[ ! -f "$APP_ICON_SOURCE" ]]; then
  echo "missing macOS app icon: $APP_ICON_SOURCE" >&2
  exit 2
fi
mkdir -p "$APP_RESOURCES"
cp "$APP_ICON_SOURCE" "$APP_RESOURCES/Suisui.icns"

while IFS= read -r -d '' framework_path; do
  mkdir -p "$APP_FRAMEWORKS"
  /usr/bin/ditto "$framework_path" "$APP_FRAMEWORKS/$(basename "$framework_path")"
done < <(find "$BUILD_DIR" -maxdepth 1 -type d -name "*.framework" -print0)

while IFS= read -r -d '' dylib_path; do
  mkdir -p "$APP_FRAMEWORKS"
  /usr/bin/ditto "$dylib_path" "$APP_FRAMEWORKS/$(basename "$dylib_path")"
done < <(find "$BUILD_DIR" -maxdepth 1 -type f -name "*.dylib" -print0)

{
  printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>'
  printf '%s\n' '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
  printf '%s\n' '<plist version="1.0">'
  printf '%s\n' '<dict>'
  printf '%s\n' '  <key>CFBundleExecutable</key>'
  printf '  <string>%s</string>\n' "$APP_NAME"
  printf '%s\n' '  <key>CFBundleIdentifier</key>'
  printf '  <string>%s</string>\n' "$BUNDLE_IDENTIFIER"
  printf '%s\n' '  <key>CFBundleDisplayName</key>'
  printf '  <string>%s</string>\n' "$APP_NAME"
  printf '%s\n' '  <key>CFBundleName</key>'
  printf '  <string>%s</string>\n' "$APP_NAME"
  printf '%s\n' '  <key>CFBundleIconFile</key>'
  printf '%s\n' '  <string>Suisui.icns</string>'
  printf '%s\n' '  <key>CFBundlePackageType</key>'
  printf '%s\n' '  <string>APPL</string>'
  printf '%s\n' '  <key>CFBundleShortVersionString</key>'
  printf '  <string>%s</string>\n' "$MARKETING_VERSION"
  printf '%s\n' '  <key>CFBundleVersion</key>'
  printf '  <string>%s</string>\n' "$CURRENT_PROJECT_VERSION"
  printf '%s\n' '  <key>LSApplicationCategoryType</key>'
  printf '  <string>%s</string>\n' "$APP_CATEGORY"
  printf '%s\n' '  <key>CFBundleDevelopmentRegion</key>'
  printf '%s\n' '  <string>en</string>'
  printf '%s\n' '  <key>CFBundleLocalizations</key>'
  printf '%s\n' '  <array>'
  printf '%s\n' '    <string>en</string>'
  printf '%s\n' '    <string>ja</string>'
  printf '%s\n' '  </array>'
  printf '%s\n' '  <key>LSMinimumSystemVersion</key>'
  printf '  <string>%s</string>\n' "$MIN_SYSTEM_VERSION"
  printf '%s\n' '  <key>NSPrincipalClass</key>'
  printf '%s\n' '  <string>NSApplication</string>'
  printf '%s\n' '  <key>NSQuitAlwaysKeepsWindows</key>'
  printf '%s\n' '  <false/>'
  printf '%s\n' '  <key>NSMicrophoneUsageDescription</key>'
  printf '%s\n' '  <string>Suisui uses the microphone when you explicitly start voice capture.</string>'
  printf '%s\n' '  <key>NSLocationUsageDescription</key>'
  printf '%s\n' '  <string>Suisui uses your location only while Today weather is being shown.</string>'
  printf '%s\n' '  <key>NSSpeechRecognitionUsageDescription</key>'
  printf '%s\n' '  <string>Suisui transcribes audio only after you explicitly record a voice command.</string>'
  printf '%s\n' '  <key>SuisuiLocalLicensePublicKey</key>'
  printf '  <string>%s</string>\n' "$(xml_escape "$LOCAL_LICENSE_PUBLIC_KEY_BASE64")"
  printf '%s\n' '  <key>SuisuiRuntimePolicy</key>'
  printf '  <string>%s</string>\n' "$RUNTIME_POLICY"
  printf '%s\n' '  <key>SuisuiBuildConfigurationFingerprint</key>'
  printf '  <string>%s</string>\n' "$BUILD_CONFIGURATION_FINGERPRINT"
  printf '%s\n' '  <key>NSHumanReadableCopyright</key>'
  printf '  <string>%s</string>\n' "$COPYRIGHT"
  printf '%s\n' '</dict>'
  printf '%s\n' '</plist>'
} >"$INFO_PLIST"

if [[ -n "$SPARKLE_FEED_URL" && -n "$SPARKLE_PUBLIC_ED_KEY" ]]; then
  /usr/libexec/PlistBuddy -c "Add :SUFeedURL string $SPARKLE_FEED_URL" "$INFO_PLIST"
  /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $SPARKLE_PUBLIC_ED_KEY" "$INFO_PLIST"
fi

if [[ "$BUILD_CONFIGURATION" == "debug" ]]; then
  codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null
fi

activate_app() {
  /usr/bin/osascript -e "tell application \"$APP_NAME\" to activate" >/dev/null 2>&1 &
  local osascript_pid=$!
  for _ in {1..20}; do
    if ! kill -0 "$osascript_pid" >/dev/null 2>&1; then
      wait "$osascript_pid" >/dev/null 2>&1 || true
      return 0
    fi
    sleep 0.1
  done
  kill "$osascript_pid" >/dev/null 2>&1 || true
  wait "$osascript_pid" >/dev/null 2>&1 || true
}

open_app() {
  if [[ "$MODE" == "--verify" || "$MODE" == "verify" ]]; then
    launch_verify_process "${1:-today}"
    return
  fi
  local open_args=(-n -F "$APP_BUNDLE")
  /usr/bin/open "${open_args[@]}"
  activate_app
}

launch_verify_process() {
  local selected_destination="$1"
  mkdir -p "$VERIFY_HOME" "$VERIFY_CFFIXED_USER_HOME" "$VERIFY_TMPDIR"
  if [[ ! -x "$VERIFY_APP_LAUNCHER_EXECUTABLE" ]]; then
    /usr/bin/swiftc -parse-as-library "$VERIFY_APP_LAUNCHER_SOURCE" -o "$VERIFY_APP_LAUNCHER_EXECUTABLE"
  fi
  VERIFY_LAUNCH_PID="$(/usr/bin/env -i \
    PATH="$PATH" \
    "$VERIFY_APP_LAUNCHER_EXECUTABLE" \
    "$APP_BUNDLE" \
    "$PATH" \
    "$VERIFY_HOME" \
    "$VERIFY_CFFIXED_USER_HOME" \
    "$VERIFY_TMPDIR" \
    "$VERIFY_DATABASE_PATH" \
    "$selected_destination")"
  if [[ ! "$VERIFY_LAUNCH_PID" =~ ^[1-9][0-9]*$ ]]; then
    ax_report_failure "launch" "bundle launcher did not return a valid app PID"
    return 1
  fi
}

resolve_verify_app_pid() {
  local launch_pid="$1"
  local resolved_pid
  if resolved_pid="$(ax_wait_for_owned_app_pid "$launch_pid" "$APP_BINARY" "$VERIFY_TIMEOUT_SECONDS")"; then
    printf '%s\n' "$resolved_pid"
    return 0
  fi
  ax_report_failure "launch" "app binary did not appear under launch pid=$launch_pid within ${VERIFY_TIMEOUT_SECONDS}s"
  return 1
}

wait_for_app_process() {
  if ax_wait_for_pid_owned_process "$APP_NAME" "$APP_PID" "$VERIFY_TIMEOUT_SECONDS" "$APP_BINARY"; then
    printf "OK: Suisui verify process launched (pid=%s)\n" "$APP_PID"
    return 0
  fi
  ax_report_failure "launch" "process did not appear for pid=$APP_PID within ${VERIFY_TIMEOUT_SECONDS}s"
  echo "BLOCKER: $APP_NAME process did not appear within ${VERIFY_TIMEOUT_SECONDS}s" >&2
  return 1
}

wait_for_verify_database() {
  local deadline=$((SECONDS + VERIFY_TIMEOUT_SECONDS))
  while true; do
    if [[ -n "${BOOTSTRAP_APP_PID:-}" ]] && ! ax_pid_is_owned_process "$APP_NAME" "$BOOTSTRAP_APP_PID" "$APP_BINARY"; then
      ax_report_failure "launch" "bootstrap app exited before isolated SQLite schema became ready (pid=$BOOTSTRAP_APP_PID)"
      return 1
    fi
    if [[ -f "$VERIFY_DATABASE_PATH" ]] && [[ "$($VERIFY_SQLITE3 -batch -noheader "$VERIFY_DATABASE_PATH" \
      "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name IN ('projects', 'tasks');" 2>/dev/null || true)" == "2" ]]; then
      return 0
    fi
    if [[ "$SECONDS" -ge "$deadline" ]]; then
      ax_report_failure "launch" "isolated SQLite schema did not become ready at $VERIFY_DATABASE_PATH"
      return 1
    fi
    sleep 0.2
  done
}

seed_verify_fixture() {
  if ! command -v "$VERIFY_SQLITE3" >/dev/null 2>&1; then
    ax_report_failure "launch" "sqlite3 is required to seed the deterministic verify fixture"
    return 1
  fi

  local due_at="2026-01-01T12:00:00+00:00"
  if ! "$VERIFY_SQLITE3" "$VERIFY_DATABASE_PATH" <<SQL
PRAGMA busy_timeout = 5000;
INSERT INTO projects (title, status, priority, deadline, workspace_path, tags_json, source_command, created_at, updated_at)
SELECT 'build-and-run-verify-fixture', 'active', 'high', NULL, NULL, '[]', 'build-and-run-verify', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
WHERE NOT EXISTS (SELECT 1 FROM projects WHERE source_command = 'build-and-run-verify');
INSERT INTO tasks (project_id, title, status, detail, due_at, completed_at, priority, source_command, created_at, updated_at)
SELECT id, 'Verify Project Board launch', 'planned', 'Deterministic local smoke fixture', '$due_at', NULL, 'high', 'build-and-run-verify', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
FROM projects
WHERE source_command = 'build-and-run-verify'
  AND NOT EXISTS (SELECT 1 FROM tasks WHERE source_command = 'build-and-run-verify');
SQL
  then
    ax_report_failure "launch" "deterministic verify fixture could not be written to $VERIFY_DATABASE_PATH"
    return 1
  fi
}

fetch_verify_project_id() {
  local project_id
  project_id="$($VERIFY_SQLITE3 -batch -noheader "$VERIFY_DATABASE_PATH" \
    "SELECT p.id
     FROM projects AS p
     JOIN tasks AS t ON t.project_id = p.id
     WHERE p.source_command = 'build-and-run-verify'
       AND p.title = 'build-and-run-verify-fixture'
       AND t.source_command = 'build-and-run-verify'
       AND t.title = 'Verify Project Board launch'
     ORDER BY p.id DESC LIMIT 1;" \
    | tr -d '[:space:]')"
  if [[ ! "$project_id" =~ ^[1-9][0-9]*$ ]]; then
    ax_report_failure "launch" "deterministic verify project ID was not found"
    return 1
  fi
  printf '%s\n' "$project_id"
}

wait_for_project_board_window() {
  local window_output=""
  local window_diagnostic_file="$VERIFY_ROOT/window.err"
  if window_output="$(ax_wait_for_pid_owned_window "$APP_NAME" "$APP_PID" "$PROJECT_BOARD_WINDOW_NAME" "$VERIFY_TIMEOUT_SECONDS" "$window_diagnostic_file" "$APP_BINARY")"; then
    printf "OK: Project Board window visible (%s)\n" "$window_output"
    return 0
  fi
  local failure_category
  failure_category="$(ax_classify_window_failure "$window_diagnostic_file" "$APP_PID")"
  ax_report_failure "$failure_category" "pid-owned Project Board window was not visible for pid=$APP_PID"
  echo "BLOCKER: Project Board window was not visible within ${VERIFY_TIMEOUT_SECONDS}s" >&2
  echo "NEXT: grant Accessibility permission if the window exists but cannot be inspected, then rerun ./script/build_and_run.sh --verify." >&2
  return 1
}

wait_for_project_board_marker() {
  local marker="$1"
  local probe_file="$VERIFY_ROOT/ax-${marker}.txt"
  mkdir -p "$VERIFY_ROOT"
  if ax_wait_for_ax_identifier "$APP_NAME" "$marker" "$VERIFY_TIMEOUT_SECONDS" "$ROOT_DIR" "$probe_file" "" "$APP_PID"; then
    printf "OK: Project Board product marker present (%s)\n" "$marker"
    return 0
  fi

  local failure_category
  failure_category="$(ax_classify_marker_failure "$probe_file" "$APP_PID")"
  ax_report_failure "$failure_category" "missing Project Board product marker=$marker"
  return 1
}

case "$MODE" in
  --build-only|build)
    release_build_and_run_lock
    ;;
  run)
    open_app
    release_build_and_run_lock
    ;;
  --debug|debug)
    release_build_and_run_lock
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    release_build_and_run_lock
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    release_build_and_run_lock
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_IDENTIFIER\""
    ;;
  --verify|verify)
    rm -f "$VERIFY_DATABASE_PATH" "$VERIFY_DATABASE_PATH-wal" "$VERIFY_DATABASE_PATH-shm"
    launch_verify_process "today"
    BOOTSTRAP_LAUNCH_PID="$VERIFY_LAUNCH_PID"
    BOOTSTRAP_APP_PID="$(resolve_verify_app_pid "$BOOTSTRAP_LAUNCH_PID")"
    if ! ax_wait_for_pid_owned_process "$APP_NAME" "$BOOTSTRAP_APP_PID" "$VERIFY_TIMEOUT_SECONDS" "$APP_BINARY"; then
      ax_report_failure "launch" "bootstrap app process was not alive for pid=$BOOTSTRAP_APP_PID"
      exit 1
    fi
    printf "OK: Suisui bootstrap process launched (launch_pid=%s app_pid=%s)\n" "$BOOTSTRAP_LAUNCH_PID" "$BOOTSTRAP_APP_PID"
    wait_for_verify_database
    terminate_owned_verify_process "bootstrap" "$BOOTSTRAP_LAUNCH_PID" "$BOOTSTRAP_APP_PID"
    BOOTSTRAP_LAUNCH_PID=""
    BOOTSTRAP_APP_PID=""
    seed_verify_fixture
    VERIFY_PROJECT_ID="$(fetch_verify_project_id)"
    launch_verify_process "project:$VERIFY_PROJECT_ID"
    APP_LAUNCH_PID="$VERIFY_LAUNCH_PID"
    APP_PID="$(resolve_verify_app_pid "$APP_LAUNCH_PID")"
    wait_for_app_process
    wait_for_project_board_window
    wait_for_project_board_marker "project-board-command-palette"
    wait_for_project_board_marker "project-board-sidebar"
    wait_for_project_board_marker "project-board-detail"
    release_build_and_run_lock
    ;;
  *)
    echo "usage: $0 [run|--build-only|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
