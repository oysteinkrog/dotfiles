# mismatch-minimizer-builder

> Phase 6 • Build `mismatch_minimizer.rs` with delta-debugging binary partition + schema-preservation guard + MismatchSignature for dedup.

## Inputs
- `<workspace>/phase0_project_class.json` (defines schema-preservation rules).
- `oracle.rs` + `differential_v2.rs` from earlier phases.
- Example divergence cases from prior runs (if any) under `<workspace>/known_divergences/`.

## Deliverables
- `<target>/crates/<project>-harness/src/mismatch_minimizer.rs` with `Subsystem` enum, `MismatchSignature` struct, binary-partition minimizer, schema-preservation guard.
- `<workspace>/phase6_mismatch_minimizer.md` documenting algorithm, schema-preservation rule for the class, dedup criteria, replay-command emission.

## Coordination
- **MCP Agent Mail thread:** `gauntlet-<run-id>-phase6-mismatch-minimizer`
- **Reservations needed:** `tool://minimizer-write` (TTL 60m).
- **Lane:** cc_1 (conformance).

## Verbatim Prompt

You are the mismatch minimizer builder. Build `mismatch_minimizer.rs` so that any divergence reported by the oracle harness gets automatically reduced to its 1-minimal form (schema preserved), classified by subsystem, and deduplicated via signature.

**Subsystem enum** (adapt names per class; SQL example):
```rust
pub enum Subsystem {
    Parser, Resolver, Planner, Vdbe, Storage, Wal, Mvcc, Functions,
    Extension, TypeSystem, Pragma, Unknown,
}
```
RESP-class: `Parser, CommandDispatch, KeyspaceOps, Persistence, Replication, PubSub, Scripting, Cluster, Unknown`. ML-System-class: `Frontend, Dispatch, Kernel, Autograd, Allocator, Distributed, JIT, Unknown`.

**MismatchSignature:**
```rust
pub struct MismatchSignature {
    pub hash: String,                     // truncated SHA-256 of canonical minimal repro
    pub classification: MismatchClassification,
    pub subsystem: Subsystem,
    pub minimal_statement_count: usize,
    pub first_diverging_sql: String,      // or first_diverging_command for RESP, first_diverging_op for ML
}
```

**Algorithm (delta-debugging binary partition):**
1. Partition the failing sequence into two halves; test each half.
2. If a half still diverges, recurse on it.
3. If neither half diverges individually, recurse with finer partition (ddmin-style).
4. Terminate when no further reduction preserves divergence — this is the 1-minimal form.

**Schema-preservation guard:** Setup statements that establish schema (CREATE TABLE / CREATE INDEX / SET COMMAND for Redis / model load for ML / OpenAPI mount for HTTP) are NEVER candidates for removal. Removal would change the divergence's meaning; we want the 1-minimal *workload* on top of the original schema.

**Dedup rule:** Two failures with identical `MismatchSignature.hash` are the same root-cause bug. A bisect that hits a known bug LINKS to the existing beads issue instead of opening a new one. Maintain `<workspace>/mismatch_signature_index.json` with `{hash: bead_id}`.

For each minimized failure emit:
- `MismatchSignature` (for dedup).
- `FailureBundle v1.0.0` (for full reproducibility — see `failure-bundle` discipline in `../references/methodology/IDENTITY-AND-REPRODUCIBILITY.md`).
- Replay command: `cargo test --test <test> -- <scenario_label> --exact --nocapture`.

Document algorithm, schema-preservation rule, dedup criteria, and replay-command emission in `phase6_mismatch_minimizer.md`.

## Exit Criteria
- `cargo test --lib mismatch_minimizer` passes (synthetic fixture: 10-stmt failure reduces to 2-stmt minimal in <60s).
- Schema-preservation guard prevents removal of `CREATE TABLE` (verified by a unit test).
- Dedup: two seeded runs of the same root-cause produce identical signatures.
- Replay command actually replays (round-trip test).
- `phase6_mismatch_minimizer.md` committed.

## References
- [PHASES.md § Phase 6](../references/PHASES.md)
- [tooling/ORACLE-TOOLCHAIN.md § mismatch minimizer](../references/tooling/ORACLE-TOOLCHAIN.md)
- [methodology/OPERATORS.md § Reduce / Minimize](../references/methodology/OPERATORS.md)
- [methodology/IDENTITY-AND-REPRODUCIBILITY.md](../references/methodology/IDENTITY-AND-REPRODUCIBILITY.md)
