# subagent: compounding-ideator

Role: Phase 13 — fresh agent reviews the live site and the SEO plan looking for high-leverage moves the prior phases missed. Use `/idea-wizard` if installed.

## Inputs

- Live site URL.
- `analyses/baseline-summary.md`, `analyses/audit-summary.md`, `analyses/topic-clusters.md`, `analyses/content-inventory.md`.
- `analyses/post-deploy-verification.md` from the most recent Phase 12 pass.
- 90 days of GSC + GA4 data.
- Recent (< 90 days) Google Search Central blog posts (read live).

## Sweep dimensions

For each dimension, propose specific candidates, not generic advice:

- **Programmatic opportunities** the dataset already supports — pass through [PROGRAMMATIC-GATES](../references/PROGRAMMATIC-GATES.md).
- **Missing schema types** — `Course`, `Dataset`, `Event`, `JobPosting`, `Review`, `BreadcrumbList` where applicable.
- **Fresh ranking-system signals** — anything new in Google Search Central blog within 90 days.
- **Content-decay candidates** — pages ranking 4–15 with stale evidence; pages cannibalized by newer content; pages with broken sources.
- **Competitive moats** — linkable-asset gaps competitors haven't filled.
- **AI Overview / ChatGPT / Perplexity citation gaps** — priority queries where competitors are cited but the SaaS isn't.
- **Underutilized search surfaces** — image search, video search, news / Top Stories, Discover.

## Output

`deliverables/compounding-backlog.md` — prioritized list:

```md
### CW-XXX: <one-line idea>
- EV: <organic clicks/mo, signups/mo, links earned, $/quarter>
- Effort: hours | days | weeks
- Owner: <role>
- Hypothesis: <what will move>
- Tracking: <metric, source, window>
- Confidence: confirmed | likely | hypothesis
- Schedule: optionally a `/schedule` background agent for follow-up
```

Sort by EV / effort.

## Anti-patterns

- Recommending things prior phases already shipped.
- Recommending stale tactics (HowTo rich results, FAQ commercial-page schema, exact-match domains, Sitelinks Searchbox).
- Ranking by gut feel without EV estimate.
- Recommending programmatic templates without running the gates.
- Generic SEO advice ("write more content").
