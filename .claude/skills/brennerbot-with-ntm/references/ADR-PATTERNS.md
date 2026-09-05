# ADR-PATTERNS.md — Architecture Decision Records Embedded in Research Artifacts

<!-- TOC: When to use ADRs | ADR template | ADR-vs-decision-memo | ADR lifecycle | Anti-patterns -->

For T4+ sessions where load-bearing decisions warrant durable records (per WALL-TIME-BUDGET.md), embed Architecture Decision Records (ADRs) in the workspace. This file documents the pattern.

Adapted from Michael Nygard's ADR pattern + saas-billing's ADR system.

---

## When to use ADRs

Use ADRs when:

- Tier is T4+ (high-stakes / existential)
- The session produced a load-bearing decision that will be referenced by future work
- The decision has notable trade-offs that future engineers/researchers should understand
- The decision is partially-irreversible AND a future revisit needs to understand the original reasoning

Don't use ADRs for:

- T1-T2 sessions (heavy machinery for low-stakes decisions)
- Operational decisions (use commit messages instead)
- Decisions that are obviously correct (no notable trade-off)

---

## Where ADRs live

Within the workspace: `<workspace>/deliverables/adr/<NNNN>-<short-slug>.md`

Cross-session ADRs (decisions that span multiple brennerbot sessions): under `references/adr/` in the skill repo, OR a separate organizational ADR repo.

---

## ADR template

```markdown
# ADR-NNNN: <one-line decision>

**Status:** proposed | accepted | superseded by ADR-NNNN | deprecated
**Date:** <YYYY-MM-DD>
**Deciders:** <operator + user + reviewers>
**Session:** RS-<YYYYMMDD>-<slug>

## Context

(1-2 paragraphs describing the situation that necessitated this decision. Cite the question of record + key evidence beads. The reader should understand why we faced this decision.)

## Forces

(Bullet list of competing considerations. ≥3 forces; otherwise the decision wasn't really hard.)

- <force 1: e.g., performance>
- <force 2: e.g., maintainability>
- <force 3: e.g., team familiarity>

## Decision

(One paragraph: what we decided.)

## Reasoning

(How the forces were weighed. Reference the disagreement_register.md entries; surface the dissent. ≥3 considered alternatives.)

### Alternative A: <description>
- **Considered because:** <one sentence>
- **Rejected because:** <one sentence with EV-NNN cite>

### Alternative B: ...

### Alternative C (chosen): ...

## Consequences

### Positive

- <expected benefit 1>
- <expected benefit 2>

### Negative

- <accepted cost 1>
- <accepted cost 2>

### Risks

- <risk + mitigation>

## What would change the decision

(Per Brenner ✂ — what observation would invalidate this decision? Specific.)

- <observation 1>
- <observation 2>

## Reversibility

- **Class:** fully | partially | one-way
- **Recovery cost if wrong:** <hours | days | weeks | months>
- **Re-evaluation trigger:** <when to revisit>
- **Re-evaluation mechanism:** <next session, monitoring metric, audit cadence>

## Provenance

- **Workspace:** <path>
- **Question of record:** intake/question_of_record.md
- **Decision memo:** deliverables/DECISION-MEMO.md (if applicable)
- **Evidence packs cited:** [<EV-pack-H-NNN.md, ...>]
- **Disagreement register entries:** D-NNN, D-NNN
- **Pre-registered:** yes/no — link to pre-registration if yes
- **Confidence at decision time:** high | medium | low

## Sign-off

- [ ] Operator: <name> at <ISO>
- [ ] User: <name> at <ISO>
- [ ] External reviewer (if T5): <name> at <ISO>

---

## Update log

(Append new entries when this ADR is updated; preserve history.)

- <ISO>: <update>
- <ISO>: <update>
```

---

## ADR vs Decision Memo

Both exist; they serve different purposes:

| Aspect | Decision Memo | ADR |
|--------|---------------|-----|
| Audience | Stakeholders, decision-makers | Future engineers/researchers |
| Format | Narrative, explanatory | Compact, schema-driven |
| Lifetime | Active during decision-making | Permanent record |
| Update cadence | Mostly one-shot | Updated as decision is revised |
| Length | 1-3 pages | 1-2 pages |
| Status field | implicit (acted on or not) | explicit (proposed/accepted/superseded) |
| Dissent visibility | Surfaced for stakeholders to weigh | Recorded so future revisit can understand original tradeoffs |

