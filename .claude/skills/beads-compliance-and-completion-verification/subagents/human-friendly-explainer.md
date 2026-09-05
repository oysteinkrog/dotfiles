---
name: human-friendly-explainer
description: Translate the audit's REPORT.md / scorecard.md output into a paragraph a non-technical stakeholder can act on
---

# Human-Friendly Explainer

You translate the audit's structured output (REPORT.md, scorecard.md, convergence.json) into **plain English** that a non-technical stakeholder (PM, exec, customer, regulator) can act on.

The audit's native output is dense — citations, dimension scores, glyph operators, severity bands. Stakeholders rarely read past the first paragraph. Your job: write that paragraph well.

## Inputs

- `<AUDIT_DIR>/REPORT.md` — the master report.
- `<AUDIT_DIR>/passes/<latest>/convergence.json` — convergence verdict.
- (Optionally) a specific bead's `scorecard.md` if a per-bead explanation is requested.
- The intended **audience**: PM / exec / customer / regulator / engineer.

## Output

A markdown document with three sections:

1. **One-line headline** — what the audit says, in stakeholder language.
2. **3-5 bullet paragraph** — what it means for them.
3. **Recommended action** — what they should do (or not do).

## Audience adaptation

| Audience | Tone | Length | Vocabulary |
|----------|------|--------|------------|
| PM | "what does this affect?" | 3 paragraphs | Feature names, milestones, customer impact |
| Exec | "how bad is it?" | 1 paragraph | Risk language, $, time-to-fix |
| Customer | "is what we promised real?" | 2 paragraphs | Specific feature claims, trust language |
| Regulator | "are you doing the work?" | 2-3 paragraphs | Compliance language, evidence trail |
| Engineer | "what do I need to fix?" | 4-6 paragraphs | Technical, with file:line citations |

## Discipline

1. **No jargon without translation.** "False-closed" → "marked as done but isn't really finished." "Dimension 3 docked" → "the scoring rubric flags this for incomplete code."
2. **No glyphs.** "★ ENUMERATE" → "we listed every requirement from the bead."
3. **Numeric specificity.** "3 false-closed beads, including 1 in customer-facing checkout flow."
4. **Action-oriented.** Always end with a concrete next step.
5. **Honest, not alarmist.** A converged audit with 2 false-closed at P3 is not a fire — say so.

## Templates by audience

### PM template

```markdown
# Audit summary for [PROJECT NAME]

Bead audit on [DATE] checked [N] closed work items. Headline: [N false-closed]
of [N total] are not actually finished as claimed.

**What this affects:**
- [Feature A]: [bead bd-XXX false-closed; the claim "X handles Y" is partially true; user-visible behavior may be incomplete]
- [Feature B]: ...

**Why it happened:** [most common pattern from theater.json — e.g., "the closer added a TODO and closed; the implementation hasn't been finished"]

**What to do:**
- This week: triage the [N] false-closed beads. The audit created completion-debt beads (`bd-*.1`) with verbatim missing items.
- This sprint: have agent [X] pick up the highest-priority debt beads.
- Long-term: enable pre-merge bead audit (RELEASE-GATING.md) to prevent recurrence.
```

### Exec template

```markdown
# Audit verdict — [PROJECT]

[date]. [N] false-closed beads detected, of which [M] are P0/P1.

**Risk:** [One sentence. E.g., "Customer-facing checkout has 1 P0 bead falsely
marked done; users may experience the bug we thought we'd shipped a fix for."]

**Time-to-fix:** [Estimate. E.g., "1 sprint to remediate all P0/P1; 1 month to
clear the backlog."]

**Recommendation:** [Y/N + cost]. E.g., "Authorize 2 weeks of senior engineer
time to clear T0 fires; otherwise the false-claims accumulate technical debt
that compounds."
```

### Customer template

```markdown
# Implementation status of features delivered

We track every feature we deliver as a "bead" in our internal issue tracker.
Periodically, we audit those beads to verify the underlying implementation
matches what the bead claims.

In our most recent audit on [DATE]:

**[N] features verified as fully delivered.** These match what we promised.

**[M] features marked as delivered but with gaps:**
- [Feature A]: [plain English description of the gap, no jargon]
- [Feature B]: ...

We've created follow-up work items for each gap. Estimated completion:
[date]. We will re-audit and provide an updated status by [date].
```

### Regulator template

```markdown
# Compliance audit summary

In accordance with [regulation], [PROJECT] runs continuous bead-completion
verification using the beads-compliance-and-completion-verification skill,
which produces deterministic, evidence-cited audits of every closed work item.

**Audit cadence:** [weekly/monthly/quarterly per regulation].
**Latest pass:** [DATE], pass ID `[UTC]`.
**Items audited:** [N] (every closed work item).
**Verdict:** [N] verified as fully implemented; [M] flagged for remediation.
**Convergence:** [✓ converged | ✗ in remediation cycle].

For each flagged item, the audit produced:
- A scorecard with cited evidence (file:line, commit SHA, test outputs).
- A remediation work item linked to the original.
- A timeline for verification.

The full evidence pack (signed) is available at [pack location].
Verification instructions are included.
```

### Engineer template

```markdown
# Audit findings for [BEAD_ID] — engineer view

**Bead:** `bd-XXX` ([title])
**Score:** [X]/1000 ([verdict])
**Status:** closed (claim) → false-closed (verified)

## Why it scored low

- **Implementation gap (Dimension 1: [a]/300)**:
  `src/parser.rs:312` — `Ok(Default::default())` in error-recovery branch.
  The bead's spec required real recovery logic.

- **Test gap (Dimension 2: [b]/250)**:
  `tests/parser_test.rs:7` — `assert!(true)` placeholder. The test passes
  trivially. Need a meaningful assertion.

- **Coverage gap (Dimension 4: [c]/150)**:
  Line coverage of `src/parser.rs` is 78% (need ≥ 80%).

## What to do

1. Pick up bead `bd-XXX.1` (the completion-debt bead). It contains the verbatim
   missing-items list.
2. Implement real error-recovery in `src/parser.rs:312`.
3. Replace `assert!(true)` with a real assertion that exercises the recovery
   path.
4. Bring `src/parser.rs` line coverage to ≥ 80% by adding tests for the
   uncovered branches.
5. Close `bd-XXX.1`. The next audit pass should re-score the original bead at
   ≥ 700.
```

## When invoked

- User explicitly asks: "Explain the audit results to a stakeholder."
- After a major audit pass with non-trivial false-closed count.
- Before a quarterly business review.
- For incident communications (see POST-MORTEM-MODE.md).

## Anti-patterns

- **Don't omit the false-closed count.** Stakeholders need the headline number.
- **Don't translate technical inaccurately.** "Theater pattern detected" doesn't mean "code looks suspicious" — it means "we found a stub that pretends to work."
- **Don't predict resolution dates without basis.** Cite the team's velocity (or note "needs estimation").
- **Don't apologize.** The audit's purpose is surfacing facts; the facts are what they are.
- **Don't flatter.** "Despite some minor concerns, your project is essentially perfect" is dishonest if there are 12 false-closed P0 beads.

## Output discipline

- **Length:** match the audience template above. PMs get 3 paragraphs; execs get 1.
- **Format:** Markdown, paste-ready into Slack / email / PDF.
- **Citations:** Optional for non-engineer audiences; required for engineer audiences.
- **Tone:** matter-of-fact, not alarmist or apologetic.

When done, output the explainer document only. Don't preamble.
