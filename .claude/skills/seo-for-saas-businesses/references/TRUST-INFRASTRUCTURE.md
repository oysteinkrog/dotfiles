# TRUST-INFRASTRUCTURE

## TOC

Trust elements per business model · Author pages · Reviewer pages · Editorial standards / corrections policy · Methodology pages · Source lists with dates · About page · Privacy/security/refund/data-use · Public update logs · Material-connection (FTC) disclosures · Brand and entity consistency · Per-tier checklist · Anti-patterns · Cross-links

Trust is not a paragraph in a footer. It is *visible operating evidence* readable by humans, search systems, and AI engines reconciling entities. Most SaaS sites lose trust signals to drift, not absence: an About page from 2022, a privacy policy with the wrong DPO email, a founder bio that doesn't match LinkedIn, a `Person` schema citing a no-longer-employed reviewer. Trust infrastructure is a maintained inventory.

Phase mappings: Phase 1 (trust inventory baseline), Phase 4 (author / reviewer / methodology pages), Phase 5 (links from priority pages to trust pages), Phase 6 (entity sameAs + brand consistency), Phase 8 (trust-signal regression alarms), Phase 13 (compounding gaps).

## Trust elements per business model

| Element | When required |
|---|---|
| Author pages with credentials | Editorial sites; high-risk content; news |
| Reviewer pages | Health / finance / legal / security content |
| Editorial standards / corrections policy | Editorial sites; original-research publishers |
| Methodology pages | Any quantitative claim (benchmarks, surveys, rankings) |
| Source lists with dates | Pages making claims that change over time |
| Product screenshots / demos / first-hand proof | Commercial pages; comparison pages |
| Real About page (named humans, real address) | Every site |
| Privacy / security / refund / data-use disclosures | Every site that handles user data |
| Public update logs | Pages with materially changing content |
| Testimonial permission records | Anywhere customer names / quotes / logos appear |
| Material-connection disclosures (FTC) | Affiliate / sponsored / incentivized content |
| Brand entity consistency (across site + sameAs profiles) | Every site |
| Audit / certification artifacts | Regulated verticals; B2B SaaS in procurement |
| Accessibility statement | Every site (US, EU, UK accessibility laws) |

(`confirmed` per canonical guide §14)

## Author pages

For editorial / blog / docs surfaces. Each author has a real public page:

```
URL: /authors/<slug>
Schema: Person
```

Required content:

- Real name (matches LinkedIn, X, GitHub).
- Photo.
- Role and affiliation (current).
- Credentials relevant to the topic area (degrees, certifications, publications).
- Publication list on this site.
- Links to external profiles (`sameAs`).
- Last reviewed / last published.

```json
{
  "@context": "https://schema.org",
  "@type": "Person",
  "name": "Jane Doe",
  "jobTitle": "Lead Security Researcher",
  "worksFor": {"@type": "Organization", "name": "Acme"},
  "image": "https://www.example.com/authors/jane-doe.jpg",
  "url": "https://www.example.com/authors/jane-doe",
  "sameAs": [
    "https://www.linkedin.com/in/janedoe-acme",
    "https://github.com/janedoe",
    "https://orcid.org/0000-0002-1234-5678"
  ]
}
```

Reference the author from each `Article`:

```json
"author": {
  "@type": "Person",
  "name": "Jane Doe",
  "url": "https://www.example.com/authors/jane-doe"
}
```

Anti-pattern: ghost-authored content. Helpful-content classifier expects accountable authorship. (`likely`)

## Reviewer pages

For high-risk content (security, finance, legal, health) where a different person reviewed the article:

```
URL: /reviewers/<slug>
Schema: Person
```

Reference the reviewer in the `Article`:

```json
"reviewedBy": {
  "@type": "Person",
  "name": "Dr. Sam Kim",
  "url": "https://www.example.com/reviewers/sam-kim",
  "jobTitle": "Compliance Counsel"
}
```

`reviewedBy` is supported by schema.org and signals expert oversight. Visible "Reviewed by Dr. Sam Kim on 2026-04-12" near the headline reinforces the schema. See [HIGH-RISK-GATE](HIGH-RISK-GATE.md).

## Editorial standards / corrections policy

A real editorial standards page covering:

- How content is researched, drafted, reviewed, published.
- Sourcing standards (primary > secondary > generic).
- AI usage disclosure.
- Conflict-of-interest policy.
- How corrections are made (separate corrections policy).

Corrections policy:

```
URL: /editorial/corrections
```

Each material correction logged with date, what was wrong, what was fixed, and a permanent reference. Visible on the corrected page itself ("Updated 2026-04-12 to correct the latency figure; original was 47 ms; corrected to 49 ms").

(`confirmed` — corrections policy is a recurring procurement and AI-citation eligibility signal.)

## Methodology pages

For every quantitative claim. See [PROOF-LIBRARY-OPS](PROOF-LIBRARY-OPS.md). One methodology page per claim family — not one giant page covering everything.

## Source lists with dates

Pages making time-sensitive claims must show their sources. Inline citations with dates outperform footer-only citations for AI-engine extraction (`likely`).

```html
<p>
  As of 2026-Q1, the median SaaS company spends 5.4% of revenue on infrastructure
  (<a href="https://battery.com/2026-saas-survey" rel="nofollow noopener">
    Battery SaaS Survey 2026
  </a>).
</p>
```

## About page

The most-overlooked trust surface. Required:

- Real legal entity name + jurisdiction.
- Real address (or "remote, headquartered in <city>" with a registered-agent address).
- Founders / leadership with names + photos + LinkedIn.
- Year founded.
- Mission / what the company does, in plain language.
- Press / media contact.
- Investor list (if applicable).

A SaaS About page that is "We're a passionate team building the future of <category>" with no names is a 2-line bot-generated page. AI engines and procurement reviewers both penalize it.

