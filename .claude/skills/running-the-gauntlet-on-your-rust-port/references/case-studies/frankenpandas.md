# Case Study: FrankenPandas — `/dp/frankenpandas`

The widest IO-surface in the family (Parquet, CSV, Excel, HDF5, JSON, Arrow, Feather, ORC, SQL, Stata, SAS, SPSS, HTML, XML) and the most NaN-sentinel ambiguity (`np.nan`, `pd.NA`, `None` in object dtype). Has "1,252 packets" of conformance evidence but no ledger and no formal FeatureUniverse.

---

## 1. Snapshot

| Field | Value |
|---|---|
| **Class** | Numerical-Python-class with IO-format overlay ([PROJECT-CLASSES.md § Numerical-Python-Class](../taxonomy/PROJECT-CLASSES.md)) |
| **Tier** | **T4 — Platform** (the 14+ IO formats overlay bumps from T3) |
| **Recommended mode** | `gauntlet-full` (first proper application) |
| **Reference pinning** | `docs/contracts/pandas_version_contract.toml` (likely `pandas-2.2.x`); preflight verifies `pd.__version__`, `pd.show_versions()` for backing-store consistency |
| **README claims summary** | DataFrame/Series/Index API parity vs pandas 2.x; IO roundtrip byte-equal where possible. Recent activity (commits `57a9122e`, `ca2c2344`, `fbb8c7ae`) shows kurtosis-alias additions + phase-2c evidence refresh — per-method coverage in active expansion. |

---

## 2. Adoption Matrix

| Pillar / Discipline | Status | Notes |
|---|:---:|---|
| Conformance | ⚠️ "1,252 packets" | bundles of test cases — **not the differential-V2 envelope pattern** |
| Negative ledger | ❌ | absent |
| cass | ⚠️ partial | |
| Agent Mail | ⚠️ partial | |
| bv | ⚠️ partial | |
| Math layer (§75–76) | ❌ | absent |
| MT-scale harness | ❌ | absent |
| RaptorQ | ❌ | not applicable |
| `DataFrameSpec` normalized comparator | ❌ | string-based comparisons via `assert_frame_equal` |
| NaN-handling MismatchClassification | ❌ | three NaN sentinels not distinguished in classification |
| IO format Tier 1/2/3 golden | ⚠️ partial | per-format roundtrips exist; tier distinction not formal |

---

## 3. Per-Pillar Deep Dive

### (a) Performance — current state + first 3 gaps

**Current state.** Per-op benches exist; no aggregate weighted score. The DataFrame-op cost matrix (row × col × dtype × NaN-density × groupby-cardinality) is large; benches likely cover only the diagonal.

**First 3 gaps:**
1. **No `.bench-history` baseline** for `groupby`, `merge_asof`, `rolling.window` — these are the workhorses; perf claims unprovable.
2. **`assign + groupby + agg` pipeline cost not measured end-to-end** — partial-pipeline benches miss the cost of intermediate copies.
3. **Arrow-backed vs NumPy-backed DataFrame perf** divergence not surfaced — backend choice changes throughput by 2–10× per op.

### (b) Conformance — current state + first 3 gaps

**Current state.** 1,252 conformance packets — bundles of test cases comparing the port to live pandas. But — packets are not content-addressed via `artifact_id = SHA-256`. NaN-sentinel ambiguity is not classified.

**First 3 gaps:**
1. **`pd.NA` vs `np.nan` vs `None` in object dtype** — these are three distinct sentinels; `assert_frame_equal` may pass with `check_dtype=False` even when the sentinel differs. First-pass: classify ≥20 packets as `NullHandlingDifference` rather than passes.
2. **`groupby` with NaN keys** — pandas dropna behavior changes by version; port may inherit one version's behavior implicitly.
3. **Multi-index column ordering after groupby+agg** — mixed-dtype keys produce different level ordering; passes `MultisetEquivalence` but fails `ExactRowMatch`.

### (c) Surface — current state + first 3 gaps

**Current state.** No formal FeatureUniverse. Per-method coverage tracked in bead-level beads (kurtosis-alias, etc.).

**First 3 gaps:**
1. **IO format coverage matrix** — 14+ formats × `read_*` / `to_*` / round-trip; some formats partial (HDF5 typically partial because of dependency on `tables`).
2. **`pd.api.extensions` (ExtensionArray)** — third-party extensibility surface; typically excluded.
3. **`pd.testing` API** — testing utilities themselves are part of pandas API; if the port reuses pandas for its own testing, that's not a port — it's a hybrid.

---

## 4. First-Pass Recipe

```bash
SKILL_ROOT="${GAUNTLET_SKILL_ROOT:-$HOME/.claude/skills/running-the-gauntlet-on-your-rust-port}"
[ -d "$SKILL_ROOT" ] || SKILL_ROOT="$HOME/.codex/skills/running-the-gauntlet-on-your-rust-port"

"$SKILL_ROOT/scripts/kickoff.sh" gauntlet-full
"$SKILL_ROOT/scripts/gauntlet.sh" /dp/frankenpandas /dp/frankenpandas__gauntlet_workspace \
  --mode gauntlet-full --dry-run

# Phase-specific inputs for the orchestrator/subagents:
# - reference pin: pandas-2.2.x
# - oracle mode: PyO3 in-process pandas
# - perf weights: DataFrameOps=0.20, GroupBy=0.20, Joins=0.15,
#   Rolling=0.10, IO=0.25, Indexing=0.10
# - conformance lift: migrate 1,252 packets to envelope format; DataFrameSpec comparator
# - failure terms: columnar storage drift, groupby fast path broke,
#   query expression rewrite wrong, IO parser shortcut, NaN sentinel mismatch,
#   multi-index level ordering, arrow-vs-numpy backend divergence

"$SKILL_ROOT/scripts/gauntlet.sh" /dp/frankenpandas /dp/frankenpandas__gauntlet_workspace \
  --mode gauntlet-full --soak-hours 72
```

