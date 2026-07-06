#!/usr/bin/env python3
import argparse
import json
from pathlib import Path
import re
import sys


PATTERNS = {
    "slack_token": re.compile(r"xox[a-z]-[A-Za-z0-9-]+"),
    "mattermost_password_env": re.compile(r"(MATTERMOST_ADMIN_PASS\s*=\s*)(.+)"),
    "smtp_password_json": re.compile(r'("SMTPPassword"\s*:\s*")([^"]+)(")'),
    "s3_secret_json": re.compile(r'("AmazonS3SecretAccessKey"\s*:\s*")([^"]+)(")'),
    "generic_password_assignment": re.compile(r"((?:password|secret|token)\s*[:=]\s*)(\S+)", re.IGNORECASE),
}


def collect_files(paths: list[str]) -> list[Path]:
    files: list[Path] = []
    for raw_path in paths:
        path = Path(raw_path)
        if path.is_file():
            files.append(path)
        elif path.is_dir():
            files.extend(file_path for file_path in sorted(path.rglob("*")) if file_path.is_file())
    return files


def redact_text(text: str) -> tuple[str, list[dict[str, str]]]:
    findings: list[dict[str, str]] = []
    redacted = text
    for name, pattern in PATTERNS.items():
        updated = []

        def repl(match: re.Match) -> str:
            findings.append({"pattern": name, "match": match.group(0)[:120]})
            groups = match.groups()
            if len(groups) == 0:
                return "[REDACTED]"
            if len(groups) == 2:
                return f"{groups[0]}[REDACTED]"
            return f"{groups[0]}[REDACTED]{groups[-1]}"

        redacted = pattern.sub(repl, redacted)
    return redacted, findings


def main() -> int:
    parser = argparse.ArgumentParser(description="Scan migration notes/logs/configs for secret exposure and optionally write redacted copies.")
    parser.add_argument("--report-json", required=True)
    parser.add_argument("--output-dir", default="")
    parser.add_argument("paths", nargs="+")
    args = parser.parse_args()

    files = collect_files(args.paths)
    if not files:
        print("error: no files found to scan", file=sys.stderr)
        return 1

    findings_report = []
    output_dir = Path(args.output_dir) if args.output_dir else None

    for file_path in files:
        try:
            text = file_path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        redacted_text, findings = redact_text(text)
        if findings:
            findings_report.append(
                {
                    "path": str(file_path),
                    "findings": findings,
                }
            )
            if output_dir:
                try:
                    relative = file_path.resolve().relative_to(Path.cwd().resolve())
                    target = output_dir / relative
                except ValueError:
                    target = output_dir / file_path.name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text(redacted_text, encoding="utf-8")

    report = {
        "scanned_files": len(files),
        "files_with_findings": len(findings_report),
        "findings": findings_report,
        "output_dir": str(output_dir) if output_dir else "",
    }

    report_path = Path(args.report_json)
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {report_path}")

    if findings_report:
        print(f"warning: found potential secrets in {len(findings_report)} files", file=sys.stderr)
        return 1

    print("no secret-like findings detected")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
