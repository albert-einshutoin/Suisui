#!/usr/bin/env python3
import argparse
import json
from pathlib import Path


def _load(path: Path) -> dict:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError("execution report must be an object")
    return data


def main() -> int:
    parser = argparse.ArgumentParser(description="Compare selective and full CI evidence")
    parser.add_argument("--selective", required=True)
    parser.add_argument("--full", required=True)
    parser.add_argument("--output", required=True)
    arguments = parser.parse_args()
    try:
        selective = _load(Path(arguments.selective))
        full = _load(Path(arguments.full))
        selective_duration = float(selective["durationSeconds"])
        full_duration = float(full["durationSeconds"])
        if selective_duration < 0 or full_duration <= 0:
            raise ValueError("execution duration is invalid")
        reduction = max(0.0, (full_duration - selective_duration) / full_duration * 100)
        report = {
            "schemaVersion": 1,
            "selectiveDurationSeconds": selective_duration,
            "fullDurationSeconds": full_duration,
            "durationReductionPercent": round(reduction, 2),
            "selectedTestCount": int(selective["executedTestCount"]),
            "selectedTargetCount": int(selective["targetCount"]),
            "fullTestCount": int(full["executedTestCount"]),
            "selectiveFailureCount": int(selective["failureCount"]),
            "fullFailureCount": int(full["failureCount"]),
            "fullOnlyFailure": (
                selective.get("status") == "passed" and full.get("status") != "passed"
            ),
            "selectiveStatus": selective.get("status"),
            "fullStatus": full.get("status"),
        }
    except (OSError, UnicodeDecodeError, json.JSONDecodeError, KeyError, TypeError, ValueError) as error:
        print("BLOCKER: comparison evidence is invalid: {0}".format(error))
        return 2
    output_path = Path(arguments.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("Selective duration: {0:.3f}s".format(selective_duration))
    print("Full duration: {0:.3f}s".format(full_duration))
    print("Duration reduction: {0:.2f}%".format(reduction))
    print("Full-only failure:", str(report["fullOnlyFailure"]).lower())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
