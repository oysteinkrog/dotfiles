# SCHEMA-COOKBOOK

Copy-paste-ready JSON-LD blocks for SaaS pages. Each block ships with rules, common bugs, and validation tips. Schema must mirror visible content; see [SCHEMA-POLICY](SCHEMA-POLICY.md) for the policy. This file is the operational complement.

## Phase mapping

| Phase | Use this doc for |
|---|---|
| 3 — Technical | Audit current schema; fix template bugs. |
| 6 — Implementation | Insert correct JSON-LD into Server Components. |
| 10 — Fresh-eyes | Validate schema mirrors visible content per priority page. |
| 12 — Verify | Post-deploy schema check against representative URLs. |

## Server-render only

```tsx
// app/components/JsonLd.tsx
export function JsonLd({ data }: { data: object }) {
  return (
    <script
      type="application/ld+json"
      dangerouslySetInnerHTML={{ __html: JSON.stringify(data) }}
    />
  );
}
```

`anti-pattern`: injecting from `useEffect`. AI bots and Google's static-HTML pass miss it. See [NEXTJS-PATTERNS](NEXTJS-PATTERNS.md).

## 1. `Organization` (root layout)

Site-wide. Place in `app/layout.tsx`. The single canonical `Organization` instance for the whole site.

```json
{
  "@context": "https://schema.org",
  "@type": "Organization",
  "@id": "https://www.example.com/#organization",
  "name": "Acme",
  "alternateName": "Acme Inc",
  "url": "https://www.example.com",
  "logo": {
    "@type": "ImageObject",
    "url": "https://www.example.com/logo.png",
    "width": 512,
    "height": 512
  },
  "description": "Acme automates SOC 2 evidence collection for SaaS companies.",
  "foundingDate": "2024-01-01",
  "founder": [
    { "@type": "Person", "name": "Jane Doe", "url": "https://www.example.com/about/jane-doe" }
  ],
  "contactPoint": [{
    "@type": "ContactPoint",
    "contactType": "customer support",
    "email": "support@example.com",
    "url": "https://www.example.com/contact",
    "availableLanguage": ["English"]
  }],
  "sameAs": [
    "https://github.com/acme",
    "https://x.com/acme",
    "https://www.linkedin.com/company/acme",
    "https://www.crunchbase.com/organization/acme",
    "https://www.producthunt.com/products/acme"
  ]
}
```

| Bug | Fix |
|---|---|
| Multiple `Organization` blocks across pages | One canonical instance via root layout; do not re-emit on child pages. |
| `logo` as relative URL | Always absolute. Required absolute by Google. |
| `sameAs` to broken / deprecated profiles | Audit quarterly; remove dead links. |
| Mixing `@type: "Corporation"` and `Organization` across pages | Pick one; `Organization` is the safer parent type. |

## 2. `WebSite` (root layout)

```json
{
  "@context": "https://schema.org",
  "@type": "WebSite",
  "@id": "https://www.example.com/#website",
  "name": "Acme",
  "url": "https://www.example.com",
  "publisher": { "@id": "https://www.example.com/#organization" },
  "inLanguage": "en-US"
}
```

`anti-pattern`: adding `potentialAction.SearchAction` for Sitelinks Searchbox — feature retired (`confirmed`). Do not include.

## 3. `WebApplication` (pricing / feature pages)

Prefer `WebApplication` over `SoftwareApplication` for cloud-delivered SaaS.

