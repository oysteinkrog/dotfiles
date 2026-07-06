#!/usr/bin/env python3
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import sys


def count_jsonl_types(path: Path) -> dict[str, int]:
    counts: dict[str, int] = {}
    if not path.exists():
        return counts
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


def load_manifest(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def resolve_artifact_path(manifest_path: Path, manifest: dict, raw_path: str) -> Path:
    path = Path(raw_path)
    if path.is_absolute():
        return path.resolve()

    candidates: list[Path] = []
    base_dir = manifest.get("base_dir")
    if base_dir:
        candidates.append((Path(base_dir) / path).resolve())
    candidates.append((Path.cwd() / path).resolve())
    candidates.append((manifest_path.parent / path).resolve())

    for candidate in candidates:
        if candidate.exists():
            return candidate

    return candidates[0]


def load_hash_from_manifests(manifest_paths: list[Path], target: Path) -> str:
    target = target.resolve()
    for manifest_path in manifest_paths:
        manifest = load_manifest(manifest_path)
        for artifact in manifest.get("artifacts", []):
            artifact_path = artifact.get("path")
            if not artifact_path:
                continue
            if resolve_artifact_path(manifest_path, manifest, artifact_path) == target:
                return artifact.get("sha256", "")
    return ""


def count_attachment_paths(path: Path) -> int:
    attachments = 0
    if not path.exists():
        return attachments
    with path.open(encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue
            kind = obj.get("type")
            payload = obj.get(kind or "", {})
            if not isinstance(payload, dict):
                continue
            for attachment in payload.get("attachments", []):
                if isinstance(attachment, dict) and attachment.get("path"):
                    attachments += 1
    return attachments


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate a Phase 1 -> Phase 2 handoff summary.")
    parser.add_argument("--workspace", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--final-zip", required=True)
    parser.add_argument("--jsonl", default="")
    parser.add_argument("--manifest", action="append", default=[])
    parser.add_argument("--known-gap", action="append", default=[])
    parser.add_argument("--sidecar-channel", action="append", default=[])
    parser.add_argument("--json-output", default="")
    parser.add_argument("--plan-tier", default="")
    parser.add_argument("--export-basis", default="")
    parser.add_argument("--allow-unknown-hash", action="store_true")
    args = parser.parse_args()

    manifest_paths = [Path(item) for item in args.manifest]
    final_zip = Path(args.final_zip)
    jsonl_path = Path(args.jsonl) if args.jsonl else None

    if not final_zip.exists():
        print(f"error: missing final zip: {final_zip}", file=sys.stderr)
        return 1

    if jsonl_path and not jsonl_path.exists():
        print(f"error: missing jsonl file: {jsonl_path}", file=sys.stderr)
        return 1

    for manifest_path in manifest_paths:
        if not manifest_path.exists():
            print(f"error: missing manifest: {manifest_path}", file=sys.stderr)
            return 1

    counts = count_jsonl_types(jsonl_path) if jsonl_path else {}
    try:
        final_hash = load_hash_from_manifests(manifest_paths, final_zip)
    except json.JSONDecodeError as exc:
        print(f"error: invalid manifest json: {exc}", file=sys.stderr)
        return 1
    if manifest_paths and not final_hash and not args.allow_unknown_hash:
        print(
            "error: could not locate final zip hash in supplied manifests; pass --allow-unknown-hash to override",
            file=sys.stderr,
        )
        return 1

    sidecars = args.sidecar_channel or [
        "slack-canvases-archive",
        "slack-lists-archive",
        "slack-export-admin",
    ]

    lines = [
        "# Handoff Summary",
        "",
        f"- Workspace: `{args.workspace}`",
        f"- Final package: `{final_zip}`",
        f"- Hash: `{final_hash or 'unknown'}`",
        "",
        "## Counts",
        f"- Users: {counts.get('user', 0)}",
        f"- Channels: {counts.get('channel', 0)}",
        f"- Posts: {counts.get('post', 0)}",
        f"- Direct channels: {counts.get('direct_channel', 0)}",
        f"- Direct posts: {counts.get('direct_post', 0)}",
        f"- Emoji: {counts.get('emoji', 0)}",
        f"- Attachments referenced: {count_attachment_paths(jsonl_path) if jsonl_path else 0}",
        "",
        "## Sidecar Channels",
    ]
    lines.extend(f"- `{channel}`" for channel in sidecars)
    lines.extend(["", "## Known Gaps"])
    if args.known_gap:
        lines.extend(f"- {gap}" for gap in args.known_gap)
    else:
        lines.append("- None recorded.")

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"wrote {output}")

    if args.json_output:
        payload = {
            "schema_version": 1,
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "workspace": args.workspace,
            "plan_tier": args.plan_tier,
            "export_basis": args.export_basis,
            "final_package": {
                "path": str(final_zip),
                "sha256": final_hash or "",
            },
            "jsonl_path": str(jsonl_path) if jsonl_path else "",
            "manifests": [str(item) for item in manifest_paths],
            "counts": {
                "users": counts.get("user", 0),
                "channels": counts.get("channel", 0),
                "posts": counts.get("post", 0),
                "direct_channels": counts.get("direct_channel", 0),
                "direct_posts": counts.get("direct_post", 0),
                "emoji": counts.get("emoji", 0),
                "attachments": count_attachment_paths(jsonl_path) if jsonl_path else 0,
            },
            "sidecar_channels": sidecars,
            "known_gaps": args.known_gap,
        }
        json_output = Path(args.json_output)
        json_output.parent.mkdir(parents=True, exist_ok=True)
        json_output.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
        print(f"wrote {json_output}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