## Privacy / security / refund / data-use

Live, dated pages. See [LIFECYCLE-CONTENT](LIFECYCLE-CONTENT.md) for the per-page-type briefs:

| Page | Anchor signals |
|---|---|
| `/privacy` | Last reviewed; DPO contact; subprocessor list link; data-residency options |
| `/security` | Auditor; report dates; encryption posture; incident-response SLOs |
| `/legal/dpa` | Public template; signed-counterpart instructions |
| `/legal/refund` | Real terms; not "depends on case" |
| `/legal/terms` | Last updated; change history |

## Public update logs

For pages that change materially:

- Editorial articles: "Last updated YYYY-MM-DD" inline.
- Pricing pages: changelog of price changes (helps existing users; signals transparency).
- Comparison pages: "Last verified YYYY-MM-DD against <competitor>'s public docs".
- Methodology pages: version history.

## Material-connection disclosures (FTC)

For US-targeted content with affiliate / sponsored / incentivized relationships:

- Visible disclosure near the start of the content, not the end.
- Specific: "This article includes affiliate links to Acme; we may earn a commission if you sign up." Not "we may receive compensation."
- Logged in `analyses/disclosures.csv` so audits can verify coverage.

## Brand and entity consistency

Across site + sameAs + external profiles, keep these *exactly* the same:

| Field | Why |
|---|---|
| Company name (case, spacing, punctuation) | "AcmeCo" vs "Acme Co" creates entity ambiguity |
| Tagline (one canonical version) | AI engines reconcile by similarity |
| Founder / executive names + titles | Procurement and PR consistency |
| Description of what the product does | Cross-source reconciliation for AI |
| Logo URL | Branded snippet display; OG default |
| Address | Local SEO + procurement |
| Phone / email / support channels | When public |

Profiles to keep current:

- LinkedIn company page.
- X / Twitter (`@acme`).
- GitHub (`github.com/acme`).
- Crunchbase.
- ProductHunt.
- Marketplaces (Stripe Apps, Shopify, etc.).
- Review sites (G2, Capterra, TrustRadius, GetApp, Software Advice).
- Press / investor pages on partner sites.

The `Organization` schema's `sameAs` array references all of these. Reciprocity matters: each linked profile should also link back to the homepage. (`confirmed` for entity reconciliation by AI engines.)

## Per-tier checklist

| Tier | Trust scope |
|---|---|
| **T1** | Real About page; privacy + security + refund pages; one named author for any blog content; corrections policy linked |
| **T2** | + Author pages with `Person` schema; methodology page for any quantitative claim; sameAs list current; accessibility statement |
| **T3** | + Reviewer pages for high-risk content; editorial standards page; public corrections log; per-page "last reviewed" stamps; FTC disclosures audited |
| **T4** | + Multi-locale trust pages; per-vertical compliance pages; published methodology versions; quarterly entity-consistency audit |

## Anti-patterns

| Don't | Why | Do instead |
|---|---|---|
| About page with no human names | Ghost company; AI / procurement penalty | Real names, photos, LinkedIn |
| `Person` schema with no real public profile | Schema lies; trust collapse on cross-check | Real profiles with sameAs reciprocity |
| Privacy policy from 2021 with current dates | Untrusted; legal exposure | Last-reviewed visible; cadence honoured |
| Corrections only via "edit silently" | No public log; trust collapse on cross-check | Visible correction note; corrections page |
| AI-generated author personas | Helpful-content + slop + scaled-content risk | Real authors only |
| `sameAs` to dead profiles | Entity reconciliation breaks | Quarterly verification |
| Tagline differs across home / OG / About / press | AI engine entity ambiguity | One canonical tagline |
| Customer logo wall without permission records | Legal exposure | Permission per logo |
| FTC disclosure at the bottom of long article | Regulatory non-compliance | Near the start of the content |
| Methodology page that says "we used LLMs to analyze data" | Insufficient methodology | Specify the data, sample, dates, exclusions |
| Material claim with no source link | Untrusted; AI engines won't cite | Inline source + date |
| Auditor name in security PDF only, not page | Procurement asks for it on-page | Visible on `/security` |
| Privacy policy as iframe to a third-party generator | Legal accuracy + tracking risk | Owned, dated, reviewed copy |
| "Last updated" hardcoded to a fixed date | Stale; trust collapse on review | Generated at build from real change history |
| Corrections policy that points to a contact form | Implies "we'll fix it if asked" but no public log | Public log of corrections |
| Three different photos of the same founder across profiles | Entity ambiguity | Canonical photo |
| No investor list when investors are public | Procurement asks; missing reduces credibility | Public investor list with logos (with permission) |

## Cross-links

- [PROOF-LIBRARY-OPS](PROOF-LIBRARY-OPS.md) — methodology and customer-permission tracking.
- [SCHEMA-POLICY](SCHEMA-POLICY.md) — `Person`, `Organization`, `Article` schemas.
- [HIGH-RISK-GATE](HIGH-RISK-GATE.md) — reviewer requirements for high-risk content.
- [LIFECYCLE-CONTENT](LIFECYCLE-CONTENT.md) — security / privacy / procurement pages.
- [AI-VISIBILITY](AI-VISIBILITY.md) — entity consistency for AI engine reconciliation.
- [AUTHORSHIP-AND-EEAT](AUTHORSHIP-AND-EEAT.md) — Person/Organization sameAs reciprocity, Wikidata, ORCID, YMYL trust overlay.
- [ACCESSIBILITY-AS-SEO](ACCESSIBILITY-AS-SEO.md) — accessibility statement is a trust artifact.
- [PHASE-7-AUTHORITY](PHASE-7-AUTHORITY.md) — earned mentions and brand-mention reclamation.
