# CONSENT-AND-ANALYTICS

Consent banners + privacy + measurement, treated as one connected problem. Done well: the banner is invisible to CWV, GA4 / GTM still answer the questions you need, and you don't ship dark patterns. Done poorly: every commercial page tanks INP and LCP on first paint, attribution is broken, and your DPA is non-compliant.

This document does not give legal advice; it gives operational defaults for SaaS marketing sites.

## Phase mapping

| Phase | Use this doc for |
|---|---|
| 3 — Technical | Banner perf audit; consent-mode wiring; testing 3 banner states. |
| 6 — Implementation | Lazy-mount banner; pre-allocate height; non-blocking. |
| 8 — Analytics | GA4 + GTM consent-mode setup; server-side measurement; referrer attribution. |
| 9 — Experimentation | Banner copy / layout A/B with INP guardrails. |
| 12 — Verify | Post-deploy: 3-state matrix (accept / deny / blocked) returns expected analytics + attribution. |

## Banner perf rules

`confirmed` (`web.dev/inp`, CrUX): consent banners are the single largest source of marketing-page INP regressions on SaaS sites. The biggest offenders are off-the-shelf IAB-TCF stacks loaded synchronously.

| Rule | Why |
|---|---|
| Banner mount must NOT push LCP | Pre-allocate height (`min-height` or sticky positioning); render after first paint. |
| Banner script must NOT block main thread | Lazy-load the consent SDK after first paint or defer to `idle`. |
| Banner CSS must NOT change layout | Reserve the banner's space; otherwise CLS regression. |
| Banner click must NOT cost > 100 ms INP | Click handler defers heavy work; main consent decision recorded immediately. |
| Banner must work without JS | Server-render a default-deny stance for users with JS disabled. (Or, more realistic: gate measurement off until JS confirms consent.) |

Measurement targets (`likely` from operator data):

| Metric | Without banner | With well-built banner | With off-the-shelf banner |
|---|---|---|---|
| LCP p75 | 1.6 s | 1.7 s | 2.4 s |
| INP p75 | 90 ms | 110 ms | 250–400 ms |
| CLS p75 | 0.04 | 0.04 | 0.10–0.18 |

If the off-the-shelf banner numbers describe the current site, the banner alone is putting commercial pages outside the `good` CWV thresholds. See [GUIDE-RECONCILIATION](GUIDE-RECONCILIATION.md) on INP and ranking.

## Banner mount pattern (Next.js 16)

```tsx
// app/components/ConsentBanner.tsx
"use client";

import { useEffect, useState } from "react";

export function ConsentBanner() {
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    // Defer to idle; don't block first paint or LCP
    const t = ("requestIdleCallback" in window)
      ? requestIdleCallback(() => setVisible(needsConsent()))
      : setTimeout(() => setVisible(needsConsent()), 0);
    return () => {
      if (typeof t === "number") clearTimeout(t);
      else cancelIdleCallback(t as number);
    };
  }, []);

  if (!visible) return null;
  return (
    <div
      role="dialog"
      aria-label="Cookie preferences"
      style={{ position: "fixed", bottom: 0, left: 0, right: 0, minHeight: 96 }}
    >
      {/* content */}
    </div>
  );
}
```

```tsx
// app/layout.tsx
<body>
  <main>{children}</main>
  <ConsentBanner /> {/* below the LCP candidate */}
</body>
```

Notes:

- The banner is below `<main>`. Even if it mounts late, it won't displace the LCP candidate.
- Pre-allocate `min-height: 96` so banner doesn't move other content on appearance.
- Don't load the IAB-TCF SDK until the user actually opens the banner's preferences modal.

## Consent-aware GA4 wiring

`confirmed`: Google Consent Mode v2 is required to measure EU/UK traffic via GA4 from 2024 onward.

Two flavors:

| Mode | Tag fires? | Cookies set? | Data quality |
|---|---|---|---|
| `granted` (user accepted) | yes | yes | full |
| `denied` (user rejected) — Basic mode | no | no | none |
| `denied` (user rejected) — Advanced mode | yes (cookie-less ping) | no | aggregated estimates via modeling |

Default to **Advanced** consent mode for analytics-light measurement under denial. For ad-related signals (`ad_storage`, `ad_user_data`, `ad_personalization`), default-deny.

GTM container snippet:

```html
<!-- BEFORE GTM loads -->
<script>
  window.dataLayer = window.dataLayer || [];
  function gtag(){dataLayer.push(arguments);}

  // Default consent state — denied for EU/UK; conservative everywhere
  gtag('consent', 'default', {
    'ad_storage': 'denied',
    'ad_user_data': 'denied',
    'ad_personalization': 'denied',
    'analytics_storage': 'denied',
    'functionality_storage': 'denied',
    'personalization_storage': 'denied',
    'security_storage': 'granted',
    'wait_for_update': 500
  });
</script>
<!-- GTM loader -->
```

After the user clicks Accept on the banner:

