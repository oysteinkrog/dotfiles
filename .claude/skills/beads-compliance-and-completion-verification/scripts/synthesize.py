#!/usr/bin/env python3
"""synthesize.py — Phase 7: cross-bead integration / contradiction synthesis.

Usage:
    synthesize.py <pass-dir>

Reads every bead's spec.json + evidence.json + show.json under the pass dir.
Produces synthesis.md with:
    - Integration gaps (bead A consumes bead B; contract drift)
    - Contradictions (two closed beads making conflicting claims)
    - Orphaned ACs
    - Dependency-graph anomalies
    - Bead-graph truthfulness flags

Heuristic implementation; the subagent (subagents/cross-bead-synthesizer.md)
can produce richer synthesis with model reasoning. This script is the
deterministic baseline that always runs.
"""
from __future__ import annotations

import json
import re
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any


# Broad bead-id pattern. br defaults to `bd-` but projects can override
# (and br auto-generates project-prefixed ids when the workspace is nameless).
# Child beads use `<parent>.<n>` form (e.g., `bd-foo.1`).
#
# Design choices:
#   - REQUIRE at least one hyphen-separated segment after the prefix to
#     reject version numbers (`v1.2`) and dotted identifiers (`tokio.sync`).
#   - Allow continuation via more hyphen segments OR `.<digits>` (the actual
#     child-bead form). Critically NOT `.<word>` — `bd-foo.bar` should match
#     only `bd-foo`, and `closing bd-foo.` should match `bd-foo` (not error
#     because the trailing `.` looks like an aborted child suffix).
#   - No trailing lookahead/`\b` — the alternation alone correctly stops
#     consumption at the right boundary in all tested cases.
#
# Used as the LAST-RESORT regex when we don't yet know the project's bead-id
# prefix. The default project prefix is derived from inventory.jsonl in main()
# and a project-specific compiled regex is preferred everywhere it's
# available. Without prefix-anchoring, hyphenated technical terms (RUSTSEC-
# 2026-0002, Content-Length, vim-style, all-targets, ...) would otherwise
# false-positive as bead IDs, polluting synthesis.md with hundreds of
# bogus "orphaned AC" rows.
BEAD_ID_RE = re.compile(r"\b([a-z][a-z0-9_]*-[a-z0-9_]+(?:-[a-z0-9_]+|\.\d+)*)", re.I)


def derive_project_bead_re(project_ids: list[str]) -> re.Pattern[str] | None:
    """Build a project-specific bead-id regex from observed inventory IDs.

    The prefix is everything up to AND INCLUDING the LAST hyphen of the
    longest common prefix of the IDs. Example: ids =
        ["coding_agent_session_search-001", "coding_agent_session_search-zz8ni"]
    → prefix = "coding_agent_session_search-".

    Returned regex matches IDs that start with that prefix and continue with
    the same trailing-segment grammar as BEAD_ID_RE. Returns None when no
    consistent prefix could be derived (e.g. mixed-prefix universe), in
    which case callers fall back to BEAD_ID_RE.
    """
    if not project_ids:
        return None
    # Longest common prefix across all ids.
    lcp = project_ids[0]
    for sid in project_ids[1:]:
        i = 0
        while i < len(lcp) and i < len(sid) and lcp[i] == sid[i]:
            i += 1
        lcp = lcp[:i]
        if not lcp:
            return None
    # Trim to last hyphen so the prefix is a real bead-id stem (avoid
    # mid-segment cuts like "bd-fo" when the corpus has bd-foo and bd-foobar).
    if "-" not in lcp:
        return None
    prefix = lcp[: lcp.rfind("-") + 1]
    if not prefix or not prefix.endswith("-"):
        return None
    # Build a regex that requires the prefix and accepts the canonical bead-id
    # tail grammar.
    escaped = re.escape(prefix)
    return re.compile(
        rf"\b({escaped}[a-z0-9_]+(?:-[a-z0-9_]+|\.\d+)*)", re.I
    )


