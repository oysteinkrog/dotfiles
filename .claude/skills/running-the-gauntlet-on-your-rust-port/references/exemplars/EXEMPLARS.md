# EXEMPLARS — Quote Bank, Rituals, Verbatim Prompts, Math Toolkit, Perf Vocabulary

> The "operationalizing-expertise" companion. Every anchor here is grep-able from the FrankenSQLite bibles; every ritual is a literal command sequence; every prompt is byte-identical to what's in the parent SKILL.md.

---

## A. Quote Bank

Anchors are stable; cite as `[Q-NNN]` in skill text. Sources: `CC.md` = `/data/projects/frankensqlite/COMPREHENSIVE_BREAKDOWN_OF_FRANKENSQLITE_PERFORMANCE_AND_CONFORMANCE_ASSURANCE_PROCESS__CC.md`; `CODEX.md` = `..._CODEX.md`.

---

**[Q-001] Negative-ledger opening rule.** *"This ledger records performance ideas that were measured and rejected. Check it before starting a new optimization pass, and add an entry whenever a candidate is abandoned, reverted, or kept out of the tree because the benchmark matrix did not move in the intended direction."*
Source: CC.md opening, lines 479–482. Use-as: AGENTS.md mandate paragraph; ledger header.

**[Q-002] CASS mining mandate.** *"For major perf campaigns, agents must also mine: last 60 days of CASS session history, recent commits, perf artifacts, failed/rejected/slower/regressed terms. If CASS or the ledger is unavailable or reserved, the agent must record a blocker or patch-ready entry rather than silently skipping the step."*
Source: CODEX.md §10.2, lines 1464–1472. Use-as: pre-flight enforcement; `scripts/mine-ledger.sh`.

**[Q-003] Teardown discipline.** *"The teardown call is *outside* the timed window — `start.elapsed()` is captured *before* `teardown()` runs."*
Source: CC.md §1.3, line 74. Use-as: bench-author validator; anti-pattern A23.

**[Q-004] Profile-first contract.** *"No code-changing performance bead starts without measured hotspot evidence, an EV-scored recommendation card, a one-lever scope, and a proof pack."*
Source: CC.md lines 710–713. Use-as: proof-pack gate.

**[Q-005] Within-noise rejection (exemplar ledger entry).** *"Reverted — within-noise. Reusing find_rowid_equality_term for the RowidLookup probe (vs 2nd scan in extract_access_path_probe) was behavior-preserving (identical selection counts; 13 probe/21 rowid/35 access_path tests pass) but point-lookup gain ~2% sits in the ±3-5% bench noise band."*
Source: CC.md line 567. Use-as: model retry-condition vocabulary form 1.

**[Q-006] Micro-lever trap.** *"A frame at 0.05% is below the noise floor of the bench (cv_pct 3-5%); the **micro-lever trap**. A frame at 1% is rare and high-value. The 0.1-1% range is where productive optimization work happens."*
Source: CC.md line 2393. Use-as: MT8 attribution threshold rule.

**[Q-007] MT8 0.1% threshold.** *"Each frame ≥0.1% is a *candidate*."*
Source: CC.md line 2390. Use-as: proof-pack scorer cutoff.

**[Q-008] Closed-residual citation template.** *"Closed 0.44% MT8 PublishedPages::clear residual."* / *"Closed 0.63% MT8 inclusive self-time."* / *"Closed 0.51% MT8 self-time symbol."*
Source: CC.md MEMORY.md citations (§63). Use-as: keep-entry vocabulary; commit-message style.

**[Q-009] Honesty in the harness (paraphrased kernel).** *"Honesty is encoded in the harness, not in the reviewer. Every claim — perf ratio, conformance pass rate, surface coverage — must survive a hostile reading of its own artifacts."*
Source: parent SKILL.md opening. Use-as: kernel axiom.

