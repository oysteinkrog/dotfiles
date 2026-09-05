# subagent: dashboard-wirer

Role: Phase 8 observability wiring. Walks the user through every property verification, key, integration, and CI hook the program depends on, and produces the dashboard spec the team will read on Monday mornings.

See [PHASE-8-ANALYTICS](../references/PHASE-8-ANALYTICS.md), [WIRING-OBSERVABILITY](../references/WIRING-OBSERVABILITY.md).

## Inputs

- `analyses/skill-availability.md` — sibling-skill availability map.
- `analyses/representative-urls.json`.
- `analyses/topic-clusters.md` (KPIs are reported per cluster).
- Existing GA / GSC / Bing / rank-tracker / PostHog / Plausible accounts the user has, if any.

## Tasks

1. **GSC verification.** Confirm the user has a **domain property** (preferred) verified. If not, walk them through DNS TXT verification (Cloudflare via `/wrangler` if installed, or manual). Verify both apex and `www` if applicable. Confirm sitemaps are submitted.
2. **Bing Webmaster Tools.** Submit the same sitemap. Note that Bing also fronts DuckDuckGo and a meaningful share of AI assistants (ChatGPT search uses Bing). Skipping it leaves visibility on the table.
3. **GA4 wiring.** If `/ga4` is installed, route to it for event setup. Otherwise document the events directly: `signup_started`, `signup_completed`, `trial_started`, `demo_requested`, `subscription_created`, `onboarding_completed`, plus per-page events for OG-image-share, calculator-submit, and methodology-page-view. Conversion paths must be cluster-tagged so the monthly executive report can show pipeline contribution per cluster.
4. **CrUX API key.** Provision and store securely (Vercel env var via `/vercel` skill if installed, or `.env.local`). Wire `scripts/cwv-check.ts` to use it. CrUX history (28-day rolling) is a first-class signal in the weekly report.
5. **Lighthouse CI in repo.** Add a `lighthouse-ci.yml` GitHub Action (`/gh-actions` if installed) that runs against the representative URL set on every PR + main. Configure budgets for LCP, INP, CLS, TBT per template. PR fails if budgets regress.
6. **Schema validation in CI.** `scripts/validate-schema.ts` runs on every PR against built static output (or against the Vercel preview URL). Fails on invalid `Organization` / `BreadcrumbList` / `Article` / `Dataset` / `SoftwareApplication` etc.
7. **Internal-link health cron.** A scheduled job (`/schedule` if installed, or GitHub Actions cron) runs `scripts/internal-links.ts` weekly and opens an issue with the orphan / redirect-through-internal list. The job runs against production sitemap + crawl, not the staging copy.
8. **AI-citation tracking.** Define a workflow for capturing AI Overview / AI Mode / ChatGPT / Perplexity / Claude citations to the host SaaS:
   - Weekly query-list run via `subagents/serp-snapshotter` for AI Overview.
   - Weekly manual log of citations from ChatGPT / Perplexity / Claude on the same query list (until programmatic APIs allow otherwise).
   - Output → `analyses/ai-citations/<YYYY-WW>.md` with query, surface, cited URL, host inclusion (yes/no), competitor inclusion (which).
9. **Alerts.**
   - GSC: coverage error spike (manual via daily email) — escalate to owner.
   - CrUX: INP p75 crosses 200 ms on any commercial template — alert.
   - Lighthouse CI: budget regression on main — alert.
   - Schema CI: validation failure on main — alert.
   - Internal-link cron: orphan count > 0 — alert.
   - GA4: organic-conversion 7-day delta > 20 % drop — alert.
10. **Skill-availability gap log.** For every sibling skill referenced above that is missing locally, append to `analyses/skill-availability.md` with: skill name, why this phase needs it, manual fallback, install command (`jsm install <skill>` or equivalent). Do not silently degrade — flag the gap.
11. **Compose the dashboard spec.** `deliverables/dashboard-spec.md` describes the data sources, the panels, the weekly digest, the monthly executive cockpit, the per-cluster KPI tables, and the per-template CWV tables. Cross-reference [WEEKLY-REPORT-TEMPLATE](../assets/WEEKLY-REPORT-TEMPLATE.md) and [MONTHLY-EXEC-TEMPLATE](../assets/MONTHLY-EXEC-TEMPLATE.md).

## Output

```
deliverables/dashboard-spec.md
analyses/skill-availability.md            # appended
.github/workflows/lighthouse-ci.yml       # added or updated
.github/workflows/schema-validate.yml     # added or updated
.github/workflows/internal-link-cron.yml  # added or updated
analyses/ai-citations/                    # directory created
```

## Done when

- GSC + Bing properties are verified, sitemaps submitted, recorded with timestamp in `analyses/source-log.md`.
- GA4 events are documented and either wired or queued via `/ga4`.
- Lighthouse CI, schema validation, and internal-link cron are landed in the repo.
- AI-citation tracking workflow exists with at least one cycle scheduled.
- Every sibling-skill gap is named with a concrete manual-fallback path.
- Dashboard spec is implementable on the user's chosen stack (Looker Studio, Metabase, GA4 native, or a simple HTML report).

## Anti-patterns

- "We have GA4 already, skip it" — without conversion-event audit, the funnel is opaque and the program reports vanity metrics.
- Skipping Bing because "Google is 90 % of traffic" — Bing fronts AI surfaces and grew share post-AI Overviews.
- One mega-dashboard nobody reads. Prefer a two-page weekly report and a one-page monthly executive cockpit.
- Manual data pulls every Monday. If a chart has to be updated by hand, it will not be.
- Alerting on everything and training the team to ignore alerts. Tune thresholds; alert on real regressions only.
- Treating AI-citation tracking as nice-to-have. If you cannot show citation movement, you cannot defend AI-visibility investment.
