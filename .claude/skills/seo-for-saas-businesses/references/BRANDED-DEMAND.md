# BRANDED-DEMAND

Branded search is the share of organic traffic where someone searched for the company name (or close variants). It's the most reliable durable asset a SaaS can build — algorithm-resilient, conversion-rich, and the dominant signal in core-update recoveries.

This document covers building branded demand, the reputation-page set required to defend it, and the operational tracking that distinguishes branded from non-branded movement.

## Phase mapping

| Phase | Use this doc for |
|---|---|
| 1 — Discovery | Branded vs non-branded baseline; reputation-page audit. |
| 4 — Content | Reputation pages (pricing, security, comparison, etc.). |
| 7 — Authority | Building branded demand via PR / community / product surface. |
| 8 — Analytics | Branded-vs-non-branded split tracking. |
| `traffic-drop-triage` | Branded vs non-branded diagnostic. |

## Building branded demand

Branded demand is *manufactured* by activities visible to the audience the brand wants to serve. It is not earned by SEO tactics in isolation.

| Activity | Effect on branded demand |
|---|---|
| PR placements (TechCrunch, BusinessWeek, vertical media) | Spike followed by sustained baseline lift |
| Founder / executive personal brand (X, podcasts, conference talks) | Steady lift; converts to GitHub stars, signups, branded queries |
| Community building (Slack / Discord / forum / Twitch) | High-quality branded queries with intent |
| Product launches with shareable artifacts (changelog, examples, free tools) | Spikes; compounds via product-led SEO |
| Open-source repo with active maintainers | Long-tail branded queries (`acme github`, `acme cli`, `acme integration`) |
| Customer-success stories | Indirect branded demand via attribution |
| Paid acquisition with brand-builder copy | Lifts branded query volume even when click-through doesn't convert directly |

`anti-pattern`: trying to "build branded demand" via SEO content only. SEO captures branded demand; PR / product / community create it.

## Reputation page set

When someone searches your brand or visits the site to evaluate, these pages must exist, be discoverable, and tell a complete story. Missing reputation pages = answers happen elsewhere (review sites, Reddit, Hacker News) where you don't control framing.

| Page | Purpose | Branded queries it captures |
|---|---|---|
| `/pricing` | What it costs | `acme pricing`, `how much is acme`, `acme cost` |
| `/security` (+ subpaths: `/security/soc2`, `/security/gdpr`, `/security/hipaa`) | Trust artifacts | `acme security`, `is acme soc2`, `acme hipaa` |
| `/compare` (or `/vs/<competitor>`) | Defensive vs competitor | `acme vs <competitor>` |
| `/refund` (or `/cancel`) | Cancellation policy | `cancel acme`, `acme refund`, `acme money back` |
| `/status` | System status | `is acme down`, `acme status` |
| `/changelog` | What's new | `acme update`, `acme new features`, `acme release` |
| `/integrations` (+ per-integration) | What it connects to | `acme + <tool>`, `acme integrations` |
| `/customers` (+ stories) | Social proof | `acme customers`, `acme case study` |
| `/careers` (+ per-role) | Hiring brand | `acme jobs`, `<role> at acme` |
| `/about` (+ team) | Company story | `acme founder`, `acme company`, `acme team` |
| `/contact` | Reachability | `contact acme`, `acme support` |
| `/legal/terms`, `/legal/privacy`, `/legal/dpa` | Legal | `acme terms`, `acme dpa` |
| `/blog` (+ posts) | Editorial | `acme on <topic>` |
| `/docs` (or `/help`) | Self-serve support | `acme docs`, `how to <action> in acme` |
| `/api` (or `/developers`) | Developer brand | `acme api`, `acme sdk`, `acme rest api` |

For T2+: every row should exist. Missing rows are entry points for negative SEO (competitor pages outranking you on your own brand) and damage control failures.

## Authoring rules for reputation pages

| Page | Critical |
|---|---|
| `/pricing` | Concrete numbers; no "Contact for pricing" on a plan that has a number; schema mirrors visible price |
| `/security` | Real artifacts (SOC 2 report PDF behind gated form, ISO 27001, pen test summary); link to a `Trust Center` |
| `/compare` | Dated; first-hand verification; updated when competitor changes |
| `/refund` | The actual policy in plain language; not legalese |
| `/status` | Real status; not just a "we're up" banner — historical incidents, uptime % |
| `/changelog` | Visible per-release history with dates; serves as freshness signal |
| `/customers` | Real logos with permission; outcome metrics where possible |
| `/about` | Specific details (founding date, location, team count, investors); not generic mission text |

