# OPERATORS — Full Card Library

This file is the card library for the 19 cognitive-move operators ("glyphs") enumerated in [../../SKILL.md § Operator Library](../../SKILL.md). Each card carries: glyph + name, the one-line **Question** that defines the operator, **Triggers** for when to apply, **Failure modes** for what going wrong looks like, the verbatim **Prompt module** an agent emits when applying the operator, and a **Quote-bank anchor** lifted from the FrankenSQLite mining extracts that grounds the move in evidence. The library is deliberately overlapping; a single perf candidate typically deserves four or five applied in sequence. See the **Composition cheat-sheet** at the end for pipelines.

---

## ★ Pin-Reference-Version

**Question:** "Does every artifact in this run identify the exact reference version it was generated against?"

**Triggers:**
- Starting a fresh gauntlet run on a port.
- Reference version bump (e.g., `sqlite-3.52.0 → 3.53.0`).
- Receiving an artifact from a contributor whose `docs/contracts/<reference>_version_contract.toml` you don't recognize.

**Failure modes:**
- "It works on my machine" perf claim — different reference binary version.
- Oracle preflight passes but mismatches expected version string.
- Artifact lane drops a result without `engines.reference_identity` populated.

**Prompt module:**
> Before any test runs, read `docs/contracts/<reference>_version_contract.toml`. Resolve the reference binary path; assert the binary's reported version matches the contract version exactly. If they diverge, halt with `oracle_preflight=red` and emit the version mismatch as the first failure. Every artifact this run emits must include the contract SHA-256 in its envelope.

**Quote-bank anchor:**
> "Verification: C SQLite oracle binary exists; expected version matches contract (3.52.0); subject identity is 'frankensqlite'; reference identity is 'csqlite-oracle'." — MINING-2 §13 (Oracle Preflight Doctor)

---

## ✦ Enumerate-Surface

**Question:** "Is every `pub` item / every dispatched opcode / every command / every public-API symbol on both sides accounted for, with `present|partial|missing|n/a|excluded`?"

**Triggers:**
- Phase 7 (Surface Parity Inventory).
- Reference version bump — new commands/opcodes/functions may have been added.
- A contributor claims "we support X" without a FeatureUniverse entry.

**Failure modes:**
- Quiet missing items: an opcode exists in the reference that has no Feature row.
- Excluded-without-rationale: `exclusion_rationale` is `None` while status is `Excluded`.
- Weights drift: `sum(weights) != 1.0` per category.

**Prompt module:**
> Enumerate the reference's full public surface (commands, opcodes, PRAGMAs, functions, methods, attributes — whichever applies to the class). For each, emit a `Feature { id, title, weight, status, exclusion_rationale }` row. Assert `sum(weights) == 1.0` per category at the loader. If status is `Excluded`, populate `exclusion_rationale` with a sentence (not "TODO", not "later").

**Quote-bank anchor:**
> "`sum(weights) == 1.0` per category enforced by loader." — MINING-3 §11

---

## ◐ Wire-Oracle

**Question:** "Does the subject have an in-process or stable subprocess bridge to the pinned reference, with `EngineIdentity` to prevent self-comparison?"

**Triggers:**
- Phase 3 (Oracle Wiring) of a new port.
- Adding a new project class to the router.
- A test passes 100% suspiciously fast.

**Failure modes:**
- Subject wired to both sides of the comparator → free 100%.
- Subprocess oracle without process-isolation seed → flaky pass.
- PyO3 interpreter shared across threads — RNG state leaks.

**Prompt module:**
> Stand up the oracle bridge per the project class (in-process rusqlite for SQL-class, subprocess `redis-server` over UNIX socket for RESP-class, PyO3 in-process Python for Numerical-Python/ML-System, fixture-corpus for HTTP-Protocol). Wire `EngineIdentity::Subject("<port>")` and `EngineIdentity::Oracle("<reference>")` constants; assert distinct at every comparator entry. Run oracle-preflight-doctor before declaring done.

**Quote-bank anchor:**
> ```rust
> const SUBJECT_IDENTITY_LABEL: &str = "frankensqlite";
> const REFERENCE_IDENTITY_LABEL: &str = "csqlite-oracle";
> ```
> "Strict parity validation: subject_identity == 'frankensqlite' and reference_identity == 'csqlite-oracle'. Enforced at harness entry; prevents oracle-on-oracle false greens." — MINING-2 §3

---

