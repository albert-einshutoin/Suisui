#!/usr/bin/env python3
import argparse
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path
from typing import Dict, List, Tuple


TARGET_PATTERN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*(?:/[A-Za-z_][A-Za-z0-9_]*)?$")
SECRET_PATTERNS = [
    re.compile(r"(?i)(authorization\s*:\s*bearer)\s+\S+"),
    re.compile(r"\b(?:sk-|gh[pousr]_|github_pat_|xox[baprs]-)[A-Za-z0-9_-]{8,}"),
    re.compile(
        r"(?i)\b([A-Za-z0-9_.-]*(?:token|secret|password|api[_-]?key))\s*[=:]\s*\S+"
    ),
]
PATH_PATTERN = re.compile(r"/(?:Users|Volumes)/[^\s]+")
XCTEST_SUMMARY_PATTERN = re.compile(
    r"Executed\s+(\d+)\s+tests?,\s+with\s+"
    r"(?:(\d+)\s+tests?\s+skipped\s+and\s+)?(\d+)\s+failures"
)
SWIFT_TESTING_SUMMARY_PATTERN = re.compile(
    r"Test run with\s+(\d+)\s+tests?\s+in\s+\d+\s+suites?"
)


class RunnerSetupError(RuntimeError):
    pass


def _sanitize(text: str) -> str:
    sanitized = PATH_PATTERN.sub("<path>", text)
    for pattern in SECRET_PATTERNS:
        sanitized = pattern.sub(
            lambda match: (match.group(1) + "=<redacted>") if match.lastindex else "<redacted>",
            sanitized,
        )
    return sanitized


def _load_plan(path: Path) -> dict:
    try:
        plan = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise RunnerSetupError("test plan could not be parsed") from error
    if not isinstance(plan, dict) or plan.get("strategy") != "selective":
        raise RunnerSetupError("selected runner requires a selective plan")
    return plan


def _test_commands(plan: dict) -> List[Dict[str, object]]:
    categories: List[Tuple[str, str]] = [
        ("unit", "unitTestTargets"),
        ("integration", "integrationTestTargets"),
        ("smoke", "smokeTestTargets"),
    ]
    commands: List[Dict[str, object]] = []
    seen = set()
    for category, key in categories:
        targets = plan.get(key)
        if not isinstance(targets, list):
            raise RunnerSetupError("test plan target list is invalid")
        for target in targets:
            if not isinstance(target, str) or not TARGET_PATTERN.fullmatch(target):
                raise RunnerSetupError("test plan contains a non-allowlisted target")
            if target in seen:
                continue
            seen.add(target)
            commands.append(
                {
                    "category": category,
                    "target": target,
                    "argv": ["swift", "test", "--filter", target],
                }
            )
    if not commands:
        raise RunnerSetupError("selective plan contains zero executable test targets")
    return commands


def _quality_commands() -> List[List[str]]:
    return [
        ["swift", "package", "dump-package"],
        ["swift", "build"],
        ["swift", "build", "--product", "suisui-cli"],
        ["./script/build_and_run.sh", "--build-only"],
        ["./scripts/ci.sh", "source-contracts"],
        ["./script/check_security_regressions.sh"],
    ]


