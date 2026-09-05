# Case Study: FrankenSQLite — `/dp/frankensqlite`

The reference adoption. Every other case study compares its current state to FrankenSQLite's; this one describes what *holding the gauntlet line* looks like once the discipline is fully landed.

---

## 1. Snapshot

| Field | Value |
|---|---|
| **Class** | SQL-class (`PROJECT-CLASSES.md § SQL-Class`) |
| **Tier** | **T4 — Platform** (per [TIER-TRIAGE.md](../methodology/TIER-TRIAGE.md)); ~200k+ LOC, multiple crates (`fsqlite-btree`, `fsqlite-vdbe`, `fsqlite-wal`, `fsqlite-mvcc`, `fsqlite-harness`, `fsqlite-e2e`, …) |
| **Recommended mode** | `gauntlet-full` for fresh evaluations; `incremental-rebase` for ongoing maintenance; `compliance-pass` for auditor re-certification against a moved C SQLite version; `red-team` for adversarial-only sweeps against new gates |
| **Reference pinning** | `docs/contracts/csqlite_version_contract.toml`, currently `sqlite-3.52.0`; preflight doctor verifies version string from `SELECT sqlite_version()`. Pin advances only via the `migration` mode. |
| **README claims summary** | "FrankenSQLite is a Rust re-implementation of SQLite aiming for byte-for-byte SQL-level parity with C SQLite, faster on the MT-MVCC workload, with WAL self-healing via RaptorQ." All three claims gated: parity by `differential_v2`, perf by `mt-mvcc-bench`, WAL FEC by `wal-fec` corpus. |

The FrankenSQLite repo is itself the *source corpus* the rest of this skill mines. See `crates/fsqlite-harness/src/{oracle,differential_v2,metamorphic,mismatch_minimizer,fault_vfs,eprocess,score_engine,replay_harness,drift_monitor,adversarial_search,failure_bundle,e2e_log_schema,first_failure_explainer,oracle_preflight_doctor,fixture_root_contract,parity_taxonomy,closure_wave,performance_regression_detector}.rs`.

---

## 2. Adoption Matrix

| Pillar / Discipline | Status | Notes |
|---|:---:|---|
| Conformance (oracle/differential V2) | ✅ | `crates/fsqlite-harness/src/differential_v2.rs` (202+ LOC, bd-1dp9.1.2); `EngineIdentity` discriminator enforced |
| Negative ledger | ✅ | **380 entries** in `docs/progress/perf-negative-results.md`; retry-condition predicates per entry |
| cass (60-day session mining) | ✅ | `scripts/mine-cass-cross-machine.sh` covers local + css + csd + ts1 + ts2 |
| Agent Mail | ✅ | Per-bead thread IDs `gauntlet-<run-id>-<phase>-<bucket>`; reservations on `tool://comprehensive-bench`, `tool://oracle-runner`, `resource://rch-worker-pool` |
| bv (bead visualization) | ✅ | `bv --robot-insights | jq '(.Cycles // []) | length == 0'` passes in every CI pass |
| Math layer (§75–76) | ✅ full | Ville's-inequality e-process, conformal bands, BOCPD, Beta posteriors, ARC buffer pool, RaptorQ all wired |
| MT-scale harness | ✅ | `mt-mvcc-bench --threads=8 --rows-per-thread=1000 --iters=3` is the canonical concurrency stress |
| RaptorQ WAL FEC | ✅ | `crates/fsqlite-wal/src/fec/` (RFC 6330 implementation) |
| Crash-boundary coverage | ✅ | 8 of 8 named boundaries instrumented (`BeforeWalHeaderWrite` → `AfterCheckpoint`) |
| Closure-wave domains | ⚠️ partial | **3 of 8+ domains** instrumented (Parser, Resolver, Pragma); missing Planner, VDBE, Storage, WAL, MVCC, Functions, Extension, TypeSystem |
| Frontier-math backlog | ⚠️ partial | P1, P3, P9, P10, P11, P12 landed; P2 Azuma / P4 Nemhauser / P5 PAC-Bayes / P6 Little's-Law-MPC / P7 Lai-Robbins / P8 renewal-reward still **proposals** |
| Adversarial-search auto-gen | ⚠️ manual | `adversarial_search.rs` covers existing gates; new-gate enrollment is human-driven |

Legend: ✅ full • ⚠️ partial • ❌ absent

---

## 3. Per-Pillar Deep Dive

### (a) Performance — current state + first 3 gaps the gauntlet would surface

