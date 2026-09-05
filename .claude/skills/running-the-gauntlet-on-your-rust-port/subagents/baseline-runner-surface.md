# baseline-runner-surface

> Phase 9 • Load FeatureUniverse; emit dashboard verdict; run always-on integrity guardrails (checksums files, manifest hashes).

## Inputs
- `FeatureUniverse` from `feature-universe-builder.md`.
- `InvariantCatalog` from `invariant-catalog-builder.md`.
- `coverage-dashboard` CLI shim from `coverage-dashboard-builder.md`.
- All fixture manifests + checksums files from Phase 4.

## Deliverables
- `<workspace>/reports/coverage_dashboard.json` (machine-readable).
- `<workspace>/reports/coverage_dashboard.md` (human-readable).
- `<workspace>/reports/integrity_guardrails.json` with per-manifest result.
- `<workspace>/phase9_baseline_surface.md` with: family-by-family coverage table, release-gate verdict, top-N missing-evidence items, integrity-guardrail summary.

## Coordination
- **MCP Agent Mail thread:** `gauntlet-<run-id>-phase9-baseline-surface`
- **Reservations needed:** `tool://dashboard-run` (TTL 60m), `tool://feature-universe-read` (TTL 60m).
- **Lane:** cc_3 (surface parity).

## Verbatim Prompt

You are the surface baseline runner. Load `FeatureUniverse`, compute coverage, run the always-on integrity guardrails, and emit the dashboard.

**Steps:**

1. **Load FeatureUniverse** — `parity_taxonomy.rs::FeatureUniverse::load_from_toml(...)`. Loader validates the three invariants (weight sum, truncate_score, sorted-by-FeatureId). Reject on violation.

2. **Compute coverage** — for every Feature, walk its ProofObligation set from `InvariantCatalog`. Roll up per category, then per family.

3. **Run integrity guardrails:**
   - For every manifest under `tests/fixtures/<tier>/<source>/manifest.v1.json`: verify SHA-256 of every fixture matches the recorded hash. Mismatch → red.
   - For every `checksums.sha256` file: run `sha256sum -c`. Non-zero exit → red.
   - For every `ArtifactRef.path` in `InvariantCatalog`: verify the path resolves AND `sha256(file) == recorded.hash`. Mismatch → `fail-invalid-references`.
   - Re-run `oracle_preflight_doctor` — must still be green from Phase 9 start.

4. **Emit dashboard:**
   ```bash
   cargo run --release --bin coverage-dashboard -- \
     --feature-universe docs/contracts/supported_surface_matrix.toml \
     --invariant-catalog reports/invariant_catalog.json \
     --out-json reports/coverage_dashboard.json \
     --out-md reports/coverage_dashboard.md
   ```

5. **Compute parity score:**
   ```bash
   scripts/compute-parity-score.sh <workspace>
   ```
   This produces both the point estimate AND the conformal LOWER bound. Release decisions use the lower bound, never the point estimate.

6. **Apply ratchet:**
   ```bash
   scripts/apply-ratchet.sh <workspace>
   ```
   Verdict ∈ `{Allow, Block, Quarantine, Waiver}`. Block surfaces a regression; Quarantine routes through manual review.

**Document** in `phase9_baseline_surface.md`:
- Family-by-family coverage table (family / coverage level / N features / pass-rate / category-weighted-score).
- Release-gate verdict.
- Top-N missing-evidence items (sorted by category weight, descending).
- Integrity-guardrail summary (N manifests, N checksums, N artifact refs; how many green/red).
- Conformal lower bound vs point estimate side-by-side.
- Ratchet verdict.

## Exit Criteria
- `reports/coverage_dashboard.json` validates against `coverage-dashboard.v1`.
- `reports/parity_score.json` populated with both point estimate AND conformal lower bound.
- Integrity guardrails: zero unexpected mismatches (a planted mismatch in a test fixture is caught and surfaced as red — verify this with a dry-run).
- Release-gate verdict is `green` OR every non-green item has a documented reason in `phase9_baseline_surface.md`.
- `phase9_baseline_surface.md` committed.

## References
- [PHASES.md § Phase 9](../references/PHASES.md)
- [taxonomy/FEATURE-UNIVERSE.md](../references/taxonomy/FEATURE-UNIVERSE.md)
- [methodology/CONFORMAL-RATCHET.md](../references/methodology/CONFORMAL-RATCHET.md)
- [methodology/OPERATORS.md § Conformal-Band § Ratchet-Lower-Bound](../references/methodology/OPERATORS.md)