```js
gtag('consent', 'update', {
  ad_storage: 'granted',
  ad_user_data: 'granted',
  ad_personalization: 'granted',
  analytics_storage: 'granted',
  functionality_storage: 'granted',
  personalization_storage: 'granted',
});
```

`anti-pattern`: granting all categories on `default` and only revoking after the click — pre-accept tracking is the single most common consent-mode bug and exposes you to GDPR enforcement.

## Server-side measurement options

Server-side tagging (sGTM) reduces client-side weight, increases measurement durability against ad-blockers, and shifts compliance posture. Trade-offs:

| Approach | Pro | Con |
|---|---|---|
| Standard GA4 (gtag client) | simple; supported | client-side weight; ad-blocker erosion |
| GTM web container + GA4 | flexible; ad-block prone | client-side cost |
| GTM Server Container (sGTM) on Cloud Run / Vercel | low client cost; resilient | infra to operate; cost; not a privacy panacea |
| Reverse-proxy GA4 endpoint | reduces ad-block | doesn't change consent legality |
| Pure server-side events from API | full control | harder to wire UX events; lose automatic page_view |

`confirmed`: server-side tagging does not exempt you from consent law. The legality is about the *processing*, not the *transport*.

For SaaS marketing T2+: sGTM is worth it if you have > 100k monthly sessions, do paid acquisition, and have engineering bandwidth. Below that threshold, standard GA4 with consent mode is fine.

## What events require consent vs strictly necessary

`confirmed` per ePrivacy + GDPR:

| Event | Consent required? |
|---|---|
| `page_view` from analytics SDK | yes (analytics_storage) |
| Performance / RUM monitoring (CrUX, Sentry RUM) | yes (analytics_storage) |
| Conversion ping to ad network | yes (ad_storage + ad_user_data) |
| Session replay | yes (analytics_storage + likely a separate banner option) |
| First-party error logging (no PII, no cookies) | strictly necessary if no identification |
| CSRF cookie on form | strictly necessary |
| Authentication session cookie | strictly necessary |
| A/B test variant cookie (no PII) | depends on jurisdiction; safer to gate behind consent |
| Stripe customer cookie (transaction) | strictly necessary for the cart/checkout flow |

`anti-pattern`: marking analytics as "strictly necessary" to avoid the banner's deny path. Regulator-friendly framing: necessary = "this cookie is required for the user-requested service to work." Analytics is not required for the user's request.

## Testing in 3 states

For every release that touches the banner or measurement, test:

| State | Setup | Expected |
|---|---|---|
| Accept | Click "Accept all" on banner | `_ga`, `_ga_*` cookies set; GA4 page_view fires; ad pixels fire; consent state `granted` for all |
| Deny | Click "Reject all" | No `_ga*` cookies; GA4 still pings under Advanced consent mode (cookie-less); no ad pixels |
| Blocked | Browser blocks 3rd-party cookies / Brave / strict tracker prevention | No GA4 ping at all OR pings via reverse-proxy if configured; site still functions; no console errors |

Add as Playwright tests in CI. Record actual Network calls; assert event names + cookie set/unset.

```ts
// tests/consent.spec.ts
test("deny path does not set _ga cookie", async ({ page, context }) => {
  await page.goto("https://www.example.com/pricing");
  await page.getByRole("button", { name: /reject/i }).click();
  const cookies = await context.cookies();
  expect(cookies.find((c) => c.name === "_ga")).toBeUndefined();
});
```

## Banner interaction with Search Console click attribution

`confirmed`: GSC clicks are not affected by consent — they come from Google's own logs.

GA4 clicks vs GSC clicks will diverge after a banner ships:

| Metric | Source |
|---|---|
| GSC clicks | Google's logs; not affected by consent |
| GA4 sessions from organic search | Affected by consent (denial path drops them or aggregates) |
| GA4 conversions | Affected by consent |

When reporting, always state which metric is which. See [WIRING-OBSERVABILITY](WIRING-OBSERVABILITY.md).

`anti-pattern`: blaming "GA4 dropped" on Google after a consent banner change — it's likely the banner. Diff the consent-rate week-over-week.

## Regional differences

`likely` to be accurate; verify with counsel before changing default.

| Region | Law | Default stance |
|---|---|---|
| EU + EEA | GDPR + ePrivacy | Default deny; explicit opt-in for analytics + advertising. |
| UK | UK GDPR + PECR | Same as EU. |
| Switzerland | Revised FADP (2023) | Functionally similar to GDPR for SaaS purposes. |
| California | CCPA / CPRA | Default-allow with prominent "Do Not Sell or Share My Personal Information" link. |
| Other US states (CO, CT, VA, UT, etc.) | various | Patchwork; default-deny is the safe stance for measurement. |
| Brazil | LGPD | Similar to GDPR; explicit opt-in. |
| Canada | PIPEDA | Implied consent for analytics often acceptable; opt-in safer. |
| Australia | Privacy Act 1988 (under reform) | Notice required; consent may be implied depending on use. |
| Japan | APPI | Notice required; explicit consent for sensitive data. |