def load_bead_dir(d: Path) -> dict[str, Any]:
    # Explicit type — mypy otherwise infers `dict[str, str]` from the
    # initial literal and rejects the dict-valued assignments below.
    out: dict[str, Any] = {"id": d.name}
    for name in ("show.json", "spec.json", "evidence.json"):
        p = d / name
        if p.exists():
            try:
                out[name.replace(".json", "")] = json.loads(p.read_text())
            except Exception:
                out[name.replace(".json", "")] = {}
        else:
            out[name.replace(".json", "")] = {}
    return out


def find_bead_refs(
    text: str | None,
    exclude: str = "",
    project_re: re.Pattern[str] | None = None,
    by_id: dict[str, Any] | None = None,
) -> set[str]:
    """Extract bead-id references from `text`.

    `project_re`, when supplied, restricts matches to the project's own
    prefix — this is the strong signal. When absent we fall back to the
    looser BEAD_ID_RE and additionally require that each candidate appear
    in `by_id` (so e.g. `Content-Length` no longer false-positives as a
    bead reference unless the project actually has a bead with that id).
    """
    if not text:
        return set()
    if project_re is not None:
        refs = set(project_re.findall(text))
    else:
        candidates = set(BEAD_ID_RE.findall(text))
        if by_id is None:
            refs = candidates
        else:
            refs = {c for c in candidates if c in by_id}
    refs.discard(exclude)
    return refs