**Current state.** Mature. `comprehensive_bench.rs` at 6,040 LOC implements six weighted scenario categories (`ReadSingle 0.35 / ReadAggregate 0.15 / WriteSingle 0.30 / WriteBulk 0.10 / ConcurrentWriters 0.05 / MixedOltp 0.05`). `release-perf` profile (LTO=thin, codegen-units=1, force-frame-pointers=yes) is the only profile used. `.bench-history/{comprehensive-bench,mt-mvcc-bench,mt-mvcc-bench.separate-tables}.latest.json` are committed. Pass-over-pass gate is a file. MT8 attribution is the canonical perf-evidence anchor: every kept win cites a specific frame ≥0.1% self-time. `cv_pct` reported per microbench; >5% disqualifies.

**First 3 gaps the gauntlet would surface in round 1:**
1. **VDBE opcode counter rot.** New opcodes have been added since the per-opcode hot-path counter table was last fully audited; a profile-card sweep would identify ≥3 new opcodes without coverage. Closure-wave for VDBE domain currently absent.
2. **`page_buffer_pool_{hits,misses}` decay during long-running connections.** The cache-key fix from CC.md §62 (prepared-statement cache: bytecode-cache key schema-bound vs data-cache key generation-bound) may have introduced subtle cache-key shadowing on the long-lived connection path; would surface as a slow drift on the >100k-iter MT8 run.
3. **`commit_finalize_seq_time_ns` non-stationarity under 16-writer load.** MT16 is not the canonical anchor; the existing MT8 attribution probably misses a sub-0.5% frame that only saturates at 16 writers — the retry predicate "MT16 shared-table ratio crosses 5x" was specifically authored to catch this.

### (b) Conformance — current state + first 3 gaps

**Current state.** Best-in-class. `differential_v2.rs` envelope with `artifact_id = SHA-256` of canonical JSON excluding `run_id`. 4 metamorphic transform families (Predicate/Projection/Structural/Literal). 8 named crash boundaries with `arm_crash_boundary` + recovery + consistency assertions. INV-1..INV-7 + INV-SSI-FP e-process invariants with hardware-enforced `p₀=1e-9, λ=0.999, α=1e-6` (CAS-backed invariants) vs software-enforced `p₀=1e-6, λ=0.9, α=0.001` (logical invariants). BOCPD with H=1/250 for regime detection.

**First 3 gaps the gauntlet would surface:**
1. **INV-WAL-Recovery-Determinism not enumerated.** Recovery from `BetweenPageTableRebuildSteps` produces the same final state across `DEFAULT_FAULT_SEED` replays — but this is asserted at the test-case level, not as a global e-process invariant. A drift in WAL-recovery determinism would not light up the global e-value.
2. **Metamorphic relations weighted toward `Predicate` and `Projection`.** The `Structural` family (subquery wrapping, INTERSECT) and `Literal` family (CAST round-trip) have ~30% fewer relations enumerated. First-pass mutation testing on `Structural` would likely surface 1-2 actionable `TrueDivergence` cases.
3. **`MismatchClassification::FalsePositive { reason }` not audited for 90+ days.** False-positive classifications accumulate; without a periodic FP-audit pass, a true bug could be hiding behind a stale FP justification.

### (c) Surface — current state + first 3 gaps

**Current state.** Strong. `parity_taxonomy.rs` + `feature_coverage_dashboard.rs` + `invariant_catalog.rs` give per-Feature `present|partial|missing|n/a|excluded` accounting. `FeatureUniverse` weight invariant `sum(weights) == 1.0 per category` enforced at load. Excluded items still count as coverage debt for a strict-100% claim.

**First 3 gaps:**
1. **PRAGMA introspection drift between `3.52.0` and the build's actual rusqlite link.** `PRAGMA function_list`, `PRAGMA compile_options`, `PRAGMA module_list` differ across SQLite compile-time flags; the FeatureUniverse needs a per-compile-flag axis it doesn't currently have.
2. **Extension surface (`crates/fsqlite-extension/`) not in the FeatureUniverse weight table.** Extensions are tagged `excluded` collectively rather than enumerated; a `strict-100%` claim is hollow on this dimension.
3. **Generated columns + virtual tables — partial coverage classified as `present`.** Several edge cases (e.g., `STORED` vs `VIRTUAL` re-computation policy on UPDATE of source columns) are partial-present and should be `partial`.

---

## 4. First-Pass Recipe (Orchestrator-Issued)

