# ANTI-PATTERNS — The Full Catalog

> Every entry: **(a)** verbatim quote from mining when available, **(b)** Symptom (how it manifests in the wild), **(c)** Detection (gate or script that catches it), **(d)** Fix (operator or section to apply).

The list is **load-bearing**: the keep-gate rules in [KEEP-GATE-RULES.md](KEEP-GATE-RULES.md), the convergence rule in [CONVERGENCE.md](CONVERGENCE.md), and the operator library in [OPERATORS.md](OPERATORS.md) all exist *because* these failure modes happened, were rejected, and were entered into the ledger. Cross-link to the source row in parent [SKILL.md § Anti-Patterns](../../SKILL.md).

---

## Tier 1 — Methodology Anti-Patterns (from CC.md §87.4)

### A1. Optimize without profiling

**Quote (CC.md §87.4, mined MINING-1 §9):** "Wastes effort on non-hotspots."

**Symptom.** A bead opens, an agent writes "the parser is probably slow", code lands, microbench moves by 8%, primary score doesn't move. No flamegraph in the proof pack.

**Detection.** `scripts/run-bench-matrix.sh <target> <workspace> --gate profile-first`; the Phase-13 proof-pack review refuses to accept a perf-bead close unless `artifacts/{bead_id}/proof_pack/baseline_profile.{flame.svg,samply.json}` exists and rank ≤5.

**Fix.** Apply `⬡ Instrument-Hot-Path` (operator) → run [tooling/BENCH-TOOLCHAIN.md § profile-first contract](../tooling/BENCH-TOOLCHAIN.md). 19 required proof-pack fields enumerated in [methodology/KEEP-GATE-RULES.md](KEEP-GATE-RULES.md).

---

### A2. Multiple changes per commit

**Quote (CC.md §87.4):** "Can't isolate regressions."

**Symptom.** A revert is forced because round-N caught a regression but round-N+1 can't bisect — the suspect commit bundles 4 unrelated changes.

**Detection.** `scripts/bead-graph-validator.sh <target> --output-root <workspace>` enforces the dependency graph; the proof-pack review flags any bead whose commit touches ≥2 distinct hot-path files without a per-file delta artifact.

**Fix.** One-lever scope mandated by proof-pack card. A "scope-creep" rejection forces split-into-N-beads.

---

### A3. Assume improvement

**Quote (CC.md §87.4):** "Must measure before/after."

**Symptom.** "This should be faster because we removed a clone." No baseline run, no diff. Bead closes; pass-over-pass surfaces a regression two passes later.

**Detection.** Pass-over-pass gate against `.bench-history/<bench>.latest.json` (committed). A close with no delta_summary.json fails the gate.

**Fix.** `🔁 Pass-Over-Pass-Gate` operator. See [methodology/KEEP-GATE-RULES.md § both-gates-same-run-window](KEEP-GATE-RULES.md).

---

### A4. Change behavior "while we're here"

**Quote (CC.md §87.4):** "Breaks isomorphism guarantee."

**Symptom.** A perf bead also "fixes" a typo, "improves" an error message, "tightens" a tolerance. Oracle suite catches one mismatch; "we'll update the snapshot" — quietly breaking the parity contract.

**Detection.** `selections= byte-identical` check + oracle differential delta = 0 required for any rejection of "perf within noise" — if behavior changes, the bead is *different question entirely*.

**Fix.** `behavior-preserving` keep-gate rule. See [methodology/KEEP-GATE-RULES.md § behavior-preserving](KEEP-GATE-RULES.md). Behavior changes route through Phase 6 oracle, not Phase 5 perf.

---

### A5. Skip golden output capture

**Quote (CC.md §87.4):** "No regression detection."

**Symptom.** A refactor lands without insta snapshot regeneration; future regression slips past CI because nothing to compare against.

**Detection.** `scripts/run-conformance-suite.sh <target> <workspace> --gate golden-captured` plus the golden-artifact review refuses if Tier 1/2/3 artifact directory is empty for touched modules.

**Fix.** `/testing-golden-artifacts` skill; three-tier equivalence required by [Polish Bar § Three-tier equivalence](../../SKILL.md).

---

## Tier 2 — Implicit Ledger Anti-Patterns (from MINING-1 §9, CC.md §40)

### A6. "No bounded micro-lever found"

**Quote (CC.md §40):** "Optimization effort on sub-0.1% hotspots below noise floor."

