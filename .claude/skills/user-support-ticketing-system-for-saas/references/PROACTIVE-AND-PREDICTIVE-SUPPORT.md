# Proactive And Predictive Support

The most expensive ticket is the one repeated by a whole affected cohort. By the time you respond to the first report, many more customers may be writing, churning silently, or posting publicly. Proactive support detects the pattern *before* the queue fills and shortcuts the loop.

This file is the architectural pattern for proactive and predictive support, leveraging the structured data the rest of the system already produces.

## Six Layers Of Proactivity

```
Layer 0: Reactive baseline                — Customer files ticket → admin replies
Layer 1: Pattern detection                — Multiple tickets with similar text → flag
Layer 2: Auto-escalation                  — Same customer files 3+ in 24h → escalate
Layer 3: Outbound notification            — System detects degradation → email known-affected customers
Layer 4: Pre-filing deflection            — Customer starts typing → KB / similar-ticket suggestions surface
Layer 5: Predictive churn intervention    — Behavior pattern predicts churn → support reaches out
```

Build incrementally. Layer 0 is the floor. Layer 5 requires the most data and the most care (false positives erode trust).

## Layer 1 — Pattern Detection (Cluster Recent Tickets)

```ts
async function detectTicketClusters(windowHours = 24): Promise<TicketCluster[]> {
  const recentTickets = await db.query.supportTickets.findMany({
    where: and(
      gte(supportTickets.createdAt, new Date(Date.now() - windowHours * 3600 * 1000)),
      inArray(supportTickets.status, OPEN_TICKET_STATUSES),
    ),
    columns: { id: true, subject: true, description: true, category: true, createdAt: true, userId: true },
  });

  // Embedding-based clustering
  const embeddings = await Promise.all(recentTickets.map(t =>
    embedText(`${t.subject}\n${t.description.slice(0, 1000)}`)
  ));
  const clusters = hierarchicalCluster(embeddings, { distanceThreshold: 0.15 });

  return clusters
    .filter(c => c.size >= 3)
    .map(c => ({
      tickets: c.indices.map(i => recentTickets[i]),
      centroidSubject: pickCentroidSubject(c, recentTickets),
      detectedAt: new Date(),
    }));
}
```

Run via cron every 30 minutes. Surface results in the admin dashboard:

```
🔥 Cluster detected (3 tickets in last 2h):
   "Cannot export skill data" - 3 customers affected
   First: 47 minutes ago
   [View tickets] [Mark as known issue] [Send proactive update]
```

Mark-as-known-issue creates a "known issue" record that:
1. Links the cluster's tickets to the issue
2. Auto-categorizes future similar tickets to the same issue (with admin confirmation)
3. Triggers a status banner on the customer-facing UI: "We're investigating reports of [issue]. Updates here."

## Layer 2 — Repeat-Filer Detection

Same customer files 3+ tickets in 24h → likely flooded by a single underlying issue. Surface in the admin queue:

```ts
async function detectRepeatFilers(windowHours = 24, threshold = 3) {
  const since = new Date(Date.now() - windowHours * 3600 * 1000);
  const counts = await db.select({
    userId: supportTickets.userId,
    count: sql<number>`count(*)::int`,
  }).from(supportTickets)
    .where(gte(supportTickets.createdAt, since))
    .groupBy(supportTickets.userId)
    .having(sql`count(*) >= ${threshold}`);
  return counts;
}
```

In the admin queue, repeat filers get a 🔁 badge:

```
[P1] Cannot export skills        🔁 4 tickets in 24h     2h ago
```

Clicking opens all of that customer's recent tickets in a single view. Often 2-3 of the 4 are facets of the same issue — the admin closes 3 with a single reply on the canonical one.

Don't treat repeat filers as abuse. Their multiplicity is signal, not noise.

## Layer 3 — Outbound Notification

When a status-page incident or known issue is created, identify customers likely to be affected and proactively email them:

