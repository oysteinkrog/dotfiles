# Pattern 115 — Closure Wave

## What

For each pipeline stage of the subject (parser, resolver, planner, pragma handler, VDBE, B-tree, WAL, ...), first *enumerate the universe of expected behaviors* and *only then* test each behavior against both the reference and the subject. The output is a `ClosureCase` per behavior with an evaluation against both engines; the report is a per-stage coverage matrix that lights up holes the way a heatmap lights up missing coordinates. You do not write tests for what you remember; you enumerate the universe, then observe which the engine handles.

## Why

> "You don't write tests for what you remember to write tests for; you enumerate the universe of behaviors, *then* observe which the engine handles." — MINING-3 §12

Failure mode prevented: ad-hoc test growth where coverage accretes around the bugs the author already fixed, leaving the un-thought-of behaviors permanently uncovered. The closure-wave inverts the order: enumeration first, evaluation second. A behavior that hasn't been thought of yet is missing from the enumeration, not silently absent from the test suite.

## Where in FrankenSQLite

- `crates/fsqlite-harness/src/closure_wave.rs` — the `ClosureCase` struct, the per-stage closure-wave runners, the coverage report.
- Per-stage enumerations live under `crates/fsqlite-harness/src/closure/` (parser, resolver, pragma).
- Coverage dashboards: `tests/artifacts/closure/{stage}_coverage.json`.

## Verbatim shape

```rust
pub struct ClosureCase {
    pub stage: PipelineStage,           // Parser | Resolver | Pragma | ...
    pub behavior_id: String,            // e.g., "parser.cte.recursive.with-aggregate"
    pub source_construct: String,       // the input fragment
    pub expected_class: BehaviorClass,  // Accept | Reject(category) | AcceptWith(warning)
    pub reference_result: EngineResult,
    pub subject_result: EngineResult,
    pub closure_status: ClosureStatus,  // Closed | Open | Gapped | Excluded
}
```

### The four-step protocol

