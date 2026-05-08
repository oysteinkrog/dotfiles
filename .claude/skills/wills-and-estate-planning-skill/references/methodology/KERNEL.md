# The Estate-Planning Kernel (Full Text)

The 12 axioms in SKILL.md are the canonical kernel. This file adds the **reasoning, citations to the guide, and worked-example failure modes** for each — for when you need to explain WHY the axiom exists, or to decide whether an edge case is actually an exception.

<!-- KERNEL_EXPANSION_START v1.0 -->

## Axiom 0 — The will does not control the whole estate

**Why it exists:** Retirement accounts, life insurance, annuities, TOD/POD accounts, joint tenancy / tenancy by the entirety / community property with right of survivorship, trust-owned property, and assets subject to buy-sell agreements **pass by contract or title, not by will**. For workplace plans actually governed by the relevant ERISA rules, an outdated beneficiary form can survive the state-law cleanup people expected.

**Failure mode (seen in practice):**

- Decedent's will: "everything equally to my three children."
- 401(k) beneficiary form: still names ex-spouse from 1998.
- House titled: joint tenancy with sister.
- Life insurance: names "my estate" — forces probate; retirement income tax accelerates.

Net result: children receive far less than the will suggested, the outdated 401(k) form can still route the account to the ex-spouse, sister gets the house, and the life-insurance proceeds land in the probate-estate workflow instead of moving cleanly outside it.

**Operational implication:** Every plan starts with an asset inventory and a beneficiary-and-titling audit (the **⧉ Beneficiary-Title Coherence** operator). No draft clause is reviewed until that map exists.

---

## Axiom 1 — One coherent story must be told by every document

**Why it exists:** The will, revocable trust, ERISA forms, deeds, POAs, healthcare directives, letter of instruction, and digital inventory must point at the same people, same shares, same contingencies, same jurisdiction. Silos produce the deepest failures.

**Failure mode:**

- Will names daughter Anna as executor.
- Revocable trust names son Ben as successor trustee.
- Healthcare proxy names ex-spouse (never updated).
- Letter of instruction gives funeral wishes that contradict the disposition-of-remains document.

Without coherence audit, the family spends the first three weeks after death fighting over "what did Dad actually want?"

**Operational implication:** After every design change, re-run the coherence audit. The Comprehensive Plan Report is a single document that documents every named agent and contingency across every document.

---

## Axiom 2 — Plan for incapacity first, death second

**Why it exists:** Serious incapacity (dementia, stroke, coma, severe mental illness, late-stage cancer, traumatic injury) is common and can last months to decades. Without planning:

- A court appoints a conservator — often a stranger and usually expensive
- Contested guardianship proceedings drag on for years
- Medical decisions default to a statutory priority order
- Bills go unpaid, homes go unmanaged, investments drift
- Caregiving costs dwarf any tax savings the plan might have produced

**Failure mode:**

- Patient with early-stage dementia enters assisted living. Family tries to use the patient's financial accounts to pay for care. No POA was ever signed. Bank refuses. Family files for conservatorship — 6 months, $30,000 in legal fees, court monitors bank activity, elderly mother loses privacy and agency.

**Operational implication:** For most adults, the incapacity package (durable financial POA + healthcare POA + living will + HIPAA authorization + revocable trust with successor trustee) should be treated as the default foundation, not as a luxury add-on for the wealthy.

---

## Axiom 3 — Beneficiary designations override wills and trusts

**Why it exists:** State law sometimes provides automatic revocation of ex-spouse designations, **but ERISA often preempts that result for qualified retirement plans**. Many state revocation statutes also have exceptions, timing problems, or asset-class carveouts. In practical terms, the plan administrator usually follows the beneficiary designation on file unless a federal overlay such as spousal-consent rules or a QDRO-type exception changes the path.

**Failure mode:**

- 2014: Divorce finalized. Decree requires both parties to update beneficiary forms.
- 2014–2025: Neither does.
- 2025: Decedent dies. 401(k) worth $850K can still pay to the ex-spouse because the old plan form was never affirmatively fixed and the expected state-law cleanup does not rescue the family under the actual plan rules.

**Operational implication:** Beneficiary forms are **personal actions**, not document actions. The plan must explicitly list every beneficiary form and verify the named parties.

---

## Axiom 4 — Fair process matters more than fair outcome

**Why it exists:** Research on family estate disputes consistently shows that heirs accept unequal inheritances when the reasoning is explained. They contest equal inheritances when they feel ambushed. The **surprise at the reading of the will** is one of the fastest accelerants of litigation.

