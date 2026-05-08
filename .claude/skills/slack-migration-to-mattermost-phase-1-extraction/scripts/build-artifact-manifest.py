#!/usr/bin/env python3
import argparse
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path
import sys


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Build a stage manifest with hashes for migration artifacts."
    )
    parser.add_argument("--workspace", required=True)
    parser.add_argument("--stage", required=True, help="raw, enriched, import-ready, etc.")
    parser.add_argument("--source", required=True, help="Artifact source label.")
    parser.add_argument("--output", required=True)
    parser.add_argument("--plan-tier", default="")
    parser.add_argument("--known-gap", action="append", default=[])
    parser.add_argument("files", nargs="+")
    args = parser.parse_args()

    artifacts = []
    for file_arg in args.files:
        path = Path(file_arg)
        if not path.exists():
            print(f"error: missing artifact: {path}", file=sys.stderr)
            return 1
        artifacts.append(
            {
                "path": str(path),
                "sha256": sha256_file(path),
                "bytes": path.stat().st_size,
                "source": args.source,
            }
        )

    manifest = {
        "created_at": datetime.now(timezone.utc).isoformat(),
        "workspace": args.workspace,
        "stage": args.stage,
        "plan_tier": args.plan_tier,
        "base_dir": str(Path.cwd()),
        "artifacts": artifacts,
        "known_gaps": args.known_gap,
    }

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {output} with {len(artifacts)} artifacts")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
