---
name: billing-observability-alerter
description: Implements webhook + cron metrics + Prometheus alert rules per § 78a.4 / B55
---

# Observability Alerter

For B55 (Observability & Defense-in-Depth). Wires the metrics + alert rules from `references/patterns/55-OBSERVABILITY-AND-DEFENSE-IN-DEPTH.md § 78a.4`.

## Inputs

- Existing webhook handlers + cron handlers.
- Project's metrics infrastructure (prom-client / OpenTelemetry / Honeycomb / Axiom / etc.).
- Project's alerting infrastructure (Prometheus + Alertmanager / Grafana Cloud / PagerDuty / Opsgenie / Slack / etc.).

## Output

- Metric instrumentation in code (counters, histograms).
- Alert rules in `monitoring/alerts/billing.yml` (or equivalent).
- Drift-guard test asserting metrics are emitted on every webhook + cron path.

## Procedure

### Metrics (per § 78a.4)

```
webhook_received_total{provider, event_type}              counter
webhook_signature_fail_total{provider}                    counter
webhook_duplicate_total{provider}                         counter
webhook_processing_duration_seconds{provider, event_type} histogram
webhook_processing_error_total{provider, event_type}      counter
webhook_replay_blocked_total{provider, reason}            counter
```

Plus cron metrics:
```
cron_run_total{cron_name}                                 counter
cron_run_duration_seconds{cron_name}                      histogram
cron_run_lock_acquired_total{cron_name}                   counter
cron_run_lock_skipped_total{cron_name}                    counter
cron_rows_processed_total{cron_name, outcome}             counter
cron_terminal_stuck_count{cron_name}                      gauge
```

Plus billing-specific:
```
mrr_snapshot_provenance_total{provenance}                 counter   ← live | fallback | unavailable
refund_processing_duration_seconds                        histogram
chargeback_received_total                                 counter
subscription_drift_detected_total                         counter
```

### Alert rules (per § 78a.4)

The rules from `55-OBSERVABILITY-AND-DEFENSE-IN-DEPTH.md`:

```yaml
groups:
- name: billing
  rules:
  - alert: WebhookSignatureFailureSpike
    expr: rate(webhook_signature_fail_total[5m]) > 5
    for: 1m
    labels: { severity: P1, team: billing }
    annotations:
      description: "Webhook signature failures spiking — possible forgery attack"
      runbook: "https://<docs>/runbooks/webhook-signature-spike.md"

  - alert: WebhookProcessingSlow
    expr: histogram_quantile(0.99, rate(webhook_processing_duration_seconds_bucket[5m])) > 10
    for: 5m
    labels: { severity: P2, team: billing }

  - alert: WebhookProcessingErrorRate
    expr: rate(webhook_processing_error_total[5m]) / rate(webhook_received_total[5m]) > 0.01
    for: 5m
    labels: { severity: P1, team: billing }

  - alert: WebhookReplayBlockedSpike
    expr: rate(webhook_replay_blocked_total[10m]) > 10
    for: 5m
    labels: { severity: P0, team: billing }

  - alert: CronStuck
    expr: cron_terminal_stuck_count > 0
    for: 1h
    labels: { severity: P2, team: billing }

  - alert: MRRSnapshotUnavailable
    expr: rate(mrr_snapshot_provenance_total{provenance="unavailable"}[5m]) > 0
    for: 15m
    labels: { severity: P2, team: billing }

  - alert: ChargebackSpike
    expr: rate(chargeback_received_total[1h]) > 3
    for: 5m
    labels: { severity: P1, team: billing }
```

### Wire in code

For each webhook handler:
- Increment `webhook_received_total` after sig verification.
- Increment `webhook_signature_fail_total` on sig failure.
- Increment `webhook_duplicate_total` when `recordWebhookEvent` returns false.
- Time `webhook_processing_duration_seconds` from after-record to mark-processed.
- Increment `webhook_processing_error_total` in the catch.
- Increment `webhook_replay_blocked_total` when `last_event_at` gate rejects.

For each cron handler:
- Increment `cron_run_total` at start.
- Increment `cron_run_lock_acquired_total` / `cron_run_lock_skipped_total` based on advisory lock.
- Time `cron_run_duration_seconds`.
- Increment `cron_rows_processed_total` per row outcome.

### Drift-guard

Test that asserts every webhook + cron handler emits the expected metric set. Walks the handler files; greps for the metric calls; reports missing.

## Integration

- Phase 5 (B55 implementation).
- Phase 7 fresh-eyes (verifies metrics are actually emitted, not just imported).
- Phase 9 staging drill (verifies alerts fire under expected conditions).
- Phase 10 runbook (each alert references its runbook).
