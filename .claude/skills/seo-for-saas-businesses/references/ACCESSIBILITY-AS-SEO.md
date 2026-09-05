# ACCESSIBILITY-AS-SEO

## TOC

Why this lives in an SEO skill · WCAG 2.2 AA pragmatic core checks · axe-core in CI · Procurement implication · Conversion impact · Common SaaS app patterns that fail · Mobile readability and touch · Tier depth selectors · Anti-patterns · Cross-links

Accessibility is SEO-adjacent revenue work. Bad accessibility is a procurement blocker for enterprise / regulated / public-sector / EU / healthcare / education buyers, a conversion drag on every visitor, a structural-readability problem search engines reward against, and (separately) a legal-exposure surface. Treating it as a "design polish" item is the cheapest way to keep losing deals you don't realize you're losing.

Phase mappings: Phase 3 (audit), Phase 6 (fix in code; PR per route group), Phase 8 (regression alarms via axe-core in CI), Phase 12 (post-deploy accessibility check).

## Why this lives in an SEO skill

- Semantic HTML + heading hierarchy + descriptive labels improve crawlability and machine extractability.
- Keyboard / screen-reader access correlates with mobile UX (ranking factor) and "page experience" signals (`likely`).
- Procurement reviews ask for VPATs / WCAG 2.2 AA conformance — a missing artifact loses deals.
- AI engines extract content from `<table>` / `<dl>` / `<figure>` / labelled forms more reliably than from `<div>` soup.

## WCAG 2.2 AA — pragmatic core checks

| Check | What to verify | Tool |
|---|---|---|
| Color contrast 4.5:1 (normal) / 3:1 (large) | Body, links, captions, button text, status colors | axe-core, contrast-finder |
| Visible focus indicators | Tab through every interactive element | Manual; Chrome DevTools |
| Keyboard reachability | Every action available without mouse | Manual; aria-screen-reader pairings |
| Skip-to-content link | First focusable element on the page | Manual |
| Headings logical hierarchy | One `<h1>`; no jumps from `<h2>` to `<h4>` | axe-core; HeadingsMap |
| Form labels | Every `<input>` has `<label>` (visible or `aria-label`) | axe-core |
| Form errors | Error messages associated with field via `aria-describedby` and announced | Manual + screen reader |
| Image alt | Informative images have alt; decorative `alt=""` | axe-core |
| Touch targets | ≥ 24×24 CSS px (2.5.8) or with adequate spacing | Manual |
| Color-only meaning | Status / required / error not signalled by color alone | Manual |
| Motion respect | `prefers-reduced-motion` honoured | Manual + DevTools |
| Language declared | `<html lang="en">` (or correct locale) | Manual |
| Page title unique and descriptive | First word ≠ generic | Crawl |
| Link purpose from text alone | "Click here" replaced with descriptive text | axe-core |
| Captions / transcripts on video | Audio content has text alternative | Manual |

(`confirmed` per WCAG 2.2 AA; verify against current spec at `w3.org/WAI/WCAG22/quickref/` per [VERIFICATION-FIRST](VERIFICATION-FIRST.md).)

## axe-core in CI

