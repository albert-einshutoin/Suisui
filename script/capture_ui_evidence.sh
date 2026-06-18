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
BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER:?BUNDLE_IDENTIFIER is required}"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
SCREENSHOT_DIR="${SOLOPM_UI_EVIDENCE_DIR:-$ROOT_DIR/docs/release/evidence/ui-screenshots}"
EVIDENCE_FILE="${SOLOPM_UI_EVIDENCE_FILE:-$ROOT_DIR/docs/release/evidence/ui-screenshots.md}"
EVIDENCE_HOME="${SOLOPM_UI_EVIDENCE_HOME:-$(mktemp -d "${TMPDIR:-/tmp}/solopm-ui-evidence.XXXXXX")}"
KEEP_HOME="${SOLOPM_UI_EVIDENCE_KEEP_HOME:-0}"
DRY_RUN=0

for arg in "$@"; do
  case "$arg" in
    --dry-run)
      DRY_RUN=1
      ;;
    *)
      echo "usage: $0 [--dry-run]" >&2
      exit 2
      ;;
  esac
done

cleanup() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  if [[ "$KEEP_HOME" != "1" && -d "$EVIDENCE_HOME" && "${SOLOPM_UI_EVIDENCE_HOME:-}" == "" ]]; then
    rm -rf "$EVIDENCE_HOME"
  fi
}
trap cleanup EXIT

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 2
  fi
}

