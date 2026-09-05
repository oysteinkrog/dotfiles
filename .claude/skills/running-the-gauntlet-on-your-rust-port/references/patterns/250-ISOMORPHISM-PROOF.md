# pattern:250-ISOMORPHISM-PROOF

## What

Every behavior-preserving change (every Pattern 1-10 instance, every refactor, every "while we're here" cleanup) must ship with a **5-line isomorphism proof** in the commit message / PR description / bead body. The proof names the change, asserts ordering preservation, asserts tie-break determinism, asserts floating-point bit-for-bit equality (or names the per-op ULP tolerance), asserts RNG-seed reproducibility, and points at the golden output that confirms it. The proof is *load-bearing* because behavior-changing optimizations dressed as behavior-preserving optimizations are the most expensive class of regression.

## What this skill provides

A canonical 5-line template that drops cleanly into any commit; an enum of `ProofInvariantClass` variants per project class; a cross-link to the longer `ISOMORPHISM-PROOF-TEMPLATE.md` reference.

## Why

> "Change behavior 'while we're here' — Breaks isomorphism guarantee" — anti-pattern catalog, CC.md §87.4 (MINING-1 §9)

> "Behavior-preserving — The candidate doesn't change observable behavior (verified by oracle tests, selection counts, bench-level row equality). Required prerequisite for any rejection-by-perf — a behavior-changing candidate is a different question entirely." — MINING-1 §1

Failure mode prevented: *the optimization that's secretly a feature change*. When an agent claims "behavior-preserving" without proof, the next agent (or the next release) inherits a divergence that nobody can attribute. Worse, the divergence may pass the differential tests *for the inputs the test suite happens to cover* and fail silently for the rest of the input space. The proof template forces the author to enumerate the dimensions along which preservation must hold and to name the artifact that confirms each.

## Where in FrankenSQLite

- Cross-link to the longer reference: [../remediation/ISOMORPHISM-PROOF-TEMPLATE.md](../remediation/ISOMORPHISM-PROOF-TEMPLATE.md)
- Cited in the 10 winning patterns: every kept optimization in `crates/fsqlite-vdbe/` and `crates/fsqlite-btree/` has the proof in the commit body
- The `selections= byte-identical` rule in the keep-gate vocabulary (CC.md §37) is one specific form of the proof

## Verbatim shape — the 5-line proof template

```
Isomorphism proof:
  Change:           <one-line description of the rewrite>
  Ordering:         <preserved | not-applicable> via <evidence>
  Tie-breaking:     <unchanged | tightened-with-test> via <evidence>
  Floating-point:   <bit-identical | within <N>-ULP per-op tolerance> via <evidence>
  RNG seeds:        <reproducible from <seed-source> | not-applicable> via <evidence>
  Golden outputs:   <unchanged> at <fixture-id> SHA-256 <hash>
```

Real example (style approximated from the prepared-cache key separation):

```
Isomorphism proof:
  Change:           Separate bytecode-cache key (schema-bound) from data-cache key (generation-bound).
  Ordering:         preserved — bytecode emission is schema-deterministic; data-cache iteration order unchanged.
  Tie-breaking:     unchanged — bytecode comparator on (SqlText, SchemaHash) is total; no new ambiguity.
  Floating-point:   not-applicable — no float ops introduced.
  RNG seeds:        not-applicable.
  Golden outputs:   unchanged at fixtures/sql/oltp_read_write_001 SHA-256 abc123…
```

## `ProofInvariantClass` enum

The minimal closed-world enumeration of preservation classes the author must consider. For SQL:

```rust
pub enum ProofInvariantClass {
    RowOrdering,                  // ORDER BY semantics; UNORDERED → row-multiset
    TieBreak,                     // ORDER BY ties resolved deterministically
    FloatingPointPrecision,       // exact IEEE-754 vs per-op ULP
    RngDeterminism,               // RANDOM(), HEX(RANDOMBLOB(N))
    GoldenChecksum,               // VACUUM INTO Tier-2 byte-identical
    TypeAffinity,                 // SQLite type affinity rules
    NullPropagation,              // three-valued logic edges
    ErrorCodes,                   // both-error agreement at category level
    AggregateSemantics,           // SUM/AVG/MIN/MAX edge cases
    WindowFunctionSemantics,      // ROWS/RANGE/GROUPS frame edges
}
```

