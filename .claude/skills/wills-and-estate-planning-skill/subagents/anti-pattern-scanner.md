# Subagent: Anti-Pattern Scanner

Scans the user's current plan (or in-progress plan) against the comprehensive anti-patterns catalog and flags risks with severity and remediation.

## Purpose

Anti-patterns are recurring failure modes in estate planning. Scanning against them catches problems before they become expensive mistakes at death.

## Inputs

- Current estate plan summary / documents
- Completed intake
- Beneficiary designations (if audited)
- Trust funding status (if applicable)
- State of residence + any prior-state ties

## Scan Categories

Reference [ANTI-PATTERNS.md](../references/anti-patterns/ANTI-PATTERNS.md) for the full 81-item catalog. Scan these domains:

### Foundations (Axiom Violations)
- [ ] Will-only planning ignoring beneficiary designations
- [ ] Beneficiary forms contradicting will/trust
- [ ] Incapacity ignored
- [ ] Domicile unaddressed
- [ ] Portability assumed but 706 never filed

### Family Structure
- [ ] Blended family — new spouse gets everything; bio kids nothing
- [ ] Non-citizen spouse handled without QDOT / treaty / portability analysis
- [ ] Minor children with UTMA release at 18
- [ ] Disabled heir named directly without a special-needs / benefits-preservation analysis
- [ ] Heir with addiction, predation, or severe money-management risk slated for outright distribution without discretionary-structure review
- [ ] Unmarried partner no provision
- [ ] Single-with-elderly-parents scenario ignored

### Assets
- [ ] Home placed in revocable trust for Medicaid planning without confirming whether the structure actually helps or instead leaves the asset countable / exposed under the governing state's rules
- [ ] Out-of-state property ancillary probate
- [ ] Firearms with no NFA trust or inheritance plan
- [ ] Crypto seed phrase inaccessible
- [ ] Foreign assets unreported (FBAR, 8938)
- [ ] Concentrated employer stock undiversified
- [ ] Business without buy-sell
- [ ] Intellectual property no succession plan

### Advanced Planning
- [ ] SLATs as reciprocal trusts
- [ ] ILIT with Crummey notices missed
- [ ] GRAT funded with wrong asset
- [ ] Gift to heirs loses step-up
- [ ] 3-year lookback on life insurance
- [ ] State gift tax (CT) ignored
- [ ] Grantor trust status accidentally lost

### Incapacity
- [ ] Springing POA that won't trigger
- [ ] Healthcare POA not updated after divorce
- [ ] POLST / MOLST / COLST-style orders not reviewed for a seriously ill patient when current medical status makes bedside orders important
- [ ] Medicaid 5-year lookback violated
- [ ] Dementia directive missing
- [ ] LTC insurance lapsed or inadequate

### Execution / Administration
- [ ] Trust not funded
- [ ] Document locations unknown to executor
- [ ] Digital accounts inaccessible
- [ ] No letter of instruction
- [ ] Executor not informed of nomination

### Communication
- [ ] Disinheritance undisclosed
- [ ] Guardian not informed
- [ ] Unequal shares without explanation
- [ ] Family meeting never held

## Output Format

```markdown
# Anti-Pattern Scan — [User Name]

## Summary
- Total checks: [N]
- Critical risks: [N]
- Important risks: [N]
- Optimization opportunities: [N]
- Clean: [N]

## CRITICAL RISKS (Fix Immediately)

### 1. [Pattern Name]
- **Evidence:** [What was observed]
- **Why it matters:** [Impact if unfixed]
- **Risk level:** CRITICAL / IMPORTANT / OPTIMIZATION
- **Cost if unfixed:** [Estimated dollar cost or family impact]
- **Fix:** [Specific actions]
- **Timeline:** [Immediate / within 30 days / etc.]
- **Professional needed:** [Attorney / CPA / etc.]

## IMPORTANT RISKS (Fix Within 30 Days)

### [Pattern Name]
[Same format]

## OPTIMIZATION OPPORTUNITIES

### [Pattern Name]
[Same format]

## CLEAN (No Issues Found)

- [Pattern Name] — verified
- [Pattern Name] — verified

## Prioritized Action Plan

1. **Critical Fix 1** — [description, deadline, owner]
2. **Critical Fix 2** — [description, deadline, owner]
3. **Important Fix 1** — [description, deadline, owner]
...

## Team to Engage

- [x] Estate planning attorney — for [issue A, B]
- [x] CPA — for [issue C]
- [x] Financial advisor — for [issue D]
```

## Severity Definitions

### CRITICAL
- Will cause plan to fail its primary purpose
- Active money loss (wrong beneficiary, missing forms)
- Incapacitation or death would cause family crisis
- Federal / state law violation
- Regulatory penalty

### IMPORTANT
- Suboptimal outcome but not catastrophic
- Tax opportunity missed
- Family tension likely
- Administrative friction

### OPTIMIZATION
- Could be improved but current plan works
- Advanced planning opportunity
- Better tax positioning
- Smoother administration

## Scan Heuristics

1. **Follow the money:** check every flow of assets from decedent to beneficiaries. Does each path work?
2. **Incapacity journey:** simulate a dementia decline. Where does the plan break?
3. **Alternate futures:** simulate divorce, remarriage, beneficiary death. What breaks?
4. **Coherence:** does every document tell the same story?
5. **Funding:** are trusts actually funded, not just drafted?
6. **Communication:** does everyone who needs to know, know?

## Cross-Reference

- Catalog: [ANTI-PATTERNS.md](../references/anti-patterns/ANTI-PATTERNS.md)
- Validation aid: [plan-validator.py](../scripts/plan-validator.py)
