# UGC-AND-MARKETPLACE-SEO

## TOC

The core tension · Index gates for UGC · Per-page-type rules · Spam-detection cadence · Site-reputation-abuse risk · Internal-link prioritization · Deletion/expired/unavailable · Tier depth selectors · Anti-patterns · Cross-links

For two-sided marketplaces, community sites, and SaaS that exposes user-contributed listings, profiles, posts, or reviews. UGC creates valuable long-tail pages but also imports spam, duplication, and legal risk onto your domain. The site-reputation-abuse policy (effective May 2024) makes this an active manual-action vector if UGC quality slips.

Phase mappings: Phase 1 (UGC inventory), Phase 3 (index discipline + spam-detection audit), Phase 5 (link-prioritization to high-quality supply), Phase 6 (gating logic), Phase 8 (spam-rate KPI), Phase 13 (compounding cleanup).

## The core tension

| Force | Push |
|---|---|
| More indexed UGC = more long-tail traffic | Pro: index everything |
| Site-reputation-abuse policy + helpful-content site signal | Con: index only quality |
| User trust on first impression | Con: index only quality |
| Crawl budget on million-URL sites | Con: index only quality |

The math: a million indexed low-quality UGC pages can drag the site-wide helpful-content classifier to suppress the *good* pages. (`confirmed` since the March 2024 helpful-content + scaled-content updates.) Indexing UGC is a quality decision, not a coverage decision.

## Index gates for UGC

Index UGC only when **all** gates pass:

| Gate | Pass criterion |
|---|---|
| Original content threshold | Page has enough first-party content to satisfy a searcher (not just template + 1 sentence) |
| Spam / scam removal velocity | Median time-to-removal for flagged content < 24 h (`likely`) |
| Thin / empty / duplicate suppression | Profiles with no content, listings with no description, duplicate posts → `noindex,follow` until populated |
| Review / rating manipulation protection | Reviews verified, throttled, and moderated; no incentivized reviews indexed without disclosure |
| Author / seller / venue value | Each contributor page has real public value, not auto-generated stub |
| Internal-link prioritization | High-quality supply gets internal links; thin supply does not |
| Lifecycle status | Deleted / expired / unavailable supply returns the right status code |

If a gate fails, the page is `noindex,follow` until it passes. **Prevent generation of indexable URLs** wherever possible — `noindex` is a signal Google still has to fetch every URL to read.

## Per-page-type rules

### Profiles (author / seller / venue / contributor)

```
URL: /u/<username> or /sellers/<id> or /venues/<slug>
```

| State | Action |
|---|---|
| New profile, no content | `noindex,follow` |
| Profile with bio + ≥ 1 published artifact | Index if quality threshold met |
| Spam / banned profile | 404 (or 410) immediately; remove from sitemap; nofollow internal links pre-removal |
| Inactive > 12 months, no listings | Reconsider: `noindex` or keep with banner |
| Verified business | Index; consider `Person` / `Organization` schema |

### Listings (jobs / properties / events / products)

| State | Action |
|---|---|
| New listing, complete fields | Index |
| New listing, missing fields | Don't generate indexable URL until complete |
| Active and updated < 30 days ago | Index |
| Expired (job filled, event past, item sold) | Status decision: `301` to closest substitute or category, or `410` if truly gone |
| Long-expired with archival value (e.g. event recap) | Keep, with banner; or move to `/archive/<id>` and noindex |

For event sites: an event in the past with a recap is content. An event in the past with no follow-up is dead inventory.

### Reviews / ratings

| Issue | Mitigation |
|---|---|
| Incentivized review without disclosure | Reject, log, signal to ML detector |
| Single-IP burst (review-bombing) | Rate limit; flag for review |
| Cross-product copy-pasted reviews | Detection cron; remove duplicates |
| Schema `aggregateRating` from manipulated data | Don't expose in schema until human-reviewed |
| Banned product still showing reviews | 410 the page; reviews go with it |

`Review` schema only when the reviews are real, visible, policy-compliant, *and* the page is the canonical home for them. Reviews aggregated from elsewhere need careful canonical decisions.

### Forum / community posts

| Issue | Mitigation |
|---|---|
| Low-quality posts (1-line, no upvotes, no replies) | `noindex` until threshold met |
| Spam / harassment / off-topic | Remove fast; `404` the URL |
| Question-without-answer | `noindex` until answered, or annotate "no accepted answer" |
| Duplicate / near-duplicate threads | Merge / link / canonical |
| Archived / closed-old | Index if substantive; `noindex` if thin |

### Marketplace / app listings (when you're the marketplace operator)

| Issue | Mitigation |
|---|---|
| App with no description, no screenshots | Don't index the listing URL |
| Suspended app | `410 Gone`; remove from category pages |
| Abandoned app (no updates > 18 months, no installs) | Surface "not maintained" banner; consider `noindex` |
| Restricted region | Honour with `availability` schema; serve relevant locale |

## Spam-detection cadence

| Cadence | Activity |
|---|---|
| Real-time | URL pattern blocklist; rate limits; new-account heuristics |
| Hourly | Image / link / phone-number heuristics on new content |
| Daily | Sample N flagged posts for human review |
| Weekly | Aggregate spam metrics; tune thresholds; sample false-positives |
| Monthly | Random audit of indexed UGC; index discipline check |
| Quarterly | Site-wide UGC quality dashboard reviewed against helpful-content classifier signals |

Spam metrics to track:

- Spam-flag-rate per supply class.
- Median time-to-removal once flagged.
- False-positive removals (creators contesting).
- New-account-to-content lag (a sign of bot-farms).
- Duplicate-content-rate across listings.
- Inbound-link spam attempts (trying to use your UGC as a link farm).

