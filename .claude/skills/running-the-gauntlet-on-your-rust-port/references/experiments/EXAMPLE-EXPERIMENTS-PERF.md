# Worked Perf Experiments

Six experiments, all mined verbatim from FrankenSQLite artifact lanes and PART XIII (the 10 winning patterns). Each uses the template from [EXPERIMENT-DESIGNS-TEMPLATE.md](EXPERIMENT-DESIGNS-TEMPLATE.md). Use as models for your project's `PERF_HYPOTHESIS_LEDGER.md`.

The pattern in each: a profile-derived hypothesis, a one-line invocation, a quantitative expected signal, and a results-inline string that proves the rule. None of these are speculative — all closed with `CONFIRMED_GAP` and a commit hash.

---

## PERF-0001: Promote `IsNull` opcode into `try_execute_hot_opcode`

- **pillar:** perf
- **hypothesis:** Pre-matching the `IsNull` VDBE opcode in `try_execute_hot_opcode` (alongside already-promoted `SCopy`, `IfNot`) will produce a measurable MT8 throughput win and eliminate the IsNull frame from the top-10 MT8 self-time table.
- **motivation:** `IsNull` accounts for 0.51% MT8 self-time in baseline flamegraph. Two siblings (`SCopy`, `IfNot`) already gained +38.6% / +31.5% from this exact promotion (CC.md §53.1). Opcode fires inside inner VDBE step loop, so branch-misprediction overhead is the assumed cost. Hot-opcode promotion is **Pattern 1** of the 10 winning patterns (see [../remediation/REMEDIATION-PATTERNS.md § Pattern 1](../remediation/REMEDIATION-PATTERNS.md)).
- **minimal_reproducer:**
  ```rust
  let conn = fsqlite::Connection::open(":memory:")?;
  conn.execute("CREATE TABLE t(a INTEGER); INSERT INTO t VALUES (NULL), (1), (NULL), (2);")?;
  for _ in 0..100_000 {
      let _ = conn.prepare("SELECT * FROM t WHERE a IS NOT NULL")?.execute(())?;
  }
  ```
- **expected_signal:** ≥5% throughput improvement on `mt_mvcc_bench --threads=8 --iters=3`; `IsNull` frame ≤0.1% in candidate flamegraph (vs 0.51% baseline).
- **falsifiability_criteria:** Throughput gain <0.1% (within ±3-5% cv_pct noise band) OR `IsNull` frame remains ≥0.5%.
- **one_line_invocation:**
  ```bash
  cargo bench --bench mt_mvcc --profile release-perf -- --threads=8 --iters=3 \
    && samply record --output tests/artifacts/perf/PERF-0001/samply.json -- \
       target/release-perf/deps/mt_mvcc_bench-* --threads=8 --iters=1
  ```
- **results_inline:** `CONFIRMED_GAP` — Closed 0.51% MT8 IsNull self-time; throughput **+27.5% / +27.2%** (commit `7c1a8b2e`). Both gates moved in same run window; `cv_pct` 1.8%; `selections=` byte-identical to baseline; `concurrent_mode_default_guard.txt` shows `CONCURRENT_MODE_DEFAULT=true`.
- **evidence_artifact_paths:**
  - `tests/artifacts/perf/PERF-0001/baseline_flame.svg`
  - `tests/artifacts/perf/PERF-0001/candidate_flame.svg`
  - `tests/artifacts/perf/PERF-0001/samply.json`
  - `tests/artifacts/perf/PERF-0001/delta_summary.json`
  - `.bench-history/mt-mvcc-bench.latest.json`
  - `.bench-history/comprehensive_bench.latest.json`
- **spawned_hypotheses:** `[PERF-0002: Apply same promotion to IfNullRow opcode]`
- **closure_predicate:** "Retry condition not applicable — the gain is structural, not numerical."

---

## PERF-0002: `PublishedPages::clear()` AtomicBool gate for empty case

- **pillar:** perf
- **hypothesis:** Wrapping `ConcurrentPublishedPages::clear()` in an AtomicBool `has_anything` gate will make the empty case O(1) instead of O(N) sharded-lock-and-scan. This is **Pattern 2** (AtomicBool gate).
- **motivation:** `PublishedPages::clear()` shows 2.92µs per call on the empty-overflow lane (which is hit on every commit even when no overflow pages exist). MT8 attribution reports 0.44% self-time. Most calls observe zero work but pay full sharded-lock cost.
- **minimal_reproducer:**
  ```rust
  // Microbench against the empty case
  let pages = ConcurrentPublishedPages::new();
  for _ in 0..1_000_000 {
      pages.clear();  // baseline: 2.92µs; expected with gate: ~1ns
  }
  ```
