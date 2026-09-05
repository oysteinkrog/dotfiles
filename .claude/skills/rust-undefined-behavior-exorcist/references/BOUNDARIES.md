# Boundaries — When to Use This Skill vs. Its Neighbors

This skill is one of several Rust-quality skills that overlap at the edges. This file is the authoritative tie-breaker. Read this BEFORE answering "should I use rust-undefined-behavior-exorcist or X?".

---

## TL;DR: 60-second decision tree

```
The user said:
├── "audit every unsafe block"            → /rust-unsafe-code-exorcist
├── "remove unsafe / safe-only feature"   → /rust-unsafe-code-exorcist
├── "is this unsafe necessary?"           → /rust-unsafe-code-exorcist
│
├── "find UB / miri sweep / soundness"    → THIS SKILL
├── "use-after-free / data race / Pin"    → THIS SKILL
├── "rustonomicon audit"                  → THIS SKILL
├── "prove the codebase is UB-free"       → THIS SKILL
│
├── "deadlock / processes hang"           → /deadlock-finder-and-fixer
├── "test flakes"                         → /deadlock-finder-and-fixer + /testing-fuzzing
│
├── "find all bugs"                       → /multi-pass-bug-hunting (then this for the Rust UB lane)
├── "code review for this branch"         → /code-review-gemini-swarm-with-ntm
│
└── "ship this crate to crates.io"        → THIS SKILL (pre-release UB audit) + /release-preparations
```

If two skills fit, **use both in sequence**. They compose; see the matrix below.

---

## Skill-by-skill comparison

### vs `/rust-unsafe-code-exorcist`

The most common confusion. Both touch `unsafe`. They are not the same skill.

| | rust-unsafe-code-exorcist | rust-undefined-behavior-exorcist |
|---|---|---|
| **Asks** | Is this `unsafe` block necessary? | Is there UB anywhere in this codebase? |
| **Scope** | Every `unsafe` site, classified (A)/(B)/(C) | Every UB/soundness bucket — `unsafe` AND safe code that can feed unsafe boundaries |
| **Catches `unsafe` block hygiene** | ✓ central | △ tangential |
| **Catches macro-generated unsafe** | ✓ central via cargo-expand | ✓ via Phase 1 inventory |
| **Catches FFI-contract violations** | △ flags as STRICTLY_UNAVOIDABLE for refactor | ✓ central, with experiment + cross-check vs C header |
| **Catches data race in 100% safe code** | ✗ out of scope | ✓ central — TSan + loom + shuttle |
| **Catches `Hash`+`Eq` inconsistency** | ✗ | ✓ as correctness / unsafe-boundary invariant |
| **Catches `Iterator::size_hint` lies** | ✗ | ✓, with UB severity only when unsafe code trusts it |
| **Catches `Pin` move-violations** | △ classified per-site | ✓ central — Miri TB + syn-walker |
| **Catches `Send`/`Sync` lies on safe types** | △ | ✓ central |
| **Output** | per-site write-ups + safe rewrites + `safe-only` feature | experiment registry + UB report + UB runbook + remediation beads |
| **Touches source code** | optional in Phase 8 (audit-only by default) | only via Phase 9 beads (caller implements) |
| **Method** | classify-then-refactor | detect-then-prove-then-fix |
| **Convergence** | <5% bucket flips across two passes | <3 new findings + 0 OPEN/NEEDS_REFINEMENT for two rounds, ≥10 rounds total |

**Run order when both apply:**

1. **`/rust-unsafe-code-exorcist` first** if the project has visible `unsafe` surface and the user wants it minimized. Output: fewer `unsafe` blocks, each one harder and more justified.
2. **`/rust-undefined-behavior-exorcist` second** to audit the result. The remaining `unsafe` blocks now have SAFETY contracts; UB-exorcist verifies those contracts empirically (Miri, sanitizers, loom, fuzz) and catches UB *outside* visible `unsafe` blocks that unsafe-exorcist doesn't look at (data races, unsafe-boundary invariant drift, FFI contract drift, etc.).

**Run only one when:**

- The project already has `#![forbid(unsafe_code)]` everywhere → use this skill alone (no visible `unsafe` to refactor, but dependency soundness, FFI wrappers, and unsafe-boundary invariants can still matter).
- The user's only goal is "minimize `unsafe`" → use unsafe-exorcist alone.
- The user got a Miri error or fuzz crash → use this skill (incident response).
- The user is preparing a crates.io release → this skill, then unsafe-exorcist if surface remains.

### vs `/deadlock-finder-and-fixer`

| | deadlock-finder-and-fixer | this skill |
|---|---|---|
| **Catches deadlocks** | ✓ central | △ as a side-effect of loom modeling |
| **Catches livelock** | ✓ | ✗ |
| **Catches await-holding-mutex** | ✓ central | △ via clippy `await_holding_lock` |
| **Catches data races (UB)** | △ | ✓ central — TSan + loom + Miri |
| **Catches non-UB perf issues from contention** | ✓ | ✗ |

**Compose:** if the user reports "processes hang AND there's a Miri error", run deadlock-finder-and-fixer to characterize the hang, then this skill to characterize the UB. They share `loom` and `shuttle` as common ground.

### vs `/multi-pass-bug-hunting`

| | multi-pass-bug-hunting | this skill |
|---|---|---|
| **Scope** | Any bug class | Rust UB only |
| **Method** | iterative audit-fix-rescan | detect-prove-fix with experiment registry |
| **Rust expertise** | language-agnostic | Rust-specialized |
| **Output** | bug list | UB report + beads + runbook |

