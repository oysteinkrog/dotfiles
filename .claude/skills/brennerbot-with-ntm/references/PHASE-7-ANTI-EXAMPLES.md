# PHASE-7-ANTI-EXAMPLES.md — Concrete Examples of Audit Failures

<!-- TOC: Why audit anti-examples | AE format | AE-7.1 LGTM × N | AE-7.2 zero findings | AE-7.3 too aggressive | AE-7.4 rhetoric over evidence | AE-7.5 same-pane audit | AE-7.6 falsifier softening | AE-7.7 scale-physics skip | AE-7.8 cross-family bypass | AE-7.9 audit speed | AE-7.10 audit on stale artifact | How to use -->

Companion to PHASE-1-ANTI-EXAMPLES.md. Phase 7 audit is where the methodology either holds or collapses; the failures here are the most damaging because they certify a flawed deliverable.

---

## Why audit anti-examples

Per SIX-LAYER-VALIDATION.md, Layer 1-5 should catch most audit issues — but these anti-examples are scenarios where the audit *itself* drifts. Operators trained on AE-7.* recognize and recover from these in real-time.

For T4+ sessions, walking through AE-7.* before bootstrap is mandatory.

---

## Anti-example format

Same as PHASE-1-ANTI-EXAMPLES:

```
AE-7.<N>: <one-line title>

**Symptoms during audit:** what the operator observes
**Bad audit produced:**
  - Findings: <what was filed (or not)>
  - Severity distribution: <ratio>
**Diagnosis:** which F-### code, which OPERATORS.md card was skipped
**Recovery:** specific operator move
**Resulting good audit pattern:**
```

---

## AE-7.1: LGTM × N

**Symptoms during audit:**
- Trio-round 1 audit panes return findings: 0 critical, 0 high, 0 medium, 0 low.
- Pane tails contain phrases like "exemplary work," "no issues," "ready for freeze."
- Operator's gut: "this seems too clean."

**Bad audit produced:**
- Findings: 0 across all severities.
- Phase 7 marked converged after 1 round.

**Diagnosis:** F-701 audit-acceptance false positive. ∿ Dephase wasn't applied. The audit panes likely under-read the artifact OR rubber-stamped without specific evidence.

