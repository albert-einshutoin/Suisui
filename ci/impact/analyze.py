#!/usr/bin/env python3
import argparse
import fnmatch
import json
import subprocess
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple


SCRIPT_DIRECTORY = Path(__file__).resolve().parent
REPOSITORY_ROOT = SCRIPT_DIRECTORY.parents[1]
if str(REPOSITORY_ROOT) not in sys.path:
    sys.path.insert(0, str(REPOSITORY_ROOT))

from ci.impact.adapters.swift import (  # noqa: E402
    SwiftAnalysisError,
    parse_target_graph,
    reverse_dependency_closure,
    select_tests,
    target_for_path,
)
from ci.impact.git_changes import GitChangeError, collect_changes  # noqa: E402
from ci.impact.projects import detect_projects, unsupported_project_types  # noqa: E402


class ConfigurationError(RuntimeError):
    pass


def load_json(path: Path) -> object:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ConfigurationError("configuration or fixture JSON could not be parsed") from error


def load_config(path: Path) -> dict:
    config = load_json(path)
    if not isinstance(config, dict) or config.get("schemaVersion") != 1:
        raise ConfigurationError("impact configuration schema is unsupported")
    required_lists = [
        "supportedAdapters",
        "smokeTestTargets",
        "documentationTestTargets",
        "integrationRules",
        "e2eRules",
        "forceFullRules",
    ]
    if any(not isinstance(config.get(key), list) for key in required_lists):
        raise ConfigurationError("impact configuration is incomplete")
    return config


def first_force_full_reason(changes: List[dict], config: dict) -> Optional[str]:
    for change in changes:
        paths = [change.get("path", "")]
        old_path = change.get("oldPath")
        if isinstance(old_path, str):
            # A rename must not make a dangerous source path disappear from the
            # policy evaluation merely because its destination is innocuous.
            paths.append(old_path)
        for rule in config["forceFullRules"]:
            if not isinstance(rule, dict):
                return "impact configuration contains an invalid full-test rule"
            pattern = rule.get("pattern")
            reason = rule.get("reason")
            if not isinstance(pattern, str) or not isinstance(reason, str):
                return "impact configuration contains an invalid full-test rule"
            if any(fnmatch.fnmatchcase(path, pattern) for path in paths):
                return reason
    return None


def matching_targets(changes: List[dict], rules: List[dict]) -> List[str]:
    targets = set()
    for change in changes:
        paths = [change["path"]]
        old_path = change.get("oldPath")
        if isinstance(old_path, str):
            # A move across module boundaries can retain impact from both the
            # source and destination, so integration/E2E rules inspect both.
            paths.append(old_path)
        for rule in rules:
            pattern = rule.get("pattern")
            rule_targets = rule.get("targets")
            if not isinstance(pattern, str) or not isinstance(rule_targets, list):
                raise ConfigurationError("impact target rule is invalid")
            if any(fnmatch.fnmatchcase(path, pattern) for path in paths):
                if not all(isinstance(target, str) and target for target in rule_targets):
                    raise ConfigurationError("impact target rule contains an invalid target")
                targets.update(rule_targets)
    return sorted(targets)


def _full_plan(
    *,
    base_revision: str,
    head_revision: str,
    changes: List[dict],
    projects: List[dict],
    reason: str,
    smoke_targets: List[str],
) -> dict:
    return {
        "schemaVersion": 1,
        "strategy": "full",
        "baseRevision": base_revision,
        "headRevision": head_revision,
        "changedFiles": changes,
        "detectedProjects": projects,
        "usedAdapters": sorted(
            {project["adapter"] for project in projects if project["adapter"] != "unsupported"}
        ),
        "affectedProjects": sorted({project["path"] for project in projects}),
        "affectedModules": [],
        "unitTestTargets": [],
        "integrationTestTargets": [],
        "e2eTestTargets": ["ui-runtime", "ui-visual", "ui-performance"],
        "smokeTestTargets": smoke_targets,
        "fallback": True,
        "fallbackReason": reason,
    }


def _validate_changes(changes: object) -> Tuple[Optional[List[dict]], Optional[str]]:
    if not isinstance(changes, list):
        return None, "changed file list is invalid"
    normalized: List[dict] = []
    for change in changes:
        if not isinstance(change, dict):
            return None, "changed file record is invalid"
        status = change.get("status")
        path = change.get("path")
        if not isinstance(status, str) or not status or not isinstance(path, str) or not path:
            return None, "changed file record is incomplete"
        if status[0] not in "ACDMRTUXB":
            return None, "changed file status is unsupported"
        item = {"status": status, "path": path}
        if status[0] in "RC":
            old_path = change.get("oldPath")
            if not isinstance(old_path, str) or not old_path:
                return None, "rename or copy record is incomplete"
            item["oldPath"] = old_path
        normalized.append(item)
    if not normalized:
        return None, "changed file list is empty"
    return normalized, None


