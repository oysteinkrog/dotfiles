#!/usr/bin/env python3
"""mine-changelog.py — extract failure-mode candidates from a project's CHANGELOG.

Every "fix" entry in a CHANGELOG.md is a real past failure mode the doctor
should be able to detect. Phase 1 archaeology becomes much faster when this
runs first: agents start with N pre-suggested FMs instead of staring at a
blank inventory.

Usage:
  mine-changelog.py <target> [--workspace <ws>] [--limit N]

Inputs:
  <target>                — project root (must be readable directory)
  --workspace <ws>        — workspace directory; outputs go to <ws>/. Default: stdout.
  --limit N               — return at most N findings (default: 200).

Output:
  Newline-delimited JSON to <ws>/changelog_findings.jsonl (or stdout).
  One object per line:
    {"source_file": "CHANGELOG.md",
     "source_line": 42,
     "message": "Fix sqlite WAL sidecar drift on crash recovery",
     "kind": "bug-fix",
     "classified_subsystem": "state_files",
     "severity_hint": "P1",
     "candidate_fm_id": "fm-state-files-sqlite-wal-sidecar-drift"}

Exit codes:
  0 — success (output written; may be empty if no CHANGELOG found)
  64 — usage error (per IO-CONTRACTS.md)
  66 — target is not a directory
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import unicodedata
from pathlib import Path

# Subsystem classifier: maps regex patterns in the message to the canonical
# subsystem names declared in GLOSSARY.md. The keyword set is curated from
# the 21 /dp projects probed in round 54.
SUBSYSTEM_PATTERNS: list[tuple[str, list[str]]] = [
    ("state_files", [
        r"\bjsonl\b", r"\bsqlite\b", r"\bdb\b", r"\bdatabase\b",
        r"\bWAL\b", r"\bSHM\b", r"\bsidecar\b", r"\btombstone\b",
        r"\bstate\.json\b", r"\.beads", r"manifest\.json",
    ]),
    ("schemas", [
        r"\bschema[_-]version\b", r"\bmigration\b", r"\bmigrate\b",
        r"\bschema mismatch\b", r"\balembic\b", r"\bdiesel\b",
    ]),
    ("concurrency_primitives", [
        r"\block\b", r"\bflock\b", r"\bpidfile\b", r"\brace\b",
        r"\bdeadlock\b", r"\bTOCTOU\b", r"\bconcurrent\b",
    ]),
    ("caches", [
        r"\bcache\b", r"\b__pycache__\b", r"\btarget/\b", r"\bnode_modules\b",
        r"\bstale\b.*\b(cache|build)\b", r"\bbuild artifact\b",
    ]),
    ("configs", [
        r"\bconfig\b", r"\bsettings\.json\b", r"\.toml\b", r"\.yaml\b",
        r"\benv var\b", r"\benvironment variable\b", r"\bdotfile\b",
    ]),
    ("network", [
        r"\bDNS\b", r"\bTLS\b", r"\bHTTPS?\b", r"\bAPI\b", r"\btoken\b",
        r"\bauth\b", r"\bOAuth\b", r"\bcertificate\b",
    ]),
    ("userland_state", [
        r"~/\.[a-z]", r"\bXDG\b", r"\bhome dir\b", r"\b\$HOME\b",
        r"\bcredential\b", r"\bkeychain\b",
    ]),
]

# Kind classifier: which CHANGELOG entries are FM candidates vs feature work.
# Lines matching FIX_PATTERNS become candidates; FEATURE_PATTERNS skipped.
FIX_PATTERNS = [
    re.compile(r, re.IGNORECASE) for r in (
        r"^\s*[-*]\s*(fix|fixed|fixes|bug|bugfix|patch|repair|recover|"
        r"resolve|resolved|address(?:ed|es)?|correct(?:ed|s)?|"
        r"prevent(?:s|ed)?|guard|defend|robust|hardening|harden):?\b",
        r"^\s*[-*]\s*\bfix\(",  # conventional commit "fix(..."
    )
]
# Section headers (## Bug fixes, ## Hardening, etc.) are NOT treated as
# fixes themselves — they're sentinels that the following bullets are.
# We simply skip them; the bullets they introduce match FIX_PATTERNS above.
# This avoids generating low-quality `fm-unknown-bug-fixes` candidates from
# what is just a header line.

FEATURE_SKIP_PATTERNS = [
    re.compile(r, re.IGNORECASE) for r in (
        r"^\s*[-*]\s*(feat|feature|add|added|new|implement|introduce)\b",
        r"^\s*[-*]\s*\bdocs?\b:",
        r"^\s*[-*]\s*\bchore\b:",
        r"^\s*[-*]\s*\brefactor\b:",
        r"^\s*[-*]\s*\bperf\b:",
    )
]

# Severity hint: terms suggesting P0/P1 vs P2/P3.
SEVERITY_HINTS = [
    (re.compile(r"\b(critical|crash|corrupt|data loss|security|panic|segfault|undefined behavior)\b", re.I), "P0"),
    (re.compile(r"\b(production|outage|incident|deadlock|hang|wedge)\b", re.I), "P0"),
    (re.compile(r"\b(major|important|significant|recovery|TOCTOU)\b", re.I), "P1"),
    (re.compile(r"\b(minor|cosmetic|polish)\b", re.I), "P3"),
]
DEFAULT_SEVERITY = "P2"

# Filenames to scan, in priority order. First found wins (we don't merge
# CHANGELOG.md and CHANGES — that's a rare and confusing case).
CANDIDATE_FILES = [
    "CHANGELOG.md", "CHANGELOG", "CHANGELOG.rst", "CHANGELOG.txt",
    "CHANGES.md", "CHANGES", "HISTORY.md", "RELEASES.md", "NEWS.md",
]


def slugify(text: str, max_len: int = 60) -> str:
    """Build a deterministic, URL-safe slug from a free-text symptom."""
    # Normalize unicode (e.g., curly quotes).
    text = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode()
    # Lowercase, replace non-alnum with `-`, collapse repeats.
    text = re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")
    if len(text) > max_len:
        text = text[:max_len].rstrip("-")
    return text or "unknown"


def classify_subsystem(message: str) -> str:
    """Heuristic subsystem classifier; returns the first match or 'unknown'."""
    for subsystem, patterns in SUBSYSTEM_PATTERNS:
        for pat in patterns:
            if re.search(pat, message, re.IGNORECASE):
                return subsystem
    return "unknown"


def classify_severity(message: str) -> str:
    for pattern, sev in SEVERITY_HINTS:
        if pattern.search(message):
            return sev
    return DEFAULT_SEVERITY


def find_changelog(target: Path) -> Path | None:
    for name in CANDIDATE_FILES:
        candidate = target / name
        if candidate.is_file():
            return candidate
    return None


def is_fix_line(line: str) -> bool:
    if any(p.match(line) for p in FEATURE_SKIP_PATTERNS):
        return False
    return any(p.match(line) for p in FIX_PATTERNS)


def extract_message(line: str) -> str:
    """Strip leading bullet/marker and trailing whitespace; collapse internal."""
    # Remove leading "- ", "* ", "## ", optional category prefix, etc.
    stripped = re.sub(r"^\s*[-*#]+\s*", "", line)
    # Strip "fix:", "fix(scope):", "Fixed " prefixes.
    stripped = re.sub(
        r"^(fix|fixed|fixes|bug|bugfix|patch|repair|recover|resolve|resolved|"
        r"prevent|harden|hardening)(\([^)]+\))?\s*:\s*",
        "",
        stripped,
        flags=re.IGNORECASE,
    )
    return re.sub(r"\s+", " ", stripped).strip().rstrip(".")


def mine(target: Path, limit: int) -> list[dict]:
    changelog = find_changelog(target)
    if changelog is None:
        return []
    findings: list[dict] = []
    seen: set[str] = set()
    try:
        text = changelog.read_text(encoding="utf-8", errors="replace")
    except OSError as e:
        print(f"mine-changelog: cannot read {changelog}: {e}", file=sys.stderr)
        return []
    for line_no, raw_line in enumerate(text.splitlines(), start=1):
        if not is_fix_line(raw_line):
            continue
        message = extract_message(raw_line)
        if not message or len(message) < 6:
            continue
        # Dedupe by normalized message (collapse case/space).
        dedupe_key = re.sub(r"\s+", " ", message.lower()).strip()
        if dedupe_key in seen:
            continue
        seen.add(dedupe_key)
        subsystem = classify_subsystem(message)
        severity = classify_severity(message)
        slug = slugify(message, max_len=50)
        candidate_fm_id = f"fm-{subsystem}-{slug}"
        findings.append({
            "source_file": changelog.name,
            "source_line": line_no,
            "message": message,
            "kind": "bug-fix",
            "classified_subsystem": subsystem,
            "severity_hint": severity,
            "candidate_fm_id": candidate_fm_id,
        })
        if len(findings) >= limit:
            break
    return findings


class _UsageExitParser(argparse.ArgumentParser):
    """argparse subclass that exits 64 on usage errors (per IO-CONTRACTS.md)."""

    def error(self, message: str) -> "None":  # noqa: ANN001 (argparse signature)
        self.print_usage(sys.stderr)
        sys.stderr.write(f"{self.prog}: error: {message}\n")
        sys.exit(64)


def main() -> int:
    parser = _UsageExitParser(description=__doc__.splitlines()[0])
    parser.add_argument("target", help="project root")
    parser.add_argument("--workspace", default=None,
                        help="workspace dir; output goes to <ws>/changelog_findings.jsonl")
    parser.add_argument("--limit", type=int, default=200,
                        help="max findings to emit (default 200)")
    args = parser.parse_args()
    target = Path(args.target)
    if not target.is_dir():
        print(f"mine-changelog: {target} is not a directory", file=sys.stderr)
        return 66
    findings = mine(target, args.limit)
    out_lines = [json.dumps(f, ensure_ascii=False) for f in findings]
    if args.workspace:
        ws = Path(args.workspace)
        if not ws.is_dir():
            print(f"mine-changelog: workspace {ws} is not a directory", file=sys.stderr)
            return 66
        out_path = ws / "changelog_findings.jsonl"
        out_path.write_text("\n".join(out_lines) + ("\n" if out_lines else ""),
                            encoding="utf-8")
        print(f"mine-changelog: wrote {len(findings)} findings to {out_path}",
              file=sys.stderr)
    else:
        sys.stdout.write("\n".join(out_lines))
        if out_lines:
            sys.stdout.write("\n")
        sys.stdout.flush()
        print(f"mine-changelog: emitted {len(findings)} findings", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
