# Page brief — `<slug>`

## Brief

- **Intent**: <informational | commercial | transactional | navigational>
- **Audience**: <named ICP>
- **Funnel stage**: <awareness | evaluation | decision | post-purchase>
- **Canonical URL**: <absolute URL>
- **Owner**: <human name>
- **Refresh cadence**: <quarterly | on-product-change | on-data-update>
- **Refresh trigger**: <specific event>
- **Page type**: <pillar | cluster | pricing | comparison | integration | docs | use-case | industry>
- **Primary entity**: <named entity>
- **Supporting entities**: <list>
- **Three-plus unique data points** (citation eligibility — non-negotiable):
  1. <data point — source — date>
  2. <data point — source — date>
  3. <data point — source — date>
- **SERP analysis**: <dominant features for target query: AIO / PAA / video / image / product / local / forum>
- **Competing pages**: <top 5 ranking competitors with notes on what they do well / poorly>
- **Internal links in**: <list — must include at least one high-authority page>
- **Internal links out**: <list — must link to canonical owner pages, no through-redirect>
- **Schema type**: <WebApplication | Article | Product | etc.> + supporting (BreadcrumbList sitewide)
- **Conversion goal**: <signup | trial | demo | docs | newsletter | contact>
- **Recheck-by**: <date>

## Title + meta

- **Title** (55–60 chars, intent-matched): `<title>`
- **Meta description** (150–160 chars, ad-copy quality, lead with outcome): `<description>`
- **H1** (matches title intent; not identical): `<h1>`
- **Slug**: `<slug>`

## OG / Twitter

- **OG image**: `<absolute URL>` (auto-generated from `opengraph-image.tsx` or static)
- **OG title**: `<title>`
- **OG description**: `<description>`
- **Twitter card**: summary_large_image | summary

## Outline

- H2: <section heading — direct-answer subtopic>
  - Direct answer (≤60 words, citation-eligible)
  - Depth: <bullet points>
  - Internal link out: <slug>
- H2: ...
- H2: ...
- Final next-step CTA: <CTA text linking to <conversion target>>

## Proof requirements

- <screenshot 1: what to capture and why>
- <data point 1: where it comes from>
- <quote / endorsement 1: who, when, with permission>
- <internal benchmark / link: confirm published>

## Quality gates

- [ ] Slop-check passed (`/de-slopify` or [SLOP-CHECKLIST](../references/SLOP-CHECKLIST.md))
- [ ] All factual claims sourced
- [ ] Confidence labels per claim (`confirmed | likely | hypothesis`)
- [ ] At least three unique data points visible without JS (`scripts/ai-crawler-view.ts`)
- [ ] Brand voice matches site
- [ ] No banned slop phrases
- [ ] If high-risk topic: [HIGH-RISK-GATE](../references/HIGH-RISK-GATE.md) passed
- [ ] Schema validates against schema.org for declared type
- [ ] Conversion path clear and specific
- [ ] Page passes Lighthouse CI thresholds in staging

## Notes

<any cluster-specific context, sales/customer transcript pulls, brand voice samples>
