# SIBLING-PROJECTS STATUS — Adoption per Project

> Per-sibling: where they are, what they've adopted, what's missing, and the next concrete action. Lead with the cross-sibling maturity matrix; then one section per sibling.

---

## Cross-Sibling Maturity Matrix (verbatim from MINING-1 §8 / CC.md §107)

| Sibling | Conformance | Ledger | cass | Agent Mail | bv | Math layer | MT-scale harness | RaptorQ |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| FrankenSQLite | ✅ | ✅ 380 entries | ✅ | ✅ | ✅ | ✅ full | ✅ mt-mvcc-bench | ✅ wal-fec |
| FrankenNumPy | ✅ | ✅ DIVERGENCES | ✅ | ✅ | ✅ | ⚠️ partial | ❌ N/A | ✅ |
| FrankenRedis | ✅ | ⚠️ implicit | ✅ | ✅ | ✅ | ❌ | ⚠️ implicit | ❌ |
| FrankenTorch | ✅ | ⚠️ implicit | ✅ | ✅ | ✅ | ⚠️ partial | ⚠️ distributed only | ❌ |
| FrankenJAX | ✅ implicit | ❌ | ⚠️ | ⚠️ | ⚠️ | ❌ | ❌ | ❌ |
| FrankenPandas | ⚠️ "1,252 packets" | ❌ | ⚠️ | ⚠️ | ⚠️ | ❌ | ❌ | ❌ |
| FrankenSciPy | ⚠️ "767 files" | ❌ | ⚠️ | ⚠️ | ⚠️ | ⚠️ CASP only | ❌ | ❌ |
| FrankenNetworkX | ✅ via backend protocol | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| FastAPI Rust | ❌ | ❌ | ✅ | ⚠️ | ⚠️ | ❌ | ❌ | ❌ |
| FastMCP Rust | ❌ | ❌ | ✅ | ⚠️ | ⚠️ | ❌ | ❌ | ❌ |
| SQLModel Rust | ❌ | ❌ | ⚠️ | ⚠️ | ⚠️ | ❌ | ❌ | ❌ |
| Franken Whisper | ❌ | ❌ | ⚠️ | ⚠️ | ⚠️ | ❌ | ❌ | ❌ |

Legend: ✅ adopted in full • ⚠️ partial/implicit • ❌ not yet

The matrix is the **adoption gradient** — projects in the top rows have inherited the full gauntlet; projects in the bottom rows are still primarily surface-level ports.

---

## FrankenSQLite — `/dp/frankensqlite`

**Status row:** ✅ ✅ 380-entries ✅ ✅ ✅ ✅ full ✅ ✅

**Has adopted (full discipline):**
- `crates/fsqlite-e2e/src/bin/comprehensive_bench.rs` (6,040 LOC) with `measure()`+`measure_with_teardown()`, six weighted scenario categories, JSON v3 self-describing reports, `release-perf` profile, `concurrent_mode_default_guard.txt`
- `.bench-history/{comprehensive-bench,mt-mvcc-bench,mt-mvcc-bench.separate-tables}.latest.json` (committed)
- `crates/fsqlite-harness/src/{oracle.rs,differential_v2.rs,metamorphic.rs,mismatch_minimizer.rs,fault_vfs.rs,eprocess.rs,score_engine.rs,replay_harness.rs,drift_monitor.rs,adversarial_search.rs,failure_bundle.rs,e2e_log_schema.rs,first_failure_explainer.rs,oracle_preflight_doctor.rs,fixture_root_contract.rs,parity_taxonomy.rs,closure_wave.rs,performance_regression_detector.rs}`
- 380-entry `docs/progress/perf-negative-results.md`
- AGENTS.md mandate paragraph with 60-day cass mining requirement
- Cross-machine cass infrastructure
- bv robot endpoints
- Full §75–76 math toolkit applied in eprocess + score_engine + replay_harness + arc_buffer_pool
- 8-thread mt_mvcc_bench as canonical concurrency stress
- RaptorQ for WAL FEC

