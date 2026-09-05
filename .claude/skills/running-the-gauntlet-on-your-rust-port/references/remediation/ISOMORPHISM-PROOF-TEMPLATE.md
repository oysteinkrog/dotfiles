# Isomorphism Proof Template

> Glyph: `⊕` **Isomorphic-Rewrite** — paired with this proof obligation. Every behavior-preserving rewrite carries a 5-line proof that anchors it to the `ProofInvariantClass` taxonomy.

The premise: "behavior-preserving" is not a feeling. It's a finite check against named invariants. If your change changes the ordering, the tie-break, the floating-point precision, the RNG consumption, or the golden-output byte layout, it is *not* an isomorphic rewrite — it's a behavior change, and it routes to conformance review, not perf review.

The 5-line proof is the minimum. For complex changes, expand each line into a paragraph; for trivial ones, the 5 lines suffice.

---

## ProofInvariantClass Taxonomy

Defined in `crates/fsqlite-harness/src/isomorphism_proof.rs`. Each class names a property the proof must address.

### Universal (apply to all project classes)

| Class | What it asserts |
|---|---|
| `RowOrdering` | The order of returned rows / records / items is preserved (or relaxed to MultisetEquivalence with explicit justification). |
| `TieBreak` | Where the spec says "if two elements compare equal, use X to break the tie", the rewrite preserves X. |
| `FloatingPointPrecision` | The rewrite produces bit-exact (`f64` IEEE-754) outputs or names a tolerance in ULPs. |
| `RngDeterminism` | The rewrite either does not touch the RNG, or shifts consumption deterministically with a recorded seed. |
| `GoldenChecksum` | The rewrite preserves the byte-identical / canonical-identical / logical-identical contract of every golden artifact it touches. |

### SQL-class extensions

| Class | What it asserts |
|---|---|
| `TypeAffinity` | SQLite's `INTEGER/REAL/TEXT/BLOB/NULL` affinity rules are preserved at storage and retrieval. |
| `NullPropagation` | Three-valued logic (`NULL = NULL → NULL`) is preserved through the rewritten path. |
| `ErrorCodes` | The exact `SQLITE_*` error code (and SQLite extended error code) is preserved. |
| `AggregateSemantics` | `COUNT/SUM/AVG/MIN/MAX` over NULL-containing inputs produce identical results. |
| `WindowFunctionSemantics` | `ROW_NUMBER`/`RANK`/`DENSE_RANK` tie-breaking and partition framing are preserved. |

### RESP-class extensions

| Class | What it asserts |
|---|---|
| `ArrayOrdering` | RESP array element order (e.g., `HGETALL` field/value pairing) is preserved or relaxed to map-iteration order with explicit guard. |
| `SetSemantics` | SREM/SDIFF/SINTER set algebra outputs are byte-equivalent in canonical sorted form. |
| `HashIteration` | Where Redis spec says "hash iteration order is unspecified", the rewrite acknowledges that and tests with reordered fixtures. |
| `ErrorCategory` | RESP error class (`-ERR`, `-WRONGTYPE`, `-NOAUTH`, etc.) is preserved; message text may differ. |

### Numerical-class extensions

| Class | What it asserts |
|---|---|
| `DtypePromotion` | NumPy/pandas dtype promotion table is followed bit-for-bit (e.g., `int32 + float32 → float64`). |
| `BroadcastSemantics` | Broadcasting axis-alignment and shape-promotion match `numpy.broadcast_shapes()`. |
| `AxisOrdering` | Reductions over multi-axis tuples produce values in the same axis-elimination order. |
| `NaNPropagation` | `NaN`/`Inf`/`-Inf` propagation through arithmetic matches reference exactly. |

### ML-class extensions

| Class | What it asserts |
|---|---|
| `GradientChain` | Autograd chain (`backward()` order) produces identical gradient values within per-op ULP tolerance. |
| `DeviceSync` | CUDA/Metal stream sync points are preserved (no missed `synchronize()` that would let async kernels race). |
| `AutogradOrder` | Op-recording order in the autograd tape is preserved. |

### HTTP-class extensions

| Class | What it asserts |
|---|---|
| `HeaderCaseInsensitive` | Header lookups remain case-insensitive; canonical header rendering may differ. |
| `BodyStreaming` | Body-streaming chunk boundaries may differ, but byte-identical concatenation is preserved. |
| `OpenAPISchema` | Generated OpenAPI schema is identical modulo property ordering (and per-property hash is identical). |

---

## The 5-Line Proof Template

Use verbatim. Each line is mandatory — even an "unchanged" line is data.