**Symptom.** Agent picks a frame at 0.05% MT8 self-time, spends 4 hours, lands a +1.8% local change that's invisible in the broad bench.

**Detection.** Profile-card scorer rejects EV when hotspot rank ≤5 BUT self-time <0.1%. The "**micro-lever trap**" (CC.md line 2393): "A frame at 0.05% is below the noise floor of the bench (cv_pct 3-5%); the micro-lever trap. A frame at 1% is rare and high-value. The 0.1-1% range is where productive optimization work happens."

**Fix.** `⤴ Attribute-To-MT8` operator + 0.1% threshold rule in [methodology/KEEP-GATE-RULES.md § MT8](KEEP-GATE-RULES.md). Retire to ledger with retry-condition: *"Retry only if a profiler attributes a clearly-above-noise share to <specific counter> on <wider workload shape>."*

---

### A7. "Focused improved, broad worsened"

**Quote (CC.md §40):** "Improved targeted workload but regressed primary score."

**Symptom.** Narrow bench (10K DELETE) wins by 22%, comprehensive-bench primary score drops 4%. Author claims "the narrow win is real" — but the broad gate moved the wrong way.

**Detection.** Both gates committed in same run window (same git, same `target/`, same machine, same minute). Any divergence between focused-direction and broad-direction is auto-reject.

**Fix.** `both gates must move in the same run window` keep-gate rule. See parent SKILL.md § Keep-Gate Rules row "Both gates move in same run window".

---

### A8. "Rejection by omission"

**Quote (MINING-1 §9):** "Diving in without audit of whether hotspot already appears in ledger."

**Symptom.** Agent reinvents an optimization that's been rejected three times — but never read the ledger.

**Detection.** `scripts/mine-ledger.sh` + `scripts/mine-cass-cross-machine.sh` run as pre-flight on every perf bead; refuses to proceed if blocker entries unread.

**Fix.** Negative-Ledger Mandate paragraph in target's AGENTS.md (see `assets/agents-md-mandate-paragraph.md`). The mandate (MINING-1 §3): *"For major perf campaigns, agents must also mine: last 60 days of CASS session history, recent commits, perf artifacts, failed/rejected/slower/regressed terms. If CASS or the ledger is unavailable or reserved, the agent must record a blocker or patch-ready entry rather than silently skipping the step."*

---

### A9. "Cold-start outlier"

**Quote (CC.md §40):** "Improvement based on first sample after rebuild."

**Symptom.** First sample post-`cargo clean && cargo build --profile release-perf` shows a 30% improvement; later samples regress to baseline. The 30% is warmup noise, not signal.

**Detection.** `WARMUP_ITERS = 2` discards cold-start. `measure()` (CC.md §1.2) hard-codes this; any custom timing loop that omits warmup is flagged during Phase-5 bench-author review or by a project-local bench validator.

**Fix.** Use the canonical `measure()` from [tooling/BENCH-TOOLCHAIN.md](../tooling/BENCH-TOOLCHAIN.md). Never roll your own.

---

### A10. "Noise-band claim"

**Quote (CC.md §40):** "Win measured within ±3-5% confidence band."

**Symptom.** Agent reports "+2% on point-lookup gain"; bench cv_pct is 3-5%. The gain sits *inside* the noise band.

**Verbatim ledger example (CC.md line 567):** *"Reverted — within-noise. Reusing find_rowid_equality_term for the RowidLookup probe (vs 2nd scan in extract_access_path_probe) was behavior-preserving (identical selection counts; 13 probe/21 rowid/35 access_path tests pass) but point-lookup gain ~2% sits in the ±3-5% bench noise band."*

**Detection.** `cv_pct` reported on every microbench; gate refuses keep if `delta_pct ≤ cv_pct` (i.e., signal does not exceed noise).

**Fix.** Run the workload at higher iteration count to shrink cv_pct, OR reject as "within noise" with the retry-condition: *"Retry only if this workload class exhibits measurable <property> below <threshold>."*

---

### A11. "Single-cell extraction"

**Quote (MINING-1 §9):** "Winning on one cell while hidden cells regress."

**Symptom.** 10K-row READ improves; 1K-row READ regresses; agent reports only the cell that won.

**Detection.** Full bench matrix (orthogonal axes: workload size × value shape × concurrency, MINING-3 §1.4). Per-category geomean regression gate (`−10%`) catches a single hidden cell that drags a category.

