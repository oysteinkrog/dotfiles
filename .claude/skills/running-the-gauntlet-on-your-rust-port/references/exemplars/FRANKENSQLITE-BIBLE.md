# FRANKENSQLITE BIBLE — Section-by-Section Routing

> The two bibles are the lived methodology. This skill is the **distilled methodology**. Routes from *"I need X"* to *"read Y in bible Z"*.

**The two source documents:**

- **CC.md** — `/data/projects/frankensqlite/COMPREHENSIVE_BREAKDOWN_OF_FRANKENSQLITE_PERFORMANCE_AND_CONFORMANCE_ASSURANCE_PROCESS__CC.md`
  ~5,065 lines, 32 `# PART` headings (Roman-numeral). Authored by Claude Code session traces. Heavy on code excerpts, MEMORY.md citations, and ledger entries.

- **CODEX.md** — `..._CODEX.md`
  ~3,798 lines, 19 numbered sections (Arabic-numeral). Authored by Codex session traces. Heavy on cross-sibling tables, surface architecture, and adoption status.

The two overlap ~70%; CC.md has more code, CODEX.md has more cross-project synthesis. When the table below cites a primary, the other is the cross-check.

---

## How to Read the Bibles Efficiently

You will **not** read either bible cover-to-cover. They're catalogues. Triage thus:

1. **Use the routing table below first.** It indexes by need.
2. **For perf decisions:** start at CC.md PART VII (§37–§43, the keep-gate vocabulary + retry vocabulary) and the negative-results ledger header (lines 479–482).
3. **For conformance decisions:** start at CC.md §2.1–§2.10 (oracle / differential / golden / property / fuzz / crash-recovery), then CC.md §8–§11 for metamorphic, fault, crash-boundary, and e-process machinery.
4. **For surface decisions:** CC.md §25 (FeatureUniverse) plus CODEX.md §16.35 (current-tree parity modules).
5. **For sibling adoption decisions:** CODEX.md §16.26 (cross-sibling tables) and CC.md PART XXIV (§97–§107, adoption status).
6. **For math/theory questions:** CC.md PART XVI (§75–76, mathematical-toolkit catalog).

**Don't grep blindly.** The bibles are catalogues; reading 200 lines around any cited section beats grep-then-jump-around. Open the bible at the section, read the part-header context (2-3 paragraphs above the cited line), then read the cited block.

---

## Routing Table — "If You Need X, Read Y"

### Performance harness anatomy

