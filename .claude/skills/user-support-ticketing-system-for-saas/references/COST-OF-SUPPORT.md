# Cost Of Support — Economics Layer

A support ticketing system produces a *measurable cost per ticket*. Most teams never measure it. Knowing the number changes which features get prioritized, which customers are profitable, and what the right size of the support team should be.

This file is the framework for computing, attributing, and acting on cost-of-support data.

## Cost Components

A typical ticket's cost decomposes into:

| Component | Source | Starter planning range |
|---|---|---|
| Admin time | (admin minutes spent) × (loaded admin cost/min) | $5–$50 |
| AI assist | Embedding + LLM tokens used | $0.01–$0.50 |
| Email sends | Resend/SES per message | $0.001 |
| Storage | Attachments × bytes × retention | $0.01 |
| Cron + observability | Amortized across all tickets | $0.05 |
| Webhook fan-out | Per outbound webhook | $0.001 |
| KB look-up | Vector search per query | $0.001 |
| **Total** | | **Measure locally; often admin time dominates** |

Admin time usually dominates. Everything else is rounding for individual tickets but matters at volume. Treat the ranges as planning placeholders until the project's own cost table is populated.

## Schema

Add a `support_ticket_costs` table:

```ts
export const supportTicketCosts = pgTable("support_ticket_costs", {
  id: uuid().primaryKey().defaultRandom(),
  ticketId: uuid().references(() => supportTickets.id, { onDelete: "cascade" }).notNull(),

  // Per-component costs (cents, integer to avoid floating-point drift)
  adminMinutes: integer().default(0).notNull(),
  adminCostCents: integer().default(0).notNull(),       // = adminMinutes × loaded rate
  aiCostCents: integer().default(0).notNull(),
  emailCostCents: integer().default(0).notNull(),
  storageCostCents: integer().default(0).notNull(),
  otherCostCents: integer().default(0).notNull(),

  totalCostCents: integer().default(0).notNull(),       // sum, denormalized

  computedAt: timestamp({ withTimezone: true }).defaultNow().notNull(),
  computedAtVersion: integer().default(1).notNull(),    // bump when methodology changes
}, t => [
  index("support_ticket_costs_ticket_idx").on(t.ticketId),
  index("support_ticket_costs_total_idx").on(t.totalCostCents),
]);
```

`computedAtVersion` matters: when methodology changes (admin loaded rate goes from $50/hr to $80/hr), bump the version so historical comparisons are honest.

## Tracking Admin Time

The fiddliest input. Three approaches, in order of accuracy:

### Approach A — Action-Based Estimation (Default)

Each admin mutation is assumed to take a baseline number of minutes:

```ts
const ACTION_BASELINE_MINUTES = {
  view: 0.5,           // load the ticket
  reply: 5,            // typical reply
  status_change: 1,
  assignee_change: 0.5,
  priority_change: 0.5,
  internal_note: 2,
  macro_execute: 1,    // less than a manual reply
};
```

Per-ticket, sum the action baselines from the audit log:

```sql
SELECT
  ticket_id,
  SUM(action_baseline_minutes(action_type)) AS estimated_minutes
FROM audit_log
WHERE entity_type = 'support_ticket' AND entity_id = $1;
```

Cheap to compute; no UI changes needed. Reasonable for back-of-envelope numbers.

### Approach B — Tab-Visibility Heuristic

When an admin has a ticket detail tab open and active (focused, no idle), accumulate elapsed time:

```tsx
useEffect(() => {
  const start = Date.now();
  let activeMs = 0;
  const onVisibility = () => {
    if (document.hidden) activeMs += Date.now() - start;
  };
  // ...track active vs hidden time
  return () => persistTimeSpent(ticketId, activeMs);
}, [ticketId]);
```

More accurate; requires UI changes; admins may dislike feeling tracked. Communicate transparently.

### Approach C — Manual Time Logging

