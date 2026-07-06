#!/usr/bin/env python3
import argparse
from collections import Counter
import json
from pathlib import Path
import sys


ORDER = {
    "version": 0,
    "emoji": 1,
    "team": 2,
    "channel": 3,
    "user": 4,
    "post": 5,
    "direct_channel": 6,
    "direct_post": 7,
}


def require_dict(obj: dict, kind: str, line_no: int, errors: list[str]) -> dict:
    payload = obj.get(kind)
    if not isinstance(payload, dict):
        errors.append(f"line {line_no}: missing or invalid payload for type={kind}")
        return {}
    return payload


def require_list(value, label: str, line_no: int, errors: list[str]) -> list:
    if value is None:
        return []
    if not isinstance(value, list):
        errors.append(f"line {line_no}: {label} must be a list")
        return []
    return value


def main() -> int:
    parser = argparse.ArgumentParser(description="Semantic validator for Phase 1 Mattermost JSONL output.")
    parser.add_argument("jsonl")
    parser.add_argument("--output-json", default="")
    args = parser.parse_args()

    path = Path(args.jsonl)
    if not path.exists():
        print(f"error: missing jsonl file: {path}", file=sys.stderr)
        return 1

    counts: Counter[str] = Counter()
    errors: list[str] = []
    warnings: list[str] = []
    teams: set[str] = set()
    channels: set[tuple[str, str]] = set()
    users: set[str] = set()
    emails: dict[str, str] = {}
    direct_channels: set[tuple[str, ...]] = set()
    emoji_names: set[str] = set()
    last_order = -1

    with path.open(encoding="utf-8") as handle:
        for line_no, raw_line in enumerate(handle, 1):
            line = raw_line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError as exc:
                errors.append(f"line {line_no}: invalid json: {exc}")
                continue

            kind = obj.get("type")
            if not isinstance(kind, str):
                errors.append(f"line {line_no}: missing type")
                continue
            counts[kind] += 1

            if line_no == 1 and kind != "version":
                errors.append(f"line 1: first object must be version, got {kind}")

            if kind in ORDER:
                order = ORDER[kind]
                if order < last_order:
                    errors.append(
                        f"line {line_no}: object type {kind} is out of order relative to prior records"
                    )
                last_order = max(last_order, order)
            else:
                warnings.append(f"line {line_no}: unrecognized type {kind}")

            if kind == "version":
                if obj.get("version") != 1:
                    errors.append(f"line {line_no}: version object must declare version=1")

            elif kind == "emoji":
                emoji = require_dict(obj, "emoji", line_no, errors)
                if emoji:
                    name = emoji.get("name")
                    image = emoji.get("image")
                    if not name or not image:
                        errors.append(f"line {line_no}: emoji records require name and image")
                    elif name in emoji_names:
                        errors.append(f"line {line_no}: duplicate emoji name {name}")
                    else:
                        emoji_names.add(str(name))
                    if image and (not isinstance(image, str) or not image.startswith("data/emoji/")):
                        warnings.append(
                            f"line {line_no}: emoji image path should normally live under data/emoji/, got {image!r}"
                        )

            elif kind == "team":
                team = require_dict(obj, "team", line_no, errors)
                name = team.get("name")
                if not name:
                    errors.append(f"line {line_no}: team missing name")
                elif name in teams:
                    errors.append(f"line {line_no}: duplicate team name {name}")
                else:
                    teams.add(name)

            elif kind == "channel":
                channel = require_dict(obj, "channel", line_no, errors)
                team_name = channel.get("team")
                channel_name = channel.get("name")
                if not team_name or not channel_name:
                    errors.append(f"line {line_no}: channel requires team and name")
                    continue
                if team_name not in teams:
                    errors.append(f"line {line_no}: channel {channel_name} references missing team {team_name}")
                key = (team_name, channel_name)
                if key in channels:
                    errors.append(f"line {line_no}: duplicate channel {team_name}/{channel_name}")
                else:
                    channels.add(key)

            elif kind == "user":
                user = require_dict(obj, "user", line_no, errors)
                username = user.get("username")
                email = user.get("email", "")
                if not username:
                    errors.append(f"line {line_no}: user missing username")
                    continue
                if username in users:
                    errors.append(f"line {line_no}: duplicate username {username}")
                else:
                    users.add(username)
                if not email:
                    warnings.append(f"line {line_no}: user {username} has empty email")
                elif email in emails and emails[email] != username:
                    errors.append(
                        f"line {line_no}: duplicate email {email} used by {emails[email]} and {username}"
                    )
                else:
                    emails[email] = username
                for membership in require_list(user.get("teams", []), "user teams", line_no, errors):
                    if not isinstance(membership, dict):
                        errors.append(f"line {line_no}: user team membership entries must be objects")
                        continue
                    team_name = membership.get("name")
                    if team_name and team_name not in teams:
                        warnings.append(
                            f"line {line_no}: user {username} references team {team_name} not defined earlier"
                        )
                    for channel_membership in require_list(
                        membership.get("channels", []),
                        "user team channels",
                        line_no,
                        errors,
                    ):
                        if not isinstance(channel_membership, dict):
                            errors.append(
                                f"line {line_no}: user channel membership entries must be objects"
                            )
                            continue
                        channel_name = channel_membership.get("name")
                        if team_name and channel_name and (team_name, channel_name) not in channels:
                            warnings.append(
                                f"line {line_no}: user {username} references missing channel {team_name}/{channel_name}"
                            )

            elif kind == "post":
                post = require_dict(obj, "post", line_no, errors)
                team_name = post.get("team")
                channel_name = post.get("channel")
                username = post.get("user")
                if not team_name or not channel_name or not username:
                    errors.append(f"line {line_no}: post requires team, channel, and user")
                    continue
                if (team_name, channel_name) not in channels:
                    errors.append(
                        f"line {line_no}: post references missing channel {team_name}/{channel_name}"
                    )
                if username not in users:
                    errors.append(f"line {line_no}: post references missing user {username}")
                create_at = post.get("create_at")
                if not isinstance(create_at, int):
                    errors.append(f"line {line_no}: post create_at must be an integer")
                attachments = require_list(post.get("attachments", []), "post attachments", line_no, errors)
                if not post.get("message") and not attachments:
                    warnings.append(f"line {line_no}: post has empty message and no attachments")

            elif kind == "direct_channel":
                direct_channel = require_dict(obj, "direct_channel", line_no, errors)
                members = direct_channel.get("members", [])
                if not isinstance(members, list) or len(members) < 2:
                    errors.append(f"line {line_no}: direct_channel requires at least two members")
                    continue
                member_tuple = tuple(sorted(str(member) for member in members))
                if member_tuple in direct_channels:
                    warnings.append(f"line {line_no}: duplicate direct_channel member set {member_tuple}")
                direct_channels.add(member_tuple)
                for member in member_tuple:
                    if member not in users:
                        errors.append(
                            f"line {line_no}: direct_channel references missing user {member}"
                        )

            elif kind == "direct_post":
                direct_post = require_dict(obj, "direct_post", line_no, errors)
                members = direct_post.get("channel_members", [])
                if not isinstance(members, list) or len(members) < 2:
                    errors.append(f"line {line_no}: direct_post requires channel_members with at least two users")
                    continue
                member_tuple = tuple(sorted(str(member) for member in members))
                if member_tuple not in direct_channels:
                    errors.append(
                        f"line {line_no}: direct_post references undefined direct channel members {member_tuple}"
                    )
                username = direct_post.get("user")
                if username not in users:
                    errors.append(f"line {line_no}: direct_post references missing user {username}")
                create_at = direct_post.get("create_at")
                if not isinstance(create_at, int):
                    errors.append(f"line {line_no}: direct_post create_at must be an integer")

    if counts["version"] != 1:
        errors.append(f"expected exactly one version record, found {counts['version']}")
    if counts["team"] == 0:
        warnings.append("no team records found")
    if counts["user"] == 0:
        errors.append("no user records found")
    if counts["channel"] == 0:
        warnings.append("no channel records found")
    if counts["post"] == 0 and counts["direct_post"] == 0:
        warnings.append("no post or direct_post records found")

    summary = {
        "path": str(path),
        "counts": dict(counts),
        "teams": len(teams),
        "channels": len(channels),
        "users": len(users),
        "direct_channels": len(direct_channels),
        "errors": errors,
        "warnings": warnings,
    }

    if args.output_json:
        output_path = Path(args.output_json)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
        print(f"wrote {output_path}")

    for warning in warnings:
        print(f"warning: {warning}", file=sys.stderr)
    if errors:
        for error in errors:
            print(f"error: {error}", file=sys.stderr)
        return 1

    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
