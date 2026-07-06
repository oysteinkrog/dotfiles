#!/usr/bin/env python3
import argparse
from collections import defaultdict
from datetime import datetime, timezone
import json
from pathlib import Path
import sys
import zipfile


def decode_year(create_at: int) -> int:
    if create_at > 10_000_000_000:
        timestamp = create_at / 1000
    else:
        timestamp = create_at
    return datetime.fromtimestamp(timestamp, tz=timezone.utc).year


def load_jsonl_from_zip(archive: zipfile.ZipFile) -> list[dict]:
    with archive.open("mattermost_import.jsonl") as handle:
        lines = [line.decode("utf-8").strip() for line in handle if line.strip()]
    records: list[dict] = []
    for line in lines:
        records.append(json.loads(line))
    return records


def attachment_paths(record: dict) -> list[str]:
    kind = str(record.get("type", ""))
    payload = record.get(kind, {})
    if not isinstance(payload, dict):
        return []
    attachments = payload.get("attachments", [])
    if not isinstance(attachments, list):
        return []
    paths: list[str] = []
    for attachment in attachments:
        if isinstance(attachment, dict) and attachment.get("path"):
            paths.append(str(attachment["path"]).lstrip("/"))
    return paths


def record_year(record: dict) -> int | None:
    kind = str(record.get("type", ""))
    if kind not in {"post", "direct_post"}:
        return None
    payload = record.get(kind, {})
    if not isinstance(payload, dict):
        raise ValueError(f"{kind} record payload must be an object")
    create_at = payload.get("create_at")
    if not isinstance(create_at, int):
        raise ValueError(f"{kind} record is missing integer create_at")
    return decode_year(create_at)


def main() -> int:
    parser = argparse.ArgumentParser(description="Split a Mattermost bulk import ZIP into per-year batches.")
    parser.add_argument("--input-zip", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--years", default="")
    parser.add_argument("--report-json", default="")
    args = parser.parse_args()

    input_zip = Path(args.input_zip)
    if not input_zip.exists():
        print(f"error: missing input zip: {input_zip}", file=sys.stderr)
        return 1

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    if args.years:
        try:
            requested_years = {int(item) for item in args.years.split(",") if item.strip()}
        except ValueError:
            print(f"error: invalid --years value: {args.years}", file=sys.stderr)
            return 1
    else:
        requested_years = set()

    try:
        with zipfile.ZipFile(input_zip) as archive:
            records = load_jsonl_from_zip(archive)
            names = set(archive.namelist())
            extra_prefixes = [
                prefix
                for prefix in ("sidecars/", "workflows/", "emoji/", "metadata/", "data/emoji/")
                if any(name.startswith(prefix) for name in names)
            ]

            shared_records: list[dict] = []
            per_year_records: dict[int, list[dict]] = defaultdict(list)
            per_year_attachments: dict[int, set[str]] = defaultdict(set)

            for record in records:
                year = record_year(record)
                if year is None:
                    shared_records.append(record)
                    continue
                if requested_years and year not in requested_years:
                    continue
                per_year_records[year].append(record)
                per_year_attachments[year].update(attachment_paths(record))

            if not per_year_records:
                print("error: no year-specific post data found to split", file=sys.stderr)
                return 1

            batch_report = {"input_zip": str(input_zip.resolve()), "batches": []}
            for year in sorted(per_year_records):
                batch_zip = output_dir / f"mattermost-bulk-import.{year}.zip"
                batch_jsonl_lines = [json.dumps(record, separators=(",", ":")) for record in shared_records]
                batch_jsonl_lines.extend(json.dumps(record, separators=(",", ":")) for record in per_year_records[year])

                with zipfile.ZipFile(batch_zip, "w", compression=zipfile.ZIP_DEFLATED) as batch_archive:
                    batch_archive.writestr("mattermost_import.jsonl", "\n".join(batch_jsonl_lines) + "\n")
                    for attachment_path in sorted(per_year_attachments[year]):
                        archive_name = attachment_path.lstrip("/")
                        if archive_name not in names:
                            continue
                        with archive.open(archive_name) as attachment_handle:
                            batch_archive.writestr(archive_name, attachment_handle.read())
                    for prefix in extra_prefixes:
                        for name in sorted(item for item in names if item.startswith(prefix) and not item.endswith("/")):
                            with archive.open(name) as handle:
                                batch_archive.writestr(name, handle.read())

                batch_report["batches"].append(
                    {
                        "year": year,
                        "zip": str(batch_zip.resolve()),
                        "posts": sum(1 for record in per_year_records[year] if record.get("type") == "post"),
                        "direct_posts": sum(1 for record in per_year_records[year] if record.get("type") == "direct_post"),
                        "attachments": len(per_year_attachments[year]),
                    }
                )
                print(f"wrote {batch_zip}")

    except KeyError:
        print(f"error: import zip is missing mattermost_import.jsonl: {input_zip}", file=sys.stderr)
        return 1
    except ValueError as exc:
        print(f"error: invalid import record in {input_zip}: {exc}", file=sys.stderr)
        return 1
    except zipfile.BadZipFile:
        print(f"error: invalid import zip: {input_zip}", file=sys.stderr)
        return 1
    except json.JSONDecodeError as exc:
        print(f"error: invalid jsonl payload in {input_zip}: {exc}", file=sys.stderr)
        return 1

    if args.report_json:
        report_json = Path(args.report_json)
        report_json.parent.mkdir(parents=True, exist_ok=True)
        report_json.write_text(json.dumps(batch_report, indent=2) + "\n", encoding="utf-8")
        print(f"wrote {report_json}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
