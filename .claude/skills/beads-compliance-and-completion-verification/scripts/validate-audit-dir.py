#!/usr/bin/env python3
"""validate-audit-dir.py — Top-level integrity check for an audit directory.

Verifies the audit dir matches the contract declared in
references/AUDIT-DIRECTORY-LAYOUT.md and is safe to consume by downstream
scripts (master-report, dashboard, convergence-check, portfolio-rollup).

Checks:
  - Required top-level files present (manifest.json, rubric.md).
  - At least one passes/<UTC>/ subdir; each pass has manifest.json + REPORT.md
    (REPORT.md may be missing on aborted passes — warning, not error).
  - Pass timestamps are sortable ISO-format dirs.
  - manifest.json is valid JSON with required fields (audit_kind, threshold,
    rubric_sha256).
  - rubric_sha256 in audit-dir/manifest.json matches the rubric file.
  - .git directory exists and HEAD is not detached at a stale commit (warn if
    HEAD age > 90 days — could be a mothballed audit).
  - No stale tmp/__pycache__/.DS_Store crud at the top level.
  - Per-pass beads/<id>/ dirs each have spec.json AT MINIMUM (others may be
    skipped depending on mode).

Usage:
    validate-audit-dir.py <audit-dir>
    validate-audit-dir.py <audit-dir> --quiet
    validate-audit-dir.py <audit-dir> --strict
"""
from __future__ import annotations

import argparse
import hashlib
import hmac
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

# Pass-dir naming: canonical `YYYY-MM-DDTHH-MM-SSZ`, optionally followed by
# `_<4-hex>` collision-avoidance suffix appended by bootstrap-audit.sh when
# two passes start in the same UTC second.
PASS_DIR_RE = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}Z(?:_[0-9a-f]{4})?$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$", re.IGNORECASE)
TOP_LEVEL_REQUIRED = ["manifest.json", "rubric.md"]
TOP_LEVEL_EXPECTED = ["passes"]
# Field names match what bootstrap-audit.sh actually writes (and what
# assets/manifest-template.json declares). Do not invent names here — keep
# this list in sync with bootstrap-audit.sh's MANIFEST jq construction.
MANIFEST_REQUIRED = ["mode", "score_threshold", "audit_dir_version", "rubric_sha256"]
MANIFEST_RECOMMENDED = ["remediation_policy", "tools", "parallelism", "skill_version"]


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("audit_dir")
    p.add_argument("--strict", action="store_true")
    p.add_argument("--quiet", action="store_true")
    args = p.parse_args()

    root = Path(args.audit_dir).resolve()
    if not root.exists():
        print(f"ERROR: {root} not found", file=sys.stderr)
        return 2
    if not root.is_dir():
        print(f"ERROR: {root} not a directory", file=sys.stderr)
        return 2

    errors: list[str] = []
    warnings: list[str] = []

    for f in TOP_LEVEL_REQUIRED:
        if not (root / f).exists():
            errors.append(f"missing top-level required file: {f}")

    for d in TOP_LEVEL_EXPECTED:
        if not (root / d).exists():
            errors.append(f"missing top-level dir: {d}/")

    manifest_path = root / "manifest.json"
    manifest: dict = {}
    if manifest_path.exists():
        try:
            manifest = json.loads(manifest_path.read_text())
        except json.JSONDecodeError as e:
            errors.append(f"manifest.json: invalid JSON ({e})")
        for f in MANIFEST_REQUIRED:
            if f not in manifest:
                errors.append(f"manifest.json: missing required field '{f}'")
        for f in MANIFEST_RECOMMENDED:
            if f not in manifest:
                warnings.append(f"manifest.json: missing recommended field '{f}'")
        if "score_threshold" in manifest:
            t = manifest["score_threshold"]
            if not (isinstance(t, int) and 1 <= t <= 999):
                errors.append(f"manifest.json: score_threshold={t} not a valid score in [1,999]")

    rubric_path = root / "rubric.md"
    if rubric_path.exists() and "rubric_sha256" in manifest:
        actual = hashlib.sha256(rubric_path.read_bytes()).hexdigest()
        expected_raw = manifest["rubric_sha256"]
        if not isinstance(expected_raw, str) or not SHA256_RE.match(expected_raw):
            errors.append("manifest.json: rubric_sha256 must be a 64-character hex string")
        else:
            expected = expected_raw.lower()
            if not hmac.compare_digest(expected, actual):
                errors.append(f"rubric_sha256 in manifest does not match rubric.md "
                              f"(manifest={expected[:12]}… file={actual[:12]}…) — "
                              f"rubric was modified out-of-band")

    passes_dir = root / "passes"
    pass_dirs: list[Path] = []
    if passes_dir.exists():
        pass_dirs = sorted(d for d in passes_dir.iterdir() if d.is_dir())
        if not pass_dirs:
            warnings.append("passes/ is empty — no audit pass has run yet")
        for pd in pass_dirs:
            if not PASS_DIR_RE.match(pd.name):
                warnings.append(f"passes/{pd.name}: not in canonical UTC-timestamp format YYYY-MM-DDTHH-MM-SSZ")
            pmf = pd / "manifest.json"
            if not pmf.exists():
                errors.append(f"passes/{pd.name}: missing manifest.json")
            else:
                try:
                    json.loads(pmf.read_text())
                except json.JSONDecodeError as e:
                    errors.append(f"passes/{pd.name}/manifest.json: invalid JSON ({e})")
            if not (pd / "REPORT.md").exists():
                warnings.append(f"passes/{pd.name}: missing REPORT.md (aborted pass?)")
            beads_dir = pd / "beads"
            if not beads_dir.exists():
                warnings.append(f"passes/{pd.name}/beads/: missing — Phase 1 inventory failed?")
            else:
                empty = [bd for bd in beads_dir.iterdir() if bd.is_dir() and not (bd / "spec.json").exists()]
                if empty:
                    warnings.append(f"passes/{pd.name}: {len(empty)} bead(s) lack spec.json (Phase 2 incomplete)")

    git_dir = root / ".git"
    if not git_dir.exists():
        warnings.append("audit dir is not a git repo (history won't be tracked)")
    else:
        # Stale-HEAD probe: read .git/HEAD timestamp.
        head_log = git_dir / "logs/HEAD"
        if head_log.exists():
            mtime = datetime.fromtimestamp(head_log.stat().st_mtime, tz=timezone.utc)
            age_days = (datetime.now(timezone.utc) - mtime).days
            if age_days > 90:
                warnings.append(f"audit dir HEAD has not moved in {age_days} days — may be mothballed")

    crud = [".DS_Store", "Thumbs.db", "__pycache__", "tmp"]
    for c in crud:
        if (root / c).exists():
            warnings.append(f"unexpected file/dir at top level: {c}")

    if args.strict:
        errors.extend(warnings)
        warnings = []

    if not args.quiet or errors:
        for w in warnings:
            print(f"WARN:  {w}")
        # Use `err` not `e` — the name `e` was an exception alias above
        # (`except json.JSONDecodeError as e`) and is `del`'d at end of
        # except-scope per Python 3 semantics. Reusing `e` here works but
        # confuses static analyzers (mypy [misc]: "Trying to read deleted
        # variable 'e'").
        for err in errors:
            print(f"ERROR: {err}")

    summary = (f"audit_dir={root}, passes={len(pass_dirs)}, "
               f"errors={len(errors)}, warnings={len(warnings)}")
    print(f"\n{summary}", file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
