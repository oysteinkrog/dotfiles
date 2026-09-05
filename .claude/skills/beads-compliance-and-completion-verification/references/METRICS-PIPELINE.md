# METRICS-PIPELINE.md — Audit Telemetry

<!-- TOC: Why metrics | Prometheus exporter | OpenTelemetry traces | Grafana dashboard | Alert rules | Long-horizon trend mining | What to alert on -->

> Once converged, the audit becomes a continuous-compliance signal. Exporting metrics turns each pass into a time series you can plot, alert on, and SLO against. Pattern adapted from `/saas-customer-analytics`'s subscription-metrics export.

---

## Why expose metrics

| Need | Metric source |
|------|---------------|
| Daily "is the bead graph still truthful?" alert | Prometheus + Alertmanager |
| Quarterly "is the project's quality trending up?" review | Grafana + audit history |
| Per-agent close-quality scoring | Time series tagged by `closed_by_session` |
| Project-portfolio health-at-a-glance | Multi-project Grafana panel |
| SLO definition ("audit converges within 4 passes of any regression") | Burn-rate alert |

---

## Prometheus exporter

`scripts/metrics-export.sh` (this file describes it; create the script if your CI / observability stack uses Prometheus):

```bash
#!/usr/bin/env bash
# Export latest pass's KPIs as Prometheus textfile collector format.
set -euo pipefail
AUDIT_DIR="${1:?audit dir}"
OUT="${2:-/var/lib/node_exporter/textfile_collector/beads_audit.prom}"

LATEST="$(ls -1d "$AUDIT_DIR/passes"/*/ 2>/dev/null | sort | tail -1)"
[ -n "$LATEST" ] || { echo "no passes" >&2; exit 1; }
MANIFEST="$LATEST/manifest.json"
PROJECT="$(jq -r .project_path "$MANIFEST")"
PASS_ID="$(basename "$LATEST")"

emit_metric() {
  local name="$1" help="$2" value="$3"
  printf '# HELP %s %s\n# TYPE %s gauge\n%s{project="%s",pass_id="%s"} %s\n' \
    "$name" "$help" "$name" "$name" "$PROJECT" "$PASS_ID" "$value"
}

# Total beads + closed counts
TOTAL=$(jq -r '.bead_counts.total_issues // .bead_counts.total // 0' "$MANIFEST")
CLOSED=$(jq -r '.bead_counts.closed_issues // 0' "$MANIFEST")
THRESHOLD=$(jq -r '.score_threshold // 700' "$MANIFEST")

# False-closed count
FC=$(grep -c '^| `' "$LATEST/REPORT.md" 2>/dev/null | head -1)

# Score median (compute from scorecards)
SCORES=$(grep -hoP 'Score:\s+\K\d+' "$LATEST/beads"/*/scorecard.md 2>/dev/null)
MEDIAN=$(echo "$SCORES" | sort -n | awk '{a[NR]=$1} END{if (NR>0) print (NR%2==1)?a[(NR+1)/2]:int((a[NR/2]+a[NR/2+1])/2); else print 0}')

# Convergence indicator
CONVERGED=$(jq -r '.convergence.is_converged // false' "$MANIFEST")
CONV_INT=$([ "$CONVERGED" = "true" ] && echo 1 || echo 0)

# Theater finding count (BLOCKING)
BLOCKING=$(jq -s 'map(.summary.BLOCKING // 0) | add' "$LATEST/beads"/*/theater.json 2>/dev/null)
MAJOR=$(jq -s 'map(.summary.MAJOR // 0) | add' "$LATEST/beads"/*/theater.json 2>/dev/null)

{
  emit_metric "beads_audit_total_beads"          "Total beads in inventory"          "$TOTAL"
  emit_metric "beads_audit_closed_beads"         "Closed beads"                      "$CLOSED"
  emit_metric "beads_audit_false_closed"         "Closed beads scoring below threshold" "${FC:-0}"
  emit_metric "beads_audit_score_threshold"      "Configured score threshold"        "$THRESHOLD"
  emit_metric "beads_audit_score_median"         "Median bead score, latest pass"    "$MEDIAN"
  emit_metric "beads_audit_converged"            "1 if last two passes converged"    "$CONV_INT"
  emit_metric "beads_audit_theater_blocking"     "Total BLOCKING theater findings"   "${BLOCKING:-0}"
  emit_metric "beads_audit_theater_major"        "Total MAJOR theater findings"      "${MAJOR:-0}"
} > "$OUT.tmp"
mv "$OUT.tmp" "$OUT"
```

Run from a cron after each pass: `*/30 * * * * /path/to/metrics-export.sh /audit/dir /var/.../beads_audit.prom`.

---

## OpenTelemetry traces

For finer-grained instrumentation (per-phase wall time, subagent invocation count, per-bead score deltas), emit OpenTelemetry spans during the audit pass:

```bash
# At start of each phase
otel-cli span --service beads-audit --name "phase-1-inventory" \
  --attribute project="$PROJECT_PATH" \
  --attribute pass_id="$PASS_ID" \
  --start-time-now-ns &

# At end of phase
otel-cli span --service beads-audit --name "phase-1-inventory" \
  --finish ...
```

Or use a Python tracing wrapper:
```python
from opentelemetry import trace
tracer = trace.get_tracer("beads-audit")

with tracer.start_as_current_span("phase-8-scoring") as span:
    span.set_attribute("project", project_path)
    span.set_attribute("pass_id", pass_id)
    span.set_attribute("bead_count", len(beads))
    # ... run scoring ...
    span.set_attribute("false_closed", fc_count)
```

Send to your OTel collector (Honeycomb, Datadog, Tempo, Jaeger). Per-phase histograms over time reveal performance regressions in the audit infrastructure itself.

---

## Grafana dashboard

A starter dashboard JSON is at `assets/grafana-dashboard.json` (template — adjust queries to your Prometheus setup):

**Panels:**

1. **Convergence indicator** — single-stat: `beads_audit_converged{project=~"$project"}` (green / red).
2. **False-closed count over time** — time series: `beads_audit_false_closed`.
3. **Score median over time** — time series with target threshold line.
4. **Per-project comparison** — bar chart of `beads_audit_false_closed` grouped by project label.
5. **Theater findings stacked** — area chart: BLOCKING (red) + MAJOR (orange) + MINOR (yellow).
6. **Recent regressions** — table: projects with non-zero `delta(beads_audit_false_closed[1d])`.

---

## Alert rules

```yaml
# /etc/prometheus/rules/beads-audit.yml
groups:
- name: beads_audit
  interval: 5m
  rules:
  - alert: BeadsAuditNotConverged
    expr: beads_audit_converged == 0
    for: 7d
    labels:
      severity: warning
    annotations:
      summary: "Project {{ $labels.project }} not converged for 7+ days"
      description: "Audit hasn't converged. Check next_pass_tasks in convergence.json."

  - alert: BeadsAuditFalseClosedSpike
    expr: increase(beads_audit_false_closed[1d]) > 5
    labels:
      severity: critical
    annotations:
      summary: "Project {{ $labels.project }} gained 5+ false-closed beads in 1 day"
      description: "Likely regression. Read REPORT.md for the new entries."

  - alert: BeadsAuditScoreMedianDrop
    expr: |
      (avg_over_time(beads_audit_score_median[7d]) -
       avg_over_time(beads_audit_score_median[7d] offset 7d)) < -50
    for: 7d
    labels:
      severity: warning
    annotations:
      summary: "Project {{ $labels.project }} score median dropped 50+ points week-over-week"
      description: "Project quality is declining. Investigate."

  - alert: BeadsAuditTheaterBlockingHigh
    expr: beads_audit_theater_blocking > 10
    for: 24h
    labels:
      severity: warning
    annotations:
      summary: "Project {{ $labels.project }} has {{ $value }} BLOCKING theater findings"
      description: "Significant theater accumulation. Review and remediate."
```

---

## Long-horizon trend mining

The `trends.md` file in the audit dir is the source of truth. Convert to a time-series database for richer queries:

```bash
# Each row: pass_id, bead_id, score
awk -F'|' '/^\| `[a-z]/ {
  gsub(/^[ \t]+|[ \t]+$/, "", $2); gsub(/^[ \t]+|[ \t]+$/, "", $3); gsub(/^[ \t]+|[ \t]+$/, "", $4);
  print $2, $3, $4
}' "$AUDIT_DIR/trends.md" \
  > /tmp/trends.csv
