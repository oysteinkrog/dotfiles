# DECISION-TREE.md — Which Mode? Which Phase? Which Subagent?

ASCII flowcharts for navigating the skill's choices.

---

## "Which mode should I use?"

```
              ┌────────────────────────┐
              │ Why are you running    │
              │ this skill?            │
              └────────┬───────────────┘
                       │
   ┌───────────────────┼──────────────────────┬─────────────────────┐
   │                   │                      │                     │
   ▼                   ▼                      ▼                     ▼
┌─────────┐        ┌─────────┐           ┌──────────┐         ┌──────────┐
│ Incident│        │ Routine │           │  Pre-    │         │ Don't    │
│ just hit│        │ audit   │           │ release  │         │ know yet │
└────┬────┘        └────┬────┘           └─────┬────┘         └────┬─────┘
     │                  │                       │                   │
     ▼                  ▼                       ▼                   ▼
 harden-           Do you want         pre-release-           triage
 incident          to LAND the         soundness-gate         (60 sec
                   fixes too?                                  enumerate
                       │                                       + score)
                       │
              ┌────────┴──────────┐
              ▼                   ▼
        Yes — land in        No — report only
        active-checkout refactors
              │                   │
              ▼                   ▼
        audit-and-           audit-only
        refactor
                              │
                              │  ┌─────────────────────┐
                              │  │ Time-constrained?   │
                              │  └──────────┬──────────┘
                              │             │
                              │             ▼
                              │      audit-only --quick
                              │
                              ▼
                              audit-only (full default)


More targeted modes (no decision needed; user knows exactly what they want):

  - dep-soundness: I want to audit MY DEPS' unsafe reachable from my pub API
  - verify-only: I want the CI verification harness, not a re-audit
  - dual-feature-migration: I want to add a `safe-only` feature flag
```

---

## "Which fast-track variant?"

```
What's your time budget?
       │
       ├── < 1 minute  ─────► triage (enumerate + risk-score; no classification)
       │
       ├── ~10 minutes ─────► audit-only --quick (single-pass classify; no harness)
       │
       ├── ~30 seconds ─────► dashboard-only (regenerate from existing audit data)
       │
       ├── ~5-10 minutes ───► drift-check (continuous-mode manual run)
       │
       └── ~30 min – hours ─► full audit-only or audit-and-refactor
```

---

## "Which bucket?" (per site)

This is the classifier's flow. The audit walks it for every site:

```
Look at the unsafe site.
       │
       ▼
Does a safe formulation exist today?
       │
   ┌───┴────┐
   │        │
  NO       YES
   │        │
   ▼        ▼
Cite the   Can the safe form match the unsafe form's
language   PERFORMANCE within the user's perf budget?
reference
that says       │
it can't   ┌───┴────┐
be safe.   │        │
   │      YES      NO
   ▼       │        │
(A)        ▼        ▼
STRICTLY-  (C)      (B)
UNAVOIDABLE REFACT-  PERF-ONLY
   │        ORABLE   │
   ▼        │        ▼
Write the   │     Measure on
JUSTIFI-    │     EVERY target.
CATION      ▼     Within budget
block      Draft  on some?
(3 failed   the   ┌──┴────────┐
alternatives + safe ▼          ▼
steel-man  code   Graduate to  Keep (B);
attack +   +     (C) for      ship safe-
rebuttal)  prop-  those       only feature
   │       erty   targets.    flag.
   ▼       test    │            │
Harden SAFETY      ▼            ▼
comment +        Per-target   Per-target
clippy lint.     differing    bench numbers
                 classifi-    in the plan.
                 cations.
```

Bias: when in doubt, default DOWNWARD: (A) → (B) → (C). Misclassification is the cardinal sin.

---

## "Which operator should I apply?" (per site)

