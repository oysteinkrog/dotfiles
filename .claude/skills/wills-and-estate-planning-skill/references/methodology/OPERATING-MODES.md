# Operating Modes

This skill should not behave as though every user wants the same full greenfield
estate-plan build. Select a primary mode first, then route overlays, outputs, and
subagents around that mode.

---

## Core Rule

Early in each session, record:

- one **primary mode**
- any **secondary tags** that modify the work
- what "done" means for this mode

Record the result in `analyses/plan-coverage-matrix.md`.

---

## Primary Modes

### 1. `new-plan`

Use when the user is building a plan from scratch or from a very weak baseline.

- First move: intake + document inventory
- Main goal: design the full structure and handoff packet
- Normally finishes with: the analyses and deliverables needed for a coherent design and attorney handoff. If the user only wants a first-pass architecture review, record what is deferred.

### 2. `existing-plan-audit`

Use when the user already has wills, trusts, POAs, beneficiary forms, or a prior
attorney-built package and wants to know whether it still works.

- First move: current-document audit + prior-plan gap analysis
- Main goal: identify stale, contradictory, or dangerous elements before redrafting
- Normally finishes with: `analyses/prior-plan-gap-analysis.md`, `analyses/coherence-audit.md`,
  `analyses/red-flag-triage.md`, and `analyses/litigation-risk-memo.md`

### 3. `life-event-delta`

Use when the user does not need full replanning yet, but a life event may have broken
the prior plan.

Common triggers:

- marriage
- divorce
- birth / adoption
- death in the family
- interstate move
- business launch or sale
- retirement
- major inheritance

- First move: identify what changed and what old assumptions are now false
- Main goal: targeted repair, not blind full redraft
- Normally finishes with: delta action list, updated beneficiary map, and updated implementation ledger

### 4. `urgent-bedside-signing`

Use when capacity is at risk, illness is advancing, travel is impossible, or the user
needs an execution-safe emergency package quickly.

- First move: identify what absolutely must be signed now vs deferred
- Main goal: execution-risk reduction under time pressure
- Normally finishes with: `deliverables/signing-readiness-checklist.md`,
  `analyses/litigation-risk-memo.md`, state-law verification items, and attorney escalation

### 5. `executor-activation`

Use when the decedent has died or the user is acting in a live post-death role.

- First move: triage deadlines, control the first week, secure property and records
- Main goal: execution of the existing plan, not redesign of the estate
- Normally finishes with: updated `deliverables/executor-checklist.md`,
  deadline sections inside that checklist, updated `deliverables/institution-contact-matrix.md`,
  and tax / probate / creditor routing captured in the checklist or implementation ledger

### 6. `business-owner-succession`

Use when an owner-operated company, professional practice, or family enterprise is
material to the estate.

- First move: identify Monday-morning operational risk
- Main goal: prevent value collapse during death or incapacity
- Normally finishes with: `deliverables/business-continuity-activation.md`,
  updates to `deliverables/implementation-ledger.md`, and a signatory / payroll
  continuity plan inside the business-continuity file

### 7. `uhnw-restructure`

Use when the estate is near or above federal transfer-tax exposure, or when the user
has multi-entity / multi-jurisdiction wealth requiring restructuring rather than basic
documents.

- First move: quantify tax, basis, liquidity, and control tradeoffs
- Main goal: redesign ownership and transfer architecture
- Normally finishes with: transfer-tax strategy, implementation queue, counsel questions,
  recommendation confidence register

### 8. `maintenance-review`

Use for annual reviews, post-signing upkeep, beneficiary sweeps, trust-funding follow-up,
or periodic "does this still work?" checks.

- First move: review what changed since last version
- Main goal: stop plan drift before it becomes a failure
- Normally finishes with: updated review schedule, implementation status, and refreshed source log

---

## Secondary Tags

These do not replace a primary mode. They modify it.

- `blended-family`
- `vulnerable-heir`
- `non-citizen-spouse`
- `cross-border`
- `execution-risk`
- `family-conflict`
- `business-critical`
- `crypto-heavy`
- `illiquid-estate`
- `state-estate-tax`

---

## Selection Heuristics

Choose the primary mode by asking:

1. Is this mainly about **creating**, **auditing**, **repairing**, **executing**, or
   **maintaining** a plan?
2. Is there a time-critical execution problem?
3. Is there a live death / incapacity / business continuity event?
4. Is the dominant risk legal design, institutional cleanup, litigation, or operations?

If two modes seem plausible:

- choose the one that determines the definition of "done"
- record the other as a secondary tag or follow-on phase

---

## Done Definition By Mode

| Mode | Minimum done condition |
|------|------------------------|
| `new-plan` | coherent plan + implementation queue + attorney handoff |
| `existing-plan-audit` | old plan weaknesses surfaced and prioritized |
| `life-event-delta` | all broken assumptions from the event mapped to repairs |
| `urgent-bedside-signing` | emergency docs, execution logistics, and litigation safeguards routed |
| `executor-activation` | first 7 / 30 / 270 day control plan established |
| `business-owner-succession` | key business continuity risks addressed |
| `uhnw-restructure` | structure options compared with verified tax / control tradeoffs |
| `maintenance-review` | drift fixed and next review clock reset |

---

## Anti-Pattern

Do not run a full exhaustive greenfield workflow by reflex when the user actually needs
one of these:

- a fast audit of an existing plan
- a targeted life-event repair
- a bedside-signing emergency
- a live executor playbook
- a business continuity intervention
