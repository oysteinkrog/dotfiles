# HIGH-RISK-GATE

For any content that can materially affect money, health, safety, legal rights, employment, housing, civic decisions, security architecture, or other consequential outcomes, raise the publishing bar.

For SaaS this is most often: anything compliance / SOC 2 / HIPAA / PCI / financial / legal-tech / healthcare-tech / fintech / security architecture.

## Pre-publish gate

Before the page becomes indexable (`index,follow`), require all of:

- [ ] Named author with relevant credentials.
- [ ] Qualified reviewer (or clearly marked unreviewed status). For SaaS: usually engineering lead, security/compliance officer, or an external expert on retainer.
- [ ] Primary or official sources where possible (NIST, ISO, IRS, FDA, HIPAA, PCI SSC, etc., for the relevant claim).
- [ ] Claim register: a list of every high-risk statement on the page with source link, retrieval date, and confidence label.
- [ ] Date reviewed and next review date.
- [ ] Visible limitations and caveats.
- [ ] Escalation guidance for cases requiring a professional ("this is not legal advice — consult a licensed attorney for your jurisdiction").
- [ ] No guarantees or unsupported outcome claims.
- [ ] Privacy and data-use disclosures when sensitive information is involved.

If any item is incomplete, ship with:

```html
<meta name="robots" content="noindex,follow">
```

Until the gate is complete.

## Author and reviewer pages

- Each author has a real bio with: full name, role, relevant credentials, photo (optional but increases trust), `sameAs` links to LinkedIn / GitHub / X / publication profiles.
- `Person` schema on the author page.
- Author bylines on every page they wrote with `author` property in the page's `Article` schema.

## Methodology pages

For benchmarks, comparisons, or research:

- Methodology page describes data sources, sample size, time window, exclusions, scoring criteria, known limitations.
- Methodology link visible from every page that uses the data.
- Methodology page itself is indexable; benchmark pages link to it.

## Corrections policy

- Corrections page describes how errors are reported and fixed.
- Visible footer link.
- Material corrections marked on the page with date and what changed.

## Legal disclosures

- "This is not [legal/medical/financial/tax] advice" where the topic touches that domain.
- Affiliate disclosures per FTC endorsement guides where applicable.
- Material connection disclosures for testimonials and case studies.

## Examples

### Pricing page (medium risk — financial)

- Named owner (revenue / RevOps).
- Reviewer: finance lead.
- Sources: internal billing system (auth.).
- Claims register: every plan limit, overage, billing-cycle claim.
- Reviewed quarterly minimum.
- Limitations: "Pricing for enterprise plans is custom; contact sales."
- No guarantees of "best price in the market" without comparison evidence.

### Security / SOC 2 page (high risk)

- Named owner: CISO or security lead.
- Reviewer: external auditor (Drata / Vanta-style attestation visible).
- Sources: SOC 2 report, DPA, security whitepaper.
- Claims register: every security control statement with audit reference.
- Reviewed at audit cadence (annually or triggered).
- Limitations: scope of audit, regions covered, compliance attestations vs certifications.
- Escalation: link to security@example.com and request-attestation form.

### Healthcare-tech feature page (high risk)

- Named owner: medical / clinical advisor.
- Reviewer: licensed clinician, named with credentials.
- Sources: FDA guidance, peer-reviewed studies, internal validation.
- Claims register: every clinical claim with source and date.
- Reviewed quarterly + on regulation change.
- Limitations: "Not a substitute for medical advice."
- Escalation: "Consult a licensed healthcare professional for your situation."

### Compliance / legal-tech page (high risk)

- Named owner: in-house counsel or named external counsel.
- Reviewer: licensed attorney in relevant jurisdiction.
- Sources: statutes, regulations, agency guidance with retrieval date.
- Claims register: every legal claim with source and date.
- Reviewed annually + on legislative change.
- Limitations: "This is general information, not legal advice. Laws vary by jurisdiction."
- Escalation: "Consult a licensed attorney in your jurisdiction."

## When the gate fails post-publish

If a high-risk page ships without the gate complete and is then noticed:

1. Add `noindex,follow` immediately.
2. Add a visible "under review" banner.
3. Complete the gate.
4. Re-enable `index,follow`.
5. Document in `seo-changelog.md`.

Do not delete the page reactively without considering existing inbound links and user value.