**Fix.** Always run the full matrix. See [tooling/BENCH-TOOLCHAIN.md § three-orthogonal-axes](../tooling/BENCH-TOOLCHAIN.md).

---

### A12. "Plausible hypothesis without profile"

**Quote (CC.md §40):** "'Parser is slow' without ranked hotspot table."

**Symptom.** Agent's perf bead opens with prose claim, no flamegraph. Lands; primary score moves by <noise.

**Detection.** Proof-pack card scorer rejects bead opening without baseline_profile.

**Fix.** Same as A1; `⬡ Instrument-Hot-Path`. Also: `/profiling-software-performance` skill ("Ranked evidence before any optimization. No hotspot list → no change.").

---

### A13. "Architectural change dressed as micro-optimization"

**Quote (CC.md §40):** "Localized fix when root cause structural. Ledger rejects with 'reconsider only inside broader X redesign'."

**Symptom.** DELETE perf bead patches a single Vdbe instruction; the real fix requires DML mutation operator redesign (architectural).

**Detection.** When the ledger has 3+ entries pointing at the same hotspot with "reconsider only inside <X> redesign" — new candidates touching that hotspot must show they're part of <X>, not standalone.

**Fix.** Retry-condition vocabulary form 2: *"Reconsider only inside the broader <X> redesign."* See [methodology/RETRY-CONDITION-VOCABULARY.md](RETRY-CONDITION-VOCABULARY.md).

---

### A14. "Micro-optimization of a fused design"

**Quote (CC.md §40):** "Optimizing one half of multi-part fused operator."

**Symptom.** Optimizing `insert()` half of a `fused empty-root direct-insert page builder` without touching the page-build half. Half-optimization yields no win, breaks future fused-design redesigns.

**Detection.** `fused-design target` keyword in the code marks paths as architecturally unified; any bead targeting only one half is rejected.

**Fix.** Identify fused-design markers (grep for `// fused-design:` comments); route to architecture redesign.

---

### A15. "Behavior-changing 'correctness-abandoned' passed as performance"

**Quote (MINING-1 §9):** "Optimization changes behavior (fails oracle tests)."

**Symptom.** Perf bead lands, oracle suite fails; agent claims "the oracle is wrong, the new behavior is more efficient and the old behavior was a quirk".

**Detection.** `correctness-abandoned` is a status: killed *before* perf measurement because correctness failed. These do **not** earn a perf ledger entry — they earn a beads bug fix. Differential V2 + EngineIdentity catches divergence.

**Fix.** `behavior-preserving` is a hard prerequisite. See A4.

---

### A16. "No retry condition written"

**Quote (CC.md §40):** "Rejection without explaining what evidence would change decision."

**Symptom.** Ledger entry says "rejected — slower"; nothing else. Six months later, same idea reappears, agent has no way to evaluate whether anything changed.

**Detection.** `scripts/mine-ledger.sh --lint <ledger.md>` rejects entries missing the retry-condition predicate.

**Fix.** Mandatory retry-condition predicate; one of 8 verbatim forms in [methodology/RETRY-CONDITION-VOCABULARY.md](RETRY-CONDITION-VOCABULARY.md).

---

### A17. "Rerun never recorded in ledger"

**Quote (MINING-1 §9):** "Attempting same idea without checking ledger."

**Symptom.** Same agent tries same idea twice in two weeks because previous attempt wasn't ledgered.

**Detection.** `scripts/mine-cass-cross-machine.sh` catches the duplicate by grepping 60-day cass history.

**Fix.** Every attempt — kept *or* rejected — gets a ledger entry (CC.md opening: *"add an entry whenever a candidate is abandoned, reverted, or kept out of the tree because the benchmark matrix did not move in the intended direction"*).

---

## Tier 3 — Metamorphic Anti-Patterns (from MINING-1 §10, /testing-metamorphic)

### A18. "Metamorphic relation too weak"

**Quote (MINING-1 §10):** "`SetEquivalence` when `ExactRowMatch` is provably sound."

**Symptom.** A predicate-rewrite transform is wrapped with `SetEquivalence` ("same set of distinct rows") when `ExactRowMatch` ("same rows, same order") is the actual provable invariant. Test passes; subtle ordering bugs slip through.

