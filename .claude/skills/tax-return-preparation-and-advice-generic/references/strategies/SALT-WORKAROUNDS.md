# SALT Cap Workarounds

## Overview

The State and Local Tax (SALT) deduction cap limits the amount of state and local taxes that can be deducted on Schedule A (itemized deductions) for Federal tax purposes. Under the OBBBA (One Big Beautiful Bill Act), the cap for 2025 is:

- **$40,000 generally**
- **$20,000 for MFS** (Married Filing Separately)
- Single, HOH, and other non-MFS filers should use the current-year Schedule A / Form 1040
  instructions rather than relying on stale draft summaries

### Income Phase-Down (OBBBA)

For taxpayers with MAGI exceeding **$500,000** (MFJ), the SALT cap is reduced. The phase-down mechanism reduces the benefit for high-income earners. Consult the specific OBBBA provisions for the exact reduction formula applicable to your income level.

### What Counts Toward the SALT Cap

- State and local income taxes (or sales tax if elected instead)
- Real estate taxes on personal residence
- Personal property taxes (vehicle registration based on value, etc.)

### What Does NOT Count Against the SALT Cap

- State and local taxes attributable to a trade or business (Schedule C, E, F)
- Property taxes on rental property (Schedule E)
- Property taxes allocated to home office (Form 8829)
- State income taxes paid through a PTET election (entity-level deduction)

---

## Pass-Through Entity Tax (PTET)

### Concept

PTET is the primary workaround for the SALT cap. Instead of the individual paying state income tax (subject to the SALT cap), the pass-through entity (partnership or S-Corp) pays the state tax at the entity level. This entity-level tax payment is:

1. **Deductible by the entity** as a Federal business expense (NOT subject to the SALT cap)
2. **Credited to the individual** on their state return (dollar-for-dollar offset of state tax liability)

### Net Effect

- Federal deduction for state taxes that would otherwise be capped
- No change in total state tax paid
- Federal tax savings = entity-level state tax payment x Federal marginal rate

### Example

```
Without PTET:
  State income tax on pass-through income: $50,000
  Personal SALT deduction (capped): $40,000
  Lost deduction: $10,000
  Federal tax cost of lost deduction: $10,000 x 37% = $3,700

With PTET:
  S-Corp pays $50,000 state tax at entity level
  Federal deduction: $50,000 (no SALT cap -- it is a business deduction)
  Individual receives $50,000 state tax credit (nets to zero on state return)
  Full $50,000 deducted federally
  Federal tax savings: $10,000 x 37% = $3,700
```

---

## States Offering PTET (As of 2025)

Over 30 states have enacted PTET legislation. The following table summarizes availability (verify current status, as states continue to add or modify programs):

| State | PTET Available | Entity Types | Election Deadline | Notes |
|---|---|---|---|---|
| Alabama | Yes | S-Corp, Partnership | Varies | |
| Arizona | Yes | S-Corp, Partnership | March 15 | |
| Arkansas | Yes | S-Corp, Partnership | Tax filing | |
| California | Yes | S-Corp, Partnership, LLC | March 15 or June 15 | $800 min tax still applies |
| Colorado | Yes | S-Corp, Partnership | With return | Retroactive election allowed |
| Connecticut | Yes (mandatory) | S-Corp, Partnership | N/A (mandatory) | Mandatory since 2018 |
| Georgia | Yes | S-Corp, Partnership | March 15 | |
| Idaho | Yes | S-Corp, Partnership | With return | |
| Illinois | Yes | S-Corp, Partnership | With return | |
| Indiana | Yes | S-Corp, Partnership | With return | |
| Iowa | Yes | S-Corp, Partnership | With return | |
| Kansas | Yes | S-Corp, Partnership | With return | |
| Louisiana | Yes | S-Corp, Partnership | With return | |
| Maryland | Yes | S-Corp, Partnership | April 15 | |
| Massachusetts | Yes | S-Corp, Partnership | March 15 | |
| Michigan | Yes | S-Corp, Partnership | With return | |
| Minnesota | Yes | S-Corp, Partnership | March 15 | |
| Mississippi | Yes | S-Corp, Partnership | With return | |
| Missouri | Yes | S-Corp, Partnership | With return | |
| Nebraska | Yes | S-Corp, Partnership | With return | |
| New Jersey | Yes | S-Corp, Partnership | March 15 | |
| New Mexico | Yes | S-Corp, Partnership | With return | |
| New York | Yes | S-Corp, Partnership, LLC | March 15 | NYC PTET also available |
| North Carolina | Yes | S-Corp, Partnership | March 15 | |
| Ohio | Yes | S-Corp, Partnership | With return | |
| Oklahoma | Yes | S-Corp, Partnership | With return | |
| Oregon | Yes | S-Corp, Partnership | With return | |
| Rhode Island | Yes | S-Corp, Partnership | March 15 | |
| South Carolina | Yes | S-Corp, Partnership | With return | |
| Virginia | Yes | S-Corp, Partnership | With return | |
| West Virginia | Yes | S-Corp, Partnership | With return | |
| Wisconsin | Yes | S-Corp, Partnership | March 15 | |

