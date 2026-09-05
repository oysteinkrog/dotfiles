# DESIGN-PHILOSOPHY.md — Why This Skill Works The Way It Does

<!-- TOC: The core failure mode | Eight design principles | What we don't do (and why) | Trade-offs we accept | Inheritance from sibling skills -->

> Operationalizing-expertise (Track A) teaches you to write down *what experts do*. This file writes down *what experts believe* — the priors that, if you don't share them, will lead you to redesign the audit and produce something subtly wrong.

---

## The core failure mode this skill is built around

A bead's `status: closed` is **machine-readable**. Whether the bead was *actually* completed is **not**.

Long-running multi-agent projects accumulate a population of beads where the gap between the two is wide. Three forces drive this:

1. **Pressure to clear the active list.** `br ready` shows ready work; closing beads is hygiene; agents close to make the queue manageable.
2. **Optimism about future passes.** "I'll wire this up next session" is sincere when written; rarely fulfilled.
3. **Lack of an audit step.** Without verification, status drifts away from reality. Drift is not adversarial — it's entropy.

This skill is the audit step. It exists because **no individual bead-close decision is wrong**, but the *cumulative* effect of unverified closes is project-corrosive.

---

## Eight design principles

### 1. Determinism over heuristics

Two runs of the audit, given the same inputs and the same rubric, produce **the same scores**. Subjective judgment lives in the rubric (which is published, versioned, and SHA-pinned), not in the scoring code.

Why: heuristics are unfalsifiable. A scorer that says "this looks bad" cannot be argued with. A scorer that says "rubric §3 BLOCKING penalty: -50 because theater.json#finding.4 cites src/parser.rs:312 returning Default::default() in the error-recovery branch the bead's design notes required" is auditable. If you disagree, you change the rubric — not the scorer.

### 2. Per-bead, not project-global

Coverage, theater density, dependency anomalies — all measured **per-bead**. A project at 85% line coverage may have a bead whose specific code is 12%-covered. The bead's score depends only on its own files.

Why: project-global metrics let bad beads hide in good neighborhoods. The point of the audit is to catch the *specific* false-closed beads, not produce a project quality score.

### 3. Re-run, don't read

Phase 4 always re-executes claimed proofs. Stale CI logs are inadmissible. A test that passed yesterday means nothing in this audit.

Why: the most common theater is "the test passed once when I added it; it never ran again." Code drift since then may have invalidated it. Re-running is the only way to catch this.

### 4. Theater invalidates surrounding "passes"

A `BLOCKING` finding in Phase 5 retroactively invalidates the corresponding `PASS` verdicts in Phase 4. The scorer cross-references `theater.json#findings[*].invalidates_phase4_check` and zeros the affected dimension.

Why: a test that exits 0 *because the implementation short-circuits* is theater squared. Phase 4's exit-code-based judgment is necessary but not sufficient. Phase 5 catches the meta-level lie.

### 5. The artifact is the evidence

Every scored dimension cites a file:line, a commit SHA, a test name, or a raw log path. Vibes don't count. A scorecard with no citations is invalid.

Why: this is what makes the audit auditable. Phase 10 spot-checks 5 random scorecards by independently re-deriving the score from the cited evidence. If the citations don't support the score, the rubric is ambiguous, the scorer is biased, or the operator pipeline drifted.

### 6. Audit dirs are sacred

Never delete a prior pass. One commit per pass. History is the convergence signal — without two consecutive passes' artifacts, convergence is meaningless.

Why: convergence is the goal, and convergence requires comparison. Deleting a pass deletes the comparison baseline. Even a "broken" pass — one with obvious bugs — is informative when compared to the next clean pass.

### 7. Remediation is graph maintenance, not implementation

Phase 9 reopens beads or creates completion-debt beads. It **does not silently fix code**. Implementation happens in a separate session by an agent who picks up the new bead.

Why: silently fixing during the audit destroys the value of the audit. The remediation bead carries the verbatim missing-items list — a future implementer (often an LLM agent) needs that visible scope. If the audit fixed it, the visibility is lost and the next audit will rediscover the same gap because the bead graph still says the original is closed.

### 8. The audit itself is auditable

Phase 10's fresh-eyes pass independently spot-checks 5 random scorecards. If the scorer disagreed by > 50 points on any of them, the rubric is ambiguous, the scorer is biased, or the operator pipeline drifted. Either way, the audit's own artifacts feed the next pass's calibration.

Why: every layer of the system needs an audit. The bead graph is audited by us; we are audited by Phase 10. Phase 10's spot-checks are recorded so they themselves can be reviewed across passes — meta-meta-audit if it ever becomes necessary.

---

## What we don't do (and why)

### We don't ship a unified "score the project" number

Tempting, but wrong. A project-wide score lets bad beads hide. We deliberately resist the temptation to roll up scores into a single project KPI; the **false-closed list** is the headline, not the median score. The dashboard shows distribution, not just average.

### We don't auto-close remediation beads

Closing a remediation bead would require this skill to verify the original false-closed bead now passes. That verification is *the next audit pass*. Auto-closing would create a recursion the audit dir's history is supposed to prevent.

### We don't `git push` the audit dir

The audit dir is local-by-default. Pushing scatters internal critique; the user explicitly opts in if they want a remote.

### We don't mock anything in Phase 4

Phase 4 hits real services per `/testing-real-service-e2e-no-mocks`. Mocking the very services the bead claims to integrate with defeats the purpose.

### We don't tune the rubric mid-pass

