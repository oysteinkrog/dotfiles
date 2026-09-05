# MENTAL-MODEL.md — The Skill in One Page

The skill in 30 seconds + the conceptual model in 5 minutes. Read first.

---

## 30-second version

1. **You point at a Rust project.** The skill enumerates every `unsafe` site.
2. **Each site lands in one of three buckets.** (A) STRICTLY_UNAVOIDABLE / (B) PERF_ONLY / (C) REFACTORABLE — with a falsifiable justification per site.
3. **For each (C):** a full safe rewrite + a property-based equivalence test proving it matches the original.
4. **For each (B):** a `safe-only` Cargo feature with the safe alternative + measured perf numbers.
5. **For each (A):** a hardened SAFETY comment + (where possible) a clippy lint catching caller-side violations.
6. **The audit dir lives inside the project** — `<project>/.unsafe-audit/` — and gets all audit artifacts. Existing project source files stay read-only until the user authorizes refactor.
7. **Continuous mode** turns the snapshot into ongoing partnership: nightly drift detection, CI gates, risk-scored bead prioritization, soundness debt dashboard.

---

## The classification triangle

```
              (A) STRICTLY_UNAVOIDABLE
               Type system can't express it.
               FFI, allocator, signal handler,
               Pin self-ref, atomic intrinsics.
              / Hardened SAFETY + clippy lint
             /
            /             [the audit's
           /              "soundness floor"]
          /
 -------- ▼ --------------- ▲ ----------
  Safe alternative           Measure perf;
  exists, equivalence        if within budget,
  proved.                    site graduates to (C).

  (C) REFACTORABLE           (B) PERF_ONLY
   Full safe rewrite +        safe-only feature +
   property test +            measured perf delta +
   miri clean.                CI matrix gate.
```

The bias is downward: when in doubt, classify (B) over (A); (C) over (B). Misclassification is the cardinal sin. Every (A) needs three failed safe alternatives + a steel-man attack + a rebuttal.

---

## The 10 phases (the loop)

```
INPUTS                                      OUTPUTS
─ Project path                              ─ unsafe-inventory.jsonl
─ Mode (audit-only by default)              ─ Per-site write-ups
─ Perf budget (5% default)                  ─ A/B/C classifications
─ Toolchain profile (full default)          ─ Refactor plans
                                            ─ Verification harness (verify.sh)
                                            ─ Bead graph (br create commands)
                                            ─ AUDIT_SUMMARY.md (the single-line tally)
                                            ─ REVIEWER_RESPONSES.md (Phase 10 review)

Phase 1: Enumerate (per-crate)         ───┐
                                           │
Phase 2: Per-site write-up (per-crate) ───┤   "What does each unsafe DO?"
                                           │
Phase 3: Synthesize (global)           ───┤   "Where's the soundness surface?"
                                           │
Phase 4: Classify (iterative)          ───┤   "Which bucket?" (repeat until quiet)
                                           │
Phase 5: Plan-draft (per-cluster)      ───┤   "For each, write the code/justification"
                                           │
Phase 6: Adversarial reclassify        ───┤   Fresh agent tries to defeat each (A)
                                           │
Phase 7: Fresh-eyes review + harness   ───┤   3 review prompts + miri/loom/fuzz/...
                                           │
Phase 8: Bead conversion + commit      ───┤   br create + git commit (audit dir only)
                                           │
Phase 9: Verify harness                ───┤   verify.sh + CI matrix template
                                           │
Phase 10: Maintainer-empathy review    ───┘   "Would I land these as maintainer?"
```

Phases 4 and 6 are **reapply-until-quiet** (≥2 passes where <5% sites flip bucket AND zero (A)→(C) flips).

---

## The audit dir's anatomy

```
<project>/.unsafe-audit/             ← in-project audit dir; nested git repo
├── phase0_scope_decision.md         ← what's in/out of scope
├── phase0_toolchain.json            ← exact tool versions
├── phase0_skill_inventory.json      ← which helper skills are available
├── unsafe-inventory.jsonl           ← the canonical list (one site per row)
├── risk-scores.json                 ← BLAST × LIKELIHOOD × DISCOVERABILITY
├── verify.sh                        ← composite harness
├── ci-matrix.yml                    ← GitHub Actions template
├── AUDIT_SUMMARY.md                 ← the user-facing one-line tally
├── REVIEWER_RESPONSES.md            ← Phase 10 review
├── .beads/                          ← bead graph (br ready / br close)
├── phase1/                          ← per-crate ast-grep + cargo expand output
├── audit/
│   ├── sites/<crate>/.md            ← per-site write-ups
│   ├── classification/site-NNNN.md  ← bucket + justification per site
│   ├── plans/site-NNNN.md           ← refactor plan per site
│   ├── plans/cluster-R-NNN.md       ← per-cluster plan
│   ├── synthesis/                   ← global views
│   │   ├── invariants.md            ← cluster sites by shared invariant
│   │   ├── soundness-surface.md     ← every pub API path reaching unsafe
│   │   ├── refactor-clusters.md     ← proposed refactor groups
│   │   ├── pre-existing-ub.md       ← UB found OUTSIDE refactor scope
│   │   ├── risk-summary.md          ← top sites by risk score
│   │   └── cross-crate-contracts.md ← workspace contracts (if workspace)
│   ├── tests/                       ← property tests, equivalence tests, regression tests
│   └── archeology/                  ← project's git-history + bead-history
├── drift/                           ← continuous mode's nightly outputs
└── baseline/                        ← snapshot for drift detection
```

