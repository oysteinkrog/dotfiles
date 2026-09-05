# ANTI-PATTERNS

Patterns that look helpful but are net-negative. Reject early; document in `analyses/anti-patterns.md` if a stakeholder pushes for one.

## Strategy

- Optimizing for keyword volume without intent / fit / conversion.
- Building "topic clusters" to simulate authority on subjects the product doesn't serve.
- Treating AI Overview citation as a side effect of organic ranking — they decoupled.
- Treating `llms.txt` as a ranking lever — no statistically meaningful effect.
- Replacing organic strategy with "we'll just optimize for ChatGPT" — citation lift requires the same substrate as organic plus three-plus unique data points.
- Skipping observability because "we already use Plausible" — wire GSC + GA4 anyway, they answer different questions.
- Buying links / participating in PBN / mass guest post — March 2024 spam policy enforcement.
- Mass programmatic launch in one batch — scaled-content-abuse tripwire.

## Technical

- Lazy-loading the LCP image.
- Importing dashboard-tier JS via shared marketing layout.
- Injecting JSON-LD from `useEffect`.
- Custom 404 page returning 200.
- Empty-state / no-results page returning 200 (soft-404).
- Canonical paginated pages to page 1.
- `noindex` to "save crawl budget" on huge URL spaces — Google still has to fetch.
- Block CSS / JS / image / API in `robots.txt`.
- Force-redirect verified crawlers based on user IP region.
- AI bot stance documented as "we don't care" — actually a business decision; document it.
- Edge config different from `next.config.ts` redirects — sources of truth disagree.
- Consent banner mounts before LCP image.
- Browser-history manipulation that traps Back or inserts deceptive intermediate pages — explicit malicious-practices spam-policy risk.

## Schema

- `aggregateRating` without real, visible reviews.
- `award` without visible award context.
- `FAQPage` on commercial pages targeting rich results (no longer broadly supported).
- `HowTo` expecting rich results (deprecated).
- `SearchAction` expecting Sitelinks Searchbox (retired).
- Schema declares price ≠ visible price.
- Multiple `Organization` entries on the same page.
- `sameAs` to broken / deprecated / inaccurate profiles.
- Fake `Person` reviewers to inflate trust.
- `Article.author` as a string instead of `Person` object.

## Content

- Slop patterns (see [SLOP-CHECKLIST](SLOP-CHECKLIST.md)).
- One LLM dump per page — no human owner, no review, no source check.
- Content created only because a keyword tool showed volume.
- Generic comparison pages with fabricated competitor limitations.
- "AI summarizing competitor pages" as the primary value-add.
- Word-count theatre — adding 1500 words of filler to a 400-word answer.
- Padded introductions ("In this article we'll explore…").
- Conclusions that restate the introduction.
- Hidden text or text rendered only to crawlers.
- Fake FAQs to win FAQ schema.
- Fake reviews / testimonials.
- "Updated 2026" date with no actual content change.

## Internal linking

- Anchor text monoculture (every internal link to pricing reads "pricing").
- Footer link dump.
- Hub pages that are link lists with no context.
- Cluster pages link to siblings but never back to pillar.
- `nofollow` on internal navigation.
- Important links rendered only by client-side JavaScript.

## Programmatic SEO

- Token-swap doorway templates.
- Generated summaries without verification.
- Pages for products / services / locations / integrations not actually supported.
- Doorway pages funneling users to one destination without unique value.
- No kill switch on a programmatic template family.
- Unstaged rollout of 500+ pages.
- Programmatic templates without owners / refresh cadence / quality dashboard.
- Faceted-nav variants crawlable at infinite scale.

## Measurement

- Vanity reporting (rank-tracker screenshots without context or decisions).
- Mixing GSC clicks and GA4 sessions in the same chart without explanation.
- Treating CrUX field data and Lighthouse lab data as interchangeable.
- Ignoring data caveats (consent, attribution, query anonymization).
- Reporting that does not drive decisions.
- No annotations — future moves are unattributable.

## Operations

- Fresh-eyes Phase 10 = author reviewing own work.
- Skip fresh-eyes when there's deadline pressure.
- Ship before two clean passes.
- Skip Phase 12 verification because Phase 11 deploy "looked fine".
- Treat audit findings as suggestions instead of as gate items.
- Call something `critical` because it's easy to fix.
- Call something `confirmed` because it sounds better than `hypothesis`.

## Migrations

- All-to-homepage redirects.
- Redesign + URL change + framework change + CMS change in one release.
- Skip the old-site crawl pre-launch.
- Decommission old sitemap before Google re-crawls old URLs through the redirects.
- No backlink notification campaign for top referring sites.

## Authority / off-page

- Paid links presented as editorial.
- PBNs.
- Mass guest-post networks.
- Automated outreach spam.
- Reciprocal-link arrangements.
- "As seen on" claims without meaningful coverage.
- Site-reputation-abuse arrangements (third-party content hosted to exploit your domain).
- Scholarship pages with no audience fit.
- Comment / profile / forum spam.
- Expired-domain manipulation.

## Experimentation

- Cloaking (different content to crawlers vs users).
- Permanent redirects on test variants.
- Concurrent tests on the same segment (confounded).
- No predefined stopping rule — peeking until "winning" appears.
- Shipping a winner site-wide that was tested on one segment.
- Title tests that swap meaningfully different intents (then it's not a title test).

## Authority claims

- "Industry-leading" without comparison evidence.
- "Best-in-class" without comparison evidence.
- "AI-powered" used as a claim of quality.
- "Trusted by" lists without permission or actual relationships.
- Customer-logo wall containing logos without permission.
- Outcome claims ("3× ROI") without methodology or context.

## When pressure mounts

If a stakeholder demands one of these, document the request, the rationale, and the SEO objection in `analyses/anti-patterns.md` so the program decision is auditable. The skill does not ship anti-patterns silently.