def analyze(
    *,
    repo: Path,
    config: dict,
    changes: object,
    base_revision: str,
    head_revision: str,
    package_graph: object,
    force_full_reason: Optional[str],
) -> dict:
    projects = detect_projects(repo)
    smoke_targets = list(config["smokeTestTargets"])
    normalized_changes, change_error = _validate_changes(changes)
    if force_full_reason:
        return _full_plan(
            base_revision=base_revision,
            head_revision=head_revision,
            changes=normalized_changes or [],
            projects=projects,
            reason=force_full_reason,
            smoke_targets=smoke_targets,
        )
    if normalized_changes is None:
        return _full_plan(
            base_revision=base_revision,
            head_revision=head_revision,
            changes=[],
            projects=projects,
            reason=change_error or "changed file discovery failed",
            smoke_targets=smoke_targets,
        )
    dangerous_reason = first_force_full_reason(normalized_changes, config)
    if dangerous_reason:
        return _full_plan(
            base_revision=base_revision,
            head_revision=head_revision,
            changes=normalized_changes,
            projects=projects,
            reason=dangerous_reason,
            smoke_targets=smoke_targets,
        )
    unsupported_types = unsupported_project_types(projects)
    if unsupported_types:
        return _full_plan(
            base_revision=base_revision,
            head_revision=head_revision,
            changes=normalized_changes,
            projects=projects,
            reason="unsupported adapter detected: " + ", ".join(sorted(unsupported_types)),
            smoke_targets=smoke_targets,
        )
    if any(
        change["status"].startswith("D")
        and (
            change["path"].startswith("Sources/")
            or change["path"].startswith("Tests/")
        )
        for change in normalized_changes
    ):
        return _full_plan(
            base_revision=base_revision,
            head_revision=head_revision,
            changes=normalized_changes,
            projects=projects,
            reason="deleted source or test file has ambiguous impact",
            smoke_targets=smoke_targets,
        )

    changed_paths = [change["path"] for change in normalized_changes]
    swift_paths = [
        path
        for path in changed_paths
        if (path.startswith("Sources/") or path.startswith("Tests/"))
        and path.endswith(".swift")
    ]
    documentation_only = all(
        path.startswith("docs/")
        or path.startswith("tasks/")
        or path in {"README.md", "README.ja.md"}
        for path in changed_paths
    )
    if not swift_paths and not documentation_only:
        return _full_plan(
            base_revision=base_revision,
            head_revision=head_revision,
            changes=normalized_changes,
            projects=projects,
            reason="unclassified important file changed",
            smoke_targets=smoke_targets,
        )

    unit_targets = set(config["documentationTestTargets"] if documentation_only else [])
    affected_modules = set()
    impacted_source_files: List[str] = []
    impacted_symbols: List[str] = []
    if swift_paths:
        try:
            if not isinstance(package_graph, dict):
                raise SwiftAnalysisError("Swift dependency graph is invalid")
            target_graph = parse_target_graph(package_graph)
            mapped_targets = [target_for_path(path, target_graph) for path in swift_paths]
            if any(target is None for target in mapped_targets):
                raise SwiftAnalysisError("changed Swift module could not be identified")
            changed_targets = {target for target in mapped_targets if target is not None}
            affected_modules = reverse_dependency_closure(changed_targets, target_graph)
            selection = select_tests(repo, swift_paths)
            unit_targets.update(selection["unitTestTargets"])
            impacted_source_files = selection["impactedSourceFiles"]
            impacted_symbols = selection["impactedSymbols"]
        except SwiftAnalysisError as error:
            return _full_plan(
                base_revision=base_revision,
                head_revision=head_revision,
                changes=normalized_changes,
                projects=projects,
                reason="dependency graph or Swift adapter failed: " + str(error),
                smoke_targets=smoke_targets,
            )

    integration_targets = matching_targets(normalized_changes, config["integrationRules"])
    e2e_targets = matching_targets(normalized_changes, config["e2eRules"])
    if not unit_targets:
        return _full_plan(
            base_revision=base_revision,
            head_revision=head_revision,
            changes=normalized_changes,
            projects=projects,
            reason="no safely selected tests for a non-empty change set",
            smoke_targets=smoke_targets,
        )
    return {
        "schemaVersion": 1,
        "strategy": "selective",
        "baseRevision": base_revision,
        "headRevision": head_revision,
        "changedFiles": normalized_changes,
        "detectedProjects": projects,
        "usedAdapters": ["swift"] if swift_paths else [],
        "affectedProjects": sorted({project["path"] for project in projects}),
        "affectedModules": sorted(affected_modules),
        "impactedSourceFiles": impacted_source_files,
        "impactedSymbols": impacted_symbols,
        "unitTestTargets": sorted(unit_targets),
        "integrationTestTargets": integration_targets,
        "e2eTestTargets": e2e_targets,
        "smokeTestTargets": smoke_targets,
        "fallback": False,
        "fallbackReason": None,
    }