The `☖ STAKE-RUBRIC` operator forbids it. Mid-pass tuning corrupts the convergence delta for every bead. Tunings go into the next pass's `rubric.md`.

### We don't let agents self-grade

The closer of a bead is not the auditor of that bead. Phase 8's scorer subagent reads only the evidence pack — not the close reason text — when applying the rubric. (The close reason is one *signal* in Phase 5's anomaly scan, but it doesn't reach the scorer.)

### We don't trust `br doctor` as the only health check

Phase 1 hands off to `/fixing-beads-problems` if doctor fails OR if any of the more granular checks (`.checks[].status == "fail"`, `.workspace_health != "healthy"`) are negative. We catch what doctor's headline summary may miss.

### We don't store secrets in the audit dir

CASS mining outputs are scrubbed for likely-secret patterns before persisting. The audit dir is git-tracked; secrets in mining output would land in git.

### We don't deprecate prior pass dirs

Even when a pass is known-bad (e.g., the project test suite was broken on HEAD), we keep the dir. We rename it `.bad_<reason>/` if needed but never delete.

---

## Trade-offs we accept

### The audit is slow on large projects

200 closed beads × 30 seconds parallel ≈ 60 minutes for a Standard mode pass. We trade speed for depth. The Tripwire mode exists for daily checks (5 minutes); deeper modes exist for periodic rigor.

### The skill is opinionated about test execution

We require Phase 4 to actually run tests. This means the audit can fail when the project's test infrastructure is broken — a legitimate failure that shouldn't be hidden behind "tests would have passed."

### The rubric is conservative

Default thresholds (80% line coverage, 60s fuzz duration, etc.) are tight. False positives are preferred to false negatives. The user can loosen via `rubric.md` per project.

### Single-agent runs lose richness

The wrapper script (`run-pass.sh`) runs end-to-end as a smoke test, but Phase 4 / 6 / 7 are stubbed. Full audits require subagent fan-out per `MODES-AND-TIERS.md`.

### Bead-graph integrity is upstream

We don't fix `br doctor` failures; we hand off to `/fixing-beads-problems`. This skill assumes the bead store is sound.

### The scoring is not Bayesian

We score deterministically with bounded penalties, not probabilistically. A more rigorous Bayesian framework is in `VERIFICATION-UNDER-UNCERTAINTY.md` for projects that want it, but the default is deterministic scoring because it's auditable and reproducible.

---

## Inheritance from sibling skills

The design choices above were not invented in isolation. Each draws from a sibling skill's lessons:

| Principle | Borrowed from |
|-----------|---------------|
| Determinism over heuristics | `/operationalizing-expertise` Track A — rules cite anchors |
| Per-bead, not project-global | `/reality-check-for-project` — vision goals are checked individually, not aggregated |
| Re-run, don't read | `/multi-pass-bug-hunting` — fresh eyes between passes; rerun the scanner |
| Theater invalidates "passes" | `/mock-code-finder` — caller-tracing reveals divergent code paths |
| The artifact is the evidence | `/testing-conformance-harnesses` — every MUST clause cites a test |
| Audit dirs are sacred | `/saas-billing-patterns` — `.billing_workspace/` per phase outputs persist |
| Remediation is graph maintenance | `/beads-workflow` — beads are the source of truth; never bypass them |
| The audit itself is auditable | `/multi-model-triangulation` — second-opinion when stakes are high |

The skill is a **composition** of these patterns, applied to the specific problem of bead-completion verification. None of this is novel; the contribution is the disciplined assembly into a phase loop with marker-bounded artifacts and explicit operator pipelines.

---

## A meta-principle: composition over invention

Every reference file in this skill borrows a pattern from `/operationalizing-expertise` or one of the sibling skills above. Specifically:

- `OPERATOR-LIBRARY.md` borrows operator-card format from `/operationalizing-expertise` Track A.
- `KICKOFF-PROMPTS.md` borrows the variant-A-through-G structure from `/reality-check-for-project`.
- `MODES-AND-TIERS.md` borrows the mode-variant table from `/documentation-website-for-software-project`.
- `BEAD-TYPE-PLAYBOOKS.md` borrows the per-archetype recipe pattern from `/saas-billing-patterns-for-stripe-and-paypal`.
- `MULTI-PASS-FLOW.md` borrows the ambition-rounds + plan-space-refinement pattern from `/reality-check-for-project` and `/beads-workflow`.
- `CI-TRIPWIRE.md` borrows GH-Actions / cron / systemd patterns from `/release-preparations` and `/cc-hooks`.
- `QUOTE-BANK.md` borrows the cass-mined evidence quote anchors from `/operationalizing-expertise` Track C.
- `BEAD-GRAPH-ANALYSIS.md` borrows the `--robot-insights` graph metrics from `/bv`.
- `VERIFICATION-UNDER-UNCERTAINTY.md` borrows from established conformal-prediction and Bayesian-verification literature.
- `COST-OPTIMIZATION.md` borrows differential-execution patterns from `/extreme-software-optimization`.
- `DEBUGGING-THE-AUDIT.md` borrows the troubleshooting-flowchart format from `/gdb-for-debugging`.
- `METRICS-PIPELINE.md` borrows Prometheus / OpenTelemetry export patterns from `/saas-customer-analytics`.

The point: this skill is not the place for novel methodology. It's the place to *combine* methodologies into a working audit. New patterns added to this skill should always reference their sibling-skill ancestor — that's how the `cross-project-pattern-extraction` discipline keeps the family of skills coherent.