# DRIFT-RUBRIC.md — Methodology Drift Check

<!-- TOC: The Replacement Test | Auditor Inputs | Rubric Sections | Improvements | Regressions | Lessons | Drift Verdict | Audit Anti-Patterns | When to Skip Phase 10 -->

Phase 10 compares actual session trajectory to canonical Brenner. The drift auditor is a *fresh* agent (not in the original swarm) that produces `deliverables/DRIFT-CHECK.md`.

This rubric is the auditor's checklist. It is intentionally strict: the default verdict for any deviation is **regression** unless the auditor can cite an explicit replacement test.

---

## The Replacement Test

A deviation is an *improvement* only when:

1. The skipped/modified Brenner principle (operator, phase, exit gate) is named explicitly with `§`-anchor.
2. The replacement is named explicitly with rationale.
3. The replacement is **measurably stronger** by a specific metric (more Hs killed, more EVs verified, faster convergence, lower wall time, fewer audit findings).
4. The metric is reported with a number, not a vibe.

If any of (1)–(4) is missing, the verdict is **regression**.

---

## Auditor Inputs

The drift auditor reads:

- `phase0_scope_decision.md` — what was *intended*
- `session-logs/round-*.md` — what *happened* tick-by-tick
- `phase_*_complete.flag` — phase exit timestamps
- All dispatched marching orders (logged in `session-logs/dispatch-*.log`)
- `deliverables/RESUME.md` and `HANDBACK.md`
- Beads state via `br list --json`

The auditor does **not** read `intake/question_of_record.md` to form a domain opinion — drift check is methodology-level, not content-level.

---

## Rubric Sections

### 1. Operators applied vs canonical

For each of the 15 operators in [OPERATORS.md](OPERATORS.md), record:

| Operator | Phase fired | Evidence | Verdict |
|----------|-------------|----------|---------|
| ◊ Paradox-Hunt | 1 | `intake/question_of_record.md § Paradox` non-empty | applied |
| ⊘ Level-Split | 3 (triage) | `H-*.category` field set on every H | applied |
| 𝓛 Recode | 3 (proposal) | `H-*.statement` includes coordinate spec | applied |
| ≡ Invariant-Extract | 4 (investigation) | `EV-*.key_findings` non-empty for every verified EV | <verdict> |
| ✂ Exclusion-Test | 3 + 4 | mandatory `falsifier:` field on every H AND probed in Phase 4 | <verdict> |
| ⟂ Object-Transpose | 4 | `EV-pack-*.md § Methodology § Proxy` non-empty | <verdict> |
| ↑ Amplify | 4 + 5 | `T-*.expected_signal` ≥10× or binary | <verdict> |
| ⌂ Materialize | 3 | mandatory `expected_evidence:` on every H | <verdict> |
| 🔧 DIY | 4 | scripts in `deliverables/scripts/` | <verdict> |
| ⊞ Scale-Check | 4 + 7 | every `assumption.type:scale_physics` has calculation | <verdict> |
| 🤝 GAN | 5 | DEBATE-* champions from different model families | <verdict> |
| ΔE Exception-Quarantine | 4 + 7 | `anomaly_register.md` with cluster check | <verdict> |
| † Theory-Kill | 5 | `state: refuted` with `refuted_by` | <verdict> |
| ∿ Dephase | 7 + 10 | audit log addresses "consensus reproduction" check | <verdict> |
| ⊙ Productive-Ignorance | 2 | `phase0_scope_decision.md` records ignorance pane | <verdict> |

