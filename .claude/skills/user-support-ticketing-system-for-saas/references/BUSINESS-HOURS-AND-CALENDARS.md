# Business Hours And Calendars

Default SLAs assume the team is reachable 24/7/365. Most teams aren't. Without business-hours awareness, P0 tickets filed at 11pm Friday accumulate violation hours over the weekend that no human could have prevented; metrics get distorted; team morale erodes ("we're always behind"); enterprise customers expecting 9-5 coverage get confused when off-hour SLAs are tighter than promised.

This file is the layer that turns wall-clock SLAs into **operating-window SLAs**.

## Two SLA Models

### Model A — "24/7" (Default in this skill)

Wall-clock arithmetic; the customer's wait counts every hour. This is the default and matches the canonical implementation.

**Use when:**
- Your offering has hard real-time uptime claims
- You have follow-the-sun staffing across timezones
- Enterprise tier specifically promises 24/7

### Model B — "Business Hours"

SLAs only count time within configured business hours. Tickets created at 11pm Friday have their clock paused until Monday 9am.

**Use when:**
- You're 9-5 in a single timezone
- Lower tiers explicitly do not promise after-hours
- You want metrics that reflect "we hit our promise to the customer"

### Hybrid (Common In Practice)

- Free tier: business hours only
- Individual tier: business hours, with on-call escalation for P0
- Enterprise tier: 24/7 P0, business hours P1+

Configure per-tier:

```ts
interface TierConfig {
  hoursModel: "wallclock" | "business_hours";
  businessHoursOverride?: BusinessHoursConfig;
  // P0 always on (24/7) regardless of model:
  p0AlwaysOn: boolean;
}
```

## Business Hours Configuration

```ts
interface BusinessHoursConfig {
  timezone: string;                              // IANA, e.g. "America/Los_Angeles"
  schedule: {
    monday?: { start: string; end: string };     // "09:00", "18:00"
    tuesday?: { start: string; end: string };
    wednesday?: { start: string; end: string };
    thursday?: { start: string; end: string };
    friday?: { start: string; end: string };
    saturday?: { start: string; end: string };
    sunday?: { start: string; end: string };
  };
  holidays: string[];                            // YYYY-MM-DD ISO dates
  // Optional: split shifts (e.g. lunch break) — array of windows per day
}

const EXAMPLE_BUSINESS_HOURS: BusinessHoursConfig = {
  timezone: "America/Los_Angeles",
  schedule: {
    monday:    { start: "09:00", end: "18:00" },
    tuesday:   { start: "09:00", end: "18:00" },
    wednesday: { start: "09:00", end: "18:00" },
    thursday:  { start: "09:00", end: "18:00" },
    friday:    { start: "09:00", end: "18:00" },
    // saturday, sunday omitted = closed
  },
  // Example US-style 2026 holiday list. Replace with the project's jurisdiction,
  // support contract, and current year; never copy this list blindly.
  holidays: [
    "2026-01-01", "2026-01-19", "2026-02-16", "2026-05-25",
    "2026-07-03", "2026-07-04", "2026-09-07", "2026-11-26",
    "2026-11-27", "2026-12-24", "2026-12-25", "2026-12-31",
  ],
};
```

Holiday lists must be maintained per year and per jurisdiction. Surface in the admin UI with a "next 12 months" view; set a calendar reminder to refresh annually. A stale holiday list is an SLA bug, not a documentation issue.

## Computing Business-Hours Deadline

```ts
import { addBusinessSeconds } from "./business-hours";

function computeSlaDeadlineWithBusinessHours(
  priority: TicketPriority,
  isEnterprise: boolean,
  type: "firstResponse" | "resolution",
  baseDate: Date,
  config: BusinessHoursConfig,
): Date {
  const tier = isEnterprise ? "enterprise" : "individual";
  const hours = SLA_CONFIG[tier][type][priority];
  return addBusinessSeconds(baseDate, hours * 3600, config);
}

// Adds business-hours seconds, skipping closed times and holidays.
function addBusinessSeconds(start: Date, seconds: number, config: BusinessHoursConfig): Date {
  let remaining = seconds;
  let cursor = start;
  while (remaining > 0) {
    const window = currentOrNextOpenWindow(cursor, config);
    if (!window) {
      throw new Error("Business-hours config has no open windows");
    }
    if (cursor < window.start) cursor = window.start;
    const windowSecondsRemaining = (window.end.getTime() - cursor.getTime()) / 1000;
    if (windowSecondsRemaining >= remaining) {
      return new Date(cursor.getTime() + remaining * 1000);
    }
    remaining -= windowSecondsRemaining;
    cursor = window.end;
  }
  return cursor;
}
```

