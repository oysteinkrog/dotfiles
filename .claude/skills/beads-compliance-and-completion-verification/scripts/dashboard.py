#!/usr/bin/env python3
"""dashboard.py — Emit an HTML dashboard from an audit dir's trends.

Usage:
    dashboard.py <audit-dir> [--output <path>]

Reads:
    <audit-dir>/trends.md           score-per-bead-per-pass table
    <audit-dir>/passes/*/REPORT.md  per-pass summary stats
    <audit-dir>/manifest.json       latest convergence + counts

Emits a single self-contained HTML file with:
    - Headline KPIs (total beads, false-closed count, convergence)
    - Score distribution histogram (latest pass)
    - Score median over passes (line chart)
    - False-closed count over passes (bar chart)
    - Per-bead trajectories (top 20 worst)
    - Per-agent close-quality (if closed_by_session populated)

Pure-stdlib (no matplotlib / plotly). Renders charts as inline SVG.
"""
from __future__ import annotations

import argparse
import html
import json
import re
import sys
from collections import defaultdict
from collections.abc import Sequence
from pathlib import Path
from statistics import median


# Match trends.md rows: `| <pass-id> | `<bead-id>` | <score> |`
# bead-id is whatever's between the backticks (any prefix, including child
# beads with `.<n>` suffix; the `[^`]+` accepts everything between backticks).
TRENDS_ROW_RE = re.compile(r"^\|\s+(\S+?)\s+\|\s+`([^`]+)`\s+\|\s+(\d+)\s+\|\s*$")


def _fmt_number(value) -> str:
    return f"{value:g}"


def parse_trends(path: Path) -> dict[str, list[tuple[str, int]]]:
    """Returns: bead_id -> [(pass_id, score), ...]"""
    out: dict[str, list[tuple[str, int]]] = defaultdict(list)
    if not path.exists():
        return out
    for line in path.read_text().splitlines():
        m = TRENDS_ROW_RE.match(line)
        if m:
            pass_id, bead_id, score = m.group(1), m.group(2), int(m.group(3))
            out[bead_id].append((pass_id, score))
    return out


def latest_pass(audit_dir: Path) -> Path | None:
    passes = sorted((audit_dir / "passes").glob("*/"))
    return passes[-1] if passes else None


def parse_scorecard(sc_path: Path) -> dict | None:
    if not sc_path.exists():
        return None
    txt = sc_path.read_text()
    score_m = re.search(r"\*\*Score:\s+(\d+)", txt)
    band_m = re.search(r"\*\*Verdict:\s+(.+?)\*\*", txt)
    title_m = re.search(r"\*\*Title:\*\*\s+(.+)", txt)
    status_m = re.search(r"\*\*Status \(claimed\):\*\*\s+(\S+)", txt)
    return {
        "bead_id": sc_path.parent.name,
        "score": int(score_m.group(1)) if score_m else 0,
        "verdict": band_m.group(1).strip() if band_m else "unknown",
        "title": title_m.group(1).strip() if title_m else "",
        "status": status_m.group(1) if status_m else "unknown",
    }


