# REDIRECT-PLAYBOOK

301 / 302 / 307 / 308 / 410 / 404 / `noindex` decision tree, per-scenario playbooks, and the source-of-truth question: *where does the redirect live*? Always one source of truth per host. Drift between `next.config.ts`, middleware, and edge config is the most common silent SEO bug on Vercel.

## Phase mapping

| Phase | Use this doc for |
|---|---|
| 1 — Discovery | Catalogue current redirects from `next.config`, middleware, edge, CDN; detect chains. |
| 3 — Technical | Audit redirect chains, soft-404s, and 4xx/5xx for verified bots. |
| 6 — Implementation | Author redirects in the right source of truth; chain-free. |
| 11 — Deploy | Old-URL re-crawl after migration; verify destinations. |
| 12 — Verify | Post-deploy redirect-chain check; representative URL set status codes. |
| `migration` mode | Old → new URL map; backlink notification. |

## Status code decision tree

```
What is the page's permanence?
│
├── Permanent (URL has changed forever)
│   └── Use 301 (or 308 to preserve method on POST/PUT)
│
├── Temporary (will return at the same URL)
│   └── Use 302 (or 307 to preserve method)
│
├── Gone (will not return; remove from index)
│   └── Use 410 (faster index removal than 404)
│
├── Not found (transient or unknown)
│   └── Use 404
│
└── Should not be indexed (still has a purpose for users)
    └── Return 200 with `<meta name="robots" content="noindex,follow">` and Robots header
```

| Code | Method preservation | Indexing effect | Use when |
|---|---|---|---|
| 301 | GET only on retry | Old URL drops, signals consolidate to new URL | Permanent move |
| 302 | GET only on retry | Old URL retained in index for some period | Genuinely temporary (A/B test, maintenance, region) |
| 307 | Method preserved | Same as 302 | Temporary + non-GET semantics matter |
| 308 | Method preserved | Same as 301 | Permanent + API endpoints |
| 410 | n/a | Faster removal than 404 | Page gone forever; do not redirect |
| 404 | n/a | Slower removal | Transient or unknown |
| `noindex` (200) | n/a | Removed from index, still crawlable | Page must remain accessible to logged-in users / search |

`confirmed`: Google treats 301 and 308 equivalently for indexing; 302 and 307 equivalently. (Google Search Central docs.)

## Source-of-truth decision

Pick *one* layer for each rule type. Document the choice in `seo-changelog.md`.

| Rule type | Best home | Why |
|---|---|---|
| Static, repo-known route changes | `next.config.ts` `redirects()` | Versioned with code; reviewed in PR. |
| Dynamic / per-request (auth gates, locale negotiation, host canonicalization) | `middleware.ts` | Runs on every matching request; needs request context. |
| High-volume host/protocol/locale rules | Vercel edge config / Cloudflare Bulk Redirects | Faster, no function invocation cost, less risk of regression. |
| One-off single-page tactical | `next.config.ts` if hardcoded; edge if hot-fix outside release | Match the rule's volatility. |

`anti-pattern`: same rule defined in two places (`next.config.ts` *and* edge). Sources of truth disagree under load; debugging takes hours.

## Per-scenario lookups

### Page moved permanently (URL change, content same)

```ts
// next.config.ts
{ source: "/old-feature", destination: "/feature", permanent: true }
```

- 301.
- Update internal links from `/old-feature` → `/feature` in same PR (do not rely on the redirect for internal traffic).
- Remove `/old-feature` from sitemap.
- Update `BreadcrumbList` schema if it referenced the old URL.

### Brand changed name (`acme.com` → `betacorp.com`)

Sequence:

1. New host serves both domains; old host 301s every URL to new host preserving path.
2. `Organization` schema on new host references both `name` and `alternateName` for 90 days.
3. Maintain `sameAs` reciprocity; update LinkedIn / X / Crunchbase / GitHub.
4. Backlink notification campaign for top 50 referring sites.
5. Old host kept live for *at least* 12 months (Google retains memory of old domains; backlinks need a destination).

