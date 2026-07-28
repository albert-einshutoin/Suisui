import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from typing import Dict, List, Optional


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
ANALYZER = REPOSITORY_ROOT / "ci" / "impact" / "analyze.py"
CONFIG = REPOSITORY_ROOT / "ci" / "config" / "impact.json"


class ImpactAnalysisTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.repo = Path(self.temporary_directory.name)
        self._write("Package.swift", "// fixture")
        self._write("Sources/SuisuiCore/App/Widget.swift", "struct Widget {}\n")
        self._write(
            "Tests/SuisuiCoreTests/WidgetTests.swift",
            "final class WidgetTests { let subject = Widget() }\n",
        )
        self._write(
            "Tests/SuisuiCoreTests/DevelopmentAutomationRuntimeSmokeTests.swift",
            "final class DevelopmentAutomationRuntimeSmokeTests {}\n",
        )
        self.package_graph = {
            "targets": [
                {"name": "SuisuiCore", "type": "regular", "dependencies": []},
                {
                    "name": "SuisuiExternalConnectors",
                    "type": "regular",
                    "dependencies": [{"byName": ["SuisuiCore", None]}],
                },
                {
                    "name": "SuisuiCoreTests",
                    "type": "test",
                    "dependencies": [
                        {"byName": ["SuisuiCore", None]},
                        {"byName": ["SuisuiExternalConnectors", None]},
                    ],
                },
            ]
        }

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def test_source_change_selects_referencing_tests_and_reverse_dependencies(self) -> None:
        plan = self._analyze([{"status": "M", "path": "Sources/SuisuiCore/App/Widget.swift"}])

        self.assertEqual(plan["strategy"], "selective")
        self.assertEqual(
            plan["affectedModules"],
            ["SuisuiCore", "SuisuiCoreTests", "SuisuiExternalConnectors"],
        )
        self.assertIn("WidgetTests", plan["unitTestTargets"])
        self.assertEqual(
            plan["e2eTestTargets"],
            ["ui-performance", "ui-runtime", "ui-visual"],
        )
        self.assertEqual(
            plan["smokeTestTargets"],
            ["DevelopmentAutomationRuntimeSmokeTests"],
        )

    def test_changed_test_file_is_always_selected(self) -> None:
        plan = self._analyze([{"status": "M", "path": "Tests/SuisuiCoreTests/WidgetTests.swift"}])

        self.assertEqual(plan["strategy"], "selective")
        self.assertIn("WidgetTests", plan["unitTestTargets"])

    def test_documentation_only_change_selects_contracts_and_smoke_without_e2e(self) -> None:
        plan = self._analyze([{"status": "M", "path": "docs/quality/guide.md"}])

        self.assertEqual(plan["strategy"], "selective")
        self.assertEqual(
            plan["unitTestTargets"],
            ["Phase5DocumentationTests", "PublicBrandSurfaceTests"],
        )
        self.assertEqual(plan["integrationTestTargets"], [])
        self.assertEqual(plan["e2eTestTargets"], [])
        self.assertEqual(
            plan["smokeTestTargets"],
            ["DevelopmentAutomationRuntimeSmokeTests"],
        )

    def test_visual_baseline_change_routes_to_ui_visual(self) -> None:
        plan = self._analyze(
            [{"status": "M", "path": "docs/quality/visual-baseline-manifest-ja.json"}]
        )

        self.assertEqual(plan["strategy"], "selective")
        self.assertEqual(plan["e2eTestTargets"], ["ui-visual"])

    def test_visual_evidence_change_routes_to_ui_visual(self) -> None:
        plan = self._analyze(
            [
                {
                    "status": "M",
                    "path": "docs/release/evidence/ui-screenshots-ja/inbox-light.png",
                }
            ]
        )

        self.assertEqual(plan["strategy"], "selective")
        self.assertEqual(plan["e2eTestTargets"], ["ui-visual"])

    def test_visual_contract_rename_preserves_source_path_routing(self) -> None:
        plan = self._analyze(
            [
                {
                    "status": "R100",
                    "oldPath": "docs/quality/visual-baselines/inbox-light.png",
                    "path": "docs/archive/inbox-light.png",
                }
            ]
        )

        self.assertEqual(plan["strategy"], "selective")
        self.assertEqual(plan["e2eTestTargets"], ["ui-visual"])

    def test_non_desktop_swift_change_selects_referencing_test_without_desktop_e2e(self) -> None:
        self._write(
            "Sources/SuisuiWeb/WebPresenter.swift",
            "struct WebPresenter {}\n",
        )
        self._write(
            "Tests/SuisuiCoreTests/WebPresenterTests.swift",
            "final class WebPresenterTests { let subject = WebPresenter() }\n",
        )
        graph = {
            "targets": self.package_graph["targets"]
            + [{"name": "SuisuiWeb", "type": "regular", "dependencies": []}]
        }

        plan = self._analyze(
            [{"status": "M", "path": "Sources/SuisuiWeb/WebPresenter.swift"}],
            package_graph=graph,
        )

        self.assertEqual(plan["strategy"], "selective")
        self.assertEqual(plan["unitTestTargets"], ["WebPresenterTests"])
        self.assertEqual(plan["e2eTestTargets"], [])

    def test_dangerous_shared_change_forces_full(self) -> None:
        self._write("Package.resolved", "{}\n")

        plan = self._analyze([{"status": "M", "path": "Package.resolved"}])

        self.assertEqual(plan["strategy"], "full")
        self.assertTrue(plan["fallback"])
        self.assertIn("dependency", plan["fallbackReason"])

    def test_release_packaging_change_forces_full(self) -> None:
        self._write("packaging/app_metadata.env", "MARKETING_VERSION=0.2.0\n")

        plan = self._analyze([{"status": "M", "path": "packaging/app_metadata.env"}])

        self.assertEqual(plan["strategy"], "full")
        self.assertTrue(plan["fallback"])
        self.assertIn("release", plan["fallbackReason"])

    def test_unmapped_source_change_forces_full_instead_of_zero_targets(self) -> None:
        self._write("Sources/SuisuiCore/App/Unreferenced.swift", "let answer = 42\n")

        plan = self._analyze(
            [{"status": "M", "path": "Sources/SuisuiCore/App/Unreferenced.swift"}]
        )

        self.assertEqual(plan["strategy"], "full")
        self.assertIn("no safely selected tests", plan["fallbackReason"])

    def test_deleted_source_forces_full_without_reading_deleted_path(self) -> None:
        plan = self._analyze(
            [{"status": "D", "path": "Sources/SuisuiCore/App/Removed.swift"}]
        )

        self.assertEqual(plan["strategy"], "full")
        self.assertIn("deleted", plan["fallbackReason"])

    def test_rename_uses_destination_path_and_preserves_provenance(self) -> None:
        self._write("Sources/SuisuiCore/App/RenamedWidget.swift", "struct RenamedWidget {}\n")
        self._write(
            "Tests/SuisuiCoreTests/RenamedWidgetTests.swift",
            "final class RenamedWidgetTests { let subject = RenamedWidget() }\n",
        )

        plan = self._analyze(
            [
                {
                    "status": "R100",
                    "oldPath": "Sources/SuisuiCore/App/OldWidget.swift",
                    "path": "Sources/SuisuiCore/App/RenamedWidget.swift",
                }
            ]
        )

        self.assertEqual(plan["strategy"], "selective")
        self.assertEqual(plan["changedFiles"][0]["oldPath"], "Sources/SuisuiCore/App/OldWidget.swift")
        self.assertIn("RenamedWidgetTests", plan["unitTestTargets"])

    def test_rename_from_dangerous_path_forces_full_using_old_path(self) -> None:
        self._write("Sources/SuisuiCore/App/RenamedSecurity.swift", "struct RenamedSecurity {}\n")
        self._write(
            "Tests/SuisuiCoreTests/RenamedSecurityTests.swift",
            "final class RenamedSecurityTests { let subject = RenamedSecurity() }\n",
        )

        plan = self._analyze(
            [
                {
                    "status": "R100",
                    "oldPath": "Sources/SuisuiCore/Security/SecurityPolicy.swift",
                    "path": "Sources/SuisuiCore/App/RenamedSecurity.swift",
                }
            ]
        )

        self.assertEqual(plan["strategy"], "full")
        self.assertIn("security", plan["fallbackReason"])

    def test_rename_from_core_preserves_old_path_e2e_targets(self) -> None:
        self._write(
            "Sources/SuisuiExternalConnectors/RenamedWidget.swift",
            "struct RenamedWidget {}\n",
        )
        self._write(
            "Tests/SuisuiCoreTests/RenamedWidgetTests.swift",
            "final class RenamedWidgetTests { let subject = RenamedWidget() }\n",
        )

        plan = self._analyze(
            [
                {
                    "status": "R100",
                    "oldPath": "Sources/SuisuiCore/App/Widget.swift",
                    "path": "Sources/SuisuiExternalConnectors/RenamedWidget.swift",
                }
            ]
        )

        self.assertEqual(plan["strategy"], "selective")
        self.assertEqual(
            plan["e2eTestTargets"],
            ["ui-performance", "ui-runtime", "ui-visual"],
        )

    def test_rename_from_connector_preserves_old_path_integration_targets(self) -> None:
        self._write("Sources/SuisuiCore/App/RenamedConnector.swift", "struct RenamedConnector {}\n")
        self._write(
            "Tests/SuisuiCoreTests/RenamedConnectorTests.swift",
            "final class RenamedConnectorTests { let subject = RenamedConnector() }\n",
        )

        plan = self._analyze(
            [
                {
                    "status": "R100",
                    "oldPath": "Sources/SuisuiExternalConnectors/Connector.swift",
                    "path": "Sources/SuisuiCore/App/RenamedConnector.swift",
                }
            ]
        )

        self.assertEqual(plan["strategy"], "selective")
        self.assertEqual(
            plan["integrationTestTargets"],
            [
                "ExternalConnectorExposurePolicyTests",
                "ExternalMCPTests",
                "SaaSConnectorTests",
            ],
        )

    def test_multiple_project_types_are_detected_and_unsupported_mix_forces_full(self) -> None:
        self._write("package.json", '{"scripts":{"test":"vitest"}}\n')
        self._write("src/index.js", "export const value = 1;\n")

        plan = self._analyze([{"status": "M", "path": "src/index.js"}])

        detected_types = {project["type"] for project in plan["detectedProjects"]}
        self.assertEqual(detected_types, {"javascript", "swift"})
        self.assertEqual(plan["strategy"], "full")
        self.assertIn("unsupported adapter", plan["fallbackReason"])

    def test_invalid_dependency_graph_forces_full(self) -> None:
        plan = self._analyze(
            [{"status": "M", "path": "Sources/SuisuiCore/App/Widget.swift"}],
            package_graph={"targets": "invalid"},
        )

        self.assertEqual(plan["strategy"], "full")
        self.assertIn("dependency graph", plan["fallbackReason"])

    def test_one_unmapped_module_in_a_mixed_change_forces_full(self) -> None:
        self._write("Sources/Unknown/Other.swift", "struct Other {}\n")
        self._write(
            "Tests/SuisuiCoreTests/OtherTests.swift",
            "final class OtherTests { let subject = Other() }\n",
        )

        plan = self._analyze(
            [
                {"status": "M", "path": "Sources/SuisuiCore/App/Widget.swift"},
                {"status": "M", "path": "Sources/Unknown/Other.swift"},
            ]
        )

        self.assertEqual(plan["strategy"], "full")
        self.assertIn("module could not be identified", plan["fallbackReason"])

    def test_force_full_is_branch_independent(self) -> None:
        plan = self._analyze(
            [{"status": "M", "path": "docs/guide.md"}],
            force_full_reason="scheduled validation",
        )

        self.assertEqual(plan["strategy"], "full")
        self.assertEqual(plan["fallbackReason"], "scheduled validation")

    def test_force_full_does_not_require_a_nonempty_diff(self) -> None:
        plan = self._analyze([], force_full_reason="manual complete validation")

        self.assertEqual(plan["strategy"], "full")
        self.assertEqual(plan["fallbackReason"], "manual complete validation")

    def test_force_full_cli_does_not_require_git_history(self) -> None:
        graph_path = self.repo / "package-graph.json"
        output_path = self.repo / "plan.json"
        graph_path.write_text(json.dumps(self.package_graph), encoding="utf-8")
        result = subprocess.run(
            [
                "python3",
                str(ANALYZER),
                "--repo",
                str(self.repo),
                "--base-revision",
                "unavailable-base",
                "--head-revision",
                "unavailable-head",
                "--swift-package-graph-json",
                str(graph_path),
                "--config",
                str(CONFIG),
                "--output",
                str(output_path),
                "--force-full-reason",
                "scheduled validation",
            ],
            text=True,
            capture_output=True,
            check=False,
        )

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        plan = json.loads(output_path.read_text(encoding="utf-8"))
        self.assertEqual(plan["fallbackReason"], "scheduled validation")

    def _analyze(
        self,
        changes: List[Dict[str, str]],
        *,
        package_graph: Optional[dict] = None,
        force_full_reason: Optional[str] = None,
    ) -> dict:
        changes_path = self.repo / "changes.json"
        graph_path = self.repo / "package-graph.json"
        output_path = self.repo / "plan.json"
        changes_path.write_text(json.dumps(changes), encoding="utf-8")
        graph_path.write_text(
            json.dumps(package_graph if package_graph is not None else self.package_graph),
            encoding="utf-8",
        )
        command = [
            "python3",
            str(ANALYZER),
            "--repo",
            str(self.repo),
            "--base-revision",
            "base-fixture",
            "--head-revision",
            "head-fixture",
            "--changed-files-json",
            str(changes_path),
            "--swift-package-graph-json",
            str(graph_path),
            "--config",
            str(CONFIG),
            "--output",
            str(output_path),
        ]
        if force_full_reason is not None:
            command.extend(["--force-full-reason", force_full_reason])
        result = subprocess.run(command, text=True, capture_output=True, check=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(output_path.exists(), result.stdout + result.stderr)
        return json.loads(output_path.read_text(encoding="utf-8"))

    def _write(self, relative_path: str, contents: str) -> None:
        destination = self.repo / relative_path
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(contents, encoding="utf-8")


if __name__ == "__main__":
    unittest.main()