**[Q-010] Pass-over-pass is a file.** *"Pass-over-pass gate is a *file*. `.bench-history/*.latest.json` is committed. You can't bench on your machine, see a 30% drop, and quietly not commit."*
Source: MINING-3 §4 (extracted from CC.md). Use-as: anti-pattern A21 fix.

**[Q-011] Both gates same window.** *"Both gates must move in the same run window — same git state, same `target/`, same machine, same minute."*
Source: CC.md §37. Use-as: keep-gate hard rule.

**[Q-012] Failure-bundle provenance.** *"A partial bundle with provenance is more valuable than no bundle. Never skip manifest writing on failure."*
Source: CC.md §15 (re failure_bundle.rs). Use-as: failure-bundle-author training prompt.

**[Q-013] First-divergence rule.** *"The pointer at `/failure/first_divergence` jumps to byte-offset where engines first disagreed, not to 'test X failed somewhere'."*
Source: CC.md §15. Use-as: first-failure explainer spec.

**[Q-014] Closure-wave principle.** *"You don't write tests for what you remember to write tests for; you enumerate the universe of behaviors, *then* observe which the engine handles."*
Source: CC.md (closure_wave.rs prelude). Use-as: surface-archaeology framing.

**[Q-015] FeatureUniverse SHA-256 chain.** *"The catalog doesn't just say 'we tested X', it says 'we tested X, the evidence is at path P with SHA-256 H against schema version V'. A release that ships the catalog ships the proof-of-work."*
Source: MINING-3 §11. Use-as: invariant-catalog-author training prompt.

**[Q-016] Three-tier equivalence rule.** *"Encode the distinction; never paper over it."*
Source: CODEX.md §5.8. Use-as: Tier 1/2/3 golden-artifact discipline.

**[Q-017] Identical PRAGMAs.** *"Both engines get identical PRAGMAs. This is a 30-line block at `comprehensive_bench.rs:502–541`, not a verbal convention."*
Source: CC.md lines 267–275, 1278. Use-as: keep-gate rule; identical-config requirement.

**[Q-018] Adversarial search threat model.** *"An agent honest enough to write the gate is biased toward making it pass. Adversarial search is the defense."*
Source: CC.md §12 (re adversarial_search.rs). Use-as: Phase 15 soak prompt.

**[Q-019] E-process Ville rejection.** *"P_{H_0}(∃t: E_t ≥ 1/α) ≤ α. Anytime-valid: check after every operation, reject when crosses `1/α`, **no Bonferroni correction needed**."*
Source: MINING-2 §10. Use-as: invariant-monitor spec.

**[Q-020] Conformal lower-bound rule.** *"P(R_{n+1} ≤ q) ≥ 1 − α for any distribution. Cost: wider intervals. Benefit: honest under heavy-tailed / bimodal / regime-shifting distributions."*
Source: MINING-2 §11 (re conformal bands). Use-as: release-decision math.

**[Q-021] truncate_score rationale.** *"x86 vs ARM vs WASM differ at LSB; truncation ensures bytewise identical scores regardless of CPU."*
Source: CC.md (score_engine.rs prelude). Use-as: cross-platform reproducibility.

**[Q-022] Both-error agreement rule.** *"Both-error = agreement (message text irrelevant). One-error-one-OK = hard failure."*
Source: MINING-2 §1. Use-as: scenario template critical rule.

**[Q-023] EngineIdentity strict-parity guard.** *"`subject_identity == 'frankensqlite'` and `reference_identity == 'csqlite-oracle'`. Enforced at harness entry; prevents oracle-on-oracle false greens."*
Source: MINING-2 §3. Use-as: oracle preflight doctor.

**[Q-024] Cache-eviction bug rule.** *"For every cache key, list which inputs it depends on; for every cache invalidation, list which inputs should invalidate it; gap = bug."*
Source: CC.md §62. Use-as: cache-design audit prompt.

**[Q-025] Algebraic counter elimination.** *"When adding counter, ask 'is this algebraically derivable from existing counters?' If yes, derive at read time."*
Source: MINING-3 §7. Use-as: counter-design audit.

