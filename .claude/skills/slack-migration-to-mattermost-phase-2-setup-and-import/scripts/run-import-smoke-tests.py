#!/usr/bin/env python3
import argparse
import io
import json
from pathlib import Path
import shlex
import subprocess
import sys
import zipfile
from urllib.parse import urlparse
from urllib.request import urlopen

HTTP_TIMEOUT_SECONDS = 30


def read_json(path_str: str) -> dict:
    path = Path(path_str)
    if not path.exists():
        raise FileNotFoundError(path)
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError(f"json root must be an object: {path}")
    return payload


def resolve_path(reference_path: Path, raw_path: str) -> Path | None:
    cleaned = str(raw_path or "").strip()
    if not cleaned:
        return None
    path = Path(cleaned)
    if path.is_absolute():
        return path.resolve()

    candidates = [
        (reference_path.parent / path).resolve(),
        (Path.cwd() / path).resolve(),
    ]
    for candidate in candidates:
        if candidate.exists():
            return candidate
    return candidates[0]


def run_psql(database_url: str, sql: str, *psql_args: str, ssh_target: str = "") -> subprocess.CompletedProcess[str]:
    command = ["psql", database_url, *psql_args, sql]
    if ssh_target:
        remote_cmd = " ".join(shlex.quote(part) for part in command)
        command = ["ssh", ssh_target, f"bash -lc {shlex.quote(remote_cmd)}"]
    return subprocess.run(
        command,
        check=False,
        capture_output=True,
        text=True,
    )


def query_count(database_url: str, sql: str, ssh_target: str = "") -> int:
    proc = run_psql(database_url, sql, "-Atc", ssh_target=ssh_target)
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.strip() or f"psql failed for query: {sql}")
    return int(proc.stdout.strip() or "0")


def query_rows(database_url: str, sql: str, ssh_target: str = "") -> list[str]:
    proc = run_psql(database_url, sql, "-AtF", "\t", "-c", ssh_target=ssh_target)
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.strip() or f"psql failed for query: {sql}")
    return [line for line in proc.stdout.splitlines() if line.strip()]


def ping(url: str) -> tuple[bool, int]:
    parsed = urlparse(url)
    path = f"{parsed.path.rstrip('/')}/api/v4/system/ping" if parsed.path not in ("", "/") else "/api/v4/system/ping"
    with urlopen(f"{parsed.scheme}://{parsed.netloc}{path}", timeout=HTTP_TIMEOUT_SECONDS) as response:
        return response.status == 200, response.status


