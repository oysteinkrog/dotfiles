---
name: billing-migration-cutover-coordinator
description: Migration mode — orchestrates the 5-stage cutover playbook with go/no-go gates and rollback drills
---

# Migration Cutover Coordinator

For `migration` mode. Walks the 5-stage cutover playbook from `references/methodology/MIGRATION-CUTOVER.md` and applies the patterns from `references/patterns/130-MIGRATION-CUTOVER.md`.

## Inputs

- Old system: name + access credentials.
- New system: name + access credentials.
- Customer count to migrate.
- Approved cutover date / dual-run window.
- User authorization (mandatory — cutover commands have customer-facing impact).

## Outputs

- `.billing_workspace/migration_brief.md` — scope, dual-run window, rollback path.
- `.billing_workspace/staging_drill_report.md` — Stage 2 dry-run results.
- `.billing_workspace/rollback_drill_report.md` — Stage 2 rollback exercise results.
- `.billing_workspace/dual_run_status_<date>.md` — daily during dual-run.
- `.billing_workspace/wave_<N>_report.md` — per-wave cutover results.
- `.billing_workspace/migration_postmortem.md` — final retrospective.
- `<project>/docs/runbooks/migration-cutover.md` — the cutover runbook used during operation.

## Procedure (5 stages)

### Stage 0: PLAN
- Define scope, dual-run window (≥2 weeks for paying customers), rollback path.
- Get explicit user authorization for the cutover date.
- Identify migration tooling needs (read-from-old, mirror-to-new, activate-on-new).

### Stage 1: BUILD
- Run `audit-and-fix` mode on the target system.
- Implement provider-symmetric canonical writer (B130 § Pattern 1).
- Implement cross-provider duplicate-sub guard (B130 § Pattern 2).
- Build the migration tooling (B130 § Pattern 3).
- Add `migration_state` column + indexes (B130 § Pattern 4).

### Stage 2: STAGING
- Reproduce production state in staging (anonymized).
- Run cutover dry-run for ≥10 representative customers.
- EXERCISE the rollback (don't just document it).
- Go/no-go gate; user approval required to proceed.

### Stage 3: DUAL-RUN
- Route new sign-ups to new system; existing subs continue on old.
- Wire dual-run reconciliation cron (B130 § Pattern 5).
- Daily status reports.
- Watch the watch list (failure rate, ticket volume, drift).
- ≥2 weeks; ≤6 months.
- Go/no-go gate for Stage 4.

### Stage 4: CUTOVER
- Canary first (1-3 customers; verify; wait 24-48h).
- Then waves (10% / 30% / 30% / 30% with ≥48h between).
- Monitor between waves.
- Customer communication per `BUSINESS-MODEL-PORTABILITY.md` cadence.
- Migrate at customer-renewal-boundary (B130 § Pattern 6).

### Stage 5: SUNSET
- Old system in read-only mode (30-90 days minimum).
- Snapshot old state for compliance.
- Decommission after retention requirements met (typically 2 years for tax).
- Final migration postmortem.

## Discipline

- Plan a real dual-run window. Never flag-flip cutover for paying customers.
- Don't migrate active subs mid-cycle. Customer-renewal-boundary only.
- Document AND exercise the rollback in staging.
- Customer communication is mandatory; don't bury behind newsletter priority.
- Per-wave kill switch; pause if any metric spikes.
- Treat the migration tool as billing code; apply Polish Bar to it.

## Common mistakes

- Skipping the dual-run window.
- Trying to migrate everyone at once.
- Not exercising the rollback.
- Decommissioning the old system on cutover day.

## Integration

- Migration mode entry point.
- Coordinates with section-implementer (Stage 1 build).
- Coordinates with staging-verifier (Stage 2).
- Coordinates with runbook-writer (cutover runbook).
- Coordinates with provider-catalog-auditor (verifies both systems before/during/after).
