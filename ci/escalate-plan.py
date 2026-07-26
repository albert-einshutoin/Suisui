#!/usr/bin/env python3
import argparse
import json
import os
import tempfile
from pathlib import Path


FULL_E2E_TARGETS = ["ui-runtime", "ui-visual", "ui-performance"]


def escalate(plan_path: Path, reason: str) -> None:
    if not reason.strip():
        raise ValueError("fallback reason must not be empty")
    try:
        plan = json.loads(plan_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ValueError("test plan could not be parsed") from error
    if not isinstance(plan, dict) or plan.get("strategy") != "selective":
        raise ValueError("only a selective plan can be escalated")

    # The selected runner can fail after analysis succeeded. Persist the
    # escalation in the canonical plan so downstream UI jobs cannot keep using
    # the narrower, now-untrusted selection.
    plan["strategy"] = "full"
    plan["fallback"] = True
    plan["fallbackReason"] = reason
    plan["e2eTestTargets"] = FULL_E2E_TARGETS

    plan_path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        dir=str(plan_path.parent),
        prefix=plan_path.name + ".",
        suffix=".tmp",
    )
    temporary_path = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as output:
            json.dump(plan, output, indent=2, sort_keys=True)
            output.write("\n")
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary_path, plan_path)
    finally:
        temporary_path.unlink(missing_ok=True)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Escalate a selective CI plan to complete validation"
    )
    parser.add_argument("--plan", required=True)
    parser.add_argument("--reason", required=True)
    arguments = parser.parse_args()
    try:
        escalate(Path(arguments.plan).resolve(), arguments.reason)
    except ValueError as error:
        print("BLOCKER:", error)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