Admin clicks "log time" with a number-of-minutes field. Most accurate; lowest adoption.

Most teams choose Approach A as the default and add Approach B for tickets above a value threshold (P0 enterprise tickets where the cost is worth knowing precisely).

## Tracking AI Cost

Every AI invocation logs tokens used:

```ts
async function callLLMWithCostTracking(prompt: string, opts: { ticketId?: string; purpose: string }) {
  const result = await llm.complete(prompt, opts);
  const costCents = estimateCost(result.usage, opts.model);
  if (opts.ticketId) {
    await db.insert(aiCostLog).values({
      ticketId: opts.ticketId,
      purpose: opts.purpose,                  // 'categorize', 'draft_reply', 'kb_search'
      promptTokens: result.usage.prompt_tokens,
      completionTokens: result.usage.completion_tokens,
      costCents,
    });
  }
  return result;
}
```

Per-purpose cost roll-up reveals where AI spend goes:

```sql
SELECT purpose, SUM(cost_cents)::int AS total_cents, COUNT(*) AS calls
FROM ai_cost_log
WHERE created_at >= NOW() - INTERVAL '30 days'
GROUP BY purpose
ORDER BY total_cents DESC;
```

Reveals if "auto-categorize on every ticket" is justified by deflection improvement.

## Per-Ticket Cost Computation

Cron runs nightly, computes/refreshes `supportTicketCosts` for tickets resolved in the last 24h:

```ts
async function computeTicketCost(ticketId: string): Promise<typeof supportTicketCosts.$inferInsert> {
  const ticket = await getTicket(ticketId);
  const auditEvents = await getAuditEventsFor(ticketId);
  const aiEvents = await getAiCostFor(ticketId);
  const messages = await getMessagesFor(ticketId);
  const attachments = await getAttachmentsFor(ticketId);

  const adminMinutes = sum(auditEvents.map(e => ACTION_BASELINE_MINUTES[e.actionType] ?? 0));
  const adminCostCents = Math.round(adminMinutes * LOADED_ADMIN_RATE_PER_MINUTE_CENTS);
  const aiCostCents = sum(aiEvents.map(e => e.costCents));
  const emailCostCents = messages.length * EMAIL_COST_CENTS;  // approximation
  const storageCostCents = sum(attachments.map(a => storageCost(a.sizeBytes, ticket.createdAt)));
  const otherCostCents = OBSERVABILITY_OVERHEAD_PER_TICKET_CENTS;
  const totalCostCents = adminCostCents + aiCostCents + emailCostCents + storageCostCents + otherCostCents;

  return { ticketId, adminMinutes, adminCostCents, aiCostCents, emailCostCents,
           storageCostCents, otherCostCents, totalCostCents };
}
```

Idempotent: rerunning produces the same numbers (unless inputs change). Storage cost grows with retention; recompute on terminal-state transition + monthly.

## Per-Customer Cost Roll-Up

```sql
SELECT
  user_id,
  COUNT(*) AS ticket_count,
  SUM(total_cost_cents) AS total_support_cost_cents,
  AVG(total_cost_cents) AS avg_per_ticket_cents
FROM support_tickets t
JOIN support_ticket_costs c ON c.ticket_id = t.id
WHERE t.created_at >= NOW() - INTERVAL '90 days'
GROUP BY user_id
ORDER BY total_support_cost_cents DESC
LIMIT 50;
```

The top-50 list is informative. Customers paying $20/mo who cost $200/mo in support are unsustainable. The fix is rarely "fire the customer" — it's usually a product or KB gap that affects many.

## Per-Tier Margin