**Missing or partial:**
- Closure-wave only covers Parser/Resolver/Pragma domains (CC.md §12 — three of N domains).
- Some §75–76 results are frontier-math *proposals* (P2 Azuma, P4 Nemhauser, P5 PAC-Bayes, P6 Little's-Law-MPC, P7 Lai-Robbins, P8 renewal-reward) — not yet landed.
- `adversarial_search.rs` covers gates but adversarial coverage of NEW gates is manual not auto-generated.

**Next action (priority order):**
1. Close out remaining frontier-math proposals P2/P4/P5/P6/P7/P8 if EV justifies.
2. Expand closure-wave to cover {Planner, VDBE, Storage, WAL, MVCC, Functions, Extension, TypeSystem}.
3. Wire auto-adversarial-search generator: when a new gate lands, queue an adversarial-search task for it.
4. Hold the line on the discipline; FrankenSQLite is the *reference adoption*.

---

## FrankenNumPy — `/dp/franken_numpy`

**Status row:** ✅ ✅ DIVERGENCES ✅ ✅ ✅ ⚠️ partial ❌ N/A ✅

**Has adopted:**
- `numpy.__all__` structural-gate parity
- Tensor bundles + dtype/shape manifests + RNG-stream fixtures (bit-exact PCG64DXSM)
- DIVERGENCES ledger (more focused than FrankenSQLite's "rejected ideas" ledger; surfaces actual divergences from NumPy parity)
- cass + Agent Mail + bv tooling
- RaptorQ (re-used from FrankenSQLite ecosystem)

**Missing or partial:**
- Math layer is "partial" — has bit-exact RNG but not the full §75–76 toolkit applied to ufunc dispatch.
- No MT-scale harness because NumPy is fundamentally single-threaded in its hot paths (mark as N/A per matrix).
- No equivalent of FrankenSQLite's `comprehensive_bench.rs` six-weighted-category structure; benches are present but unweighted.

**Next action (priority order from MINING-1 §8 / CC.md §99):**
1. **Lift FrankenSQLite's `comprehensive_bench` template.** Six weighted categories adapted for NumPy: `UfuncDispatch 0.30 / Reductions 0.20 / ShapeTransforms 0.15 / Linalg 0.15 / RNGDistributions 0.10 / IOFormats 0.10` (proposal weights; revise after baseline).
2. **Explicit metamorphic relation catalog.** Per-ufunc: `ExactBitEqual` for integer ops, `UlpToleranceEqual { n_ulps }` for float ops, `BroadcastEquivalent` for shape transforms.
3. **Cross-reference G1-G8 to FrankenSQLite Phase-1..Phase-9 plan.** Each G-level (Group 1..8 in NumPy's plan) maps to a Phase deliverable in this skill's 16-Phase Loop.
4. Apply §75–76 toolkit selectively: Beta-Binomial for ufunc pass rates, e-process for `numpy.testing` invariant monitoring, BOCPD for performance regime tracking.

---

## FrankenRedis — `/dp/frankenredis`

**Status row:** ✅ ⚠️ implicit ✅ ✅ ✅ ❌ ⚠️ implicit ❌

**Has adopted:**
- Conformance vs vendored Redis/Valkey 7.2.4 via RESP transcripts
- RDB/AOF byte fixtures, stream/group fixtures
- cass + Agent Mail + bv tooling
- "Implicit" ledger: rejected event-loop changes, parser fast paths, allocator swaps, write coalescing, AOF batching, RDB codec changes are discussed in commit messages but not in a central `docs/progress/perf-negative-results.md`-style file.
- "Implicit" MT-scale: handles N concurrent client connections but doesn't have a `mt_mvcc_bench`-class adversarial workload.

**Missing or partial:**
- **No central perf-negative-results ledger.** Discussions live in commit messages and chat; new agents have to mine from scratch.
- **No `RespValue` normalized comparator** with all 14 RESP3 types.
- **No formal e-process layer** for invariant monitoring ("RESP frames well-formed", "PUBSUB ordering FIFO per subscriber", "DEL idempotent within transaction").
- No RaptorQ adoption (Redis doesn't need WAL-FEC the same way; AOF is the analog).

**Next action (priority order, from MINING-1 §8 / CC.md §97):**
1. **Add `docs/progress/perf-negative-results.md` header from FrankenSQLite verbatim** (CC.md lines 479–482 quote). Mandate it in AGENTS.md.
2. **Add AGENTS.md paragraph** with 60-day cass mining mandate; failure terms per RESP class (`rejected, reverted, slower, regressed, didn't help, within noise, parser refactor backed out, allocator swap reverted`).
3. **Build `RespValue::{14 RESP3 types}` normalized comparator.** Single canonical form for `Null, BlobString, SimpleString, SimpleError, Number, Double, Bool, BigNumber, BlobError, VerbatimString, Map, Set, Attribute, Push`. Asserted via `EngineIdentity` analogue.
4. **Define "RPS p99 latency" primary score** with explicit threshold (e.g., `−3%` p99 regression triggers rejection). Six weighted categories proposed: `StringCommands 0.25 / HashCommands 0.15 / ListCommands 0.10 / SortedSetCommands 0.15 / StreamCommands 0.10 / PubSub 0.05 / Persistence 0.15 / ReplicationLag 0.05`.
5. **Start `.bench-history/comprehensive_bench.latest.json` baseline.** Commit. Run weekly; ratchet enforced.
6. (Later) Add e-process invariants for RESP framing, PUBSUB ordering, DEL idempotence.

---

## FrankenTorch — `/dp/frankentorch`

**Status row:** ✅ ⚠️ implicit ✅ ✅ ✅ ⚠️ partial ⚠️ distributed only ❌

**Has adopted:**
- PyTorch oracle (live PyTorch)
- Tensor input/output bundles, gradient bundles, state-dict fixtures
- Deterministic autograd ledgers (with `torch.use_deterministic_algorithms(True)`)
- cass + Agent Mail + bv tooling
- "Distributed-only" MT-scale: multi-GPU / multi-rank workloads tested via NCCL collectives + rendezvous, but the canonical "8-thread saturation stress" doesn't exist (Torch's hot paths are GPU kernel launches, not CPU contention).
- Partial math layer: gradient checking via finite differences, autograd JVP/VJP consistency tests — but no e-process invariants for "softmax sums to 1", no BOCPD for kernel-time regime detection.

**Missing or partial:**
- **No central perf-negative-results ledger** — kernel-fusion experiments, memory-format changes, allocator pooling are discussed but not centrally tracked.
- **No per-op ULP tolerance table.** Each op uses ad-hoc tolerances; this is fragile.
- **No equivalent of `comprehensive_bench.rs`** for per-op microbenchmarks + model forward/backward + optimizer step + transformer block.
- No metamorphic transform-equivalence tests (e.g., `LayerNorm(x) == Affine(Normalize(x))` under specific conditions).

**Next action (priority order, from MINING-1 §8 / CC.md §98):**
1. **Per-op ULP tolerance table as `docs/contracts/ulp_tolerance_v1.toml`.** One row per `aten::` op with the operator-class default (`4 ULP` for `f32` matmul, `2 ULP` for elementwise default), exception rows for known wider operators (`softmax: 8 ULP`, `log: 16 ULP`).
2. **Make `torch.use_deterministic_algorithms(True)` a `cargo test` invariant.** Drop a `concurrent_mode_default_guard.txt`-analog `determinism_default_guard.txt` per artifact lane.
3. **Build `TensorSpec { shape, dtype, device, requires_grad, data_hash }` normalized comparator.** This is the Torch analog of `NormalizedValue::normalize_value()`.
4. **Add metamorphic transform-equivalence tests.** TransformFamily analogs: `OperatorRewrite` (e.g., `x * 0 + y == y`), `LayerEquivalent` (e.g., `Conv1d == Conv2d with H=1`), `OptimizerStepEquivalent`, `GradFormalEquivalence` (forward vs reverse-mode AD).
5. **Start the ledger.** `docs/progress/perf-negative-results.md` with the verbatim header. Mine the last 90 days of chat/commits to seed initial entries.
6. (Later) Add e-process invariants for `softmax sums to 1.0 within ε`, `gradient norm bounded`, `autograd tape monotone in op count`.

---

## FrankenJAX — `/dp/frankenjax`

**Status row:** ✅ implicit ❌ ⚠️ ⚠️ ⚠️ ❌ ❌ ❌

**Has adopted:**
- JAX oracle for primitives + transforms (live JAX comparison)
- Trace Transform Ledger (jaxpr IR comparison)
- Transform stack signatures
- "Implicit" conformance — passes JAX oracle but no formal differential-V2-style envelope

**Missing or partial:**
- **No central perf ledger.**
- **cass, Agent Mail, bv all partial.**
- No math layer, no MT-scale harness, no RaptorQ.
- No e-process for JAX-specific invariants (e.g., "JIT-trace independence: same input → same jaxpr regardless of trace history").

**Next action:**
1. Wire cass + Agent Mail + bv to baseline.
2. Start `docs/progress/perf-negative-results.md`. JAX-specific failure terms: `traced incorrectly, jit cache miss spike, transform unrolled wrong, e-graph rewrite rejected`.
3. Build differential-V2-analog envelope for `(primitive, jaxpr signature, transform stack, expected output shape/dtype)`.
4. Define primary score: `jit-cached-call-rate p99 latency + transform-composition-correctness pass rate`.
5. Per-transform metamorphic catalog: `jit(grad(f)) == grad(jit(f))` (where defined), `vmap(jit(f)) == jit(vmap(f))`, etc.

---

## FrankenPandas — `/dp/frankenpandas`

**Status row:** ⚠️ "1,252 packets" ❌ ⚠️ ⚠️ ⚠️ ❌ ❌ ❌

**Has adopted:**
- 1,252 conformance packets from pandas oracle (per CODEX.md row)
- DataFrame JSON fixtures, IO roundtrips
- Partial cass/Agent Mail/bv

**Missing or partial:**
- **No ledger.** Discussions exist; central record does not.
- No math layer, no MT-scale harness, no RaptorQ.
- Conformance is "packet-style" — bundles of test cases — not the differential-V2 envelope pattern.

**Next action:**
1. Migrate 1,252 packets into envelope-format with `artifact_id = SHA-256` content-addressing.
2. Wire AGENTS.md mandate + ledger.
3. Primary score: `dataframe-op latency p99 + groupby/merge_asof correctness rate + IO-roundtrip byte-equality rate`.
4. Per-op metamorphic: `merge(A, B) == merge(B, A) reordered`, `groupby(K).agg(F) == groupby([K]).agg({col: F})`.

---

## FrankenSciPy — `/dp/frankenscipy`

**Status row:** ⚠️ "767 files" ❌ ⚠️ ⚠️ ⚠️ ⚠️ CASP only ❌ ❌

**Has adopted:**
- 767 conformance files (per CODEX.md row) covering domain crates for linalg/sparse/opt/integrate
- CASP solver policy (math layer is partial — only the CASP solver-selection math is wired)

**Missing or partial:**
- **No ledger, no formal AGENTS.md mandate.**
- cass + Agent Mail + bv all partial.
- Per-solver portfolio not benchmarked at the gauntlet level.

**Next action:**
1. Wire AGENTS.md mandate + ledger.
2. Per-solver portfolio bench: condition-number × sparsity × problem-size grid.
3. Tolerance policy: `docs/contracts/scipy_tolerance_policy_v1.toml` — per-solver default tolerances + exception rows.
4. Decision-fingerprint capture: when CASP picks solver X over Y, log the inputs + score; build differential against live SciPy's choices.

---

## FrankenNetworkX — `/dp/franken_networkx`

**Status row:** ✅ via backend protocol ❌ ❌ ❌ ❌ ❌ ❌ ❌

**Has adopted:**
- Backend-dispatch protocol (NetworkX 3.x's dispatch mechanism gives a clean parity surface)
- Python parity suite, graph fixture corpus, iteration-order snapshots, serialization roundtrips

**Missing or partial:**
- Everything except the conformance protocol.

**Next action:**
1. Wire cass + Agent Mail + bv.
2. Start the ledger; failure terms: `hash-layout-changed, iteration-order-divergent, parallel-tie-break-differs, backend-fallback-too-aggressive`.
3. Per-algorithm primary score: `traversal-throughput nodes/sec + algorithm-correctness rate`.
4. Per-family metamorphic: `BFS(G).reverse() == DFS(G.reverse())` (where defined).

---

## FastAPI Rust — `/dp/fastapi_rust`

**Status row:** ❌ ❌ ✅ ⚠️ ⚠️ ❌ ❌ ❌

**Has adopted:**
- cass tooling
- HTTP transcript fixtures, validation-error JSON, OpenAPI golden files, route macro compile-fail tests (per CODEX.md row)

**Missing or partial:**
- **No formal conformance harness** (vs FastAPI/Pydantic/OpenAPI behavior).
- No ledger, no math layer, no MT-scale harness, no RaptorQ.

**Next action:**
1. Build the conformance harness: `HTTP request → response normalized form` comparator. Status + headers case-insensitive + body MIME-aware + OpenAPI schema diff.
2. AGENTS.md mandate + ledger. Failure terms: `extractor fast path broke, parser zero-copy regressed, validation cache invalidated wrong, DI lifetime changed`.
3. Primary score: `requests/sec p99 latency` across `JSON body sizes × middleware stacks × concurrency`.
4. Five request-lifecycle crash boundaries (open / header / body-start / body-end / close + cancellation).

---

## FastMCP Rust — `/dp/fastmcp_rust`

**Status row:** ❌ ❌ ✅ ⚠️ ⚠️ ❌ ❌ ❌

**Has adopted:**
- cass tooling
- MCP transcript fixtures, tool/resource schema snapshots, outcome classification tests, cancellation scenarios

**Missing or partial:**
- Same as FastAPI Rust pattern; no formal conformance harness, no ledger, no math layer.

**Next action:**
1. Build the conformance harness: MCP protocol spec + Python FastMCP behavior comparator. JSON-RPC envelope + four-valued outcomes (success/error/cancelled/timeout) + capability security checks.
2. AGENTS.md mandate + ledger. Failure terms: `macro expansion changed, schema generation cache miss, budget enforcement weakened, resource streaming regressed, error mapping broke`.
3. Primary score: `tool invocation latency p99 + schema generation correctness rate + cancellation budget enforcement rate`.

---

## SQLModel Rust — `/dp/sqlmodel_rust`

**Status row:** ❌ ❌ ⚠️ ⚠️ ⚠️ ❌ ❌ ❌

**Has adopted:**
- Derive macro model schema
- Query builder, dialect SQL generation, validation
- Generated SQL golden files, schema migration snapshots, model derive compile-fail tests, DB roundtrip fixtures

**Missing or partial:**
- No central conformance harness vs Python SQLModel/SQLAlchemy.
- No ledger, no math layer.

**Next action:**
1. Build SQL-class oracle wiring (similar to FrankenSQLite — `rusqlite` for SQLite dialect parity).
2. Add comparator for `(query_built_AST, generated_SQL, executed_result)` against Python SQLModel.
3. AGENTS.md mandate + ledger. Failure terms: `query builder rewrite broke, SQL rendering cache key changed, relationship loading regressed, returning/upsert semantics drifted`.
4. Primary score: `query build time + insert/select/update/delete throughput + dialect SQL byte-equality rate`.

---

## Franken Whisper — `/dp/franken_whisper`

**Status row:** ❌ ❌ ⚠️ ⚠️ ⚠️ ❌ ❌ ❌

**Has adopted:**
- Stub of cass / Agent Mail / bv

**Missing or partial:**
- Almost everything. Treat as "Day 1" of the bootstrapping order.

**Next action:**
- Follow CC.md §24 bootstrapping order verbatim: Day 1 oracle.rs scaffold, Day 2 comprehensive_bench, Day 3 .bench-history, ... Day 60 certification_policy.rs.

---

## Cross-Reference

The Universal Floor (what every sibling must reach to be considered "on the gauntlet") is in [FRANKENSQLITE-BIBLE.md § Universal Floor](FRANKENSQLITE-BIBLE.md) → CC.md §23.12 lines 1493–1521.

The Day 1..Day 60 Bootstrapping Order is in [FRANKENSQLITE-BIBLE.md § Bootstrapping Order](FRANKENSQLITE-BIBLE.md) → CC.md §24 lines 1525–1540.

When porting the methodology to a new sibling (Day 0), use the **planning workflow**: `/planning-workflow` skill → assemble Day-1 deliverables → run gauntlet Phase 0 → enter Phase 1 recon.

---

**End of SIBLING-PROJECTS-STATUS.** The matrix is a snapshot; revise as projects move through the gradient. The matrix order roughly corresponds to FrankenSQLite-proximity: top rows have inherited the most discipline; bottom rows are still primarily surface-level ports waiting for the gauntlet to land.
