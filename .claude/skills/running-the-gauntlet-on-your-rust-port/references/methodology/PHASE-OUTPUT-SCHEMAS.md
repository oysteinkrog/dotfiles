# Phase Output Schemas

Every phase produces machine-readable artifacts with pinned JSON schemas. This file catalogs them — schema version + required fields + optional fields + producer + consumers. The schemas double as gatekeepers: downstream phases REJECT inputs that don't match the schema (per K-10 BEAD_ID + SCHEMA_VERSION discipline).

When a schema bumps, the bumper runs `subagents/schema-version-bumper.md` to safely propagate (producer + every consumer + migration test + log entry).

---

## Phase 0 outputs

### `phase0_toolchain_inventory.json` → `gauntlet.phase0_toolchain_inventory.v1`

```jsonc
{
  "schema_version": "gauntlet.phase0_toolchain_inventory.v1",
  "generated_at": "<ISO 8601>",
  "red_count": <int>,
  "tools": [
    {"name": "<tool>", "status": "green|yellow|red", "detail": "<version-or-reason>"}
  ]
}
```
- Producer: `scripts/install-toolchain.sh`
- Consumers: `scripts/oracle-preflight-doctor.sh` (refuses to proceed if `red_count > 0`); `subagents/workspace-bootstrapper.md`.

### `phase0_project_class.json` → `gauntlet.phase0_project_class.v1`

```jsonc
{
  "schema_version": "gauntlet.phase0_project_class.v1",
  "generated_at": "<ISO>",
  "target": "<path>",
  "detected_class": "SQL-class|RESP-class|Numerical-Python-class|ML-System-class|HTTP-Protocol-class|UNKNOWN",
  "confidence": <0.0..1.0>,
  "matching_reference": "<reference name>",
  "sibling_project_example": "<sibling name>",
  "scores": {"<class>": <int>}
}
```
- Producer: `scripts/detect-project-class.sh`
- Consumers: every script with a per-class gate (run-tcl-tests, run-numpy-all-check, gradcheck, verify-resp-protocol, openapi-schema-diff); every per-class subagent.

### `phase0_skill_inventory.json` → `gauntlet.phase0_skill_inventory.v1`

```jsonc
{
  "schema_version": "gauntlet.phase0_skill_inventory.v1",
  "generated_at": "<ISO>",
  "jsm_available": true,
  "missing_count": <int>,
  "skills": [
    {"name": "<skill>", "claude": <bool>, "codex": <bool>, "gemini": <bool>, "jsm_installable": <bool>, "available": <bool>}
  ]
}
```
- Producer: `scripts/check-skills.sh`
- Consumers: `subagents/workspace-bootstrapper.md` (prompts jsm install for missing); fallback dispatch logic in every subagent that calls a helper skill.

### `phase0_intake.json` → `gauntlet.phase0_intake.v1`

```jsonc
{
  "schema_version": "gauntlet.phase0_intake.v1",
  "run_id": "<run-id>",
  "started_at": "<ISO>",
  "target_path": "<absolute path>",
  "workspace_path": "<absolute path>",
  "project_class_confirmed": "<class>",
  "reference_version_pinned": "<X.Y.Z>",
  "mode": "<mode-from-mode-router>",
  "tier": "<T1..T5>",
  "rch_offload_authorized": <bool>,
  "fresh_or_resume": "fresh|resume|incremental-rebase",
  "final_artifact_tier": "internal-only|public-release|certification-bundle"
}
```
- Producer: orchestrator (assembles from user answers).

---

## Phase 1 outputs

### `phase1_recon_<crate>.md` → freeform markdown with frontmatter

```yaml
---
schema_version: gauntlet.phase1_recon.v1
crate: "<crate-name>"
generated_at: "<ISO>"
generator: surface-archaeologist
public_api_count: <int>
unsafe_block_count: <int>
extern_c_count: <int>
no_mangle_count: <int>
macro_export_count: <int>
hot_loops_identified: <int>
counters_present: <int>
oracle_tests_present: <int>
fault_hooks_present: <int>
---
```

### `phase1_unified_recon.md` → freeform markdown

Collated from per-crate; same frontmatter shape with `crates: ["a", "b", ...]` array.

---

## Phase 2 outputs

The four contract files, each with its own pinned schema:
- `docs/contracts/<reference>_version_contract.toml` → `gauntlet.version_contract.v1` (see `assets/version-contract-template.toml`)
- `docs/contracts/supported_surface_matrix.toml` → `gauntlet.supported_surface_matrix.v1`
- `docs/contracts/parity_score_contract.toml` → `gauntlet.parity_score_contract.v1`
- `docs/contracts/eprocess_calibration.toml` → `gauntlet.eprocess_calibration.v1`

Plus `phase2_scope_decision.md` (freeform markdown documenting the scope rationale).

---

## Phase 3-7 outputs

Per phase, Rust source files (the harness modules); each carries a module-level `// SAFETY:` / `// SCHEMA_VERSION:` doc comment naming the bead it serves.

Plus per-phase `phase<N>_*.md` summary file documenting decisions + cross-refs.

---

## Phase 9 baseline outputs

### `phase9_baseline/conformance_findings.json`
```jsonc
{
  "schema_version": "gauntlet.conformance_findings.v1",
  "run_id": "<run-id>",
  "round": <int>,
  "started_at": "<ISO>",
  "ended_at": "<ISO>",
  "tests_run": <int>,
  "tests_passed": <int>,
  "tests_failed": <int>,
  "failure_signatures": [<sig>, ...],   // distinct MismatchSignature.hash values
  "true_divergences": <int>,
  "by_classification": {"TrueDivergence": <int>, "OrderDependentDifference": <int>, ...},
  "failure_bundles": ["<path>", ...]
}
```

