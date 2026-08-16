import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
AGENT_ENTRYPOINT = REPOSITORY_ROOT / "AGENTS.md"
SELECTED_RUNNER = REPOSITORY_ROOT / "ci" / "run-selected.py"
FULL_RUNNER = REPOSITORY_ROOT / "ci" / "run-full.sh"
ALL_RUNNER = REPOSITORY_ROOT / "ci" / "run-all.sh"
CI_SCRIPT = REPOSITORY_ROOT / "scripts" / "ci.sh"
WORKFLOW = REPOSITORY_ROOT / ".github" / "workflows" / "ci.yml"
RELEASE_PREFLIGHT = REPOSITORY_ROOT / "script" / "check_automated_release_preflight.sh"
RELEASE_READINESS = REPOSITORY_ROOT / "script" / "release_readiness_report.sh"
MCP_VERIFIER = REPOSITORY_ROOT / "script" / "verify_mcp_compliance.sh"
MCP_PROVENANCE = REPOSITORY_ROOT / "script" / "mcp_source_provenance.sh"
TRUSTED_GIT = REPOSITORY_ROOT / "ci" / "trusted-bin" / "git"
ORCHESTRATOR = REPOSITORY_ROOT / "ci" / "run-pr-ci.sh"
PLAN_EXPORTER = REPOSITORY_ROOT / "ci" / "export-plan.py"
PLAN_ESCALATOR = REPOSITORY_ROOT / "ci" / "escalate-plan.py"


