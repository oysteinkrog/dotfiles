# CRAWL-BUDGET

Crawl budget is the rate at which Google fetches pages on a site. It only meaningfully constrains *large, fast-changing, or technically problematic* sites. For most SaaS marketing sites, "crawl budget" worry is a distraction. This document tells you when it does matter, what to do, and what is unhelpful work disguised as crawl optimization.

## Phase mapping

| Phase | Use this doc for |
|---|---|
| 1 — Discovery | Determine if crawl budget is a real concern (it usually isn't). |
| 3 — Technical | If concern is real: useful work to do. |
| 12 — Verify | Did Googlebot fetch the changed URLs? |

## When crawl budget actually matters

Per Google's official guidance (`confirmed`): crawl budget is a concern for sites with **at least one** of:

| Trigger | Threshold |
|---|---|
| Large URL count | > 10,000 indexable URLs |
| Fast-changing inventory | New content daily; stale-on-crawl is real |
| Faceted nav generating combinatorial URLs | See [FACETED-NAV](FACETED-NAV.md) |
| Server reliability issues | 5xx rate ≥ 1 % for Googlebot |
| Slow server response | p95 response time > 1 s for Googlebot |

If none of these apply: crawl budget is *not* the bottleneck. Don't tune it; tune content quality and signals.

| Tier | Crawl budget concern? |
|---|---|
| T1 | No |
| T2 | Rarely |
| T3 | Often |
| T4 | Always |

## What useful work looks like

### 1. Sitemap freshness

`confirmed`: Google uses sitemap `lastmod` as a hint, not a guarantee.

| Useful | Unhelpful |
|---|---|
| Update `lastmod` only when the page meaningfully changed | Update `lastmod` to `now()` on every build |
| Include only canonical, indexable, 200-status URLs | Include 301'd, 404, noindex, or canonicalized-away URLs |
| Split into multiple sub-sitemaps by section | One giant sitemap above 50k URL / 50 MB limit |
| Compressed (`.xml.gz`) for large sites | Plain XML > 50 MB |
| Reference from `/robots.txt` | Submit only via GSC, no robots reference |

```ts
// app/sitemap.ts — only include real lastmod
export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  const posts = await getPosts(); // includes a real `updatedAt`
  return posts.map((p) => ({
    url: `https://www.example.com/blog/${p.slug}`,
    lastModified: p.updatedAt, // not new Date()
    changeFrequency: "monthly" as const,
    priority: 0.7,
  }));
}
```

### 2. Real 404 / 410, no soft-404s

`confirmed`: soft-404s (200 status with "not found" content) waste crawl budget *and* hurt the helpful-content signal.

| Symptom | Fix |
|---|---|
| Custom 404 page returns 200 | Return 404 from `not-found.tsx` |
| Empty search results / category returns 200 with "no items" | Return 404 OR redirect to substitute OR return 200 + `noindex,follow` |
| Discontinued integration returns 200 with "no longer available" | 301 to closest parent OR 410 |
| Filter with zero results returns 200 | 404 or `noindex,follow` |

Detection: GSC `Coverage` → `Soft 404` cluster. Treat as a backlog.

### 3. Eliminate redirect chains

See [REDIRECT-PLAYBOOK](REDIRECT-PLAYBOOK.md). One-hop redirects only. Multi-hop chains:

- Cost crawl budget for every hop.
- Leak signal at each hop.
- Risk Google giving up on the chain.

### 4. Server reliability

`confirmed`: 5xx for Googlebot makes Google reduce its crawl rate for the site.

| Metric | Target |
|---|---|
| Googlebot 5xx % over 7 days | < 0.5 % |
| Googlebot p95 response time | < 1 s |
| Googlebot timeout count | 0 sustained |

Monitor via [LOG-FILE-ANALYSIS](LOG-FILE-ANALYSIS.md). Alert > 1 % 5xx over 1 hour.

### 5. Faceted-nav and parameter discipline

The single largest crawl-waste source for medium-sized SaaS. See [FACETED-NAV](FACETED-NAV.md).

### 6. Internal link discipline

Crawlers follow links. Garbage internal links (UTM-tagged, sort-tagged, session-IDed) waste crawl budget on duplicates.

| Source | Fix |
|---|---|
| Internal links with UTM tags | Strip in component; use clean canonical URLs |
| Sort dropdowns rendered as `<a>` | Use `<button>` + JS |
| Pagination with `rel=next`/`rel=prev` only (no real `<a>`) | Add `<a>` to numeric pagination |
| Footer link dump with every category combination | Restrict to canonical hubs |

## What unhelpful work looks like

`anti-pattern`: spending engineering time on crawl-budget tactics that don't help.

| Tactic | Why it doesn't help |
|---|---|
| Constantly tweaking `robots.txt` to "save budget" | `robots.txt` blocks crawl, not consumption of budget on the URL space remaining |
| `noindex` on huge URL spaces to save crawl budget | Google still has to fetch to see the noindex (`confirmed`) |
| Reducing sitemap to "only the most important" 100 URLs | Sitemap doesn't gate Google's crawl |
| Adding `rel="nofollow"` to internal links to "preserve PageRank" | nofollow on internal links is largely ignored; can hurt discovery |
| Daily sitemap regeneration on a stable site | No effect; Google doesn't re-crawl just because lastmod ticked |
| Setting `priority` field in sitemap | Largely ignored by Google (`confirmed`) |
| `changefreq` field set aggressively | Hint only; doesn't override actual crawl decisions |
| Disabling JS / CSS in robots | Breaks Google's render; major SEO regression |
| Worry on a 200-page T1 site | Crawl budget is not the bottleneck |

## GSC `Crawl stats` interpretation

GSC → Settings → Crawl stats. Read this report quarterly on T3+ sites; less often on T2.

| Section | What it says |
|---|---|
| Total crawl requests over time | Trend; sudden drop signals server issue or robots.txt block |
| By response | 200 / 3xx / 4xx / 5xx ratios; 5xx > 1 % is the high-severity tripwire |
| By file type | HTML / CSS / JS / image; CSS/JS 4xx breaks render |
| By purpose | `Discovery` (new) vs `Refresh` (re-crawl); imbalance signals new-URL discovery problem |
| By Googlebot type | Smartphone vs Desktop vs Image; Smartphone is the primary signal for indexing |
| Host availability | DNS / robots.txt / connectivity issues |

`anti-pattern`: chasing daily fluctuations. Look at 28-day trends.

## When the budget is actually being squeezed

Symptoms (`confirmed`):

- New URLs discovered but not crawled within 28 days.
- `lastmod` updates on existing URLs not re-crawled within 14 days.
- Sitemap submitted URL count >> URLs ever fetched in last 90 days.
- GSC `Pages` report shows large `Discovered — currently not indexed` cluster.

Triage:

1. Confirm via [LOG-FILE-ANALYSIS](LOG-FILE-ANALYSIS.md) that Googlebot is actually rate-limited (fetches/day plateau or down).
2. Check 5xx rate; fix server reliability first.
3. Reduce crawl waste (faceted nav, UTM internal links, soft-404s).
4. Improve internal-link signals to high-priority new URLs.
5. As a last resort, request increased crawl rate via GSC (rarely helpful; Google decides).

## Per-tier depth

| Tier | Depth |
|---|---|
| T1 | Skip; budget is not the bottleneck. |
| T2 | Quarterly GSC `Crawl stats` glance; fix soft-404s; verify sitemap freshness logic. |
| T3 | Monthly review; log-led crawl-waste sweep; alert on Googlebot 5xx spike. |
| T4 | Continuous; per-template fetch budget; per-deploy crawl-coverage check; alert on crawl-rate plateau. |

## Worked example — when budget worry was misplaced

State (2026-03):
- T2 SaaS site, 1,200 indexable URLs, organic stable.
- New SEO consultant claimed crawl budget was "the problem".
- Recommended: drop sitemap to "essential 50 URLs", add `nofollow` to all blog tag links, daily sitemap regeneration.

Reality (verified via [LOG-FILE-ANALYSIS](LOG-FILE-ANALYSIS.md)):
- Googlebot fetched 320 URLs/day; sitemap had 1,200; coverage was 90 % within 28 days.
- 5xx rate: 0.1 %.
- Soft-404 cluster: 12 URLs (low).
- New URLs were discovered and crawled within 5 days.

Conclusion: no crawl-budget bottleneck. The recommended tactics would have:

- Hidden 1,150 URLs from sitemap → no impact on Google's crawl, less metadata for prioritization.
- `nofollow` on internal blog tag links → Google may follow anyway; hurt discovery.
- Daily sitemap regen with bumped `lastmod` → no impact, possibly noisy signal.

Documented in `analyses/decision-log.md` as a rejected proposal.

## Worked example — when budget really was being squeezed

State (2026-04):
- T3 SaaS, 18,000 indexable integration / template pages.
- 110 query parameters across templates → ~3M URLs in the crawlable space.
- Googlebot fetched 12k URLs/day; sitemap had 18k; coverage was 23 % over 28 days.
- New templates discovered, but their indexing lagged ~45 days.

Diagnosis:
- Top 100 Googlebot paths: 70 % of fetches were on `?sort=`, `?utm_*=`, and combinatorial filter URLs.
- 5xx rate fine; server reliability not the issue.
- Crawl waste was the bottleneck.

Fix (sequential):
1. `robots.txt` disallow on combinatorial filter URLs.
2. Sort dropdowns moved to `<button>` + JS.
3. UTM-strip middleware on internal links.
4. Sitemap split per section (templates / integrations / blog) to surface lastmod separately.

Result (28 days):
- Googlebot fetches/day: 12k → 9k (down because waste eliminated).
- Coverage: 23 % → 71 % over 28 days.
- New-URL indexing lag: 45 days → 11 days.

## Anti-patterns

- Treating crawl budget as the universal SEO bottleneck.
- Tweaking `robots.txt` weekly.
- `noindex` on huge URL spaces to "save budget" (Google must fetch to see the directive).
- Reducing sitemap to "the important ones".
- `nofollow` on internal navigation.
- Stale `lastmod` (always `now()`); causes Google to ignore the field.
- Aggressive `changefreq` / `priority` settings.
- Disabling Googlebot rate manually unless server is dying.
- Investing in crawl-budget tooling on a 500-URL site.
- Ignoring soft-404s; calling crawl waste a "minor issue".
- Blocking JS/CSS to "save budget".

## Cross-references

- [LOG-FILE-ANALYSIS](LOG-FILE-ANALYSIS.md) — verified Googlebot fetches.
- [FACETED-NAV](FACETED-NAV.md) — single largest crawl-waste source.
- [REDIRECT-PLAYBOOK](REDIRECT-PLAYBOOK.md) — chain elimination.
- [PHASE-3-TECHNICAL](PHASE-3-TECHNICAL.md) — soft-404 sweep.
- [PHASE-12-VERIFICATION](PHASE-12-VERIFICATION.md) — post-deploy crawl-coverage check.
- [GUIDE-RECONCILIATION](GUIDE-RECONCILIATION.md) — crawl-budget framing in guide.
- [ANTI-PATTERNS](ANTI-PATTERNS.md) — full catalog.
- [EVIDENCE-LABELS](EVIDENCE-LABELS.md) — confidence/severity grammar.