`anti-pattern`: reputation page exists but is gated, vague, or marketing-fluff-only. Search engines and AI bots cannot extract it.

## Branded-vs-non-branded split tracking

Per Operator ⌗ Branded-vs-Non-Branded Split.

### Defining "branded"

A branded query contains at least one of:

- The brand name (`acme`).
- The brand name + product name (`acme pro`).
- A common misspelling (`acmme`, `acm`).
- The brand name + competitor (`acme vs competitor` — counted as branded for the competitor too).
- Founder / executive name + brand context.

Non-branded = everything else.

Build the regex once; refresh quarterly:

```regex
\b(acme|acmme|acm|acme[ -]?pro|acme\.com)\b
```

### Tracking in GSC

GSC Performance → filter Query → Custom (regex) → Matches the brand regex. Compare clicks/impressions over time vs the inverse filter.

```
Branded:     queries matching brand regex
Non-branded: queries NOT matching brand regex
```

Track weekly in `analyses/branded-split.csv`:

| week | branded_clicks | branded_impressions | non_branded_clicks | non_branded_impressions | branded_share_clicks |
|---|---|---|---|---|---|
| 2026-W17 | 4,820 | 6,200 | 3,140 | 92,000 | 0.61 |

### Diagnostic interpretation

When traffic moves, the split tells you what kind of move:

| Branded | Non-branded | Diagnosis |
|---|---|---|
| Down | Down | Site-wide quality / spam policy / manual action / infra issue |
| Down | Up | Brand crisis / product issue / reputation event / Reddit thread / negative press |
| Up | Down | Algorithm shift, content quality classifier, competitive loss in non-branded |
| Up | Up | Healthy growth |
| Flat | Down | Likely algorithm-driven non-branded loss; brand intact |
| Flat | Up | Non-branded gain; brand level |

Always run this diagnostic *first* in `traffic-drop-triage` mode. It changes the entire fix path.

## Branded autocomplete monitoring

Google Autocomplete suggestions for `<brand name>` reveal what people are searching for *and* what reputation challenges exist (e.g. `acme down`, `acme alternatives`, `acme reddit`, `acme refund`).

Quarterly capture:

```
Search 1: "<brand>"
Search 2: "<brand> "  (with trailing space)
Search 3: "<brand> a", "<brand> b", ... (alphabet sweep)
```

Catalogue in `analyses/branded-autocomplete-YYYY-Q.md`:

| Suggestion | Position | Sentiment | Action |
|---|---|---|---|
| `acme reviews` | 1 | neutral | Ensure G2 / Capterra / Trustpilot are claimed and managed |
| `acme alternatives` | 2 | neutral-negative | Build defensive `/compare` pages |
| `acme pricing` | 3 | neutral | `/pricing` page well-structured; check it ranks #1 |
| `acme down` | 6 | negative | Status page must rank #1 for this query |
| `acme reddit` | 9 | unknown | Monitor relevant subreddits |

`anti-pattern`: discovering negative autocomplete via a customer's screenshot in a sales call. Run the sweep proactively.

## Brand-protection queries

A brand-protection query is one where you must rank #1 because not doing so directly leaks demand.

| Query | Why protect |
|---|---|
| `<brand>` | Bare brand; #1 must be your domain |
| `<brand> login` | Phishing risk if a clone outranks |
| `<brand> pricing` | Conversion-critical |
| `<brand> reviews` | Reputation control |
| `<brand> alternatives` | Defensive |
| `<brand> vs <competitor>` | Defensive |
| `<brand> support` | Customer-experience |
| `<brand> down` | Status / outage handling |
| `<brand> refund` / `<brand> cancel` | Cancellation policy clarity |
| `<brand> integration with <tool>` | Conversion-adjacent |

Quarterly: verify your domain ranks #1 for each. If not, identify what's outranking you and remediate.

## Branded SEO in core updates

`likely`, operator-observed: strong branded demand acts as an algorithm-resilience buffer.

| Site state | Core-update behavior |
|---|---|
| Strong branded demand + healthy non-branded | Updates rarely affect significantly; small fluctuations |
| Strong branded + weak non-branded | Branded stable; non-branded fluctuates more |
| Weak branded + strong non-branded | High exposure; non-branded swings hit harder |
| Weak branded + weak non-branded | Maximally exposed; can lose 30–60 % traffic in a single update |

