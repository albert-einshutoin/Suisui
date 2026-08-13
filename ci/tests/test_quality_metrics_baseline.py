import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = REPOSITORY_ROOT / "script" / "quality_metrics_baseline.py"
SPEC = importlib.util.spec_from_file_location("quality_metrics_baseline", MODULE_PATH)
assert SPEC and SPEC.loader
METRICS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(METRICS)


class QualityMetricsBaselineTests(unittest.TestCase):
    def test_parse_workflow_runs_accepts_stdin_fixture(self) -> None:
        fixture = '{"workflow_runs":[{"id":1,"run_attempt":1,"status":"completed","conclusion":"success"}]}'

        self.assertEqual(
            METRICS.parse_workflow_runs(fixture),
            [{"id": 1, "run_attempt": 1, "status": "completed", "conclusion": "success"}],
        )

    def test_parse_workflow_runs_rejects_a_non_list_payload(self) -> None:
        with self.assertRaisesRegex(ValueError, "workflow_runs"):
            METRICS.parse_workflow_runs('{"workflow_runs": {}}')

    def test_parse_workflow_runs_rejects_missing_or_invalid_identity_fields(self) -> None:
        for fixture in (
            '{"workflow_runs":[{"run_attempt":1,"status":"completed","conclusion":"success"}]}',
            '{"workflow_runs":[{"id":1,"run_attempt":"2","status":"completed","conclusion":"success"}]}',
            '{"workflow_runs":[{"id":1,"run_attempt":1,"conclusion":"success"}]}',
        ):
            with self.subTest(fixture=fixture), self.assertRaisesRegex(ValueError, "workflow run"):
                METRICS.parse_workflow_runs(fixture)

    def test_build_baseline_uses_final_attempt_and_known_first_attempts(self) -> None:
        runs = METRICS.parse_workflow_runs(
            json.dumps(
                {
                    "workflow_runs": [
                        {"id": 10, "run_attempt": 1, "status": "completed", "conclusion": "failure"},
                        {"id": 10, "run_attempt": 2, "status": "completed", "conclusion": "success"},
                        {"id": 20, "run_attempt": 1, "status": "completed", "conclusion": "cancelled"},
                        {"id": 30, "run_attempt": 1, "status": "completed", "conclusion": "neutral"},
                        {"id": 40, "run_attempt": 1, "status": "in_progress", "conclusion": None},
                    ]
                }
            )
        )

        baseline = METRICS.build_baseline(runs, {"repository": "owner/repo", "limit": 4})

        self.assertEqual(baseline["schemaVersion"], 1)
        self.assertEqual(baseline["runs"], {"total": 4, "completed": 3, "success": 1, "failure": 0, "cancelled": 1, "neutral": 1})
        self.assertEqual(baseline["metrics"]["firstAttemptSuccessRate"], 0.0)
        self.assertEqual(baseline["metrics"]["firstAttemptSuccessRateStatus"], "available")
        self.assertEqual(baseline["metrics"]["rerunRate"], 0.25)
        self.assertEqual(baseline["metrics"]["overallSuccessRate"], 1 / 3)
        self.assertEqual(baseline["metrics"]["averageAttempts"], 1.25)

    def test_build_baseline_marks_missing_first_attempt_as_unavailable(self) -> None:
        baseline = METRICS.build_baseline(
            [{"id": 50, "run_attempt": 2, "status": "completed", "conclusion": "success"}],
            {"repository": "owner/repo", "limit": 1},
        )

        self.assertIsNone(baseline["metrics"]["firstAttemptSuccessRate"])
        self.assertEqual(baseline["metrics"]["firstAttemptSuccessRateStatus"], "unavailable")
        self.assertEqual(baseline["sampleStatus"], "partial")

    def test_build_baseline_marks_partially_available_first_attempt_rate(self) -> None:
        baseline = METRICS.build_baseline(
            [
                {"id": 60, "run_attempt": 1, "status": "completed", "conclusion": "success"},
                {"id": 70, "run_attempt": 2, "status": "completed", "conclusion": "success"},
            ],
            {"repository": "owner/repo", "limit": 2},
        )

        self.assertEqual(baseline["metrics"]["firstAttemptSuccessRate"], 1.0)
        self.assertEqual(baseline["metrics"]["firstAttemptSuccessRateStatus"], "partial")

    def test_build_baseline_has_an_explicit_empty_status(self) -> None:
        baseline = METRICS.build_baseline([], {"repository": "owner/repo", "limit": 10})

        self.assertEqual(baseline["sampleStatus"], "empty")
        self.assertEqual(baseline["runs"]["total"], 0)
        self.assertIsNone(baseline["metrics"]["overallSuccessRate"])
        self.assertEqual(baseline["metrics"]["overallSuccessRateStatus"], "unavailable")

    def test_build_baseline_marks_unknown_conclusions_as_partial(self) -> None:
        baseline = METRICS.build_baseline(
            [{"id": 1, "run_attempt": 1, "status": "completed", "conclusion": "startup_failure"}],
            {"repository": "owner/repo", "limit": 1},
        )

        self.assertEqual(baseline["sampleStatus"], "partial")
        self.assertIsNone(baseline["metrics"]["overallSuccessRate"])
        self.assertEqual(baseline["metrics"]["overallSuccessRateStatus"], "unavailable")

    def test_limit_logical_runs_keeps_all_attempts_for_the_first_ids(self) -> None:
        runs = [
            {"id": 1, "run_attempt": 2, "status": "completed", "conclusion": "success"},
            {"id": 2, "run_attempt": 1, "status": "completed", "conclusion": "success"},
            {"id": 1, "run_attempt": 1, "status": "completed", "conclusion": "failure"},
        ]

        self.assertEqual(METRICS.limit_logical_runs(runs, 1), [runs[0], runs[2]])

    def test_load_live_runs_encodes_user_supplied_api_parameters(self) -> None:
        with patch.object(METRICS, "_gh_api", return_value={"workflow_runs": []}) as gh_api:
            METRICS.load_live_runs("owner/repo", "ci file.yml", "feature/a b", 10)

        gh_api.assert_called_once_with(
            "/repos/owner/repo/actions/workflows/ci%20file.yml/runs?branch=feature%2Fa+b&per_page=10"
        )

    def test_write_output_rejects_symbolic_links(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            target = root / "target.json"
            target.write_text("protected", encoding="utf-8")
            link = root / "output.json"
            link.symlink_to(target)

            with self.assertRaisesRegex(ValueError, "symbolic link"):
                METRICS.write_output(link, "replacement\n")

            self.assertEqual(target.read_text(encoding="utf-8"), "protected")


if __name__ == "__main__":
    unittest.main()