**[Q-026] AtomicBool gate subtlety.** *"Flag is allowed false positive but *never* false negative. Set flag *before* publishing, clear *after* sweeping."*
Source: MINING-1 §4 Pattern 2. Use-as: AtomicBool-gate review checklist.

**[Q-027] Mauboussin process vs outcome.** *"Good outcome + bad process = rejected."*
Source: MINING-1 §7 row 32 (re Mauboussin 2012). Use-as: keep-gate philosophy underlying axiom.

**[Q-028] Logs as API.** *"Not free text for humans; machine-consumable trace future agents parse to compute coverage and bisect regressions."*
Source: MINING-2 §16. Use-as: e2e log schema spec.

**[Q-029] SeedContract rule.** *"Never `rand::random()`. Same input → same seed → same SQL → same bugs found."*
Source: MINING-2 §4. Use-as: corpus-generator review checklist.

**[Q-030] cv_pct noise floor.** *"Every microbench result reports the coefficient of variation; if `cv_pct > 5`, the result is noise and not eligible for keep."*
Source: parent SKILL.md keep-gate row. Use-as: bench JSON v3 schema requirement.

---

## B. Rituals (Recurring Agent Behaviors)

Each ritual is a literal command sequence. Run in order; don't skip.

### Ritual R1: "Read ledger first" (pre-flight on every perf bead)

```bash
# 1. Local ledger sweep
rg -n --color=never \
   "rejected|reverted|abandoned|slower|regressed|didn't help|within noise|no improvement|failed to improve|rolled back|backed out|not a keep|keep gate" \
   docs/progress/perf-negative-results.md

# 2. Cross-machine cass mining (60-day window)
./scripts/mine-cass-cross-machine.sh \
   --window 60d \
   --terms "rejected reverted abandoned slower regressed within-noise" \
   --hostname-set "local,css,csd,ts1,ts2" \
   --output reports/pre-flight-cass-mining.json

# 3. Recent commit grep (last 90 days)
git log --since="90 days ago" --all --grep='revert\|within.*noise\|no.*improvement\|backed.*out' \
   --pretty=format:'%h %s'
```

If any output overlaps the proposed hotspot, the candidate is **blocked** until the existing rejection is read and a delta-rationale is written.

### Ritual R2: "Grep cass for failure terms" (Phase 8 ledger seeding)

```bash
timeout 30s cass search "(rejected OR reverted OR abandoned OR slower OR regressed OR \"didn't help\" OR \"within noise\" OR \"no improvement\" OR \"failed to improve\" OR \"rolled back\" OR \"backed out\" OR \"not a keep\" OR \"keep gate\")" \
   --robot-format jsonl --days 60 --limit 200 --mode lexical --timeout 30000 > workspace/phase8_cass_findings.jsonl

# Then bucket per pillar
jq -r 'select(.body | test("perf|bench|throughput|latency")) | @json' \
   workspace/phase8_cass_findings.jsonl \
   > workspace/phase8_perf_candidates.jsonl
```

### Ritual R3: "Check recent commits" (before any source change)

```bash
git log --since="30 days ago" --all --first-parent \
   --pretty=format:'%h %an %s' \
   -- <touched-path>

# Surface anyone who edited this file recently → coordinate via Agent Mail
```

### Ritual R4: "Profile before code"

```bash
# 1. Baseline build under release-perf
cargo build --profile release-perf --bin comprehensive-bench

# 2. Flamegraph on the canonical concurrent workload
cargo flamegraph --profile release-perf --bin mt-mvcc-bench -- \
   --threads=8 --rows-per-thread=1000 --iters=3

# 3. Samply JSON for self-time table
samply record --output artifacts/<bead_id>/proof_pack/candidate_profile.samply.json \
   ./target/release-perf/mt-mvcc-bench --threads=8 --rows-per-thread=1000

# 4. Extract top-10 ≥0.1% self-time frames
samply query --self-time-min 0.001 \
   artifacts/<bead_id>/proof_pack/candidate_profile.samply.json \
   > artifacts/<bead_id>/proof_pack/hotspot_rank.txt
```

