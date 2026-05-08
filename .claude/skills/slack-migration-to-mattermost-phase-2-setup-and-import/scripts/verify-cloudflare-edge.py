#!/usr/bin/env python3
import argparse
import hashlib
import http.client
import json
from pathlib import Path
import socket
import ssl
import sys
from urllib.parse import urlparse


def resolve_host(hostname: str) -> list[str]:
    addresses = {
        item[4][0]
        for item in socket.getaddrinfo(hostname, None, type=socket.SOCK_STREAM)
    }
    return sorted(addresses)


def http_ping(url: str) -> tuple[bool, dict]:
    parsed = urlparse(url)
    if parsed.scheme != "https":
        raise ValueError("edge verification expects an https URL")
    path = parsed.path.rstrip("/")
    endpoint = f"{path}/api/v4/system/ping" if path else "/api/v4/system/ping"
    conn = http.client.HTTPSConnection(parsed.hostname, parsed.port or 443, timeout=10)
    try:
        conn.request("GET", endpoint)
        response = conn.getresponse()
        body = response.read().decode("utf-8", errors="replace")
        ok = response.status == 200
        return ok, {"status": response.status, "body": body[:500]}
    finally:
        conn.close()


def origin_tls_probe(hostname: str, origin_ip: str, port: int) -> tuple[bool, dict, bytes]:
    context = ssl.create_default_context()
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    with socket.create_connection((origin_ip, port), timeout=10) as sock:
        with context.wrap_socket(sock, server_hostname=hostname) as wrapped:
            cert_der = wrapped.getpeercert(binary_form=True) or b""
            cipher = wrapped.cipher()
            version = wrapped.version()
    ok = bool(cert_der)
    details = {
        "cipher": cipher[0] if cipher else "",
        "tls_version": version or "",
        "fingerprint_sha256": hashlib.sha256(cert_der).hexdigest() if cert_der else "",
    }
    return ok, details, cert_der


def pem_fingerprint(cert_path: Path) -> str:
    pem_text = cert_path.read_text(encoding="utf-8")
    der = ssl.PEM_cert_to_DER_cert(pem_text)
    return hashlib.sha256(der).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Verify Cloudflare edge DNS resolution, edge HTTPS reachability, and direct origin TLS."
    )
    parser.add_argument("--hostname", required=True)
    parser.add_argument("--mattermost-url", default="")
    parser.add_argument("--origin-ip", required=True)
    parser.add_argument("--origin-port", type=int, default=443)
    parser.add_argument("--origin-cert-file", default="")
    parser.add_argument("--calls-hostname", default="")
    parser.add_argument("--calls-origin-ip", default="")
    parser.add_argument("--output-json", required=True)
    args = parser.parse_args()

    edge_url = args.mattermost_url or f"https://{args.hostname}"
    checks: dict[str, dict] = {}
    errors: list[str] = []
    warnings: list[str] = []

    try:
        resolved = resolve_host(args.hostname)
        proxied_ok = args.origin_ip not in resolved
        checks["dns"] = {
            "resolved_ips": resolved,
            "proxied_ok": proxied_ok,
            "origin_ip": args.origin_ip,
        }
        if not proxied_ok:
            errors.append("chat hostname resolves directly to the origin IP instead of Cloudflare edge")
    except Exception as exc:
        checks["dns"] = {"ok": False, "error": str(exc)}
        errors.append(f"dns resolution failed: {exc}")

    try:
        ok, details = http_ping(edge_url)
        checks["edge_http"] = {"ok": ok, **details}
        if not ok:
            errors.append("edge ping did not return HTTP 200")
    except Exception as exc:
        checks["edge_http"] = {"ok": False, "error": str(exc)}
        errors.append(f"edge ping failed: {exc}")

    try:
        ok, details, cert_der = origin_tls_probe(args.hostname, args.origin_ip, args.origin_port)
        checks["origin_tls"] = {"ok": ok, **details}
        if not ok:
            errors.append("origin TLS probe did not return a peer certificate")
        elif args.origin_cert_file:
            cert_path = Path(args.origin_cert_file)
            if not cert_path.exists():
                errors.append(f"origin cert file does not exist: {cert_path}")
            else:
                expected = pem_fingerprint(cert_path)
                checks["origin_tls"]["expected_fingerprint_sha256"] = expected
                if details["fingerprint_sha256"] != expected:
                    errors.append("origin TLS certificate fingerprint does not match local Origin CA certificate")
    except Exception as exc:
        checks["origin_tls"] = {"ok": False, "error": str(exc)}
        errors.append(f"origin TLS probe failed: {exc}")

    if args.calls_hostname:
        try:
            calls_resolved = resolve_host(args.calls_hostname)
            calls_expected_ip = args.calls_origin_ip or args.origin_ip
            direct_ok = calls_expected_ip in calls_resolved
            checks["calls_dns"] = {
                "resolved_ips": calls_resolved,
                "expected_origin_ip": calls_expected_ip,
                "dns_only_ok": direct_ok,
            }
            if not direct_ok:
                errors.append("calls hostname does not resolve directly to the expected origin IP")
        except Exception as exc:
            checks["calls_dns"] = {"ok": False, "error": str(exc)}
            errors.append(f"calls dns resolution failed: {exc}")
    else:
        warnings.append("calls hostname not supplied; Calls plugin DNS-only verification skipped")

    payload = {
        "status": "passed" if not errors else "failed",
        "hostname": args.hostname,
        "mattermost_url": edge_url,
        "origin_ip": args.origin_ip,
        "checks": checks,
        "warnings": warnings,
        "errors": errors,
    }

    output_path = Path(args.output_json)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {output_path}")

    for warning in warnings:
        print(f"warning: {warning}", file=sys.stderr)
    if errors:
        for error in errors:
            print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
