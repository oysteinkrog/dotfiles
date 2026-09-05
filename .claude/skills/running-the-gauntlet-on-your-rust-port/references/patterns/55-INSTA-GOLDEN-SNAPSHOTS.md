# Pattern 55 — INSTA GOLDEN SNAPSHOTS (internal-layer regression pinning)

## What

`cargo insta` (`cargo insta test --review`, `cargo insta accept`) wraps every internal-layer artifact — VDBE bytecode, query plan text, RESP frame transcripts, OpenAPI schemas, JIT-IR dumps, autograd graph serializations — in a committed `.snap` file. A failing snapshot is a regression *unless* the contract changed; a passing snapshot is a frozen guarantee that the bytecode-or-plan didn't drift behind the agent's back. Regenerate only when a contract change is explicitly intended; never to make red green.

## Why

> "Insta snapshots: Subject = current build's bytecode/plan; Oracle = last-committed `.snap`; Comparator = text equality." — MINING-2 §Summary

Differential V2 catches behavior changes (different rows out). Insta catches *internal-layer* changes (same rows out, but the query planner picked a different plan). Same rows can hide a 10x performance regression behind a "no-functional-change" PR. Snapshots make that drift loud at PR review time: the diff IS the review.

## Where in FrankenSQLite

- `crates/fsqlite-vdbe/tests/snapshots/` — VDBE bytecode + plan snapshots
- `crates/fsqlite-planner/tests/snapshots/` — query plan tree snapshots
- `crates/fsqlite-wal/tests/snapshots/` — WAL frame format snapshots
- Workflow: `cargo insta test --review` (inspect diffs), `cargo insta accept` (commit), `cargo insta reject` (regenerate after intended contract change)

## Verbatim shape — the workflow

```bash
# Phase 1: run the suite
cargo insta test --review

# Snapshots get written as *.snap.new files alongside the existing *.snap.
# An interactive review session shows each diff and lets the human choose:
# (a)ccept | (r)eject | (s)kip | (q)uit
cargo insta review

# Or batch-accept after manual diff inspection (for intended changes only):
cargo insta accept
```

### Canonical `.snap` shape (insta v1.x)

```
---
source: crates/fsqlite-vdbe/tests/snapshot_bytecode.rs
expression: bytecode_for_query("SELECT x FROM t WHERE y > 5")
---
[
  OpenRead(0, t, 1),
  Rewind(0, 12, 0),
  Column(0, 1, r1),
  Lt(r1, 5, 11),
  Column(0, 0, r2),
  ResultRow(r2, 1, 0),
  Next(0, 2, 0),
  Halt,
]
```

The `---` block is YAML metadata; the body is the rendered artifact (text-equality compared).

## Per-class instantiation — snapshot inventory

### SQL-class

| Snapshot category | Path | Trigger to regenerate |
|---|---|---|
| **Query plan** (`explain_query_plan` output) | `crates/fsqlite-planner/tests/snapshots/plan__*.snap` | Planner heuristic change (must accompany perf claim with attribution) |
| **VDBE bytecode** | `crates/fsqlite-vdbe/tests/snapshots/bytecode__*.snap` | Opcode addition/removal/renaming; bytecode-cache key change |
| **WAL frame format** | `crates/fsqlite-wal/tests/snapshots/wal_frame__*.snap` | WAL format version bump |
| **PRAGMA introspection** | `crates/fsqlite-pragma/tests/snapshots/pragma__*.snap` | New PRAGMA added; existing PRAGMA semantics changed |
| **Schema migration plan** | `crates/fsqlite-schema/tests/snapshots/migration__*.snap` | DDL parser change |

### RESP-class

| Snapshot category | Path | Trigger to regenerate |
|---|---|---|
| **RESP frame transcript** | `crates/frankenredis-protocol/tests/snapshots/resp__*.snap` | RESP3 type addition; encoding optimization |
| **Command dispatch trace** | `crates/frankenredis-dispatch/tests/snapshots/dispatch__*.snap` | New command; command rename |
| **RDB header layout** | `crates/frankenredis-persistence/tests/snapshots/rdb__*.snap` | RDB version bump |
| **Cluster slot table** | `crates/frankenredis-cluster/tests/snapshots/slots__*.snap` | Slot-resharding logic change |

### Numerical / ML-class