No flamegraph, no bead.

### Ritual R5: "Write the keep entry"

Every retired candidate — kept *or* rejected — gets a ledger entry. Template:

```
## YYYY-MM-DD bd-XXXX  <one-line summary>
**Status:** kept | rejected | pulled | correctness-abandoned | within-noise | refresh | durable-infra
**Scratch worktree:** /data/tmp/<project>-<feature>-<timestamp>
**Hotspot evidence:** artifacts/{bead_id}/proof_pack/baseline_profile.flame.svg
**Measurement:** focused <metric> <before> → <after>, broad primary score <before> → <after>, cv_pct=<n>
**Behavior-preserving:** selections= byte-identical (yes/no), oracle delta = 0 (yes/no)
**Retry condition:** <one of 8 verbatim forms — see RETRY-CONDITION-VOCABULARY.md>
```

### Ritual R6: "Update bench-history"

```bash
# 1. Run the full matrix
./scripts/run-bench-matrix.sh <target> <workspace>

# 2. Diff against the committed baseline
./scripts/compute-parity-score.sh <workspace>
./scripts/apply-ratchet.sh <workspace>

# 3. If allow → commit new latest.json
cp reports/run-*/comprehensive_bench.v3.json .bench-history/comprehensive_bench.latest.json
git add .bench-history/comprehensive_bench.latest.json
git commit -m "bench: pass-over-pass refresh ($(date -u +%Y-%m-%dT%H:%M:%SZ))"
```

The `.bench-history` commit is the gate-of-record; CI can verify any later claim against the committed baseline.

---

## C. Verbatim Prompts (use byte-identically)

### C1. Phase 5 kickoff — Performance Harness Author

```
You are the Phase-5 performance-harness author for <project>. You inherit the
Phase-0 toolchain (cargo-criterion, hyperfine, samply, cargo-flamegraph, dhat,
heaptrack, strace, perf), the Phase-2 reference contract
(docs/contracts/<reference>_version_contract.toml), and the Phase-3 oracle
bridge (EngineIdentity asserted-distinct).

YOUR DELIVERABLES (one per workload family):
1. crates/<project>-e2e/src/bin/comprehensive_bench.rs containing:
   - WARMUP_ITERS=2, MIN_ITERS=3, MAX_ITERS=10, TARGET_DURATION=5s (HARD CONSTANTS).
   - measure() and measure_with_teardown() with teardown OUTSIDE the timed window.
   - Three orthogonal axes: workload size [100,1000,10000,100000], value shape
     {Tiny,Small,Medium,Large}, concurrency [2,4,8].
   - Identical PRAGMAs/config block applied to BOTH engines.
   - Six weighted categories summing to 1.0 (ReadSingle 0.35 / ReadAggregate 0.15
     / WriteSingle 0.30 / WriteBulk 0.10 / ConcurrentWriters 0.05 / MixedOltp 0.05).
   - JSON v3 self-describing report with schema_version, detected_environment,
     summary{average_ratio,geomean_ratio,median_ratio,p90_ratio,p99_ratio,
     per_category_weighted{score,weights}}, ci_regression_gate.

2. .bench-history/comprehensive_bench.latest.json initial baseline (committed).

3. A focused narrow bench per top-3 ledger-blocker workloads (mt_mvcc_bench.rs,
   mt_oltp_bench.rs, perf_update_delete.rs analogues).

4. concurrent_mode_default_guard.txt (or project-class equivalent) dropped in
   every artifact lane.

5. release-perf profile in Cargo.toml (NEVER bare --release).

6. HotPathProfileSnapshot per §23.6 row for <project_class>.

FORBIDDEN:
- Cold-start measurement (WARMUP_ITERS handles this).
- cv_pct dropped from output.
- Population inside timed window.
- One-shot timing (MIN_ITERS=3 minimum).
- Size-optimized release profile.

EXIT CRITERIA:
- ./scripts/run-bench-matrix.sh exits 0.
- JSON validates against fsqlite-e2e.comprehensive-bench-report.v3 schema.
- Pass-over-pass gate green on baseline (trivially; first run).
- .bench-history/comprehensive_bench.latest.json committed.

Coordinate via thread: gauntlet-<run-id>-phase5-<workload-family>.
Reservations needed: tool://comprehensive-bench (60min), resource://host-pinned-cores.
```