```
What KIND of unsafe is this?
       │
       ├── FFI / extern "C" / libc ─────────────► ⊙ ⊕ ⊗ 🪟 🔒 🔁
       │
       ├── unsafe impl Send / Sync ─────────────► ⊙ ⚖ ⊕ 🔐 ⊗
       │
       ├── SIMD / hot-loop intrinsic ───────────► ⊙ ⏱ 🪞 ✦
       │
       ├── MaybeUninit::assume_init ────────────► ⊙ 🗄 🔒 🧪
       │
       ├── Pin::new_unchecked ──────────────────► ⊙ 🔁 ⊕ ⊗
       │
       ├── mem::transmute ──────────────────────► ⊙ 🧪 ⊠
       │
       ├── slice::get_unchecked ────────────────► ⊙ ⏱
       │
       ├── macro-generated (from cargo expand) ─► ⌖ ⊙ 🧪
       │
       ├── Allocator impl ──────────────────────► ⊙ 📐 ⊗ 🔒
       │
       ├── Lock-free / concurrent ──────────────► ⊙ ⚖ ⊞ ✦ 🔁 🧪
       │
       ├── Pointer-int cast / tagged pointer ───► ⊙ ⊟ (strict-provenance) ⊠
       │
       ├── `(core|std)::hint::*_unchecked` /
       │   `(core|std)::intrinsics::*` ────────► ⊙ ⊗ ⏱  (bundle: 25-INTRINSICS-AND-COMPILER-HINTS.md)
       │
       ├── `(core|std)::ptr::read / write / copy /
       │    swap / drop_in_place`  ────────────► ⊙ ⊗ ⤴ 🧪  (bundle: 25-INTRINSICS-AND-COMPILER-HINTS.md)
       │
       ├── Manual `UnsafeCell::new` ────────────► ⊙ ⚖ 🔐  (bundle: 27-UNSAFECELL-PATTERNS.md)
       │
       └── Multi-resource Drop interaction ─────► ⊙ ⊰ 🔒 🔁

Always apply on Phase 9 globally: 🪞 (geiger delta) + ⚑ (pre-existing UB triage)

Always apply on Phase 7 (per (C) rewrite): ⤴ (Drop-glue sanity)

Always apply on Phase 6 adversarial: ⊗ Falsifiable-Justification recheck for (A);
                                     missed safe-equivalent for (B);
                                     stress-test equivalence for (C)
```

Full operator cards: [OPERATORS.md](OPERATORS.md).

---

## "Which subagent for what?"

```
PHASE      OWNER                     WHAT IT DOES
─────────────────────────────────────────────────────────────
Pre-Phase  cass-miner               Query prior agent sessions for relevant patterns
Pre-Phase  exemplar-miner           Read exemplar repos' refactor history
Pre-Phase  archeologist             Mine THIS project's git history + closed PRs + beads

Phase 1    enumerator(per crate)    ast-grep + cargo-geiger + cargo expand + rustdoc

Phase 2    site-analyzer(per crate) Per-site write-up (same agent as Phase 1)

Phase 3    synthesizer              Global view: invariants + soundness surface + clusters

Phase 4    classifier(per pass)     A/B/C bucket per site; iterate until quiet
Phase 4    risk-scorer              Quantified BLAST × LIKELIHOOD × DISCOVERABILITY

Phase 5    refactor-planner(per cluster)  Full safe code + tests + (A) hardening
Phase 5    equivalence-prover(per (C))    Property-based equivalence tests
Phase 5    safety-comment-author          Hardened SAFETY for (A) sites
Phase 5    api-stability-reviewer         Classify API impact of (C) plans
Phase 5    test-generator                 Auto-generate property tests from write-ups
Phase 5    kani-prover (high-stakes)      Formal verification proofs

Phase 6    adversarial-reclassifier(per pass)  Try to defeat each (A); iterate
Phase 6    multi-model-triangulator           Codex/Gemini/Grok second opinions
Phase 6    allocator-identity-auditor         Catch silent allocator changes
Phase 6    panic-boundary-auditor             Audit panic-unwinding boundaries

Phase 7    fresh-eyes-reviewer(per round)  Three verbatim review prompts
Phase 7    pin-projection-auditor          Pin sites specialty
Phase 7    inverse-auditor (opt-in)        Fuzz from pub API; find missed bugs

Phase 8    bead-converter                  Plans → br create commands
Phase 8.5  worktree-implementer(per cluster; legacy name) Land in active checkout; optionally open PRs

Phase 9    harness-builder                 verify.sh + ci-matrix.yml

Phase 10   maintainer-empathy-reviewer    "Would I land this as maintainer?"
Phase 10   idea-generator                  /idea-wizard for missed strategies
Phase 10   changelog-writer               CHANGELOG + RELEASE-NOTES + advisory
Phase 10   security-md-author             Generate SECURITY.md
Phase 10   contract-verifier (workspace)  Cross-crate contract verification

Continuous drift-detector                  Nightly cron drift check

dep-soundness mode  upstream-issue-filer  Drafts upstream issues for dep concerns

harden-incident mode  regression-test-author  Pins each fix to a named regression test
```

