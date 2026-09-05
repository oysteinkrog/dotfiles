# Ticket Lifecycle State Machine And Conformance

The ticketing system is only support-ready if status transitions are computed
the same way from every entry point: user API, admin API, email webhook, cron,
migration import, and future AI assist actions.

This file is the portable state-machine spec. Framework-specific docs such as
`SLA-ENGINE.md` explain how to implement it in Next.js + Drizzle, but the state
machine itself is independent of framework, ORM, and provider.

## Canonical Statuses

| Status | Meaning | SLA Clock |
|---|---|---|
| `open` | New ticket, not yet acknowledged | running |
| `acknowledged` | Team has accepted the ticket but not begun work | running |
| `in_progress` | Team owns next action | running |
| `awaiting_customer` | Customer must answer before work can continue | paused |
| `resolved` | Team believes the issue is solved | stopped |
| `closed` | Thread is complete and should not reopen automatically | stopped |

Projects may add extension states, but they must map each extension to one of:

- SLA running;
- SLA paused;
- terminal.

If an extension state cannot be classified this way, it is not ready for
automation.

## Canonical Events

| Event | Meaning |
|---|---|
| `customer_create` | Customer opens a new ticket. |
| `customer_reply` | Customer adds a message through UI/email. |
| `support_ack` | Support marks the ticket acknowledged without customer-visible message. |
| `support_reply` | Support sends a customer-visible reply. |
| `support_internal_note` | Support adds internal-only context. |
| `support_resolve` | Support marks ticket resolved. |
| `support_close` | Support closes ticket. |
| `cron_sla_check` | Cron recomputes `slaStatus`; never closes or messages. |

## Required Transition Table

| Current | Event | Next | Side Effects |
|---|---|---|---|
| none | `customer_create` | `open` | create ticket, compute SLA deadline, send created email |
| `open` | `support_ack` | `acknowledged` | audit reason, no customer-visible send |
| `open` | `support_reply` | `awaiting_customer` | send response email, audit, pause SLA |
| `acknowledged` | `support_reply` | `awaiting_customer` | send response email, audit, pause SLA |
| `in_progress` | `support_reply` | `awaiting_customer` | send response email, audit, pause SLA |
| `awaiting_customer` | `customer_reply` | `in_progress` | resume SLA, audit user reply |
| `open` | `customer_reply` | `open` | append message, recompute priority if needed |
| `acknowledged` | `customer_reply` | `in_progress` | append message, support owns next action |
| `in_progress` | `customer_reply` | `in_progress` | append message, keep running |
| `open` / `acknowledged` / `in_progress` / `awaiting_customer` | `support_resolve` | `resolved` | audit reason, optional resolved email |
| `resolved` | `support_close` | `closed` | audit reason |
| `closed` | `customer_reply` | reject | do not reopen automatically; ask customer to create new ticket |
| any | `support_internal_note` | unchanged | audit/internal note only |
| any non-terminal | `cron_sla_check` | unchanged | may update `slaStatus`; never sends/auto-resolves |

## Conformance Fixture Shape

Use language-neutral fixtures so any stack can prove behavior:

```json
{
  "name": "support reply pauses sla",
  "initial": {
    "status": "in_progress",
    "slaStatus": "ok",
    "slaDeadline": "2026-04-27T18:00:00Z"
  },
  "event": {
    "type": "support_reply",
    "actor": "admin",
    "body": "Can you send the exact CLI version?"
  },
  "expected": {
    "status": "awaiting_customer",
    "slaClock": "paused",
    "emailSent": true,
    "auditWritten": true
  }
}
```

Every implementation should run at least these fixture groups:

- create ticket;
- support acknowledgement;
- support reply pauses SLA;
- customer reply resumes SLA;
- internal note does not email;
- cron marks breached but does not close;
- closed ticket rejects customer reply;
- admin mutation without reason rejects;
- unsupported extension state fails with a clear mapping error.

## Extension States

Some products need states such as:

- `awaiting_engineering`;
- `blocked_by_provider`;
- `escalated_to_legal`;
- `merged_as_duplicate`;
- `pending_refund_review`.

Extensions are allowed only if each has:

```json
{
  "state": "awaiting_engineering",
  "slaClock": "running",
  "terminal": false,
  "owner": "engineering",
  "customerVisibleLabel": "Investigating"
}
```

Do not add an enum value until the lifecycle semantics and customer-visible copy
are both defined.

## Known Gap: Business-Hours SLAs

This spec assumes wall-clock deadlines. Enterprise contracts often require
business-hours calculations with holidays and customer timezone. Treat that as a
project-specific extension with a freshness/evidence anchor in the policy docs.

Do not claim business-hours SLA support unless tests cover:

- timezone;
- weekend/holiday skip;
- daylight saving transitions;
- customer/org-specific calendars;
- pause/resume across closed hours.

## Acceptance Standard

The ticketing system is not done until:

- every status mutation enters through one service-layer transition function;
- the conformance fixtures pass;
- cron proves it never sends, closes, or resolves tickets;
- the triage handoff adapter exposes normalized status and SLA fields;
- extension states, if any, map to running/paused/terminal semantics;
- docs identify the state machine as canonical and implementation pages as
  framework-specific.
