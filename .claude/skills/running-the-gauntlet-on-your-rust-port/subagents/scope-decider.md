# scope-decider

> Phase 2 • Reference pinning + supported-surface matrix + canonical parity contract + parity-score contract.

## Inputs
- All `<workspace>/phase1_recon_<crate>.md` files from Phase 1.
- `<workspace>/phase0_project_class.json` (project class).
- Reference version chosen at intake.
- Maintainer constraints / explicit exclusions (e.g., "no Lua scripting", "no GPU backend").

## Deliverables
- `<workspace>/docs/contracts/<reference>_version_contract.toml` — pinned reference version, source-of-truth URL, expected build flags, oracle binary path requirements.
- `<workspace>/docs/contracts/supported_surface_matrix.toml` — every FeatureId from Phase 1 with one of `supported | partial | excluded` plus rationale for excluded items.
- `<workspace>/docs/contracts/canonical_parity_contract.md` — human-readable scope decisions, the "what we are and are not promising" document.
- `<workspace>/docs/contracts/parity_score_contract.toml` — category weights (sum-per-category == 1.0), category list, scoring policy.
- `<workspace>/phase2_scope_decision.md` — change-set summary; the version contract hash; the supported-surface matrix counts (supported/partial/excluded); the parity-score weights table; the maintainer-confirmation checkbox list.

## Coordination
- **MCP Agent Mail thread:** `gauntlet-<run-id>-phase2-scope`
- **Reservations needed:** `tool://contracts-write` (TTL 60m).
- **Lane:** single coherent agent (orchestrator-tier; do not parallelize — the four contract files must agree).

## Verbatim Prompt

You are the scope decider for the gauntlet on `<target-port>`. Phase 1 produced one `phase1_recon_<crate>.md` per crate. Your job: collapse them into the four contract files listed under Deliverables, with full agreement across the four.

Start by reading every `phase1_recon_*.md` file. Build a master list of every draft FeatureId. For each, propose `supported | partial | excluded` with a one-line rationale citing the source file + line. Group by category (the categories live in `parity_score_contract.toml`; for SQL-class typical categories are `core, types, joins, transactions, mvcc, wal, recovery, extensions, pragma, functions, performance`; for RESP-class typical categories are `strings, hashes, lists, sets, zsets, streams, scripting, pubsub, cluster, replication, persistence`; for ML-System-class typical categories are `aten_dispatch, autograd, optim, datasets, jit, distributed, compile`).

Assign weights per category such that `sum(weights) == 1.0` for the global parity score AND `sum(weights_within_category) == 1.0` for the per-category score. The loader will enforce both invariants (see `../references/taxonomy/FEATURE-UNIVERSE.md`).

Fill out `<reference>_version_contract.toml` with: pinned reference version, vendor URL, expected build flags, oracle binary path (e.g., `/usr/local/bin/sqlite3` or `vendored/redis-server-7.2.5`), version-string regex, and contract SHA-256 self-hash placeholder.

Write `canonical_parity_contract.md` as human-readable prose: what the port commits to behaving identically to the reference for, what is `partial`-with-known-divergence-classes, and what is explicitly out of scope. This is the document the maintainer signs.

Write `phase2_scope_decision.md` with the four contract hashes, the counts (supported N, partial N, excluded N), the parity-score weights table, and a maintainer-confirmation checkbox list. Post the change-set summary to the MCP thread.

## Exit Criteria
- All four contract files exist and are internally consistent.
- `sum(weights) == 1.0` per category (validated by `scripts/compute-parity-score.sh <workspace>`).
- Every FeatureId from Phase 1 appears exactly once in `supported_surface_matrix.toml`.
- `phase2_scope_decision.md` posted with maintainer-confirmation checkbox.
- The four contracts committed to git as `phase2: scope decided`.

## References
- [PHASES.md § Phase 2](../references/PHASES.md)
- [taxonomy/FEATURE-UNIVERSE.md](../references/taxonomy/FEATURE-UNIVERSE.md)
- [methodology/OPERATORS.md § Pin-Reference-Version](../references/methodology/OPERATORS.md)
- [assets/version-contract-template.toml](../assets/version-contract-template.toml)
- [assets/supported-surface-matrix-template.toml](../assets/supported-surface-matrix-template.toml)
- [assets/parity-score-contract-template.toml](../assets/parity-score-contract-template.toml)
