#!/usr/bin/env bash
set -euo pipefail

if [[ "${SUISUI_CODEX_RUN_SUBSCRIPTION_SMOKE:-0}" != "1" ]]; then
  echo "Codex subscription smoke is opt-in because it may consume the current user's Codex allowance."
  echo "Run with SUISUI_CODEX_RUN_SUBSCRIPTION_SMOKE=1 and optionally SUISUI_CODEX_EXECUTABLE=/absolute/path/to/codex."
  exit 2
fi

codex_executable="${SUISUI_CODEX_EXECUTABLE:-}"
if [[ -z "$codex_executable" ]]; then
  codex_executable="$(command -v codex || true)"
fi

if [[ "$codex_executable" != /* || ! -x "$codex_executable" ]]; then
  echo "A valid absolute Codex executable path is required." >&2
  exit 1
fi

"$codex_executable" --version
# `login status` reports readiness without printing the credential store.
"$codex_executable" login status

export SUISUI_CODEX_LIVE_TEST=1
export SUISUI_CODEX_EXECUTABLE="$codex_executable"

swift test --filter CodexLocalRuntimeProviderTests/testLiveSubscriptionGeneratesToolFreeActionPlanWhenExplicitlyEnabled
swift test --filter CodexLocalRuntimeProviderTests/testLiveSubscriptionAccountModelAndCancelableLoginWhenExplicitlyEnabled