```ts
// middleware.ts on old domain
import { NextResponse, type NextRequest } from "next/server";

export function middleware(req: NextRequest) {
  const url = new URL(req.url);
  const newUrl = new URL(url.pathname + url.search, "https://www.betacorp.com");
  return NextResponse.redirect(newUrl, 301);
}
```

### Page expired (gone, will not return)

Use 410. Faster index removal than 404 (`confirmed`).

```ts
// app/old-product/page.tsx
import { notFound } from "next/navigation";

export default function Page() {
  // Custom handler returning 410 — see "404 vs 410" below
}

// or via next.config rewrite to a route that emits 410:
// export async function GET() {
//   return new Response("Gone", { status: 410 });
// }
```

### Page merged (two pages → one)

301 the lower-traffic / lower-authority URL into the higher one. If the merged page intentionally serves both intents, the title/H1/intro should reflect both query families.

```ts
// next.config.ts
{ source: "/feature/scim", destination: "/feature/sso", permanent: true }
```

Update internal links so they go directly to the survivor; track destination's GSC for cannibalization.

### Page out-of-stock (SaaS analogue: discontinued integration)

Two options based on permanence:

| Decision | Action |
|---|---|
| Discontinued; will not return | 301 to closest parent (e.g. `/integrations`) or 410 if no good parent |
| Temporarily disabled (vendor outage) | 200 with prominent banner + `noindex,follow` until restored |

`anti-pattern`: returning 200 + "this integration is no longer supported" forever — soft-404 risk.

### Vanity URL / shortlink

```ts
// next.config.ts — vanity URLs always 301 to canonical
{ source: "/launch", destination: "/blog/launch-announcement", permanent: true }
```

- Always 301 (even though the vanity is "current") because the canonical is the long URL.
- Do not put vanities in sitemap.
- Do not let internal links use the vanity once the canonical is live.

### Locale split (single-locale → multi-locale)

```ts
// next.config.ts
{ source: "/blog/:slug", destination: "/en/blog/:slug", permanent: true }
{ source: "/pricing", destination: "/en/pricing", permanent: true }
```

Then introduce `/de/blog/:slug` etc. with `hreflang` declared on each page. See [HREFLANG-COOKBOOK](HREFLANG-COOKBOOK.md).

`anti-pattern`: redirecting `/` to `/en` based on `Accept-Language`. Traps verified Googlebot Smartphone (US-IP) into the wrong locale.

### `/blog` → `/resources` (taxonomy rename)

Whole sub-tree pattern with parameter forwarding:

```ts
// next.config.ts
{ source: "/blog", destination: "/resources", permanent: true }
{ source: "/blog/:slug*", destination: "/resources/:slug*", permanent: true }
```

Update all internal links in same PR; drop old paths from sitemap; submit re-indexing request via GSC URL inspection for the top 20 affected pages.

### Trailing-slash canonicalization

Pick one (slash or no-slash) site-wide.

```ts
// next.config.ts
trailingSlash: false,  // or true; pick one and document
```

301 the non-canonical form. Internal links use canonical. Sitemap uses canonical. Schema URLs use canonical.

### `www` vs apex

Pick one (typically `www` for SaaS marketing sites where you also use a `app.` subdomain). 301 the other to it.

