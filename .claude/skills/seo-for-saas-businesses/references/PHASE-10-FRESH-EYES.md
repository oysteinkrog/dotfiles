# PHASE 10 — FRESH-EYES REVIEW & QA

Goal: independent verification before deploy. Two clean passes in a row before Phase 11.

## The three fresh-eyes prompts (run as separate subagents)

### 1. Bug-hunt the new code

`subagents/fresh-eyes-bughunt.md`. Spawn an Explore agent with no prior context on the work. Prompt:

> Review the diff for PRs <list>. Treat them as if you're the senior engineer who wasn't in the planning meeting. Flag: rendering-mode mistakes (CSR where SSR was needed), route-group regressions, structured-data drift, edge-redirect ordering, CWV regressions hidden in shared components, missing CODEOWNERS, missing tests, broken imports. Do not skim. Read every changed file. Report findings as audit items.

If the diff touches navigation, routing, modals, overlays, filters, ads, affiliate redirects, consent flows, or `history.pushState` / `history.replaceState`, add a back-button-hijacking check: browser Back must immediately return to the previous page and must not land on an inserted deceptive page or loop.

### 2. Randomly trace files for issues

`subagents/fresh-eyes-trace.md`. Sample N files from the diff and trace them end-to-end:

> Pick 5 random files from the PR diff. For each, trace the full data flow: server fetch → render → network → DOM → measurement. Look for: hydration mismatches, missing error handling at the boundary, unverified inputs from URL params, schema mismatches, INP-leaking patterns, data fetching that should be server-only running on the client. Report findings as audit items.

For any sampled file that changes client navigation state, trace browser-history behavior as part of the flow: initial URL → interaction → Back → expected prior URL.

### 3. Review fellow agents' work

`subagents/fresh-eyes-cross-review.md`. Each cluster writer reviews another cluster's draft:

> Cluster A writer reviews Cluster B's draft for: factual accuracy, brand-voice fit, slop patterns, hidden cannibalization, citation eligibility (3+ unique data points visible without JS), proof-link freshness, schema-content agreement, conversion path. Cluster B writer reviews Cluster A. Report findings.

## Tooling pass

In addition to the three prompts:

- `bun run typecheck`
- `bun run lint`
- `bun run build`
- `/ubs <changed-files>` — Ultimate Bug Scanner if installed.
- `bun test` — unit + Playwright SSR checks.
- `bun run scripts/validate-schema.ts` against staging.
- `bunx @lhci/cli@latest autorun` against staging.
- `bun run scripts/ai-crawler-view.ts --rep-set ...` against staging.

## Iteration rule

Findings → fix → re-run all three prompts + tooling pass. Two consecutive clean passes (no new findings) before Phase 11.

A *clean pass* means: zero `critical` or `high` findings; remaining `medium`/`low` items are queued for the next Phase 6 cycle, not blockers.

## Anti-patterns

- Treating fresh-eyes as a rubber stamp (writer reviews own work).
- Skipping when there's deadline pressure.
- One pass and ship.
- Not re-running tooling after fixes.
- Counting "no critical findings" as a clean pass when there are several `high` items pending.

## Outputs

- `analyses/fresh-eyes/<pass>/<reviewer>.md` — per-pass per-reviewer findings.
- `analyses/fresh-eyes/summary.md` — gate decision.