def histogram_svg(scores: list[int], width: int = 500, height: int = 200) -> str:
    bins = [0] * 10  # 0-99, 100-199, ..., 900-999
    for s in scores:
        bins[min(s // 100, 9)] += 1
    if not bins or max(bins) == 0:
        return f'<svg width="{width}" height="{height}"><text x="10" y="20">No data</text></svg>'
    bar_w = width / 10
    max_h = max(bins)
    bars = []
    for i, count in enumerate(bins):
        # Minimum bar height of 2 pixels for any non-zero count, so small
        # values don't disappear into the axis.
        if count == 0:
            h = 0
        else:
            h = max(2, int((count / max_h) * (height - 30)))
        x = i * bar_w
        y = height - 20 - h
        # Color by band (matches scorecard verdict bands).
        floor = i * 100
        if floor >= 950: color = "#22c55e"
        elif floor >= 850: color = "#84cc16"
        elif floor >= 700: color = "#eab308"
        elif floor >= 500: color = "#f97316"
        elif floor >= 250: color = "#ef4444"
        else: color = "#7c2d12"
        bars.append(f'<rect x="{x:.1f}" y="{y}" width="{bar_w-2:.1f}" height="{h}" fill="{color}"/>')
        bars.append(f'<text x="{x + bar_w/2:.1f}" y="{height-5}" text-anchor="middle" font-size="10" fill="#666">{floor}</text>')
        if count > 0:
            bars.append(f'<text x="{x + bar_w/2:.1f}" y="{y - 3}" text-anchor="middle" font-size="11" fill="#000">{count}</text>')
    return f'<svg width="{width}" height="{height}" xmlns="http://www.w3.org/2000/svg">{"".join(bars)}</svg>'


def line_chart_svg(series: Sequence[tuple[str, float]], width: int = 500, height: int = 200, color: str = "#2563eb") -> str:
    if not series:
        return f'<svg width="{width}" height="{height}"><text x="10" y="20">No data</text></svg>'
    xs = list(range(len(series)))
    ys = [s[1] for s in series]
    y_max = max(ys) if ys else 1
    y_min = 0
    def xpx(i): return 40 + (i / max(1, len(series) - 1)) * (width - 60)
    def ypx(v): return height - 30 - ((v - y_min) / max(1, y_max - y_min)) * (height - 50)
    points = " ".join(f"{xpx(i):.1f},{ypx(y):.1f}" for i, y in enumerate(ys))
    circles = "".join(
        f'<circle cx="{xpx(i):.1f}" cy="{ypx(y):.1f}" r="3" fill="{color}"/>'
        for i, y in enumerate(ys)
    )
    # Y-axis labels
    y_labels = []
    for v in [y_min, y_max / 2, y_max]:
        y_labels.append(f'<text x="35" y="{ypx(v):.1f}" text-anchor="end" font-size="10" fill="#666">{_fmt_number(v)}</text>')
    return (
        f'<svg width="{width}" height="{height}" xmlns="http://www.w3.org/2000/svg">'
        f'<polyline points="{points}" fill="none" stroke="{color}" stroke-width="2"/>'
        f'{circles}'
        f'{"".join(y_labels)}'
        f'</svg>'
    )


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("audit_dir")
    p.add_argument("--output", default=None, help="Output HTML path; default <audit_dir>/dashboard.html")
    args = p.parse_args()

    audit_dir = Path(args.audit_dir)
    output = Path(args.output) if args.output else (audit_dir / "dashboard.html")

    # Tolerate a corrupt top-level manifest. The dashboard is a downstream
    # convenience artifact — it should still render headline + charts even
    # when manifest.json is malformed (e.g. partial write from a concurrent
    # bootstrap, or a hand-edit gone wrong). Without this guard the script
    # crashes with a traceback before writing dashboard.html.
    manifest_path = audit_dir / "manifest.json"
    if manifest_path.exists():
        try:
            manifest = json.loads(manifest_path.read_text())
        except Exception as exc:
            print(f"WARNING: manifest.json could not be parsed ({exc}); "
                  "rendering with defaults", file=sys.stderr)
            manifest = {}
    else:
        manifest = {}
    trends = parse_trends(audit_dir / "trends.md")
    latest = latest_pass(audit_dir)

    if not latest:
        print("ERROR: no passes/ directory yet", file=sys.stderr)
        return 2

    # Parse latest pass scorecards
    scorecards = [
        s for s in (parse_scorecard(sc) for sc in (latest / "beads").glob("*/scorecard.md"))
        if s is not None
    ]
    threshold = manifest.get("score_threshold", 700)
    false_closed = [s for s in scorecards if s["status"] == "closed" and s["score"] < threshold]

    # Score distribution
    scores = [s["score"] for s in scorecards]
    hist_svg = histogram_svg(scores)

    # Median per pass
    pass_medians: dict[str, list[int]] = defaultdict(list)
    for bead_id, ts in trends.items():
        for pass_id, score in ts:
            pass_medians[pass_id].append(score)
    median_series = sorted(
        [(pid, median(vals)) for pid, vals in pass_medians.items()],
        key=lambda x: x[0],
    )
    median_svg = line_chart_svg(median_series, color="#2563eb")

    # False-closed per pass (recompute by reading per-pass REPORT.md)
    fc_series: list[tuple[str, int]] = []
    for pdir in sorted((audit_dir / "passes").glob("*/")):
        rpt = pdir / "REPORT.md"
        if not rpt.exists():
            continue
        m = re.search(r"\*\*(\d+)\*\* false-closed", rpt.read_text())
        if m:
            fc_series.append((pdir.name, int(m.group(1))))
    fc_svg = line_chart_svg(fc_series, color="#ef4444")

    # Top 20 worst beads (latest pass) — show their trajectories
    worst = sorted(scorecards, key=lambda s: s["score"])[:20]

    # Render
    project = html.escape(manifest.get("project_path", "(unknown)"))
    convergence = manifest.get("convergence", {})
    converged = convergence.get("is_converged") if isinstance(convergence, dict) else None
    converged_badge = "✓ converged" if converged else ("✗ not converged" if converged is False else "— first pass")

    rows = []
    for s in worst:
        bid = s["bead_id"]
        ts = trends.get(bid, [])
        traj = " → ".join(str(score) for _, score in ts[-5:])
        rows.append(
            f"<tr><td><code>{html.escape(bid)}</code></td>"
            f"<td>{s['score']}</td>"
            f"<td>{html.escape(s['verdict'])}</td>"
            f"<td>{html.escape(s['title'][:60])}</td>"
            f"<td><code>{html.escape(traj or '—')}</code></td></tr>"
        )

    style = """
    body { font-family: -apple-system, system-ui, sans-serif; max-width: 1100px; margin: 2em auto; color: #111; padding: 0 1em; }
    h1, h2 { color: #1e293b; border-bottom: 1px solid #e2e8f0; padding-bottom: 0.3em; }
    table { border-collapse: collapse; width: 100%; margin-top: 1em; }
    th, td { padding: 0.4em 0.8em; border-bottom: 1px solid #e2e8f0; text-align: left; }
    th { background: #f1f5f9; font-weight: 600; }
    .kpi { display: inline-block; padding: 1em 1.5em; margin: 0.5em; background: #f8fafc; border-radius: 8px; min-width: 140px; vertical-align: top; }
    .kpi .v { font-size: 1.8em; font-weight: 700; color: #1e293b; display: block; }
    .kpi .l { font-size: 0.85em; color: #64748b; }
    .converged { color: #059669; }
    .not-converged { color: #dc2626; }
    code { background: #f1f5f9; padding: 0.1em 0.3em; border-radius: 3px; }
    .chart { margin: 1em 0; }
    """

    html_doc = f"""<!doctype html>
<html><head>
<meta charset="utf-8">
<title>Beads compliance dashboard — {project}</title>
<style>{style}</style>
</head><body>
<h1>Beads compliance dashboard</h1>
<p><strong>Project:</strong> <code>{project}</code><br>
<strong>Latest pass:</strong> <code>{latest.name}</code><br>
<strong>Convergence:</strong> <span class="{'converged' if converged else 'not-converged'}">{converged_badge}</span></p>

<h2>Headline</h2>
<div>
  <div class="kpi"><span class="v">{len(scorecards)}</span><span class="l">beads audited</span></div>
  <div class="kpi"><span class="v">{len(false_closed)}</span><span class="l">false-closed</span></div>
  <div class="kpi"><span class="v">{_fmt_number(median(scores)) if scores else 0}</span><span class="l">score median</span></div>
  <div class="kpi"><span class="v">{threshold}</span><span class="l">threshold</span></div>
</div>

<h2>Score distribution (latest pass)</h2>
<div class="chart">{hist_svg}</div>

<h2>Median score over passes</h2>
<div class="chart">{median_svg}</div>

<h2>False-closed count over passes</h2>
<div class="chart">{fc_svg}</div>

<h2>Worst 20 beads (latest pass)</h2>
<table>
  <thead><tr><th>Bead</th><th>Score</th><th>Verdict</th><th>Title</th><th>Trajectory (last 5)</th></tr></thead>
  <tbody>
    {''.join(rows)}
  </tbody>
</table>

<p style="color: #64748b; font-size: 0.85em; margin-top: 3em;">
Generated by <code>scripts/dashboard.py</code> from
<code>{html.escape(str(audit_dir))}</code> at {html.escape(latest.name)}.
</p>
</body></html>"""

    output.write_text(html_doc)
    print(f"Wrote {output}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
