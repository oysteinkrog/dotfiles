# Ticket Lifecycle States — Beyond Open / Closed

Most ticketing systems ship with a binary: open and closed. Real triage needs richer state. The customer's experience, the SLA's correctness, and the team's queue legibility all depend on the right state being set at the right moment. This file is the canonical state machine — and the discipline of moving tickets through it without losing information.

> **Core insight:** the wrong state at the right moment is invisible to the customer but corrupts every downstream metric and every handoff. A ticket "open" while actually waiting on the customer hurts your SLA stats; "closed" while the customer never confirmed hurts your retention. Get the states right and the rest of the triage system works as intended.

This file complements the existing `🚦 PAUSE-SLA` operator (which sets `awaiting_customer`) and `📤 SEND` (which often transitions state). Together they govern the lifecycle.

---

## The Canonical States

| State | Meaning | SLA | Owner attention |
|---|---|---|---|
| **new** | Just landed; not yet triaged | Yes (FRT clock running) | High (next ★ ORIENT target) |
| **investigating** | Triage in progress; not yet ready to draft | Yes | Active |
| **draft-ready** | Reply drafted; awaiting owner approval | Paused | Owner |
| **awaiting_customer** | Sent; customer has the ball | Paused | Low (timer for nudge) |
| **awaiting_engineering** | Bug confirmed; passed to eng team | Paused (for support SLA) | Low for support; high for eng |
| **awaiting_external** | Blocked on a third-party (Stripe, PayPal, vendor) | Paused | Low for support; tracked |
| **snoozed** | Owner explicitly deferred to a date | Paused (until snooze ends) | None until wake |
| **watching** | Resolved-pending-confirmation; alert if customer comes back | Closed | None unless re-activates |
| **legal-hold** | Counsel-engaged; standard process suspended | Paused | Counsel |
| **crisis-hold** | Crisis-flag detected (per `TRAUMA-INFORMED-SUPPORT.md`); special path | Paused | Owner + specialist |
| **closed** | Resolved; customer confirmed or appropriate timeout reached | Closed | None |
| **closed-unresolved** | Closed but didn't resolve to customer satisfaction (rare; mark explicitly) | Closed | Quality review |

Project-specific systems may add states; these are the defaults the skill assumes. `05-policies.md` records project additions.

---

## State Transitions And When They Trigger

```
        ┌─────────────────────────────────────────────┐
        │                                             │
        ▼                                             │
      [ new ]                                         │
        │                                             │
   ★ ORIENT triggered                                 │
        ▼                                             │
   [ investigating ]                                  │
        │                                             │
   ✉ DRAFT produced                                   │
        ▼                                             │
   [ draft-ready ]                                    │
        │                                             │
   ✓ CONFIRM by owner                                 │
        ▼                                             │
   📤 SEND  ─── outbound has a question? ── yes ──→ [ awaiting_customer ]
        │                                                       │
        no (resolution sent)                                    │ customer replies
        ▼                                                       │ within nudge window
   [ watching ]  ──── customer comes back? ─── yes ──────────→ [ investigating ] (reopen)
        │                                                       │
        time out (default 14d)                                  │
        ▼                                                       │
   [ closed ]                                                   │
                                                                │
   Detected scope:                                              │
     Crisis flag         → [ crisis-hold ]                      │
     Legal/red-flag      → [ legal-hold ]                       │
     Bug confirmed       → 🐞 BEAD; [ awaiting_engineering ]    │
     Third-party blocker → [ awaiting_external ]                │
     Owner defers        → [ snoozed ]                          │
                                                                │
   Recovery from non-customer states:                           │
     awaiting_engineering → fix shipped → 🔁 LOOPBACK ──────────┘
     awaiting_external → vendor responded → ────────────────────┘
     snoozed → wake date → [ investigating ] ───────────────────┘
     legal-hold → counsel cleared → [ investigating ] ──────────┘
     crisis-hold → owner cleared → [ investigating ] ───────────┘
```

---

## When To Use Each State (Common Mistakes)

