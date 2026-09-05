# MO-pre-publication-review.md — Adversarial Review Before Publication

**Phase:** Phase 7 (audit) for any T4+ session whose deliverable will be published
**Operators activated:** † Theory-Kill, ✂ Exclusion-Test, ∿ Dephase
**Parameters:** `<DELIVERABLE_PATH>`, `<PUBLICATION_VENUE>`, `<SESSION_ID>`

---

A deliverable published externally has reputation cost if wrong. This MO is the publication-grade adversarial review. Per `pre-publication-review` mode in EXTENDED-OPERATING-MODES.md.

---

**Step 1 — Identify reviewers.**

For T5: ≥3 external reviewers (NOT the original session's panes).

For T4: ≥1 external reviewer + 1 brennerbot adversarial sub-session.

External reviewers can be:

- Subject-matter experts (domain content)
- Methodology experts (Brenner-method)
- Adversarial reviewers (would attack)

Document reviewer roster in `analyses/pre-publication-review/reviewer-roster.md`.

**Step 2 — Brief reviewers.**

Each reviewer receives:

- The deliverable (`<DELIVERABLE_PATH>`)
- The session's HANDBACK + KEY-DECISIONS-LOG + DRIFT-CHECK
- Their role (SME / methodology / adversarial)
- Specific questions to answer

Sample reviewer brief:

```markdown
You are reviewing a brennerbot-with-ntm session output for publication at <PUBLICATION_VENUE>.

Your role: <role>

Specifically address:

[For SME reviewer:]
1. Are the substantive claims defensible by domain standards?
2. Is the related work fairly represented?
3. Are there obvious counter-examples we missed?
4. What would a skeptical SME object to?

[For methodology reviewer:]
1. Is the falsifier discipline maintained throughout?
2. Are the operator cards applied per OPERATORS.md?
3. Is the disagreement_register substantive (not silent averaging)?
4. Is Phase 7 audit complete or would you find additional issues?

[For adversarial reviewer:]
1. What's the strongest attack on the load-bearing claim?
2. What evidence type is the deliverable most vulnerable to (e.g., a counter-example, a stronger algorithm, a different metric)?
3. If you wanted to write a rebuttal, what would your strongest one-paragraph attack be?

Format: file findings in `analyses/pre-publication-review/<reviewer>-findings.md`.
Severity: critical | high | medium | low.
```

**Step 3 — Run brennerbot adversarial sub-session (T4+).**

In addition to external reviewers, run a `red-team-only` mode session (per EXTENDED-OPERATING-MODES.md):

- Target: the deliverable
- Roster: Squad with mandatory red-team-tool composition
- Phases: 1, 3, 5, 7 only (compressed)
- Output: red-team-findings.md

**Step 4 — Aggregate findings.**

```markdown
# In analyses/pre-publication-review/AGGREGATE.md:

# Pre-publication review aggregate

## Reviewers consulted
- <name 1> (<role>)
- <name 2> (<role>)
- ...

## Findings by severity
| Severity | Count | Source |
|----------|-------|--------|
| critical | N     | <reviewer> |
| high     | N     | <reviewer> |
| medium   | N     | <reviewer> |
| low      | N     | <reviewer> |

## Critical findings (must address)
- <finding 1>
- <finding 2>

## High findings (strongly recommend address)
- <finding 1>
...

## Verdict
- READY FOR PUBLICATION (no critical findings)
- READY WITH REVISIONS (critical/high findings addressable)
- NOT READY (fundamental methodology or content issues)
```

**Step 5 — Address findings.**

For each critical / high finding:

- File audit-finding bead
- Phase 4 reopen if substantive
- Update deliverable with revision
- Re-review the affected section

For medium / low findings:

- Aggregate; address in batch
- Document any non-addressed (with reason) in deliverable's caveats section

**Step 6 — Final sign-off.**

Each reviewer signs off (via comment in `aggregate.md`):

```markdown
## Sign-off

- [x] <Reviewer 1> — date — "Findings addressed satisfactorily."
- [ ] <Reviewer 2> — pending revision review
```

Don't publish before all reviewers sign off (or document why specific reviewer's findings were not addressed).

**Step 7 — Update HANDBACK.**

Add to deliverables/HANDBACK.md § Cross-references:

```markdown
- Pre-publication review: <date> | <reviewer count> reviewers | aggregate at analyses/pre-publication-review/AGGREGATE.md
- Critical findings addressed: <count>
- Outstanding caveats: <list> (if any)
```

---

**Anti-patterns:**

- ✗ Skip pre-publication review for "low-stakes" publication (reputation cost is non-zero)
- ✗ Use only original session's panes as reviewers (no independence)
- ✗ Override reviewer's critical findings without addressing (reputation cost)
- ✗ Treat reviewer findings as suggestions vs requirements
- ✗ Skip the brennerbot red-team for T4+ (external reviewer alone insufficient at T4+)

**Ship-or-Surface SLA:** wall time depends on review depth; T4 typical: 1-2 weeks; T5: 4-8 weeks.

---

## Composition

- Compose with /multi-pass-bug-hunting if deliverable contains code
- Compose with /lean-formal-feedback-loop if formal claims are made
- Compose with subagents/red-team.md as standard

Per SKILL-COMPOSITION-PATTERNS.md.
