#!/usr/bin/env python3
"""
Claude Code User Manager
Manage multiple Claude Code accounts and switch between them.
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path


# Paths
CLAUDE_DIR = Path.home() / ".claude"
USERS_DIR = Path.home() / ".claude-users"
ACTIVE_FILE = USERS_DIR / "active_user.txt"

# Files to backup/restore for each user
AUTH_FILES = [".credentials.json", "credentials.json", "auth.json"]
SETTINGS_FILES = ["settings.json", "settings.local.json"]


def get_claude_auth_files() -> list[Path]:
    """Find existing auth-related files in Claude directory."""
    files = []
    if CLAUDE_DIR.exists():
        for pattern in AUTH_FILES:
            found = list(CLAUDE_DIR.glob(pattern))
            files.extend(found)
    return files


def get_token_info(user_dir: Path) -> dict:
    """Extract token/user info from credentials and settings files."""
    info = {}

    # Check for API key in settings.json
    settings_path = user_dir / "settings.json"
    if settings_path.exists():
        try:
            data = json.loads(settings_path.read_text())
            if isinstance(data, dict) and 'apiKeyHelper' in data:
                helper = data['apiKeyHelper']
                # Extract API key from "echo <KEY>" format
                if helper.startswith('echo '):
                    api_key = helper[5:].strip()
                    if len(api_key) > 16:
                        info['api_key'] = f"{api_key[:8]}...{api_key[-8:]}"
                    else:
                        info['api_key'] = api_key
                    info['type'] = 'api_key'
        except (json.JSONDecodeError, KeyError):
            pass

    # Check credential files for OAuth tokens
    for auth_file in AUTH_FILES:
        cred_path = user_dir / auth_file
        if cred_path.exists():
            try:
                data = json.loads(cred_path.read_text())

                # Try to extract useful identifiers
                if isinstance(data, dict):
                    # Check for common token/user fields
                    for key in ['email', 'user', 'account', 'accountId', 'user_id', 'userId']:
                        if key in data:
                            info['email'] = data[key]
                            break

                    # Extract token (show partial for identification)
                    for key in ['token', 'accessToken', 'access_token', 'claudeAiOauth']:
                        if key in data:
                            token = data[key]
                            if isinstance(token, str) and len(token) > 16:
                                info['token'] = f"{token[:8]}...{token[-8:]}"
                                info['type'] = 'oauth'
                            elif isinstance(token, dict):
                                # Handle nested token objects
                                for subkey in ['token', 'accessToken', 'access_token']:
                                    if subkey in token:
                                        t = token[subkey]
                                        if isinstance(t, str) and len(t) > 16:
                                            info['token'] = f"{t[:8]}...{t[-8:]}"
                                            info['type'] = 'oauth'
                                        break
                            break

                    # If no token found, just show we have credentials
                    if 'token' not in info and 'api_key' not in info and data:
                        info['has_creds'] = True
                        # Show first key's partial value as identifier
                        for k, v in data.items():
                            if isinstance(v, str) and len(v) > 16:
                                info['token'] = f"{v[:8]}...{v[-8:]}"
                                break

            except (json.JSONDecodeError, KeyError):
                pass

    return info


def ensure_dirs():
    """Create necessary directories."""
    USERS_DIR.mkdir(parents=True, exist_ok=True)


def get_active_user() -> str | None:
    """Get currently active user name."""
    if ACTIVE_FILE.exists():
        return ACTIVE_FILE.read_text().strip()
    return None


def set_active_user(name: str | None):
    """Set the active user name."""
    if name:
        ACTIVE_FILE.write_text(name)
    elif ACTIVE_FILE.exists():
        ACTIVE_FILE.unlink()


def list_users():
    """List all stored users."""
    ensure_dirs()
    active = get_active_user()

    users = [d.name for d in USERS_DIR.iterdir() if d.is_dir()]

    if not users:
        print("No users stored yet.")
        print("Use 'add <name>' to add a new user.")
        return

    print("Stored users:")
    for user in sorted(users):
        marker = " *" if user == active else "  "
        user_dir = USERS_DIR / user
        token_info = get_token_info(user_dir)

        # Build info string
        info_parts = []
        auth_type = token_info.get('type', '')
        if auth_type:
            info_parts.append(auth_type)
        if 'email' in token_info:
            info_parts.append(token_info['email'])
        if 'api_key' in token_info:
            info_parts.append(f"key: {token_info['api_key']}")
        elif 'token' in token_info:
            info_parts.append(f"token: {token_info['token']}")
        elif token_info.get('has_creds'):
            info_parts.append("(credentials present)")

        info_str = f" [{', '.join(info_parts)}]" if info_parts else ""
        print(f"{marker} {user}{info_str}")


def save_current_user(name: str):
    """Save current Claude credentials to a named slot."""
    ensure_dirs()
    user_dir = USERS_DIR / name

    if user_dir.exists():
        response = input(f"User '{name}' already exists. Overwrite? [y/N]: ")
        if response.lower() != 'y':
            print("Cancelled.")
            return False
        shutil.rmtree(user_dir)

    user_dir.mkdir(parents=True, exist_ok=True)

    # Copy all auth and settings files
    copied = []
    if CLAUDE_DIR.exists():
        for item in CLAUDE_DIR.iterdir():
            if item.is_file() and (item.name in AUTH_FILES or item.name in SETTINGS_FILES or item.suffix == '.json'):
                shutil.copy2(item, user_dir / item.name)
                copied.append(item.name)

    if copied:
        print(f"Saved user '{name}' ({len(copied)} files)")
        set_active_user(name)
        return True
    else:
        print("Warning: No credential files found to save.")
        user_dir.rmdir()
        return False


# Auth-specific keys in settings.json that should be swapped when switching users
AUTH_SETTINGS_KEYS = ['apiKeyHelper']


def switch_user(name: str):
    """Switch to a different stored user."""
    ensure_dirs()
    user_dir = USERS_DIR / name

    if not user_dir.exists():
        print(f"Error: User '{name}' not found.")
        print("Available users:")
        list_users()
        return False

    if not CLAUDE_DIR.exists():
        CLAUDE_DIR.mkdir(parents=True, exist_ok=True)

    # Clear current credential files
    for pattern in AUTH_FILES:
        for f in CLAUDE_DIR.glob(pattern):
            f.unlink()

    # Load current settings
    current_settings_path = CLAUDE_DIR / "settings.json"
    current_settings = {}
    if current_settings_path.exists():
        try:
            current_settings = json.loads(current_settings_path.read_text())
        except json.JSONDecodeError:
            pass

    # Remove auth keys from current settings
    for key in AUTH_SETTINGS_KEYS:
        current_settings.pop(key, None)

    # Restore user's files
    restored = []
    for item in user_dir.iterdir():
        if item.is_file():
            if item.name == "settings.json":
                # Only copy auth keys from user's settings
                try:
                    user_settings = json.loads(item.read_text())
                except json.JSONDecodeError:
                    user_settings = {}

                for key in AUTH_SETTINGS_KEYS:
                    if key in user_settings:
                        current_settings[key] = user_settings[key]
                        restored.append(f"settings.json:{key}")
            else:
                # Copy credential files directly
                shutil.copy2(item, CLAUDE_DIR / item.name)
                restored.append(item.name)

    # Write merged settings
    current_settings_path.write_text(json.dumps(current_settings, indent=2))

    set_active_user(name)
    print(f"Switched to user '{name}' ({', '.join(restored)})")
    return True


def add_new_user(name: str):
    """Logout, prompt for new login, and save as new user."""
    ensure_dirs()
    user_dir = USERS_DIR / name

    if user_dir.exists():
        response = input(f"User '{name}' already exists. Overwrite? [y/N]: ")
        if response.lower() != 'y':
            print("Cancelled.")
            return

    print(f"Adding new user: {name}")
    print("-" * 40)

    # Logout first
    print("Step 1: Logging out current user...")
    try:
        subprocess.run(["claude", "/logout"], check=False, capture_output=True)
    except FileNotFoundError:
        print("Warning: 'claude' command not found. Make sure Claude Code is installed.")

    # Clear auth files
    if CLAUDE_DIR.exists():
        for pattern in AUTH_FILES:
            for f in CLAUDE_DIR.glob(pattern):
                f.unlink()
                print(f"  Removed {f.name}")

    print("\nStep 2: Please log in with the new account...")
    print("Run: claude /login")
    print("-" * 40)

    input("Press Enter after you've logged in with the new account...")

    # Verify login worked
    auth_files = get_claude_auth_files()
    if not auth_files:
        print("Warning: No auth files detected. Login may have failed.")
        response = input("Save anyway? [y/N]: ")
        if response.lower() != 'y':
            print("Cancelled.")
            return

    # Save the new credentials
    if save_current_user(name):
        print(f"\nUser '{name}' added and activated!")


def add_api_key_user(name: str, api_key: str | None = None):
    """Add a new user with an API key."""
    ensure_dirs()
    user_dir = USERS_DIR / name

    if user_dir.exists():
        response = input(f"User '{name}' already exists. Overwrite? [y/N]: ")
        if response.lower() != 'y':
            print("Cancelled.")
            return

    # Get API key if not provided
    if not api_key:
        api_key = input("Enter API key: ").strip()
        if not api_key:
            print("Error: API key cannot be empty.")
            return

    # Validate API key format (basic check)
    if not api_key.startswith('sk-'):
        print("Warning: API key doesn't start with 'sk-'. Continuing anyway...")

    # Create user directory and settings.json
    user_dir.mkdir(parents=True, exist_ok=True)

    settings = {"apiKeyHelper": f"echo {api_key}"}
    settings_path = user_dir / "settings.json"
    settings_path.write_text(json.dumps(settings, indent=2))

    set_active_user(name)
    print(f"Added API key user '{name}'")

    # Ask if user wants to activate now
    response = input("Activate this user now? [Y/n]: ")
    if response.lower() != 'n':
        switch_user(name)


def remove_user(name: str):
    """Remove a stored user."""
    ensure_dirs()
    user_dir = USERS_DIR / name

    if not user_dir.exists():
        print(f"Error: User '{name}' not found.")
        return

    response = input(f"Remove user '{name}'? [y/N]: ")
    if response.lower() != 'y':
        print("Cancelled.")
        return

    shutil.rmtree(user_dir)

    if get_active_user() == name:
        set_active_user(None)

    print(f"Removed user '{name}'")


def rename_user(old_name: str, new_name: str):
    """Rename a stored user."""
    ensure_dirs()
    old_dir = USERS_DIR / old_name
    new_dir = USERS_DIR / new_name

    if not old_dir.exists():
        print(f"Error: User '{old_name}' not found.")
        return

    if new_dir.exists():
        print(f"Error: User '{new_name}' already exists.")
        return

    old_dir.rename(new_dir)

    # Update active user if renamed
    if get_active_user() == old_name:
        set_active_user(new_name)

    print(f"Renamed '{old_name}' to '{new_name}'")


def next_user():
    """Switch to the next user in the list (for quota rotation)."""
    ensure_dirs()

    users = sorted([d.name for d in USERS_DIR.iterdir() if d.is_dir()])
    if not users:
        print("No users stored. Use 'add <name>' first.")
        return

    active = get_active_user()

    if active and active in users:
        idx = users.index(active)
        next_idx = (idx + 1) % len(users)
    else:
        next_idx = 0

    next_name = users[next_idx]

    if next_name == active:
        print(f"Only one user stored: {next_name}")
    else:
        switch_user(next_name)


def status():
    """Show current status."""
    active = get_active_user()
    auth_files = get_claude_auth_files()

    print("Claude Code User Status")
    print("-" * 30)
    print(f"Active user: {active or '(none)'}")
    print(f"Auth files present: {len(auth_files)}")
    for f in auth_files:
        print(f"  - {f.name}")


def main():
    parser = argparse.ArgumentParser(
        description="Manage multiple Claude Code users",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s list              List all stored users
  %(prog)s add work          Add new OAuth user named 'work'
  %(prog)s addkey api1       Add new API key user named 'api1'
  %(prog)s switch personal   Switch to user 'personal'
  %(prog)s next              Switch to next user (quota rotation)
  %(prog)s save myname       Save current credentials as 'myname'
  %(prog)s remove olduser    Remove stored user
  %(prog)s rename old new    Rename a stored user
  %(prog)s status            Show current status
        """
    )

    subparsers = parser.add_subparsers(dest="command", help="Command to run")

    # list
    subparsers.add_parser("list", aliases=["ls"], help="List stored users")

    # add (OAuth)
    add_parser = subparsers.add_parser("add", aliases=["new"], help="Logout and add new OAuth user")
    add_parser.add_argument("name", help="Name for the new user")

    # addkey (API key)
    addkey_parser = subparsers.add_parser("addkey", aliases=["key", "apikey"], help="Add user with API key")
    addkey_parser.add_argument("name", help="Name for the new user")
    addkey_parser.add_argument("--key", "-k", help="API key (will prompt if not provided)")

    # switch
    switch_parser = subparsers.add_parser("switch", aliases=["sw", "use"], help="Switch to stored user")
    switch_parser.add_argument("name", help="User name to switch to")

    # save
    save_parser = subparsers.add_parser("save", help="Save current credentials to a slot")
    save_parser.add_argument("name", help="Name to save as")

    # remove
    remove_parser = subparsers.add_parser("remove", aliases=["rm", "delete"], help="Remove stored user")
    remove_parser.add_argument("name", help="User name to remove")

    # rename
    rename_parser = subparsers.add_parser("rename", aliases=["mv"], help="Rename stored user")
    rename_parser.add_argument("old_name", help="Current user name")
    rename_parser.add_argument("new_name", help="New user name")

    # next
    subparsers.add_parser("next", aliases=["n", "rotate"], help="Switch to next user (quota rotation)")

    # status
    subparsers.add_parser("status", aliases=["st"], help="Show current status")

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        return

    if args.command in ("list", "ls"):
        list_users()
    elif args.command in ("add", "new"):
        add_new_user(args.name)
    elif args.command in ("addkey", "key", "apikey"):
        add_api_key_user(args.name, getattr(args, 'key', None))
    elif args.command in ("switch", "sw", "use"):
        switch_user(args.name)
    elif args.command == "save":
        save_current_user(args.name)
    elif args.command in ("remove", "rm", "delete"):
        remove_user(args.name)
    elif args.command in ("rename", "mv"):
        rename_user(args.old_name, args.new_name)
    elif args.command in ("next", "n", "rotate"):
        next_user()
    elif args.command in ("status", "st"):
        status()


if __name__ == "__main__":
    main()