### `awaiting_customer` (the most-misused)

**Use when**: the *only* way to advance is data from the customer (logs, version, exact error, identity verification).

**Don't use when**: you're investigating in parallel; you sent a reply but expect they don't need to respond; you wanted to game the SLA.

The 🚦 PAUSE-SLA operator's discipline applies: every paused ticket must contain a numbered ask. Pausing without a clear ask compounds frustration.

### `awaiting_engineering`

**Use when**: bug is confirmed and the next material movement is a code fix; support's role is monitoring not investigating.

**Don't use when**: you haven't yet confirmed it's a bug; you've filed a bead but haven't told the customer.

The customer should know the ticket is in this state ("logged as engineering issue ENG-217; we'll notify you when fixed"). Hidden hand-off destroys trust; transparent hand-off preserves it.

### `awaiting_external`

**Use when**: the next material movement is from a third-party (Stripe is processing the refund; vendor X is investigating their outage; bank is reviewing the chargeback).

**Don't use when**: you're hoping the third-party will get back; you should be following up actively.

Tickets in this state need a *follow-up cadence* in the agent's working state. "Stripe replied within 48h" is normal; "Stripe didn't reply for 7 days" should escalate the agent's behaviour to chase.

### `snoozed`

**Use when**: you've made a decision to defer ("we'll revisit in two weeks once the new feature ships").

**Don't use when**: you don't know what to do; you're hoping the issue resolves itself.

A snoozed ticket needs a wake date and a wake action. "Snoozed until Q3" without specifics is just hidden backlog.

### `watching`

**Use when**: you've sent a resolution; the customer hasn't confirmed; you want to be alerted if they return.

**Don't use when**: you sent and forgot.

Default watching window: 7-14 days. After that: if customer didn't respond, close with a "happily reopen if you need more" note. If customer came back: reopen to `investigating`.

### `legal-hold` and `crisis-hold`

These are special states where standard automation **does not apply**:

- No SLA reminders
- No automated follow-ups
- No batch-bundle inclusion
- No automated reassignment
- Audit-log access restricted

Per `EVIDENCE-CHAIN-OF-CUSTODY.md` and `TRAUMA-INFORMED-SUPPORT.md` respectively. Mis-classification (treating a `crisis-hold` as `awaiting_customer`) is among the worst possible failures.

### `closed-unresolved`

A discipline most teams skip: distinguish "closed because resolved" from "closed because we couldn't help / customer gave up / ran out of patience". Tracking these separately:

- Reveals the real CSAT picture
- Catches patterns of repeated unresolved cases
- Surfaces owner-side learning

When `closed-unresolved` is triggered:
- Internal note explains why
- Theme tag reflects the unresolved class
- Aggregate to scoreboard

---

## State Transitions As Customer-Visible Events

