#!/usr/bin/env python3
import argparse
from datetime import datetime, timedelta, timezone
import email
from email.header import decode_header, make_header
from email.parser import BytesParser
from email.policy import default as default_policy
import http.cookiejar
import imaplib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
from typing import Iterable
from urllib.parse import urljoin

import requests
from bs4 import BeautifulSoup


DEFAULT_READY_SUBJECT = "data is ready"
DEFAULT_READY_FROM = "feedback@slack.com"
URL_RE = re.compile(r"https?://[^\s<>\"]+")


def sha256_file(path: Path) -> str:
    import hashlib

    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def decode_mime_header(value: str) -> str:
    return str(make_header(decode_header(value or "")))


def build_session(cookie_jar: str, cookie_header: str) -> requests.Session:
    session = requests.Session()
    session.headers.update(
        {
            "User-Agent": (
                "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
                "(KHTML, like Gecko) Chrome/126.0 Safari/537.36"
            )
        }
    )
    if cookie_jar:
        jar = http.cookiejar.MozillaCookieJar()
        jar.load(cookie_jar, ignore_discard=True, ignore_expires=True)
        session.cookies.update(jar)
    if cookie_header:
        for token in cookie_header.split(";"):
            if "=" not in token:
                continue
            name, value = token.split("=", 1)
            session.cookies.set(name.strip(), value.strip())
    return session


def parse_key_value(items: list[str]) -> dict[str, str]:
    parsed: dict[str, str] = {}
    for item in items:
        if "=" not in item:
            raise ValueError(f"expected KEY=VALUE argument, got: {item}")
        key, value = item.split("=", 1)
        parsed[key.strip()] = value
    return parsed


def find_export_form(page_url: str, html: str) -> tuple[str, dict[str, str]]:
    soup = BeautifulSoup(html, "html.parser")
    for form in soup.find_all("form"):
        text = form.get_text(" ", strip=True).lower()
        if "export" not in text and "download" not in text:
            continue
        fields: dict[str, str] = {}
        for input_tag in form.find_all("input"):
            name = input_tag.get("name")
            if not name:
                continue
            fields[name] = input_tag.get("value", "")
        action = form.get("action") or page_url
        return urljoin(page_url, action), fields
    raise ValueError("could not identify an export form on the Slack admin export page")


def maybe_add_date_fields(fields: dict[str, str], start_date: str, end_date: str) -> None:
    if not start_date and not end_date:
        return
    for key in list(fields):
        lowered = key.lower()
        if start_date and any(marker in lowered for marker in ("start", "from")):
            fields[key] = start_date
        elif end_date and any(marker in lowered for marker in ("end", "to")):
            fields[key] = end_date


def trigger_export(session: requests.Session, args, evidence_dir: Path) -> dict:
    evidence_dir.mkdir(parents=True, exist_ok=True)
    trigger_info: dict[str, object] = {"mode": args.trigger_mode, "invoked_at": now_iso()}

    attempted_http = False
    if args.trigger_mode in {"auto", "http-form"} and args.export_page_url:
        attempted_http = True
        response = session.get(args.export_page_url, timeout=30)
        response.raise_for_status()
        snapshot_path = evidence_dir / "trigger-page.html"
        snapshot_path.write_text(response.text, encoding="utf-8")
        action_url, fields = find_export_form(args.export_page_url, response.text)
        maybe_add_date_fields(fields, args.start_date, args.end_date)
        fields.update(parse_key_value(args.trigger_field))
        post_response = session.post(action_url, data=fields, timeout=30)
        post_response.raise_for_status()
        result_path = evidence_dir / "trigger-response.html"
        result_path.write_text(post_response.text, encoding="utf-8")
        trigger_info.update(
            {
                "http_form": {
                    "page_url": args.export_page_url,
                    "action_url": action_url,
                    "status_code": post_response.status_code,
                    "snapshot_path": str(snapshot_path.resolve()),
                    "response_path": str(result_path.resolve()),
                }
            }
        )

    if args.trigger_command:
        proc = subprocess.run(
            args.trigger_command,
            shell=True,
            capture_output=True,
            text=True,
            check=False,
        )
        stdout_path = evidence_dir / "trigger.stdout.log"
        stderr_path = evidence_dir / "trigger.stderr.log"
        stdout_path.write_text(proc.stdout or "", encoding="utf-8")
        stderr_path.write_text(proc.stderr or "", encoding="utf-8")
        trigger_info["command"] = {
            "command": args.trigger_command,
            "returncode": proc.returncode,
            "stdout_path": str(stdout_path.resolve()),
            "stderr_path": str(stderr_path.resolve()),
        }
        if proc.returncode != 0:
            raise RuntimeError(f"trigger command failed with exit code {proc.returncode}")
    elif args.trigger_mode == "command-only":
        raise ValueError("--trigger-command is required for trigger-mode=command-only")
    elif args.trigger_mode == "http-form" and not attempted_http:
        raise ValueError("--export-page-url is required for trigger-mode=http-form")

    if args.trigger_mode == "skip":
        trigger_info["skipped"] = True

    return trigger_info


