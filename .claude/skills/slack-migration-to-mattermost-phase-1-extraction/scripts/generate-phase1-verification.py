#!/usr/bin/env python3
import argparse
import json
from pathlib import Path
import sys


def read_json(path_str: str) -> dict:
    path = Path(path_str)
    if not path.exists():
        raise FileNotFoundError(path)
    return json.loads(path.read_text(encoding="utf-8"))


def status_for_report(report: dict, default: str = "not-run") -> str:
    if not report:
        return default
    if report.get("status"):
        return str(report["status"])
    if report.get("errors"):
        return "failed"
    return "passed"


def extend_lines(lines: list[str], title: str, items: list[str]) -> None:
    lines.append(title)
    if items:
        lines.extend(f"- {item}" for item in items)
    else:
        lines.append("- None.")
    lines.append("")


COUNT_KEYS = {
    "users": ("users", "user"),
    "channels": ("channels", "channel"),
    "posts": ("posts", "post"),
    "direct_channels": ("direct_channels", "direct_channel"),
    "direct_posts": ("direct_posts", "direct_post"),
    "emoji": ("emoji",),
    "attachments": ("attachments",),
}


def lookup_count(*sources: dict, aliases: tuple[str, ...]) -> int:
    for source in sources:
        if not isinstance(source, dict):
            continue
        for alias in aliases:
            if alias in source:
                return int(source.get(alias, 0) or 0)
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate a human-readable Phase 1 verification report.")
    parser.add_argument("--workspace", required=True)
    parser.add_argument("--output-md", required=True)
    parser.add_argument("--artifact-report", default="")
    parser.add_argument("--jsonl-report", default="")
    parser.add_argument("--enrichment-report", default="")
    parser.add_argument("--reconciliation-report", default="")
    parser.add_argument("--integration-report", default="")
    parser.add_argument("--secret-scan-report", default="")
    parser.add_argument("--handoff-json", default="")
    args = parser.parse_args()

    try:
        artifact_report = read_json(args.artifact_report) if args.artifact_report else {}
        jsonl_report = read_json(args.jsonl_report) if args.jsonl_report else {}
        enrichment_report = read_json(args.enrichment_report) if args.enrichment_report else {}
        reconciliation_report = read_json(args.reconciliation_report) if args.reconciliation_report else {}
        integration_report = read_json(args.integration_report) if args.integration_report else {}
        secret_scan_report = read_json(args.secret_scan_report) if args.secret_scan_report else {}
        handoff = read_json(args.handoff_json) if args.handoff_json else {}
    except FileNotFoundError as exc:
        print(f"error: missing verification input: {exc}", file=sys.stderr)
        return 1
    except json.JSONDecodeError as exc:
        print(f"error: invalid verification input json: {exc}", file=sys.stderr)
        return 1

    lines = [
        "# Phase 1 Verification",
        "",
        f"- Workspace: `{args.workspace}`",
        f"- Artifact gate: `{status_for_report(artifact_report)}`",
        f"- JSONL gate: `{status_for_report(jsonl_report)}`",
        f"- Enrichment gate: `{status_for_report(enrichment_report)}`",
        f"- Reconciliation gate: `{status_for_report(reconciliation_report, 'completed')}`",
        f"- Secret scan: `{status_for_report(secret_scan_report, 'not-run')}`",
        "",
        "## Counts",
    ]

    handoff_counts = handoff.get("counts", {})
    jsonl_counts = jsonl_report.get("counts", {})
    if handoff_counts or jsonl_counts:
        for key, aliases in COUNT_KEYS.items():
            lines.append(f"- {key}: {lookup_count(handoff_counts, jsonl_counts, aliases=aliases)}")
    else:
        lines.append("- Counts were not captured.")
    lines.append("")

    extend_lines(lines, "## Blocking Issues", artifact_report.get("errors", []) + jsonl_report.get("errors", []) + enrichment_report.get("errors", []))
    extend_lines(lines, "## Warnings", artifact_report.get("warnings", []) + jsonl_report.get("warnings", []) + enrichment_report.get("warnings", []) + reconciliation_report.get("warnings", []))

    services = integration_report.get("services", [])
    lines.append("## Integration Inventory")
    if services:
        for service in services[:20]:
            lines.append(
                f"- `{service['service']}`: {service.get('event_count', 0)} events; actions: {', '.join(service.get('sample_actions', [])) or 'n/a'}"
            )
    else:
        lines.append("- No integration inventory was captured.")
    lines.append("")

    lines.append("## Handoff Snapshot")
    if handoff:
        lines.append(f"- Final package: `{handoff.get('final_package', {}).get('path', '')}`")
        lines.append(f"- Final package SHA256: `{handoff.get('final_package', {}).get('sha256', '')}`")
        known_gaps = handoff.get("known_gaps", [])
        if known_gaps:
            lines.append("- Known gaps:")
            lines.extend(f"  - {gap}" for gap in known_gaps)
    else:
        lines.append("- Handoff JSON was not supplied.")
    lines.append("")

    if secret_scan_report:
        lines.append("## Secret Scan")
        findings = secret_scan_report.get("findings", [])
        lines.append(f"- Findings: {len(findings)}")
        lines.append("")

    output = Path(args.output_md)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"wrote {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