def _run(repo: Path, argv: List[str]) -> Tuple[int, float, str]:
    started = time.monotonic()
    result = subprocess.run(
        argv,
        cwd=str(repo),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    duration = time.monotonic() - started
    print(_sanitize(result.stdout), end="")
    return result.returncode, duration, result.stdout


def _test_counts(output: str) -> Tuple[int, int, int]:
    xctest_matches = [
        (int(executed), int(skipped or 0), int(failures))
        for executed, skipped, failures in XCTEST_SUMMARY_PATTERN.findall(output)
    ]
    if xctest_matches:
        xctest_executed = max(executed for executed, _, _ in xctest_matches)
        xctest_skipped = max(
            skipped
            for executed, skipped, _ in xctest_matches
            if executed == xctest_executed
        )
        xctest_failures = max(
            failures
            for executed, _, failures in xctest_matches
            if executed == xctest_executed
        )
    else:
        xctest_executed = 0
        xctest_skipped = 0
        xctest_failures = 0
    swift_testing_matches = [
        int(executed) for executed in SWIFT_TESTING_SUMMARY_PATTERN.findall(output)
    ]
    swift_testing_executed = max(swift_testing_matches, default=0)
    return xctest_executed + swift_testing_executed, xctest_skipped, xctest_failures


def _write_report(path: Path, report: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def _base_report(status: str, commands: List[dict], duration: float) -> dict:
    return {
        "schemaVersion": 1,
        "strategy": "selective",
        "status": status,
        "commit": os.environ.get("GITHUB_SHA", ""),
        "branch": os.environ.get("GITHUB_REF_NAME", ""),
        "commands": commands,
        "qualityCommands": _quality_commands(),
        "targetCount": len(commands),
        "executedTestCount": 0,
        "successCount": 0,
        "failureCount": 0,
        "skippedCount": 0,
        "durationSeconds": round(duration, 3),
        "totalComputeSeconds": round(duration, 3),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Execute an allowlisted selective test plan")
    parser.add_argument("--plan", required=True)
    parser.add_argument("--report", required=True)
    parser.add_argument("--repo", default=".")
    parser.add_argument("--dry-run", action="store_true")
    arguments = parser.parse_args()
    report_path = Path(arguments.report).resolve()
    started = time.monotonic()
    commands: List[dict] = []
    try:
        plan = _load_plan(Path(arguments.plan).resolve())
        commands = _test_commands(plan)
    except RunnerSetupError as error:
        report = _base_report("setup-failed", commands, time.monotonic() - started)
        report["failureReason"] = str(error)
        _write_report(report_path, report)
        print("BLOCKER:", error, file=sys.stderr)
        return 2

    if arguments.dry_run:
        report = _base_report("passed", commands, time.monotonic() - started)
        report["successCount"] = len(commands)
        _write_report(report_path, report)
        return 0

    repo = Path(arguments.repo).resolve()
    results = []
    quality_failed = False
    selection_setup_error = None
    for argv in _quality_commands():
        status, duration, _ = _run(repo, argv)
        results.append(
            {
                "category": "quality",
                "argv": argv,
                "status": "passed" if status == 0 else "failed",
                "durationSeconds": round(duration, 3),
            }
        )
        if status != 0:
            quality_failed = True
            break

    if not quality_failed:
        for command in commands:
            status, duration, output = _run(repo, list(command["argv"]))
            executed_count, skipped_count, reported_failure_count = _test_counts(output)
            test_failure_count = (
                max(1, reported_failure_count) if status != 0 else reported_failure_count
            )
            result = dict(command)
            result["status"] = "passed" if status == 0 else "failed"
            result["durationSeconds"] = round(duration, 3)
            result["executedTestCount"] = executed_count
            result["skippedCount"] = skipped_count
            result["failureCount"] = test_failure_count
            result["successCount"] = max(
                0,
                executed_count - skipped_count - reported_failure_count,
            )
            results.append(result)
            if status == 0 and executed_count == 0:
                selection_setup_error = (
                    "selected test filter executed zero tests: " + str(command["target"])
                )
                result["status"] = "setup-failed"
                break

    test_results = [result for result in results if result["category"] != "quality"]
    duration = time.monotonic() - started
    failure_count = sum(result.get("failureCount", 0) for result in test_results)
    executed_test_count = sum(result.get("executedTestCount", 0) for result in test_results)
    skipped_count = sum(result.get("skippedCount", 0) for result in test_results)
    success_count = sum(result.get("successCount", 0) for result in test_results)
    report = _base_report(
        (
            "setup-failed"
            if selection_setup_error
            else "failed" if quality_failed or failure_count else "passed"
        ),
        commands,
        duration,
    )
    report["commands"] = results
    report["executedTestCount"] = executed_test_count
    report["successCount"] = success_count
    report["skippedCount"] = skipped_count
    report["failureCount"] = failure_count + int(quality_failed or selection_setup_error is not None)
    if selection_setup_error:
        report["failureReason"] = selection_setup_error
    _write_report(report_path, report)
    if selection_setup_error:
        print("BLOCKER:", selection_setup_error, file=sys.stderr)
        return 2
    return 1 if quality_failed or failure_count else 0


if __name__ == "__main__":
    raise SystemExit(main())
