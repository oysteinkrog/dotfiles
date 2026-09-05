# KEEP-GATE-RULES — The FrankenSQLite Keep-Gate Discipline

This file is the operational rule-set the gauntlet uses to decide whether a perf candidate is *kept* (merged + ratchet bumped) or *rejected* (logged in the negative ledger with a retry-condition predicate). It mirrors the [SKILL.md § Keep-Gate Rules](../../SKILL.md) table but expands every term with verbatim citations and a worked rejection. Cross-link to [KERNEL.md](KERNEL.md) for the K-2 / K-4 axioms it enforces, to [RETRY-CONDITION-VOCABULARY.md](RETRY-CONDITION-VOCABULARY.md) for the predicate forms, and to [ANTI-PATTERNS.md](ANTI-PATTERNS.md) for the failure modes it prevents.

---

## (a) The perf vocabulary glossary

Every term below is taken from MINING-1 §1 (CC.md §37). When a ledger entry uses a term informally, it means *exactly* this. Do not redefine.

| Term | Verbatim definition (CC.md §37) |
|---|---|
| **keep gate** | The numeric threshold an optimization must clear to be merged. Singular "the keep gate" usually means the comprehensive-bench primary score. Specific gates are *named*: "focused DML keep gate", "10K DELETE keep gate", "MT8 keep gate". |
| **within noise** | Improvement is ≤ the workload's cv_pct band (typically ±3–5%). Not a win — *technically also not a loss*, but not durable evidence. |
| **within ±N% noise band** | Quantitative version: explicit confidence interval. Required when "within noise" is the rejection reason. |
| **fresh-eyes pass** | A full re-review of recent code by an agent who didn't write it. Often surfaces a regression that the author rationalized away. The pattern: "fresh-eyes fix" entries land *along with* the rejection of the author's defense. |
| **scratch worktree** | A directory under `/data/tmp/frankensqlite-<feature>-<timestamp>` where the rejected candidate's code lives so it can be inspected later without polluting main. The path itself goes into the ledger entry. |
| **correctness-abandoned** | Killed before perf measurement because correctness failed. *Different from* "perf-rejected" — these don't earn a perf ledger entry; they earn a beads bug fix. But the ledger sometimes records *the attempt* if it had been previously considered viable. |
| **focused gate vs broad gate** | Two-level gating: focused = the targeted workload (e.g., 10K DELETE), broad = the comprehensive-bench primary score. *Both must move in the same run window* — improving focused while breaking broad is a rejection. |
| **behavior-preserving** | The candidate doesn't change observable behavior (verified by oracle tests, selection counts, bench-level row equality). Required prerequisite for any rejection-by-perf — a behavior-changing candidate is a different question entirely. |
| **selections= counts byte-identical** | A specific form of behavior-preservation proof: the bench harness exposes per-scenario selection counters; a change that preserves selection counts to the byte is verified non-behavior-affecting. |
| **fused-design target** | A path that has been architecturally unified — e.g., "fused empty-root direct-insert page builder" means insert + page-build are a single fused operator. Optimizing one half of a fused design without redesigning the whole is usually rejected. |
| **DML mutation operator** | The project-wide ongoing redesign that bundles per-statement DML work into a single transaction-local operator. Many DELETE entries are rejected with the phrase "reconsider only inside the broader DML mutation operator redesign". Deferred-architectural pattern: localized fixes are blocked until the architecture lands. |
| **hot path** | A code path that *measurably* dominates a profile sample. Saying "this is a hot path" is meaningless without the profile; the ledger demands the profile. |
| **cold start** | The first sample after a `target/` rebuild or process restart. Always discarded. A "cold-start outlier" entry typically explains why an apparent improvement was actually warmup noise. |
| **MT8 / MT 8t** | Multi-thread 8-thread benchmark — the canonical concurrency-stress workload. Used as a profiling anchor: "MT8 attribution" means the profiler ran under MT8 load, which exercises the MVCC plane realistically. |
| **micro-lever** | A small optimization that *could* help in principle. The phrase "no bounded micro-lever found" is a common rejection reason: the team looked for a few-ns win and found none. |
| **frontier** | The current performance ratio frontier — the workloads at the edge of FrankenSQLite-vs-CSQLite where the next gain is most valuable. |
| **refresh** | A measurement-only run (no source change) to capture a current-state profile. Refresh entries are *baseline captures*, not optimization attempts. |
| **durable infra** | A change that *isn't* an optimization but is kept anyway because it serves future work — e.g., a new benchmark, a new counter, a new fault profile. Marked "kept (durable infra)" in the status field. |
| **both gates must move in the same run window** | The non-negotiable rule for keeping a perf change. Same run = same git state, same `target/`, same machine, same minute. |
| **pulled / pulled the pin** | Discarded a previously-committed-then-reverted candidate. Distinct from "rejected uncommitted". Used when the candidate was on a branch that got abandoned. |

For per-class adaptations (RESP, Tensor, HTTP), see [../taxonomy/PROJECT-CLASSES.md § failure-terms](../taxonomy/PROJECT-CLASSES.md).

---

## (b) The 10 rules in tabular form

