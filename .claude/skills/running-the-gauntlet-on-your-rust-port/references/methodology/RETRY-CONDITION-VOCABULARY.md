# RETRY-CONDITION-VOCABULARY — The 8 Verbatim Retry-Predicate Forms

This file is the verbatim template library for the load-bearing **retry-condition predicate** every closed negative-ledger entry must carry. Every entry in `docs/progress/perf-negative-results.md` (and the two sibling ledgers) is closed with one of these 8 forms — never "later", never "tracked elsewhere", never "if it seems important". The predicate is what makes the ledger queryable, the convergence tracker decidable, and the next-agent's first-grep productive. See [KEEP-GATE-RULES.md § (e)](KEEP-GATE-RULES.md) for the entry template these forms slot into, and [KERNEL.md § K-3](KERNEL.md) for the axiom that mandates them.

---

## Form 1 — Profile attribution above noise

**Template:**
> Retry only if a profiler attributes a clearly-above-noise share to **<specific counter or frame>** on **<wider workload shape>**.

**Worked examples (in the style of the FrankenSQLite ledger):**

> Retry only if a profiler attributes a clearly-above-noise share to `find_rowid_equality_term` on the **mt-mvcc-bench --threads=16 --rows-per-thread=2000** workload (point-lookup currently sits in ±3-5% bench noise band on the 8-thread workload).

> Retry only if `flamegraph` attributes ≥0.5% self-time to `BtreePageHeader::parse` on the **TPC-C order-status** workload (currently 0.03% on read-heavy; below the micro-lever trap).

> Retry only if `samply` attributes ≥0.2% self-time to `ConcurrentPublishedPages::clear` on the **MT16 separate-tables** workload at steady state (the empty-overflow fast path already closed the 0.44% MT8 residual at commit `1a2b3c4d`).

**When to pick this form:** the most common case. The candidate was profile-driven, the profile didn't show enough attribution to justify the change *on the workload measured*, but a different workload shape might surface the cost. Names the *evidence pipeline* (which profiler, which workload) — not just "be sure to remeasure".

---

## Form 2 — Architectural defer

**Template:**
> Reconsider only inside the broader **<X>** redesign.

**Worked examples:**

> Reconsider only inside the broader **DML mutation operator** redesign. Localized fix to `Connection::execute` for batch-DELETE would optimize one half of a path the upcoming operator unifies; isolated change has been rejected three times under the same retry predicate (see ledger entries 2026-03-14, 2026-04-02, 2026-04-29).

> Reconsider only inside the broader **fused empty-root direct-insert page builder** redesign. The current insert+page-build split is being unified; optimizing the split phase loses meaning once fused.

> Reconsider only inside the broader **prepared-statement cache key separation** redesign (track as `bd-stmtcache.1`). Touching the eviction policy before the bytecode/data key split is committed will re-introduce the COMMIT-cliff regression.

**When to pick this form:** the candidate is locally sensible but is duplicating work an upcoming architectural change makes obsolete. Names the redesign; ledger entry blocks until that redesign lands. CC.md §43 line 1921 introduced the convention of naming an explicit blocker bead.

---

## Form 3 — Gate-driven reconsideration

**Template:**
> Worth reconsidering when **<specific gate>** moves.

**Worked examples:**