### C2. Phase 10 — `/idea-wizard` Orchestrator

```
Run /idea-wizard against <project_class> with the following context:
- Phase-1 archaeology: <workspace>/phase1_recon/
- Phase-5 baseline: <workspace>/phase5_perf/baseline/
- Phase-6 conformance: <workspace>/phase6_conformance/baseline/
- Phase-7 surface: <workspace>/phase7_surface/feature_universe.json
- Three ledgers (frozen at this round): <workspace>/ledgers/
- Last 60d cass mining: <workspace>/phase8_cass_findings.jsonl

DELIVERABLE: 30 candidate ideas → 5 surviving after Phase-2 idea-wizard scoring,
then 10 additional ideas spawned from the surviving 5 ("idea sprouting"). Each
idea must have:
- name
- pillar (perf / conformance / surface)
- hypothesis (testable, falsifiable)
- minimal_repro (one-line invocation)
- expected_signal (numerical or boolean prediction)
- falsifiability (what observation would kill it)
- one_line_invocation
- estimated_effort (S / M / L)
- impact_score (1-10)
- confidence_score (1-10)
- EV = (impact * confidence) / effort_multiplier

Write to <workspace>/round-<N>/idea-wizard-output.md AND to
<workspace>/GAUNTLET_EXPERIMENT_DESIGNS.md (append).

Also invoke:
- advanced-methods mining against <project_class> for public systems-technique candidates
- frontier-math compilation for math-toolkit candidates

Coordinate via thread: gauntlet-<run-id>-phase10-idea-wizard.
```

### C3. Phase 14 — Fresh-Eyes Reviewer A

```
You are a fresh-eyes reviewer with NO history in this workspace. Read only the
current state of:
- <workspace>/FINAL_GAUNTLET_REPORT.md (draft)
- <workspace>/PARITY_RUNBOOK.md (draft)
- <workspace>/RELEASE_CERTIFICATION_TEMPLATE.md (draft)
- The three ledgers
- The Phase-7 FeatureUniverse + InvariantCatalog

DO NOT read the workspace history. DO NOT read prior round artifacts. Pretend
you've never seen this project before.

YOUR JOB: Find what a maintainer reading these documents for the first time
would catch. Surface:
- claims unsupported by the artifacts they cite
- broken cross-links
- inconsistencies between FINAL_REPORT and RUNBOOK
- assumptions about "the team knows" that aren't in any doc
- numbers that don't match between sections
- gates that pass but exclude the very thing they're meant to gate
- retry-condition predicates that say "later" or "if it seems important"
- ledger entries missing scratch-worktree path or hotspot evidence
- proof-pack cards missing 1+ of the 19 required fields
- any victory-claim on one pillar while another regresses

WRITE: <workspace>/round-<N>/fresh-eyes-A-findings.md
Each finding: severity (high/med/low), one-paragraph evidence, exact file:line
citation, proposed fix.

EXIT: Hand off to reviewer B (different model recommended). Round is clean ONLY
when reviewers A AND B AND C each report <3 new high-severity findings.
```

### C4. Phase 14 — Fresh-Eyes Reviewer B (random-walk + AGENTS.md compliance)

