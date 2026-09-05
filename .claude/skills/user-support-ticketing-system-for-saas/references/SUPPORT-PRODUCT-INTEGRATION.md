# Support Product Integration

The cheapest support ticket is the one that doesn't get filed because the customer found the answer where they were already standing — on the product page they were stuck on. The most expensive ticket is the one filed without context, where the agent has to ask 8 follow-up questions to figure out what the customer was trying to do. The pattern below wires support directly into the product so help is contextual and tickets carry full context from creation.

This file is the architectural pattern for in-product help that lives on the same substrate as the support ticketing system. It complements [USER-UI.md](USER-UI.md) (the support widget itself), [KNOWLEDGE-BASE.md](KNOWLEDGE-BASE.md) (the KB structure), and [DOCUMENTATION-FEEDBACK-LOOP.md](DOCUMENTATION-FEEDBACK-LOOP.md) (improving docs from ticket signal).

## The Surfaces, Ranked By Friction

| Surface | When to use | Friction | Volume impact |
|---|---|---|---|
| Inline tooltip / `?` icon | Any field a user might misunderstand | Lowest | Deflects hundreds of micro-questions |
| Contextual help panel | Per-page concept explanations | Low | Big deflection on docs-shaped questions |
| Embedded KB search | When the user clicks "help" | Low–medium | Deflects many "is this possible" questions |
| "Was this helpful?" widget | After viewing KB or completing a flow | Low | Improves docs over time |
| In-app announcement banner | New feature, status notice, deprecation | Low | Pre-empts "what is this" tickets |
| Contact-us / open-ticket modal | When self-service has failed | Medium | Captures the rest with full context |
| Email support | Power-user / out-of-app | Higher | Last resort |

The goal is to give the right surface for the question. A user struggling with the export page doesn't want the email-support form; they want a `?` next to the broken control.

## The `?` Help Bubble Pattern

Every non-obvious control has a `?` icon. The icon expands to a tooltip with:

```
┌── Help: Export format ──────────────────────────────────────┐
│ Choose how rows are formatted in the export.                │
│                                                             │
│  • CSV: standard comma-separated values                     │
│  • TSV: tab-separated, better for complex strings           │
│  • JSONL: one JSON object per line, for programs            │
│                                                             │
│ Most spreadsheet tools want CSV.                            │
│                                                             │
│ [Read more →] [Was this helpful? 👍 👎]                     │
└─────────────────────────────────────────────────────────────┘
```

The bubble is short (≤3 sentences), uses the customer's vocabulary, and has a "read more" path for depth. Clicks on `?` icons are tracked — high click-rate on a bubble means the surrounding UI is unclear; low click-rate doesn't mean clarity, it means low traffic.

## Contextual KB Article Surfacing

When a user spends >N seconds on a page or attempts an action that fails, surface relevant articles inline:

```ts
async function surfaceContextualKb(opts: {
  userId: string;
  surface: string;            // 'export_page'
  recentEvent?: string;        // 'export_failed_400'
  dwellSeconds: number;
}) {
  if (opts.dwellSeconds < 30 && !opts.recentEvent) return;       // not stuck yet

  const candidates = await searchKbForSurface({
    surface: opts.surface,
    event: opts.recentEvent,
    locale: await getUserLocale(opts.userId),
  });

  return rank(candidates, {
    relevanceWeight: 0.6,
    recencyWeight: 0.2,
    helpfulVoteWeight: 0.2,
  }).slice(0, 3);
}
```

Surface 1–3 article links inline (sidebar, slide-up panel, or contextual chip). Don't open a modal — modals interrupt; chips invite. Per [DOCUMENTATION-FEEDBACK-LOOP.md](DOCUMENTATION-FEEDBACK-LOOP.md), every surfaced-article impression is logged so docs effectiveness can be measured.

## "Was This Helpful?" Widgets

After a user completes (or abandons) a flow, ask:

```
┌── Was this helpful? ─────────────────────────────────────────┐
│ ☐ Yes, this solved my problem                                │
│ ☐ Not quite — I'd like to talk to support                    │
│                                                              │
│ [Skip]                                                       │
└──────────────────────────────────────────────────────────────┘
```