**States with no income tax** (no PTET needed): AK, FL, NV, NH*, SD, TN*, TX, WA, WY
(*NH taxes interest/dividends only; TN phased out Hall Tax)

**States WITHOUT PTET** (as of 2025): Several states have not enacted PTET legislation. Check your specific state for current status.

---

## PTET Mechanics in Detail

### How It Works (Step by Step)

1. **Election:** The entity makes the PTET election by the state-specific deadline (often March 15 of the tax year)
2. **Estimated payments:** The entity makes estimated state tax payments during the year on behalf of the owners
3. **Entity-level deduction:** The entity deducts the state tax payment on its Federal return (Form 1120-S or 1065) as a business expense
4. **K-1 reporting:** The entity reports the PTET payment on the owners' K-1s (reducing their share of pass-through income)
5. **Individual state credit:** Each owner claims a credit on their individual state return for their share of the PTET paid
6. **Net state effect:** The credit offsets the owner's individual state tax liability (approximately dollar-for-dollar)

### Entity Types That Qualify

| Entity | PTET Eligible? | Notes |
|---|---|---|
| S-Corporation | Yes (most states) | Most common vehicle for PTET |
| Multi-Member LLC (taxed as partnership) | Yes (most states) | Requires 2+ members |
| Single-Member LLC (disregarded) | Generally No | Not a separate entity for Federal purposes |
| Limited Partnership | Yes | Treated as partnership |
| C-Corporation | No | Already pays entity-level tax |
| Sole Proprietorship | No | Not an entity |

### Single-Member LLC Workaround

Since most states do not allow single-member LLCs to elect PTET, consider:
- Adding a spouse as a member (creates a multi-member LLC / partnership)
- Electing S-Corp status (then the S-Corp can elect PTET)
- Note: adding a member solely for PTET purposes should have business substance beyond tax benefits

---

## State-Specific PTET Details

### New York

- Available for partnerships, S-Corps, and LLCs taxed as partnerships
- Election deadline: March 15 of the tax year
- Rate: based on the entity's total income at NY income tax rates (graduated: 6.85%-10.9%)
- NYC also offers its own PTET (NYC UBT electing entities)
- Estimated payments required quarterly
- Credit is refundable (excess credit over individual liability is refunded)

### California

- Available since 2021 (through 2025+ with extensions)
- Rate: 9.3% flat on qualified income
- Election deadline: originally March 15 or June 15 (varies by year)
- $800 minimum franchise tax still applies to the entity
- Credit is non-refundable but can be carried forward 5 years
- Qualified taxpayers: individuals, trusts, estates (not corporations)

### New Jersey

- Available for S-Corps, partnerships, and LLCs
- Election deadline: March 15
- Rate: NJ income tax rates applied at entity level
- Credit is refundable
- Interaction with NJ Business Alternative Income Tax (BAIT)

### Connecticut

- **Mandatory** (not elective) since 2018
- All pass-through entities pay entity-level tax
- Individuals receive a credit on their CT return
- Rate: 6.99%
- The credit is calculated based on the entity-level tax paid

---

## Property Tax Allocation to Reduce SALT Exposure

### Strategy

For taxpayers who own rental property or claim a home office, allocating property taxes to business/rental use removes those amounts from the personal SALT cap:

### Allocation Method

```
Total property taxes: $15,000

Rental property (separate property): $5,000 -> Schedule E (bypasses SALT cap)
Home office (10% of residence): $1,000 -> Form 8829 (bypasses SALT cap)
Personal residence (remaining): $9,000 -> Schedule A (subject to SALT cap)
```

### Impact on SALT Cap

