#!/usr/bin/env python3
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import stat
import sys

import requests


API_BASE = "https://api.cloudflare.com/client/v4"


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def cf_request(
    session: requests.Session,
    api_token: str,
    method: str,
    path: str,
    *,
    params: dict | None = None,
    payload: dict | None = None,
) -> dict:
    response = session.request(
        method,
        f"{API_BASE}{path}",
        headers={
            "Authorization": f"Bearer {api_token}",
            "Content-Type": "application/json",
        },
        params=params,
        json=payload,
        timeout=30,
    )
    response.raise_for_status()
    body = response.json()
    if not body.get("success", False):
        raise RuntimeError(json.dumps(body.get("errors", [])))
    return body


def write_secret_file(path: Path, contents: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(contents, encoding="utf-8")
    path.chmod(stat.S_IRUSR | stat.S_IWUSR)


def find_dns_record(session: requests.Session, api_token: str, zone_id: str, record_type: str, name: str) -> dict:
    body = cf_request(
        session,
        api_token,
        "GET",
        f"/zones/{zone_id}/dns_records",
        params={"type": record_type, "name": name},
    )
    for record in body.get("result", []):
        if record.get("type") == record_type and record.get("name") == name:
            return record
    return {}


def ensure_dns_record(
    session: requests.Session,
    api_token: str,
    zone_id: str,
    *,
    mode: str,
    record_type: str,
    name: str,
    content: str,
    proxied: bool,
    ttl: int = 1,
) -> dict:
    desired = {
        "type": record_type,
        "name": name,
        "content": content,
        "proxied": proxied,
        "ttl": ttl,
    }
    if mode == "plan":
        return {"status": "planned", "desired": desired}

    existing = find_dns_record(session, api_token, zone_id, record_type, name)
    if not existing:
        body = cf_request(
            session,
            api_token,
            "POST",
            f"/zones/{zone_id}/dns_records",
            payload=desired,
        )
        return {"status": "created", "desired": desired, "result": body.get("result", {})}

    changed = {
        key: value
        for key, value in desired.items()
        if existing.get(key) != value
    }
    if not changed:
        return {"status": "unchanged", "desired": desired, "result": existing}

    body = cf_request(
        session,
        api_token,
        "PATCH",
        f"/zones/{zone_id}/dns_records/{existing['id']}",
        payload=desired,
    )
    return {"status": "updated", "desired": desired, "result": body.get("result", {})}


def set_zone_setting(
    session: requests.Session,
    api_token: str,
    zone_id: str,
    *,
    mode: str,
    setting: str,
    value: str,
) -> dict:
    if mode == "plan":
        return {"status": "planned", "setting": setting, "value": value}
    body = cf_request(
        session,
        api_token,
        "PATCH",
        f"/zones/{zone_id}/settings/{setting}",
        payload={"value": value},
    )
    return {"status": "applied", "setting": setting, "value": value, "result": body.get("result", {})}


def issue_origin_certificate(
    session: requests.Session,
    api_token: str,
    *,
    hostnames: list[str],
    requested_validity: int,
) -> dict:
    body = cf_request(
        session,
        api_token,
        "POST",
        "/certificates",
        payload={
            "hostnames": hostnames,
            "requested_validity": requested_validity,
            "request_type": "origin-rsa",
        },
    )
    result = body.get("result", {})
    return {
        "id": result.get("id", ""),
        "certificate": result.get("certificate", ""),
        "private_key": result.get("private_key", ""),
        "expires_on": result.get("expires_on", ""),
        "hostnames": result.get("hostnames", hostnames),
    }


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Plan or apply Cloudflare DNS, TLS mode, HTTPS redirect, and Origin CA materialization."
    )
    parser.add_argument("--mode", choices=["plan", "apply"], default="plan")
    parser.add_argument("--api-token", default="")
    parser.add_argument("--zone-id", default="")
    parser.add_argument("--hostname", required=True)
    parser.add_argument("--origin-ip", required=True)
    parser.add_argument("--calls-hostname", default="")
    parser.add_argument("--calls-origin-ip", default="")
    parser.add_argument("--origin-hostname", action="append", default=[])
    parser.add_argument("--requested-validity-days", type=int, default=5475)
    parser.add_argument("--origin-cert-out", default="")
    parser.add_argument("--origin-key-out", default="")
    parser.add_argument("--ssl-mode", default="strict")
    parser.add_argument("--always-use-https", default="on")
    parser.add_argument("--websockets", default="on")
    parser.add_argument("--output-json", required=True)
    args = parser.parse_args()

    api_token = args.api_token or os.environ.get("CLOUDFLARE_API_TOKEN", "")
    zone_id = args.zone_id or os.environ.get("CF_ZONE_ID", "")

    if args.mode == "apply":
        if not api_token:
            print("error: Cloudflare API token is required for --mode apply", file=sys.stderr)
            return 1
        if not zone_id:
            print("error: Cloudflare zone id is required for --mode apply", file=sys.stderr)
            return 1

    errors: list[str] = []
    warnings: list[str] = []
    records: dict[str, dict] = {}
    settings: dict[str, dict] = {}
    certificate: dict[str, object] = {}

    session = requests.Session()

    try:
        records["chat"] = ensure_dns_record(
            session,
            api_token,
            zone_id,
            mode=args.mode,
            record_type="A",
            name=args.hostname,
            content=args.origin_ip,
            proxied=True,
        )
        if args.calls_hostname:
            records["calls"] = ensure_dns_record(
                session,
                api_token,
                zone_id,
                mode=args.mode,
                record_type="A",
                name=args.calls_hostname,
                content=args.calls_origin_ip or args.origin_ip,
                proxied=False,
            )
        settings["ssl"] = set_zone_setting(
            session,
            api_token,
            zone_id,
            mode=args.mode,
            setting="ssl",
            value=args.ssl_mode,
        )
        settings["always_use_https"] = set_zone_setting(
            session,
            api_token,
            zone_id,
            mode=args.mode,
            setting="always_use_https",
            value=args.always_use_https,
        )
        settings["websockets"] = set_zone_setting(
            session,
            api_token,
            zone_id,
            mode=args.mode,
            setting="websockets",
            value=args.websockets,
        )
    except requests.HTTPError as exc:
        errors.append(f"cloudflare api request failed: {exc}")
    except RuntimeError as exc:
        errors.append(f"cloudflare api returned an error: {exc}")

    desired_hostnames = args.origin_hostname[:] if args.origin_hostname else [args.hostname]
    if args.hostname not in desired_hostnames:
        desired_hostnames.insert(0, args.hostname)

    origin_cert_out = Path(args.origin_cert_out) if args.origin_cert_out else None
    origin_key_out = Path(args.origin_key_out) if args.origin_key_out else None
    if bool(origin_cert_out) != bool(origin_key_out):
        errors.append("origin cert and key outputs must be provided together")

    if origin_cert_out and origin_key_out:
        if origin_cert_out.exists() and origin_key_out.exists():
            certificate = {
                "status": "existing",
                "cert_path": str(origin_cert_out.resolve()),
                "key_path": str(origin_key_out.resolve()),
                "hostnames": desired_hostnames,
            }
        elif args.mode == "plan":
            certificate = {
                "status": "planned",
                "cert_path": str(origin_cert_out.resolve()),
                "key_path": str(origin_key_out.resolve()),
                "hostnames": desired_hostnames,
            }
        else:
            if not api_token:
                errors.append("cannot issue Origin CA certificate without API token")
            else:
                try:
                    issued = issue_origin_certificate(
                        session,
                        api_token,
                        hostnames=desired_hostnames,
                        requested_validity=args.requested_validity_days,
                    )
                    certificate = {
                        "status": "issued",
                        "id": issued.get("id", ""),
                        "expires_on": issued.get("expires_on", ""),
                        "hostnames": issued.get("hostnames", desired_hostnames),
                        "cert_path": str(origin_cert_out.resolve()),
                        "key_path": str(origin_key_out.resolve()),
                    }
                    write_secret_file(origin_cert_out, str(issued.get("certificate", "")))
                    write_secret_file(origin_key_out, str(issued.get("private_key", "")))
                except requests.HTTPError as exc:
                    errors.append(f"origin ca issuance failed: {exc}")
                except RuntimeError as exc:
                    errors.append(f"origin ca issuance returned an error: {exc}")

    if not args.calls_hostname:
        warnings.append("calls hostname not configured; Calls plugin DNS-only path is not provisioned")

    payload = {
        "generated_at": now_iso(),
        "status": "passed" if not errors else "failed",
        "mode": args.mode,
        "hostname": args.hostname,
        "origin_ip": args.origin_ip,
        "calls_hostname": args.calls_hostname,
        "calls_origin_ip": args.calls_origin_ip or args.origin_ip,
        "records": records,
        "settings": settings,
        "certificate": certificate,
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
