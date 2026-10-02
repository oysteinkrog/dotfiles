#!/usr/bin/env python3
"""Pre-commit secret guard.

Two layers of protection:

1. Static banlist (BANNED): SHA-256 hashes of values that should never appear
   in any commit. The banlist itself does not leak the values. Used for
   secrets that aren't (or aren't anymore) in ~/.config/secrets/.env.

   To add a new static ban:
       python3 -c 'import hashlib,sys; s=sys.argv[1]; \
print(f"({len(s.encode())}, \"{hashlib.sha256(s.encode()).hexdigest()}\", \"<label>\"),")' \
           '<the-secret-value>'
   and paste the resulting tuple into BANNED below.

2. Dynamic banlist from ~/.config/secrets/.env: every KEY=VALUE with
   len(VALUE) >= MIN_DYNAMIC_LEN is automatically protected, except the keys
   listed in NOT_SECRET_KEYS. No manual sync needed; adding or rotating a key
   in .env immediately updates protection. Values stay in memory only for the
   duration of the hook.

Bypass once with `git commit --no-verify` only if you are absolutely sure
the match is a false positive, and then rotate the colliding secret if there
is any doubt.

Tests: python3 check-secrets.test.py
"""

from __future__ import annotations

import hashlib
import subprocess
import sys
from pathlib import Path

BANNED: list[tuple[int, str, str]] = [
    (
        64,
        "ac1965cfe1837cc09d20afe8e3333fcc4019add4016c8bafd53347cc646ba07c",
        "mcp-agent-mail bearer token leaked in settings.json.bak (2026-07-05 audit)",
    ),
    (
        13,
        "32568ece5a3127cc89f28257bda8c3d60375f0e3fc640c75d39df895d3e00b98",
        "proxy-domain",
    ),
    (
        37,
        "853b5858f506ec297bf0baa634b1c2185f5845dbbadfd8d153b3acb81e0ddc3a",
        "proxy-key-v1",
    ),
    (
        69,
        "da554d4f1e141ab7c0e048caa08ecca1bea7fd620eebd3eb928c250ce03d6186",
        "proxy-key-v2",
    ),
]

# Keys in .env whose values are configuration rather than credentials:
# hostnames, addresses, workspace and client identifiers, a wifi network name.
# They are long enough to pass MIN_DYNAMIC_LEN and they legitimately appear in
# committed content. Any Jira link in any document carries JIRA_SITE, and an
# author line carries JIRA_EMAIL.
#
# Protecting them cannot prevent a leak, because knowing one of these values
# grants nothing on its own. The paired token is what grants access, and the
# token stays protected. What protecting them does do is refuse ordinary
# commits, and each false refusal teaches the next person to reach for
# --no-verify, which is how a real secret gets through.
#
# Add a key here only when disclosing its value alone grants nothing.
NOT_SECRET_KEYS: frozenset[str] = frozenset(
    {
        "AIOLOS_OBSERVE_URL",
        "ANTHROPIC_BASE_URL",
        "GOOGLE_OAUTH_CLIENT_ID",
        "JIRA_EMAIL",
        "JIRA_SITE",
        "RPI_WIFI_SSID",
        "SLACK_TEAM_ID",
        "ZENDESK_EMAIL",
        "ZENDESK_SUBDOMAIN",
    }
)

ENV_FILE = Path.home() / ".config" / "secrets" / ".env"
MIN_DYNAMIC_LEN = 16  # below this, false-positive risk on substring search


def _git(args: list[str]) -> bytes:
    return subprocess.run(["git"] + args, check=True, capture_output=True).stdout


def merge_parents() -> list[str]:
    """The extra parents of an in-progress merge, or [] for a normal commit.

    `git diff --cached` compares the index against HEAD, which during a merge
    is the first parent only. Everything the other side contributed therefore
    reads as an added line, so a merge that brings in content already committed
    on the other branch would be refused for adding nothing.
    """
    try:
        git_dir = _git(["rev-parse", "--git-dir"]).decode().strip()
    except (subprocess.CalledProcessError, UnicodeDecodeError):
        return []
    try:
        text = (Path(git_dir) / "MERGE_HEAD").read_text(encoding="utf-8")
    except (FileNotFoundError, PermissionError, IsADirectoryError):
        return []
    return [line.strip() for line in text.splitlines() if line.strip()]


def added_lines(diff: bytes) -> list[bytes]:
    return [
        line[1:]
        for line in diff.split(b"\n")
        if line.startswith(b"+") and not line.startswith(b"+++")
    ]


def staged_added_blob() -> bytes:
    """The content this commit introduces, and nothing the repo already had.

    For a normal commit that is the staged diff against HEAD. For a merge it is
    the intersection of the staged diffs against every parent, so a line counts
    as added only when no side of the merge already had it.
    """
    added = added_lines(_git(["diff", "--cached", "--no-color", "-U0"]))
    for parent in merge_parents():
        try:
            other = added_lines(_git(["diff", "--cached", "--no-color", "-U0", parent]))
        except subprocess.CalledProcessError:
            # That parent cannot be read, so keep the stricter answer.
            continue
        keep = set(other)
        added = [line for line in added if line in keep]
    return b"\n".join(added)


def find_match(blob: bytes, length: int, expected_hex: str) -> int | None:
    if len(blob) < length:
        return None
    for i in range(len(blob) - length + 1):
        if hashlib.sha256(blob[i : i + length]).hexdigest() == expected_hex:
            return i
    return None


def env_secrets(env_path: Path) -> list[tuple[bytes, str]]:
    """Return [(value_bytes, label), ...] for KEY=VALUE entries with
    len(VALUE) >= MIN_DYNAMIC_LEN, skipping NOT_SECRET_KEYS. Returns [] if the
    file is missing."""
    try:
        data = env_path.read_text(encoding="utf-8")
    except (FileNotFoundError, PermissionError, IsADirectoryError):
        return []
    out: list[tuple[bytes, str]] = []
    for raw in data.splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, val = line.partition("=")
        key = key.strip()
        if key in NOT_SECRET_KEYS:
            continue
        val_b = val.encode("utf-8")
        if len(val_b) >= MIN_DYNAMIC_LEN:
            out.append((val_b, f"env:{key}"))
    return out


def scan(blob: bytes, dynamic: list[tuple[bytes, str]]) -> list[str]:
    hits: list[str] = []
    for length, digest, label in BANNED:
        if find_match(blob, length, digest) is not None:
            hits.append(label)
    for val_b, label in dynamic:
        if val_b in blob:
            hits.append(label)
    return hits


def main() -> int:
    blob = staged_added_blob()
    if not blob:
        return 0
    hits = scan(blob, env_secrets(ENV_FILE))
    if hits:
        sys.stderr.write(
            "pre-commit: refused. Banned secret value(s) detected in staged "
            "content: " + ", ".join(hits) + "\n"
            "Remove the secret, then retry. Use --no-verify only if you are\n"
            "absolutely sure the match is a false positive (and rotate the\n"
            "secret if there is any doubt).\n"
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