## Per-class instantiation

| Class | `ProofInvariantClass` variants (additional or substituted) |
|---|---|
| **SQL** | RowOrdering, TieBreak, FloatingPointPrecision, RngDeterminism, GoldenChecksum, TypeAffinity, NullPropagation, ErrorCodes, AggregateSemantics, WindowFunctionSemantics |
| **RESP** | RespFrameByteIdentity, CollectionSemantics (set/list/hash/zset/stream-XADD-id), PubsubFifo, ExpirationDeterminism, AofReplayIdentity, RdbChecksum, ClusterSlotMapping, ErrorCategoryMatch |
| **Numerical** | ShapeBroadcast, DtypePromotion, ViewVsCopySemantics, NanPropagation, PCG64DXSMStreamIdentity, AxisOrderPreservation, BlasUlpTolerance, UfuncDispatchOrder, ContiguousVsStridedIteration |
| **ML** | AutogradTapeOrder, GradientNumeric (per-op ULP table), DeterministicAlgorithmFlag, RngStateCheckpointReproducibility, BatchOrderingPreservation, DistributedAllReduceCommutativity, MixedPrecisionRounding, NondeterministicOpFlag |
| **HTTP** | StatusCodeMatch, HeaderCaseInsensitiveEquality, BodyMimeAwareEquality, RoutingDispatchDeterminism, MiddlewareTraversalOrder, ValidationErrorCategory, OpenApiSchemaShape, CookieJarSerialization |

The author picks the variants relevant to the change and emits one proof line per relevant variant. Variants not mentioned are implicitly asserted as "not affected" — but the author must be able to defend that on demand.

## Composition

- Pairs with every Pattern 200-245 — each of the 10 winning patterns is behavior-preserving by construction; the proof template is the artifact that *proves* it.
- Pairs with [pattern:30-DIFFERENTIAL-V2-ENVELOPE](30-DIFFERENTIAL-V2-ENVELOPE.md) — the golden-output line of the proof points at a Differential V2 envelope's `artifact_id`.
- Pairs with [pattern:50-THREE-TIER-EQUIVALENCE](50-THREE-TIER-EQUIVALENCE.md) — the proof must name the equivalence tier (1 byte / 2 canonical / 3 logical) used as evidence.
- Pairs with [pattern:165-PASS-OVER-PASS-GATE](165-PASS-OVER-PASS-GATE.md) — the proof is half; the same-run-window measurement is the other half. A perf change without the proof OR without the measurement is incomplete.
- Cross-link: [../remediation/ISOMORPHISM-PROOF-TEMPLATE.md](../remediation/ISOMORPHISM-PROOF-TEMPLATE.md) for the longer-form template and rubric.

## Pitfalls

- **Proof present but empty.** "Ordering: preserved" without evidence is just an assertion. The `via <evidence>` clause is mandatory; "via oracle suite green on commit abc123" is the minimum.
- **Skipping variants by claiming irrelevance without thought.** "Floating-point: not-applicable" on a change that touches numeric coercion is a tell that the author didn't audit; in numeric ports, the variant should be considered for almost every change.
- **Golden-output reference that's a directory, not a hash.** The point is *content addressing*; a directory mtime can drift without the agent noticing.
- **Per-class trap (ML): claiming bit-identical when only the `torch.use_deterministic_algorithms(True)` path is bit-identical and the production path uses non-deterministic kernels.** The proof must distinguish.
- **Per-class trap (RESP): proof omits "RESP version" — RESP2 vs RESP3 frame encoding differs.** The proof must name the version.
- **Per-class trap (Numerical): RNG-stream identity asserted without naming PCG64DXSM advancement count.** NumPy 1.17+ uses PCG64DXSM and the stream is sensitive to advance count.
- **Treating the proof as a commit-message ritual.** The proof is *evidence*; if a reviewer cannot run the cited fixture and get the cited hash, the proof is dead.
- **Author skipping the proof because "it's obvious."** Anti-pattern by definition: if it's obvious the future agent will see it's obvious and not re-derive; the proof is for the agent who *doesn't* yet see it.
