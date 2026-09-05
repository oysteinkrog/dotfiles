---
name: final-artifact-author
description: Single Phase 12 subagent that writes FINAL_UB_REPORT.md + UB_RUNBOOK.md from the workspace's accumulated phase artifacts.
---

# Final-Artifact Author

**Invoke with `subagent_type=general-purpose`** — writes the two top-level audit deliverables. `Explore` cannot.

Single instance per run. Spawned at the start of Phase 12 after all preceding phases have committed their artifacts.

## Inputs at invocation

- `{WORKSPACE}` — absolute path to `<source>/.ub-exorcism/<run-id>/`
- `{SOURCE_PATH}` — absolute path to the audited source repo root
- `{RUN_ID}`
- `{MODE}` — Quick / Standard / Exhaustive (drives how much detail goes into the runbook's CI section)
- `{ARCHETYPE}` — the per-PROJECT-TYPES.md archetype tag, used to size the runbook's bucket coverage

## What this subagent reads

- `phase0_run.json`, `phase0_partition.json`, `phase0_toolchain_inventory.json`, `preflight_smoke.json`
- `phase1_unsafe_surface_inventory.md`
- `phase2_findings_<bucket>.md` (all of them)
- `phase3_dynamic_findings.md` + `phase3_raw/*.log` (referenced as appendix only, not inlined)
- `phase4_unified_findings.md`
- `UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md` (verdict per EXP)
- `phase6_idea_wizard_round_*.md`
- `phase7_convergence_round_*.json`
- `phase8_remediation_plan.md`
- `phase9_beads_log.md`
- `phase10_fresh_eyes_log.md`
- `phase11_*.md` (Exhaustive only)

## What this subagent writes

### `{WORKSPACE}/FINAL_UB_REPORT.md`

```markdown
# Final UB Audit Report — {SOURCE_PATH} ({RUN_ID})

## Executive summary
- Mode: {MODE} · Archetype: {ARCHETYPE} · Wall time: {h}h{m}m · Convergence rounds: {N}
- Findings: {n} CONFIRMED_UB, {n} REFUTED, {n} DEFERRED
- Verdict: <one paragraph>

## Findings table
| Severity | F-ID | Bucket | Site | EXP | Remediation | Bead |
|---|---|---|---|---|---|---|
| HIGH | F-001 | … | crates/x/src/y.rs:42 | EXP-007 | R-003 | proj-abc12 |

## Per-finding detail
### F-001 — <title>
- Bucket(s): …
- Site(s): …
- Reproducer: experiments/EXP-007/repro.rs
- Verdict: CONFIRMED_UB under MIRIFLAGS=…
- Chosen remediation: <one line + link to phase8_remediation_plan.md §R-003>
- Bead: `br show <id>`

## Convergence evidence
- Round 1: <new findings> Round 2: <new> … Round N: 0 + Round N-1: 0
- Quiet streak: 2

## Open questions
- Any DEFERRED findings with re-check criteria

## Phase 13 Execution Log (only present if user accepted auto-remediation)
- Beads attempted: {n}
- CLOSED-WITH-FIX: {n} · CLOSED-OBSOLETE: {n} · DEFERRED-NEEDS-HUMAN: {n}
- Per-bead disposition: see phase13_remediation_log.md
```

### `{WORKSPACE}/UB_RUNBOOK.md`

For future maintainers of `{SOURCE_PATH}`:

```markdown
# UB Runbook — {SOURCE_PATH}

## Minimum lint group
…the exact `-W clippy::…` flags discovered during this audit

## CI MIRIFLAGS matrix
…copy from scripts/run-miri-matrix.sh (the exact axes that ran clean)

## Loom models that must stay green
…list per Phase 3 loom output

## Fuzz corpora to preserve
…list of fuzz/corpus/<target>/ paths

## `// SAFETY:` comment template
…3-line minimum; cite invariants by name; reference enforcing code
(template from references/INVARIANT-CATALOG.md)

## "If you change X, re-run experiment Y" recipes
…one per high-stakes finding

## How to re-audit
…command to re-run this skill with `mode=Quick` against the post-remediation tree
```

## Quality gates

- [ ] Both files exist at `{WORKSPACE}/`
- [ ] FINAL_UB_REPORT.md's findings table has at least one row per CONFIRMED_UB experiment in `UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md`
- [ ] Severity column is filled for every row (HIGH/MEDIUM/LOW/INFO)
- [ ] UB_RUNBOOK.md's CI MIRIFLAGS matrix is the exact subset that ran clean in Phase 3 (do not list axes that failed)
- [ ] UB_RUNBOOK.md's loom and fuzz lists reference real artifacts from the workspace
- [ ] If Phase 13 was run, the Execution Log appendix in FINAL_UB_REPORT.md is filled

## Failure modes to watch for

- **Inlining raw tool output**: Phase 3 raw logs can be MBs. Reference them by path; never paste them into the report.
- **Listing failing Miri axes in the runbook**: the runbook is the project's PERMANENT CI gate — only include axes that ran clean post-remediation.
- **Forgetting Phase 13**: if `phase13_remediation_log.md` exists, the FINAL_UB_REPORT.md MUST have the execution-log appendix. Check first.
- **Stale severity**: do not copy severity from Phase 4's draft table — re-derive after Phase 8's remediation plan settles (a finding that's been remediated drops severity in the FINAL report).

## Coordination

Reservation: `path://{WORKSPACE}/FINAL_UB_REPORT.md`, `path://{WORKSPACE}/UB_RUNBOOK.md` exclusive, TTL 30 min.
Mail thread: `ub-exorcism-{RUN_ID}-phase12-final`.
