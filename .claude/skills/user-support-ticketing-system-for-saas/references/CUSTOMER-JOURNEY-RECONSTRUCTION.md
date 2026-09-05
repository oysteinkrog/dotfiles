# Customer Journey Reconstruction

The single biggest determinant of support reply quality: how quickly the agent understands what the customer was *actually doing* when the issue happened. The data is already there — product analytics, error logs, audit logs, billing events, feature flags — it's just scattered. This file is the architectural pattern for assembling a unified journey view, gated tightly to the support cockpit.

## The Goal

```
Customer files: "I can't export my skills"

Agent opens ticket. Within 2 seconds, sees:
- Customer's last 50 product actions, timestamped
- Last 5 client errors with stack traces
- Current feature-flag membership
- Subscription state + most recent invoices
- Previous tickets (same customer)
- Recent KB views (which pages did they hit before filing?)
- Whether the customer hit a status-page-known incident
```

Without this, the first 5 minutes of every reply is reconstruction. With it, the agent reads, understands, and responds.

## Schema: A Cross-Surface View, Not A New Table

Don't create a `customer_journey` table. The data lives in:
- `analytics_events` (already exists)
- `error_log` or Sentry (already exists)
- `audit_log` (already exists)
- `subscriptions` / `invoices` (already exist)
- `feature_flags` (already exist)
- `kb_views` (if KB exists)
- `support_tickets` (already exists)

Build a **service function** that joins them:

```ts
async function getCustomerJourney(userId: string, opts: {
  windowDays?: number;
  ticketId?: string;     // anchor; events closer to this ticket get higher relevance
  limit?: number;
}): Promise<CustomerJourney> {
  const since = new Date(Date.now() - (opts.windowDays ?? 7) * 86400000);
  const recentTicketSince = new Date(Date.now() - 90 * 86400000);

  const [events, errors, audits, subscription, invoices, flags, kbViews, recentTickets] = await Promise.all([
    db.query.analyticsEvents.findMany({
      where: and(eq(analyticsEvents.userId, userId), gte(analyticsEvents.createdAt, since)),
      orderBy: desc(analyticsEvents.createdAt),
      limit: 50,
    }),
    fetchErrorsForUser(userId, since, 10),
    db.query.auditLog.findMany({
      where: and(eq(auditLog.actorUserId, userId), gte(auditLog.timestamp, since)),
      limit: 20,
    }),
    getCurrentSubscription(userId),
    listRecentInvoices(userId, 5),
    listFeatureFlagsForUser(userId),
    db.query.kbViews.findMany({
      where: and(eq(kbViews.userId, userId), gte(kbViews.viewedAt, since)),
      limit: 10,
    }).catch(() => []),  // OK if KB doesn't exist
    db.query.supportTickets.findMany({
      where: and(eq(supportTickets.userId, userId), gte(supportTickets.createdAt, recentTicketSince)),
      limit: 10,
    }),
  ]);

  return {
    events, errors, audits, subscription, invoices, flags, kbViews, recentTickets,
    fetchedAt: new Date(),
  };
}
```

Cache aggressively: 60-second TTL keyed on `userId + windowDays`. Most ticket-detail loads happen in clusters as agents triage.

## UI: Sidecar Panel On Ticket Detail

```
┌──────────────────── Ticket: Cannot export skills ────────────────────┐
│                                                                       │
│ Customer: Jane Doe (jane@example.com)                                 │
│ [Customer journey ▼]                                                  │
│                                                                       │
│ ════════════════════════════════════════════════════════════════════ │
│ TICKET CONVERSATION             │  CUSTOMER JOURNEY (last 7d)          │
│                                  │                                      │
│ Customer · 2h ago               │  ⚠ ERRORS (3)                         │
│ When I click export, nothing... │   • TypeError on /export 1.5h ago    │
│                                  │   • TypeError on /export 1.5h ago    │
│ ...                             │   • TypeError on /export 1.5h ago    │
│                                  │                                      │
│                                  │  📊 ACTIONS (last 50)                 │
│                                  │   1.5h ago: Click "Export Skills"   │
│                                  │   1.5h ago: View dashboard          │
│                                  │   2h  ago: Login                    │
│                                  │   ... [show all]                    │
│                                  │                                      │
│                                  │  💳 SUBSCRIPTION                     │
│                                  │   Tier: Individual ($19/mo)         │
│                                  │   Status: Active, paid 5d ago       │
│                                  │                                      │
│                                  │  🚩 FLAGS                            │
│                                  │   - new_export_pipeline (cohort B)  │
│                                  │                                      │
│                                  │  📚 KB VIEWS                         │
│                                  │   1.4h ago: "How to export skills"  │
│                                  │                                      │
│                                  │  🎫 PREVIOUS TICKETS (2 in 90d)      │
│                                  │   • Fixed: Login redirect (32d ago) │
│                                  │   • Resolved: Billing q (75d ago)   │
└────────────────────────────────────────────────────────────────────────┘
```

The agent immediately sees: client error correlated with the failed export attempt, customer in cohort B of `new_export_pipeline` flag (likely the cause), subscription active (no entitlement issue), customer self-served the KB first (they tried).

## Per-Section Implementation Notes

### Errors

Pull from Sentry / equivalent via API. Filter to user's session. Show stack-trace summary, deduplicated. Click-through to full error in Sentry (link).