The pragmatic SaaS default: deny by default everywhere, accept on click, regional differences in banner copy and the presence of a "Sell or Share" toggle where required.

## Geographic banner targeting

`anti-pattern`: showing the banner only to EU users via geo-IP, with ad-network conversion tracking firing for everyone else by default.

Two reasons not to do this:

1. Privacy posture is increasingly multinational; many US states now require regional handling.
2. Geo-IP is fallible; a German user behind a US VPN gets the no-banner version.

Operational default: show the banner globally; vary copy by region; vary default categories minimally.

## Banner copy minimums

| Element | Required |
|---|---|
| Plain-language description of categories | yes |
| "Accept all" button | yes |
| "Reject all" button at the same prominence (not a link, not buried in modal) | yes — `confirmed` per CNIL + ICO guidance |
| Link to full privacy policy | yes |
| List of cookies / vendors | accessible (one click away is fine) |
| Persistence: rememberable choice | yes |
| Re-prompt period | 6–12 months typical; document the choice |

`anti-pattern`: prominent "Accept all" + barely visible "Manage" + no top-level "Reject all". Drives consent rates artificially; regulator scrutiny.

## Per-tier depth

| Tier | Depth |
|---|---|
| T1 | First-party analytics (Plausible / Vercel Analytics) for low-config option; no banner if no third-party cookies. Wire GSC. |
| T2 | GA4 + GTM with Consent Mode v2 Advanced; lightweight banner; 3-state Playwright tests. |
| T3 | + sGTM if paid traffic > 30%; per-event consent gating; quarterly DPA review. |
| T4 | + dedicated privacy team; per-region banner copy; annual external audit; consent rate as KPI. |

## Worked example — banner-induced INP regression

State 2026-04-01:
- Marketing site INP p75: 165 ms (passing).
- Marketing team installs OneTrust default snippet (synchronous).

State 2026-04-15 (CrUX field data 28-day):
- INP p75: 380 ms (failing).
- LCP p75: 1.6 s → 2.3 s.
- CLS p75: 0.05 → 0.14.
- Organic position on commercial pages: -1.2 average per query (`likely` from GSC).

Diagnosis (Operator ⚒ INP Component Hunt):
- Profile shows `OneTrust.js` parsing on main thread for 240 ms before first input.
- Banner DOM mounts before LCP candidate; CLS attributable to banner mount push.

Fix:
1. Defer OneTrust script to `idle` callback; load only the consent record-keeping minimum on first paint.
2. Pre-allocate `min-height` on banner container.
3. Move banner DOM below LCP candidate.
4. Move full IAB-TCF SDK behind "Manage preferences" click — only download when user opens the modal.

Result (28 days):
- INP p75: 145 ms.
- LCP p75: 1.7 s.
- CLS p75: 0.04.
- Organic positions: recovered.

Documented in `seo-changelog.md`. Captured as a CWV-banner pattern in [ANTI-PATTERNS](ANTI-PATTERNS.md).

## Anti-patterns

- Banner mounts before LCP candidate.
- "Accept all" prominent + "Reject all" hidden.
- Defaults granted before user choice (consent-mode bug).
- Synchronous IAB-TCF SDK on first paint.
- Banner CSS shifts layout (CLS regression).
- Geo-IP-only banner (other-region users skip it entirely).
- Server-side tagging treated as a privacy exemption.
- A/B testing the banner without INP guardrails — winner ships INP regression.
- Marking analytics as "strictly necessary" to dodge the banner.
- Re-prompting on every visit (annoyance + lower trust).
- Banner choice not persisted across subdomains where cookies are scoped to apex.
- Stale vendor list (a vendor was removed but banner still asks consent for them).
- Tracking GA4 events server-side without checking consent state stored client-side.
- Treating GSC clicks and GA4 sessions as the same thing post-banner.
- Banner does not work without JS, *and* the page is gated by client-side measurement (broken funnel).

## Cross-references

- [WIRING-OBSERVABILITY](WIRING-OBSERVABILITY.md) — measurement architecture; what GSC vs GA4 answer.
- [NEXTJS-PATTERNS](NEXTJS-PATTERNS.md) — consent banner mount pattern; INP rules.
- [PHASE-3-TECHNICAL](PHASE-3-TECHNICAL.md) — banner perf audit step.
- [PHASE-8-ANALYTICS](PHASE-8-ANALYTICS.md) — wiring GA4 + GTM with consent.
- [GUIDE-RECONCILIATION](GUIDE-RECONCILIATION.md) — INP < 200 ms and ranking.
- [ga4](../scripts/) skill — full GA4 + GTM setup details for Next.js SaaS.
- [OPERATORS](OPERATORS.md) ⚒ INP Component Hunt.
- [ANTI-PATTERNS](ANTI-PATTERNS.md) — full anti-pattern catalog.
- [EVIDENCE-LABELS](EVIDENCE-LABELS.md) — confidence/severity grammar.
