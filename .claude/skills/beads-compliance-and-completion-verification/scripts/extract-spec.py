#!/usr/bin/env python3
"""extract-spec.py — Phase 2: parse one bead body into spec.json checklist.

Usage:
    extract-spec.py <pass-dir>/beads/<bead-id>/show.json > spec.json

Reads the bead's full payload (description + design + acceptance_criteria + notes)
and emits a structured checklist conforming to references/EVIDENCE-SCHEMAS.md.

The parser is INTENTIONALLY simple — it extracts what's there literally, never
inventing requirements. Implicit-requirement injection by bead type is applied last.
"""
from __future__ import annotations

import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

# ---------- Patterns for literal extraction ----------

PATH_HINT_RE = re.compile(r"`([\w./_\-]+\.\w+|[\w./_\-]+/)`")
# Filter out tokens that LOOK like `name.ext` paths but are actually bead IDs
# (e.g. `br-1bm.1.1`, `bd-abc123.42`). The PATH_HINT_RE regex above happily eats
# them and gather-evidence.sh then literally globs the source tree for them,
# finding nothing — driving real implementations into the false-closed band.
# Discovered during audit pass 2026-05-09T00-49-33Z; tracked as bead br-14z5c.
BEAD_ID_RE = re.compile(r"^(?:br|bd|bv)-[a-z0-9]+(?:\.[0-9]+)*$", re.I)
TEST_TYPE_KEYWORDS = {
    "unit": [r"unit\s+test", r"unit-test"],
    "integration": [r"integration\s+test"],
    "e2e": [r"\be2e\b", r"end[- ]to[- ]end"],
    "fuzz": [r"\bfuzz", r"fuzz(er|ing|target)"],
    "property": [r"property[- ]based", r"proptest"],
    "metamorphic": [r"metamorphic"],
    "golden": [r"golden", r"snapshot test", r"insta"],
    "conformance": [r"conformance", r"compliance harness"],
}
DURATION_RE = re.compile(r"(\d+)\s*(s|sec|second|seconds|m|min|minute|minutes)\b", re.I)
COVERAGE_RE = re.compile(r"(\d+)\s*%\s*(line|branch)?\s*coverage", re.I)
NO_MOCKS_RE = re.compile(r"\bno\s*mocks?\b", re.I)
ALLOW_MOCK_RE = re.compile(r"mock\s+(allowed|ok)\s+for[: ]+([\w-]+)", re.I)
README_RE = re.compile(r"\b(README|readme|docs?/)", re.I)
MIGRATION_RE = re.compile(r"\bmigration|migrate\s+(schema|data)", re.I)
FEATURE_FLAG_RE = re.compile(r"feature\s*flag\s*[:=]?\s*([\w_-]+)", re.I)
TELEMETRY_RE = re.compile(r"\b(metric|gauge|histogram|counter|trace|span|log)\b", re.I)
CI_RE = re.compile(r"\.github/workflows/|gh\s+actions|github\s+actions", re.I)


def _now() -> str:
    # Second-precision matches what the shell scripts (gather-evidence.sh,
    # theater-scan.sh, anomaly-scan.sh, etc.) emit via `date -u
    # +%Y-%m-%dT%H:%M:%SZ`. Without normalising, Python's default
    # microsecond-bearing `.isoformat()` made spec.json look NEWER than
    # evidence.json by sub-second micros — producing a false-positive
    # "timestamp regression" warning from validate-evidence.py on every
    # pass.
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


# Bullet alternatives, ORDERED MOST-SPECIFIC FIRST. Python's regex alternation
# is left-to-right, so `- [x] foo` must be matched by `-\s*\[[ xX]\]\s+`
# BEFORE the looser `[-*+]\s+` would match just `- ` and leave `[x] foo`.
# Includes `+ [x]` and `* [x]` task-list variants as well.
_BULLET_PREFIX_RE = re.compile(
    r"^(?:[-*+]\s*\[[ xX]\]\s+|\[[ xX]\]\s+|[-*+]\s+|\d+[.)]\s+)"
)


