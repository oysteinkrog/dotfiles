#!/usr/bin/env python3
"""Output active Claude Code user for statusline."""

import json
from pathlib import Path

USERS_DIR = Path.home() / ".claude-users"
ACTIVE_FILE = USERS_DIR / "active_user.txt"
AUTH_FILES = [".credentials.json", "credentials.json", "auth.json"]


def main():
    if not ACTIVE_FILE.exists():
        print("no user")
        return

    name = ACTIVE_FILE.read_text().strip()
    if not name:
        print("no user")
        return

    user_dir = USERS_DIR / name
    if user_dir.exists():
        print(f"\U0001F511 {name}")  # key emoji
    else:
        print(f"? {name}")


if __name__ == "__main__":
    main()
