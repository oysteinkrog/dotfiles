# Healthcare Power of Attorney, Living Will, HIPAA, Dementia Directives

These four documents work together to govern medical decisions when you can't speak for yourself. For most adults, some version of all four should at least be considered, but the exact package and formality requirements are state-specific.

## Document 1: Healthcare Power of Attorney (Healthcare Proxy)

Names a person ("healthcare agent" or "proxy") to make medical decisions when you can't.

### Key Decisions

- **Who is your agent?** Pick someone who:
  - Knows you well
  - Can make decisions under stress
  - Lives close enough to be present (or available by phone urgently)
  - Will follow your wishes, not their own preferences
  - Is comfortable saying no to other family members
- **Successor agents** — multiple backups
- **Specific authorities granted** — typically broad: any medical decision a competent patient could make
- **Special instructions** — religious requirements, specific treatment preferences

### Common Mistakes

- Naming spouse as agent without backup (what if you're in a car crash together?)
- Naming aging parent who may not be capable when needed
- Naming distant relative who can't be present
- Naming someone with conflicting religious or values orientation
- Not telling the agent

## Document 2: Living Will (Advance Directive)

Written statement of your treatment preferences if you're terminally ill or permanently unconscious.

### Standard Scenarios to Address

For each, specify your preference:

#### Terminal illness with no chance of recovery
- Mechanical ventilation? (yes / no / time-limited trial)
- Artificial nutrition and hydration?
- CPR / resuscitation?
- Dialysis?
- Antibiotics for new infection?
- Hospice care preferred?

#### Permanent unconsciousness (persistent vegetative state)
- Same questions, often answered the same way

#### Severe dementia, physically healthy (NEW — increasingly important)
- Aggressive treatment for new conditions?
- Antibiotics for pneumonia?
- Hand-feeding when unable to recognize family?
- Transfer to memory care vs. home care?
- Participation in research studies?

### Five Wishes and Similar Broader Documents

Beyond pure medical preferences, address:
- Pain management priorities
- Comfort and dignity wishes
- Spiritual support
- Specific people you want present
- Specific people you don't want present

### POLST/MOLST Distinction

- Living will = your future wishes (when terminally ill or PVS)
- POLST/MOLST = actual medical orders (signed by physician for current illness)
- Use POLST/MOLST when current illness or frailty makes bedside medical orders appropriate; many programs use the "< 1 year" heuristic, but treat it as a clinical prompt rather than a universal legal threshold. See POLST-MOLST.md.

## Document 3: HIPAA Authorization

Lets named people access your medical records. Without it, even your spouse may be locked out under federal privacy law.

### Who to List

- Healthcare agent (proxy)
- Spouse (separately, in case healthcare agent isn't spouse)
- Adult children
- Trusted friend who might need to coordinate care
- Attorney
- Hospital case manager (if applicable)

### Coverage

- Medical records and test results
- Mental health records (separate authorization often required)
- Substance abuse treatment records (separate authorization required under 42 CFR Part 2)
- Communications with healthcare providers

### Hospital Visitation Authorization

Separately from HIPAA, hospitals may restrict visitation. Authorization for unmarried partner, friend, or chosen family is critical particularly for LGBTQ+ individuals and unmarried couples.

## Document 4: Dementia-Specific Directive (NEW BUT IMPORTANT)

Dementia presents scenarios that traditional living wills don't address well: physically healthy patient with severe cognitive decline.

### Issues to Address

- **Stopping artificial nutrition and hydration** when unable to recognize family or self
- **Hand-feeding** during late-stage dementia (some states allow refusing; others require provision)
- **Aggressive treatment of new conditions** vs. comfort care only
- **Antibiotics for routine infections** vs. accepting infection as natural course
- **Transfer between home, nursing home, hospital**
- **Participation in research studies**
- **Specific quality-of-life thresholds** that should trigger comfort-only care

### Resources

- Dementia Care Foundation
- Compassion & Choices Dementia Provision
- "Final Acts" by Dr. Stephen Kiernan
- "Being Mortal" by Atul Gawande

### Legal Status

Varies by state. Some states have specific dementia directive forms; others require careful drafting within general advance directive framework.

## Coordination Across All Four Documents

```
HIPAA Authorization
   ↓ (gives access to medical info)
Healthcare Agent (under Healthcare POA)
   ↓ (makes decisions based on info)
Living Will (provides standing instructions for terminal/PVS)
Dementia Directive (provides standing instructions for cognitive decline)
```

## Where to Store

- **Original**: in a quickly accessible location known to your healthcare agent
- **Copy**: with your primary care physician (in your medical record)
- **Copy**: with your attorney
- **Copy**: in your "If I die tomorrow" file
- **Copy**: at your local hospital if you have a chronic condition
- **Wallet card**: pointing to where the documents are
- **Digital**: hospital systems increasingly accept digital uploads (MyChart, etc.)

**Bad primary location:** a safe deposit box. The documents need to be quickly accessible during a hospital or EMS crisis.

## Common Failure Modes

1. **Healthcare POA not signed** — defaults govern (state statutory hierarchy)
2. **Living will signed but never shared with agent** — agent doesn't know your wishes
3. **No HIPAA authorization** — agent can't access records
4. **Healthcare POA in safe deposit box** — inaccessible at hospital
5. **Stale documents** (>10 years old) — providers may question validity
6. **Dementia not addressed** — long, slow decline with conflicting family preferences
7. **Religious requirements not specified** — providers may not know
8. **Hospital visitation not authorized** for unmarried partner — locked out
9. **Healthcare agent in different state** — communication delays during crisis
10. **Multiple agents listed jointly** — disagreement, paralysis

## State-Specific Notes

- **Five Wishes** is widely used, but do not assume it is sufficient in a specific state without checking local execution and acceptance rules
- **POLST/MOLST** programs vary by state (often called eMOLST in NY)
- **Massachusetts**: healthcare-proxy, MOLST, and related form practice are state-specific; verify the current form and bedside-use rules
- **California**: detailed AHCD form with specific provisions
- **Florida**: separate forms for healthcare surrogate vs. living will

## When to Activate

Healthcare-agent authority typically activates when the patient is unable to make or communicate informed decisions under the governing state-law standard, often determined in practice by treating clinicians at the bedside. That trigger is not always identical to a financial POA's incapacity standard.

## Cross-Reference

- Foundation: [CORE-DOCUMENTS.md](../foundations/CORE-DOCUMENTS.md)
- Related: [DURABLE-POA.md](DURABLE-POA.md), [POLST-MOLST.md](POLST-MOLST.md), [MENTAL-HEALTH-DIRECTIVES.md](MENTAL-HEALTH-DIRECTIVES.md)
- Operators: ⧒ Incapacity-Transition
- Templates: [DISPOSITION-OF-REMAINS.md](../../assets/DISPOSITION-OF-REMAINS.md)
- Anti-patterns: [ANTI-PATTERNS.md](../anti-patterns/ANTI-PATTERNS.md)