A T4+ session typically produces BOTH: a decision memo (Phase 9) for stakeholder review, and an ADR (post-decision) for permanent record. The ADR is *derived from* the decision memo.

---

## ADR lifecycle

### Proposed → Accepted

When the decision memo is signed off, derive the ADR:

```bash
# Number the ADR (next available)
LAST=$(ls deliverables/adr/ 2>/dev/null | grep -oE '^[0-9]+' | sort -n | tail -1)
NEXT=$(printf "%04d" $(( ${LAST:-0} + 1 )))

# Create from template
cp assets/templates/adr-template.md deliverables/adr/${NEXT}-<slug>.md
# Operator fills in
git add deliverables/adr/${NEXT}-<slug>.md
git commit -m "ADR-${NEXT}: <decision>"
```

Status starts `accepted`.

### Accepted → Superseded

When a future session decides differently:

1. Don't edit the original ADR's content (preserve history)
2. Update the original's `Status: superseded by ADR-NNNN`
3. Append to its update log: `<ISO>: superseded by ADR-NNNN; reason: <one-line>`
4. The new ADR's `Context` references the superseded ADR

### Accepted → Deprecated

When the underlying problem no longer applies (e.g., the system was retired):

1. Update `Status: deprecated`
2. Update log: `<ISO>: deprecated because <reason>`

Don't delete; future archaeologists may want the context.

---

## Cross-session ADRs

Some decisions span multiple sessions (e.g., "We use brennerbot for all T4+ research questions" — that's itself an ADR). For those, ADRs live in the skill repo:

- `<skill>/references/adr/<NNNN>-<slug>.md`

These ADRs are governance-level. Updating them requires explicit operator + user decision (NOT just a session's drift-check lesson).

The skill's own existence is itself ADR-001-equivalent: "We adopt the Brenner-method-on-NTM pattern for multi-agent research methodology." That ADR would live at `references/adr/0001-adopt-brennerbot.md` if it were formalized.

---

## ADR index

Maintain `deliverables/adr/INDEX.md` (or `references/adr/INDEX.md` for skill-level ADRs):

```markdown
# ADR Index

| Number | Title | Status | Date | Session | Supersedes |
|--------|-------|--------|------|---------|------------|
| 0001 | <decision> | accepted | <date> | RS-... | — |
| 0002 | <decision> | superseded by 0005 | <date> | RS-... | — |
| 0005 | <decision> | accepted | <date> | RS-... | 0002 |
```

---

## Anti-patterns

| ✗ | Why |
|---|-----|
| Edit ADR content after acceptance | Loses history; future readers can't reconstruct original reasoning |
| Skip "What would change the decision" | Missing falsifier for the ADR itself; can't revisit cleanly |
| Skip reversibility analysis | Decisions get locked in beyond their actual reversibility window |
| ADR without alternatives considered | Looks like fait accompli; readers can't evaluate tradeoffs |
| Single-stakeholder sign-off on T4+ ADR | High-stakes decisions need multiple eyes |
| Combining multiple decisions in one ADR | Each load-bearing decision deserves its own; harder to supersede selectively |
| Status "proposed" forever | An unaccepted ADR is incomplete; decide and commit |

---

## Promotion to brennerbot canonical

When a session-level ADR proves applicable across many sessions of the same archetype, consider promoting:

1. Phase 10 drift-check identifies the recurring decision pattern
2. A meta-ADR is filed at `references/adr/` documenting the pattern as canonical
3. ARCHETYPE-START-PACKS.md or QUESTION-ARCHETYPES.md is updated to default to that decision

Examples of promotable patterns:

- "For A1 design-space sessions, the answer is workload-conditional matrix" (already in ARCHETYPE-START-PACKS.md as A1's distillation form — a kind of latent ADR)
- "For T4+ adversarial audits, run red-team subagent" (latent ADR; could be formalized)

Don't promote prematurely — wait for ≥3 sessions where the same decision was made.
