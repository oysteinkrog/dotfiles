# FUZZ-TOOLCHAIN.md — Coverage-Guided + Structure-Aware + Differential Fuzzing

How to wire `cargo-fuzz` (libFuzzer), `cargo-afl` (AFL++), `arbitrary` / `bolero` (structure-aware), and the differential-fuzz pattern that uses the oracle from [ORACLE-TOOLCHAIN.md](ORACLE-TOOLCHAIN.md) as the equivalence comparator. Cross-links: [SANITIZER-TOOLCHAIN.md](SANITIZER-TOOLCHAIN.md) for running fuzz harnesses under ASan/TSan/MSan; [CONCURRENCY-TOOLCHAIN.md](CONCURRENCY-TOOLCHAIN.md) for loom/shuttle complementary coverage.

## 0. Core Discipline

Three rules that make fuzz campaigns generate evidence instead of garbage:

1. **Every fuzz target is structure-aware (`arbitrary` derived).** Raw `&[u8]` is the slow path; valid-by-construction inputs cover real code paths.
2. **Differential fuzz prefers an oracle.** A panic-finding fuzz target finds panics; a differential fuzz target finds divergences from the reference, which is what matters for a port.
3. **Crashes are corpus.** A crash is checked into `proptest-regressions/` (or `corpus/<target>/seeds/`) immediately, with the seed in the filename.

---

## 1. `cargo fuzz` (libFuzzer)

### 1.1 Init + Run

```bash
cargo install cargo-fuzz
rustup toolchain install nightly

# Initialize the fuzz directory inside your crate
cd crates/fsqlite-parser
cargo +nightly fuzz init

# Add a target
cargo +nightly fuzz add fuzz_sql_parser

# Run the target (CTRL+C to stop)
cargo +nightly fuzz run fuzz_sql_parser

# Run with a runtime budget
cargo +nightly fuzz run fuzz_sql_parser -- -max_total_time=3600   # 1 hour

# Run with sanitizers (default is ASan; thread/memory/leak available)
cargo +nightly fuzz run fuzz_sql_parser --sanitizer thread
cargo +nightly fuzz run fuzz_sql_parser --sanitizer memory
cargo +nightly fuzz run fuzz_sql_parser --sanitizer leak
```

### 1.2 Target Skeleton (Raw `&[u8]`)

```rust
// fuzz/fuzz_targets/fuzz_sql_parser.rs
#![no_main]
use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    if let Ok(s) = std::str::from_utf8(data) {
        let _ = fsqlite_parser::parse(s);   // panic = bug
    }
});
```

### 1.3 Target Skeleton (Structure-Aware)

```rust
// fuzz/fuzz_targets/fuzz_expr_parser.rs
#![no_main]
use libfuzzer_sys::fuzz_target;
use arbitrary::Arbitrary;

#[derive(Arbitrary, Debug)]
struct ExprInput {
    op_seq:     Vec<BinOp>,
    leaves:     Vec<Leaf>,
    grouping:   Vec<bool>,
}

fuzz_target!(|input: ExprInput| {
    let expr_str = render_to_sql(&input);
    let _ = fsqlite_parser::parse_expr(&expr_str);
});
```

Structure-aware inputs hit semantically valid SQL ~99% of the time; raw `&[u8]` hits valid SQL <0.1% of the time. The 1000x coverage improvement is real.

### 1.4 Corpus Minimization

```bash
cargo +nightly fuzz cmin fuzz_sql_parser
# Reads fuzz/corpus/fuzz_sql_parser/, removes redundant inputs,
# leaves a minimal set covering the same edges.
```

Run weekly. Without minimization, corpora bloat to GBs and slow new runs.

### 1.5 Coverage Report

```bash
cargo +nightly fuzz coverage fuzz_sql_parser
cargo +nightly cov -- show \
    target/x86_64-unknown-linux-gnu/coverage/x86_64-unknown-linux-gnu/release/fuzz_sql_parser \
    --instr-profile fuzz/coverage/fuzz_sql_parser/coverage.profdata \
    > coverage.txt
```

Read `coverage.txt` to find blocks fuzzing hasn't reached. Each one is a TODO: write a structure-aware generator for that branch.

---

## 2. `cargo afl` (AFL++)

