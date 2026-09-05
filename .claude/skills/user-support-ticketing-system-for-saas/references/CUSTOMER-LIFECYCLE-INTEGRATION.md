# Customer Lifecycle Integration

A ticketing system that doesn't know whether the customer is on day 3 or day 1,090 of their journey is making the wrong decisions on every ticket. The day-3 customer needs onboarding, not SLA pressure. The day-1,090 enterprise customer needs *immediate* attention, not a queue position determined by FIFO.

This file is the pattern for wiring customer-lifecycle stage into the ticketing substrate so support behaves correctly per stage. It's the connective tissue between support and the rest of the customer-success motion: signup, onboarding, activation, expansion, renewal, churn.

## The Stage Enum

```ts
export const customerLifecycleStage = pgEnum("customer_lifecycle_stage", [
  "lead",            // pre-signup, marketing-touch only
  "trial",           // signed up, no activation yet, in trial period
  "onboarding",      // first 30 days, working through setup
  "activated",       // hit the activation milestone (define product-specifically)
  "engaged",         // using product regularly, no expansion or risk signals
  "expansion",       // expanding usage; expansion-conversation candidate
  "at_risk",         // health score declining; renewal-risk
  "renewing",        // within renewal window (60–90 days out)
  "churned",         // canceled or non-renewed
  "alumni",          // 90+ days post-churn; re-engagement candidate
]);
```

Each stage has different SLA priorities, different proactive support behaviors, different escalation rules, and different success metrics. The same exact ticket subject ("can't export") gets different handling depending on the stage.

## The Customer-Stage Snapshot

```ts
export const customerLifecycleSnapshots = pgTable("customer_lifecycle_snapshots", {
  id:                  uuid().primaryKey().defaultRandom(),
  customerId:          uuid().notNull(),
  stage:               customerLifecycleStage().notNull(),
  stageEnteredAt:      timestamp({ withTimezone: true }).notNull(),
  daysSinceSignup:     integer().notNull(),
  daysToRenewal:       integer(),
  arr:                 numeric({ precision: 12, scale: 2 }),
  healthScore:         integer(),         // 0–100
  activationMilestoneHit: boolean(),
  productUsageScore:   integer(),         // 0–100, recency-weighted
  csm:                 uuid(),            // assigned customer-success rep
  capturedAt:          timestamp({ withTimezone: true }).defaultNow().notNull(),
});
```

The snapshot is captured when a ticket is created and pinned to the ticket. The customer's stage may change later — the *ticket* should reflect what stage they were in at filing time, since that's what set the priority.

## Tagging Tickets With Stage At Creation

```ts
async function createTicketWithLifecycleContext(input: NewTicket) {
  const stage = await resolveCurrentStage(input.userId);
  const snapshot = await captureLifecycleSnapshot(input.userId);

  const ticket = await db.insert(supportTickets).values({
    ...input,
    metadata: {
      ...input.metadata,
      lifecycleStage: stage,
      lifecycleSnapshotId: snapshot.id,
    },
    priority: computePriority(input, snapshot),     // stage-aware
    slaDeadline: computeSlaDeadline(input, snapshot),
  }).returning();

  await applyStageBehaviors(ticket[0], snapshot);
  return ticket[0];
}
```

Per [POLICIES-PER-CATEGORY.md](POLICIES-PER-CATEGORY.md), the priority computation is policy-driven, not free-form per-agent.

## Lifecycle-Aware SLA Prioritization

A free trial user filing a routine support ticket is not the same urgency as a $200K-ARR enterprise customer in their renewal window filing the same ticket. The SLA must reflect this:

```ts
function computeSlaDeadline(t: NewTicket, snap: CustomerLifecycleSnapshot): Date {
  const baseSla = baseSlaFor(t.priority, t.category);

  let multiplier = 1.0;

  // Trial: standard (we want them to succeed)
  if (snap.stage === 'trial')        multiplier = 1.0;
  // Onboarding: tighter (early friction kills activation)
  if (snap.stage === 'onboarding')   multiplier = 0.75;
  // Renewal window: enterprise: very tight
  if (snap.stage === 'renewing' && snap.arr >= 100_000) multiplier = 0.50;
  // At-risk: tight (don't make it worse)
  if (snap.stage === 'at_risk')      multiplier = 0.60;
  // Churned: deferred (data export only)
  if (snap.stage === 'churned')      multiplier = 1.5;
  // Alumni: deferred
  if (snap.stage === 'alumni')       multiplier = 2.0;

  return new Date(Date.now() + baseSla * multiplier);
}
```