| Snapshot category | Path | Trigger to regenerate |
|---|---|---|
| **JIT-IR dump** | `crates/frankenjax-jit/tests/snapshots/jaxpr__*.snap` | Primitive lowering rule change |
| **Autograd graph** | `crates/frankentorch-autograd/tests/snapshots/graph__*.snap` | Backward-pass synthesis change |
| **Dtype promotion table** | `crates/franken_numpy-dtype/tests/snapshots/promotion__*.snap` | Promotion rule change |
| **Optimizer step trace** | `crates/frankentorch-optim/tests/snapshots/step__*.snap` | Optimizer formula change |

### HTTP-class

| Snapshot category | Path | Trigger to regenerate |
|---|---|---|
| **OpenAPI schema** | `crates/fastapi_rust-openapi/tests/snapshots/openapi__*.snap` | Route signature change; schema generation cache key change |
| **Route table** | `crates/fastapi_rust-router/tests/snapshots/routes__*.snap` | Route addition/removal |
| **Validation-error format** | `crates/fastapi_rust-validation/tests/snapshots/errors__*.snap` | Pydantic version bump; error format policy change |
| **Middleware order** | `crates/fastapi_rust-middleware/tests/snapshots/order__*.snap` | Middleware stack reordering |

## Composition

- [pattern:05-SUBJECT-ORACLE-COMPARATOR](05-SUBJECT-ORACLE-COMPARATOR.md) — insta is the row labeled "Subject = current build's bytecode/plan; Oracle = last-committed `.snap`; Comparator = text equality".
- [pattern:50-THREE-TIER-EQUIVALENCE](50-THREE-TIER-EQUIVALENCE.md) — insta snapshots are Tier 1 raw byte equality on the rendered text.
- [pattern:90-FAILURE-BUNDLE](90-FAILURE-BUNDLE.md) — an insta failure produces a bundle with the `.snap` diff as the divergence body.
- [pattern:30-DIFFERENTIAL-V2-ENVELOPE](30-DIFFERENTIAL-V2-ENVELOPE.md) — insta and Differential V2 are siblings: insta catches internal-layer drift; Differential V2 catches behavioral drift. Both required.

## Regeneration discipline

**Regenerate only when the contract changes; never to make red green.**

The discipline:

1. **Red insta** → first reaction is *investigate*, not *accept*. The diff is the test failing on purpose.
2. If the diff reflects an *intended* contract change (e.g., a new opcode was added on purpose), the PR includes both the code change AND `cargo insta accept` in separate commits with the second commit's message explaining *why* the contract changed.
3. If the diff is unintended, the test is doing its job — block the PR until the source-side change is reverted or justified.
4. Never `cargo insta accept` without reading every diff.

## Pitfalls

- **`cargo insta accept` in CI to "fix" flaky tests.** This is the K-2 anti-pattern: the harness now lies. If a snapshot test is flaky, the rendered output is non-deterministic; fix the renderer (sort the output, seed the RNG), don't accept whatever the latest run produced.
- **Snapshot covers too much.** A single snapshot of "the entire planner output for 100 queries" makes every PR look like a snapshot regression. Split into one snapshot per logical unit; the diff stays readable.
- **Snapshot covers too little.** A snapshot of `query.plan.first_node.name` only is useless; if the planner reorganizes the plan tree, the snapshot still matches but the plan changed. Snapshot the whole rendered tree.
- **Non-deterministic snapshot content.** Including timestamps, PIDs, memory addresses, or hash-set iteration order in a snapshot makes it permanently flaky. Strip or sort these before rendering.
- **Snapshot file not committed.** A snapshot in `.gitignore` cannot regression-pin anything. Every `.snap` lives in `tests/snapshots/` and is committed.
- **Insta running only locally.** If CI doesn't run `cargo insta test`, the regression catcher is a no-op. CI runs `cargo insta test --no-review --no-create` (fail-on-diff, fail-on-missing).
- **Insta accepted without diff review during a rebase.** A merge that involves snapshot conflicts is the most dangerous moment; the temptation is to "just regenerate". Resolve manually, diff the result against both parents, and only then accept.
- **Treating insta as a behavior test.** Insta catches internal-layer drift; it does NOT prove the behavior is correct. Pair every snapshot test with a Differential V2 behavior test ([pattern:30-DIFFERENTIAL-V2-ENVELOPE](30-DIFFERENTIAL-V2-ENVELOPE.md)). Snapshot says "the plan didn't change"; differential says "the answer is right".
