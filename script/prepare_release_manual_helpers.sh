#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

release_candidate_source_commit() {
  local commit
  # Manual helpers are regenerated around evidence files, but the stale check
  # should follow the release-candidate app/runtime source, not helper commits.
  commit="$(
    git -C "$ROOT_DIR" log -1 --format=%h -- \
      Sources/SoloPMApp \
      Sources/SoloPMCore \
      Sources/SoloPMCLI \
      Sources/SoloPMExternalConnectors \
      Package.swift \
      packaging/app_metadata.env 2>/dev/null || true
  )"
  if [[ -n "$commit" ]]; then
    printf "%s" "$commit"
  else
    git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || printf "unknown"
  fi
}

SOURCE_COMMIT="$(release_candidate_source_commit)"

VOICEOVER_SCRIPT="$ROOT_DIR/script/prepare_voiceover_review_candidate.sh"
COMPETITOR_SCRIPT="$ROOT_DIR/script/create_competitor_hands_on_evidence.sh"
RELEASE_MACHINE_SCRIPT="$ROOT_DIR/script/prepare_release_machine_evidence.sh"

COMPETITOR_PENDING_RELATIVE=".tmp/competitor-hands-on/competitor-hands-on-pending-$SOURCE_COMMIT.md"
COMPETITOR_BENCHMARK_PENDING_RELATIVE=".tmp/competitor-hands-on/competitor-benchmark-pending-$SOURCE_COMMIT.md"
VOICEOVER_PENDING_RELATIVE=".tmp/voiceover-review/accessibility-voiceover-pending-$SOURCE_COMMIT.md"
VOICEOVER_WORKSHEET_RELATIVE=".tmp/voiceover-review/voiceover-worksheet.md"
VOICEOVER_COMMAND_RELATIVE=".tmp/voiceover-review/create-evidence-command.sh"
COMPETITOR_COMMAND_RELATIVE=".tmp/competitor-hands-on/create-evidence-command.sh"
RELEASE_MACHINE_WORKSHEET_RELATIVE=".tmp/release-machine/release-machine-worksheet.md"
RELEASE_MACHINE_COMMAND_RELATIVE=".tmp/release-machine/create-release-evidence-command.sh"
PRUNE_STALE=0

usage() {
  printf '%s\n' "usage: $0 [--prune-stale]"
  printf '%s\n' ""
  printf '%s\n' "Regenerates release-candidate manual review helpers without writing passed evidence."
  printf '%s\n' "This does not mark VoiceOver, competitor hands-on, signing, notarization, Sparkle, Gatekeeper, or release evidence as passed."
  printf '%s\n' ""
  printf '%s\n' "--prune-stale removes ignored pending preview files for older source commits and legacy default preview files after the release-candidate helpers are regenerated."
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --prune-stale)
      PRUNE_STALE=1
      shift
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

prune_stale_preview_files() {
  local pattern="$1"
  local current_basename="$2"
  local file
  local basename
  local relative_path

  for file in $pattern; do
    [[ -e "$file" ]] || continue
    basename="${file##*/}"
    [[ "$basename" == "$current_basename" ]] && continue
    relative_path="${file#"$ROOT_DIR/"}"
    rm -f "$file"
    printf 'Removed stale manual helper preview: %s\n' "$relative_path"
  done
}

prune_stale_manual_helper_previews() {
  prune_stale_preview_files \
    "$ROOT_DIR/.tmp/voiceover-review/accessibility-voiceover-pending-*.md" \
    "accessibility-voiceover-pending-$SOURCE_COMMIT.md"
  prune_stale_preview_files \
    "$ROOT_DIR/.tmp/competitor-hands-on/competitor-hands-on-pending-*.md" \
    "competitor-hands-on-pending-$SOURCE_COMMIT.md"
  prune_stale_preview_files \
    "$ROOT_DIR/.tmp/competitor-hands-on/competitor-benchmark-pending-*.md" \
    "competitor-benchmark-pending-$SOURCE_COMMIT.md"

  local legacy_competitor_evidence="$ROOT_DIR/.tmp/competitor-hands-on/evidence.md"
  if [[ -e "$legacy_competitor_evidence" ]]; then
    rm -f "$legacy_competitor_evidence"
    printf 'Removed legacy manual helper preview: %s\n' "${legacy_competitor_evidence#"$ROOT_DIR/"}"
  fi
}

require_clean_tracked_source_tree_for_manual_helpers() {
  local tracked_source_status

  if ! git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "BLOCKER: manual release helper preparation requires git to verify the release source tree" >&2
    exit 2
  fi

  if ! tracked_source_status="$(git -C "$ROOT_DIR" status --porcelain --untracked-files=no 2>/dev/null)"; then
    echo "BLOCKER: manual release helper preparation could not inspect tracked source tree status" >&2
    exit 2
  fi

  if [[ -n "$tracked_source_status" ]]; then
    echo "BLOCKER: manual release helper preparation requires a clean tracked source tree. Commit or revert tracked source changes, then rerun ./script/prepare_release_manual_helpers.sh for this release candidate." >&2
    exit 2
  fi
}

for helper_script in "$VOICEOVER_SCRIPT" "$COMPETITOR_SCRIPT" "$RELEASE_MACHINE_SCRIPT"; do
  if [[ ! -x "$helper_script" ]]; then
    echo "missing executable helper script: ${helper_script#"$ROOT_DIR/"}" >&2
    exit 2
  fi
done

cd "$ROOT_DIR"
require_clean_tracked_source_tree_for_manual_helpers

printf 'Preparing manual release helpers for release-candidate source commit: %s\n' "$SOURCE_COMMIT"
printf '%s\n' 'This does not write passed manual evidence.'

"$VOICEOVER_SCRIPT" --no-launch --skip-build
"$COMPETITOR_SCRIPT" \
  --pending \
  --output "$COMPETITOR_PENDING_RELATIVE" \
  --benchmark-output "$COMPETITOR_BENCHMARK_PENDING_RELATIVE"
"$RELEASE_MACHINE_SCRIPT"

printf '\n'
printf 'Manual release helpers prepared for release-candidate source commit: %s\n' "$SOURCE_COMMIT"
printf -- '- VoiceOver pending preview: `%s`\n' "$VOICEOVER_PENDING_RELATIVE"
printf -- '- VoiceOver worksheet: `%s`\n' "$VOICEOVER_WORKSHEET_RELATIVE"
printf -- '- VoiceOver evidence command: `%s`\n' "$VOICEOVER_COMMAND_RELATIVE"
printf -- '- Competitor pending evidence: `%s`\n' "$COMPETITOR_PENDING_RELATIVE"
printf -- '- Competitor benchmark pending worksheet: `%s`\n' "$COMPETITOR_BENCHMARK_PENDING_RELATIVE"
printf -- '- Competitor worksheet: `.tmp/competitor-hands-on/hands-on-worksheet.md`\n'
printf -- '- Competitor evidence command: `%s`\n' "$COMPETITOR_COMMAND_RELATIVE"
printf -- '- Release machine worksheet: `%s`\n' "$RELEASE_MACHINE_WORKSHEET_RELATIVE"
printf -- '- Release evidence command: `%s`\n' "$RELEASE_MACHINE_COMMAND_RELATIVE"
printf '\n'

if [[ "$PRUNE_STALE" -eq 1 ]]; then
  prune_stale_manual_helper_previews
  printf '\n'
fi

printf '%s\n' 'NEXT: replace placeholders in the generated command files only after the real manual pass is complete.'
printf '%s\n' 'NEXT: rerun `./script/release_readiness_report.sh` to verify helper freshness.'
