#!/usr/bin/env python3
import argparse
import json
from pathlib import Path
import sys


def get_path(obj: dict, dotted: str):
    cur = obj
    for part in dotted.split("."):
        if not isinstance(cur, dict) or part not in cur:
            return None
        cur = cur[part]
    return cur


def normalize_allowed_origins(value) -> set[str]:
    if isinstance(value, str):
        tokens = value.replace(",", " ").split()
    elif isinstance(value, list):
        tokens = [str(item) for item in value]
    else:
        tokens = []
    return {token.strip() for token in tokens if str(token).strip()}


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate critical Mattermost config.json settings.")
    parser.add_argument("config")
    parser.add_argument("--expected-site-url", required=True)
    parser.add_argument("--expected-listen", default="127.0.0.1:8065")
    parser.add_argument("--allow-origin", action="append", default=[])
    parser.add_argument("--min-max-file-size", type=int, default=52428800)
    parser.add_argument("--min-max-post-size", type=int, default=16383)
    parser.add_argument("--require-open-server", action="store_true")
    parser.add_argument("--require-signup-enabled", action="store_true")
    parser.add_argument("--require-email-verification-disabled", action="store_true")
    parser.add_argument("--require-smtp", action="store_true")
    parser.add_argument("--output-json", default="")
    args = parser.parse_args()

    config_path = Path(args.config)
    try:
        config = json.loads(config_path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        print(f"error: config not found: {config_path}", file=sys.stderr)
        return 1
    except json.JSONDecodeError as exc:
        print(f"error: invalid JSON in {config_path}: {exc}", file=sys.stderr)
        return 1
    if not isinstance(config, dict):
        print(f"error: config root must be a JSON object: {config_path}", file=sys.stderr)
        return 1

    errors: list[str] = []
    warnings: list[str] = []

    site_url = get_path(config, "ServiceSettings.SiteURL")
    if site_url != args.expected_site_url:
        errors.append(f"SiteURL mismatch: expected {args.expected_site_url}, got {site_url}")

    listen = get_path(config, "ServiceSettings.ListenAddress")
    if listen != args.expected_listen:
        errors.append(f"ListenAddress mismatch: expected {args.expected_listen}, got {listen}")

    max_file_size = get_path(config, "FileSettings.MaxFileSize")
    if max_file_size is None:
        warnings.append(f"MaxFileSize is missing; expected at least {args.min_max_file_size}")
    else:
        try:
            if int(max_file_size) < args.min_max_file_size:
                warnings.append(
                    f"MaxFileSize is {max_file_size}; expected at least {args.min_max_file_size}"
                )
        except (TypeError, ValueError):
            warnings.append(
                f"MaxFileSize is not an integer value: {max_file_size!r}"
            )

    max_post_size = get_path(config, "ServiceSettings.MaxPostSize")
    if max_post_size is None:
        warnings.append(f"MaxPostSize is missing; expected at least {args.min_max_post_size}")
    else:
        try:
            if int(max_post_size) < args.min_max_post_size:
                errors.append(
                    f"MaxPostSize is {max_post_size}; expected at least {args.min_max_post_size}"
                )
        except (TypeError, ValueError):
            errors.append(f"MaxPostSize is not an integer value: {max_post_size!r}")

    signup = get_path(config, "EmailSettings.EnableSignUpWithEmail")
    if args.require_signup_enabled and signup is not True:
        errors.append("EnableSignUpWithEmail is not true")
    elif signup is not True:
        warnings.append("EnableSignUpWithEmail is not true")

    open_server = get_path(config, "TeamSettings.EnableOpenServer")
    if args.require_open_server and open_server is not True:
        errors.append("EnableOpenServer is not true")

    require_email_verification = get_path(config, "EmailSettings.RequireEmailVerification")
    if args.require_email_verification_disabled and require_email_verification is not False:
        errors.append("RequireEmailVerification must be false for migration activation flows")

    if args.require_smtp:
        smtp_server = get_path(config, "EmailSettings.SMTPServer")
        smtp_port = get_path(config, "EmailSettings.SMTPPort")
        smtp_username = get_path(config, "EmailSettings.SMTPUsername")
        smtp_password = get_path(config, "EmailSettings.SMTPPassword")
        smtp_auth_enabled = get_path(config, "EmailSettings.EnableSMTPAuth")

        smtp_required = {
            "SMTPServer": smtp_server,
            "SMTPPort": smtp_port,
        }
        for key, value in smtp_required.items():
            if not value:
                errors.append(f"Missing required SMTP setting: {key}")
        if smtp_auth_enabled is True or smtp_username or smtp_password:
            if not smtp_username:
                errors.append("Missing required SMTP setting: SMTPUsername")
            if not smtp_password:
                errors.append("Missing required SMTP setting: SMTPPassword")

    allowed = normalize_allowed_origins(get_path(config, "ServiceSettings.AllowCorsFrom"))
    for origin in args.allow_origin:
        if "*" not in allowed and origin not in allowed:
            errors.append(f"AllowCorsFrom missing trusted origin: {origin}")

    result = {
        "config": str(config_path),
        "expected_site_url": args.expected_site_url,
        "expected_listen": args.expected_listen,
        "errors": errors,
        "warnings": warnings,
        "status": "passed" if not errors else "failed",
    }

    if args.output_json:
        output_path = Path(args.output_json)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
        print(f"wrote {output_path}")

    for warning in warnings:
        print(f"warning: {warning}", file=sys.stderr)
    if errors:
        for error in errors:
            print(f"error: {error}", file=sys.stderr)
        return 1

    print("mattermost config validation passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