**Failure mode:**

- Parent leaves $2M estate. Three children. The two high-earning children each get $500K; the teacher who cared for Mom gets $1M. Equal in hours contributed, unequal in dollars.
- No explanation given during life.
- High-earning children assume caregiver child manipulated the parent. Sue. Three years of litigation consumes $400K from the estate.

**Versus:**

- Same estate, same shares. Parent held a family meeting 5 years earlier, explained reasoning, named the caregiver role aloud. Left a letter of explanation. No litigation.

**Operational implication:** The Family Meeting Agenda and Letter of Wishes are not optional "nice-to-haves." They are load-bearing components of the plan.

---

## Axiom 5 — Under the 2026 $15M exemption, basis often dominates tax

**Why it exists:** With the federal basic exclusion at $15M per person, and a roughly doubled married-couple shelter only when both spouses' exclusion amounts are actually preserved, **most American estates owe no federal estate tax**. For those estates, the biggest tax lever is the **step-up in basis at death** — unrealized gains vanish for income tax purposes.

**The tradeoff:**

- Lifetime gift of appreciated asset → recipient inherits donor's basis → capital gains tax when sold
- Asset held until death → stepped-up basis → capital gain erased

**Failure mode:**

- $3M estate. Father gifts $1M in appreciated stock (basis $100K) to adult son during life.
- No estate tax would have been owed either way (under $15M exemption).
- Son sells stock: pays 23.8% federal + state capital gains tax on $900K of gain = $250K+ of tax.

Had Father held the stock until death, son inherits with stepped-up basis, sells immediately, $0 capital gain.

**When it reverses:** For estates **above** the federal or state exemption, removing appreciation from the estate at a 40% transfer-tax rate can beat paying capital gains at ~24%. **GRATs, IDGT sales, and SLATs dominate in that regime.**

**Operational implication:** The Tier Triage (see [TIER-TRIAGE.md](TIER-TRIAGE.md)) routes on this axiom. Tier 1–2 plans prioritize step-up. Tier 4–5 plans prioritize appreciation-removal.

---

## Axiom 6 — State law controls more than federal law for most families

**Why it exists:** Federal estate tax applies only above $15M. **State estate tax and state inheritance tax apply at much lower thresholds. Rough 2026-style reference points include:**

- Oregon: $1M
- Rhode Island: ~$1.84M
- Massachusetts: $2M
- Minnesota: ~$3M
- Illinois: $4M
- Vermont, Maryland: $5M
- New York: ~$7.35M (with a notorious "cliff")
- Connecticut: matches federal ($15M)

Plus inheritance-tax states: KY, NE, NJ, PA + MD.

State law also controls: elective share / forced share (typically 1/3 to 1/2 for surviving spouse), community property vs. common law regime, homestead protections, TOD deed availability, Medicaid lookback rules, trust situs, rule against perpetuities.

**Failure mode:**

- Massachusetts resident dies with $3M estate, all to children. Under federal law: $0 estate tax. Under Massachusetts: a meaningful state estate tax bill. A more intentional first-spouse plan might have reduced or deferred that state-level hit.

**Operational implication:** Ask early: "what state are you domiciled in?" and "what states do you own real property in?" before designing structure.

---

## Axiom 7 — Titling of real estate and major assets governs transfer at death

**Why it exists:** A will cannot override the titling of an asset. Joint tenancy with right of survivorship passes automatically to the survivor. Tenancy by the entirety does similar plus offers protection from creditors of only one spouse. Properly classified community property can produce a full basis adjustment at the first spouse's death, but only if the asset is actually community property under the relevant state's law. TOD deeds (available in a growing list of states) name beneficiaries who take automatically.

**Failure mode:**

- Decedent's will: "my house to my son Mark."
- House actually titled: joint tenancy with right of survivorship with daughter Emma (from a 2015 refinancing when Emma co-signed).
- On death, Emma owns the house. Mark gets nothing. The will is silent-overridden by titling.

**Operational implication:** The Asset Inventory must capture titling, not just ownership identity. **⧉ Beneficiary-Title Coherence** is the operator.

---

## Axiom 8 — Irrevocable choices must clear an intent-plus-cost test

**Why it exists:** Irrevocable trusts, Medicaid gift transfers, large lifetime gifts, ILIT premium funding, GRAT execution — these cannot be easily undone. Today's higher exemption may feel durable, but Congress can change it and families definitely change. A 2016 irrevocable trust designed for a $5M exemption regime may be counterproductive today.

**The three-prong test before going irrevocable:**

