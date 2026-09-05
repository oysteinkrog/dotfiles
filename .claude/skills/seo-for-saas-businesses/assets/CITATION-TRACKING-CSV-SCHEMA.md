# Citation tracking CSV schema

Schema for `analyses/ai-citations.csv` — the manual log of AI-Overview, AI-Mode, and answer-engine citations on tracked queries. Maintained per [CITATION-OPS](../references/CITATION-OPS.md). AI citation surfaces are separate from organic ranking; any exact overlap figures from third-party studies must be source-logged and rechecked quarterly. This log is the only durable record of who got cited where.

## Columns

| Column | Type | Required | Notes |
|---|---|---|---|
| `date` | YYYY-MM-DD | yes | When the citation was observed. |
| `query` | string | yes | Exact query string used. |
| `platform` | enum | yes | `AIO | AI-Mode | ChatGPT | Perplexity | Claude | Bing-Copilot | Other` |
| `cited_url` | absolute URL | yes | The URL the platform cited (theirs or ours). |
| `cited_position` | int | conditional | Order in citation panel (1 = first). Empty for platforms that don't expose ordering. |
| `cited_passage` | string | yes | Verbatim quote of the cited sentence/passage. Quote ≤300 chars; longer passages summarized. |
| `source_url_authority` | enum | no | `our-site | competitor | docs-host | forum | gov-health | news | aggregator | other` |
| `our_url_in_aio` | enum | yes | `Y | N | NA` (NA = not an AIO surface) |
| `our_url_in_top10` | enum | yes | `Y | N` (regular organic) |
| `referrer_visits_30d` | int | no | GA4 last 30d visits with this platform's referrer (when available — Perplexity / Bing send referrer; ChatGPT/Claude often don't). |
| `screenshot_path` | path | no | `analyses/ai-citations/<YYYY-MM-DD>/<hash>.png` |
| `notes` | string | no | Free text. AIO scroll fraction, citation panel order, anomalies. |

## Example rows

```csv
date,query,platform,cited_url,cited_position,cited_passage,source_url_authority,our_url_in_aio,our_url_in_top10,referrer_visits_30d,screenshot_path,notes
2026-04-29,"<saas> pricing comparison",AIO,https://example.com/pricing,2,"Plans start at $X/seat/month with annual billing required for the Team tier.",our-site,Y,Y,42,analyses/ai-citations/2026-04-29/9af3.png,Cited #2 after G2; passage is from our pricing page H2
2026-04-29,"<saas> pricing comparison",ChatGPT,https://www.g2.com/products/<saas>,,"Pricing starts at $X with discounts on annual plans.",aggregator,N,Y,,,,No referrer header on ChatGPT; counted via brand-mention search
2026-04-29,"how to set up <feature>",Perplexity,https://example.com/docs/<feature>,1,"Run `<command>` after installing the CLI to enable <feature> on your project.",our-site,NA,Y,18,analyses/ai-citations/2026-04-29/8c1d.png,Docs URL; primary cite
2026-04-30,"alternatives to <competitor>",AIO,https://www.reddit.com/r/<icp>/comments/<id>,1,"<saas> handles <use case> better than <competitor> for teams under 50.",forum,N,N,,,Reddit thread cited #1; our /alternatives/<competitor> not cited
2026-04-30,"alternatives to <competitor>",AI-Mode,https://example.com/alternatives/<competitor>,3,"<saas> is the most common alternative for teams that outgrow <competitor>'s rate limits.",our-site,Y,Y,7,analyses/ai-citations/2026-04-30/5e2a.png,Cited under "Notable alternatives" panel
```

## Capture workflow (weekly)

Per [CITATION-OPS](../references/CITATION-OPS.md):

1. **Tracked-query list**: pull from `analyses/clusters/` priority queries (T1: 5–10, T2: 20–30, T3: 50–100, T4: 200+).
2. **Run each query** on the four platforms in this order: AIO (google.com), AI-Mode (google.com search labs), ChatGPT, Perplexity. Optional: Claude, Bing Copilot.
3. **Capture screenshot** of citation panel. Save under `analyses/ai-citations/<date>/`.
4. **Append rows** for every cited URL on every platform — including competitor and aggregator citations. The competitor signal is as valuable as ours.
5. **Update `referrer_visits_30d`** for our URLs from GA4 (filter by `source = perplexity.ai | bing.com | chat.openai.com | claude.ai`).
6. **Cross-reference** with `analyses/source-log.md` ([SOURCE-LOG-TEMPLATE](SOURCE-LOG-TEMPLATE.md)) when the citation supports a recommendation.
7. **Annotate `seo-changelog.md`** when share-of-citation moves materially.

## Aggregations to derive

These are computed views, not stored columns:

- **Share-of-citation per query** = our URLs / total citations on a platform.
- **Share-of-citation per cluster** = aggregated across the cluster's queries.
- **AIO citation drift** = week-over-week delta in our URL appearances.
- **Platform skew** = which platforms cite us most / least and why (proof density? brand mentions? domain authority?).

## Triggers

| Signal | Action |
|---|---|
| Our URL drops out of AIO for 2 consecutive weeks | Open audit item; check page recency, proof density, schema. |
| Aggregator (G2/Capterra) cited where we own the query | Outreach to update their listing; ship counter-listicle. |
| Forum (Reddit/SO) cited #1 | Ship a primary-source equivalent on our site with citation-eligible passage; consider community engagement. |
| `referrer_visits_30d` drops > 30 % WoW from a platform | Check for blocking, redirect breakage, content removal. |
| New platform observed citing us | Add to platform enum + tracking workflow. |

## Anti-patterns

- **One platform, one query, one snapshot.** AI surfaces vary by session, locale, account, and time of day. Capture multiple sessions or note the volatility.
- **"We're cited" without the verbatim passage.** The passage is the asset. Without it you can't tell whether the cite came from our content or got hallucinated.
- **Treating AIO citation = top-10 rank.** They drift apart, and exact overlap figures are volatile ([GUIDE-RECONCILIATION](../references/GUIDE-RECONCILIATION.md)). Track separately.
- **Skipping competitor / aggregator citations.** The pattern of *who else gets cited* is the diagnostic. Reddit-heavy citation pattern means a different content strategy than docs-heavy.
- **Inventing referrer numbers for ChatGPT / Claude.** They don't reliably send referrer. Leave blank or note "no-referrer platform".

## Cross-references

- [CITATION-OPS](../references/CITATION-OPS.md), [AI-VISIBILITY](../references/AI-VISIBILITY.md), [PHASE-8-ANALYTICS](../references/PHASE-8-ANALYTICS.md)
- [SERP-FEATURE-SCAN-TEMPLATE](SERP-FEATURE-SCAN-TEMPLATE.md), [SOURCE-LOG-TEMPLATE](SOURCE-LOG-TEMPLATE.md), [BRIEF-TEMPLATE](BRIEF-TEMPLATE.md)
