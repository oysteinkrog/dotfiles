# MERCHANT-FEED-ALIGNMENT

## TOC

The four-corner consistency rule · Per-marketplace specifics · Page ↔ structured data ↔ feed alignment · Validation in CI · Price changes · Product identifier discipline · Currency/locale · Availability and discontinuation · Tier depth selectors · Anti-patterns · Cross-links

For SaaS that lists in marketplaces (Stripe Apps, Shopify App Store, Slack App Directory, Salesforce AppExchange, HubSpot Marketplace, AWS Marketplace, Vercel Marketplace, Atlassian Marketplace) — or has product-grid surfaces (templates, integrations, plugins) — page content, structured data, marketplace feed, and checkout must agree on every load-bearing field. Disagreement loses visibility, suppresses merchant rich results, and erodes user trust at the worst possible moment (decision time).

Phase mappings: Phase 1 (inventory feeds + marketplace listings), Phase 3 (alignment audit), Phase 6 (data source unification), Phase 8 (drift-detection alarms), Phase 12 (post-deploy parity check).

## The four-corner consistency rule

| Corner | What it shows | Source of truth |
|---|---|---|
| Page content (visible) | Plan card, price, included features, currency | CMS / page data |
| Structured data (JSON-LD) | `WebApplication`, `Offer`, `priceCurrency`, `availability` | Same source as page |
| Marketplace feed | Listing on Stripe Apps / Shopify / Salesforce | Often a separate feed file or admin form |
| Checkout (Stripe / PayPal / merchant gateway) | What the buyer is actually charged | Stripe `Price` object |

If page says `$29/mo`, structured data says `$29 USD MONTH`, marketplace listing says `$29.00 USD recurring`, and checkout charges $29.00 — pass. If any one drifts, fail.

The most common drift: pricing page updated, schema not regenerated, marketplace listing untouched, Stripe price object updated last week with a typo. (`confirmed` — observed across multiple pricing migrations.)

## Per-marketplace specifics

| Marketplace | Listing rich-data | Quirks |
|---|---|---|
| Stripe Apps | App ID; pricing model; supported regions | Stripe enforces signed manifest; price typo blocks listing |
| Shopify App Store | Pricing tiers; trial; categories; supported plans | Approval reviews check page-listing consistency |
| Slack App Directory | Pricing model (free / freemium / paid); scopes; supported workspaces | Free vs paid cliff visible at submission |
| Salesforce AppExchange | OEM listing; managed package version; security review status | Security review is separate; expires periodically |
| HubSpot Marketplace | Pricing tiers; trial; categories | Listing screenshot freshness matters |
| AWS Marketplace | Public price; private offer (negotiated); contract term | Many SaaS use private-offer; ensure public price isn't stale |
| Atlassian Marketplace | Pricing per user count; Cloud / DC variants | Per-tier price calculator must match |
| Vercel Marketplace | Provisioning manifest; pricing model | Plans visible in Vercel UI must match marketplace listing |
| Azure / Google Marketplace | Public price + private offer; metering plans | Metering plan changes propagate slowly |

(`likely` for marketplace-specific quirks; verify against current marketplace docs per [VERIFICATION-FIRST](VERIFICATION-FIRST.md).)

## Page ↔ structured data ↔ feed alignment

Generate from one source. The pattern:

```ts
// app/lib/pricing.ts — single source
export const PLANS = [
  {
    id: "starter",
    name: "Starter",
    monthlyUsd: 29,
    yearlyUsd: 290,        // 2 months free
    features: ["Up to 5 users", "10k events/mo", "Email support"],
    stripePriceMonthly: "price_1NxStarterMonthly",
    stripePriceYearly: "price_1NxStarterYearly",
    listed_in: ["stripe-apps", "shopify-app-store"],
    available: true,
    region: ["US", "EU", "GB", "CA"],
  },
  // ...
] as const;
```