```ts
// middleware.ts (or edge rule)
if (host === "example.com") {
  return NextResponse.redirect(`https://www.example.com${pathname}${search}`, 301);
}
```

DNS: `example.com` → ALIAS / ANAME / flattened CNAME to `www.example.com`. Some registrars require a redirect at the DNS provider; Cloudflare Page Rule or Vercel edge handles cleanly.

### HTTP → HTTPS

Always; no exceptions. Most platforms (Vercel, Cloudflare) enforce by default. Verify after every deploy:

```bash
curl -sI http://www.example.com/pricing | grep -i location
# Location: https://www.example.com/pricing
```

### Migration vs cleanup

Distinguish:

| Type | Trigger | Approach |
|---|---|---|
| Migration | Framework change, CMS change, domain change, big IA restructure | All-old-URL audit; one-hop 301s; backlink notification; old sitemap kept for re-crawl. See [MIGRATION-CHECKLIST](MIGRATION-CHECKLIST.md). |
| Cleanup | Decommissioning a single feature / page / cluster | 301 / 410 case-by-case; smaller PR; same-day verification. |

## Chain detection

Multi-hop redirects (`A → B → C → D`) silently leak signal and waste crawl budget.

`scripts/redirect-chain.ts`:

```ts
async function chain(url: string, hops: string[] = []): Promise<string[]> {
  const r = await fetch(url, { redirect: "manual" });
  hops.push(`${r.status} ${url}`);
  if (r.status >= 300 && r.status < 400) {
    const next = r.headers.get("location");
    if (!next) return hops;
    if (hops.length > 5) return [...hops, "DEPTH-LIMIT"];
    return chain(new URL(next, url).toString(), hops);
  }
  return hops;
}
```

Run against the full sitemap + the old-URL list pre/post-migration. Threshold: > 1 hop = `severity: high`. Two hops or more = always fix in same PR.

## Edge config vs middleware vs `next.config`

| Rule volatility | Pattern count | Recommended layer |
|---|---|---|
| Stable, < 50 rules | < 50 | `next.config.ts` |
| Stable, 50–500 rules | < 500 | Vercel edge config |
| Dynamic per-request | n/a | `middleware.ts` |
| 500+ rules (post-migration) | > 500 | Cloudflare Bulk Redirects or Vercel edge config (split per host) |

`middleware.ts` runs every matching request and adds latency. Restrict the matcher:

```ts
// middleware.ts
export const config = {
  matcher: ["/((?!_next|api|.*\\..*).*)"],
};
```

Otherwise the matcher catches `/_next/static/...` and image routes; you ship a redirect loop or major perf regression.

## 404 vs 410 vs `noindex` vs redirect — choosing the right tool

```
Has the URL ever indexed AND received external traffic / backlinks?
│
├── No → 404 is fine; 410 if you want faster removal.
│
└── Yes
    │
    ├── Is there a meaningful destination that satisfies the same intent?
    │   ├── Yes → 301 to it
    │   └── No  → 410 (preserves "gone forever" signal; faster than 404)
    │
    └── Special case: page must remain reachable for logged-in users → 200 + noindex,follow
```

`anti-pattern`: 301'ing every removed page to the homepage. Google treats this as soft-404 (`confirmed` per Google docs); does not pass signals.

## Custom 404 page

Must return HTTP 404, not 200.

```tsx
// app/not-found.tsx — Next.js 16
export default function NotFound() {
  return <main>...</main>;
}
```

Verify:

```bash
curl -sI https://www.example.com/this-does-not-exist
# HTTP/2 404
```

`anti-pattern`: rewriting unknown routes to a 200 page with "Not found" text. Soft-404 cluster grows in GSC over weeks.

## Migration redirect map (operational format)

`analyses/redirect-map.csv`:

| old_url | status | new_url | code | reason | source_of_truth | last_verified |
|---|---|---|---|---|---|---|
| `https://acme.com/blog/launch` | live → migrating | `https://www.acme.com/resources/launch` | 301 | host + taxonomy rename | next.config | 2026-04-22 |
| `https://acme.com/legacy-pricing` | gone | — | 410 | discontinued plan tier | edge | 2026-04-22 |
| `https://acme.com/integrations/zapier` | merged | `https://www.acme.com/integrations` | 301 | integration retired | next.config | 2026-04-22 |
| `https://acme.com/sign-up` | renamed | `https://www.acme.com/signup` | 301 | URL hyphen normalization | next.config | 2026-04-22 |

Re-crawl old URL set post-deploy; mark each row green/red.

## Backlink notification (migrations only)