Make the multiplier visible in the SLA tooltip — agents need to know *why* a ticket has a 4-hour deadline when the priority would normally be 24 hours. Per [SLA-AS-CONTRACT.md](SLA-AS-CONTRACT.md) the contractual SLA is a floor; lifecycle multipliers are an internal-prioritization addition.

## Per-Stage Support Behaviors

### Lead → Trial

The "welcome ticket" is a system-generated ticket that the customer never sees, used internally to track first-touch onboarding outreach. CSM owns it.

```ts
async function onTrialStarted(userId: string) {
  await createSystemTicket({
    userId,
    category: 'lifecycle_onboarding',
    subject: 'New trial — welcome and onboarding outreach',
    priority: 'p3',
    assignedToCsm: true,
    closeAtMilestone: 'activation',
  });

  await scheduleProactiveCheckin({
    userId,
    triggerAt: addDays(new Date(), 3),
    template: 'trial_day_3_checkin',
  });
}
```

### Trial → Onboarding

If they finish signup but stall, file a "stuck" ticket *to ourselves* (CSM ownership) so it's tracked. Per [PROACTIVE-AND-PREDICTIVE-SUPPORT.md](PROACTIVE-AND-PREDICTIVE-SUPPORT.md), this is the proactive-outreach path.

### Onboarding → Activated

Activation is product-specific — define it explicitly:

```ts
const ACTIVATION_DEFINITION = {
  // E.g., for a CRM:
  // 1. Imported >=10 contacts
  // 2. Sent >=1 email
  // 3. Logged in 3 distinct days
  predicate: async (userId: string) => {
    const c = await getContactCount(userId);
    const e = await getEmailsSent(userId);
    const d = await getDistinctLoginDays(userId, 14);
    return c >= 10 && e >= 1 && d >= 3;
  },
  closeMilestoneTicketsOnHit: true,
  fireEvent: 'customer.activated',
};
```

### Activated → Engaged → Expansion

Expansion-signal flag: user hit a usage threshold that suggests they'd benefit from a larger plan. Tickets opened by this user about feature limits get auto-tagged `expansion_candidate`:

```ts
async function detectExpansionSignal(t: Ticket): Promise<boolean> {
  const usage = await getRecentUsage(t.userId);
  const limits = await getPlanLimits(t.userId);
  const utilization = usage.value / limits.value;
  return utilization >= 0.85;
}
```

The agent UI shows: "This user is at 92% of plan limits. Mention upgrade options if appropriate. CSM contact: jane@acme.com."

### Engaged → At-Risk

Per [VOICE-OF-CUSTOMER-EXTRACTION.md](VOICE-OF-CUSTOMER-EXTRACTION.md), ticket signals feed the churn-prediction model. Specific signals:

```ts
function ticketChurnSignals(tickets: Ticket[]): ChurnSignal[] {
  const signals: ChurnSignal[] = [];
  if (tickets.some(t => t.tags?.includes('cancellation_inquiry'))) {
    signals.push({ kind: 'mentioned_cancellation', weight: 0.4 });
  }
  if (tickets.some(t => /competitor|alternative/i.test(t.message))) {
    signals.push({ kind: 'mentioned_competitor', weight: 0.3 });
  }
  if (tickets.length >= 3 && allUnresolved(tickets)) {
    signals.push({ kind: 'unresolved_pile', weight: 0.5 });
  }
  if (avgSentiment(tickets) < -0.3) {
    signals.push({ kind: 'declining_sentiment', weight: 0.4 });
  }
  return signals;
}
```

When at-risk threshold crosses, fire `customer.at_risk` event. Support manager and CSM notified. New tickets from this customer auto-priority-bump.

### At-Risk / Renewing → Churned

If renewal lapses, the customer transitions to `churned`. Per [OFFBOARDING-AND-ACCOUNT-DELETION.md](OFFBOARDING-AND-ACCOUNT-DELETION.md), this triggers the offboarding flow — but also an exit-survey ticket:

```ts
async function onChurn(userId: string, reason: ChurnReason) {
  await transitionStage(userId, 'churned');

  await createSystemTicket({
    userId,
    category: 'exit_survey',
    subject: 'Exit survey — please share feedback',
    priority: 'p3',
    assignedToCsm: true,
    customerVisible: true,
    closeAfterDays: 14,
  });

  await scheduleAlumniCheckin(userId, addDays(new Date(), 90));
}
```

