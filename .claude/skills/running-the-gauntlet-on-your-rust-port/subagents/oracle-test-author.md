# oracle-test-author

> Phase 6 • Write one `*_oracle_e2e.rs` test file per behavior class using the 30-line `scenario()` template.

## Inputs
- `<workspace>/phase0_project_class.json` (selects behavior class catalog).
- `<workspace>/docs/contracts/supported_surface_matrix.toml` (scope).
- `oracle.rs` from `oracle-wirer.md` (provides `scenario()` + EngineIdentity).
- Behavior class (e.g., `null_semantics`, `group_by_having`, `recursive_cte`, `join_types`, `triggers`, `returning`, `pragma`, `like_glob`, `numeric_arithmetic`, `blob_io`, `foreign_keys`, `check_constraints`, `conflict_resolution`, `compound_select`, `default`, `attach_temp`, `alter_table_rename`, `collation`, `datetime`, `scalar_functions`, `order_limit_offset`, `views`, `transactions_savepoints`, `rowid_without_rowid`, `index_features`, `multi_row_values`, `concurrent_dml`, `mvcc_visibility`, `wal_checkpoint`) — passed as `<behavior>` argument.

## Deliverables
- `<target>/crates/<project>-e2e/tests/<behavior>_oracle_e2e.rs` with ≥10 scenarios.
- `<workspace>/phase6_oracle_<behavior>.md` documenting behavior coverage, edge cases tested, known false-positive classifications, expected pass rate.

## Coordination
- **MCP Agent Mail thread:** `gauntlet-<run-id>-phase6-oracle-<behavior>`
- **Reservations needed:** `tool://oracle-tests::<behavior>` (TTL 90m).
- **Lane:** cc_1 (conformance).

## Verbatim Prompt

You are the oracle test author for behavior class `<behavior>`. Write `<target>/crates/<project>-e2e/tests/<behavior>_oracle_e2e.rs` containing ≥10 scenarios, each driven through the verbatim `scenario(stmts, queries, label)` helper from `oracle.rs`.

For each scenario:
- Choose stmts that set up the schema/state for this behavior.
- Choose queries that exercise both the common case AND at least one explicit edge case from `../references/taxonomy/PROJECT-CLASSES.md § public-API oracle-parity surface`.
- Label the scenario uniquely: `<behavior>_<scenario_name>`.

Behavior-class coverage requirements:
- **null_semantics:** three-valued logic (NULL = NULL → NULL, NULL OR TRUE → TRUE, NULL AND FALSE → FALSE), IS NULL vs `= NULL`, COALESCE / IFNULL, NULL in aggregates, NULL ordering.
- **group_by_having:** non-aggregated columns in GROUP BY, HAVING vs WHERE, empty groups, aggregate functions on empty sets, GROUPING SETS / ROLLUP / CUBE (if supported).
- **recursive_cte:** anchor + recursive part, termination, mutual recursion, UNION vs UNION ALL semantics.
- **join_types:** INNER, LEFT, RIGHT, FULL, CROSS, NATURAL; column ambiguity resolution; ON vs USING.
- **mvcc_visibility:** snapshot isolation, read-your-writes, lost-update prevention, write-skew detection (SSI).
- **wal_checkpoint:** PASSIVE, FULL, RESTART, TRUNCATE; busy-handler interactions.
- (Adapt per class; see `../references/taxonomy/PROJECT-CLASSES.md`.)

**Critical rules** (encoded by `scenario()`):
- Both-error = agreement (regardless of message text).
- One-error-one-OK = hard failure.
- String rendering uniform via `normalize_value()`.

Document behavior coverage, edge cases, known false-positive classifications (those that should be classified as `OrderDependentDifference | TypeAffinityDifference | NullHandlingDifference | FloatingPointDifference | FalsePositive` rather than `TrueDivergence`), and expected pass rate in `phase6_oracle_<behavior>.md`.

## Exit Criteria
- `cargo test --test <behavior>_oracle_e2e` runs; all scenarios either PASS or emit a structured `MismatchSignature` (no panics).
- Every scenario has a unique label.
- `phase6_oracle_<behavior>.md` lists every scenario by label with status (pass / known-divergence / new-divergence).
- Any `TrueDivergence` is filed as a `FailureBundle` and a beads issue; non-actionable classifications go to the triage queue.

## References
- [PHASES.md § Phase 6](../references/PHASES.md)
- [methodology/KERNEL.md § scenario template](../references/methodology/KERNEL.md)
- [taxonomy/PROJECT-CLASSES.md § public-API oracle-parity surface](../references/taxonomy/PROJECT-CLASSES.md)
- [tooling/ORACLE-TOOLCHAIN.md § MismatchClassification](../references/tooling/ORACLE-TOOLCHAIN.md)
