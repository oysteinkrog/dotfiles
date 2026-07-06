#!/usr/bin/env python3
import argparse
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


def resolve_artifact_path(manifest_path: Path, manifest: dict, raw_path: str) -> Path:
    path = Path(raw_path)
    if path.is_absolute():
        return path

    candidates: list[Path] = []
    base_dir = manifest.get("base_dir")
    if base_dir:
        candidates.append(Path(base_dir) / path)
    candidates.append(Path.cwd() / path)
    candidates.append(manifest_path.parent / path)

    for candidate in candidates:
        if candidate.exists():
            return candidate

    return candidates[0]


def inspect_zip(path: Path, errors: list[str]) -> None:
    try:
        with zipfile.ZipFile(path) as archive:
            names = set(archive.namelist())
            basenames = {Path(name).name for name in names if not name.endswith("/")}
            if "mattermost_import.jsonl" in basenames:
                if not any(name == "data/" or name.startswith("data/") for name in names):
                    errors.append(f"{path}: missing data/ directory in import zip")
            else:
                if not ({"users.json", "org_users.json"} & basenames):
                    errors.append(f"{path}: missing users.json or org_users.json")
                if not ({"channels.json", "groups.json", "dms.json", "mpims.json"} & basenames):
                    errors.append(
                        f"{path}: missing conversation index (channels.json/groups.json/dms.json/mpims.json)"
                    )
    except zipfile.BadZipFile:
        errors.append(f"{path}: invalid zip file")


def count_jsonl_types(path: Path) -> dict[str, int]:
    counts: dict[str, int] = {}
    with path.open(encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue
            kind = obj.get("type", "unknown")
            counts[kind] = counts.get(kind, 0) + 1
    return counts


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate Phase 1 manifests and artifacts.")
    parser.add_argument("--root", default="artifacts")
    parser.add_argument("--output-json", default="")
    args = parser.parse_args()

    root = Path(args.root)
    errors: list[str] = []
    warnings: list[str] = []

    manifests = sorted(root.rglob("manifest*.json"))
    if not manifests:
        warnings.append(f"no manifests found under {root}")

    for manifest_path in manifests:
        try:
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            errors.append(f"{manifest_path}: invalid json: {exc}")
            continue
        for artifact in manifest.get("artifacts", []):
            artifact_path = artifact.get("path")
            if not artifact_path:
                errors.append(f"{manifest_path}: artifact entry missing path")
                continue
            path = resolve_artifact_path(manifest_path, manifest, artifact_path)
            if not path.exists():
                errors.append(f"{manifest_path}: missing artifact {path}")
                continue
            expected = artifact.get("sha256")
            if expected:
                actual = sha256_file(path)
                if actual != expected:
                    errors.append(f"{manifest_path}: sha mismatch for {path}")
            if path.suffix == ".zip":
                inspect_zip(path, errors)

    jsonl_files = sorted(root.rglob("mattermost_import.jsonl"))
    for jsonl_path in jsonl_files:
        counts = count_jsonl_types(jsonl_path)
        if counts.get("user", 0) == 0:
            errors.append(f"{jsonl_path}: no user objects found")
        if counts.get("channel", 0) == 0:
            errors.append(f"{jsonl_path}: no channel objects found")
        if counts.get("post", 0) == 0:
            warnings.append(f"{jsonl_path}: no post objects found")
        print(f"{jsonl_path}: {json.dumps(counts, sort_keys=True)}")

    report = {
        "root": str(root),
        "manifests": [str(path) for path in manifests],
        "errors": errors,
        "warnings": warnings,
        "status": "passed" if not errors else "failed",
    }

    if args.output_json:
        output_path = Path(args.output_json)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        print(f"wrote {output_path}")

    for warning in warnings:
        print(f"warning: {warning}", file=sys.stderr)
    if errors:
        for error in errors:
            print(f"error: {error}", file=sys.stderr)
        return 1

    print("phase1 artifact validation passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