The implementation is fiddly; pin a reliable test suite around it. (Real-world test: deadline computation for a P2 ticket created Friday at 4pm — the resulting deadline should land Monday during business hours, not Saturday.)

## Pause Outside Business Hours

For tickets in `awaiting_customer`, the SLA pause already handles the pause. For tickets in active states during off-hours under business-hours model, the deadline is *not* extended in real-time — the deadline was already computed at create-time using business-hours arithmetic, so it inherently accounts for off-hours.

**Do not** double-pause: don't extend a deadline that was already computed with off-hours skipped.

## Cron-Time Awareness

The SLA-detection cron's "is this ticket breached" check must use the same business-hours arithmetic:

```ts
function isBreachedNow(ticket: SupportTicket, now: Date, config: BusinessHoursConfig): boolean {
  if (ticket.slaDeadline === null) return false;
  return isWithinBusinessHours(now, config) && now > ticket.slaDeadline;
}
```

A ticket whose deadline passed *during the night* shouldn't be flagged as breached at 9am on Monday — the deadline was computed assuming business-hours, so it lands during business hours by definition. But if `now` is before `slaDeadline` (which is correct), no breach.

The trap: comparing `now` to a wallclock deadline when the deadline was business-hours-computed yields false breaches across weekends.

## Customer Communication

The SLA expectation surfaced to the customer must reflect the model:

```ts
function formatSlaExpectation(deadline: Date, config: BusinessHoursConfig): string {
  const formatted = formatInTimezone(deadline, config.timezone, "MMM d, h:mm a z");
  const note = config.timezone === customerTimezone ? "" : ` (${config.timezone})`;
  return `Expected response by ${formatted}${note}`;
}
```

Show the team's timezone, even if different from the customer's. A response time of "9:30am" without timezone is meaningless.

For enterprise customers in different timezones, the email template includes the customer's local time alongside the team's — *both* are accurate predictions; one is just clearer for them.

## Holiday-Aware Customer Messaging

When a ticket is created on a holiday or after-hours, the auto-confirmation email softly sets expectation:

```
Thanks for reaching out! Our team operates Monday–Friday, 9am–6pm Pacific.
Your ticket was filed at 8:42pm tonight — we'll respond by tomorrow morning.

For urgent issues outside business hours, see our emergency policy: [link].
```

This is *much* better than a "we'll respond within 24 hours" promise the customer expects at 24h sharp.

## Multi-Region Support Teams

For "follow-the-sun" teams (e.g. SF + London + Tokyo), the system can support per-region routing:

```ts
interface RegionConfig {
  name: string;
  timezone: string;
  schedule: BusinessHoursConfig["schedule"];
  agents: string[];           // admin user IDs
}

function pickHandoffRegion(now: Date): RegionConfig {
  // Find the region currently in business hours
  return REGIONS.find(r => isWithinBusinessHours(now, r)) ?? REGIONS[0];
}
```

Tickets created during SF off-hours auto-assign to the London region (or Tokyo, depending on UTC). The deadline is wall-clock 24/7 because *some* team is always on.

## On-Call Escalation Layer

Even on business-hours model, P0 tickets need a path:

```ts
interface OnCallConfig {
  enabled: boolean;
  escalationPolicy: {
    immediate: { method: "pagerduty" | "phone" | "slack-priority"; target: string };
    after15Min: { method: ...; target: string };
    after30Min: { method: ...; target: string };  // wake up the next person
  };
  acknowledgmentRequired: boolean;
}
```

When a P0 ticket lands outside business hours and `p0AlwaysOn` is true:
1. Cron detects on creation, fires the immediate notification.
2. If unacknowledged in 15 min, escalates to next-tier on-call.
3. Etc.

PagerDuty integration is the cleanest path; build via their REST API, sign with their API key.

## Customer-Configurable Timezones

For SaaS where customers schedule things, the customer's timezone matters. Surface it on the customer's profile:

```ts
const userPreferences = {
  timezone: "America/New_York",
  emailDigestHour: 9,                            // local time
};
```

Use customer timezone for:
- Email digest delivery time
- Customer-visible deadline display
- Customer-visible status timestamps ("created 2h ago" computed against their clock)

Not for: SLA computation. SLA is anchored to *team* business hours, not customer expectation.

