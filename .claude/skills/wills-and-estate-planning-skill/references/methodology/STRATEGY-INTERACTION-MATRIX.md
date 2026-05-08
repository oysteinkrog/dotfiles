# Strategy Interaction Matrix — How Estate Planning Moves Combine, Conflict, and Chain

Estate-planning strategies do not stand alone. They stack, collide, and often fail when
implemented in the wrong order. This document captures the highest-EV interactions.

---

## Strategy Chains — Execute in Order

### Chain 1: Revocable Trust Planning

1. Design the dispositive plan
2. Draft revocable trust + pour-over will + incapacity documents
3. Confirm successor fiduciaries and backups
4. Re-title assets into the trust or designate the trust where appropriate
5. Update beneficiary forms to match the trust architecture
6. Record the trust-funding status in the implementation ledger

Breakage mode: a revocable trust that never gets funded.

### Chain 2: Blended-Family Protection

1. Confirm goals toward spouse vs first-marriage children
2. Confirm elective-share / homestead / ERISA constraints
3. Decide outright to spouse vs QTIP / credit-shelter / separate shares
4. Coordinate non-probate beneficiaries so they do not bypass the protection design
5. Build the communication and rationale plan

Breakage mode: "everything to spouse" on will but children are supposedly protected only by hope.

### Chain 3: Federal Portability / Credit Shelter / QTIP

1. Quantify current federal and state transfer-tax exposure
2. Determine whether portability alone is sufficient
3. If state estate tax or remarriage risk exists, test credit-shelter / QTIP structures
4. Confirm tax-apportionment clauses and basis consequences
5. Confirm first-death filing obligations and liquidity

Breakage mode: relying on portability without actually filing the return that elects it.

### Chain 4: Lifetime Gifting

1. Verify basis and appreciation profile
2. Verify estate-tax pressure at federal and state level
3. Compare gifting to retaining for step-up
4. If gifting still wins, decide outright vs trust
5. Track reporting, valuation, and future basis records

Breakage mode: giving away low-basis appreciating property in an estate that would never have paid estate tax.

### Chain 5: ILIT / Death-Benefit Liquidity

1. Verify that liquidity is actually needed
2. Verify that estate inclusion is a real problem
3. Compare direct ownership, spouse ownership, revocable-trust ownership, and ILIT
4. If ILIT wins, address Crummey administration and premium flow
5. Record the loss of control and step-up tradeoff

Breakage mode: adding irrevocability for a family whose real need was just better beneficiary coordination.

---

## Strategy Conflicts

### Conflict 1: Outright Distribution vs Vulnerable Beneficiary Protection

| Outright gift | Protective trust |
|---|---|
| Simpler, lower admin burden | Asset protection, creditor / divorce / addiction / SNT benefits |
| Full beneficiary autonomy | Trustee mediation and guardrails |
| Dangerous for fragile heirs | Better for instability and means-tested-benefit sensitivity |

Rule: never optimize for simplicity if it destroys benefits eligibility or predictably funds self-harm.

### Conflict 2: Step-Up Maximization vs Estate Reduction

| Retain asset until death | Gift asset during life |
|---|---|
| Potential basis step-up | Removes future appreciation from taxable estate |
| Better below transfer-tax threshold | Better above threshold or with strong creditor / dynasty goals |

Rule: below the relevant exemption regime, basis often dominates.

### Conflict 3: Revocable Trust vs TOD / POD / Direct Beneficiary Transfers

| Revocable trust | TOD/POD / direct beneficiary |
|---|---|
| Better central coordination | Simpler institution-by-institution transfer |
| Better for incapacity and multi-asset governance | Easier to drift out of coherence |
| Useful for ancillary-probate avoidance across many assets | Can bypass equalization / share logic |

Rule: use direct designations only if they still tell the same story as the rest of the plan.

### Conflict 4: Equal Shares vs Fair Outcomes

| Equal shares | Equitable shares |
|---|---|
| Clean arithmetic | Better reflects caregiving, prior support, special needs, or concentrated risk |
| Can still feel unfair | Requires explanation and stronger process discipline |

Rule: if shares are unequal, explanation quality must rise.

### Conflict 5: Co-Fiduciaries vs Single Fiduciary With Backup

| Co-executors / co-trustees | Single primary + successor |
|---|---|
| Shared responsibility | Faster decision-making |
| More veto power and deadlock risk | Lower administrative friction |

Rule: in a conflicted family, co-fiduciaries are often a bug, not a feature.

---

## Interaction Hotspots

### Portability vs Credit Shelter Trust

- Portability preserves the unused exclusion of the first spouse only if timely elected.
- Credit-shelter trust can protect appreciation and may matter more in state-estate-tax jurisdictions.
- Portability is simpler, but simplicity is not always cheaper.

### QTIP vs Outright To Spouse

- QTIP is not about distrust for its own sake.
- It is about controlling the remainder while qualifying for the marital deduction.
- Particularly high EV in second marriages and mixed-family systems.

### ILIT vs Retained Ownership

- ILIT can exclude proceeds from the taxable estate.
- Retained ownership preserves flexibility and may be perfectly fine below relevant exemption levels.
- The administrative burden is not trivial and should be justified.

### TOD Deed vs Trust Transfer for Real Estate

- TOD deed can avoid probate on a specific parcel where state law supports it.
- Trust transfer is often better when incapacity management, multi-state coordination, or contingent shares matter.
- Confirm lender, HOA, insurance, and state-law mechanics before treating the strategy as implementation-ready.

### Vacation Home Equal Shares vs Governance Wrapper

- Equal shares of a lumpy asset invite deadlock.
- LLC or trust governance with buyout / scheduling / maintenance rules often wins.
- If the family does not actually want shared ownership, plan for sale, not fantasy.

### Special Needs Trust vs Discretionary Family Trust

- General discretionary trust language is often not enough for public-benefits protection.
- If means-tested benefits matter, route to special-needs analysis and specialist counsel.

---

## Questions to Ask Before Using Any Strategy

1. What concrete failure does this strategy prevent?
2. What new failure mode does it introduce?
3. What happens if nobody updates it for five years?
4. Who has to actually administer it after death or incapacity?
5. Does it still work if the family behaves badly?
6. Does it still work if a key fiduciary dies, moves, or becomes estranged?

---

## Output Template

Use this structure in `analyses/decision-ledger.md` when a recommendation depends on a
strategy interaction:

```markdown
## [Decision]

- Goal served:
- Alternative considered:
- Interaction / conflict:
- Why chosen:
- What must be coordinated for it to work:
- What would break it:
- What the attorney must confirm:
```

---

## Operating Rule

Never recommend an estate-planning strategy in isolation.

Say what it must be coordinated with, what it displaces, and what it can break.
