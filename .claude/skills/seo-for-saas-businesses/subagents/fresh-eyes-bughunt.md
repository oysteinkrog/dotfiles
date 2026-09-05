# subagent: fresh-eyes-bughunt

Role: Phase 10 — independent review of the diff with no prior context.

## Inputs

- The branch / PR set (e.g. `seo/foundation`, `seo/per-route-metadata`, `seo/structured-data`).
- The audit-issues this PR set is supposed to address.
- The representative URL set.

## Approach

Treat the diff as if you weren't in the planning meeting. Read every changed file. Look for:

### Rendering-mode mistakes
- A component that should be a Server Component is a Client Component (`"use client"` at the top of something used in a marketing page).
- JSON-LD injected from `useEffect`.
- `app/sitemap.ts` returns dynamic content but doesn't await async data.
- `generateMetadata({ params })` not awaiting `params` (Next.js 16 requires await).

### Route-group regressions
- A new `app/(group)/layout.tsx` accidentally inherited from a parent that sets `noindex`.
- A route moved between groups but its metadata didn't follow.
- Locale prefix `[locale]` accidentally applied to a route that should not be localized.

### Structured-data drift
- A schema property removed without explanation.
- `aggregateRating` claiming reviews the page doesn't visibly contain.
- `Article.author` as a string instead of a `Person` object.
- Schema's price disagrees with rendered price.

### Edge / redirect ordering
- A `next.config.ts` redirect that masks a route the new content depends on.
- Middleware matcher accidentally including `/_next/`, `/api/og/`, or static assets.
- Trailing-slash inconsistency between sitemap and canonical.

### CWV regressions
- A new shared component imports a chart library on a marketing route.
- A new image without `width` / `height` causes CLS.
- Lazy-loaded LCP image.
- New consent banner mounts before LCP and blocks main thread.

### Tests / CODEOWNERS / build
- Missing tests for new metadata generation logic.
- Missing CODEOWNERS for `app/(marketing)/` or `next.config.*`.
- Build doesn't verify (`bun run build`).

## Output

- `analyses/fresh-eyes/pass-N/bughunt.md` — findings as audit items.

Each finding follows the audit-item format. Include: file, line numbers, exact issue, proposed fix.

## Anti-patterns

- Reviewing only the PR description.
- Skimming over files because "it looks fine".
- Not actually running the build / tests.
- Marking every finding `critical` or every finding `low` — earn the severity.
