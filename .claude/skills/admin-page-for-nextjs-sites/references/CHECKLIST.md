# Admin Cockpit Checklist

## Preflight
- [ ] Inventory `/admin` pages + `/api/admin` endpoints.
- [ ] Document permission model + roles.
- [ ] Document audit model + gaps.
- [ ] Map capabilities to canonical domains.

## Design
- [ ] Single IA; no duplicate sections.
- [ ] Shared admin primitives defined.
- [ ] Query-key/hook boundaries defined.
- [ ] Mutation contract template agreed.

## Backend
- [ ] Permission checks on all mutations.
- [ ] Zod schemas for body/query params.
- [ ] `reason` required for high-risk actions.
- [ ] Audit emission for privileged actions.

## Frontend
- [ ] Consistent shell/nav across sections.
- [ ] Queue/action flows for operator work.
- [ ] Consistent search/sort/filter/pagination.
- [ ] Freshness + error states visible/actionable.

## Quality
- [ ] API tests for auth/permissions/transitions.
- [ ] E2E smoke for `/admin` + one critical mutation.
- [ ] Lint, typecheck, tests pass.
- [ ] No parallel admin systems added.

## Launch Readiness
- [ ] Runbook for critical flows.
- [ ] Rollback path for risky actions.
- [ ] Monitoring/alerts for admin job failures.
- [ ] Operator feedback loop in place.

## DoD (Per Slice)
- [ ] End-to-end operator path works.
- [ ] Privileged actions are permission-protected + audited.
- [ ] Empty/loading/error/stale states handled.
- [ ] Freshness timestamps shown where needed.
- [ ] Long-term owner assigned.

## Data Integrity
- [ ] All billing/revenue surfaces consume ONE canonical MRR snapshot (never compute independently).
- [ ] KPI cards hydrate from DB-backed API on load (not client-only SSE state).
- [ ] Unknown/unavailable values render as `--`, never as `$0` or `0`.
- [ ] Provider API calls fail independently via `Promise.allSettled()`.
- [ ] Test/admin/E2E accounts excluded via shared exclusion function in every analytics query.
- [ ] Concurrent admin refreshes deduplicated (in-flight promise coordination).
- [ ] `refresh=true` supersedes stale in-flight work (not silently joined).
- [ ] `cachedAt` timestamps stored at compute time, not generated at read time.
- [ ] Cache invalidation prevents older in-flight writes from overwriting newer state.
- [ ] Provider health/staleness checked per-provider, not globally.
- [ ] Stock metrics (MRR, ARR) and flow metrics (net revenue, fees) never substitute for each other.
- [ ] Webhook payload amounts parsed from correct nested provider paths (not flat `payload.amount`).
- [ ] Error fallback responses marked as `degraded` (not fake zero payloads).

## Red Flags (Stop and Fix)
- [ ] Duplicate capability introduced.
- [ ] High-risk mutation lacks reason + audit.
- [ ] Data-grid behavior inconsistent with rest of admin.
- [ ] Operational page lacks retry/escalation controls.
- [ ] Risky action has no rollback path.
- [ ] KPI card shows `$0` when the real answer is "unavailable."
- [ ] Two admin pages show different numbers for the same metric.
- [ ] Analytics query does not exclude test/admin accounts.
- [ ] In-flight deduplication missing for expensive admin computation.
- [ ] Provider failure takes down the entire admin stats endpoint.
