# Experiment-Design Template

> Glyph: `🧪` **Experiment-Design** — "Does this suspected gap have a hypothesis / minimal-repro / expected-signal / falsifiability / one-line-invocation / results-inline entry in the appropriate ledger?"

Every gap, hunch, suspected regression, or "we should look at" thought lands here. The discipline: no narrative work without an experiment record. Stale ideas die fast; promising ideas accumulate evidence; closed ideas leave behind a retry-condition predicate.

---

## Where Experiments Live

All four ledgers are top-level markdown files inside `<project>__gauntlet_workspace/`:

| File | Pillar | Purpose |
|---|---|---|
| `GAUNTLET_EXPERIMENT_DESIGNS.md` | Mixed | Free-form catch-all; experiments not yet routed to a pillar |
| `PERF_HYPOTHESIS_LEDGER.md` | Performance | Every perf hypothesis, open or closed |
| `CONFORMANCE_HYPOTHESIS_LEDGER.md` | Conformance | Every oracle / metamorphic / fault / e-process / fuzz hypothesis |
| `SURFACE_PARITY_HYPOTHESIS_LEDGER.md` | Surface | Every coverage / FeatureUniverse / SurfaceMatrix hypothesis |

These four files are tracked in git. They survive compaction. The iteration coordinator (`subagents/iteration-coordinator.md`) reads them at the top of every round.

Routing rule: an experiment starts in `GAUNTLET_EXPERIMENT_DESIGNS.md` if its pillar is uncertain. Once classified, it moves to the pillar-specific ledger. Cross-pillar experiments (rare) live in `GAUNTLET_EXPERIMENT_DESIGNS.md`.

---

## Mandatory Fields per Experiment

| Field | Type | Purpose |
|---|---|---|
| `experiment_id` | per-ledger sequence (e.g., `PERF-0042`, `CONF-0017`, `SURF-0009`) | Stable handle; referenced in commits, beads, FailureBundles |
| `pillar` | `perf | conformance | surface` | Determines which gates and harness apply |
| `hypothesis` | one sentence, *falsifiable* | The whole point. No "investigate", "look at", "consider". |
| `motivation` | 1–3 sentences | Why this matters; what gap closes if confirmed |
| `minimal_reproducer` | smallest possible repro | Code path / SQL / RESP command / tensor op / HTTP request that exhibits the suspected behavior |
| `expected_signal` | what oracle/sanitizer/profiler/regression-detector should produce *if* the hypothesis is true | Quantitative when possible (e.g., ≥5% throughput improvement, ≥1 ULP delta, ≥0.1% MT8 self-time) |
| `falsifiability_criteria` | what would refute the hypothesis | Quantitative (e.g., gain <0.1% means refuted) |
| `one_line_invocation` | literal command | Copy-paste runnable; pinned profile; deterministic seed |
| `results_inline` | filled after the run | `CONFIRMED_GAP | NO_EVIDENCE | NEEDS_REFINEMENT | NEW_HYPOTHESIS_SPAWNED` + one-line evidence |
| `evidence_artifact_paths` | list of paths under `tests/artifacts/` | Flamegraph, samply JSON, FailureBundle, criterion CSV, etc. |
| `spawned_hypotheses` | list (only if result is `NEW_HYPOTHESIS_SPAWNED`) | Each must have its own entry created |
| `closure_predicate` | what makes this experiment CLOSED | The retry-condition vocabulary; e.g., "Reconsider only inside the broader DML mutation operator redesign" |

### Result-state semantics

- **`CONFIRMED_GAP`** — hypothesis held; remediation work (bead) is now owed. Cite the evidence; record the artifact paths; the next round must produce a bead.
- **`NO_EVIDENCE`** — ran the invocation; signal did not appear above noise / threshold. Move to closed with retry-condition; do NOT silently delete — the ledger keeps the negative result so the next round doesn't re-explore.
- **`NEEDS_REFINEMENT`** — the experiment was too coarse, too noisy, or the hypothesis was ambiguous. Stays open; the *next round* refines the invocation or the falsifiability criterion.
- **`NEW_HYPOTHESIS_SPAWNED`** — the experiment revealed a different gap. The original closes with a pointer; the new hypothesis gets its own entry. This is the loop fuel.

### Closure predicate (the load-bearing retry condition)

Every closed entry MUST have one. The vocabulary (see [methodology/RETRY-CONDITION-VOCABULARY.md](../methodology/RETRY-CONDITION-VOCABULARY.md)) is strict:

