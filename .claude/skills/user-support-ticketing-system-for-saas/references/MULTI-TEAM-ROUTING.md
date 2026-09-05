# Multi-Team Routing

A growing support function splits into specialized lanes: front-line support, engineering escalation, billing, content moderation, customer success. Routing rules determine which lane sees which ticket — and getting routing right cuts response time without adding headcount.

Start with the lanes that actually exist. A solo founder may only need
`tier_1` plus an owner-only `security` escalation path; an enterprise support
org may need the full split. Empty teams create routing theater and slower
handoffs.

## The Routing Decision

Three inputs determine where a ticket goes:

1. **Category** (`auth` / `billing` / `bug` / `content_moderation` / etc.)
2. **Priority** (P0–P3, possibly tier-adjusted)
3. **Customer tier / segment** (free / individual / team / enterprise / VIP / design-partner)

Output: a *team* (the lane) and possibly a *specific assignee* (the on-call admin in that lane).

## Schema

```ts
export const supportTeamEnum = pgEnum("support_team", [
  "tier_1",                    // generalist front-line
  "engineering_escalation",    // bug + perf
  "billing_specialists",       // billing + refunds + plan changes
  "content_moderation",        // copyright, abuse, take-downs
  "customer_success",          // enterprise account managers
  "security",                  // ATO, suspected breach, sensitive disclosure
]);

// Add to supportTickets:
//   team: supportTeamEnum().default("tier_1").notNull(),
//   assignee: text(),  // already exists

// Optional: routing rule table
export const supportRoutingRules = pgTable("support_routing_rules", {
  id: uuid().primaryKey().defaultRandom(),
  matchCategory: supportCategoryEnum(),    // null = match any
  matchPriority: ticketPriorityEnum(),     // null = match any
  matchTier: text(),                       // null = match any; or 'enterprise'
  matchKeywordRegex: text(),               // null = no keyword match
  routeToTeam: supportTeamEnum().notNull(),
  routeToAssignee: text(),                 // if specific person
  priority: integer().notNull(),           // ordering — lower number wins
  active: boolean().default(true).notNull(),
  createdById: uuid().references(() => users.id),
  createdAt: timestamp({ withTimezone: true }).defaultNow().notNull(),
});
```

Rules evaluate top-down by `priority`. First match wins.

## Default Rules

```ts
const DEFAULT_ROUTING_RULES = [
  // Highest priority: explicit override paths
  { priority: 100, matchCategory: "content_moderation", routeToTeam: "content_moderation" },
  { priority: 110, matchKeywordRegex: "hacked|compromised|breach|stolen account", routeToTeam: "security" },

  // Enterprise gets customer success
  { priority: 200, matchTier: "enterprise", routeToTeam: "customer_success" },

  // Categorical defaults
  { priority: 300, matchCategory: "billing", routeToTeam: "billing_specialists" },
  { priority: 310, matchCategory: "bug", matchPriority: "p0", routeToTeam: "engineering_escalation" },
  { priority: 320, matchCategory: "bug", matchPriority: "p1", routeToTeam: "engineering_escalation" },

  // Catch-all
  { priority: 9999, routeToTeam: "tier_1" },
];
```

Rules editable through admin UI; never hardcoded only.

## Routing Service

```ts
async function routeTicket(ticket: { category: SupportCategory; priority: TicketPriority; tier: string; description: string }): Promise<{ team: SupportTeam; assignee: string | null; ruleId: string }> {
  const rules = await db.select().from(supportRoutingRules).where(eq(supportRoutingRules.active, true)).orderBy(asc(supportRoutingRules.priority));
  for (const rule of rules) {
    if (rule.matchCategory && rule.matchCategory !== ticket.category) continue;
    if (rule.matchPriority && rule.matchPriority !== ticket.priority) continue;
    if (rule.matchTier && rule.matchTier !== ticket.tier) continue;
    if (rule.matchKeywordRegex && !safeRegexMatch(rule.matchKeywordRegex, ticket.description)) continue;
    return { team: rule.routeToTeam, assignee: rule.routeToAssignee ?? null, ruleId: rule.id };
  }
  return { team: "tier_1", assignee: null, ruleId: "default" };
}
```

Treat admin-editable regexes as untrusted configuration: validate length,
compile at save-time, reject catastrophic patterns, and cap scanned text. A bad
regex in a routing rule must not become a ReDoS vector on ticket creation.

`createTicket` calls `routeTicket(...)` and writes `team` + `assignee` to the ticket. Audit captures which rule fired.

## Round-Robin Within Team

When `assignee` is null, round-robin within the team's roster:

```ts
async function assignWithinTeam(team: SupportTeam): Promise<string | null> {
  const onCall = await getCurrentOnCall(team);
  if (onCall) return onCall.adminUserId;
  // Otherwise round-robin
  const roster = await getTeamRoster(team);
  if (roster.length === 0) return null;
  const lastAssignedIdx = await getRoundRobinCursor(team);
  const nextIdx = (lastAssignedIdx + 1) % roster.length;
  await setRoundRobinCursor(team, nextIdx);
  return roster[nextIdx];
}
```

Round-robin is a simple default. More advanced: workload-aware (assign to admin with fewest open tickets).

