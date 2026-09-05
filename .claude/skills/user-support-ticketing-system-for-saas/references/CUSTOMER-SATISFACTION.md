# Customer Satisfaction — CSAT, NPS, Cancellation Surveys

The ticket data tells you what happened. The survey data tells you how it felt. Building the ticketing system without the satisfaction loop wastes data.

This file is the data-capture side of the triage skill's [VOICE-OF-CUSTOMER-LOOP.md](../../user-support-triage-for-saas-and-open-source-projects/references/VOICE-OF-CUSTOMER-LOOP.md). CSAT, NPS, cancellation, and sales-lost verbatims should feed the same theme vocabulary as tickets, otherwise the product team gets five incompatible piles of evidence.

## CSAT (Customer Satisfaction)

### Trigger

Send 5 minutes after a ticket is moved to `resolved` status.

```ts
// in service layer, after resolve():
after(async () => {
  await sendCsatSurvey(ticket);
});
```

### The Survey

Keep it minimal. The single question matters most:

```
How would you rate the support you received?

(1) Very dissatisfied  (2) Dissatisfied  (3) Neutral  (4) Satisfied  (5) Very satisfied

[ Optional ]
What could we have done better?
[ textarea ]

[ Submit ]
```

Single click for the score. Optional textarea. Form submits without a page navigation.

### Schema

```ts
export const csatResponses = pgTable("csat_responses", {
  id:        uuid().primaryKey().defaultRandom(),
  ticketId:  uuid().notNull().references(() => supportTickets.id),
  userId:    uuid().notNull().references(() => users.id),
  score:     integer().notNull(),  // 1-5
  verbatim:  text(),
  ts:        timestamp({ withTimezone: true }).defaultNow().notNull(),
}, t => [
  index("csat_ticket_idx").on(t.ticketId),
  index("csat_score_idx").on(t.score),
  index("csat_ts_idx").on(t.ts),
]);
```

### One-click URL Pattern

The survey email links directly to a click-through-to-rate URL:

```
https://app.example.com/csat/<token>?score=5
```

The token is a signed JWT containing the ticket ID + user ID + expiry. The page increments the score (no auth wall — auth is implicit in the token) and asks for the optional verbatim.

```ts
// /api/csat/[token]
const SECRET = process.env.CSAT_JWT_SECRET;
if (!SECRET) throw new Error("CSAT_JWT_SECRET is required");

const payload = jwt.verify(token, SECRET) as {
  ticketId: string;
  userId: string;
  score: number;
};

await db.insert(csatResponses).values({
  ticketId: payload.ticketId,
  userId: payload.userId,
  score: payload.score,
});

return Response.redirect("/csat/thanks");
```

### Email Template

```
Subject: Quick question about ticket #abc123

Hi,

Quick check-in. We just resolved your ticket about <subject>.

How did we do?

😞 [1]   😕 [2]   😐 [3]   🙂 [4]   😄 [5]

(One click — no login needed.)

Thanks for helping us get better.

— <team>
```

5 emoji buttons, each linking to the score URL.

### Acting On Detractors

A score ≤ 3 triggers an alert:

```ts
if (score <= 3) {
  await slackPost(`⚠ CSAT detractor on ticket ${ticketId}: ${score}/5\n${verbatim ?? "(no verbatim)"}`);
  await db.insert(beads).values({
    type: "csat-followup",
    ticketId,
    score,
    priority: "p2",
  });
}
```

The owner reads detractor verbatims daily. The score itself is just an aggregator.

### Reporting

```sql
-- Weekly CSAT
SELECT
  DATE_TRUNC('week', ts) AS week,
  AVG(score)::numeric(3,2) AS avg_score,
  COUNT(*) AS responses,
  COUNT(*) FILTER (WHERE score <= 3) AS detractors,
  COUNT(*) FILTER (WHERE score = 5) AS promoters
FROM csat_responses
GROUP BY 1 ORDER BY 1 DESC;

-- Per-agent CSAT (when assignee is set)
SELECT
  t.assignee,
  AVG(c.score)::numeric(3,2) AS avg_score,
  COUNT(*) AS responses
FROM csat_responses c
JOIN support_tickets t ON c.ticket_id = t.id
WHERE c.ts > now() - interval '30 days'
GROUP BY 1 ORDER BY avg_score DESC;
```

