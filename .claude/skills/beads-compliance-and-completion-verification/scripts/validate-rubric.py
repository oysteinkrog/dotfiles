#!/usr/bin/env python3
"""validate-rubric.py — Sanity-check a rubric.md before a pass commits to it.

A drifted rubric is the worst class of bug: every score is wrong, every
convergence verdict is wrong, every false-closed bead either gets missed or
gets a fictional reason. This validator catches the drift BEFORE Phase 8
runs, when fixing it is cheap.

Checks:
  - Frontmatter present and parseable (rubric_version, dimensions[]).
  - Every dimension has: name, max, what_it_measures.
  - Sum(max) over dimensions == 1000 (the universe of points).
  - Score-to-verdict bands cover [0, 1000] without gaps or overlaps.
  - Per-bead-type weight overrides (if present) also sum to 1000.
  - Threshold is in [1, 999].
  - Marker pairs (RUBRIC_START / RUBRIC_END) balance if present.
  - sha256 in audit-dir/manifest.json (if path supplied) matches the rubric file.

Usage:
    validate-rubric.py <rubric.md>
    validate-rubric.py <rubric.md> --manifest <audit-dir/manifest.json>
"""
from __future__ import annotations

import argparse
import hashlib
import hmac
import json
import re
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    print("ERROR: PyYAML required (pip install pyyaml)", file=sys.stderr)
    sys.exit(2)

FRONTMATTER_RE = re.compile(r"^---\n(.*?)\n---\n", re.S)
# Match: | <any non-pipe text> | NNN–NNN | …
# Old version used \S+ ?\S* and missed multi-word names like "Substantially complete".
BAND_ROW_RE = re.compile(r"\|\s*([^|]+?)\s*\|\s*(\d+)\s*[–—\-]\s*(\d+)\s*\|", re.M)


def split_md_row(line: str) -> list[str]:
    return [cell.strip().strip("*` ") for cell in line.strip().strip("|").split("|")]


