#!/usr/bin/env python3
import argparse
from collections import Counter
import csv
import json
from pathlib import Path
import sys
import zipfile


TOP_LEVEL_METADATA = {
    "channels.json",
    "groups.json",
    "dms.json",
    "mpims.json",
    "users.json",
    "org_users.json",
    "integration_logs.json",
}
NON_MESSAGE_PARTS = {"__uploads", "sidecars", "workflows", "emoji"}


def detect_archive_root(names: list[str]) -> str:
    file_paths = [Path(name) for name in names if name and not name.endswith("/")]
    if not file_paths:
        return ""
    if any(len(path.parts) == 1 for path in file_paths):
        return ""
    roots = {path.parts[0] for path in file_paths if path.parts}
    if len(roots) != 1:
        return ""
    return next(iter(roots))


def canonicalize_archive_path(path: Path, archive_root: str) -> Path:
    if archive_root and len(path.parts) > 1 and path.parts[0] == archive_root:
        return Path(*path.parts[1:])
    return path


def path_is_message_json(path: Path) -> bool:
    return (
        path.suffix == ".json"
        and len(path.parts) >= 2
        and path.name not in TOP_LEVEL_METADATA
        and all(part not in NON_MESSAGE_PARTS for part in path.parts)
    )


def slack_user_count(counts: dict[str, int]) -> int:
    return int(counts.get("users", 0)) + int(counts.get("org_users", 0))


def count_archive(archive_path: Path) -> dict[str, int]:
    counts: Counter[str] = Counter()
    with zipfile.ZipFile(archive_path) as archive:
        names = archive.namelist()
        archive_root = detect_archive_root(names)
        file_entries = [
            (name, canonicalize_archive_path(Path(name), archive_root))
            for name in names
            if name and not name.endswith("/")
        ]
        metadata_members = {
            canonical.name: original
            for original, canonical in file_entries
            if len(canonical.parts) == 1 and canonical.name in TOP_LEVEL_METADATA
        }

        for metadata in ("channels.json", "groups.json", "dms.json", "mpims.json", "users.json", "org_users.json"):
            member_name = metadata_members.get(metadata)
            if not member_name:
                continue
            with archive.open(member_name) as handle:
                data = json.load(handle)
            key = metadata.replace(".json", "")
            counts[key] += len(data) if isinstance(data, list) else 1

        for name, canonical_path in file_entries:
            if "__uploads" in canonical_path.parts:
                counts["uploads"] += 1
            if path_is_message_json(canonical_path):
                with archive.open(name) as handle:
                    data = json.load(handle)
                if isinstance(data, list):
                    counts["messages"] += len(data)
                    for message in data:
                        if not isinstance(message, dict):
                            continue
                        file_objects = message.get("files", [])
                        if isinstance(file_objects, list):
                            counts["message_file_refs"] += len(file_objects)
    return dict(counts)


def count_jsonl(path: Path) -> dict[str, int]:
    counts: Counter[str] = Counter()
    with path.open(encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue
            counts[obj.get("type", "unknown")] += 1
    return dict(counts)


def count_channel_audit(path: Path) -> int:
    with path.open(encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        return sum(1 for _ in reader)


def main() -> int:
    parser = argparse.ArgumentParser(description="Reconcile raw, enriched, and import-ready Phase 1 counts.")
    parser.add_argument("--raw-archive", required=True)
    parser.add_argument("--enriched-archive", default="")
    parser.add_argument("--jsonl", default="")
    parser.add_argument("--channel-audit-csv", default="")
    parser.add_argument("--output-json", default="")
    args = parser.parse_args()

    raw_archive = Path(args.raw_archive)
    if not raw_archive.exists():
        print(f"error: missing raw archive: {raw_archive}", file=sys.stderr)
        return 1

    try:
        raw_counts = count_archive(raw_archive)
    except (zipfile.BadZipFile, json.JSONDecodeError) as exc:
        print(f"error: unable to inspect raw archive {raw_archive}: {exc}", file=sys.stderr)
        return 1

    report: dict[str, object] = {
        "raw_archive": str(raw_archive),
        "raw_counts": raw_counts,
        "enriched_archive": "",
        "enriched_counts": {},
        "jsonl": "",
        "jsonl_counts": {},
        "channel_audit_rows": 0,
        "warnings": [],
    }

    if args.enriched_archive:
        enriched_archive = Path(args.enriched_archive)
        if not enriched_archive.exists():
            print(f"error: missing enriched archive: {enriched_archive}", file=sys.stderr)
            return 1
        report["enriched_archive"] = str(enriched_archive)
        try:
            report["enriched_counts"] = count_archive(enriched_archive)
        except (zipfile.BadZipFile, json.JSONDecodeError) as exc:
            print(f"error: unable to inspect enriched archive {enriched_archive}: {exc}", file=sys.stderr)
            return 1

    if args.jsonl:
        jsonl_path = Path(args.jsonl)
        if not jsonl_path.exists():
            print(f"error: missing jsonl file: {jsonl_path}", file=sys.stderr)
            return 1
        report["jsonl"] = str(jsonl_path)
        report["jsonl_counts"] = count_jsonl(jsonl_path)

    if args.channel_audit_csv:
        channel_audit_csv = Path(args.channel_audit_csv)
        if not channel_audit_csv.exists():
            print(f"error: missing channel audit csv: {channel_audit_csv}", file=sys.stderr)
            return 1
        report["channel_audit_rows"] = count_channel_audit(channel_audit_csv)

    raw_counts = report["raw_counts"]
    enriched_counts = report["enriched_counts"]
    jsonl_counts = report["jsonl_counts"]
    warnings = report["warnings"]

    if enriched_counts:
        if slack_user_count(enriched_counts) < slack_user_count(raw_counts):
            warnings.append("enriched archive has fewer users than raw archive")
        if enriched_counts.get("message_file_refs", 0) > 0 and enriched_counts.get("uploads", 0) == 0:
            warnings.append("enriched archive references files but has no uploaded files")

    if jsonl_counts:
        slack_channel_total = raw_counts.get("channels", 0) + raw_counts.get("groups", 0)
        if slack_channel_total and jsonl_counts.get("channel", 0) == 0:
            warnings.append("jsonl has no channel records despite channels/groups in Slack export")
        if raw_counts.get("messages", 0) and jsonl_counts.get("post", 0) == 0 and jsonl_counts.get("direct_post", 0) == 0:
            warnings.append("jsonl has no posts despite messages in Slack export")
        if slack_user_count(raw_counts) and jsonl_counts.get("user", 0) == 0:
            warnings.append("jsonl has no user objects despite users in Slack export")

    if args.output_json:
        output_path = Path(args.output_json)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        print(f"wrote {output_path}")

    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
