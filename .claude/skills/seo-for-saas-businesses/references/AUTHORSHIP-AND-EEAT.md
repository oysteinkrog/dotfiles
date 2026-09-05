# AUTHORSHIP-AND-EEAT — Author Entity & Trust Signals for 2026

> **Why this exists:** E-E-A-T (Experience, Expertise, Authoritativeness, Trustworthiness) is a Search Quality Rater concept, not a direct checklist ranking factor. For SaaS SEO, it is still operationally useful because visible expertise, entity consistency, citations, and review discipline make pages more trustworthy to users and easier for search / answer systems to reconcile. This reference is the practical pattern catalog.

## TOC

§1 Author entity surface · §2 Wikidata Q-ID · §3 ORCID · §4 Author archive page · §5 Per-post authorship · §6 Last-reviewed-date · §7 `knowsAbout` topical authority · §8 Organization entity · §9 `sameAs` reciprocity · §10 YMYL trust overlay · §11 Anti-patterns · §12 Verification checklist · §13 Related references

---

## §1 — Author entity surface

For every byline on the site, build a stable, machine-readable Author entity. Three layers:

1. **Author archive page** at `/authors/<slug>` — indexable, human-friendly bio + topical clustering of their posts.
2. **`Person` JSON-LD** with `sameAs` pointing to authoritative external profiles (verifiable identity).
3. **Author-bound trust badges** on every post they author (byline links to archive).

### Person schema template

```json
{
  "@context": "https://schema.org",
  "@type": "Person",
  "@id": "https://www.example.com/authors/jane-doe#person",
  "name": "Jane Doe",
  "url": "https://www.example.com/authors/jane-doe",
  "image": "https://www.example.com/authors/jane-doe.jpg",
  "jobTitle": "Principal Engineer",
  "worksFor": { "@id": "https://www.example.com/#organization" },
  "alumniOf": [
    { "@type": "CollegeOrUniversity", "name": "Stanford University" }
  ],
  "knowsAbout": ["distributed systems", "PostgreSQL", "observability"],
  "sameAs": [
    "https://www.linkedin.com/in/janedoe",
    "https://x.com/janedoe",
    "https://github.com/janedoe",
    "https://orcid.org/0000-0002-1234-5678",
    "https://www.wikidata.org/wiki/Q12345678",
    "https://stackoverflow.com/users/123456/jane-doe",
    "https://scholar.google.com/citations?user=ABCDEFG"
  ]
}
```

**Required `sameAs` for technical/SaaS authors (in priority order):**
1. LinkedIn (canonical professional identity)
2. GitHub (technical credibility)
3. X / Twitter (author voice + reach)
4. ORCID (academic / research credibility — get one for free at orcid.org)
5. Wikidata Q-ID (high leverage when genuinely notable and well sourced)
6. Stack Overflow / Stack Exchange (technical reputation)
7. Mastodon `rel=me` (federated identity)
8. Personal site / blog (`rel=me` reciprocal link required)

**Validate reciprocity** with `entity-consistency-check.ts` adapted for Person (currently checks Organization; extend pattern as needed).

---

## §2 — Wikidata Q-ID — a high-leverage entity move

Wikidata is one of the major public entity registries used across the web. A legitimate Wikidata Q-ID for an author or company can help create a persistent identity that other systems can reconcile, but it is not a guaranteed Knowledge Graph entry or ranking lever.

**Notability bar:** Wikidata is often more permissive than Wikipedia, but it still requires real, independently verifiable facts and citations. A SaaS founder, technical author, or speaker may qualify when reliable sources support the claims; do not create thin or promotional entities.

**Process:**
1. Create a Wikidata account.
2. Create the entity (`Special:NewItem`).
3. Add canonical statements: `instance of` (Q5 = human, Q4830453 = business), `occupation`, `employer`, `educated at`, `country of citizenship`.
4. Add `official website`, `LinkedIn ID`, `GitHub username`, `ORCID iD`, `X username`, `Mastodon address` as identifier statements.
5. Add **reliable source citations** for everything — uncited claims get reverted.
6. Reciprocate: include the Wikidata URL in your site's Person/Organization `sameAs`.

**Wikipedia is harder.** Notability requires multiple independent in-depth secondary sources. Don't try to create an article about yourself — community will revert and may flag you. Instead: do work that gets covered, and let editors create the article. Wikidata first; Wikipedia eventually.

---

## §3 — ORCID for technical authors