Every state transition is implicitly visible to the customer (they hear back from us, they don't, they get a reminder). Discipline:

- **`new` → `investigating`**: send a courtesy "we're on this" if SLA tier requires fast acknowledgement
- **`investigating` → `draft-ready`**: invisible to customer
- **`draft-ready` → `awaiting_customer` (after send)**: customer sees the question in the reply
- **`awaiting_customer` → `investigating` (reopen)**: invisible; the customer's reply is the trigger
- **`investigating` → `awaiting_engineering`**: tell the customer ("logged as eng issue; expect update by [date]")
- **`awaiting_engineering` → ... → `closed` (after fix)**: 🔁 LOOPBACK notification
- **`watching` → `closed`**: optional "everything ok?" check before closing
- **anything → `legal-hold`**: invisible to customer; counsel handles further communication
- **anything → `crisis-hold`**: dedicated handling per `TRAUMA-INFORMED-SUPPORT.md`

The principle: customers hate state transitions they don't know about. Transparent transitions are slow but trustworthy; hidden ones are fast but corrosive.

---

## Reopen Logic

A common bug: the customer's tangential reply re-opens a closed ticket; the SLA clock starts; the next "first response" SLA breach fires immediately because the agent didn't notice.

The 🎚 LIFECYCLE-STATE operator's specific rule:

```
[OPERATOR-LOCAL: 🎚 LIFECYCLE-STATE — reopen]
1) On any new message in a closed ticket, do NOT auto-reopen.
2) Read the message. Decide:
   a) Tangential reply ("thanks!") → keep closed; SLA clock does NOT
      start; optional "you're welcome" reply.
   b) New issue ("oh, also I'm seeing this other thing") → file new
      ticket; link to the original; SLA clock starts on new ticket.
   c) Continuation of original issue ("it's not actually fixed") →
      reopen this ticket → state = investigating; SLA clock starts.
3) If the SLA-tier rule is "reopen on any reply," lobby to change it
   in 05-policies.md; this is one of the top-cited anti-patterns
   (per ANTI-PATTERNS.md §11).
```

The reopen-on-any-reply pattern is so common and so harmful that fixing it is among the highest-leverage improvements a project can make to its support system.

---

## State And Metrics

The scoreboard (`TRIAGE-SCOREBOARD.md`) reads heavily from state:

- **FRT** = time from `new` → first send (in any state)
- **TTR** = time from `new` → `closed` or `watching`
- **Time-paused** = time in `awaiting_customer` + `awaiting_engineering` + `awaiting_external` + `snoozed` (excluded from active SLA)
- **Reopen rate** = of `closed` tickets, % that returned to `investigating` within 14d
- **Hold rate** = % of tickets that touch `legal-hold` or `crisis-hold`
- **Closed-unresolved rate** = `closed-unresolved` / total closed

If the metrics scoreboard doesn't expose these accurately, state-machine discipline is the issue, not the metrics.

---

## Multi-State Conditions (Edge Cases)

Some tickets are *legitimately* in multiple states or don't fit cleanly:

- **Active outage; customer's ticket is one of N**: keep ticket `investigating` but link to outage incident; the *incident* moves through state machine, customer's ticket moves with it
- **Customer reports two issues in one ticket**: 🔀 SPLIT (per the new operator) into two tickets; original goes to `watching` once both are addressed
- **Duplicate of another ticket from same customer**: 🔗 MERGE; one ticket survives, the other goes to `closed-merged`
- **Cross-customer duplicates** (same root cause): keep tickets separate but link via incident ID; resolve simultaneously via 🪧 BROADCAST

State machine doesn't have to bend; the *number* of tickets adjusts.

---

## How This File Plugs In

| Used by | How |
|---|---|
| 🎚 LIFECYCLE-STATE operator | The state-management discipline |
| 🚦 PAUSE-SLA operator | `awaiting_customer` specifically |
| 📤 SEND operator | State transition on send |
| 🐞 BEAD operator | `awaiting_engineering` transition |
| 🔁 LOOPBACK operator | Wake from `awaiting_engineering` |
| 🔀 SPLIT / 🔗 MERGE operators | Multi-issue ticket handling |
| METRICS-AND-DASHBOARDS.md | State-derived metrics |
| TRIAGE-SCOREBOARD.md | State-aware scoreboard |
| ANTI-PATTERNS.md | Reopen-on-reply, hidden-handoff failure modes |

---

## Cross-References

- [TRIAGE-WORKFLOW.md](TRIAGE-WORKFLOW.md) — phase-by-phase workflow
- [OPERATOR-LIBRARY.md](OPERATOR-LIBRARY.md) — operators that drive state
- [METRICS-AND-DASHBOARDS.md](METRICS-AND-DASHBOARDS.md) — state-derived metrics
- [TRIAGE-SCOREBOARD.md](TRIAGE-SCOREBOARD.md) — what to measure
- [TRAUMA-INFORMED-SUPPORT.md](TRAUMA-INFORMED-SUPPORT.md) — `crisis-hold` discipline
- [EVIDENCE-CHAIN-OF-CUSTODY.md](EVIDENCE-CHAIN-OF-CUSTODY.md) — `legal-hold` discipline