```sql
SELECT
  CASE
    WHEN o.subscription_tier = 'enterprise' THEN 'enterprise'
    WHEN o.subscription_tier = 'team' THEN 'team'
    ELSE 'individual'
  END AS tier,
  COUNT(DISTINCT u.id) AS customer_count,
  SUM(s.mrr_cents) AS total_mrr_cents,
  SUM(c.total_cost_cents) AS total_support_cost_cents,
  (SUM(s.mrr_cents) - SUM(c.total_cost_cents))::float / NULLIF(SUM(s.mrr_cents), 0) AS margin
FROM users u
LEFT JOIN organizations o ON o.id IN (...)
LEFT JOIN subscriptions s ON s.user_id = u.id
LEFT JOIN support_tickets t ON t.user_id = u.id
LEFT JOIN support_ticket_costs c ON c.ticket_id = t.id
WHERE t.created_at >= NOW() - INTERVAL '90 days'
GROUP BY tier;
```

If individual tier has -15% support margin, you have a pricing problem (or a churn problem you don't know about yet).

## Per-Category Cost Distribution

```sql
SELECT
  t.category,
  COUNT(*) AS ticket_count,
  AVG(c.total_cost_cents) AS avg_cost_cents,
  AVG(c.admin_minutes) AS avg_admin_minutes
FROM support_tickets t
JOIN support_ticket_costs c ON c.ticket_id = t.id
WHERE t.created_at >= NOW() - INTERVAL '90 days'
GROUP BY t.category
ORDER BY avg_cost_cents DESC;
```

If `billing` tickets cost 3× more than `bug` tickets, the billing UX is a target for redesign.

## ROI On Knowledge Base Articles

KB articles deflect tickets. Quantify:

```ts
async function kbArticleROI(articleId: string, periodDays = 30) {
  const deflections = await db.select({ count: sql<number>`count(*)::int` })
    .from(deflectionEvents)
    .where(and(
      eq(deflectionEvents.kbArticleId, articleId),
      gte(deflectionEvents.createdAt, sinceDate),
    ));

  const avgTicketCost = await getAverageTicketCost(periodDays);
  const valueGenerated = deflections.count * avgTicketCost;
  const articleAuthorCost = await getArticleAuthorCost(articleId);  // 1-time + maintenance

  return {
    valueGenerated,
    articleAuthorCost,
    roi: articleAuthorCost > 0 ? valueGenerated / articleAuthorCost : null,
  };
}
```

Articles with ROI > 5x are obvious wins. Articles with ROI < 1x are candidates
for rewrite or archival. If author cost is unknown, show value generated and
mark ROI as "needs cost estimate" rather than dividing by zero or inventing a
number.

## ROI On AI Features

Auto-categorize has a measurable 30-day cost. How much admin time does it save?

```ts
const aiCategorizeCostCents = await sumAiCost("categorize", 30);
const adminTimeSavedMinutes = await estimateCategorizationTimeSaved(30);
const adminCostSavedCents = adminTimeSavedMinutes * LOADED_ADMIN_RATE_PER_MINUTE_CENTS;
const roi = adminCostSavedCents / aiCategorizeCostCents;
```

If ROI < 2x, the feature isn't pulling its weight. Adjust thresholds, narrow scope, or disable.

## Anomaly Detection

A ticket whose cost is 5× the median for its category deserves a look:

```sql
SELECT t.id, t.subject, c.total_cost_cents, c.admin_minutes
FROM support_ticket_costs c
JOIN support_tickets t ON t.id = c.ticket_id
WHERE c.total_cost_cents > 5 * (
  SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY total_cost_cents)
  FROM support_ticket_costs
  WHERE ticket_id IN (SELECT id FROM support_tickets WHERE category = t.category)
)
ORDER BY c.total_cost_cents DESC
LIMIT 20;
```

These are usually:
- Genuinely hard problems (worth understanding)
- Communication failures (customer didn't understand the answer; rounds piled up)
- Process failures (admin mishandled and had to redo)

Investigate; if there's a pattern, fix the underlying.

## Dashboard

Daily cost dashboard for the support lead:

```
SUPPORT COSTS (Last 30 Days)
─────────────────────────────
Total spend:           $12,847
Tickets:                  823
Avg / ticket:           $15.61
Median / ticket:         $9.20

By category:
  billing  ⬛⬛⬛⬛⬛⬛⬛⬛  $4,200  (32.7%, 287 tickets, avg $14.63)
  bug      ⬛⬛⬛⬛⬛⬛       $3,100  (24.1%, 198 tickets, avg $15.65)
  auth     ⬛⬛⬛⬛           $2,400  (18.7%, 145 tickets, avg $16.55)
  access   ⬛⬛               $1,800  (14.0%, 102 tickets, avg $17.65)
  other    ⬛                 $1,347  (10.5%,  91 tickets, avg $14.80)

Top 3 cost drivers (this period):
  - "Cannot export skill data" (cluster of 12 tickets, $480 total)
  - "Stripe webhook missed" (cluster of 8 tickets, $400 total)
  - "Login redirect loop on Safari" (cluster of 6 tickets, $300 total)

KB articles deflecting:
  - "How to reset 2FA" — 47 deflections this month, ~$700 saved
  - "Billing FAQ" — 31 deflections, ~$465 saved

Tier margin:
  Enterprise: +71%   Individual: +28%   Free: -34%
```

The "Top 3 cost drivers" list is the single highest-leverage view. Each is a fixable cluster.

## Sharing Numbers With Engineering

The cost dashboard becomes a roadmap input. The "12 tickets about export" cost $480, but they map to maybe 1 day of engineering work to fix the underlying bug. ROI: ~30x.

Wire engineering's bug tracker → support cluster → cost computation:

```ts
// When admin marks a cluster's "known issue" as engineering-tracked, compute total cluster cost
const clusterCost = sum(cluster.tickets.map(t => t.totalCostCents));
const engineeringTicket = await createEngineeringTicket({
  title: cluster.centroidSubject,
  body: `Affecting ${cluster.tickets.length} customers; estimated support cost so far: $${clusterCost / 100}.`,
  metadata: { supportClusterId: cluster.id, supportCostCents: clusterCost },
});
```

When the engineering ticket resolves, mark all linked support tickets as auto-resolved (with admin confirmation), record the cost-saved.

## Anti-Patterns

| ✗ | Why |
|---|---|
| Tracking admin time without telling admins | Surveillance vibes; trust loss; data quality erodes |
| Including admin time during meetings/breaks | Massively inflates cost; produces unbelievable numbers |
| One blended cost number ("we spend $X/mo on support") | Hides where the cost actually goes |
| Cost methodology changes without bumping version | Historical comparisons drift; quarterly numbers diverge |
| Treating high-cost customers as "bad customers" | Often signals product gaps that affect many; punitive frame backfires |
| Sharing per-customer cost numbers with sales | Skews incentives; sales avoids the customers most needing help |
| Using cost data to justify saying "no" to customers | Defeats the support function; cost reduction by underservice is a death spiral |
| Computing cost per-ticket but not per-cluster | The cluster view is where action lives |
| Not refreshing cost on closed tickets when methodology changes | Stale numbers persist forever |

## Wire Points Checklist

- [ ] `supportTicketCosts` table with per-component breakdown
- [ ] Admin time tracking (Approach A baseline at minimum)
- [ ] AI cost log per LLM call with `purpose` + `ticketId`
- [ ] Email cost approximation per send
- [ ] Storage cost computed monthly + on terminal-state transition
- [ ] Nightly cron refreshes costs for tickets resolved in last 24h
- [ ] `LOADED_ADMIN_RATE_PER_MINUTE_CENTS` configurable per-environment
- [ ] `computedAtVersion` bumped when methodology changes
- [ ] Dashboard with by-category, by-tier, by-customer breakdowns
- [ ] Anomaly detection on cost outliers
- [ ] KB-article ROI computation
- [ ] AI-feature ROI computation
- [ ] Cluster-cost integration with engineering bug tracker
- [ ] CSV export of cost data (admin permission required, audited)
