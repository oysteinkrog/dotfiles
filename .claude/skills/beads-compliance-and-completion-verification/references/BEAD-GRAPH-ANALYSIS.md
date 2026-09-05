# BEAD-GRAPH-ANALYSIS.md — Using `/bv` Graph Metrics In The Audit

<!-- TOC: Why graph metrics | The 7 metrics | Per-bead PageRank as audit weight | Critical-path beads | Slack analysis | Articulation points | Cycles must be empty | Integration with phases -->

> `/bv` (`beads_viewer`) computes deterministic graph metrics over the bead DAG: PageRank, betweenness, HITS, eigenvector, critical path, k-core, articulation points, slack. The audit uses these to **weight beads by importance** so prioritization, scoring, and synthesis reflect graph centrality, not just per-bead evidence quality.

---

## Why graph metrics matter for auditing

A bead's score in the rubric measures *internal* completeness (was THIS bead actually done?). Graph metrics measure *positional* importance (does this bead's status matter to the project?).

A perfect bead in a backwater corner of the graph is less important than a 700-scoring bead at the critical path's bottleneck. The audit uses graph metrics to:

1. **Order remediation** — fix high-PageRank beads first (most downstream impact).
2. **Inform scoring** — Phase 8 dimension 6 (cross-bead) reflects synthesis findings weighted by graph centrality.
3. **Surface bottlenecks** — articulation points / critical-path beads get extra scrutiny in synthesis.
4. **Detect cycles** — the audit refuses to score a project with cycles in `br dep cycles --json`.

---

## The 7 metrics (bv --robot-insights)

```bash
bv --robot-insights | jq '.'
```

Returns:

| Metric | Meaning | Audit use |
|--------|---------|-----------|
| **PageRank** | Authority centrality (how much downstream depends on this bead) | Order remediation by descending PageRank |
| **Betweenness** | Bridge centrality (how many shortest paths pass through this bead) | Bottleneck identification |
| **HITS** (auth/hub) | Authority and hub scores | Auth = bead-graph "leaders"; Hub = beads that depend on many leaders |
| **Eigenvector** | Influence centrality (similar to PageRank but symmetric) | Cross-validation of PageRank |
| **Critical path** | Longest dependency chain | Beads on critical path get +25% remediation priority |
| **k-core** | Densest connected subgraph | High-k beads form interconnected clusters; flag for synthesis |
| **Cycles** | Circular dependencies | MUST be empty; cycles invalidate audit semantics |
| **Articulation points** | Beads whose removal disconnects the graph | Highest-stakes beads |
| **Slack** | Gap between earliest and latest scheduling | Negative slack = behind schedule |

Two-phase output:
- **Phase 1 (instant):** degree, topo sort, density.
- **Phase 2 (async, 500ms timeout):** PageRank, betweenness, HITS, eigenvector, cycles.

The audit captures both at Phase 1 of the audit (Phase 1 of bv = instant; well before our test execution begins).

---

## Per-bead PageRank as audit weight

After Phase 1 of the audit captures `dag.json` (via `bv --robot-graph --graph-format json`), the orchestrator runs:

```bash
bv --robot-insights --beads-jsonl "$PASS_DIR/inventory.jsonl" \
  > "$PASS_DIR/graph_metrics.json" 2>/dev/null || true
```

Then for every bead:

```bash
PAGERANK=$(jq -r --arg id "$ID" '.PageRank[$id] // 0' "$PASS_DIR/graph_metrics.json")
```

Phase 8's scorer reads this value and applies a weighted-importance bonus:

```python
# In score-bead.py (future enhancement)
graph_weight = pagerank * 100  # rough scaling
# Bonus: high-PageRank beads scoring well get +0 (no penalty), but high-PageRank
# beads scoring poorly get amplified consequence in REPORT.md exec summary.
```

The score itself doesn't change — determinism is preserved — but the **executive summary** highlights high-PageRank false-closed beads first:

```markdown
## Executive summary

- 35 false-closed beads detected.
- **Highest-PageRank false-closed:** bd-XXX (PR=0.082, score=287) — central dependency, 7 downstream beads blocked.
- **Highest-betweenness false-closed:** bd-YYY (BC=0.245, score=512) — bottleneck on critical path.
```

This nudges human triage toward the beads whose status genuinely matters.

