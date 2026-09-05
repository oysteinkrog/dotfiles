# fuzz-author

> Phase 6 • Build differential fuzz target with `arbitrary`-generated input passed through both reference and subject through the comparator; one per target.

## Inputs
- `<workspace>/phase0_project_class.json` (selects input grammar).
- `oracle.rs` (comparator) + `differential_v2.rs` (envelope) from earlier phases.
- Fuzz target name (`<target_name>`, e.g., `differential_sql`, `differential_resp_commands`, `differential_tensor_ops`, `differential_http_requests`) — passed as argument.

## Deliverables
- `<target>/fuzz/fuzz_targets/<target_name>.rs` (cargo-fuzz target).
- `<target>/fuzz/fuzz_targets/<target_name>_seed_corpus/` with seed inputs covering the supported-surface matrix.
- `<workspace>/phase6_fuzz_<target_name>.md` documenting grammar, oracle wiring, dedup strategy, expected steady-state corpus size.

## Coordination
- **MCP Agent Mail thread:** `gauntlet-<run-id>-phase6-fuzz-<target_name>`
- **Reservations needed:** `tool://fuzz-corpus::<target_name>` (TTL 90m).
- **Lane:** cc_1 (conformance).

## Verbatim Prompt

You are the fuzz target author for `<target_name>`. Build a differential cargo-fuzz target where:
1. `arbitrary`-generated input is interpreted as a sequence of operations against the subject's input grammar.
2. The same operation sequence is executed against the reference oracle.
3. Outputs are compared via the comparator (`oracle.rs`).
4. Any divergence becomes a `MismatchSignature` via the minimizer; the harness panics on first `TrueDivergence` so libFuzzer treats it as a crash and saves the input to the failure corpus.

**Skeleton:**
```rust
#![no_main]
use libfuzzer_sys::fuzz_target;
use arbitrary::{Arbitrary, Unstructured};
use <project>_harness::{scenario_for_fuzz, MismatchClassification};

#[derive(Arbitrary, Debug)]
struct Input { ops: Vec<Op>, seed: u64 }

#[derive(Arbitrary, Debug)]
enum Op { /* per-class grammar; see below */ }

fuzz_target!(|input: Input| {
    let mut subject = open_subject();
    let mut oracle  = open_oracle();
    for op in input.ops {
        let s = apply(&mut subject, &op);
        let o = apply(&mut oracle, &op);
        match (s, o) {
            (Ok(_),  Ok(_))  => continue,
            (Err(_), Err(_)) => continue, // both-error = agreement
            _ => {
                let sig = classify_and_minimize(&op, /* state snapshots */);
                if sig.classification.is_actionable() {
                    panic!("TrueDivergence: {:?}", sig);
                }
                // non-actionable classifications go to triage queue, not failure corpus
            }
        }
    }
});
```

**Per-class Op grammar:**
- **SQL-class:** `CreateTable { name, cols } | Insert { table, vals } | Select { table, where_ } | Update | Delete | Begin | Commit | Rollback | Pragma | CreateIndex`.
- **RESP-class:** `Set | Get | Del | Hset | Hget | Lpush | Rpush | Sadd | Zadd | Subscribe | Publish | Multi | Exec | Discard`.
- **ML-System-class:** `Add | Mul | Matmul | Reshape | Sum | Softmax | Conv | Backward | Optim`.
- **HTTP-Protocol-class:** `Get { path, params } | Post { path, body } | Put | Delete | Options | Head`.

**Seed corpus:** Cover every entry in `supported_surface_matrix.toml` with at least one seed. The fuzzer mutates from seeds; better seeds = better coverage.

**Dedup:** `classify_and_minimize` returns a `MismatchSignature` whose `hash` field deduplicates findings. Two crash inputs with identical hash are the same bug — only one beads issue.

**`SeedContract`:** the `seed` field of `Input` drives any internal randomness deterministically.

Document grammar, oracle wiring, dedup strategy, expected steady-state corpus size, and the rch-offload invocation (`cargo fuzz run <target_name> -- -max_total_time=86400`) in `phase6_fuzz_<target_name>.md`.

## Exit Criteria
- `cargo fuzz build <target_name>` succeeds.
- A 60-second smoke run discovers ≥10 unique inputs (`cargo fuzz coverage`).
- Seed corpus covers every category in `supported_surface_matrix.toml`.
- Deliberate planted bug (e.g., subject returns wrong result for a known input) is caught within 60s.
- `phase6_fuzz_<target_name>.md` committed.

## References
- [PHASES.md § Phase 6](../references/PHASES.md)
- [tooling/FUZZ-TOOLCHAIN.md](../references/tooling/FUZZ-TOOLCHAIN.md)
- [tooling/ORACLE-TOOLCHAIN.md § MismatchSignature](../references/tooling/ORACLE-TOOLCHAIN.md)
- [methodology/SOAK-PROTOCOL.md § fuzz](../references/methodology/SOAK-PROTOCOL.md)
