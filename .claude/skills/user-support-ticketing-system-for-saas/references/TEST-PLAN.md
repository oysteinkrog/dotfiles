# Integration Test Plan

Cover the wire points where bugs hide. Use a real Postgres. For email, use Resend test mode or a narrow boundary fake in API tests; the E2E smoke must hit the real delivery/test-mode provider path.

## Service-Layer Unit Tests

```
✔ computeSlaStatus returns ok / at_risk / breached at the right thresholds
✔ computeNextStatusAfterMessage flips awaiting_customer ↔ in_progress correctly
✔ computeNextStatusAfterMessage refuses to mutate resolved/closed
✔ createTicket sets slaDeadline based on tier+priority
✔ updateTicket on status=resolved clears slaDeadline, keeps slaBreachedAt
✔ awaiting_customer pause: deadline frozen, on resume += pause duration
```

Also run the portable fixtures from
[STATE-MACHINE-CONFORMANCE.md](STATE-MACHINE-CONFORMANCE.md). They are the
stack-independent acceptance tests for lifecycle semantics; the service-layer
unit tests are the local implementation of the same contract.

## API Tests

```
✔ POST /api/support/tickets requires auth, accepts valid input, returns shortId
✔ POST .../tickets sends ticket-created email (assert sendEmail called with right args)
✔ POST .../[id]/messages from customer flips awaiting_customer → in_progress
✔ Customer can't reply to closed ticket
✔ Customer can't access another user's ticket (404, not 403)

✔ Admin GET /api/admin/support/tickets returns paginated + counts
✔ Admin GET respects status / priority / assignee filters
✔ Admin GET in slaBreachHours mode merges breached + approaching, sorted
✔ Admin GET batches user/org lookups (no N+1 — assert query count)

✔ Admin PATCH requires reason; fails 400 without it
✔ Admin PATCH writes audit row with before/after state
✔ Admin POST .../[id]/messages writes message AND fires sendTicketResponseEmail
✔ Admin POST flips ticket to awaiting_customer (pauses SLA)
```

## Cron Tests

```
✔ /api/cron/sla-alerts requires CRON_SECRET; 403 without it
✔ Run with no breaches → no DB writes, no Slack
✔ Run with new breach → slaStatus=breached, slaBreachedAt set, Slack ping fired once
✔ Run twice in succession → second run is no-op (idempotent)
✔ Run with at_risk → slaStatus flips ok → at_risk, no breach yet
```

## Email Tests

```
✔ sendTicketCreatedEmail handles missing user gracefully (returns {sent: false})
✔ sendTicketResponseEmail subject line uses short ID, not UUID
✔ All emails carry the right metadata tags for Resend analytics
✔ User without email address doesn't crash the request flow
```

## Rate-Limit Tests

```
✔ Anonymous user: hit limit at the anon threshold
✔ Free user: hit limit at the free threshold (higher than anon)
✔ Paid user: hit limit at the paid threshold (much higher)
✔ Paid users on shared IP do NOT share buckets
```

## E2E (Playwright) — User Path

```
✔ User opens widget, files ticket, sees confirmation + email arrives
✔ User sees their ticket in the list
✔ User opens detail page, sees support reply, posts a customer reply
✔ Status pill updates to in_progress after customer reply
```

## E2E — Admin Path

```
✔ Admin signs in, sees the ticket on /admin/support/tickets
✔ Admin filters by status=open
✔ Admin clicks ticket, replies, sees email log entry
✔ Admin resolves ticket; user gets resolved email; ticket disappears from open queue
✔ Admin attempts to resolve without reason → form rejects
```

## Triage Adapter Tests

```
✔ .claude/support-triage/scripts/list-open.sh prints support-adapter-v1 JSON
✔ validate-adapter-output.py passes on the open-item output
✔ adapter output includes evidence and safe/unsafe action boundaries
✔ routine fire-drill fixture creates a no-send draft bundle
✔ high-risk fire-drill fixture requires owner confirmation before any unsafe action
```

## Mock Boundary

Per project standard: integration tests hit a real local Postgres. Avoid deep mocks inside services, routes, or Drizzle. Email has one allowed seam: a provider boundary fake that proves the route called `sendTicketResponseEmail` with the right payload. Final E2E still uses Resend test mode or a real sandbox inbox, because mocked delivery passes while production breaks. See `/testing-real-service-e2e-no-mocks`.
