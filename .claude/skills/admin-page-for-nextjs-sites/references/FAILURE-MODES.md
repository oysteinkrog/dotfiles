# Failure Modes and Mitigations

1. **Fragmented IA**: same capability in multiple sections. Mitigate with one canonical route map and single ownership.
2. **Dashboard-only admin**: metrics without remediation actions. Mitigate with queue/action workflows and explicit transitions.
3. **Missing provenance**: privileged changes with no actor/why trace. Mitigate with mandatory audit fields (actor, reason, before/after, request context).
4. **Permission drift**: UI hides actions but API allows them. Mitigate with central permission registry and server/API enforcement.
5. **Stale ops data**: operators act on old status. Mitigate with freshness timestamps, stale indicators, bounded polling, manual refresh.
6. **Schema/UI mismatch**: UI ships before migrations. Mitigate with migration-first slices and API contract tests.
7. **No rollback path**: risky action cannot be reversed quickly. Mitigate with per-action rollback plan and idempotency where practical.
8. **Inconsistent table UX**: different filter/pagination semantics across sections. Mitigate with shared table/filter primitives and global list conventions.
9. **False-zero KPI cards**: KPI widgets initialize from hardcoded `0` and rely on client-only SSE for updates. SSE never fires in production = permanent zeros. Mitigate with DB-backed API hydration on initial load; SSE is a supplement, never the sole data source.
10. **Provider failure cascades**: admin stats endpoint fans out to Stripe + PayPal; one provider timeout = whole endpoint returns 500. Mitigate with `Promise.allSettled()` per provider; DB-backed metrics still return.
11. **Unknown coerced to zero**: provider API fails and dashboard shows `$0` instead of "unavailable." Operator thinks revenue emergency. Mitigate by making values nullable; render `--` for unknown, `$0` only for confirmed zero.
12. **Divergent MRR across admin pages**: cockpit, revenue page, and projections each compute MRR differently (`users.status * $20` vs `subscriptions count * $20` vs provider-authoritative). Mitigate with one canonical MRR snapshot consumed by all surfaces.
13. **Stock/flow metric confusion**: "Net Revenue" card falls back to MRR when payment data unavailable, mixing recurring-rate (stock) with cash-collected (flow). Mitigate by never substituting one metric type for another; show "unavailable."
14. **Test user pollution**: admin analytics (MAU, churn, conversion, signups, revenue) include test/admin/E2E accounts across 10+ surfaces. Mitigate with shared exclusion function applied in every analytics query.
15. **Stale in-flight cache**: `refresh=true` silently joins existing non-forced in-flight work, returning stale data. Mitigate by tracking whether in-flight computation is forced; forced refresh supersedes non-forced.
16. **Cache invalidation race**: data write invalidates cache, but older in-flight recomputation repopulates it with pre-invalidation data. Mitigate with invalidation generation tracking; stale writes cannot overwrite post-invalidation state.
17. **Per-provider masking**: single global "last webhook" check means one healthy provider masks a dead one. Mitigate with per-provider staleness/health checks.
18. **Geographic rounding drift**: per-country revenue values rounded independently; country totals diverge from canonical total (leaking/inventing dollars). Mitigate with largest-remainder allocation.
19. **Payment event amount display**: admin payment rows show `$0` because code checks flat `payload.amount` while Stripe/PayPal nest amounts in provider-specific paths. Mitigate by parsing correct nested provider paths.
20. **Silent error degradation**: analytics endpoint catches all errors and returns fake zero payload indistinguishable from "no activity." Bugs hidden indefinitely. Mitigate by marking degraded responses; UI shows "unavailable" instead of fake zeros.