Two outcomes from "not quite":

1. **Open ticket flow** with full context attached automatically.
2. **Update KB-article-effectiveness metric** — feeds [DOCUMENTATION-FEEDBACK-LOOP.md](DOCUMENTATION-FEEDBACK-LOOP.md).

Resist the urge to add a 5-star scale or a 50-character "what could be better?" textarea. Those increase friction and lower response rates. Two clicks max.

## In-App Announcement Banners

Tied to the status page (per [STATUS-PAGE-INTEGRATION.md](STATUS-PAGE-INTEGRATION.md)) and to the changelog (per [CROSS-PRODUCT-LINKING.md](CROSS-PRODUCT-LINKING.md)):

```ts
export const inAppAnnouncements = pgTable("in_app_announcements", {
  id:              uuid().primaryKey().defaultRandom(),
  kind:            text().notNull(),          // 'incident_active' | 'feature_launch' | 'deprecation' | 'maintenance'
  title:           text().notNull(),
  body:            text().notNull(),
  ctaLabel:        text(),
  ctaUrl:          text(),
  startsAt:        timestamp({ withTimezone: true }).notNull(),
  endsAt:          timestamp({ withTimezone: true }).notNull(),
  audienceFilter:  jsonb(),                    // { tier: ['enterprise'], surface: ['billing'] }
  severity:        text().notNull(),          // 'info' | 'warning' | 'critical'
  dismissable:     boolean().default(true).notNull(),
  linkedIncidentId: uuid(),
  linkedReleaseId: uuid(),
  createdAt:       timestamp({ withTimezone: true }).defaultNow().notNull(),
});
```

Banner mock:

```
┌──────────────────────────────────────────────────────────────┐
│ ⚠ Login provider degraded — some users may see slow logins.  │
│   See status: status.acme.com/INC-...   [Dismiss]            │
└──────────────────────────────────────────────────────────────┘
```

Critical-severity banners are *not* dismissable until the underlying incident closes. Customers will have read it whether they wanted to or not, which is what you want during incidents.

## The "Ask In Product" Ticket-Create Flow

When the user finally needs to open a ticket, capture every piece of relevant context automatically. The customer should write 1–2 sentences; the system fills in everything else.

```ts
async function captureTicketContext(opts: {
  userId: string;
  surface: string;
  pageUrl: string;
  userMessage: string;
}): Promise<TicketContext> {
  const [user, sessionEvents, browserInfo, featureFlags, recentErrors, sessionVideoUrl] = await Promise.all([
    getUser(opts.userId),
    getRecentEvents(opts.userId, { lookbackMinutes: 30 }),
    getBrowserInfo(opts.userId),
    getActiveFeatureFlags(opts.userId),
    getRecentClientErrors(opts.userId, { lookbackMinutes: 30 }),
    getSessionRecordingUrl(opts.userId, { lookbackMinutes: 30 }),
  ]);

  return {
    surface: opts.surface,
    pageUrl: opts.pageUrl,
    userAgent: browserInfo.userAgent,
    viewport: browserInfo.viewport,
    locale: user.locale,
    featureFlags,
    recentEvents: sessionEvents.slice(-20),       // last 20 actions
    recentErrors,
    sessionVideoUrl,                                // privacy-redacted, time-bounded link
    userMessage: opts.userMessage,
  };
}
```

When the ticket is created, the support agent sees:

```
┌── Ticket #4571 ──────────────────────────────────────────────┐
│ Customer: jane@acme.com                                      │
│ Wrote: "Export isn't working"                                │
│                                                              │
│ Auto-captured context:                                       │
│   Surface: export_page                                       │
│   URL: /app/projects/proj_abc/export                         │
│   Browser: Chrome 122 / macOS 14.4                           │
│   Locale: en-US                                              │
│                                                              │
│   Last 5 actions:                                            │
│     14:31:12 click "Export"                                  │
│     14:31:12 POST /api/export → 500 (connection_reset)       │
│     14:31:18 click "Export" (retry)                          │
│     14:31:18 POST /api/export → 500                          │
│     14:31:34 navigate to /support                            │
│                                                              │
│   Active flags: new_export_v2 (rolled out 14:18 today)       │
│   Recent client errors: 2× ExportTimeoutError                 │
│   Session recording: [view 02:47 redacted clip]              │
│                                                              │
│ Auto-tagged: surface:export, recent_deploy_correlated         │
└──────────────────────────────────────────────────────────────┘
```

