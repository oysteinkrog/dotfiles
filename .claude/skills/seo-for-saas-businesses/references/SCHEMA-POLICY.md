# SCHEMA-POLICY

Structured data mirrors visible page content. It is not a ranking hack. Plan around what is *currently supported* by Google, not what 2019 blogs recommended.

## Core principles

1. **Schema must mirror visible content.** Don't claim aggregateRating, awards, expert review, FAQs, or affiliations the page does not visibly contain.
2. **Validate after every template change.** A template edit can silently break schema.
3. **Use schema only when it accurately describes content and might enable a feature.** Otherwise it is noise.
4. **Server-render JSON-LD.** Never inject from `useEffect`.
5. **Don't plan around retired or restricted features.**

## Currently retired / restricted (as of 2026-Q2)

| Type / feature | Status | Action |
|---|---|---|
| `HowTo` rich results | Deprecated for general web results | Don't plan rich-result strategy around it. The schema is fine for entity understanding, just not for visible rich results. |
| `Sitelinks Searchbox` (`SearchAction`) | Retired | Remove if added; do not plan around it. |
| `FAQPage` rich results | Restricted to authoritative government / health sites | Don't add FAQ schema as a commercial-page rich-result tactic. Only on real visible FAQs. |
| `QAPage` rich results | Restricted | Use only on genuine Q&A community pages. |
| `Dataset` in general Google Search | No longer a generic Search rich-result plan; Google documentation points it to Dataset Search | Use for real public datasets / benchmarks where Dataset Search or entity clarity matters, not as a normal SERP feature tactic. |
| Merchant return / shipping policy markup | Relevant only when the SaaS has an ecommerce / marketplace / merchant-feed surface | Use for SaaS marketplaces, paid app stores, or commerce-like products with visible policy pages; skip for ordinary B2B SaaS. |

## Recommended types for SaaS

| Page | Type(s) |
|---|---|
| Homepage | `Organization` + `WebSite` |
| Pricing | `WebApplication` (preferred for cloud SaaS over `SoftwareApplication`) + `Offer`(s) |
| Comparison | `Article` (or none — schema is optional here) |
| Use case / industry | `Article` |
| Integration detail | `WebApplication` (the integration is a software interaction) |
| Docs / tutorial | `Article` (do not use `HowTo` for visible rich results) |
| Customer story | `Article` |
| Author page | `Person` |
| Blog post | `Article` + author `Person` |
| Changelog entry | `Article` (date sensitive) |
| Security page | `Organization` (root) + `Article` |
| Review hub (genuine, moderated) | `Review` (only when reviews are real, visible, policy-compliant) |
| Sitewide breadcrumbs | `BreadcrumbList` |
| Product video | `VideoObject` (only when video is embedded and visible) |
| Public dataset | `Dataset` when it is a real downloadable / queryable dataset or benchmark; track as Dataset Search / entity clarity, not generic Google Search rich-result lift |
| Live event / webinar | `Event` |
| Job listing | `JobPosting` |
| Course / training | `Course` |

## SaaS-specific patterns

### `WebApplication` over `SoftwareApplication`

`WebApplication` is a subtype of `SoftwareApplication` and more accurate for cloud-delivered SaaS. Use:

```json
{
  "@context": "https://schema.org",
  "@type": "WebApplication",
  "name": "Acme",
  "applicationCategory": "BusinessApplication",
  "operatingSystem": "Any (web-based)",
  "browserRequirements": "Requires JavaScript",
  "url": "https://www.example.com",
  "offers": [
    {
      "@type": "Offer",
      "name": "Starter",
      "price": "29",
      "priceCurrency": "USD",
      "priceSpecification": {
        "@type": "UnitPriceSpecification",
        "price": "29",
        "priceCurrency": "USD",
        "billingIncrement": 1,
        "unitText": "MONTH"
      }
    }
  ]
}
```

### `Organization` + `WebSite` on homepage

