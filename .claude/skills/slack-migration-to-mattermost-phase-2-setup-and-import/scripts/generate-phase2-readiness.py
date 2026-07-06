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


def dict_field(payload: dict, key: str, warnings: list[str], label: str) -> dict:
    value = payload.get(key, {})
    if value in ("", None):
        return {}
    if not isinstance(value, dict):
        warnings.append(f"{label} must be a JSON object")
        return {}
    return value


def string_list_field(payload: dict, key: str, warnings: list[str], label: str) -> list[str]:
    value = payload.get(key, [])
    if value in ("", None):
        return []
    if isinstance(value, list):
        return [str(item) for item in value]
    warnings.append(f"{label} must be a JSON array")
    return []


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate a Phase 2 readiness summary from validation artifacts.")
    parser.add_argument("--output-md", required=True)
    parser.add_argument("--handoff-json", required=True)
    parser.add_argument("--intake-report", default="")
    parser.add_argument("--config-report", default="")
    parser.add_argument("--live-report", default="")
    parser.add_argument("--edge-report", default="")
    parser.add_argument("--score-json", default="")
    parser.add_argument("--staging-report", default="")
    parser.add_argument("--smoke-report", default="")
    parser.add_argument("--reconciliation-report", default="")
    parser.add_argument("--activation-report", default="")
    parser.add_argument("--cutover-report", default="")
    args = parser.parse_args()

    try:
        handoff = read_json(args.handoff_json)
        intake = read_json(args.intake_report) if args.intake_report else {}
        config = read_json(args.config_report) if args.config_report else {}
        live = read_json(args.live_report) if args.live_report else {}
        edge = read_json(args.edge_report) if args.edge_report else {}
        score = read_json(args.score_json) if args.score_json else {}
        staging = read_json(args.staging_report) if args.staging_report else {}
        smoke = read_json(args.smoke_report) if args.smoke_report else {}
        reconciliation = read_json(args.reconciliation_report) if args.reconciliation_report else {}
        activation = read_json(args.activation_report) if args.activation_report else {}
        cutover = read_json(args.cutover_report) if args.cutover_report else {}
    except FileNotFoundError as exc:
        print(f"error: missing readiness input: {exc}", file=sys.stderr)
        return 1
    except (json.JSONDecodeError, ValueError) as exc:
        print(f"error: invalid readiness input json: {exc}", file=sys.stderr)
        return 1

    warnings: list[str] = []
    final_package = dict_field(handoff, "final_package", warnings, "handoff.final_package")
    counts = dict_field(handoff, "counts", warnings, "handoff.counts")

    known_gaps = string_list_field(handoff, "known_gaps", warnings, "handoff.known_gaps")
    blockers = []
    blockers.extend(string_list_field(intake, "errors", warnings, "intake.errors"))
    blockers.extend(string_list_field(config, "errors", warnings, "config.errors"))
    blockers.extend(string_list_field(live, "errors", warnings, "live.errors"))
    blockers.extend(string_list_field(edge, "errors", warnings, "edge.errors"))
    blockers.extend(string_list_field(staging, "errors", warnings, "staging.errors"))
    blockers.extend(string_list_field(smoke, "errors", warnings, "smoke.errors"))
    blockers.extend(string_list_field(reconciliation, "errors", warnings, "reconciliation.errors"))
    blockers.extend(string_list_field(activation, "errors", warnings, "activation.errors"))
    blockers.extend(string_list_field(cutover, "errors", warnings, "cutover.errors"))

    lines = [
        "# Phase 2 Readiness Summary",
        "",
        f"- Workspace: `{handoff.get('workspace', 'unknown')}`",
        f"- Final package: `{final_package.get('path', '')}`",
        f"- Handoff counts: users={counts.get('users', 0)}, channels={counts.get('channels', 0)}, posts={counts.get('posts', 0)}",
        f"- Intake status: `{intake.get('status', 'not-run')}`",
        f"- Config status: `{config.get('status', 'not-run')}`",
        f"- Live stack status: `{live.get('status', 'not-run')}`",
        f"- Cloudflare edge status: `{edge.get('status', 'not-run')}`",
        f"- Staging status: `{staging.get('status', 'not-run')}`",
        f"- Post-import smoke: `{smoke.get('status', 'not-run')}`",
        f"- Reconciliation: `{reconciliation.get('status', 'not-run')}`",
        f"- Activation proof: `{activation.get('status', 'not-run')}`",
        f"- Cutover gate: `{cutover.get('status', 'not-run')}`",
        f"- Readiness score: `{score.get('score', 'not-scored')}`",
    ]
    if warnings:
        lines.extend(["", "## Input Warnings"])
        lines.extend(f"- {warning}" for warning in warnings)

    lines.extend(["", "## Known Gaps"])
    if known_gaps:
        lines.extend(f"- {gap}" for gap in known_gaps)
    else:
        lines.append("- None recorded.")

    lines.extend(["", "## Blocking Issues"])
    if blockers:
        lines.extend(f"- {blocker}" for blocker in blockers)
    else:
        lines.append("- None.")

    output = Path(args.output_md)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"wrote {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