def _split_acceptance_criteria(ac: str | None) -> list[dict[str, str]]:
    """ACs are usually bulleted. Extract each bullet verbatim, stripping ONLY the
    bullet marker (`- `, `* `, `+ `, `1. `, `1) `, `[ ] `, `- [x] `).
    Numeric content like '1.5x faster' inside the bullet is preserved.
    """
    if not ac:
        return []
    items: list[dict[str, str]] = []
    for i, line in enumerate(ac.splitlines()):
        stripped = line.strip()
        if not stripped:
            continue
        clean = _BULLET_PREFIX_RE.sub("", stripped)
        if clean:
            items.append({"id": f"ac.{len(items) + 1}", "verbatim": clean})
    return items


def _extract_code_artifacts(text: str, *, project_is_rust: bool = False) -> list[dict[str, Any]]:
    """Find file paths mentioned in backticks; treat as expected_path_hints.

    Filters (added 2026-05-09 per audit-infra bead br-14z5c):
    - Drop tokens matching ^(br|bd|bv)-... — bead IDs that look like `name.ext`
      to PATH_HINT_RE but are not real paths.
    - When project_is_rust is True, drop tokens ending in .py — these are
      Python-legacy filenames the bead is porting away from, not Rust files
      gather-evidence.sh should grep for.
    """
    raw_hints = set(PATH_HINT_RE.findall(text))
    filtered: set[str] = set()
    dropped: list[str] = []
    for h in raw_hints:
        if BEAD_ID_RE.match(h):
            dropped.append(h)
            continue
        if project_is_rust and h.lower().endswith(".py"):
            dropped.append(h)
            continue
        filtered.add(h)
    hints = sorted(filtered)
    if not hints:
        return []
    artifact: dict[str, Any] = {
        "id": "code.primary",
        "description": "Primary code artifact(s) named in bead body",
        "source_quote": "extracted from backtick-quoted paths in description/design",
        "expected_path_hints": hints,
        "weight": 2,
    }
    if dropped:
        artifact["dropped_hints"] = sorted(dropped)
        artifact["dropped_reason"] = "bead-id pattern or .py in Rust project (br-14z5c)"
    return [artifact]


def _extract_tests(text: str) -> dict[str, list[dict[str, Any]]]:
    out: dict[str, list[dict[str, Any]]] = {k: [] for k in TEST_TYPE_KEYWORDS}
    for ttype, patterns in TEST_TYPE_KEYWORDS.items():
        for pat in patterns:
            if re.search(pat, text, re.I):
                item: dict[str, Any] = {
                    "id": f"tests.{ttype}.primary",
                    "description": f"{ttype} test required by bead body",
                    "weight": 2 if ttype in ("e2e", "conformance") else 1,
                }
                if ttype == "fuzz":
                    dur = DURATION_RE.search(text)
                    if dur:
                        secs = int(dur.group(1))
                        if dur.group(2).lower().startswith("m"):
                            secs *= 60
                        item["duration_seconds"] = secs
                    item["ci_wired"] = bool(CI_RE.search(text))
                    item["no_crashes"] = True
                out[ttype].append(item)
                break
    return out


def _extract_constraints(text: str) -> dict[str, Any]:
    constraints: dict[str, Any] = {
        "no_mocks": bool(NO_MOCKS_RE.search(text)),
        "allowed_mocks": [m.group(2) for m in ALLOW_MOCK_RE.finditer(text)],
    }
    cov = COVERAGE_RE.search(text)
    if cov:
        threshold = int(cov.group(1)) / 100.0
        kind = (cov.group(2) or "line").lower()
        constraints[f"coverage_minimum_{kind}"] = threshold
    return constraints


def _extract_non_code(text: str) -> dict[str, list[dict[str, Any]]]:
    out: dict[str, list[dict[str, Any]]] = {
        "documentation": [],
        "migrations": [],
        "feature_flags": [],
        "telemetry": [],
        "ci_workflows": [],
    }
    if README_RE.search(text):
        out["documentation"].append({"id": "docs.readme", "description": "README update referenced in bead"})
    if MIGRATION_RE.search(text):
        out["migrations"].append({"id": "migrations.primary", "description": "Migration referenced in bead"})
    for m in FEATURE_FLAG_RE.finditer(text):
        out["feature_flags"].append({"id": f"flag.{m.group(1)}", "name": m.group(1)})
    if TELEMETRY_RE.search(text):
        out["telemetry"].append({"id": "telemetry.primary", "description": "Telemetry referenced in bead"})
    if CI_RE.search(text):
        out["ci_workflows"].append({"id": "ci.workflow", "description": "CI workflow referenced in bead"})
    return out