> Worth reconsidering when **MT16 shared-table ratio crosses 5x** (currently 3.2x; the optimization's overhead amortizes only when contention is high enough that the fast-path skip dominates).

> Worth reconsidering when **`per_category_weighted.score` for ConcurrentWriters** crosses 0.45 (currently 0.31; the candidate's broad-gate cost is only justifiable in a regime where ConcurrentWriters dominates the weighted score).

> Worth reconsidering when **`mt_oltp_bench` Jain fairness** falls below 0.95 (currently 0.97; the candidate trades fairness for throughput, which is only worthwhile if fairness is already lost).

**When to pick this form:** the candidate makes a tradeoff that's only worthwhile in a specific gate regime. Names the gate explicitly so a future agent can grep "Worth reconsidering when MT16" and find this entry the day MT16 moves.

---

## Form 4 — Standalone retirement

**Template:**
> Not worth retrying as a standalone patch.

**Worked examples:**

> Not worth retrying as a standalone patch. The micro-lever closes at most 4 ns of a 230 ns commit path; the path is being rewritten under `bd-commit-fastpath.3`; any savings will be absorbed there.

> Not worth retrying as a standalone patch. Two attempts (2026-02-11, 2026-04-07) both showed focused +1% / broad −0.4%; the dominant cost is downstream of the optimization point and only a full pipeline rewrite would surface gain here.

> Not worth retrying as a standalone patch. The proposed change introduces a `Send + Sync` constraint that propagates through 14 call sites; the propagation cost outweighs the local 6 ns win on every wider workload tested.

**When to pick this form:** explicit declaration of permanent retirement *as a standalone change*. Distinct from form 2 (architectural defer) — this entry says "not now, not as a separate PR, ever". Still leaves room for the optimization to come back inside a larger redesign.

---

## Form 5 — Evidence-pipeline mandate

**Template:**
> Do not retry from a cold read; use **<specific evidence pipeline>** instead.

**Worked examples:**

> Do not retry from a cold read; use **comprehensive-bench attribution under MT8 steady-state** instead. The 2026-03-22 retry attributed gain to a cold-start outlier; the steady-state attribution dropped to within noise.

> Do not retry from a cold read; use **samply + dhat triangulation across 3 runs** instead. The original attribution from a single flamegraph sample was misleading — dhat revealed the dominant cost was heap pressure, not the CPU frame the flamegraph highlighted.

> Do not retry from a cold read; use **mt-mvcc-bench --separate-tables with `FSQLITE_TRACE_GROUP_COMMIT=1`** instead. The shared-table results hid the per-table commit-fence contention that the proposed fix targets.

**When to pick this form:** the candidate has been retried using the wrong evidence pipeline. Names the *specific* pipeline that would give honest attribution. Prevents the same wrong-pipeline retry from recurring.

---

## Form 6 — Structural not numerical

**Template:**
> Retry condition not applicable — the gain is structural, not numerical.

**Worked examples:**

> Retry condition not applicable — the gain is structural, not numerical. The change splits `TransactionKind` into two enums for compile-time guarantees; perf was measured at parity (broad +0.1%, focused −0.2%, both within noise). Kept as durable infra; not subject to perf retry.

> Retry condition not applicable — the gain is structural, not numerical. The introduction of `FeatureUniverse::features()` deterministic iteration changes no hot path; it makes the ratchet bytewise reproducible. Perf irrelevant by design.

> Retry condition not applicable — the gain is structural, not numerical. The fault-VFS deterministic seed (`0xD1A6_A3F4_9B17_0C5E`) replaces a `rand::random()` per-iteration; this is a reproducibility fix, not a perf change. Perf measurements skipped.

**When to pick this form:** the change isn't a perf candidate at all — it's structural (deterministic, compile-time, infrastructure). Explicit declaration that the perf retry framework doesn't apply. The entry still goes in the ledger as `kept (durable infra)` so that the next agent grepping for the touched code finds the rationale.

---

## Form 7 — Workload-property threshold

**Template:**
> Retry only if **<workload class>** exhibits measurable **<property>** below **<threshold>**.

**Worked examples:**

> Retry only if **ReadAggregate** exhibits measurable **median p99 latency** below **5ms** (currently 12ms; the candidate's cache-warming overhead is only amortized when the steady-state latency is already low enough that the warming cost dominates).

> Retry only if **ConcurrentWriters** exhibits measurable **cv_pct** below **2.5%** (currently 4.1%; the candidate's gain (~2%) is within the workload's noise floor; it would surface only when noise tightens).

> Retry only if **WriteBulk** exhibits measurable **arena_alloc_bytes per row** below **48 bytes** (currently 71 bytes; the candidate optimizes an allocation that only dominates when the per-row alloc is already small enough that per-call cost matters).

**When to pick this form:** derived from within-noise classification tied to the workload's cv_pct. Names the workload + the specific property + the numeric threshold. Lets the future agent grep "cv_pct below 2.5" and find this entry the day cv_pct tightens.

---

## Form 8 — Blocked-by architectural dependency

**Template:**
> Blocked until **<architectural_dependency>** lands; track as **<bead_id>**.

**Worked examples:**

> Blocked until **MVCC version-arena epoch reclamation** lands; track as **bd-arena-ebr.2**. The proposed swizzle-out optimization requires the EBR-style retired-slot batching to avoid the use-after-free hazard the 2026-03-11 fuzz target surfaced.

> Blocked until **WAL FEC repair** lands; track as **bd-wal-fec.4**. The proposed checkpoint-fastpath would skip the WAL verification phase that FEC repair depends on for crash-recovery correctness; cannot land before FEC.

> Blocked until **conformal-band calibrator stable across 10 windows** lands; track as **bd-conformal-stable.1**. The proposed parity-score throughput-streaming optimization changes the stream's distributional shape, which would invalidate the current calibration; must wait for the recalibration tooling.

**When to pick this form:** the candidate is blocked on a named, tracked, beaded piece of architectural work. Distinct from form 2 (which defers to a redesign without necessarily having an open bead). Use form 8 when there is an explicit bead id to grep for.

---

## Anti-vocabulary (forbidden phrases)

These phrases fail the load-bearing test. A ledger entry containing any of them is **invalid** and will be flagged by `convergence-tracker.sh` as an unresolved hypothesis. The convergence loop cannot terminate while any entry carries one of these.

| Forbidden phrase | Why it fails |
|---|---|
| **"later"** / **"in the future"** / **"down the road"** | Names no condition; the next agent has no signal to act on. "Later" is the absence of a predicate. |
| **"if it seems important"** | Subjective and unverifiable. Whose judgment? On what evidence? Not actionable. |
| **"we should revisit"** | Passive-voice deferral with no trigger. Identical failure mode to "later". |
| **"tracked elsewhere"** (without a bead id) | If it's tracked, name where. "Elsewhere" cannot be grepped, cannot be queried, cannot be closed. |
| **"TODO"** / **"FIXME"** | Code-comment idiom that doesn't belong in a ledger entry. A ledger entry that resolves to "TODO" was never actually closed. |
| **"future work"** | Synonym for "later". Same failure mode. |
| **"might be worth trying"** | Hedged speculation; no falsifiable predicate. If it's worth trying, write form 1 or form 7. If it's not, write form 4. |
| **"someone should look at this"** | Diffuses responsibility; no trigger; no owner; no evidence pipeline. |
| **"interesting direction"** | Editorial commentary, not a retry condition. |
| **"worth exploring"** | Synonym for "interesting direction". Same failure mode. |

### How the anti-vocabulary fails the load-bearing test

A retry-condition predicate is *load-bearing* when:
1. **It is grep-able.** A future agent can `rg "MT16 shared-table ratio"` and find this entry the day MT16 moves.
2. **It is falsifiable.** There exists a measurement that would *settle* whether to retry — the evidence pipeline is named.
3. **It survives compaction.** A new agent dropping into the workspace can read the predicate and act without needing the original author's context.

"Later" fails all three. "If it seems important" fails all three. "Tracked elsewhere" fails (1) without a bead id. The anti-vocabulary list is what a convergence tracker greps for as a *negative signal* — entries containing these phrases are presumed unresolved.

### Recovery rule

If a ledger entry exists with anti-vocabulary, the fix is to rewrite it using one of forms 1–8. If you genuinely cannot pick a form, the rejection was probably premature — the candidate should be reopened and re-investigated, not closed under a forbidden phrase. See [OPERATORS.md § 🗄 Ledger-Retire](OPERATORS.md) for the operator that runs this sweep.

---

## Cross-links

- This vocabulary is mandated by [KERNEL.md § K-3](KERNEL.md) (negative evidence first-class) and [K-12](KERNEL.md) (convergence as CI gate).
- The keep-vs-reject entry template in [KEEP-GATE-RULES.md § (e)](KEEP-GATE-RULES.md) carries the predicate as a required field.
- The convergence tracker that flags anti-vocabulary is documented in [CONVERGENCE.md § convergence-tracker.sh](CONVERGENCE.md).
- The operator that runs the predicate sweep is [OPERATORS.md § 🗄 Ledger-Retire](OPERATORS.md).
- Forms 1, 5, 7 reference "above noise" / "below noise"; the noise quantification is per [KEEP-GATE-RULES.md § cv_pct](KEEP-GATE-RULES.md).
