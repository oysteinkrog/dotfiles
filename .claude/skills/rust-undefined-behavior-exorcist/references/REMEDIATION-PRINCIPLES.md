# Remediation Principles — User Preferences Mined From The Corpus

Beyond the rubric in [REMEDIATION-PATTERNS.md](REMEDIATION-PATTERNS.md), the user has *recurring preferences* about HOW to fix bugs. The skill's remediation-architect (Phase 8) should respect these.

Anchors: cass Q-401 (fix-the-chokepoint), Q-402 (shape-sweep + checked operators), Q-501 (forward-only release), Q-801 (same-shape sweep).

---

## Principle 1: Fix at the chokepoint, don't delete it

**Cass anchor:** Q-401 — AWK END block kept, gated by `found` accumulator.

**The pattern:** When a chokepoint (a function, an END block, a gate) has a bug, the user fixes the chokepoint rather than removing it. The chokepoint exists for a reason; removing it loses the contract.

**Example:** The AWK script's `END { exit 1 }` was overriding pattern-block `exit 0`. The "simple fix" would have been to delete the END block. The user's fix kept the END block but routed exit through a `found` accumulator:

```awk
# Before
in_section && /command/ { exit 0 }
END { exit 1 }

# After
BEGIN { found = 0 }
in_section && /command/ { found = 1 }
END { exit (found ? 0 : 1) }
```

**Application to UB exorcism:** When a SAFETY contract is wrong, fix the contract; don't remove the `unsafe` block. The block exists because the perf path matters; rewriting the SAFETY comment to be honest is the fix.

**Anti-pattern:** "Just delete this `unsafe impl Send` and switch to `Mutex`" — only if the perf is OK. Otherwise, fix the synchronization story while keeping the impl.

---

## Principle 2: Shape-sweep before commit

**Cass anchor:** Q-801 — float-modulo bug fixed in VDBE and MVCC in the same fresh-eyes pass.

**The pattern:** When fixing UB pattern X at site A, *immediately* `rg` / `ast-grep` for the same shape across the workspace. Fix all sites in the same commit.

**Why:** A reviewer sees the bug + the fix at site A and may not realize the bug exists elsewhere. If sites B, C, D are fixed in the same commit, the fix is comprehensive; if not, the bug stays in B, C, D for months until someone else notices.

**Application to UB exorcism:** Phase 8 designs the remediation ONCE; Phase 9 produces a bead ladder with [ancillary] beads for every additional site (see [UB-BEAD-LADDER.md](UB-BEAD-LADDER.md)).

See [SHAPE-SWEEP.md](SHAPE-SWEEP.md) for the full workflow.

---

## Principle 3: Prefer `checked_*` and total operators

**Cass anchor:** Q-402 — `checked_rem` + `match` for the `i64::MIN % -1` edge case.

**The pattern:** When the operation has an edge case that produces wrong results or panics, use the `checked_*` variant with explicit handling of the edge:

```rust
// Before (silent UB / panic):
let result = ia % ib;

// After (explicit handling):
let result = match ia.checked_rem(ib) {
    Some(r) => r,
    None => 0,  // i64::MIN % -1 = 0, documented edge case
};
```

**Application to UB exorcism:** Audit every arithmetic on integer types. Use `checked_*`, `saturating_*`, or `wrapping_*` based on the desired semantics. Document the choice with an inline comment.

**Anti-pattern:** `as` casts without bounds check; `+` on `usize` near overflow boundary; `*` on values that could exceed `T::MAX`.

---

## Principle 4: Document the rejected alternatives

**Cass anchor:** Q-401, Q-402 — both fixes include rationale for the path NOT taken.

**The pattern:** When choosing remediation A over B and C, *record A's choice AND why B and C were rejected*. Future maintainers may face different constraints and revisit.

**Example from Q-402 (float-mod):**
> "Could have kept floats and added an explicit `i64::MIN/-1` guard. Chose to convert to integer-domain entirely, document the `i64::MIN % -1 = 0` decision in a comment, and use `checked_rem` for total correctness."

The integer-domain choice is recorded WITH the rejected float-with-guard alternative.

**Application to UB exorcism:** Phase 8 `phase8_remediation_plan.md` requires ≥2 candidates with rubric scores. Runner-ups are explicitly preserved. The kernel invariant I4 codifies this.

---

## Principle 5: Forward-only releases (no backporting)

**Cass anchor:** Q-501 — bump + topological re-publish; never cherry-pick to older versions.

**The pattern:** When a UB fix lands on `main`, the user releases the new version (e.g., `v0.2.6`) to crates.io. Older versions are NOT backported. Downstream users upgrade.

**Application to UB exorcism:** [BACKPORTING.md](BACKPORTING.md) is advisory-only; the default is [RELEASE-FORWARD-ONLY.md](RELEASE-FORWARD-ONLY.md).

When backport DOES apply (downstream user explicitly requests it), treat as a separate workflow.

---

## Principle 6: Reread AGENTS.md before remediating

**Cass anchor:** Q-201..Q-206 — every audit pass begins with this.

**The pattern:** Before designing a remediation, re-load the project's AGENTS.md constraints. The remediation must comply.

