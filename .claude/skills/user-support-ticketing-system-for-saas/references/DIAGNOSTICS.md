# Diagnostics — Symptom-Keyed Troubleshooting

When something is broken on a live ticketing system, jump straight to the symptom. Each entry has: minimal repro, most-likely cause, copy-paste check, and the fix wire-point.

This doc is for **operating** the system after Phase 7. For build-time wiring see [CHECKLIST.md](CHECKLIST.md); for failure modes that warn you off bad designs see [ANTI-PATTERNS.md](ANTI-PATTERNS.md).

## Smoke First

```bash
./scripts/doctor.sh                 # required + informational checks
./scripts/doctor.sh --json | jq .   # machine-readable
```

If `doctor.sh` reports any required failure, fix that first — every symptom below assumes the prerequisites are green.

## Symptom Index

| Symptom | Section |
|---|---|
| Customer says "I never got the email" | [Email not arriving](#email-not-arriving) |
| Admin reply sent but customer not notified | [Admin reply email silent](#admin-reply-email-silent) |
| `slaStatus` stuck on `ok` past the deadline | [SLA cron not flagging](#sla-cron-not-flagging) |
| Customer reply doesn't move ticket out of `awaiting_customer` | [Status transition skipped](#status-transition-skipped) |
| Closed ticket reopens on a customer reply | [Closed ticket reopen leak](#closed-ticket-reopen-leak) |
| Admin list endpoint slow / `pg_stat_statements` shows N+1 | [Admin list N+1](#admin-list-n1) |
| Paid user hits `429` on user routes | [Tier-blind rate limit](#tier-blind-rate-limit) |
| `support.read` permission denies for an admin | [Permission registry mismatch](#permission-registry-mismatch) |
| Audit log empty after PATCH | [Audit log not writing](#audit-log-not-writing) |
| Cron returns `403` silently | [Cron 403](#cron-403) |
| Resend dashboard shows `domain_unverified` | [Resend domain unverified](#resend-domain-unverified) |
| Migration brought tickets in but `resolvedAt` is all NULL | [Provider import resolvedAt missing](#provider-import-resolvedat-missing) |

## Email not arriving

**Repro**: file a test ticket from a Gmail address; wait 60s; check inbox + spam.

**Most-likely causes** (in order):

1. **Resend domain not verified** — see [Resend domain unverified](#resend-domain-unverified).
2. **`after()` not used and request was aborted** — if the email is fired in `after()` but the platform doesn't support it, the email never sends. Confirm the runtime is Next.js 16 App Router on Vercel; on other hosts use a queue.
3. **`RESEND_FROM_EMAIL` mismatch** — must match the verified domain exactly.
4. **Rate-limited by Resend** — free tier is 100/day; check Resend dashboard.

```bash
# Confirm the env vars are loaded
grep -hE '^(RESEND_API_KEY|RESEND_FROM_EMAIL|RESEND_FROM_NAME)=' .env.local .env 2>/dev/null

# Confirm domain is verified (replace with your domain)
curl -s -H "Authorization: Bearer $RESEND_API_KEY" \
  https://api.resend.com/domains | jq '.data[] | {name, status}'
```

**Fix**: see [EMAIL.md](EMAIL.md) "Wire points" — every customer-touching reply MUST go through `sendTicketResponseEmail` or equivalent.

## Admin reply email silent

**Repro**: as admin, post a message via `POST /api/admin/support/tickets/[id]/messages`. Customer should receive `sendTicketResponseEmail`.

**Most-likely causes**:

1. **Wire-point bypass** — handler writes `supportMessages` directly instead of routing through `addAdminMessage()` in the service layer.
2. **`after()` registered but the route returned an error response** — `after()` only fires on a *successful* response. Check the response status.
3. **Customer email is null on the user record** — `sendEmail` short-circuits to a no-op.

```bash
# Find direct table writes in handlers (should be zero hits)
grep -rn "db.insert(supportMessages)" src/app/api/admin
```

**Fix**: route every admin message through `addAdminMessage()` in `src/lib/services/support-tickets.ts`. The service is the only path that triggers email; handlers must not write the table directly.

## SLA cron not flagging

**Repro**: file a P0 ticket, advance time past the deadline, hit `/api/cron/sla-alerts` with the cron secret, observe `slaStatus`.

**Most-likely causes**:

1. **Cron schedule not registered** — the route exists but Vercel never calls it.
2. **`OPEN_TICKET_STATUSES` excludes a status that's actually open in your config** — the deadline check skips the ticket because it isn't considered "open".
3. **`getTicketsApproachingSla()` clock arithmetic uses local time vs UTC** — silent drift.

```bash
# Check Vercel cron schedule
jq '.crons' vercel.json

# Manually fire the cron with the secret (read-only via GET)
curl -s -H "Authorization: Bearer $CRON_SECRET" \
  http://localhost:3000/api/cron/sla-alerts | jq .

# Verify which ticket statuses count as "open"
grep -nE 'OPEN_TICKET_STATUSES\s*=' src/lib/services/support-tickets.ts
```

**Fix**: see [CRON-AND-ALERTS.md](CRON-AND-ALERTS.md). `awaiting_customer` MUST be excluded from `OPEN_TICKET_STATUSES`; everything else open should be included.

## Status transition skipped

**Repro**: ticket in `awaiting_customer`, customer posts a reply via `POST /api/support/tickets/[id]/messages`, expect status to become `in_progress`.

**Most-likely causes**:

1. **Handler writes the message without calling `computeNextStatusAfterMessage()`** — message lands but ticket stays paused.
2. **`senderType` not set on the new message** — function falls into a default branch and no-ops.
3. **Ticket was `closed`, not `awaiting_customer`** — closed terminal MUST reject reopen ([ANTI-PATTERNS.md](ANTI-PATTERNS.md) item 11).

```bash
# Verify the customer-message path uses the service
grep -rn "addCustomerMessage\|computeNextStatusAfterMessage" src/app/api/support
```

**Fix**: route customer messages through `addCustomerMessage()`. The service computes next status atomically with the insert.

## Closed ticket reopen leak

**Repro**: close a ticket, then post a customer reply. Expect 409 / explicit rejection. If status flips back to `open`, you have the leak.

**Most-likely cause**: `addCustomerMessage()` doesn't check terminal status before computing the transition.

```bash
# Look for the guard
grep -nE "if .*status.*===.*['\"](closed|resolved)" src/lib/services/support-tickets.ts
```

**Fix**: at the top of `addCustomerMessage()`, reject with a specific error code when `ticket.status` is `closed`. `resolved` MAY accept the reply and re-open to `in_progress` (project-specific — see your `05-policies.md`).

## Admin list N+1

**Repro**: open `/admin/support/tickets`. Watch DB query log; if the tickets list spawns N lookups for users + N for orgs, you have the leak.

**Most-likely cause**: list handler calls `getUserById()` per row instead of a single `inArray()` batch.

```bash
# Should be using inArray for users and orgs
grep -nE "inArray\(.*users\.id" src/app/api/admin/support/tickets/route.ts
grep -nE "inArray\(.*organizations\.id" src/app/api/admin/support/tickets/route.ts
```

**Fix**: collect all `userId` / `orgId` values from the page of tickets, fetch once via `inArray`, then build a Map and join in JS. Pattern in [ADMIN-API.md](ADMIN-API.md) under "List endpoint shape".

## Tier-blind rate limit

**Repro**: log in as a paid user; hit `POST /api/support/tickets` 5 times in 60s. If you 429 before the paid bucket would, identity is being resolved AFTER the limiter.

**Most-likely cause**: limiter middleware runs before `requireUser()`, so all requests share the anonymous bucket.

**Fix**: resolve user / tier first, THEN look up the appropriate bucket. See [SECURITY.md](SECURITY.md) "Rate-limit tier" for the helper.

## Permission registry mismatch

**Repro**: admin with `support.read` granted gets `403` from the list endpoint.

**Most-likely causes**:

1. **Permission key not registered** — `requireAdminPermission("support.read")` checks against a registry; the key was added to the route but never registered.
2. **Typo in the key** — `support.read` vs `support_read` vs `supportRead`.

```bash
# All three should refer to the same string literal
grep -rn "support\.read\|support\.assign\|support\.resolve" src/lib src/app/api/admin
```

**Fix**: register the three keys in your permission registry (see [SECURITY.md](SECURITY.md) "Permission registration"). The registry MUST be the only source of truth.

## Audit log not writing

**Repro**: PATCH a ticket as admin, confirm `auditLog` table grew by one row.

**Most-likely cause**: handler invokes the service mutation directly without the `withAudit()` wrapper.

```bash
grep -rn "withAudit\|auditLog.insert" src/app/api/admin/support
```

**Fix**: every admin mutation MUST go through the shared `withAudit()` helper which writes before/after diff + reason. Direct service calls bypass it.

## Cron 403

**Repro**: Vercel cron fires; logs show `403` from `/api/cron/sla-alerts`; alerts don't run.

**Most-likely causes**:

1. **`CRON_SECRET` env var not set in Vercel project settings** — local dev works, prod silently 403s.
2. **`Authorization` header check is case-sensitive against a lowercase `bearer`** — Vercel sends `Bearer`.
3. **Different secret values between Vercel and Resend / vendor cron** — they're independent secrets; rotating one doesn't rotate the other.

```bash
# Verify it's set in Vercel (run locally with vercel CLI)
vercel env ls production | grep CRON_SECRET
```

**Fix**: see [CRON-AND-ALERTS.md](CRON-AND-ALERTS.md) "CRON_SECRET wiring". Compare with `Bearer ${CRON_SECRET}` exactly.

## Resend domain unverified

**Repro**: `domain_unverified` errors in Resend dashboard, or all sends silently bounce.

**Most-likely cause**: DNS records (SPF / DKIM / DMARC) not propagated, or were added under a different DNS provider than the one currently authoritative.

```bash
# Confirm DNS is propagated for your sending domain
dig TXT yourdomain.com | grep -i 'spf\|dkim\|resend'
dig CNAME resend._domainkey.yourdomain.com
```

**Fix**: re-pull the domain's DNS records from Resend's dashboard, paste into your DNS provider, wait 1h, click "Verify" again. Don't first-send until status is `verified`.

## Provider import resolvedAt missing

(Specific to migrations from Zendesk/Intercom/Help Scout/etc.)

**Repro**: imported tickets have `status = 'closed'` but `resolvedAt = NULL`. Reports breaks.

**Most-likely causes**:

1. **Zendesk**: `solved_at` lives on the `metric_set` sideload, not the base ticket. Without `?include=metric_sets` the field is always `null`.
2. **Intercom**: `state` of `closed` doesn't carry a timestamp; need `statistics.last_close_at`.
3. **Help Scout**: `closedAt` only present if status is `closed`; `active` tickets won't have it.

```bash
# For Zendesk: confirm export request included metric_sets
grep -n "include=metric_sets\|include=users" scripts/export-zendesk.sh
```

**Fix**: see [MIGRATION-PER-PROVIDER.md](MIGRATION-PER-PROVIDER.md) per-provider sections — each has a verified field-mapping table.

## Adding new symptoms

When you hit a real production failure not listed above:

1. Add a new `## Symptom` section using the same template (Repro / Causes / Check / Fix wire-point).
2. Add a row to the [Symptom Index](#symptom-index).
3. If the failure is recoverable via a migration / config change, link to the relevant ref doc; if it's a design defect, also add a row to [ANTI-PATTERNS.md](ANTI-PATTERNS.md).