```
You are fresh-eyes reviewer B. Reviewer A has already done a top-down read.
You do a DIFFERENT pass: random-walk file selection + AGENTS.md compliance.

PROCEDURE:
1. Pick 20 random files from the touched-files set across the gauntlet run
   (use `git log --since='<run start>' --name-only --pretty=format: | shuf | head -20`).
2. For each, read it cold and ask: "If this is my first look, does the
   surrounding scaffold (tests, ledger entries, proof-pack cards) make sense?"
3. Read the target project's AGENTS.md. For each mandate paragraph, grep the
   commits since <run start> for compliance evidence. Flag every mandate that
   has at least one violating commit.
4. Read the three ledgers in random order. Spot-check 10 entries: does each
   have a retry-condition predicate from the 8 verbatim forms? Does each
   point at a scratch worktree that still exists?
5. Re-read all the `concurrent_mode_default_guard.txt` (or equivalent) files
   from every artifact lane this run. Are they all consistent?

WRITE: <workspace>/round-<N>/fresh-eyes-B-findings.md
```

### C5. Phase 14 — Fresh-Eyes Reviewer C (fellow-agent code review)

```
You are fresh-eyes reviewer C. You are reviewing as a fellow agent who will
inherit this code next month. Your concerns:

1. Can I drop into this code mid-flight without losing context?
   - Are run_id, scenario_id, seed always populated in logs?
   - Does every failure bundle contain the replay command?
   - Does every artifact lane carry the EngineIdentity assertion?

2. Could I bisect a future regression?
   - Is .bench-history/<bench>.latest.json committed?
   - Are commits one-lever (single change per commit)?
   - Does every retry-condition predicate name a concrete observation that
     would change the decision?

3. Are the gates honest?
   - Run scripts/oracle-preflight-doctor.sh; does it return green?
   - Run scripts/convergence-tracker.sh; does it exit 0?
   - Run scripts/bead-graph-validator.sh; any cycles?
   - Spot-check 5 random "kept" perf entries: does each cite a profile frame
     ≥0.1% self-time with a quote?

4. Can I trust the score?
   - Does the parity score use the conformal LOWER bound, not the point estimate?
   - Is truncate_score applied (6 decimal places)?
   - Does sum(weights) == 1.0 hold per category?

WRITE: <workspace>/round-<N>/fresh-eyes-C-findings.md
This is the THIRD reviewer; if all three report <3 new high-severity findings,
the round counts as clean. Two consecutive clean rounds → Phase 15.
```

---

## D. §75–76 Mathematical-Toolkit Catalog (verbatim from MINING-1 §7)

The 32 mathematical results actually applied in FrankenSQLite. Each row points at the file where it lives.