After old-URL → new-URL map is live:

1. Pull top 50 referring domains from GSC + Ahrefs / Majestic.
2. For each, find a contact (author, editor, founder).
3. Send a short, specific email: "We moved `X` to `Y`; if you'd like to update the link, the canonical URL is `Y`."
4. Track replies; do not chase.

This is the single highest-leverage activity in a migration's first 30 days.

## Per-tier depth

| Tier | Depth |
|---|---|
| T1 | `next.config.ts` only; one source of truth; verify after each PR. |
| T2 | + middleware for host/locale; redirect-chain check in CI. |
| T3 | + edge config for high-volume rules; redirect map versioned per release. |
| T4 | + dedicated migration runbook; 410 cleanup as a quarterly sweep. |

## Worked example — `/blog` → `/resources` migration

State at 2026-04-15:
- 312 published `/blog/*` URLs.
- 11k inbound links to top 20 posts.
- Internal link graph: 1,820 internal links into `/blog/*`.

PR plan:

1. `next.config.ts`: 301 `/blog` → `/resources`, `/blog/:slug*` → `/resources/:slug*`.
2. Codemod: rewrite all internal links (Markdown + components + `Link` href props).
3. New sitemap entries for `/resources/*`; remove `/blog/*`.
4. Update `BreadcrumbList` schema generator.
5. Update Google News / Discover sitemap if applicable.
6. Old sitemap (`/sitemap-blog.xml`) keeps emitting *and* contains `lastmod` updates so Google sees the redirect signals quickly.
7. After 30 days of clean re-crawl confirmed via GSC URL inspection on a sample of 20, drop the old sitemap.

Verification (T+0):

```bash
# All old paths return 301
for path in $(cat analyses/blog-paths.txt); do
  code=$(curl -sI "https://www.example.com$path" -o /dev/null -w "%{http_code}")
  echo "$code $path"
done | grep -v "^301" || echo "all 301"
```

Verification (T+14):

- GSC Coverage: `Page with redirect` count rises (expected); `Submitted URL not found (404)` should not rise.
- Top 20 posts: re-crawled, indexed at new URL, ranking within ±2 positions of pre-migration.
- AI citations: re-checked at new URL on AIO / ChatGPT / Perplexity / Claude.

Rollback:

- Disable 301 in `next.config.ts`; ship.
- Old URLs serve again at 200.
- Issues with internal links remain (those code-modded). Track them as a separate cleanup PR.

## Anti-patterns

- All-to-homepage redirects (soft-404 risk).
- Redirect chains > 1 hop.
- Same rule in `next.config.ts` and edge config (drift).
- 302 used for permanent moves.
- 301 used for genuinely temporary (A/B, maintenance) moves.
- Custom 404 returning 200.
- Discontinued page returning 200 with "no longer available".
- Locale auto-redirect that catches verified Googlebot.
- Removing old sitemap before Google re-crawls old URLs through the redirects.
- Redirecting `/_next/static/*` (caused by sloppy middleware matcher).
- Redirecting before authentication check (auth redirect after canonical redirect chain).
- Rewriting (200) when you mean redirecting (301) — content unchanged but URL changes signal preservation.

## Cross-references

- [NEXTJS-PATTERNS](NEXTJS-PATTERNS.md) — `next.config.ts redirects()`, middleware matcher.
- [MIGRATION-CHECKLIST](MIGRATION-CHECKLIST.md) — full migration sequence.
- [HREFLANG-COOKBOOK](HREFLANG-COOKBOOK.md) — locale routing + redirects.
- [PHASE-3-TECHNICAL](PHASE-3-TECHNICAL.md) — chain audit step.
- [PHASE-12-VERIFICATION](PHASE-12-VERIFICATION.md) — post-deploy status-code check.
- [ANTI-PATTERNS](ANTI-PATTERNS.md) — redirect-related anti-patterns.
- [EVIDENCE-LABELS](EVIDENCE-LABELS.md) — confidence/severity grammar.