1. **Intent persistence:** Will the user's intent still be the intent in 20 years? (If there's a material chance not, include trust protector, decanting clauses, power to change beneficiaries within a class.)
2. **Tax/creditor benefit:** Does the tax or creditor-protection benefit justify (a) loss of control, (b) loss of step-up basis at death?
3. **Flexibility hooks:** Is there a trust protector who can remove/replace trustees, change situs, modify administrative provisions? Is decanting authorized? Is the trust grantor for income tax purposes so the grantor bears the tax burden?

**Failure mode:**

- 2014: Family creates irrevocable trust, funds it with $2M of low-basis stock. Exemption then was $5.34M.
- 2026: Exemption is now $15M. Under the modeled facts, the family likely would not have owed federal estate tax. The $2M is now worth $8M, but heirs will get no step-up because it's in the irrevocable trust. Result: lost step-up worth ~$1.4M in future capital gains tax. Gained: zero federal estate-tax savings under that scenario.

**Operational implication:** Before recommending irrevocability, **run the three-prong test explicitly** with the user. Document the reasoning in the plan report. Consider decanting older trusts that no longer serve their purpose.

---

## Axiom 9 — Illiquidity at death is the silent killer

**Why it exists:** Federal estate tax is due **in cash, nine months after death**. State estate tax deadlines vary but are similarly short. Family businesses, farms, real estate, private fund interests, and private company stock cannot be sold into probate at market prices.

**Failure mode:**

- Family business worth $25M. Federal estate tax: ~$4M. No life insurance. §6166 not elected. Heirs must sell a block of shares to fund the tax bill. Sale to a PE firm at a 30% discount (because it's a forced sale). Family loses both cash and continued voting control.

**Available remedies:**

- **ILIT-owned life insurance** sized to the expected tax bill (see [ILIT.md](../advanced-planning/ILIT.md))
- **§6166 deferral** for qualified closely held business interests (spreads tax over 14 years)
- **§303 redemption** for closely held corporation stock to pay tax without dividend treatment
- **Buy-sell agreements** funded by insurance, triggered at death
- **Planned liquidity reserves** — a percentage of the portfolio kept liquid specifically for estate settlement

**Operational implication:** The Liquidity Test (**⧗ Liquidity-at-Death** operator) runs on every plan where estate tax or significant administration expenses are expected.

---

## Axiom 10 — Communication is the actual work

**Why it exists:** Every experienced estate planner has seen plans where the structure was brilliant and the family still tore itself apart — and plans where the documents were simple and the family came out stronger. One of the biggest differentiators is communication.

**The communication agenda:**

- Values and hopes (more important than asset allocation)
- Big picture of the plan (structure, not dollar amounts)
- Why unequal, if unequal (during life, in person)
- What you expect of them (caring for each other, stewarding philanthropy)
- Where documents are kept
- Openness to feedback — sometimes heirs know things you don't

**Failure mode:**

- Parent never discussed plan with children. Assumed they'd figure it out.
- Will reading reveals one child has been given the vacation home, another the business, a third nothing but a letter about addiction concerns.
- Third child had no idea about the concerns, no chance to respond. Contest litigation consumes a large chunk of the estate.

**Operational implication:** The Family Meeting Agenda asset is a deliverable. Decline is allowed if the user has a specific reason, but the reason must be documented.

---

## Axiom 11 — Plans atrophy on contact with life

**Why it exists:** Every plan is written against a snapshot: tax law, family configuration, assets, health, values. Each of those changes. A 2015 plan written for a $5.43M exemption for a couple that has since divorced, remarried, moved from NY to FL, and had a fourth child is not just out of date — it is actively dangerous.

**Review triggers:**

- Every 3–5 years minimum (healthy adult, stable circumstances)
- Annually for UHNW or planning-intensive phases
- Immediately after: marriage, divorce, birth, adoption, death of beneficiary or fiduciary, major inheritance, business sale or acquisition, interstate move, change in domicile, change in tax law, material change in net worth, change in named agent's circumstances, new diagnosis

**An audit checks:**

- Document currency (will, trust, POAs, directives)
- Beneficiary designations on every account
- Trust funding — new assets acquired since last review need to be re-titled
- Named agents still appropriate and willing
- Guardian designations still appropriate as children age
- Tax law changes (year-specific: exemption, rates, rules)
- Insurance adequacy
- Digital asset inventory current

**Operational implication:** Every plan ships with a `review-schedule.md` and the user is given a calendar reminder and an attorney-review reminder. This is a deliverable.

<!-- KERNEL_EXPANSION_END v1.0 -->