Complementary coverage strategy; better at finding bugs in branchy code that libFuzzer's coverage-guided strategy plateaus on.

```bash
cargo install afl

# AFL needs the target built with its instrumentation
cd crates/fsqlite-parser
cargo afl build --release --bin fuzz_sql_parser_afl

# Seed corpus directory MUST contain at least one valid input
mkdir -p in
echo "SELECT 1" > in/seed

# Run
cargo afl fuzz -i in -o out -- ./target/release/fuzz_sql_parser_afl

# Output: out/default/crashes/, out/default/hangs/, out/default/queue/
```

### When to prefer AFL over libFuzzer

| Pattern | Preferred |
|---|---|
| Stateful / multi-step input | AFL (mutation tracks edges across whole input) |
| Highly branchy switch statements | AFL (coverage-guided with branch entropy) |
| Numerical edge cases | libFuzzer with `arbitrary::Arbitrary` over float types |
| Stateless parsing | libFuzzer (faster fork + restart) |
| Memory-corruption hunting | Run both, sanitizer-built |

### Coverage-Guided Advantage

AFL's mutator is informed by edge coverage feedback: an input that hits a new edge gets promoted into the next-gen population. This is why AFL finds bugs in "deep" code paths that random mutation never reaches.

---

## 3. Structure-Aware Fuzzing via `arbitrary` / `bolero`

### 3.1 `arbitrary` — Derive on Input Types

```rust
use arbitrary::Arbitrary;

#[derive(Arbitrary, Debug)]
struct SqlScript {
    statements: Vec<Statement>,
}

#[derive(Arbitrary, Debug)]
enum Statement {
    Select  { columns: Vec<Column>, from: Table, where_: Option<Predicate> },
    Insert  { table: Table, rows: Vec<Row> },
    Update  { table: Table, set: Vec<(Column, Value)>, where_: Option<Predicate> },
    Delete  { table: Table, where_: Option<Predicate> },
    Pragma  { name: PragmaName, value: PragmaValue },
}
// ... Column, Table, Predicate, Row, Value derive Arbitrary too
```

`arbitrary::Arbitrary` reads bytes from the fuzzer-provided source and constructs typed values; the fuzzer's coverage feedback shapes which byte sequences produce which input shapes.

### 3.2 `bolero` — Test-Function-Native Fuzzing

```rust
use bolero::check;

#[test]
fn sql_parser_does_not_panic() {
    check!()
        .with_type::<SqlScript>()
        .for_each(|script| {
            let sql = script.to_sql_string();
            let _ = fsqlite_parser::parse(&sql);
        });
}
```

`bolero` runs as a regular `cargo test` invocation in property-testing mode; switches to libFuzzer/AFL via `cargo bolero test --engine libfuzzer sql_parser_does_not_panic`. Best for: integrating fuzz into existing test files without a separate `fuzz/` directory.

### 3.3 Reducing Search Space to Valid Inputs

The art of structure-aware fuzz is making the input type **as narrow as possible** while still generating diverse interesting inputs:

```rust
// BAD: generates mostly invalid column counts
#[derive(Arbitrary)]
struct Row { cols: Vec<Value> }

// GOOD: column count bounded by schema's column list
#[derive(Arbitrary)]
struct Row {
    #[arbitrary(with = |u: &mut Unstructured| u.int_in_range(0..=8))]
    col_count: usize,
    values: Vec<Value>,
}
```

---

## 4. The Differential-Fuzz Canonical Pattern

The pattern: an `arbitrary`-generated input drives **both** the reference and the subject through the same comparator from [ORACLE-TOOLCHAIN.md](ORACLE-TOOLCHAIN.md); any divergence is a bug.

