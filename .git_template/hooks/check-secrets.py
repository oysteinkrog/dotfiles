#!/usr/bin/env python3
"""Pre-commit secret guard.

Refuses to commit content containing any banned literal value, identified
only by SHA-256 so the banlist itself does not leak the values.

To add a new ban:
    python3 -c 'import hashlib,sys; s=sys.argv[1]; \
print(f"({len(s.encode())}, \"{hashlib.sha256(s.encode()).hexdigest()}\", \"<label>\"),")' \
        '<the-secret-value>'
and paste the resulting tuple into BANNED below.

Bypass once with `git commit --no-verify` only if you are absolutely sure
the match is a false positive — and then rotate the colliding secret if
there is any doubt.
"""
from __future__ import annotations

import hashlib
import subprocess
import sys

BANNED: list[tuple[int, str, str]] = [
    (13, "32568ece5a3127cc89f28257bda8c3d60375f0e3fc640c75d39df895d3e00b98", "proxy-domain"),
    (37, "853b5858f506ec297bf0baa634b1c2185f5845dbbadfd8d153b3acb81e0ddc3a", "proxy-key-v1"),
    (69, "da554d4f1e141ab7c0e048caa08ecca1bea7fd620eebd3eb928c250ce03d6186", "proxy-key-v2"),
]


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


def main() -> int:
    blob = staged_added_blob()
    if not blob:
        return 0
    hits: list[str] = []
    for length, digest, label in BANNED:
        if find_match(blob, length, digest) is not None:
            hits.append(label)
    if hits:
        sys.stderr.write(
            "pre-commit: refused — banned secret pattern(s) detected: "
            + ", ".join(hits) + "\n"
            "Remove the secret, then retry. Use --no-verify only if you are\n"
            "absolutely sure the match is a false positive.\n"
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