**Detection.** Mutation-testing harness plants 5 known-divergent transforms; each `EquivalenceExpectation` must catch the planted bug at the tightest level. Loose relations let mutations through.

**Fix.** Strengthen to tightest provable relation: `ExactRowMatch > MultisetEquivalence > SetEquivalence > TypeCoercionEquivalent`. See `crates/fsqlite-harness/src/metamorphic.rs` (MINING-2 §4).

---

### A19. "Metamorphic relation without soundness proof sketch"

**Quote (MINING-1 §10):** "Landing transform without explaining why rewrite preserves semantics."

**Symptom.** New `TransformFamily::Structural` operator added; no comment, no proof sketch. Two weeks later it's miscategorized as `Literal` by a refactor.

**Detection.** PR review checklist: every new transform must include a 3-5 line proof sketch (axiom A → axiom B → therefore preserves <relation>).

**Fix.** Treat each transform like a small theorem. See `/lean-formal-feedback-loop` skill ("Treat proof friction as evidence.").

---

### A20. "Mutation testing validation skipped"

**Quote (MINING-1 §10):** "Claiming relation is effective without proving catches planted bugs."

**Symptom.** Metamorphic suite is "comprehensive" but mutation kill-rate is 0% — no planted bugs ever caught.

**Detection.** `scripts/run-conformance-suite.sh <target> <workspace> --mutation-test` plants N mutations; kill-rate <80% fails the gate once the target project has implemented mutation fixtures.

**Fix.** Mutation testing as a first-class gate alongside the corpus. See `/testing-metamorphic` skill (parent SKILL.md proprietary-skills enumeration).

---

## Tier 4 — Process / Coordination Anti-Patterns (from parent SKILL.md)

### A21. Cherry-picked baseline

**Quote (parent SKILL.md):** "The kept win evaporates next pass."

**Symptom.** Agent runs bench 10 times, reports best result, commits, doesn't commit `.bench-history`. Next pass shows regression because the "baseline" was the cherry-picked max.

**Detection.** `.bench-history/<bench>.latest.json` is a committed file; pass-over-pass diff is mechanical, not narrative.

**Fix.** "Pass-over-pass gate is a *file*. You can't bench on your machine, see a 30% drop, and quietly not commit." (MINING-3 §4).

---

### A22. "It works on my machine" perf claim

**Quote (parent SKILL.md):** "Different host = different ratio."

**Symptom.** Agent on a 64-core machine reports a 3x win; CI on 8-core box reports flat. The 64-core ratio is anomalous (per-thread contention masked by core surplus).

**Detection.** `concurrent_mode_default_guard.txt` + host fingerprint in artifact lane (MINING-3 §1.9). Pass-over-pass requires same `host_id`.

**Fix.** Pin placement profile (`baseline_unpinned | recommended_pinned | adversarial_cross_node`). Both gates same minute, same host.

---

### A23. Population inside timed window

**Quote (parent SKILL.md):** "Free win disappears under realistic load."

**Symptom.** `measure()` includes the `INSERT 100000 rows` setup AND the actual DELETE measurement in the timed window — the "delete time" is dominated by setup, optimization invisible.

**Detection.** `measure_with_teardown()` discipline (MINING-3 §1.3): *"The teardown call is *outside* the timed window — `start.elapsed()` is captured *before* `teardown()` runs."*

**Fix.** Use `measure_with_teardown()`; verify teardown ordering in the Phase-5 bench-author review or a project-local bench validator.

---

### A24. Agreement-by-error-message-string

**Quote (parent SKILL.md):** "Two engines failing differently look 'agreed'."

**Symptom.** Frank returns "constraint failed"; rusqlite returns "UNIQUE constraint failed: t.id"; agent compares strings, marks as disagreement. Or worse — both return some error, agent marks as agreement when they're different errors.

**Detection.** Scenario template rule (MINING-2 §1): *"Both-error = agreement REGARDLESS of message; one-error-one-OK = hard failure."* `MismatchClassification::TrueDivergence` is the only CI-failing class; others go to triage queue.

**Fix.** Hard-coded in the 30-line scenario template; never roll a custom comparator.

---

### A25. Oracle-against-self

**Quote (parent SKILL.md):** "Apparent 100% pass rate."

**Symptom.** Oracle preflight broken; both subject and oracle resolve to the *same* rusqlite library; differential reports 100% agreement (trivially).