ORCID iD is a 16-digit registry for researchers. Free at orcid.org. Critical for:
- Academic SaaS (research tools, citation managers)
- Healthtech / fintech where author credentials matter
- Engineers who publish papers, white papers, or influential blog posts

ORCID helps disambiguate technical and scientific authors. Wire it into Person `sameAs` when the author actually has a research identity; do not create empty ORCID profiles purely for SEO optics.

---

## §4 — Author archive page pattern

Each author gets a page with:

```
URL:    /authors/jane-doe
Title:  Jane Doe — Principal Engineer at Acme | Acme Blog
Description: Articles by Jane Doe on distributed systems, PostgreSQL, and observability.

H1:     Jane Doe
H2:     About
        - Bio (2-4 sentences with verifiable claims: years experience, prior employers, notable projects)
        - Credentials list (degrees, certifications, talks given)
        - Areas of expertise (matches knowsAbout in JSON-LD)
H2:     Connect
        - LinkedIn, GitHub, X, ORCID, Wikidata (icons + links)
H2:     Recent posts
        - Reverse-chronological list with topic chips
H2:     Topic clusters
        - Posts grouped by topic (e.g., "Database performance (12 posts)")

JSON-LD: <Person> + <CollectionPage> referencing the author's posts
```

Indexable. Linked from every post byline. Inbound-link gravity from individual posts compounds the author archive's authority.

---

## §5 — Per-post authorship pattern

Every post should expose:

1. **Visible byline** with link to author archive: `By [Jane Doe](/authors/jane-doe), Principal Engineer · April 30, 2026 · Last reviewed May 14, 2026`
2. **`Article.author`** in JSON-LD referencing the author `@id`:

```json
{
  "@context": "https://schema.org",
  "@type": "TechArticle",
  "headline": "Why your Postgres SELECT is slow",
  "datePublished": "2026-04-30",
  "dateModified": "2026-05-14",
  "author": { "@id": "https://www.example.com/authors/jane-doe#person" },
  "publisher": { "@id": "https://www.example.com/#organization" },
  "mainEntityOfPage": "https://www.example.com/blog/postgres-select-slow"
}
```

3. **`reviewedBy`** (different from author) for review-dated content:

```json
"reviewedBy": { "@id": "https://www.example.com/authors/john-smith#person" }
```

**Note:** Google deprecated the author photo / byline rich result in SERPs years ago. The reason to do this in 2026 is *entity reconciliation in Knowledge Graph and LLM retrieval pools*, not SERP appearance.

---

## §6 — Last-reviewed-date for evergreen content

YMYL and technical content benefits from explicit `dateModified` + visible "Last reviewed: <date> by <Person>". Patterns:

- Update `dateModified` on every meaningful edit (not on whitespace changes).
- For evergreen content, schedule quarterly reviews; have the reviewer initial the post and bump the date.
- Surface the date prominently — both for users (signals freshness) and for downstream freshness interpretation.

---

## §7 — `knowsAbout` as topical authority signal

`knowsAbout` is an array of topics the author is credible on. Use schema.org topics or canonical Wikidata Q-IDs:

```json
"knowsAbout": [
  { "@type": "DefinedTerm", "name": "PostgreSQL", "url": "https://www.wikidata.org/wiki/Q192490" },
  { "@type": "DefinedTerm", "name": "distributed systems" }
]
```

`knowsAbout` can help disambiguate authors writing on multiple topics. A SaaS engineering blog with 8 authors and 200 posts should tag each author's expertise precisely; treat any retrieval-pool benefit as a hypothesis to measure, not a promise.

---

## §8 — Organization entity — the same pattern at company scale

Mirror the Person pattern for the Organization:

```json
{
  "@context": "https://schema.org",
  "@type": ["Organization", "Corporation"],
  "@id": "https://www.example.com/#organization",
  "name": "Acme",
  "legalName": "Acme Inc.",
  "url": "https://www.example.com",
  "logo": "https://www.example.com/logo.svg",
  "founder": [{ "@id": "https://www.example.com/authors/founder#person" }],
  "foundingDate": "2018-04-01",
  "address": { "@type": "PostalAddress", "addressCountry": "US" },
  "sameAs": [
    "https://www.linkedin.com/company/acme",
    "https://x.com/acme",
    "https://github.com/acme",
    "https://www.crunchbase.com/organization/acme",
    "https://www.wikidata.org/wiki/Q...",
    "https://en.wikipedia.org/wiki/Acme_Inc."
  ],
  "contactPoint": [{
    "@type": "ContactPoint",
    "contactType": "customer support",
    "email": "support@acme.com",
    "url": "https://www.acme.com/contact"
  }]
}
```