def extract_urls_from_message(message: email.message.EmailMessage) -> list[str]:
    urls: list[str] = []
    if message.is_multipart():
        for part in message.walk():
            if part.get_content_maintype() == "multipart":
                continue
            payload = part.get_payload(decode=True) or b""
            try:
                text = payload.decode(part.get_content_charset() or "utf-8", errors="replace")
            except LookupError:
                text = payload.decode("utf-8", errors="replace")
            urls.extend(URL_RE.findall(text))
    else:
        payload = message.get_payload(decode=True) or b""
        try:
            text = payload.decode(message.get_content_charset() or "utf-8", errors="replace")
        except LookupError:
            text = payload.decode("utf-8", errors="replace")
        urls.extend(URL_RE.findall(text))
    return urls


def save_attachment(part: email.message.EmailMessage, destination: Path) -> None:
    payload = part.get_payload(decode=True) or b""
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(payload)


def mailbox_messages_from_dir(mailbox_dir: Path) -> Iterable[tuple[Path, email.message.EmailMessage]]:
    for candidate in sorted(mailbox_dir.glob("*.eml")):
        yield candidate, BytesParser(policy=default_policy).parsebytes(candidate.read_bytes())


def message_matches(message: email.message.EmailMessage, args, started_at: datetime) -> bool:
    subject = decode_mime_header(message.get("Subject", ""))
    sender = decode_mime_header(message.get("From", ""))
    lowered_subject = subject.lower()
    lowered_sender = sender.lower()
    if args.ready_from and args.ready_from.lower() not in lowered_sender:
        return False
    if args.ready_subject and args.ready_subject.lower() not in lowered_subject:
        return False
    try:
        parsed_date = email.utils.parsedate_to_datetime(message.get("Date"))
    except Exception:
        parsed_date = None
    if parsed_date is not None:
        if parsed_date.tzinfo is None:
            parsed_date = parsed_date.replace(tzinfo=timezone.utc)
        if parsed_date < started_at - timedelta(days=1):
            return False
    return True