```ts
async function sendProactiveIncidentNotice(incident: StatusPageIncident) {
  // Find customers who:
  // 1. Have used the affected feature in the last 7 days
  // 2. Or have an open ticket about a similar issue
  const affectedUserIds = await findAffectedUsers(incident);

  for (const userId of affectedUserIds) {
    await scheduleSupportSideEffect(
      () => sendIncidentNoticeEmail({ incident, userId }),
      { incident: incident.id, userId },
      "Incident notice scheduled outside request"
    );
  }
}

async function findAffectedUsers(incident: StatusPageIncident): Promise<string[]> {
  // Heuristic: anyone with a feature_used_at in the last 7 days
  // Plus anyone with an open support ticket whose embedding is close to the incident description
  // Filter against opt-out preferences
}
```

**Critical** — every proactive notification respects:
- Per-customer opt-out for proactive notices (separate from transactional)
- Frequency cap (max one proactive email per customer per day)
- Owner-confirmation gate (this is bulk customer-visible communication)

Wire to the same de-slopify + audit + footer-prefs-link pipeline as transactional emails.

## Layer 4 — Pre-Filing Deflection

When a customer starts typing in the new-ticket form, debounce-search the KB + recent resolved tickets. Surface suggestions inline:

```tsx
function NewTicketForm() {
  const [subject, setSubject] = useState("");
  const [description, setDescription] = useState("");
  const debouncedQuery = useDebounce(`${subject}\n${description}`, 500);
  const { data: suggestions } = useDeflectionSuggestions(debouncedQuery);

  return (
    <form>
      <input name="subject" onChange={e => setSubject(e.target.value)} />
      <textarea name="description" onChange={e => setDescription(e.target.value)} />

      {suggestions && suggestions.length > 0 && (
        <div className="border-l-4 border-blue-500 bg-blue-50 p-3">
          <p className="font-medium">💡 Maybe one of these helps?</p>
          <ul>
            {suggestions.map(s => (
              <li key={s.id}>
                <a href={s.url}>{s.title}</a>
                <button onClick={() => onDeflect(s)}>This solved it</button>
              </li>
            ))}
          </ul>
        </div>
      )}

      <button type="submit">Create Ticket Anyway</button>
    </form>
  );
}
```

**"This solved it"** is the deflection signal. Click → record a `deflected_kb` synthetic ticket so deflection rate is measurable. The form clears.

**"Create Ticket Anyway"** always wins. Never block ticket filing because deflection thinks it has the answer.

### Deflection Suggestion Endpoint

```ts
// POST /api/support/deflection-suggest
const suggestSchema = z.object({
  text: z.string().min(10).max(5000),
  category: z.enum(SUPPORT_CATEGORIES).optional(),
});

export async function POST(req: Request) {
  const auth = await requireUser(req);
  if (!auth.success) return auth.response;
  const { text, category } = suggestSchema.parse(await req.json());

  const queryEmbedding = await embedText(text);
  const [kbMatches, ticketMatches] = await Promise.all([
    findSimilarKbArticles(queryEmbedding, { topK: 3, minSimilarity: 0.75 }),
    findSimilarResolvedTickets(queryEmbedding, { topK: 2, minSimilarity: 0.85 }),
  ]);

  return NextResponse.json({
    kb: kbMatches.map(toPublicShape),
    similarTickets: ticketMatches.map(toAnonymizedShape),  // strip customer info
  });
}
```

Anonymize: similar-ticket suggestions show subject + resolution summary, never the original customer's name or details.

### Deflection Metrics

Track deflection per period:
- `deflection_rate = deflected_kb / (created_tickets + deflected_kb)`
- Per-category deflection rate (where is the KB strongest?)
- Per-suggestion deflection rate (which articles work?)
- Time-to-deflect (how long was the customer typing before the suggestion landed?)

Articles with consistently high deflection rate get more prominent placement. Articles with low rate get rewritten.

## Layer 5 — Predictive Churn Intervention

The most ambitious. The intuition: customers exhibit observable patterns before churning. Catching them early gives support time to intervene.

**Signals (per customer, 30-day rolling):**
- Tickets filed (volume, especially category mix)
- CSAT scores
- Reopen rate
- Feature usage trend (declining vs stable vs growing)
- Login frequency (declining vs stable)
- Support reply sentiment (LLM-scored, advisory)
- Recent SLA breaches affecting them

Compose into a churn-risk score. When score crosses threshold + customer is high-value:
1. Surface in a dedicated "intervention queue" for support leadership
2. Generate an internal note suggesting reach-out
3. Track outcome — did intervention prevent churn? (Compare retention vs un-intervened cohort)