Crunchbase can be a useful citation source for B2B SaaS when the company profile is real and maintained. Wikipedia + Wikidata is high leverage only when the company genuinely meets independent-source notability.

---

## §9 — `sameAs` reciprocity

Every link declared in `sameAs` must reciprocate. The platform-by-platform map:

| Platform | Where to put the back-link |
|---|---|
| LinkedIn personal | "Websites" in profile contact info |
| LinkedIn company | About page → website field |
| GitHub user | profile → "Website" field |
| GitHub org | org settings → URL |
| X / Twitter | profile → website |
| Mastodon | profile → links → set `rel=me` |
| Wikipedia (when applicable) | infobox → official website |
| Wikidata | `P856` (official website) statement |
| Crunchbase | company profile → website |
| ORCID | person record → websites |
| Stack Overflow | profile → "Website" |

Run `entity-consistency-check.ts` after any sameAs change. The script verifies reciprocity for the platforms it knows; gaps appear as `SAMEAS_NO_RECIPROCAL` warnings.

---

## §10 — YMYL trust overlay

For SaaS in regulated verticals (fintech, healthtech, legaltech, identity, securitytech), additional E-E-A-T signals are load-bearing:

| Signal | Implementation |
|---|---|
| Visible regulatory disclaimer | Footer + dedicated /legal/regulatory page |
| Author credentials displayed | Required for any review/recommendation content (CFA, MD, JD, CPA, CISSP, etc.) |
| Last-reviewed-by-an-expert dates | Visible on every YMYL article |
| Citations to primary sources | Inline link + footnote reference list |
| Editorial policy / corrections page | `/about/editorial-policy`, `/about/corrections` |
| About-the-author micro-bios | At top of every YMYL article (not just byline) |
| Contact info + physical address | If applicable; required for fintech in many jurisdictions |
| security.txt + responsible-disclosure | `/.well-known/security.txt` per RFC 9116 |
| Compliance badges with verifiable links | SOC 2, ISO 27001, HIPAA, PCI-DSS, GDPR/CCPA — link to the issuing audit firm |

Regulated-vertical SaaS pages without these trust surfaces are harder for users, reviewers, and answer systems to trust. Treat trust-surface gaps as high-priority risks, but do not claim invisibility without measured evidence.

---

## §11 — Anti-patterns

1. **Don't fabricate `Person` profiles.** "Generated author bios" are a manual-action vector. Real people, real bios, real `sameAs`.
2. **Don't put generic stock photos as author images.** Reverse-image-searchable stock photos signal AI-generated content.
3. **Don't use a shared "Editorial Team" byline for content where an individual author is appropriate.** Generic bylines lose the author-entity benefit.
4. **Don't add `sameAs` to a profile you don't actually own.** Reciprocity check will catch you and signal manipulation.
5. **Don't forget to update `dateModified` after a real edit.** Stale dates weaken user trust and freshness interpretation.
6. **Don't use `Article.author.url` without `@id`.** Knowledge Graph reconciles by `@id`; URL-only is weaker.
7. **Don't `knowsAbout` everything.** Three to seven precise topics beats fifteen vague ones.

---

## §12 — Verification checklist

Before claiming authorship hygiene is done, verify:

- [ ] Every byline links to an indexable author archive.
- [ ] Every author archive has Person JSON-LD with sameAs covering 5+ platforms.
- [ ] `entity-consistency-check.ts` passes with no `SAMEAS_NO_RECIPROCAL` for the canonical author.
- [ ] At least the founder/CEO has a Wikidata Q-ID.
- [ ] Every post has Article.author + Article.publisher + dateModified.
- [ ] YMYL pages have visible reviewer, last-reviewed date, and citation footer.
- [ ] Organization JSON-LD on homepage with founder reference and 5+ sameAs.

Wire these checks into Phase 10 / Phase 12 gates with `validate-schema.ts` and `entity-consistency-check.ts`.

---

## §13 — Related references

- `entity-consistency-check.ts` — script
- `TRUST-INFRASTRUCTURE.md` — broader trust signals
- `CITATION-OPS.md` — extracting citations from content
- `SCHEMA-COOKBOOK.md` — schema patterns including Person/Article
- `AI-VISIBILITY.md` — how E-E-A-T plays into LLM citation