**Compose:** `/multi-pass-bug-hunting` is the umbrella; it can drive this skill as the "Rust UB lane" of a broader audit. The umbrella skill should call this one explicitly for the UB pass.

### vs `/security-audit-for-saas`

Different domain. `/security-audit-for-saas` is for SaaS billing security (Stripe, PayPal, RLS, webhooks). This skill is for Rust UB. They share the audit-with-beads pattern but the content is disjoint.

### vs `/testing-fuzzing` / `/testing-metamorphic` / `/testing-conformance-harnesses`

| | testing-* | this skill |
|---|---|---|
| **Purpose** | Author tests | Use tests to prove UB |
| **Output** | A test suite | A UB report |
| **Owns** | Test infrastructure design | Experiment registry |

**Compose:** When this skill needs a fuzz target for an unsafe API that lacks one, the `fuzz-author-and-runner` subagent (Phase 3) can invoke `/testing-fuzzing` to do the authoring well. When it needs metamorphic equivalence tests for a SIMD remediation, invoke `/testing-metamorphic`. See [INTEGRATIONS.md](INTEGRATIONS.md).

### vs `/extreme-software-optimization`

If the user wants a fast remediation, they may want to invoke `/extreme-software-optimization` after Phase 8 to refine the chosen rewrite. The two skills don't conflict; they're sequential.

### vs direct use of Kani / Prusti / Creusot / Aeneas

Formal-verification tooling (Kani, Prusti, Creusot, Aeneas) shines for cases where formal-verification-grade guarantees matter. This skill recommends invoking those verifiers directly in Phase 8 for high-stakes findings — see operator `⊢ PROVE` in [OPERATOR-LIBRARY.md](OPERATOR-LIBRARY.md).

### vs `/lean-formal-feedback-loop`

If the user wants Lean-level proofs of soundness for a hot kernel, that's `/lean-formal-feedback-loop`. This skill instead converges via Miri + sanitizers + loom + fuzz + experiment registry — empirical proof, not formal. They are complementary: empirical first to find UB, formal second to *prove the fix* on the highest-stakes sites.

### vs `/code-review-gemini-swarm-with-ntm`

`/code-review-gemini-swarm-with-ntm` is a code-review skill that fans out via NTM tmux panes. This skill is a UB audit; it shares the swarm-fan-out shape but its content is UB-specific. The `fresh-eyes-reviewer` subagent in Phase 10 *can* delegate to the gemini-swarm skill for the three-prompts review if the user has it set up.

### vs `/ubs` (Ultimate Bug Scanner)

`ubs` is a fast static analyzer (per AGENTS.md, runs on changed Rust files). It's a *gate*, not an audit. This skill runs `ubs` in Phase 2 as one of many sweeps, and re-runs it in Phase 10 as a green-gate. Don't confuse a `ubs` clean run with UB-free — `ubs` finds a fraction of UB; this skill is exhaustive.

---

## Decision matrix (read top to bottom)

| Situation | Primary skill | Secondary skills |
|---|---|---|
| "Audit `frankensqlite` for UB before crates.io release" | this skill | `/release-preparations`, `/rust-crates-publishing` |
| "Refactor away all unsafe in this lib" | `/rust-unsafe-code-exorcist` | this skill (verify result) |
| "Miri error in fn X — diagnose and fix" | this skill (incident response) | `/multi-model-triangulation` if ambiguous |
| "Processes hang under load" | `/deadlock-finder-and-fixer` | this skill if a race is the cause |
| "Tests flake under TSan" | this skill | `/deadlock-finder-and-fixer` |
| "Audit this whole repo for any kind of bug" | `/multi-pass-bug-hunting` | this skill (Rust UB lane) |
| "Code review on this PR" | `/code-review-gemini-swarm-with-ntm` | this skill if PR touches `unsafe` or concurrency |
| "Prove this lock-free queue is sound" | this skill | Kani / Prusti directly |
| "Build a CI gate that blocks new UB" | this skill (Phase 12 produces `UB_RUNBOOK.md` for this) | `/cc-hooks`, `/gh-actions` |

---

## What this skill explicitly **does not** do

- It does **not** classify `unsafe` blocks into (A)/(B)/(C). That's unsafe-exorcist's domain.
- It does **not** ship a `safe-only` Cargo feature. That's unsafe-exorcist's domain.
- It does **not** decide whether your `unsafe` is "necessary" — it checks whether your code violates Rustonomicon UB rules or adjacent invariants that can feed unsafe boundaries.
- It does **not** rewrite the source code directly. Phase 9 produces beads; the caller implements them.
- It does **not** do general code review. Phase 10 fresh-eyes reviews the *remediation plan and beads*, not the original source.
- It does **not** measure performance. Phase 8 rubric scores perf delta of candidate rewrites, but the skill doesn't run a comprehensive bench suite. Use `/extreme-software-optimization` for that.

---

## What this skill explicitly **does** do that no neighbor covers

- Full Rustonomicon UB plus soundness-adjacent taxonomy (25 buckets, see [UB-TAXONOMY.md](UB-TAXONOMY.md)) — not just `unsafe`-block contracts.
- Empirical proof per finding via the `UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md` registry with strict verdict tracking.
- Convergence proof — ≥10 rounds, two consecutive quiet, `convergence-tracker.sh`-measured.
- Project-shaped `/idea-wizard` round for UB shapes specific to *this* codebase's custom allocators, lock-free DS, custom intrusive lists, FFI handles, etc.
- Polished beads with mandatory test-bead + docs-bead deps per remediation — every fix has a regression canary.
- `UB_RUNBOOK.md` deliverable: the project's permanent CI gates for staying UB-free going forward.
