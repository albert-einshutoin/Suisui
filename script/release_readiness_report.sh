#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BLOCKER_COUNT=0
MOCK_PATTERN="(?i:fake|mock|canned|stub|skeleton|todo|fixme|not[[:space:]_-]*implemented|notimplemented|inmemory)|(?i:(^|[^[:alnum:]_])(demo|sample|placeholder)([^[:alnum:]_]|$))|Static[A-Za-z0-9_]*|:memory:|fatalError|preconditionFailure"
UI_EVIDENCE_RELATIVE="docs/release/evidence/ui-screenshots.md"
UI_SCREENSHOT_RELATIVE_DIR="docs/release/evidence/ui-screenshots"
UI_SCREENSHOT_MIN_BYTES=50000
UI_SCREENSHOT_MIN_WIDTH=640
UI_SCREENSHOT_MIN_HEIGHT=420
VOICEOVER_EVIDENCE_RELATIVE="docs/release/evidence/accessibility-voiceover.md"
MCP_EVIDENCE_RELATIVE="docs/release/evidence/mcp-inspector.md"
RUNTIME_SOURCE_DIRS=(
  "$ROOT_DIR/Sources/SoloPMCore"
  "$ROOT_DIR/Sources/SoloPMApp"
  "$ROOT_DIR/Sources/SoloPMCLI"
)
UI_SCREENSHOTS=(
  "Light:project-board-light.png"
  "Dark:project-board-dark.png"
  "System:project-board-system.png"
)
VOICEOVER_REQUIRED_MARKERS=(
  "Status: passed"
  "Project navigation"
  "Project board detail"
  "Open task"
  "Status controls"
  "Task inspector"
  "Save Changes"
  "Delete Task confirmation"
  "No keyboard trap"
  "No unlabeled primary CRUD controls"
)
MCP_EVIDENCE_REQUIRED_MARKERS=(
  "Generated:"
  "Scope: validate the release MCP stdio fixture"
  'Stable baseline: `2025-11-25`'
  'Draft watchlist: `2026-07-28`'
  "not a full MCP host"
  "initialize -> tools/list -> tools/call"
  "MCP Inspector CLI tools/list"
  "MCP Inspector CLI tools/call"
  "SoloPM local smoke success"
  "malformed-json"
  "mismatched-id"
  "invalid-schema"
  "timeout"
  "exit: 0"
)

section() {
  printf "\n== %s ==\n" "$1"
}

blocker() {
  BLOCKER_COUNT=$((BLOCKER_COUNT + 1))
  printf "BLOCKER: %s\n" "$1"
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

printf "SoloPM release readiness report\n"

section "Runtime mock/fake scan"
if ! command -v rg >/dev/null 2>&1; then
  blocker "rg is required for source scanning"
else
  missing_runtime_source=0
  for source_dir in "${RUNTIME_SOURCE_DIRS[@]}"; do
    if [[ ! -d "$source_dir" ]]; then
      blocker "missing runtime source directory: ${source_dir#"$ROOT_DIR/"}"
      missing_runtime_source=1
    fi
  done

  if [[ "$missing_runtime_source" -eq 0 ]]; then
    set +e
    scan_output="$(rg -n "$MOCK_PATTERN" "${RUNTIME_SOURCE_DIRS[@]}" 2>&1)"
    scan_status=$?
    set -e

    case "$scan_status" in
      0)
        printf "%s\n" "$scan_output"
        blocker "runtime source contains mock/fake/demo/test-only markers"
        ;;
      1)
        printf "OK: no runtime mock/fake/demo markers in Sources/SoloPMCore Sources/SoloPMApp Sources/SoloPMCLI\n"
        ;;
      *)
        if [[ -n "$scan_output" ]]; then
          printf "%s\n" "$scan_output"
        fi
        blocker "runtime mock/fake scan failed"
        ;;
    esac
  fi
fi