```json
{
  "@context": "https://schema.org",
  "@type": "WebApplication",
  "@id": "https://www.example.com/pricing#webapp",
  "name": "Acme",
  "applicationCategory": "BusinessApplication",
  "applicationSubCategory": "Compliance Automation",
  "operatingSystem": "Any (web-based)",
  "browserRequirements": "Requires JavaScript and a modern browser",
  "url": "https://www.example.com",
  "description": "...",
  "publisher": { "@id": "https://www.example.com/#organization" },
  "offers": [
    {
      "@type": "Offer",
      "name": "Starter",
      "price": "29",
      "priceCurrency": "USD",
      "url": "https://www.example.com/pricing#starter",
      "priceSpecification": {
        "@type": "UnitPriceSpecification",
        "price": "29",
        "priceCurrency": "USD",
        "unitText": "MONTH",
        "billingIncrement": 1
      },
      "availability": "https://schema.org/InStock"
    },
    {
      "@type": "Offer",
      "name": "Pro",
      "price": "99",
      "priceCurrency": "USD",
      "url": "https://www.example.com/pricing#pro",
      "priceSpecification": {
        "@type": "UnitPriceSpecification",
        "price": "99",
        "priceCurrency": "USD",
        "unitText": "MONTH"
      },
      "availability": "https://schema.org/InStock"
    },
    {
      "@type": "Offer",
      "name": "Enterprise",
      "price": "0",
      "priceCurrency": "USD",
      "url": "https://www.example.com/pricing#enterprise",
      "description": "Custom pricing; contact sales.",
      "priceSpecification": {
        "@type": "UnitPriceSpecification",
        "price": "0",
        "priceCurrency": "USD",
        "unitText": "MONTH"
      }
    }
  ]
}
```

| Bug | Fix |
|---|---|
| Schema price ≠ visible price | Read schema and visible price from same source (e.g. CMS plan record). |
| `Offer.price` as a number not a string | Use string per Google docs. |
| `availability` missing on a "Contact sales" plan | Use a descriptive `description` field; omit `availability` rather than fake `InStock`. |
| Adding `aggregateRating` without real visible reviews | Don't (`anti-pattern`; manual-action risk). |

## 4. `Article` (blog / changelog / customer story)

```json
{
  "@context": "https://schema.org",
  "@type": "Article",
  "@id": "https://www.example.com/blog/soc2-checklist-2026#article",
  "headline": "SOC 2 evidence checklist for SaaS in 2026",
  "description": "47-item checklist with sources, control mapping, and refresh cadence.",
  "image": [
    "https://www.example.com/blog/soc2-checklist-2026/hero-1200x630.png",
    "https://www.example.com/blog/soc2-checklist-2026/hero-1200x900.png",
    "https://www.example.com/blog/soc2-checklist-2026/hero-1200x1200.png"
  ],
  "datePublished": "2026-04-30T08:00:00-04:00",
  "dateModified": "2026-04-30T08:00:00-04:00",
  "author": {
    "@type": "Person",
    "@id": "https://www.example.com/authors/jane-doe#person",
    "name": "Jane Doe",
    "url": "https://www.example.com/authors/jane-doe"
  },
  "publisher": { "@id": "https://www.example.com/#organization" },
  "mainEntityOfPage": {
    "@type": "WebPage",
    "@id": "https://www.example.com/blog/soc2-checklist-2026"
  },
  "articleSection": "Compliance",
  "keywords": ["SOC 2", "evidence collection", "compliance automation"],
  "wordCount": 2310
}
```

| Bug | Fix |
|---|---|
| `author` as a string | Use a `Person` object with `@id` and `url` so it links to a real bio. |
| `datePublished` updated on every build | Only on actual publish; preserves freshness signal. |
| `image` as a single non-1200×630 image | Provide three aspect ratios per Google docs; minimum 1200px wide. |
| `headline` > 110 characters | Trim; 110 is the documented soft cap. |
| Changelog entries with no dateModified | Add; changelog freshness matters more than blog freshness for SaaS. |

## 5. `BreadcrumbList` (sitewide)

One per page that has a visible breadcrumb. Mirrors the breadcrumb exactly.

```json
{
  "@context": "https://schema.org",
  "@type": "BreadcrumbList",
  "itemListElement": [
    { "@type": "ListItem", "position": 1, "name": "Home", "item": "https://www.example.com" },
    { "@type": "ListItem", "position": 2, "name": "Integrations", "item": "https://www.example.com/integrations" },
    { "@type": "ListItem", "position": 3, "name": "Notion", "item": "https://www.example.com/integrations/notion" }
  ]
}
```

| Bug | Fix |
|---|---|
| Final item links somewhere | Final item should still have `item` set to the current canonical URL (per Google docs). |
| Trailing slash mismatch with canonical | Match canonical exactly. |
| Hidden breadcrumb (CSS) but schema present | Schema must mirror *visible* content. Either show breadcrumb or drop schema. |

## 6. `Person` (author page)

Place on `/authors/<slug>` or wherever the canonical bio lives.

