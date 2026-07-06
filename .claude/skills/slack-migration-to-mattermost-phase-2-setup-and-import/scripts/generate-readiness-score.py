#!/usr/bin/env python3
import argparse
import json
from pathlib import Path
import sys


def read_json(path_str: str) -> dict:
    path = Path(path_str)
    if not path.exists():
        raise FileNotFoundError(path)
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError(f"json root must be an object: {path}")
    return payload


def passed(report: dict, success_value: str = "passed") -> bool:
    status = report.get("status", "")
    return status == success_value


def dict_field(payload: dict, key: str, warnings: list[str], label: str) -> dict:
    value = payload.get(key, {})
    if value in ("", None):
        return {}
    if not isinstance(value, dict):
        warnings.append(f"{label} must be a JSON object")
        return {}
    return value


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate a weighted readiness score from Phase 2 validation artifacts.")
    parser.add_argument("--handoff-json", required=True)
    parser.add_argument("--intake-report", required=True)
    parser.add_argument("--config-report", required=True)
    parser.add_argument("--live-report", default="")
    parser.add_argument("--edge-report", default="")
    parser.add_argument("--staging-report", required=True)
    parser.add_argument("--smoke-report", default="")
    parser.add_argument("--reconciliation-report", default="")
    parser.add_argument("--activation-report", default="")
    parser.add_argument("--cutover-report", required=True)
    parser.add_argument("--restore-report", default="")
    parser.add_argument("--output-json", required=True)
    parser.add_argument("--output-md", default="")
    args = parser.parse_args()

    try:
        handoff = read_json(args.handoff_json)
        intake = read_json(args.intake_report)
        config = read_json(args.config_report)
        live = read_json(args.live_report) if args.live_report else {}
        edge = read_json(args.edge_report) if args.edge_report else {}
        staging = read_json(args.staging_report)
        smoke = read_json(args.smoke_report) if args.smoke_report else {}
        reconciliation = read_json(args.reconciliation_report) if args.reconciliation_report else {}
        activation = read_json(args.activation_report) if args.activation_report else {}
        cutover = read_json(args.cutover_report)
        restore = read_json(args.restore_report) if args.restore_report else {}
    except FileNotFoundError as exc:
        print(f"error: missing score input: {exc}", file=sys.stderr)
        return 1
    except (json.JSONDecodeError, ValueError) as exc:
        print(f"error: invalid score input json: {exc}", file=sys.stderr)
        return 1

    warnings: list[str] = []
    final_package = dict_field(handoff, "final_package", warnings, "handoff.final_package")

    checks = {
        "handoff_hash_present": 10 if final_package.get("sha256") else 0,
        "intake_validation": 15 if intake.get("status") == "passed" else 0,
        "config_validation": 15 if config.get("status") == "passed" else 0,
        "live_stack_validation": 10 if (not args.live_report or live.get("status") == "passed") else 0,
        "cloudflare_edge_validation": 5 if (not args.edge_report or edge.get("status") == "passed") else 0,
        "staging_rehearsal": 15 if staging.get("status") == "success" else 0,
        "post_import_smoke": 10 if (not args.smoke_report or smoke.get("status") == "passed") else 0,
        "reconciliation": 10 if (not args.reconciliation_report or reconciliation.get("status") == "matched") else 0,
        "activation_proof": 10 if (not args.activation_report or activation.get("status") == "passed") else 0,
        "cutover_gate": 5 if cutover.get("status") == "ready" else 0,
        "restore_drill": 5 if (not args.restore_report or restore.get("status") == "success") else 0,
    }
    raw_score = sum(checks.values())
    max_score = 110
    score = round((raw_score / max_score) * 100) if max_score else 0

    payload = {
        "workspace": handoff.get("workspace", ""),
        "score": score,
        "raw_score": raw_score,
        "max_score": max_score,
        "checks": checks,
        "warnings": warnings,
    }

    output_json = Path(args.output_json)
    output_json.parent.mkdir(parents=True, exist_ok=True)
    output_json.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {output_json}")

    if args.output_md:
        output_md = Path(args.output_md)
        lines = [
            "# Readiness Score",
            "",
            f"- Workspace: `{payload['workspace']}`",
            f"- Score: **{score}/100**",
            f"- Raw score: `{raw_score}/{max_score}`",
            "",
            "## Checks",
        ]
        lines.extend(f"- {check}: {value}" for check, value in checks.items())
        if warnings:
            lines.extend(["", "## Input Warnings"])
            lines.extend(f"- {warning}" for warning in warnings)
        output_md.parent.mkdir(parents=True, exist_ok=True)
        output_md.write_text("\n".join(lines) + "\n", encoding="utf-8")
        print(f"wrote {output_md}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
