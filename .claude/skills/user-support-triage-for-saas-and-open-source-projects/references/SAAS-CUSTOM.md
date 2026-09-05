# SaaS Custom DB Ticketing Fork

For SaaS apps that store tickets in their own database (not a third-party tool). Common default shape: `support_tickets`, `support_messages`, and optional `support_requests` tables; an admin API or dashboard guarded by project auth; an outbound-email provider for customer replies.

## Onboarding Outputs

The codebase-archaeology pass should produce `01-architecture.md` answering:

- **Tables** — what's in the schema? (`support_tickets`, `support_messages`, `support_requests`, `enterprise_leads`, etc.)
- **Enums** — priorities (`p0|p1|p2|p3`), statuses (`open|acknowledged|in_progress|awaiting_customer|resolved|closed`), categories
- **SLA engine** — file path, deadlines per tier (individual vs enterprise vs free)
- **Service layer** — where business logic lives (e.g., `src/lib/services/support-tickets.ts`)
- **Admin API surface** — every route under `/api/admin/support/*`
- **User API surface** — every route under `/api/support/*`
- **Email pipeline** — `sendTicketCreatedEmail`, `sendTicketResponseEmail`, etc.
- **Cron jobs** — SLA breach alerter, reconciliation, etc.
- **Auth** — admin key vs session, permission keys (`support.read`, `support.assign`, `support.resolve`)

Use the [SAAS-CUSTOM-DETECTOR.md](#detector-queries) queries below.

## Detector Queries

```bash
# Schema tables
rg -n "supportTickets|supportMessages|supportRequests" src/lib/db/ db/ schema.ts schema/ 2>/dev/null

# Enums (priority, status, SLA)
rg -n "ticketPriorityEnum|slaStatusEnum|supportStatusEnum|supportCategoryEnum" src/

# Service layer (SLA computation)
rg -n "computeSlaStatus|slaDeadline|first_response|resolution" src/lib/services src/services

# Admin API routes
rg --files src/app/api/admin/support src/app/api/admin/tickets

# User API routes
rg --files src/app/api/support src/app/api/tickets

# Email pipeline
rg -n "sendTicketResponseEmail|sendTicketCreatedEmail|sendTicketResolvedEmail|sendSupportRequestResponseEmail" src/

# Cron / SLA alerts
rg -l "sla-alerts|sla_breach|sla_alert" src/
```

## Admin API Authentication (How To Connect)

Two patterns are common:

**Pattern A — admin API key (simplest for owner-operated SaaS):**

```bash
ADMIN_KEY=$(grep ADMIN_API_KEY <project>/.env | cut -d= -f2)
BASE="https://<project-domain>"

curl -s "$BASE/api/admin/support/tickets?status=open&limit=50" \
  -H "Authorization: Bearer $ADMIN_KEY" | python3 -m json.tool
```

**Pattern B — admin session cookie (Clerk, NextAuth, Supabase admin):**

Sign in once via the dashboard; export the session cookie; use it as `Cookie: session=...` on every API call. Detection: route uses `requireAdmin(request)` that resolves a user from the session, not a header. Document the procedure in `07-secrets.md`.

If neither exists, the SaaS likely needs admin tooling — propose `/admin-page-for-nextjs-sites` or build a minimal admin auth layer first.

## Standard Quick-Start (paste-ready, parameterize later)

```bash
PROJECT="<project-path>"
DET="$PROJECT/.claude/support-triage/_detection.json"
ADMIN_KEY=$(grep ADMIN_API_KEY "$PROJECT/.env" | cut -d= -f2)
BASE=$(jq -r .base_url "$DET")

# 1. Open tickets (SLA-tracked)
curl -s "$BASE/api/admin/support/tickets?status=open&limit=50" \
  -H "Authorization: Bearer $ADMIN_KEY" | python3 -m json.tool

# 2. SLA metrics
curl -s "$BASE/api/admin/support/sla-metrics" \
  -H "Authorization: Bearer $ADMIN_KEY" | python3 -m json.tool

# 3. Ack a breached ticket (stops the SLA clock; does NOT message customer)
curl -s -X PATCH "$BASE/api/admin/support/tickets" \
  -H "Authorization: Bearer $ADMIN_KEY" -H "Content-Type: application/json" \
  -d '{"ticketId":"<UUID>","status":"acknowledged","reason":"Investigating"}'

# 4. Post a support-agent reply (TRIGGERS EMAIL — only after owner approval!)
curl -s -X POST "$BASE/api/admin/support/tickets/<TICKET_UUID>/messages" \
  -H "Authorization: Bearer $ADMIN_KEY" -H "Content-Type: application/json" \
  -d '{"message":"<approved reply text>"}'

# 5. Resolve
curl -s -X PATCH "$BASE/api/admin/support/tickets" \
  -H "Authorization: Bearer $ADMIN_KEY" -H "Content-Type: application/json" \
  -d '{"ticketId":"<UUID>","status":"resolved","reason":"Fixed in <SHA>"}'
```

## Multi-Channel Intake

A custom ticketing system rarely covers every channel. Document each in `02-channels.md`:

| Channel | Where | Has email? | SLA tracked? |
|---|---|---|---|
| Tickets | `/api/admin/support/tickets` | yes | yes |
| Legacy support requests | `/api/admin/support` | sometimes — verify | no |
| Skill / product feedback | `/api/admin/feedback` | no | no |
| Social media (X, Discord, Slack) | manual | no | no |
| `support@` mailbox bounces | DNS / Cloudflare Email Routing | n/a | n/a |

Always pull from every channel before drafting — see [TRIAGE-WORKFLOW.md](TRIAGE-WORKFLOW.md) Phase 1.

## Known Silent Failures (build into 06-recurring-issues.md)

Custom systems are full of "no error message but wrong behavior". The onboarding pass should hunt for and document these specifically:

- Token / credential file write fails silently → user can't log in but no error
- Webhook missing `payer_id` / `customer_id` → DB never updates; user shows wrong subscription state
- Reconciliation cron returns early → provider state and DB diverge
- Telemetry deduplication broken → events silently dropped
- Auto-deploy disabled → fix lands in `main` but never reaches production
- Internal admin notes ≠ customer notification → user never told about resolution

Each project will have its own list. Maintain it as bugs surface.

## Bug-Confirmed → Fix Pattern

When triage confirms a bug, this skill can also fix it (the agent already has full repo context):

1. File a bead: `br create "<bug>" --type bug --priority p1`
2. Reproduce against production with `curl` / actual user flow (not a proxy)
3. Fix in code; run typecheck + tests + UBS
4. Deploy (verify auto-deploy is on, check Vercel deployment timestamp)
5. Re-run the production reproduction; confirm fixed
6. Reply to ticket with: "Confirmed and fixed in `<SHA>`. Released. Please retry and let us know if it persists."
7. Resolve ticket
8. Close bead

If the fix is non-trivial, **stop and surface to owner** — don't ship a fix mid-triage without an extra eye on it.