```bash
SKILL_ROOT="${GAUNTLET_SKILL_ROOT:-$HOME/.claude/skills/running-the-gauntlet-on-your-rust-port}"
[ -d "$SKILL_ROOT" ] || SKILL_ROOT="$HOME/.codex/skills/running-the-gauntlet-on-your-rust-port"

"$SKILL_ROOT/scripts/kickoff.sh" gauntlet-full
"$SKILL_ROOT/scripts/gauntlet.sh" /dp/frankensqlite /dp/frankensqlite__gauntlet_workspace \
  --mode gauntlet-full --dry-run

# Phase-specific inputs for the orchestrator/subagents:
# - reference pin: sqlite-3.52.0
# - oracle mode: in-process rusqlite via libsqlite3-sys
# - full rch offload required for Phase 9 baseline, Phase 11 iteration, and Phase 15 soak
# - Phase 14: keep looping until two clean fresh-eyes rounds

"$SKILL_ROOT/scripts/gauntlet.sh" /dp/frankensqlite /dp/frankensqlite__gauntlet_workspace \
  --mode gauntlet-full --soak-hours 120
```

Expected wall time T4 × `gauntlet-full`: **30–45 days.** `rch` offload mandatory. Multi-model triangulation mandatory on Phase 14. Certification bundle required.

---

## 5. Expected Pillar Findings (Top 5-10 per Pillar)

### Performance
1. **VDBE opcode without `try_execute_hot_opcode` promotion** — at least one opcode firing ≥50% in inner loop, eligible for [pattern:200-HOT-OPCODE-PROMOTION](../patterns/200-HOT-OPCODE-PROMOTION.md).
2. **`PublishedPages::clear` residual** — sub-0.5% MT8 frame; AtomicBool gate covers the obvious case but a sibling clear path may not have the gate yet.
3. **Algebraic-redundant counter survives `score_engine.rs`** — pattern 3 (`FSQLITE_SSI_VALIDATIONS_TOTAL` lesson) applies again somewhere — likely a per-shard counter that aggregates from per-bucket counters.
4. **HashSet in `summarize_*_keys()`** — pattern 4 lesson — newer code may re-introduce HashSet for ≤100-element membership queries.
5. **BlobReader bounds-check** — pattern 5 lesson — a new BLOB I/O path may parse byte-by-byte with `chunks_exact()` rather than `as_chunks::<N>()`.
6. **Trait-object dispatch frame ≥0.1%** — pattern 6 lesson — a new VFS-trait method or new `TransactionKind` variant could re-introduce devirtualization headroom.
7. **`env::var` inside trace ceremony** — pattern 7 lesson — Planner perf 2026-05-20 was once; a fresh occurrence is plausible.
8. **`.clone()` on probe builder** — pattern 8 lesson — every new probe-builder hot path is a candidate.
9. **`OnceLock`-eligible derivation recomputed per call** — pattern 9 lesson — every new "compile-once, use-many" surface is a candidate.
10. **Cache-key shadowing on prepared-statement cache** — pattern 10 lesson — every new cache-key needs the eviction-input-graph audit.

### Conformance
1. **PRAGMA result-row drift** between rusqlite and fsqlite for `PRAGMA compile_options` if compile flags differ.
2. **`recursive_cte` termination edge** — `WITH RECURSIVE` with `LIMIT 0` semantics differ if termination check is post-LIMIT.
3. **Three-valued logic in `NOT IN (subquery_with_NULL)`** — SQLite-specific: `NOT IN` against a subquery containing NULL is always `NULL`; first-pass differential will catch any divergence.
4. **`GROUP BY` collation on TEXT columns** — `BINARY` vs `NOCASE` vs `RTRIM` ordering can drift.
5. **`ATTACH`-then-rename-source semantics** — `ALTER TABLE rename` propagation across attached databases is a known edge.
6. **`WAL recovery` after `BetweenPageTableRebuildSteps` crash** — first-pass fault-VFS run will likely surface one new boundary case if the recovery state-machine has changed.
7. **JSON1 `json_extract` NULL behavior on missing path** — extension-class divergence.
8. **`DEFAULT CURRENT_TIMESTAMP` precision** — fractional seconds differ.

### Surface
1. **Missing PRAGMA from FeatureUniverse** — at least one PRAGMA introduced in a 3.5x release not enumerated.
2. **`STRICT` table semantics partial-present** — strict-type-affinity edges underspecified.
3. **`UNIQUE` constraint on `WITHOUT ROWID` table** — a corner case present in C SQLite, marked `partial` in FrankenSQLite.
4. **Generated column re-computation policy** — `STORED` recomputed on UPDATE-of-source-column is a subtle present/partial line.
5. **Window function `RANGE BETWEEN INTERVAL` frame spec** — likely `excluded` but counts as coverage debt for strict-100%.