```json
{
  "@context": "https://schema.org",
  "@type": "Organization",
  "name": "Acme",
  "alternateName": "Acme Inc",
  "url": "https://www.example.com",
  "logo": "https://www.example.com/logo.png",
  "description": "...",
  "foundingDate": "2024-01-01",
  "founder": [{"@type": "Person", "name": "Founder Name"}],
  "sameAs": [
    "https://github.com/acme",
    "https://x.com/acme",
    "https://www.linkedin.com/company/acme",
    "https://www.crunchbase.com/organization/acme",
    "https://www.producthunt.com/products/acme"
  ]
}
```

`sameAs` reciprocity matters for entity reconciliation — every linked profile should also link back to the homepage.

### `Article` for editorial pages

```json
{
  "@context": "https://schema.org",
  "@type": "Article",
  "headline": "...",
  "description": "...",
  "image": "https://www.example.com/...",
  "datePublished": "2026-04-30T08:00:00Z",
  "dateModified": "2026-04-30T08:00:00Z",
  "author": {
    "@type": "Person",
    "name": "Author Name",
    "url": "https://www.example.com/authors/author-name"
  },
  "publisher": {
    "@type": "Organization",
    "name": "Acme",
    "logo": {
      "@type": "ImageObject",
      "url": "https://www.example.com/logo.png"
    }
  }
}
```

### `BreadcrumbList` sitewide

Once per breadcrumbed page, mirroring the visible breadcrumb:

```json
{
  "@context": "https://schema.org",
  "@type": "BreadcrumbList",
  "itemListElement": [
    {"@type": "ListItem", "position": 1, "name": "Home", "item": "https://www.example.com"},
    {"@type": "ListItem", "position": 2, "name": "Integrations", "item": "https://www.example.com/integrations"},
    {"@type": "ListItem", "position": 3, "name": "Notion", "item": "https://www.example.com/integrations/notion"}
  ]
}
```

## Validation

`scripts/validate-schema.ts` runs against the representative URL set:

1. Fetches each URL.
2. Extracts every `<script type="application/ld+json">`.
3. Parses each as JSON.
4. Validates `@type` against schema.org current types.
5. Validates required + recommended properties for known Google-supported types.
6. Verifies the schema's claims (e.g. `Offer` `price`) match the visible page (best-effort heuristic).
7. Emits per-URL pass/fail report.

CI gate: PR cannot merge if validate-schema fails.

## Feature-churn guard

Structured-data eligibility changes often enough that every Phase 3 / Phase 10 schema recommendation must log its current source:

1. Check Google Search Central's documentation update feed and the specific structured-data feature page.
2. Label the recommendation:
   - `confirmed`: Google currently supports this feature for this page type.
   - `likely`: schema is valid and helpful for entity clarity, but visible Search treatment is limited or not guaranteed.
   - `hypothesis`: schema may help downstream systems, but there is no current Google feature support.
3. If a type is retired or restricted, remove "rich result" from the expected impact. The expected impact becomes entity clarity, data consistency, or downstream reuse only.
4. Never let schema be the only reason to create a page. Page value comes first; schema describes it.

## When schema is wrong

| Symptom | Cause | Fix |
|---|---|---|
| GSC shows enhancement errors after deploy | Template change dropped a required property | Diff the template; restore property |
| Rich results lost | Type deprecated or page no longer matches type | Remove if deprecated; restore visible content match |
| Schema declares price ≠ visible price | Schema imports stale snapshot | Make schema read from the same data source as the page |
| Manual action: structured data | Schema claims things not visible (e.g. fake reviews) | Remove false claims; submit reconsideration after fix |

## Anti-patterns

- `aggregateRating` without real, visible reviews.
- `award` without visible award context on page.
- `FAQPage` on commercial pages targeting rich results.
- `HowTo` expecting rich results.
- `SearchAction` expecting Sitelinks Searchbox.
- Multiple `Organization` entries on the same page (one canonical instance only).
- `sameAs` to broken / deprecated profiles.
- Fake `Person` reviewers to inflate trust.
- Schema injected from `useEffect`.
- `Article.author` as a string instead of a `Person` object.
- `Article.publisher.logo` as a relative URL when image needs absolute.