1. "Retry only if a profiler attributes a clearly-above-noise share to `<specific counter>` on `<wider workload shape>`"
2. "Reconsider only inside the broader `<X>` redesign"
3. "Worth reconsidering when `<specific gate moves>`"
4. "Not worth retrying as a standalone patch"
5. "Do not retry from a cold read; use `comprehensive-bench` attribution instead"
6. "Retry condition not applicable — the gain is structural, not numerical"
7. "Retry only if this workload class exhibits measurable `<property>` below `<threshold>`"
8. "Blocked until `<architectural_dependency>` lands; track as `<beads_id>`"

**Never** "later", "if it seems important", "TBD", "needs more thought".

---

## Convergence Interaction

The four ledgers drive the [methodology/CONVERGENCE.md](../methodology/CONVERGENCE.md) loop:

- **Every confirmed gap gets at least one experiment.** A gap without an entry is invisible to the convergence tracker.
- **Ambiguous gaps get multiple experiments**, each isolating a different assumption. Example: a regression appears on MT8 but not MT4; experiments E1 (lock contention), E2 (cache thrashing), E3 (allocator pressure) each isolate one cause.
- **Results feed the next round.** `convergence-tracker.sh` reads the four ledgers, counts open + `NEEDS_REFINEMENT` + `NEW_HYPOTHESIS_SPAWNED` entries, and refuses to certify until: ≥10 rounds, two consecutive rounds with <3 new genuine findings, every open hypothesis resolved.
- **Spawned hypotheses are first-class.** When E1 result is "lock contention not the cause; spawned E1.1 = cache-line false-sharing", E1.1 enters the ledger as a real experiment with its own fields.

---

## Paste-Ready Markdown Template

Drop this into the appropriate ledger; fill before running; update `results_inline` and `evidence_artifact_paths` after running.

```markdown
### PERF-NNNN: <short imperative hypothesis title>

- **pillar:** perf
- **hypothesis:** <one falsifiable sentence>
- **motivation:** <1-3 sentences why this matters>
- **minimal_reproducer:**
  ```sql
  -- or rust, or RESP, or python, or HTTP — whatever the smallest repro is
  CREATE TABLE t(a INTEGER);
  INSERT INTO t VALUES (1), (2), (3);
  SELECT * FROM t WHERE a IS NOT NULL;
  ```
- **expected_signal:** <quantitative; e.g., ≥5% throughput improvement on MT8, frame disappearing from top-10 self-time>
- **falsifiability_criteria:** <quantitative; e.g., gain <0.1%, OR frame still ≥0.5%>
- **one_line_invocation:**
  ```bash
  cargo bench --bench mt_mvcc --profile release-perf -- --threads=8 --iters=3
  ```
- **results_inline:** OPEN
- **evidence_artifact_paths:** []
- **spawned_hypotheses:** []
- **closure_predicate:** <one of the 8 retry-condition forms>
```

---

## Worked Example (Canonical)

Use this verbatim as a model when constructing your own. Pulled from the canonical FrankenSQLite MT8 IsNull lever.

### PERF-0042: Promote `IsNull` opcode into `try_execute_hot_opcode`

- **pillar:** perf
- **hypothesis:** Pre-matching the `IsNull` VDBE opcode in `try_execute_hot_opcode` (alongside the already-promoted `SCopy` and `IfNot`) will produce a measurable MT8 throughput win and eliminate the IsNull frame from the top-10 MT8 self-time table.
- **motivation:** `IsNull` accounts for 0.51% MT8 self-time in baseline `flame.svg`. Two siblings (`SCopy`, `IfNot`) gained +38.6% and +31.5% from this exact promotion. The opcode fires inside the inner VDBE step loop, so branch-misprediction overhead is the assumed cost.
- **minimal_reproducer:**
  ```rust
  // tests/artifacts/perf/PERF-0042/repro.rs
  let conn = fsqlite::Connection::open("file:bench.db?mode=memory&cache=shared")?;
  conn.execute("CREATE TABLE t(a INTEGER); INSERT INTO t VALUES (NULL), (1), (NULL), (2);")?;
  for _ in 0..100_000 {
      let _ = conn.prepare("SELECT * FROM t WHERE a IS NOT NULL")?.execute(())?;
  }
  ```
- **expected_signal:** ≥5% throughput improvement on `mt_mvcc_bench --threads=8`; `IsNull` frame ≤0.1% in candidate flamegraph (currently 0.51%).
- **falsifiability_criteria:** Throughput gain <0.1% (within ±3-5% cv_pct noise band) OR `IsNull` frame remains ≥0.5%.
- **one_line_invocation:**
  ```bash
  cargo bench --bench mt_mvcc --profile release-perf -- --threads=8 --iters=3 \
      && samply record --output tests/artifacts/perf/PERF-0042/samply.json -- \
         target/release-perf/deps/mt_mvcc_bench --threads=8 --iters=1
  ```
