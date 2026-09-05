# Source log

Format for `analyses/source-log.md` — the verification audit trail required by [VERIFICATION-FIRST](../references/VERIFICATION-FIRST.md). Every volatile claim that ships into a recommendation, audit item, brief, or decision card is logged here with primary source, retrieval date, and confidence label. Cross-referenced from [GUIDE-RECONCILIATION](../references/GUIDE-RECONCILIATION.md) when the live source disagrees with `multi_agent_seo_guide.md`.

Append-only. Corrections go in as new entries that supersede prior ones (cite the entry being superseded in `notes`).

## Per-entry format

```md
### <YYYY-MM-DD> — <one-line claim>

- **Claim**: <what is being supported>
- **Primary source**: <URL>
- **Retrieved**: <YYYY-MM-DD HH:MM TZ>
- **Key quote / fact**: <verbatim, ≤300 chars; longer summarized with link to archived snapshot>
- **Used in**: <AUDIT-####>, <DC-####>, <brief path>, <decision/PR>
- **Confidence**: confirmed | likely | hypothesis (per [EVIDENCE-LABELS](../references/EVIDENCE-LABELS.md))
- **Recheck-by**: <YYYY-MM-DD>
- **Notes**: <discrepancy with guide? archived snapshot path? supersedes earlier entry?>
```

## Required fields

Every entry has all eight fields. If you cannot fill `key quote` because the source isn't quotable (e.g. an interactive tool), record the screenshot path under `notes` and a one-sentence summary as the quote. If you cannot reach a primary source, the claim does not ship — escalate to the user.

## Example entries

```md
### 2026-04-30 — INP `good` threshold is 200 ms p75

- Claim: A page meets Google's "good" Core Web Vitals INP target when 75 % of its interactions complete within 200 ms.
- Primary source: https://web.dev/articles/inp
- Retrieved: 2026-04-30 14:02 PT
- Key quote: "A page meets the recommended target if 75% of its interactions have an INP of 200 milliseconds or less."
- Used in: AUDIT-0123, AUDIT-0145, DC-0012
- Confidence: confirmed
- Recheck-by: 2026-10-30
- Notes: Aligns with guide §6 framing; thresholds reinforced in GUIDE-RECONCILIATION INP / Core Web Vitals row.

### 2026-04-30 — `HowTo` rich result is deprecated

- Claim: Google deprecated `HowTo` rich results; the markup remains valid schema but no longer eligible for the visual treatment.
- Primary source: https://developers.google.com/search/docs/appearance/structured-data/how-to
- Retrieved: 2026-04-30 14:18 PT
- Key quote: "HowTo structured data is no longer used. Removing the markup will not affect Search performance."
- Used in: AUDIT-0231 (remove HowTo from /docs/<feature>), SCHEMA-POLICY review
- Confidence: confirmed
- Recheck-by: 2027-04-30
- Notes: Aligns with GUIDE-RECONCILIATION Schema policy row.

### 2026-04-30 — AI Overview citation overlap is a volatile market observation

- Claim: A disclosed-methodology third-party study observed stronger domain-level than URL-level correlation between organic ranking and AIO citation for its sampled queries. Do not treat the exact percentages as evergreen.
- Primary source: <citation study URL — early 2026 multi-vendor analysis, methodology disclosed>
- Retrieved: 2026-04-30 14:33 PT
- Key quote: "92.4% of cited domains had at least one URL ranking in the top 10 for the original query, while 37.6% of cited URLs themselves ranked in the top 10."
- Used in: AI-VISIBILITY, GUIDE-RECONCILIATION AI Overviews / AI Mode row, brief priority for `analyses/clusters/<cluster>.md`
- Confidence: likely
- Recheck-by: 2026-07-30 (volatile; AI surface behaviour changes quarterly)
- Notes: Methodology disclosed; corroborated by one peer study. Treat downstream recommendations as `likely`. If methodology, geography/device, sample size, or query set are missing, downgrade the exact numbers to `hypothesis` and keep only the qualitative operator.

### 2026-04-30 — Back-button hijacking is a malicious-practices spam-policy violation

- Claim: Browser-history manipulation that prevents Back from returning users to the previous page is an explicit Google malicious-practices spam-policy violation.
- Primary source: https://developers.google.com/search/blog/2026/04/back-button-hijacking
- Retrieved: 2026-04-30 18:45 ET
- Key quote: "Back button hijacking breaks this fundamental expectation."
- Used in: Phase 10 QA, Phase 12 verification, PROGRAMMATIC-GATES, release-day tripwire
- Confidence: confirmed
- Recheck-by: 2026-10-30
- Notes: Cross-check spam policies page for current wording before enforcement-sensitive recommendations.

### 2026-04-30 — Next.js metadata API supports per-route `metadata` export and `generateMetadata`

- Claim: Next.js App Router exposes `export const metadata` and `export async function generateMetadata` in route segments for title, description, canonical, OG, robots, and `alternates.languages`.
- Primary source: https://nextjs.org/docs/app/api-reference/functions/generate-metadata (version 16.x in `package.json`)
- Retrieved: 2026-04-30 14:51 PT
- Key quote: "You can either statically define the metadata object, or dynamically generate it based on route or async data using the generateMetadata function."
- Used in: deliverables/prs/seo-per-route-metadata.md, NEXTJS-PATTERNS
- Confidence: confirmed
- Recheck-by: 2026-10-30 or on Next.js major version bump
- Notes: Verified against `package.json` Next.js version. Re-verify on each upgrade.
```

