# CASE-STUDIES — What Running the Gauntlet on Each Sibling Looks Like

Short case studies of what running the gauntlet on each of the Franken-family / Rust-port siblings would look like. Use this file to right-size effort BEFORE Phase 0; cross-reference [TIER-TRIAGE.md](TIER-TRIAGE.md) for tier definitions and [MODE-ROUTER.md](MODE-ROUTER.md) for mode definitions. For the current adoption-state truth of each sibling, see [exemplars/SIBLING-PROJECTS-STATUS.md](../exemplars/SIBLING-PROJECTS-STATUS.md).

These are calibration studies. They are not promises about wall time, finding-counts, or specific bugs — the gauntlet's value comes from the discipline applied, not from a script that predicts the outcome. But they help an orchestrator quote a wall-time estimate, pick the right tier, and anticipate the most-likely-high-impact finding class.

---

## FrankenSQLite — `/dp/frankensqlite`

**Reference:** SQLite (vendored C SQLite, currently pinned to 3.52.0).

**Tier:** **T4** (Platform).
**Recommended mode:** `gauntlet-full` for fresh runs; `incremental-rebase` for routine; `compliance-pass` for auditor re-cert.

**Pillar likely to need most work:** **Conformance.** Performance is well-managed (380-entry negative-ledger, MT-mvcc-bench, `comprehensive_bench.rs` mature). Surface is heavily inventoried (`parity_taxonomy.rs` + `invariant_catalog.rs` + `feature_coverage_dashboard.rs` all wired). The remaining headroom is **deeper conformance coverage**: metamorphic transformation families beyond Predicate/Projection/Structural/Literal, more closure-wave domains (currently Parser/Resolver/Pragma — needs Planner / VDBE / Storage / WAL / MVCC / Functions / Extension / TypeSystem), and more e-process invariant coverage (currently INV-1..INV-7 + INV-SSI-FP; needs INV-WAL-Recovery-Determinism etc.).

**Project-class-specific patterns to lift first:**
- Already lifted: the full kernel; six weighted scenario categories; `mt-mvcc-bench` MT8 attribution; pass-over-pass via `.bench-history`; `oracle_preflight_doctor.rs`; `failure_bundle.rs` with `first_divergence_jsonptr`; `eprocess.rs` with Howard-Ramdas-McAuliffe-Sekhon calibration; `score_engine.rs` with Beta posterior + conformal band; `replay_harness.rs` with BOCPD; RaptorQ-FEC for WAL self-healing.
- To lift next:
  1. **Closure-wave expansion** (Pattern from MINING-3 §12) — currently covers 3 domains; expand to the remaining 8.
  2. **Adversarial-search auto-generator** — when a new gate lands, queue an adversarial-search task for it. Currently manual.
  3. **§75–76 frontier-math closure** — P2 Azuma, P4 Nemhauser, P5 PAC-Bayes, P6 Little's Law + MPC, P7 Lai-Robbins, P8 renewal-reward. EV-justified ones land; the others go to the negative ledger.

**Estimated rounds to convergence (gauntlet-full):** **12-18 rounds.** FrankenSQLite is the reference adoption — the 10-round minimum is comfortably exceeded, and the codebase is large enough that genuine new findings keep surfacing in mid-rounds.

**Most likely high-impact finding (one sentence):** A new opcode or VDBE branch was added without a corresponding hot-path counter, so a MT8 attribution profile won't catch its regression — the closure-wave for VDBE will surface it.

**Wall time (T4 × gauntlet-full):** 30-45 days. **rch-offload mandatory.** Multi-model triangulation mandatory. Full certification bundle required.

---

## FrankenRedis — `/dp/frankenredis`

**Reference:** vendored Redis/Valkey (currently 7.2.4-7.2.5 range).

**Tier:** **T4** (Platform).
**Recommended mode:** `gauntlet-full` for first proper application of the gauntlet (per the SIBLING-PROJECTS-STATUS.md "Next-Action Lists per Sibling" §97, FrankenRedis has *implicit* ledger discipline but no central `perf-negative-results.md`).

