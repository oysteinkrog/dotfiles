#!/usr/bin/env python3
"""portfolio-rollup.py — Aggregate per-repo audit dirs into a portfolio summary.

Usage:
    portfolio-rollup.py <parent-dir>

Reads:
    <parent>/<repo>/beads_compliance_audit/manifest.json
    <parent>/<repo>/beads_compliance_audit/REPORT.md (latest)

Writes (to stdout):
    Portfolio summary markdown — headline KPIs, per-project ranking, worst-of-
    the-worst beads, and recommended actions.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from statistics import median


SCORE_RE = re.compile(r"\*\*Score:\s+(\d+)\s*/\s*1000\*\*", re.M)
STATUS_RE = re.compile(r"\*\*Status \(claimed\):\*\*\s+(\S+)", re.M)
TITLE_RE = re.compile(r"\*\*Title:\*\*\s+(.+)", re.M)


def _fmt_number(value) -> str:
    return f"{value:g}"


def latest_pass(audit_dir: Path) -> Path | None:
    passes = sorted((audit_dir / "passes").glob("*/"))
    return passes[-1] if passes else None


def parse_pass(audit_dir: Path) -> dict | None:
    manifest_path = audit_dir / "manifest.json"
    if not manifest_path.exists():
        return None
    manifest = json.loads(manifest_path.read_text())
    latest = latest_pass(audit_dir)
    if not latest:
        return None
    bead_scores: list[tuple[str, int, str, str]] = []
    for sc in (latest / "beads").glob("*/scorecard.md"):
        txt = sc.read_text()
        s_m = SCORE_RE.search(txt)
        st_m = STATUS_RE.search(txt)
        t_m = TITLE_RE.search(txt)
        if s_m:
            bead_scores.append((
                sc.parent.name,
                int(s_m.group(1)),
                st_m.group(1) if st_m else "unknown",
                t_m.group(1).strip()[:80] if t_m else "",
            ))
    threshold = manifest.get("score_threshold", 700)
    closed = [b for b in bead_scores if b[2] == "closed"]
    fc = [b for b in closed if b[1] < threshold]
    convergence = manifest.get("convergence") or {}
    return {
        "project": manifest.get("project_path", str(audit_dir.parent)),
        "name": Path(manifest.get("project_path", "unknown")).name,
        "audit_dir": str(audit_dir),
        "threshold": threshold,
        "pass_completed_at": manifest.get("pass_completed_at"),
        "total_beads": len(bead_scores),
        "closed_beads": len(closed),
        "false_closed": len(fc),
        "false_closed_rate": (len(fc) / len(closed)) if closed else 0.0,
        "score_median": median([b[1] for b in bead_scores]) if bead_scores else 0,
        "is_converged": convergence.get("is_converged"),
        "worst_beads": sorted(fc, key=lambda b: b[1])[:5],
    }


def main() -> int:
    # Use argparse for proper `--help` support. The skill's contract (SKILL.md
    # § Scripts) says every executable script must respond to `--help`. The
    # earlier `Path(sys.argv[1])` fallback would silently treat `--help` as
    # the parent path and print "No audit dirs found under --help" — useless.
    p = argparse.ArgumentParser(
        description="Aggregate per-repo audit dirs under <parent-dir> into a "
                    "portfolio summary printed to stdout. Default parent: /data/projects.",
    )
    p.add_argument("parent_dir", nargs="?", default="/data/projects",
                   help="directory containing one or more repos each with a beads_compliance_audit/ subdir")
    args = p.parse_args()
    parent = Path(args.parent_dir)
    # Audit dirs now live INSIDE each project repo at <repo>/beads_compliance_audit/.
    # Glob one level deep to find them. (We deliberately avoid recursing further
    # so we don't pick up audit dirs nested inside vendored/cloned subprojects.)
    audit_dirs = sorted(parent.glob("*/beads_compliance_audit"))
    if not audit_dirs:
        print(f"# Portfolio summary\n\nNo audit dirs found under {parent}.")
        return 0

    rows: list[dict] = []
    for ad in audit_dirs:
        try:
            r = parse_pass(ad)
            if r:
                rows.append(r)
        except Exception as e:
            print(f"<!-- skipping {ad}: {e} -->", file=sys.stderr)

    if not rows:
        print(f"# Portfolio summary\n\n{len(audit_dirs)} audit dirs found but none parsable.")
        return 0

    rows.sort(key=lambda r: r["false_closed_rate"], reverse=True)

    total_beads = sum(r["total_beads"] for r in rows)
    total_closed = sum(r["closed_beads"] for r in rows)
    total_fc = sum(r["false_closed"] for r in rows)
    portfolio_fc_rate = (total_fc / total_closed * 100) if total_closed else 0.0
    medians = [r["score_median"] for r in rows]
    converged = sum(1 for r in rows if r["is_converged"] is True)

    out: list[str] = []
    out.append("# Portfolio Compliance Summary")
    out.append(f"Generated: `{datetime.now(timezone.utc).isoformat()}`  |  "
               f"Projects audited: {len(rows)}")
    out.append("")
    out.append("## Headline\n")
    out.append("| Metric | Value |")
    out.append("|--------|------:|")
    out.append(f"| Total beads across portfolio       | {total_beads:,} |")
    out.append(f"| Total closed beads                  | {total_closed:,} |")
    out.append(f"| Total false-closed across portfolio | {total_fc:,} |")
    out.append(f"| Portfolio false-closed rate         | {portfolio_fc_rate:.1f}% |")
    out.append(f"| Median per-project score            | {_fmt_number(median(medians)) if medians else 0} |")
    out.append(f"| Number of converged projects        | {converged} / {len(rows)} |")

    out.append("\n## Per-project ranking (worst false-closed rate first)\n")
    out.append("| Project | Closed | False-closed | Rate | Score median | Convergence | Last pass |")
    out.append("|---------|-------:|-------------:|-----:|-------------:|:-----------:|-----------|")
    for r in rows:
        cv = "✓" if r["is_converged"] is True else ("✗" if r["is_converged"] is False else "—")
        last = (r["pass_completed_at"] or "")[:10]
        rate = f"{r['false_closed_rate']*100:.1f}%"
        out.append(f"| {r['name']} | {r['closed_beads']} | {r['false_closed']} | {rate} | "
                   f"{_fmt_number(r['score_median'])} | {cv} | {last} |")

    # Worst-of-worst
    all_worst: list[tuple[str, str, int, str]] = []
    for r in rows:
        for bead_id, score, _, title in r["worst_beads"]:
            all_worst.append((r["name"], bead_id, score, title))
    all_worst.sort(key=lambda x: x[2])

    out.append("\n## Worst-of-the-worst beads (top 20 across portfolio)\n")
    out.append("| Bead | Project | Score | Title |")
    out.append("|------|---------|------:|-------|")
    # Escape `|` in titles so a bead title containing a pipe (e.g.
    # `refactor: split foo | bar`) does not break the markdown table row,
    # mirroring master-report.py's `_esc_md_cell`. Computed via a separate
    # variable rather than inline in the f-string so the file stays
    # compatible with Python <3.12 (backslash-in-fstring-expression is
    # only legal since 3.12).
    bar = "\\|"
    for project, bead_id, score, title in all_worst[:20]:
        title_safe = title.replace("|", bar)
        out.append(f"| `{bead_id}` | {project} | {score} | {title_safe} |")

    out.append("\n## Recommended actions\n")
    if rows[0]["false_closed_rate"] > 0.20:
        out.append(f"1. **{rows[0]['name']}** has the worst false-closed rate "
                   f"({rows[0]['false_closed_rate']*100:.1f}%). Run a Comprehensive-mode "
                   f"audit and start remediation work.")
    if any(r["is_converged"] is True for r in rows):
        out.append(f"2. **{converged} of {len(rows)} projects converged.** Maintain those with "
                   f"weekly tripwire (see references/CI-TRIPWIRE.md).")
    # `.rstrip("Z").replace("Z", "+00:00")` was a no-op (the rstrip already
    # removes the Z, so the replace had nothing to act on). Just replace once.
    # Wrap in try/except: a malformed timestamp from one bad manifest
    # shouldn't crash the entire portfolio rollup.
    def _is_stale(s: str | None, days: int = 30) -> bool:
        if not s:
            return False
        try:
            parsed = datetime.fromisoformat(s.replace("Z", "+00:00"))
        except (ValueError, TypeError, AttributeError):
            return False
        return (datetime.now(timezone.utc) - parsed).days > days

    stale = [r for r in rows if _is_stale(r.get("pass_completed_at"))]
    if stale:
        out.append(f"3. **{len(stale)} project(s) have stale audits (> 30 days).** Re-run them: "
                   f"{', '.join(r['name'] for r in stale[:5])}.")

    print("\n".join(out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