This is the difference between an agent reading "export isn't working" with no context (15 minutes of back-and-forth) and an agent who can immediately see the rolled-out flag, the 500 response, and the failed retry (resolution in 90 seconds).

Per [CUSTOMER-JOURNEY-RECONSTRUCTION.md](CUSTOMER-JOURNEY-RECONSTRUCTION.md) the journey reconstruction logic is shared; this file is the *capture* point.

## Auto-Tagging With Surface

```ts
async function inferSurfaceFromContext(ctx: TicketContext): Promise<string> {
  const surfaceHints = [
    { match: /\/export/i, surface: 'export' },
    { match: /\/billing/i, surface: 'billing' },
    { match: /\/checkout/i, surface: 'checkout' },
    { match: /\/settings/i, surface: 'settings' },
    { match: /\/login/i, surface: 'auth' },
    { match: /\/onboarding/i, surface: 'onboarding' },
  ];

  for (const hint of surfaceHints) {
    if (hint.match.test(ctx.pageUrl)) return hint.surface;
  }
  return ctx.surface ?? 'unknown';
}
```

Surface-tagged tickets feed:

- Per-surface volume metrics ([METRICS-AND-REPORTING.md](METRICS-AND-REPORTING.md))
- Regression detection ([REGRESSION-DETECTION-FROM-TICKETS.md](REGRESSION-DETECTION-FROM-TICKETS.md))
- Documentation feedback ([DOCUMENTATION-FEEDBACK-LOOP.md](DOCUMENTATION-FEEDBACK-LOOP.md))
- Per-surface routing rules ([MULTI-TEAM-ROUTING.md](MULTI-TEAM-ROUTING.md))

## Modal vs Panel vs Page

Three places the in-product support widget can live, with different ergonomics:

| Form factor | Best for | Cost |
|---|---|---|
| **Modal** (overlay) | One-off "I have a quick question" | Interrupts the page; customer loses their work-in-progress unless preserved |
| **Side panel** (slide-in) | "Help me as I work" | Reduces real estate but preserves work; my recommendation as default |
| **Full page** (`/support`) | "Manage all my tickets" | Full context, but a navigation; only for the ticket index |

The default in-product help should be a panel, not a modal. The panel:

- Slides in from the right, takes ~33% of viewport
- Page content remains interactive
- Customer can copy-paste from page into the support panel
- Closes without losing the ticket draft

```
┌─────────────────────────────────┐ ┌──────── Help ────────┐
│                                 │ │                      │
│  /export                        │ │ Search KB...         │
│                                 │ │                      │
│  ┌───────────────────────────┐  │ │ ┌──────────────────┐│
│  │ Export options            │  │ │ │ Recent help     ││
│  │                           │  │ │ │  • Export form  ││
│  │ Format: [CSV    v]        │  │ │ │  • CSV troubles ││
│  │ Range:  [Last 30d v]      │  │ │ │  • API export   ││
│  │                           │  │ │ └──────────────────┘│
│  │ [Export]                  │  │ │                      │
│  └───────────────────────────┘  │ │ Still stuck?         │
│                                 │ │ [Open ticket]        │
└─────────────────────────────────┘ └──────────────────────┘
```

On mobile, per [MOBILE-RESPONSIVE-PATTERNS.md](MOBILE-RESPONSIVE-PATTERNS.md), the panel becomes a full-screen sheet. The same context-capture logic applies.

## Privacy In Auto-Capture

Session recording, recent events, and active flags can all leak data the customer didn't intend to share. Wire privacy:

- **Redact form field values** in session recordings (passwords, payment fields, freeform text fields).
- **Bound the time window** of auto-captured data to the last 30 minutes by default.
- **Customer-visible disclosure** when context is being captured: "We'll attach what page you're on and a few recent actions to help us help you. [Show me what gets attached]."
- **Per-customer opt-out** of session recording.

