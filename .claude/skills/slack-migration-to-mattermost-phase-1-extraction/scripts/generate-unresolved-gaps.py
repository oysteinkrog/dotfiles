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


def classify_gap(text: str) -> str:
    lowered = text.lower()
    if "sidecar" in lowered or "workflow" in lowered or "canvas" in lowered:
        return "sidecar-only"
    if "integration" in lowered or "emoji" in lowered:
        return "manual-rebuild"
    if "missing" in lowered or "unrecoverable" in lowered or "no " in lowered:
        return "unrecoverable"
    return "needs-disposition"


def main() -> int:
    parser = argparse.ArgumentParser(description="Aggregate unresolved gaps from Phase 1 validation artifacts.")
    parser.add_argument("--workspace", required=True)
    parser.add_argument("--output-md", required=True)
    parser.add_argument("--handoff-json", default="")
    parser.add_argument("--enrichment-report", default="")
    parser.add_argument("--reconciliation-report", default="")
    parser.add_argument("--artifact-report", default="")
    parser.add_argument("--manual-gap", action="append", default=[])
    args = parser.parse_args()

    try:
        handoff = read_json(args.handoff_json) if args.handoff_json else {}
        enrichment = read_json(args.enrichment_report) if args.enrichment_report else {}
        reconciliation = read_json(args.reconciliation_report) if args.reconciliation_report else {}
        artifact = read_json(args.artifact_report) if args.artifact_report else {}
    except FileNotFoundError as exc:
        print(f"error: missing gap input: {exc}", file=sys.stderr)
        return 1
    except json.JSONDecodeError as exc:
        print(f"error: invalid gap input json: {exc}", file=sys.stderr)
        return 1

    gap_lines: list[str] = []
    gap_lines.extend(str(item) for item in handoff.get("known_gaps", []))
    gap_lines.extend(str(item) for item in enrichment.get("warnings", []))
    gap_lines.extend(str(item) for item in reconciliation.get("warnings", []))
    gap_lines.extend(str(item) for item in artifact.get("warnings", []))
    gap_lines.extend(args.manual_gap)

    deduped: list[str] = []
    seen: set[str] = set()
    for item in gap_lines:
        normalized = item.strip()
        if not normalized or normalized in seen:
            continue
        seen.add(normalized)
        deduped.append(normalized)

    lines = [
        "# Unresolved Gaps",
        "",
        f"- Workspace: `{args.workspace}`",
        f"- Gap count: {len(deduped)}",
        "",
        "## Items",
    ]
    if deduped:
        for item in deduped:
            lines.append(f"- [{classify_gap(item)}] {item}")
    else:
        lines.append("- None recorded.")

    output = Path(args.output_md)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"wrote {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