class ExecutionContractTests(unittest.TestCase):
    def test_repository_agent_entrypoint_records_model_routing(self) -> None:
        contents = AGENT_ENTRYPOINT.read_text(encoding="utf-8")

        for model in ("Sol xhigh/max", "Terra high/xhigh", "Luna high/max"):
            self.assertIn(model, contents)
        self.assertIn("黙って代替せず", contents)

    def test_selected_runner_dry_run_emits_allowlisted_argv_and_counts(self) -> None:
        plan = {
            "strategy": "selective",
            "unitTestTargets": ["WidgetTests"],
            "integrationTestTargets": ["ExternalMCPTests"],
            "smokeTestTargets": ["DevelopmentAutomationRuntimeSmokeTests"],
            "e2eTestTargets": [],
        }
        result, report = self._run_selected(plan)

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(report["status"], "passed")
        self.assertEqual(report["targetCount"], 3)
        self.assertEqual(report["successCount"], 3)
        self.assertEqual(report["failureCount"], 0)
        self.assertEqual(
            report["commands"][0]["argv"],
            ["swift", "test", "--filter", "WidgetTests"],
        )
        self.assertTrue(all(isinstance(item["argv"], list) for item in report["commands"]))

    def test_selected_runner_rejects_non_allowlisted_target_as_setup_failure(self) -> None:
        plan = {
            "strategy": "selective",
            "unitTestTargets": ["WidgetTests; touch escaped"],
            "integrationTestTargets": [],
            "smokeTestTargets": ["DevelopmentAutomationRuntimeSmokeTests"],
            "e2eTestTargets": [],
        }
        result, report = self._run_selected(plan)

        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertEqual(report["status"], "setup-failed")
        self.assertEqual(report["successCount"], 0)

    def test_selected_runner_treats_zero_executed_tests_as_setup_failure(self) -> None:
        result, report = self._run_selected_with_fake_toolchain(
            "Executed 0 tests, with 0 failures (0 unexpected)\n"
        )

        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertEqual(report["status"], "setup-failed")
        self.assertIn("zero tests", report["failureReason"])

    def test_selected_runner_reports_actual_test_counts_instead_of_filter_count(self) -> None:
        result, report = self._run_selected_with_fake_toolchain(
            "Executed 3 tests, with 1 test skipped and 0 failures (0 unexpected)\n"
        )

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(report.get("targetCount"), 1)
        self.assertEqual(report.get("executedTestCount"), 3)
        self.assertEqual(report.get("successCount"), 2)
        self.assertEqual(report.get("skippedCount"), 1)

    def test_selected_runner_reports_actual_failure_and_success_counts(self) -> None:
        result, report = self._run_selected_with_fake_toolchain(
            "Executed 4 tests, with 1 test skipped and 2 failures (0 unexpected)\n",
            test_exit_code=1,
        )

        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertEqual(report.get("executedTestCount"), 4)
        self.assertEqual(report.get("successCount"), 1)
        self.assertEqual(report.get("failureCount"), 2)
        self.assertEqual(report.get("skippedCount"), 1)

    def test_full_runner_is_independent_from_planner_and_runs_canonical_gates(self) -> None:
        self.assertTrue(FULL_RUNNER.exists(), "independent full runner must exist")
        contents = FULL_RUNNER.read_text(encoding="utf-8")

        self.assertIn("./scripts/ci.sh swiftpm", contents)
        self.assertIn("./script/check_pseudo_voiceover_paths.sh", contents)
        self.assertNotIn("check_pseudo_voiceover_paths.sh --swift-test", contents)
        self.assertNotIn("./scripts/ci.sh source-contracts", contents)
        self.assertIn("./script/check_security_regressions.sh", contents)
        self.assertIn("int(executed) - int(skipped)", contents)
        self.assertIn("BLOCKER: full execution report could not be written", contents)
        self.assertIn("full test count evidence is missing or invalid", contents)
        self.assertNotIn("impact/analyze", contents)
        self.assertNotIn("ci/config", contents)
        self.assertNotIn("ci/tests", contents)

    def test_all_runner_adds_every_ui_lane_to_full_validation_with_pinned_helpers(self) -> None:
        self.assertTrue(ALL_RUNNER.exists(), "complete local CI runner must exist")
        contents = ALL_RUNNER.read_text(encoding="utf-8")

        self.assertIn("-u SUISUI_SWIFTPM_TEST_BASELINE_FILE", contents)
        self.assertIn("-u SUISUI_SWIFTPM_MAX_SKIPPED_FILE", contents)
        self.assertIn("./ci/run-full.sh", contents)
        self.assertNotIn("cargo fmt --manifest-path", contents)
        self.assertNotIn("cargo test --manifest-path", contents)
        self.assertNotIn("cargo clippy --manifest-path", contents)
        for variable in (
            "SQLITE3",
            "AX_HELPERS",
            "AX_TEXT_INPUT_HELPER",
            "AX_SCROLL_HELPER",
            "AX_BUTTON_HELPER",
            "AX_MARKER_HELPER",
            "AX_FRAME_HELPER",
            "AX_PRESS_ELEMENT_HELPER",
            "AX_RESIZE_WINDOW_HELPER",
            "AX_IDENTIFIER_COUNT_HELPER",
            "WINDOW_CONTENT_SIZE_HELPER",
        ):
            self.assertIn(variable, contents)
        self.assertIn("GIT_NO_REPLACE_OBJECTS=1", contents)
        self.assertIn('PATH="$ROOT_DIR/ci/trusted-bin:/usr/bin:/bin:', contents)
        self.assertNotIn("export GIT_CONFIG_GLOBAL=", contents)
        for variable in (
            "SUISUI_RUNTIME_ACCESSIBLE_CRUD_RECOVERABLE_ONLY",
            "SUISUI_LAYOUT_STABILITY_FRAME_DELTA_THRESHOLD_PX",
            "SUISUI_LAYOUT_STABILITY_CLIPPING_TOLERANCE_PX",
            "SUISUI_LAYOUT_STABILITY_DATABASE_PATH",
            "SUISUI_HEADER_LAYOUT_DATABASE_PATH",
            "SUISUI_HEADER_LAYOUT_ENTRYPOINTS_ONLY",
            "SUISUI_LAYOUT_STABILITY_WINDOW_MIN_WIDTH",
            "SUISUI_LAYOUT_STABILITY_WINDOW_STANDARD_WIDTH",
            "SUISUI_LAYOUT_STABILITY_WINDOW_WIDE_WIDTH",
            "SUISUI_RUNTIME_TODAY_MAX_TOOLBAR_LAYOUT_DEPTH",
            "SUISUI_RUNTIME_TODAY_WINDOW_WIDTH",
            "SUISUI_RUNTIME_TODAY_WINDOW_HEIGHT",
        ):
            self.assertIn(f"-u {variable}", contents)
        self.assertIn("./scripts/ci.sh ui-runtime", contents)
        self.assertIn("SUISUI_CI_COMPLETE_RUNTIME=1", contents)
        ci_contents = CI_SCRIPT.read_text(encoding="utf-8")
        self.assertIn('if [[ "$CI_COMPLETE_RUNTIME" == "1" ]]', ci_contents)
        self.assertIn("require_fully_exercised_runtime", ci_contents)
        self.assertIn("accessible_crud_recoverable_only=0", ci_contents)
        self.assertIn(
            "SUISUI_CI_COMPLETE_RUNTIME: 0",
            WORKFLOW.read_text(encoding="utf-8"),
        )
        release_contents = RELEASE_PREFLIGHT.read_text(encoding="utf-8")
        self.assertIn("SUISUI_CI_COMPLETE_RUNTIME=1", release_contents)
        self.assertIn("-u SUISUI_LAYOUT_STABILITY_FRAME_DELTA_THRESHOLD_PX", release_contents)
        self.assertIn("-u SUISUI_LAYOUT_STABILITY_CLIPPING_TOLERANCE_PX", release_contents)
        self.assertIn("-u SUISUI_RUNTIME_TODAY_MAX_TOOLBAR_LAYOUT_DEPTH", release_contents)
        self.assertIn("SUISUI_CI_VISUAL_BASELINE_PROFILE=local-display", release_contents)
        self.assertIn("SUISUI_RUNTIME_POLICY=public-alpha", contents)
        self.assertIn("-u SUISUI_CI_VISUAL_GATE_LOCALE", contents)
        for variable in self._visual_proof_overrides():
            self.assertIn(f"-u {variable}", contents)
        self.assertIn("SUISUI_CI_VISUAL_BASELINE_PROFILE=local-display", contents)
        self.assertIn("./scripts/ci.sh ui-visual", contents)
        for variable in (
            "SUISUI_PERFORMANCE_PROFILE",
            "SUISUI_PERFORMANCE_BUILD_CONFIGURATION",
            "SUISUI_PERFORMANCE_MAX_COLD_LAUNCH_MS",
            "SUISUI_PERFORMANCE_MAX_DESTINATION_SWITCH_MS",
            "SUISUI_PERFORMANCE_USE_PREBUILT_APP",
            "SUISUI_PERFORMANCE_DATABASE_PATH",
        ):
            self.assertIn(f"-u {variable}", contents)
        self.assertIn("./scripts/ci.sh ui-performance", contents)
        self.assertNotIn("impact/analyze", contents)

    def test_release_preflight_pins_complete_evidence_inputs(self) -> None:
        contents = RELEASE_PREFLIGHT.read_text(encoding="utf-8")

        self.assertIn('XCODE_SCHEME="Suisui"', contents)
        self.assertIn('XCODE_DESTINATION="platform=macOS"', contents)
        self.assertIn('XCODE_CONFIGURATION="Debug"', contents)
        self.assertNotIn('XCODE_SCHEME="${SUISUI_XCODE_SCHEME', contents)
        self.assertNotIn('XCODE_DESTINATION="${SUISUI_XCODE_DESTINATION', contents)
        self.assertNotIn('XCODE_CONFIGURATION="${SUISUI_XCODE_CONFIGURATION', contents)
        for variable in (
            "SUISUI_CI_LANE",
            "SUISUI_SWIFTPM_TEST_BASELINE_FILE",
            "SUISUI_SWIFTPM_MAX_SKIPPED_FILE",
        ):
            self.assertIn(f"-u {variable}", contents)
        for variable in (
            "SQLITE3",
            "AX_HELPERS",
            "AX_TEXT_INPUT_HELPER",
            "AX_SCROLL_HELPER",
            "AX_BUTTON_HELPER",
            "AX_MARKER_HELPER",
            "AX_FRAME_HELPER",
            "AX_PRESS_ELEMENT_HELPER",
            "AX_RESIZE_WINDOW_HELPER",
            "AX_IDENTIFIER_COUNT_HELPER",
            "WINDOW_CONTENT_SIZE_HELPER",
        ):
            self.assertIn(variable, contents)
        for variable in self._visual_proof_overrides():
            self.assertIn(f"-u {variable}", contents)
        for variable in (
            "GIT_DIR",
            "GIT_WORK_TREE",
            "GIT_COMMON_DIR",
            "GIT_INDEX_FILE",
            "GIT_OBJECT_DIRECTORY",
            "GIT_ALTERNATE_OBJECT_DIRECTORIES",
            "GIT_SHALLOW_FILE",
        ):
            self.assertIn(variable, contents)
        self.assertIn("GIT_NO_REPLACE_OBJECTS=1", contents)
        self.assertIn('TRUSTED_GIT="$ROOT_DIR/ci/trusted-bin/git"', contents)
        self.assertNotIn("export GIT_CONFIG_GLOBAL=", contents)
        self.assertIn("/usr/bin/xcodebuild", contents)
        self.assertIn("-u SUISUI_MCP_INSPECTOR_BIN", contents)
        self.assertIn("SUISUI_MCP_SOURCE_REF=HEAD", contents)
        self.assertIn("-u SUISUI_MCP_NPX_BIN", contents)
        self.assertIn("initialize_automated_preflight_evidence_destination", contents)
        self.assertIn("unsafe automated preflight evidence destination", contents)
        self.assertIn("/bin/mv -fh", contents)

    def test_trusted_git_ignores_caller_diff_configuration(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(["/usr/bin/git", "init", "-q", str(root)], check=True)
            tracked = root / "tracked.txt"
            tracked.write_text("before\n", encoding="utf-8")
            subprocess.run(["/usr/bin/git", "-C", str(root), "add", "tracked.txt"], check=True)
            subprocess.run(
                [
                    "/usr/bin/git",
                    "-C",
                    str(root),
                    "-c",
                    "user.name=CI Test",
                    "-c",
                    "user.email=ci@example.invalid",
                    "commit",
                    "-qm",
                    "baseline",
                ],
                check=True,
            )
            tracked.write_text("after\n", encoding="utf-8")
            environment = os.environ.copy()
            environment["GIT_CONFIG_PARAMETERS"] = (
                "'diff.external=/usr/bin/true' 'diff.trustExitCode=true'"
            )

            result = subprocess.run(
                [str(TRUSTED_GIT), "-C", str(root), "diff", "--quiet", "--", "."],
                env=environment,
                check=False,
            )

            self.assertNotEqual(result.returncode, 0)

    def test_trusted_git_ignores_repository_fsmonitor_configuration(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(["/usr/bin/git", "init", "-q", str(root)], check=True)
            tracked = root / "tracked.txt"
            tracked.write_text("before\n", encoding="utf-8")
            subprocess.run(["/usr/bin/git", "-C", str(root), "add", "tracked.txt"], check=True)
            subprocess.run(
                [
                    "/usr/bin/git",
                    "-C",
                    str(root),
                    "-c",
                    "user.name=CI Test",
                    "-c",
                    "user.email=ci@example.invalid",
                    "commit",
                    "-qm",
                    "baseline",
                ],
                check=True,
            )
            fake_monitor = root / "fake-fsmonitor.sh"
            fake_monitor.write_text("#!/bin/sh\nprintf 'token\\0'\n", encoding="utf-8")
            fake_monitor.chmod(0o755)
            subprocess.run(
                [
                    "/usr/bin/git",
                    "-C",
                    str(root),
                    "config",
                    "core.fsmonitor",
                    str(fake_monitor),
                ],
                check=True,
            )
            subprocess.run(
                ["/usr/bin/git", "-C", str(root), "status", "--porcelain=v1"],
                check=True,
                capture_output=True,
            )
            tracked.write_text("after\n", encoding="utf-8")

            result = subprocess.run(
                [str(TRUSTED_GIT), "-C", str(root), "diff", "--quiet", "--", "."],
                check=False,
            )

            self.assertNotEqual(result.returncode, 0)

    def test_release_preflight_rejects_external_and_symlink_evidence_paths_early(self) -> None:
        (REPOSITORY_ROOT / ".tmp").mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory() as outside_directory:
            outside = Path(outside_directory)
            external_result = self._run_release_preflight_with_evidence(outside / "evidence.md")
            self.assertNotEqual(external_result.returncode, 0)
            self.assertIn("unsafe automated preflight evidence destination", external_result.stderr)

            with tempfile.TemporaryDirectory(dir=REPOSITORY_ROOT / ".tmp") as trusted_directory:
                trusted = Path(trusted_directory)
                ancestor_link = trusted / "ancestor"
                ancestor_link.symlink_to(outside, target_is_directory=True)
                ancestor_result = self._run_release_preflight_with_evidence(
                    ancestor_link / "evidence.md"
                )
                self.assertNotEqual(ancestor_result.returncode, 0)
                self.assertIn(
                    "unsafe automated preflight evidence destination",
                    ancestor_result.stderr,
                )
                self.assertFalse((outside / "evidence.md").exists())

                protected_target = outside / "protected.md"
                protected_target.write_text("protected\n", encoding="utf-8")
                leaf_link = trusted / "leaf.md"
                leaf_link.symlink_to(protected_target)
                leaf_result = self._run_release_preflight_with_evidence(leaf_link)
                self.assertNotEqual(leaf_result.returncode, 0)
                self.assertIn(
                    "unsafe automated preflight evidence destination",
                    leaf_result.stderr,
                )
                self.assertEqual(protected_target.read_text(encoding="utf-8"), "protected\n")

    def test_mcp_verifier_rejects_empty_successful_inspector_output(self) -> None:
        (REPOSITORY_ROOT / ".tmp").mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=REPOSITORY_ROOT / ".tmp") as directory:
            root = Path(directory)
            evidence = root / "mcp-inspector.md"
            fake_bin = root / "bin"
            fake_bin.mkdir()
            git_marker = root / "fake-git-invoked"
            fake_git = fake_bin / "git"
            fake_git.write_text(
                "#!/bin/sh\n"
                f"printf invoked > {git_marker}\n"
                "exec /usr/bin/git \"$@\"\n",
                encoding="utf-8",
            )
            fake_git.chmod(0o755)
            environment = os.environ.copy()
            environment.update(
                {
                    "PATH": str(fake_bin) + os.pathsep + environment["PATH"],
                    "GIT_DIR": str(root / "forged.git"),
                    "GIT_WORK_TREE": str(root / "forged-worktree"),
                    "SUISUI_MCP_INSPECTOR_BIN": "/usr/bin/true",
                    "SUISUI_MCP_EVIDENCE_FILE": str(evidence),
                }
            )
            result = subprocess.run(
                [str(MCP_VERIFIER)],
                cwd=str(REPOSITORY_ROOT),
                env=environment,
                text=True,
                capture_output=True,
                check=False,
            )

            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("Inspector tools/list output is invalid", result.stderr)
            self.assertFalse(git_marker.exists(), "MCP provenance must use /usr/bin/git")

    def test_mcp_verifier_resolves_npx_without_caller_path(self) -> None:
        contents = MCP_VERIFIER.read_text(encoding="utf-8")

        for path in ("/opt/homebrew/bin/npx", "/usr/local/bin/npx", "/usr/bin/npx"):
            self.assertIn(path, contents)
        self.assertIn('SUISUI_MCP_NPX_BIN:-', contents)
        self.assertNotIn("INSPECTOR_COMMAND=(npx ", contents)
        self.assertIn('@modelcontextprotocol/inspector@2.2.0', contents)
        self.assertIn("NPM_CONFIG_REGISTRY=https://registry.npmjs.org/", contents)
        self.assertIn("NPM_CONFIG_USERCONFIG=/dev/null", contents)
        self.assertIn("-u NODE_OPTIONS", contents)
        provenance = MCP_PROVENANCE.read_text(encoding="utf-8")
        self.assertIn("mcp_git()", provenance)
        self.assertIn('/usr/bin/git "$@"', provenance)
        self.assertNotIn('/usr/bin/git -C "$root_dir"', provenance)

    def test_mcp_verifier_rejects_symlink_evidence_destination_early(self) -> None:
        (REPOSITORY_ROOT / ".tmp").mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=REPOSITORY_ROOT / ".tmp") as directory:
            root = Path(directory)
            target = root / "protected.md"
            target.write_text("protected\n", encoding="utf-8")
            link = root / "evidence.md"
            link.symlink_to(target)
            environment = os.environ.copy()
            environment.update(
                {
                    "SUISUI_MCP_INSPECTOR_BIN": "/usr/bin/true",
                    "SUISUI_MCP_EVIDENCE_FILE": str(link),
                }
            )

            result = subprocess.run(
                [str(MCP_VERIFIER)],
                cwd=str(REPOSITORY_ROOT),
                env=environment,
                text=True,
                capture_output=True,
                check=False,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("unsafe MCP evidence destination", result.stderr)
            self.assertEqual(target.read_text(encoding="utf-8"), "protected\n")

    def test_release_mcp_evidence_cannot_use_custom_inspector(self) -> None:
        environment = os.environ.copy()
        environment.update(
            {
                "SUISUI_MCP_INSPECTOR_BIN": "/usr/bin/true",
                "SUISUI_MCP_EVIDENCE_FILE": str(
                    REPOSITORY_ROOT / "docs/release/evidence/mcp-inspector.md"
                ),
            }
        )
        result = subprocess.run(
            [str(MCP_VERIFIER)],
            cwd=str(REPOSITORY_ROOT),
            env=environment,
            text=True,
            capture_output=True,
            check=False,
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("custom MCP Inspector may write test evidence only", result.stderr)
        readiness = RELEASE_READINESS.read_text(encoding="utf-8")
        self.assertIn("-u SUISUI_MCP_INSPECTOR_BIN", readiness)
        self.assertIn("-u SUISUI_MCP_NPX_BIN", readiness)
        self.assertIn("SUISUI_MCP_SOURCE_REF=HEAD", readiness)
        self.assertIn('$ROOT_DIR/.tmp/mcp-runtime-evidence.XXXXXX.md', readiness)

    def test_release_readiness_uses_sanitized_git_for_all_provenance(self) -> None:
        readiness = RELEASE_READINESS.read_text(encoding="utf-8")
        provenance = MCP_PROVENANCE.read_text(encoding="utf-8")

        self.assertIn("release_git()", readiness)
        self.assertNotRegex(readiness, r'(?m)^\s*git -C "\$ROOT_DIR"')
        self.assertIn('PATH="$ROOT_DIR/ci/trusted-bin:$PATH"', readiness)
        self.assertIn("/usr/bin/env -i", provenance)
        self.assertIn("PATH=/usr/bin:/bin", provenance)

    def test_orchestrator_self_test_proves_fail_closed_state_transitions(self) -> None:
        self.assertTrue(ORCHESTRATOR.exists(), "PR orchestrator must exist")
        result = subprocess.run(
            [str(ORCHESTRATOR), "--self-test"],
            cwd=str(REPOSITORY_ROOT),
            text=True,
            capture_output=True,
            check=False,
        )

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("planner-failure -> full: passed", result.stdout)
        self.assertIn("selector-setup-failure -> full: passed", result.stdout)
        self.assertIn("selected-test-failure -> failed: passed", result.stdout)

    def test_plan_exporter_defaults_to_full_when_plan_is_missing(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            output = root / "outputs.txt"
            result = subprocess.run(
                [
                    "python3",
                    str(PLAN_EXPORTER),
                    "--plan",
                    str(root / "missing.json"),
                    "--github-output",
                    str(output),
                ],
                cwd=str(REPOSITORY_ROOT),
                text=True,
                capture_output=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            exported = output.read_text(encoding="utf-8")
            self.assertIn("strategy=full", exported)
            self.assertIn("ui_runtime=true", exported)
            self.assertIn("fallback_reason=plan unavailable or invalid", exported)

    def test_plan_exporter_maps_only_selective_e2e_outputs(self) -> None:
        plan = {
            "strategy": "selective",
            "e2eTestTargets": ["ui-runtime"],
            "fallbackReason": None,
        }
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            plan_path = root / "plan.json"
            output = root / "outputs.txt"
            plan_path.write_text(json.dumps(plan), encoding="utf-8")
            result = subprocess.run(
                [
                    "python3",
                    str(PLAN_EXPORTER),
                    "--plan",
                    str(plan_path),
                    "--github-output",
                    str(output),
                ],
                cwd=str(REPOSITORY_ROOT),
                text=True,
                capture_output=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            exported = output.read_text(encoding="utf-8")
            self.assertIn("strategy=selective", exported)
            self.assertNotIn("shadow_full", exported)
            self.assertIn("ui_runtime=true", exported)
            self.assertIn("ui_visual=false", exported)

    def test_plan_escalator_records_full_fallback_and_all_ui_targets(self) -> None:
        plan = {
            "strategy": "selective",
            "fallback": False,
            "fallbackReason": None,
            "e2eTestTargets": [],
        }
        with tempfile.TemporaryDirectory() as directory:
            plan_path = Path(directory) / "plan.json"
            plan_path.write_text(json.dumps(plan), encoding="utf-8")
            result = subprocess.run(
                [
                    "python3",
                    str(PLAN_ESCALATOR),
                    "--plan",
                    str(plan_path),
                    "--reason",
                    "selected test runner setup failed",
                ],
                cwd=str(REPOSITORY_ROOT),
                text=True,
                capture_output=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            escalated = json.loads(plan_path.read_text(encoding="utf-8"))
            self.assertEqual(escalated["strategy"], "full")
            self.assertTrue(escalated["fallback"])
            self.assertEqual(
                escalated["fallbackReason"],
                "selected test runner setup failed",
            )
            self.assertEqual(
                escalated["e2eTestTargets"],
                ["ui-runtime", "ui-visual", "ui-performance"],
            )
            output_path = Path(directory) / "outputs.txt"
            export_result = subprocess.run(
                [
                    "python3",
                    str(PLAN_EXPORTER),
                    "--plan",
                    str(plan_path),
                    "--github-output",
                    str(output_path),
                ],
                cwd=str(REPOSITORY_ROOT),
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(
                export_result.returncode,
                0,
                export_result.stdout + export_result.stderr,
            )
            exported = output_path.read_text(encoding="utf-8")
            self.assertIn("strategy=full", exported)
            self.assertIn("ui_runtime=true", exported)
            self.assertIn("ui_visual=true", exported)
            self.assertIn("ui_performance=true", exported)

    def _run_selected(self, plan: dict):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            plan_path = root / "plan.json"
            report_path = root / "execution.json"
            plan_path.write_text(json.dumps(plan), encoding="utf-8")
            result = subprocess.run(
                [
                    "python3",
                    str(SELECTED_RUNNER),
                    "--plan",
                    str(plan_path),
                    "--report",
                    str(report_path),
                    "--dry-run",
                ],
                cwd=str(REPOSITORY_ROOT),
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertTrue(report_path.exists(), result.stdout + result.stderr)
            return result, json.loads(report_path.read_text(encoding="utf-8"))

    def _run_release_preflight_with_evidence(self, evidence_path: Path):
        environment = os.environ.copy()
        environment["SUISUI_AUTOMATED_PREFLIGHT_EVIDENCE_FILE"] = str(evidence_path)
        return subprocess.run(
            [str(RELEASE_PREFLIGHT)],
            cwd=str(REPOSITORY_ROOT),
            env=environment,
            text=True,
            capture_output=True,
            check=False,
        )

    @staticmethod
    def _visual_proof_overrides() -> tuple[str, ...]:
        return (
            "SUISUI_VISUAL_SOURCE_REF",
            "SUISUI_VISUAL_FIXTURE_SEEDER_BIN",
            "SUISUI_AX_AUDIT_RESULT",
            "SUISUI_VISUAL_CURRENT_SOURCE_COMMIT",
            "SUISUI_VISUAL_BASELINE_VIEWPORT",
            "SUISUI_SETTINGS_VISUAL_BASELINE_VIEWPORT",
            "SUISUI_VOICE_COMMAND_VISUAL_BASELINE_VIEWPORT",
            "SUISUI_VISUAL_EVIDENCE_REFERENCE_INSTANT",
            "SUISUI_VISUAL_EVIDENCE_TIME_ZONE",
            "SUISUI_VISUAL_EVIDENCE_LOCALE_IDENTIFIER",
            "SUISUI_VISUAL_EVIDENCE_SCHEDULE_MODE",
            "SUISUI_VISUAL_EVIDENCE_STABLE_BACKDROP",
            "SUISUI_VISUAL_EVIDENCE_SYSTEM_APPEARANCE",
            "SUISUI_UI_EVIDENCE_TARGET_TIMEOUT_SECONDS",
            "SUISUI_UI_EVIDENCE_AX_MAX_NODES",
        )

    def _run_selected_with_fake_toolchain(
        self,
        test_output: str,
        *,
        test_exit_code: int = 0,
    ):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            repository = root / "repo"
            fake_bin = root / "bin"
            fake_bin.mkdir()
            repository.mkdir()
            for relative_path in [
                "script/build_and_run.sh",
                "script/check_security_regressions.sh",
                "scripts/ci.sh",
            ]:
                script = repository / relative_path
                script.parent.mkdir(parents=True, exist_ok=True)
                script.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
                script.chmod(0o755)
            swift = fake_bin / "swift"
            swift.write_text(
                "#!/bin/sh\n"
                "if [ \"${1:-}\" = test ]; then\n"
                "  printf '%s' \"${FAKE_SWIFT_TEST_OUTPUT:-}\"\n"
                "  exit \"${FAKE_SWIFT_TEST_EXIT_CODE:-0}\"\n"
                "fi\n"
                "exit 0\n",
                encoding="utf-8",
            )
            swift.chmod(0o755)
            plan_path = root / "plan.json"
            report_path = root / "execution.json"
            plan_path.write_text(
                json.dumps(
                    {
                        "strategy": "selective",
                        "unitTestTargets": ["WidgetTests"],
                        "integrationTestTargets": [],
                        "smokeTestTargets": [],
                        "e2eTestTargets": [],
                    }
                ),
                encoding="utf-8",
            )
            environment = os.environ.copy()
            environment["PATH"] = str(fake_bin) + os.pathsep + environment["PATH"]
            environment["FAKE_SWIFT_TEST_OUTPUT"] = test_output
            environment["FAKE_SWIFT_TEST_EXIT_CODE"] = str(test_exit_code)
            result = subprocess.run(
                [
                    "python3",
                    str(SELECTED_RUNNER),
                    "--plan",
                    str(plan_path),
                    "--report",
                    str(report_path),
                    "--repo",
                    str(repository),
                ],
                cwd=str(REPOSITORY_ROOT),
                env=environment,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertTrue(report_path.exists(), result.stdout + result.stderr)
            return result, json.loads(report_path.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
