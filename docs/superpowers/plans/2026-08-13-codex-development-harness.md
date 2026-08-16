# Codex Development Harness Implementation Plan

> **For Codex:** Use the Ponytail skill throughout. Implement each task with the smallest change that reuses Suisui's existing quality gates. Use the selected Sol/Terra/Luna role routing and keep this worktree isolated from the user's main checkout.

**Goal:** Give Suisui a short repository-specific Codex entrypoint, fixed UI completion criteria, repeatable engineering-quality baselines, and lean task-specific Skill profiles.

**Architecture:** Keep policy in small index documents and compose existing scripts instead of introducing a second validation framework. Store reusable Codex profiles in `$CODEX_HOME`, keep repository behavior in root `AGENTS.md`, and generate metric snapshots from GitHub's read-only API with a tested standard-library parser.

**Tech Stack:** Markdown, TOML, Bash/Python standard library, GitHub CLI, SwiftPM/macOS validation scripts.

---

### Task 1: Create the repository entrypoint

**Files:**
- Create: `AGENTS.md`
- Create: `ARCHITECTURE.md`

- [x] Point agents to canonical build, test, security, architecture, ADR, UI, and PR-completion sources.
- [x] Record the Sol/Terra/Luna routing and the rule that unavailable models must be reported rather than silently substituted.
- [x] Keep architectural detail in existing documents; make the root file an index and boundary map.
- [x] Verify every referenced path and command exists.

### Task 2: Fix the UI definition of done

**Files:**
- Create: `docs/quality/ui-done-criteria.md`
- Modify: `AGENTS.md`

- [x] Define when runtime, accessibility, localization, visual, layout, performance, and human review evidence is required.
- [x] Bind each criterion to an existing Suisui command or evidence artifact.
- [x] State fail-closed rules for unknown impact, unavailable selectors, and stale evidence.
- [x] Run focused source-contract tests that protect quality documentation.

### Task 3: Add a repeatable quality-metric baseline

**Files:**
- Create: `script/quality_metrics_baseline.py`
- Create: `ci/tests/test_quality_metrics_baseline.py`
- Create: `docs/quality/engineering-metrics.md`
- Create: `docs/quality/engineering-metrics-baseline.json`

- [x] Write failing parser tests for empty samples, first-attempt success, reruns, failed runs, and neutral conclusions.
- [x] Implement a standard-library collector that reads GitHub Actions JSON from stdin or `gh api`, redacts repository-independent details, and emits a versioned deterministic summary.
- [x] Define a bounded sample window and explicitly distinguish missing data from zero.
- [x] Capture the current live baseline without mutating GitHub state.
- [x] Run the focused Python tests and validate the generated JSON.

### Task 4: Split Skill context by use case

**Files:**
- Modify: `/Users/shutoide/.codex/AGENTS.md`
- Create: `/Users/shutoide/.codex/macos.config.toml`
- Create: `/Users/shutoide/.codex/web.config.toml`
- Create: `/Users/shutoide/.codex/rust.config.toml`
- Create: `/Users/shutoide/.codex/research.config.toml`
- Create: `/Users/shutoide/.codex/PROFILES.md`

- [x] Replace obsolete goal/subagent model instructions with the selected Sol/Terra/Luna routing.
- [x] Keep Ponytail, GitHub, Superpowers, and security capabilities in development profiles while disabling unrelated language and product skills.
- [x] Keep research/documentation capabilities in the research profile and disable implementation-only plugins there.
- [x] Document selection commands and the difference between global defaults, profiles, and repository instructions.
- [x] Validate every profile with strict Codex config parsing.

### Task 5: Verify and review

**Files:**
- Review all files above.

- [x] Run `python3 -m unittest ci.tests.test_quality_metrics_baseline`.
- [x] Run `./script/check_security_regressions.sh`.
- [x] Run the repository's relevant focused tests, then `./scripts/ci.sh` because the entrypoint changes global development policy. The full lane exposed the pre-existing stale MCP inspector evidence test; focused changed-scope gates passed.
- [x] Run strict config validation for all four profiles.
- [x] Use a Python reviewer for the collector and a Sol max final review for the complete change.
- [x] Resolve important findings, rerun affected gates, and leave the branch in a clean, reviewable state.