def sql_quote(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def read_import_lines(handoff: dict, handoff_path: Path) -> list[dict]:
    jsonl_raw = str(handoff.get("jsonl_path", "") or "").strip()
    jsonl_path = resolve_path(handoff_path, jsonl_raw)
    if jsonl_path is not None and jsonl_path.is_file():
        data = jsonl_path.read_text(encoding="utf-8")
    else:
        final_package_path = resolve_path(handoff_path, str(handoff.get("final_package", {}).get("path", "")))
        if final_package_path is None or not final_package_path.is_file():
            raise FileNotFoundError("neither handoff jsonl_path nor final package path exists")
        with zipfile.ZipFile(final_package_path) as archive:
            jsonl_name = next((name for name in archive.namelist() if name.endswith("mattermost_import.jsonl")), "")
            if not jsonl_name:
                raise FileNotFoundError("mattermost_import.jsonl not found in final package")
            data = archive.read(jsonl_name).decode("utf-8")
    return [json.loads(line) for line in io.StringIO(data) if line.strip()]


def import_selectors(handoff: dict, handoff_path: Path) -> dict[str, set]:
    selectors = {
        "teams": set(),
        "users": set(),
        "channels": set(),
        "direct_channels": set(),
        "emoji": set(),
    }
    for entry in read_import_lines(handoff, handoff_path):
        kind = entry.get("type", "")
        if kind == "team":
            team = entry.get("team", {})
            name = team.get("name")
            if name:
                selectors["teams"].add(name)
        elif kind == "user":
            user = entry.get("user", {})
            username = user.get("username")
            if username:
                selectors["users"].add(username)
        elif kind == "channel":
            channel = entry.get("channel", {})
            team_name = channel.get("team")
            channel_name = channel.get("name")
            if team_name and channel_name:
                selectors["channels"].add((team_name, channel_name))
        elif kind == "direct_channel":
            direct_channel = entry.get("direct_channel", {})
            members = sorted({member for member in direct_channel.get("members", []) if member})
            if len(members) >= 2:
                selectors["direct_channels"].add(tuple(members))
        elif kind == "emoji":
            emoji = entry.get("emoji", {})
            name = emoji.get("name")
            if name:
                selectors["emoji"].add(name)
    return selectors


def count_imported_users(database_url: str, usernames: set[str], ssh_target: str = "") -> int:
    if not usernames:
        return 0
    values = ", ".join(sql_quote(username) for username in sorted(usernames))
    return query_count(database_url, f"SELECT COUNT(*) FROM Users WHERE DeleteAt = 0 AND Username IN ({values});", ssh_target=ssh_target)


def channel_where_clause(channel_pairs: set[tuple[str, str]]) -> str:
    return " OR ".join(
        f"(t.Name = {sql_quote(team_name)} AND c.Name = {sql_quote(channel_name)})"
        for team_name, channel_name in sorted(channel_pairs)
    )


def count_imported_channels(database_url: str, channel_pairs: set[tuple[str, str]], ssh_target: str = "") -> int:
    if not channel_pairs:
        return 0
    where_clause = channel_where_clause(channel_pairs)
    return query_count(
        database_url,
        "SELECT COUNT(*) "
        "FROM Channels c "
        "JOIN Teams t ON t.Id = c.TeamId "
        f"WHERE c.DeleteAt = 0 AND c.Type IN ('O', 'P') AND ({where_clause});",
        ssh_target=ssh_target,
    )


def count_imported_posts(database_url: str, channel_pairs: set[tuple[str, str]], ssh_target: str = "") -> int:
    if not channel_pairs:
        return 0
    where_clause = channel_where_clause(channel_pairs)
    return query_count(
        database_url,
        "SELECT COUNT(*) "
        "FROM Posts p "
        "JOIN Channels c ON c.Id = p.ChannelId "
        "JOIN Teams t ON t.Id = c.TeamId "
        f"WHERE p.DeleteAt = 0 AND c.Type IN ('O', 'P') AND ({where_clause});",
        ssh_target=ssh_target,
    )


def imported_direct_channel_ids(database_url: str, member_sets: set[tuple[str, ...]], ssh_target: str = "") -> list[str]:
    if not member_sets:
        return []
    rows = query_rows(
        database_url,
        "SELECT c.Id, string_agg(u.Username, ',' ORDER BY u.Username) "
        "FROM Channels c "
        "JOIN ChannelMembers cm ON cm.ChannelId = c.Id "
        "JOIN Users u ON u.Id = cm.UserId "
        "WHERE c.DeleteAt = 0 AND c.Type IN ('D', 'G') "
        "GROUP BY c.Id;",
        ssh_target=ssh_target,
    )
    ids: list[str] = []
    for row in rows:
        channel_id, usernames = row.split("\t", 1)
        members = tuple(name for name in usernames.split(",") if name)
        if members in member_sets:
            ids.append(channel_id)
    return ids


def count_direct_posts(database_url: str, channel_ids: list[str], ssh_target: str = "") -> int:
    if not channel_ids:
        return 0
    values = ", ".join(sql_quote(channel_id) for channel_id in channel_ids)
    return query_count(
        database_url,
        f"SELECT COUNT(*) FROM Posts WHERE DeleteAt = 0 AND ChannelId IN ({values});",
        ssh_target=ssh_target,
    )


def count_imported_emoji(database_url: str, emoji_names: set[str], ssh_target: str = "") -> int:
    if not emoji_names:
        return 0
    values = ", ".join(sql_quote(name) for name in sorted(emoji_names))
    return query_count(
        database_url,
        f"SELECT COUNT(*) FROM Emoji WHERE DeleteAt = 0 AND Name IN ({values});",
        ssh_target=ssh_target,
    )


def count_imported_attachments(
    database_url: str,
    channel_pairs: set[tuple[str, str]],
    direct_channel_ids: list[str],
    ssh_target: str = "",
) -> int:
    clauses: list[str] = []
    if channel_pairs:
        where_clause = channel_where_clause(channel_pairs)
        clauses.append(f"(c.Type IN ('O', 'P') AND ({where_clause}))")
    if direct_channel_ids:
        direct_values = ", ".join(sql_quote(channel_id) for channel_id in direct_channel_ids)
        clauses.append(f"(c.Type IN ('D', 'G') AND c.Id IN ({direct_values}))")
    if not clauses:
        return 0
    return query_count(
        database_url,
        "SELECT COUNT(*) "
        "FROM FileInfo fi "
        "JOIN Posts p ON p.Id = fi.PostId "
        "JOIN Channels c ON c.Id = p.ChannelId "
        "LEFT JOIN Teams t ON t.Id = c.TeamId "
        f"WHERE fi.DeleteAt = 0 AND p.DeleteAt = 0 AND ({' OR '.join(clauses)});",
        ssh_target=ssh_target,
    )


def main() -> int:
    parser = argparse.ArgumentParser(description="Collect post-import counts and smoke-check the imported Mattermost instance.")
    parser.add_argument("--handoff-json", required=True)
    parser.add_argument("--database-url", required=True)
    parser.add_argument("--ssh-target", default="")
    parser.add_argument("--mattermost-url", default="")
    parser.add_argument("--output-json", required=True)
    parser.add_argument("--output-md", default="")
    args = parser.parse_args()
    handoff_path = Path(args.handoff_json)

    try:
        handoff = read_json(args.handoff_json)
    except (FileNotFoundError, json.JSONDecodeError, ValueError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    errors: list[str] = []
    checks: dict[str, object] = {}
    counts: dict[str, int] = {}
    selectors: dict[str, set] = {
        "teams": set(),
        "users": set(),
        "channels": set(),
        "direct_channels": set(),
        "emoji": set(),
    }

    try:
        selectors = import_selectors(handoff, handoff_path)
    except Exception as exc:
        errors.append(f"failed to derive import selectors from handoff bundle: {exc}")

    try:
        counts["users"] = count_imported_users(args.database_url, selectors["users"], ssh_target=args.ssh_target)
        counts["channels"] = count_imported_channels(args.database_url, selectors["channels"], ssh_target=args.ssh_target)
        counts["posts"] = count_imported_posts(args.database_url, selectors["channels"], ssh_target=args.ssh_target)
        direct_channel_ids = imported_direct_channel_ids(args.database_url, selectors["direct_channels"], ssh_target=args.ssh_target)
        counts["direct_channels"] = len(direct_channel_ids)
        counts["direct_posts"] = count_direct_posts(args.database_url, direct_channel_ids, ssh_target=args.ssh_target)
        counts["emoji"] = count_imported_emoji(args.database_url, selectors["emoji"], ssh_target=args.ssh_target)
        counts["attachments"] = count_imported_attachments(
            args.database_url,
            selectors["channels"],
            direct_channel_ids,
            ssh_target=args.ssh_target,
        )
    except Exception as exc:
        errors.append(str(exc))

    if args.mattermost_url:
        try:
            ok, status_code = ping(args.mattermost_url)
            checks["ping"] = {"ok": ok, "status": status_code}
            if not ok:
                errors.append("mattermost system ping did not return 200")
        except Exception as exc:  # pragma: no cover - live service dependent
            checks["ping"] = {"ok": False, "error": str(exc)}
            errors.append(f"mattermost ping failed: {exc}")

    expected = handoff.get("counts", {})
    if not isinstance(expected, dict):
        errors.append("handoff counts must be an object")
        expected = {}
    for key in ("users", "channels", "posts", "direct_channels", "direct_posts", "emoji", "attachments"):
        try:
            expected_count = int(expected.get(key, 0))
        except (TypeError, ValueError):
            errors.append(f"handoff counts.{key} must be an integer")
            continue
        if expected_count > 0 and counts.get(key, 0) == 0:
            errors.append(f"observed {key} count is zero despite nonzero handoff expectation")

    payload = {
        "workspace": handoff.get("workspace", ""),
        "status": "passed" if not errors else "failed",
        "counts": counts,
        "selectors": {
            "teams": sorted(selectors.get("teams", set())),
            "users": sorted(selectors.get("users", set())),
            "channels": [list(item) for item in sorted(selectors.get("channels", set()))],
            "direct_channels": [list(item) for item in sorted(selectors.get("direct_channels", set()))],
            "emoji": sorted(selectors.get("emoji", set())),
        },
        "checks": checks,
        "errors": errors,
    }

    output_json = Path(args.output_json)
    output_json.parent.mkdir(parents=True, exist_ok=True)
    output_json.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {output_json}")

    if args.output_md:
        output_md = Path(args.output_md)
        lines = [
            "# Import Smoke Tests",
            "",
            f"- Workspace: `{payload['workspace']}`",
            f"- Status: `{payload['status']}`",
            "",
            "## Counts",
        ]
        lines.extend(f"- {key}: {value}" for key, value in counts.items())
        if errors:
            lines.extend(["", "## Errors"])
            lines.extend(f"- {error}" for error in errors)
        output_md.parent.mkdir(parents=True, exist_ok=True)
        output_md.write_text("\n".join(lines) + "\n", encoding="utf-8")
        print(f"wrote {output_md}")

    if errors:
        for error in errors:
            print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
