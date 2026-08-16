#!/usr/bin/env python3
"""Emit a reproducible, bounded GitHub Actions workflow-run baseline."""

import argparse
import json
import subprocess
import sys
import tempfile
from collections.abc import Iterable
from pathlib import Path
from typing import Any, Optional
from urllib.parse import quote, urlencode


SCHEMA_VERSION = 1
FAILURE_CONCLUSIONS = {"failure", "action_required", "startup_failure", "timed_out"}
CANCELLED_CONCLUSIONS = {"cancelled", "stale"}
NEUTRAL_CONCLUSIONS = {"neutral", "skipped"}
RECOGNIZED_CONCLUSIONS = {"success"} | FAILURE_CONCLUSIONS | CANCELLED_CONCLUSIONS | NEUTRAL_CONCLUSIONS


def parse_workflow_runs(payload: str) -> list[dict[str, Any]]:
    """Parse a saved `gh api` response without performing I/O."""
    try:
        decoded = json.loads(payload)
    except json.JSONDecodeError as error:
        raise ValueError("invalid JSON payload") from error
    runs = decoded.get("workflow_runs") if isinstance(decoded, dict) else None
    if not isinstance(runs, list) or not all(isinstance(run, dict) for run in runs):
        raise ValueError("workflow_runs must be a list of objects")
    for run in runs:
        if type(run.get("id")) is not int or run["id"] <= 0:
            raise ValueError("workflow run id must be a positive integer")
        if type(run.get("run_attempt")) is not int or run["run_attempt"] <= 0:
            raise ValueError("workflow run run_attempt must be a positive integer")
        if not isinstance(run.get("status"), str):
            raise ValueError("workflow run status must be a string")
        if run.get("conclusion") is not None and not isinstance(run["conclusion"], str):
            raise ValueError("workflow run conclusion must be a string or null")
    return runs


def limit_logical_runs(runs: list[dict[str, Any]], limit: int) -> list[dict[str, Any]]:
    """Keep every attempt for the first `limit` logical run ids."""
    selected: list[int] = []
    for run in runs:
        run_id = run["id"]
        if run_id not in selected:
            if len(selected) == limit:
                continue
            selected.append(run_id)
    selected_ids = set(selected)
    return [run for run in runs if run["id"] in selected_ids]


def build_baseline(runs: Iterable[dict[str, Any]], sample: dict[str, Any]) -> dict[str, Any]:
    """Aggregate supplied workflow attempt records deterministically."""
    grouped: dict[str, list[dict[str, Any]]] = {}
    for run in runs:
        run_id = run.get("id")
        if run_id is None:
            continue
        grouped.setdefault(str(run_id), []).append(run)

    final_runs: list[dict[str, Any]] = []
    first_runs: list[Optional[dict[str, Any]]] = []
    for attempts in grouped.values():
        ordered = sorted(attempts, key=lambda run: _attempt_number(run))
        final_runs.append(ordered[-1])
        first_runs.append(next((run for run in ordered if _attempt_number(run) == 1), None))

    completed = [run for run in final_runs if run.get("status") == "completed"]
    conclusions = [run.get("conclusion") for run in completed]
    known_conclusions = [conclusion for conclusion in conclusions if conclusion in RECOGNIZED_CONCLUSIONS]
    success = sum(conclusion == "success" for conclusion in known_conclusions)
    failure = sum(conclusion in FAILURE_CONCLUSIONS for conclusion in known_conclusions)
    cancelled = sum(conclusion in CANCELLED_CONCLUSIONS for conclusion in known_conclusions)
    neutral = sum(conclusion in NEUTRAL_CONCLUSIONS for conclusion in known_conclusions)
    eligible_first_runs = first_runs
    first_completed = [
        run for run in eligible_first_runs
        if run is not None
        and run.get("status") == "completed"
        and run.get("conclusion") in RECOGNIZED_CONCLUSIONS
    ]
    reruns = sum(_attempt_number(run) > 1 for run in final_runs)

    first_success_rate = _rate(
        sum(run.get("conclusion") == "success" for run in first_completed), len(first_completed)
    )
    overall_success_rate = _rate(success, len(known_conclusions))
    missing_first = len(first_completed) != len(eligible_first_runs)
    missing_final = len(known_conclusions) != len(final_runs)
    first_status = "unavailable" if not first_completed else "partial" if missing_first else "available"
    overall_status = "unavailable" if not known_conclusions else "partial" if missing_final else "available"
    sample_status = "empty" if not final_runs else "partial" if missing_first or missing_final else "complete"

    return {
        "schemaVersion": SCHEMA_VERSION,
        "sampleStatus": sample_status,
        "sample": sample,
        "runs": {
            "total": len(final_runs),
            "completed": len(completed),
            "success": success,
            "failure": failure,
            "cancelled": cancelled,
            "neutral": neutral,
        },
        "metrics": {
            "firstAttemptSuccessRate": first_success_rate,
            "firstAttemptSuccessRateStatus": first_status,
            "rerunRate": _rate(reruns, len(final_runs)),
            "rerunRateStatus": "available" if final_runs else "unavailable",
            "overallSuccessRate": overall_success_rate,
            "overallSuccessRateStatus": overall_status,
            "averageAttempts": _rate(sum(_attempt_number(run) for run in final_runs), len(final_runs)),
            "averageAttemptsStatus": "available" if final_runs else "unavailable",
        },
    }


