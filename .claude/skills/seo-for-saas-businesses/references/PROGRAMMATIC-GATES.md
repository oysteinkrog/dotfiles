# PROGRAMMATIC-GATES

Programmatic SEO compounds when each page has unique, useful, maintained information. It poisons the domain when pages are token-swap doorways. Since the March 2024 *scaled-content-abuse* policy and the *site-reputation-abuse* policy effective May 2024, the cost of a bad programmatic launch is the whole template demoted *and* the helpful-content classifier dragging the rest of the site.

Treat the gates below as ship-blockers, not advice.

## Gate 1 — Real underlying data

The dataset must support genuine per-page differentiation:

- [ ] The data source has at least 5 distinct fields per page that meaningfully differ.
- [ ] At least 80 % of candidate pages have non-empty values for every required field.
- [ ] The 20 % with missing fields suppress (do not publish) rather than emit stub pages.
- [ ] Each page has data the reader cannot trivially get elsewhere (or where the differentiator is the curation, freshness, or first-hand validation).

If the dataset is "city × product name", that is not differentiation. That is token swap.

## Gate 2 — Per-page user value

Each page passes:

- [ ] Stands alone as useful for someone who landed only on this page.
- [ ] Has at least one piece of unique evidence (screenshot, dated quote, internal benchmark, original analysis).
- [ ] Has a clear next action (try, book, compare, read, contact).
- [ ] Has a defined refresh cadence and trigger.

Walk a sample of 20 generated pages manually. If even one feels like a doorway, the dataset is too thin for indexation.

## Gate 3 — Maintenance contract

Before publishing, the team commits to:

- [ ] Owner per template family (named human).
- [ ] Refresh cadence per page type (monthly / quarterly / on-trigger).
- [ ] Refresh trigger source (CMS field updated, dataset refresh, product release, manual review queue).
- [ ] Quality dashboard tracking impressions, CTR, position, conversion, and complaint rate per template.
- [ ] Process for delisting individual pages that go stale.

Without this, the template ages into spam.

## Gate 4 — Index discipline

- [ ] Self-canonical on every indexable page.
- [ ] Sitemap includes only canonical indexable URLs.
- [ ] Filter / sort / parameter URLs are not crawlable or are explicitly canonicalized.
- [ ] Empty / missing-data variants suppress, not noindex (preventing generation > noindexing after the fact).
- [ ] Internal links promote high-value variants, not every variant.

## Gate 5 — Staged rollout

Never launch the whole template family at once.

| Stage | Volume | Wait | Decision check |
|---|---|---|---|
| 1 | 10–25 pages | 14 days | Crawled? Indexed? Useful in GSC URL inspection? Manual review of 5 random samples? |
| 2 | +100 pages | 14 days | Impressions / position / CTR show real demand? Index-state stable? Quality maintained? |
| 3 | +500 pages | 28 days | Conversion signal? Decay queue empty? No "duplicate without canonical" cluster? |
| 4 | full rollout | — | All quality gates green; rollback procedure tested |

Kill switch (must work before stage 1):

- One-flag rollback that:
  - Removes the template's URLs from sitemap.
  - Adds `noindex,follow` (kept crawlable so Google sees the directive).
  - Optionally `301`s to the closest non-programmatic parent.
- Tested in staging before stage 1 launches.

## Gate 6 — Spam-policy tripwire check

Before stage 1, run through:

| Tripwire | Failure looks like | Pass means |
|---|---|---|
| Scaled content abuse | "Many pages whose primary purpose is search manipulation" | Per-page user value (Gate 2) demonstrably present |
| Site reputation abuse | Third-party content hosted to exploit your domain reputation | Pages are first-party; if partner-authored, "first-party oversight or involvement" is documented |
| Doorway pages | Pages funneling users to the same destination without unique value | Each page has unique CTA, unique answer, or unique inventory |
| Expired-domain abuse | Repurposing acquired domain content | N/A unless mergers/migrations involved |
| Thin affiliate | Pages adding nothing beyond merchant feed | Original analysis, dated commentary, or genuine first-hand testing |
| Back-button hijacking | Template inserts deceptive history entries, traps Back, or redirects users away from the page they came from | Browser Back immediately returns to the previous page; pushState/replaceState use is route-faithful and tested |

## Gate 7 — Anti-cannibalization

For each template:

- [ ] What query family does this template own?
- [ ] Is there an existing pillar / category / hub that already owns or partly owns it?
- [ ] If yes, is the relationship pillar→cluster (acceptable) or competitor (not acceptable)?
- [ ] What anchor text routes between them?

Cannibalization is the single most common quiet failure of programmatic launches. The anti-cannibalization map (Phase 2) gates this.

## Gate 8 — AI visibility

If the SaaS depends on AI Overview / ChatGPT / Perplexity citations, AI bots see only initial HTML. Programmatic templates often use heavy client-side data fetching that breaks AI visibility while staying fine for Googlebot.

- [ ] Each generated page has its evidence in initial HTML.
- [ ] JSON-LD is server-rendered.
- [ ] At least three unique data points per page visible without JS.

## Common patterns that *do* work

| Pattern | Why it works |
|---|---|
| Integration pages with real setup steps | Genuine per-integration differentiation; user evidence; refresh on partner change |
| Comparison pages with dated competitor claims | Editorial work + first-hand validation |
| Programmatic templates / examples / generators | Each output is unique; user value clear |
| Local pages where there *is* real local presence | Real inventory, hours, photos, reviews |
| Industry / use-case pages with unique workflows | Domain expertise expressed per industry |
| Glossary terms with original explainers + interactive examples | Clear demand × clear value |

## Common patterns that *don't* work

| Pattern | Why it fails |
|---|---|
| `<city> + <product>` location pages without local presence | Doorway; no unique value |
| `<integration> for <industry>` matrix where most variants are stub | Fails Gate 1 + Gate 2 |
| Generated comparison pages with no original analysis | Site reputation abuse / scaled content |
| Job-listing aggregations without first-party data | Often soft-404s + thin pages |
| AI-summarized competitor pages | Slop + fabricated competitor limitations |
| Calendar / date / pagination without uniqueness per page | Crawl trap |

## Pre-launch checklist (one row → ship)

| # | Gate | Pass? |
|---|---|---|
| 1 | Real underlying data |  |
| 2 | Per-page user value |  |
| 3 | Maintenance contract signed |  |
| 4 | Index discipline configured |  |
| 5 | Staged rollout plan + kill switch tested |  |
| 6 | Spam-policy tripwires reviewed |  |
| 7 | Anti-cannibalization map reviewed |  |
| 8 | AI visibility check |  |

If any row is empty, do not launch. Lower the launch volume, improve the dataset, or skip the template.
