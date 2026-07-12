# SoloPM TAKT Automation

This directory configures local subscription-only TAKT/devloopd automation for
SoloPM. Planning and final arbitration use Codex, implementation and scoped
verification fixes use Cursor Agent, and mergeability/security review uses agy.
OpenCode is intentionally not configured because this project must remain
operable when the OpenCode token allowance is exhausted.

## Prerequisites

Install and authenticate `takt`, `devloopd`, `codex`, `cursor-agent`, `agy`,
`gh`, and `jq`. Run commands from the SoloPM repository root.

Set the repository once per shell when auto-detection is not enough:

```bash
export TAKT_LOOP_REPO=albert-einshutoin/soloPM
```

`TAKT_LOOP_*` is the automation environment prefix.

## Verification

```bash
./script/check_takt_configuration.sh
./.takt/quality-gates/project-check.sh
TAKT_LOOP_GATE_MODE=full ./.takt/quality-gates/project-check.sh
devloopd doctor --subscription-only --repo "$PWD"
devloopd provider-smoke --cwd "$PWD" --provider codex-cli cursor-cli agy-cli
```

## One Issue

```bash
devloopd run \
  --issue 123 \
  --repo "${TAKT_LOOP_REPO:-owner/repo}" \
  --workflow .takt/workflows/subscription-devloop.yaml \
  --verbose
```

## One Scan Cycle

```bash
devloopd start \
  --repo "${TAKT_LOOP_REPO:-owner/repo}" \
  --workflow .takt/workflows/subscription-devloop.yaml \
  --once
```

## Full Auto Loop

```bash
.takt/automation/full-auto-devloop.sh once
.takt/automation/full-auto-devloop.sh loop
```

The loop:

1. creates required automation labels,
2. marks one safe issue with `agent:ready`,
3. runs `devloopd start --once`,
4. waits for PR checks,
5. posts an agy mergeability review for the current PR head,
6. merges only when checks, local guards, and review all pass.

Disable merge while validating a new project:

```bash
TAKT_LOOP_AUTO_MERGE=0 .takt/automation/full-auto-devloop.sh loop
```

Tune conservative auto-merge limits:

```bash
TAKT_LOOP_MAX_AUTO_MERGE_FILES=20 \
TAKT_LOOP_MAX_AUTO_MERGE_LINES=800 \
.takt/automation/full-auto-devloop.sh once
```

To also create new low-risk issues when no safe issue exists, enable the
generic issue crafter:

```bash
TAKT_LOOP_CREATE_ISSUES=1 \
.takt/automation/full-auto-devloop.sh loop
```

The issue crafter reads bounded project sources from README/docs/tasks by
default. Tune it per project when those are not the right product inputs:

```bash
TAKT_LOOP_PROJECT_NAME=my-project \
TAKT_LOOP_ISSUE_SOURCE_PATHS='README.md:docs:tasks' \
.takt/automation/create-product-issues.sh plan
```

For lower-noise continuous operation, use the staged scheduler. It separates
issue scouting, issue-to-PR, PR review, review-fix, and merge stages:

```bash
.takt/automation/staged-devloop.sh once
.takt/automation/staged-devloop.sh loop
```

## Agent Routing

- `codex-cli` / `gpt-5.5`: product-safe planning and final arbitration
- `cursor-cli` / `composer-2.5`: primary TDD implementation, scoped fixes, and hygiene review; this invokes `cursor-agent`
- `agy-cli` / `Gemini 3.5 Flash (High)`: mergeability and security review