```ts
// playwright/a11y.spec.ts
import { test, expect } from "@playwright/test";
import AxeBuilder from "@axe-core/playwright";

const REPRESENTATIVE = ["/", "/pricing", "/security", "/integrations", "/blog/post-x"];

for (const path of REPRESENTATIVE) {
  test(`a11y: ${path}`, async ({ page }) => {
    await page.goto(`http://localhost:3000${path}`);
    const results = await new AxeBuilder({ page }).analyze();
    const serious = results.violations.filter((v) => ["serious", "critical"].includes(v.impact ?? ""));
    expect(serious, JSON.stringify(serious, null, 2)).toEqual([]);
  });
}
```

CI gate: PR fails on new serious / critical violations. (`confirmed` — most effective single control on accessibility regression.) Pair with `/ux-audit` for the heuristic / manual layer.

## Procurement implication

Many B2B buyers explicitly require:

| Document / artifact | Required for |
|---|---|
| VPAT (Voluntary Product Accessibility Template) 2.5 | Federal procurement (US Section 508); enterprise |
| WCAG 2.2 AA conformance statement | EU public sector (EAA / EN 301 549); UK; Canada |
| Accessibility roadmap | Enterprise procurement asks for visible commitment |
| Latest accessibility audit / report | Enterprise; HE / education |
| ARIA / WAI-ARIA conformance details | Federal accessibility reviews |

A SaaS without any of these loses by default in regulated procurement. Mid-tier companies discover this when their first big deal stalls in legal review. (`confirmed` — common pattern in B2B SaaS deal-stage analytics.)

The procurement deliverable lives at `/security/accessibility` (or `/legal/accessibility`) and links to the latest VPAT, audit, statement, and the public accessibility statement. See [LIFECYCLE-CONTENT](LIFECYCLE-CONTENT.md) for procurement-page patterns.

## Conversion impact

Accessibility issues that quietly bleed conversions:

| Issue | Conversion drag |
|---|---|
| Invisible focus indicator on CTA button | Keyboard / power-user signups never start |
| Pricing toggle not keyboard-reachable | Comparing plans abandoned silently |
| Form errors only by red border | Accessibility users never resolve; bounce |
| Modal traps focus inside but no escape | User stuck; abandons |
| Cookie banner blocks page until interacted | High-bounce; fastest-to-bounce signal |
| Tooltip carries critical info | Touch-only / screen-reader users miss it |
| Dropdown that requires hover | Mobile / keyboard users can't reach |

Removing one of these on a high-traffic template typically moves conversion measurably (`likely` — varies; instrument and A/B test the fix). See [PHASE-9-EXPERIMENTATION](PHASE-9-EXPERIMENTATION.md).

## Common SaaS app patterns that fail

| Pattern | Failure | Fix |
|---|---|---|
| Dashboard table with no row headers | Screen reader cannot navigate row context | `<th scope="row">` for the first cell |
| Tooltip-only critical info ("Click to see why") | Touch users can't access; AI bots can't extract | Move critical info into the body |
| Custom `<div>`-based select without keyboard | Tab/space/arrows don't work; screen reader reads "..." | Native `<select>` or `headlessui` Combobox; ARIA combobox + `role="listbox"` + keyboard handlers |
| Modal that traps but no Escape | Stuck modal; rage-quits | Esc + `aria-modal="true"` + focus trap with restore on close |
| Form errors without `aria-live` / `aria-describedby` | Error not announced; user retries blindly | `aria-describedby` on input pointing to error text; error region `role="alert"` |
| Carousel with no pause control | Vestibular issues; auto-advance distracting | Pause control; respect `prefers-reduced-motion` |
| "Loading..." spinner with no `aria-live` | Screen reader doesn't notice; user thinks page froze | `aria-live="polite"` on a status region |
| Icon button (just `<button><svg /></button>`) | Screen reader says "button" with no purpose | `aria-label` on the button or visually-hidden text |
| `<a href="#">` for buttons | Screen reader reads as link; semantically wrong | `<button>` for actions, `<a>` for navigation |
| Sticky header that hides skip-to-content target | Anchor link "lands behind" the header | `scroll-margin-top` on targets |
| Text inside `<canvas>` chart | Not extractable by screen readers or AI | `<table>` companion; or accessible chart library (Visx with ARIA, etc.) |
| Color-only status (red/green badge with no text) | Color-blind / screen-reader users miss state | Text label + icon + color |
| Required-field marked only by red asterisk | Non-visible | "Required" text or `aria-required="true"` + visible "(required)" |
| Pricing comparison with hover-only details | Mobile / keyboard / screen-reader users can't access | Always-visible details OR keyboard-accessible disclosure |
| Inaccessible date picker | Forms abandoned | Native `<input type="date">` first; only custom if necessary |

## Mobile readability and touch

| Check | Value |
|---|---|
| Body text ≥ 16 px (mobile) | `confirmed` reading-comfort baseline |
| Line length 50–80 chars | Accessibility + reading speed |
| Touch targets ≥ 24×24 CSS px (WCAG 2.2) or ≥ 44×44 (Apple HIG) | Use the larger value where possible |
| Tap-target spacing | Avoid double-taps; ≥ 8 px gap |
| No horizontal scroll (`overflow-x: hidden`) | At any tested viewport width 320 px+ |
| Forms zoom-friendly | `<meta name="viewport">` does not include `user-scalable=no` |

## Tier depth selectors

| Tier | Accessibility scope |
|---|---|
| T1 | Color contrast + alt + form labels + heading hierarchy on commercial pages; manual audit |
| T2 | + axe-core on CI for representative URL set; first VPAT-equivalent statement |
| T3 | + axe-core per-PR; manual + screen-reader pass quarterly; published accessibility statement; first formal VPAT |
| T4 | + Continuous monitoring (axe Monitor / Pa11y CI); annual external audit; public roadmap; multi-locale; localized accessibility statements |

## Anti-patterns

| Don't | Why | Do instead |
|---|---|---|
| Treat accessibility as "design polish" | Loses deals; legal exposure; conversion drag | Treat as procurement-blocking; CI-enforced |
| Run axe-core only on the homepage | Most violations are on auth / dashboard / app surfaces | Per-route axe-core in CI |
| Add `aria-label="image"` to every image | Redundant for screen readers; pollutes accessibility tree | `alt` for `<img>`; `aria-label` only on interactive elements |
| `aria-hidden="true"` on a focusable element | Hides from accessibility tree but still focusable; broken state | If hiding, also `tabindex="-1"`; better, don't hide |
| `tabindex` values > 0 | Disrupts natural tab order | `tabindex="0"` only when needed; never positive |
| Custom focus styles that disable browser default | Focus invisible | `:focus-visible` styles + browser default fallback |
| Auto-play video / carousel without pause | Vestibular / cognitive accessibility violation | Respect `prefers-reduced-motion`; pause control |
| Color-only error / status | Inaccessible to color-blind users | Color + text + icon |
| Inaccessible "we'll fix it later" mode | Compounds; never gets fixed | Block new accessibility regressions in CI |
| VPAT generated by AI without testing | Misrepresents conformance; legal risk | Real audit with named auditor and date |
| Skip-to-content link visually hidden but not at the top of the DOM | Doesn't work for keyboard users | First focusable element; visible on focus |
| `placeholder` as label | Vanishes on input; some screen readers skip | Real `<label>`; placeholder is supplementary at most |
| `<div role="button">` instead of `<button>` | Lacks default keyboard / accessibility behaviour | Native `<button>`; only role when truly needed |
| Modal that puts focus on Close button | First-action confusion; escape-via-tab broken | Focus the modal title or first input; escape returns focus |
| "Accessibility statement" that is one paragraph | Procurement asks for specifics | Real statement: standards conformed to, known gaps, contact, last reviewed |

## Cross-links

- [PHASE-3-TECHNICAL](PHASE-3-TECHNICAL.md) — accessibility as audit area.
- [PHASE-6-IMPLEMENTATION](PHASE-6-IMPLEMENTATION.md) — accessibility fixes per route group.
- [LIFECYCLE-CONTENT](LIFECYCLE-CONTENT.md) — `/security/accessibility` and procurement pack.
- [TRUST-INFRASTRUCTURE](TRUST-INFRASTRUCTURE.md) — accessibility statement as trust evidence.
- [IMAGE-PERF-COOKBOOK](IMAGE-PERF-COOKBOOK.md) — alt text, decorative `alt=""`.
- [INP-DEEP-DIVE](INP-DEEP-DIVE.md) — accessibility-friendly interactions tend to be lower-INP too.
- `/ux-audit` — companion skill for the manual / heuristic accessibility pass.
