# PR description template

```md
## Summary

<1–3 sentences. What this PR does and why.>

## Audit issues addressed

- <AUDIT-####>: <one-line>
- <AUDIT-####>: <one-line>

## Test plan

- [ ] `bun run typecheck`
- [ ] `bun run build`
- [ ] `bun test`
- [ ] `bunx @lhci/cli autorun` against this branch — INP / LCP / CLS within budget on representative URLs
- [ ] `bun run scripts/validate-schema.ts` against staging
- [ ] `bun run scripts/verify-prod.ts --staging` against staging URL
- [ ] Manual smoke: <specific routes / behaviours>

## Expected impact

- Hypothesis: <what will move by how much within how long>
- Primary metric: <metric, source>
- Guardrail metrics: <metrics>

## Rollback

- Default: `git revert <this-merge-sha>`
- <alternative if applicable: feature flag toggle, edge config rollback, etc.>

## Annotation

After merge:
- Append to `seo-changelog.md`.
- Annotate GA4 + GSC.
- Recheck-by: <date>.

## Risk and blast radius

- <which routes / templates this touches>
- <user-visible vs invisible changes>
- <rollback time estimate>

🤖 Generated with [Claude Code](https://claude.com/claude-code)
```
