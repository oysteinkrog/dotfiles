#!/usr/bin/env python3
import argparse
from collections import Counter
import json
from pathlib import Path
import sys
import zipfile


def load_integration_logs(archive_path: Path):
    with zipfile.ZipFile(archive_path) as archive:
        if "integration_logs.json" not in archive.namelist():
            return []
        with archive.open("integration_logs.json") as handle:
            data = json.load(handle)
    if isinstance(data, list):
        return data
    if isinstance(data, dict):
        if isinstance(data.get("logs"), list):
            return data["logs"]
        return [data]
    return []


def main() -> int:
    parser = argparse.ArgumentParser(description="Extract an integration/app inventory from Slack export audit logs.")
    parser.add_argument("--archive", required=True)
    parser.add_argument("--output-json", required=True)
    parser.add_argument("--output-md", default="")
    args = parser.parse_args()

    archive_path = Path(args.archive)
    if not archive_path.exists():
        print(f"error: missing archive: {archive_path}", file=sys.stderr)
        return 1

    try:
        rows = load_integration_logs(archive_path)
    except (zipfile.BadZipFile, json.JSONDecodeError) as exc:
        print(f"error: unable to inspect integration logs in {archive_path}: {exc}", file=sys.stderr)
        return 1

    by_service: Counter[str] = Counter()
    by_action: Counter[str] = Counter()
    services: dict[str, dict] = {}

    for row in rows:
        if not isinstance(row, dict):
            continue
        service = str(
            row.get("service_name")
            or row.get("service")
            or row.get("app_name")
            or row.get("name")
            or "unknown"
        )
        action = str(row.get("action") or row.get("event") or row.get("type") or "unknown")
        by_service[service] += 1
        by_action[action] += 1
        if service not in services:
            services[service] = {
                "service": service,
                "sample_actions": [],
                "service_ids": set(),
                "actors": set(),
                "channels": set(),
            }
        service_entry = services[service]
        if len(service_entry["sample_actions"]) < 5 and action not in service_entry["sample_actions"]:
            service_entry["sample_actions"].append(action)
        for key in ("service_id", "app_id", "id"):
            if row.get(key):
                service_entry["service_ids"].add(str(row.get(key)))
        for key in ("user_id", "actor_id", "user"):
            if row.get(key):
                service_entry["actors"].add(str(row.get(key)))
        for key in ("channel_id", "channel"):
            if row.get(key):
                service_entry["channels"].add(str(row.get(key)))

    normalized_services = []
    for service, info in sorted(services.items()):
        normalized_services.append(
            {
                "service": service,
                "sample_actions": info["sample_actions"],
                "service_ids": sorted(info["service_ids"]),
                "actors": sorted(info["actors"]),
                "channels": sorted(info["channels"]),
                "event_count": by_service[service],
            }
        )

    payload = {
        "archive": str(archive_path),
        "integration_log_rows": len(rows),
        "services": normalized_services,
        "event_count_by_service": dict(sorted(by_service.items())),
        "event_count_by_action": dict(sorted(by_action.items())),
    }

    output_json = Path(args.output_json)
    output_json.parent.mkdir(parents=True, exist_ok=True)
    output_json.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {output_json}")

    if args.output_md:
        output_md = Path(args.output_md)
        lines = [
            "# Integration Inventory",
            "",
            f"- Archive: `{archive_path}`",
            f"- Integration log rows: {len(rows)}",
            "",
            "## Services",
        ]
        for service in normalized_services:
            lines.append(f"- `{service['service']}`: {service['event_count']} events; sample actions: {', '.join(service['sample_actions']) or 'n/a'}")
        output_md.parent.mkdir(parents=True, exist_ok=True)
        output_md.write_text("\n".join(lines) + "\n", encoding="utf-8")
        print(f"wrote {output_md}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
