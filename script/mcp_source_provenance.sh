#!/usr/bin/env bash

MCP_SOURCE_PATHS=(
  Sources/SuisuiCore/ExternalMCP
  Sources/SuisuiApp/SuisuiApp.swift
  Sources/SuisuiApp/Composition
  Sources/SuisuiApp/Views/SettingsView.swift
  fixtures/mcp
  Package.swift
)

mcp_git() {
  /usr/bin/env -i \
    PATH=/usr/bin:/bin \
    GIT_NO_REPLACE_OBJECTS=1 \
    /usr/bin/git \
    -c core.fsmonitor=false \
    -c core.ignoreStat=false \
    -c core.abbrev=8 \
    -c core.hooksPath=/dev/null \
    -c diff.external= \
    -c diff.trustExitCode=false \
    "$@"
}

mcp_content_source_ref() {
  local root_dir="$1"
  local source_ref="$2"
  local parent_suffix
  local candidate_parent
  local content_source_ref="$source_ref"
  local followed_parent

  # A GitHub merge commit can make `git log -- <paths>` select an unrelated
  # first-parent commit by timestamp even when the merged MCP content is exactly
  # the contributor parent's content. Prefer that content-preserving parent so
  # pre-merge evidence remains valid, and continue through later commits that do
  # not touch MCP paths. If neither parent matches, retaining the current ref
  # makes newly introduced or conflict-resolved content require fresh evidence.
  while true; do
    followed_parent=false
    for parent_suffix in ^2 ^1; do
      if ! candidate_parent="$(
        mcp_git -C "$root_dir" rev-parse \
          --verify "${content_source_ref}${parent_suffix}^{commit}" 2>/dev/null
      )"; then
        continue
      fi
      if mcp_git -C "$root_dir" diff --quiet "$candidate_parent" "$content_source_ref" -- \
        "${MCP_SOURCE_PATHS[@]}"; then
        content_source_ref="$candidate_parent"
        followed_parent=true
        break
      fi
    done
    if [[ "$followed_parent" == false ]]; then
      break
    fi
  done

  printf "%s" "$content_source_ref"
}

mcp_evidence_source_commit_for_ref() {
  local root_dir="$1"
  local source_ref="$2"
  local commit
  local content_source_ref

  if ! mcp_git -C "$root_dir" rev-parse --verify "${source_ref}^{commit}" >/dev/null 2>&1; then
    printf "Invalid SUISUI_MCP_SOURCE_REF: %s\n" "$source_ref" >&2
    return 1
  fi

  content_source_ref="$(mcp_content_source_ref "$root_dir" "$source_ref")"
  commit="$(
    mcp_git -C "$root_dir" log -1 --format=%h "$content_source_ref" -- \
      "${MCP_SOURCE_PATHS[@]}"
  )"
  if [[ -n "$commit" ]]; then
    printf "%s" "$commit"
  else
    mcp_git -C "$root_dir" rev-parse --short "$content_source_ref"
  fi
}