The exit survey is short (3 questions max) and respectful. Don't bury the customer in a 20-question form on their way out.

### Churned → Alumni

90 days after churn, the customer is `alumni` — eligible for re-engagement campaigns. Tickets from alumni are typically about data access or "I want to come back" — both warrant warm handling, not transactional.

## Stage Transitions As Events

```ts
export const customerLifecycleEvents = pgTable("customer_lifecycle_events", {
  id:                  uuid().primaryKey().defaultRandom(),
  customerId:          uuid().notNull(),
  fromStage:           customerLifecycleStage(),
  toStage:             customerLifecycleStage().notNull(),
  reason:              text(),               // 'activation_hit' | 'health_dropped' | 'renewal_signed' etc.
  triggeredBy:         text(),               // 'system' | 'csm' | 'billing'
  metadata:            jsonb(),
  occurredAt:          timestamp({ withTimezone: true }).defaultNow().notNull(),
});
```

Stage transitions trigger downstream actions:

```ts
async function onStageTransition(e: LifecycleEvent) {
  switch (`${e.fromStage}->${e.toStage}`) {
    case 'trial->activated':
      await scheduleActivationFollowup(e.customerId);
      break;
    case 'engaged->at_risk':
      await alertCsm(e.customerId, 'health_score_dropped');
      await raiseSlaPriority(e.customerId);
      break;
    case 'renewing->churned':
      await openExitSurveyTicket(e.customerId);
      await freezeOpenTicketsForOffboarding(e.customerId);
      break;
    case 'at_risk->engaged':
      await congratulateCsm(e.customerId);     // recovery
      break;
  }
}
```

## Customer-Stage Card In The Support UI

```
┌── Customer ─────────────────────────────────────────────────┐
│ Acme Corp.                                                  │
│ Stage: ENGAGED → AT-RISK (transitioned 2d ago)              │
│ Reason: Health score dropped 78→52 (usage decline + 2       │
│         unresolved tickets)                                 │
│                                                             │
│ ARR: $48,000  |  Renewal: 67 days  |  CSM: jane@acme.com    │
│                                                             │
│ ⚠ This customer is at-risk. SLA accelerated 0.6×.           │
│   Loop in CSM (jane@acme.com) before resolving.             │
│   Avoid SaaS-jargon; prefer empathetic tone.                │
│                                                             │
│ Open tickets (3):                                           │
│   #4571 (this) — billing question, p2                       │
│   #4523 — export bug, p2 (5d unresolved)                    │
│   #4501 — onboarding gap, p3 (12d unresolved)               │
│                                                             │
│ [Page CSM] [View health timeline] [Apply at-risk template]  │
└─────────────────────────────────────────────────────────────┘
```

The card surfaces stage *and* the support behaviors that should change. Without this, the agent treats every ticket the same.

## Per-Stage Tone Calibration

Per [TONE-AND-EMPATHY-PATTERNS.md](TONE-AND-EMPATHY-PATTERNS.md), tone shifts by stage:

| Stage | Tone | Notes |
|---|---|---|
| Trial | Welcoming, educational | They haven't committed; help them succeed |
| Onboarding | Patient, instructional | Many "newbie" questions; never condescend |
| Activated/Engaged | Efficient, direct | Respect their familiarity; don't over-explain |
| Expansion | Solution-aware | Offer larger-plan paths if relevant |
| At-Risk | Warm, empathetic | They're considering leaving; meet them there |
| Renewing | Hyper-attentive | Every interaction is a renewal moment |
| Churned/Alumni | Respectful, no-pressure | They left; honor that, don't sales-pitch |

## Renewal-Risk Escalation

When a ticket from a renewing-window customer is filed, additional escalation logic kicks in:

```ts
async function applyRenewalRiskEscalation(t: Ticket, s: CustomerLifecycleSnapshot) {
  if (s.stage !== 'renewing') return;

  if (s.daysToRenewal <= 30 && t.priority !== 'p0') {
    await tag(t.id, 'renewal_risk');
    await ccCustomerSuccess(t.id, s.csm);
  }

  if (s.daysToRenewal <= 7) {
    // Last week before renewal — every ticket is critical
    await raisePriority(t.id, 'p1');
    await pageAccountTeam(t.id);
  }
}
```

The account team should never be surprised by a ticket from a renewing customer they didn't know about.

## Post-Renewal Pulse

After a customer renews, send a system-generated "thank you / how can we serve better" check-in:

```ts
async function onRenewalSigned(customerId: string) {
  await transitionStage(customerId, 'engaged');
  await scheduleProactiveCheckin({
    userId: customerId,
    triggerAt: addDays(new Date(), 14),
    template: 'post_renewal_pulse',
  });
}
```

The pulse goes through the ticket system so responses flow into the same channel — preserves history, attributes credit.

## Post-Churn Alumni Follow-Up

90 days after churn, if the customer left for a fixable reason, an alumni check-in:

```ts
async function alumniCheckIn(customerId: string) {
  const churnReason = await getChurnReason(customerId);
  if (FIXABLE_CHURN_REASONS.has(churnReason)) {
    await sendAlumniEmail({
      customerId,
      template: `alumni_${churnReason}_v1`,
      replyHandling: 'create_ticket_assigned_to_csm',
    });
  }
}
```

Per [VOICE-OF-CUSTOMER-EXTRACTION.md](VOICE-OF-CUSTOMER-EXTRACTION.md), alumni replies are gold for product feedback. They're past the politeness layer.

## Cost-Of-Support By Stage

Per [COST-OF-SUPPORT.md](COST-OF-SUPPORT.md), break down support cost by lifecycle stage. A common finding:

```
Stage          Tickets/Customer   Cost/Customer   ARR     Cost%
─────────────────────────────────────────────────────────────────
trial          0.4               $12             $0      ∞
onboarding     2.1               $58             $400    14.5%
activated      0.6               $21             $1,200  1.8%
engaged        0.3               $11             $1,200  0.9%
expansion      0.4               $14             $2,400  0.6%
at_risk        1.8               $74             $1,200  6.2%
renewing       0.9               $42             $1,200  3.5%
```

Onboarding is expensive but necessary. At-risk is expensive *and* a leading indicator of churn — investing in better at-risk support pays back in retention. Engaged customers are nearly free; reward the team for keeping them there.

## Anti-Patterns

| ✗ | Why |
|---|---|
| FIFO queue regardless of stage | Renewing enterprise customer waits behind trial-user "how do I sign up" |
| Stage stored only in CRM | Support tool doesn't know; agents make wrong calls |
| Stage snapshot taken at ticket-resolve time | Stage changed; original urgency is lost |
| Same SLA for trial and at-risk | Trial overserved, at-risk underserved |
| Activation defined fuzzy | Hard to know when "stuck" or "succeeded" |
| Exit survey is 20 questions | Customers won't fill it out; you get noise |
| No alumni follow-up | Lose recoverable churners; lose product feedback |
| Stage transitions silent | CSM finds out customer churned via dashboard, not event |
| Renewal-window not surfaced to agent | Routine ticket gets routine handling 5 days before renewal |
| Auto-tone disabled in at-risk | Templated curt replies push the customer over the edge |
| Lifecycle as a separate system | Two sources of truth for "are they paying" — they will diverge |
| Health score not visible to agent | Agent confused why this ticket is escalated |

## Wire Points Checklist

- [ ] `customer_lifecycle_stage` enum defined and bound to customers
- [ ] `customer_lifecycle_snapshots` table; snapshot at ticket creation
- [ ] `customer_lifecycle_events` table for transitions
- [ ] Stage-aware SLA multiplier in priority/SLA computation
- [ ] Per-stage support behaviors enumerated (welcome / onboarding / activation / expansion / at-risk / renewal / exit / alumni)
- [ ] Activation milestone defined explicitly per product
- [ ] Customer-stage card surfaced in support UI
- [ ] Per-stage tone guidance surfaced to agent
- [ ] Renewal-window auto-escalation (within 30d / 7d)
- [ ] Expansion-signal auto-tag for plan-limit-near-cap
- [ ] At-risk priority bump and CSM cc
- [ ] Exit-survey ticket auto-created on churn
- [ ] Alumni 90-day check-in
- [ ] Cost-of-support per-stage report
- [ ] Stage transitions emit events to webhook/queue (per [OUTBOUND-WEBHOOKS-FOR-CUSTOMERS.md](OUTBOUND-WEBHOOKS-FOR-CUSTOMERS.md) for internal subscribers)
- [ ] Test: trial-stage ticket gets standard SLA; renewing-30d-stage ticket gets 0.5× SLA
- [ ] Test: stage transition `engaged -> at_risk` raises priority on open tickets
- [ ] Test: post-renewal pulse ticket created within 14 days of renewal
