---
name: a11y-auditor
description: Runs axe-core + Nielsen-heuristics accessibility audit against the deployed docs site. Fixes any critical violations.
---

# Accessibility Auditor

Runs in Phase 9 (or on-demand in Phase 6c). The goal: zero critical axe violations on every sampled page.

## Inputs

- `{BASE_URL}` — live URL of the docs site (local dev or deployed)
- `{SAMPLE_PAGES}` — representative paths to scan; default `["/","/overview/what-is-this","/overview/architecture"]`

## Workflow

1. Run `./scripts/a11y-check.sh {BASE_URL} {SAMPLE_PAGES...}`. Parse output.
2. For each violation:
   - **Critical / Serious**: fix in the codebase. Typical fixes:
     - Missing alt text → add to MDX images.
     - Color contrast → adjust theme tokens in `globals.css`.
     - Missing skip-to-content link → add to `app/layout.tsx` (see [ADVANCED-NEXTRA.md § 20](../references/ADVANCED-NEXTRA.md#20-accessibility-defaults)).
     - Form labels missing → add to any custom form components.
     - Heading skips → renumber headings.
     - Keyboard trap → ensure all interactive components expose `tabIndex` + `onKeyDown`.
   - **Moderate**: file as a follow-up unless quick to fix.
   - **Minor**: log only.

3. Nielsen pass (manual, since heuristics need judgment):
   - **Recognition over recall**: is every interactive control labeled?
   - **Error messages**: does the 404 page suggest next steps?
   - **Consistency**: same component for same job (always `<Callout>` for warnings)?
   - **Keyboard navigation**: tab through every page; does focus visually indicate?
   - **Mobile**: touch targets ≥44×44px; sidebar opens via tap.

4. Re-run axe after fixes. Target: zero critical, zero serious.

5. Log results to `phase9_a11y_report.md`:
   ```markdown
   # a11y audit (2026-04-22T17:30:00Z)

   Pages sampled: /, /overview/..., /reference/...

   ## Before
   - Critical: 2
   - Serious: 5
   - Moderate: 11

   ## Fixes applied
   - Added skip-to-content link in app/layout.tsx
   - Raised text contrast on dark-mode code blocks (4.1:1 → 5.2:1)
   - Added alt text to 7 architecture diagrams

   ## After
   - Critical: 0
   - Serious: 0
   - Moderate: 3 (filed as follow-ups)
   ```

## Cross-reference

- Detailed WCAG AA targets: [QUALITY-METRICS.md § Accessibility](../references/QUALITY-METRICS.md)
- Nielsen heuristics mapping: [QUALITY-METRICS.md § Nielsen heuristics mapping](../references/QUALITY-METRICS.md#nielsen-heuristics-mapping-for-ux-audit-equivalents)
- If `/ux-audit` skill is installed, prefer it for the Nielsen pass.

## Don't do

- Suppress axe rules without justification — if you disable a rule, log why
- Fix on dev only — deploy fix and re-run against production URL
- Stop at "no critical" — serious is almost as bad for many users
