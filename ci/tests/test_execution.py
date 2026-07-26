import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SELECTED_RUNNER = REPOSITORY_ROOT / "ci" / "run-selected.py"
FULL_RUNNER = REPOSITORY_ROOT / "ci" / "run-full.sh"
ORCHESTRATOR = REPOSITORY_ROOT / "ci" / "run-pr-ci.sh"
PLAN_EXPORTER = REPOSITORY_ROOT / "ci" / "export-plan.py"
PLAN_ESCALATOR = REPOSITORY_ROOT / "ci" / "escalate-plan.py"


class ExecutionContractTests(unittest.TestCase):
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
        self.assertIn("./scripts/ci.sh source-contracts", contents)
        self.assertIn("./script/check_security_regressions.sh", contents)
        self.assertIn("int(executed) - int(skipped)", contents)
        self.assertIn("BLOCKER: full execution report could not be written", contents)
        self.assertIn("full test count evidence is missing or invalid", contents)
        self.assertNotIn("impact/analyze", contents)
        self.assertNotIn("ci/config", contents)
        self.assertNotIn("ci/tests", contents)

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