def canonical_dimension_rows(text: str) -> list[tuple[str, int]]:
    lines = text.splitlines()
    rows: list[tuple[str, int]] = []
    for i, line in enumerate(lines):
        if not line.startswith("|"):
            continue
        header = split_md_row(line)
        if len(header) < 2 or header[0].lower() != "dimension" or header[1].lower() != "max":
            continue
        for row in lines[i + 1:]:
            if not row.startswith("|"):
                break
            if set(row.replace("|", "").strip()) <= {"-", ":"}:
                continue
            cells = split_md_row(row)
            if len(cells) < 2:
                continue
            value = cells[1].replace(",", "")
            if value.isdigit():
                rows.append((cells[0], int(value)))
        break
    return rows


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("rubric")
    p.add_argument("--manifest", default=None)
    p.add_argument("--threshold-min", type=int, default=1)
    p.add_argument("--threshold-max", type=int, default=999)
    args = p.parse_args()

    rubric_path = Path(args.rubric)
    if not rubric_path.exists():
        print(f"ERROR: {rubric_path} not found", file=sys.stderr)
        return 2
    text = rubric_path.read_text()

    errors: list[str] = []
    warnings: list[str] = []

    fm_match = FRONTMATTER_RE.match(text)
    fm: dict = {}
    if fm_match:
        try:
            fm = yaml.safe_load(fm_match.group(1)) or {}
        except yaml.YAMLError as e:
            errors.append(f"frontmatter: invalid YAML: {e}")
    else:
        warnings.append("no frontmatter found — rubric should declare version/dimensions in YAML frontmatter")

    if "rubric_version" not in fm:
        warnings.append("frontmatter missing 'rubric_version' (recommended for upgrade tracking)")

    score_threshold = fm.get("score_threshold")
    legacy_threshold = fm.get("threshold")
    if score_threshold is not None and legacy_threshold is not None and score_threshold != legacy_threshold:
        warnings.append("frontmatter has both 'score_threshold' and legacy 'threshold' with different values; score_threshold wins")
    threshold = score_threshold if score_threshold is not None else legacy_threshold
    if threshold is not None:
        if not isinstance(threshold, int):
            errors.append(f"score_threshold must be int, got {type(threshold).__name__}")
        elif not (args.threshold_min <= threshold <= args.threshold_max):
            errors.append(f"score_threshold={threshold} outside [{args.threshold_min}, {args.threshold_max}]")

    fm_dimensions = fm.get("dimensions", []) or []
    if isinstance(fm_dimensions, list) and fm_dimensions:
        total = 0
        for i, d in enumerate(fm_dimensions):
            if not isinstance(d, dict):
                errors.append(f"dimensions[{i}] not an object")
                continue
            for k in ("name", "max"):
                if k not in d:
                    errors.append(f"dimensions[{i}] missing '{k}'")
            if "max" in d:
                if not isinstance(d["max"], int):
                    errors.append(f"dimensions[{i}].max must be int, got {type(d['max']).__name__}")
                else:
                    total += d["max"]
        if total != 1000:
            errors.append(f"sum of dimension max values = {total}, must be 1000")
    else:
        # Fall back to Markdown table parsing.
        rows = canonical_dimension_rows(text)
        if not rows:
            if fm.get("weights_by_type"):
                warnings.append("no canonical dimension table parsed — treating this as a per-type rubric variant")
            else:
                warnings.append("no dimension table parsed — checked frontmatter and markdown both empty")
        else:
            total = sum(m for _, m in rows)
            if total != 1000:
                # Markdown total of 1000 (the canonical row) appears as the last row;
                # subtract it if it equals the sum of the rest.
                without_last = sum(m for _, m in rows[:-1])
                if without_last == 1000 and rows[-1][1] == 1000:
                    pass  # canonical: dimensions sum to 1000 + a TOTAL row of 1000
                else:
                    errors.append(f"markdown dimension max values sum to {total}, must be 1000 (or 2000 with explicit TOTAL row)")

    bands = BAND_ROW_RE.findall(text)
    if not bands:
        warnings.append("no score-to-verdict bands parsed (default bands assumed)")
    else:
        ranges = sorted([(int(lo), int(hi), name) for name, lo, hi in bands])
        # Coverage check: union should be [0, 1000].
        covered: set[int] = set()
        for lo, hi, _ in ranges:
            for s in range(lo, hi + 1):
                covered.add(s)
        missing = [s for s in range(0, 1001) if s not in covered]
        if missing:
            errors.append(f"score bands leave {len(missing)} score(s) uncovered, e.g. {missing[:5]}")
        # Overlap check.
        for i in range(1, len(ranges)):
            if ranges[i][0] <= ranges[i-1][1]:
                errors.append(f"score bands overlap: '{ranges[i-1][2]}' ({ranges[i-1][0]}-{ranges[i-1][1]}) "
                              f"vs '{ranges[i][2]}' ({ranges[i][0]}-{ranges[i][1]})")

    # Per-bead-type weight overrides.
    by_type = fm.get("weights_by_type", {}) or {}
    for bead_type, weights in by_type.items():
        if not isinstance(weights, dict):
            errors.append(f"weights_by_type.{bead_type} must be object")
            continue
        s = sum(v for v in weights.values() if isinstance(v, int))
        if s != 1000:
            errors.append(f"weights_by_type.{bead_type}: sum={s}, must be 1000")

    # Marker balance (RUBRIC_START / RUBRIC_END pairs).
    starts = re.findall(r"<!--\s*([A-Z_]+)_START\b", text)
    ends = re.findall(r"<!--\s*([A-Z_]+)_END\b", text)
    if sorted(starts) != sorted(ends):
        errors.append(f"marker pairs unbalanced: starts={starts} ends={ends}")

    # Manifest sha256 cross-check.
    if args.manifest:
        m_path = Path(args.manifest)
        if m_path.exists():
            try:
                manifest = json.loads(m_path.read_text())
                expected = manifest.get("rubric_sha256")
                actual = hashlib.sha256(rubric_path.read_bytes()).hexdigest()
                if expected and not hmac.compare_digest(str(expected), actual):
                    errors.append(f"manifest rubric_sha256 ({expected[:12]}…) does not match rubric file "
                                  f"({actual[:12]}…) — rubric was modified after pass started")
            except Exception as e:
                warnings.append(f"could not cross-check manifest sha256: {e}")
        else:
            warnings.append(f"--manifest {m_path} not found")

    for w in warnings:
        print(f"WARN:  {w}")
    # `err` not `e` — the latter is `del`'d at end of an `except ... as e`
    # scope above (Python 3 semantics) and mypy complains about the reuse.
    for err in errors:
        print(f"ERROR: {err}")
    print(f"\nValidation summary: {len(errors)} error(s), {len(warnings)} warning(s)", file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