relative_path() {
  local path="$1"
  case "$path" in
    "$ROOT_DIR"/*) printf '%s\n' "${path#"$ROOT_DIR/"}" ;;
    *) printf '%s\n' "$path" ;;
  esac
}

app_env_args() {
  printf '%s\0' \
    --env "HOME=$EVIDENCE_HOME" \
    --env "CFFIXED_USER_HOME=$EVIDENCE_HOME"
}

open_evidence_app() {
  xargs -0 /usr/bin/open -n -F "$APP_BUNDLE" < <(app_env_args)
}

activate_evidence_app() {
  /usr/bin/osascript -e "tell application \"$APP_NAME\" to activate" >/dev/null 2>&1 || true
}

wait_for_process() {
  for _ in {1..40}; do
    if pgrep -x "$APP_NAME" >/dev/null; then
      return 0
    fi
    sleep 0.25
  done
  echo "$APP_NAME did not launch." >&2
  exit 1
}

wait_for_database() {
  local database_path="$1"
  for _ in {1..40}; do
    if [[ -f "$database_path" ]]; then
      return 0
    fi
    sleep 0.25
  done
  echo "database was not created: $database_path" >&2
  exit 1
}

find_window_capture_metadata() {
  SOLOPM_WINDOW_OWNER="$APP_NAME" /usr/bin/swift - <<'SWIFT'
import CoreGraphics
import Foundation

let ownerName = ProcessInfo.processInfo.environment["SOLOPM_WINDOW_OWNER"] ?? "SoloPM"
let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
guard let windowInfo = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
    fputs("Could not read window list.\n", stderr)
    exit(2)
}

struct Candidate {
    let id: Int
    let x: Int
    let y: Int
    let width: Int
    let height: Int
    let area: Double
}

let candidates = windowInfo.compactMap { window -> Candidate? in
    guard window[kCGWindowOwnerName as String] as? String == ownerName else { return nil }
    guard (window[kCGWindowLayer as String] as? Int) == 0 else { return nil }
    guard (window[kCGWindowAlpha as String] as? Double ?? 1) > 0 else { return nil }
    guard let id = window[kCGWindowNumber as String] as? Int else { return nil }
    guard let bounds = window[kCGWindowBounds as String] as? [String: Any] else { return nil }
    let width = bounds["Width"] as? Double ?? 0
    let height = bounds["Height"] as? Double ?? 0
    guard width >= 640, height >= 420 else { return nil }
    let x = bounds["X"] as? Double ?? 0
    let y = bounds["Y"] as? Double ?? 0
    return Candidate(
        id: id,
        x: Int(x.rounded(.down)),
        y: Int(y.rounded(.down)),
        width: Int(width.rounded(.down)),
        height: Int(height.rounded(.down)),
        area: width * height
    )
}.sorted { $0.area > $1.area }

guard let candidate = candidates.first else {
    fputs("No visible SoloPM window was found.\n", stderr)
    exit(1)
}

print("\(candidate.id) \(candidate.x) \(candidate.y) \(candidate.width) \(candidate.height)")
SWIFT
}

assert_screenshot_has_visible_content() {
  local image_path="$1"

  /usr/bin/swift - "$image_path" <<'SWIFT'
import CoreGraphics
import Foundation
import ImageIO

guard CommandLine.arguments.count == 2 else {
    fputs("screenshot content check requires an image path.\n", stderr)
    exit(2)
}

let imagePath = CommandLine.arguments[1]
let imageURL = URL(fileURLWithPath: imagePath)

guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fputs("screenshot content check could not read image: \(imagePath)\n", stderr)
    exit(2)
}

let sampleWidth = min(max(image.width, 1), 160)
let sampleHeight = min(max(image.height, 1), 100)
let bytesPerPixel = 4
let bytesPerRow = sampleWidth * bytesPerPixel
var pixels = [UInt8](repeating: 0, count: sampleHeight * bytesPerRow)

guard let context = CGContext(
    data: &pixels,
    width: sampleWidth,
    height: sampleHeight,
    bitsPerComponent: 8,
    bytesPerRow: bytesPerRow,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fputs("screenshot content check could not create sampling context.\n", stderr)
    exit(2)
}

context.interpolationQuality = .low
context.draw(image, in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight))

var minimumLuminance = 255
var maximumLuminance = 0
var visiblePixelCount = 0

for offset in stride(from: 0, to: pixels.count, by: bytesPerPixel) {
    let alpha = Int(pixels[offset + 3])
    guard alpha > 16 else { continue }

    let red = Int(pixels[offset])
    let green = Int(pixels[offset + 1])
    let blue = Int(pixels[offset + 2])
    let luminance = (red * 2_126 + green * 7_152 + blue * 722) / 10_000

    minimumLuminance = min(minimumLuminance, luminance)
    maximumLuminance = max(maximumLuminance, luminance)
    visiblePixelCount += 1
}

let minimumVisiblePixels = max(1, (sampleWidth * sampleHeight) / 20)
guard visiblePixelCount >= minimumVisiblePixels else {
    fputs("Screenshot appears blank or too low contrast: \(imagePath)\n", stderr)
    exit(1)
}

let luminanceRange = maximumLuminance - minimumLuminance
if luminanceRange < 12 {
    fputs("Screenshot appears blank or too low contrast: \(imagePath)\n", stderr)
    exit(1)
}
SWIFT
}

write_appearance_preference() {
  local appearance="$1"
  HOME="$EVIDENCE_HOME" CFFIXED_USER_HOME="$EVIDENCE_HOME" \
    /usr/bin/defaults write "$BUNDLE_IDENTIFIER" solopm.appearancePreference -string "$appearance"
}

seed_database() {
  local database_path="$1"
  local tomorrow
  tomorrow="$(date -v+1d +%Y-%m-%d)"

  sqlite3 "$database_path" <<SQL
DELETE FROM tasks WHERE source_command = 'ui-evidence';
DELETE FROM projects WHERE source_command = 'ui-evidence';

INSERT INTO projects (title, status, priority, deadline, workspace_path, tags_json, source_command)
VALUES ('Launch Readiness', 'active', 'high', '$tomorrow', NULL, '["ui-evidence","local"]', 'ui-evidence');

INSERT INTO tasks (project_id, title, status, detail, due_at, priority, source_command)
VALUES
  ((SELECT id FROM projects WHERE source_command = 'ui-evidence' AND title = 'Launch Readiness' ORDER BY id DESC LIMIT 1),
   'Capture launch screenshots', 'planned', 'Verify board card density, sidebar, and inspector in each theme.', '$tomorrow', 'high', 'ui-evidence'),
  ((SELECT id FROM projects WHERE source_command = 'ui-evidence' AND title = 'Launch Readiness' ORDER BY id DESC LIMIT 1),
   'Review VoiceOver focus path', 'in_progress', 'Confirm project board to task card to inspector path before public alpha.', '$tomorrow', 'medium', 'ui-evidence'),
  ((SELECT id FROM projects WHERE source_command = 'ui-evidence' AND title = 'Launch Readiness' ORDER BY id DESC LIMIT 1),
   'Document remaining release blockers', 'blocked', 'Keep signing, notarization, and manual accessibility gates visible.', NULL, 'medium', 'ui-evidence');
SQL
}

capture_appearance() {
  local appearance="$1"
  local output_path="$2"

  write_appearance_preference "$appearance"
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  open_evidence_app
  wait_for_process
  activate_evidence_app
  sleep 1.5

  local window_metadata
  window_metadata="$(find_window_capture_metadata)"
  read -r window_id window_x window_y window_width window_height <<<"$window_metadata"

  if ! screencapture -x -l "$window_id" "$output_path"; then
    local full_screenshot
    full_screenshot="$(mktemp "${TMPDIR:-/tmp}/solopm-ui-evidence-full.XXXXXX.png")"
    trap 'rm -f "$full_screenshot"; cleanup' EXIT
    if ! screencapture -x "$full_screenshot"; then
      echo "screen capture failed. Grant Screen Recording permission to the terminal/Codex app and rerun." >&2
      exit 1
    fi
    /usr/bin/sips \
      -c "$window_height" "$window_width" \
      --cropOffset "$window_x" "$window_y" \
      "$full_screenshot" \
      --out "$output_path" >/dev/null
    rm -f "$full_screenshot"
    trap cleanup EXIT
  fi

  if [[ ! -s "$output_path" ]]; then
    echo "screenshot was not created: $output_path" >&2
    exit 1
  fi

  /usr/bin/sips -g pixelWidth -g pixelHeight "$output_path" >/dev/null

  if ! assert_screenshot_has_visible_content "$output_path"; then
    echo "This usually means Screen Recording permission is missing, the display is locked/headless, or the captured image is blank." >&2
    rm -f "$output_path"
    exit 1
  fi

  local bytes
  bytes="$(wc -c <"$output_path" | tr -d '[:space:]')"
  if [[ "$bytes" -lt 50000 ]]; then
    echo "screenshot is unexpectedly small ($bytes bytes): $output_path" >&2
    echo "This usually means Screen Recording permission is missing or the captured image is blank." >&2
    rm -f "$output_path"
    exit 1
  fi
}

write_evidence_file() {
  local generated_at="$1"
  local light_path="$2"
  local dark_path="$3"
  local system_path="$4"

  cat >"$EVIDENCE_FILE" <<EOF
# UI Screenshot Evidence

Generated with \`script/capture_ui_evidence.sh\`.

- Generated at: \`$generated_at\`
- App bundle: \`dist/$APP_NAME.app\`
- Data isolation: isolated temporary HOME via \`HOME\` and \`CFFIXED_USER_HOME\`
- Seed data: local \`Launch Readiness\` project with planned, in-progress, and blocked task cards
- Scope: Project board sidebar, task cards, and right inspector across Light/Dark/System

## Screenshots

- Light: \`$(relative_path "$light_path")\`
- Dark: \`$(relative_path "$dark_path")\`
- System: \`$(relative_path "$system_path")\`

## Notes

- The script seeds only deterministic local Project/Task data into the isolated SQLite database.
- API keys and provider tokens are not read, written, logged, or rendered.
- The capture host must grant Screen Recording permission to the terminal/Codex app; otherwise the script fails before treating screenshots as evidence.
- VoiceOver focus order still requires a manual assistive-technology pass.
EOF
}

require_command sqlite3
require_command screencapture
require_command swift
require_command sips
require_command osascript

mkdir -p "$SCREENSHOT_DIR"
mkdir -p "$EVIDENCE_HOME/Library/Application Support"

if [[ "$DRY_RUN" == "1" ]]; then
  echo "UI evidence dry run"
  echo "bundle: $APP_BUNDLE"
  echo "home: $EVIDENCE_HOME"
  echo "screenshots: $SCREENSHOT_DIR"
  echo "evidence: $EVIDENCE_FILE"
  exit 0
fi

"$ROOT_DIR/script/build_and_run.sh" --build-only

open_evidence_app
wait_for_process
activate_evidence_app
DATABASE_PATH="$EVIDENCE_HOME/Library/Application Support/SoloPM/SoloPM.sqlite"
wait_for_database "$DATABASE_PATH"
pkill -x "$APP_NAME" >/dev/null 2>&1 || true

seed_database "$DATABASE_PATH"

LIGHT_SCREENSHOT="$SCREENSHOT_DIR/project-board-light.png"
DARK_SCREENSHOT="$SCREENSHOT_DIR/project-board-dark.png"
SYSTEM_SCREENSHOT="$SCREENSHOT_DIR/project-board-system.png"

capture_appearance light "$LIGHT_SCREENSHOT"
capture_appearance dark "$DARK_SCREENSHOT"
capture_appearance system "$SYSTEM_SCREENSHOT"

GENERATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
write_evidence_file "$GENERATED_AT" "$LIGHT_SCREENSHOT" "$DARK_SCREENSHOT" "$SYSTEM_SCREENSHOT"

echo "UI screenshot evidence generated:"
echo "- $(relative_path "$LIGHT_SCREENSHOT")"
echo "- $(relative_path "$DARK_SCREENSHOT")"
echo "- $(relative_path "$SYSTEM_SCREENSHOT")"
echo "- $(relative_path "$EVIDENCE_FILE")"
