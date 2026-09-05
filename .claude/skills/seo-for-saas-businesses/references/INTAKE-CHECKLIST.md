# INTAKE-CHECKLIST

Before any phase runs, capture the substrate. Save to `analyses/intake.md`.

## Project location

- [ ] Absolute path to the SaaS repo on this machine.
- [ ] Branch the user is currently on; default branch (usually `main`).
- [ ] Working tree clean? If not, what is in flight (other agents, in-progress feature work)?
- [ ] Framework + version: Next.js (which version? `package.json`), Astro, Remix, Rails, Django, WordPress, static site, other.
- [ ] Package manager: bun (preferred) → pnpm → npm → yarn. Use `/bun` skill if installed.
- [ ] Hosting: Vercel? Self-hosted? Cloudflare Pages / Workers? AWS? GCP?
- [ ] CDN / WAF in front: Cloudflare? Vercel Edge? Akamai? Fastly?
- [ ] DNS provider (matters for redirect / locale routing): Cloudflare? Route 53? Vercel?

## Public URLs

- [ ] Production URL.
- [ ] Staging / preview URL (if any).
- [ ] Marketing site URL if separate from app URL (common: `marketing.example.com` vs `app.example.com`, or `example.com` vs `app.example.com`).
- [ ] Subdomain inventory: blog, docs, status, changelog, careers, support.

## Analytics & search properties

- [ ] Google Search Console — domain property or URL-prefix property? Verified for which user(s)?
- [ ] Bing Webmaster Tools — verified?
- [ ] GA4 property ID; conversion events configured?
- [ ] Plausible / PostHog / Fathom present?
- [ ] Rank tracker subscription? Source of truth for SERP positions?
- [ ] CrUX API key (free) for field CWV?
- [ ] BigQuery export from GSC (T3+)?
- [ ] Server log access? (T3+ only — Vercel logs, CloudFront, Cloudflare, NGINX)

If any of GSC / GA4 / Bing is missing: offer to wire now per [WIRING-OBSERVABILITY](WIRING-OBSERVABILITY.md). Do not skip.

## SEO maturity

- [ ] Existing SEO program / agency / consultant?
- [ ] Existing content calendar?
- [ ] Existing keyword list?
- [ ] Existing competitor list?
- [ ] Recent traffic events (post-deploy drops, core-update overlap, manual actions)?
- [ ] Known-broken templates or routes?

## Working surface decision

Default = feature branch on existing repo, one PR per phase logical group. Confirm and capture.

## Git remote & PR flow

- [ ] GitHub / GitLab / Bitbucket? `gh` CLI available and authenticated?
- [ ] Required reviewers / CODEOWNERS for `app/`, `next.config.*`, `middleware.*`?
- [ ] CI provider (GitHub Actions / Vercel preview / other)?

## Beads / issue tracking

- [ ] `br` available? `.beads/` present? If so use the [/beads-workflow](/beads-workflow) skill.
- [ ] Otherwise, GitHub issues. Create a label `seo` and milestones per phase.

## Skill availability

Run `jsm list` (if installed). Check that these are available; install if missing and `jsm` authenticated:

- og-share-images, creating-share-images
- de-slopify
- ab-testing
- ga4
- vercel, vercel:next-cache-components, vercel:deployments-cicd
- supabase, supabase:supabase-postgres-best-practices
- github
- ubs
- ux-audit
- idea-wizard

Missing skills go in `analyses/skill-availability.md`. The phases that need them list manual fallback paths.

## Sign-off

Before proceeding to Phase 1, confirm with the user:

1. Working surface (branch / worktree / direct).
2. PR cadence (one per logical group, one mega PR, separate repo).
3. Authorization to ship to production via `/vercel:deploy prod` (default: never without explicit per-deploy confirmation).
4. Authorization to wire missing observability (default: ask once, then proceed).