**Recovery:**
1. Run `liveness-check.sh` to verify panes actually read the artifact (didn't skim).
2. Run `red-flag-scan.sh` for convergence-language false positives.
3. Dispatch 2nd trio with explicit directive: "Find ≥3 methodology gaps even if artifact looks clean. Apply ⊞ Scale-Check, ∿ Dephase, ✂ re-verify."
4. If 2nd trio also returns 0: trio panes may share blind spot. Force cross-family audit (per OC-019 OPERATOR-CARDS.md).
5. If 3rd cross-family trio also returns 0 AND `audit-bead-invariants.sh --all` is clean: artifact may genuinely be sound. Proceed with operator-confidence note in HANDBACK.

**Resulting good audit pattern:**
- Trio-rounds explicitly tasked with ≥3 findings target per round (calibration prior); converge when ≥2 consecutive trios have 0 critical/high.
- Per OPERATOR-CARDS.md OC-019: audit panes from family ≠ synthesizer family.

---

## AE-7.2: Zero findings on first pass (under-reading)

**Symptoms:**
- Audit pane tail shows "I read the artifact" but cites no specific lines.
- Findings 0 because audit didn't actually engage.

**Bad audit produced:**
- Findings: 0; pane tails are 1-line.

**Diagnosis:** F-701 underwork. Liveness illusion (per LIVENESS-TRUTH-STACK in SKILL.md): pane "completed" but didn't substantively engage.

**Recovery:**
1. Reject the pane's verdict: "Your audit must cite ≥5 specific lines/sections of the artifact AND apply ≥3 operators (e.g., ✂ ⊞ ∿)."
2. Re-dispatch with explicit minimum requirements.
3. If re-dispatched output is still thin: kill+respawn the pane (context corruption, per `/vibing-with-ntm` OC-009).
4. Track in OPERATOR-CALIBRATION-LOG: which panes consistently under-read?

**Resulting good audit pattern:**
- Audit panes' findings cite specific artifact sections + specific operators applied.
- Pane tail captures show ≥10 lines of substantive content per audit round.

---

## AE-7.3: Too aggressive (everything is critical)

**Symptoms:**
- Audit pane returns 47 findings: 12 critical, 18 high, 11 medium, 6 low.
- Adjudicator reads them; most are stylistic / nit-pick, not load-bearing.

**Bad audit produced:**
- Severity inflation across the board.
- Adjudicator forced to triage manually.

**Diagnosis:** F-503 inflation. Audit pane treats all findings as equally significant (anti-CRITIQUE-CRAFT.md severity calibration).

**Recovery:**
1. Reject inflated findings: "Per CRITIQUE-CRAFT.md severity rubric: critical = falsifier-firing for an H; high = unverified load-bearing assumption; medium = recoverable issue; low = style/nit. Re-grade your 47 findings."
2. Pane re-grades, expected distribution: 1-3 critical, 3-7 high, 5-10 medium, 10-20 low.
3. If pane can't re-grade meaningfully: replace.

**Resulting good audit pattern:**
- Severity distribution roughly: 1 critical : 3 high : 5 medium : 10 low (per CRITIQUE-CRAFT.md calibration).
- Each finding cites specific evidence and specific severity-rubric criterion.

---

## AE-7.4: Rhetoric over evidence

**Symptoms:**
- Audit findings read like opinion pieces: "I think this approach is suboptimal" / "the design feels brittle."
- No specific EV-NNN or H-NNN cited.
- No verbatim quotes from the artifact.

**Bad audit produced:**
- 8 findings; all severity high; none cite specific beads or quotes.

**Diagnosis:** F-503 rhetoric. Per CRITIQUE-CRAFT.md, critiques without evidence are vibes, not audit findings.

**Recovery:**
1. Reject all rhetoric-only findings.
2. Re-dispatch: "Each finding must cite: (a) ≥1 specific bead (H-NNN or EV-NNN), (b) ≥1 verbatim quote from the artifact, (c) the methodology violation (F-### or OPERATORS.md card)."
3. If re-dispatch produces fewer findings (because pane can't ground them): that's correct behavior. Inflated rhetoric was hiding empty critique.

**Resulting good audit pattern:**
- Each finding has bead-cite + verbatim-quote + methodology-violation reference.

---

## AE-7.5: Same-pane audit (no independence)

**Symptoms:**
- Phase 7 audit dispatched to the same panes that produced Phase 6 distillations.
- Audit panes "approve their own work."

**Bad audit produced:**
- Predictable: panes don't find issues with their own outputs.

**Diagnosis:** F-705 audit-pane-equals-synthesizer-pane. Same blind spot.

**Recovery:**
1. Per OC-019 (OPERATOR-CARDS.md), audit panes MUST be from a family different from the dominant per-family distillation family.
2. Operator should kill audit dispatch immediately and re-dispatch via cross-family panes.
3. If insufficient cross-family panes available, operator must add: kill+respawn, or shift another pane's role.

**Resulting good audit pattern:**
- Per OC-019, audit panes are from family ≠ synthesizer family.
- Documented in `phase0_scope_decision.md § audit_pane_assignment`.

---

## AE-7.6: Falsifier softening (silent post-hoc rationalization)

**Symptoms:**
- During Phase 7 audit, an H-NNN.falsifier field looks different from Phase 3 snapshot.
- The new falsifier is easier to pass than the original.
- No explicit refinement bead documented.

**Bad audit produced:**
- Audit doesn't catch the softening.
- Phase 7 marks H confirmed based on lenient falsifier.

**Diagnosis:** F-303 silent drift. Possibly maliciously, possibly accidentally — either way, anti-Brenner.

**Recovery:**
1. Per `subagents/falsifier-grader.md`: re-grade ALL active H falsifiers at Phase 7 start.
2. Compare to Phase 3 snapshot (in `phase0_scope_decision.md § hypothesis_pre_registration`).
3. If softened: restore the original falsifier text with an explicit audit note OR document the refinement as a separate refinement-H per `MO-falsifier-fired.md` discipline.
4. For pre-registered sessions: this is a hard violation; re-run.

**Resulting good audit pattern:**
- Phase 7 includes explicit falsifier-history check.
- All falsifier changes are bead-documented refinements with ADR-style rationale.

---

## AE-7.7: Scale-physics skip

**Symptoms:**
- Some H beads have `assumption_type: scale_physics` (e.g., "memory bandwidth saturates at 100GB/s").
- Phase 7 audit doesn't re-verify the calculation.
- The downstream H assumed the calculation; if the calc is wrong, the H is unsupported.

**Bad audit produced:**
- Audit cleared H without re-checking the load-bearing assumption.

**Diagnosis:** F-704 audit-skips-load-bearing-assumption. Per OPERATORS.md ⊞ Scale-Check: every scale_physics assumption needs explicit Phase 7 re-verification.

**Recovery:**
1. Per OC-021 (OPERATOR-CARDS.md): Phase 7 audit explicit checklist item — for each `scale_physics` assumption, re-run the calculation independently.
2. If math doesn't hold: file critical audit-finding; the H depending on the assumption is affected.
3. If audit didn't do this: re-dispatch audit.

**Resulting good audit pattern:**
- Phase 7 audit checklist explicitly includes scale_physics re-verification.
- Each scale_physics assumption has a Phase 7 verification entry in `audit-findings/scale-physics-verification.md`.

---

## AE-7.8: Cross-family bypass

**Symptoms:**
- Phase 7 audit panes are all from same family (e.g., all cc).
- Cross-family findings don't surface.

**Bad audit produced:**
- Findings are family-coherent; cross-family blind spots persist.

**Diagnosis:** F-602 single-family dominance + F-705 audit-pane-blindness. Roster fails diversity check.

**Recovery:**
1. Run `scripts/list-distinct-model-families.sh` before audit.
2. If <2 families available: explicit note in HANDBACK that triangulation is degraded.
3. Otherwise: enforce cross-family audit (kill+respawn one pane in different family if needed).

**Resulting good audit pattern:**
- Audit panes from ≥2 families when available.
- Per OC-019: audit family roster differs from synthesizer roster.

---

## AE-7.9: Audit speed (rushed audit)

**Symptoms:**
- Phase 7 audit completed in <10 minutes.
- Operator rushed to hit Phase 8 deadline.

**Bad audit produced:**
- Findings appear comprehensive but are surface-level.

**Diagnosis:** Wall-time pressure caused operator to accept thin audit. F-WT-1 (per WALL-TIME-BUDGET.md hard breach).

**Recovery:**
1. Per WALL-TIME-BUDGET.md: hard-breach protocol — pause and decide. Don't extend silently.
2. Options: (a) escalate tier (T3 → T4 with extended budget), (b) accept incomplete with caveats, (c) reframe.
3. For audit specifically: never accept under-time audit; either extend OR mark deliverable as draft.

**Resulting good audit pattern:**
- Phase 7 wall-time budget honored: typically 30-60 min per trio-round, 2-3 rounds total.
- If under budget but still finds zero issues: 2nd trio with explicit "find ≥3" mandate.

---

## AE-7.10: Audit on stale artifact

**Symptoms:**
- Phase 7 audit dispatched against `meta_synthesis.md` rev N.
- Phase 6 panes meanwhile produced rev N+1 (caught a bug post-audit-dispatch).
- Audit's findings reference rev N; rev N+1 is what gets frozen.

**Bad audit produced:**
- Audit findings are misaligned with frozen artifact.

**Diagnosis:** Coordination failure. Audit dispatched without locking the artifact.

**Recovery:**
1. Per Phase 7 protocol: artifact must be content-hash-pinned before audit dispatch.
2. If artifact changes mid-audit: re-dispatch audit on new rev.
3. Alternatively: operator commits artifact to git BEFORE audit; audit operates against committed version.

**Resulting good audit pattern:**
- Phase 7 audit dispatch records artifact content-hash.
- Synthesizers are frozen during audit (no new edits to audited artifact).
- Post-audit findings are addressed in a separate revision pass.

---

## How to use audit anti-examples

### During Phase 7 audit dispatch

Operator drafts MO-07a-fresh-eyes dispatch. Before sending:
- Check: am I dispatching against same panes as synthesizers? (AE-7.5)
- Check: did I content-hash the artifact? (AE-7.10)
- Check: did I include scale-physics + falsifier re-grade? (AE-7.7, AE-7.6)

### During audit findings review

After trio-round 1 returns:
- Findings count = 0? Apply AE-7.1 recovery.
- Findings count = 47? Apply AE-7.3 recovery.
- Findings rhetoric-only? Apply AE-7.4 recovery.
- Same-pane audit? Apply AE-7.5 recovery.

### During Phase 10 drift

Drift auditor checks: did Phase 7 match any AE-7.* pattern? Document in DRIFT-CHECK.md.

---

## Cross-references

- SIX-LAYER-VALIDATION.md (Layer 1-5 should catch many AE-7)
- OPERATOR-CARDS.md OC-019 to OC-021 (Phase 7-specific cards)
- CRITIQUE-CRAFT.md (severity calibration; rhetoric vs evidence)
- WALL-TIME-BUDGET.md (audit wall-time protocol)
- FAILURE-TABLE.md (F-7xx audit failures)