**Verdict legend:** `applied` (full), `partial` (some panes/phases applied, others didn't), `skipped` (not applied at all), `replaced` (intentionally replaced by something else — must pass the replacement test).

For each `partial` / `skipped` / `replaced`, the auditor writes a 1-paragraph note. For `replaced`, the replacement test fields go in.

---

### 2. Phase ordering vs canonical

| Phase | Started at | Completed at | Skipped? | Reordered? | Verdict |
|-------|-----------|--------------|----------|------------|---------|
| 1 | <ISO> | <ISO> | no | no | normal |
| 2 | <ISO> | <ISO> | no | no | normal |
| 3 | ... | ... | no | no | normal |
| 4 | ... | ... | no | no | normal — N rounds, kill_rate ≥ add_rate at round M |
| 5 | ... | ... | no | no | normal |
| 6 | ... | ... | no | no | normal — converged at pass M |
| 7 | ... | ... | no | no | normal — converged at trio-round M |
| 8 | ... | ... | no | no | normal |
| 9 | ... | ... | no | no | normal |
| 10 | ... | (this run) | n/a | n/a | n/a |

**Common deviations:**

- **Phase 4 hard-capped at 6 rounds without convergence.** Auditor records: "Phase 4 did not converge; exited via hard cap. Likely cause: [...]. Recommendation for next loop: [...]."
- **Phase 5 skipped because only 1 hypothesis survived Phase 4.** Auditor records: "Single-hypothesis exit from Phase 4 → Phase 5 trivially adjudicated. Verify the lone surviving H actually has ≥2 supporting EVs from independent sources."
- **Phase 6 ran with only 1 model family in roster (Solo tier).** Auditor records: "Solo tier eliminates triangulation; `disagreement_register.md` cannot be populated. This is a known Solo limitation, not a regression."
- **Phase 8 freeze deferred until next session start.** Regression: Phase 8 must run at session end; deferring breaks resume semantics.

---

### 3. Marching-order modifications

For each `MO-*.md` template that was dispatched, did the operator deviate? List deviations:

```markdown
- **MO-04a-investigate.md** dispatched 4 times. 1 deviation:
  - Round 2 to pane 5: Operator added "skip the Object-Transpose step; investigate H-007 directly in production code." Rationale: corpus too small to host a meaningful proxy. Verdict: replacement-tested OK (smaller workspace; no decisive proxy available).
- **MO-05a-cross-exam.md** dispatched 3 times. 0 deviations.
- ...
```

Deviations without rationale are flagged regressions.

---

### 4. Convergence behavior

For each reapply-until-quiet phase:

| Phase | Rounds run | Hard cap (6/4/4) | Converged? | Reason if not |
|-------|-----------|-----------------|------------|---------------|
| 4 | 4 | 6 | yes (round 4: kill_rate 3, add_rate 1) | n/a |
| 6 | 2 | 4 | yes (pass 2: only typo edits) | n/a |
| 7 | 3 | 4 | yes (trio-round 3: 0 critical/high findings) | n/a |

If hard cap hit without convergence, auditor describes:

- What was un-converged
- Likely cause
- Recommendation: retry Phase X / abandon question / reframe

---

### 5. Evidence + bead invariants

The auditor runs `scripts/audit-bead-invariants.sh` and reports any violations:

- Hypotheses without `falsifier:` (per ✂)
- Hypotheses without `expected_evidence:` (per ⌂)
- `state: refuted` without `refuted_by` (per †)
- `state: confirmed` without ≥1 DEBATE + ≥2 EV from independent sources
- `assumption.type:scale_physics` without `calculation:` (per ⊞)
- Slate without `origin:third_alternative` (per Brenner §103)
- Disagreement register entries < (N choose 2) where N = model families

Violations are regressions.

---

### 6. Improvements section

If any deviation passed the replacement test, list under `## Improvements`:

```markdown
## Improvements

### I-001: Replaced ⟂ Object-Transpose at Phase 4 round 2 with direct code investigation
- **Replaced:** ⟂ Object-Transpose (Brenner §91)
- **Replacement:** direct investigation against the target codebase (no proxy)
- **Rationale:** corpus was the codebase itself; no proxy was available cheaper than the direct surface
- **Metric:** investigation completed in 18 min (vs estimated 90 min for proxy-search-then-investigate)
- **Verdict:** improvement (4× speedup; same investigative depth verified by Phase 7 audit)
```

---

### 7. Regressions section

For every operator/phase/invariant verdict that was `partial` / `skipped` / a deviation without replacement test, write a regression entry:

```markdown
## Regressions

### R-001: ∿ Dephase operator never fired in Phase 7 audit
- **Source:** §143 (out of phase), §192 (opening game)
- **Expected:** Phase 7 audit log addresses "is our top H just inheriting consensus?"
- **Actual:** No mention of consensus check in any audit round.
- **F-code:** F-1001 (would have caught this if Phase 10 had run earlier)
- **Recommendation:** Add "consensus check" to MO-07a-fresh-eyes.md as mandatory step 6.
```

---

### 8. Lessons section

The auditor writes ≥1 lesson that updates a `references/` file:

```markdown
## Lessons

### L-001: Update OPERATORS.md ⟂ card to allow "no proxy" as a documented case
- **Reason:** the corpus-mode improvement (I-001) revealed that ⟂'s recipe doesn't always apply when the question target IS the natural primary surface.
- **Change:** Add a "When NOT to apply ⟂" subsection in OPERATORS.md with the conditions.
- **Owner:** operator commits this update before closing Phase 10.
```

The skill cannot exit Phase 10 without ≥1 lesson committed.

---

## Drift Verdict (one-line summary)

The auditor produces a single-line verdict at the top of `DRIFT-CHECK.md`:

```
DRIFT VERDICT: <convergent | divergent-improvement | divergent-regression | mixed>
```

- **convergent**: every operator applied, every phase ran in canonical order, every invariant satisfied. Lessons are *enhancements*, not corrections.
- **divergent-improvement**: ≥1 deviation, all of which passed the replacement test. Lessons document the new patterns.
- **divergent-regression**: ≥1 deviation that failed the replacement test. Lessons document the fix for next session.
- **mixed**: improvements AND regressions. Both lists populated.

---

## Audit Anti-Patterns

| ✗ | Why | Fix |
|---|-----|-----|
| Treat "we couldn't find a proxy" as automatic improvement | Skipping ⟂ might just be laziness; require the replacement test | rubric line 1 |
| Skip the bead-invariants check because "we trust the panes" | Invariants are the floor; without them, the rubric is vibes | section 5 mandatory |
| Verdict: "improvements" without metrics | "It seemed faster" is not a metric | section 6 requires numbers |
| Audit by reading distillations only, not session logs | Distillations are post-hoc; session logs show what *happened* | inputs section requires logs |
| Write lessons for next session without committing them | The `references/` file MUST be updated; otherwise lessons are forgotten | rubric exit gate |
| Run the drift check from a swarm pane | Drift check requires fresh perspective; use a fresh general-purpose Agent | inputs explicitly say "fresh agent" |

---

## When to Skip Phase 10

Phase 10 can be skipped only when:

- Mode is `incident-investigation` (compressed phases; no methodology evolution intended)
- Mode is `methodology-drift-check` (Phase 10 IS the whole session — recursive Phase 10 makes no sense)

In all other modes, Phase 10 is mandatory. Skipping it is itself a regression that the *next* drift check will flag.