```rust
// fuzz/fuzz_targets/fuzz_differential_sql.rs
#![no_main]
use libfuzzer_sys::fuzz_target;
use arbitrary::Arbitrary;

#[derive(Arbitrary, Debug)]
struct DiffScript {
    setup:   Vec<DDL>,
    queries: Vec<DMLOrQuery>,
}

fuzz_target!(|script: DiffScript| {
    // Both engines start from identical empty state.
    let subject   = fsqlite::Connection::open_in_memory().unwrap();
    let reference = rusqlite::Connection::open_in_memory().unwrap();

    // 1. Apply setup, both sides; ignore divergent-error setups (skip).
    for ddl in &script.setup {
        let s = sql::render(ddl);
        let sub_ok = subject.execute(&s).is_ok();
        let ref_ok = reference.execute_batch(&s).is_ok();
        if sub_ok != ref_ok { return; }   // setup divergence not interesting at this layer
    }

    // 2. Run each query against both sides.
    for q in &script.queries {
        let s = sql::render_query(q);
        let sub_result = frank_rows(&subject,   &s);
        let ref_result = sqlite_rows(&reference, &s);

        match (sub_result, ref_result) {
            (Ok(a), Ok(b)) if a == b => continue,              // PASS
            (Err(_), Err(_))         => continue,              // both-error = agreement
            (a, b) => {
                // CRASH: this triggers libfuzzer to save the input as a crash.
                panic!("DIFFERENTIAL DIVERGENCE\n  sql: {s}\n  sub: {a:?}\n  ref: {b:?}");
            }
        }
    }
});
```

When a panic fires, libFuzzer minimizes the input (its built-in minimizer) and saves it to `fuzz/artifacts/fuzz_differential_sql/crash-<sha>`. The agent's job: triage the crash through the [ORACLE-TOOLCHAIN.md § mismatch-minimizer](ORACLE-TOOLCHAIN.md) to dedupe by `MismatchSignature` and decide if it's `TrueDivergence` or a known-class divergence.

---

## 5. Existing FrankenSQLite Fuzz Targets

| Target | Harness shape |
|---|---|
| `fuzz_sql_parser` | Raw `&[u8]` → UTF-8 attempt → `parser::parse(s)`. Panic = parser bug. |
| `fuzz_expr_parser` | `Arbitrary<ExprInput>` → render → `parser::parse_expr(&str)`. Panic = expr-parser bug. |
| `fuzz_lexer` | Raw `&[u8]` → `lexer::tokenize(bytes)`. Panic = lexer bug. |
| `fuzz_record_roundtrip` | `Arbitrary<RecordPayload>` → `Record::encode(p) → bytes → Record::decode(bytes) → p'` ; assert `p == p'`. |
| `xor_merge_guard` | `Arbitrary<(VecA, VecB)>` → `xor_merge(a, b)` ; assert XOR-symmetry invariant: `xor_merge(a, b) == xor_merge(b, a)`. |

Each target is <30 lines. The point isn't cleverness; it's **multiplication**: 5 targets × 24 hours × 10k execs/sec = 4.3 billion inputs/day across the parser surface.

---

## 6. Per-Class Fuzz Targets

### 6.1 Redis (`frankenredis`)

| Target | Shape |
|---|---|
| `fuzz_resp_parser` | Raw `&[u8]` → `resp::parse(bytes)`. Catches: malformed bulk strings, integer-overflow length prefixes, embedded-CRLF in inline commands. |
| `fuzz_command_dispatch` | `Arbitrary<CommandSequence>` → render to RESP → run against subject AND vendored `redis-server`; differential on RESP-value-tree. |
| `fuzz_cluster_slot_router` | `Arbitrary<(key, slot_count)>` → `crc16(key) % slot_count`; assert == reference implementation. |
| `fuzz_rdb_roundtrip` | `Arbitrary<DbState>` → write RDB → read RDB → assert state equal. |

### 6.2 Torch / NumPy (`frankentorch` / `franken_numpy`)

| Target | Shape |
|---|---|
| `fuzz_ufunc_dispatch` | `Arbitrary<(UfuncName, [TensorSpec; N])>` → run subject + numpy/torch oracle; ULP-tolerant differential. |
| `fuzz_autograd_chain` | `Arbitrary<OpChain>` → forward + backward; assert `gradcheck_max_rel_error < 1e-5` against analytical Jacobian. |
| `fuzz_broadcasting` | `Arbitrary<(Shape, Shape)>` → assert subject + numpy agree on broadcast-shape output (or both error). |
| `fuzz_dtype_promotion` | `Arbitrary<(DType, DType)>` → `promote_types(a, b)` against `np.promote_types`. |
| `fuzz_rng_stream_parity` | `Arbitrary<(Seed, n_draws)>` → assert subject and `np.random.default_rng(seed)` produce bit-exact stream (PCG64DXSM). |

