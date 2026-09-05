# Audit Prompt — Existing System

For projects that already have *some* support ticketing — checks each Hard Invariant and lists gaps.

## Prompt

```
Audit the existing support ticketing system in this Next.js codebase against
the Hard Invariants defined in user-support-ticketing-system-for-saas. Return
a punch list grouped by severity:

CRITICAL (ship-blocking):
- Direct-table writes from API handlers (bypass service layer)
- Missing email-out wire on admin reply (silent admin notes)
- Rate-limit not tier-aware (paid users in anon bucket)
- No audit on privileged mutations
- Missing CRON_SECRET check on alert endpoint

HIGH (real risk):
- OPEN_TICKET_STATUSES duplicated or inconsistent across files
- Status-transition logic implemented in handlers, not service
- N+1 in admin list endpoint (no inArray batch fetch)
- Customer can read another user's ticket (any 403, should be 404)
- Cron auto-resolves or auto-closes (footgun)
- No support-triage handoff docs or list-open adapter, so future agents re-discover the queue every session

MEDIUM (cleanup):
- Permissions inline-checked instead of via key registry
- Email subject lines use full UUID
- Reply form doesn't disable on closed status
- Missing slaBreachedAt stickiness (clears on resolve)
- Policies exist only in code comments, not owner-approved support docs

LOW (polish):
- Admin UI missing count pills / SLA filter bucket
- User UI doesn't translate awaiting_customer to plain English
- AGENTS.md / docs lacks support-system blurb

For each finding: file:line, current behavior, desired behavior, fix sketch.
```

## Mining For Findings

Run these searches first:

```bash
# Direct table writes from handlers
rg -n "db\.update\(supportTickets\)|db\.insert\(supportTickets\)" \
  src/app/api/admin/support src/app/api/support

# OPEN_TICKET_STATUSES duplicated definitions
rg -n "OPEN_TICKET_STATUSES|SLA_ACTIVE_STATUSES" src/

# N+1 risk in list endpoints
rg -n "for.*await.*query|\.map.*await.*db" src/app/api/admin/support

# Rate-limit identity resolution
rg -n "enforceRateLimit|getClientIp|rateLimit" src/app/api/support src/lib/rate-limit*

# Audit calls
rg -n "logAction|auditLog" src/app/api/admin/support

# Triage handoff artifacts
test -f .claude/support-triage/_detection.json
test -x .claude/support-triage/scripts/list-open.sh
rg -n "Refunds|Escalation|Send Confirmation|Security" .claude/support-triage/05-policies.md
```

## Output Format

Match `/codebase-audit` style: each finding has

```
🔴/🟠/🟡 file:line
  Current:  what's there
  Risk:     specifically what could go wrong
  Fix:      one-paragraph sketch with the right pattern from this skill's references
```

## Common Findings (From Real Audits)

These are recurring:

1. `requireUser` runs *after* `enforceRateLimit` → paid users land in anon bucket. Move identity resolution first.
2. PATCH mutates without writing audit. Add the `mutation.context.logAction(...)` call in every PATCH path.
3. `awaiting_customer` SLA clock still counts down. Audit the SLA query: it should filter to `OPEN_TICKET_STATUSES`.
4. Admin support reply path forgets `sendTicketResponseEmail`. Wire it into the POST handler with `after()`.
5. The cron uses a request-time secret comparison but `req.headers.get("x-cron-secret")` returns null because Vercel passes it under a different name. Verify against Vercel docs.