## ⬡ Instrument-Hot-Path

**Question:** "Does this hot loop have a counter ≥ 0.1% self-time that would attribute a regression to a specific frame?"

**Triggers:**
- Authoring a new bench scenario.
- Proposing any optimization to a path you haven't profiled.
- The `HotPathProfileSnapshot` for this domain doesn't list a counter for the suspected hot frame.

**Failure modes:**
- "Parser is slow" without a counter that exposes parse-time-ns.
- Optimization lands, perf regresses 6 weeks later, no counter to point at the regressed frame.
- Counter exists but is algebraically redundant (see ⊕ + the Algebraically-redundant counter anti-pattern).

**Prompt module:**
> Locate the relevant `HotPathProfileSnapshot` row in [../tooling/BENCH-TOOLCHAIN.md](../tooling/BENCH-TOOLCHAIN.md). If the counter that would attribute a change in this hot loop is missing, add it before touching the loop. Audit existing counters: if a counter is algebraically derivable from others, eliminate it at write-time and derive at read-time.

**Quote-bank anchor:**
> "Rule (CC.md line 2390): 'Each frame ≥0.1% is a *candidate*.'" — MINING-3 §3
> "Pattern 3: Algebraically-redundant counter elimination — `FSQLITE_SSI_VALIDATIONS_TOTAL` was static AtomicU64; `validations_total == commits + aborts` by construction. Dropping and deriving at snapshot time: **3.91 → 1.90 ns/call (−51.5%, ~2x)**." — MINING-1 §4 Pattern 3

---

## ⚠ Escalate-To-Fresh-Repro

**Question:** "If this only reproduces on my workstation, does the FailureBundle have the seed, schedule fingerprint, exact repro command, and platform fingerprint?"

**Triggers:**
- A new conformance divergence.
- A flaky bench result.
- A reviewer cannot reproduce a kept perf win on a different host.

**Failure modes:**
- Skipped manifest writing on failure (lost context).
- `seed = rand::random()` instead of `derive_entry_seed(corpus_entry_id)`.
- No `schedule_fingerprint` → loom/shuttle reruns can't recover the same interleaving.

**Prompt module:**
> Emit a `FailureBundle v1.0.0`: `{failure_type, seed, fixture_id, schedule_fingerprint, artifact_sha256, db_page_previews, wal_state_at_failure, expected_vs_actual, first_divergence_jsonptr, git_sha, toolchain_version, platform, feature_flags}`. If you cannot fill a field, write `null` with an explicit "why partial" note. A partial bundle with provenance is more valuable than no bundle.

**Quote-bank anchor:**
> "Critical: 'A partial bundle with provenance is more valuable than no bundle. Never skip manifest writing on failure.'" — MINING-2 §15

---

## ⊕ Isomorphic-Rewrite

**Question:** "What are 2+ behavior-preserving rewrites for this code path, and what does each cost on the rubric?"

**Triggers:**
- Phase 12 (Remediation Design).
- A perf candidate that changes one line — likely you missed 2 alternatives.
- A conformance gap that admits multiple fixes.

**Failure modes:**
- Single-option remediation — no triangulation.
- Behavior-changing rewrite passed as "isomorphic" (fails oracle).
- Rewrite that improves focused but regresses broad (K-4 violation).

**Prompt module:**
> Enumerate at least 2 behavior-preserving rewrites. For each, write a 5-line proof sketch from [../remediation/ISOMORPHISM-PROOF-TEMPLATE.md](../remediation/ISOMORPHISM-PROOF-TEMPLATE.md): Change / Ordering preserved / Tie-breaking unchanged / Floating-point unchanged / RNG seeds unchanged / Golden outputs preserved. Score each on the rubric (impact × confidence / effort ≥ 2.0). The winner must also pass ⬡ + ⤴ before merge.

**Quote-bank anchor:**
> "Pattern 10: Detect the cache-eviction bug — architectural fix. Audit cache-key design: *for every cache key, list which inputs it depends on; for every cache invalidation, list which inputs should invalidate it; gap = bug*. Fix: separate *bytecode-cache key* (schema-bound) from *data-cache key* (generation-bound). Contributed to **MT 8t fs_wps 778 → 5458 (7.0x)** and **1t fs_wps 88k → 305k (3x+)**." — MINING-1 §4 Pattern 10

---

## ⊙ Debounce-False-Positive

