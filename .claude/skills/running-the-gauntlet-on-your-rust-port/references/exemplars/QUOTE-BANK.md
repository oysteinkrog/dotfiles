# Quote Bank — Verbatim Source-Anchored Quotes

Per `/operationalizing-expertise` § FORMATS canonical quote-bank format. Every cognitive operator, pattern, and methodology decision in this skill cites a verbatim quote from this bank by anchor ID (`[Q-NNN]`). This file is the audit trail for "where does this discipline come from."

Sources:
- **CC.md** = `/data/projects/frankensqlite/COMPREHENSIVE_BREAKDOWN_OF_FRANKENSQLITE_PERFORMANCE_AND_CONFORMANCE_ASSURANCE_PROCESS__CC.md` (~5,065 lines, 32 current `# PART` headings)
- **CODEX.md** = `/data/projects/frankensqlite/COMPREHENSIVE_BREAKDOWN_OF_FRANKENSQLITE_PERFORMANCE_AND_CONFORMANCE_ASSURANCE_PROCESS__CODEX.md` (~3,798 lines, 19 numbered sections)

Format per `/operationalizing-expertise § FORMATS.md`:

```
## [Q-NNN] — §X.Y — Short topic anchor
> "Verbatim quote..."
— Source: CC.md §X.Y (line range if available)
Tags: tag1, tag2, ...
```

---

## §1 — Kernel philosophy

### [Q-001] — CC.md §2.1 — The 30-line scenario template (preface)
> "Both engines get identical PRAGMAs. This is a 30-line block at `comprehensive_bench.rs:502–541`, not a verbal convention."
— Source: CC.md §1.5 (lines 267–275, 1278)
Tags: kernel, oracle, identical-config, K-7, K-2

### [Q-002] — CC.md §1.5 — Same-run-window non-negotiable
> "Both gates must move in the same run window. Same run = same git state, same `target/`, same machine, same minute."
— Source: CC.md PART VII §37 (mined: MINING-1 §1, the keep-gate vocabulary glossary)
Tags: keep-gate, K-4, both-gates, same-run-window

### [Q-003] — CC.md §0 (Executive Summary) — Subject/Oracle/Comparator as the engine
> "Subject/Oracle/Comparator Across 8 Quality Concerns" — every artifact in the gauntlet decomposes into a Subject, an Oracle, and a Comparator. If you cannot name all three on demand for a given gate, the gate is not a gate.
— Source: MINING-2 §Summary
Tags: kernel, K-1, gate-definition

### [Q-004] — MINING-2 §12 — Adversarial threat model
> "An agent honest enough to write the gate is biased toward making it pass."
— Source: MINING-2 §12 (Adversarial search threat model)
Tags: kernel, K-2, adversarial, gate-honesty

### [Q-005] — CC.md PART VII §37 — Keep-gate definition
> "The numeric threshold an optimization must clear to be merged. Singular 'the keep gate' usually means the comprehensive-bench primary score. Specific gates are *named*: 'focused DML keep gate', '10K DELETE keep gate', 'MT8 keep gate'."
— Source: CC.md §37 (PART VII)
Tags: keep-gate, vocabulary, perf

---

## §2 — Honest measurement vocabulary

### [Q-010] — CC.md §37 — Within noise
> "Improvement is ≤ the workload's cv_pct band (typically ±3–5%). Not a win — *technically also not a loss*, but not durable evidence."
— Source: CC.md PART VII §37
Tags: vocabulary, perf, cv_pct, micro-lever

### [Q-011] — CC.md §37 — Fresh-eyes pass
> "A full re-review of recent code by an agent who didn't write it. Often surfaces a regression that the author rationalized away. The pattern: 'fresh-eyes fix' entries land *along with* the rejection of the author's defense."
— Source: CC.md PART VII §37
Tags: vocabulary, fresh-eyes, agent-honesty

### [Q-012] — CC.md §37 — MT8 attribution
> "Multi-thread 8-thread benchmark — the canonical concurrency-stress workload. Used as a profiling anchor: 'MT8 attribution' means the profiler ran under MT8 load, which exercises the MVCC plane realistically."
— Source: CC.md PART VII §37
Tags: vocabulary, perf, MT8, attribution

### [Q-013] — CC.md §37 — Micro-lever trap
> "A small optimization that *could* help in principle. The phrase 'no bounded micro-lever found' is a common rejection reason: the team looked for a few-ns win and found none."
— Source: CC.md PART VII §37
Tags: vocabulary, perf, micro-lever, anti-pattern