Wall time T4 × `gauntlet-full`: **21–35 days.**

---

## 5. Expected Pillar Findings

### Performance
1. **`merge_asof` quadratic on unsorted input** — pandas sorts first; port may not.
2. **`groupby.apply` slower than `groupby.agg`** by 5–20× — UDF cost.
3. **Arrow→NumPy backend conversion in `read_parquet`** — silent re-cast.
4. **`rolling.mean(window=N)` not amortized** for large N — should use Welford's online algorithm.
5. **`to_csv` line-buffering** — write throughput sensitive to buffer size.
6. **`read_excel` per-sheet overhead** — repeated xlrd/openpyxl initialization.
7. **`assign + chain` materializes intermediates** — fluent API perf trap.
8. **`pd.concat` quadratic** for many small DataFrames — list-then-concat is correct pattern.

### Conformance
1. **`groupby('x').sum()` with NaN in `x`** — `dropna=True` (default) vs `False`.
2. **`pd.merge` on float keys** — NaN-key handling.
3. **`df.loc[df['x'] > 0]` returns view vs copy** — chained-assignment warning.
4. **`pd.NA` propagation in arithmetic** — `pd.NA + 1` vs `np.nan + 1`.
5. **`df.dropna(axis=1)` with mixed dtypes** — column-drop ordering.
6. **`pd.read_csv` `na_values` interaction** with `keep_default_na`.
7. **`to_datetime` ambiguous format strings** (e.g., `01-02-2024`) — DMY vs MDY default differs.
8. **`pivot_table` aggfunc with NaN** — passes through vs fills.
9. **`resample('M')` vs `'ME'`** — pandas 2.x deprecation.
10. **`df.eval('a + b')` semantics** — numexpr vs Python eval.

### Surface
1. **`pd.api.types.is_*`** introspection — partial coverage typical.
2. **`pd.options.*` (display, mode, io)** — global state; partial.
3. **`pd.Timedelta` arithmetic edges** — overflow at extreme durations.

---

## 6. Patterns to Apply First

1. **[pattern:30-DIFFERENTIAL-V2-ENVELOPE](../patterns/30-DIFFERENTIAL-V2-ENVELOPE.md)** — migrate 1,252 packets to envelope-format with `artifact_id = SHA-256` content-addressing.
2. **[pattern:180-NEGATIVE-LEDGER](../patterns/180-NEGATIVE-LEDGER.md)** — seed ledger.
3. **NaN-sentinel-aware MismatchClassification** — extend the enum: `NullHandlingDifference { sentinel: NanSentinel }`; `NanSentinel ∈ {NpNan, PdNA, None}`.
4. **Per-API metamorphic relations** — `df.groupby('x').sum() ≡ df.assign(g=...).groupby('g').sum().reset_index()`; `merge(A, B) ≡ merge(B, A).reorder_columns()`; `df.dropna().reset_index() ≡ df[df.notna().all(axis=1)].reset_index()`.
5. **Columnar storage golden artifacts at Tier 1 AND Tier 2** — Arrow vs NumPy backing differ at byte level but agree logically; both tiers needed.

---

## 7. Estimated Rounds to Convergence

**10–14 rounds.** Wide surface but 1,252 packets already gathered. Round 1 migrates packets to envelope format; rounds 2–5 fix NaN-sentinel classification; rounds 6–10 close IO format roundtrips; rounds 11–14 close per-method tail.

---

## 8. Risk Register

1. **Pandas 2.x deprecation timeline** — many APIs (`'M'`, `inplace=`) deprecated; pinning vs forward-compat tension. *Mitigation:* `migration` mode for version bumps.
2. **Optional dependency matrix** — Parquet (pyarrow), HDF5 (tables), Excel (openpyxl/xlrd) — each adds version pinning surface. *Mitigation:* one contract per IO format with optional-dep version.
3. **NaN sentinels in object dtype** — `None` and `pd.NA` and `np.nan` all coexist; comparison logic subtle. *Mitigation:* `NullHandlingDifference { sentinel }` classification.

---

## 9. What Ships from Convergence

`certification_bundle/`:
- Universal floor
- `dataframe_op_compliance.json` — per-method pass rate
- `io_format_roundtrip.json` — per-format Tier-1/2/3 results
- `nan_sentinel_classification.json` — per-test sentinel categorization
- `groupby_correctness_under_nan.json` — explicit dropna-vs-keep coverage

---

## Cross-references

- [SIBLING-PROJECTS-STATUS.md § FrankenPandas](../exemplars/SIBLING-PROJECTS-STATUS.md)
- [PROJECT-CLASSES.md § Numerical-Python-Class](../taxonomy/PROJECT-CLASSES.md)
- [first-bug-hunt/numerical-python-class.md](../first-bug-hunt/numerical-python-class.md)
- [case-studies/franken_numpy.md](franken_numpy.md) — backing-array compatibility
