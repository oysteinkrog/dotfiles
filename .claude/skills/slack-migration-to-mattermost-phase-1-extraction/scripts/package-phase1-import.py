#!/usr/bin/env python3
import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import sys
import zipfile


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def iter_files(root: Path):
    for file_path in sorted(root.rglob("*")):
        if file_path.is_file():
            yield file_path


def jsonl_counts(path: Path) -> dict[str, int]:
    counts: Counter[str] = Counter()
    with path.open(encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            obj = json.loads(line)
            counts[str(obj.get("type", "unknown"))] += 1
    return dict(counts)


def add_tree(archive: zipfile.ZipFile, root: Path, prefix: str) -> int:
    count = 0
    if not root.exists():
        return count
    for file_path in iter_files(root):
        arcname = str(Path(prefix) / file_path.relative_to(root))
        archive.write(file_path, arcname)
        count += 1
    return count


def artifact_entry(path: Path, source: str) -> dict:
    return {
        "path": str(path.resolve()),
        "sha256": sha256_file(path),
        "bytes": path.stat().st_size,
        "source": source,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Package Phase 1 JSONL, attachments, sidecars, and emoji into the import bundle.")
    parser.add_argument("--workspace", required=True)
    parser.add_argument("--jsonl", required=True)
    parser.add_argument("--output-zip", required=True)
    parser.add_argument("--manifest-out", required=True)
    parser.add_argument("--summary-out", default="")
    parser.add_argument("--attachments-dir", default="")
    parser.add_argument("--emoji-asset-dir", default="")
    parser.add_argument("--sidecar-dir", action="append", default=[])
    parser.add_argument("--workflow-dir", action="append", default=[])
    parser.add_argument("--emoji-dir", action="append", default=[])
    args = parser.parse_args()

    jsonl_path = Path(args.jsonl)
    if not jsonl_path.exists():
        print(f"error: missing jsonl file: {jsonl_path}", file=sys.stderr)
        return 1

    output_zip = Path(args.output_zip)
    output_zip.parent.mkdir(parents=True, exist_ok=True)

    attachments_dir = Path(args.attachments_dir) if args.attachments_dir else None
    emoji_asset_dir = Path(args.emoji_asset_dir) if args.emoji_asset_dir else None
    sidecar_dirs = [Path(item) for item in args.sidecar_dir if item]
    workflow_dirs = [Path(item) for item in args.workflow_dir if item]
    emoji_dirs = [Path(item) for item in args.emoji_dir if item]

    for directory in ([attachments_dir] if attachments_dir else []) + ([emoji_asset_dir] if emoji_asset_dir else []) + sidecar_dirs + workflow_dirs + emoji_dirs:
        if not directory.exists():
            print(f"error: missing package input directory: {directory}", file=sys.stderr)
            return 1

    with zipfile.ZipFile(output_zip, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.write(jsonl_path, "mattermost_import.jsonl")
        archive.writestr("data/bulk-export-attachments/", b"")
        if emoji_asset_dir:
            archive.writestr("data/emoji/", b"")
        attachment_count = (
            add_tree(archive, attachments_dir, "data/bulk-export-attachments")
            if attachments_dir
            else 0
        )
        emoji_asset_count = (
            add_tree(archive, emoji_asset_dir, "data/emoji")
            if emoji_asset_dir
            else 0
        )
        sidecar_count = sum(add_tree(archive, directory, "sidecars") for directory in sidecar_dirs)
        workflow_count = sum(add_tree(archive, directory, "workflows") for directory in workflow_dirs)
        emoji_count = sum(add_tree(archive, directory, "emoji") for directory in emoji_dirs)

    summary = {
        "schema_version": 1,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "workspace": args.workspace,
        "output_zip": str(output_zip.resolve()),
        "jsonl_counts": jsonl_counts(jsonl_path),
        "bundle_counts": {
            "attachments": attachment_count,
            "emoji_native_assets": emoji_asset_count,
            "sidecars": sidecar_count,
            "workflows": workflow_count,
            "emoji_assets": emoji_count,
        },
    }

    manifest = {
        "schema_version": 1,
        "created_at": datetime.now(timezone.utc).isoformat(),
        "workspace": args.workspace,
        "stage": "import-ready",
        "plan_tier": "",
        "base_dir": str(output_zip.parent.resolve()),
        "artifacts": [artifact_entry(jsonl_path, "phase1-package"), artifact_entry(output_zip, "phase1-package")],
        "known_gaps": [],
    }
    for directory in ([attachments_dir] if attachments_dir else []) + ([emoji_asset_dir] if emoji_asset_dir else []) + sidecar_dirs + workflow_dirs + emoji_dirs:
        for file_path in iter_files(directory):
            manifest["artifacts"].append(artifact_entry(file_path, "phase1-package"))

    manifest_out = Path(args.manifest_out)
    manifest_out.parent.mkdir(parents=True, exist_ok=True)
    manifest_out.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {manifest_out}")

    if args.summary_out:
        summary_out = Path(args.summary_out)
        summary_out.parent.mkdir(parents=True, exist_ok=True)
        summary_out.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
        print(f"wrote {summary_out}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
