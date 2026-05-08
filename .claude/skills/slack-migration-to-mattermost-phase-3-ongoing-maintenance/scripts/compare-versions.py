#!/usr/bin/env python3
"""compare-versions.py — compare current Mattermost version to an upgrade candidate.

Fetches the running version from the live Mattermost and the release notes
for the candidate version, summarizes the delta in agent-readable form.

Usage:
    ./compare-versions.py --target 10.11.3
    ./compare-versions.py --target 10.12.0 --out changelog.md
"""

import argparse
import json
import os
import re
import sys
from pathlib import Path
from urllib.request import Request, urlopen


def load_config() -> dict:
    script_dir = Path(__file__).resolve().parent
    config_path = Path(os.environ.get("CONFIG_PATH", script_dir.parent / "config.env"))
    cfg = {}
    if config_path.exists():
        for line in config_path.read_text().splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, _, v = line.partition("=")
            cfg[k.strip()] = v.strip().strip('"').strip("'")
    return cfg


def current_version(url: str) -> str:
    try:
        req = Request(f"{url}/api/v4/config/client?format=old", headers={"User-Agent": "phase3/1.0"})
        with urlopen(req, timeout=10) as r:
            body = r.read().decode("utf-8")
            m = re.search(r'"Version":"([^"]+)"', body)
            return m.group(1) if m else "unknown"
    except Exception as e:
        return f"unreachable ({e})"


def release_notes_url(version: str) -> str:
    # Mattermost publishes releases on GitHub
    return f"https://api.github.com/repos/mattermost/mattermost/releases/tags/v{version}"


def fetch_release_notes(version: str) -> dict | None:
    try:
        req = Request(release_notes_url(version), headers={
            "User-Agent": "phase3/1.0",
            "Accept": "application/vnd.github+json",
        })
        with urlopen(req, timeout=10) as r:
            return json.loads(r.read().decode("utf-8"))
    except Exception:
        return None


def classify_delta(cur: str, target: str) -> str:
    def parts(v):
        return [int(x) for x in re.findall(r"\d+", v)[:3]]
    try:
        a = parts(cur)
        b = parts(target)
    except Exception:
        return "unknown"
    while len(a) < 3:
        a.append(0)
    while len(b) < 3:
        b.append(0)
    if b[0] > a[0]:
        return "major"
    if b[1] > a[1]:
        return "minor"
    if b[2] > a[2]:
        return "patch"
    if b == a:
        return "same"
    return "downgrade"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--target", required=True, help="Candidate Mattermost version, e.g. 10.11.3")
    parser.add_argument("--out", default=None)
    args = parser.parse_args()

    cfg = load_config()
    url = cfg.get("MATTERMOST_URL", "")
    cur = current_version(url) if url else "unknown"
    delta = classify_delta(cur, args.target)

    notes = fetch_release_notes(args.target)
    notes_body = notes.get("body", "") if notes else "(GitHub API did not return release notes)"

    out_md = []
    out_md.append(f"# Mattermost version comparison\n")
    out_md.append(f"- Current: `{cur}`")
    out_md.append(f"- Target:  `{args.target}`")
    out_md.append(f"- Delta:   **{delta}**")
    out_md.append("")
    out_md.append("## Release notes (target)\n")
    out_md.append(notes_body[:4000])  # truncate for agent context
    if len(notes_body) > 4000:
        out_md.append("\n\n... (truncated)")

    text = "\n".join(out_md)
    print(text)

    if args.out:
        out_path = Path(args.out)
    else:
        # Anchor default output next to the skill dir so the file lands in a
        # predictable location regardless of the caller's cwd.
        skill_dir = Path(__file__).resolve().parent.parent
        out_path = skill_dir / "workdir-phase3" / "reports" / f"version-compare-{args.target}.md"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(text)
    print(f"\nMarkdown: {out_path}")
    # "same" is not a failure; it just means nothing to do. Downgrade remains an error.
    return 0 if delta in ("same", "patch", "minor", "major") else 1


if __name__ == "__main__":
    sys.exit(main())