**Question:** "Is this divergence classified as `TrueDivergence` or as one of the 5 known classes (Order / TypeAffinity / NullHandling / FloatingPoint / FalsePositive)?"

**Triggers:**
- New mismatch surfaces in a metamorphic family.
- CI green-yellow flicker on parity.
- A divergence in an order-sensitive query that doesn't have ORDER BY.

**Failure modes:**
- Classifying `TypeAffinityDifference` as `TrueDivergence` → false alert.
- Classifying `TrueDivergence` as `FalsePositive` → real bug hidden.
- Floating-point divergence reported without `max_epsilon_str`.

**Prompt module:**
> Run the mismatch through `MismatchClassification::triage_priority`. CI fails only on `TrueDivergence { description }`. Everything else flows into a triage queue with its enum-tagged class. Populate the class-specific fields (e.g., `max_epsilon_str` for floating-point). If you cannot decide, default to `TrueDivergence` and document the doubt.

**Quote-bank anchor:**
> "CI rule: CI fails only on `TrueDivergence`. Other classes flow into triage queue." — MINING-2 §4

---

## ⊞ Soak

**Question:** "Has this been run for the soak duration (24h fuzz / multi-day miri / multi-thousand-iter loom-shuttle / multi-day BOCPD)?"

**Triggers:**
- Phase 15 (Soak / Deep Validation).
- Candidate for release certification.
- An invariant that has only been checked under per-round tests.

**Failure modes:**
- 5-minute "soak" — does not surface rare bugs.
- Loom run with `iterations=100` — DPOR coverage too shallow.
- BOCPD declared `Stable` after one window.

**Prompt module:**
> Dispatch to `rch` per the [SOAK-PROTOCOL.md](SOAK-PROTOCOL.md) durations: 24h+ differential fuzz, multi-day Miri across harness internals, multi-thousand-iter loom + shuttle, multi-thousand-iter crash-boundary, multi-day BOCPD on parity-score stream (assert `Regime::Stable`), adversarial-search against every gate. Failures loop back to Phase 12 (Remediation).

**Quote-bank anchor:**
> "Multi-day BOCPD on parity-score stream; assert `Stable` regime." — [../../SKILL.md § Subagents § soak-runner-bocpd](../../SKILL.md)

---

## ⌘ Reduce / Minimize

**Question:** "Has this failure been reduced to its delta-debugged minimum with schema-preservation guard?"

**Triggers:**
- New conformance failure with a multi-statement repro.
- Fuzz corpus has 100-byte input that reproduces — could it be 10 bytes?
- Duplicate failures suspected — need MismatchSignature.

**Failure modes:**
- Schema setup removed during minimization → false repro.
- 1-minimal not achieved (still 5 statements).
- Two distinct failures collapsed under same MismatchSignature (under-deduplication).

**Prompt module:**
> Run mismatch-minimizer binary-partition with the schema-preservation guard (schema setup never removed). Iterate until 1-minimal. Compute `MismatchSignature { hash, classification, subsystem, minimal_statement_count, first_diverging_sql }`. If signature matches an existing bead, link instead of opening new.

**Quote-bank anchor:**
> "Algorithm: binary partition → recursive narrowing → 1-minimal → schema preservation (schema setup never removed). Dedup rule: Two failures with same `MismatchSignature` are the same root-cause bug. A bisect that hits a known bug links instead of opens new beads issue." — MINING-2 §5

---

## ⟁ Triangulate-Profile

**Question:** "Do flamegraph + samply + dhat + strace agree on the attribution, or is one source disagreeing?"