| # | Result / Theorem | Canonical Paper | FrankenSQLite Usage | File pointer |
|---|---|---|---|---|
| 1 | Ville's inequality | Ville 1939 | E-process Ville threshold rejection | `crates/fsqlite-harness/src/eprocess.rs` |
| 2 | E-process (anytime-valid sequential testing) | Howard-Ramdas-McAuliffe-Sekhon 2021 | MVCC INV-1..INV-7 monitoring; SsiFalsePositiveRate drift | `eprocess.rs` |
| 3 | Conformal prediction (distribution-free intervals) | Vovk-Gammerman-Shafer 2005 | Conformal bands on Beta posterior; Phase-9 verification gates | `crates/fsqlite-harness/src/score_engine.rs` |
| 4 | Bayesian Online Change-Point Detection | Adams-MacKay 2007 | Replay-harness regime detection; drift_monitor.rs BOCPD layer | `crates/fsqlite-harness/src/replay_harness.rs`, `drift_monitor.rs` |
| 5 | Normal-Gamma conjugate posterior | Standard Bayesian | BOCPD predictive model for throughput / contention | `replay_harness.rs` |
| 6 | Beta-Binomial conjugate posterior | Standard Bayesian | BOCPD for abort rates; per-category pass rate | `score_engine.rs`, `replay_harness.rs` |
| 7 | Cahill-Fekete SSI rule | Cahill-Röhm-Fekete VLDB 2008 | `fsqlite-mvcc::SireadTable` + commit-time validation | `crates/fsqlite-mvcc/` |
| 8 | Mazurkiewicz traces | Mazurkiewicz 1977 | asupersync `LabRuntime` + DPOR exploration | `crates/asupersync/` |
| 9 | Dynamic Partial Order Reduction (DPOR) | Flanagan-Godefroid POPL 2005 | Same as Mazurkiewicz | `crates/asupersync/` |
| 10 | Epoch-Based Reclamation (EBR) | Fraser 2004 | `crossbeam-epoch`-style retired-slot batching in MVCC version arena | `crates/fsqlite-mvcc/` |
| 11 | Adaptive Replacement Cache (ARC) | Megiddo-Modha FAST 2003 | Buffer pool `ArcBufferPool` (T1 / T2 / B1 / B2) | `crates/fsqlite-core/src/buffer_pool.rs` |
| 12 | Birthday paradox | Folklore | README "Probabilistic Conflict Model"; threshold predictor for MVCC abort rates | `docs/` |
| 13 | GF(2⁸) field arithmetic | Standard | RaptorQ encode/decode, WAL repair | `crates/fsqlite-wal/` |
| 14 | RaptorQ fountain codes (RFC 6330) | Luby et al. 2011 | WAL self-healing, replication, ECS object storage | `crates/fsqlite-wal/`, `crates/fsqlite-replication/` |
| 15 | BLAKE3 | O'Connor et al. 2020 | ObjectId derivation for content addressing | `crates/fsqlite-core/src/object_id.rs` |
| 16 | XXH3 | Collet 2021 | Page checksums; WAL frame integrity | `crates/fsqlite-core/`, `crates/fsqlite-wal/` |
| 17 | Argon2id | Biryukov-Dinu-Khovratovich 2015 | KEK derivation from PRAGMA key | `crates/fsqlite-crypto/` |
| 18 | XChaCha20-Poly1305 | Bernstein 2008 + Aumasson | Per-page encryption | `crates/fsqlite-crypto/` |
| 19 | Database cracking | Idreos-Kersten-Manegold CIDR 2007 | `cracking.rs` | `crates/fsqlite-btree/src/cracking.rs` |
| 20 | LeanStore cooling | Leis-Haubenschild-Neumann-Kemper ICDE 2018 | `cooling.rs` | `crates/fsqlite-btree/src/cooling.rs` |
| 21 | Learned indexes (RMI) | Kraska-Beutel-Chi-Dean-Polyzotis SIGMOD 2018 | `learned_index.rs` | `crates/fsqlite-btree/src/learned_index.rs` |
| 22 | Direct-DML | Neumann SIGMOD 2015 | Advanced-methods queue item 1; DML mutation operator design | `docs/architecture/dml-mutation-operator.md` |
| 23 | MonetDB vectorized execution | Boncz-Manegold-Kersten 2005 | Advanced-methods item 2; vectorized modules | `crates/fsqlite-vectorized/` |
| 24 | Cicada read-ts | Lim-Kaminsky-Andersen SIGMOD 2017 | Advanced-methods queue item 5 | `crates/fsqlite-mvcc/` |
| 25 | Azuma's inequality | Azuma 1967 | Frontier-math P2 proposal; bounded-difference martingale concentration | proposal docs |
| 26 | Nemhauser submodular bound | Nemhauser-Wolsey-Fisher 1978 | Frontier-math P4; submodular workload selection | proposal docs |
| 27 | McAllester PAC-Bayes | McAllester COLT 1999 | Frontier-math P5; generalization bound for learned components | proposal docs |
| 28 | Little's Law + MPC | Little 1961 + Camacho-Bordons 2007 | Frontier-math P6; throughput/concurrency relationship | proposal docs |
| 29 | Lai-Robbins bandit lower bound | Lai-Robbins 1985 | Frontier-math P7; adaptive optimization selection | proposal docs |
| 30 | Renewal-reward processes | Wald 1944 | Frontier-math P8; long-run reward accounting | proposal docs |
| 31 | PostgreSQL's measured SSI overhead | Ports-Grittner SIGMOD 2012 | Empirical baseline for SSI overhead (<7% throughput, 0.5% false positive) | `docs/baselines/` |
| 32 | Mauboussin's "process vs outcome" | Mauboussin 2012 | Implicit in keep-gate philosophy: good outcome + bad process = rejected | `docs/methodology/` |