Don't optimize agents on raw score (gaming risk). Use it as a starting point for coaching.

## NPS (Net Promoter Score)

NPS is product-level, not ticket-level. Sample 20% of MAU quarterly.

### The Question

```
On a scale of 0-10, how likely are you to recommend <product> to a friend or
colleague?

[0] [1] [2] [3] [4] [5] [6] [7] [8] [9] [10]

What's the main reason for your score?
[ textarea ]
```

### Scoring

- **Promoters**: 9-10
- **Passives**: 7-8
- **Detractors**: 0-6
- **NPS** = %Promoters − %Detractors

### Schema

```ts
export const npsResponses = pgTable("nps_responses", {
  id:        uuid().primaryKey().defaultRandom(),
  userId:    uuid().notNull().references(() => users.id),
  score:     integer().notNull(),
  verbatim:  text(),
  context:   text(),  // 'quarterly' | 'onboarding' | 'cancellation'
  themeTags: text("theme_tags").array(),
  keeperConsent: boolean("keeper_consent").default(false).notNull(),
  ts:        timestamp({ withTimezone: true }).defaultNow().notNull(),
}, t => [
  index("nps_ts_idx").on(t.ts),
  index("nps_context_idx").on(t.context),
]);
```

### Sampling

Don't over-survey. Cron monthly, sample 20% of MAU who haven't been surveyed in 90 days:

```sql
-- Pool: active users not surveyed in the last 90 days. Sample 20% of THIS
-- pool (not 20% of all MAU — that would over-sample once long-tenured users
-- accumulate recent responses).
WITH eligible AS (
  SELECT u.id
  FROM users u
  LEFT JOIN nps_responses r
    ON r.user_id = u.id AND r.ts > now() - interval '90 days'
  WHERE r.id IS NULL
    AND u.last_active_at > now() - interval '30 days'
),
sample_size AS (
  SELECT GREATEST(1, (COUNT(*) * 0.2)::int) AS n FROM eligible
)
INSERT INTO nps_invitations (user_id, sent_at)
SELECT id, now()
FROM eligible, sample_size
ORDER BY random()
LIMIT (SELECT n FROM sample_size);
```

Send via the email pipeline. Same one-click pattern as CSAT.

Add the companion table:

```ts
export const npsInvitations = pgTable("nps_invitations", {
  id:     uuid().primaryKey().defaultRandom(),
  userId: uuid().notNull().references(() => users.id),
  sentAt: timestamp({ withTimezone: true }).defaultNow().notNull(),
}, t => [
  // Lookups go through both columns: (userId) for "skip if already invited
  // recently" exclusions in the sampling CTE, and (sentAt) for reporting
  // and rate-limit checks.
  index("nps_invitations_user_idx").on(t.userId),
  index("nps_invitations_sent_idx").on(t.sentAt),
]);
```

### Detractor Follow-Up

The single highest-leverage action: a personal outreach to detractors within 24 hours.

```
Subject: <name>, sorry we missed the mark

<name>,

Saw your NPS score yesterday. Thanks for being honest.

You said: "<verbatim>"

I'd love to hear more — got 15 min for a call this week? Pick any time:
<calendar-link>

— <owner-name>
```

Track outreach response rate. Detractor → call → fix specific issue → follow-up email = the loop that converts detractors to passives or promoters over months.

## Onboarding NPS

Special context: first 7 days after activation. Higher response rate (~30% vs ~10% quarterly).

```
Subject: How's your first week with <product>?

You signed up <N days ago> and just <triggered the activation event>. Quick
check: how likely are you to recommend us to a friend, on a 0-10 scale?

[0] ... [10]
```

This catches early friction before churn.

## Cancellation Survey

Trigger when the user clicks "Cancel subscription" — BEFORE the cancellation completes.