```tsx
// app/pricing/page.tsx
import { PLANS } from "@/lib/pricing";
import { JsonLd } from "@/app/components/JsonLd";

export default function Pricing() {
  return (
    <>
      {PLANS.map((p) => <PlanCard key={p.id} plan={p} />)}
      <JsonLd data={{
        "@context": "https://schema.org",
        "@type": "WebApplication",
        name: "Acme",
        applicationCategory: "BusinessApplication",
        operatingSystem: "Any (web-based)",
        offers: PLANS.map((p) => ({
          "@type": "Offer",
          name: p.name,
          price: p.monthlyUsd.toString(),
          priceCurrency: "USD",
          availability: p.available ? "https://schema.org/InStock" : "https://schema.org/Discontinued",
          priceSpecification: {
            "@type": "UnitPriceSpecification",
            price: p.monthlyUsd.toString(),
            priceCurrency: "USD",
            unitText: "MONTH",
          },
        })),
      }} />
    </>
  );
}
```

```ts
// scripts/generate-marketplace-feed.ts
// Builds the Stripe Apps / Shopify / Slack feed from PLANS
import { PLANS } from "@/lib/pricing";
// emit JSON / YAML / XML in marketplace-specific format
```

When `PLANS` changes, *every* surface updates from the same commit. Drift becomes a CI failure, not a 6-month-old discovery.

## Validation in CI

```ts
// scripts/check-feed-alignment.ts (Phase 12 / CI gate)
const livePage = await fetchPage("/pricing");
const liveSchema = extractJsonLd(livePage);
const liveFeed = await fetch("https://www.example.com/marketplace-feed.json").then(r => r.json());
const liveStripe = await stripe.prices.list({ active: true });

assertEqual(livePage.starterPrice, liveSchema.starterOffer.price, "page vs schema");
assertEqual(liveSchema.starterOffer.price, liveFeed.starter.price, "schema vs feed");
assertEqual(liveFeed.starter.stripe_price_id, liveStripe.find(p => p.nickname === "starter").id, "feed vs Stripe");
```

CI gate: PR cannot merge if alignment fails. (`confirmed` — single most effective control to prevent pricing-related rich-result loss.)

## Price changes — the moment alignment matters most

Pricing changes are high-risk SEO + revenue events. Run this checklist:

1. **Plan the change in `lib/pricing.ts`** on a feature branch.
2. **Update Stripe `Price` objects** (new `Price`, don't edit existing — Stripe disallows editing price after creation).
3. **Generate the marketplace feed** from the branch.
4. **Run alignment CI** on the preview deployment.
5. **Submit feed updates to each marketplace** (some are API; some are admin UI).
6. **Verify rich result on Search Console URL inspection** for `/pricing`.
7. **Annotate** in `seo-changelog.md` with the timestamp and the diff.
8. **Watch GSC enhancement reports** for 7 days post-deploy for `Offer` errors.

Common pricing-change regressions:

- Schema price updated, marketplace lag of 24–72 h → mismatch flagged.
- Stripe price typo'd ($299 → $290) → schema correct, checkout charges wrong.
- Price changes mid-month for some users; the page shows new price; schema reflects old → confusion + rich-result drop.
- New plan added; marketplace listing missed → marketplace surface becomes stale.

## Product identifier discipline

For SaaS templates, plugins, integrations marketed as discrete "products":

| Identifier | Use |
|---|---|
| Internal SKU | Source of truth in your DB |
| `productID` in schema | Public id matching marketplace listing |
| Marketplace listing ID | Marketplace-assigned (e.g. Shopify app handle) |
| Stripe `Product` ID | Stripe-side identifier |
| GTIN / UPC | Only for physical products; not relevant for pure SaaS |

Map them once; treat the mapping as `lib/identifiers.ts`. AI engines that surface "<product> by <vendor>" rely on consistent `name` + `productID` + `sameAs` to reconcile entities. (`likely` — confirmed across product-listing-rich-result migrations.)

## Currency / locale

Multi-region SaaS with locale pricing must:

| Decision | Rule |
|---|---|
| Per-locale pricing page | Self-canonical per locale; `priceCurrency` matches |
| Auto-redirect by IP | Don't auto-redirect verified crawlers; respect `Accept-Language`; allow currency switcher |
| FX-converted prices | Show last-updated date; consider quarterly review |
| `hreflang` | Reciprocal across all pricing locales; `x-default` for the global default |
| Marketplace per-region | Marketplace feed includes per-region price |

Anti-pattern: page shows `€29` based on geolocation but JSON-LD always says `USD 29`. Schema validates but rich result doesn't display correctly for EU users. (`confirmed`)

## Availability and discontinuation

Schema has explicit availability values:

| Schema value | When |
|---|---|
| `InStock` | Available now |
| `LimitedAvailability` | Capped seat or waitlist |
| `PreOrder` | Announced, not yet shippable |
| `BackOrder` | Available but delayed |
| `Discontinued` | No longer offered |
| `SoldOut` | Capacity exhausted (rare for SaaS) |

When a plan is discontinued: schema flips to `Discontinued`; marketplace listing updated; page either redirects (if a successor exists) or remains with banner explaining the change. Do not silently delete pricing pages — existing users link there.

## Tier depth selectors

| Tier | Merchant alignment scope |
|---|---|
| T1 | Manual: pricing page + schema + Stripe in agreement; one marketplace if listed |
| T2 | + Centralized `PLANS` source; marketplace feed generated from same source |
| T3 | + CI alignment check; per-region pricing; multi-marketplace listings; drift alarm |
| T4 | + Per-locale price; per-region availability; private-offer reconciliation; per-marketplace publishing pipeline |

## Anti-patterns

| Don't | Why | Do instead |
|---|---|---|
| Update price on the page without updating schema | Rich result loses; AI engines cite stale price | Single source; CI alignment gate |
| Hardcode price in three places | Drift inevitable | One `PLANS` constant; everything reads from it |
| Edit a Stripe `Price` instead of creating new | Stripe disallows; existing subscribers may behave oddly | Create new `Price`, deactivate old |
| Forget marketplace feed when launching a new plan | Marketplace listing stale; missed audience | Marketplace feed in launch checklist |
| Auto-redirect by IP without `x-default` | Crawlers trapped; users can't reach other regions | Currency switcher; respect `Accept-Language` |
| Show price in `<span>` with no schema | No rich result eligibility | `Offer` schema mirroring visible price |
| Different price visible vs. checked out | Trust collapse; refund / chargeback risk | One source of truth; checkout reads same |
| Generate schema from a stale snapshot | Schema lies about current price | Generate at request time from same data |
| List on marketplaces but disable listing pages on site | Inbound users see soft-404 | Keep landing pages live with self-canonical |
| Use `aggregateRating` from marketplace reviews unverified | Schema lies; manual-action risk | Mirror visible reviews on the page; only schema if visible |
| Skip currency / locale on `Offer` | Defaults to USD silently; mismatch in non-US SERPs | Always set `priceCurrency` |
| Set `availability` based on hope ("we're coming back!") | Misleading rich result | Set what's actually true |
| Bury "discontinued" plan with no successor link | Users hit dead end | Visible note + link to recommended replacement |
| Per-marketplace price varies arbitrarily ("we charge more on Shopify") | Trust erodes when buyers compare | Document the differential or reconcile |

## Cross-links

- [SCHEMA-POLICY](SCHEMA-POLICY.md) — `WebApplication` + `Offer` patterns.
- [NEXTJS-PATTERNS](NEXTJS-PATTERNS.md) — server-rendered JSON-LD.
- [PHASE-3-TECHNICAL](PHASE-3-TECHNICAL.md) — pricing-page audit.
- [PHASE-12-VERIFICATION](PHASE-12-VERIFICATION.md) — post-deploy alignment check.
- [LIFECYCLE-CONTENT](LIFECYCLE-CONTENT.md) — plan-comparison and upgrade pages.
- [UGC-AND-MARKETPLACE-SEO](UGC-AND-MARKETPLACE-SEO.md) — marketplace reviews and ratings.
- [TRUST-INFRASTRUCTURE](TRUST-INFRASTRUCTURE.md) — pricing transparency as trust signal.