**Detection.** `EngineIdentity` discriminator (MINING-2 §3): `SUBJECT_IDENTITY_LABEL = "frankensqlite"`, `REFERENCE_IDENTITY_LABEL = "csqlite-oracle"`. Strict parity validation at harness entry.

**Fix.** Oracle preflight doctor (MINING-2 §13) checks identity strings AND version match BEFORE any comparison runs. See [tooling/ORACLE-TOOLCHAIN.md § EngineIdentity](../tooling/ORACLE-TOOLCHAIN.md).

---

### A26. Size-optimized release profile for perf

**Quote (MINING-3 §1.7):** "Never `--release` (size-optimized) for any perf claim."

**Symptom.** Agent runs `cargo bench --release`; LTO is `false`, codegen-units high, debug stripped. Numbers are 30% off the production profile.

**Detection.** Every artifact carries `cargo_profile = "release-perf"`; pass-over-pass enforces match.

**Fix.** `release-perf` profile (MINING-3 §1.7):
```toml
[profile.release-perf]
inherits = "release"
opt-level = 3
lto = "thin"
codegen-units = 1
debug = "line-tables-only"
strip = false
RUSTFLAGS = "-C force-frame-pointers=yes"
```

---

### A27. Concurrent mode silently off

**Quote (MINING-3 §1.9):** "Feb 2026 an agent silently disabled concurrent mode; project didn't notice until pass-over-pass gate flipped."

**Symptom.** "MVCC perf win" was running serial; the win is fake.

**Detection.** `concurrent_mode_default_guard.txt` (or project-equivalent) in every artifact lane:
```
CONCURRENT_MODE_DEFAULT=true
GIT_SHA=<sha>
TIMESTAMP=<ISO-8601>
```

**Fix.** Every artifact lane drops the proof file. For Redis: `RESP_VERSION=3`. For Torch: `CUDA_DEVICE_COUNT`.

---

### A28. cv_pct dropped from report

**Quote (parent SKILL.md):** "Noise looks like signal."

**Symptom.** Bench report omits cv_pct; agent eyeballs delta as significant.

**Detection.** JSON v3 report schema requires `cv_pct` field per row; missing → schema validator rejects.

**Fix.** Every microbench reports cv_pct; `>5%` is noise (see A10).

---

### A29. Flake masquerading as throughput win

**Quote (parent SKILL.md):** "Once-in-five-runs result becomes 'the new baseline'."

**Symptom.** Agent runs 5 trials, takes the best, commits. Pass-over-pass surfaces regression next pass.

**Detection.** Median + MAD detector (MINING-3 §9): `Median(p50_samples) as baseline; MAD = Median(|sample - median|) as spread`. Distribution-free, outlier-robust.

**Fix.** Never max; always median. See `crates/fsqlite-harness/src/performance_regression_detector.rs`.

---

### A30. "Recent research" without a queue

**Quote (parent SKILL.md):** "Discovery dies in the chat scrollback."

**Symptom.** Agent reads paper, says "we should try this", does nothing. Idea evaporates.

**Detection.** Every clever idea must land in `GAUNTLET_EXPERIMENT_DESIGNS.md` with hypothesis-minimal-repro-expected-signal-falsifiability-one-line-invocation. The advanced-methods miner keeps the queue.

**Fix.** Apply `🧪 Experiment-Design` operator. See [experiments/EXPERIMENT-DESIGNS-TEMPLATE.md](../experiments/EXPERIMENT-DESIGNS-TEMPLATE.md).

---

### A31. Communication purgatory

**Quote (parent SKILL.md):** "Agents wait on each other forever."

**Symptom.** Agent A waits for Agent B's result; B is blocked on C; C is dead. Hours wasted in synchronous "are you done yet" reads.

**Detection.** MCP Agent Mail thread IDs per phase: `gauntlet-<run-id>-<phase>-<bucket>`. Reservations via `tool://comprehensive-bench`, `tool://oracle-runner`, etc.

**Fix.** Async-only; thread-IDs in [orchestration/ORCHESTRATION.md](../orchestration/ORCHESTRATION.md). Never block on synchronous read.

---

### A32. Tidying up other agents' edits

**Quote (parent SKILL.md):** "Destroys parallel work."

**Symptom.** Agent A sees unfamiliar diff in workspace; reverts it as "cleanup". A was concurrently working in another lane.

**Detection.** Reservations + lane assignment (cc_1..cc_4 convention).