### [Q-014] — CC.md §37 — Pulled the pin
> "Discarded a previously-committed-then-reverted candidate. Distinct from 'rejected uncommitted'. Used when the candidate was on a branch that got abandoned."
— Source: CC.md PART VII §37
Tags: vocabulary, perf, ledger, rejection-state

### [Q-015] — CC.md §37 — Behavior-preserving
> "The candidate doesn't change observable behavior (verified by oracle tests, selection counts, bench-level row equality). Required prerequisite for any rejection-by-perf — a behavior-changing candidate is a different question entirely."
— Source: CC.md PART VII §37
Tags: vocabulary, perf, behavior-preserving, isomorphism-proof

### [Q-016] — CC.md §37 — Selections= byte-identical
> "A specific form of behavior-preservation proof: the bench harness exposes per-scenario selection counters; a change that preserves selection counts to the byte is verified non-behavior-affecting."
— Source: CC.md PART VII §37
Tags: vocabulary, perf, selections, byte-identical, proof

---

## §3 — Negative ledger discipline

### [Q-020] — CC.md opening lines 479–482 — Ledger purpose
> "This ledger records performance ideas that were measured and rejected. Check it before starting a new optimization pass, and add an entry whenever a candidate is abandoned, reverted, or kept out of the tree because the benchmark matrix did not move in the intended direction."
— Source: CC.md opening (lines 479–482)
Tags: ledger, negative-evidence, K-3

### [Q-021] — CODEX.md §10.2 lines 1464–1472 — Pre-perf-work mandate
> "For major perf campaigns, agents must also mine: last 60 days of CASS session history, recent commits, perf artifacts, failed/rejected/slower/regressed terms. If CASS or the ledger is unavailable or reserved, the agent must record a blocker or patch-ready entry rather than silently skipping the step."
— Source: CODEX.md §10.2 (lines 1464–1472)
Tags: ledger, cass-mining, AGENTS.md-mandate

### [Q-022] — CC.md §39 — Retry-condition vocabulary (canonical example)
> "Reverted — within-noise. Reusing find_rowid_equality_term for the RowidLookup probe (vs 2nd scan in extract_access_path_probe) was behavior-preserving (identical selection counts; 13 probe/21 rowid/35 access_path tests pass) but point-lookup gain ~2% sits in the ±3-5% bench noise band."
— Source: CC.md PART VII §39 (line 567)
Tags: ledger, retry-condition, within-noise, example

### [Q-023] — CC.md §39 — Architecturally-deferred predicate
> "reconsider only inside the broader DML mutation operator redesign"
— Source: CC.md §43 (line 1921)
Tags: ledger, retry-condition, architectural-defer

---

## §4 — Performance machinery

### [Q-030] — CC.md §1.2 — Six timing constants
> "WARMUP_ITERS: usize = 2; MIN_ITERS: usize = 3; MAX_ITERS: usize = 10; TARGET_DURATION: Duration = Duration::from_secs(5);"
— Source: CC.md §1.2 (lines 49–52)
Tags: perf, constants, comprehensive-bench

### [Q-031] — CC.md §1.2 — measure_with_teardown discipline
> "Crucially, the teardown call is *outside* the timed window — `start.elapsed()` is captured *before* `teardown()` runs."
— Source: CC.md §1.2 (line 74)
Tags: perf, comprehensive-bench, teardown, K-2

### [Q-032] — CC.md §1.7 — release-perf profile
> "[profile.release-perf] inherits = 'release', opt-level = 3, lto = 'thin', codegen-units = 1, debug = 'line-tables-only', strip = false, RUSTFLAGS='-C force-frame-pointers=yes'. Never `--release` (size-optimized) for any perf claim."
— Source: CC.md §1.7 (lines 192–196)
Tags: perf, release-perf, profile, K-4

### [Q-033] — CC.md §1.9 — concurrent_mode_default_guard
> "concurrent_mode_default_guard.txt dropped into every artifact lane as proof that the experiment ran with the project's defining feature enabled."
— Source: CC.md §1.9 (lines 186, 1277)
Tags: perf, honesty-file, K-2, guard-file

### [Q-034] — CC.md §63 — MT8 attribution citation form
> "Closed 0.44% MT8 PublishedPages::clear residual"
— Source: CC.md §63 (line 2256)
Tags: perf, MT8, attribution, citation-form

### [Q-035] — CC.md §63 — 0.1% self-time threshold
> "A frame at 0.05% is below the noise floor of the bench (cv_pct typically 3-5%) and trying to optimize it is the **micro-lever trap**. A frame at 1% is rare and high-value. The 0.1-1% range is where productive optimization work happens."
— Source: CC.md §63 (line 2393)
Tags: perf, MT8, threshold, micro-lever-trap