## The site-reputation-abuse risk

The policy targets third-party content hosted on a primary domain "mainly to take advantage of host signals." For UGC platforms, the question becomes:

| Pattern | Risk |
|---|---|
| Marketplace where each seller writes their own listing | Low risk — first-party seller content |
| "Sponsored content" / "partner content" sections that exist mainly for SEO | High risk |
| User-generated content that gets clear human moderation | Low risk |
| Affiliate-style "deals from partners" sections without first-party oversight | Higher risk; document moderation explicitly |
| Coupons / deals from third parties posted without verification | Higher risk |

Document the moderation pipeline publicly (methodology page) and keep it active. (`confirmed` per Google's enforcement track since May 2024.)

## Internal-link prioritization

Internal links should compound on quality supply, not every newly-created post. Pattern:

- Category / tag / hub pages link to *curated* selections, not "newest" feeds.
- "Newest" feeds: `nofollow` or `noindex` (depending on whether the feed itself has lasting value).
- Featured / verified content with `quality_score_0_1000 >= 750` gets prominent internal links.
- Sitemap by quality tier — sitemap-quality-tier-1.xml, sitemap-quality-tier-2.xml — for diagnostic visibility in GSC.

The goal: an internal link to a page implies the page is worth visiting. UGC sites that wire-link every new post discover their helpful-content signal collapse three months later. (`likely` — multi-platform pattern.)

## Deletion / expired / unavailable

| State | Status code | Why |
|---|---|---|
| User deleted their content | `404` if no replacement, `410` to confirm deletion to crawlers |
| Listing expired (job filled, event past) | `301` to closest substitute (the parent category) if substitute exists; `410` otherwise |
| Item unavailable / out of stock for long | `availability: "Discontinued"` in schema; consider `noindex` if no return planned |
| Banned account / banned content | `410`, immediately, no redirect to live content |
| Privacy-driven removal (right-to-be-forgotten) | `404` (sufficient); ensure no internal links remain |
| Account temporarily suspended | `503` with retry-after if short; `410` if permanent |

`410` tells Google "this is gone, don't bother retrying." `404` is treated similarly but with longer retry windows. Both eventually drop from the index. (`confirmed`)

## Tier depth selectors

| Tier | UGC scope |
|---|---|
| T1 | Probably no UGC; if any, index nothing until the platform has moderation |
| T2 | Index a curated subset; spam-detection cron daily; explicit quality gates |
| T3 | Tiered sitemaps; per-supply-class quality thresholds; spam dashboard; site-reputation-abuse audit quarterly |
| T4 | ML-driven `quality_score_0_1000`; per-locale moderation; per-vertical compliance (e.g. medical claims); independent audit of moderation pipeline |

## Anti-patterns

| Don't | Why | Do instead |
|---|---|---|
| Index every newly-created profile / listing / post | Helpful-content classifier suppresses the site over time | Quality gates; `noindex,follow` until threshold |
| `noindex` a million UGC URLs to "save crawl budget" | Google still fetches each to read the directive | Prevent generation; or block via `robots.txt` from the start |
| Auto-generate "Best <category> in <city>" from one listing | Doorway / scaled content | Generate only when there are ≥ N quality listings |
| Show empty profile pages with no skeletons | Soft-404 risk; thin pages | Don't generate the indexable URL until populated |
| Index forum threads with one line "thanks" | Thin pages | `noindex` until substantive |
| Schema `aggregateRating` based on incentivized reviews | Manual-action vector | Disclose incentives; only schema verified non-incentivized |
| Redirect expired listings to homepage | Soft-404 storm | `410` or `301` to closest category |
| Treat marketplace as a search-traffic-grab project | Site-reputation-abuse risk | First-party value with documented moderation |
| Hide poor moderation behind opaque "trust & safety" copy | Doesn't survive helpful-content evaluation | Public methodology page; transparent stats |
| Pay for reviews / incentivize reviews without disclosure | FTC compliance + Google policy | Honest, disclosed, moderated |
| Keep banned accounts' content "for SEO value" | Trust collapse on discovery; legal exposure | Remove and 410 |
| Internal-link from main nav to "newest posts" | Compounds noise | Link to curated / featured instead |
| Open up `/search?q=` to indexable URLs | Doorway risk | `noindex` search results |
| Mix UGC with editorial in one sitemap | Diagnostic blindness | Split sitemaps by content class |
| Treat "all profiles" as a category page | Often thin; cannibalizes individual profiles | Index only top-quality / featured / verified |
| Quote a UGC post with `Review` schema when the page is mostly chrome | Schema doesn't mirror visible content | Schema only when the review is the visible content |

## Cross-links

- [PROGRAMMATIC-GATES](PROGRAMMATIC-GATES.md) — many UGC patterns are functionally programmatic.
- [SCHEMA-POLICY](SCHEMA-POLICY.md) — `Review`, `Person`, `Event`, `JobPosting` per-type rules.
- [PHASE-3-TECHNICAL](PHASE-3-TECHNICAL.md) — UGC index discipline audit.
- [PHASE-5-IA](PHASE-5-IA.md) — internal-link prioritization to quality supply.
- [PHASE-8-ANALYTICS](PHASE-8-ANALYTICS.md) — spam metrics dashboard.
- [TRUST-INFRASTRUCTURE](TRUST-INFRASTRUCTURE.md) — moderation methodology page.
- [TRAFFIC-DROP-PLAYBOOK](TRAFFIC-DROP-PLAYBOOK.md) — UGC sites are most exposed to helpful-content drag.
