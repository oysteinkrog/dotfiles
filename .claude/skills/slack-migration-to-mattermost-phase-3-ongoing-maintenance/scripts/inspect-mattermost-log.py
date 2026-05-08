#!/usr/bin/env python3
"""inspect-mattermost-log.py — structured error-bucket report from Mattermost logs.

Reads /opt/mattermost/logs/mattermost.log on TARGET_HOST over an N-hour window,
groups errors by (msg prefix, level, plugin_id if present), and reports the
top-N buckets with counts and representative examples.

Usage:
    ./inspect-mattermost-log.py --window 1h
    ./inspect-mattermost-log.py --window 24h --min-count 10
"""

import argparse
import json
import os
import re
import subprocess
import sys
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone
from pathlib import Path


def parse_duration(s: str) -> timedelta:
    m = re.fullmatch(r"(\d+)([hm])", s)
    if not m:
        raise ValueError(f"bad duration: {s}")
    n, unit = int(m.group(1)), m.group(2)
    return timedelta(hours=n) if unit == "h" else timedelta(minutes=n)


def load_config() -> dict:
    script_dir = Path(__file__).resolve().parent
    config_path = Path(os.environ.get("CONFIG_PATH", script_dir.parent / "config.env"))
    if not config_path.exists():
        sys.exit(f"config.env not found at {config_path}")
    cfg = {}
    for line in config_path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, _, v = line.partition("=")
        cfg[k.strip()] = v.strip().strip('"').strip("'")
    return cfg


def fetch_logs(cfg: dict, window: timedelta) -> list[dict]:
    target = f"{cfg.get('TARGET_SSH_USER', 'deploy')}@{cfg['TARGET_HOST']}"
    ssh_opts = cfg.get("TARGET_SSH_OPTS", "-o BatchMode=yes -o ConnectTimeout=10")
    # Fetch the last N minutes of log content
    minutes = int(window.total_seconds() // 60)
    cmd = [
        "ssh", *ssh_opts.split(), target,
        f"sudo -n find /opt/mattermost/logs/mattermost.log -mmin -{minutes} -exec cat {{}} \\;"
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        sys.exit(f"ssh failed: {result.stderr}")
    records = []
    for line in result.stdout.splitlines():
        try:
            records.append(json.loads(line))
        except json.JSONDecodeError:
            continue  # Skip malformed lines
    return records


def bucket_key(rec: dict) -> tuple:
    level = rec.get("level", "")
    msg = rec.get("msg", "").strip()
    # Normalize: drop per-request IDs, IDs, timestamps within msg
    msg_norm = re.sub(r"[a-f0-9]{8,}", "<id>", msg)
    msg_norm = re.sub(r"\d{4,}", "<n>", msg_norm)
    # Truncate
    msg_norm = msg_norm[:120]
    plugin_id = rec.get("plugin_id", "")
    return (level, msg_norm, plugin_id)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--window", default="1h", help="e.g. 15m, 1h, 24h")
    parser.add_argument("--min-count", type=int, default=2)
    parser.add_argument("--top", type=int, default=20)
    parser.add_argument("--out", default=None)
    args = parser.parse_args()

    cfg = load_config()
    window = parse_duration(args.window)

    records = fetch_logs(cfg, window)
    level_totals = Counter(r.get("level", "") for r in records)
    error_records = [r for r in records if r.get("level") in ("error", "warn", "panic", "fatal")]
    buckets = defaultdict(list)
    for r in error_records:
        buckets[bucket_key(r)].append(r)

    sorted_buckets = sorted(
        ((k, v) for k, v in buckets.items() if len(v) >= args.min_count),
        key=lambda kv: -len(kv[1]),
    )[:args.top]

    report = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "window": args.window,
        "total_records": len(records),
        "level_totals": dict(level_totals),
        "error_bucket_count": len(buckets),
        "top_buckets": [
            {
                "count": len(v),
                "level": k[0],
                "msg_prefix": k[1],
                "plugin_id": k[2],
                "example": v[0],
            }
            for k, v in sorted_buckets
        ],
    }

    print(f"\n=== Mattermost log inspection ({args.window}) ===")
    print(f"Total records: {len(records)}")
    for level, count in level_totals.most_common():
        print(f"  {level:8s} {count}")
    print(f"\nTop {len(sorted_buckets)} error/warn buckets:")
    for k, v in sorted_buckets:
        level, msg, plugin = k
        plugin_tag = f" [{plugin}]" if plugin else ""
        print(f"  {len(v):4d}  {level:6s}{plugin_tag}  {msg}")

    out_path = args.out or f"workdir-phase3/reports/log-inspection-{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')}.json"
    Path(out_path).parent.mkdir(parents=True, exist_ok=True)
    Path(out_path).write_text(json.dumps(report, indent=2, default=str))
    print(f"\nJSON: {out_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