```
Sorry to see you go.

Help us understand:

  ◯ Too expensive
  ◯ Missing a feature I need
  ◯ Switched to another product
  ◯ Not using it enough
  ◯ Too many bugs / poor performance
  ◯ Bad support experience
  ◯ Privacy / security concerns
  ◯ Other

[ tell us more ]
[ textarea ]

[ Continue cancellation ]    [ Wait, what if we... ]
```

The "wait, what if we..." button leads to a save-flow (discount offer, plan downgrade, etc.). Don't gate cancellation behind this — it'll backfire.

### Schema

```ts
export const cancellationSurveys = pgTable("cancellation_surveys", {
  id:        uuid().primaryKey().defaultRandom(),
  userId:    uuid().notNull().references(() => users.id),
  reason:    text().notNull(),  // categorical
  verbatim:  text(),
  themeTags: text("theme_tags").array(),
  sourceStream: text("source_stream").default("cancellation").notNull(),
  saveOfferShown: boolean().default(false).notNull(),
  saveOfferAccepted: boolean(),
  ts:        timestamp({ withTimezone: true }).defaultNow().notNull(),
});
```

### Reading The Data

The cancellation reasons distribution by month → product backlog priorities:

```sql
SELECT
  DATE_TRUNC('month', ts) AS month,
  reason,
  COUNT(*) AS count,
  COUNT(*)::float / SUM(COUNT(*)) OVER (PARTITION BY DATE_TRUNC('month', ts)) AS pct
FROM cancellation_surveys
WHERE ts > now() - interval '6 months'
GROUP BY 1, 2 ORDER BY 1 DESC, 3 DESC;
```

A spike in "missing a feature" → roadmap signal. A spike in "too expensive" → pricing investigation.

## VoC Tagging Rules

Before dashboards consume survey rows:

1. Tag verbatims against the same controlled vocabulary used for tickets.
2. Preserve the original words; paraphrases are less useful for product, sales, and copy.
3. Mark `keeperConsent=false` by default. Public testimonial or case-study use needs explicit consent.
4. Feed detractor/passive/promoter themes into the monthly VoC synthesis, not just the NPS score.
5. When a shipped fix addresses a tagged survey/theme, set up the triage `🔁 LOOPBACK` path rather than hoping the customer notices.

## Survey Best Practices

| Do | Don't |
|---|---|
| Single question, optional verbatim | 10-question Likert grid |
| One click to score | Login wall before voting |
| Ask within 5 min of resolve (or context) | Ask weeks later |
| Personalize ("we resolved your ticket about X") | Generic "share your feedback" |
| Read every detractor verbatim | Only watch the aggregate score |
| Owner replies to detractors personally | Auto-canned response |
| Include the actual rating in the URL (one-click rating) | Multi-step: link → form → submit |
| Cap survey frequency per user (1 per 30d) | Spam |
| Show the response rate in the dashboard | Treat low response = bad data |

## Bias And Blind Spots

- **Selection bias**: only happy/angry users respond. Watch for this in NPS.
- **Recency bias**: a great recent ticket inflates your numbers; a bad recent ticket deflates.
- **The "9" trap**: in NPS, people who give 9 vs 10 may be similar; the cutoff is arbitrary. Don't over-tune to nudge 9s up to 10s.
- **Verbatim > score**: 100 detractors with no verbatim = less actionable than 5 detractors with detailed verbatim.

## Companion Refs

- [SCHEMA.md](SCHEMA.md) — base schema
- [EMAIL.md](EMAIL.md) — Resend pipeline for survey emails
- [OBSERVABILITY.md](OBSERVABILITY.md) — track CSAT/NPS as metrics
- [VOICE-OF-CUSTOMER-LOOP.md](../../user-support-triage-for-saas-and-open-source-projects/references/VOICE-OF-CUSTOMER-LOOP.md) — theme mining, keeper verbatims, loopback
- `/saas-customer-analytics` — full analytics framework
- `/user-support-triage-for-saas-and-open-source-projects` — METRICS-AND-DASHBOARDS.md
