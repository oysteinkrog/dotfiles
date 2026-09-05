# pattern:200-HOT-OPCODE-PROMOTION

## What

Identify opcodes (or, more generally, match-arm dispatch targets) firing in inner loops billions of times per workload, and extract them into a **pre-match hot-path function** that handles the hot arms before falling through to the full dispatcher. The hot path takes the same opcode, hits the targeted arm in O(1), and returns `Ok(true)` if it handled it or `Ok(false)` if the caller should fall through to the full match. This reduces branch-misprediction overhead, shortens the hot-path instruction sequence, and lets the compiler aggressively inline the hot arms.

## Why

> "Identify opcodes firing in inner loops; extract them to a pre-match hot-path function to reduce branch misprediction overhead." — CC.md §53 (verbatim)

Failure mode prevented: *a 200-arm match in the hottest loop in the codebase*. When the VDBE step loop dispatches on `Opcode`, the cmov/branch predictor cannot keep up with 200 cold arms; the hot arms suffer the same prediction cost as the rare ones. Pre-matching them in a separate function lets the compiler emit a tight branch predictor-friendly sequence for the hot arms and isolates the cold dispatch entirely.

## Where in FrankenSQLite

- `crates/fsqlite-vdbe/src/engine.rs:7818` — `try_execute_hot_opcode` definition
- `crates/fsqlite-vdbe/src/engine.rs:12343` — call site in the step loop

## Verbatim shape

From CC.md §53:

```rust
fn try_execute_hot_opcode(&mut self, op: &VdbeOp, pc: &mut usize, ...) -> Result<bool> {
    match op.opcode {
        Opcode::Column              => { /* hot logic */ return Ok(true); }
        Opcode::ColumnSubstrPrefix  => { /* hot logic */ return Ok(true); }
        Opcode::ResultRow           => { /* hot logic */ return Ok(true); }
        // ... more pre-matched opcodes ...
        _ => Ok(false),
    }
}
```

Call-site pattern:

```rust
if self.try_execute_hot_opcode(op, &mut pc, ...)? {
    continue;  // hot path handled it
}
// fall through to full dispatch
match op.opcode { /* all 200+ arms */ }
```

## Measurement proof (verbatim, CC.md §53.1)

| Opcode | Gain (1t) | Gain (MT8) |
|---|---|---|
| `SCopy` | +38.6% | +37.8% |
| `IfNot` | +31.5% | +32.7% |
| `IsNull` | +27.5% | +27.2% |
| `AddImm` | +9.9% | — |
| `Copy` | +23.4% | +24.7% |
| `IdxRowid` | +5.3% | +8.7% |

## Spot the shape

In an unfamiliar codebase, look for:

1. A `match` / `switch` statement with **≥20 arms** sitting in an **inner loop**.
2. Profile (samply / perf record) showing the loop function in the top 10 self-time frames at ≥1%.
3. An opcode/command histogram across a representative workload showing **one or two arms fire ≥50%** of the time.
4. A profile-guided opt build (PGO) or LBR profile showing branch-misprediction cost concentrated in the dispatch.

If those four shapes hold, pre-match the top arms. Order: most-frequent arm first, then next-frequent, etc.

## Per-class transferability

| Class | Hot-dispatch site | Hot arms typically pre-matched |
|---|---|---|
| **SQL** (FrankenSQLite, SQLModel Rust) | VDBE opcode dispatch in `engine.rs::step_inner` | `Column`, `SCopy`, `IfNot`, `IsNull`, `ResultRow`, `Copy`, `IdxRowid`, `AddImm` |
| **RESP** (FrankenRedis) | Command dispatch table (`commandTable[]` style) in `process_command()` | `GET`, `SET`, `INCR`, `LPUSH`, `HGET`, `EXISTS`, `MGET` |
| **Numerical** (FrankenNumPy) | Ufunc dispatch in the BLAS layer (per-dtype) | `float64+float64→float64`, `float32+float32→float32`, `int64+int64→int64` |
| **ML** (FrankenTorch, FrankenJAX) | Aten op dispatch in `c10`-style core dispatcher | `add`, `mul`, `matmul`, `relu`, `softmax`, `layer_norm`, `linear` |
| **HTTP** (FastAPI Rust, FastMCP Rust) | Route-match trie traversal | root (`/`), `/health`, the project's top 5 traffic-share endpoints |

## Composition

- Pairs with [pattern:225-DEVIRTUALIZE-MATCH-ARM](225-DEVIRTUALIZE-MATCH-ARM.md) — devirt closes a different shape (trait → enum) but the underlying principle (concentrate the hot path) is the same.
- Pairs with [pattern:160-MT8-ATTRIBUTION](160-MT8-ATTRIBUTION.md) — the opcode-frequency histogram lives in the MT8 attribution profile.
- Pairs with [pattern:145-HOT-PATH-COUNTERS](145-HOT-PATH-COUNTERS.md) — per-opcode counters (e.g., `vdbe_step_opcode_<name>_count`) make the histogram cheap.
- Pairs with [pattern:150-PROFILE-FIRST-CARD](150-PROFILE-FIRST-CARD.md) — every pre-match landing must include the profile that justified arm selection.

## Pitfalls

- **Pre-matching every arm.** Defeats the purpose; the hot path becomes the full dispatcher. Pre-match only arms with ≥10% frequency in the representative workload.
- **No histogram.** Picking arms by intuition ("the column op feels hot") is a guess. The histogram is what makes the selection defensible in the ledger.
- **`_ => Ok(false)` arm doing real work.** The whole point is that the hot path is *short*; if the fallthrough arm allocates or hits the heap, the win evaporates.
- **`#[inline]` missing on the wrapper.** The pre-match function should be `#[inline]` or `#[inline(always)]`; without it the function-call overhead can absorb the win on small ops.
- **Forgetting the broad gate.** A wider workload may have a different histogram. The same-run-window rule applies: focused (e.g., per-opcode microbench) + broad (`comprehensive-bench`) must both move.
- **Adding a hot arm without removing it from the full match.** Both arms compile-out the unreachable one only if the compiler can prove it; `Ok(true)` + `continue` in the call site is the guarantee.
- **Per-class slip: RESP commands pre-matched by static frequency instead of per-deployment.** Different RESP deployments have wildly different command mixes (cache vs queue vs lock service); the arm selection should be parametric.