**Triggers:**
- Hot-path attribution claim.
- A frame at exactly 0.1% — boundary case.
- Surprising attribution (e.g., "the parser is taking 30%" when you didn't expect it).

**Failure modes:**
- Single-profiler attribution → instrumentation skew.
- dhat shows heap pressure flamegraph doesn't reflect.
- strace shows a syscall storm samply isn't sampling.

**Prompt module:**
> Capture profiles with at least two of {flamegraph, samply, dhat, strace, perf}. If they agree on the top-5 self-time frames, claim attribution. If they disagree, the disagreement IS the finding — record it in the perf hypothesis ledger and refine. Do not optimize before triangulation closes.

**Quote-bank anchor:**
> "Required tools: `cargo-flamegraph`, `hyperfine`, `heaptrack`, `strace`, `samply`, `perf`." — MINING-3 §8

---

## ⤴ Attribute-To-MT8

**Question:** "Does this kept perf win name a specific profile frame ≥0.1% self-time, with a quoted citation?"

**Triggers:**
- About to commit a perf change.
- Writing the ledger entry for a kept candidate.
- Reviewing someone else's perf claim.

**Failure modes:**
- Claim has no MT8 (or class-equivalent) profile attached.
- Attribution at 0.05% — below the **micro-lever trap**.
- "We think this helps" — no specific frame named.

**Prompt module:**
> Re-run profile under canonical concurrent workload (MT8 = 8-thread multi-writer bench for SQL; equivalent for RESP/Torch/etc.). Cite the specific frame: "Closed 0.44% MT8 PublishedPages::clear residual" or equivalent. If the frame is <0.1% self-time, you are in the **micro-lever trap** — reject the candidate.

**Quote-bank anchor:**
> "Discipline: (1) Run `mt-mvcc-bench --threads=8 --rows-per-thread=1000 --iters=3`. (2) Capture flamegraph during *steady-state*. (3) Identify top 5–10 self-time frames. (4) Each ≥0.1% is a *candidate*. (5) Pick highest cost-effort ratio." — MINING-1 §4 Bonus Pattern
> "A frame at 0.05% is below the noise floor of the bench (cv_pct 3-5%); the **micro-lever trap**." — MINING-3 §3

---

## 🔁 Pass-Over-Pass-Gate

**Question:** "Have both the focused and broad gates moved in the same run window (same git state, same `target/`, same machine, same minute)?"

**Triggers:**
- About to commit a perf change.
- New `.bench-history/*.latest.json` candidate.
- CI bench result divergent from local.

**Failure modes:**
- Focused improved, broad worsened (K-4 violation).
- `.bench-history/*.latest.json` not committed.
- Bench run on different git SHA than source change.

**Prompt module:**
> Run focused + broad bench from the same `target/` build, on the same machine, within the same minute. Diff against `.bench-history/<bench>.latest.json`. Within the gate thresholds (primary −3%, geomean −5%, per-category −10%, p90 −15%, throughput −5%)? Commit the new `.bench-history/*.latest.json` together with the source change. Otherwise, reject.

**Quote-bank anchor:**
> "Pass-over-pass gate is a *file*. `.bench-history/*.latest.json` is committed. You can't bench on your machine, see a 30% drop, and quietly not commit." — MINING-3 §4

---

## ⚖ Ratchet-Lower-Bound

**Question:** "Does the proposed change raise the conformal LOWER bound on parity score without lowering any per-category bound?"

**Triggers:**
- Conformance change.
- New feature added.
- Release candidate.

**Failure modes:**
- Point-estimate cited instead of lower bound.
- Per-category bound lowered for a global gain (Pareto violation).
- Ratchet state not updated on a real improvement.

**Prompt module:**
> Compute `theta_c ~ Beta(α_prior + Σ weighted_successes, β_prior + Σ weighted_failures)` per category. Compute distribution-free conformal band. Use the LOWER bound for the decision. Compare to `reports/ratchet_state.json`. `apply-ratchet.sh` emits `Allow | Block | Quarantine | Waiver`. A legitimate downgrade requires a structured waiver — see [CONFORMAL-RATCHET.md § waiver](CONFORMAL-RATCHET.md).

**Quote-bank anchor:**
> "Lower confidence bound for release decisions." — MINING-2 §11 (Score Engine)

---

## 🪟 Fresh-Eyes

**Question:** "Have the three calibrated fresh-eyes prompts run against this code? Has the round come up clean twice?"

**Triggers:**
- Phase 14 (Fresh-Eyes Review).
- About to declare convergence.
- Author defended a candidate against a rejection — fresh eyes are now mandatory.

**Failure modes:**
- Only one fresh-eyes prompt run.
- Fresh-eyes reviewer was the author (defeats the point).
- One clean round and then declaring done — must be two consecutive.

**Prompt module:**
> Dispatch the three verbatim fresh-eyes subagents (see [../../SKILL.md § Subagents § fresh-eyes-reviewer-{a,b,c}](../../SKILL.md)). Each is independent. Aggregate findings. Loop until two consecutive clean passes. The pattern: "fresh-eyes fix entries land *along with* the rejection of the author's defense."

**Quote-bank anchor:**
> "'fresh-eyes pass' — CC.md §37: A full re-review of recent code by an agent who didn't write it. Often surfaces a regression that the author rationalized away. The pattern: 'fresh-eyes fix' entries land *along with* the rejection of the author's defense." — MINING-1 §1

---

## 🗄 Ledger-Retire

**Question:** "Does this ledger entry name a concrete retry-condition predicate (not 'later', not 'if it seems important')?"

**Triggers:**
- Closing a perf candidate.
- Reviewing the negative ledger.
- An entry has been open for >60 days.

**Failure modes:**
- "We should revisit this later" — anti-vocabulary.
- "Tracked elsewhere" without a bead id.
- Rejected entry without status.

**Prompt module:**
> Use one of the 8 verbatim retry-predicate forms from [RETRY-CONDITION-VOCABULARY.md](RETRY-CONDITION-VOCABULARY.md). Name the specific gate, counter, or architectural dependency. If you cannot name one, you do not understand the rejection — return to ⟁ + ⬡.

**Quote-bank anchor:**
> "Retry only if a profiler attributes a clearly-above-noise share to <specific counter> on <wider workload shape>" — MINING-1 §2

---

## 🧪 Experiment-Design

**Question:** "Does this suspected gap have a hypothesis-minimal-repro-expected-signal-falsifiability-one-line-invocation-results-inline entry in the appropriate ledger?"

**Triggers:**
- Idea-wizard emits a candidate.
- Suspected gap surfaces in archaeology.
- Verbal "what if we…" in chat.

**Failure modes:**
- Hypothesis without falsifiability criterion.
- One-line invocation that requires 3 paragraphs of setup.
- Results not inlined into the experiment doc.

**Prompt module:**
> Write the experiment in [../experiments/EXPERIMENT-DESIGNS-TEMPLATE.md](../experiments/EXPERIMENT-DESIGNS-TEMPLATE.md) format. Required fields: hypothesis (one sentence), minimal repro (commands), expected signal (specific counter / pass rate / ratio threshold), falsifiability (what would prove the hypothesis WRONG), one-line invocation (a single shell command), results inline (after running).

**Quote-bank anchor:**
> "Every clever idea lands in `GAUNTLET_EXPERIMENT_DESIGNS.md` with hypothesis-minimal-repro-expected-signal-falsifiability-one-line-invocation." — [../../SKILL.md § Anti-Patterns](../../SKILL.md)

---

## 📐 Conformal-Band

**Question:** "Does the release decision use the distribution-free conformal LOWER bound and not the point estimate?"

**Triggers:**
- Release certification.
- Ratchet update.
- Workload distribution suspected non-Gaussian (heavy-tailed, bimodal, regime-shifting).

**Failure modes:**
- Point estimate cited instead of lower bound.
- Bayesian credible interval used in place of conformal band on a heavy-tailed workload.
- Band narrowed by "assuming Normality" — invalid for adversarial workloads.

**Prompt module:**
> Calibrate the conformal band from per-category residuals (frequentist vs Bayesian gap). `P(R_{n+1} ≤ q) ≥ 1 − α` for any distribution. The cost is wider intervals; the benefit is honesty under heavy-tailed/bimodal/regime-shifting distributions. Release uses the LOWER bound; intermediate dashboards may show the point estimate.

**Quote-bank anchor:**
> "Distribution-free finite-sample coverage. Calibrated from per-category residuals (frequentist vs Bayesian gap). `P(R_{n+1} ≤ q) ≥ 1 − α` for any distribution. Cost: wider intervals. Benefit: honest under heavy-tailed / bimodal / regime-shifting distributions." — MINING-2 §11

---

## 🎚 Raise-ULP-Tolerance

**Question:** "Has the ULP tolerance change been justified, scoped to the operator, and accompanied by a `gradcheck_max_rel_error` snapshot?"

**Triggers:**
- Numerical-Python or ML-System class candidate.
- A tensor diff fails by < 4 ULP.
- Reference upgrade changes one operator's accumulator.

**Failure modes:**
- Global ULP tolerance bump for a per-op fix.
- Tolerance change without `gradcheck_max_rel_error` capture.
- "Just barely fails" → bump tolerance, hide regression.

**Prompt module:**
> Open `docs/contracts/ulp_tolerance_v1.toml`. Find the operator row. Bump tolerance ONLY for that operator. Capture `gradcheck_max_rel_error` before and after. If `max_rel_error` increased, the tolerance change is a regression masquerading as a fix — escalate to ⊕.

**Quote-bank anchor:**
> "Per-op ULP tolerance table as `docs/contracts/ulp_tolerance_v1.toml`. Make `torch.use_deterministic_algorithms(True)` a `cargo test` invariant." — MINING-1 §8 FrankenTorch next-action

---

## 🪞 Engine-Identity-Guard

**Question:** "Does every emitted artifact have `EngineIdentity::{Subject,Oracle}` set and asserted-distinct at the comparator?"

**Triggers:**
- Authoring a new comparator.
- New oracle bridge.
- Test passes suspiciously fast or at 100% on a hard target.

**Failure modes:**
- Both sides of the comparator are the oracle.
- Subject identity string is "test-engine" not "<port>".
- `assert_ne!(subject_identity, reference_identity)` missing at harness entry.

**Prompt module:**
> Grep every comparator entry point for `EngineIdentity`. Each must assert subject ≠ oracle at runtime. Oracle preflight doctor checks the identity strings before the first test. Per-class: `subject_identity = "frankensqlite" / "frankenredis" / "frankentorch" / ...` and `reference_identity = "csqlite-oracle" / "redis-server-7.2.5-oracle" / "pytorch-2.X-oracle" / ...`.

**Quote-bank anchor:**
> "EngineIdentity Discriminator: const SUBJECT_IDENTITY_LABEL: &str = 'frankensqlite'; const REFERENCE_IDENTITY_LABEL: &str = 'csqlite-oracle'; Strict parity validation [...] Enforced at harness entry; prevents oracle-on-oracle false greens." — MINING-2 §3

---

## Composition Cheat-Sheet

The operators are deliberately overlapping — a single candidate typically needs 4–5 in sequence. The standard pipelines:

### Perf candidate (focused win in a hot loop)
```
⬡  → ⤴ → ⟁ → 🔁 → 🗄
```
Instrument the hot path; verify ≥0.1% MT8 attribution; triangulate across profilers; confirm both gates move in the same run window; write the ledger entry with a retry-condition predicate.

### Conformance divergence (mismatch surfaces in a metamorphic family)
```
⊙ → ⌘ → ⚠ → ⊕ → ⚖
```
Classify the divergence; minimize to 1-minimal; emit FailureBundle; enumerate isomorphic-rewrite fixes; apply ratchet (lower bound) to the candidate fix.

### Surface gap (reference added a new command/opcode/function)
```
✦ → 🧪 → ⚖
```
Enumerate the new surface item; design the experiment to test it on the subject; apply the ratchet with the new weighting.

### Release certification candidate
```
⊞ → 🪟 → 📐 → ⚖ → 🗄
```
Soak (full duration); fresh-eyes (two consecutive clean rounds); conformal band (lower bound); ratchet (Allow or Block); ledger any rejected/deferred items with predicates.

### Numerical-Python or ML-System optimization
```
⬡ → ⟁ → 🎚 → ⊕ → ⚖
```
Instrument the op; triangulate profile; if ULP raise is on the table, scope it; isomorphic rewrites; ratchet.

### Adversarial finding (counterexample from adversarial-search subagent)
```
⚠ → ⌘ → ⊙ → ⊕ → 🪟
```
FailureBundle the counterexample; minimize; classify; isomorphic rewrite; fresh-eyes the fix.

### Stale ledger sweep (60-day cass mining)
```
🗄 → 🧪
```
Reread every open ledger entry. If the retry-predicate has been satisfied since, run the experiment; if not, either tighten the predicate or retire as `Not worth retrying as a standalone patch`.

### Catching the cache-eviction class of bug
```
⬡ → ⊕ → ⤴ → 🔁
```
Instrument the cache; enumerate cache-key/invalidation-key dependencies (the Pattern-10 audit); MT8 attribution to confirm the gain isn't noise; both-gates-same-window.

### Catching a new oracle-on-oracle leak
```
🪞 → ◐ → ★
```
Engine-identity audit; rewire the oracle bridge; re-pin the reference version to make the rewire explicit in the contract.

### When the loop seems converged but the BOCPD says ShiftDetected
```
⊞ → ⚠ → ⌘ → 🧪
```
Soak more; bundle the shift evidence; minimize the window where the shift occurred; design experiments to attribute the regime change.

---

## Deep Review Operator Inheritance (Round 5 extension)

The gauntlet adds four deep-review operators (see [`DEEP-HYPOTHESIS-REVIEW.md`](DEEP-HYPOTHESIS-REVIEW.md)). To avoid glyph collisions with the gauntlet's existing 19, these operators use distinct glyphs in this file.

## △ Review-Score

**When to apply:** Phase 10 (idea-wizard winnow), Phase 11 (round-start ranking of open hypotheses), Phase 12 (tie-breaker between equally-scored remediation candidates).

**The pattern:** rank candidates by

```
   (expected mind-change × downstream option value)
   ─────────────────────────────────────────────────
   (time × cost × ambiguity × infrastructure-dependence)
```

Each factor scored 1-5. The winning candidate is the one that **deletes the most hypothesis space per token spent** — not the one that accumulates the most evidence.

**Concrete example** — Phase 10 candidate "differential-fuzz the WAL frame header parser":
- `expected_mind_change = 0.7` (probably surfaces 2-3 new divergences)
- `downstream_option_value = 0.9` (every conformance bead depends on parser correctness)
- `time = 3` (hours)
- `cost = 1` (rch fuzz worker; modest)
- `ambiguity = 1.2` (could surface false-positives if seed contract has bugs)
- `infrastructure_dependence = 0.8` (cargo-fuzz already installed)

Score = `(0.7 × 0.9) / (3 × 1 × 1.2 × 0.8)` ≈ `0.22`. Compare across candidates; pick top-K that fit the round budget.

**Failure modes:**
- Scoring optimism (every factor scored 5) — pushes back: require a comparator (at least one other candidate scored lower).
- Confusing "evidence accumulation" with "mind change" — `expected_mind_change` is about *deleting hypothesis space*, not "we'll learn something". Most experiments learn nothing decisive.
- Ignoring the denominator — a high-cost high-confidence candidate often loses to a cheap-and-noisy one because score scales linearly with cost.

**Cross-reference:** [`DEEP-HYPOTHESIS-REVIEW.md § 1`](DEEP-HYPOTHESIS-REVIEW.md), [`RUBRICS.md § Perf-pillar additional gate`](RUBRICS.md) (where the gauntlet uses Impact × Confidence / Effort as a closely-related shape).

## ⊚ Productive-Ignorance

**When to apply:** Phase 11 mid-loop when the swarm seems "in-phase" with consensus (review pathology: "Consensus collapse" or "Productive-ignorance starvation"). Phase 14 T3+ when triangulation produces full-agreement on every finding (no disagreement signal).

**The pattern:** Deliberately spawn ONE cc_4 pane with MINIMAL onboarding:
- NO negative-ledger preamble.
- NO prior round's findings.
- NO synthesizer summary.
- ONLY: the project's spec sources + the immediate question + AGENTS.md.

The instruction includes: *"Read minimally and reason from first principles. Do not let yourself be primed by what other panes have concluded."*

**Concrete example** — Round 6 of a gauntlet on a SQL-class port. Every fresh-eyes pane has reported the same root cause for a PRAGMA divergence ("the dispatch table is missing entry X"). Productive-ignorance pane reads only the failing test + the SQL spec, reasons from first principles, and reports: *"The dispatch table is fine; the divergence is in the canonicalization step — your normalize_value() drops the underscore variant of PRAGMA names but the reference accepts both."* This is the wider-net finding the prior consensus missed.

**Failure modes:**
- Onboarding-creep: someone adds "just one document" to the productive-ignorance pane's reading list. Defeats the purpose; the pane is now primed.
- The ignorant pane requesting full context — DENY (with explanation). The friction is the point.
- Using productive-ignorance for routine work — it's expensive (the pane often misses obvious things). Reserve for the moments when consensus is suspicious.

**Cross-reference:** [`DEEP-HYPOTHESIS-REVIEW.md § 2`](DEEP-HYPOTHESIS-REVIEW.md), [`AGENT-FUNGIBILITY.md`](../orchestration/AGENT-FUNGIBILITY.md).

## † Theory-Kill

**When to apply:** Phase 11 close of every round. Phase 14 fresh-eyes finding that a previously-OPEN hypothesis is decisively refuted. ANY time the ledger has a `NO_EVIDENCE` outcome that hasn't been formally closed.

**The pattern:** Refuted hypotheses are CLOSED IMMEDIATELY with a retry-condition predicate. No "theory-zombies" — hypotheses that failed their falsifier but linger OPEN because nobody wanted to formally kill them.

```markdown
### YYYY-MM-DD — <hypothesis name> — KILLED
- target_pillar: <perf | conformance | surface>
- falsifier: "<the predicate that would resurrect this hypothesis>"
- evidence_artifact_paths:
  - <path to the experiment that refuted it>
- retry_condition_predicate: "<ONE of the 8 verbatim forms from RETRY-CONDITION-VOCABULARY.md>"
- bead_id: <bd-...>
```

**Concrete example** — Hypothesis: "GROUP BY HAVING NULL semantics divergence is caused by missing 3VL handling in the aggregator". Phase 11 round 4 ran an experiment that proved the divergence persists with 3VL correctly handled. Theory-kill: write CONFORMANCE_NEGATIVE_RESULTS.md entry with retry_condition_predicate "Reconsider only if a profiler attributes a clearly-above-noise share to the aggregator dispatch when 3VL is enabled" — and close the bead.

**Failure modes:**
- Open-ended deferrals ("we'll get to it later") — banned vocabulary per [`RETRY-CONDITION-VOCABULARY.md`](RETRY-CONDITION-VOCABULARY.md).
- Refusing to kill because "maybe we missed something" — that's what retry-condition predicates ARE for. Kill it now; resurrect when the predicate holds.
- Killing a hypothesis that wasn't actually refuted (the experiment was inconclusive, not refutation) — re-classify as `NEEDS_REFINEMENT` instead and design a sharper experiment.

**Cross-reference:** [`pattern:185-RETRY-CONDITION-PREDICATE`](../patterns/185-RETRY-CONDITION-PREDICATE.md), [`pattern:180-NEGATIVE-LEDGER`](../patterns/180-NEGATIVE-LEDGER.md), [`DEEP-HYPOTHESIS-REVIEW.md § Pathology Triggers`](DEEP-HYPOTHESIS-REVIEW.md).

## ∿ Dephase

**When to apply:** Phase 14 T3+ when triangulation produces full-agreement consensus across all lenses (review pathology: "Adversarial collapse"). Phase 11 when adversarial-search returns 0 counterexamples for 5+ rounds on the same gates.

**The pattern:** Rotate the lens list or model mix to introduce disagreement signal. The swarm is most informative when not in-phase; full consensus is suspicious (likely all panes reading the same context).

Concrete moves:
- Rotate the triangulation lens list (per [`TRIANGULATION.md`](TRIANGULATION.md)) — replace "correctness" with "performance-edge" lens for one round.
- Swap model mix (per [`AGENT-FUNGIBILITY.md`](../orchestration/AGENT-FUNGIBILITY.md)) — if the swarm was all `cc`, add `cod` + `gmi` for round N+1.
- Dispatch one ⊚ Productive-Ignorance pane.
- For adversarial-search specifically: add a fresh red-team-attacker pass with a new lens (e.g., "agent-honesty-bias" → "cross-pillar-coupling" → "temporal-monotonicity").

**Concrete example** — Round 7 fresh-eyes. All three reviewers (a/b/c verbatim prompts) returned "no findings" for 2 rounds straight. Dephase: rotate from `cc` to `cod` for variant-a, swap variant-b's lens from "AGENTS.md compliance" to "first-principle algorithmic correctness", add a ⊚ Productive-Ignorance pane. Round 8 fresh-eyes produces 7 new findings.

**Failure modes:**
- Dephasing too aggressively (every round) — creates noise without signal. Reserve for genuine consensus collapse.
- Dephasing the synthesizer (not the investigators) — the synthesizer's job is to converge; the investigators' job is to diverge. Wrong layer.
- Treating disagreement signal as "the dephased pane is wrong" — disagreement IS the value; investigate the disagreement, don't dismiss it.

**Cross-reference:** [`DEEP-HYPOTHESIS-REVIEW.md § 2 / § Pathology Triggers`](DEEP-HYPOTHESIS-REVIEW.md), [`../../subagents/triangulator.md`](../../subagents/triangulator.md), [`../../subagents/red-team-attacker.md`](../../subagents/red-team-attacker.md).

---

### Review-glyph cross-walk

| Review glyph | Review name | Gauntlet glyph (this file) |
|:---:|---|:---:|
| `△` | Review-Score | `△` (same; no collision) |
| `⊙`† | Productive-Ignorance | `⊚` (gauntlet `⊙` is Debounce-False-Positive) |
| `†` | Theory-Kill | `†` (same; no collision) |
| `∿` | Dephase | `∿` (same; no collision) |

†This file uses `⊚` to avoid collision with the gauntlet's own `⊙ Debounce-False-Positive`.
