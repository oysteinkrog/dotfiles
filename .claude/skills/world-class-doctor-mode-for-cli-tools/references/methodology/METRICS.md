# Metrics — Observability Beyond the Scorecard

The scorecard measures the doctor's **maturity** (per the rubric). Day-to-day **operational** observability needs different metrics: latency, throughput, resource usage, and trends. This file pins what to measure, where to record it, and how to alert.

---

## Three layers of observability

### Layer 1 — Per-run metrics (in `report.json`)

Every doctor run emits structured timing in its run-artifact. These are the canonical observability data points.

```jsonc
{
  "schema_version": "1.0",
  "run_id": "...",
  "started_at": "2026-05-06T14:23:07Z",
  "finished_at": "2026-05-06T14:23:07.412Z",
  "duration_ms": 412,
  "phase_timings_ms": {
    "diagnose": 132,
    "plan": 8,
    "acquire_lock": 14,
    "mutate": 250,
    "verify": 8
  },
  "per_detector_ms": {
    "fm-state-files-jsonl-tombstone-drift": 30,
    "fm-schemas-db-version-mismatch": 5,
    ...
  },
  "per_fixer_ms": {
    "fm-state-files-jsonl-tombstone-drift": 50,
    ...
  },
  "actions_taken": 3,
  "bytes_backed_up": 18293,
  "backup_count": 3,
  "online_calls": 0,
  "panics_caught": 0
}
```

Every field above is required (or zero). The `phase_timings_ms` keys correspond to [STATE-MACHINE.md](STATE-MACHINE.md) state transitions.

### Layer 2 — Per-run trend (in `.doctor/scorecard_history.jsonl`)

One line per invocation, append-only:

```jsonc
{"run_id":"...","started_at":"...","tool_version":"0.5.0","doctor_version":"1.0.0","ok":true,"total_findings":0,"by_severity":{"P0":0,"P2":0},"aggregate_score":893,"actions_taken":0,"duration_ms":412,"health_p95_ms":187}
```

This file IS the dashboard. Anyone can `tail -f` it; CI can `tail -100 | jq` to compute trends.

### Layer 3 — Aggregate dashboards (optional; Pattern 9 distributed CLIs)

If the project is a distributed CLI (Pattern 9) and has telemetry infrastructure, the doctor can **opt-in** publish per-run summaries to the user's chosen sink (Datadog, Honeycomb, Prometheus, …) via `<tool> doctor metrics-export --sink=<url>`. Always opt-in, always documented in capabilities, always offline-first (a network failure logs locally and proceeds).

This skill does not prescribe a specific sink; the user's project decides.

---

## Canonical metric set (per pattern)

### Pattern 1 (single-binary state-owning)

| Metric | Source | SLO |
|--------|--------|-----|
| `<tool>_doctor_health_duration_ms_p95` | `phase_timings_ms.diagnose` filtered to fast-path | < 200 |
| `<tool>_doctor_diagnose_duration_ms_p95` | `phase_timings_ms.diagnose` (default tier) | < 5000 |
| `<tool>_doctor_fix_duration_ms_p95` | full `duration_ms` for `--fix` runs | < 30000 |
| `<tool>_doctor_findings_total` | `total_findings` per run | trend ↓ over time |
| `<tool>_doctor_actions_taken_total` | `actions_taken` per `--fix` run | depends on FM cycle |
| `<tool>_doctor_aggregate_score` | latest `scorecard.json::aggregate.score` | ≥ 700 (Polish Bar floor) |
| `<tool>_doctor_panics_caught_total` | sum of `panics_caught` per run | == 0 (any panic is a P0 bug) |

### Pattern 4 (daemon CLI) additional metrics

| Metric | Source | SLO |
|--------|--------|-----|
| `<tool>_daemon_alive_seconds` | from `health --running` | depends on uptime expectations |
| `<tool>_daemon_watchdog_age_ms_p99` | from running daemon's protocol | < 10000 |
| `<tool>_doctor_daemon_alive_during_fix_total` | counts of attempted --fix while daemon alive | == 0 (always refused) |

### Pattern 9 (distributed CLI) additional metrics

| Metric | Source | SLO |
|--------|--------|-----|
| `<tool>_doctor_online_call_duration_ms_p95` | `phase_timings_ms.diagnose` for online detectors | < 2000 |
| `<tool>_doctor_vendor_5xx_total` | per-vendor 5xx counts | trend ↓ |
| `<tool>_doctor_token_expired_findings_total` | finding count for token expiry FMs | trend ↓ when active users keep tokens fresh |

