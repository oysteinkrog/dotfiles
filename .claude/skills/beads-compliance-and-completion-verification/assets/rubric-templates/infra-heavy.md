---
rubric_version: "infra-heavy-1.0.0"
threshold: 750
score_threshold: 750
weights_by_type:
  migration:
    implementation: 250
    tests:           200
    anti_theater:    100
    test_depth:      150
    docs:            150    # runbook + post-migration validation matter
    integration:     150    # who else depends on the schema
  schema:
    implementation: 250
    tests:           200
    anti_theater:    100
    test_depth:      150
    docs:            150
    integration:     150
  infra:
    implementation: 250
    tests:           150
    anti_theater:    100
    test_depth:      150
    docs:            200    # operability docs are first-class
    integration:     150
weights_by_label:
  blast-radius-high:
    docs:           300     # rollback, runbook, paging procedures
    integration:    200
---

# Rubric — infra-heavy variant

For projects with many migration / schema / DDL / deploy / infra beads.
Bumps `migration-safety-reviewer` weight; rollback drill is BLOCKING by
default; operability docs (runbook, alert routing) are first-class.

## Per-type overrides

For `migration` / `schema` / `infra` beads:

| Dimension | infra max | Default | Why |
|-----------|----------:|--------:|-----|
| Implementation | 250 | 300 | Smaller; the value is in safety guarantees |
| Tests | 200 | 250 | Forward + reverse + idempotency + dry-run |
| Anti-theater | 100 | 150 | Spec-as-stub is rare here |
| Test depth | 150 | 150 | Same |
| **Docs** | **150–200** | 100 | Runbook, rollback procedure, alert routing |
| **Integration** | **150** | 50 | Schema changes ripple; track explicitly |

## Threshold = 750

A migration that's "passing" at 700 means there's a real gap (probably the
rollback drill, the lock-test, or the idempotency check). Set the bar high.

## Hard rules (per `subagents/migration-safety-reviewer.md`)

- Forward migration that runs cleanly + reverse migration that runs cleanly + idempotency proof: ALL THREE required. Missing any → BLOCKING.
- Production rehearsal (forward + tests against prod-clone data) required. Missing → MAJOR.
- Rollback drill (running the reverse against the post-forward state) required. Missing AND no documented "no rollback possible" justification → BLOCKING.
- Lock-acquisition under concurrent write load required for schema migrations on tables > 1M rows. Missing → MAJOR.
- "no downtime" claim without ALGORITHM=INPLACE / `pg_repack` / `gh-ost` / two-step `NOT VALID` → BLOCKING.

## Operability requirements

For any `infra` bead:
- Runbook: 1+ paragraphs covering "what breaks if this fails" and "how to recover"
- Alert routing: which on-call rotation gets paged
- Capacity headroom: explicit number for the next 6 months of growth

## When to use

- Project with > 30% of beads tagged `migration` / `schema` / `infra` / `deploy`
- Pre-launch ops sign-off
- Quarterly capacity review
- Post-incident hardening (production fire prompted by a missed migration step)