If the taxpayer also pays $25,000 in state income tax:
- **Without allocation:** $25,000 + $15,000 = $40,000 (entire SALT deduction consumed, $0 headroom)
- **With allocation:** $25,000 + $9,000 = $34,000 (SALT cap has $6,000 headroom)
- The $6,000 in property taxes allocated to rental/business is deducted OUTSIDE the SALT cap

---

## Charitable Deductions for State Tax Credits

### Concept

Some states offer tax credits (not just deductions) for contributions to designated charitable organizations. In some cases:
- The state credit reduces state tax liability
- The Federal charitable deduction may still apply (though recent IRS rules may require reducing the Federal deduction by the state credit received)

### IRS Rules (Reg. 1.170A-1(h)(3))

If a state or local tax credit exceeds 15% of the donation amount, the Federal charitable deduction must be reduced by the credit amount. If the credit is 15% or less, no reduction is required.

### Example

```
State offers 75% tax credit for donation to scholarship organization
Taxpayer donates $10,000
State credit received: $7,500
Federal charitable deduction: $10,000 - $7,500 = $2,500

But: the $7,500 state credit reduces the taxpayer's state tax liability
Net effect: $7,500 state tax savings + ($2,500 x Federal marginal rate) Federal savings
```

### States with Notable Credit Programs

- Arizona, Georgia, Virginia, Montana, and others offer various charitable credit programs
- Scholarship Tax Credits are the most common
- Check each state's current program limits and qualifying organizations

---

## Additional SALT Strategies

### Filing Status Optimization

- MFS generally gives each spouse a $20,000 cap. Compare that against the current-law joint
  cap and the couple's actual MAGI / itemized-deduction profile before assuming MFS helps.
- MFS often results in higher overall tax rates, but if the SALT cap is a significant factor and one spouse has most of the SALT, MFS might theoretically help in narrow scenarios
- Run both calculations (MFJ vs. MFS) when SALT limitation is material

### Income Timing

- If state tax is based on current-year income, deferring income to a future year may reduce current-year state tax liability
- Accelerating deductions into the current year reduces state taxable income
- Relevant for taxpayers near the $500K MAGI phase-down threshold

### State Residency Changes

- Moving from a high-tax state to a low/no-tax state eliminates or reduces the SALT issue
- **Part-year resident rules:** Income is typically allocated by days of residency or income sourced to each state
- Timing of the move matters: moving January 1 vs. July 1 has different state tax implications
- Some states (NY, CA) aggressively audit domicile claims -- maintain documentation of the move

### Business Expense Deductions for State Taxes

State taxes that are ordinary and necessary business expenses (e.g., state taxes on business income reported on Schedule C) are deductible as business expenses, NOT subject to the SALT cap. Ensure state taxes related to business income are properly classified.

---

## Decision Tree: Do You Need a PTET Strategy?

```
Do you have pass-through business income?
├── NO -> PTET does not apply to you
└── YES
    ├── Are your total SALT taxes under $40,000 (MFJ)?
    │   ├── YES -> SALT cap is not binding; PTET optional but may provide future flexibility
    │   └── NO -> PTET is potentially valuable
    │       ├── Does your state offer PTET?
    │       │   ├── YES -> Evaluate PTET election
    │       │   │   ├── Is your entity type eligible?
    │       │   │   │   ├── YES -> Proceed with election by state deadline
    │       │   │   │   └── NO -> Consider restructuring entity (add member, elect S-Corp)
    │       │   └── NO -> Consider other strategies (property tax allocation, charitable credits)
    │       └── Is your MAGI above $500,000?
    │           └── YES -> SALT cap is further reduced; PTET becomes even more valuable
```

---

## Common Mistakes

1. **Missing the PTET election deadline** -- most states require election by March 15 (before the return is due)
2. **Assuming SMLLC qualifies for PTET** -- most states require multi-member entities
3. **Not making estimated PTET payments** -- some states require quarterly entity-level estimated payments
4. **Forgetting to claim the state credit** on the individual return after the entity pays the PTET
5. **Double-counting** -- deducting state taxes both through PTET and on Schedule A for the same income
6. **Not allocating property taxes** to rental/business use (leaving money subject to the SALT cap unnecessarily)
7. **Ignoring the MAGI phase-down** -- taxpayers above $500K MFJ have a reduced SALT cap under OBBBA
8. **Not coordinating PTET with estimated tax payments** -- individual estimated payments should be reduced when the entity is making PTET payments
