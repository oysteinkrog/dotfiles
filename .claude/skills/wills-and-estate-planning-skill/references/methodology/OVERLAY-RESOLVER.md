# Overlay Resolver

The skill has a large corpus. That is only useful if the right parts are loaded when
they matter and the wrong parts are not silently skipped. This file is a coverage
discipline, not a robot law.

---

## Default Output

Most substantial planning sessions should generate or update:

- `analyses/plan-coverage-matrix.md`

That file is meant to show:

- which planning mode was selected
- which overlays were triggered
- which references were loaded
- which outputs were required
- which subagents were relevant
- what remains unresolved

---

## Resolver Inputs

Resolve across these axes:

1. **Mode**
   - `new-plan`
   - `existing-plan-audit`
   - `life-event-delta`
   - `urgent-bedside-signing`
   - `executor-activation`
   - `business-owner-succession`
   - `uhnw-restructure`
   - `maintenance-review`

2. **Tier**
   - 1 through 5 per `TIER-TRIAGE.md`

3. **States**
   - domicile
   - real-estate situs states
   - states of major probate / tax concern

4. **Family overlays**
   - blended family
   - minors
   - disability / benefits exposure
   - addiction / creditor / divorce exposure
   - disinheritance
   - non-citizen spouse
   - unconventional family

5. **Asset overlays**
   - retirement
   - life insurance
   - concentrated stock / equity comp
   - private business
   - private funds
   - real estate
   - foreign assets
   - crypto
   - NFA firearms
   - IP / royalties

6. **Profession overlays**
   - use profession references only when compensation, liability, or succession
     mechanics are materially affected

7. **Life-event overlays**
   - only when the event is current or still legally relevant

8. **Risk overlays**
   - execution-risk
   - family-conflict
   - illiquidity
   - litigation
   - cross-border conflict of laws

---

## Resolver Procedure

### Step 1: Pick the primary mode

Load `OPERATING-MODES.md` and record the primary mode.

### Step 2: Compute minimum required references

Normally load these baseline references unless the session is genuinely narrow and answer-only:

- `KERNEL.md`
- `OPERATORS.md`
- `INTERVIEW-FLOW.md` if intake is active
- `VERIFICATION-FIRST.md`

Then add:

- usually one primary tier file
- every triggered state / family / asset / life-event / profession overlay
- any methodology file required by the mode

### Step 3: Compute required outputs

Every required reference should usually imply one or more likely outputs, but do not force artifact production that adds no value to the user's actual session.

Examples:

- `execution-risk` -> `deliverables/signing-readiness-checklist.md`
- `family-conflict` -> `deliverables/conflict-prevention-plan.md`
- `litigation` -> `analyses/litigation-risk-memo.md`
- `business-critical` -> `deliverables/business-continuity-activation.md`
- `cross-border` -> `analyses/foreign-and-conflict-of-laws-review.md`

### Step 4: Compute required subagents

Call out which subagents are worth invoking, not as decoration, but because the surface
is large enough that focused passes reduce omissions. If a human-style integrated pass is better than decomposition, prefer that.

### Step 5: Record negative decisions

For any overlay that might reasonably have applied but was excluded, note why.

Examples:

- "No vulnerable-heir overlay loaded because no beneficiary has benefits, addiction,
  creditor, or incapacity risk."
- "No foreign-assets overlay loaded because assets and heirs are entirely domestic."

---

## Output Template

Use the template in `assets/PLAN-COVERAGE-MATRIX.md`.

Minimum columns:

| Category | Signal | Why it matters | Required references | Required outputs | Required subagents | Status | Notes |
|----------|--------|----------------|---------------------|------------------|--------------------|--------|-------|

Status values:

- `required`
- `loaded`
- `produced`
- `blocked`
- `not-applicable`

---

## High-Value Resolver Rules

1. If a **business** exists, explicitly consider whether
   `business-owner-succession` is a secondary tag.
2. If a **move** occurred or is planned, explicitly consider whether an
   execution-formality reload is required.
3. If there is **unequal treatment**, **estrangement**, or **disinheritance**, strongly
   consider triggering litigation-defense review.
4. If key facts come from memory rather than documents, usually trigger document-quality
   triage and recommendation-confidence scoring.
5. If there is any **foreign asset, foreign heir, or non-citizen spouse**, treat
   cross-border escalation review as the default unless you can explain why it truly
   adds nothing in the specific fact pattern.

---

## Anti-Pattern

Do not say "I considered everything relevant" unless the coverage matrix proves it.
