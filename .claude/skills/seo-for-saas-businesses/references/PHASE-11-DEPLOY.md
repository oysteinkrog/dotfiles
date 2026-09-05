# PHASE 11 — DEPLOYMENT & VERIFICATION

Goal: ship the PRs and reset baselines correctly.

## Pre-deploy checks

- [ ] Phase 10 returned two clean passes.
- [ ] Lighthouse CI green vs main on representative URLs.
- [ ] Schema validation green.
- [ ] AI-crawler view contains headline answer + three unique data points on priority pages.
- [ ] CODEOWNERS approvals received.
- [ ] User has authorized the deploy.

## Deploy via Vercel

Use `/vercel:deploy` skill. Production deploy requires explicit user invocation:

```bash
# Preview deploy (automatic on PR)
# already happens via Vercel integration

# Production deploy — user runs this
vercel --prod
```

Or `/vercel:deploy prod`.

## Post-deploy immediate actions

1. **Annotate**: append to `seo-changelog.md` with timestamp, PR scope, expected impact, recheck-by.
2. **GSC annotation**: in Search Console, add a comment / note via the appropriate property; or maintain `analyses/gsc-annotations.md` paired with GA4.
3. **GA4 annotation**: add an event for the deploy.
4. **Submit updated sitemaps**: GSC → Sitemaps → resubmit each segment (or wait for ping if `lastmod` is honest).
5. **Bing**: resubmit sitemap.
6. **Request indexing** on highest-priority new URLs (rate-limit; do not abuse — GSC will throttle).
7. **Rank-tracker baseline reset** with annotation.

## Use `/github` for the PR flow

```bash
gh pr merge <num> --squash --delete-branch
gh issue close <num> --comment "Shipped in <pr-url>"
```

Per AGENTS.md "Landing the Plane" protocol:

```bash
git pull --rebase
br sync --flush-only
git add .beads/
git commit -m "sync beads"
git push
git status   # should show "up to date with origin"
```

## Post-deploy 7-day window

- Day 0: GSC URL inspection on top 5 new / changed URLs to confirm rendering and structured data look right.
- Day 1: Watch GSC coverage for new errors.
- Day 3: Re-run `scripts/verify-prod.ts` (Phase 12).
- Day 7: Initial impressions / clicks deltas in GSC; first signal of impact.

## Rollback

If a deploy regresses traffic, indexation, or CWV materially, roll back:

- Code: `git revert <merge-sha>` and ship as a follow-up PR; or revert via Vercel deployment promote.
- Programmatic: flip the kill-switch flag (sitemap removal + `noindex,follow` + optional 301 to parent).
- Annotate the revert in `seo-changelog.md` with reason.

## Anti-patterns

- Ship without annotation. Future traffic moves become unattributable.
- Request indexing on hundreds of URLs at once. GSC will throttle and queue some out.
- Promote winning experiment site-wide on the same deploy as a separate batch of changes. Confounds attribution.
- Skip `git push` because "the merge is enough". Per AGENTS.md, work is not complete until push succeeds.
- Skip rank-tracker baseline reset; trend lines mix pre/post change behaviour.