```
Change: <one-line description of the change>
Ordering preserved: <yes | no | with-caveat: "<caveat>">
Tie-breaking unchanged: <yes | no | with-caveat: "<caveat>">
Floating-point: <bit-exact | ULP=N | tolerant=ε | not-applicable>
RNG seeds: <untouched | deterministic-shift | seeded-rewrite>
Golden outputs: <byte-identical | canonical-identical | logical-identical | not-applicable>
```

### How each line is filled

- **`Change`** — single imperative sentence. "Promote `IsNull` opcode to `try_execute_hot_opcode`". Not "made the code better" or "optimized the hot path".
- **`Ordering preserved`** — `yes` for in-place mutations, `with-caveat` for plan-changing rewrites where MultisetEquivalence is the correct contract. `no` is a hard stop — go to conformance review.
- **`Tie-breaking unchanged`** — for SQL, ORDER BY tie-breaks by ROWID. For sorts on ties, name the tie-breaker. If the rewrite touches a comparator, this is the line that catches the bug.
- **`Floating-point`** — `bit-exact` when the rewrite doesn't touch floats. `ULP=N` when it does and N is the maximum acceptable ULP delta. `tolerant=ε` for numerical-class changes that pass through `numpy.allclose`. `not-applicable` for integer-only paths.
- **`RNG seeds`** — `untouched` if the path doesn't use RNG. `deterministic-shift` if the order of RNG consumption changes but the seed and count are recorded. `seeded-rewrite` if the rewrite explicitly re-seeds. Anything else (e.g., calling `rand::random()`) is a hard stop.
- **`Golden outputs`** — for the three-tier equivalence: `byte-identical` (Tier 1), `canonical-identical` (Tier 2 — same after canonicalization like `VACUUM INTO`), `logical-identical` (Tier 3 — same row counts, columns, values via `==`). `not-applicable` only when no golden artifact exists for this path.

---

## Worked Examples

### Example 1: AccessPath probe move (Pattern 8)

```
Change: Replace `.clone()` on `Box<Probe>` in `order_joins` single-table path with move semantics; refactor `AccessPath::with_probe` to take `Probe` by value.
Ordering preserved: yes (no comparator touched; row ordering by ROWID unchanged).
Tie-breaking unchanged: yes (planner cost-tie-break by AccessPath index unchanged).
Floating-point: not-applicable (probe builder is integer-only).
RNG seeds: untouched.
Golden outputs: byte-identical (`tests/artifacts/snapshots/access_path_explain.snap` regenerated, byte-equal to baseline).
```

**Evidence:**
- Commit `b35e1f9c`, bd-4ndk2.
- `cargo insta review` shows zero changes to `access_path_explain.snap`.
- `selections=` counter byte-identical to baseline; `oltp_cost_estimation_hot_paths` MISS path improved −21.9%.

### Example 2: AtomicBool gate on `PublishedPages::clear()` (Pattern 2)

```
Change: Wrap O(N) shard-iteration in `ConcurrentPublishedPages::clear()` with `has_anything: AtomicBool` gate; early-return when empty.
Ordering preserved: yes (clear() is order-free; semantically idempotent).
Tie-breaking unchanged: yes (no tie-break in this path).
Floating-point: not-applicable (page-ID arithmetic is integer).
RNG seeds: untouched.
Golden outputs: byte-identical (no golden artifact depends on this path; verified via `mt_mvcc_bench` `selections=` counter byte-identical).
```

**Evidence:**
- Empty-overflow microbench `2.92µs → 1 ns ≈ 2922x`; closed 0.44% MT8 PublishedPages::clear residual.
- Subtlety captured in commit message: "Flag is allowed false positive but *never* false negative. Set flag before publishing, clear after sweeping."

### Example 3: Algebraically-redundant counter elimination (Pattern 3)

```
Change: Drop `FSQLITE_SSI_VALIDATIONS_TOTAL` static AtomicU64; compute at snapshot-read time as `commits_total + aborts_total`.
Ordering preserved: yes (counter read is order-free).
Tie-breaking unchanged: yes (no tie-break in counter path).
Floating-point: not-applicable (counters are integer).
RNG seeds: untouched.
Golden outputs: byte-identical for `comprehensive-bench` JSON snapshots (validations_total field still appears, derived at output time).
```

**Evidence:**
- Commit `36504496`. `3.91 → 1.90 ns/call (−51.5%, ~2x)`.
- `mt_mvcc_bench` `selections=` counters and JSON v3 output structurally unchanged; only computational shape changed.