```json
{
  "@context": "https://schema.org",
  "@type": "Person",
  "@id": "https://www.example.com/authors/jane-doe#person",
  "name": "Jane Doe",
  "jobTitle": "CEO and Co-founder, Acme",
  "worksFor": { "@id": "https://www.example.com/#organization" },
  "url": "https://www.example.com/authors/jane-doe",
  "image": "https://www.example.com/authors/jane-doe.jpg",
  "description": "Jane Doe leads Acme. Previously security engineer at StripeCo (2019–2024).",
  "sameAs": [
    "https://www.linkedin.com/in/jane-doe",
    "https://x.com/janedoe",
    "https://github.com/janedoe"
  ],
  "alumniOf": { "@type": "EducationalOrganization", "name": "MIT" }
}
```

| Bug | Fix |
|---|---|
| `Person` only on blog post, not on a real bio page | Build a real `/authors/<slug>` page; bots reconcile entities across the site. |
| Bio inconsistent across LinkedIn / Crunchbase / page | Canonicalize; see [CITATION-OPS](CITATION-OPS.md) entity reconciliation. |
| Made-up authors (LLM bylines) | `anti-pattern`; manual-action risk and citation poison. |

## 7. `Course` (academy / learning paths)

Use only on real courses with structured learning content.

```json
{
  "@context": "https://schema.org",
  "@type": "Course",
  "@id": "https://www.example.com/academy/soc2-fundamentals#course",
  "name": "SOC 2 fundamentals",
  "description": "Six-module path covering scope, controls, evidence, and audit.",
  "provider": { "@id": "https://www.example.com/#organization" },
  "educationalLevel": "Beginner",
  "inLanguage": "en-US",
  "hasCourseInstance": {
    "@type": "CourseInstance",
    "courseMode": "online",
    "courseWorkload": "PT4H"
  },
  "offers": {
    "@type": "Offer",
    "category": "Free",
    "price": "0",
    "priceCurrency": "USD",
    "url": "https://www.example.com/academy/soc2-fundamentals"
  }
}
```

`hasCourseInstance` and `offers` are required for current Google Course rich result eligibility (`confirmed`, per Google docs).

## 8. `Dataset` (public benchmarks)

For pages that publish a real, downloadable, citable dataset.

```json
{
  "@context": "https://schema.org",
  "@type": "Dataset",
  "@id": "https://www.example.com/benchmarks/soc2-timing#dataset",
  "name": "SOC 2 Type II completion timing benchmarks (2026-Q1)",
  "description": "Anonymized completion timing across 312 SaaS customers, Q1 2026.",
  "url": "https://www.example.com/benchmarks/soc2-timing",
  "sameAs": "https://www.example.com/benchmarks/soc2-timing.csv",
  "license": "https://creativecommons.org/licenses/by/4.0/",
  "keywords": ["SOC 2", "compliance timing", "benchmark"],
  "creator": { "@id": "https://www.example.com/#organization" },
  "datePublished": "2026-04-15",
  "dateModified": "2026-04-15",
  "distribution": [
    {
      "@type": "DataDownload",
      "encodingFormat": "text/csv",
      "contentUrl": "https://www.example.com/benchmarks/soc2-timing.csv"
    }
  ],
  "temporalCoverage": "2026-01-01/2026-03-31",
  "spatialCoverage": "Global"
}
```

Datasets are link magnets for AI citation. Treat each public dataset as a [PRODUCT-LED-SEO](PRODUCT-LED-SEO.md) asset.

## 9. `JobPosting` (careers)

```json
{
  "@context": "https://schema.org",
  "@type": "JobPosting",
  "@id": "https://www.example.com/careers/staff-platform-engineer#job",
  "title": "Staff Platform Engineer",
  "description": "<p>Full HTML description as it appears on the page...</p>",
  "datePosted": "2026-04-22",
  "validThrough": "2026-06-22T23:59:59-07:00",
  "employmentType": "FULL_TIME",
  "hiringOrganization": { "@id": "https://www.example.com/#organization" },
  "jobLocationType": "TELECOMMUTE",
  "applicantLocationRequirements": [
    { "@type": "Country", "name": "United States" }
  ],
  "baseSalary": {
    "@type": "MonetaryAmount",
    "currency": "USD",
    "value": {
      "@type": "QuantitativeValue",
      "minValue": 220000,
      "maxValue": 280000,
      "unitText": "YEAR"
    }
  },
  "directApply": true
}
```