Every kept perf change must satisfy ALL of these (mirrors [SKILL.md § Keep-Gate Rules](../../SKILL.md), expanded with verbatim citations and specific numeric gates):

| # | Rule | Verbatim test | Numeric gate |
|---|---|---|---|
| 1 | **Profile-first** | "No code-changing performance bead starts without measured hotspot evidence, an EV-scored recommendation card, a one-lever scope, and a proof pack." — MINING-3 §5 | Hotspot evidence ≥0.1% self-time in `artifacts/{bead_id}/proof_pack/baseline_profile.{flame.svg,samply.json}` BEFORE source touch. |
| 2 | **Both gates in same run window** | "Same run = same git state, same `target/`, same machine, same minute." — MINING-1 §1 | Focused bench JSON + broad bench JSON both committed from the same git SHA, same `target/`, same hostname, timestamps within 60s. |
| 3 | **`release-perf` profile (never `--release`)** | "Never `--release` (size-optimized) for any perf claim." — MINING-3 §1.7 | Cargo profile: `[profile.release-perf] inherits = "release"; opt-level = 3; lto = "thin"; codegen-units = 1; debug = "line-tables-only"; strip = false; RUSTFLAGS = "-C force-frame-pointers=yes"` |
| 4 | **`concurrent_mode_default_guard.txt` equivalent** | "Rationale: Feb 2026 an agent silently disabled concurrent mode; project didn't notice until pass-over-pass gate flipped. This proof file, part of artifact contract, prevents silent regression." — MINING-3 §1.9 | Every artifact lane drops a feature-defining-mode-default proof file: `CONCURRENT_MODE_DEFAULT=true\nGIT_SHA=<sha>\nTIMESTAMP=<ISO-8601>` (or `RESP_VERSION=3` / `CUDA_DEVICE_COUNT=N` per class). |
| 5 | **Symmetric retry shells** | Both engines wrapped in identical retry shells of identical framework cost — implied by "Reference-side and subject-side PRAGMAs / config / pool sizes byte-identical." — MINING-3 §1.5 | If subject retries on busy, oracle gets the same retry wrapper even if it never needs it. Framework cost must be symmetric. |
| 6 | **Identical PRAGMAs / config** | "Both engines get identical PRAGMAs. This is a 30-line block at `comprehensive_bench.rs:502–541`, not a verbal convention." — MINING-3 §1.5 | journal_mode=wal, synchronous=NORMAL, cache_size=-2000, page_size=4096 (SQL class); class-equivalent for others. |
| 7 | **`selections=` byte-identical** | "A change that preserves selection counts to the byte is verified non-behavior-affecting." — MINING-1 §1 | Counter values match exactly between runs that should be byte-identical. |
| 8 | **cv_pct reported, `>5%` is noise** | "Every microbench result reports the coefficient of variation; if `cv_pct > 5`, the result is noise and not eligible for keep." — [../../SKILL.md § Keep-Gate Rules](../../SKILL.md) | `cv_pct ≤ 5` for any cell claimed as a win. |
| 9 | **MT8 attribution ≥0.1%** | "The kept win names a specific frame ≥0.1% self-time (e.g., 'Closed 0.44% MT8 PublishedPages::clear residual'). Below 0.1% is the **micro-lever trap**." — [../../SKILL.md § Keep-Gate Rules](../../SKILL.md) | Frame share ≥ 0.1%; 0.1%–1% is the productive band; <0.1% is the trap. |
| 10 | **Pass-over-pass ratchet thresholds** | "Threshold table: Primary score regression −3%; Geomean regression −5%; Per-category geomean regression −10%; p90 regression −15%; Pass-over-pass throughput drop −5%." — MINING-3 §4 | **Primary score: −3%, Geomean: −5%, Per-category: −10%, p90: −15%, Throughput: −5%.** A breach of any one is a rejection. |

---

## (c) What "same run window" means in practice

The non-negotiable rule (rule 2 + K-4) decomposes into four checklist items:

```
[ ] Same git state         — `git rev-parse HEAD` identical for focused + broad JSON.
[ ] Same target/           — no `cargo clean` between focused + broad runs.
[ ] Same machine           — `hostname` + `uname -a` identical in both JSONs' detected_environment.
[ ] Same minute            — TIMESTAMP fields within 60s; preferably consecutive invocations.
```

If any one of these fails, the run window is broken and the keep claim is invalid. The pass-over-pass gate is a file precisely so this cannot be silently violated: `.bench-history/<bench>.latest.json` is committed; if the focused JSON is from a different SHA than the broad JSON, the diff is visible in the PR.

**Special case — `rch`-offloaded runs:** The `rch` worker is a different machine from the dev host. For perf claims, run BOTH focused and broad on the SAME `rch` worker; commit the worker's `hostname` in both JSONs. Do not mix dev-host focused with rch broad.

---

## (d) Worked rejection example

Verbatim from MINING-1 §2 (CC.md line 567):

> **Reverted — within-noise.** Reusing `find_rowid_equality_term` for the `RowidLookup` probe (vs 2nd scan in `extract_access_path_probe`) was behavior-preserving (identical selection counts; 13 probe/21 rowid/35 access_path tests pass) but point-lookup gain ~2% sits in the ±3-5% bench noise band.