This is *not* permission to ignore non-branded SEO. It's evidence that branded demand is the foundation that makes non-branded SEO survivable.

When branded demand cannot save you:

- Manual action (separate from algorithm; no quality of branded demand fixes this).
- Infrastructure / availability issues (blocked / 5xx / unrendered).
- Site-wide spam policy violation (scaled content abuse, site reputation abuse).
- Catastrophic helpful-content classifier shift on a site with too much thin content.

## Per-tier depth

| Tier | Depth |
|---|---|
| T1 | Reputation set: pricing, security, about, contact, status, terms, privacy. Skip branded-vs-non-branded (insufficient data). |
| T2 | Full reputation set; weekly branded-split track; quarterly autocomplete sweep. |
| T3 | + brand-protection query verification; + per-segment branded share (region, plan, vertical). |
| T4 | + brand-mention monitoring (uncited mentions in news / forums / social); + per-product branded share if multi-product. |

## Worked example — branded-vs-non-branded diagnosis

Symptom (2026-04-15):
- Total organic clicks down 22 % over 14 days.
- No GSC manual action.
- No reported algorithm update.
- T2 SaaS, ~12k weekly clicks.

Diagnosis:

1. Pulled GSC weekly clicks/impressions, branded vs non-branded.
2. Branded: 4,820 → 4,920 (flat).
3. Non-branded: 8,200 → 4,400 (-46 %).

Conclusion: non-branded loss; brand intact.

4. Per-cluster non-branded analysis: integrations cluster down 60 %; blog down 15 %; pricing-adjacent down 30 %.
5. Integrations cluster examined: a refactor 3 weeks prior had introduced a `useEffect` to populate the integration list on `/integrations`. Bot fetches dropped (no list = no internal link discovery).
6. Bot view via `scripts/ai-crawler-view.ts` confirmed: integration list missing from initial HTML.

Fix:
- Move integration list to Server Component.
- Re-submit sitemap.
- Spot-check via GSC URL inspection on top 20 integration pages.

Recovery (28 days):
- Non-branded clicks: 4,400 → 7,800.
- Branded: stable through the whole event.

The branded-vs-non-branded split located the problem in 30 minutes vs. weeks of guesswork.

## Anti-patterns

- Treating branded SEO as something separate from organic SEO.
- "We don't need a /pricing page" — let competitors and Reddit answer for you.
- Hiding pricing behind "Contact sales" on plans that should be self-serve.
- Status page only operational during incidents — must be live 24/7 with historical data.
- Reputation pages thin enough to be classified as filler.
- Comparison pages with fabricated competitor limitations.
- Customer logos without permission (legal + brand risk).
- Founder bio in three different forms across LinkedIn / Crunchbase / About page.
- Branded query #1 result is a third-party (because the brand site is technically broken or thin).
- No branded-vs-non-branded tracking at T2+ — every traffic event becomes a fishing expedition.
- Buying branded ads on your own brand without a defensive case (cannibalizes organic and tests Google's allowance).
- Letting Reddit and Hacker News *be* your reputation pages.

## Cross-references

- [PHASE-1-DISCOVERY](PHASE-1-DISCOVERY.md) — branded baseline.
- [PHASE-4-CONTENT](PHASE-4-CONTENT.md) — reputation page authoring.
- [PHASE-7-AUTHORITY](PHASE-7-AUTHORITY.md) — PR + linkable assets feeding branded demand.
- [PHASE-8-ANALYTICS](PHASE-8-ANALYTICS.md) — branded-split dashboard.
- [TRAFFIC-DROP-PLAYBOOK](TRAFFIC-DROP-PLAYBOOK.md) — diagnosis using the split.
- [CONTENT-INVENTORY-OPS](CONTENT-INVENTORY-OPS.md) — reputation-page state in inventory.
- [PRODUCT-LED-SEO](PRODUCT-LED-SEO.md) — product surface as branded demand creator.
- [OPERATORS](OPERATORS.md) ⌗ Branded-vs-Non-Branded Split, ⇲ Trust Surface Audit.
- [ANTI-PATTERNS](ANTI-PATTERNS.md) — full catalog.
- [EVIDENCE-LABELS](EVIDENCE-LABELS.md) — confidence/severity grammar.