- **expected_signal:** ≥100x speedup on `published_pages_clear_empty` microbench; ≥0.4% MT8 self-time reduction attributable to `PublishedPages::clear` frame.
- **falsifiability_criteria:** Speedup <10x (gate overhead dominates), OR MT8 attribution unchanged.
- **one_line_invocation:**
  ```bash
  cargo bench --bench overflow_microbenches --profile release-perf -- published_pages_clear \
    && cargo bench --bench mt_mvcc --profile release-perf -- --threads=8
  ```
- **results_inline:** `CONFIRMED_GAP` — empty-overflow `2.92µs → 1 ns ≈ 2922x speedup`. Closed 0.44% MT8 PublishedPages::clear residual. Subtlety captured in commit message: "Flag is allowed false positive but *never* false negative. Set flag *before* publishing, clear *after* sweeping."
- **evidence_artifact_paths:**
  - `tests/artifacts/perf/PERF-0002/published_pages_baseline.json`
  - `tests/artifacts/perf/PERF-0002/published_pages_candidate.json`
  - `tests/artifacts/perf/PERF-0002/mt8_flame_before.svg`
  - `tests/artifacts/perf/PERF-0002/mt8_flame_after.svg`
- **spawned_hypotheses:** `[PERF-0003: ShardedPageCache::clear empty-shards lane; PERF-0004: notify_all_waiters SeqCst fence avoidance]`
- **closure_predicate:** "Retry condition not applicable — the gain is structural; same pattern applies elsewhere as separate experiments."

---

## PERF-0003: HashSet → sorted Vec rewrite of `HandleView` on SSI commit path