**Fix.** "Treat unfamiliar changes as your own; never stash / revert / overwrite other agents' work." (parent SKILL.md row).

---

### A33. Reading entire file instead of grep-first

**Symptom.** Agent burns context reading 6000-LOC files to find one function.

**Detection.** Self-imposed; flagged by /codebase-archaeology skill ("rg-optimized" sister skill).

**Fix.** `rg` for shortlist → `ast-grep` for AST shape → `Read` only the lines needed.

---

### A34. Hallucinating a function that doesn't exist

**Symptom.** Skill recommends `fsqlite::FooBar::optimize()` — function doesn't exist; recommendation rots.

**Detection.** PR review must `rg` for every named symbol before mention.

**Fix.** Before recommending a file/function/flag, grep for it.

---

### A35. Writing prose where structured table is required

**Symptom.** Robot-emitting command returns natural-language paragraphs; downstream parser breaks.

**Detection.** Schema validator on JSON output paths.

**Fix.** Robot commands always emit machine-readable JSON; the markdown is the human view.

---

### A36. Running bare `cass` / `bv` / `cargo bench` / `cargo test --workspace` in automated session

**Symptom.** Automated agent invokes `cass` (TUI) → hangs. Or `cargo test --workspace` on a 12-crate project → hammers host for hours.

**Detection.** Hook routing in [orchestration/ORCHESTRATION.md § automation guards](../orchestration/ORCHESTRATION.md).

**Fix.** `cass --robot`, `bv --robot-*`, `cargo bench --bench <one>`, `cargo test -p <one-crate>`. Never bare invocations in agent loops.

---

## Cross-Reference Table

| Anti-pattern | Glyph | Fix-section |
|---|---|---|
| A1, A12 (no profile) | `⬡` | [BENCH-TOOLCHAIN.md](../tooling/BENCH-TOOLCHAIN.md) |
| A2 (multi-change) | — | proof-pack card one-lever scope |
| A3, A21, A29 (no/cherry baseline) | `🔁` | [KEEP-GATE-RULES.md](KEEP-GATE-RULES.md) |
| A4, A15 (behavior change) | — | [KEEP-GATE-RULES.md § behavior-preserving](KEEP-GATE-RULES.md) |
| A5 (no goldens) | — | three-tier equivalence |
| A6 (micro-lever) | `⤴` | [KEEP-GATE-RULES.md § MT8](KEEP-GATE-RULES.md) |
| A7 (focused vs broad) | `🔁` | both-gates rule |
| A8, A17 (ledger skip) | `🗄` | [RETRY-CONDITION-VOCABULARY.md](RETRY-CONDITION-VOCABULARY.md) |
| A9 (cold-start) | — | `WARMUP_ITERS = 2` |
| A10, A28 (noise / cv) | — | cv_pct gate |
| A11 (single-cell) | — | full matrix |
| A13, A14 (architectural) | `⊕` | [REMEDIATION-PATTERNS.md](../remediation/REMEDIATION-PATTERNS.md) |
| A16 (no retry condition) | `🗄` | [RETRY-CONDITION-VOCABULARY.md](RETRY-CONDITION-VOCABULARY.md) |
| A18, A19, A20 (metamorphic) | `⊙` | [ORACLE-TOOLCHAIN.md § MismatchClassification](../tooling/ORACLE-TOOLCHAIN.md) |
| A22 (host) | `⚠` | [IDENTITY-AND-REPRODUCIBILITY.md](IDENTITY-AND-REPRODUCIBILITY.md) |
| A23 (timed-window) | — | `measure_with_teardown` |
| A24 (error-string) | `⊙` | scenario template |
| A25 (oracle-self) | `🪞` | EngineIdentity |
| A26 (release profile) | — | `release-perf` |
| A27 (concurrent off) | — | `concurrent_mode_default_guard.txt` |
| A30 (no queue) | `🧪` | [EXPERIMENT-DESIGNS-TEMPLATE.md](../experiments/EXPERIMENT-DESIGNS-TEMPLATE.md) |
| A31, A32 (coordination) | — | [ORCHESTRATION.md](../orchestration/ORCHESTRATION.md) |
| A33, A34, A35, A36 (hygiene) | — | per-row above |

---

**End of catalog.** When in doubt: read the ledger before you touch the hot path. Add an entry whenever a candidate is abandoned, reverted, or kept out of the tree. Write the retry-condition predicate.