section "Phase checklist blockers"
phase_unchecked=""
if [[ -d "$ROOT_DIR/tasks" ]]; then
  while IFS= read -r phase_file; do
    phase_name="$(basename "$phase_file")"
    case "$phase_name" in
      Phase[0-9].md|Phase[0-9]-*.md|Phase10.md|Phase10-*.md)
        unchecked_items="$(rg -n --with-filename -- "- \\[ \\]" "$phase_file" || true)"
        if [[ -n "$unchecked_items" ]]; then
          if [[ -n "$phase_unchecked" ]]; then
            phase_unchecked+=$'\n'
          fi
          phase_unchecked+="$unchecked_items"
        fi
        ;;
    esac
  done < <(find "$ROOT_DIR/tasks" -maxdepth 1 -type f -name 'Phase*.md' | sort)
else
  blocker "missing tasks directory"
fi
readme_template_unchecked="$(rg -n -g '*.md' -- "- \\[ \\]" "$ROOT_DIR/tasks/README.md" || true)"

if [[ -n "$phase_unchecked" ]]; then
  printf "%s\n" "$phase_unchecked"
  blocker "phase checklist still has unchecked release/manual gates"
else
  printf "OK: no unchecked items in release phase checklists (Phase0-Phase10)\n"
fi

if [[ -n "$readme_template_unchecked" ]]; then
  printf "INFO: tasks/README.md contains unchecked template examples and is not counted as a release blocker.\n"
fi

section "UI screenshot evidence"
ui_evidence_file="$ROOT_DIR/$UI_EVIDENCE_RELATIVE"
if [[ ! -f "$ui_evidence_file" ]]; then
  blocker "missing UI screenshot evidence file: $UI_EVIDENCE_RELATIVE"
else
  if ! grep -F 'Generated with `script/capture_ui_evidence.sh`.' "$ui_evidence_file" >/dev/null; then
    blocker "UI screenshot evidence file was not generated by script/capture_ui_evidence.sh"
  fi
  if ! grep -F -- "- Generated at:" "$ui_evidence_file" >/dev/null; then
    blocker "UI screenshot evidence is missing generated timestamp"
  fi
fi

for screenshot_entry in "${UI_SCREENSHOTS[@]}"; do
  screenshot_label="${screenshot_entry%%:*}"
  screenshot_filename="${screenshot_entry#*:}"
  screenshot_relative="$UI_SCREENSHOT_RELATIVE_DIR/$screenshot_filename"
  screenshot_path="$ROOT_DIR/$screenshot_relative"

  if [[ ! -f "$screenshot_path" ]]; then
    blocker "missing UI screenshot file: $screenshot_relative"
    continue
  fi

  if [[ ! -s "$screenshot_path" ]]; then
    blocker "empty UI screenshot file: $screenshot_relative"
    continue
  fi

  screenshot_bytes="$(wc -c <"$screenshot_path" | tr -d '[:space:]')"
  if [[ "$screenshot_bytes" -lt "$UI_SCREENSHOT_MIN_BYTES" ]]; then
    blocker "UI screenshot is unexpectedly small ($screenshot_bytes bytes): $screenshot_relative"
    continue
  fi

  if [[ -f "$ui_evidence_file" ]] && ! grep -F "$screenshot_relative" "$ui_evidence_file" >/dev/null; then
    blocker "UI screenshot evidence does not reference $screenshot_relative"
  fi

  set +e
  dimensions_output="$(/usr/bin/sips -g pixelWidth -g pixelHeight "$screenshot_path" 2>&1)"
  dimensions_status=$?
  set -e

  if [[ "$dimensions_status" -ne 0 ]]; then
    printf "%s\n" "$dimensions_output"
    blocker "UI screenshot dimensions are unreadable: $screenshot_relative"
    continue
  fi

  pixel_width="$(awk '/pixelWidth:/ {print $2}' <<<"$dimensions_output" | tail -1)"
  pixel_height="$(awk '/pixelHeight:/ {print $2}' <<<"$dimensions_output" | tail -1)"
  if [[ ! "$pixel_width" =~ ^[0-9]+$ || ! "$pixel_height" =~ ^[0-9]+$ ]]; then
    blocker "UI screenshot dimensions are missing: $screenshot_relative"
    continue
  fi

  if [[ "$pixel_width" -lt "$UI_SCREENSHOT_MIN_WIDTH" || "$pixel_height" -lt "$UI_SCREENSHOT_MIN_HEIGHT" ]]; then
    blocker "UI screenshot dimensions are too small (${pixel_width}x${pixel_height}): $screenshot_relative"
    continue
  fi

  if ! command -v swift >/dev/null 2>&1; then
    blocker "swift is required for UI screenshot content validation"
    continue
  fi

  set +e
  content_output="$(assert_screenshot_has_visible_content "$screenshot_path" 2>&1)"
  content_status=$?
  set -e

  if [[ "$content_status" -ne 0 ]]; then
    if [[ -n "$content_output" ]]; then
      printf "%s\n" "$content_output"
    fi
    blocker "UI screenshot appears blank or too low contrast: $screenshot_relative"
    continue
  fi

  printf "OK: %s screenshot %s (%sx%s, %s bytes)\n" \
    "$screenshot_label" \
    "$screenshot_relative" \
    "$pixel_width" \
    "$pixel_height" \
    "$screenshot_bytes"