**Example:** A remediation that proposes `git reset --hard` would violate AGENTS.md's "no destructive git commands" rule. The remediation-architect catches this before producing the bead.

**Application to UB exorcism:** Phase 8 sub-agent's kickoff (see [KICKOFF.md](KICKOFF.md)) explicitly includes the ↻A operator (Reread AGENTS.md). See [FRESH-EYES-OPERATORS.md](FRESH-EYES-OPERATORS.md).

---

## Principle 7: Multi-line SAFETY contracts (no one-liners)

**Cass anchor:** Q-201 (frankensqlite MmapBacking) — 4-line SAFETY contract; documentation-website skill's `>40 chars = strong, <40 chars = weak` heuristic.

**The pattern:** Every SAFETY comment is ≥3 lines and names every invariant the unsafe op depends on. Pattern from [EXEMPLARS.md E1](EXEMPLARS.md):

```rust
// SAFETY:
//   1. <invariant 1; cite where it's enforced>
//   2. <invariant 2>
//   3. <invariant 3>
unsafe { ... }
```

**Application to UB exorcism:** Phase 1's unsafe-surface-mapper flags SAFETY comments <40 chars as `PRESENT_WEAK`. Phase 8 remediation includes a docs-bead per site that upgrades the SAFETY comment.

---

## Principle 8: Test the fix is detected, not just present

**Cass anchor:** Q-101 — adversarial matrix gated on zero false negatives.

**The pattern:** A test that asserts "the code path runs cleanly" isn't enough. The test must assert "if the bug were re-introduced, the detection fires". Use an inverted assertion or a fault injection matrix.

**Example:** For an aliasing remediation, the test should:
1. Run the corrected code under Miri tree-borrows → green
2. Run a *deliberately-broken* version (cfg-gated) under Miri → expect "Undefined Behavior"

Without (2), a future refactor that breaks the fix slips through without test failure.

**Application to UB exorcism:** [UB-TEST-MATRIX.md](UB-TEST-MATRIX.md) and operator `✕ INVALIDATE` codify this.

---

## Principle 9: Bead ladder shape (audit → core → ancillary → test → e2e)

**Cass anchor:** Q-802 — bd-1ddv 5-step structure.

**The pattern:** Per [UB-BEAD-LADDER.md](UB-BEAD-LADDER.md), every remediation has 5 beads in a dependency chain. Don't shortcut.

**Application:** Phase 9 polish enforces the 5-step structure.

---

## Principle 10: CVE-arena artifacts for security-grade fixes

**Cass anchor:** Q-602 — frankenlibc's `tests/cve_arena/results/bd-18qq.4/...` layout.

**The pattern:** For CVE-grade remediations, the test produces persistent JSON artifacts in `tests/cve_arena/results/<bead-id>/`. These feed the disclosure timeline + the trend analysis.

**Application:** See [CVE-ARENA-LAYOUT.md](CVE-ARENA-LAYOUT.md).

---

## Principle 11: Workspace-version-bump on every UB release

**Cass anchor:** Q-501 — workspace versions move together.

**The pattern:** For multi-crate workspaces, every UB-bearing release bumps the *workspace* version, not just the affected crate. All member crates re-publish at the new version. This keeps the dep graph consistent.

**Application:** Phase 8 release-prep bead bumps the workspace `version` field; member crates inherit if using `workspace.dependencies`.

---

## Principle 12: Concurrency soundness ranks equal to memory soundness

**Cass anchor:** Q-103 — cancel-correctness audited with same rigor as memory safety.

**The pattern:** A missing `cx: &Cx` or a leaked task is treated as a soundness violation, not a feature request.

**Application:** See [CANCEL-CORRECTNESS.md](CANCEL-CORRECTNESS.md).

---

## Encoding these into Phase 8

The `remediation-architect` subagent's kickoff prompt (see [KICKOFF.md §K7](KICKOFF.md)) should reference this file. Specifically, the rubric scoring should incorporate:
- **Correctness margin** considers Principle 8 (test fires when bug re-introduced)
- **Diff blast radius** considers Principle 2 (shape-sweep multi-site)
- **Reviewability** considers Principle 4 (runners-up recorded) + Principle 7 (SAFETY comments)
- **Maintainability** considers Principle 6 (AGENTS.md-compliant) + Principle 1 (fix-don't-delete)

---

## Cross-references

- cass Q-401, Q-402, Q-501, Q-801, Q-201, Q-101, Q-602, Q-103 — verbatim sources
- [REMEDIATION-PATTERNS.md](REMEDIATION-PATTERNS.md) — the catalog of *what* to choose
- [SHAPE-SWEEP.md](SHAPE-SWEEP.md) — Principle 2
- [UB-BEAD-LADDER.md](UB-BEAD-LADDER.md) — Principle 9
- [UB-TEST-MATRIX.md](UB-TEST-MATRIX.md) — Principle 8
- [CVE-ARENA-LAYOUT.md](CVE-ARENA-LAYOUT.md) — Principle 10
- [CANCEL-CORRECTNESS.md](CANCEL-CORRECTNESS.md) — Principle 12
- [FRESH-EYES-OPERATORS.md](FRESH-EYES-OPERATORS.md) — Principle 6
