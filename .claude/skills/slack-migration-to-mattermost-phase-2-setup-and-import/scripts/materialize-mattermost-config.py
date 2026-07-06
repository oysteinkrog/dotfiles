#!/usr/bin/env python3
import argparse
import json
from pathlib import Path
import sys


def get_path(obj: dict, dotted: str):
    cur = obj
    for part in dotted.split("."):
        if not isinstance(cur, dict):
            return None
        cur = cur.get(part)
    return cur


def set_path(obj: dict, dotted: str, value) -> None:
    cur = obj
    parts = dotted.split(".")
    for part in parts[:-1]:
        if part not in cur or not isinstance(cur[part], dict):
            cur[part] = {}
        cur = cur[part]
    cur[parts[-1]] = value


def delete_path(obj: dict, dotted: str) -> None:
    cur = obj
    parts = dotted.split(".")
    for part in parts[:-1]:
        if not isinstance(cur, dict) or part not in cur:
            return
        cur = cur[part]
    if isinstance(cur, dict):
        cur.pop(parts[-1], None)


def main() -> int:
    parser = argparse.ArgumentParser(description="Render a Mattermost config.json tuned for Slack migration imports.")
    parser.add_argument("--output", required=True)
    parser.add_argument("--site-url", required=True)
    parser.add_argument("--listen-address", default="127.0.0.1:8065")
    parser.add_argument("--data-source", required=True)
    parser.add_argument("--existing-config", default="")
    parser.add_argument("--file-driver", default="local")
    parser.add_argument("--max-file-size", type=int, default=52428800)
    parser.add_argument("--max-post-size", type=int, default=16383)
    parser.add_argument("--open-server", action="store_true")
    parser.add_argument("--signup-enabled", action="store_true")
    parser.add_argument("--disable-email-verification", action="store_true")
    parser.add_argument("--enable-local-mode", action="store_true")
    parser.add_argument("--local-mode-socket", default="/var/tmp/mattermost_local.socket")
    parser.add_argument("--smtp-server", default="")
    parser.add_argument("--smtp-port", default="")
    parser.add_argument("--smtp-username", default="")
    parser.add_argument("--smtp-password", default="")
    parser.add_argument("--allow-origin", action="append", default=[])
    args = parser.parse_args()

    config: dict = {}
    if args.existing_config:
        existing_config = Path(args.existing_config)
        if not existing_config.exists():
            print(f"error: missing existing config: {existing_config}", file=sys.stderr)
            return 1
        try:
            config = json.loads(existing_config.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            print(f"error: invalid existing config json: {exc}", file=sys.stderr)
            return 1
        if not isinstance(config, dict):
            print(f"error: existing config root must be a JSON object: {existing_config}", file=sys.stderr)
            return 1

    delete_path(config, "ServiceSettings.EnableOpenServer")

    set_path(config, "ServiceSettings.SiteURL", args.site_url)
    set_path(config, "ServiceSettings.ListenAddress", args.listen_address)
    set_path(config, "ServiceSettings.MaxPostSize", args.max_post_size)
    set_path(config, "TeamSettings.EnableOpenServer", args.open_server)
    set_path(config, "ServiceSettings.EnableLocalMode", args.enable_local_mode)
    if args.enable_local_mode:
        set_path(config, "ServiceSettings.LocalModeSocketLocation", args.local_mode_socket)
    if args.allow_origin:
        set_path(config, "ServiceSettings.AllowCorsFrom", " ".join(args.allow_origin))

    set_path(config, "SqlSettings.DataSource", args.data_source)
    set_path(config, "FileSettings.DriverName", args.file_driver)
    set_path(config, "FileSettings.MaxFileSize", args.max_file_size)

    set_path(config, "EmailSettings.EnableSignUpWithEmail", args.signup_enabled)
    if args.disable_email_verification:
        set_path(config, "EmailSettings.RequireEmailVerification", False)
    if args.smtp_server:
        enable_smtp_auth = bool(args.smtp_username or args.smtp_password)
        set_path(config, "EmailSettings.SMTPServer", args.smtp_server)
        set_path(config, "EmailSettings.SMTPPort", args.smtp_port or "587")
        set_path(config, "EmailSettings.SMTPUsername", args.smtp_username)
        set_path(config, "EmailSettings.SMTPPassword", args.smtp_password)
        set_path(config, "EmailSettings.EnableSMTPAuth", enable_smtp_auth)
        set_path(config, "EmailSettings.SendEmailNotifications", True)

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
