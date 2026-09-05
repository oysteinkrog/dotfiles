# Pattern 45 — MISMATCH MINIMIZER (delta-debug + schema-preservation guard + `MismatchSignature`)

## What

A binary-partition delta-debugging algorithm that reduces a failing test case (a sequence of N SQL statements, or N RESP commands, or N tensor ops) to its 1-minimal form: the smallest prefix that still reproduces the divergence. Two guards protect correctness: (1) the schema-preservation guard refuses to delete schema-setup statements (CREATE TABLE, CREATE INDEX); (2) a `MismatchSignature` (truncated SHA-256 of the canonical minimal repro + classification + subsystem) deduplicates failures: two failures with the same signature are the same root-cause bug.

## Why

> "Dedup rule: Two failures with same `MismatchSignature` are the same root-cause bug. A bisect that hits a known bug links instead of opens new beads issue." — MINING-2 §5

Without minimization, a 200-statement test that triggers a bug is impossible to debug — the bug could be anywhere. With minimization, the same failure reduces to 3 statements. Without signature deduplication, every new generated test that hits the same root-cause bug opens a new beads issue, and the triage queue silently grows by 50/day. Both guards together turn a fuzz campaign from "thousands of failures, all noise" into "12 distinct bugs, ranked by triage_priority".

## Where in FrankenSQLite

- `crates/fsqlite-harness/src/mismatch_minimizer.rs` (bead `bd-1dp9.2.3`) — the minimizer + `Subsystem` + `MismatchSignature` (MINING-2 §5)
- Subsystem attribution rules in `crates/fsqlite-harness/src/subsystem_classifier.rs`

## Verbatim shape — the three types + the algorithm

### `Subsystem`

From MINING-2 §5, verbatim:

```rust
pub enum Subsystem {
    Parser, Resolver, Planner, Vdbe, Storage, Wal, Mvcc, Functions,
    Extension, TypeSystem, Pragma, Unknown,
}
```

### `MismatchSignature` (the dedup primitive)

```rust
pub struct MismatchSignature {
    pub hash: String,                        // truncated SHA-256 of canonical minimal repro
    pub classification: MismatchClassification,
    pub subsystem: Subsystem,
    pub minimal_statement_count: usize,
    pub first_diverging_sql: String,
}
```

### Algorithm (verbatim from MINING-2 §5)

> "binary partition → recursive narrowing → 1-minimal → schema preservation (schema setup never removed)."

Canonical pseudo-code:

```rust
fn minimize(stmts: Vec<Stmt>) -> Vec<Stmt> {
    let schema_stmts: Vec<Stmt> = stmts.iter().filter(|s| is_schema(s)).cloned().collect();
    let mut workload: Vec<Stmt> = stmts.iter().filter(|s| !is_schema(s)).cloned().collect();

    loop {
        let n = workload.len();
        if n <= 1 { break; }

        // Binary partition: try first half, then second half.
        let mid = n / 2;
        let first_half = [&schema_stmts[..], &workload[..mid]].concat();
        let second_half = [&schema_stmts[..], &workload[mid..]].concat();

        if reproduces_divergence(&first_half) {
            workload = workload[..mid].to_vec();
        } else if reproduces_divergence(&second_half) {
            workload = workload[mid..].to_vec();
        } else {
            // 1-minimal at this granularity; try single-statement deletion.
            let mut shrunk = false;
            for i in (0..workload.len()).rev() {
                let mut without = workload.clone();
                without.remove(i);
                let candidate = [&schema_stmts[..], &without[..]].concat();
                if reproduces_divergence(&candidate) {
                    workload = without;
                    shrunk = true;
                    break;
                }
            }
            if !shrunk { break; }
        }
    }
    [&schema_stmts[..], &workload[..]].concat()
}

fn is_schema(s: &Stmt) -> bool {
    matches!(s.kind, StmtKind::CreateTable | StmtKind::CreateIndex | StmtKind::CreateView
                   | StmtKind::CreateTrigger | StmtKind::Pragma { schema_affecting: true })
}
```

### "Two failures with same signature = same bug"

```rust
impl MismatchSignature {
    pub fn dedup_key(&self) -> String {
        // First 16 hex chars of SHA-256 + subsystem name + classification discriminant.
        format!("{}-{:?}-{:?}",
            &self.hash[..16],
            self.subsystem,
            std::mem::discriminant(&self.classification))
    }
}

// In the failure-collection path:
fn record_failure(sig: MismatchSignature, bundle: FailureBundle) {
    let key = sig.dedup_key();
    let existing: Option<BeadId> = lookup_open_bead(&key);
    match existing {
        Some(bead_id) => link_failure_to_bead(bead_id, bundle),
        None => {
            let bead_id = open_new_bead(&sig, &bundle);
            insert_dedup_key(key, bead_id);
        }
    }
}
```