| Need | Primary | Cross-check | Code file |
|---|---|---|---|
| `comprehensive_bench.rs` 6,040-LOC skeleton | CC.md §1.1 | CODEX.md §1 | `crates/fsqlite-e2e/src/bin/comprehensive_bench.rs` |
| `measure()` body (warmup-2, MIN_ITERS=3, MAX_ITERS=10, TARGET=5s) | CC.md §1.2 lines 49–78 | — | `comprehensive_bench.rs:48–95` |
| `measure_with_teardown()` and the OUTSIDE-the-timed-window rule | CC.md §1.3 lines 70–80 | — | `comprehensive_bench.rs:97–135` |
| Three orthogonal axes (size × shape × concurrency) | CC.md §1.3 | — | `comprehensive_bench.rs:200–280` |
| Identical PRAGMAs block (CC.md note: "30-line block at lines 502–541") | CC.md lines 267–275 + 1278 | — | `comprehensive_bench.rs:502–541` |
| Six weighted scenario categories (sum-to-1.0) | CC.md §1.4 | CODEX.md §5.1 | `comprehensive_bench.rs:600–680` |
| `release-perf` profile (NEVER bare `--release`) | CC.md lines 192–196 | — | `Cargo.toml [profile.release-perf]` |
| JSON v3 self-describing report | CC.md §1.5 | CODEX.md §5.2 | `comprehensive_bench.rs:1500–1750` |
| `concurrent_mode_default_guard.txt` | CC.md §20 | — | dropped per artifact lane |
| Narrow benches: `mt_mvcc_bench.rs` (1,445 LOC) | CC.md §1.1 | CODEX.md §5.3 | `crates/fsqlite-e2e/src/bin/mt_mvcc_bench.rs` |
| Narrow: `mt_oltp_bench.rs` (914 LOC) | CC.md §1.1 | CODEX.md §5.4 | `mt_oltp_bench.rs` |
| Narrow: `perf_update_delete.rs` (1,497 LOC) | CC.md §1.1 | CODEX.md §5.5 | `perf_update_delete.rs` |
| Narrow: `swarm_multiprocess.rs` (79 KB; GitHub #70) | CC.md §16 | — | `swarm_multiprocess.rs` |
| MT8 attribution 0.1% threshold rule | CC.md line 2390, 2393 | — | conceptual |
| Pass-over-pass ratchet (`.bench-history/*.latest.json`) | CC.md §1.9 + §12 | — | `.bench-history/` (committed) |
| Robust regression detection: Median + MAD | CODEX.md §6.3 | — | `crates/fsqlite-harness/src/performance_regression_detector.rs` |
| HotPathProfileSnapshot per-domain counter table | CC.md §23.6 | CODEX.md §6 | `crates/fsqlite-core/src/connection.rs:686–835` |
| `FeatureUniverse` + `InvariantCatalog` | CC.md §25 + §27 | CODEX.md §13 | `crates/fsqlite-harness/src/parity_taxonomy.rs` |
| Algebraically-redundant counter elimination (FSQLITE_SSI_VALIDATIONS_TOTAL: 3.91→1.90 ns/call) | CC.md §55 | — | commit `36504496` |
| Closure-wave pattern | CC.md §28 | — | `crates/fsqlite-harness/src/closure_wave.rs` |
| Verification-contract enforcement (4 states × 4 gates) | CODEX.md §16.6 | — | `verification_contract_enforcement.rs` |
| Proof-pack baseline structure | CC.md §142 | CODEX.md §6.1 | `crates/fsqlite-harness/src/perf_loop.rs` |
| Proof-pack card 19 required fields | CC.md lines 710–713 | — | `perf_loop.rs::ProofPackCard` |

### Conformance machinery (oracle / differential / metamorphic / fault / e-process / Bayesian)

| Need | Primary | Cross-check | Code file |
|---|---|---|---|
| The 30-line `scenario()` template (subject vs oracle parity) | CC.md §3 lines 240–281 | — | `crates/fsqlite-e2e/tests/null_semantics_oracle_e2e.rs` |
| `NormalizedValue::normalize_value()` (NaN, Inf, NULL, float-f64-15-precision) | CC.md §3.1 lines 284–310 | — | `crates/fsqlite-harness/src/oracle.rs` |
| Differential V2 envelope (content-addressed `artifact_id`) | CC.md §2.3 | CODEX.md §5.8 | `crates/fsqlite-harness/src/differential_v2.rs` (bd-1dp9.1.2) |
| `ExecutionEnvelope` struct + canonical-JSON SHA-256 | CC.md §2.3 | — | `differential_v2.rs::ExecutionEnvelope` |
| `EngineIdentity` discriminator (subject ≠ oracle) | CC.md §2.3 + §23.1 | — | `differential_v2.rs::SUBJECT_IDENTITY_LABEL` |
| Metamorphic machinery (TransformFamily, EquivalenceExpectation, MismatchClassification) | CC.md §8.1–§8.4 | CODEX.md §7 | `crates/fsqlite-harness/src/metamorphic.rs` |
| SeedContract (deterministic seed derivation; never `rand::random()`) | CC.md §8.5 | — | `metamorphic.rs::derive_entry_seed` |
| Mismatch minimizer (binary-partition delta-debug + Subsystem attribution + MismatchSignature) | CC.md §29 | — | `crates/fsqlite-harness/src/mismatch_minimizer.rs` (bd-1dp9.2.3) |
| Three-tier equivalence for golden artifacts (Tier1Raw / Tier2Canonical / Tier3Logical) | CODEX.md §5.8 | — | golden artifact tier enum |
| Replay harness with BOCPD regime detection (Regime { Stable, Improving, Regressing, ShiftDetected }) | CC.md §30 | — | `crates/fsqlite-harness/src/replay_harness.rs` (bd-1dp9.2.4) |
| Fault VFS / FaultSpec (FaultKind enum, 8 variants) | CC.md §9.1–§9.4 | — | `crates/fsqlite-harness/src/fault_vfs.rs` (bd-3go.2, 57 KB) |
| F-1..F-8 fault adoption checklist | CC.md §9.4 | — | conceptual |
| Crash-boundary protocol injection (8 named WAL boundaries) | CC.md §10 | — | `crates/fsqlite-wal/src/fault_hooks.rs::CrashBoundary` |
| E-processes (8 monitored MVCC invariants; INV-1..INV-7 + SsiFalsePositiveRate) | CC.md §11 + §20 | — | `crates/fsqlite-harness/src/eprocess.rs` (bd-3go.3, 70 KB) |
| E-process calibration (hardware p₀=1e-9 vs software p₀=1e-6) | CC.md §11.2 | — | `eprocess.rs::MvccInvariant` enum |
| Global e-value as arithmetic mean (regardless of dependence) | CC.md §11.3 | — | `eprocess.rs::global_e_value` |
| Ville's inequality (anytime-valid rejection) | CC.md §11.4 | — | `eprocess.rs::ville_threshold` |
| Bayesian + conformal score engine (BetaParams + conformal bands + truncate_score) | CC.md §14.1–§14.3 + §25 | CODEX.md §8 | `crates/fsqlite-harness/src/score_engine.rs` (bd-1dp9.1.3) |
| Lower-bound for release decisions | CC.md §14.3 | — | `score_engine.rs::release_decision` |
| `truncate_score(x: f64) -> f64` (6 decimal places, cross-platform reproducibility) | CC.md §25 | — | `score_engine.rs::truncate_score` |
| Adversarial search of gates | CC.md §31 | — | `crates/fsqlite-harness/src/adversarial_search.rs` (bd-1dp9.8.5) |
| Drift monitor (passive watcher with e-processes + BOCPD; Info/Warning/Critical) | CC.md §31 | — | `crates/fsqlite-harness/src/drift_monitor.rs` (bd-1dp9.8.2) |
| Oracle preflight doctor | CC.md §137 | — | `crates/fsqlite-harness/src/oracle_preflight_doctor.rs` |
| Fixture root contract | CC.md §138 | — | `crates/fsqlite-harness/src/fixture_root_contract.rs` |
| Failure bundle (`/failure/first_divergence` jsonptr; reproducibility as schema) | CC.md §15 | — | `crates/fsqlite-harness/src/failure_bundle.rs` (bd-mblr.4.4) |
| E2E log schema (logs as API; required fields + replayability keys) | CC.md §17 | — | `crates/fsqlite-harness/src/e2e_log_schema.rs` (bd-1dp9.7.2) |
| First-failure explainer (first_divergence + RootCauseDomain + replay_command + RemediationPlaybook) | CC.md §18 | — | `crates/fsqlite-harness/src/first_failure_explainer.rs` |
| Public-API oracle-parity surface (SQL class behavior list: NULL, 3VL, GROUP BY, recursive CTE, etc.) | CC.md §19 | — | conceptual surface enumeration |

### Keep-gate vocabulary + ledger discipline

| Need | Primary | Cross-check |
|---|---|---|
| Full keep-gate vocabulary (keep gate / within noise / fresh-eyes / scratch worktree / correctness-abandoned / focused-vs-broad / behavior-preserving / selections= / fused-design / DML mutation operator / hot path / cold start / MT8 / micro-lever / frontier / refresh / durable infra / both-gates-same-window / pulled-the-pin) | CC.md PART VII §37 | CODEX.md §16.20–§16.24 |
| 8 retry-condition vocabulary forms (verbatim) | CC.md PART VII §39 | — |
| Ledger entry exemplar (CC.md line 567 — "Reverted — within-noise. Reusing find_rowid_equality_term...") | CC.md line 567 | — |
| 12 implicit ledger anti-patterns | CC.md §40 | — |
| Negative-ledger mandate (the AGENTS.md paragraph) | CODEX.md §10.2 lines 1464–1472 | CC.md opening lines 479–482 |
| Ledger header "This ledger records performance ideas that were measured and rejected" | CC.md lines 479–482 | — |
| Blocked-until-architecture-lands pattern | CC.md §43 line 1921 | — |

### 10 winning optimization patterns (PART XIII)

| Pattern | Primary | Code file | Headline measurement |
|---|---|---|---|
| 1: `try_execute_hot_opcode` | CC.md §53 + §53.1 | `crates/fsqlite-vdbe/src/engine.rs:7818, 12343` | SCopy +38.6%/+37.8%; IfNot +31.5%/+32.7%; IsNull +27.5%/+27.2% |
| 2: AtomicBool gate for O(N) sweep usually O(1) | CC.md §54 | `crates/fsqlite-mvcc/src/published_pages.rs` | PublishedPages::clear 2.92µs→1ns (~2922x); ShardedPageCache::clear 529ns→5ns (~106x); notify_all_waiters 1057.8→8.2 ns (~129x) |
| 3: Algebraically-redundant counter elimination | CC.md §55 | commit `36504496` | FSQLITE_SSI_VALIDATIONS_TOTAL 3.91→1.90 ns/call (~2x) |
| 4: HashSet → sorted Vec + binary_search | CC.md §56 | `crates/fsqlite-mvcc/src/handle_view.rs` | HandleView 1674.8→970.8 ns/build (~1.7x) |
| 5: Bounds-elide via const-array (`as_chunks::<N>`) | CC.md §57 | `crates/fsqlite-btree/src/page_header.rs` | BtreePageHeader::parse 10.7→3.7 ns (~2.9x) |
| 6: Trait-object → match-arm devirtualization | CC.md §58 | commit `0375b55e` | TransactionKind closed 0.36% + 0.29% MT8 self-time |
| 7: Trace-ceremony gated behind `enabled!(LEVEL)` | CC.md §59 | commit `f43902e2`, bd-mziaw | 4-10x oltp_cost |
| 8: Move-not-Clone on probe-builder hot paths | CC.md §60 | commit `b35e1f9c`, bd-4ndk2 | AccessPath MISS path −21.9% |
| 9: OnceLock for one-time-derivable state | CC.md §61 | `crates/fsqlite-vdbe/src/program.rs` | VdbeProgram cached; part of MT 8t 778→5458 (7x) cluster |
| 10: Detect cache-eviction bug (architectural) | CC.md §62 | prepared-statement cache | MT 8t fs_wps 778→5458 (7x); 1t fs_wps 88k→305k (3x+) |
| Bonus: MT8 attribution discipline | CC.md §63 | — | per-frame ≥0.1% candidate; 0.1-1% the productive range |

### Math toolkit + sibling-project tables + adoption status + proprietary skills

| Need | Primary | Cross-check |
|---|---|---|
| §75–76 mathematical-toolkit catalog (32 results) | CC.md PART XVI §§75–76 | — (see [EXEMPLARS.md § D](EXEMPLARS.md)) |
| Sibling-project tables (per-project reference oracle / surface contract / perf matrix / golden / negative-evidence focus) | CODEX.md §16.26 lines 2692–2711 | CC.md §107 |
| Sibling adoption status (cross-sibling maturity matrix) | CC.md PART XXIV §97–§107 | — (see [SIBLING-PROJECTS-STATUS.md](SIBLING-PROJECTS-STATUS.md)) |
| Helper-method enumeration (`/profiling-software-performance`, `/extreme-software-optimization`, `/testing-metamorphic`, etc.) plus advanced-methods mining | CC.md PART XXIII lines 2924–2942 | — |
| Skill→module mapping | CC.md §108 | — |
| Universal floor (what every sibling must have) | CC.md §23.12 lines 1493–1521 | CODEX.md §16 |
| Bootstrapping order (Day 1..Day 60: what to add when) | CC.md §24 lines 1525–1540 | — |

### Specific deep-dives

| Need | Primary |
|---|---|
| Why CASS mining is mandatory pre-flight (the silent-skip failure mode) | CODEX.md §10.2 |
| Why `EngineIdentity` strict-parity matters (oracle-on-oracle false greens) | CC.md §2.3 |
| Why `truncate_score` is needed at all (x86 vs ARM vs WASM LSB divergence) | CC.md §25 |
| Why the `concurrent_mode_default_guard.txt` exists (Feb 2026 silent-disable incident) | CC.md §1.9 |
| Why `WARMUP_ITERS=2` discards cold-start (target/ rebuild dominates first sample) | CC.md §1.2 |
| Why the global e-value uses arithmetic mean not geomean (it's an e-process regardless of dependence) | CC.md §11.3 |
| Why metamorphic relations must include a proof sketch (refactor miscategorization risk) | MINING-1 §10 (sourced from CC.md /testing-metamorphic citation) |
| Why partial bundles still get written on failure (provenance > completeness) | CC.md §15 |
| Why ARC buffer pool (T1/T2/B1/B2) is the canonical buffer-pool design (Megiddo-Modha FAST 2003) | CC.md §75 row 11 |
| Why fault VFS uses deterministic seeds (DEFAULT_FAULT_SEED = 0xD1A6_A3F4_9B17_0C5E) | CC.md §9.3 |
| Why crash boundary 8 (not 4 or 16): one per WAL-protocol commit point | CC.md §10 |

---

## What's NOT in This Skill That IS in the Bibles

This skill captures the *methodology*. The bibles also contain:

- **Implementation details of specific Frankensqlite internals** (page format, WAL frame layout, B-tree cell encoding, MVCC version chain layout, RaptorQ frame structure, ARC parameter tuning history). When porting *to* a sibling project, you don't need these; when *contributing to FrankenSQLite itself*, you do.
- **Project-specific commit history and ledger entries** (the 380-entry negative-results ledger). This skill quotes representative entries; the full ledger is the source of truth for *that* project.
- **Bead history with thousands of beads-IDs** (`bd-XXXX-YY.Z.W`). These are bookkeeping for FrankenSQLite's swarm; the skill mentions a few exemplars but the full graph belongs to the project.
- **Specific GitHub issue numbers and PR threads** (`#70` swarm_multiprocess, etc.). Reference markers only.
- **Per-PR diff hunks and reviewer comments.** Useful for FrankenSQLite archaeology, not for porting the methodology.
- **MEMORY.md citations to specific MT8 attribution wins** (e.g., "Closed 0.44% MT8 PublishedPages::clear residual"). Some are quoted in [EXEMPLARS.md § A](EXEMPLARS.md) as templates; the bulk is bookkeeping.
- **Detailed parser/resolver/planner/VDBE internals.** Each gets a dedicated PART; this skill abstracts to "instrument the hot path".
- **Advanced-methods queue items 1–N with paper citations.** The bibles enumerate the queue.

**Rule of thumb.** If you find yourself asking "what does this specific commit do?" — read CC.md. If you're asking "how does a sibling project adopt this discipline?" — read CODEX.md. If you're asking "what's the methodology?" — read **this skill**.

---

## CC.md Route Index (Selected)

CC.md has 32 current `# PART` headings. This table is a selected routing index for the parts agents use most, not an exhaustive PART listing:

| PART | Topic | Anchor sections |
|---|---|---|
| I | Performance harness anatomy + `measure()` | §1.1–§1.9 |
| II | Narrow benches (`mt_mvcc_bench`, `mt_oltp_bench`, `perf_update_delete`, `swarm_multiprocess`) | §2.1–§2.4 |
| III | MT8 attribution discipline + 0.1% threshold | §3 (incorporating line 2390 and 2393 quotes) |
| IV | Pass-over-pass gate + `.bench-history/*.latest.json` | §4 |
| V | Parity stack: oracle / differential / metamorphic / three-tier equivalence | §7.1–§7.6 |
| VI | Robust regression detection (Median + MAD) | §9 (re `performance_regression_detector.rs`) |
| VII | Keep-gate vocabulary + retry-condition vocabulary + negative-ledger header | §37–§43; line 567 exemplar entry; lines 479–482 |
| VIII | Oracle preflight doctor + fixture root contract | §16.3, §16.4 |
| IX | Fault VFS / FaultSpec / 8 fault kinds | §9.1–§9.4 |
| X | Crash-boundary protocol injection (8 named WAL boundaries) | §10 |
| XI | E-processes + MVCC invariants + Ville's inequality + arithmetic mean | §11, §20 |
| XII | Adversarial search of gates + drift monitor | §12 |
| XIII | Ten winning optimization patterns | §53–§63 |
| XIV | Bayesian + conformal score engine + truncate_score | §14.1–§14.4 |
| XV | Failure bundle + first-failure explainer + e2e log schema | §15–§18 |
| XVI | Mathematical-toolkit catalog (32 results) | §75–§76 |
| XVII | Public-API oracle-parity surface enumeration | §19 |
| XVIII | FeatureUniverse + InvariantCatalog + verification contract | §11 (re `parity_taxonomy.rs`), §13 |
| XIX | Closure-wave pattern | §12 (re `closure_wave.rs`) |
| XX | E-process calibration (hardware vs software) | §11.2 |
| XXI | Per-domain hot-path counter table | §23.6 |
| XXII | Universal floor (what every sibling must have) | §23.12 lines 1493–1521 |
| XXIII | Proprietary skills enumeration + skill→module mapping | lines 2924–2942, §108 |
| XXIV | Sibling-project adoption status | §97–§107 |

The PARTs are not strictly ordered; reading PART VII (keep-gate vocab) before PART XIII (winning patterns) is necessary because the patterns are described *as* keep-gate wins.

---

## CODEX.md Section Index (19 Sections)

| §  | Topic | Cross-check in CC.md |
|---|---|---|
| 1 | Investigation scope | CC.md executive summary |
| 2 | Executive model | CC.md PART I + synthesis sections |
| 3 | Project boundary: current versus aspirational | CC.md caveat / gap sections |
| 4 | Central product invariant | CC.md §19–§21 |
| 5 | Performance measurement architecture | CC.md performance harness anatomy |
| 6 | Profiling and optimization governance | CC.md PART VII + PART XIII |
| 7 | Conformance and golden artifact system | CC.md parity / oracle sections |
| 8 | Certification, scorecards, and release gates | CC.md score / ratchet sections |
| 9 | Artifact bundles and failure bundles | CC.md failure-bundle and first-failure sections |
| 10 | Negative Evidence Ledger | CC.md PART VII + ledger header |
| 11 | Beads graph findings | CC.md bead-linked proof obligations |
| 12 | Git history findings | CC.md artifact-lane and ledger examples |
| 13 | What makes the process reliable | CC.md synthesis sections |
| 14 | Generalized pattern for FrankenRedis | CC.md sibling adoption status |
| 15 | Generalized pattern for FrankenTorch | CC.md sibling adoption status |
| 16 | Expansion addendum: details that make the process work | CC.md universal floor + gap sections |
| 17 | Reusable implementation checklist | CC.md bootstrap / definition-of-done routes |
| 18 | Current caveats | CC.md honest caveat sections |
| 19 | Bottom line | CC.md closing synthesis |

---

## Cross-Bible Discrepancies (When the Two Disagree)

The two bibles overlap heavily but occasionally diverge in framing. When they disagree:

| Topic | CC.md says | CODEX.md says | Resolution |
|---|---|---|---|
| Bootstrapping cadence | Day 1..Day 60 (CC.md §24) | Day-cadence varies per sibling (CODEX.md §18) | Both are right; CC.md is the FrankenSQLite-specific timeline, CODEX.md is per-class. Use CC.md for SQL-class; consult CODEX.md for non-SQL siblings. |
| Number of crash boundaries | 8 WAL boundaries (CC.md §10) | 6 RDB/AOF (CODEX.md §16.26) | Both right per-class. SQL=8, RESP=6+, Torch=5+2, FastAPI=5, NumPy/Pandas=N/A. See [taxonomy/PROJECT-CLASSES.md](../taxonomy/PROJECT-CLASSES.md). |
| Conformance ledger style | "Rejected ideas ledger" (CC.md PART VII) | "DIVERGENCES ledger" (CODEX.md §16.26 table notes for FrankenNumPy) | Both are valid styles. FrankenNumPy chose the divergences framing because divergences ARE the rejected ideas in a numerical-Python port. Other siblings should default to FrankenSQLite's framing. |
| FeatureUniverse weight enforcement | Loader enforces `sum == 1.0` (CC.md §25) | `truncate_score` 6-decimal-places ALSO required (CODEX.md §8) | Both. Sum-to-1 is the structural invariant; truncate_score is the cross-platform-determinism invariant. |
| Math toolkit applicability | All 32 listed apply to FrankenSQLite (CC.md §75) | Many are sibling-specific (CODEX.md §16 expansion addendum) | CC.md lists ALL results across the catalog; CODEX.md notes which are wired in non-SQL siblings (e.g., RaptorQ is FrankenSQLite-and-FrankenNumPy only). |

---

## Quick-Cite Patterns

When citing the bibles in your work:

```
(CC.md §1.2 lines 49–78) — for the measure() body
(CC.md §1.3 line 74) — for "teardown call is OUTSIDE the timed window"
(CC.md §1.9) — for concurrent_mode_default_guard.txt rationale
(CC.md §37) — for keep-gate vocabulary
(CC.md §39) — for retry-condition vocabulary forms 1–8
(CC.md §40) — for 12 implicit-ledger anti-patterns
(CC.md §43 line 1921) — for "blocked-until-architecture-lands" pattern
(CC.md line 479–482) — for the ledger header rule
(CC.md line 567) — for the canonical within-noise ledger entry exemplar
(CC.md line 2390, 2393) — for the 0.1% MT8 attribution threshold + micro-lever trap
(CC.md §53.1) — for try_execute_hot_opcode measurements
(CC.md §54) — for AtomicBool gate pattern (PublishedPages::clear ~2922x)
(CC.md §55) — for algebraically-redundant counter elimination (SSI_VALIDATIONS_TOTAL)
(CC.md §56) — for HashSet → sorted Vec (HandleView 1.7x)
(CC.md §57) — for as_chunks::<N> bounds-elide (BtreePageHeader 2.9x)
(CC.md §58) — for trait-object → match devirtualization (TransactionKind)
(CC.md §59) — for tracing::enabled!() gating (4-10x oltp_cost)
(CC.md §60) — for move-not-clone (AccessPath MISS −21.9%)
(CC.md §61) — for OnceLock (VdbeProgram, contributed to 7x cluster)
(CC.md §62) — for cache-eviction bug detection (prepared-stmt 778→5458)
(CC.md §63) — for MT8 attribution discipline
(CC.md §75) — for 32-result math toolkit
(CC.md §23.6) — for HotPathProfileSnapshot per-domain table
(CC.md §23.12 lines 1493–1521) — for the universal floor
(CC.md §24 lines 1525–1540) — for the Day 1..Day 60 bootstrapping order
(CODEX.md §10.2 lines 1464–1472) — for the AGENTS.md mandate paragraph
(CODEX.md §16.26 lines 2692–2711) — for the sibling-project tables
(CC.md PART XXIV §97–§107) — for sibling adoption status
```

---

## Frequent "Where Is X?" Lookups

The following questions come up often enough to deserve named answers:

**Q: Where is the `measure()` function definition?**
A: CC.md §1.2 lines 49–78. File: `crates/fsqlite-e2e/src/bin/comprehensive_bench.rs:48–95`.

**Q: Where is the rule about teardown outside the timed window?**
A: CC.md §1.3 line 74. Quote: *"The teardown call is *outside* the timed window — `start.elapsed()` is captured *before* `teardown()` runs."*

**Q: Where is the `release-perf` profile defined?**
A: CC.md §1.7 lines 192–196. File: project's `Cargo.toml` `[profile.release-perf]` section.

**Q: Where are the six weighted scenario categories enumerated?**
A: CC.md §1.6. ReadSingle 0.35 / ReadAggregate 0.15 / WriteSingle 0.30 / WriteBulk 0.10 / ConcurrentWriters 0.05 / MixedOltp 0.05.

**Q: Where is the JSON v3 schema spec?**
A: CC.md §1.8, with cross-check at CODEX.md §2.

**Q: Where is the `concurrent_mode_default_guard.txt` rationale (the Feb 2026 incident)?**
A: CC.md §1.9.

**Q: Where is the 30-line scenario template?**
A: CC.md §3 lines 240–281. File: `crates/fsqlite-e2e/tests/null_semantics_oracle_e2e.rs` (representative).

**Q: Where is `NormalizedValue::normalize_value()`?**
A: CC.md §3.1 lines 284–310. File: `crates/fsqlite-harness/src/oracle.rs`.

**Q: Where is the Differential V2 `ExecutionEnvelope` + `artifact_id`?**
A: CC.md §2.3. File: `crates/fsqlite-harness/src/differential_v2.rs`.

**Q: Where are the `EngineIdentity` constants?**
A: CC.md §2.3. File: `differential_v2.rs::SUBJECT_IDENTITY_LABEL` (= "frankensqlite") and `REFERENCE_IDENTITY_LABEL` (= "csqlite-oracle").

**Q: Where is the metamorphic `TransformFamily` enum?**
A: CC.md §8.1. File: `crates/fsqlite-harness/src/metamorphic.rs`.

**Q: Where is the three-tier equivalence enum?**
A: CODEX.md §5.8. EquivalenceTier { Tier1Raw, Tier2Canonical, Tier3Logical }.

**Q: Where is the mismatch minimizer (delta-debug binary partition)?**
A: CC.md §29. File: `crates/fsqlite-harness/src/mismatch_minimizer.rs`.

**Q: Where is the fault VFS `FaultKind` enum?**
A: CC.md §9.1. File: `crates/fsqlite-harness/src/fault_vfs.rs`.

**Q: Where is the 8-boundary `CrashBoundary` enum?**
A: CC.md §10. File: `crates/fsqlite-wal/src/fault_hooks.rs::CrashBoundary`.

**Q: Where is the `MvccInvariant` enum + e-process calibration table?**
A: CC.md §11, §11.2. File: `crates/fsqlite-harness/src/eprocess.rs`.

**Q: Where is Ville's-inequality anytime-valid rejection logic?**
A: CC.md §11.4 (and §75 row 1). File: `eprocess.rs::ville_threshold`.

**Q: Where is `truncate_score` and why (the LSB divergence rationale)?**
A: CC.md §25. File: `crates/fsqlite-harness/src/score_engine.rs::truncate_score`.

**Q: Where is the `FailureBundle` struct + `/failure/first_divergence` jsonptr?**
A: CC.md §15. File: `crates/fsqlite-harness/src/failure_bundle.rs`.

**Q: Where is the e2e log schema (REQUIRED_EVENT_FIELDS, REPLAYABILITY_KEYS)?**
A: CC.md §17. File: `crates/fsqlite-harness/src/e2e_log_schema.rs`.

**Q: Where is `FirstFailureExplainer`?**
A: CC.md §18. File: `crates/fsqlite-harness/src/first_failure_explainer.rs`.

**Q: Where is the oracle preflight doctor?**
A: CC.md §137. File: `crates/fsqlite-harness/src/oracle_preflight_doctor.rs`.

**Q: Where is the FeatureUniverse + sum-to-1 weight invariant?**
A: CC.md §25 (re `parity_taxonomy.rs`), CODEX.md §13. Three load-bearing invariants in MINING-3 §11.

**Q: Where is the closure-wave pattern?**
A: CC.md §28. File: `crates/fsqlite-harness/src/closure_wave.rs`. Currently covers Parser / Resolver / Pragma.

**Q: Where is the verification-contract enforcement table (4 status × 4 gates)?**
A: CODEX.md §16.6.

---

**End of BIBLE routing.** Skill text should cite either the routing entry above OR the section in the bibles directly; never both (the routing exists to map need→section, not to be re-cited).
