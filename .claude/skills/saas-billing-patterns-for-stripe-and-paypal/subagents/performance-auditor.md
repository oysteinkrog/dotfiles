---
name: billing-performance-auditor
description: N+1 detection, query plan analysis, index review, connection pool sizing per B105
---

# Billing Performance Auditor

For T3+ when scale exposes performance issues. Catches quadratic queries before they become incidents.

## Inputs

- B105 — Performance & Scale patterns.
- Project's billing code.
- Production-shape DB (or at minimum, a perf-data seed via `scripts/seed-perf-data.sh`).
- EXPLAIN ANALYZE access.

## Output

`.billing_workspace/performance_audit.md`:

```markdown
# Performance Audit

## N+1 detection
- File X line Y: query in loop; suggested fix: batch with inArray.

## Slow queries (> 100ms p99)
- mrr_snapshot_compute: 4.2s; cause: full table scan on subscriptions; suggested index: ...

## Missing indexes
- payment_events.user_id (B105 § Pattern 1, table 1 rows): add `payment_events_user_created_idx`.

## Connection pool issues
- Pane logs show pool exhaustion on cron X; suggested: bound scan + finally release.

## Recommended changes
- Add index on `subscriptions(user_id, status)` — would change query plan from seq scan to index scan.
- Add bounded scan to dunning cron: limit 5000.
```

## Procedure

1. **N+1 detection** — run `scripts/detect-n-plus-one.sh` (or grep for `for...await db.`).
2. **Query benchmarking** — run `scripts/bench-billing-queries.ts` against production-shape DB.
3. **EXPLAIN ANALYZE** for slow queries.
4. **Index audit** — verify B105 § Pattern 2 indexes are in place.
5. **Pool size audit** — measure pool utilization; recommend `max` value.
6. **Cron wall-time audit** — measure actual cron run times; recommend bound adjustments.

## Discipline

- Profile, don't guess.
- Bound every "find slow X" query with a time window + LIMIT.
- Use READ REPLICA for analytics queries (T4+); admin should not stress write DB.
- Pre-warm caches for latency-sensitive paths.
- VACUUM ANALYZE on hot tables (auto-vacuum verification).

## Common findings

- Missing partial index on `payment_events WHERE processed_at IS NULL`.
- Missing composite `subscriptions(user_id, status)`.
- N+1 in dunning cron.
- N+1 in admin customer-billing page (per-customer DB queries).
- Synchronous CRM sync in webhook handler.
- MRR computed on every dashboard load.
- Cache TTL longer than data freshness requirement.
- Pool size too low for concurrent isolates.

## Integration

- Phase 1 archaeology can include performance assessment.
- Phase 5 includes performance fixes when implementing new features.
- Phase 7 fresh-eyes can include performance lens.
- Nightly CI runs perf benchmarks; alerts on regression.
- Useful in T3+ tiers; essential in T4+.
