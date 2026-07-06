#!/usr/bin/env python3
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import sys


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def iter_files(path: Path):
    if path.is_file():
        yield path
        return
    for file_path in sorted(path.rglob("*")):
        if file_path.is_file():
            yield file_path


def main() -> int:
    parser = argparse.ArgumentParser(description="Build an auditable evidence pack manifest for a Slack-to-Mattermost migration.")
    parser.add_argument("--workspace", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--note", action="append", default=[])
    parser.add_argument("--approval", action="append", default=[])
    parser.add_argument("paths", nargs="+")
    args = parser.parse_args()

    entries = []
    seen_paths: set[Path] = set()
    for raw_path in args.paths:
        path = Path(raw_path)
        if not path.exists():
            print(f"error: missing evidence path: {path}", file=sys.stderr)
            return 1
        for file_path in iter_files(path):
            resolved_path = file_path.resolve()
            if resolved_path in seen_paths:
                continue
            seen_paths.add(resolved_path)
            entries.append(
                {
                    "path": str(file_path),
                    "sha256": sha256_file(file_path),
                    "bytes": file_path.stat().st_size,
                }
            )

    payload = {
        "schema_version": 1,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "workspace": args.workspace,
        "approvals": args.approval,
        "notes": args.note,
        "files": entries,
    }

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {output} with {len(entries)} files")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