def find_ready_message(args, started_at: datetime, evidence_dir: Path) -> dict:
    evidence_dir.mkdir(parents=True, exist_ok=True)
    matched_message = None
    matched_source = ""
    downloaded_attachment_paths: dict[str, str] = {}
    urls: list[str] = []

    if args.mailbox_dir:
        mailbox_dir = Path(args.mailbox_dir)
        if not mailbox_dir.exists():
            raise FileNotFoundError(f"mailbox dir not found: {mailbox_dir}")
        for source_path, message in mailbox_messages_from_dir(mailbox_dir):
            if not message_matches(message, args, started_at):
                continue
            matched_message = message
            matched_source = str(source_path.resolve())
            break
    elif args.imap_host:
        mailbox = imaplib.IMAP4_SSL(args.imap_host, args.imap_port)
        try:
            mailbox.login(args.imap_username, args.imap_password)
            mailbox.select(args.imap_mailbox)
            status, data = mailbox.search(None, "ALL")
            if status != "OK":
                raise RuntimeError("imap search failed")
            for message_id in reversed(data[0].split()):
                status, fetched = mailbox.fetch(message_id, "(RFC822)")
                if status != "OK" or not fetched:
                    continue
                raw_message = fetched[0][1]
                if not isinstance(raw_message, bytes):
                    continue
                message = BytesParser(policy=default_policy).parsebytes(raw_message)
                if not message_matches(message, args, started_at):
                    continue
                matched_message = message
                matched_source = f"imap:{message_id.decode('utf-8', errors='replace')}"
                break
        finally:
            try:
                mailbox.logout()
            except Exception:
                pass

    if matched_message is None:
        raise TimeoutError("did not find a Slack export-ready mailbox message before timeout")

    urls = extract_urls_from_message(matched_message)
    attachments_dir = evidence_dir / "mailbox-attachments"
    for part in matched_message.walk():
        filename = part.get_filename()
        if not filename:
            continue
        decoded_filename = decode_mime_header(filename)
        lowered = decoded_filename.lower()
        if lowered.endswith(".csv"):
            target = attachments_dir / decoded_filename
            save_attachment(part, target)
            if "channel" in lowered and args.channel_audit_out:
                Path(args.channel_audit_out).parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(target, args.channel_audit_out)
                downloaded_attachment_paths["channel_audit"] = str(Path(args.channel_audit_out).resolve())
            elif ("member" in lowered or "user" in lowered) and args.member_csv_out:
                Path(args.member_csv_out).parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(target, args.member_csv_out)
                downloaded_attachment_paths["member_csv"] = str(Path(args.member_csv_out).resolve())

    metadata = {
        "source": matched_source,
        "subject": decode_mime_header(matched_message.get("Subject", "")),
        "from": decode_mime_header(matched_message.get("From", "")),
        "date": matched_message.get("Date", ""),
        "urls": urls,
        "csv_attachments": downloaded_attachment_paths,
    }
    metadata_path = evidence_dir / "matched-message.json"
    metadata_path.write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    return metadata


def mailbox_page_candidates(urls: list[str]) -> list[str]:
    ranked: list[tuple[int, str]] = []
    seen: set[str] = set()
    for url in urls:
        normalized = url.strip().rstrip(").,")
        if not normalized or normalized in seen:
            continue
        seen.add(normalized)
        lowered = normalized.lower()
        score = 0
        if lowered.endswith(".zip") or ".zip?" in lowered:
            score -= 10
        if lowered.endswith(".csv") or ".csv?" in lowered:
            score -= 8
        if "services/export" in lowered:
            score += 8
        if "export" in lowered:
            score += 4
        if "download" in lowered:
            score -= 2
        ranked.append((score, normalized))
    ranked.sort(key=lambda item: (-item[0], item[1]))
    return [url for _, url in ranked]


def classify_link(href: str, text: str) -> str:
    lowered = f"{href} {text}".lower()
    if lowered.endswith(".zip") or ".zip" in lowered:
        return "archive"
    if ".csv" in lowered and "channel" in lowered:
        return "channel_audit"
    if ".csv" in lowered and ("member" in lowered or "user" in lowered):
        return "member_csv"
    return ""


def discover_links(session: requests.Session, page_url: str, evidence_dir: Path) -> dict[str, str]:
    evidence_dir.mkdir(parents=True, exist_ok=True)
    response = session.get(page_url, timeout=30)
    response.raise_for_status()
    snapshot_path = evidence_dir / "export-page-latest.html"
    snapshot_path.write_text(response.text, encoding="utf-8")

    soup = BeautifulSoup(response.text, "html.parser")
    links: dict[str, str] = {}
    for anchor in soup.find_all("a"):
        href = anchor.get("href")
        if not href:
            continue
        kind = classify_link(href, anchor.get_text(" ", strip=True))
        if not kind or kind in links:
            continue
        links[kind] = urljoin(page_url, href)
    return links


