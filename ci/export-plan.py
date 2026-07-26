#!/usr/bin/env python3
import argparse
import json
from pathlib import Path
from typing import Dict


E2E_OUTPUTS = {
    "ui-runtime": "ui_runtime",
    "ui-visual": "ui_visual",
    "ui-performance": "ui_performance",
}


def _safe_output_value(value: object) -> str:
    text = str(value).replace("\r", " ").replace("\n", " ")
    return text[:512]


def _defaults() -> Dict[str, str]:
    return {
        "strategy": "full",
        "ui_runtime": "true",
        "ui_visual": "true",
        "ui_performance": "true",
        "fallback_reason": "plan unavailable or invalid",
    }


def export_values(plan_path: Path) -> Dict[str, str]:
    try:
        plan = json.loads(plan_path.read_text(encoding="utf-8"))
        strategy = plan["strategy"]
        targets = plan["e2eTestTargets"]
        fallback_reason = plan.get("fallbackReason")
        if strategy not in {"selective", "full"}:
            raise ValueError("invalid strategy")
        if not isinstance(targets, list) or not all(isinstance(item, str) for item in targets):
            raise ValueError("invalid E2E targets")
    except (OSError, UnicodeDecodeError, json.JSONDecodeError, KeyError, TypeError, ValueError):
        return _defaults()

    values = {
        "strategy": strategy,
        "fallback_reason": _safe_output_value(fallback_reason or ""),
    }
    for target, output_name in E2E_OUTPUTS.items():
        values[output_name] = str(strategy == "full" or target in targets).lower()
    return values


def main() -> int:
    parser = argparse.ArgumentParser(description="Export validated plan fields to GitHub outputs")
    parser.add_argument("--plan", required=True)
    parser.add_argument("--github-output", required=True)
    arguments = parser.parse_args()
    values = export_values(Path(arguments.plan))
    output_path = Path(arguments.github_output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("a", encoding="utf-8") as output:
        for key in [
            "strategy",
            "ui_runtime",
            "ui_visual",
            "ui_performance",
            "fallback_reason",
        ]:
            output.write("{0}={1}\n".format(key, values[key]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