done

section "VoiceOver accessibility evidence"
voiceover_evidence_file="$ROOT_DIR/$VOICEOVER_EVIDENCE_RELATIVE"
if [[ ! -f "$voiceover_evidence_file" ]]; then
  blocker "missing VoiceOver accessibility evidence file: $VOICEOVER_EVIDENCE_RELATIVE"
else
  for required_marker in "${VOICEOVER_REQUIRED_MARKERS[@]}"; do
    if [[ "$required_marker" == "Status: passed" ]]; then
      marker_present=0
      grep -Fx "Status: passed" "$voiceover_evidence_file" >/dev/null && marker_present=1
    else
      marker_present=0
      grep -F "$required_marker" "$voiceover_evidence_file" >/dev/null && marker_present=1
    fi

    if [[ "$marker_present" -ne 1 ]]; then
      case "$required_marker" in
        "Status: passed")
          blocker "VoiceOver accessibility evidence is not marked passed"
          ;;
        *)
          blocker "VoiceOver accessibility evidence is missing marker: $required_marker"
          ;;
      esac
    fi
  done

  if grep -Eiq '(pending|todo|tbd|placeholder|sample|example|replace me)' "$voiceover_evidence_file"; then
    blocker "VoiceOver accessibility evidence still contains pending/template/placeholder text"
  fi
fi

section "MCP Inspector evidence"
mcp_evidence_file="$ROOT_DIR/$MCP_EVIDENCE_RELATIVE"
if [[ ! -f "$mcp_evidence_file" ]]; then
  blocker "missing MCP Inspector evidence file: $MCP_EVIDENCE_RELATIVE"
else
  mcp_missing_marker_count=0
  for required_marker in "${MCP_EVIDENCE_REQUIRED_MARKERS[@]}"; do
    if ! grep -F "$required_marker" "$mcp_evidence_file" >/dev/null; then
      blocker "MCP Inspector evidence is missing marker: $required_marker"
      mcp_missing_marker_count=$((mcp_missing_marker_count + 1))
    fi
  done
  if [[ "$mcp_missing_marker_count" -eq 0 ]]; then
    printf "OK: MCP Inspector evidence covers stable baseline, draft boundary, tools/list, tools/call, and failure taxonomy\n"
  fi
fi

section "Release environment preflight"
set +e
preflight_output="$("$ROOT_DIR/script/verify_release_environment.sh" 2>&1)"
preflight_status=$?
set -e

printf "%s\n" "$preflight_output"
if [[ "$preflight_status" -ne 0 ]]; then
  blocker "release environment preflight did not pass"
else
  printf "OK: release environment preflight passed\n"
fi

section "Summary"
if [[ "$BLOCKER_COUNT" -gt 0 ]]; then
  printf "NOT READY: %d blocker group(s) remain.\n" "$BLOCKER_COUNT"
  exit 2
fi

printf "READY: runtime, task checklist, and release environment gates passed.\n"
