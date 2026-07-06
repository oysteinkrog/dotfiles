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


def resolve_path(reference_path: Path, raw_path: str, base_dir: str = "") -> Path:
    path = Path(raw_path)
    if path.is_absolute():
        return path.resolve()

    candidates: list[Path] = []
    if base_dir:
        candidates.append((Path(base_dir) / path).resolve())
    candidates.append((reference_path.parent / path).resolve())
    candidates.append((Path.cwd() / path).resolve())

    for candidate in candidates:
        if candidate.exists():
            return candidate
    return candidates[0]


def dict_field(payload: dict, key: str, errors: list[str], label: str) -> dict:
    value = payload.get(key, {})
    if value in ("", None):
        return {}
    if not isinstance(value, dict):
        errors.append(f"{label} must be a JSON object")
        return {}
    return value


def string_list_field(payload: dict, key: str, errors: list[str], label: str) -> list[str]:
    value = payload.get(key, [])
    if value in ("", None):
        return []
    if isinstance(value, list):
        return [str(item) for item in value]
    errors.append(f"{label} must be a JSON array")
    return []


def safe_count(counts: dict, key: str, errors: list[str]) -> int | None:
    try:
        return int(counts.get(key, 0))
    except (TypeError, ValueError):
        errors.append(f"handoff count {key} must be an integer")
        return None


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate the Phase 2 intake bundle produced by Phase 1.")
    parser.add_argument("--handoff-json", required=True)
    parser.add_argument("--intake-manifest", default="")
    parser.add_argument("--output-json", default="")
    args = parser.parse_args()

    handoff_path = Path(args.handoff_json)
    if not handoff_path.exists():
        print(f"error: missing handoff json: {handoff_path}", file=sys.stderr)
        return 1

    try:
        handoff = json.loads(handoff_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        print(f"error: invalid handoff json: {exc}", file=sys.stderr)
        return 1
    if not isinstance(handoff, dict):
        print(f"error: handoff json root must be an object: {handoff_path}", file=sys.stderr)
        return 1

    errors: list[str] = []
    warnings: list[str] = []

    final_package = dict_field(handoff, "final_package", errors, "handoff.final_package")
    final_path_raw = str(final_package.get("path", ""))
    expected_hash = str(final_package.get("sha256", ""))
    if not final_path_raw:
        errors.append("handoff json is missing final package path")
    else:
        final_path = resolve_path(handoff_path, final_path_raw)
    if final_path_raw and not final_path.exists():
        errors.append(f"missing final package: {final_path}")
    elif final_path_raw:
        actual_hash = sha256_file(final_path)
        if not expected_hash:
            errors.append("handoff json is missing final package sha256")
        elif actual_hash != expected_hash:
            errors.append("final package sha256 does not match handoff json")
        try:
            with zipfile.ZipFile(final_path) as archive:
                names = set(archive.namelist())
            if "mattermost_import.jsonl" not in names:
                errors.append("final package is missing mattermost_import.jsonl")
            if not any(name.startswith("data/") for name in names):
                errors.append("final package is missing data/ directory")
        except zipfile.BadZipFile:
            errors.append("final package is not a valid zip file")

    counts = dict_field(handoff, "counts", errors, "handoff.counts")
    for key in ("users", "channels"):
        value = safe_count(counts, key, errors)
        if value is not None and value <= 0:
            errors.append(f"handoff count {key} must be > 0")
    posts = safe_count(counts, "posts", errors)
    direct_posts = safe_count(counts, "direct_posts", errors)
    for key in ("direct_channels", "emoji", "attachments"):
        safe_count(counts, key, errors)
    if posts is not None and direct_posts is not None and posts <= 0 and direct_posts <= 0:
        warnings.append("handoff reports zero posts and zero direct posts")

    manifests = string_list_field(handoff, "manifests", errors, "handoff.manifests")
    if not manifests:
        warnings.append("handoff json includes no manifest paths")
    else:
        for manifest in manifests:
            resolved_manifest = resolve_path(handoff_path, str(manifest))
            if not resolved_manifest.exists():
                errors.append(f"referenced manifest does not exist: {resolved_manifest}")

    sidecar_channels = string_list_field(handoff, "sidecar_channels", errors, "handoff.sidecar_channels")
    if not sidecar_channels:
        warnings.append("handoff json does not list any sidecar channels")

    if args.intake_manifest:
        intake_manifest_path = Path(args.intake_manifest)
        if not intake_manifest_path.exists():
            errors.append(f"missing intake manifest: {intake_manifest_path}")
        else:
            try:
                intake_manifest = json.loads(intake_manifest_path.read_text(encoding="utf-8"))
            except json.JSONDecodeError as exc:
                errors.append(f"invalid intake manifest json: {exc}")
            else:
                if not isinstance(intake_manifest, dict):
                    errors.append(f"intake manifest root must be a JSON object: {intake_manifest_path}")
                    intake_manifest = {}
                intake_base_dir = str(intake_manifest.get("base_dir", ""))
                artifacts = intake_manifest.get("artifacts", [])
                if artifacts in ("", None):
                    artifacts = []
                if not isinstance(artifacts, list):
                    errors.append("intake manifest artifacts must be a JSON array")
                    artifacts = []
                for artifact in artifacts:
                    if not isinstance(artifact, dict):
                        errors.append("intake manifest contains a non-object artifact entry")
                        continue
                    artifact_path = artifact.get("path", "")
                    if not artifact_path:
                        errors.append("intake manifest artifact is missing path")
                        continue
                    path = resolve_path(intake_manifest_path, str(artifact_path), intake_base_dir)
                    if not path.exists():
                        errors.append(f"intake manifest references missing artifact: {path}")
                        continue
                    expected_artifact_hash = str(artifact.get("sha256", ""))
                    if expected_artifact_hash and sha256_file(path) != expected_artifact_hash:
                        errors.append(f"intake manifest sha256 mismatch for artifact: {path}")

    report = {
        "handoff_json": str(handoff_path),
        "intake_manifest": args.intake_manifest,
        "status": "passed" if not errors else "failed",
        "errors": errors,
        "warnings": warnings,
        "counts": counts,
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

    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