## On-Call Schedule

Per-team on-call rotation lets one admin "own" incoming during their shift:

```ts
export const supportOnCallShifts = pgTable("support_on_call_shifts", {
  id: uuid().primaryKey().defaultRandom(),
  team: supportTeamEnum().notNull(),
  adminUserId: uuid().references(() => users.id).notNull(),
  startsAt: timestamp({ withTimezone: true }).notNull(),
  endsAt:   timestamp({ withTimezone: true }).notNull(),
}, t => [index("on_call_shifts_active_idx").on(t.team, t.startsAt, t.endsAt)]);

async function getCurrentOnCall(team: SupportTeam): Promise<{ adminUserId: string } | null> {
  const now = new Date();
  const [shift] = await db.select().from(supportOnCallShifts)
    .where(and(eq(supportOnCallShifts.team, team), lte(supportOnCallShifts.startsAt, now), gt(supportOnCallShifts.endsAt, now)))
    .limit(1);
  return shift ? { adminUserId: shift.adminUserId } : null;
}
```

Surface in admin dashboard: "Currently on-call: Engineer A (engineering_escalation), 9am–6pm." Bug tickets routed to engineering route to Engineer A specifically.

## Re-Routing

Admins can re-route a ticket. Common cases:
- "Tier-1 picked up a bug; needs engineering" → admin reassigns to `engineering_escalation`
- "Engineering identified it as a billing issue" → reassign to `billing_specialists`

Re-route is a separate action from individual reassignment:
- Reassign within team: `assignee` change only.
- Re-route: changes `team`, clears `assignee`, may auto-assign by team's on-call.

Both audited; re-route requires a reason.

## Lane SLA Differentiation

Each team can have its own SLA tier override:

```ts
const TEAM_SLA_OVERRIDES: Partial<Record<SupportTeam, Partial<typeof SLA_CONFIG>>> = {
  engineering_escalation: {
    enterprise: { firstResponse: { p0: 1, p1: 2, p2: 4, p3: 8 }, resolution: { p0: 4, p1: 8, p2: 24, p3: 48 } },
  },
  customer_success: {
    enterprise: { firstResponse: { p0: 0.5, p1: 1, p2: 2, p3: 4 }, resolution: { p0: 2, p1: 4, p2: 12, p3: 24 } },
  },
  // tier_1 uses defaults
};
```

Customer success has tighter SLAs because enterprise expects high-touch. Engineering escalation may have looser resolution SLAs (depends on engineering's response time).

## Ticket Hand-Off Hygiene

Every routing change is captured in the conversation thread as a system message:

```
─── system · 1.2h ago ──────────────────────────────
Routed from tier_1 to engineering_escalation
Reason: "P0 bug — escalating per policy"
─────────────────────────────────────────────────────
```

The history shows the path the ticket took. New admin reads the journey, not just the latest state.

## Lane Performance Metrics

Per-team metrics surfaced in `/admin/support/teams`:
- Tickets handled / period
- Avg first-response time
- Avg resolution time
- SLA compliance rate
- Customer CSAT
- Re-routes outbound (how often does this team punt?)
- Re-routes inbound (how often does it receive transfers?)

High inbound re-routes to one lane = the previous lane is mis-classifying. Tune routing rules.
High outbound re-routes from one lane = the lane lacks the skills it needs; train or hire.

## Cross-Team Comments

Sometimes a ticket assigned to engineering needs billing context. Internal notes (see [INTERNAL-NOTES-VS-PUBLIC.md](INTERNAL-NOTES-VS-PUBLIC.md)) with `@team:billing` or `@admin:jane` mentions notify the relevant person without re-routing.

This keeps the ticket on its primary lane while pulling in expertise.

## Routing Anti-Patterns

| ✗ | Why |
|---|---|
| Hardcoded routing logic in service code | Hard to change; non-engineers can't adjust |
| Routing rules without `priority` ordering | First-match-wins becomes unpredictable |
| Re-routing without conversation-thread system message | Customer / next admin loses context |
| Assigning by round-robin without consideration of workload | One overloaded admin gets pile of tickets |
| Multiple teams owning the same ticket simultaneously | Confusion; double-replies; audit chaos |
| Customer-visible `team` field on ticket | Customer doesn't care; internal-only |
| Billing-specialist team that also handles `auth` | Specialization erodes; either grow it as billing or fold back to tier_1 |
| No on-call coverage during off-hours for engineering_escalation lane | P0 bugs stall overnight |

## Wire Points Checklist

- [ ] `supportTeamEnum` defined
- [ ] `team` column on `supportTickets` (default tier_1)
- [ ] `supportRoutingRules` table with priority-ordered rules
- [ ] `routeTicket(...)` service function
- [ ] `createTicket` calls `routeTicket` and persists team
- [ ] Round-robin assignment within team
- [ ] On-call schedule table + lookup
- [ ] Re-route action distinct from reassignment, with reason
- [ ] Re-route writes system message to conversation thread
- [ ] Per-team SLA overrides (optional)
- [ ] Per-team metrics dashboard
- [ ] Cross-team mentions in internal notes
- [ ] Audit on routing rule changes
- [ ] Routing-rule UI for editing without code changes