| Bug | Fix |
|---|---|
| `description` as plain text without HTML | Google expects HTML. Use `<p>`, `<ul>`. |
| `validThrough` missing | Required. Google warnings emit when missing. |
| Closed job still indexed | Add `noindex` and remove from sitemap when closed; do not leave stale posting structured data. |
| Remote job with no location | Use `jobLocationType: "TELECOMMUTE"` and `applicantLocationRequirements`. |

## 10. `Event` (webinars, conferences)

```json
{
  "@context": "https://schema.org",
  "@type": "Event",
  "@id": "https://www.example.com/webinars/soc2-2026-05#event",
  "name": "SOC 2 in 2026: what auditors actually want",
  "startDate": "2026-05-15T17:00:00-04:00",
  "endDate": "2026-05-15T18:00:00-04:00",
  "eventAttendanceMode": "https://schema.org/OnlineEventAttendanceMode",
  "eventStatus": "https://schema.org/EventScheduled",
  "location": {
    "@type": "VirtualLocation",
    "url": "https://www.example.com/webinars/soc2-2026-05"
  },
  "image": "https://www.example.com/webinars/soc2-2026-05/share.png",
  "description": "Live webinar with Q&A.",
  "organizer": { "@id": "https://www.example.com/#organization" },
  "offers": {
    "@type": "Offer",
    "url": "https://www.example.com/webinars/soc2-2026-05/register",
    "price": "0",
    "priceCurrency": "USD",
    "availability": "https://schema.org/InStock",
    "validFrom": "2026-04-15T00:00:00-04:00"
  }
}
```

After the event ends, change `eventStatus` to `EventScheduled` (if rescheduled) or `EventCancelled` / set page to `noindex` if no replay.

## 11. `FAQPage` (rare; eligibility restricted)

`confirmed`: FAQ rich results are restricted to authoritative government / health sites since 2023. For commercial SaaS pages, FAQ schema rarely produces visible rich results. *Don't add it as a rich-result tactic*; only add it where the page is genuinely a FAQ.

```json
{
  "@context": "https://schema.org",
  "@type": "FAQPage",
  "mainEntity": [
    {
      "@type": "Question",
      "name": "Does Acme support SAML SSO?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "Yes. SAML SSO is included on Pro and Enterprise plans. Configuration takes ~10 minutes via /settings/sso."
      }
    },
    {
      "@type": "Question",
      "name": "Is Acme HIPAA-eligible?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "Yes. BAA available on Enterprise. See /security/hipaa."
      }
    }
  ]
}
```

`anti-pattern`: turning every commercial page into a fake FAQ to win schema. Removed by Google enforcement, hurts trust signals.

## 12. `VideoObject` (embedded product videos)

Only when the video is visibly embedded.

```json
{
  "@context": "https://schema.org",
  "@type": "VideoObject",
  "name": "Connecting Acme to Notion in 5 minutes",
  "description": "Step-by-step video showing OAuth, scope selection, and first sync.",
  "thumbnailUrl": [
    "https://www.example.com/integrations/notion/video-thumb-1280x720.png"
  ],
  "uploadDate": "2026-04-20T10:00:00-04:00",
  "duration": "PT5M12S",
  "contentUrl": "https://cdn.example.com/videos/notion-setup.mp4",
  "embedUrl": "https://www.youtube.com/embed/abc123",
  "publisher": { "@id": "https://www.example.com/#organization" }
}
```

| Bug | Fix |
|---|---|
| `duration` in seconds | Use ISO 8601: `PT5M12S`. |
| Single thumbnail in 4:3 | Provide 16:9 minimum 1280×720 for Video rich results. |
| Schema present but video lazy-loaded behind a click placeholder | Either embed the player at load (with poster) or drop the schema. |

## 13. `Review` (genuine, moderated, visible)

Use only when the review is real, visible on the page, by a real reviewer, not aggregated from third parties.

