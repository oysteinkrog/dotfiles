# MO-deliverable-rejection.md — When Deliverable Fails Sanity Check

**Phase:** 9 (HANDBACK production)
**Operators activated:** ✂ Exclusion-Test (re-verify), ∿ Dephase
**Parameters:** `<DELIVERABLE_PATH>`, `<REJECTION_REASON>`, `<SESSION_ID>`

---

Sometimes the operator drafts a HANDBACK / DECISION-MEMO / THREAT-CATALOG and notices it doesn't pass sanity check. Common signals:
- Verdict feels disconnected from the evidence
- Confidence claim doesn't match the W-aggregate
- HANDBACK reads like rationalization, not synthesis
- Specific cited EVs don't actually support the verdict on re-read

The temptation: ship anyway because Phase 9 is supposed to be "wrap-up". The discipline: reject the deliverable, fix the underlying issue, re-produce.

This MO is that discipline.

---

**Step 1 — Identify the rejection signal.**

Common rejection categories:

### R1: Verdict-evidence disconnect

Verdict says X; cited EVs support Y or are silent on X.

### R2: Confidence-W mismatch

HANDBACK states confidence:high; W aggregate is below 0.7.

### R3: Caveat-gap

Load-bearing assumption isn't stated. The verdict could be wrong if assumption is wrong but reader doesn't know.

### R4: Action-rule unclear

"Migrate by Q3" without specific date, owner, or rollback plan.

### R5: Unresolved-thread incomplete

Unresolved H/EV/AF/D listed under "What's still open" without `next-action:` (per F-902).

### R6: Voice failure

HANDBACK has hedged language ("appears to suggest", "could potentially") that obscures the verdict.

### R7: Citation density too low

≤3 sentences of reasoning with 0 EV citations (per CRITIQUE-CRAFT.md guidance).

### R8: Length issue

HANDBACK > 80 lines (per F-901).

**Step 2 — Reject the draft.**

```bash
# Move draft to rejected/:
mv deliverables/HANDBACK.md deliverables/_rejected/HANDBACK-DRAFT-<TIMESTAMP_UTC>.md

# Document the rejection:
cat >> deliverables/_rejected/REJECTION-LOG.md <<EOF

## <TIMESTAMP_UTC> — HANDBACK draft rejected

**Reason:** <R1-R8>
**Specific issue:** <one-line>
**Recovery action:** <what to fix>
EOF
```

**Step 3 — Address root cause.**

### R1 (verdict-evidence disconnect) recovery

The verdict is rationalized, not synthesized. Re-read the cited EVs. Either:
- Change the verdict to match the evidence, OR
- Find the missing EVs that would support the original verdict (Phase 4 reopen)

### R2 (confidence-W mismatch) recovery

Either downgrade the confidence (per MO-confidence-downgrade.md) OR strengthen evidence (per MO-evidence-promote.md). Don't fudge.

### R3 (caveat-gap) recovery

Identify the load-bearing assumption that, if wrong, flips the verdict. Add to HANDBACK as explicit caveat.

### R4 (action-rule unclear) recovery

Per HANDBACK-VOICE-GUIDE.md imperative principle: tell the user what, when, by whom. Re-write action items as SMART (specific, measurable, assigned, realistic, time-bound).

### R5 (unresolved-thread incomplete) recovery

For each item listed under "What's still open", add a `next-action:` field. Run `audit-bead-invariants.sh --check=handback_open_thread_tags` to verify.

### R6 (voice failure) recovery

Per HANDBACK-VOICE-GUIDE.md, replace hedge phrases with direct assertions. If genuinely uncertain, state it explicitly with flip-condition.

### R7 (citation density) recovery

Add EV citations where claim load is highest. Per CRITIQUE-CRAFT.md, ≥3 EV cites in reasoning section.

### R8 (length issue) recovery

Compress, don't extend. Per HANDBACK-VOICE-GUIDE.md tightening table. Move detail to longer artifacts (DECISION-MEMO.md) and reference from HANDBACK.

**Step 4 — Re-produce the deliverable.**

After fixing root cause, re-draft. Run the editing pass per HANDBACK-VOICE-GUIDE.md.

**Step 5 — Run sanity check.**

Self-check before finalizing:

1. Does verdict match cited evidence? (R1)
2. Does confidence match W aggregate? (R2)
3. Are load-bearing assumptions stated? (R3)
4. Are actions SMART? (R4)
5. Do unresolved threads have next-action? (R5)
6. Is voice direct? (R6)
7. Is citation density healthy? (R7)
8. Is length ≤80 lines? (R8)

If all pass, proceed to Phase 8 freeze.

If any fail, return to Step 2 (reject again).

**Step 6 — If repeated rejections.**

If 3+ consecutive drafts fail sanity check, the underlying issue may be deeper than draft quality:

- Phase 4 may have produced flawed evidence (Phase 4 reopen)
- Phase 6 distillation may have missed disagreements (Phase 6 redo)
- Question framing may have been wrong (Phase 1 reframe)

Per OC-024 (OPERATOR-CARDS.md): operator should escalate rather than push through.

**Step 7 — Document the rejection-recovery cycle.**

In `analyses/handback-revisions.md`:

```markdown
| Iteration | Rejection reason | Recovery action | Result |
|-----------|------------------|-----------------|--------|
| 1 | R2 | downgraded H-005 from high to medium | confidence aligned with W |
| 2 | R7 | added EV-018 citation | density adequate |
| Final | (passed) | committed | Phase 8 ready |
```

**Step 8 — Phase 10 lesson candidate.**

If rejection pattern recurs across sessions, file as Phase 10 lesson:

- "Recurring R6 (voice hedge): operator needs HANDBACK-VOICE-GUIDE.md training"
- "Recurring R7 (low citation density): operator needs CRITIQUE-CRAFT.md re-read"

Per OPERATOR-CALIBRATION-LOG.md.

---

**Anti-patterns:**

- ✗ Ship a flawed deliverable to "save time"
- ✗ Patch the deliverable rather than fix the root cause
- ✗ Reject without specific R1-R8 categorization
- ✗ Re-draft 5+ times without escalating to Phase 4/6/1 reopen
- ✗ Skip the rejection log (future operators won't see the pattern)

**Ship-or-Surface SLA:** within 30-60 min per rejection cycle.

---

## When the deliverable can't be made sound

Sometimes the underlying session is genuinely under-determined:
- Insufficient evidence to reach a confident verdict
- Genuine equipoise between competing hypotheses
- Methodology gaps that can't be closed within session budget

In these cases:
- Don't fake a confident HANDBACK
- Produce a "session incomplete" HANDBACK that explicitly documents the indeterminacy
- Recommend follow-up sessions OR external expertise

This is honest reporting; per HANDBACK-VOICE-GUIDE.md, "we don't know" with explicit reasons is a valid verdict.

---

## Composition with other patterns

- Per HANDBACK-VOICE-GUIDE.md: editing pass and tightening table
- Per CRITIQUE-CRAFT.md: severity-grading and citation density
- Per CONFIDENCE-SCORING.md: W-confidence calibration
- Per MO-confidence-downgrade.md: when verdict is over-confident
- Per ANTI-PATTERNS.md: ship-quality discipline

---

## Cross-references

- HANDBACK-VOICE-GUIDE.md (the voice and structure rules)
- CRITIQUE-CRAFT.md (severity and citations)
- FAILURE-TABLE.md (F-901, F-902)
- OPERATOR-CARDS.md OC-024 + OC-025
- ANTI-PATTERNS.md (handback drift)
