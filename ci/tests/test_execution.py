import json
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SELECTED_RUNNER = REPOSITORY_ROOT / "ci" / "run-selected.py"
FULL_RUNNER = REPOSITORY_ROOT / "ci" / "run-full.sh"
ORCHESTRATOR = REPOSITORY_ROOT / "ci" / "run-pr-ci.sh"
PLAN_EXPORTER = REPOSITORY_ROOT / "ci" / "export-plan.py"
COMPARISON = REPOSITORY_ROOT / "ci" / "compare-runs.py"


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

    def test_full_runner_is_independent_from_planner_and_runs_canonical_gates(self) -> None:
        self.assertTrue(FULL_RUNNER.exists(), "independent full runner must exist")
        contents = FULL_RUNNER.read_text(encoding="utf-8")

        self.assertIn("./scripts/ci.sh swiftpm", contents)
        self.assertIn("./scripts/ci.sh source-contracts", contents)
        self.assertIn("./script/check_security_regressions.sh", contents)
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

    def test_plan_exporter_maps_selective_e2e_and_shadow_outputs(self) -> None:
        plan = {
            "strategy": "selective",
            "shadowFull": True,
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
            self.assertIn("shadow_full=true", exported)
            self.assertIn("ui_runtime=true", exported)
            self.assertIn("ui_visual=false", exported)

    def test_comparison_report_calculates_savings_and_full_only_failure(self) -> None:
        selective = {
            "status": "passed",
            "durationSeconds": 12,
            "targetCount": 4,
            "failureCount": 0,
        }
        full = {
            "status": "failed",
            "durationSeconds": 60,
            "executedTestCount": 100,
            "failureCount": 1,
        }
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            selective_path = root / "selective.json"
            full_path = root / "full.json"
            output_path = root / "comparison.json"
            selective_path.write_text(json.dumps(selective), encoding="utf-8")
            full_path.write_text(json.dumps(full), encoding="utf-8")
            result = subprocess.run(
                [
                    "python3",
                    str(COMPARISON),
                    "--selective",
                    str(selective_path),
                    "--full",
                    str(full_path),
                    "--output",
                    str(output_path),
                ],
                cwd=str(REPOSITORY_ROOT),
                text=True,
                capture_output=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            comparison = json.loads(output_path.read_text(encoding="utf-8"))
            self.assertEqual(comparison["durationReductionPercent"], 80.0)
            self.assertTrue(comparison["fullOnlyFailure"])
            self.assertEqual(comparison["selectedTestCount"], 4)
            self.assertEqual(comparison["fullTestCount"], 100)

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


if __name__ == "__main__":
    unittest.main()