Full subagent specs: see `subagents/*.md`.

---

## "Where does my finding fit?"

You saw a specific failure (miri UB, fuzz crash, mutants miss, etc.). Where does it belong?

```
What did the harness say?
       │
       ├── miri found UB ──┬── In code we TOUCHED ──► Refine the plan; rerun
       │                    │
       │                    └── In code we DIDN'T touch ──► pre-existing-ub-N bead
       │
       ├── loom failed ────┬── In a (C) rewrite ──► (C) plan needs concurrency model fix
       │                    │
       │                    └── In existing code ──► pre-existing-ub-N bead
       │
       ├── fuzz panic ─────┬── On a (C) rewrite ──► Add the input to property test; re-prove
       │                    │
       │                    └── On existing pub API ──► pre-existing-ub-N bead OR audit-gap
       │
       ├── mutants missed ─► Add test cases that pin the behavior
       │
       ├── geiger went UP ─► Refactor introduced new unsafe; reclassify or revise
       │
       └── geiger went DOWN ─► Refactor closed sites; good! Update inventory + dashboard
```

Operator ⚑ Pre-Existing-UB-Isolator owns this triage. See [PRE-EXISTING-UB-PROTOCOL.md](PRE-EXISTING-UB-PROTOCOL.md).

---

## "Should I trigger an audit or wait?"

```
Has the project drifted since the last audit?
       │
   ┌───┴────┐
   │        │
  YES      NO
   │        │
   ▼        ▼
Continuous mode    Skip. Save the
already running?   audit budget.
   │
┌──┴────┐
│       │
YES   NO
│       │
▼       ▼
Drift   Run audit-only
beads   to baseline + enable
auto-   continuous mode.
filed.
Address
them.

Other triggers:
  - Pre-release → pre-release-soundness-gate
  - Customer incident → harden-incident
  - Dep upgrade considered → differential audit (A vs B)
  - PR introducing new unsafe → CI-integration auto-classifier
```

---

## "I have a Rust project. Where do I start?"

```
Step 1. Read README.md (1 page, 5 min).
Step 2. Run scripts/check-prerequisites.sh (30 sec).
Step 3. Install any required-tier missing tools.
Step 4. Try the toy project (5 min smoke test).
Step 5. If toy works, run on YOUR project:

  - Don't know what your project's unsafe looks like? → triage (60 sec)
  - Want a defensible audit?                           → audit-only (hours)
  - Want to land the changes?                          → audit-and-refactor (hours+)
  - Releasing soon?                                    → pre-release-soundness-gate
  - Just want to check deps?                           → dep-soundness

Step 6. Read AUDIT_SUMMARY.md when done.
Step 7. Address top-risk-score sites (per audit/synthesis/risk-summary.md).
Step 8. Enable continuous mode so drift is caught.
```

---

## What this file is NOT

- Not a substitute for reading [OPERATING-MODES.md](OPERATING-MODES.md) (per-mode exit criteria).
- Not a substitute for [CLASSIFICATION-RUBRIC.md](CLASSIFICATION-RUBRIC.md) (the falsification tests).
- It's a NAVIGATION aid — these ASCII trees help you find the right reference quickly.

When a decision is non-obvious, drop into the relevant reference for depth.