---

## §5 — Conformance machinery

### [Q-040] — CC.md §2.1 — Both-error agreement rule
> "Both-error = agreement (message text irrelevant). One-error-one-OK = hard failure."
— Source: MINING-2 §1 (mined from CC.md §2.1)
Tags: conformance, oracle, K-8, error-agreement

### [Q-041] — CC.md §2.3 — Differential V2 artifact_id
> "artifact_id = SHA-256 of canonical JSON excluding run_id. Two runs with identical semantic inputs (same engines, pragmas, schema, workload, seed) produce the same artifact ID even if their run_id differs by timestamp or process ID."
— Source: CC.md §2.3 + crates/fsqlite-harness/src/differential_v2.rs:183–198
Tags: conformance, differential-v2, content-addressed, K-11

### [Q-042] — CODEX.md §5.8 — Three-tier equivalence rule
> "Encode the distinction; never paper over it."
— Source: CODEX.md §5.8 (equivalence tiers)
Tags: conformance, three-tier, golden-artifacts

### [Q-043] — CC.md §15 — Failure bundle never-skip rule
> "A partial bundle with provenance is more valuable than no bundle. Never skip manifest writing on failure."
— Source: CC.md §15 (crates/fsqlite-harness/src/failure_bundle.rs module description)
Tags: conformance, failure-bundle, provenance

### [Q-044] — CC.md §8.4 — Seed contract
> "All seeds are derived from `derive_entry_seed(corpus_entry_id)`. Given the same corpus entry, the same transforms run in the same order on the same RNG draws, producing the same SQL. Never `rand::random()`. Flake (non-determinism) is a class of bug."
— Source: CC.md §8.4 (metamorphic.rs SeedContract)
Tags: conformance, seed-contract, determinism, anti-flake

### [Q-045] — CC.md §17 — E2E log as API
> "Logs aren't free text for humans; they're a machine-consumable trace of test execution that future agents (and CI) parse to compute coverage, find gaps, and bisect regressions. This is *log-as-API*."
— Source: CC.md §17 (lines 1210–1211)
Tags: conformance, e2e-log, schema-as-api, K-10

---

## §6 — Mathematical machinery

### [Q-050] — CC.md §11 — E-process anytime-validity
> "Ville's inequality: P_{H_0}(∃t: E_t ≥ 1/α) ≤ α. Anytime-valid: check after every operation, reject when crosses 1/α, no Bonferroni correction needed."
— Source: CC.md PART XVI §11 + §20
Tags: math, e-process, ville-inequality, anytime-valid

### [Q-051] — CC.md §11.3 — Arithmetic-mean global e-value
> "Arithmetic mean of e-processes is itself an e-process under the global null *regardless of dependence between the individual invariants*."
— Source: CC.md §11.3
Tags: math, e-process, dependence, aggregation

### [Q-052] — CC.md §14.1 — Conformal band rationale
> "Database benchmark distributions are heavy-tailed, bimodal, regime-shifting. A normal-distribution-based confidence interval would lie. Conformal prediction's guarantee P(R_{n+1} ≤ q) ≥ 1 − α holds for *any* distribution. The cost is the interval is wider than parametric — but it's *honest*."
— Source: CC.md §14.1 (lines 1109–1111)
Tags: math, conformal, distribution-free, K-6

### [Q-053] — CC.md §11.4 — truncate_score rationale
> "x86, ARM, and WASM floating-point arithmetic differ at the LSB; truncating to 6 decimal places ensures that two runs produce bytewise identical scores regardless of CPU architecture."
— Source: CC.md §11.4 (score_engine.rs file header lines 29–30)
Tags: math, truncate_score, cross-platform, K-5

---

## §7 — Optimization patterns (PART XIII)

### [Q-060] — CC.md §53 — try_execute_hot_opcode promotion
> "Identify opcodes firing in inner loops of the main VDBE dispatch; extract them to a pre-match hot-path function to reduce branch misprediction overhead."
— Source: CC.md §53 (lines 2207–2241)
Tags: optimization, hot-opcode, vdbe, branch-prediction

### [Q-061] — CC.md §54 — AtomicBool empty gate (canonical proof number)
> "ConcurrentPublishedPages::clear() empty-overflow: 2.92µs → 1 ns (~2922x). ShardedPageCache::clear() empty-shards: 529 ns → 5 ns (~106x). InProcessPageLockTable::notify_all_waiters SeqCst-fenced: 1057.8 → 8.2 ns (~129x)."
— Source: CC.md §54 (lines 2256–2260)
Tags: optimization, atomic-bool, fast-path, proof-numbers