def _attempt_number(run: dict[str, Any]) -> int:
    attempt = run.get("run_attempt", 1)
    return attempt if isinstance(attempt, int) and attempt > 0 else 1


def _rate(numerator: int, denominator: int) -> Optional[float]:
    return numerator / denominator if denominator else None


def _gh_api(path: str) -> Optional[dict[str, Any]]:
    try:
        result = subprocess.run(
            ["gh", "api", "--method", "GET", path], text=True, capture_output=True, check=False
        )
    except OSError:
        return None
    if result.returncode:
        return None
    try:
        decoded = json.loads(result.stdout)
    except json.JSONDecodeError:
        return None
    return decoded if isinstance(decoded, dict) else None


def load_live_runs(repository: str, workflow: str, branch: str, limit: int) -> list[dict[str, Any]]:
    """Fetch at most `limit` current runs and their needed first attempts."""
    repository_path = "/".join(quote(part, safe="") for part in repository.split("/"))
    workflow_path = quote(workflow, safe="")
    query = (
        f"/repos/{repository_path}/actions/workflows/{workflow_path}/runs?"
        f"{urlencode({'branch': branch, 'per_page': limit})}"
    )
    payload = _gh_api(query)
    if payload is None:
        raise RuntimeError("GitHub Actions workflow runs could not be read")
    latest_runs = parse_workflow_runs(json.dumps(payload))[:limit]
    first_attempts: list[dict[str, Any]] = []
    for run in latest_runs:
        if _attempt_number(run) <= 1 or run.get("id") is None:
            continue
        first = _gh_api(f"/repos/{repository_path}/actions/runs/{run['id']}/attempts/1")
        if first is None:
            # The final run remains useful; omitting attempt one makes partial data explicit.
            continue
        try:
            validated = parse_workflow_runs(json.dumps({"workflow_runs": [first]}))[0]
        except ValueError:
            continue
        if validated["id"] != run["id"] or validated["run_attempt"] != 1:
            continue
        first_attempts.append(validated)
    return latest_runs + first_attempts


def write_output(path: Path, content: str) -> None:
    """Replace a regular output file atomically without following a symlink."""
    # `mkdir` follows existing parent symlinks, so reject every path component first.
    if any(component.is_symlink() for component in (path, *path.parents)):
        raise ValueError("output path must not be a symbolic link")
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, name = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.")
    temporary_path = Path(name)
    try:
        with open(descriptor, mode="w", encoding="utf-8", closefd=True) as temporary:
            temporary.write(content)
        temporary_path.replace(path)
    finally:
        temporary_path.unlink(missing_ok=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", help="GitHub repository as OWNER/REPO")
    parser.add_argument("--workflow", default="ci.yml", help="Workflow file name (default: ci.yml)")
    parser.add_argument("--branch", default="main", help="Branch to sample (default: main)")
    parser.add_argument("--limit", type=int, default=100, help="Maximum logical runs (1-100, default: 100)")
    parser.add_argument("--stdin", action="store_true", help="Read a saved workflow-runs JSON payload from standard input")
    parser.add_argument("--output", type=Path, help="Write JSON to this file instead of standard output")
    args = parser.parse_args()
    if not 1 <= args.limit <= 100:
        parser.error("--limit must be between 1 and 100")
    if not args.stdin and not args.repository:
        parser.error("--repository is required unless --stdin is used")

    try:
        if args.stdin:
            runs = limit_logical_runs(parse_workflow_runs(sys.stdin.read()), args.limit)
            source = "stdin"
        else:
            runs = load_live_runs(args.repository, args.workflow, args.branch, args.limit)
            source = "github-actions"
    except (RuntimeError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 2

    baseline = build_baseline(runs, {
        "source": source,
        "repository": args.repository,
        "workflow": args.workflow,
        "branch": args.branch,
        "limit": args.limit,
    })
    encoded = json.dumps(baseline, indent=2, sort_keys=True) + "\n"
    if args.output:
        try:
            write_output(args.output, encoded)
        except (OSError, ValueError) as error:
            print(f"error: {error}", file=sys.stderr)
            return 2
    else:
        print(encoded, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
