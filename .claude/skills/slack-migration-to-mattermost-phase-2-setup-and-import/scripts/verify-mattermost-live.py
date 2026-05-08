#!/usr/bin/env python3
import argparse
import http.client
import json
from pathlib import Path
import socket
import ssl
import sys
from urllib.parse import urlparse


def connection_for_url(parsed, insecure: bool):
    if parsed.scheme == "https":
        context = ssl.create_default_context()
        if insecure:
            context.check_hostname = False
            context.verify_mode = ssl.CERT_NONE
        return http.client.HTTPSConnection(parsed.hostname, parsed.port or 443, timeout=10, context=context)
    return http.client.HTTPConnection(parsed.hostname, parsed.port or 80, timeout=10)


def endpoint_path(parsed, suffix: str) -> str:
    suffix = suffix if suffix.startswith("/") else f"/{suffix}"
    base_path = parsed.path.rstrip("/")
    return f"{base_path}{suffix}" if base_path else suffix


def http_ping(parsed, insecure: bool) -> tuple[bool, dict]:
    conn = connection_for_url(parsed, insecure)
    try:
        conn.request("GET", endpoint_path(parsed, "/api/v4/system/ping"))
        response = conn.getresponse()
        body = response.read().decode("utf-8", errors="replace")
        ok = response.status == 200
        return ok, {"status": response.status, "body": body[:500]}
    finally:
        conn.close()


def websocket_probe(parsed, websocket_path: str, insecure: bool) -> tuple[bool, dict]:
    conn = connection_for_url(parsed, insecure)
    headers = {
        "Connection": "Upgrade",
        "Upgrade": "websocket",
        "Sec-WebSocket-Key": "dGhlIHNhbXBsZSBub25jZQ==",
        "Sec-WebSocket-Version": "13",
        "Host": parsed.netloc,
    }
    try:
        conn.request("GET", endpoint_path(parsed, websocket_path), headers=headers)
        response = conn.getresponse()
        ok = response.status == 101
        return ok, {"status": response.status, "reason": response.reason}
    finally:
        conn.close()


def smtp_probe(host: str, port: int) -> tuple[bool, dict]:
    with socket.create_connection((host, port), timeout=10) as sock:
        banner = sock.recv(512).decode("utf-8", errors="replace")
        sock.sendall(b"EHLO mattermost-migration\r\n")
        ehlo = sock.recv(512).decode("utf-8", errors="replace")
    ok = banner.startswith("2") or "SMTP" in banner.upper() or ehlo.startswith("2")
    return ok, {"banner": banner[:200], "ehlo": ehlo[:200]}


def main() -> int:
    parser = argparse.ArgumentParser(description="Verify live Mattermost HTTP, WebSocket, and SMTP reachability.")
    parser.add_argument("--mattermost-url", required=True)
    parser.add_argument("--output-json", required=True)
    parser.add_argument("--output-md", default="")
    parser.add_argument("--websocket-path", default="/api/v4/websocket")
    parser.add_argument("--smtp-host", default="")
    parser.add_argument("--smtp-port", type=int, default=25)
    parser.add_argument("--retries", type=int, default=1)
    parser.add_argument("--retry-delay", type=float, default=0.0)
    parser.add_argument("--insecure", action="store_true")
    args = parser.parse_args()

    parsed = urlparse(args.mattermost_url)
    if parsed.scheme not in {"http", "https"} or not parsed.hostname:
        print(f"error: invalid Mattermost URL: {args.mattermost_url}", file=sys.stderr)
        return 1

    checks: dict[str, dict] = {}
    errors: list[str] = []

    attempts = max(args.retries, 1)
    for attempt in range(1, attempts + 1):
        errors = []
        checks = {}

        try:
            ok, details = http_ping(parsed, args.insecure)
            checks["http_ping"] = {"ok": ok, "attempt": attempt, **details}
            if not ok:
                errors.append("system ping did not return HTTP 200")
        except Exception as exc:  # pragma: no cover - network failures are environment-dependent
            checks["http_ping"] = {"ok": False, "attempt": attempt, "error": str(exc)}
            errors.append(f"http ping failed: {exc}")

        try:
            ok, details = websocket_probe(parsed, args.websocket_path, args.insecure)
            checks["websocket"] = {"ok": ok, "attempt": attempt, **details}
            if not ok:
                errors.append("websocket probe did not receive HTTP 101")
        except Exception as exc:  # pragma: no cover - network failures are environment-dependent
            checks["websocket"] = {"ok": False, "attempt": attempt, "error": str(exc)}
            errors.append(f"websocket probe failed: {exc}")

        if args.smtp_host:
            try:
                ok, details = smtp_probe(args.smtp_host, args.smtp_port)
                checks["smtp"] = {"ok": ok, "attempt": attempt, **details}
                if not ok:
                    errors.append("smtp probe did not receive an expected banner/ehlo")
            except Exception as exc:  # pragma: no cover - network failures are environment-dependent
                checks["smtp"] = {"ok": False, "attempt": attempt, "error": str(exc)}
                errors.append(f"smtp probe failed: {exc}")

        if not errors or attempt == attempts:
            break

        if args.retry_delay > 0:
            import time

            time.sleep(args.retry_delay)

    payload = {
        "mattermost_url": args.mattermost_url,
        "status": "passed" if not errors else "failed",
        "checks": checks,
        "errors": errors,
        "attempts": attempts,
    }

    output_json = Path(args.output_json)
    output_json.parent.mkdir(parents=True, exist_ok=True)
    output_json.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {output_json}")

    if args.output_md:
        output_md = Path(args.output_md)
        lines = [
            "# Live Stack Verification",
            "",
            f"- Mattermost URL: `{args.mattermost_url}`",
            f"- Status: `{payload['status']}`",
            "",
            "## Checks",
        ]
        for name, details in checks.items():
            lines.append(f"- {name}: ok={details.get('ok')}, details={json.dumps(details, sort_keys=True)}")
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