```ts
async function captureWithPrivacy(opts: CaptureOpts): Promise<TicketContext> {
  const settings = await getCustomerPrivacySettings(opts.userId);
  if (settings.sessionRecording === 'disabled') {
    return capture({ ...opts, includeSessionVideo: false });
  }
  return capture(opts);
}
```

Per [INTERNAL-NOTES-VS-PUBLIC.md](INTERNAL-NOTES-VS-PUBLIC.md), auto-captured context is internal-only by default; customer can request to see what's attached.

## Deflection Metric

The whole point of in-product help is deflection. Measure it:

```sql
WITH page_visits AS (
  SELECT user_id, surface, COUNT(*) AS visits, SUM(opened_help) AS opened_help, SUM(opened_ticket) AS opened_ticket
  FROM product_help_events
  WHERE occurred_at > NOW() - INTERVAL '30 days'
  GROUP BY user_id, surface
)
SELECT
  surface,
  SUM(visits) AS total_visits,
  SUM(opened_help) AS opened_help_panel,
  SUM(opened_ticket) AS opened_ticket,
  SUM(opened_ticket)::numeric / NULLIF(SUM(opened_help), 0) AS conversion_to_ticket,
  1 - (SUM(opened_ticket)::numeric / NULLIF(SUM(opened_help), 0)) AS deflection_rate
FROM page_visits
GROUP BY surface
ORDER BY total_visits DESC;
```

A deflection rate > 0.7 (70% of help-panel opens don't become tickets) is good. Below 0.5 means the in-product help isn't answering the questions; either the KB needs more content or the surface needs more guardrails.

## Anti-Patterns

| ✗ | Why |
|---|---|
| Modal that breaks the page | Customer loses work-in-progress; opens ticket because the modal frustrated them |
| `?` icons that link to long external docs page | Defeats the purpose of inline help |
| No context auto-captured at ticket creation | Agent asks "what URL?" 8 times a day |
| Session recording without redaction | PII leaks; legal exposure |
| KB search results ranked by recency only | Stale, popular articles outrank the actually-relevant new ones |
| Banner with no expiry | "Maintenance Sunday" still showing in March |
| In-app announcement not localized | English banners on Japanese-locale users |
| Auto-capture of every flag (including dev flags) | Noise; agent can't see the relevant one |
| Help panel hidden behind navigation | Customers can't find it; defeats the point |
| Same widget on mobile and desktop | Full panel doesn't fit on phone; widget unusable |
| "Was this helpful" with required text response | Friction; response rate drops to <5% |
| Ticket created without surface tag | Lost in routing; cannot feed analytics |

## Wire Points Checklist

- [ ] `?` help bubbles on every non-obvious control
- [ ] Inline KB-article surfacing on dwell or fail
- [ ] "Was this helpful?" two-click widget
- [ ] `in_app_announcements` table with audience filtering
- [ ] Banner integration with [STATUS-PAGE-INTEGRATION.md](STATUS-PAGE-INTEGRATION.md)
- [ ] Side-panel default form factor; modal only for one-shot
- [ ] Auto-capture: page URL, surface, browser, viewport, locale, recent events, errors, flags
- [ ] Session-recording integration with PII redaction
- [ ] Privacy disclosure of what gets captured + customer opt-out
- [ ] Auto-tag tickets with `surface:*`
- [ ] Cross-link feeds: regression, docs, routing, metrics, journey
- [ ] Mobile sheet variant per [MOBILE-RESPONSIVE-PATTERNS.md](MOBILE-RESPONSIVE-PATTERNS.md)
- [ ] Deflection metric per surface, weekly review
- [ ] Localization of in-product help per [INTERNATIONALIZATION-AND-LOCALIZATION.md](INTERNATIONALIZATION-AND-LOCALIZATION.md)
- [ ] Test: opening ticket from `/export` auto-tags `surface:export`
- [ ] Test: session recording with PII opt-out does not include video
- [ ] Test: critical banner cannot be dismissed while incident open