### 6.3 FastAPI (`fastapi_rust`) / FastMCP (`fastmcp_rust`)

| Target | Shape |
|---|---|
| `fuzz_router_match` | `Arbitrary<(RouteSpec, RequestPath)>` → match against subject + Python reference; assert identical handler-id. |
| `fuzz_json_body_parser` | Raw `&[u8]` → both subject and `pydantic.BaseModel.parse_raw`; classify error or compare structures. |
| `fuzz_validation_errors` | `Arbitrary<(Schema, JsonBody)>` → assert subject's error JSON matches Pydantic's structure (field, type, loc, msg, ctx). |
| `fuzz_mcp_tool_invocation` | `Arbitrary<(ToolSchema, Args)>` → invoke via JSON-RPC; assert outcome class (Success / ToolError / SchemaError / Cancelled) matches reference. |
| `fuzz_mcp_cancellation` | `Arbitrary<(CallSequence, CancelAt)>` → assert subject releases resources within budget. |

---

## 7. Corpus Management

### 7.1 Checked-In Regression Corpus

```
crates/fsqlite-parser/proptest-regressions/
  parser.txt                     # proptest-style; one regression per line
  expr_parser.txt
  lexer.txt

fuzz/corpus/fuzz_sql_parser/
  seeds/                         # hand-crafted seeds + curated crashes
    SELECT_basic
    SELECT_with_join
    SELECT_window_function
    ...
```

Every triaged crash becomes a `seed` after the fix lands. Why: the fixed code is now the *baseline*; regressing back into the bug means failing the in-suite property test before reaching production fuzz.

### 7.2 Mining Session History for Crashes

```bash
# Find every "panicked at" in the last 60 days of agent sessions
timeout 30s cass search "panicked at" --days 60 --robot-format jsonl --limit 200 --mode lexical --timeout 30000 > /tmp/panics.jsonl

# For each unique panic, check if there's a regression seed
jq -r '.context | match("at (.+?):(\\d+)").captures[].string' /tmp/panics.jsonl \
  | sort -u \
  | while read loc; do
        grep -l "$loc" fuzz/corpus/*/seeds/* || echo "MISSING: $loc"
    done
```

A panic recorded in session history but **not** represented in the regression corpus is an evidence gap. Open a bead.

### 7.3 `FailureBundle` Integration

Every differential-fuzz crash emits a `FailureBundle` per the schema in [ORACLE-TOOLCHAIN.md § failure-bundle equivalent](ORACLE-TOOLCHAIN.md):

```rust
fuzz_target!(|script: DiffScript| {
    if let Err(divergence) = run_differential(&script) {
        let bundle = FailureBundle {
            failure_type:        FailureType::Divergence,
            seed:                fuzzer_seed(),
            fixture_id:          format!("inline-{}", blake3_hex(&serialize(&script))),
            schedule_fingerprint: "single-thread".to_string(),
            artifact_sha256:     vec![],
            db_page_previews:    vec![],
            wal_state_at_failure: None,
            expected_vs_actual:  divergence.render(),
            first_divergence_jsonptr: divergence.jsonptr(),
            git_sha:             env!("FSQLITE_GIT_SHA").to_string(),
            toolchain_version:   env!("FSQLITE_TOOLCHAIN").to_string(),
            platform:            std::env::consts::OS.to_string(),
            feature_flags:       vec!["fuzz".to_string()],
        };
        bundle.persist_at(format!("artifacts/fuzz-bundles/{}.json", bundle.artifact_id()));
        panic!("DIVERGENCE: {}", divergence);
    }
});
```

---

## 8. Soak Campaigns

A soak campaign is a fuzz run dispatched to `rch` with a multi-day budget. Verbatim discipline: **24h+ differential fuzz against previously-divergent APIs** before declaring an API "stable".

### 8.1 Dispatch Pattern

```bash
# Local-only: 1 hour, low confidence
cargo +nightly fuzz run fuzz_differential_sql -- -max_total_time=3600

# rch-offloaded: 24 hours per worker × N workers
rch dispatch \
    --workers 8 \
    --runtime 24h \
    --output artifacts/soak/$(date +%s)/ \
    -- cargo +nightly fuzz run fuzz_differential_sql -- -max_total_time=86400 -workers=8
```