Cross-link: applying these to a sibling project → see [SIBLING-PROJECTS-STATUS.md](SIBLING-PROJECTS-STATUS.md) "Math layer" column.

---

## E. Perf Vocabulary Glossary (with anchor IDs)

Cross-referenceable definitions. Source: MINING-1 §1 (verbatim from CC.md §37).

**[V-001] keep gate.** The numeric threshold an optimization must clear to be merged. Singular "the keep gate" usually means the comprehensive-bench primary score. Specific gates are *named*: "focused DML keep gate", "10K DELETE keep gate", "MT8 keep gate".

**[V-002] within noise.** Improvement is ≤ the workload's cv_pct band (typically ±3–5%). Not a win — *technically also not a loss*, but not durable evidence.

**[V-003] within ±N% noise band.** Quantitative version: explicit confidence interval. Required when "within noise" is the rejection reason.

**[V-004] fresh-eyes pass.** A full re-review of recent code by an agent who didn't write it. Often surfaces a regression the author rationalized away.

**[V-005] scratch worktree.** A directory under `/data/tmp/<project>-<feature>-<timestamp>` where the rejected candidate's code lives so it can be inspected later without polluting main. The path itself goes into the ledger entry.

**[V-006] correctness-abandoned.** Killed before perf measurement because correctness failed. *Different from* "perf-rejected" — these don't earn a perf ledger entry; they earn a beads bug fix.

**[V-007] focused gate vs broad gate.** Two-level gating: focused = the targeted workload (e.g., 10K DELETE), broad = the comprehensive-bench primary score. *Both must move in the same run window.*

**[V-008] behavior-preserving.** The candidate doesn't change observable behavior (verified by oracle tests, selection counts, bench-level row equality). Required prerequisite for any rejection-by-perf.

**[V-009] selections= counts byte-identical.** A specific form of behavior-preservation proof: the bench harness exposes per-scenario selection counters; a change that preserves selection counts to the byte is verified non-behavior-affecting.

**[V-010] fused-design target.** A path that has been architecturally unified — e.g., "fused empty-root direct-insert page builder" means insert + page-build are a single fused operator. Optimizing one half without redesigning the whole is rejected.

**[V-011] DML mutation operator.** The project-wide ongoing redesign that bundles per-statement DML work into a single transaction-local operator. Many DELETE entries are rejected with "reconsider only inside the broader DML mutation operator redesign".

**[V-012] hot path.** A code path that *measurably* dominates a profile sample. Saying "this is a hot path" is meaningless without the profile.

**[V-013] cold start.** The first sample after a `target/` rebuild or process restart. Always discarded.

**[V-014] MT8 / MT 8t.** Multi-thread 8-thread benchmark — the canonical concurrency-stress workload.

**[V-015] micro-lever.** A small optimization that *could* help in principle. The phrase "no bounded micro-lever found" is a common rejection reason.

**[V-016] frontier.** The current performance ratio frontier — the workloads at the edge of subject-vs-reference where the next gain is most valuable.

**[V-017] refresh.** A measurement-only run (no source change) to capture a current-state profile.

**[V-018] durable infra.** A change that *isn't* an optimization but is kept anyway because it serves future work — e.g., a new benchmark, a new counter, a new fault profile.

**[V-019] both gates must move in the same run window.** The non-negotiable rule. Same run = same git state, same `target/`, same machine, same minute.

**[V-020] pulled / pulled the pin.** Discarded a previously-committed-then-reverted candidate.

---

**End of EXEMPLARS.** When you write a ledger entry, copy from C; when you cite a quote, use the Q-anchor; when you reach for a math result, look at D; when you use a vocabulary term, V-anchor it.