## Per-class instantiation — schema-preservation rules

| Class | "Schema" statements that are NEVER removed |
|---|---|
| **SQL** | `CREATE TABLE`, `CREATE INDEX`, `CREATE VIEW`, `CREATE TRIGGER`, `PRAGMA <schema_affecting>` (foreign_keys, journal_mode, page_size), `ATTACH DATABASE`, `WITH … AS …` recursive-CTE definitions |
| **RESP** | `SELECT <db>`, `CONFIG SET`, `MODULE LOAD`, key-creation commands for any key the workload reads (`SET prerequisite_key …`) |
| **Numerical / ML** | `import` statements, RNG seed setting (`np.random.seed`, `torch.manual_seed`), determinism config (`torch.use_deterministic_algorithms(True)`), device placement, dtype default |
| **HTTP** | Server setup (route registrations, middleware stack), authentication setup (issued tokens), DB seed inserts that any test request reads |

### Per-class `Subsystem` analogues

| Class | `Subsystem` enum variants |
|---|---|
| SQL | (verbatim above) Parser, Resolver, Planner, Vdbe, Storage, Wal, Mvcc, Functions, Extension, TypeSystem, Pragma, Unknown |
| RESP | Parser, CommandDispatch, Persistence, Replication, Cluster, PubSub, Eval, Modules, Networking, Unknown |
| Numerical | DtypePromotion, BroadcastEngine, UfuncDispatch, RngGenerator, BlasLapack, ArrayMemory, Unknown |
| ML | DispatchTable, Autograd, KernelLauncher, AllocatorPool, NcclTransport, JitCache, Unknown |
| HTTP | Routing, Extraction, Validation, Middleware, DI, Serialization, Unknown |

## Composition

- [pattern:40-METAMORPHIC-TRANSFORMS](40-METAMORPHIC-TRANSFORMS.md) — `MismatchClassification` is the field of `MismatchSignature`.
- [pattern:90-FAILURE-BUNDLE](90-FAILURE-BUNDLE.md) — every failure bundle carries the minimized workload + the signature; dedup happens before bead creation.
- [pattern:95-FIRST-FAILURE-EXPLAINER](95-FIRST-FAILURE-EXPLAINER.md) — the explainer cites the minimal first-diverging statement, sourced from `MismatchSignature.first_diverging_sql`.
- [pattern:180-NEGATIVE-LEDGER](180-NEGATIVE-LEDGER.md) — closed bugs land in the conformance ledger; the dedup_key prevents the same root-cause bug from getting two ledger entries.

## Pitfalls

- **Schema-preservation guard too narrow.** Forgetting `CREATE TRIGGER` or `ATTACH DATABASE`: the minimizer deletes the trigger that the bug depends on, the divergence vanishes, the minimizer says "done", and now the agent is debugging a smaller test that doesn't reproduce the bug. Conservative is correct here.
- **Schema-preservation guard too broad.** Treating *every* `PRAGMA` as schema means harmless toggle pragmas (`PRAGMA case_sensitive_like = ON`) cannot be removed even when they're irrelevant. Use the `schema_affecting: bool` annotation.
- **Minimization runs in serial.** A 200-statement test can take hours to minimize. Parallelize the binary-partition step (try first-half and second-half concurrently); only the post-partition single-statement deletion is inherently serial.
- **Dedup key includes timestamps.** The whole point is that two failures discovered at different times produce the same key. The hash is of the *canonical* minimal repro — sorted statements (where order doesn't matter), normalized whitespace, no temp-table names that vary per run.
- **Treating `Unknown` subsystem as actionable.** When the classifier can't decide, it returns `Unknown`. The triage queue should de-prioritize `Unknown` and surface the failure for human classification before opening a bead.
- **`first_diverging_sql` truncated mid-token.** If the first-diverging statement is 4KB, displaying the first 80 chars cuts in the middle of a CTE. Truncate at statement boundaries; for very long statements, hash the rest into the signature and show the first 80 chars + `...<sha:abc123>`.
- **`reproduces_divergence` not deterministic.** If the workload is timing-sensitive (e.g., depends on a `BUSY_TIMEOUT` lottery), minimization shrinks until the timing window changes and "reproduces" becomes false. Run each candidate ≥3 times and require all reproductions to be byte-identical before considering it a valid reduction step.
- **Skipping the single-statement deletion phase.** Binary partition reduces by half each round but stops at a local minimum; the single-statement deletion is what gets you to truly 1-minimal. Skipping it leaves you with 8-statement repros that should be 3-statement repros.
- **Opening a new bead for every variant of the same bug.** Without the dedup_key, a fuzz run finds the same NULL-handling bug 50 times and opens 50 beads. The dedup_key collapses them into 1 with 50 reproductions.
