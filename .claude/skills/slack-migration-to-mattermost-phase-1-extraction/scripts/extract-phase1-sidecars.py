#!/usr/bin/env python3
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import shutil
import sys
import zipfile


SIDECAR_MARKERS = {"canvas", "canvases", "list", "lists", "bookmark", "bookmarks", "admin", "audit"}
WORKFLOW_MARKERS = {"workflow", "workflows"}


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def bucket_for_path(path: Path) -> str:
    lowered_parts = [part.lower() for part in path.parts]
    if any(marker in lowered_parts for marker in WORKFLOW_MARKERS):
        return "workflows"
    if path.name == "integration_logs.json":
        return "sidecars"
    if any(marker in lowered_parts for marker in SIDECAR_MARKERS):
        return "sidecars"
    return ""


def copy_tree(source: Path, destination_root: Path, source_label: str, records: list[dict]) -> None:
    if source.is_file():
        destination = destination_root / source.name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
        records.append(
            {
                "bucket": destination_root.name,
                "path": str(destination.resolve()),
                "sha256": sha256_file(destination),
                "bytes": destination.stat().st_size,
                "source": source_label,
            }
        )
        return

    for file_path in sorted(source.rglob("*")):
        if not file_path.is_file():
            continue
        destination = destination_root / source.name / file_path.relative_to(source)
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(file_path, destination)
        records.append(
            {
                "bucket": destination_root.name,
                "path": str(destination.resolve()),
                "sha256": sha256_file(destination),
                "bytes": destination.stat().st_size,
                "source": source_label,
            }
        )


def extract_from_zip(archive_path: Path, output_dir: Path, records: list[dict]) -> None:
    with zipfile.ZipFile(archive_path) as archive:
        for name in archive.namelist():
            if name.endswith("/"):
                continue
            bucket = bucket_for_path(Path(name))
            if not bucket:
                continue
            destination = output_dir / bucket / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            with archive.open(name) as source_handle:
                destination.write_bytes(source_handle.read())
            records.append(
                {
                    "bucket": bucket,
                    "path": str(destination.resolve()),
                    "sha256": sha256_file(destination),
                    "bytes": destination.stat().st_size,
                    "source": "raw-archive",
                }
            )


def main() -> int:
    parser = argparse.ArgumentParser(description="Collect sidecar and workflow artifacts for Phase 1.")
    parser.add_argument("--workspace", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--metadata-out", required=True)
    parser.add_argument("--raw-archive", default="")
    parser.add_argument("--sidecar-input", action="append", default=[])
    parser.add_argument("--workflow-input", action="append", default=[])
    args = parser.parse_args()

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    records: list[dict] = []

    if args.raw_archive:
        raw_archive = Path(args.raw_archive)
        if not raw_archive.exists():
            print(f"error: missing raw archive: {raw_archive}", file=sys.stderr)
            return 1
        try:
            extract_from_zip(raw_archive, output_dir, records)
        except zipfile.BadZipFile:
            print(f"error: invalid raw archive: {raw_archive}", file=sys.stderr)
            return 1

    for raw_path in args.sidecar_input:
        source = Path(raw_path)
        if not source.exists():
            print(f"error: missing sidecar input: {source}", file=sys.stderr)
            return 1
        copy_tree(source, output_dir / "sidecars", "operator-sidecar", records)

    for raw_path in args.workflow_input:
        source = Path(raw_path)
        if not source.exists():
            print(f"error: missing workflow input: {source}", file=sys.stderr)
            return 1
        copy_tree(source, output_dir / "workflows", "operator-workflow", records)

    payload = {
        "schema_version": 1,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "workspace": args.workspace,
        "counts": {
            "sidecars": sum(1 for record in records if record["bucket"] == "sidecars"),
            "workflows": sum(1 for record in records if record["bucket"] == "workflows"),
        },
        "artifacts": records,
    }

    metadata_out = Path(args.metadata_out)
    metadata_out.parent.mkdir(parents=True, exist_ok=True)
    metadata_out.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {metadata_out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