### [Q-062] — CC.md §55 — Algebraic counter elimination
> "validations_total == commits_total + aborts_total by construction. Dropping the static counter and deriving the validations count at snapshot time produced 3.91 → 1.90 ns/call (-51.5%, ~2x) on the hot path (commit 36504496)."
— Source: CC.md §55 (lines 2295–2302)
Tags: optimization, counter-elimination, derive-not-accumulate

### [Q-063] — CC.md §62 — Cache-eviction bug audit
> "Audit discipline: for every cache, list which inputs it ACTUALLY depends on; for every invalidation, list which inputs SHOULD invalidate it; gap = bug."
— Source: CC.md §62 (lines 2374–2381)
Tags: optimization, cache-key, semantic-bug, audit

### [Q-064] — CC.md §62 — Cache-eviction bug measured win
> "Prepared-statement cache was being evicted on every COMMIT because the cache key included db_generation, but bytecode doesn't depend on data generation (only schema). Fix: separate bytecode-cache key (schema-bound) from data-cache key (generation-bound). Result: MT 8t fs_wps 778 → 5458 (7.0x), 1t fs_wps 88k → 305k (3x+)."
— Source: CC.md §62
Tags: optimization, cache-key, semantic-bug, 7x-win

---

## §8 — Surface parity discipline

### [Q-070] — CC.md §25 — Three loader-enforced invariants
> "Three invariants enforced by the loader: `sum(weights) == 1.0` per category (no silent score inflation from new features without rebalancing); `truncate_score` for cross-platform determinism; deterministic iteration order by FeatureId."
— Source: CC.md §25 (lines 1579–1583)
Tags: surface, FeatureUniverse, loader, weight-sum, K-5

### [Q-071] — CC.md §27 — Catalog ships the proof-of-work
> "The catalog doesn't just say 'we tested X', it says 'we tested X, the evidence is at path P with SHA-256 H against schema version V'. A release that ships the catalog ships the proof-of-work."
— Source: CC.md §27 (line 1629)
Tags: surface, invariant-catalog, proof-of-work, K-10

### [Q-072] — CC.md §28 — Closure wave discipline
> "You don't write tests for what you remember to write tests for; you enumerate the universe of behaviors, *then* observe which the engine handles."
— Source: CC.md §28 (line 1644)
Tags: surface, closure-wave, enumeration-first

---

## §9 — Skill-composition philosophy

### [Q-080] — CC.md PART XXIII — Profiling skill rule
> "/profiling-software-performance — Ranked evidence before any optimization. No hotspot list → no change."
— Source: CC.md PART XXIII (lines 2924-2942)
Tags: skill, profiling, rule-of-thumb

### [Q-081] — CC.md PART XXIII — Extreme optimization rule
> "/extreme-software-optimization — Profile first. Prove behavior unchanged. One change at a time."
— Source: CC.md PART XXIII
Tags: skill, optimization, rule-of-thumb

### [Q-082] — CC.md PART XXIII — Multi-pass bug hunting
> "/multi-pass-bug-hunting — First pass finds obvious bugs. Second pass finds bugs hidden by the obvious ones. Third pass catches what you introduced fixing the first two."
— Source: CC.md PART XXIII
Tags: skill, fresh-eyes, multi-pass

### [Q-083] — CC.md PART XXIII — Deadlock 4th-instance rule
> "/deadlock-finder-and-fixer — There is almost always a fourth instance."
— Source: CC.md PART XXIII
Tags: skill, deadlock, 4th-instance

### [Q-084] — CC.md PART XXIII — Flywheel generative grammar
> "/flywheel — Don't summarize — extract the **generative grammar**. Your repeated behaviors ARE your methodology."
— Source: CC.md PART XXIII
Tags: skill, flywheel, methodology-from-behavior

---

## §10 — Anti-patterns

### [Q-090] — CC.md §87.4 — Optimize without profiling
> "Optimize without profiling — Wastes effort on non-hotspots."
— Source: CC.md §87.4 (lines 3098-3104)
Tags: anti-pattern, perf, profile-first

### [Q-091] — CC.md §87.4 — Multiple changes per commit
> "Multiple changes per commit — Can't isolate regressions."
— Source: CC.md §87.4
Tags: anti-pattern, perf, commit-discipline