def main() -> int:
    if len(sys.argv) >= 2 and sys.argv[1] in ("--help", "-h"):
        print(__doc__)
        return 0
    if len(sys.argv) < 2:
        print("Usage: synthesize.py <pass-dir>", file=sys.stderr)
        return 2
    pass_dir = Path(sys.argv[1])
    beads_dir = pass_dir / "beads"
    if not beads_dir.exists():
        print("No beads/ directory in pass dir", file=sys.stderr)
        return 2

    beads = [load_bead_dir(d) for d in sorted(beads_dir.iterdir()) if d.is_dir()]
    by_id = {b["id"]: b for b in beads}

    integration_gaps: list[tuple[str, str, str]] = []
    orphan_acs: list[tuple[str, str, str]] = []
    dep_anomalies: list[tuple[str, str, str]] = []
    truthfulness_flags: list[tuple[str, str, str]] = []
    cross_refs: list[tuple[str, str, str]] = []

    # Initialize dep-enrichment state at top of main so the Coverage notes
    # section below can reference these regardless of whether inventory.jsonl
    # exists (guards against NameError in the no-inventory case).
    all_ids: list[str] = []
    db_args: list[str] = []
    # MAX_PROBES caps the number of beads we query `br dep list` for. Each
    # probe is a subprocess; on universes of 1000+ beads, an uncapped run
    # adds 30+ seconds of wall time. The cap is overridable via the
    # SYNTHESIZE_MAX_PROBES env var so swarm-tier runs that need full coverage
    # can opt in. We also emit a stderr warning at run time AND write a
    # machine-readable `synthesis_coverage.json` — relying on the synthesis.md
    # footer alone hid the cap from operators (Bug 10 in v1.0).
    import os
    try:
        MAX_PROBES = int(os.environ.get("SYNTHESIZE_MAX_PROBES", "500"))
    except ValueError:
        MAX_PROBES = 500

    # Derive a project-specific bead-id regex so we don't match every
    # hyphenated technical term (RUSTSEC-2026-0002, Content-Length, ...) as
    # a bead reference. The regex is derived from the longest common prefix
    # of all known bead IDs in this universe; falls back to the loose
    # BEAD_ID_RE only when the prefix can't be derived.
    project_bead_re = derive_project_bead_re(sorted(by_id.keys()))

    for b in beads:
        bid = b["id"]
        show = b.get("show", {}) or {}
        spec = b.get("spec", {}) or {}
        ev = b.get("evidence", {}) or {}
        body = " ".join([
            show.get("description") or "",
            show.get("design") or "",
            show.get("acceptance_criteria") or "",
            show.get("notes") or "",
            show.get("close_reason") or "",
        ])
        # 1) Cross-references: which other beads does this one mention?
        for ref in find_bead_refs(body, exclude=bid, project_re=project_bead_re, by_id=by_id):
            cross_refs.append((bid, ref, "body mentions " + ref))
            # If the referenced bead's status is closed but a child of this
            # bead's spec mentions an unmet requirement, flag orphan AC.
            other = by_id.get(ref)
            if other:
                other_status = (other.get("show") or {}).get("status", "unknown")
                if isinstance(other_status, dict):
                    other_status = next(iter(other_status.values()), "unknown")
                if str(other_status).lower() != "closed":
                    truthfulness_flags.append(
                        (bid, ref, f"references non-closed bead {ref} (status={other_status})")
                    )

        # 2) Acceptance criteria orphans: AC bullets that delegate to another bead
        ac_text = (show.get("acceptance_criteria") or "")
        for line in ac_text.splitlines():
            for ref in find_bead_refs(line, exclude=bid, project_re=project_bead_re, by_id=by_id):
                other = by_id.get(ref)
                if not other:
                    # Only emit "references unknown bead" when the candidate
                    # actually matches the project prefix (so we don't false-
                    # positive on hyphenated phrases). The project_re path
                    # guarantees this; the fallback path would never reach
                    # this branch because find_bead_refs already filters by
                    # by_id.
                    orphan_acs.append((bid, line.strip()[:80], f"references unknown bead {ref}"))
                else:
                    other_evidence = (other.get("evidence") or {}).get("checks", [])
                    if not other_evidence or all(c.get("status") == "MISSING" for c in other_evidence):
                        orphan_acs.append((bid, line.strip()[:80], f"delegates to {ref} but {ref} has no evidence"))

        # 3) Dep anomalies: closed bead with all dependents still open
        # (read from inventory.jsonl if available)
        # Implemented best-effort below via inventory iteration

    # Dependency-graph: parse inventory.jsonl for status, then optionally fetch
    # actual dep edges via `br dep list <id> --json` per bead. Inventory shows
    # whether a bead has dependencies but the edge data lives in br's separate
    # dependencies table; show.json doesn't include it.
    inv_path = pass_dir / "inventory.jsonl"
    manifest_path = pass_dir / "manifest.json"
    if inv_path.exists():
        import subprocess
        deps_by_parent: dict[str, list[str]] = defaultdict(list)
        status_by_id: dict[str, str] = {}
        for line in inv_path.read_text().splitlines():
            try:
                obj = json.loads(line)
            except Exception:
                continue
            sid = obj.get("id", "")
            if not sid:
                continue
            all_ids.append(sid)
            status = obj.get("status", "unknown")
            if isinstance(status, dict):
                status = next(iter(status.values()), "unknown")
            status_by_id[sid] = str(status).lower()

        # Resolve the project's bead DB path. synthesize.py runs from the skill
        # dir, NOT the project dir, so br won't auto-discover .beads/ unless we
        # pass --db explicitly. Skip dep enrichment entirely if we can't find it.
        if manifest_path.exists():
            try:
                project_path = json.loads(manifest_path.read_text()).get("project_path")
                if project_path:
                    beads_dir = Path(project_path) / ".beads"
                    if beads_dir.exists():
                        dbs = sorted(beads_dir.glob("*.db"))
                        if dbs:
                            db_args = ["--db", str(dbs[0])]
            except Exception:
                pass

        # Best-effort: query br for each bead's dependencies. Skipped if br is
        # not on PATH OR we couldn't resolve --db. Capped at MAX_PROBES to bound
        # subprocess overhead on huge bead universes (1000+ beads).
        # Only emit the cap-warning when we'd actually run the probe loop;
        # otherwise the message is misleading (no probes are about to happen).
        if db_args and len(all_ids) > MAX_PROBES:
            print(
                f"WARNING: synthesize.py: {len(all_ids)} beads in inventory; "
                f"dep-graph enrichment capped at first {MAX_PROBES}. "
                f"Beads beyond the cap will have NO dep-anomaly data in this pass. "
                f"Set SYNTHESIZE_MAX_PROBES=<n> to override (e.g. "
                f"SYNTHESIZE_MAX_PROBES={len(all_ids)}).",
                file=sys.stderr,
            )
        try:
            if not db_args:
                # Don't hammer br with no DB context — would auto-discover from
                # the wrong cwd and either fail or pick up an unrelated store.
                raise FileNotFoundError("no project DB resolved")
            for sid in all_ids[:MAX_PROBES]:
                proc = subprocess.run(
                    ["br", *db_args, "dep", "list", sid, "--json"],
                    capture_output=True, text=True, timeout=15, check=False,
                )
                if proc.returncode != 0 or not proc.stdout.strip():
                    continue
                try:
                    payload = json.loads(proc.stdout)
                except Exception:
                    continue
                # br dep list returns: [{"issue_id":..,"depends_on_id":..,"type":..,...}, ...]
                # Handle: bare array (current format), or {"dependencies":[...]} envelope.
                if isinstance(payload, dict):
                    deps_list = payload.get("dependencies") or payload.get("deps") or []
                else:
                    deps_list = payload if isinstance(payload, list) else []
                for dep in deps_list:
                    if isinstance(dep, dict):
                        # br emits depends_on_id (current); fall back to other names
                        # for forward-compat with future shape changes.
                        parent = (dep.get("depends_on_id") or dep.get("depends_on")
                                  or dep.get("blocks_on") or dep.get("parent_id")
                                  or dep.get("from"))
                        if parent and parent != sid:  # don't self-loop
                            deps_by_parent[parent].append(sid)
                    elif isinstance(dep, str) and ":" in dep:
                        _, parent = dep.split(":", 1)
                        deps_by_parent[parent.strip()].append(sid)
        except FileNotFoundError:
            pass  # br not available OR no DB found; skip dep-edge enrichment
        except Exception:
            pass  # any other failure: degrade gracefully

        for parent_id, dependents in deps_by_parent.items():
            if status_by_id.get(parent_id) == "closed":
                open_deps = [d for d in dependents if status_by_id.get(d) not in ("closed", "tombstone")]
                if open_deps and len(open_deps) == len(dependents):
                    dep_anomalies.append(
                        (parent_id, ",".join(open_deps[:3]),
                         f"closed bead {parent_id} has {len(open_deps)} open dependents — verify integration")
                    )

    # Render synthesis.md
    out_lines: list[str] = []
    out_lines.append(f"# Cross-Bead Synthesis — Pass {pass_dir.name}\n")
    out_lines.append(f"Generated by `scripts/synthesize.py` over {len(beads)} beads.\n")

    out_lines.append("## Integration gaps\n")
    if integration_gaps:
        out_lines.append("| Producer | Consumer | Drift |")
        out_lines.append("|----------|----------|-------|")
        for p, c, drift in integration_gaps:
            out_lines.append(f"| `{p}` | `{c}` | {drift} |")
    else:
        out_lines.append("(none auto-detected — subagent may find more by reading evidence cross-shapes)")
    out_lines.append("")

    out_lines.append("## Orphaned ACs\n")
    if orphan_acs:
        out_lines.append("| Bead | AC bullet | Where it should have lived |")
        out_lines.append("|------|-----------|----------------------------|")
        # Escape `|` in the AC bullet — it is verbatim text from the user-
        # written acceptance_criteria and routinely contains pipes (e.g.
        # `Given X | When Y | Then Z` Gherkin-style ACs). Without escaping
        # the table row gains extra columns and visually breaks for the
        # reader. Same fix as master-report.py's `_esc_md_cell`. Computed
        # outside the f-string because backslash-in-expression is only legal
        # since Python 3.12 and this skill should work on 3.10/3.11 CI too.
        bar = "\\|"
        for bid, ac, where in orphan_acs:
            ac_safe = ac.replace("|", bar)
            out_lines.append(f"| `{bid}` | {ac_safe} | {where} |")
    else:
        out_lines.append("(none)")
    out_lines.append("")

    out_lines.append("## Dependency-graph anomalies\n")
    if dep_anomalies:
        out_lines.append("| Issue | Beads | Severity |")
        out_lines.append("|-------|-------|----------|")
        for parent, deps, desc in dep_anomalies:
            out_lines.append(f"| `{parent}` (closed) → open: `{deps}` | many | needs-review |")
    else:
        out_lines.append("(none — dependency graph is consistent)")
    out_lines.append("")

    out_lines.append("## Bead-graph truthfulness flags\n")
    if truthfulness_flags:
        out_lines.append("| Bead | References | Note |")
        out_lines.append("|------|------------|------|")
        for bid, ref, note in truthfulness_flags:
            out_lines.append(f"| `{bid}` | `{ref}` | {note} |")
    else:
        out_lines.append("(none)")
    out_lines.append("")

    out_lines.append("## Cross-references (for awareness)\n")
    out_lines.append(f"Found {len(cross_refs)} bead-to-bead references in bead bodies. "
                     "Use as raw signal for the senior synthesizer subagent.\n")

    # Honest disclosure when dep enrichment was capped or skipped — otherwise
    # users may interpret "no anomalies" as truth when really we just did not look.
    out_lines.append("## Coverage notes\n")
    if not db_args:
        # Specific reason helps the user fix the right thing.
        if not inv_path.exists():
            reason = "inventory.jsonl missing (Phase 1 inventory was not written)"
        elif not manifest_path.exists():
            reason = "manifest.json missing (audit dir not bootstrapped properly)"
        elif not all_ids:
            reason = "inventory.jsonl is empty (no beads found)"
        else:
            reason = ("could not resolve project's bead DB — manifest.json "
                      "lacks `project_path`, the path is unreachable, or "
                      "`<project>/.beads/*.db` does not exist")
        out_lines.append(
            f"⚠ Dependency-graph enrichment was SKIPPED — {reason}. "
            "The dep-anomalies section above reflects only what could be derived "
            "without querying `br dep list`. To enable full dep-anomaly "
            "detection, ensure the audit dir bootstrap recorded a reachable "
            "`project_path` and the project's `.beads/` is intact.\n"
        )
    elif len(all_ids) > MAX_PROBES:
        out_lines.append(
            f"⚠ Dependency-graph enrichment was CAPPED at the first {MAX_PROBES} "
            f"of {len(all_ids)} beads to bound subprocess overhead. Beads beyond "
            f"the cap are unaudited for dep anomalies in this pass. To enable "
            f"full coverage, set the `SYNTHESIZE_MAX_PROBES` env var (e.g. "
            f"`SYNTHESIZE_MAX_PROBES={len(all_ids)} synthesize.py <pass-dir>`) "
            f"before re-running. The same warning was emitted on stderr at "
            f"run time so it isn't only visible in this footer.\n"
        )
    else:
        out_lines.append(
            f"✓ Dependency-graph enrichment completed for all {len(all_ids)} beads.\n"
        )

    syn_path = pass_dir / "synthesis.md"
    syn_path.write_text("\n".join(out_lines) + "\n")

    # Emit a machine-readable coverage envelope alongside synthesis.md so
    # downstream tooling (master-report.py, validate-audit-dir.py) can detect
    # capped runs without parsing markdown. Stored under
    # <pass-dir>/synthesis_coverage.json.
    coverage_payload = {
        "total_beads": len(all_ids),
        "max_probes": MAX_PROBES,
        "probed_beads": min(len(all_ids), MAX_PROBES),
        "capped": len(all_ids) > MAX_PROBES,
        "db_resolved": bool(db_args),
        "integration_gaps": len(integration_gaps),
        "orphan_acs": len(orphan_acs),
        "dep_anomalies": len(dep_anomalies),
        "truthfulness_flags": len(truthfulness_flags),
    }
    (pass_dir / "synthesis_coverage.json").write_text(
        json.dumps(coverage_payload, indent=2) + "\n"
    )

    print(f"Wrote {syn_path} ({len(integration_gaps)} integration gaps, "
          f"{len(orphan_acs)} orphan ACs, {len(dep_anomalies)} dep anomalies)",
          file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