```

Load into SQLite for ad-hoc queries:

```bash
sqlite3 /tmp/audit_trends.db <<EOF
CREATE TABLE IF NOT EXISTS trends (pass_id TEXT, bead_id TEXT, score INT);
.mode csv
.import /tmp/trends.csv trends
EOF

# Per-bead trajectory
sqlite3 /tmp/audit_trends.db "
SELECT bead_id, GROUP_CONCAT(score, '→') AS trajectory
FROM trends
GROUP BY bead_id
ORDER BY bead_id;"

# Beads with worst single-pass regression
sqlite3 /tmp/audit_trends.db "
WITH numbered AS (
  SELECT bead_id, score, ROW_NUMBER() OVER (PARTITION BY bead_id ORDER BY pass_id) AS rn
  FROM trends
)
SELECT a.bead_id, a.score AS prior, b.score AS now, b.score - a.score AS delta
FROM numbered a JOIN numbered b ON a.bead_id = b.bead_id AND b.rn = a.rn + 1
WHERE delta < -100
ORDER BY delta;"
```

---

## What to alert on

Generally:

| Metric | Alert when | Reason |
|--------|-----------|--------|
| `beads_audit_converged` | == 0 for 7+ days | Project's bead graph is drifting |
| `beads_audit_false_closed` | spike > 5 in 1 day | Real regression OR new agent introduced theater |
| `beads_audit_score_median` | drops > 50 week-over-week | Project-wide quality drop |
| `beads_audit_theater_blocking` | > 10 | Significant theater accumulation |
| Per-pass wall time (OTel) | > 4× p50 | Audit infrastructure regression |
| Last pass age | > 30 days | Tripwire stopped running |

Don't alert on:
- Single-pass score deltas under ±10 (within convergence noise).
- New false-closed beads in *Onboarding mode* (expected on first pass).
- Slack messages from "audit converged" events (success isn't an alert).

---

## Per-agent close-quality dashboards

If you tag every metric with `closed_by_session` (requires the exporter to read each scorecard's bead's session metadata), you can plot per-agent quality:

```yaml
- alert: AgentCloseQualityRegression
  expr: |
    avg by (closed_by_session) (beads_audit_score_median{closed_by_session!=""}) <
    avg by (closed_by_session) (beads_audit_score_median{closed_by_session!=""} offset 7d) - 30
  for: 1d
  annotations:
    summary: "Agent {{ $labels.closed_by_session }} close quality dropped 30+ points"
```

This is the long-horizon analog to anomaly-scan's per-pass batch-close detection: it catches *systematic* quality drift by an agent rather than one bad batch.

---

## Privacy considerations

If exporting to a multi-tenant Prometheus / Grafana, ensure:
- `project=` label values don't leak repo paths with sensitive prefixes.
- `closed_by_session=` doesn't include user emails or PII.
- The audit dir itself isn't exposed to the metrics endpoint (it can contain raw test outputs with secrets if compliance verification touched secret-bearing code).

The `scripts/metrics-export.sh` template emits only counters and aggregates — no raw text.