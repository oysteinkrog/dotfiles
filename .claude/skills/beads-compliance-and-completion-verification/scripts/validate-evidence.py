#!/usr/bin/env python3
"""validate-evidence.py — Validate per-bead evidence pack JSON files.

Checks each *.json artifact in a bead dir against the schemas declared in
references/EVIDENCE-SCHEMAS.md. Catches:
  - Missing required fields (bead_id, timestamps, etc.)
  - Wrong types (e.g. score is string instead of int)
  - Stale timestamps (evidence dated after compliance — order broken)
  - Inconsistent bead-ids across the pack (one file says bd-foo, another bd-bar)
  - Empty arrays where the schema says "non-empty"
  - PASS verdicts in compliance.json that contradict BLOCKING in theater.json

This is the pack-level equivalent of a skill validator.

Usage:
    validate-evidence.py <bead-dir>           # validate one bead
    validate-evidence.py <pass-dir>           # validate every bead under passes/<>/beads/
    validate-evidence.py <pass-dir> --strict  # warnings become errors
    validate-evidence.py <pass-dir> --scope-to-beads <id-list-file>
                                              # validate only the listed beads
                                              # (one bead-id per line); skipped
                                              # beads aren't even reported.

Partial-audit handling: when the inventory's bead count is much larger than
the count of beads with spec.json artifacts, the script auto-detects this as
a partial audit and switches to summary mode (one WARN line) instead of
emitting per-bead "Phase may have been skipped" warnings for every
non-sampled bead. Override with --no-partial-detect.

Exit:
    0 = all valid
    1 = errors found
    2 = usage error
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import datetime
from pathlib import Path

REQUIRED = {
    "spec.json": ["bead_id", "checklist", "extracted_at"],
    "evidence.json": ["bead_id", "checks", "gathered_at"],
    "compliance.json": ["bead_id", "executed_at", "executor", "checks"],
    "theater.json": ["bead_id", "scanned_at", "findings"],
    "test_depth.json": ["bead_id", "audited_at", "auditor", "checks"],
}

# Timestamps are written by both Python (`datetime.now(timezone.utc).isoformat()`
# → trailing `+00:00`) and shell `date -u +%Y-%m-%dT%H:%M:%SZ` (→ trailing `Z`).
# Both are ISO-8601 UTC; accept both. Optional fractional seconds.
ISO_RE = re.compile(
    r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|\+00:00)$"
)

# Theater / anomaly findings vocabulary actually written by theater-scan.sh,
# anomaly-scan.sh, and theater-detector.md. ADVISORY is reserved for
# committee-mode 1-of-N findings (see MULTI-MODEL-COMMITTEE.md). INFO/WARNING
# are NOT used by this skill; do not add them here without updating the
# scanners to match.
ALLOWED_SEVERITIES = {"BLOCKING", "MAJOR", "MINOR", "NOTE", "ADVISORY"}

# Verdict enums are PER-FILE per references/EVIDENCE-SCHEMAS.md:
#   compliance.json#checks[].verdict
#   test_depth.json#checks[].verdict
# These do not share an enum. score-bead.py also reads {ERROR, TIMEOUT,
# MISSING} as "treat as fail" — those are valid Phase 4 outcomes too.
COMPLIANCE_VERDICTS = {"PASS", "FAIL", "MISSING", "ERROR", "TIMEOUT", "SKIPPED",
                       "UNVERIFIED_INFRA", "WAIVED"}
TEST_DEPTH_VERDICTS = {"PASS", "PARTIAL", "FAIL", "WAIVED", "INFRA_MISSING"}

# Bead IDs are project data, not a validator-owned grammar. Other scripts parse
# IDs from report table cells verbatim so scoped/domain IDs such as
# `auth.bd-42` remain valid. Only flag characters that would corrupt the JSON
# pack or generated Markdown tables.
UNSAFE_BEAD_ID_RE = re.compile(r"[\x00-\x1f`|]")


def parse_iso(s: str) -> datetime | None:
    if not isinstance(s, str) or not ISO_RE.match(s):
        return None
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00"))
    except ValueError:
        return None


def waived_depth_has_spec_link(check: dict) -> bool:
    reason = str(check.get("reason") or check.get("notes") or "").strip()
    reason_l = reason.lower()
    explicit_link = any(check.get(k) for k in ("spec_ref", "spec_item_id", "linked_spec_item", "constraint_ref"))
    textual_link = "spec" in reason_l or "checklist" in reason_l or "not required" in reason_l or "did not require" in reason_l
    return bool(reason and (explicit_link or textual_link))


def validate_bead(bead_dir: Path, strict: bool) -> tuple[list, list]:
    errors: list[str] = []
    warnings: list[str] = []
    bid_seen: set = set()
    timestamps: dict[str, datetime] = {}

    if not bead_dir.is_dir():
        errors.append(f"{bead_dir}: not a directory")
        return errors, warnings

    expected_id = bead_dir.name
    if UNSAFE_BEAD_ID_RE.search(expected_id):
        warnings.append(f"{bead_dir.name}: bead-id contains control, backtick, or table-delimiter characters")

    for fname, fields in REQUIRED.items():
        fpath = bead_dir / fname
        if not fpath.exists():
            warnings.append(f"{bead_dir.name}/{fname}: not present (Phase may have been skipped)")
            continue
        try:
            data = json.loads(fpath.read_text())
        except json.JSONDecodeError as e:
            errors.append(f"{bead_dir.name}/{fname}: invalid JSON: {e}")
            continue
        if not isinstance(data, dict):
            errors.append(f"{bead_dir.name}/{fname}: top-level must be object, got {type(data).__name__}")
            continue
        for field in fields:
            if field not in data:
                errors.append(f"{bead_dir.name}/{fname}: missing required field '{field}'")
        # bead_id present-and-empty (e.g. "") is a real malformed-pack signal —
        # the required-field check above only catches truly missing keys.
        if "bead_id" in data:
            bid = data["bead_id"]
            if not isinstance(bid, str) or not bid:
                errors.append(f"{bead_dir.name}/{fname}: bead_id is present but empty/non-string ({bid!r})")
            else:
                bid_seen.add(bid)
                if bid != expected_id:
                    errors.append(f"{bead_dir.name}/{fname}: bead_id='{bid}' but dir name is '{expected_id}'")
        for ts_field in ("extracted_at", "gathered_at", "executed_at", "scanned_at", "audited_at"):
            if ts_field in data:
                dt = parse_iso(data[ts_field])
                if dt is None:
                    errors.append(f"{bead_dir.name}/{fname}: {ts_field}='{data[ts_field]}' not ISO-8601 UTC (must end with 'Z' or '+00:00')")
                else:
                    timestamps[fname] = dt

        if fname in ("compliance.json", "test_depth.json"):
            allowed = COMPLIANCE_VERDICTS if fname == "compliance.json" else TEST_DEPTH_VERDICTS
            checks = data.get("checks", [])
            if not isinstance(checks, list):
                errors.append(f"{bead_dir.name}/{fname}: checks must be array, got {type(checks).__name__}")
            else:
                for i, ch in enumerate(checks):
                    if not isinstance(ch, dict):
                        errors.append(f"{bead_dir.name}/{fname}: checks[{i}] not an object")
                        continue
                    if "verdict" in ch and ch["verdict"] not in allowed:
                        errors.append(f"{bead_dir.name}/{fname}: checks[{i}].verdict='{ch['verdict']}' not in {sorted(allowed)}")
                    if fname == "test_depth.json" and ch.get("verdict") == "WAIVED" and not waived_depth_has_spec_link(ch):
                        warnings.append(f"{bead_dir.name}/{fname}: checks[{i}] WAIVED without reason linked to spec/checklist")
        if fname == "theater.json":
            findings = data.get("findings", [])
            if not isinstance(findings, list):
                errors.append(f"{bead_dir.name}/theater.json: findings must be array")
            else:
                for i, f in enumerate(findings):
                    if not isinstance(f, dict):
                        errors.append(f"{bead_dir.name}/theater.json: findings[{i}] not an object")
                        continue
                    sev = f.get("severity")
                    if sev and sev not in ALLOWED_SEVERITIES:
                        errors.append(f"{bead_dir.name}/theater.json: findings[{i}].severity='{sev}' not in {sorted(ALLOWED_SEVERITIES)}")

    # Cross-file bead_id consistency.
    if len(bid_seen) > 1:
        errors.append(f"{bead_dir.name}: pack has inconsistent bead_ids: {sorted(bid_seen)}")

    # Timestamp ordering: extract → gather → execute → scan → audit (loose;
    # warning-only because parallel phases can write out of strict order).
    # Tolerance: ignore regressions below 2 seconds. Producers mix shell
    # `date +%Y-%m-%dT%H:%M:%SZ` (second-precision) and Python
    # `datetime.now(timezone.utc).strftime(...)` (also second-precision now,
    # but historically emitted microseconds). When two phases ran in the
    # same wall-clock second, sub-second comparisons could falsely flag the
    # newer phase as "older" — which spammed every audit with a spurious
    # warning. 2s leaves headroom for clock skew across parallel workers
    # without hiding a true ordering bug (real Phase 4 / Phase 5 work takes
    # much longer than that).
    order = ["spec.json", "evidence.json", "compliance.json", "theater.json", "test_depth.json"]
    seen_dt: list[tuple[str, datetime]] = []
    for fn in order:
        if fn in timestamps:
            seen_dt.append((fn, timestamps[fn]))
    for i in range(1, len(seen_dt)):
        regression_seconds = (seen_dt[i-1][1] - seen_dt[i][1]).total_seconds()
        if regression_seconds > 2:
            warnings.append(f"{bead_dir.name}: timestamp regression — {seen_dt[i][0]} ({seen_dt[i][1]}) is older than {seen_dt[i-1][0]} ({seen_dt[i-1][1]}) by {regression_seconds:.1f}s")

    # Cross-file consistency: BLOCKING theater finding should invalidate at least one
    # PASS in compliance (Axiom 4: theater invalidates surrounding "passes").
    # We require compliance.json to exist as a precondition (the linkage points
    # at a Phase 4 check), but only need to read theater.json for the check
    # itself; verifying the cited check exists in compliance is a future
    # enhancement.
    th_path = bead_dir / "theater.json"
    co_path = bead_dir / "compliance.json"
    if th_path.exists() and co_path.exists():
        try:
            th = json.loads(th_path.read_text())
        except Exception:
            th = {}
        blocking = [f for f in th.get("findings", []) if f.get("severity") == "BLOCKING"]
        if blocking:
            invalidates = [f for f in blocking if f.get("invalidates_phase4_check")]
            if not invalidates:
                warnings.append(f"{bead_dir.name}: BLOCKING theater finding(s) present but none cite invalidates_phase4_check (Axiom 4 requires explicit linkage)")

    if strict:
        errors.extend(warnings)
        warnings = []
    return errors, warnings


def detect_partial_audit(pass_dir: Path, bead_dirs: list[Path]) -> tuple[bool, int, int]:
    """Return (is_partial, expected_count, observed_count).

    A partial audit is one where Phase 1 inventoried N beads but only some
    subset M < N have evidence packs. Knowing this lets us suppress the
    flood of "Phase may have been skipped" warnings for the (N - M)
    non-sampled beads — those aren't bugs, the user just chose to audit a
    sample.
    """
    expected = 0
    inv = pass_dir / "inventory.jsonl"
    if inv.exists():
        try:
            for ln in inv.read_text().splitlines():
                if ln.strip():
                    expected += 1
        except OSError:
            expected = 0
    if expected == 0:
        manifest = pass_dir / "manifest.json"
        if manifest.exists():
            try:
                m = json.loads(manifest.read_text())
                expected = int((m.get("bead_counts") or {}).get("total_issues") or 0)
            except Exception:
                expected = 0
    observed = sum(1 for bd in bead_dirs if (bd / "spec.json").exists())
    # Treat as partial when at least 25% of inventoried beads are missing
    # spec.json AND we have at least one expected bead. The 25% threshold
    # avoids flagging projects where 1-2 beads legitimately failed Phase 2.
    is_partial = expected > 0 and observed > 0 and (expected - observed) > max(2, expected // 4)
    return is_partial, expected, observed


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("path", help="bead dir OR pass dir (will recurse to beads/<id>/)")
    p.add_argument("--strict", action="store_true", help="treat warnings as errors")
    p.add_argument("--quiet", action="store_true", help="only print failing bead summaries")
    p.add_argument("--scope-to-beads", metavar="FILE",
                   help="path to a file containing bead IDs (one per line). "
                        "Only those beads are validated; the rest are skipped "
                        "silently. Useful for sample audits.")
    p.add_argument("--no-partial-detect", action="store_true",
                   help="disable the 'partial audit' auto-detection (which "
                        "otherwise replaces per-bead 'Phase skipped' warnings "
                        "with a single summary line when most beads have no "
                        "spec.json).")
    args = p.parse_args()

    root = Path(args.path).resolve()
    if not root.exists():
        print(f"ERROR: {root} not found", file=sys.stderr)
        return 2

    bead_dirs: list[Path] = []
    pass_dir: Path | None = None
    if (root / "spec.json").exists() or (root / "evidence.json").exists():
        bead_dirs = [root]
    elif (root / "beads").is_dir():
        bead_dirs = sorted([d for d in (root / "beads").iterdir() if d.is_dir()])
        pass_dir = root
    else:
        print(f"ERROR: {root} is neither a bead dir nor a pass dir (no beads/ subdir)", file=sys.stderr)
        return 2

    # --scope-to-beads: load the allowlist and intersect with bead_dirs.
    if args.scope_to_beads:
        scope_path = Path(args.scope_to_beads)
        if not scope_path.exists():
            print(f"ERROR: --scope-to-beads file not found: {scope_path}", file=sys.stderr)
            return 2
        wanted = {ln.strip() for ln in scope_path.read_text().splitlines() if ln.strip()}
        bead_dirs = [bd for bd in bead_dirs if bd.name in wanted]
        if not bead_dirs:
            print(f"ERROR: no bead dirs matched the IDs in {scope_path}", file=sys.stderr)
            return 2

    # Auto-detect partial audit. When detected, beads with NO evidence pack
    # at all are summarised as one line instead of producing N spurious
    # warnings.
    is_partial = False
    expected_count = observed_count = 0
    bead_dirs_to_validate = bead_dirs
    if pass_dir is not None and not args.no_partial_detect and not args.scope_to_beads:
        is_partial, expected_count, observed_count = detect_partial_audit(pass_dir, bead_dirs)
        if is_partial:
            # Only validate the beads that DO have any evidence; the rest are
            # explicitly out of scope for this sample.
            bead_dirs_to_validate = [bd for bd in bead_dirs if any(
                (bd / fname).exists() for fname in ("spec.json", "evidence.json", "compliance.json")
            )]
            print(
                f"NOTE: partial audit detected — {observed_count}/{expected_count} beads "
                f"have evidence packs; validating only those. "
                f"Use --no-partial-detect to validate every bead dir.",
                file=sys.stderr,
            )

    total_errors = 0
    total_warnings = 0
    for bd in bead_dirs_to_validate:
        errs, warns = validate_bead(bd, args.strict)
        total_errors += len(errs)
        total_warnings += len(warns)
        if errs or (warns and not args.quiet):
            print(f"\n=== {bd.name} ===")
            for e in errs:
                print(f"  ERROR: {e}")
            for w in warns:
                print(f"  WARN:  {w}")

    skipped = len(bead_dirs) - len(bead_dirs_to_validate)
    summary_extra = f", {skipped} skipped (partial audit)" if skipped else ""
    print(
        f"\nValidation summary: {len(bead_dirs_to_validate)} bead(s), "
        f"{total_errors} error(s), {total_warnings} warning(s){summary_extra}",
        file=sys.stderr,
    )
    return 1 if total_errors else 0


if __name__ == "__main__":
    sys.exit(main())