**Critical safeguards:**
- Predictions advisory only; no automatic outbound to customer
- Score visible only to support leadership (not generic admins)
- False-positive cost (annoying outreach to a happy customer) > false-negative cost (missed churn) — calibrate threshold high

This crosses from support into customer success. Use [`/saas-customer-analytics`](../../saas-customer-analytics/SKILL.md) for the modeling layer.

## Status-Page Awareness In The Widget

When `statusPage.currentIncident` is non-null, the support widget shows a banner:

```
🟡 We're investigating reports of: API latency
   Updates: status.example.com
```

If the customer files anyway, their ticket is auto-tagged with `incident_id`. When the incident is resolved, all incident-linked tickets get a unified status update.
That update uses the same owner-confirmed `🪧 BROADCAST` path as any other bulk
customer-visible message; auto-linking tickets is safe, auto-emailing people is
not.

## Anti-Patterns

| ✗ | Why |
|---|---|
| Auto-creating tickets from error logs without consent | GDPR/privacy issue; customers don't expect tickets they didn't file |
| Cluster detection that ignores false-positive cost | Bad clustering surfaces "noise" alerts that desensitize the team |
| Outbound notice sent to all customers (not just affected) | Spam; reduces signal of future notices |
| Deflection that blocks ticket filing | Customers feel unheard and escalate through another channel instead |
| Churn predictor with low-precision threshold | Annoying outreach to happy customers — itself causes churn |
| Repeat-filer treated as abuse | Often the symptom of a real bug; punitive treatment makes it worse |
| Proactive notices without per-customer rate limit | Customers unsubscribe from all transactional emails |
| Status-page banner on widget without specifics | "Something is wrong" without actionable info — anxiety, not information |
| Pre-filing deflection that uses outdated KB | Suggesting a phantom feature is worse than no suggestion |

## Wire Points Checklist

### Layer 1 (Cluster Detection)
- [ ] Cron every 30min runs cluster detection on last-24h tickets
- [ ] Embedding service (OpenAI ada / Voyage / self-hosted) configured
- [ ] Cluster-results surfaced in admin dashboard
- [ ] "Mark as known issue" creates a `knownIssues` record

### Layer 2 (Repeat-Filer)
- [ ] Repeat-filer detection in cron output
- [ ] 🔁 badge in admin queue rows
- [ ] Single-customer ticket-history view from badge click

### Layer 3 (Outbound)
- [ ] Per-customer opt-out for proactive notices (separate from transactional)
- [ ] Frequency cap enforced (1/day per customer)
- [ ] Owner-confirmation gate before bulk send
- [ ] Audit row per send

### Layer 4 (Deflection)
- [ ] `/api/support/deflection-suggest` endpoint exists
- [ ] Embedding+similarity search infrastructure
- [ ] Anonymized similar-ticket display (no customer PII)
- [ ] "This solved it" creates `deflected_kb` synthetic record
- [ ] "Create Ticket Anyway" always wins
- [ ] Deflection metrics in dashboard
- [ ] KB articles tagged with last-verified date

### Layer 5 (Churn Prediction)
- [ ] Composable churn-risk scoring (separate concern from support; see `/saas-customer-analytics`)
- [ ] Intervention queue surface for support leadership only
- [ ] Outcome tracking on intervention efficacy
- [ ] Threshold calibration favoring precision over recall

### Status-Page Integration
- [ ] Status-page API or webhook integration
- [ ] Widget renders incident banner with link
- [ ] Tickets filed during incident auto-tagged with `incident_id`
- [ ] Unified resolution update when incident resolved

## How To Stage Rollout

1. **Week 1-2:** Layer 1 (cluster detection) + Layer 2 (repeat filers). Pure read-only on top of existing data; very low risk.
2. **Week 3-4:** Layer 4 (pre-filing deflection). UI add; doesn't change ticket flow.
3. **Month 2:** Layer 3 (outbound notification). Requires opt-out infrastructure + admin training.
4. **Month 3+:** Layer 5 (churn prediction). Pulls in customer-analytics work.

Skip layers if you don't have the data yet. Pre-filing deflection requires a real KB. Churn prediction requires usage telemetry. Proactive notification requires an opt-out preference table.
