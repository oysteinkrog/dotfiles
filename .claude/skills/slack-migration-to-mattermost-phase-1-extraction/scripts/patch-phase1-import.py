#!/usr/bin/env python3
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import shutil
import sys


ARCHIVE_CHANNEL_SPECS = {
    "slack-canvases-archive": {
        "display_name": "Slack Canvases Archive",
        "type": "P",
        "header": "Archived Slack canvases preserved during migration",
        "purpose": "Read-only archive of Slack canvas artifacts",
    },
    "slack-lists-archive": {
        "display_name": "Slack Lists Archive",
        "type": "P",
        "header": "Archived Slack lists preserved during migration",
        "purpose": "Read-only archive of Slack list artifacts",
    },
    "slack-export-admin": {
        "display_name": "Slack Export Admin",
        "type": "P",
        "header": "Slack migration admin artifacts and provenance",
        "purpose": "Read-only archive of Slack admin-side artifacts and proofs",
    },
}

CHANNEL_BUCKETS = {
    "canvas": "slack-canvases-archive",
    "list": "slack-lists-archive",
    "admin": "slack-export-admin",
    "workflow": "slack-export-admin",
}


def load_jsonl(path: Path) -> list[dict]:
    records: list[dict] = []
    with path.open(encoding="utf-8") as handle:
        for line_no, raw_line in enumerate(handle, 1):
            line = raw_line.strip()
            if not line:
                continue
            try:
                records.append(json.loads(line))
            except json.JSONDecodeError as exc:
                raise ValueError(f"{path}:{line_no}: invalid json: {exc}") from exc
    return records


