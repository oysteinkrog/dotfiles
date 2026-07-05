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
   len(VALUE) >= MIN_DYNAMIC_LEN is automatically protected. No manual sync
   needed; adding/rotating a key in .env immediately updates protection.
   Values stay in memory only for the duration of the hook.

Bypass once with `git commit --no-verify` only if you are absolutely sure
the match is a false positive — and then rotate the colliding secret if
there is any doubt.
"""
from __future__ import annotations

import hashlib
import os
import subprocess
import sys
from pathlib import Path

BANNED: list[tuple[int, str, str]] = [
    (64, "ac1965cfe1837cc09d20afe8e3333fcc4019add4016c8bafd53347cc646ba07c", "mcp-agent-mail bearer token leaked in settings.json.bak (2026-07-05 audit)"),
    (13, "32568ece5a3127cc89f28257bda8c3d60375f0e3fc640c75d39df895d3e00b98", "proxy-domain"),
    (37, "853b5858f506ec297bf0baa634b1c2185f5845dbbadfd8d153b3acb81e0ddc3a", "proxy-key-v1"),
    (69, "da554d4f1e141ab7c0e048caa08ecca1bea7fd620eebd3eb928c250ce03d6186", "proxy-key-v2"),
]

ENV_FILE = Path.home() / ".config" / "secrets" / ".env"
MIN_DYNAMIC_LEN = 16  # below this, false-positive risk on substring search


def staged_added_blob() -> bytes:
    out = subprocess.run(
        ["git", "diff", "--cached", "--no-color", "-U0"],
        check=True, capture_output=True
    ).stdout
    parts: list[bytes] = []
    for line in out.split(b"\n"):
        if line.startswith(b"+") and not line.startswith(b"+++"):
            parts.append(line[1:])
    return b"\n".join(parts)


def find_match(blob: bytes, length: int, expected_hex: str) -> int | None:
    if len(blob) < length:
        return None
    for i in range(len(blob) - length + 1):
        if hashlib.sha256(blob[i:i + length]).hexdigest() == expected_hex:
            return i
    return None


def env_secrets(env_path: Path) -> list[tuple[bytes, str]]:
    """Return [(value_bytes, label), ...] for KEY=VALUE entries with
    len(VALUE) >= MIN_DYNAMIC_LEN. Returns [] if the file is missing."""
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
        val_b = val.encode("utf-8")
        if len(val_b) >= MIN_DYNAMIC_LEN:
            out.append((val_b, f"env:{key}"))
    return out


def main() -> int:
    blob = staged_added_blob()
    if not blob:
        return 0
    hits: list[str] = []
    for length, digest, label in BANNED:
        if find_match(blob, length, digest) is not None:
            hits.append(label)
    for val_b, label in env_secrets(ENV_FILE):
        if val_b in blob:
            hits.append(label)
    if hits:
        sys.stderr.write(
            "pre-commit: refused — banned secret value(s) detected in staged content: "
            + ", ".join(hits) + "\n"
            "Remove the secret, then retry. Use --no-verify only if you are\n"
            "absolutely sure the match is a false positive (and rotate the\n"
            "secret if there is any doubt).\n"
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