---

## 6. Project-Specific Patterns to Apply First

1. **[pattern:115-CLOSURE-WAVE](../patterns/115-CLOSURE-WAVE.md)** — expand from 3 domains to 8+ (Planner, VDBE, Storage, WAL, MVCC, Functions, Extension, TypeSystem); largest single conformance-pillar headroom.
2. **[pattern:160-MT8-ATTRIBUTION](../patterns/160-MT8-ATTRIBUTION.md)** — add MT16 attribution as a sibling profile; some sub-frame regressions only saturate at 16 writers.
3. **[pattern:200-HOT-OPCODE-PROMOTION](../patterns/200-HOT-OPCODE-PROMOTION.md)** — re-audit every VDBE opcode for inner-loop coverage; new opcodes likely added since last sweep.
4. **[pattern:245-CACHE-KEY-EVICTION-AUDIT](../patterns/245-CACHE-KEY-EVICTION-AUDIT.md)** — every new cache (e.g., extension-registry cache) gets the eviction-input-graph audit.
5. **[pattern:70-E-PROCESSES](../patterns/70-E-PROCESSES.md)** — add INV-WAL-Recovery-Determinism + INV-MVCC-VersionChainConsistency to the monitored set; current 8-invariant set is a floor, not a ceiling.

---

## 7. Estimated Rounds to Convergence

**12–18 rounds.** The 10-round minimum is met early; subsequent rounds surface diminishing-but-still-genuine findings because the codebase is large enough that idea-wizard + closure-wave keep producing candidates well past round 10. Two consecutive clean rounds usually arrive between rounds 14 and 17.

---

## 8. Risk Register

1. **Frontier-math backlog (P2/P4/P5/P6/P7/P8) drains agent attention without landing.** Each is an EV decision: P2 Azuma's inequality on bounded-difference martingale concentration may be high-leverage; P6 Little's Law + MPC may be a research distraction. *Mitigation:* triage each via the `EV-justified` predicate in [pattern:185-RETRY-CONDITION-PREDICATE](../patterns/185-RETRY-CONDITION-PREDICATE.md) and ledger the rest with explicit "Not worth retrying as a standalone patch."
2. **MT8 attribution saturates → micro-lever trap.** As the easy ≥0.1% frames close out, the residual is sub-0.1%; agent attention shifts to micro-levers below the keep gate. *Mitigation:* enforce the "Closed N% MT8 attribution" citation requirement; reject any kept perf change that doesn't quote a specific frame.
3. **Reference C SQLite version bump (3.52.0 → 3.53.x) lands during a run.** Invalidates pinned golden artifacts. *Mitigation:* `migration` mode is the only way to bump; never bump mid-run.

---

## 9. What Ships from Convergence

A `certification_bundle/` containing:

- `confidence_gate.json` — Beta posterior + conformal lower bound per category; release uses LOWER bound.
- `verification_contract.json` — `pass | fail-missing-evidence | fail-invalid-references | fail-mixed` matrix.
- `release_certificate.json` — strict-conformant-release.v1; embeds `csqlite_version_contract.toml` SHA-256.
- `ci_artifact_manifest.json` — every per-Phase artifact path + SHA-256.
- `benchmark_summary.json` — `.bench-history/{comprehensive-bench,mt-mvcc-bench,mt-mvcc-bench.separate-tables}.latest.json` snapshots.
- `scorecards.json` — per-Feature Pass/Partial/Missing/Excluded.
- `critical_path_report.json` — bead-graph critical path; `br dep cycles` empty.
- `ratchet_state.json` — current conformal lower bound.

Plus `FINAL_GAUNTLET_REPORT.md`, `PARITY_RUNBOOK.md`, `RELEASE_CERTIFICATION_TEMPLATE.md` triple, and a polished bead graph where every remediation bead has a test-bead + benchmark-bead + documentation-bead dependency.

---

## Cross-references

- [SIBLING-PROJECTS-STATUS.md § FrankenSQLite](../exemplars/SIBLING-PROJECTS-STATUS.md) — current adoption truth
- [PROJECT-CLASSES.md § SQL-Class](../taxonomy/PROJECT-CLASSES.md) — class wiring
- [methodology/CASE-STUDIES.md](../methodology/CASE-STUDIES.md) — short calibration view
- [methodology/CONVERGENCE.md](../methodology/CONVERGENCE.md) — convergence math