Each `rch` worker runs a single sanitizer-built fuzz target with a different start seed; combined corpus is union'd back into the repo at end.

### 8.2 When a Soak Campaign Is Mandatory

- Any API that has had a `TrueDivergence` in the last 90 days.
- Any API gated by an `EquivalenceExpectation::MultisetEquivalence` (looser equivalence → more chance for hidden bugs).
- Pre-release Phase 15 ([../methodology/SOAK-PROTOCOL.md](../methodology/SOAK-PROTOCOL.md)).

### 8.3 Reporting

Soak output:
```
artifacts/soak/<ts>/
  corpus/                                      # new edges covered
  crashes/                                     # de-duped via MismatchSignature
  coverage-report.txt                          # delta vs pre-soak baseline
  execs-per-second.json                        # throughput; flag if <5k/s (something hanged)
  longest-input-bytes.json                     # flag >1MB; fuzzer is stuck on giants
```

---

## 9. Pitfalls

| Pitfall | Why it bites | Fix |
|---|---|---|
| Non-deterministic generators | Same input → different output → unreproducible crash | `arbitrary::Arbitrary` derive is deterministic; if you write a custom `Arbitrary` impl, it must be too. No `rand::random()`. |
| Mocking the reference | Comparing subject against subject = always passes | Use the real reference: vendored `redis-server`, PyO3 numpy, real Pydantic, etc. EngineIdentity check from ORACLE-TOOLCHAIN.md §4. |
| Unbounded input sizes | Fuzzer generates 100MB inputs, OOMs | `arbitrary` bounded with `int_in_range(0..=N)`; libFuzzer `-max_len=8192`. |
| Crash without minimization | A 50KB crash input is useless for triage | libFuzzer minimizes on crash automatically; if using AFL, `cargo afl tmin` after. |
| Crash not added to corpus | Same bug re-found next campaign | Every triaged crash → `fuzz/corpus/<target>/seeds/` (after the fix lands as baseline). |
| Sanitizer disabled in soak | Soak finds slow-but-valid divergences but misses UB | Sanitizer-built per [SANITIZER-TOOLCHAIN.md](SANITIZER-TOOLCHAIN.md); see §1.1 above for `--sanitizer` flag. |
| Fuzz directory not in CI | Fuzz targets bit-rot | At minimum, CI runs `cargo +nightly fuzz check fuzz_*` to confirm targets compile. Light-touch nightly: 5-minute run per target. |
| Coverage report skipped | Don't know what fuzz missed | Run `cargo fuzz coverage` quarterly; new uncovered blocks are bead candidates. |
| Differential fuzz without dedup | One root-cause bug = 1000 crash files in the bundle store | `MismatchSignature` from [ORACLE-TOOLCHAIN.md § mismatch-minimizer](ORACLE-TOOLCHAIN.md) dedupes. |
| Schema-changing inputs in setup | Setup divergence masks query divergence | Filter at `if sub_ok != ref_ok { return; }` in setup phase (§4); analyze setup divergences in a separate target. |

---

## See Also

- [ORACLE-TOOLCHAIN.md](ORACLE-TOOLCHAIN.md) — the comparator + `MismatchSignature` differential-fuzz dedupes against.
- [SANITIZER-TOOLCHAIN.md](SANITIZER-TOOLCHAIN.md) — building fuzz targets under ASan/TSan/MSan.
- [CONCURRENCY-TOOLCHAIN.md](CONCURRENCY-TOOLCHAIN.md) — `loom` / `shuttle` for concurrency-divergence fuzz that libFuzzer can't reach.
- [BENCH-TOOLCHAIN.md](BENCH-TOOLCHAIN.md) — running fuzz under perf instrumentation when corpus generation is the bottleneck.
- [../methodology/SOAK-PROTOCOL.md](../methodology/SOAK-PROTOCOL.md) — multi-day fuzz campaigns in Phase 15.
- [../experiments/EXAMPLE-EXPERIMENTS-CONFORMANCE.md](../experiments/EXAMPLE-EXPERIMENTS-CONFORMANCE.md) — worked examples of differential-fuzz experiment designs.