1. **Enumerate** — for a given pipeline stage, write down every behavior the stage could exhibit. Sources: reference test corpus, grammar productions, opcode lists, command catalog, public-API symbol list.
2. **Encode** — each enumerated behavior becomes a `ClosureCase` with `expected_class` defined a priori.
3. **Evaluate** — run both reference and subject; record `reference_result` and `subject_result`.
4. **Classify** — `Closed` (both agree per expected_class), `Open` (subject diverges), `Gapped` (subject doesn't implement at all), `Excluded` (per SurfaceMatrix).

The wave name comes from the gap-closure dynamic: each pass over the enumeration "closes" some open cases by implementing them; the next pass enumerates more behaviors (the universe expands with reference releases); the cycle repeats.

## Per-class instantiation

| Class | Pipeline stages to enumerate |
|---|---|
| SQL | `Tokenizer`, `Parser`, `Resolver`, `Planner`, `PragmaHandler`, `VdbeAssembler`, `Vdbe`, `BtreeOps`, `WalProtocol`, `MvccValidator`, `FunctionDispatch`, `TypeCoercion`, `RecoveryReplay` |
| RESP | `Tokenizer` (RESP2/RESP3 framing), `Decoder` (type tags), `CommandDispatch`, `ScriptCompiler` (Lua), `AofWriter`, `RdbSerializer`, `ReplicationOffsetTracker`, `PubSubFanout`, `ClusterSlotResolver` |
| Numerical-Python | `DtypePromotion`, `BroadcastShape`, `UfuncDispatch`, `ReductionLoop`, `LinalgRouter`, `RngStreamStateMachine`, `IoCodec` |
| ML-System (JAX-flavored) | `TracerConstruct`, `PrimitiveDispatch`, `JaxprEmit`, `JitCompile`, `XlaHloPass`, `PjitPartition`, `VmapUnroll`, `GradJvpVjp` |
| ML-System (Torch-flavored) | `AtenDispatch`, `AutogradTapeAppend`, `JitCacheLookup`, `KernelLaunch`, `NcclCollective`, `StreamSync` |
| HTTP-Protocol | `RouteMatch`, `ExtractorBind`, `ValidationRules`, `MiddlewareTraverse`, `OpenApiEmit`, `Cancellation`, `WebSocketUpgrade`, `StreamingBody` |

A stage's enumeration is itself a versioned artifact (`closure/{stage}_universe.toml`) so additions are bead-tracked.

### Worked example — SQL Parser stage

```
behavior_id: parser.cte.recursive.with-aggregate
source_construct: "WITH RECURSIVE t(n) AS (SELECT 1 UNION ALL SELECT n+1 FROM t LIMIT 5) SELECT sum(n) FROM t"
expected_class: Accept
reference_result: ok(...)
subject_result: ok(...)
closure_status: Closed

behavior_id: parser.cte.recursive.cross-cte
source_construct: "WITH RECURSIVE a AS (...), b AS (SELECT * FROM a JOIN ...) SELECT ..."
expected_class: Accept
reference_result: ok(...)
subject_result: err(unsupported)
closure_status: Open
```

The closure report names the second case as a *currently-open gap* against the parser stage; the coverage dashboard rolls open cases into per-stage "gap budget" metrics.

## Composition

- [pattern:105-FEATURE-UNIVERSE](105-FEATURE-UNIVERSE.md) — each enumerated behavior either is a `Feature` directly or rolls up to one. Closure-wave is the *bottom-up enumeration mechanism*; FeatureUniverse is the *top-down score-rollup mechanism*.
- [pattern:110-INVARIANT-CATALOG](110-INVARIANT-CATALOG.md) — `ClosureCase` evaluations become `ProofObligation` evidence (`OracleDifferential` kind) for the parent Feature's invariants.
- [pattern:40-METAMORPHIC-TRANSFORMS](40-METAMORPHIC-TRANSFORMS.md) — for each closed case, apply the 4 transform families and check `EquivalenceExpectation`; closes derived cases without manual enumeration of every rewrite.
- [pattern:115-CLOSURE-WAVE](115-CLOSURE-WAVE.md) (self) — the wave runs *per stage in parallel*; coordination is by [orchestration/ORCHESTRATION.md § subagent lane assignment](../orchestration/ORCHESTRATION.md), one subagent per stage.
- [pattern:120-VERIFICATION-CONTRACT](120-VERIFICATION-CONTRACT.md) — bead-close gate consults the per-stage open-gap count; a bead that *adds* a stage opens gaps until they close.

## Pitfalls

- **Enumerating only behaviors the subject already handles** — defeats the wave. The enumeration is sourced from the reference's grammar / opcode list / command catalog, not from the subject's existing tests.
- **Letting `Excluded` close gaps silently** — an enumeration of 100 behaviors with 40 `Excluded` is debt against the strict-100% claim. The dashboard must report `Closed`, `Open`, `Gapped`, `Excluded` separately.
- **Re-enumerating per-test rather than per-stage** — duplicates work and produces inconsistent universes. Each stage has *one* `_universe.toml`.
- **Treating the wave as a one-shot** — closure is iterative; the reference changes (SQLite 3.52 → 3.53), the universe expands, gaps reappear. Schedule a wave run per release of the reference.
- **Confusing "no test failure" with `Closed`** — `Closed` means: behavior enumerated, expected_class declared a priori, both engines evaluated, results match expected_class. A behavior with no expected_class but two engines that both return `ok(...)` is not `Closed`; it is undefined.
- **Skipping `Gapped` reporting because "we know we don't implement that yet"** — the metric is exactly what you want visible. Gapped cases are the road map; deleting them deletes the road map.
- **Coupling enumeration files to crate source** — the enumeration lives under `crates/{c}-harness/src/closure/{stage}_universe.toml` and is versioned, surveyed across `cargo doc`, and queryable; not inlined in test files.