---

## Who does what (agents)

```
ORCHESTRATOR (one)                  ← the audit's coordinator
├── enumerator (per crate)          Phase 1
├── site-analyzer (per crate)       Phase 2 (same agent as enumerator)
├── synthesizer (one)               Phase 3
├── classifier (per pass)           Phase 4 — iterative
├── refactor-planner (per cluster)  Phase 5
├── equivalence-prover (per (C))    Phase 5
├── adversarial-reclassifier (per pass) Phase 6 — iterative
├── fresh-eyes-reviewer (per round) Phase 7
├── harness-builder (one)           Phase 9
├── bead-converter (one)            Phase 8
└── maintainer-empathy-reviewer     Phase 10 (fresh agent, no prior context)

PLUS — specialty agents
├── cass-miner (Phase 0.5)
├── exemplar-miner (Phase 0.5)
├── archeologist (Phase 0.5)
├── multi-model-triangulator (Phase 6 / 7 / 10)
├── idea-generator (Phase 10)
├── safety-comment-author (Phase 5 / 8.5)
├── allocator-identity-auditor (Phase 6 / 7)
├── panic-boundary-auditor (Phase 6 / 7)
├── api-stability-reviewer (Phase 5 / 6)
├── upstream-issue-filer (dep-soundness mode)
├── regression-test-author (harden-incident mode)
├── changelog-writer (Phase 8.5 / 10)
├── kani-prover (Phase 5 / 7 for high-stakes (C))
├── worktree-implementer (Phase 8.5; legacy filename, active-checkout implementation)
├── pin-projection-auditor (Phase 1 / 2 specialty)
├── drift-detector (continuous mode)
├── risk-scorer (Phase 4 / 8)
├── inverse-auditor (inverse-audit mode)
├── contract-verifier (workspace)
├── test-generator (Phase 5 / 8)
└── security-md-author (Phase 10 / per-release)
```

---

## The verification stack

From cheapest to strongest:

```
cargo build                  ← compiles
cargo test                   ← unit tests pass
cargo +nightly geiger        ← unsafe count tracked
cargo +nightly careful test  ← runtime UB detection at native speed
cargo +nightly miri test     ← stacked-borrows UB detection (interpreted)
  ├── -Zmiri-strict-provenance ← strict pointer-int casts
  └── -Zmiri-tree-borrows      ← newer aliasing model
loom (RUSTFLAGS="--cfg loom") ← concurrency interleaving model
cargo fuzz                    ← input-space exploration
cargo mutants                 ← did tests actually pin behavior?
kani (formal verification)    ← bounded model checking; symbolic proof
```

`verify.sh` runs the lower 6 (geiger / careful / miri / loom / fuzz / mutants) + the project's test suite under default + `safe-only` features. Kani is opt-in for highest-stakes sites.

---

## What this skill is NOT

- **Not a Rust learner.** Assumes you read Rust; cites the nomicon when it matters.
- **Not a perf optimizer.** When perf wins, the (B) bucket holds them; the skill measures + chooses, doesn't tune.
- **Not a refactor framework.** It produces plans + beads; the user (or active-checkout implementer agent) does the authorized refactor. Git worktrees are forbidden.
- **Not autonomous against the project repo.** Audit dir is the contract until Phase 8.5 + explicit authorization.
- **Not a one-time tool.** Continuous mode turns it into ongoing partnership; the IDEAS.md backlog shows where it can grow.

---

## How to navigate

| You're asking | Read |
|---------------|------|
| "What does this skill do?" | THIS file |
| "How do I start?" | [SKILL.md § Quick Start](../../SKILL.md), then [COOKBOOK.md](COOKBOOK.md) |
| "Which mode should I use?" | [OPERATING-MODES.md](OPERATING-MODES.md) |
| "What are the buckets?" | [CLASSIFICATION-RUBRIC.md](CLASSIFICATION-RUBRIC.md) |
| "I see symptom X — what pattern?" | [95-INDEX.md](../patterns/95-INDEX.md) |
| "What command do I run?" | [QUICK-REFERENCE.md](QUICK-REFERENCE.md) |
| "I have a tricky scenario" | [COOKBOOK.md](COOKBOOK.md) |
| "Something broke" | [TROUBLESHOOTING.md](TROUBLESHOOTING.md) |
| "What's the long-term vision?" | [IDEAS.md](IDEAS.md) |

The skill is large because it's thorough. But you don't need to read it all — pick the entry point that matches your question.