### Pattern 11 (installer) additional metrics

| Metric | Source | SLO |
|--------|--------|-----|
| `<tool>_doctor_signature_verify_failures_total` | from `verify-install --json` | == 0 (any failure is a supply-chain alert) |
| `<tool>_doctor_reinstall_count` | how often `reinstall` is invoked | depends on artifact stability |

---

## Alert thresholds

For projects with monitoring infra:

| Alert | Trigger | Action |
|-------|---------|--------|
| **Doctor regression** | Last 3 runs show `aggregate_score` dropping > 50 pts | File P0 bead; review changes since last green |
| **Health latency budget** | p95 over last 100 runs > 500 ms | File P1; profile fast-path detectors |
| **Findings spike** | Last 24h average findings > 2× prior week | Investigate; could be a real degradation in the project |
| **Panic detected** | any non-zero `panics_caught` | P0; the catch is for safety but the bug must be fixed |
| **Lock contention** | exit 5 ratio > 5% of fix invocations | Review concurrency expectations; maybe wider TTL |
| **Backup failure** | `bytes_backed_up == 0` on a `--fix` that took actions | P0; backup invariant violated |

These alerts are recommendations; the project's existing alerting infra (PagerDuty, Slack, email, etc.) wires them.

---

## CI gates

Beyond the scorecard regression check (which runs in CI per Phase 8), additional gates:

```yaml
- name: doctor health latency budget
  run: |
    <tool> doctor health
    p95=$(tail -100 .doctor/scorecard_history.jsonl \
      | jq -rs 'map(.health_p95_ms // .duration_ms // empty) | sort | if length == 0 then 0 else .[((length - 1) * 95 / 100 | floor)] end')
    [ "$p95" -lt 500 ] || { echo "health p95=$p95 exceeds budget"; exit 1; }

- name: doctor panics
  run: |
    panics=$(tail -100 .doctor/scorecard_history.jsonl \
      | jq -rs 'map(.panics_caught // 0) | add // 0')
    [ "$panics" = "0" ] || { echo "doctor panicked $panics times historically"; exit 1; }
```

`scorecard.py` may grow `latency-p95` and `panics-total` convenience wrappers later; until then, CI uses the JSONL + `jq` gates above.

---

## What NOT to measure

- **Per-detector wall time when it's < 1 ms.** Sub-millisecond noise drowns the signal.
- **Per-finding free-text content.** Findings are agent-facing; metrics are operator-facing.
- **Memory usage.** Doctors are short-lived. RAM rarely matters; if it does, it's a P0 bug independent of metrics.
- **Network bytes for offline detectors.** They're zero by definition.
- **Counts of `<tool> doctor --help` invocations.** Doesn't tell you anything actionable.

---

## Per-pattern dashboards

Reference dashboard layouts (the project replicates in its preferred infra):

### Single-binary dashboard
- Top: `aggregate_score` over time (line chart).
- Middle: per-FM finding rate (stacked area).
- Bottom: latency percentiles for `health` and `diagnose`.

### Daemon dashboard (Pattern 4)
- Top: daemon uptime + watchdog freshness.
- Middle: `health --running` results over time.
- Bottom: `--fix` attempts blocked by daemon-alive vs. successful.

### Distributed CLI dashboard (Pattern 9)
- Top: per-vendor success rate.
- Middle: token-expiry finding rate over time.
- Bottom: rate-limit budget consumption.

### Installer dashboard (Pattern 11)
- Top: signature verification success ratio (always 100%; deviation is alert).
- Middle: reinstall frequency per artifact.
- Bottom: per-platform install integrity.

---

## Recovery from telemetry gaps

If the user runs `<tool> doctor` without telemetry sink available, the local `scorecard_history.jsonl` is still complete. After connectivity returns:

```bash
<tool> doctor metrics-export --since=2026-05-01 --sink=https://...
```

Replays the last N days of run summaries. The export is idempotent — re-running on the same range produces the same summaries. The export uses each run's stable `run_id` as the deduplication key.

---

## Privacy

Per [SECURITY.md](SECURITY.md), the metrics never include credential values. The metric NAMES include the tool name and FM IDs (which are not sensitive). The metric VALUES are timings, counts, hashes — no user-identifiable data unless the user explicitly opts in via a documented `--include-user-id` flag (rare).

For projects subject to compliance regimes, the metrics export goes through the same redaction set as the agent-facing JSON output.