```ts
async function fetchErrorsForUser(userId: string, since: Date, limit: number) {
  const query = new URLSearchParams({
    query: `user.id:${userId}`,
    since: since.toISOString(),
    limit: String(limit),
  });
  const resp = await fetch(`https://sentry.io/api/0/projects/${PROJECT}/events/?${query}`, {
    headers: { Authorization: `Bearer ${SENTRY_TOKEN}` },
  });
  const events = await resp.json();
  return events.map(e => ({
    id: e.id, message: e.title, timestamp: e.dateCreated,
    sentryUrl: `https://sentry.io/organizations/${ORG}/issues/${e.groupID}/`,
  }));
}
```

If Sentry is unavailable, fail soft — show "Error log unavailable; check Sentry directly" with a link.

### Actions

Pull from analytics events table. Curate event types: `page_view`, `cta_click`, `feature_used`, `purchase`. Filter out chatty events (mouse moves, etc.).

Render as a vertical timeline with relative timestamps. Cluster events less than 5s apart visually.

### Subscription

Single-row pull. Show:
- Tier
- Status (active / past_due / canceled / trialing)
- Last payment date
- Next renewal
- Lifetime value (LTV)

If `dunning_state !== "none"`, prominent warning. Don't surface dunning to the customer; surface to the agent.

### Feature Flags

List flags currently affecting this user with their cohort. Particularly relevant for bug tickets — if a customer is in a beta cohort and the bug only happens for that cohort, the agent identifies the regression source instantly.

### KB Views

KB views before ticket filing are a strong signal: "the customer searched for the answer, didn't find it, gave up, filed." If multiple KB views before filing → the relevant article exists but isn't answering their question. Improve the article.

If zero KB views → the customer didn't try. Different reply tone (point them at the existing answer if one exists).

### Previous Tickets

The same customer's last 90 days of tickets. Helps the agent see patterns ("this is their third billing question this quarter") and avoid repeating answers ("we already explained this in #5421"). Click-through to the previous ticket's full thread.

## Performance Considerations

The journey view is the **second-heaviest read** in the support cockpit (after the ticket list). Default behavior:
- Lazy-load: don't fetch until the agent expands the panel
- 60-second cache per user
- Skeletons for each section while loading
- Parallel fetches via `Promise.all`

Per-request budget: ≤ 800ms total to fetch all sections. If slower, drop the slowest section to a "loaded on demand" subpanel.

## Privacy / Boundary

The journey view contains **a lot** of customer data. Treat it as the most sensitive surface in the cockpit:

- Permission: `support.read_journey` (not just `support.read`). Default: tier-2 admins only.
- Audit: every load is audited (`actionType: "support_journey_loaded"`, `entityId: ticketId`). Subpoena-ready.
- Customer-side: NEVER expose. Customer's `/account/support` page shows only what they file and the conversation thread.
- GDPR: the journey is reconstructed from canonical sources; deletion of underlying records (analytics events, error logs) flows through automatically. Don't denormalize into a `customer_journey` table.

## AI-Generated Briefing (Optional Layer)

After fetching the journey, optionally have an LLM produce a 5-line briefing:

```
This customer (Individual tier, paying since 2024-08) hit a TypeError on
/export 1.5h ago immediately after clicking "Export Skills" — the same flow
they're filing about. They are in cohort B of new_export_pipeline (potential
regression source). They viewed the export KB article 1.4h ago, suggesting
the article didn't help. No previous export-related tickets.
```

The briefing is internal-note style — never customer-visible. Saves the agent 3 minutes of cross-reading. See [PROACTIVE-AND-PREDICTIVE-SUPPORT.md](PROACTIVE-AND-PREDICTIVE-SUPPORT.md) Auto-Brief.

## Anti-Patterns

| ✗ | Why |
|---|---|
| Materializing a `customer_journey` table | Stale data; complicates GDPR; doesn't add speed (cache is enough) |
| Loading journey eagerly on ticket-list render | 50× the load when admin browses queue |
| Customer-visible journey | Surveillance vibes; privacy regression; trust crater |
| Skipping audit on journey loads | Compliance gap |
| Non-cached journey loads under high admin concurrency | Pool saturation; dashboards slow |
| Showing dunning state in customer-facing UI | Embarrassing; dunning is internal |
| Including ticket text in the journey events feed | Recursive; performance; pointless |
| LLM briefing rendered into customer-facing reply | Internal data leak |
| Journey panel renders before ticket-detail panel | UX feels backwards |

## Wire Points Checklist

- [ ] `getCustomerJourney(userId, opts)` service function joins all sources
- [ ] Cached 60s in-memory or per-edge (private only)
- [ ] Sentry / error-log integration with token + filter
- [ ] Analytics events table queryable by user + time range
- [ ] Feature flags exposable per-user
- [ ] KB views table populated by frontend (if KB exists)
- [ ] Sidecar panel UI on admin ticket detail
- [ ] Permission `support.read_journey` separate from `support.read`
- [ ] Audit log on journey loads
- [ ] Failure-soft graceful degradation when subsystems unavailable
- [ ] LLM briefing (optional layer; advisory; internal-only)
- [ ] Performance budget ≤ 800ms aggregate fetch
- [ ] Customer-side ticket detail does NOT expose journey
- [ ] GDPR deletion flows through to journey reconstruction (no denormalized table)