## Vacation / Reduced-Coverage Periods

The team going to a holiday party / company offsite / conference creates a temporary exception:

```ts
const COVERAGE_OVERRIDES = [
  {
    start: "2026-12-23T17:00",
    end: "2026-12-26T09:00",
    reason: "Christmas holiday - reduced coverage",
    impactedTiers: ["free", "individual"],     // enterprise still on
    customerMessage: "Our team is observing the holiday from Dec 23-26. Tickets will be triaged when we return on Dec 26. For urgent issues, [escalation path].",
  },
];
```

Cron + auto-confirmation email both consult coverage overrides. Customers know in advance.

## SLA Reporting Under Business Hours

`getSlaMetrics` must respect the model. A ticket that breaches at 5:01pm Friday and resolves at 9:01am Monday isn't a 64-hour breach — it's a 1-minute breach by business-hours arithmetic.

```ts
function computeBusinessHoursElapsed(start: Date, end: Date, config: BusinessHoursConfig): number {
  // Walk the business-hours windows between start and end, sum their seconds
  // ... implementation similar to addBusinessSeconds but in reverse
}

const responseTimes = resolvedTickets.map(t => {
  if (t.tier === "wallclock") {
    return (t.resolvedAt.getTime() - t.createdAt.getTime()) / 3600000;
  } else {
    return computeBusinessHoursElapsed(t.createdAt, t.resolvedAt, businessHours) / 3600;
  }
});
```

The CSV export should show both wall-clock and business-hours response times for transparency.

## Anti-Patterns

| ✗ | Why |
|---|---|
| Hardcoding 9-5 PT in service layer | Teams move; tier configs change; needs to be data, not constant |
| Computing deadline with naive `Date.toISOString()` and timezone arithmetic | DST bugs everywhere; use a battle-tested library (date-fns-tz, luxon, temporal) |
| Skipping holidays for "simplicity" | First customer-affecting holiday produces angry tickets |
| Showing customer the team's timezone without label | "9:30am" without zone is half-info |
| Different SLA arithmetic in cron vs UI vs metrics | Drift; the queue says "breached" while metrics say "met" |
| Forgetting to update the holiday list yearly | The 2027 holidays bug fires on January 1 |
| Promising 24/7 you can't deliver | Better to under-promise (business hours) and over-deliver (24/7 in practice) than the reverse |

## Implementation Recommendation

1. Default the skill to wall-clock (Model A) — simplest, matches the canonical implementation.
2. If business-hours is needed, build it as a *separate layer* over the existing SLA engine: `computeBusinessHoursDeadline(...)` is called from `createTicket` instead of `computeSlaDeadline(...)` for tiers in business-hours mode. The persisted `slaDeadline` is still a single timestamp; the cron compares against it normally.
3. Document the chosen model in the project's `00-intake.md` (handoff to the triage skill).
4. Surface the model in the customer-facing pricing page.

## Library Recommendations

- **luxon** (broadest support; well-maintained)
- **date-fns-tz** (lightweight; date-fns ecosystem)
- **TC39 Temporal proposal** (stage 3; future-proof; polyfill available)

Avoid `moment-timezone` (deprecated for new projects).

## Test Fixtures

```yaml
# Friday 4pm PT, 4h SLA, business hours = M-F 9-6 PT
- given: { createdAt: "2026-03-06T16:00:00-08:00", priority: p2, tier: individual_business_hours }
  expected: { slaDeadline: "2026-03-09T11:00:00-07:00" }  # Monday 11am (DST already applied)

# Wednesday 10am PT, 24h SLA, business hours = M-F 9-6 PT (= 9 hours per day)
- given: { createdAt: "2026-03-04T10:00:00-08:00", priority: p2, tier: individual_business_hours }
  expected: { slaDeadline: "2026-03-06T11:00:00-08:00" }  # Friday 11am (24h = 2.67 business days)

# Holiday on a deadline-bearing day (Thanksgiving)
- given: { createdAt: "2026-11-25T16:00:00-08:00", priority: p2, tier: individual_business_hours }
  expected: { slaDeadline: "2026-11-30T11:00:00-08:00" }  # Skips Nov 26-27

# 24/7 model unaffected by hours
- given: { createdAt: "2026-03-06T16:00:00-08:00", priority: p2, tier: enterprise_24_7 }
  expected: { slaDeadline: "2026-03-06T20:00:00-08:00" }  # createdAt + 4h
```
