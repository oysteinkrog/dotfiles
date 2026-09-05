#!/usr/bin/env python3
"""Cross-link integrity check for a gauntlet skill directory (or a subset of files).

Verifies every markdown link [text](path) points at an existing file. Skips
external URLs (http/https), mailto, anchors-only (#fragment), placeholders
(<...>, path/to/...), and absolute paths (home-expansion / Unix root).

Usage:
    check-cross-links.py                              # scan the running-the-gauntlet skill root
    check-cross-links.py path/to/skill/               # scan a specific skill root
    check-cross-links.py file1.md file2.md ...        # scan only specific files

Exit codes:
    0 = no broken links
    1 = at least one broken link (paths printed to stderr)
    2 = bad invocation
"""
from __future__ import annotations
import argparse
import re
import sys
from pathlib import Path

LINK_PATTERN = re.compile(r'\[[^\]]+\]\((?!https?://|mailto:|#|<)([^)]+)\)')

# Default skill root if no arguments given: derive from this script's own
# location so the checker works no matter where the skill is installed
# (`~/.claude/skills/...`, `~/.codex/skills/...`, a checkout under
# `/some/path/.claude/skills/...`, etc.). Falls back to `~/.claude/skills/...`
# if invoked via stdin or in a layout we can't resolve.
def _resolve_default_skill_root() -> Path:
    try:
        # scripts/check-cross-links.py → ../ is the skill root
        return Path(__file__).resolve().parent.parent
    except (NameError, OSError):
        return Path.home() / ".claude/skills/running-the-gauntlet-on-your-rust-port"


DEFAULT_SKILL_ROOT = _resolve_default_skill_root()


def is_external_or_placeholder(link: str) -> bool:
    """True if the link should be skipped (external, placeholder, home-rooted, etc.)."""
    if not link:
        return True
    if link.startswith("<"):
        return True  # angle-bracket placeholder, e.g., <workspace>
    if "<" in link:
        return True  # template variable inside the link
    if "path/to" in link:
        return True  # generic placeholder
    if link.startswith("~"):
        return True  # home-expansion; skip
    if link.startswith("/"):
        return True  # absolute path; can't validate from skill root
    return False


def check_file(md_path: Path) -> list[tuple[Path, str]]:
    """Return list of (source_file, broken_link) tuples."""
    broken: list[tuple[Path, str]] = []
    try:
        content = md_path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError) as exc:
        print(f"ERROR reading {md_path}: {exc}", file=sys.stderr)
        return broken

    base = md_path.parent
    for m in LINK_PATTERN.finditer(content):
        link = m.group(1).split("#", 1)[0].strip()
        if is_external_or_placeholder(link):
            continue
        target = (base / link).resolve()
        if not target.exists():
            broken.append((md_path, link))
    return broken


def collect_files(args: list[str]) -> list[Path]:
    """Return the list of markdown files to scan."""
    if not args:
        # Default: scan the running-the-gauntlet skill root.
        if DEFAULT_SKILL_ROOT.is_dir():
            return sorted(DEFAULT_SKILL_ROOT.rglob("*.md"))
        else:
            print(
                f"ERROR: default skill root {DEFAULT_SKILL_ROOT} not found; pass an argument",
                file=sys.stderr,
            )
            sys.exit(2)

    files: list[Path] = []
    for arg in args:
        p = Path(arg)
        if p.is_dir():
            files.extend(sorted(p.rglob("*.md")))
        elif p.is_file():
            if p.suffix.lower() == ".md":
                files.append(p)
            else:
                print(f"WARN: {p} is not a .md file; skipping", file=sys.stderr)
        else:
            print(f"ERROR: {p} does not exist", file=sys.stderr)
            sys.exit(2)
    return files


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Check markdown cross-link integrity.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument(
        "paths",
        nargs="*",
        help="Markdown files or directories to scan; defaults to the running-the-gauntlet skill root.",
    )
    parser.add_argument(
        "--verbose",
        "-v",
        action="store_true",
        help="Print per-file scan progress.",
    )
    args = parser.parse_args()

    files = collect_files(args.paths)
    if args.verbose:
        print(f"Scanning {len(files)} files...", file=sys.stderr)

    all_broken: list[tuple[Path, str]] = []
    for f in files:
        all_broken.extend(check_file(f))

    if all_broken:
        print(f"BROKEN LINKS: {len(all_broken)}", file=sys.stderr)
        for src, link in all_broken:
            print(f"  {src} -> {link}", file=sys.stderr)
        return 1
    else:
        if args.verbose:
            print(f"All {sum(1 for _ in files)} files clean.", file=sys.stderr)
        return 0


if __name__ == "__main__":
    sys.exit(main())