### [Q-092] — CC.md §40 — Single-cell extraction
> "Winning on one cell of a multi-cell matrix (e.g., 10K rows) while hidden cells (100 rows) regress. Must check all cells."
— Source: CC.md §40 (mined from ledger frequency table)
Tags: anti-pattern, perf, cherry-pick

### [Q-093] — CC.md §40 — Plausible hypothesis without profile
> "'The parser is slow' or 'locking is probably the bottleneck' without a ranked hotspot table tied to flamegraph/profile artifact."
— Source: CC.md §40
Tags: anti-pattern, perf, evidence-first

### [Q-094] — CC.md §40 — Behavior-changing 'correctness-abandoned'
> "Attempting to merge an optimization that changes behavior (fails oracle tests) by framing it as a perf change. Ledger marks as 'correctness-abandoned' and blocks."
— Source: CC.md §40
Tags: anti-pattern, perf, correctness, behavior-preserving

---

## §11 — Reproducibility / identity

### [Q-100] — CC.md §15 — First-divergence jsonptr
> "The pointer at `/failure/first_divergence` is one of the most important UX details in the project: a CI failure jumps you straight to the byte-offset where the two engines first disagreed, not to 'test X failed somewhere'."
— Source: CC.md §15 (lines 1140-1148)
Tags: reproducibility, failure-bundle, first-divergence, ux

### [Q-101] — CC.md §17 — Required event fields
> "REQUIRED_EVENT_FIELDS = ['run_id', 'timestamp', 'phase', 'event_type']. run_id = {bead_id}-{timestamp}-{pid}. timestamp = ISO 8601 UTC. phase = setup | execute | validate | teardown."
— Source: CC.md §17 (lines 1192-1197)
Tags: reproducibility, e2e-log, schema, K-10

### [Q-102] — CC.md §137 — Oracle preflight failure prevention
> "Prevents several high-cost failure modes: self-comparison where FrankenSQLite accidentally compares against itself; version drift where oracle binary is not the target SQLite version; stale corpus manifests where tests are not measuring the current fixture set; fixture roots that look present but don't satisfy cardinality floors; red certification runs being mistaken for legitimate evidence."
— Source: CC.md §137 (Oracle Preflight Doctor)
Tags: reproducibility, oracle-preflight, failure-mode-prevention

---

## §12 — Convergence + iteration

### [Q-110] — SKILL.md (this skill) § Convergence Rule — The 3 conditions
> "Minimum rounds met — ≥10 full iterations of Phases 5→10. Two consecutive clean rounds — each producing <3 new genuine findings. Every open hypothesis resolved."
— Source: this skill's SKILL.md § Convergence Rule
Tags: convergence, K-12, gating-rule

---

## §13 — Sibling adoption (status)

### [Q-120] — CC.md PART XXIV (matrix preface)
> "Cross-sibling maturity matrix"
— Source: CC.md PART XXIV (lines 3621-3637, MINING-1 §8)
Tags: sibling, adoption-status, matrix

### [Q-121] — CC.md §99 — FrankenNumPy bit-exact PCG64DXSM
> "**Bit-exact PCG64DXSM RNG parity** for explicit seeds"
— Source: CC.md §99 (lines 3502-3529) (MINING-1 §8)
Tags: sibling, franken_numpy, bit-exact, RNG, non-negotiable

### [Q-122] — CC.md §98 — FrankenTorch absolute parity doctrine
> "'Absolute parity doctrine'; has LabRuntime; missing per-op ULP table, gradcheck-as-CI-invariant"
— Source: CC.md §98 (MINING-1 §8)
Tags: sibling, frankentorch, absolute-parity, ULP-table

---

## Adding new entries

When adding a quote:

1. Pick the next free slot in the relevant §N section (keep within the 10-id-per-section band where possible; e.g., §4 perf machinery is Q-030..Q-039).
2. Cite the verbatim quote (not paraphrase). Use blockquote `>` markdown.
3. Source line: `— Source: <CC.md or CODEX.md> §X.Y (lines N–M if available)`.
4. Tags: comma-separated; first tag is the section name; second is the K-N axiom if applicable.

Cross-reference quotes from:
- `[methodology/KERNEL.md](../methodology/KERNEL.md)` § K-N axioms
- `[methodology/OPERATORS.md](../methodology/OPERATORS.md)` operator cards
- `[patterns/NN-NAME.md](../patterns/00-INDEX.md)` "Why" sections
- `[methodology/ANTI-PATTERNS.md](../methodology/ANTI-PATTERNS.md)` rejection rationales