---

## Critical-path beads

```bash
bv --robot-insights | jq '.CriticalPath'
```

Returns the longest dependency chain. Each bead on this path gets:

1. **+1 to dimension 6 weight** in the scorer's per-bead rubric (small bump).
2. **Inclusion in the executive summary** even if scoring well — "these beads are on the critical path; verify they remain healthy."
3. **Tighter convergence threshold** — score deltas of ±5 (instead of ±10) trigger non-convergence for critical-path beads.

The motivation: a bead on the critical path is more sensitive to drift; small score changes there matter more than at the periphery.

---

## Slack analysis

`bv --robot-insights | jq '.Slack'` returns per-bead slack (in days). Negative slack = the bead is behind schedule (its dependencies finished later than expected).

Audit use: a *closed* bead with negative slack of more than 7 days is suspect. Why was it closed late? Often because the team rushed to close it without proper verification. The auditor cross-references negative-slack closures with `closed_by_session` for batch-close patterns.

---

## Articulation points

`bv --robot-insights | jq '.ArticulationPoints'` returns beads whose removal disconnects the graph. These are the **highest-stakes** beads in the project — their failure propagates widely.

Audit policy: every articulation-point bead, regardless of score, gets:
- **Inclusion in REPORT.md's "Articulation points" subsection** (always present, even if all healthy).
- **Mandatory Phase 6 deep-coverage check** (line + branch).
- **Mandatory Phase 7 contract verification** with all dependents.
- **Phase 10 spot-check eligibility weighting** — articulation points are 3× more likely to be selected for fresh-eyes verification.

---

## Cycles must be empty

```bash
bv --robot-insights | jq '.Cycles'
```

A non-empty cycles list = invalid bead-graph state. The audit refuses to proceed:

```bash
if [ "$(jq '.Cycles | length' "$PASS_DIR/graph_metrics.json")" != "0" ]; then
  echo "ERROR: bead graph has cycles. Run 'br dep cycles' to identify, then break them." >&2
  exit 4
fi
```

Cycles invalidate dependency-aware remediation and convergence semantics. Fix them via `br dep remove <child> <parent>` before continuing.

---

## Integration with phases

| Phase | Graph metric used | How |
|------:|-------------------|-----|
| 1 | Cycles | Hard-fail if non-empty |
| 1 | DAG capture | Save to `dag.json` |
| 7 | Articulation points, k-core | Surface clustered/critical beads in synthesis.md |
| 8 | PageRank, betweenness | Weight executive summary entries |
| 9 | PageRank, critical path | Order remediation list |
| 10 | Articulation points | 3× weighting in fresh-eyes spot-check selection |

---

## Visualization

The HTML dashboard includes a graph-centrality chart (top 20 beads by PageRank, colored by audit score) so users can see at a glance whether high-importance beads are healthy.

```bash
bv --export-graph "$AUDIT_DIR/dependency_graph.html"
```

This produces an interactive D3-based force graph where each node's size = PageRank, color = audit score band.

---

## Limits of graph analysis

Graph metrics tell you which beads are *positionally* important. They don't tell you which beads are *strategically* important to the user. A bead at low PageRank may be a P0 customer commitment; a bead at high PageRank may be infrastructure scaffolding nobody cares about.

**Use graph metrics as a Bayesian prior, not as a verdict.** Combine with priority + label + consequence-class weighting from `REMEDIATION-PRIORITIZATION.md`.

---

## Worked example

Project has 247 closed beads. Phase 7 finds 35 false-closed. Without graph analysis, the remediation list is sorted by score:

```
bd-FOO (score 187) [low PageRank — backwater module]
bd-BAR (score 245) [high PageRank — central dependency]
bd-BAZ (score 287) [low PageRank]
...
```

Remediator would tackle FOO first (lowest score). But BAR, despite scoring 245, is far more impactful (high PageRank → 12 downstream beads depend on it being correct).

With graph analysis, the executive summary surfaces BAR first:

```
🚨 Highest-impact false-closed:
  1. bd-BAR (score 245, PageRank 0.082, blocks 12 downstream)
  2. bd-XYZ (score 412, PageRank 0.065, on critical path)
  3. bd-FOO (score 187, PageRank 0.001, isolated)
```

The user immediately sees that BAR is the fire, not FOO.