**Pillar likely to need most work:** **Conformance + Surface.** The conformance pillar is the most underbuilt — no `RespValue` normalized comparator with all 14 RESP3 types yet; no formal e-process layer for invariant monitoring ("RESP frames well-formed", "PUBSUB ordering FIFO per subscriber", "DEL idempotent within transaction"). Surface enumeration is partial — 241 commands + RDB v11 + AOF + replication + Lua + cluster mode is a wide surface; the FeatureUniverse is missing entries.

**Project-class-specific patterns to lift first:**
1. **AGENTS.md mandate paragraph** — per MINING-1 §8 next action: "Add AGENTS.md paragraph mandating ledger reads before perf work."
2. **`docs/progress/perf-negative-results.md`** with the verbatim FrankenSQLite preamble.
3. **`RespValue::{14 RESP3 types}` normalized comparator** — per MINING-2 §1 generalization: `render_resp_value()` over the 14 RESP3 variants (SimpleString, Error, Integer, BulkString, Array, NullBulkString, NullArray, Boolean, Double, BigNumber, BulkError, VerbatimString, Map, Set, Push, Attribute).
4. **"RPS p99 latency" primary score** with explicit threshold.
5. **`.bench-history/comprehensive_bench.latest.json`** baseline.
6. **6+ AOF/RDB crash boundaries** — `BeforeAofRewriteRename`, `DuringRdbWrite`, `BeforeReplicationOffsetUpdate`, `MidPsync`, `AfterReplOffsetBeforeAck`, `DuringFsync`.
7. **`RdbFaultVfs`** — partial AOF rewrites, mid-rdb torn writes, fsync-then-power-cut, `EAGAIN` storms on replication socket.

**Estimated rounds to convergence (gauntlet-full):** **10-14 rounds.** First-round will surface most of the structural gaps; subsequent rounds will fill in coverage incrementally.

**Most likely high-impact finding (one sentence):** A PUBSUB ordering case where N subscribers receive messages out-of-order under replication backlog pressure — invariant "PUBSUB FIFO per subscriber" is violated but no e-process exists to catch it.

**Wall time (T4 × gauntlet-full):** 30-45 days, similar to FrankenSQLite. **rch-offload mandatory.**

---

## FrankenTorch — `/dp/frankentorch`

**Reference:** Live PyTorch (currently 2.X.Y range).

**Tier:** **T4** (Platform).
**Recommended mode:** `gauntlet-full`; per SIBLING-PROJECTS-STATUS.md §98 the ledger is "implicit" — needs the same formalization treatment as FrankenRedis.

**Pillar likely to need most work:** **Conformance.** Performance has the GPU profiling story (a different beast than CPU-side `samply`); surface is partially inventoried via aten dispatch table. Conformance is where the depth is needed: per-op ULP tolerance table is rough; `torch.use_deterministic_algorithms(True)` is not yet a `cargo test` invariant; metamorphic transform-equivalence tests are sparse.

**Project-class-specific patterns to lift first:**
1. **Per-op ULP tolerance table as `docs/contracts/ulp_tolerance_v1.toml`** — per MINING-1 §8 / CC.md §98 next action.
2. **`torch.use_deterministic_algorithms(True)` as `cargo test` invariant** — enforced by the harness, not the test author.
3. **`TensorSpec { shape, dtype, device, requires_grad, data_hash }` normalized comparator** — per MINING-2 §1 generalization.
4. **Metamorphic transform-equivalence tests** — `forward(transform(x)) ≈ transform(forward(x))` for differentiable transforms.
5. **Ledger seed** — `docs/progress/perf-negative-results.md` + AGENTS.md mandate paragraph.
6. **`CheckpointFaultVfs`** — partial `torch.save`, mid-shard NCCL drops, `CUDA_ERROR_LAUNCH_FAILED` mid-collective.
7. **5 checkpoint-save crash boundaries + 2 distributed-collective** — per MINING-2 §9 per-class table.
8. **E-process invariants** — "softmax outputs sum to 1.0 within ε", "autograd gradient matches forward-mode JVP within ε".

