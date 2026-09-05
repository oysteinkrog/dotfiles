# Dual-Use Ethics Review

**Reviewed deliverable:** <DELIVERABLE_PATH>
**Domain:** <DOMAIN>
**Review date:** <ISO>
**Reviewer:** <name / ethics-reviewer subagent>

---

## Reviewers consulted

- [<name 1>] (<role>) — sign-off date: <ISO>
- [<name 2>] (<role>) — sign-off date: <ISO>
- [ethics-reviewer subagent] — automated; recommendation only

(For T5: ≥3 human reviewers; severity:critical concerns always require human review.)

---

## Dual-use surface analysis

| Claim/technique | Defensive use | Offensive use | Severity if misused |
|-----------------|---------------|---------------|---------------------|
| <C1>            | <case>        | <case>        | <low/med/high/crit> |
| <C2>            | ...           | ...           | ...                 |
| <C3>            | ...           | ...           | ...                 |

**Summary surface assessment:** <one paragraph>

---

## Ethical framework analysis

(Per Asilomar / Pilbara / NeurIPS dual-use framework.)

### 1. Direct harm potential

**Q:** Who could be harmed by this output, in what scenarios?

**A:** <answer>

### 2. Counterfactual impact

**Q:** Would this be available without our work? Is it a re-discovery of widely-known result?

**A:** <answer>

### 3. Asymmetry

**Q:** Does the output favor defense or attack?

**A:** <answer>

### 4. Mitigation strategy

**Q:** Can we design publication/release to favor defense?

**A:** <answer; list specific mitigations>

### 5. Disclosure ethics

**Q:** Should this be disclosed responsibly (vendors first, with embargo)?

**A:** <answer>

### 6. Long-term concerns

**Q:** Even if low risk now, does the output enable future harm?

**A:** <answer>

---

## Mitigations applied

| Mitigation | Implementation | Owner | Status |
|------------|----------------|-------|--------|
| <m1> | <how> | <name> | <planned/in-progress/done> |
| <m2> | <how> | <name> | <planned/in-progress/done> |

---

## Verdict

(Choose one:)

- [ ] **PUBLISH AS-IS** — no significant dual-use concerns
- [ ] **PUBLISH WITH REDACTION** — methodology OK; specific elements need redaction
- [ ] **COORDINATED DISCLOSURE FIRST** — notify vendors/authorities, embargo period, then publish
- [ ] **DO NOT PUBLISH** — risk too high; insight stays internal
- [ ] **ESCALATE TO HUMAN GOVERNANCE BODY** — beyond reviewer authority; needs IRB/DSAI/etc

**Verdict explanation:** <2-3 paragraphs>

---

## If verdict is "PUBLISH WITH REDACTION"

**Items to redact:**

- <item 1>
- <item 2>

**Redaction approach:** <e.g., replace specific code with pseudo-code; remove specific datasets; etc>

---

## If verdict is "COORDINATED DISCLOSURE FIRST"

**Disclosure plan:**

- Who to notify (vendors / researchers / authorities):
  - <name 1>
  - <name 2>
- What to share with each:
  - <recipient 1>: <content>
  - <recipient 2>: <content>
- Embargo timeline: <duration>
- Public release date: <ISO>

(Save full plan in `analyses/dual-use-review/DISCLOSURE-PLAN.md`.)

---

## If verdict is "DO NOT PUBLISH"

**Restriction reason:** <one paragraph>

**Workspace status:**

- [ ] Marked `restricted: true; restriction_reason: <one-line>` in HANDBACK
- [ ] Not committed to public git
- [ ] Internal use only

**Periodic review:** Schedule quarterly review; conditions may change.

---

## If verdict is "ESCALATE"

**Escalation target:** <governance body>
**Escalation contact:** <name / email>
**Halt conditions:** <e.g., "no Phase 8 freeze pending response">

---

## Caveats / dissents

(Any concerns from reviewers that didn't change the verdict but should be documented for posterity.)

- <caveat 1>
- <caveat 2>

---

## Reviewer sign-off

- [ ] <reviewer 1>: <name> — <ISO>
- [ ] <reviewer 2>: <name> — <ISO>
- [ ] <reviewer 3 (T5 only)>: <name> — <ISO>

(Sign-off attests reviewer has read the deliverable, applied the framework, and accepts the verdict + mitigations.)

---

## Re-review trigger conditions

This review is valid as of <ISO>. Re-review if any of:

- New evidence about offensive misuse surfaces
- Mitigation strategy fails (e.g., disclosure embargo broken)
- Domain risk landscape changes
- Methodology improvement catches issue this review missed

---

## Cross-references

- HANDBACK.md § Ethical considerations: <link>
- DISCLOSURE-PLAN.md (if applicable): <link>
- Pre-publication review (if T5): <link to AGGREGATE.md>