## Triggers (when to log)

Log an entry whenever a recommendation depends on a row from the [VERIFICATION-FIRST](../references/VERIFICATION-FIRST.md) trigger table:

- CWV thresholds and page-experience claims
- Helpful Content / scaled content / site reputation abuse / expired domain spam policies
- Specific structured-data type eligibility
- Search Console feature, export, or BigQuery behaviour
- AI Overview / AI Mode citation behaviour
- Next.js metadata / sitemap / robots / `next/og` API
- Vercel Cache Components / Edge Config behaviour
- FTC endorsement / disclosure rules
- Robots.txt specification edge cases

Also log when a recommendation depends on a *third-party study* — methodology, sample size, dates required.

## Cross-reference with GUIDE-RECONCILIATION

If the source contradicts `multi_agent_seo_guide.md`:

1. Log the entry here with the discrepancy noted.
2. Open / update the matching row in [GUIDE-RECONCILIATION](../references/GUIDE-RECONCILIATION.md) — claim from guide, current evidence, action.
3. Update the affected reference docs and downstream recommendations.
4. Do not silently override the guide. The audit trail is the audit trail.

## Recheck cadence guidance

| Source class | Recheck cadence |
|---|---|
| Google Search Central / web.dev policy pages | 6 months |
| Schema.org type definitions | 12 months |
| Next.js / framework API surface | per major version bump or 6 months |
| AI surface behaviour studies | 3 months (volatile) |
| Search Console feature docs | 6 months |
| FTC / regulatory guidance | 12 months or on rule update |

Set `recheck-by` accordingly. Recheck-by passing without re-verification = the recommendation downgrades to `hypothesis` until re-verified.

## Anti-patterns

- **Citing a secondary source.** SEO blog summarizing Google docs is not primary. Read the doc itself ([VERIFICATION-FIRST](../references/VERIFICATION-FIRST.md) defines acceptable primary sources).
- **Stale entries that never recheck.** A 14-month-old `confirmed` entry on a volatile topic (AIO, CWV thresholds, schema eligibility) is functionally `hypothesis`.
- **Logging without `used in`.** An entry not connected to a downstream artifact is decorative; the connection is the audit trail.
- **Quoting paraphrased text.** The quote is verbatim. Summaries belong in `notes`.
- **No recheck-by**. Without it the entry never gets re-verified.
- **Editing past entries.** Append-only. Corrections supersede with a new entry that cites the entry it replaces.

## Cross-references

- [VERIFICATION-FIRST](../references/VERIFICATION-FIRST.md), [EVIDENCE-LABELS](../references/EVIDENCE-LABELS.md), [GUIDE-RECONCILIATION](../references/GUIDE-RECONCILIATION.md)
- [DECISION-CARD](DECISION-CARD.md), [AUDIT-ITEM-TEMPLATE](AUDIT-ITEM-TEMPLATE.md), [BRIEF-TEMPLATE](BRIEF-TEMPLATE.md)