**Estimated rounds to convergence (gauntlet-full):** **12-18 rounds.** Distributed coordination + GPU determinism + per-op ULP variability all conspire to surface findings deep into the iteration loop.

**Most likely high-impact finding (one sentence):** An operator's per-op ULP tolerance was set generously (e.g., 4 ULP for matmul) but a specific dtype × shape combination consistently exceeds it; the metamorphic relation catches it but the existing per-op tolerance hid it.

**Wall time (T4 × gauntlet-full):** 30-60 days. **rch-offload mandatory; GPU resources required for soak.**

---

## FrankenJAX — `/dp/frankenjax`

**Reference:** Live JAX (for primitives + transforms).

**Tier:** **T3** (Workspace) — borderline T4 because of the nested transform matrix; treat as T3 with the **compile-time codegen** + **numerical determinism** overlays from [TIER-TRIAGE.md § Complexity overlay](TIER-TRIAGE.md). Effectively T4 for those features.

**Recommended mode:** `gauntlet-full` (first proper application).

**Pillar likely to need most work:** **All three** — per SIBLING-PROJECTS-STATUS.md FrankenJAX has ❌ on Ledger, ⚠️ on cass / Agent Mail / bv. Foundational discipline is missing.

**Project-class-specific patterns to lift first:**
1. The ENTIRE FrankenSQLite floor (per MINING-3 §15 "Universal Floor"): `oracle.rs`, `differential_v2.rs`, `ratchet_policy.rs`, `failure_bundle.rs`, `e2e_log_schema.rs`, `fault_vfs.rs` equivalent, `comprehensive_bench.rs`, `.bench-history/<primary_bench>.latest.json`, AGENTS.md mandate paragraph.
2. **JAX Oracle fixtures** — per the §16.26 sibling table, "JAX oracle fixtures, Trace Transform Ledger, input/output IR snapshots, transform stack signatures."
3. **Per-primitive metamorphic relations** — JAXPR transformations that should be algebraically equivalent (e.g., `vmap(grad(f))` vs `grad(vmap(f))` for valid orderings).
4. **Per-primitive ULP tolerance table** — similar to FrankenTorch but at the JAXPR level.
5. **E-process invariants** — "rewrite rules are algebraically valid", "AD shortcuts preserve higher-order gradients", "transform cache keys are stable".

**Estimated rounds to convergence (gauntlet-full):** **15-25 rounds.** The transform composition matrix (jit × grad × vmap × pmap × shard_map × ...) creates a combinatorial explosion of behaviors to verify.

**Most likely high-impact finding (one sentence):** A rewrite rule in the JAXPR optimizer is algebraically valid but numerically incorrect — passes a single-transform metamorphic test but fails under `grad(jit(...))` composition.

**Wall time (T3+ × gauntlet-full):** 21-45 days. **rch-offload recommended.**

---

## FrankenNumPy — `/dp/franken_numpy`

**Reference:** Live NumPy + `numpy.__all__`.

**Tier:** **T3** (Workspace) with **numerical determinism** overlay.
**Recommended mode:** `gauntlet-full` for completing the partial adoption; `incremental-rebase` for routine.

**Pillar likely to need most work:** **Performance.** Conformance and surface are well-managed (`numpy.__all__` structural-gate parity, tensor bundles, dtype/shape manifests, RNG-stream fixtures, DIVERGENCES ledger). The performance pillar is "partial" per the matrix — has bit-exact RNG but not the full §75–76 toolkit applied to ufunc dispatch, no `comprehensive_bench`-equivalent with six weighted categories, benches present but unweighted.