def _implicit_requirements(bead_type: str) -> list[dict[str, str]]:
    rules = {
        "feature": [{"id": "implicit.feature.happy_path_test", "description": "Feature beads need at least one happy-path test", "added_because": "bead_type=feature"}],
        "bug": [{"id": "implicit.bug.regression_test", "description": "Bug beads need a regression test that would have caught the bug", "added_because": "bead_type=bug"}],
        "epic": [{"id": "implicit.epic.children_closed", "description": "Epic is closed only if every child bead is closed and pass-grade", "added_because": "bead_type=epic"}],
        "docs": [{"id": "implicit.docs.file_exists", "description": "Doc file must exist and be reachable", "added_because": "bead_type=docs"}],
    }
    return rules.get(bead_type, [])


def _detect_project_is_rust(show_path: Path) -> bool:
    """Walk up from <pass-dir>/beads/<id>/show.json to find audit-dir manifest.json,
    read project_path, then check for Cargo.toml. Returns False on any failure
    (the path-hint filter is purely additive, so a False answer just means the
    .py filter is skipped — no harm done). Added per bead br-14z5c.
    """
    try:
        # show.json -> beads/<id>/show.json -> passes/<UTC>/ -> passes/ -> <audit-dir>
        audit_dir = show_path.parent.parent.parent.parent
        manifest = audit_dir / "manifest.json"
        if not manifest.is_file():
            return False
        data = json.loads(manifest.read_text())
        project_path = data.get("project_path")
        if not project_path:
            return False
        return (Path(project_path) / "Cargo.toml").is_file()
    except Exception:
        return False


def extract(show: dict[str, Any], *, project_is_rust: bool = False) -> dict[str, Any]:
    bead_id = show.get("id", "unknown")
    bead_type = show.get("issue_type", "task")
    if isinstance(bead_type, dict):
        bead_type = next(iter(bead_type.values()), "task")
    bead_type = str(bead_type).lower()
    # `close_reason` is included in the body the extractor scans because many
    # projects use it as the canonical "what got done" field — often citing
    # commit SHAs and file paths the description omits. The extractor's
    # heuristics (PATH_HINT_RE, TEST_TYPE_KEYWORDS, etc.) will pick those up
    # so the spec checklist reflects what the closer actually claimed,
    # regardless of which field they wrote it in. Without this, beads with
    # rich close_reason and thin description used to look spec-empty to the
    # downstream phases — falsely amplifying the "Phase 3 missing evidence"
    # signal even though the closer DID cite their work.
    body_parts = [
        show.get("title") or "",
        show.get("description") or "",
        show.get("design") or "",
        show.get("acceptance_criteria") or "",
        show.get("notes") or "",
        show.get("close_reason") or "",
    ]
    text = "\n\n".join(p for p in body_parts if p)

    coverage_gaps: list[str] = []
    if not text.strip():
        coverage_gaps.append("bead body is empty; cannot verify against any spec")
    elif len(text) < 200 and not show.get("acceptance_criteria") and not show.get("close_reason"):
        coverage_gaps.append("bead body is very short and has no acceptance_criteria or close_reason; verification will be shallow")

    spec = {
        "bead_id": bead_id,
        "extracted_at": _now(),
        "extractor": "scripts/extract-spec.py",
        "bead_status_at_extraction": show.get("status", "unknown"),
        "bead_close_reason": show.get("close_reason"),
        "bead_closed_at": show.get("closed_at"),
        "bead_type": bead_type,
        "bead_priority": show.get("priority", 2),
        "checklist": {
            "code_artifacts": _extract_code_artifacts(text, project_is_rust=project_is_rust),
            "tests": _extract_tests(text),
            "documentation": [],
            "migrations": [],
            "feature_flags": [],
            "telemetry": [],
            "ci_workflows": [],
            "acceptance_criteria": _split_acceptance_criteria(show.get("acceptance_criteria")),
            "implicit_requirements": _implicit_requirements(bead_type),
        },
        "constraints": _extract_constraints(text),
        "coverage_gaps": coverage_gaps,
        "extraction_notes": (
            "Heuristic extraction from bead body. An LLM-driven extractor "
            "(subagents/bead-spec-extractor.md) should be preferred for richer "
            "spec capture; this script is the deterministic fallback."
        ),
    }

    non_code = _extract_non_code(text)
    for k, v in non_code.items():
        spec["checklist"][k] = v

    return spec