Anatomy of this rejection:
- **Verb:** "Reverted" — the candidate was committed, then pulled. (Distinct from "Rejected uncommitted" which would not have a revert.)
- **Status:** "within-noise" — names the [vocabulary](#a-the-perf-vocabulary-glossary) term that classifies the rejection.
- **Behavior-preservation proof:** "identical selection counts; 13 probe/21 rowid/35 access_path tests pass" — explicit citation of the `selections=` byte-identical (rule 7) check + the oracle pass count.
- **Measurement:** "point-lookup gain ~2%" — the focused measurement.
- **Noise quantification:** "±3-5% bench noise band" — the workload's cv_pct envelope.
- **Implicit retry-condition:** the candidate would be retryable if the wider workload moves above 5% (form 1 from [RETRY-CONDITION-VOCABULARY.md](RETRY-CONDITION-VOCABULARY.md)).

Note: nothing in this entry says "we should try again later" or "tracked elsewhere". The retry condition is *implicit in the noise band citation* — the entry is load-bearing because the next agent grepping for "RowidLookup probe" finds this and knows exactly what evidence would unblock the retry.

---

## (e) How to write a "keep" entry vs a "rejected" entry

### Keep entry template
```markdown
### <Date> | <bead_id> | <Title>

**Status:** kept (durable optimization | durable infra | fused-design completion)

**Profile attribution:** "Closed <X>% MT8 <Frame::name> <residual|inclusive self-time|self-time symbol>"
  - flamegraph: <artifacts/{bead_id}/proof_pack/baseline_profile.flame.svg>
  - samply: <artifacts/{bead_id}/proof_pack/baseline_profile.samply.json>
  - candidate: <artifacts/{bead_id}/proof_pack/candidate_profile.*>

**Measurement (focused):** <bench name> <metric> = <before> → <after> (<delta%>, <speedup>)
  - cv_pct = <X> (≤ 5)

**Measurement (broad):** comprehensive_bench primary_score = <before> → <after> (<delta%>)
  - Per-category: ReadSingle <delta%>, ReadAggregate <delta%>, WriteSingle <delta%>, ...
  - Both gates in same run window: git=<sha>, target/=<mtime>, host=<hostname>, ts=<ISO-8601>

**Behavior-preservation:** "<test summary>; selections= counts byte-identical between baseline and candidate."

**Pattern applied:** <Hot opcode promotion | AtomicBool gate | Algebraically-redundant counter elim | HashSet→sorted Vec | Bounds-elide | Trait→match devirt | Trace gating | Move-not-Clone | OnceLock | Cache-eviction fix>

**Rollback recipe:** `git revert <sha>` is sufficient (no dependent migration).
```

### Rejected entry template
```markdown
### <Date> | <bead_id-or-scratch-path> | <Title>

**Status:** rejected (within-noise | focused-improved-broad-worsened | cold-start-outlier | no-bounded-micro-lever | correctness-abandoned | architectural-change-dressed-as-micro | fused-design-half-optimization | flake)

**Scratch worktree:** /data/tmp/<project>-<feature>-<timestamp>

**Profile attribution:** "<X>% <Frame>"
  - flamegraph: <path>

**Measurement (focused):** <before> → <after> (<delta%>)
  - cv_pct = <X>
  - noise band: ±<N>%

**Measurement (broad):** primary_score <before> → <after> (<delta%>)

**Behavior-preservation:** <pass | fail; if fail, this is correctness-abandoned not perf-rejected>

**Retry-condition predicate:** <one of the 8 verbatim forms from RETRY-CONDITION-VOCABULARY.md>
  Example: "Retry only if a profiler attributes a clearly-above-noise share to <counter> on <wider workload shape>."

**Sibling references:** <bead_ids of related closed/open work>
```

The retry-condition predicate is **load-bearing**. Without it, the entry fails [RETRY-CONDITION-VOCABULARY.md § Anti-vocabulary](RETRY-CONDITION-VOCABULARY.md) and will be flagged by `convergence-tracker.sh` as an unresolved hypothesis.

---

## Cross-links

- Keep-gate enforces [KERNEL.md § K-2](KERNEL.md) (honesty in the harness) and [K-4](KERNEL.md) (both gates same run window).
- The retry-condition predicate per entry is mandated by [KERNEL.md § K-3](KERNEL.md) (negative evidence first-class) and detailed in [RETRY-CONDITION-VOCABULARY.md](RETRY-CONDITION-VOCABULARY.md).
- Anti-patterns that violate this rule-set are catalogued in [ANTI-PATTERNS.md](ANTI-PATTERNS.md).
- The 10 winning patterns referenced in the keep-entry template are detailed in [../remediation/REMEDIATION-PATTERNS.md](../remediation/REMEDIATION-PATTERNS.md).
- The proof-pack baseline structure is in [../tooling/BENCH-TOOLCHAIN.md § Proof-Pack Baseline](../tooling/BENCH-TOOLCHAIN.md).