### `phase9_baseline/perf_findings.json`
```jsonc
{
  "schema_version": "gauntlet.perf_findings.v1",
  "run_id": "<run-id>",
  "round": <int>,
  "bench_history_committed": <bool>,
  "comprehensive_bench_report": "<path>",
  "per_category_score": {"ReadSingle": <truncate_score>, "ReadAggregate": ..., ...},
  "primary_score": <truncate_score>,
  "conformal_lower_bound": <truncate_score>,
  "mt8_top_frames": [{"symbol": "...", "self_pct": <f>}, ...]
}
```

### `phase9_baseline/surface_findings.json`
```jsonc
{
  "schema_version": "gauntlet.surface_findings.v1",
  "run_id": "<run-id>",
  "round": <int>,
  "feature_universe_total": <int>,
  "by_status": {"Passing": <int>, "Partial": <int>, "Missing": <int>, "Excluded": <int>, "n/a": <int>},
  "coverage_debt_pct": <truncate_score>,
  "per_family": {"<category>": {"verdict": "none|partial|full", ...}}
}
```

### `phase9_baseline_summary.md` — freeform markdown with frontmatter linking the three JSON files.

---

## Phase 11 outputs

### `reports/convergence_tracker.json` → `gauntlet.convergence_tracker.v1`
```jsonc
{
  "schema_version": "gauntlet.convergence_tracker.v1",
  "generated_at": "<ISO>",
  "workspace": "<path>",
  "round_count": <int>,
  "min_rounds_required": 10,
  "clean_threshold": 3,
  "required_consecutive_clean": 2,
  "open_hypothesis_count": <int>,
  "round_findings": [{"round": "round_1", "new_findings": <int>}],
  "last_two_findings": [<int>, <int>],
  "clean_last_two": <bool>,
  "converged": <bool>
}
```

Per-round directories `round_<N>/` contain mirrors of phase9 findings + `mt8_*` + `<pillar>_failures/<sig>/`.

---

## Phase 12 outputs

### `phase12_remediation_<gap>.md` → freeform with frontmatter
```yaml
---
schema_version: gauntlet.phase12_remediation.v1
gap_id: "<id>"
pillar: perf|conformance|surface
severity: CRITICAL|HIGH|MEDIUM|LOW
selected_rewrite: "<name>"
selected_score: <int 0..30>
runners_up:
  - {name: "<name>", score: <int>, rejection_reason: "<reason>"}
test_evidence: ["<exp-id>", ...]
remediation_evidence_expected: ["<exp-id>", ...]
bead_id: "<bd-...>"
---
```

### `phase12_remediation_index.md` — table of all remediation files with status.

---

## Phase 13 outputs

### `phase13_beads_summary.md` → freeform with frontmatter
```yaml
---
schema_version: gauntlet.phase13_beads_summary.v1
beads_total: <int>
beads_by_priority: {"P0": <int>, "P1": <int>, "P2": <int>, "P3": <int>}
beads_with_test_dep: <int>
beads_with_bench_dep: <int>
beads_with_doc_dep: <int>
cycles_detected: <int>     # MUST be 0
graph_validator_passed: <bool>
---
```

---

## Phase 14 outputs

### `phase14_fresh_eyes_diff.md` — see `subagents/fresh-eyes-reviewer-{a,b,c}.md` for shape.

### `phase14_triangulation_<lens>/CONSENSUS.md` — see `subagents/triangulator.md`.

### `phase14_red_team_<lens>.md` — see `subagents/red-team-attacker.md`.

---

## Phase 15 outputs

Per-soak-runner summary JSON (see each subagent doc for shape). Common fields: `schema_version`, `target`, `duration_hours`, completion stats, regime label.

---

## Phase 16 outputs

### `FINAL_GAUNTLET_REPORT.md` → schema `gauntlet.final-report.v1` (see `assets/final-gauntlet-report-template.md` frontmatter).

### `PARITY_RUNBOOK.md` → schema `gauntlet.parity-runbook.v1`.

### `RELEASE_CERTIFICATION_TEMPLATE.md` → schema `strict-conformant-release.v1`.

### `certification_bundle/BUNDLE_MANIFEST.json` → `gauntlet.certification_bundle_manifest.v1`.

### `cookbook/<motion>.md` — see `subagents/cookbook-author.md`.

### `sibling_audits/<sibling>_<date>.md` — see `subagents/sibling-status-auditor.md`.

### `onboarding_<role>_<expertise>.md` — see `subagents/knowledge-transfer.md`.

---

## Schema version bump policy

Per `subagents/schema-version-bumper.md`:

1. **Additive** (new optional field with serde-default) → MINOR bump (`v1` → `v1.1`); migration test for the additive case.
2. **Renamed field** → MINOR bump + dual-name reader for one round; then MAJOR bump dropping the old name.
3. **Removed field** → MAJOR bump.
4. **Type change** → MAJOR bump.

Every bump is logged in `<workspace>/SCHEMA_VERSION_LOG.md` with bead_id + rationale + migration test path.

## Cross-references

- [`subagents/schema-version-bumper.md`](../../subagents/schema-version-bumper.md)
- [`methodology/KERNEL.md`](KERNEL.md) (K-10 SCHEMA_VERSION discipline)
- [`pattern:100-E2E-LOG-SCHEMA`](../patterns/100-E2E-LOG-SCHEMA.md)