def main() -> int:
    if len(sys.argv) == 2 and sys.argv[1] in ("--help", "-h"):
        print(__doc__ or "extract-spec.py — Phase 2: parse a bead's show.json into a structured spec.json checklist.")
        print()
        print("Usage: extract-spec.py <show.json>")
        return 0
    if len(sys.argv) != 2:
        print("Usage: extract-spec.py <show.json>", file=sys.stderr)
        return 2
    show_path = Path(sys.argv[1])
    # Tolerate a single malformed show.json. run-pass.sh's Phase 2 loop has
    # no `|| true` (unlike Phase 3/5), so a JSONDecodeError here under set -e
    # would abort the loop and skip every bead AFTER the bad one — turning
    # one corrupt bead into a pass-wide audit failure. Emit a stub spec
    # whose coverage_gaps make the failure visible to downstream phases
    # (and ultimately the scorecard) instead.
    try:
        show = json.loads(show_path.read_text())
    except Exception as exc:
        bead_id = show_path.parent.name or "unknown"
        stub = {
            "bead_id": bead_id,
            "extracted_at": _now(),
            "extractor": "scripts/extract-spec.py",
            "bead_status_at_extraction": "unknown",
            "bead_type": "task",
            "checklist": {"code_artifacts": [], "tests": {}, "documentation": [],
                          "migrations": [], "feature_flags": [], "telemetry": [],
                          "ci_workflows": [], "acceptance_criteria": [],
                          "implicit_requirements": []},
            "constraints": {},
            "fatal_extraction_error": "show_json_parse_error",
            "coverage_gaps": [f"show.json could not be parsed: {exc}"],
            "extraction_notes": "Stub emitted because show.json failed to parse; downstream scorers will see an empty spec and rate this bead at 0.",
        }
        json.dump(stub, sys.stdout, indent=2)
        sys.stdout.write("\n")
        print(f"WARNING: malformed show.json at {show_path}: {exc}", file=sys.stderr)
        return 0
    spec = extract(show, project_is_rust=_detect_project_is_rust(show_path))

    # Surface a stderr warning when the deterministic extractor's output is
    # likely too sparse to be useful — the caller should either accept
    # weak coverage or dispatch the bead-spec-extractor subagent for a
    # richer LLM-driven extraction.
    #
    # Heuristic: count actionable items across the checklist. A spec with
    # < 3 items in projects whose beads have substantive bodies (≥ 200 chars
    # of text scanned) almost certainly lost coverage to prose-style ACs that
    # the regex-based extractor can't parse.
    def _spec_item_count(s: dict) -> int:
        cl = s.get("checklist", {}) or {}
        n = 0
        n += len(cl.get("code_artifacts") or [])
        for ttype, items in (cl.get("tests") or {}).items():
            n += len(items or [])
        for k in ("documentation", "migrations", "feature_flags",
                  "telemetry", "ci_workflows", "acceptance_criteria",
                  "implicit_requirements"):
            n += len(cl.get(k) or [])
        return n

    items = _spec_item_count(spec)
    body_len = sum(len(show.get(k) or "") for k in
                   ("title", "description", "design", "acceptance_criteria",
                    "notes", "close_reason"))
    if items < 3 and body_len >= 200:
        bead_id = spec.get("bead_id", "unknown")
        print(
            f"WARNING: extract-spec.py: bead {bead_id} produced only {items} "
            f"item(s) from a {body_len}-char body. The deterministic parser "
            f"struggles with prose-style acceptance criteria; consider "
            f"dispatching subagents/bead-spec-extractor.md for richer "
            f"LLM-driven extraction. Field tests: LLM gets 10-49 items vs "
            f"deterministic 0-7 on prose ACs.",
            file=sys.stderr,
        )

    json.dump(spec, sys.stdout, indent=2)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