**Project-class-specific patterns to lift first:**
1. **Lift FrankenSQLite's `comprehensive_bench` template** — per MINING-1 §8 / CC.md §99 next action. Six weighted categories adapted: `UfuncDispatch 0.30 / Reductions 0.20 / ShapeTransforms 0.15 / Linalg 0.15 / RNGDistributions 0.10 / IOFormats 0.10` (proposal weights; revise after baseline).
2. **Explicit metamorphic relation catalog** — per-ufunc: `ExactBitEqual` for integer ops, `UlpToleranceEqual { n_ulps }` for float ops, `BroadcastEquivalent` for shape transforms.
3. **§75–76 toolkit selectively applied** — Beta-Binomial for ufunc pass rates, e-process for `numpy.testing` invariant monitoring, BOCPD for performance regime tracking.
4. **Cross-reference G1-G8 to FrankenSQLite Phase-1..Phase-9 plan** — each G-level (Group 1..8 in NumPy's plan) maps to a Phase deliverable.

**Estimated rounds to convergence (gauntlet-full):** **8-12 rounds.** Existing DIVERGENCES ledger and bit-exact RNG give a strong starting baseline; rounds 1-5 add structure, rounds 6-12 converge on remaining gaps.

**Most likely high-impact finding (one sentence):** A ufunc's SIMD vectorization path changes the IEEE 754 NaN propagation order vs. the scalar path, surfacing as a metamorphic-relation failure under `UlpToleranceEqual { n_ulps=2 }` for transcendental functions.

**Wall time (T3 × gauntlet-full):** 14-28 days. **rch-offload recommended** for full bench matrix.

---

## FrankenPandas — `/dp/frankenpandas`

**Reference:** Live pandas.

**Tier:** **T3** (Workspace).
**Recommended mode:** `gauntlet-full` (first proper application).

**Pillar likely to need most work:** **Conformance + Surface.** Has "1,252 packets" of conformance evidence per SIBLING-PROJECTS-STATUS.md but no formal FeatureUniverse, no central ledger. Discipline is missing.

**Project-class-specific patterns to lift first:**
1. Full FrankenSQLite floor.
2. **Per-API metamorphic relations** — DataFrame operations: `df.groupby('x').sum() ≡ df.assign(g=...).groupby('g').sum().reset_index()` for sound rewrites.
3. **NaN-handling-specific MismatchClassification** — pandas has 3+ NaN sentinels (`np.nan`, `pd.NA`, `None` in object dtype); the MismatchClassification must distinguish.
4. **Columnar storage golden artifacts** at Tier 1 (byte) AND Tier 2 (canonical-after-VACUUM-equivalent) — Arrow vs NumPy backing arrays differ at byte level but agree at logical.
5. **IO format roundtrip fixtures** — Parquet, CSV, Excel, HDF5 — per format, capture Tier 1/2/3 golden.

**Estimated rounds to convergence (gauntlet-full):** **10-14 rounds.** Wide surface but conformance evidence is already gathered.

**Most likely high-impact finding (one sentence):** A `groupby` operation that produces multi-index columns where the level ordering differs from pandas in the rare case of mixed-dtype keys — passes `MultisetEquivalence` but fails `ExactRowMatch`.

**Wall time (T3 × gauntlet-full):** 14-28 days.

---

## FrankenSciPy — `/dp/frankenscipy`

**Reference:** Live SciPy + tolerance policy.

**Tier:** **T3** (Workspace) with **numerical determinism** overlay.
**Recommended mode:** `gauntlet-full` (first proper application).

**Pillar likely to need most work:** **Conformance.** "767 files" of evidence per matrix; CASP solver-policy is the math-layer foothold but otherwise the discipline is unbuilt.

**Project-class-specific patterns to lift first:**
1. Full FrankenSQLite floor.
2. **Per-solver portfolio attribution** — per CODEX.md §16.26 sibling-projects table: "Solver portfolios by condition/sparsity, FFT sizes, optimization problems, distributions".
3. **Tolerance policy as docs/contracts** — explicit `ulp_tolerance_v1.toml` AND `solver_tolerance_policy.toml`.
4. **Metamorphic for solver selection** — same problem solved by alternate solvers should agree within declared tolerance.
5. **Per-domain golden artifacts** — linalg (one fixture set per condition number), sparse (one per sparsity pattern), optimization (one per problem class), integrate, distributions.

**Estimated rounds to convergence (gauntlet-full):** **10-16 rounds.** CASP solver story gives a partial baseline; wide domain surface requires many rounds.

**Most likely high-impact finding (one sentence):** A solver-selection threshold (e.g., condition number boundary between iterative and direct solver) was tuned for SciPy's specific stopping criteria, and the Rust port's choice differs at exactly the workload class that benchmarks measure most.

**Wall time (T3 × gauntlet-full):** 14-28 days.

---

## FrankenNetworkX — `/dp/franken_networkx`

**Reference:** NetworkX 3.x as behavioral oracle.

**Tier:** **T3** (Workspace).
**Recommended mode:** `gauntlet-full` (first proper application).

**Pillar likely to need most work:** **Conformance + Performance.** Conformance via backend-protocol parity exists implicitly; performance discipline is absent (matrix shows ❌ across the row).

**Project-class-specific patterns to lift first:**
1. Full FrankenSQLite floor.
2. **Algorithm-family weighted benches** — `BFS_DFS 0.15 / ShortestPaths 0.20 / Centrality 0.20 / Components 0.10 / PageRank 0.15 / MST 0.10 / Other 0.10`.
3. **Iteration-order golden artifacts** — graph algorithms with tied edges (e.g., BFS from a node with equal-weight neighbors) require explicit tie-breaking; capture as Tier 3 logical (the iteration order IS the contract for downstream callers).
4. **Parallel-traversal metamorphic** — single-threaded vs parallel BFS should produce identical reachable set + identical depth labels.
5. **Serialization roundtrip fixtures** — every graph fixture must roundtrip through serialize → deserialize → re-execute → identical result.

**Estimated rounds to convergence (gauntlet-full):** **10-14 rounds.**

**Most likely high-impact finding (one sentence):** A parallel BFS implementation has a tie-breaking rule that differs from NetworkX's deterministic order, surfacing as a per-fixture divergence whose root cause is the parallelism strategy, not the algorithm.

**Wall time (T3 × gauntlet-full):** 14-28 days.

---

## FastAPI Rust — `/dp/fastapi_rust`

**Reference:** FastAPI / Pydantic / OpenAPI behavior.

**Tier:** **T3** (Workspace).
**Recommended mode:** `gauntlet-full` (first proper application).

**Pillar likely to need most work:** **All three.** Matrix shows ❌ on Conformance, ❌ on Ledger, ❌ on Math layer. Cass + Agent Mail + bv ⚠️ partial.

**Project-class-specific patterns to lift first:**
1. Full FrankenSQLite floor (adapted for HTTP-Protocol class).
2. **HTTP transcript fixtures** per route — request → response with full headers, status, body — Tier 1 byte where deterministic, Tier 2 canonical where headers like `Date` differ, Tier 3 logical for body content.
3. **Validation-error JSON golden files** — Pydantic v2 vs v1 differ; pin in the contract.
4. **OpenAPI golden file diff** — generated OpenAPI schema must match per-version baseline.
5. **5 request-lifecycle crash boundaries** — `open / header / body-start / body-end / close / cancellation`.
6. **`RequestFaultMiddleware`** — connection drops mid-body, slow-loris, partial multipart.
7. **Route macro compile-fail tests** — codegen for routes; compile-fail covers macro misuse.

**Estimated rounds to convergence (gauntlet-full):** **8-12 rounds.** HTTP protocol is well-specified; convergence is faster than the numerical-class siblings.

**Most likely high-impact finding (one sentence):** A custom-extractor's lifetime annotation differs subtly between async and sync handler paths, surfacing as a runtime panic in a rarely-exercised middleware-stack ordering.

**Wall time (T3 × gauntlet-full):** 10-21 days.

---

## FastMCP Rust — `/dp/fastmcp_rust`

**Reference:** MCP protocol spec + Python FastMCP.

**Tier:** **T3** (Workspace) with **protocol versioning** overlay.
**Recommended mode:** `gauntlet-full` (first proper application).

**Pillar likely to need most work:** **All three** (same as FastAPI Rust). Matrix shows ❌/⚠️ across the row.

**Project-class-specific patterns to lift first:**
1. Full FrankenSQLite floor.
2. **MCP transcript fixtures** — JSON-RPC request/response transcripts per tool/resource/prompt; Tier 1/2/3.
3. **Four-valued outcome classification tests** — MCP outcomes are not just success/failure; they're (success, partial, error, cancelled). Each requires explicit test coverage.
4. **Cancellation scenarios** — cancellation-budget enforcement; resource-streaming mid-cancel; tool-invocation mid-cancel.
5. **Macro expansion oracle** — codegen for `#[tool]` macros; expansion result must match per-version baseline.
6. **Schema generation caching** — JSON schema for tool inputs/outputs; cache key must include version + macro hash.
7. **Capability security tests** — tool-invocation permissions; resource-read permissions; per-client capability negotiation.

**Estimated rounds to convergence (gauntlet-full):** **10-14 rounds.** Cancellation correctness + four-valued outcomes are deep wells of bugs.

**Most likely high-impact finding (one sentence):** A `#[tool]` macro generates schema that omits an optional parameter's null-vs-absent distinction, surfacing as a client-side validation error that the protocol spec considers legal but the macro forbids.

**Wall time (T3 × gauntlet-full):** 14-21 days.

---

## SQLModel Rust — `/dp/sqlmodel_rust`

**Reference:** Python SQLModel / SQLAlchemy.

**Tier:** **T3** (Workspace) with **compile-time codegen** overlay.
**Recommended mode:** `gauntlet-full` (first proper application).

**Pillar likely to need most work:** **All three.** Matrix shows ❌ across the row.

**Project-class-specific patterns to lift first:**
1. Full FrankenSQLite floor.
2. **Derive-macro model schema oracle** — for each `#[derive(SQLModel)]` input, the generated SQL DDL must match per-dialect baseline.
3. **Query-builder golden files** — for each query pattern (filter, join, order_by, group_by), capture the rendered SQL per dialect.
4. **Dialect-specific golden** — Postgres, MySQL, SQLite each have differing SQL renderings; capture per dialect.
5. **Schema-migration snapshots** — Alembic-equivalent migration generation; per-version baseline.
6. **Model-derive compile-fail tests** — macro misuse must compile-fail with deterministic error message.
7. **DB-roundtrip fixtures** — each model → insert → select → assert-equal.

**Estimated rounds to convergence (gauntlet-full):** **10-14 rounds.** Codegen + dialect-variance + ORM semantics create many edges.

**Most likely high-impact finding (one sentence):** A relationship-loading optimization (lazy vs eager) differs in transaction-boundary semantics between the Rust port and SQLAlchemy, surfacing as a subtle `N+1 query` issue that the conformance harness catches but the perf harness doesn't.

**Wall time (T3 × gauntlet-full):** 14-21 days.

---

## franken_whisper — `/dp/franken_whisper`

**Reference:** OpenAI Whisper (Python reference implementation).

**Tier:** **T3** (Workspace) with **numerical determinism** overlay — ML-System-class shaped as CLI surface.
**Recommended mode:** `gauntlet-full` (first proper application).

**Pillar likely to need most work:** **Conformance.** ASR is fundamentally lossy and tolerance-bound; the discipline of per-op ULP + per-output WER tolerance is the central engineering challenge.

**Project-class-specific patterns to lift first:**
1. Full FrankenSQLite floor (adapted for ML-System-class).
2. **Per-op ULP tolerance table** — Mel-spectrogram, attention, layer-norm each have per-op ULP budgets.
3. **Per-output WER tolerance** — Word Error Rate between port output and reference output must be below a declared threshold per audio class.
4. **Audio-fixture corpus** — per language × per accent × per noise-condition; Tier 3 (logical = WER ≤ ε); Tier 2 (canonical = identical token IDs); Tier 1 (byte = identical waveform pre-processing).
5. **5 checkpoint-save crash boundaries** (model state during fine-tune); 2 distributed-collective (if distributed inference).
6. **E-process invariants** — "softmax outputs over vocab sum to 1.0 within ε", "attention scores within (-∞, 0]", "beam search keeps top-K monotonically".

**Estimated rounds to convergence (gauntlet-full):** **10-15 rounds.** Audio variance + numerical drift + tokenization edge cases conspire.

**Most likely high-impact finding (one sentence):** The Rust port's tokenizer differs from Whisper's BPE for non-Latin scripts in a way that doesn't show up in the high-resource English benchmark but adds 2-3% absolute WER for low-resource languages.

**Wall time (T3 × gauntlet-full):** 14-28 days.

---

## Decision flow

```
Pick a sibling → look up its row in [exemplars/SIBLING-PROJECTS-STATUS.md] (current adoption state)
                  ↓
Look up its case study (above) → tier + mode + likely pillar + first patterns
                  ↓
Cross-reference TIER-TRIAGE.md → required patterns / subagents / wall time
                  ↓
Dispatch via the appropriate kickoff prompt from KICKOFF-PROMPTS.md
```

---

## Common scoping mistakes (across siblings)

- **Treating ML-System siblings as Numerical-Python siblings.** Per-op ULP tolerances are NOT the same as `numpy.testing.assert_array_almost_equal` defaults; ML-System needs explicit per-op + per-shape calibration.
- **Treating HTTP-Protocol siblings as code-only ports.** The protocol IS the contract; transcript fixtures are the source of truth. Skip them and the conformance pillar is hollow.
- **Skipping the AGENTS.md mandate paragraph because the sibling has "implicit" ledger discipline.** Implicit is not durable; the next contributor doesn't have the same context.
- **Picking the wrong tier for compile-time-codegen siblings.** SQLModel Rust + FastMCP Rust look small but have macro-expansion surfaces that effectively bump them to T4 for those features.
- **Skipping the cross-sibling consistency check at T5.** If multiple numerical-class siblings are being gauntleted, their per-op ULP tolerance tables should AGREE where they cover the same primitive — divergence between sibling per-op tables is itself a finding.

---

## Family roll-up (T5)

If the user dispatches `gauntlet-full` against the *entire* numerical-class family (franken_numpy + franken_scipy + frankenpandas + frankentorch + frankenjax in lockstep), apply the family-orchestrator pattern from [TIER-TRIAGE.md § T5](TIER-TRIAGE.md):

1. Per-port gauntlet runs in parallel via NTM.
2. Shared `family_feature_universe.toml` consolidates per-port FeatureUniverses with cross-references.
3. Cross-port consistency operator `⛬` (see TIER-TRIAGE.md) flags Features that appear in ≥2 ports with disagreeing statuses.
4. Per-port certification bundles + family-level `FAMILY_RELEASE_CERTIFICATION.md`.
5. Months of wall time at minimum; multi-month for a thorough family roll-up.

---

## See also

- [exemplars/SIBLING-PROJECTS-STATUS.md](../exemplars/SIBLING-PROJECTS-STATUS.md) — current adoption truth (do not duplicate it here; this case-studies file is *prospective*).
- [TIER-TRIAGE.md](TIER-TRIAGE.md) — tier definitions.
- [MODE-ROUTER.md](MODE-ROUTER.md) — mode definitions.
- [taxonomy/PROJECT-CLASSES.md](../taxonomy/PROJECT-CLASSES.md) — per-class oracle wiring + crash-boundary enumeration + failure terms.
