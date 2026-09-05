# feature-universe-builder

> Phase 7 • Build `parity_taxonomy.rs` with Feature struct + weight normalization + deterministic iteration order + truncate_score discipline.

## Inputs
- `<workspace>/docs/contracts/supported_surface_matrix.toml` (every FeatureId + status + weight).
- `<workspace>/docs/contracts/parity_score_contract.toml` (category weights).
- All `phase1_recon_*.md` files (source-of-truth for FeatureIds).

## Deliverables
- `<target>/crates/<project>-harness/src/parity_taxonomy.rs` with `Feature`, `FeatureId`, `ParityStatus`, `FeatureUniverse` + loader + validators.
- `<workspace>/phase7_feature_universe.md` documenting counts (total features, per-category, per-status), weight-sum validation results, `truncate_score` policy.

## Coordination
- **MCP Agent Mail thread:** `gauntlet-<run-id>-phase7-feature-universe`
- **Reservations needed:** `tool://feature-universe-write` (TTL 90m).
- **Lane:** cc_3 (surface parity).

## Verbatim Prompt

You are the feature-universe builder. Construct `parity_taxonomy.rs` so that every parity claim downstream (the scoring engine, the dashboard, the certification bundle) reads from one source-of-truth.

**Feature struct:**
```rust
pub struct Feature {
    pub id: FeatureId,                   // e.g., F-SQL-001, F-RESP-CLUSTER-007
    pub title: String,
    pub category: String,                // matches a category in parity_score_contract.toml
    pub weight: f64,                     // sum-per-category == 1.0
    pub status: ParityStatus,            // Passing | Partial | Missing | Excluded
    pub exclusion_rationale: Option<String>,
}

pub enum ParityStatus { Passing, Partial, Missing, Excluded }
```

**Three load-bearing invariants** (the loader MUST enforce all three; reject the file on violation):

1. **Weight normalization:** `sum(weights_within_category) == 1.0` for every category. Use exact f64 equality after `truncate_score` to 6 decimals; reject if any category sums to `1.000001` or `0.999999`.

2. **Cross-platform reproducibility (`truncate_score`):**
```rust
pub fn truncate_score(x: f64) -> f64 {
    (x * 1_000_000.0).trunc() / 1_000_000.0  // truncate to 6 decimal places
}
```
x86 vs ARM vs WASM differ at LSB; truncation ensures bytewise identical scores regardless of CPU.

3. **Deterministic iteration order:** `FeatureUniverse::features()` returns features sorted by `FeatureId` (lexicographic). Deterministic iteration → deterministic scoring → meaningful SHA-256 of report.

**FeatureUniverse API:**
```rust
impl FeatureUniverse {
    pub fn load_from_toml(path: &Path) -> Result<Self, LoaderError> { /* validates 3 invariants */ }
    pub fn features(&self) -> impl Iterator<Item = &Feature> { /* sorted by FeatureId */ }
    pub fn by_category(&self, cat: &str) -> impl Iterator<Item = &Feature> { /* sorted */ }
    pub fn validate(&self) -> Vec<Violation> { /* re-checks every invariant */ }
    pub fn stats(&self) -> Stats { Stats { total, passing, partial, missing, excluded, per_category } }
}
```

**Excluded-as-debt rule (verbatim):** Excluded items still count as coverage debt for a strict-100% claim. The certification bundle reports excluded count separately and the strict-conformant-release.v1 template treats a non-zero excluded count as a hard fail.

Document counts, weight-sum validation results, and `truncate_score` application in `phase7_feature_universe.md`.

## Exit Criteria
- `parity_taxonomy.rs` compiles and `cargo test --lib parity_taxonomy` passes.
- Loader rejects a deliberately-malformed TOML (weight sum != 1.0) with a clear error.
- `FeatureUniverse::features()` returns features in stable sorted order across runs.
- `truncate_score(0.123456789) == 0.123456` (verified by unit test).
- `phase7_feature_universe.md` committed.

## References
- [PHASES.md § Phase 7](../references/PHASES.md)
- [taxonomy/FEATURE-UNIVERSE.md](../references/taxonomy/FEATURE-UNIVERSE.md)
- [methodology/CONFORMAL-RATCHET.md § truncate_score](../references/methodology/CONFORMAL-RATCHET.md)
- [methodology/OPERATORS.md § Enumerate-Surface](../references/methodology/OPERATORS.md)
