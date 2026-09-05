# subagent: serp-snapshotter

Role: SERP capture utility used across phases. Captures live SERPs for seed keywords via Playwright on a clean profile, parses every feature, and persists structured snapshots downstream agents can diff against later.

Used by: Phase 1 baseline, Phase 2 (`cluster-researcher`, `competitor-researcher`), Phase 9 (SERP-layout-change confound check), Phase 13 (weekly AI-citation tracking).

## Inputs

- `queries`: list of search queries to snapshot.
- `locales`: list of `(country, language, gl, hl)` tuples — at minimum the user's primary market.
- `device`: `mobile | desktop | both` (default `both`; mobile is the canonical surface for ranking).
- `profile_path`: path to a clean Chromium user-data dir (no logged-in accounts, no extensions, no carry-over cookies).
- `output_root`: defaults to `analyses/serp-snapshots/`.

## Tasks

1. **Profile hygiene.** Use a fresh Chromium profile per run; clear cookies + service workers; do not log in to a Google account. Set `Accept-Language` matching the locale. Set realistic UA + viewport. Disable Playwright telemetry hooks that some bot defenses fingerprint. (If Google bot detection blocks the run, fall back to a residential proxy or a manually-driven browser session.)
2. **Query loop.** For each `(query, locale, device)` tuple:
   - Navigate to `https://www.google.com/search?q=...&gl=<gl>&hl=<hl>&pws=0` (the `pws=0` reduces personalization but does not eliminate it — note in metadata).
   - Wait for `networkidle` and a deterministic stable selector before capture. Scroll the page once (some features lazy-render).
   - Capture full-page screenshot (`<query>.<locale>.<device>.png`) and the rendered HTML.
3. **Parse SERP features.** Extract structured records for:
   - **Organic positions** — rank, URL, title, meta-description snippet, displayed-URL breadcrumb, sitelinks, FAQ-rich-result lines (where present), publish/refresh date if visible.
   - **AI Overview / AI Mode** — presence (yes/no), the rendered answer text, every cited URL with its visible position in the citation strip, the "Show more" expansion if it triggers without interaction.
   - **People Also Ask** — questions, expanded answer text per question (after a single expansion to capture the dominant answer source), source URLs.
   - **Video pack** — channel, title, URL, position in the SERP.
   - **Image pack** — presence, source URLs sampled.
   - **Product pack / Shopping** — presence and slot count.
   - **Local pack** — presence, count, sponsored vs organic.
   - **Forum block** — Reddit, Stack Exchange, Quora, Hacker News appearances with position.
   - **News box** — outlets, recency.
   - **Ads** — top-ad count, bottom-ad count, shopping-ad count.
4. **Determinism stamp.** Persist the date, time, gl, hl, device, UA, viewport, and the Chromium build to the snapshot's metadata so future diffs distinguish algorithm changes from infrastructure changes.
5. **Schema.** Persist `analyses/serp-snapshots/<query-slug>.<locale>.<device>.json`:

```json
{
  "query": "...",
  "locale": {"country": "US", "language": "en", "gl": "us", "hl": "en"},
  "device": "mobile",
  "captured_at": "2026-04-30T15:21:08Z",
  "ua": "...",
  "viewport": {"w": 412, "h": 915},
  "ai_overview": {"present": true, "cited_urls": [...], "answer_text": "..."},
  "people_also_ask": [...],
  "organic": [{"rank": 1, "url": "...", "title": "...", "snippet": "..."}, ...],
  "video": [...],
  "image_pack": {"present": true, "samples": [...]},
  "product_pack": {"present": false},
  "local_pack": {"present": false, "count": 0},
  "forum_block": [...],
  "news_box": [...],
  "ads": {"top": 2, "bottom": 1, "shopping": 0},
  "screenshot": "analyses/serp-snapshots/<slug>.<locale>.<device>.png",
  "html": "analyses/serp-snapshots/<slug>.<locale>.<device>.html"
}
```

6. **Diff helper.** When a previous snapshot exists for the same `(query, locale, device)`, write `<slug>.<locale>.<device>.diff.md` with rank changes, AI Overview presence delta, citation-set delta, new SERP features, and disappeared SERP features. Phase 9 uses this for confound checks.
7. **Rate limiting.** Respect a polite cadence — random jitter between requests, exponential backoff on 429 / captcha walls. If captcha appears, stop and surface to the user; do not attempt to bypass.

## Output

```
analyses/serp-snapshots/
  <slug>.<locale>.<device>.json
  <slug>.<locale>.<device>.png
  <slug>.<locale>.<device>.html
  <slug>.<locale>.<device>.diff.md       # only when prior snapshot existed
analyses/serp-snapshots/_index.json      # roll-up of all snapshots in this run
```

## Done when

- Every requested `(query, locale, device)` tuple has a JSON record + screenshot + raw HTML.
- AI Overview presence and cited-URL set are explicit (do not silently report "no AIO" if the page just lazy-rendered).
- Diff file exists for every query that had a prior snapshot.
- Metadata captures all determinism inputs.

## Anti-patterns

- Capturing only screenshots — downstream agents need structured fields, not OCR.
- Logging in to a Google account "for cleaner results" — personalization will dominate the snapshot.
- Treating `pws=0` as full incognito — reduce, do not eliminate.
- Skipping the second scroll — AI Overview and PAA frequently render lazily.
- Reporting forum results as "Reddit" without the position — position is the ranking signal that matters.
- Bypassing captcha walls programmatically — escalate and stop.
- Sharing one Chromium profile across many runs — cookie carry-over corrupts the next snapshot.