```json
{
  "@context": "https://schema.org",
  "@type": "Review",
  "itemReviewed": {
    "@type": "WebApplication",
    "name": "Notion",
    "applicationCategory": "ProductivityApplication"
  },
  "author": {
    "@type": "Person",
    "name": "Jane Doe",
    "url": "https://www.example.com/authors/jane-doe"
  },
  "datePublished": "2026-04-22",
  "reviewRating": {
    "@type": "Rating",
    "ratingValue": "4",
    "bestRating": "5"
  },
  "reviewBody": "Notion is excellent for documentation but limited for...",
  "publisher": { "@id": "https://www.example.com/#organization" }
}
```

`anti-pattern`: aggregating G2 / Capterra / Trustpilot ratings into `aggregateRating` on your own page. Manual-action risk under Google's review-snippet guidelines. Use only first-party, visible, moderated reviews. (`confirmed`)

## Common cross-template bugs

| Bug | Detection | Fix |
|---|---|---|
| Two `@type: "Organization"` blocks (root + a marketing page repeats) | Search rendered HTML for `Organization` count > 1 | Use `@id` references; emit `Organization` only in root layout. |
| Relative URLs in schema | grep for `\"url\":\\s*\"/` in JSON-LD output | Always absolute. |
| `dateModified` updated on every deploy | Diff `lastModified` over consecutive builds | Only update on real content change. |
| Schema validates but doesn't match visible page | Manual side-by-side review | Make schema read from same source as page render. |
| `@id` used inconsistently | `@id` on Organization but not on WebSite, etc. | Use `@id` on every long-lived entity; reference via `@id` rather than re-emitting. |
| Schema injected client-side | Curl raw HTML; count `application/ld+json` | Move to Server Component. |

## Validation tips

`scripts/validate-schema.ts` should:

1. Fetch URL with `Googlebot` user-agent.
2. Extract every `<script type="application/ld+json">`.
3. JSON-parse each (catch syntax errors first).
4. For each `@type`, validate against schema.org current types.
5. For known Google-supported types (Article, Product, JobPosting, Event, Course, Dataset, BreadcrumbList, VideoObject, Review, Organization, WebSite, WebApplication), validate required + recommended properties.
6. Cross-check schema price/title/date against visible HTML (best-effort).
7. Emit a per-URL pass/fail report. Block PR merge on fail.

External tools (use as a second opinion, not as primary):

- `https://validator.schema.org` — type/property validation, not Google rich-result eligibility.
- Google's Rich Results Test — current Google eligibility check.
- GSC Enhancements report — production state, lagging signal.

## Per-page JSON-LD inventory (T2+)

Maintain `analyses/schema-inventory.csv`:

| URL | Types declared | Types validated | Last checked | Mirrors visible? |
|---|---|---|---|---|
| `/` | Organization, WebSite | yes | 2026-04-22 | yes |
| `/pricing` | WebApplication+Offer | yes | 2026-04-22 | yes |
| `/blog/soc2` | Article+Person | yes | 2026-04-22 | yes |
| `/integrations/notion` | WebApplication, BreadcrumbList | partial — `Offer` price stale | 2026-04-22 | NO — schema price ≠ visible |
| `/about` | Organization (DUPLICATE — root already emits) | NO | 2026-04-22 | duplicate |

## Anti-patterns

- Adding schema "in case it helps" without an actual feature target.
- Schema declared but visible content removed (drift).
- `aggregateRating` without real, visible, first-party reviews.
- Multiple `Organization` entries across pages.
- `Article.author` as string.
- `HowTo` for visible rich results (`confirmed` deprecated).
- `SearchAction` / Sitelinks Searchbox (`confirmed` retired).
- FAQPage on commercial pages targeting rich results.
- Schema injected via `useEffect`.
- Using `Product` for cloud SaaS plan; prefer `WebApplication` + `Offer`.
- Logos, prices, dates in schema that disagree with the page.

## Cross-references

- [SCHEMA-POLICY](SCHEMA-POLICY.md) — policy, deprecations, retired features.
- [NEXTJS-PATTERNS](NEXTJS-PATTERNS.md) — Server-Component injection pattern.
- [CITATION-OPS](CITATION-OPS.md) — entity reconciliation; schema as a citation surface.
- [PROGRAMMATIC-GATES](PROGRAMMATIC-GATES.md) — schema + AI visibility gate for programmatic templates.
- [ANTI-PATTERNS](ANTI-PATTERNS.md) — full anti-pattern catalog.
- [EVIDENCE-LABELS](EVIDENCE-LABELS.md) — confidence/severity grammar.