def _swift_package_graph(repo: Path) -> object:
    result = subprocess.run(
        ["swift", "package", "dump-package"],
        cwd=str(repo),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode != 0:
        raise SwiftAnalysisError("swift package dump-package failed")
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError as error:
        raise SwiftAnalysisError("swift package dump-package returned invalid JSON") from error


def _write_plan(path: Path, plan: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(plan, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def _log_plan(plan: dict) -> None:
    print("Test strategy:", plan["strategy"])
    print("Base revision:", plan["baseRevision"])
    print("Head revision:", plan["headRevision"])
    print("Detected projects:", len(plan["detectedProjects"]))
    print("Adapters:", ", ".join(plan["usedAdapters"]) or "none")
    print("Changed files:", len(plan["changedFiles"]))
    for change in plan["changedFiles"]:
        previous = " <- " + change["oldPath"] if "oldPath" in change else ""
        print("  {0} {1}{2}".format(change["status"], change["path"], previous))
    print("Affected modules:", ", ".join(plan["affectedModules"]) or "none")
    print("Unit test targets:", len(plan["unitTestTargets"]))
    print("Integration test targets:", len(plan["integrationTestTargets"]))
    print("E2E test targets:", len(plan["e2eTestTargets"]))
    print("Smoke test targets:", len(plan["smokeTestTargets"]))
    print("Fallback:", str(plan["fallback"]).lower())
    if plan["fallbackReason"]:
        print("Fallback reason:", plan["fallbackReason"])


def main() -> int:
    parser = argparse.ArgumentParser(description="Create a fail-closed CI test plan")
    parser.add_argument("--repo", default=".")
    parser.add_argument("--base-revision", required=True)
    parser.add_argument("--head-revision", required=True)
    parser.add_argument("--changed-files-json")
    parser.add_argument("--swift-package-graph-json")
    parser.add_argument("--config", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--force-full-reason")
    arguments = parser.parse_args()

    repo = Path(arguments.repo).resolve()
    output = Path(arguments.output).resolve()
    try:
        config = load_config(Path(arguments.config).resolve())
    except ConfigurationError as error:
        print("BLOCKER:", error, file=sys.stderr)
        return 2

    base_revision = arguments.base_revision
    try:
        if arguments.changed_files_json:
            changes = load_json(Path(arguments.changed_files_json).resolve())
        elif arguments.force_full_reason:
            # Branch, schedule, release, and manual lanes are full by policy;
            # requiring a diff here would make an unavailable base obscure that
            # explicit reason without improving the validation decision.
            changes = []
        else:
            discovered = collect_changes(repo, arguments.base_revision, arguments.head_revision)
            base_revision = str(discovered["baseRevision"])
            changes = discovered["changes"]
        package_graph = (
            load_json(Path(arguments.swift_package_graph_json).resolve())
            if arguments.swift_package_graph_json
            else _swift_package_graph(repo)
        )
        plan = analyze(
            repo=repo,
            config=config,
            changes=changes,
            base_revision=base_revision,
            head_revision=arguments.head_revision,
            package_graph=package_graph,
            force_full_reason=arguments.force_full_reason,
        )
    except (ConfigurationError, GitChangeError, SwiftAnalysisError) as error:
        projects = detect_projects(repo)
        plan = _full_plan(
            base_revision=base_revision,
            head_revision=arguments.head_revision,
            changes=[],
            projects=projects,
            reason=str(error),
            smoke_targets=list(config["smokeTestTargets"]),
        )
    _write_plan(output, plan)
    _log_plan(plan)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