def download_file(session: requests.Session, url: str, destination: Path) -> dict:
    destination.parent.mkdir(parents=True, exist_ok=True)
    with session.get(url, stream=True, timeout=120) as response:
        response.raise_for_status()
        with destination.open("wb") as handle:
            for chunk in response.iter_content(chunk_size=1024 * 1024):
                if chunk:
                    handle.write(chunk)
    return {
        "path": str(destination.resolve()),
        "sha256": sha256_file(destination),
        "bytes": destination.stat().st_size,
        "url": url,
    }


def intake_official_export(args, archive_path: Path, channel_audit_path: Path | None, member_csv_path: Path | None) -> None:
    script_path = Path(__file__).resolve().with_name("intake-official-export.py")
    cmd = [
        sys.executable,
        str(script_path),
        "--workspace",
        args.workspace,
        "--archive",
        str(archive_path),
        "--output-dir",
        args.output_dir,
        "--manifest-out",
        args.manifest_out,
        "--summary-out",
        args.summary_out,
        "--source-label",
        "official-export-automation",
    ]
    if channel_audit_path is not None and channel_audit_path.exists():
        cmd += ["--channel-audit-csv", str(channel_audit_path)]
    if member_csv_path is not None and member_csv_path.exists():
        cmd += ["--member-csv", str(member_csv_path)]
    subprocess.run(cmd, check=True)


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Trigger, poll, download, and intake an official Slack admin export with provenance capture."
    )
    parser.add_argument("--workspace", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--manifest-out", required=True)
    parser.add_argument("--summary-out", required=True)
    parser.add_argument("--provenance-out", required=True)
    parser.add_argument("--archive-out", default="")
    parser.add_argument("--channel-audit-out", default="")
    parser.add_argument("--member-csv-out", default="")
    parser.add_argument("--workspace-url", default="")
    parser.add_argument("--export-page-url", default="")
    parser.add_argument("--cookie-jar", default="")
    parser.add_argument("--cookie-header", default="")
    parser.add_argument("--trigger-mode", choices=["auto", "http-form", "command-only", "skip"], default="auto")
    parser.add_argument("--trigger-command", default="")
    parser.add_argument("--trigger-field", action="append", default=[])
    parser.add_argument("--start-date", default="")
    parser.add_argument("--end-date", default="")
    parser.add_argument("--imap-host", default="")
    parser.add_argument("--imap-port", type=int, default=993)
    parser.add_argument("--imap-username", default="")
    parser.add_argument("--imap-password", default="")
    parser.add_argument("--imap-mailbox", default="INBOX")
    parser.add_argument("--mailbox-dir", default="")
    parser.add_argument("--ready-from", default=DEFAULT_READY_FROM)
    parser.add_argument("--ready-subject", default=DEFAULT_READY_SUBJECT)
    parser.add_argument("--poll-interval-seconds", type=int, default=60)
    parser.add_argument("--timeout-seconds", type=int, default=3600)
    args = parser.parse_args()

    if not args.export_page_url and not args.workspace_url and args.trigger_mode != "skip":
        print(
            "error: either --export-page-url/--workspace-url or --trigger-mode=skip is required",
            file=sys.stderr,
        )
        return 1
    if not args.export_page_url and args.workspace_url:
        args.export_page_url = urljoin(args.workspace_url.rstrip("/") + "/", "services/export")
    if not args.archive_out:
        args.archive_out = str(Path(args.output_dir) / "slack-export.zip")
    if not args.channel_audit_out:
        args.channel_audit_out = str(Path(args.output_dir) / "channel-audit.csv")
    if not args.member_csv_out:
        args.member_csv_out = str(Path(args.output_dir) / "member-list.csv")
    if args.imap_host and (not args.imap_username or not args.imap_password):
        print("error: imap username/password are required when --imap-host is set", file=sys.stderr)
        return 1
    if args.imap_host and args.mailbox_dir:
        print("error: choose either --imap-host or --mailbox-dir, not both", file=sys.stderr)
        return 1

    output_dir = Path(args.output_dir)
    evidence_dir = output_dir / "automation-evidence"
    output_dir.mkdir(parents=True, exist_ok=True)
    evidence_dir.mkdir(parents=True, exist_ok=True)
    archive_path = Path(args.archive_out)
    channel_audit_path = Path(args.channel_audit_out)
    member_csv_path = Path(args.member_csv_out)
    started_at = datetime.now(timezone.utc)

    try:
        session = build_session(args.cookie_jar, args.cookie_header)
        trigger_info = trigger_export(session, args, evidence_dir / "trigger")
    except Exception as exc:
        print(f"error: failed to trigger official export: {exc}", file=sys.stderr)
        return 1

    links: dict[str, str] = {}
    mailbox_metadata: dict = {}
    mailbox_enabled = bool(args.imap_host or args.mailbox_dir)
    deadline = time.monotonic() + max(args.timeout_seconds, 1)
    while time.monotonic() < deadline:
        try:
            if mailbox_enabled and not mailbox_metadata:
                mailbox_metadata = find_ready_message(args, started_at, evidence_dir / "mailbox")
                for url in mailbox_metadata.get("urls", []):
                    if url.endswith(".zip") and "archive" not in links:
                        links["archive"] = url
            page_url = args.export_page_url
            if not page_url and mailbox_metadata.get("urls"):
                candidates = mailbox_page_candidates(list(mailbox_metadata["urls"]))
                page_url = candidates[0] if candidates else ""
            if page_url:
                discovered = discover_links(session, page_url, evidence_dir / "page")
                links.update({key: value for key, value in discovered.items() if value})
            if "archive" in links:
                break
        except TimeoutError:
            pass
        except Exception as exc:
            warning_path = evidence_dir / "poll-warning.log"
            with warning_path.open("a", encoding="utf-8") as handle:
                handle.write(f"{now_iso()} {exc}\n")
        time.sleep(max(args.poll_interval_seconds, 1))

    if "archive" not in links:
        print("error: export archive link never became available before timeout", file=sys.stderr)
        return 1

    downloaded: dict[str, dict] = {}
    try:
        downloaded["archive"] = download_file(session, links["archive"], archive_path)
        if "channel_audit" in links and not channel_audit_path.exists():
            downloaded["channel_audit"] = download_file(session, links["channel_audit"], channel_audit_path)
        elif channel_audit_path.exists():
            downloaded["channel_audit"] = {
                "path": str(channel_audit_path.resolve()),
                "sha256": sha256_file(channel_audit_path),
                "bytes": channel_audit_path.stat().st_size,
                "url": "mailbox-attachment",
            }
        if "member_csv" in links and not member_csv_path.exists():
            downloaded["member_csv"] = download_file(session, links["member_csv"], member_csv_path)
        elif member_csv_path.exists():
            downloaded["member_csv"] = {
                "path": str(member_csv_path.resolve()),
                "sha256": sha256_file(member_csv_path),
                "bytes": member_csv_path.stat().st_size,
                "url": "mailbox-attachment",
            }
    except Exception as exc:
        print(f"error: failed to download Slack export artifacts: {exc}", file=sys.stderr)
        return 1

    try:
        intake_official_export(args, archive_path, channel_audit_path if channel_audit_path.exists() else None, member_csv_path if member_csv_path.exists() else None)
    except subprocess.CalledProcessError as exc:
        print(f"error: intake-official-export.py failed with exit code {exc.returncode}", file=sys.stderr)
        return 1

    provenance = {
        "schema_version": 1,
        "generated_at": now_iso(),
        "workspace": args.workspace,
        "status": "completed",
        "trigger": trigger_info,
        "mailbox": mailbox_metadata,
        "links": links,
        "downloads": downloaded,
        "manifest_out": str(Path(args.manifest_out).resolve()),
        "summary_out": str(Path(args.summary_out).resolve()),
    }
    provenance_path = Path(args.provenance_out)
    provenance_path.parent.mkdir(parents=True, exist_ok=True)
    provenance_path.write_text(json.dumps(provenance, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {provenance_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