- **pillar:** perf
- **hypothesis:** Replacing 6× `HashSet` instances in `HandleView` with sorted `Vec<HandleId>` + `binary_search` will speed up SSI commit path by ≥1.5x, because the upstream `summarize_witness_keys()` already produces sorted Vec which the old code re-collected into HashSets. This is **Pattern 4** (HashSet → sorted Vec).
- **motivation:** `cargo flamegraph` on SSI commit path shows `HashSet::insert` / `HashSet::contains` accounting for ~40% of `HandleView::build()` self-time. The 6 HashSets have ≤100 elements each (matches Pattern 4's "≤100 elements" criterion). Source is already sorted.
- **minimal_reproducer:**
  ```rust
  let witness = summarize_witness_keys(/* fixture inputs */);
  // baseline: builds 6 HashSets internally
  let view = HandleView::build(&witness);  // measure this
  ```
- **expected_signal:** ≥1.5x speedup on `handle_view_build` criterion bench; SSI commit p50 latency ≥5% lower on `mt_oltp_bench`.
- **falsifiability_criteria:** Speedup <1.2x (means HashSet hash cost was not the dominant factor), OR p50 latency unchanged.
- **one_line_invocation:**
  ```bash
  cargo bench --bench ssi_microbenches --profile release-perf -- handle_view_build \
    && cargo bench --bench mt_oltp --profile release-perf
  ```
- **results_inline:** `CONFIRMED_GAP` — `1674.8 → 970.8 ns/build (−42.0%, ~1.7x)` on SSI commit path (2026-04-25 ledger entry). Insight recorded: "`summarize_witness_keys()` already produced sorted Vecs that old code re-collected into HashSets." Both focused (`handle_view_build`) and broad (`mt_oltp_bench` p50) moved in same run window.
- **evidence_artifact_paths:**
  - `tests/artifacts/perf/PERF-0003/criterion_handle_view_build.json`
  - `tests/artifacts/perf/PERF-0003/mt_oltp_baseline.json`
  - `tests/artifacts/perf/PERF-0003/mt_oltp_candidate.json`
- **closure_predicate:** "Retry condition not applicable — structural; audit other HashSets via `rg -n 'HashSet::' --type rust crates/`."

---

## PERF-0004: Prepared-statement cache eviction on every COMMIT — cache-eviction bug

- **pillar:** perf
- **hypothesis:** Prepared-statement cache is being evicted on every COMMIT because the cache key includes `db_generation`, but bytecode doesn't depend on generation — only schema. Cache-miss-rate metric should show >50% miss rate after every commit. This is **Pattern 10** (cache-eviction bug detection).
- **motivation:** MT 8t `fs_wps` is 778 ops/sec, but oracle (`csqlite`) is 5458 ops/sec at the same workload — 7x faster. `prepared_lookup_time_ns` HotPathProfileSnapshot counter shows 99%+ cache misses. Suspected the eviction policy is over-aggressive. Per Pattern 10's audit rule: "for every cache key, list which inputs it depends on; for every cache invalidation, list which inputs should invalidate it; gap = bug."
- **minimal_reproducer:**
  ```rust
  let conn = fsqlite::Connection::open(":memory:")?;
  conn.execute("CREATE TABLE t(a INTEGER); INSERT INTO t VALUES (1);")?;
  let mut hit_count = 0;
  for _ in 0..1000 {
      conn.execute("BEGIN")?;
      conn.execute("UPDATE t SET a = a + 1")?;
      conn.execute("COMMIT")?;
      // Now re-prepare the same UPDATE — should be a cache hit
      let prepared = conn.prepare("UPDATE t SET a = a + 1")?;
      if !prepared.is_freshly_compiled() { hit_count += 1; }
  }
  assert!(hit_count > 950, "expected >95% cache hits; got {hit_count}");
  ```
- **expected_signal:** Audit confirms `db_generation` in cache key; fix (separating bytecode-cache key bound to schema from data-cache key bound to generation) raises `fs_wps` from 778 to ~5000 on MT 8t; cache-hit-rate metric jumps from <5% to >95% post-commit.
- **falsifiability_criteria:** Audit shows cache key already correct (refuted), OR fix yields <2x throughput improvement (other bottleneck dominates).
- **one_line_invocation:**
  ```bash
  cargo bench --bench mt_mvcc --profile release-perf -- --threads=8 --iters=3 \
    && cargo test -p fsqlite-vdbe --test prepared_cache_hit_rate
  ```
- **results_inline:** `CONFIRMED_GAP` — Audit confirmed `db_generation` in key. Fix produced **MT 8t fs_wps 778 → 5458 (7.0x)** and **1t fs_wps 88k → 305k (3x+)** (CC.md §62). This was the single largest perf win in the project. Spawned multiple sibling experiments (OnceLock derivation caching, schema-bound bytecode interning).
- **evidence_artifact_paths:**
  - `tests/artifacts/perf/PERF-0004/cache_key_audit.md`
  - `tests/artifacts/perf/PERF-0004/mt_mvcc_baseline_778.json`
  - `tests/artifacts/perf/PERF-0004/mt_mvcc_candidate_5458.json`
  - `tests/artifacts/perf/PERF-0004/1t_baseline_88k.json`
  - `tests/artifacts/perf/PERF-0004/1t_candidate_305k.json`
- **spawned_hypotheses:** `[PERF-0005: OnceLock VdbeProgram derivation; PERF-0006: separate schema-bound vs generation-bound caches in every cache crate]`
- **closure_predicate:** "Retry condition not applicable — architectural fix; future cache-key designs must include audit per Pattern 10's checklist."

---

## PERF-0005: Devirtualize `TransactionKind::get_page` via match arm

- **pillar:** perf
- **hypothesis:** Replacing `&dyn TransactionKind` dispatch for `get_page` and `write_page_data` with an enum-match (since the concrete-type set is small and stable: `Direct`, `Wal`, `Mvcc`) will close two MT8 dispatch-frame self-time entries (0.36% + 0.29%). This is **Pattern 6** (trait-object → match-arm devirtualization).
- **motivation:** MT8 attribution profile shows `<dyn TransactionKind>::get_page` at 0.36% self-time and `<dyn TransactionKind>::write_page_data` at 0.29% self-time. Both are above the 0.1% MT8 threshold (per **Pattern Bonus: MT8 attribution profile**). Cost is the indirect-call branch-mispredict. The concrete-type set is closed and stable in the crate hierarchy.
- **minimal_reproducer:**
  ```bash
  perf stat -e branch-misses,branch-instructions \
    target/release-perf/deps/mt_mvcc_bench-* --threads=8 --iters=1
  ```
- **expected_signal:** Each frame removed from MT8 top-10 self-time table (≤0.1% post-devirt); branch-miss rate on `mt_mvcc_bench --threads=8` drops by ≥0.3%; aggregate MT8 throughput improvement attributable to these two frames ≈0.65%.
- **falsifiability_criteria:** Frames remain >0.1% post-devirt (indirect call wasn't the cost), OR branch-miss rate unchanged.
- **one_line_invocation:**
  ```bash
  cargo bench --bench mt_mvcc --profile release-perf -- --threads=8 --iters=3 \
    && samply record --output tests/artifacts/perf/PERF-0005/samply.json -- \
       target/release-perf/deps/mt_mvcc_bench-* --threads=8 --iters=1
  ```
- **results_inline:** `CONFIRMED_GAP` — Devirtualized `get_page` and `write_page_data` only (commit `0375b55e`). Closed 0.36% + 0.29% MT8 dispatch-frame self-time entries. MEMORY.md citation: "Other `TransactionKind` methods stay on the closure helpers — cold or shape-uniform." (Per discipline: devirtualize the hot frames only, not the trait.)
- **evidence_artifact_paths:**
  - `tests/artifacts/perf/PERF-0005/baseline_mt8_top10.json`
  - `tests/artifacts/perf/PERF-0005/candidate_mt8_top10.json`
  - `tests/artifacts/perf/PERF-0005/perf_stat_baseline.txt`
  - `tests/artifacts/perf/PERF-0005/perf_stat_candidate.txt`
- **closure_predicate:** "Retry only if a profiler attributes a clearly-above-noise share to other `TransactionKind` methods on a wider workload shape."

---

## PERF-0006: Gate planner trace-ceremony behind `tracing::enabled!(INFO)`

- **pillar:** perf
- **hypothesis:** The planner `index-selection` trace ceremony evaluates 3× `env::var(...)` calls and string formatting *unconditionally*, even when no trace subscriber is attached. Wrapping the entire ceremony in `if tracing::enabled!(tracing::Level::INFO)` will produce 4-10× speedup on the `oltp_cost_estimation_hot_paths` bench. This is **Pattern 7** (trace-ceremony gating).
- **motivation:** Planner 2026-05-20 fresh-eyes pass spotted `env::var` calls inside a `tracing::debug!(...)` macro's argument list, which `tracing` evaluates before checking subscriber presence. `oltp_cost_estimation_hot_paths` is on the frontier (per CC.md §39 "frontier" definition); bd-mziaw filed.
- **minimal_reproducer:**
  ```bash
  RUST_LOG="" cargo bench --bench planner_microbenches --profile release-perf -- oltp_cost
  RUST_LOG=debug cargo bench --bench planner_microbenches --profile release-perf -- oltp_cost
  # Compare; if same time, ceremony is paid even with no subscriber.
  ```
- **expected_signal:** `RUST_LOG=""` candidate ≥4× faster than `RUST_LOG=""` baseline. `RUST_LOG=debug` performance equivalent (since the ceremony is genuinely needed there).
- **falsifiability_criteria:** Speedup <2× (other costs dominate the planner), OR `tracing` macro already gates internally and the perceived issue is profile noise.
- **one_line_invocation:**
  ```bash
  RUST_LOG="" cargo bench --bench planner_microbenches --profile release-perf -- oltp_cost
  ```
- **results_inline:** `CONFIRMED_GAP` — **4-10× oltp_cost** improvement (commit `f43902e2`, bd-mziaw). The 3× `env::var` calls were the dominant cost when no subscriber attached. Generalization mined: every `tracing::*!` macro with non-trivial arguments needs `if tracing::enabled!(...)` gate.
- **evidence_artifact_paths:**
  - `tests/artifacts/perf/PERF-0006/oltp_cost_baseline.json`
  - `tests/artifacts/perf/PERF-0006/oltp_cost_candidate.json`
  - `tests/artifacts/perf/PERF-0006/env_var_count_baseline.txt`
- **spawned_hypotheses:** `[PERF-0007: audit every tracing::* invocation in hot crates for ungated env::var or format!]`
- **closure_predicate:** "Retry only if a new tracing call appears in hot path without an `enabled!()` gate."

---

## Cross-Cutting Notes

- **Hypothesis specificity.** Every hypothesis above names: a quantitative threshold, an exact frame or counter, and a falsifiability criterion. The vague version ("the planner is slow") is the **plausible-hypothesis-without-profile** anti-pattern (CC.md §40 #7).
- **MT8 attribution discipline.** PERF-0001, PERF-0002, PERF-0005 all attribute to specific MT8 frames. The 0.1% threshold rule: "A frame at 0.05% is below the noise floor of the bench (cv_pct 3-5%); the **micro-lever trap**. A frame at 1% is rare and high-value. The 0.1-1% range is where productive optimization work happens." (MINING-3 §3.)
- **Both-gates-same-window rule.** Every `CONFIRMED_GAP` above cites both the focused gate and the broad gate (`.bench-history/comprehensive_bench.latest.json` or `mt-mvcc-bench.latest.json`). If only one moves, the candidate is rejected per `KEEP-GATE-RULES.md`.
- **Spawned hypotheses are first-class.** PERF-0002 spawned 0003-0004; PERF-0004 spawned 0005-0006. The loop fuels itself — closing one gap reveals two more, until convergence (10+ rounds, 2 consecutive clean rounds).

See also: [../remediation/REMEDIATION-PATTERNS.md](../remediation/REMEDIATION-PATTERNS.md) for the full 10-pattern catalog with proof numbers and transferability notes.
