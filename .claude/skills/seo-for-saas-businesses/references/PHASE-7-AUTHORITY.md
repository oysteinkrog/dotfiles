# PHASE 7 — OFF-PAGE & AUTHORITY STRATEGY

Goal: earned links and citations from genuinely useful assets. White-hat only.

## Strategy

Build assets people *want* to reference. Outreach amplifies; it does not replace.

## Linkable-asset inventory

For each candidate, emit `authority_asset_score_0_1000`:

| Component | Points |
|---|---:|
| Solves a narrow, real problem | 0-250 |
| Referenceable without a sales pitch | 0-250 |
| SaaS has unique data, view, or capability to produce it | 0-250 |
| Maintenance cost is realistic | 0-250 |

`0` = reject; `500` = maybe if cheap; `750` = plan; `900+` = priority asset. Never use a 1-5 or 1-10 authority score.

Strong asset types for SaaS:
- Original research / benchmark report (latency, accuracy, cost, market sizing).
- Free public tool tied to product (calculator, validator, generator, analyzer).
- Definitive guide for an underserved query.
- Public dataset or open-source utility.
- Annual report (state of X) with original data.
- Interactive comparison or decision tool.
- Templates / examples library.
- Industry maps / landscape diagrams (when not already saturated).

Weak assets:
- "Ultimate guide to X" that summarizes other ultimate guides.
- Listicle ("Top 50 tools for…").
- Badge programs purely for backlinks.
- Scholarship pages with no audience fit.

## Outreach campaigns

For each asset, 90-day outreach plan:

| Surface | What to do |
|---|---|
| Industry publications | Pitch original-data angle; offer pre-publication look; provide methodology |
| Newsletters | Pitch the asset to relevant newsletters as a one-time feature |
| Podcasts | Founder / domain expert interviews tied to the asset |
| Communities | Share where genuinely relevant (Hacker News, relevant subreddits, LinkedIn, X — mod-friendly) |
| HARO / Qwoted / Connectively | Respond to relevant queries with original data |
| Partner / integration directories | Update profile; push fresh screenshots / copy |
| Industry events | Speaking opportunities tied to the asset's data |
| Brand-mention reclamation | Find unlinked brand mentions; ask author to link (no quid-pro-quo) |
| Existing relationships | Surface to customers, investors, advisors who naturally share |

## Tracking

`deliverables/authority-plan.md` lists each campaign:

```md
## Campaign: 2026 SaaS pricing benchmark report
- Owner: <name>
- Asset URL: https://www.example.com/research/2026-saas-pricing-benchmark
- Launch date: 2026-05-15
- Outreach list: 47 contacts (industry publications, newsletters, podcasts)
- Expected outcomes: 10 dofollow links, 3 publication features, 1 conference speaking slot
- KPI: referring domains, branded search uplift, qualified leads from research traffic
- Tracked in beads: BR-456 through BR-503
```

Per-contact tracker in beads or sheet:
- Contact, publication, role, last touch, status (queued / sent / replied / placed / declined), linked URL.

## Third-party platform discoverability

For each platform the SaaS shows up in:

- [ ] Accurate name, category, description, logo, and homepage link.
- [ ] Screenshots match current product.
- [ ] Clear installation or signup path.
- [ ] Support and security links.
- [ ] Relevant tags / categories without stuffing.
- [ ] Changelog or freshness signals where the platform supports them.
- [ ] Review response process.
- [ ] UTM-tagged links where permitted.

Common platforms for SaaS:
- GitHub (public repos with clear READMEs).
- Vercel / Netlify integration directories.
- Product Hunt.
- App stores (Slack, Salesforce, HubSpot, Zapier, etc.).
- G2, Capterra, Trustpilot, GetApp.
- StackShare.
- Crunchbase, ProductHunt, AlternativeTo.
- Industry-specific (e.g. HIPAA-related directories for health SaaS).

Schedule a quarterly profile audit per platform.

## Brand-mention reclamation

`scripts/brand-mention-scan.ts` — scrape industry publications and reputable communities for brand mentions, cross-reference with backlink data, surface unlinked mentions for outreach.

## Anti-patterns (hard prohibitions)

- Paid links presented as editorial.
- Private blog networks (PBNs).
- Mass guest-post networks.
- Automated outreach spam.
- Large-scale reciprocal linking.
- Comment / profile / forum spam.
- Expired-domain manipulation (also a March 2024 spam policy).
- Low-quality directory blasts.
- Pretending to be a journalist.
- Hidden affiliations.
- Site-reputation-abuse arrangements (third-party content hosted on the SaaS domain mainly to exploit the SaaS's reputation — a documented 2024 spam policy).

## Integration with other phases

- Phase 4 (content) produces the assets.
- Phase 6 (implementation) ships the asset pages.
- Phase 8 (analytics) tracks referring domains, branded search uplift, qualified leads from asset traffic.
- Phase 9 (experimentation) may A/B asset CTAs.
- Phase 13 (compounding) reviews which assets compounded vs decayed.
