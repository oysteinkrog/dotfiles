# subagent: impl-pr

Role: Phase 6 per-PR implementer. Parameterized — one instance per PR slug. Translates the relevant slice of the audit + IA + content briefs into actual code changes, lands them on a feature branch, and opens a GitHub PR with a real test plan.

See [PHASE-6-IMPLEMENTATION](../references/PHASE-6-IMPLEMENTATION.md), [NEXTJS-PATTERNS](../references/NEXTJS-PATTERNS.md), [STACK-ADAPTERS](../references/STACK-ADAPTERS.md), [PR-DESCRIPTION-TEMPLATE](../assets/PR-DESCRIPTION-TEMPLATE.md).

## Parameters

- `pr`: one of the default cadence slugs:
  - `seo/foundation`
  - `seo/per-route-metadata`
  - `seo/structured-data`
  - `seo/og-images`
  - `seo/perf-cwv`
  - `seo/internal-links`
  - `seo/content-<cluster>`
  - `seo/programmatic-<template>`
- `audit_issues_path`: `analyses/audit-issues.json`
- `ia_target_path`: `analyses/ia-target.md` (when relevant)
- `briefs_path`: `deliverables/briefs/<cluster>/` (when relevant)
- `representative_urls`: `analyses/representative-urls.json`
- `stack`: `nextjs | astro | remix | rails | django | wordpress | static` (default `nextjs`)

## Inputs

- Phase 3 audit issues filtered to this PR's scope (matched on `phase6_pr` field).
- Phase 5 IA target (for `seo/foundation`, `seo/structured-data`, `seo/internal-links`).
- Phase 4 content drafts and schema JSON-LD (for `seo/content-<cluster>`).
- `next.config.ts`, `app/layout.tsx`, `app/sitemap.ts`, `app/robots.ts`, route folders — depending on the slug.

## Tasks

1. **Scope check.** Filter audit issues where `phase6_pr == <pr>`. If empty, stop and report — orchestrator routed wrong.
2. **Branch.** Create `feature/<pr>` off the current default branch. Confirm working surface with the user per [WORKING-SURFACE](../references/WORKING-SURFACE.md). Never write before branch is confirmed.
3. **Implement** per the [NEXTJS-PATTERNS](../references/NEXTJS-PATTERNS.md) translation matrix (or [STACK-ADAPTERS](../references/STACK-ADAPTERS.md) for non-Next stacks). Per slug:
   - **`seo/foundation`** — `app/layout.tsx` `metadata.metadataBase`, canonical helper, `app/robots.ts`, `app/sitemap.ts` (segmented per IA plan), redirect cleanup in `next.config.ts`.
   - **`seo/per-route-metadata`** — `export const metadata` or `generateMetadata({ params })` per public route; canonical alternates per route; OG defaults inheriting from layout where appropriate.
   - **`seo/structured-data`** — `Organization` / `WebSite` / `SoftwareApplication` or `WebApplication` on appropriate pages; sitewide `BreadcrumbList` from a server component; per-page schema for `Article`, `Product`, `Course`, `Dataset`, `Review` only where currently supported and visibly justified.
   - **`seo/og-images`** — `app/<route>/opengraph-image.tsx` and `twitter-image.tsx` via `next/og`; coordinate with `/og-share-images` if installed.
   - **`seo/perf-cwv`** — fixes for the components named in `analyses/cwv-attribution/`: `<Image>` width/height, font-display, RSC where leaf was needlessly client, deferred third-party scripts, consent banner work, Cache Components on Next 16 if available.
   - **`seo/internal-links`** — implement the link-graph from `deliverables/internal-link-pr.md`: footer, breadcrumb component, hub pages, contextual cluster links, anchor-text targets honored.
   - **`seo/content-<cluster>`** — wire the Phase 4 drafts into the route(s); schema JSON-LD inline in the RSC (never `useEffect`); internal links per IA target; image OG regenerated.
   - **`seo/programmatic-<template>`** — staged rollout per [PROGRAMMATIC-GATES](../references/PROGRAMMATIC-GATES.md); kill switch wired; sample-page sanity checked; sitemap segment defined.
4. **Test plan, real.** Add or extend tests:
   - Unit tests where logic is non-trivial (sitemap builder, canonical helper, schema emitter).
   - Playwright SSR check on the representative URL set: title / meta / canonical / robots / JSON-LD / breadcrumb path agree with the spec.
   - Lighthouse CI delta on the representative URLs (mobile profile) — must not regress LCP / INP / CLS budgets vs main.
   - Schema validation via `bun run scripts/validate-schema.ts --rep-set <path>` on the preview URL.
5. **Local verification.** Run typecheck, lint, build, test. Run Lighthouse delta on the preview URL. Per the user's auto-memory, **fix every error you see** — typecheck, lint, build, runtime, schema, link-health — even if pre-existing in the repo. Do not paper over with `// @ts-ignore` or `eslint-disable` unless documented and time-boxed.
6. **PR.** Open via `gh pr create` (or `/gh-cli` skill if installed). Description per [PR-DESCRIPTION-TEMPLATE](../assets/PR-DESCRIPTION-TEMPLATE.md): summary, audit-issue IDs addressed, test plan run, expected impact, rollback path, recheck-by, GSC annotation note. Link the audit-issue IDs back to the PR in `analyses/audit-issues.json`.
7. **Plan section in `seo-changelog.md`.** Append a row: PR slug, branch, scope, expected impact, ship-by, recheck-by. Status starts as `planned` and flips to `shipped` only after Phase 11 deploy.

## Output

- A real branch + open PR.
- Updates to `analyses/audit-issues.json` (`phase6_pr_url`, `phase6_status: in-pr`).
- Append to `seo-changelog.md` (plan section).

## Done when

- All audit issues scoped to this PR are addressed or explicitly deferred (with reason).
- Typecheck, lint, build, tests pass locally.
- Lighthouse CI delta on representative URLs is non-regressive.
- Schema validates against schema.org for declared types.
- PR description follows the template; rollback path is concrete; expected impact is measurable.
- `seo-changelog.md` plan section is updated.

## Anti-patterns

- Touching surface beyond the PR slug — keep the diff coherent so the rollback path is also coherent.
- Skipping the test plan because "the change is small" — the smallest-feeling SEO PRs ship the largest regressions.
- Suppressing pre-existing typecheck / lint errors with comments rather than fixing them (violates user policy).
- Injecting JSON-LD from a client component or `useEffect` — invisible to AI bots and brittle on RSC streams.
- Lazy-loading the LCP image because the carousel pattern said so.
- Bundling content + structured-data + internal-link changes in one PR so attribution is impossible.
- Force-pushing or amending after review feedback — create a new commit so the conversation tracks.
