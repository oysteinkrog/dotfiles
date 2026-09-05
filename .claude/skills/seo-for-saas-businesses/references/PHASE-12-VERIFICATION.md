# PHASE 12 — LIVE-SITE PLAYWRIGHT VERIFICATION

Goal: confirm what shipped is actually visible to crawlers.

## Inputs

- `analyses/representative-urls.json` (from Phase 1 / 3).
- The PR set merged in Phase 11 with deploy timestamp.

## Run

```bash
bun run scripts/verify-prod.ts --rep-set "$REPO/analyses/representative-urls.json" \
  --output "$REPO/analyses/post-deploy-verification.md"
```

## Per-URL checks

For each representative URL:

| Check | How |
|---|---|
| Status code | HTTP fetch returns expected status (200 for pages, 301 for legacy redirects, 404 for known-removed) |
| Meta tags rendered server-side | Raw HTML (no JS execution) contains title, meta description, canonical, robots, OG/Twitter, JSON-LD |
| JSON-LD validates | Each `<script type="application/ld+json">` parses; declared `@type` matches a current schema.org type; required properties present |
| OG/Twitter image returns 200 with correct dimensions | HEAD request; `width: 1200, height: 630` or per-spec |
| Canonical points to itself or to declared owner | Canonical absent → flag; canonical to a different URL → flag unless intentional |
| robots directive | Matches expected (`index,follow` for indexable; `noindex,follow` for utility) |
| Internal links resolve to 200 | All `<a href>` in raw HTML respond 200 (sample if too many) |
| No hydration-driven content invisible to crawlers | Diff raw HTML vs DOM at network-idle; primary content blocks present in raw |
| INP / LCP / CLS under thresholds | Lighthouse CI mobile profile; field check via CrUX API |
| AI-crawler view consistent with Googlebot view | `--as GPTBot` and `--as ClaudeBot` and `--as PerplexityBot` initial-HTML responses contain headline answer + three unique data points |
| Browser Back behavior sane | Playwright navigates representative flows, opens/closes modals/filters/overlays, then presses Back; result is the actual previous page with no deceptive inserted history entry or loop |

## Output

```md
# Post-deploy verification — 2026-04-30

## Summary
- Representative URLs: 47
- Pass: 45
- Fail: 2
- Flagged for follow-up: 1

## Failures
### https://www.example.com/integrations/notion
- [FAIL] OG image returns 404
  - Expected: /integrations/notion/opengraph-image returns 200 image/png
  - Got: 404
  - Likely cause: opengraph-image.tsx not generating for slugs with Capital first letter
  - Remediation: lowercase slug param before lookup; add test
  - Owner: engineering
  - Audit ID created: AUDIT-0234

### https://www.example.com/security
- [FAIL] JSON-LD invalid
  - Expected: Organization + WebApplication
  - Got: WebApplication missing required `applicationCategory`
  - Likely cause: PR seo/structured-data dropped the field on the security page only
  - Remediation: re-add applicationCategory to security page schema
  - Owner: engineering
  - Audit ID created: AUDIT-0235

## Flags
### https://www.example.com/pricing
- [FLAG] AI-crawler view shows skeleton plan list
  - GPTBot initial HTML contains placeholder "Loading..." not plan data
  - Googlebot view OK after render
  - Likely cause: Suspense boundary moved to RSC stream after PR seo/perf-cwv
  - Remediation: move plan list to a non-streamed segment
  - Owner: engineering
  - Audit ID created: AUDIT-0236

## CWV
| URL | LCP p75 | INP p75 | CLS p75 | Pass? |
|---|---|---|---|---|
| / | 1.8s | 120ms | 0.04 | yes |
| /pricing | 2.1s | 180ms | 0.06 | yes |
| /integrations | 2.4s | 220ms | 0.05 | NO (INP) |
| ... |
```

## Failure → audit item

Every failure becomes a new audit item with severity calibrated by impact (e.g. `high` if a top-traffic page; `medium` if a low-traffic edge case). Items go into the next Phase 6 PR cycle.

## AI-crawler view as a separate gate

The most common Phase 12 surprise: pages render fine for Googlebot but show skeletons / placeholders / loading states to AI crawlers. This is the `Phase 12 → AI visibility` gate.

When it fails:
- Move the affected content out of Suspense streaming into the static shell, OR
- Render a server-side fallback that contains the citation-eligible content.

Do not suppress AI bots as a workaround — that loses citation eligibility entirely.

## Locale verification

For internationalized sites:

- Each locale's representative URLs verified in turn.
- `hreflang` reciprocity verified.
- Auto-redirect behaviour verified with `Googlebot` and a non-default-region IP / geo-override.
- `x-default` selector reachable.

## Schema regression check

Compare current schema against a previous snapshot to detect drift:

```bash
bun run scripts/validate-schema.ts \
  --representative "$REPO/analyses/representative-urls.json" \
  --baseline "$REPO/analyses/schema-baseline.json" \
  --output "$REPO/analyses/schema-diff.md"
```

If a previously-valid type is now invalid, that is a regression — flag it even if Phase 11's PR was unrelated.

## Sign-off rule

Phase 12 is complete only when:
- Zero `FAIL` items.
- All `FLAG` items have audit IDs and ownership.
- CWV passes thresholds on representative pages.
- AI-crawler view contains headline answer + three unique data points on every priority page.

If any of the above is open, do not proceed to declare the program shipped. Open the next Phase 6 PR cycle.