def write_jsonl(path: Path, records: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        for record in records:
            handle.write(json.dumps(record, separators=(",", ":")) + "\n")


def sanitize_name(value: str, default: str) -> str:
    cleaned = re.sub(r"[^a-z0-9_-]+", "-", value.lower()).strip("-_")
    return cleaned or default


def unique_destination(root: Path, relative_path: Path) -> Path:
    candidate = root / relative_path
    candidate.parent.mkdir(parents=True, exist_ok=True)
    if not candidate.exists():
        return candidate
    stem = candidate.stem
    suffix = candidate.suffix
    counter = 1
    while True:
        deduped = candidate.with_name(f"{stem}.{counter}{suffix}")
        if not deduped.exists():
            return deduped
        counter += 1


def copy_asset(source: Path, destination_root: Path, relative_path: Path) -> Path:
    destination = unique_destination(destination_root, relative_path)
    shutil.copy2(source, destination)
    return destination


def iter_source_files(source: Path) -> list[tuple[Path, Path]]:
    if source.is_file():
        return [(source, Path(source.name))]
    results: list[tuple[Path, Path]] = []
    for file_path in sorted(source.rglob("*")):
        if file_path.is_file():
            results.append((file_path, file_path.relative_to(source)))
    return results


def load_json(path: Path, label: str) -> dict:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise FileNotFoundError(f"missing {label}: {path}") from exc
    except json.JSONDecodeError as exc:
        raise ValueError(f"invalid {label} json: {path}: {exc}") from exc
    if not isinstance(payload, dict):
        raise ValueError(f"{label} json root must be an object: {path}")
    return payload


def infer_bucket(relative_path: Path, explicit_bucket: str) -> str:
    if explicit_bucket == "workflow":
        return "workflow"
    lowered_parts = [part.lower() for part in relative_path.parts]
    lowered_name = relative_path.name.lower()
    if "workflow" in lowered_parts or "workflows" in lowered_parts:
        return "workflow"
    if any("canvas" in part for part in lowered_parts) or lowered_name.endswith(".html"):
        return "canvas"
    if any("list" in part for part in lowered_parts):
        return "list"
    return "admin"


def archive_message(bucket: str, filename: str, source_hint: str) -> str:
    if bucket == "canvas":
        label = "Slack Canvas"
    elif bucket == "list":
        label = "Slack List"
    elif bucket == "workflow":
        label = "Slack Workflow Artifact"
    else:
        label = "Slack Admin Artifact"
    return (
        f"**{label}:** `{filename}`\n\n"
        f"Preserved during Slack migration patching.\n"
        f"Source: `{source_hint}`"
    )


def ensure_archive_user_membership(user_record: dict, team_name: str, channel_names: list[str]) -> None:
    payload = user_record.get("user")
    if not isinstance(payload, dict):
        raise ValueError("archive user record payload is invalid")
    memberships = payload.setdefault("teams", [])
    if not isinstance(memberships, list):
        raise ValueError("archive user teams membership must be a list")

    target_membership = None
    for membership in memberships:
        if isinstance(membership, dict) and membership.get("name") == team_name:
            target_membership = membership
            break
    if target_membership is None:
        target_membership = {"name": team_name, "roles": "team_user", "channels": []}
        memberships.append(target_membership)

    channel_memberships = target_membership.setdefault("channels", [])
    if not isinstance(channel_memberships, list):
        raise ValueError("archive user team channels must be a list")

    existing = {item.get("name") for item in channel_memberships if isinstance(item, dict)}
    for channel_name in channel_names:
        if channel_name not in existing:
            channel_memberships.append(
                {"name": channel_name, "roles": "channel_user", "favorite": False}
            )


def choose_archive_user(user_records: list[dict], archive_user: str) -> dict:
    if archive_user:
        for record in user_records:
            payload = record.get("user", {})
            if isinstance(payload, dict) and payload.get("username") == archive_user:
                return record
        raise ValueError(f"archive user not found in jsonl: {archive_user}")

    for record in user_records:
        payload = record.get("user", {})
        roles = str(payload.get("roles", "")) if isinstance(payload, dict) else ""
        if "system_admin" in roles:
            return record
    if not user_records:
        raise ValueError("jsonl contains no user records for archive injection")
    return user_records[0]


def max_create_at(post_records: list[dict], direct_post_records: list[dict]) -> int:
    max_seen = int(datetime.now(timezone.utc).timestamp() * 1000)
    for record in list(post_records) + list(direct_post_records):
        kind = str(record.get("type", ""))
        payload = record.get(kind, {})
        if isinstance(payload, dict):
            value = payload.get("create_at")
            if isinstance(value, int):
                max_seen = max(max_seen, value)
    return max_seen


def infer_team_name(by_type: dict[str, list[dict]], explicit_team: str) -> str:
    if explicit_team:
        return explicit_team
    for record in by_type.get("team", []):
        payload = record.get("team", {})
        if isinstance(payload, dict) and payload.get("name"):
            return str(payload["name"])
    for record in by_type.get("channel", []):
        payload = record.get("channel", {})
        if isinstance(payload, dict) and payload.get("team"):
            return str(payload["team"])
    for record in by_type.get("user", []):
        payload = record.get("user", {})
        if not isinstance(payload, dict):
            continue
        teams = payload.get("teams", [])
        if isinstance(teams, list):
            for membership in teams:
                if isinstance(membership, dict) and membership.get("name"):
                    return str(membership["name"])
    return ""


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Inject native emoji objects and archive posts/channels into a Phase 1 Mattermost import JSONL."
    )
    parser.add_argument("--workspace", required=True)
    parser.add_argument("--jsonl", required=True)
    parser.add_argument("--attachments-root", required=True)
    parser.add_argument("--emoji-assets-dir", default="")
    parser.add_argument("--emoji-manifest", default="")
    parser.add_argument("--emoji-aliases", default="")
    parser.add_argument("--sidecar-dir", action="append", default=[])
    parser.add_argument("--workflow-dir", action="append", default=[])
    parser.add_argument("--archive-user", default="")
    parser.add_argument("--team", default="")
    parser.add_argument("--team-display-name", default="")
    parser.add_argument("--summary-out", default="")
    args = parser.parse_args()

    jsonl_path = Path(args.jsonl)
    if not jsonl_path.exists():
        print(f"error: missing jsonl file: {jsonl_path}", file=sys.stderr)
        return 1

    attachments_root = Path(args.attachments_root)
    attachments_root.mkdir(parents=True, exist_ok=True)
    emoji_assets_dir = Path(args.emoji_assets_dir) if args.emoji_assets_dir else None
    if emoji_assets_dir is not None:
        emoji_assets_dir.mkdir(parents=True, exist_ok=True)

    sidecar_dirs = [Path(item) for item in args.sidecar_dir if item]
    workflow_dirs = [Path(item) for item in args.workflow_dir if item]
    for source_dir in sidecar_dirs + workflow_dirs:
        if not source_dir.exists():
            print(f"error: missing patch input directory: {source_dir}", file=sys.stderr)
            return 1

    try:
        records = load_jsonl(jsonl_path)
    except ValueError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    by_type: dict[str, list[dict]] = {
        "version": [],
        "emoji": [],
        "team": [],
        "channel": [],
        "user": [],
        "post": [],
        "direct_channel": [],
        "direct_post": [],
        "unknown": [],
    }
    for record in records:
        kind = str(record.get("type", ""))
        by_type[kind if kind in by_type else "unknown"].append(record)

    if len(by_type["version"]) != 1:
        print("error: expected exactly one version record before patching", file=sys.stderr)
        return 1
    if not by_type["user"]:
        print("error: expected at least one user record before patching", file=sys.stderr)
        return 1

    team_name = infer_team_name(by_type, args.team)
    if not team_name:
        print("error: could not determine Mattermost team name from jsonl", file=sys.stderr)
        return 1
    team_record_added = False
    if not by_type["team"]:
        by_type["team"].append(
            {
                "type": "team",
                "team": {
                    "name": team_name,
                    "display_name": args.team_display_name or team_name,
                    "type": "O",
                    "allow_open_invite": True,
                },
            }
        )
        team_record_added = True
    if args.team_display_name:
        for record in by_type["team"]:
            payload = record.get("team")
            if isinstance(payload, dict) and payload.get("name") == team_name:
                payload["display_name"] = args.team_display_name

    try:
        archive_user_record = choose_archive_user(by_type["user"], args.archive_user)
    except ValueError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    archive_user = str(archive_user_record.get("user", {}).get("username", ""))
    if not archive_user:
        print("error: archive user record is missing username", file=sys.stderr)
        return 1

    existing_channels = {
        str(record.get("channel", {}).get("name", ""))
        for record in by_type["channel"]
        if isinstance(record.get("channel"), dict)
    }
    existing_emoji = {
        str(record.get("emoji", {}).get("name", ""))
        for record in by_type["emoji"]
        if isinstance(record.get("emoji"), dict)
    }

    injected_channels: list[dict] = []
    injected_emoji: list[dict] = []
    injected_posts: list[dict] = []
    warnings: list[str] = []

    if args.emoji_manifest:
        manifest_path = Path(args.emoji_manifest)
        aliases_path = Path(args.emoji_aliases) if args.emoji_aliases else None
        try:
            manifest = load_json(manifest_path, "emoji manifest")
            aliases = load_json(aliases_path, "emoji aliases") if aliases_path else {"aliases": {}}
        except (FileNotFoundError, ValueError) as exc:
            print(f"error: {exc}", file=sys.stderr)
            return 1

        custom_emoji = manifest.get("custom_emoji", [])
        if not isinstance(custom_emoji, list):
            print(f"error: emoji manifest has invalid custom_emoji payload: {manifest_path}", file=sys.stderr)
            return 1
        if emoji_assets_dir is None:
            print("error: --emoji-assets-dir is required when --emoji-manifest is supplied", file=sys.stderr)
            return 1

        for entry in custom_emoji:
            if not isinstance(entry, dict):
                warnings.append("skipping non-object custom emoji entry")
                continue
            name = sanitize_name(str(entry.get("name", "")), "emoji")
            if name in existing_emoji:
                continue
            raw_path = Path(str(entry.get("path", "")))
            if not raw_path.exists():
                warnings.append(f"custom emoji asset missing on disk: {raw_path}")
                continue
            destination = copy_asset(raw_path, emoji_assets_dir, Path(f"{name}{raw_path.suffix or '.bin'}"))
            injected_emoji.append(
                {
                    "type": "emoji",
                    "emoji": {
                        "name": name,
                        "image": str(Path("data/emoji") / destination.name),
                    },
                }
            )
            existing_emoji.add(name)

        alias_map = aliases.get("aliases", {}) if isinstance(aliases, dict) else {}
        if isinstance(alias_map, dict) and alias_map:
            destination = copy_asset(
                aliases_path,
                attachments_root,
                Path("admin") / aliases_path.name,
            )
            injected_posts.append(
                {
                    "type": "post",
                    "post": {
                        "team": team_name,
                        "channel": CHANNEL_BUCKETS["admin"],
                        "user": archive_user,
                        "message": (
                            "**Slack Emoji Aliases**\n\n"
                            "Mattermost bulk import has no native alias object type. "
                            "This preserved alias map documents the original Slack alias relationships."
                        ),
                        "attachments": [
                            {
                                "path": str(
                                    Path("data/bulk-export-attachments")
                                    / destination.relative_to(attachments_root)
                                )
                            }
                        ],
                    },
                }
            )

    staged_posts: list[dict] = []
    for source_dir, bucket_label in [(path, "sidecar") for path in sidecar_dirs] + [
        (path, "workflow") for path in workflow_dirs
    ]:
        for source_file, relative_path in iter_source_files(source_dir):
            bucket = infer_bucket(relative_path, bucket_label)
            channel_name = CHANNEL_BUCKETS[bucket]
            destination = copy_asset(
                source_file,
                attachments_root,
                Path("workflows" if bucket_label == "workflow" else "sidecars") / relative_path,
            )
            staged_posts.append(
                {
                    "type": "post",
                    "post": {
                        "team": team_name,
                        "channel": channel_name,
                        "user": archive_user,
                        "message": archive_message(bucket, source_file.name, str(relative_path)),
                        "attachments": [
                            {
                                "path": str(
                                    Path("data/bulk-export-attachments")
                                    / destination.relative_to(attachments_root)
                                )
                            }
                        ],
                    },
                }
            )

    required_channels = sorted(
        {
            post["post"]["channel"]
            for post in list(injected_posts) + staged_posts
            if isinstance(post.get("post"), dict) and post["post"].get("channel")
        }
    )
    for channel_name in required_channels:
        if channel_name in existing_channels:
            continue
        spec = ARCHIVE_CHANNEL_SPECS[channel_name]
        injected_channels.append(
            {
                "type": "channel",
                "channel": {
                    "team": team_name,
                    "name": channel_name,
                    "display_name": spec["display_name"],
                    "type": spec["type"],
                    "header": spec["header"],
                    "purpose": spec["purpose"],
                },
            }
        )
        existing_channels.add(channel_name)

    try:
        ensure_archive_user_membership(archive_user_record, team_name, required_channels)
    except ValueError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    timestamp_seed = max_create_at(by_type["post"], by_type["direct_post"])
    sequence = 1
    for post in list(injected_posts) + staged_posts:
        payload = post.get("post", {})
        if isinstance(payload, dict):
            payload["create_at"] = timestamp_seed + sequence
            sequence += 1
    injected_posts.extend(staged_posts)

    rewritten = (
        by_type["version"]
        + by_type["emoji"]
        + injected_emoji
        + by_type["team"]
        + by_type["channel"]
        + injected_channels
        + by_type["user"]
        + by_type["post"]
        + injected_posts
        + by_type["direct_channel"]
        + by_type["direct_post"]
        + by_type["unknown"]
    )
    write_jsonl(jsonl_path, rewritten)

    summary = {
        "schema_version": 1,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "workspace": args.workspace,
        "status": "patched",
        "jsonl": str(jsonl_path.resolve()),
        "team": team_name,
        "archive_user": archive_user,
        "counts": {
            "team_records_added": 1 if team_record_added else 0,
            "emoji_records_added": len(injected_emoji),
            "archive_channels_added": len(injected_channels),
            "archive_posts_added": len(injected_posts),
            "archive_channel_names": required_channels,
        },
        "warnings": warnings,
    }

    if args.summary_out:
        summary_path = Path(args.summary_out)
        summary_path.parent.mkdir(parents=True, exist_ok=True)
        summary_path.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
        print(f"wrote {summary_path}")

    for warning in warnings:
        print(f"warning: {warning}", file=sys.stderr)
    print(f"patched {jsonl_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
