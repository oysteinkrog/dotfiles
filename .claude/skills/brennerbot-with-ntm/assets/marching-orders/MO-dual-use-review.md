# MO-dual-use-review.md — Dual-Use / Ethics Review for Sensitive Outputs

**Phase:** Phase 7 (audit) for sessions whose output could enable harm if misused
**Operators activated:** ⌂ Materialize (specific harm scenarios), ⊞ Scale-Check (impact magnitude)
**Parameters:** `<DELIVERABLE_PATH>`, `<DOMAIN>` (e.g., security/biology/chemistry/AI), `<SESSION_ID>`

---

Some research outputs are dual-use — useful for defense AND attack. Examples: security vulnerability disclosures, weaponizable techniques, privacy-eroding methods, pre-existing-tech enhancement.

This MO formalizes the dual-use ethics review. Per `dual-use-review` mode in EXTENDED-OPERATING-MODES.md.

---

**Step 1 — Identify dual-use surface.**

For each major claim or technique in `<DELIVERABLE_PATH>`:

```markdown
# In analyses/dual-use-review/SURFACE.md:

| Claim/technique | Defensive use | Offensive use | Severity if misused |
|-----------------|---------------|---------------|---------------------|
| <claim 1>       | <case>        | <case>        | <low|med|high|crit> |
| <claim 2>       | ...           | ...           | ...                 |
```

If all claims are clearly defense-only, dual-use review may be brief.

If any claim is severity:high or critical for offensive use, full review required.

**Step 2 — Reviewer roster.**

Recruit:

- Domain ethicist (depending on `<DOMAIN>`)
- Subject-matter expert who's aware of misuse landscape
- Risk officer (if organization has one)

For ad-hoc projects: ≥1 person with relevant domain expertise + general ethics framing.

**Step 3 — Frame ethical questions.**

Per the Asilomar / Pilbara / NeurIPS dual-use framework:

```markdown
1. **Direct harm potential**: who could be harmed by this output, in what scenarios?
2. **Counterfactual impact**: would this be available without our work? (E.g., is it a re-discovery of widely-known result?)
3. **Asymmetry**: does the output favor defense or attack? (Sometimes a technique helps defenders more than attackers.)
4. **Mitigation**: can we design publication/release to favor defense?
5. **Disclosure ethics**: should this be disclosed responsibly (to vendors first, with embargo)?
6. **Long-term concerns**: even if low risk now, does the output enable future harm?
```

**Step 4 — Apply mitigations.**

Common mitigations:

- **Coordinated disclosure**: notify vendors / authorities before public release
- **Redaction**: publish methodology but redact specific exploits / payloads
- **Defensive framing**: lead with detection/mitigation rather than attack technique
- **Access control**: distribute via channels accessible to defenders (e.g., CERTs)
- **Embargo**: delay public release to allow remediation

If mitigations apply, document in `<DELIVERABLE_PATH>` § Ethical considerations.

**Step 5 — Document review.**

```markdown
# In deliverables/ETHICAL-REVIEW.md:

# Dual-Use Ethics Review

## Domain
<DOMAIN>

## Reviewers consulted
- <name 1> (<role>)

## Dual-use surface analysis
<reference to analyses/dual-use-review/SURFACE.md>

## Ethical framework analysis
1. Direct harm potential: <answer>
2. Counterfactual impact: <answer>
3. Asymmetry: <answer>
4. Mitigation strategy: <answer>
5. Disclosure ethics: <answer>
6. Long-term concerns: <answer>

## Mitigations applied
- <mitigation 1>
- <mitigation 2>

## Verdict
- PUBLISH AS-IS
- PUBLISH WITH REDACTION
- COORDINATED DISCLOSURE FIRST (then publish)
- DO NOT PUBLISH
- ESCALATE TO HUMAN GOVERNANCE BODY (e.g., DSAI, university IRB)

## Reviewer sign-off
- [ ] <name 1>
- [ ] <name 2>
```

**Step 6 — If verdict is "DO NOT PUBLISH"**:

The session's deliverable stays internal. Specifically:

- HANDBACK marked `restricted: true; restriction_reason: <one-line>`
- workspace not committed to public git
- Internal use only
- Review periodically; conditions may change

This is rare but should be a real option. Sometimes the right answer is "this insight is too dangerous to share at this time."

**Step 7 — If verdict is "COORDINATED DISCLOSURE FIRST"**:

Define disclosure plan:

- Who to notify (vendors, researchers, authorities)
- What to share with each
- Embargo timeline
- Public release date

Track in `analyses/dual-use-review/DISCLOSURE-PLAN.md`. Review quarterly.

---

**Anti-patterns:**

- ✗ Skip dual-use review because "we're researchers, not weapons designers" (any insight has dual-use potential in some domain)
- ✗ Treat dual-use review as paperwork (it's a real ethical decision)
- ✗ Refuse dual-use review out of paranoia (most outputs are fine to publish; review establishes baseline)
- ✗ Skip mitigation design (often the right answer is publication-with-care)
- ✗ Skip reviewer sign-off (decisions need accountability)

**Ship-or-Surface SLA:** wall time depends on review depth; typically 1-3 days for full review.

---

## When this MO is mandatory

- Security research surfacing exploits, vulnerabilities, attack techniques
- AI/ML research that could enable harmful capabilities (deception, manipulation, automation of harm)
- Biological / chemical / physical research with weapons potential
- Privacy research that could enable surveillance
- Social science research that could enable manipulation at scale

For these, MO-dual-use-review is non-optional in Phase 7.

---

## When this MO is optional but recommended

- Research that's potentially misused but predominantly defensive
- Methodology papers (less direct harm potential)
- Education materials
- Literature surveys

The threshold is: "Could a smart, motivated bad actor get harm out of this?" If yes, run the review.

---

## Composition

- Compose with subagents/red-team.md (red-team identifies misuse vectors)
- Compose with subagents/ethics-reviewer.md
- Compose with /pre-publication-review for T5 publications (ethics review is part of pre-publication)