- **results_inline:** `CONFIRMED_GAP` — Closed 0.51% MT8 IsNull self-time; throughput +27.5% (commit `7c1a8b2e`). Both gates moved in same run window (`mt-mvcc-bench.latest.json` and `comprehensive_bench.latest.json` both green); `cv_pct` 1.8%; `selections=` byte-identical to baseline.
- **evidence_artifact_paths:**
  - `tests/artifacts/perf/PERF-0042/baseline_flame.svg`
  - `tests/artifacts/perf/PERF-0042/candidate_flame.svg`
  - `tests/artifacts/perf/PERF-0042/samply.json`
  - `tests/artifacts/perf/PERF-0042/delta_summary.json`
  - `.bench-history/mt-mvcc-bench.latest.json` (post-merge)
- **spawned_hypotheses:** `[PERF-0043: Apply same promotion to IfNullRow]`
- **closure_predicate:** "Retry condition not applicable — the gain is structural, not numerical; future similar opcodes follow the same pattern as candidates."

---

## Companion Templates per Pillar

### Conformance experiment template

```markdown
### CONF-NNNN: <short imperative hypothesis title>

- **pillar:** conformance
- **hypothesis:** <one falsifiable sentence; e.g., "Subject implements SQL three-valued logic for NULL = NULL identically to oracle">
- **motivation:** <gap suspected because: oracle differential / metamorphic / fuzz / e-process / property test reported X>
- **minimal_reproducer:**
  ```sql
  SELECT NULL = NULL;     -- expected oracle: NULL; subject: ?
  SELECT NULL IS NULL;    -- expected both: 1
  SELECT NULL <> NULL;    -- expected oracle: NULL; subject: ?
  ```
- **expected_signal:** Oracle and subject return identical NormalizedValue for each query; both-error agreement counted as match.
- **falsifiability_criteria:** Any query produces TrueDivergence per MismatchClassification (NullHandlingDifference is borderline; classify before deciding).
- **one_line_invocation:**
  ```bash
  cargo test -p fsqlite-e2e --test null_semantics_oracle_e2e -- --nocapture
  ```
- **results_inline:** OPEN
- **evidence_artifact_paths:** []
- **closure_predicate:** "Retry only if oracle's NULL semantics change in reference version <X.Y>"
```

### Surface experiment template

```markdown
### SURF-NNNN: <short imperative hypothesis title>

- **pillar:** surface
- **hypothesis:** <one falsifiable sentence; e.g., "Every entry in `numpy.__all__` is covered by a FeatureUniverse entry">
- **motivation:** Surface contract claim audited against reference enumeration source-of-truth.
- **minimal_reproducer:**
  ```python
  python -c "import numpy; print(len(numpy.__all__), sorted(numpy.__all__))" \
      | diff - <(rg --no-filename 'id = "F-NP-' crates/fnp-harness/src/parity_taxonomy.rs | sort)
  ```
- **expected_signal:** Zero-diff output; cardinality matches (499/499 for NumPy 1.26.0).
- **falsifiability_criteria:** Any name in `__all__` absent from FeatureUniverse AND not in the explicit Excluded list with rationale.
- **one_line_invocation:**
  ```bash
  cargo test -p fnp-harness --test feature_universe_covers_numpy_all
  ```
- **results_inline:** OPEN
- **evidence_artifact_paths:** []
- **closure_predicate:** "Retry only when reference version bumps; coverage gate is permanent."
```

---

## See Also

- [EXAMPLE-EXPERIMENTS-PERF.md](EXAMPLE-EXPERIMENTS-PERF.md) — 6 worked perf experiments
- [EXAMPLE-EXPERIMENTS-CONFORMANCE.md](EXAMPLE-EXPERIMENTS-CONFORMANCE.md) — 6 worked conformance experiments
- [EXAMPLE-EXPERIMENTS-SURFACE.md](EXAMPLE-EXPERIMENTS-SURFACE.md) — 6 worked surface experiments
- [../methodology/RETRY-CONDITION-VOCABULARY.md](../methodology/RETRY-CONDITION-VOCABULARY.md) — the 8 closure-predicate forms
- [../methodology/CONVERGENCE.md](../methodology/CONVERGENCE.md) — how the ledgers feed `convergence-tracker.sh`
- [../remediation/REMEDIATION-PATTERNS.md](../remediation/REMEDIATION-PATTERNS.md) — the 10 winning patterns that confirmed-gap experiments most often resolve into
