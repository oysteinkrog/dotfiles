# Voice Of Customer Extraction

The support system is the highest-density source of customer truth a SaaS produces. Tickets contain unfiltered descriptions of what's broken, what's confusing, what's missing, what's unexpectedly delightful. Most teams let this signal evaporate. This file is the methodology for systematically extracting voice-of-customer (VoC) value from the queue and feeding it back to product, marketing, and leadership.

This is the *active extraction* layer above the triage skill's `VOICE-OF-CUSTOMER-LOOP.md` — that file specifies *what fields to capture*; this file specifies *what to do with them once captured*.

## The Five VoC Outputs

| Output | Audience | Cadence |
|---|---|---|
| **Top Pains** | Product leadership | Weekly |
| **Feature Demand Index** | Product PM | Monthly |
| **Documentation Gaps** | Docs / DevRel | Monthly |
| **Marketing Angles** | Marketing | Monthly |
| **Customer Quotes Bank** | Marketing + sales | Continuous |

Each is generated from the same underlying ticket corpus, queried differently.

## The Tagging Substrate

Every ticket gets two layers of tagging:

**Mandatory (always captured):**
- Category (auth/billing/access/bug/etc.)
- Priority (p0–p3)
- Resolution (resolved/closed/won't-fix)

**VoC tags (admin-applied during or post-resolution):**
- `theme` — substantive thing the customer is talking about (e.g., "export-pipeline", "billing-cycle-confusion")
- `persona` — who they are (e.g., "first-time-user", "power-user", "agency", "enterprise-admin")
- `register` — emotional register (e.g., "frustrated", "confused", "excited")
- `voc-keeper` — admin flagged this ticket as exemplary VoC signal

`themes` is a free-tag; AI-assist suggests existing themes; admin can add new.

```ts
export const ticketTags = pgTable("ticket_tags", {
  id: uuid().primaryKey().defaultRandom(),
  ticketId: uuid().references(() => supportTickets.id, { onDelete: "cascade" }).notNull(),
  kind: text().notNull(),                    // 'theme' | 'persona' | 'register' | 'voc-keeper'
  value: text().notNull(),                   // 'export-pipeline'
  appliedById: uuid().references(() => users.id),
  source: text().notNull(),                  // 'admin' | 'ai_suggested_admin_confirmed' | 'ai_auto'
  createdAt: timestamp({ withTimezone: true }).defaultNow().notNull(),
}, t => [
  index("ticket_tags_kind_value_idx").on(t.kind, t.value),
  index("ticket_tags_ticket_idx").on(t.ticketId),
  unique("ticket_tags_unique").on(t.ticketId, t.kind, t.value),
]);
```

## Output 1 — Top Pains (Weekly)

The single highest-leverage VoC artifact. Generated weekly:

```sql
WITH theme_volume AS (
  SELECT
    tt.value AS theme,
    COUNT(DISTINCT t.id) AS ticket_count,
    COUNT(DISTINCT t.user_id) AS unique_customers,
    AVG(EXTRACT(EPOCH FROM (t.resolved_at - t.created_at)) / 3600) AS avg_resolution_hours,
    AVG(c.total_cost_cents) AS avg_cost_cents,
    COUNT(DISTINCT t.id) FILTER (WHERE t.priority IN ('p0', 'p1')) AS high_priority_count
  FROM ticket_tags tt
  JOIN support_tickets t ON t.id = tt.ticket_id
  LEFT JOIN support_ticket_costs c ON c.ticket_id = t.id
  WHERE tt.kind = 'theme'
    AND t.created_at >= NOW() - INTERVAL '7 days'
  GROUP BY tt.value
)
SELECT *,
  ticket_count * unique_customers * (1 + high_priority_count * 0.5) AS pain_score
FROM theme_volume
ORDER BY pain_score DESC
LIMIT 10;
```

`pain_score` weights *volume × spread × severity* — a single P0 themed thing matters less than a P2 thing affecting 20 customers.

Format the output:

```
TOP CUSTOMER PAINS (Last 7 days)
─────────────────────────────────
1. export-pipeline                47 tickets, 31 customers, $720 support cost
   Recent quote: "When I click export, nothing happens. Tried 3 times."

2. billing-cycle-confusion        22 tickets, 22 customers, $440 support cost
   Recent quote: "Why was I charged on the 14th when I signed up on the 22nd?"

3. ios-safari-login                17 tickets, 17 customers, $300 support cost
   Recent quote: "Login works in Chrome but loops on iOS Safari"
```

Email this to product + leadership Mondays.

## Output 2 — Feature Demand Index (Monthly)

Tickets often contain explicit feature requests. Track demand:

```ts
async function computeFeatureDemandIndex(periodDays = 30) {
  // Use AI (advisory) to extract feature-request mentions per ticket
  // Or: rely on admin tagging "feature-request" + theme
  const featureRequestTickets = await db.query.supportTickets.findMany({
    where: and(
      ticketHasTag("feature-request"),
      gte(supportTickets.createdAt, sinceDate),
    ),
  });
  // Group by theme, score by:
  //   - Number of unique customers requesting
  //   - Their tier (enterprise weighted higher)
  //   - Their LTV
  //   - Frequency (recurring same-customer = 1, new customer = +1)
  return scored;
}
```

Output:

```
FEATURE DEMAND INDEX (Last 30 days)
─────────────────────────────────────
1. SAML SSO                        18 enterprise customers, $480k LTV
2. CSV import                      12 customers, mixed tier, $89k LTV
3. Bulk delete                     9 customers, $32k LTV
```

Hand to product PM. They prioritize against engineering capacity. Pre-emptive: "we're shipping this in Q2" gets messaged back to those customers proactively.

## Output 3 — Documentation Gaps (Monthly)

Tickets that should have been deflected by KB:

```sql
SELECT
  category,
  COUNT(*) AS ticket_count,
  ARRAY_AGG(DISTINCT subject ORDER BY created_at DESC LIMIT 5) AS sample_subjects
FROM support_tickets t
WHERE created_at >= NOW() - INTERVAL '30 days'
  AND t.id NOT IN (
    -- Tickets that arrived AFTER the customer viewed a relevant KB article
    SELECT ticket_id FROM kb_views_before_filing
  )
  AND status = 'resolved'
  AND resolved_at - created_at < INTERVAL '4 hours'  -- quick resolutions = KB-able
GROUP BY category
ORDER BY ticket_count DESC;
```

Quickly-resolved tickets are the most KB-able — the answer was easy; the customer just couldn't find it. Convert these to KB articles:

```
KB GAPS (Last 30 days)
──────────────────────
- "How to update payment method"   23 tickets, all resolved in <30min
- "Where is account settings"      19 tickets, mostly first-week users
- "Bulk-import contacts"           14 tickets, repeated power-users
```

Each becomes a KB ticket for the docs team. Track post-publish deflection.

## Output 4 — Marketing Angles (Monthly)

Customer language *about* your product in support tickets is gold for marketing copy. Mine:

```ts
async function extractCustomerVocabulary(periodDays = 30) {
  // Pull all customer messages
  const messages = await getCustomerMessagesInPeriod(periodDays);
  // Filter to those with positive register tag OR explicit praise patterns
  const positiveSnippets = messages
    .filter(m => hasPositiveSentiment(m.message))
    .map(m => extractKeyPhrase(m.message));
  // Aggregate frequent phrases
  return groupByFrequency(positiveSnippets);
}
```

Output:

```
CUSTOMER VOCABULARY (positive contexts, last 30 days)
─────────────────────────────────────────────────────
- "saved me hours" (38 mentions)
- "my whole team uses it" (24 mentions)
- "finally a [X] that doesn't suck" (19 mentions)
- "cancelled three competitors after" (12 mentions)
```

Marketing rewrites homepage hero based on what customers actually say. Authentic > clever.

Pair with **negative** vocabulary — phrases that indicate confusion or anti-pattern:

```
- "I had to dig through three menus"
- "Wasn't sure what 'Export' actually does"
- "Confusing that [feature] isn't where I'd expect"
```

Each is a UX investigation candidate.

## Output 5 — Customer Quotes Bank

Specific quotes from customers, opted-in for marketing/sales use:

```ts
export const customerQuotes = pgTable("customer_quotes", {
  id: uuid().primaryKey().defaultRandom(),
  ticketId: uuid().references(() => supportTickets.id),
  userId: uuid().references(() => users.id).notNull(),
  quote: text().notNull(),
  context: text(),                            // 1-line context for why this is a great quote
  consentStatus: text().notNull(),             // 'requested' | 'granted' | 'declined' | 'expired'
  consentRequestedAt: timestamp({ withTimezone: true }),
  consentGrantedAt: timestamp({ withTimezone: true }),
  consentScope: text().notNull(),              // 'name+quote' | 'company+quote' | 'anonymous'
  curatedById: uuid().references(() => users.id).notNull(),
  createdAt: timestamp({ withTimezone: true }).defaultNow().notNull(),
});
```

### Consent Flow

When admin marks a customer message as VoC-keeper-worthy AND consent-eligible:

1. Auto-email the customer asking permission, with the specific quote inline
2. Link to their preferences page where they can grant/decline
3. Granted → use in marketing, sales decks
4. Declined or no-response after 14 days → quote stays internal-only (or anonymized)

The consent record is durable. Never use a quote past consent revocation.

```
Hi [Name],

A while back, you mentioned that [feature] "saved me hours every week."
We loved hearing that, and we'd be honored to share it on our website
or in a sales conversation.

Could we use this quote? You're in control of how:
- [ ] Yes, with my name and company
- [ ] Yes, with just my company name
- [ ] Yes, anonymous
- [ ] No thanks

[Manage your preferences]

Thanks,
The team
```

## Themed Routing → Product Roadmap

Themes that recur across many customers feed the *roadmap input*:

```
PRODUCT ROADMAP INPUTS (Quarterly review)
─────────────────────────────────────────
Theme: export-pipeline
  Tickets: 312 in past 90 days
  Customer impact: 187 unique
  Resolved by current workaround: 234
  Required engineering fix: 78
  Escalations: 12
  → Recommendation: dedicate 2 sprints in Q2

Theme: ios-safari-edge-cases
  Tickets: 47 in past 90 days
  Customer impact: 47 unique
  Pattern: confined to Safari 16.x users
  → Recommendation: add to "browser support" KB; deprioritize fix
```

PM uses this alongside other inputs (sales, NPS, business strategy). VoC isn't the only input, but it's the most-direct customer signal.

## Personas From Tags

Aggregate `persona` tags to understand audience composition:

```sql
SELECT
  persona,
  COUNT(DISTINCT user_id) AS unique_users,
  AVG(theme_count_per_user) AS avg_themes_touched
FROM personas_aggregated
GROUP BY persona;
```

Tells the team:
- 47% of tickets come from "first-time-user" persona
- 12% from "power-user"
- 41% from "agency"

Onboarding investments → first-time-user reduction. Documentation depth → power-user retention. Bulk-action affordances → agency satisfaction.

## Trend Detection

Per-theme volume over time:

```sql
SELECT
  DATE_TRUNC('week', t.created_at) AS week,
  tt.value AS theme,
  COUNT(*) AS tickets
FROM ticket_tags tt
JOIN support_tickets t ON t.id = tt.ticket_id
WHERE tt.kind = 'theme'
  AND t.created_at >= NOW() - INTERVAL '90 days'
GROUP BY week, theme
ORDER BY theme, week;
```

Visualize as line chart. Spikes correlate with: product releases, marketing campaigns, blog posts going viral, status-page incidents.

A previously-stable theme suddenly tripling in volume is an early warning.

## AI-Assisted Theme Suggestion (Advisory)

When admin resolves a ticket, AI suggests theme tags:

```ts
async function suggestThemes(ticket: SupportTicket): Promise<{ existing: string[]; novel: string[] }> {
  const allThemes = await listAllThemes();
  const ticketEmbedding = await embedTicket(ticket);
  // Top-3 closest existing themes
  const existing = top3MostSimilar(ticketEmbedding, allThemes);
  // Plus AI-extracted novel theme candidates from the ticket text
  const novel = await extractNovelThemes(ticket);  // structured AI output
  return { existing, novel };
}
```

Admin sees suggestions, picks 1-3 themes, optionally adds a novel one. Lowers tagging friction → broader adoption.

Apply [ADVANCED-AI-FEATURES.md](ADVANCED-AI-FEATURES.md) hardening: PII redaction, output validation, cost cap.

## VoC Field Notes — Patterns Worth Capturing

A "field note" is admin's specific observation, attached to a ticket but useful generally. Captured field:

```ts
export const vocFieldNotes = pgTable("voc_field_notes", {
  id: uuid().primaryKey().defaultRandom(),
  ticketId: uuid().references(() => supportTickets.id),
  authorId: uuid().references(() => users.id).notNull(),
  category: text().notNull(),     // 'pain' | 'delight' | 'unmet-need' | 'workaround' | 'language'
  note: text().notNull(),
  createdAt: timestamp({ withTimezone: true }).defaultNow().notNull(),
});
```

Examples:

```
[pain]    Customer felt our pricing page hides the per-seat cost.
[delight] Customer said the export-progress bar made them trust the system.
[unmet]   Asked for "schedule export weekly" — our scheduler doesn't expose this.
[workaround] User pasted CSV into a Google Doc and re-uploaded; 6 customers doing this.
[language] Customer used "scratch pad" for what we call "drafts."
```

Aggregated quarterly into a "VoC field notes" report for product/UX teams.

## Anti-Patterns

| ✗ | Why |
|---|---|
| One bucket called "general" | All tickets land here; useless aggregation |
| Tags applied only by AI without admin review | Drift; tags lose meaning |
| Themes growing unbounded | 1000 themes = no themes |
| Customer quotes used without consent | Legal + trust risk |
| Trend monitoring without weekly cadence | Patterns invisible until they're full crises |
| VoC reports without owner | Generated and ignored; effort wasted |
| AI-extracted themes that hallucinate "support" subjects | Polluted analysis |
| No consent expiry | Customer's permission from 5 years ago no longer represents their wishes |
| Tag schema changes without migration | Old tickets become un-aggregatable |
| Aggregating personas a customer didn't self-identify with | Stereotyping; admins guess wrong |

## Wire Points Checklist

- [ ] `ticket_tags` table with kind/value structure
- [ ] Mandatory tags applied at resolution (admin can't close without)
- [ ] AI theme suggestion + admin review flow
- [ ] Theme taxonomy reviewed quarterly to prune redundant
- [ ] `customer_quotes` table with consent flow
- [ ] Consent request email triggered when admin marks "VoC-keeper"
- [ ] Top-Pains report (weekly) emailed to product + leadership
- [ ] Feature-Demand-Index report (monthly) handed to PM
- [ ] Documentation-Gaps report (monthly) to docs team
- [ ] Customer-Vocabulary mining (monthly) to marketing
- [ ] Customer-Quotes bank curated continuously
- [ ] Persona aggregation per quarter
- [ ] Theme trend visualization in admin dashboard
- [ ] `voc_field_notes` table for ad-hoc captures
- [ ] Quarterly VoC field notes report
- [ ] Consent expires after 24 months unless renewed
- [ ] All VoC reports have a named owner who acts on them
