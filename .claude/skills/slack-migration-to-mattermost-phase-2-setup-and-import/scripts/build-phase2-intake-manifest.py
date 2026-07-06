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


def main() -> int:
    parser = argparse.ArgumentParser(description="Build a Phase 2 intake manifest for handoff artifacts and server-side validation inputs.")
    parser.add_argument("--workspace", required=True)
    parser.add_argument("--environment", default="staging")
    parser.add_argument("--output", required=True)
    parser.add_argument("files", nargs="+")
    args = parser.parse_args()

    artifacts = []
    for raw_path in args.files:
        path = Path(raw_path)
        if not path.exists():
            print(f"error: missing artifact: {path}", file=sys.stderr)
            return 1
        artifacts.append(
            {
                "path": str(path),
                "sha256": sha256_file(path),
                "bytes": path.stat().st_size,
            }
        )

    payload = {
        "schema_version": 1,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "workspace": args.workspace,
        "environment": args.environment,
        "base_dir": str(Path.cwd()),
        "artifacts": artifacts,
    }

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