### Example 4: HashSet → sorted Vec on HandleView (Pattern 4)

```
Change: Replace 6× `HashSet<HandleId>` in `HandleView` with sorted `Vec<HandleId>`; replace `.contains()` with `binary_search()`.
Ordering preserved: yes (HandleView semantically returns sorted-handle view; previous HashSet randomness now stable).
Tie-breaking unchanged: yes (handles compared by HandleId; sorted order is canonical).
Floating-point: not-applicable.
RNG seeds: untouched.
Golden outputs: canonical-identical (`tests/artifacts/snapshots/handle_view_dump.snap` previously had no stable order across HashSet iterations; new dump is sorted-by-HandleId; one-time golden refresh required and committed in same change).
```

**Evidence:**
- Commit lands together with golden refresh of `handle_view_dump.snap`.
- `1674.8 → 970.8 ns/build (−42.0%, ~1.7x)`. Insight: `summarize_witness_keys()` already produces sorted Vec.
- Tier 2 canonical-identical OK because previous Tier 1 was already non-deterministic across HashSet hash-seed changes.

### Example 5: Devirtualize `TransactionKind::get_page` (Pattern 6)

```
Change: Replace `&dyn TransactionKind` dispatch for `get_page` and `write_page_data` with enum-match against `enum TransactionKindDispatcher { Direct, Wal, Mvcc }`.
Ordering preserved: yes (dispatcher choice does not affect output order).
Tie-breaking unchanged: yes (no comparator in dispatch path).
Floating-point: not-applicable (page I/O is integer + bytes).
RNG seeds: untouched.
Golden outputs: byte-identical (page-image roundtrip Tier 1 unchanged; verified by `cargo test --test page_roundtrip_golden`).
```

**Evidence:**
- Commit `0375b55e`. Closed 0.36% + 0.29% MT8 self-time entries.
- MEMORY.md note: "Other `TransactionKind` methods stay on the closure helpers — cold or shape-uniform." (Discipline: devirtualize the hot frames only.)

---

## When a Line Forces a Hard Stop

- **`Ordering preserved: no`** — the rewrite changes output order. Either change EquivalenceExpectation to `MultisetEquivalence` (with metamorphic re-verification) or revert. Never silently change ORDER BY semantics.
- **`Tie-breaking unchanged: no`** — the rewrite changes tie-break behavior. SQL clients may depend on tie-break order; this is a behavior change. Conformance review required; goes to `CONF_HYPOTHESIS_LEDGER.md` not perf.
- **`Floating-point: ULP=N` for N>4 (f32) or N>1 (f64)`** — non-trivial precision change. Requires `🎚 Raise-ULP-Tolerance` operator and per-op tolerance table update.
- **`RNG seeds: seeded-rewrite`** — every seeded rewrite needs a fixture-corpus regeneration. `SeedContract::derive_entry_seed` must produce identical seeds for identical inputs.
- **`Golden outputs: logical-identical`** for what was previously `byte-identical`** — a golden-tier downgrade. Requires explicit ledger entry explaining why Tier 1 is no longer attainable.

---

## How to Wire Into Commits

1. Include the 5-line proof as a markdown block in the commit body, immediately after the one-line summary.
2. CI's `isomorphism_proof_validator` greps for the 5 mandatory lines in every perf-bead commit; missing lines = commit fails the gate.
3. The proof is also stored as `tests/artifacts/perf/<bead-id>/isomorphism_proof.txt` for offline audit.

Example commit message:

```
perf(vdbe): promote IsNull opcode into try_execute_hot_opcode

Change: Pre-match IsNull alongside SCopy/IfNot in try_execute_hot_opcode.
Ordering preserved: yes (opcode dispatch is order-free; row ordering by VDBE program unchanged).
Tie-breaking unchanged: yes (no comparator touched).
Floating-point: not-applicable (IsNull is type-test, integer result).
RNG seeds: untouched.
Golden outputs: byte-identical (VDBE explain snapshots unchanged).

MT8 throughput +27.5% / +27.2%; closed 0.51% MT8 IsNull self-time.
Both gates moved in same run window:
  - mt-mvcc-bench.latest.json: 5458 → 6951 ops/sec
  - comprehensive_bench.latest.json: primary_score 0.3792 → 0.4151

Refs: PERF-0001
```

See also: [REMEDIATION-PATTERNS.md](REMEDIATION-PATTERNS.md), [../methodology/KEEP-GATE-RULES.md](../methodology/KEEP-GATE-RULES.md), [../taxonomy/PROJECT-CLASSES.md](../taxonomy/PROJECT-CLASSES.md).
