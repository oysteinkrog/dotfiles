#!/usr/bin/env python3
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import shutil
import sys
import zipfile


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def ensure_zip(path: Path) -> None:
    with zipfile.ZipFile(path):
        return


def copy_path(source: Path, destination_dir: Path) -> Path:
    destination_dir.mkdir(parents=True, exist_ok=True)
    target = destination_dir / source.name
    if target.resolve() == source.resolve():
        return target
    if target.exists():
        stem = source.stem
        suffix = source.suffix
        counter = 1
        while True:
            candidate = destination_dir / f"{stem}.{counter}{suffix}"
            if not candidate.exists():
                target = candidate
                break
            counter += 1
    shutil.copy2(source, target)
    return target


def add_artifact(artifacts: list[dict], path: Path, source_label: str, imported_from: Path) -> None:
    artifacts.append(
        {
            "path": str(path.resolve()),
            "sha256": sha256_file(path),
            "bytes": path.stat().st_size,
            "source": source_label,
            "imported_from": str(imported_from.resolve()),
        }
    )


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Quarantine official Slack export artifacts into the Phase 1 raw artifact tree."
    )
    parser.add_argument("--workspace", required=True)
    parser.add_argument("--archive", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--manifest-out", required=True)
    parser.add_argument("--summary-out", default="")
    parser.add_argument("--channel-audit-csv", default="")
    parser.add_argument("--member-csv", default="")
    parser.add_argument("--extra", action="append", default=[])
    parser.add_argument("--source-label", default="official-export")
    args = parser.parse_args()

    archive_path = Path(args.archive)
    if not archive_path.exists():
        print(f"error: missing archive: {archive_path}", file=sys.stderr)
        return 1
    try:
        ensure_zip(archive_path)
    except zipfile.BadZipFile:
        print(f"error: invalid zip file: {archive_path}", file=sys.stderr)
        return 1

    raw_dir = Path(args.output_dir)
    raw_dir.mkdir(parents=True, exist_ok=True)
    artifacts: list[dict] = []
    copied_paths: list[Path] = []

    copied_archive = copy_path(archive_path, raw_dir)
    copied_paths.append(copied_archive)
    add_artifact(artifacts, copied_archive, args.source_label, archive_path)

    optional_paths = [
        Path(item)
        for item in [args.channel_audit_csv, args.member_csv, *args.extra]
        if item
    ]

    for optional_path in optional_paths:
        if not optional_path.exists():
            print(f"error: missing optional artifact: {optional_path}", file=sys.stderr)
            return 1
        copied = copy_path(optional_path, raw_dir)
        copied_paths.append(copied)
        add_artifact(artifacts, copied, args.source_label, optional_path)

    manifest = {
        "schema_version": 1,
        "created_at": datetime.now(timezone.utc).isoformat(),
        "workspace": args.workspace,
        "stage": "raw",
        "plan_tier": "",
        "base_dir": str(raw_dir.resolve()),
        "artifacts": artifacts,
        "known_gaps": [],
    }

    manifest_out = Path(args.manifest_out)
    manifest_out.parent.mkdir(parents=True, exist_ok=True)
    manifest_out.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {manifest_out}")

    if args.summary_out:
        summary = {
            "workspace": args.workspace,
            "status": "quarantined",
            "source_label": args.source_label,
            "raw_dir": str(raw_dir.resolve()),
            "copied_files": [str(path.resolve()) for path in copied_paths],
            "manifest": str(manifest_out.resolve()),
        }
        summary_out = Path(args.summary_out)
        summary_out.parent.mkdir(parents=True, exist_ok=True)
        summary_out.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
        print(f"wrote {summary_out}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
