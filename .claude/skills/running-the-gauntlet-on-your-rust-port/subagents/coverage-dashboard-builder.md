# coverage-dashboard-builder

> Phase 7 • Build `feature_coverage_dashboard.rs` with per-family coverage (none|partial|full) + release-gate verdict.

## Inputs
- `parity_taxonomy.rs` (FeatureUniverse from `feature-universe-builder.md`).
- `parity_invariant_catalog.rs` (from `invariant-catalog-builder.md`).
- `<workspace>/docs/contracts/parity_score_contract.toml` (category weights).

## Deliverables
- `<target>/crates/<project>-harness/src/feature_coverage_dashboard.rs` with per-family coverage rollup + release-gate verdict emitter.
- `<target>/bin/coverage-dashboard` CLI shim emitting `<workspace>/reports/coverage_dashboard.json` and `coverage_dashboard.md`.
- `<workspace>/phase7_coverage_dashboard.md` documenting verdict shape, per-family rules, integration with verification-contract.

## Coordination
- **MCP Agent Mail thread:** `gauntlet-<run-id>-phase7-coverage-dashboard`
- **Reservations needed:** `tool://dashboard-write` (TTL 60m).
- **Lane:** cc_3 (surface parity).

## Verbatim Prompt

You are the coverage dashboard builder. The dashboard is the single rollup view a maintainer looks at to answer "is this release ready?"

**Coverage levels (per family):**
- `none` — zero features in the family have any ProofObligation with status `pass`.
- `partial` — some features pass, some fail or are missing evidence.
- `full` — every supported feature in the family has every ProofObligation passing AND the verification contract is `pass | allowed`.

**Per-family verdict** combines:
1. Feature-level status from `FeatureUniverse`.
2. Proof-obligation status from `InvariantCatalog`.
3. Verification-contract status from `parity_invariant_catalog.rs`.

**Release-gate verdict (top-level):**
- `green` — every family `full` AND zero `fail-missing-evidence` AND zero `fail-invalid-references` AND zero `fail-mixed`.
- `yellow` — every family ≥ `partial` AND every failure has a recorded waiver.
- `red` — any family `none` OR any verification status `fail-mixed` OR any `Excluded` feature lacks rationale.

**Output shape (`coverage_dashboard.json`):**
```jsonc
{
  "schema_version": "coverage-dashboard.v1",
  "generated_timestamp": "2026-MM-DDTHH:MM:SSZ",
  "release_gate_verdict": "green | yellow | red",
  "global_parity_score_truncated": 0.937642,
  "global_parity_score_lower_bound": 0.921108,  // conformal LOWER bound; release decision uses this
  "families": [
    {
      "family": "core",
      "coverage": "full",
      "feature_count": 42,
      "passing": 42, "partial": 0, "missing": 0, "excluded": 0,
      "category_weighted_score": 1.000000,
      "verification_contract_status": "pass | allowed"
    },
    ...
  ],
  "failures": [
    { "feature_id": "F-SQL-...", "invariant_id": "INV-...", "evidence_ref": "...", "failure_reason": "..." }
  ]
}
```

**Render markdown (`coverage_dashboard.md`)** with a per-family table and the release-gate verdict at the top.

**Integration with verification contract:** the dashboard CANNOT emit `green` if any `ProofObligation.status == fail-missing-evidence` or `fail-invalid-references`. The dashboard is downstream of the contract; it does NOT override it.

Document verdict shape, per-family rules, integration with verification-contract, and a worked example in `phase7_coverage_dashboard.md`.

## Exit Criteria
- `cargo run --bin coverage-dashboard -- --json > reports/coverage_dashboard.json` succeeds on a clean workspace.
- The JSON validates against `coverage-dashboard.v1` schema (sort keys, ISO-8601 timestamps).
- A deliberately-introduced fail-missing-evidence produces `release_gate_verdict: "red"`.
- `coverage_dashboard.md` table renders correctly.
- `phase7_coverage_dashboard.md` committed.

## References
- [PHASES.md § Phase 7](../references/PHASES.md)
- [taxonomy/FEATURE-UNIVERSE.md § feature coverage dashboard](../references/taxonomy/FEATURE-UNIVERSE.md)
- [taxonomy/INVARIANT-CATALOG.md](../references/taxonomy/INVARIANT-CATALOG.md)
- [methodology/CONFORMAL-RATCHET.md](../references/methodology/CONFORMAL-RATCHET.md)
