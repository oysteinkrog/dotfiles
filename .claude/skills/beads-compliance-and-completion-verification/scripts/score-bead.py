#!/usr/bin/env python3
"""score-bead.py — Phase 8: apply the rubric to one bead's evidence pack.

Usage:
    score-bead.py <pass-dir>/beads/<bead-id>
                  [--rubric <audit-dir>/rubric.md]
                  [--threshold 700]
                  [--prior-pass-dir <prior-pass-path>]
                  [--synthesis <synthesis.md path>]

Reads spec.json, evidence.json, compliance.json, theater.json, test_depth.json
from the bead dir. Writes scorecard.md to the same dir. Prints a one-line
JSON summary to stdout (so callers can pipe into the master report).

Deterministic: given the same inputs and rubric, two runs produce the same score.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import tempfile
from pathlib import Path
from typing import Any


def atomic_write_text(path: Path, content: str) -> None:
    """Write `content` to `path` atomically via a sibling tmp file + os.replace.

    The ATOMIC RENAME is what makes this safe against shell `>` redirection.

    Concrete failure mode this defends against: an operator runs the scorer
    as `python3 score-bead.py BD > BD/scorecard.md` to capture the JSON
    summary. Bash opens scorecard.md with O_TRUNC (truncating the inode),
    holds fd 1 pointing at it, then exec's python. If the script wrote the
    full scorecard via `path.write_text()`, that fresh open writes the file,
    but on script exit Python's stdout `print(json.dumps(...))` lands at
    fd 1 → the same inode at offset 0, partially overwriting the markdown.
    Result: scorecard.md begins with the JSON envelope and the start of the
    real title is gone — exactly the artifact reported by operators recovering
    from theater-scan failures.

    With atomic rename, scorecard.md is replaced by a NEW inode after the
    rename, so the operator's bash fd (pointing at the orphaned old inode)
    can no longer corrupt the file on disk.

    File mode: `tempfile.mkstemp` defaults to 0o600 (owner-only), but
    `path.write_text()` respects umask (typically yielding 0o644). To avoid
    a silent permission downgrade on existing scorecards, we preserve the
    existing file's mode when present, or apply umask-modulated 0o666 for
    new files (matching write_text behavior).
    """
    path = Path(path)
    parent = path.parent
    parent.mkdir(parents=True, exist_ok=True)
    # Compute target mode BEFORE creating the tmp file so we can chmod
    # immediately after creation (avoiding a brief 0o600 window).
    if path.exists():
        try:
            target_mode = path.stat().st_mode & 0o777
        except OSError:
            target_mode = None
    else:
        # Read umask without permanently changing it (umask() returns the
        # previous value; we set it back immediately).
        cur_umask = os.umask(0)
        os.umask(cur_umask)
        target_mode = 0o666 & ~cur_umask
    fd, tmp_path = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=parent)
    try:
        if target_mode is not None:
            try:
                os.chmod(tmp_path, target_mode)
            except OSError:
                # Best-effort; non-critical if chmod fails (some filesystems).
                pass
        with os.fdopen(fd, "w", encoding="utf-8") as fp:
            fp.write(content)
            fp.flush()
            try:
                os.fsync(fp.fileno())
            except OSError:
                # fsync is best-effort: some filesystems don't support it.
                pass
        os.replace(tmp_path, path)
    except Exception:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise

try:
    import yaml
except ImportError:  # pragma: no cover - fallback keeps the scorer usable.
    yaml = None

# ---------- Defaults (override via rubric.md frontmatter; see RUBRIC.md) ----------

DEFAULT_WEIGHTS = {
    "implementation": 300,
    "tests": 250,
    "anti_theater": 150,
    "test_depth": 150,
    "docs_etc": 100,
    "cross_bead": 50,
}

VERDICT_BANDS = [
    (950, "🟢 Verified"),
    (850, "🟢 Substantially complete"),
    (700, "🟡 Partial"),
    (500, "🟠 False-closed (mild)"),
    (250, "🔴 False-closed (severe)"),
    (0, "🚨 Theater"),
]


def _band(score: int) -> str:
    for floor, label in VERDICT_BANDS:
        if score >= floor:
            return label
    return "🚨 Theater"


def _load_json(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text())
    except json.JSONDecodeError as exc:
        raise ValueError(f"{path}: invalid JSON: {exc}") from exc


def _citation_paths(check: dict[str, Any]) -> set[str]:
    paths: set[str] = set()
    for citation in check.get("citations", []) or []:
        if isinstance(citation, dict) and citation.get("path"):
            paths.add(str(citation["path"]))
    return paths


def score_implementation(spec: dict, evidence: dict, compliance: dict, theater: dict, max_score: int) -> tuple[int, list[str]]:
    items = spec.get("checklist", {}).get("code_artifacts", [])
    if not items:
        # Even with no code_artifacts in the deterministic spec, the LLM
        # evidence may have rich findings worth scoring against. The legacy
        # path returned max_score unconditionally; keep that for the no-LLM
        # case but defer to verdict_summary when an LLM gatherer ran AND
        # produced a non-empty verdict_summary.
        gatherer = str(evidence.get("gatherer") or "")
        if gatherer.startswith(_LLM_GATHERER_PREFIX):
            vs = evidence.get("verdict_summary")
            if isinstance(vs, dict) and (int(vs.get("FOUND", 0) or 0)
                                          + int(vs.get("MISSING", 0) or 0)
                                          + int(vs.get("AMBIGUOUS", 0) or 0)) > 0:
                return _score_from_verdict_summary(evidence, max_score, "Implementation")
        return max_score, ["n/a — no code artifacts in spec"]
    # Detect spec-vs-evidence schema mismatch (skill bug #1). Triggers on
    # zero ID overlap OR LLM-gatherer-with-≥2x-more-checks. Per-item lookups
    # below would miss when the LLM gatherer used `ac.X` IDs derived from
    # the bead body while the deterministic spec used `code.primary`-style
    # IDs. Score from verdict_summary instead.
    if _evidence_supersedes_spec(spec, evidence):
        return _score_from_verdict_summary(evidence, max_score, "Implementation")
    ev_by_id = {c["spec_item_id"]: c for c in evidence.get("checks", [])}
    cl_by_id = {c["spec_item_id"]: c for c in compliance.get("checks", [])}
    # Defensive .get() for severity AND path: subagent-written theater.json
    # may omit path on a "global" finding (e.g. one that flags the bead as a
    # whole rather than a file). f["path"] would KeyError and crash the
    # scorer for this bead, which run-pass.sh's `|| true` then swallows —
    # producing silent data loss (no scorecard.md, master-report ignores it).
    blocking_paths = {f["path"] for f in theater.get("findings", [])
                      if f.get("severity") == "BLOCKING" and f.get("path")}
    major_paths = {f["path"] for f in theater.get("findings", [])
                   if f.get("severity") == "MAJOR" and f.get("path")}

    # When Phase 4 ran in stub mode (no compliance-verifier subagent), the
    # compliance.json envelope has no per-item verdicts. Without a fallback,
    # every code artifact would resolve to verdict=="MISSING" and the
    # dimension would collapse to ~0 even when evidence.json located the
    # files. Mirror the Tests-dimension stub branch but with REDUCED credit
    # because Phase 3 evidence (file located + cited) is a weaker signal
    # than Phase 4 compliance (file located + tests pass against it):
    #
    #   FOUND     → 0.7  (file is present and cited; uncertain if it does what spec demands)
    #   AMBIGUOUS → 0.4  (rg-shortlist match; could be the right file or a same-named neighbour)
    #   MISSING   → 0.0  (Phase 3 found nothing)
    #
    # The scorecard banner already warns "DETERMINISTIC-ONLY PASS" so the
    # reader knows this is an upper bound. Without this, sample-mode audits
    # produced misleading 🚨 Theater verdicts on beads whose Phase 3
    # evidence was actually rich.
    compliance_stubbed = is_stub_pack(compliance)

    total_w = 0
    weighted = 0.0
    notes: list[str] = []
    for item in items:
        w = item.get("weight", 1)
        total_w += w
        ev = ev_by_id.get(item["id"])
        cl = cl_by_id.get(item["id"])
        if not ev or ev.get("status") == "MISSING":
            notes.append(f"{item['id']}: MISSING (0)")
            continue
        # Reuse the canonical citation-path extractor instead of an inline
        # `{c["path"] for c in ...}` — the inline form crashes on a citation
        # entry that lacks "path" (or isn't a dict at all), same silent-data-
        # loss failure mode as the theater-finding access above.
        cited = _citation_paths(ev)
        has_blocking = bool(cited & blocking_paths)
        has_major = bool(cited & major_paths)
        verdict = (cl or {}).get("verdict", "MISSING")
        if compliance_stubbed and verdict == "MISSING":
            # Fall back to evidence.json status with reduced credit;
            # theater findings still apply (they're independent of Phase 4).
            ev_status = ev.get("status")
            if ev_status == "FOUND":
                if has_blocking:
                    score_i = 0.0
                    notes.append(f"{item['id']}: FOUND in evidence but BLOCKING theater → 0 (Phase 4 stubbed)")
                elif has_major:
                    score_i = 0.35  # half of the 0.7 evidence-only credit
                    notes.append(f"{item['id']}: FOUND with MAJOR theater → 35% (Phase 4 stubbed)")
                else:
                    score_i = 0.7
                    notes.append(f"{item['id']}: FOUND in evidence → 70% (Phase 4 stubbed; upper bound)")
            elif ev_status == "AMBIGUOUS":
                score_i = 0.4
                notes.append(f"{item['id']}: AMBIGUOUS evidence → 40% (Phase 4 stubbed)")
            else:
                score_i = 0.0
        elif verdict == "PASS" and not has_blocking and not has_major:
            score_i = 1.0
        elif verdict == "PASS" and has_blocking:
            score_i = 0.0
            notes.append(f"{item['id']}: PASS but BLOCKING theater → 0")
        elif verdict == "PASS" and has_major:
            score_i = 0.5
            notes.append(f"{item['id']}: PASS with MAJOR theater → 50%")
        elif verdict == "FAIL":
            score_i = 0.25
            notes.append(f"{item['id']}: FAIL")
        elif verdict == "ERROR":
            score_i = 0.1
        elif ev.get("status") == "AMBIGUOUS":
            score_i = 0.3
        else:
            score_i = 0.0
        weighted += w * score_i
    score = int(max_score * weighted / total_w) if total_w else 0
    if compliance_stubbed:
        notes.insert(0, "Phase 4 in stub mode — Implementation scored from evidence.json with reduced credit (FOUND→70%, AMBIGUOUS→40%); upper bound, see scorecard banner")
    return score, notes


STUB_EXECUTORS = frozenset({"stub-wrapper", "single-bead-stub"})


_LLM_GATHERER_PREFIX = "subagent:llm-evidence-gatherer"


def _evidence_supersedes_spec(spec: dict, evidence: dict) -> bool:
    """True when the LLM evidence-gatherer's checklist should be trusted over
    the deterministic spec extractor's checklist.

    Two conditions trigger this (either is sufficient):

      A. **Total ID-scheme mismatch.** Spec has at least one checklist ID and
         evidence has at least one `spec_item_id`, but the two sets are
         disjoint. The deterministic extractor used `code.primary` /
         `tests.unit.primary` while the LLM gatherer used `ac.1` / `ac.2` /
         `ac.X` derived from the bead body. Per-item lookups will all miss.

      B. **LLM gatherer with weak overlap.** `evidence.gatherer` matches
         the LLM family (`subagent:llm-evidence-gatherer*`) AND fewer than
         half of the spec's IDs appear in the evidence's IDs. Per-item
         lookups would mark most spec items as MISSING because the LLM
         re-derived the checklist with its own scheme. The 50% threshold
         keeps the legacy path running on beads where the LLM happened to
         match the spec's IDs (because then per-item works fine).

    Concrete bug this defends against (skill bug #1, observed in
    /data/projects/coding_agent_session_search beads_compliance_audit pass
    2026-05-09T00-50-03Z):

      The deterministic spec extractor (`extract-spec.py`) emits checklist
      item IDs like `code.primary`, `tests.unit.primary`. An LLM evidence-
      gatherer subagent, told to "for each acceptance criterion in the bead
      body, mark FOUND/MISSING/AMBIGUOUS", uses `ac.1`, `ac.2`, etc. — i.e.
      a checklist re-derived from the bead body, not the deterministic spec.

      `score_implementation` and `score_tests` build
      `ev_by_id = {c.spec_item_id: c}`, look up `ev_by_id[item.id]`, get
      None, and treat the item as MISSING. Even when the LLM evidence
      reports rich FOUND coverage with citations.

      Wave-2 audit pass exhibits:
        - `coding_agent_session_search-2dccg.2.1` had spec_ids = {code.primary},
          ev_ids = {ac.1, ac.2, ac.3} (total disjoint, condition A).
        - `coding_agent_session_search-lxn5` had spec_ids = {code.primary,
          telemetry.primary, implicit.feature.happy_path_test} (3 items),
          ev_ids = {code.parallel_search, ac.dispatch_threshold,
          ac.deterministic_ordering, ac.rollback_env_var,
          implicit.feature.happy_path_test} (5 items). Only 1 of 3 spec
          IDs appears in evidence (33% overlap → condition B fires).

    The fix: when this condition holds, score Implementation and Tests
    dimensions from `evidence.verdict_summary` directly (FOUND/MISSING/
    AMBIGUOUS counts) rather than per-item lookups against the partial spec.

    Returns False when:
      - The spec checklist has no IDs to compare against (no fallback needed —
        the legacy "no items → max_score" path already handles this).
      - The evidence has no checks (no fallback signal available).
      - At least 50% of spec IDs appear in evidence AND the gatherer isn't
        an LLM (legacy per-item path works fine).
    """
    if not isinstance(spec, dict) or not isinstance(evidence, dict):
        return False
    spec_ids: set[str] = set()
    checklist = spec.get("checklist", {}) or {}
    # code_artifacts is a flat list. tests is a {ttype: [items]} dict. The
    # other six (documentation, migrations, feature_flags, telemetry,
    # ci_workflows, acceptance_criteria, implicit_requirements) are flat
    # lists. Without all of these, docs-heavy beads (whose spec puts every
    # ID under documentation/migrations/etc.) compare against an empty
    # spec_ids set, the helper returns False, and the legacy per-item-ID
    # lookup misses every LLM-derived ac.X check — collapsing the docs
    # dimension to 0 even when LLM evidence reports rich FOUND coverage.
    for key in ("code_artifacts", "documentation", "migrations",
                "feature_flags", "telemetry", "ci_workflows",
                "acceptance_criteria", "implicit_requirements"):
        for it in checklist.get(key, []) or []:
            if isinstance(it, dict) and it.get("id"):
                spec_ids.add(str(it["id"]))
    for items in (checklist.get("tests", {}) or {}).values():
        for it in items or []:
            if isinstance(it, dict) and it.get("id"):
                spec_ids.add(str(it["id"]))
    if not spec_ids:
        return False
    ev_ids: set[str] = set()
    for c in evidence.get("checks", []) or []:
        if isinstance(c, dict) and c.get("spec_item_id"):
            ev_ids.add(str(c["spec_item_id"]))
    if not ev_ids:
        return False
    # All three conditions require an LLM gatherer. Handwritten or
    # deterministic-only evidence (`scripts/gather-evidence.sh`) stays on
    # the legacy per-item path because:
    #   - The deterministic gatherer iterates spec items to build evidence,
    #     so zero overlap with the spec almost always means evidence is
    #     stale/corrupt rather than a different ID scheme. Falling through
    #     to verdict_summary in that case rewards staleness.
    #   - Manually-edited evidence without a gatherer field is opaque to
    #     us; we can't tell whether it was LLM-derived. Default to the
    #     stricter legacy path.
    gatherer = str(evidence.get("gatherer") or "")
    if not gatherer.startswith(_LLM_GATHERER_PREFIX):
        return False
    # Condition A: zero overlap. The LLM gatherer used a fully different
    # ID scheme (typically `ac.1` / `ac.X` derived from the bead body)
    # while the spec uses deterministic-extractor IDs (`code.primary` /
    # `tests.unit.primary` / `docs.readme` / etc.).
    if spec_ids.isdisjoint(ev_ids):
        return True
    overlap = len(spec_ids & ev_ids)
    # Condition B: weak overlap. Strictly fewer than half of spec IDs
    # appear in evidence. Catches multi-dimensional specs where the LLM
    # used different IDs for most categories (e.g. lxn5 had spec_ids=3
    # spanning code+telemetry+implicit-test, only `implicit.feature.
    # happy_path_test` reused; per-item lookup MISSes the other 2).
    if overlap * 2 < len(spec_ids):
        return True
    # Condition C: LLM expanded the checklist. Evidence has at least 2×
    # as many checks as the spec has total items. Catches thin-spec beads
    # where the LLM happened to reuse the spec's lone ID but added many
    # more ACs the deterministic extractor missed (e.g. ifr7 had spec_ids=
    # {code.primary} (1 item), ev_ids included code.primary + 4 distinct
    # ac.X items; per-item lookup matches the 1 but discards the 4).
    if len(ev_ids) >= 2 * len(spec_ids):
        return True
    return False


def _score_from_verdict_summary(evidence: dict, max_score: int, dimension: str) -> tuple[int, list[str]]:
    """Score a dimension purely from `evidence.verdict_summary` counts.

    Used when `_evidence_supersedes_spec` is True — we trust the LLM
    evidence-gatherer's own checklist (re-derived from the bead body) more
    than the deterministic spec extractor's ID scheme.

    Credit allocation mirrors the Phase-4-stub fallback in `score_implementation`:
      FOUND     → 1.0  (file located + cited; LLM agent verified meaning)
      AMBIGUOUS → 0.4  (weak signal; could be the right artifact or a neighbour)
      MISSING   → 0.0  (LLM agent looked and found nothing)

    FOUND is awarded full 1.0 (not 0.7 as in the deterministic Phase 4 stub
    branch) because the LLM agent reading the bead body and grepping the
    codebase IS the verification step that the deterministic gather lacks —
    its FOUND verdicts are not "file present" but "file present AND content
    matches what the bead asked for". The 0.7 reduction in the deterministic
    branch defends against blind file-name matches; LLM evidence has no such
    weakness.

    Sources of truth, in priority order:
      1. `evidence.verdict_summary` (the LLM agent's own count).
      2. Counted from `evidence.checks[*].status` if verdict_summary is
         absent or empty. LLM agents writing evidence by hand may forget
         the summary block but always emit checks — falling back to
         counting them keeps the dimension scoreable in that case.

    Falls back to max_score with a "no verdict_summary" note ONLY when both
    sources yield zero countable evidence (legitimately empty pack).
    """
    vs = evidence.get("verdict_summary") or {}
    found = int(vs.get("FOUND", 0) or 0)
    missing = int(vs.get("MISSING", 0) or 0)
    ambiguous = int(vs.get("AMBIGUOUS", 0) or 0)
    total = found + missing + ambiguous
    counted_from = "verdict_summary"
    if total == 0:
        # Fall back to counting individual checks. LLM-written evidence.json
        # without a verdict_summary block is common; without this fallback
        # we'd return max_score (full credit) which over-credits.
        for c in evidence.get("checks", []) or []:
            if not isinstance(c, dict):
                continue
            status = str(c.get("status", "")).upper()
            if status == "FOUND":
                found += 1
            elif status == "MISSING":
                missing += 1
            elif status == "AMBIGUOUS":
                ambiguous += 1
        total = found + missing + ambiguous
        if total > 0:
            counted_from = "checks[]"
    if total == 0:
        return max_score, [
            f"{dimension}: spec-evidence ID-scheme mismatch and no countable verdicts in evidence — defaulting to full credit (upper bound)"
        ]
    weighted = found + 0.4 * ambiguous
    score = int(round(max_score * weighted / total))
    return score, [
        f"{dimension}: spec/evidence ID-scheme mismatch (LLM gatherer used different IDs); "
        f"scored from {counted_from} (FOUND={found}, AMBIGUOUS={ambiguous}, MISSING={missing}) "
        f"→ {score}/{max_score}"
    ]


def is_stub_pack(pack: dict) -> bool:
    """True if this Phase 4/6 artifact was produced by a deterministic stub
    rather than a real subagent / test re-run.

    `run-pass.sh` and `single-bead-audit.sh` emit empty Phase 4/6 packs with
    a stub executor name when no compliance-verifier / test-depth-auditor
    subagent is wired into the loop. Without distinguishing this, the
    scorer would treat the empty checks[] array as evidence of a failed
    Phase 4 — silently zeroing the Required-tests dimension on every bead.

    Recognized stub signals (any one is sufficient):
      1. executor / auditor name in STUB_EXECUTORS (the documented form)
      2. `stub_reason` string present (operators writing recovery stubs by hand)
      3. completely missing pack — `_load_json` returns {} so `pack` is empty
         AND no `checks` key at all. Empty `checks: []` WITHOUT any of these
         signals is still treated as "phase ran, found nothing" since the
         scorer cannot tell the difference between "real run with no findings"
         and "lazy operator wrote {} as compliance.json"; the documented
         operator path is to set `stub_reason`.

    Previously only signal 1 was recognized, which forced operators recovering
    from a Phase 4/6 crash to know the magic string `stub-wrapper`. The other
    two signals make the API discoverable: an empty file is treated as a stub
    and a `stub_reason` string is human-natural for recovery work.
    """
    if not isinstance(pack, dict):
        return False
    if str(pack.get("executor") or pack.get("auditor") or "") in STUB_EXECUTORS:
        return True
    if pack.get("stub_reason"):
        return True
    if not pack:
        # Pack file missing entirely — `_load_json` returned {}. Phase didn't
        # produce an artifact at all, which is operationally identical to a
        # stub: the dimension cannot be evaluated, so award full credit and
        # rely on the stub banner to tell the operator the result is an
        # upper bound.
        return True
    return False


def score_tests(spec: dict, evidence: dict, compliance: dict, theater: dict, max_score: int) -> tuple[int, list[str]]:
    test_items: list[dict] = []
    for ttype, items in spec.get("checklist", {}).get("tests", {}).items():
        for it in items:
            it = dict(it)
            it["_type"] = ttype
            test_items.append(it)
    if not test_items:
        # When the deterministic spec extracted no test items but the LLM
        # evidence has superseding checks with FOUND/MISSING/AMBIGUOUS
        # verdicts, the LLM agent's checklist (re-derived from the bead
        # body) is the better signal. Score from verdict_summary so
        # test-flavored ACs captured by the LLM aren't lost.
        # `_score_from_verdict_summary` falls back to checks[] internally
        # when verdict_summary is missing, so we don't pre-guard on it
        # here — that previous over-guard caused docs beads with rich
        # checks[] but no summary to mis-score 0.
        if _evidence_supersedes_spec(spec, evidence):
            return _score_from_verdict_summary(evidence, max_score, "Required tests")
        # No test items in spec AND no LLM-derived evidence: WAIVE with full
        # credit. Rationale (added 2026-05-09 per audit-infra bead br-22j76):
        # the prior behaviour returned 0/max_score, which systematically
        # penalized bug-fix beads whose body talks about a runtime fix
        # without enumerating test plans. Field-tested on pass
        # 2026-05-09T00-49-33Z: 47 of 60 deepening-verified beads flagged
        # false-closed by the deterministic pass were real implementations
        # whose only "fault" was a spec without tests. Awarding 0 turns a
        # heuristic-extractor gap into an apparent quality failure. The
        # deepening-overlay subagent is the right surface to verify a
        # missing regression test, not the deterministic scorer.
        bead_type = spec.get("bead_type", "task")
        note = f"WAIVED — no tests enumerated in spec; awarding full {max_score} (br-22j76)."
        if bead_type == "bug":
            note += " NOTE: bead_type=bug — deepening verifier should confirm a regression test exists."
        return max_score, [note]
    # Detect spec/evidence ID-scheme mismatch (skill bug #1) — same pattern
    # as score_implementation: when the LLM gatherer's checks don't align
    # with the deterministic spec's IDs, score from verdict_summary instead
    # of returning per-item zeros for every test item.
    if _evidence_supersedes_spec(spec, evidence):
        return _score_from_verdict_summary(evidence, max_score, "Required tests")
    if is_stub_pack(compliance):
        # Phase 4 was a stub — we can't tell PASS from FAIL because no
        # subagent re-ran the tests. Mark the dimension WAIVED and award
        # full credit; the scorecard banner will surface the stub-mode
        # disclaimer so the reader knows this dimension wasn't actually
        # verified. Without this, run-pass.sh produces "X false-closed
        # beads" reports that are really just coverage gaps in the
        # orchestrator.
        return max_score, [f"WAIVED — Phase 4 ran in stub mode (executor={compliance.get('executor')!r}); award full {max_score} pending real compliance-verifier subagent run"]

    type_weights = {"unit": 1, "integration": 2, "e2e": 3, "fuzz": 2,
                    "property": 2, "metamorphic": 2, "golden": 1, "conformance": 3}
    cl_by_id = {c["spec_item_id"]: c for c in compliance.get("checks", [])}
    ev_by_id = {c["spec_item_id"]: c for c in evidence.get("checks", [])}
    theater_by_path: dict[str, list[dict[str, Any]]] = {}
    for finding in theater.get("findings", []):
        if finding.get("severity") not in ("BLOCKING", "MAJOR"):
            continue
        path = finding.get("path")
        if path:
            theater_by_path.setdefault(str(path), []).append(finding)
    # Use .get("severity") for parity with score_implementation above — a
    # finding without a severity key would otherwise KeyError and crash the
    # whole bead's scoring run.
    test_theater_ids = {f.get("invalidates_phase4_check") for f in theater.get("findings", [])
                        if f.get("severity") in ("BLOCKING", "MAJOR")}

    total_w = 0.0
    weighted = 0.0
    notes: list[str] = []
    for item in test_items:
        w = type_weights.get(item["_type"], 1)
        total_w += w
        cl = cl_by_id.get(item["id"])
        verdict = (cl or {}).get("verdict", "MISSING")
        cited_paths = _citation_paths(ev_by_id.get(item["id"], {}))
        path_findings = [f for p in cited_paths for f in theater_by_path.get(p, [])]
        has_blocking = any(f.get("severity") == "BLOCKING" for f in path_findings)
        has_major = any(f.get("severity") == "MAJOR" for f in path_findings)
        invalidated = item["id"] in test_theater_ids or has_blocking
        if verdict == "PASS" and not invalidated:
            if has_major:
                score_i = 0.5
                paths = ", ".join(sorted(cited_paths))
                notes.append(f"{item['id']}: PASS with MAJOR theater in cited test path(s) {paths} → 50%")
            else:
                score_i = 1.0
        elif verdict == "PASS" and invalidated:
            score_i = 0.0
            paths = ", ".join(sorted(cited_paths)) or "explicit invalidates_phase4_check"
            notes.append(f"{item['id']}: PASS but invalidated by theater in {paths} → 0")
        elif verdict == "TIMEOUT":
            score_i = 0.2
            notes.append(f"{item['id']}: TIMEOUT")
        elif verdict == "FAIL":
            score_i = 0.0
        elif verdict == "SKIPPED":
            score_i = 0.0
            notes.append(f"{item['id']}: SKIPPED")
        else:
            score_i = 0.0
            notes.append(f"{item['id']}: {verdict}")
        weighted += w * score_i
    score = int(max_score * weighted / total_w) if total_w else 0
    return score, notes


def score_anti_theater(theater: dict, max_score: int) -> tuple[int, list[str]]:
    summary = theater.get("summary", {})
    penalty = (summary.get("BLOCKING", 0) * 50
               + summary.get("MAJOR", 0) * 15
               + summary.get("MINOR", 0) * 3)
    score = max(0, max_score - penalty)
    notes = [f"BLOCKING={summary.get('BLOCKING', 0)} MAJOR={summary.get('MAJOR', 0)} MINOR={summary.get('MINOR', 0)} → -{penalty}"]
    return score, notes


def score_test_depth(test_depth: dict, max_score: int) -> tuple[int, list[str]]:
    if is_stub_pack(test_depth):
        # Phase 6 was a stub — same reasoning as score_tests's stub branch.
        return max_score, [f"WAIVED — Phase 6 ran in stub mode (auditor={test_depth.get('auditor')!r}); award full {max_score} pending real test-depth-auditor subagent run"]
    checks = test_depth.get("checks", [])
    if not checks:
        return 0, ["No depth checks performed → 0"]
    total = 0.0
    notes: list[str] = []
    for c in checks:
        v = c.get("verdict", "FAIL")
        if v == "WAIVED":
            reason = str(c.get("reason") or c.get("notes") or "").strip()
            reason_l = reason.lower()
            linked = bool(c.get("spec_ref") or c.get("spec_item_id") or c.get("linked_spec_item") or c.get("constraint_ref"))
            text_links_spec = "spec" in reason_l or "checklist" in reason_l or "not required" in reason_l or "did not require" in reason_l
            if reason and (linked or text_links_spec):
                total += 1.0
            else:
                notes.append(f"{c.get('test_type', 'unknown')}:{c.get('depth_metric', 'unknown')}: WAIVED without spec-linked reason → 0")
            continue
        verdict_scores = {"PASS": 1.0, "PARTIAL": 0.5, "FAIL": 0.0, "INFRA_MISSING": 0.0}  # nosec B105 - verdict labels, not credentials.
        total += verdict_scores.get(v, 0.0)
    notes.insert(0, f"{len(checks)} checks; weighted average {total/len(checks):.2f}")
    return int(max_score * total / len(checks)), notes


def score_docs_etc(spec: dict, evidence: dict, max_score: int) -> tuple[int, list[str]]:
    chk = spec.get("checklist", {})
    items = (chk.get("documentation", []) + chk.get("migrations", [])
             + chk.get("feature_flags", []) + chk.get("telemetry", [])
             + chk.get("ci_workflows", []))
    if not items:
        return max_score, ["n/a — no non-code artifacts in spec"]
    # Same skill bug #1 fix as score_implementation/score_tests: when the
    # LLM gatherer's checklist supersedes the deterministic spec, score
    # from verdict_summary instead of per-item ID lookups. Without this,
    # docs-heavy beads (e.g. coding_agent_session_search-5wi4z.2 in audit
    # pass 2026-05-09T00-50-03Z) collapse the 750-max docs dimension to 0
    # because the deterministic extractor's docs.* IDs don't match the
    # LLM gatherer's ac.X IDs — even when the LLM verdict_summary reports
    # FOUND for all the documentation requirements.
    if _evidence_supersedes_spec(spec, evidence):
        return _score_from_verdict_summary(evidence, max_score, "Docs/non-code")
    ev_by_id = {c["spec_item_id"]: c for c in evidence.get("checks", [])}
    present = sum(1 for it in items if (ev_by_id.get(it["id"]) or {}).get("status") == "FOUND")
    return int(max_score * present / len(items)), [f"{present}/{len(items)} non-code items found"]


def score_cross_bead(synthesis_findings: list[dict], bead_id: str, max_score: int) -> tuple[int, list[str]]:
    relevant = [f for f in synthesis_findings if bead_id in f.get("beads", [])]
    if not relevant:
        return max_score, ["No synthesis findings touch this bead"]
    # Coerce `kind` to str (it could be None per .get()) before looking it up
    # in the penalty table; mypy [arg-type] otherwise rejects the None arg.
    kind_penalty = {"integration_gap": 25, "contradiction": 25, "orphan_ac": 10, "dep_anomaly": 10}
    penalty = sum(kind_penalty.get(str(f.get("kind") or ""), 10) for f in relevant)
    return max(0, max_score - penalty), [f"{len(relevant)} synthesis findings → -{penalty}"]


SYNTHESIS_SECTION_RE = re.compile(r"^##\s+(.+?)\s*$", re.M)
# Broad bead-id pattern. br defaults to `bd-` prefix but every project can override
# (and br auto-generates project-prefixed ids like `audit-final3-1778042649-s7g`).
# Child beads (created by `br create --parent <id>`) use `<parent-id>.<n>` form.
# REQUIRE at least one hyphen-separated segment to distinguish from version
# numbers like `v1.2` and dotted identifiers like `tokio.sync`. Periods only
# allowed when followed by digits (the actual child-bead form), so `bd-foo.bar`
# matches only `bd-foo` (not the whole thing).
BEAD_ID_IN_LINE_RE = re.compile(r"`([a-z][a-z0-9_]*-[a-z0-9_]+(?:-[a-z0-9_]+|\.\d+)*)`")
SECTION_KIND = {
    "Integration gaps": "integration_gap",
    "Contradictions": "contradiction",
    "Orphaned ACs": "orphan_ac",
    "Dependency-graph anomalies": "dep_anomaly",
    "Shared invariants nobody owns": "orphan_ac",
    "Bead-graph truthfulness flags": "dep_anomaly",
}


def parse_synthesis(synthesis_path: Path) -> list[dict]:
    """Walk synthesis.md; for each table row under a known section, emit a finding
    with `kind` and the list of bead IDs mentioned anywhere in the row.

    Header / separator rows are skipped. The previous implementation had a Python
    operator-precedence bug where `A or B if C else D` was being read incorrectly;
    rewritten here for clarity.
    """
    if not synthesis_path or not synthesis_path.exists():
        return []
    findings: list[dict] = []
    text = synthesis_path.read_text()
    current_kind: str | None = None
    for line in text.splitlines():
        m = SYNTHESIS_SECTION_RE.match(line)
        if m:
            current_kind = SECTION_KIND.get(m.group(1).strip())
            continue
        if not current_kind or not line.startswith("|"):
            continue
        # Skip separator rows (`|---|---|---|`) — `---` in any cell is a clear
        # signal regardless of column count.
        if "---" in line:
            continue
        cells = [c.strip() for c in line.split("|") if c.strip()]
        if not cells:
            continue
        # Skip header rows: first cell starts with a capital letter and isn't
        # a backticked id. Bead-citing rows always lead with `<id>`.
        first = cells[0]
        if first and first[0].isupper() and not first.startswith("`"):
            continue
        beads = BEAD_ID_IN_LINE_RE.findall(line)
        if beads:
            findings.append({"kind": current_kind, "beads": beads, "raw": line.strip()})
    return findings


def load_prior_score(prior_pass_dir: Path | None, bead_id: str) -> int | None:
    """Best-effort: parse the bead's prior scorecard for its total score."""
    if not prior_pass_dir:
        return None
    sc = prior_pass_dir / "beads" / bead_id / "scorecard.md"
    if not sc.exists():
        return None
    m = re.search(r"\*\*Score:\s+(\d+)\s*/\s*1000\*\*", sc.read_text())
    return int(m.group(1)) if m else None


def load_show_for_scorecard(path: Path) -> tuple[dict[str, Any], str | None]:
    """Load show.json for display fields without letting one corrupt raw bead
    payload abort Phase 8 after spec extraction already degraded gracefully.
    """
    if not path.exists():
        return {}, None
    try:
        return json.loads(path.read_text()), None
    except json.JSONDecodeError as exc:
        return {}, f"{path}: invalid JSON: {exc}"


def write_fatal_scorecard(
    bd: Path,
    bead_id: str,
    spec: dict[str, Any],
    show_error: str | None,
    threshold: int,
) -> None:
    status = str(spec.get("bead_status_at_extraction", "unknown")).lower()
    false_closed = status == "closed"
    md = [
        f"# Scorecard — {bead_id}\n",
        "**Type:** task  **Priority:** P2",
        f"**Status (claimed):** {status}",
        "\n**Score: 0 / 1000**",
        "**Verdict: 🚨 Theater**",
    ]
    if false_closed:
        md.append(f"**🚨 FALSE-CLOSED** (status=closed, score=0 < threshold {threshold})")
    md.append("\n## Fatal extraction error\n")
    md.append(str(spec.get("fatal_extraction_error") or "spec extraction failed"))
    if show_error:
        md.append(f"- show.json: {show_error}")
    for gap in spec.get("coverage_gaps", []) or []:
        md.append(f"- {gap}")
    md.append("\n## Citations\n")
    for f in ("spec.json", "show.json"):
        if (bd / f).exists():
            md.append(f"- {f}: `{bd / f}`")
    atomic_write_text(bd / "scorecard.md", "\n".join(md) + "\n")
    print(json.dumps({"bead_id": bead_id, "score": 0, "band": "🚨 Theater", "false_closed": false_closed}))


DIMENSION_ALIASES = {
    "implementation": "implementation",
    "implementation_completeness": "implementation",
    "tests": "tests",
    "required_tests": "tests",
    "test": "tests",
    "anti_theater": "anti_theater",
    "theater": "anti_theater",
    "test_depth": "test_depth",
    "depth": "test_depth",
    "docs_etc": "docs_etc",
    "docs": "docs_etc",
    "documentation": "docs_etc",
    "cross_bead": "cross_bead",
    "cross_bead_integration": "cross_bead",
    "integration": "cross_bead",
}

DIMENSION_NUMBER_ALIASES = {
    "dimension_1": "implementation",
    "dimension_2": "tests",
    "dimension_3": "anti_theater",
    "dimension_4": "test_depth",
    "dimension_5": "docs_etc",
    "dimension_6": "cross_bead",
}


def _coerce_score(value: Any) -> int | None:
    if isinstance(value, bool):
        return None
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        return int(value)
    if isinstance(value, str) and re.fullmatch(r"-?\d+", value.strip()):
        return int(value.strip())
    if isinstance(value, dict):
        for key in ("score", "new_score", "override_score", "post_defense_score"):
            coerced = _coerce_score(value.get(key))
            if coerced is not None:
                return coerced
    return None


def defense_dimension_overrides(defense: dict[str, Any]) -> tuple[dict[str, int], list[str]]:
    verdict = str(defense.get("defense_verdict") or defense.get("verdict") or "").strip().lower()
    if verdict not in {"accepted", "partial"}:
        return {}, []

    overrides: dict[str, int] = {}
    ignored: list[str] = []

    dimensions = defense.get("dimensions")
    if isinstance(dimensions, dict):
        for raw_key, raw_value in dimensions.items():
            key = DIMENSION_ALIASES.get(str(raw_key).strip().lower())
            score = _coerce_score(raw_value)
            if key and score is not None:
                overrides[key] = score
            else:
                ignored.append(str(raw_key))

    change = defense.get("audit_verdict_change")
    if isinstance(change, dict):
        for numbered, key in DIMENSION_NUMBER_ALIASES.items():
            for suffix in ("_new", "_score", "_override", "_post_defense"):
                raw_name = f"{numbered}{suffix}"
                if raw_name in change:
                    score = _coerce_score(change.get(raw_name))
                    if score is not None:
                        overrides[key] = score
                    break

    notes = [f"closer-defense verdict={verdict}; applied {len(overrides)} dimension override(s)"]
    if ignored:
        notes.append(f"ignored unrecognized defense dimension(s): {', '.join(sorted(ignored))}")
    if not overrides:
        notes.append("defense accepted/partial but supplied no per-dimension score overrides")
    return overrides, notes


def normalize_weight_map(raw: Any) -> dict[str, int] | None:
    if not isinstance(raw, dict):
        return None
    weights: dict[str, int] = {}
    for raw_key, raw_value in raw.items():
        key = DIMENSION_ALIASES.get(str(raw_key).strip().lower())
        score = _coerce_score(raw_value)
        if key and score is not None:
            weights[key] = score
    if set(weights) != set(DEFAULT_WEIGHTS):
        return None
    if sum(weights.values()) != 1000:
        return None
    return weights


def parse_rubric_overrides(rubric_path: Path | None) -> dict[str, Any]:
    """Pull the score_threshold and any per-type weight overrides from the audit
    dir's rubric.md frontmatter. Best-effort; missing fields fall back to defaults.
    """
    if not rubric_path or not rubric_path.exists():
        return {}
    text = rubric_path.read_text()
    m = re.match(r"\A---\s*\n(.*?)\n---\s*\n", text, re.S)
    if not m:
        return {}
    if yaml is not None:
        try:
            data = yaml.safe_load(m.group(1)) or {}
            return data if isinstance(data, dict) else {}
        except Exception:
            return {}
    out: dict[str, Any] = {}
    for line in m.group(1).splitlines():
        if ":" not in line:
            continue
        k, _, v = line.partition(":")
        k = k.strip()
        v = v.strip()
        if not k:
            continue
        try:
            out[k] = json.loads(v) if v else None
        except Exception:
            out[k] = v
    return out


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("bead_dir")
    p.add_argument("--rubric", required=False, help="Path to audit dir rubric.md (frontmatter overrides defaults).")
    p.add_argument("--threshold", type=int, default=700)
    p.add_argument("--prior-pass-dir", default=None,
                   help="Prior pass dir; if given, the bead's prior score is loaded for trend display.")
    p.add_argument("--synthesis", default=None,
                   help="Path to synthesis.md; cross-bead findings touching this bead are folded into dimension 6.")
    p.add_argument("--prior-score", type=int, default=None,
                   help="Override: prior score for trend (only used if --prior-pass-dir is not given).")
    args = p.parse_args()

    bd = Path(args.bead_dir)
    spec = _load_json(bd / "spec.json")
    evidence = _load_json(bd / "evidence.json")
    compliance = _load_json(bd / "compliance.json")
    theater = _load_json(bd / "theater.json")
    depth = _load_json(bd / "test_depth.json")
    show, show_error = load_show_for_scorecard(bd / "show.json")
    defense = _load_json(bd / "defense.json")

    rubric_overrides = parse_rubric_overrides(Path(args.rubric)) if args.rubric else {}
    threshold = int(rubric_overrides.get("score_threshold", args.threshold))

    weights = dict(DEFAULT_WEIGHTS)

    bead_type = (spec.get("bead_type") or "task").lower()
    if bead_type == "bug":
        weights["implementation"] = 200
        weights["tests"] = 350
    elif bead_type == "epic":
        weights = {"implementation": 100, "tests": 100, "anti_theater": 100,
                   "test_depth": 100, "docs_etc": 100, "cross_bead": 500}
    elif bead_type == "docs":
        weights = {"implementation": 50, "tests": 50, "anti_theater": 50,
                   "test_depth": 50, "docs_etc": 750, "cross_bead": 50}

    weights_by_type = rubric_overrides.get("weights_by_type", {})
    if isinstance(weights_by_type, dict):
        rubric_weights = normalize_weight_map(weights_by_type.get(bead_type))
        if rubric_weights is not None:
            weights = rubric_weights

    bead_id = spec.get("bead_id") or bd.name
    if spec.get("fatal_extraction_error"):
        write_fatal_scorecard(bd, bead_id, spec, show_error, threshold)
        return 0

    # Synthesis findings touching this bead — fixes the "cross-bead always max" bug.
    synthesis_path = Path(args.synthesis) if args.synthesis else (bd.parent.parent / "synthesis.md")
    synthesis_findings = parse_synthesis(synthesis_path)

    # Prior score for trend.
    prior_score = args.prior_score
    if prior_score is None and args.prior_pass_dir:
        prior_score = load_prior_score(Path(args.prior_pass_dir), bead_id)

    s_impl, n_impl = score_implementation(spec, evidence, compliance, theater, weights["implementation"])
    s_tests, n_tests = score_tests(spec, evidence, compliance, theater, weights["tests"])
    s_at, n_at = score_anti_theater(theater, weights["anti_theater"])
    s_td, n_td = score_test_depth(depth, weights["test_depth"])
    s_de, n_de = score_docs_etc(spec, evidence, weights["docs_etc"])
    s_cb, n_cb = score_cross_bead(synthesis_findings, bead_id, weights["cross_bead"])

    dimension_scores = {
        "implementation": s_impl,
        "tests": s_tests,
        "anti_theater": s_at,
        "test_depth": s_td,
        "docs_etc": s_de,
        "cross_bead": s_cb,
    }
    dimension_notes = {
        "implementation": n_impl,
        "tests": n_tests,
        "anti_theater": n_at,
        "test_depth": n_td,
        "docs_etc": n_de,
        "cross_bead": n_cb,
    }
    defense_overrides, defense_notes = defense_dimension_overrides(defense)
    for key, override in defense_overrides.items():
        if key not in dimension_scores:
            continue
        old = dimension_scores[key]
        bounded = max(0, min(int(override), weights[key]))
        dimension_scores[key] = bounded
        dimension_notes[key].append(f"closer-defense override: {old} → {bounded}")
    s_impl = dimension_scores["implementation"]
    s_tests = dimension_scores["tests"]
    s_at = dimension_scores["anti_theater"]
    s_td = dimension_scores["test_depth"]
    s_de = dimension_scores["docs_etc"]
    s_cb = dimension_scores["cross_bead"]

    total = s_impl + s_tests + s_at + s_td + s_de + s_cb
    band = _band(total)
    status = show.get("status", spec.get("bead_status_at_extraction", "unknown"))
    if isinstance(status, dict):
        status = next(iter(status.values()), "unknown")
    status = str(status).lower()
    false_closed = (status == "closed" and total < threshold)

    stub_phase4 = is_stub_pack(compliance)
    stub_phase6 = is_stub_pack(depth)

    md = []
    md.append(f"# Scorecard — {bead_id}\n")
    md.append(f"**Title:** {show.get('title', 'unknown')}")
    md.append(f"**Type:** {bead_type}  **Priority:** P{show.get('priority', 2)}")
    md.append(f"**Status (claimed):** {status}")
    if show.get("close_reason"):
        md.append(f"**Close reason:** \"{show['close_reason']}\" ({show.get('closed_at', 'unknown')})")
    # `closed_by_session` is what trauma-guard.sh and anomaly-scan.sh's
    # batch-close detector key off of. Surfacing it on the scorecard makes
    # the forensic chain visible in the human-readable artifact too — and
    # matches the field promised by `assets/scorecard-template.md`.
    if show.get("closed_by_session"):
        md.append(f"**Closed by session:** {show['closed_by_session']}")
    md.append(f"\n**Score: {total} / 1000**")
    md.append(f"**Verdict: {band}**")
    if stub_phase4 or stub_phase6:
        which = []
        if stub_phase4:
            which.append("Phase 4 (Required tests)")
        if stub_phase6:
            which.append("Phase 6 (Test depth)")
        md.append(
            f"**⚠ DETERMINISTIC-ONLY PASS:** {', '.join(which)} "
            "ran in stub mode (no subagent re-ran tests); those dimensions are WAIVED with full credit. "
            "The score above is an UPPER BOUND on real completion — re-run with the real compliance-verifier "
            "and test-depth-auditor subagents before treating any verdict as definitive."
        )
    if false_closed:
        md.append(f"**🚨 FALSE-CLOSED** (status=closed, score={total} < threshold {threshold})")
    if prior_score is not None:
        delta = total - prior_score
        sign = "+" if delta >= 0 else ""
        md.append(f"**Trend:** {prior_score} → {total} ({sign}{delta})")
    if defense_notes:
        md.append(f"**Defense round:** {'; '.join(defense_notes)}")
    md.append("\n## Dimension scores\n")
    md.append("| Dimension | Score | Max | Why |")
    md.append("|-----------|------:|----:|-----|")
    md.append(f"| Implementation completeness vs. spec | {s_impl} | {weights['implementation']} | {'; '.join(n_impl) or 'see evidence.json + compliance.json'} |")
    md.append(f"| Required tests present and meaningfully passing | {s_tests} | {weights['tests']} | {'; '.join(n_tests) or 'see compliance.json'} |")
    md.append(f"| Anti-theater | {s_at} | {weights['anti_theater']} | {'; '.join(n_at)} |")
    md.append(f"| Test depth | {s_td} | {weights['test_depth']} | {'; '.join(n_td)} |")
    md.append(f"| Docs / migrations / telemetry / flags | {s_de} | {weights['docs_etc']} | {'; '.join(n_de)} |")
    md.append(f"| Cross-bead integration | {s_cb} | {weights['cross_bead']} | {'; '.join(n_cb)} |")
    md.append(f"| **TOTAL** | **{total}** | **1000** | |\n")
    md.append("## Citations\n")
    for f in ("spec.json", "evidence.json", "compliance.json", "theater.json", "test_depth.json", "defense.json"):
        if (bd / f).exists():
            md.append(f"- {f}: `{bd / f}`")
    md.append(f"- raw logs: `{bd / 'raw'}/`\n")
    md.append("## Missing items (verbatim)\n")
    missing = []
    for c in evidence.get("checks", []):
        if c.get("status") == "MISSING":
            missing.append(f"- spec item `{c['spec_item_id']}` — {c.get('notes', 'no notes')}")
    for c in compliance.get("checks", []):
        if c.get("verdict") in ("FAIL", "MISSING"):
            missing.append(f"- check `{c['spec_item_id']}` ({c.get('verdict')}) — {c.get('failure_reason', '')}")
    for f in theater.get("findings", []):
        if f.get("severity") == "BLOCKING":
            path = f.get("path") or "<global>"
            line = f.get("line") or "?"
            desc = f.get("description") or f.get("reason") or "blocking theater finding"
            missing.append(f"- theater [{f.get('severity')}] `{path}:{line}` — {desc}")
    if not missing:
        md.append("(none — all spec items satisfied)")
    else:
        md.extend(missing)

    atomic_write_text(bd / "scorecard.md", "\n".join(md) + "\n")
    # Print the score to stdout for the calling script. Use stderr-flush+
    # stdout-flush ordering so a caller redirecting stdout (e.g. `python3
    # score-bead.py > scorecard.md`, an operator anti-pattern) cannot race
    # with the atomic rename above.
    sys.stdout.flush()
    print(json.dumps({"bead_id": bead_id, "score": total, "band": band, "false_closed": false_closed}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
