# Migration From Third-Party Providers

## Table of Contents

- [General Strategy](#general-strategy)
- [Common Schema Mapping](#common-schema-mapping)
- [Provider 1: Zendesk](#provider-1-zendesk)
- [Provider 2: Intercom](#provider-2-intercom)
- [Provider 3: Help Scout](#provider-3-help-scout)
- [Provider 4: Freshdesk](#provider-4-freshdesk)
- [Provider 5: Plain](#provider-5-plain)
- [Provider 6: Linear (As Support)](#provider-6-linear-as-support)
- [Provider 7: Jira Service Management (JSM)](#provider-7-jira-service-management-jsm)
- [Provider 8: HubSpot Service Hub](#provider-8-hubspot-service-hub)
- [Provider 9: Salesforce Service Cloud](#provider-9-salesforce-service-cloud)
- [Provider 10: Front](#provider-10-front)
- [Provider 11: Gorgias (Shopify Ecommerce)](#provider-11-gorgias-shopify-ecommerce)
- [Provider 12: Zoho Desk](#provider-12-zoho-desk)
- [Dual-Write During Migration](#dual-write-during-migration)
- [Customer Communication](#customer-communication)
- [Anti-Patterns](#anti-patterns)
- [Validation Checklist](#validation-checklist)
- [Companion Refs](#companion-refs)

<!-- TOC: General Strategy | Common Schema Mapping | Providers | Dual-Write | Customer Communication | Anti-Patterns | Validation Checklist | Companion Refs -->

When migrating off any major support platform back to in-app DB ticketing, the data shape and the cutover pattern matter. This file covers 12 providers across SaaS, ecommerce, and enterprise verticals.

Two columns of verification status:

- **Direct verify**: I (the skill author) directly fetched the live URL while writing this doc and the listed claims appeared verbatim in what came back.
- **Subagent verify**: a research subagent I ran reported these claims with citations, but the live doc rendering (often JS-driven schema viewers) didn't match the URL on follow-up direct fetch. Treat as "claims by trusted hearsay" — high confidence from cross-referencing community sources, but the subagent's specific quotes haven't been reproduced.

Run a 5-ticket dry run on staging for **every** provider before committing to a full migration, regardless of column.

| # | Provider | Direct verify | Subagent verify | Notes |
|---|---|---|---|---|
| 1 | Zendesk | partial | ✅ | Ticket/Comment/User base shapes; `solved_at` is on `metric_set` sideload only |
| 2 | Intercom | ✅ | ✅ | Field is `title`, not `subject` — quoted verbatim from `/api.intercom.io/Conversations/conversation/` |
| 3 | Help Scout | ✅ | partial | `createdBy.id/email/type` (NOT `primaryCustomer.id`); status enum `active\|all\|closed\|open\|pending\|spam` |
| 4 | Freshdesk | ✗ | ✅ | Field shapes from subagent only |
| 5 | Plain | partial | ✅ | Endpoint host `core-api.uk.plain.com/graphql/v1` directly confirmed; `events` → `timelineEntries` rename is subagent-only |
| 6 | Linear | ✅ | ✅ | `Authorization: <KEY>` (no `Bearer`) for personal API keys — quoted verbatim from `linear.app/developers/graphql` |
| 7 | Jira Service Management | ✗ | ✅ | Subagent only; community references for JSDCLOUD-7997 are real |
| 8 | HubSpot Service Hub | ✗ | ✅ | Subagent only |
| 9 | Salesforce Service Cloud | ✗ | ✅ | v66.0 / Spring '26 claim from subagent — direct fetch of the version-index page didn't return the version table |
| 10 | Front | ✗ | ✅ | Subagent only; epoch-seconds gotcha widely reported in community |
| 11 | Gorgias | ✗ | partial | Subagent confirmed pagination & auth; could NOT reach the JS-rendered field schema. Treat field names as candidates to verify |
| 12 | Zoho Desk | ✅ | ✅ | `limit=50`, `orgId` required (directly confirmed); regional host list (`.jp`/`.ca`/`.sa`/`.uk`) is subagent-only |



## General Strategy

```
1. Run dual-write (or read-from-old, write-new) for ≥ 7 days
2. Backfill historical tickets in batches
3. Update the in-app widget to point at new system
4. Update outbound email reply-to / from
5. Cut over inbound: customer replies route to new system
6. Sunset the old provider (cancel subscription)
```

Don't rip-and-replace. Customers in the middle of a multi-message thread cannot have their conversation drop.

## Common Schema Mapping

Whatever the source, the target shape is:

```
supportTickets:
  - id (new UUID)
  - external_id (string, unique, indexed)  -- the source provider's ticket ID
  - source (enum: zendesk|intercom|helpscout|freshdesk|plain|migrated|native)
  - subject, description, status, priority, ...

supportMessages:
  - ticket_id
  - external_id (the source's message/comment ID)
  - sender_type, sender_id, message, ...
```

The `external_id` + `source` pair is your idempotency key during migration.

## Provider 1: Zendesk

### Export

Zendesk Pro/Enterprise has API access. Use:

```bash
# Tickets (paginated, max 1000/page in cursor pagination). Sideload `metric_sets`
# to populate `solved_at` on each ticket — the field doesn't appear on the base
# Ticket payload (see "solved_at accuracy" below).
curl -u "$EMAIL/token:$ZENDESK_API_TOKEN" \
  "https://$SUBDOMAIN.zendesk.com/api/v2/incremental/tickets/cursor.json?start_time=0&include=metric_sets" \
  > zendesk-tickets-page-1.json

# Comments per ticket
curl -u "$EMAIL/token:$ZENDESK_API_TOKEN" \
  "https://$SUBDOMAIN.zendesk.com/api/v2/tickets/$TICKET_ID/comments.json"

# Users
curl -u "$EMAIL/token:$ZENDESK_API_TOKEN" \
  "https://$SUBDOMAIN.zendesk.com/api/v2/users.json"
```

For larger exports: Zendesk Sunshine SDK, or contact Zendesk support for bulk export.

### Field Mapping

| Zendesk | In-app |
|---|---|
| `id` | `external_id` |
| `subject` | `subject` |
| `description` | first message body |
| `status` (`new\|open\|pending\|hold\|solved\|closed`) | `status` (see map below) |
| `custom_status_id` (when custom statuses are on) | preserve in raw JSON; map after status |
| `priority` (`low\|normal\|high\|urgent`) | `priority` (`p3\|p2\|p1\|p0`) |
| `requester_id` | `userId` (resolve via side-loaded users → email → our user) |
| `assignee_id` | `assignee` (resolve via side-loaded users → email) |
| `tags` | `tags text[]` |
| `created_at` | `createdAt` |
| `updated_at` | `updatedAt` |
| `solved_at` | `resolvedAt` (see note below) |

Status map (legacy field):
- `new`, `open` → `open`
- `pending` → `awaiting_customer`
- `hold` → `in_progress`
- `solved` → `resolved`
- `closed` → `closed`

**Custom statuses (new accounts)**: Zendesk turned on custom ticket statuses by default; `custom_status_id` rides alongside the legacy `status` field. Preserve `custom_status_id` in a `raw_payload` JSON column so you can do a project-specific mapping later — dropping it loses information you can't recover.

**`solved_at` accuracy**: the field is **not** part of the base Ticket payload at `GET /api/v2/tickets/{id}`. It comes from the **Ticket Metrics** sideload (`?include=metric_sets`) or appears on Search API hits. For historically accurate state-change timestamps, the audits endpoint (`GET /api/v2/tickets/{id}/audits.json`) is the canonical source — each audit event records the status transition with its real timestamp. Migration recipe: use `metric_set.solved_at` (via sideload) for the first pass; reconcile from audits if SLA reporting on historical tickets matters.

### Comments Mapping

```
Zendesk comment:
  author_id → users.id (lookup by side-loaded email)
  body → message
  public (true|false) → if false, skip (internal note; out of scope)
  via.channel (email|web|api|...) → store as `source_channel` for analytics
  created_at → createdAt
```

**Determining staff vs customer.** Zendesk has no `is_staff` flag on the comment. Two options, in order of robustness:

1. **Read `users[].role` from the side-load** (recommended): `end-user` = customer; `agent` / `admin` = staff. Survives "agent files ticket on behalf of customer," CC'd users, and light agents.
2. **Fall back to `c.author_id === zd.requester_id`** if the user isn't in the side-loaded users array. Less accurate but never panics on missing data.

### Migration Script

```ts
// scripts/migrate-zendesk.ts
import { db } from "@/lib/db";
import * as schema from "@/lib/db/schema";

const ZENDESK_TO_STATUS: Record<string, string> = {
  new: "open", open: "open", pending: "awaiting_customer",
  hold: "in_progress", solved: "resolved", closed: "closed",
};
const ZENDESK_TO_PRIORITY: Record<string, string> = {
  low: "p3", normal: "p2", high: "p1", urgent: "p0",
};

// `sideloadedUsers` comes from the `?include=users` side-load on the
// comments call: a top-level `users` array of `{ id, email, name, role }`
// objects. Pass it here so we can (1) resolve `c.author_id` → email → our
// user UUID and (2) read `role` to classify staff vs customer.
async function migrateTicket(
  zd: ZendeskTicket,
  comments: ZendeskComment[],
  sideloadedUsers: { id: number; email: string; role: string }[] = []
) {
  // Idempotent: skip if already migrated
  const existing = await db.query.supportTickets.findFirst({
    where: (t, { eq, and }) => and(
      eq(t.externalId, String(zd.id)),
      eq(t.source, "zendesk"),
    ),
  });
  if (existing) return existing.id;

  // Zendesk's `requester_id` / `assignee_id` / `author_id` are Zendesk-internal
  // user IDs that don't match our user UUIDs. Use `?include=users` on the
  // tickets and comments calls: that adds a top-level `users` array we can
  // index by id, then look up our user by the side-loaded email. None of
  // `zd.requester_email`, `zd.assignee_email`, or `c.author_email` are real
  // fields — only `users[].email` is.
  const usersById = new Map<number, { id: number; email: string }>(
    (sideloadedUsers ?? []).map(u => [u.id, u])
  );

  const requesterEmail = usersById.get(zd.requester_id)?.email;
  if (!requesterEmail) {
    console.warn(`Skipping ticket ${zd.id}: requester id ${zd.requester_id} not in side-loaded users`);
    return null;
  }
  const requester = await db.query.users.findFirst({
    where: (u, { eq }) => eq(u.email, requesterEmail),
  });
  if (!requester) {
    console.warn(`Skipping ticket ${zd.id}: requester ${requesterEmail} not in our DB`);
    return null;
  }

  const assigneeEmail = zd.assignee_id
    ? usersById.get(zd.assignee_id)?.email ?? null
    : null;

  const ticket = await db.insert(schema.supportTickets).values({
    externalId: String(zd.id),
    source: "zendesk",
    userId: requester.id,
    subject: zd.subject,
    description: zd.description,
    status: ZENDESK_TO_STATUS[zd.status] ?? "open",
    priority: ZENDESK_TO_PRIORITY[zd.priority] ?? "p2",
    tags: zd.tags ?? [],
    assignee: assigneeEmail,
    // Preserve fields we can't map cleanly into a `raw_payload` JSONB column:
    // - `custom_status_id` if custom statuses are enabled on this Zendesk
    //   account (default for new accounts since 2023). Lets a later pass map
    //   custom statuses to project-specific values.
    // - The full ticket payload is also useful for forensic purposes during
    //   the dual-write window.
    rawPayload: { custom_status_id: zd.custom_status_id ?? null, source: zd },
    createdAt: new Date(zd.created_at),
    updatedAt: new Date(zd.updated_at),
    // `solved_at` is NOT on the base Ticket object — it lives on the
    // sideloaded `metric_set`. Pass `?include=metric_sets` on the list call
    // to populate `zd.metric_set` (singular). For untouched/never-solved
    // tickets the field is null.
    resolvedAt: zd.metric_set?.solved_at ? new Date(zd.metric_set.solved_at) : null,
  }).returning();

  // Zendesk comments don't expose an `is_staff` flag. Use the side-loaded
  // user's `role` (`end-user` = customer; `agent` / `admin` = staff). This
  // survives "agent files ticket on behalf of customer" and CC'd users that
  // a `c.author_id !== zd.requester_id` check would misclassify. If the
  // user isn't in the side-load (rare), fall back to the requester check.
  // Skip `public === false` rows up-front since those are internal notes,
  // out of scope for this migration.
  for (const c of comments.filter(c => c.public)) {
    const zendeskUser = usersById.get(c.author_id);
    const isStaff = zendeskUser
      ? zendeskUser.role !== "end-user"
      : c.author_id !== zd.requester_id;
    const sender = !isStaff && zendeskUser
      ? await db.query.users.findFirst({
          where: (u, { eq }) => eq(u.email, zendeskUser.email),
        })
      : null;

    await db.insert(schema.supportMessages).values({
      ticketId: ticket[0].id,
      externalId: String(c.id),
      // Customer messages link to a real user when we can match the email.
      // Staff messages keep senderId null and rely on senderType to label
      // them — staff identity in Zendesk doesn't correspond to a user row.
      senderId: isStaff ? null : sender?.id ?? null,
      senderType: isStaff ? "support" : "customer",
      // `via.channel` (email | web | api | chat | mobile_sdk | ...) tells us
      // how the message originated. Useful for analytics — track e.g. "what
      // % of bug reports come from in-app vs email".
      sourceChannel: c.via?.channel ?? null,
      message: c.body,
      createdAt: new Date(c.created_at),
    });
  }
  return ticket[0].id;
}
```

Run in batches of 100 with progress logging. Estimated runtime: 1000 tickets in ~5 minutes.

### Cutover

1. Update Zendesk forwarding rule to forward incoming emails to the new in-app system's inbound mailbox.
2. Update outbound `from` address in your in-app email module.
3. Add a banner on the Zendesk customer portal: "We've moved support to <new-url>. Visit there to see your tickets."
4. Wait 30 days. Cancel Zendesk subscription.

## Provider 2: Intercom

### Export

```bash
# Conversations
curl -H "Authorization: Bearer $INTERCOM_TOKEN" \
  "https://api.intercom.io/conversations" > intercom-conversations.json

# Per-conversation parts (messages)
curl -H "Authorization: Bearer $INTERCOM_TOKEN" \
  "https://api.intercom.io/conversations/$CONVERSATION_ID"

# Contacts (users)
curl -H "Authorization: Bearer $INTERCOM_TOKEN" \
  "https://api.intercom.io/contacts"
```

### Field Mapping

Intercom `conversation` ≈ ticket:

| Intercom | In-app |
|---|---|
| `id` | `external_id` |
| `title` (often empty for Messenger — NOTE: `title`, NOT `subject`) | `subject` (synth from first part body if blank) |
| `state` (`open\|closed\|snoozed`) | `status` |
| `priority` (`priority\|not_priority`) | `priority` (P1 if priority, P2 default) |
| `contacts.contacts[0].id` | `userId` (via email) |
| `team_assignee_id` / `admin_assignee_id` | `assignee` |
| `tags.tags[].name` | `tags` |
| `created_at` (epoch seconds) | `createdAt` (multiply by 1000 for JS Date) |
| `updated_at` (epoch seconds) | `updatedAt` |

State map:
- `open` → `open`
- `snoozed` → `awaiting_customer`
- `closed` → `closed`

Conversation parts mapping:

```
part_type:
  comment → support or customer (depending on author.type)
  note → internal (skip — not customer-facing)
  assignment / open / close → state event (skip; reconstruct from final state)
```

### Migration Script Sketch

Same shape as Zendesk's, with Intercom-specific field accessors.

### Cutover

Intercom Messenger can stay live (great for in-app chat) — only migrate ticket conversations. If sunsetting Intercom entirely:
- Remove the Intercom widget from the app
- Replace with your `SupportWidget` from this skill

## Provider 3: Help Scout

### Export

Help Scout has a Mailbox API:

```bash
curl -H "Authorization: Bearer $HELPSCOUT_TOKEN" \
  "https://api.helpscout.net/v2/conversations?status=all"

curl -H "Authorization: Bearer $HELPSCOUT_TOKEN" \
  "https://api.helpscout.net/v2/conversations/$ID/threads"
```

### Field Mapping

| Help Scout | In-app |
|---|---|
| `id` | `external_id` |
| `subject` | `subject` |
| `status` (full enum: `active\|all\|closed\|open\|pending\|spam` — `active` is the default filter; `open` and `active` are not synonyms — `active` means "not archived") | `status` |
| `createdBy.id` (with `createdBy.email` and `createdBy.type` — verified against the [list-conversations docs](https://developer.helpscout.com/mailbox-api/endpoints/conversations/list/)) | `userId` (via `createdBy.email` lookup) |
| `assignee.id` / `assignee.email` | `assignee` |
| `tags[].tag` | `tags` |
| `createdAt` | `createdAt` |
| `closedAt` | `resolvedAt` |

Threads (messages) at `GET /v2/conversations/{id}/threads`:
- `type` (full enum per [Help Scout docs](https://developer.helpscout.com/mailbox-api/endpoints/conversations/threads/list/): `email\|chat\|phone\|note\|customer\|reply` — six values, not four)
  - `email`, `chat`, `phone`, `customer` → customer-originated (use `senderType: customer`)
  - `reply` → staff-authored reply (use `senderType: support`)
  - `note` → internal staff note (skip; not customer-facing)
- `body` → message (HTML — strip to text or render server-side)
- `createdBy.email` → sender lookup
- `createdAt` → message timestamp

### Cutover

Help Scout email forwarding can be flipped at the mailbox level; nice clean cutover.

## Provider 4: Freshdesk

```bash
curl -u "$FRESHDESK_API_KEY:X" \
  "https://$SUBDOMAIN.freshdesk.com/api/v2/tickets"
curl -u "$FRESHDESK_API_KEY:X" \
  "https://$SUBDOMAIN.freshdesk.com/api/v2/tickets/$ID/conversations"
```

Field mapping similar to Zendesk; status integers map: `2`=open, `3`=pending, `4`=resolved, `5`=closed.

## Provider 5: Plain

Plain has a GraphQL API. Endpoint: `https://core-api.uk.plain.com/graphql/v1` — the per-tenant subdomain matters; check the project's `apiKeys` page in the Plain admin for the exact host (per [Plain's API reference](https://www.plain.com/docs/api-reference)). Auth header: `Authorization: Bearer <API_KEY>`.

```graphql
query Threads {
  threads(first: 50) {
    edges {
      node {
        id title status priority
        customer { id email fullName }
        assignedTo { ... on User { id email } }
        labels { labelType { name } }
        createdAt updatedAt
      }
    }
  }
}
```

**Status values are tenant-configurable**, NOT a fixed enum. Plain ships with built-in statuses (`TODO`, `IN_PROGRESS`, `DONE`, etc.) but the customer's tenant may use custom ones. Run an introspection query (`__type(name: "ThreadStatus")`) against the live tenant before assuming values, or pull each project's status set from `tenantSettings`.

**Messages live in `timelineEntries`** (NOT "events" — Plain renamed this). Each `TimelineEntry` is one of several entry-type unions (e.g., `EmailMessage`, `Note`, `ChatMessage`, `CustomEvent`). Walk the union and dispatch by `__typename` to extract `message` content per type.

## Provider 6: Linear (As Support)

Linear is sometimes used as a support backstop for OSS projects. Issues with `support` label:

```bash
# Linear's GraphQL endpoint. NOTE the auth header form:
#   - Personal API keys: `Authorization: $LINEAR_API_KEY` (NO `Bearer` prefix)
#   - OAuth2 access tokens: `Authorization: Bearer $TOKEN`
# Mixing them up is the #1 cause of 401s. See https://linear.app/developers/graphql.
curl -X POST https://api.linear.app/graphql \
  -H "Authorization: $LINEAR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"query":"query { issues(filter: {labels: {name: {eq: \"support\"}}}) { nodes { identifier title description state { name } priority assignee { email } } } }"}'
```

Or if their `linear-cli` is installed:

```bash
linear issue list --label=support --json
```

### Field Mapping

| Linear | In-app |
|---|---|
| `identifier` (e.g., "ENG-123") | `external_id` |
| `title` | `subject` |
| `description` | `description` |
| `state.name` (`Triage`/`Backlog`/`In Progress`/`Done`/`Cancelled`) | `status` |
| `priority` (0-4) | `priority` |
| `assignee.email` | `assignee` |
| `labels` | `tags` |
| `comments` | `supportMessages` |

## Provider 7: Jira Service Management (JSM)

JSM is the dominant ITSM/dev-tool support stack for enterprise. It's Jira issues with extra metadata.

### Export

```bash
# List service desks (one project per desk)
curl -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
  "https://$DOMAIN.atlassian.net/rest/servicedeskapi/servicedesk"

# Customer requests (≈ tickets) for a desk
curl -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
  "https://$DOMAIN.atlassian.net/rest/servicedeskapi/request?serviceDeskId=$ID&start=0&limit=50"

# Comments — note the `expand` parameter is essential for body content
curl -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
  "https://$DOMAIN.atlassian.net/rest/servicedeskapi/request/$ISSUE_KEY/comment?expand=renderedBody"
```

### Field Mapping

| JSM | In-app |
|---|---|
| `issueKey` (e.g., `HELP-123`) | `external_id` |
| `summary` (top-level on the request object) | `subject` |
| `requestFieldValues[]` entry where `fieldId == 'description'` → `value` | `description` |
| `currentStatus.status` (free-form per workflow) | `status` (custom map per project) |
| `requestFieldValues[]` entry where `fieldId == 'priority'` → `value.name` (`Highest\|High\|Medium\|Low\|Lowest`) | `priority` (`p0..p4`) |
| `reporter.accountId` → `reporter.emailAddress` | `userId` (lookup by email) |
| (assignee — see note below) | `assignee` |
| `requestType.name` | `category` (custom map) |
| `customfield_*` (per-tenant) | preserve in `raw_payload` |
| `comments[].public` boolean | filter; only `public: true` migrates |
| `comments[].author.emailAddress` | sender lookup by email |
| `comments[].body` (ADF JSON or rendered HTML) | `message` (use `renderedBody` if available) |
| `created` (ISO) | `createdAt` |

**Assignee gotcha**: the `/rest/servicedeskapi/request/{key}` response does NOT include an `assignee` field — its documented schema is `issueId`, `issueKey`, `summary`, `requestTypeId`, `serviceDeskId`, `createdDate`, `reporter`, `requestFieldValues`, `currentStatus`, `_links`, `_expands`. To get the assignee, call the underlying Jira issue API for each request:

```bash
curl -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
  "https://$DOMAIN.atlassian.net/rest/api/3/issue/$ISSUE_KEY?fields=assignee"
# → { fields: { assignee: { emailAddress, accountId, displayName } } }
```

This doubles your API calls (one per ticket), so for large migrations you may want to query Jira's `/rest/api/3/search?jql=project=HELP` in 100-issue pages to gather assignee data in batches.

### Comments Mapping And The `public` / `jsdPublic` Trap

JSM exposes the public-vs-internal flag under TWO different field names depending on which endpoint you hit:

| Endpoint | Field | Reliability |
|---|---|---|
| `GET /rest/servicedeskapi/request/{key}/comment` | `public` (boolean) | **Authoritative** — read this for migrations. |
| `GET /rest/api/3/issue/{key}/comment` (underlying Jira) | `jsdPublic` (boolean) | **Unreliable on write** — comments authored by users without an active JSD agent license get coerced to internal regardless. See [JSDCLOUD-7997](https://jira.atlassian.com/browse/JSDCLOUD-7997). |

For migration **always read** through the servicedeskapi endpoint and trust `c.public`. Skip `c.public === false` rows (internal staff notes).

```ts
const resp = await fetchComments(issueKey); // /rest/servicedeskapi/request/{key}/comment?expand=renderedBody
for (const c of resp.values.filter(c => c.public)) {
  // Atlassian's `accountType` values are `atlassian` (agent/admin),
  // `customer` (end-user), and `app` (Connect app / bot). Treat anything
  // that ISN'T `customer` as staff so app-generated replies (e.g., from
  // an automation rule) don't get logged as customer messages.
  await db.insert(supportMessages).values({
    externalId: c.id,
    senderType: c.author.accountType === "customer" ? "customer" : "support",
    message: c.renderedBody ?? adfToText(c.body),
    createdAt: new Date(c.created),
  });
}
```

### Atlassian Document Format (ADF) Gotcha

`comment.body` is an **ADF JSON document** by default — a node tree, not plain text. Either:
1. Use `?expand=renderedBody` to get HTML, then strip to text. Easier.
2. Walk the ADF tree (use Atlassian's `@atlaskit/adf-utils` or write a small recursive helper that concatenates `text` nodes).

Don't `String(c.body)` — you'll persist `[object Object]`.

### Status Mapping

JSM workflows are per-project and free-form. There is no canonical `open/in_progress/closed` enum. The migration script must accept a project-specific map:

```ts
const JSM_STATUS_MAP: Record<string, string> = {
  // Customer's actual workflow names → in-app status
  "Open": "open",
  "Waiting for support": "open",
  "In Progress": "in_progress",
  "Waiting for customer": "awaiting_customer",
  "Resolved": "resolved",
  "Closed": "closed",
  "Cancelled": "closed",
  // ... extend per tenant
};
```

Get this map by: `GET /rest/api/3/project/{projectKey}/statuses` and asking the project owner what each status means.

### Cutover

- Email forwarding: each JSM service desk has an inbound email (`<servicedesk>@<tenant>.atlassian.net`). Re-route to your in-app inbound mailbox.
- Customer portal: Atlassian's customer portal stays live during migration; add a banner via JSM's portal customization.
- API tokens: scoped per-user, not per-app. Plan for token rotation.

## Provider 8: HubSpot Service Hub

Common in SMB and mid-market accounts already running HubSpot CRM. The Tickets object lives in HubSpot's CRM schema; messages live in Conversations as a separate object graph joined by associations.

### Export

```bash
# Tickets (CRM object)
curl -H "Authorization: Bearer $HUBSPOT_TOKEN" \
  "https://api.hubapi.com/crm/v3/objects/tickets?limit=100&properties=subject,content,hs_pipeline,hs_pipeline_stage,hs_ticket_priority,hubspot_owner_id,createdate,closed_date"

# Associations: ticket → contacts (the customer)
curl -H "Authorization: Bearer $HUBSPOT_TOKEN" \
  "https://api.hubapi.com/crm/v3/objects/tickets/$TICKET_ID/associations/contacts"

# Conversations threads associated with the ticket
curl -H "Authorization: Bearer $HUBSPOT_TOKEN" \
  "https://api.hubapi.com/conversations/v3/conversations/threads?associatedObjectType=TICKET&associatedObjectId=$TICKET_ID"

# Messages in a thread
curl -H "Authorization: Bearer $HUBSPOT_TOKEN" \
  "https://api.hubapi.com/conversations/v3/conversations/threads/$THREAD_ID/messages"
```

### Field Mapping

| HubSpot | In-app |
|---|---|
| `id` | `external_id` |
| `properties.subject` | `subject` |
| `properties.content` | `description` |
| `properties.hs_pipeline_stage` (custom per pipeline) | `status` (project-specific map) |
| `properties.hs_ticket_priority` (`LOW\|MEDIUM\|HIGH\|URGENT`) | `priority` (`p3..p0`) |
| (associated contact) `email` | `userId` (lookup by email) |
| `properties.hubspot_owner_id` → owner email | `assignee` |
| `properties.createdate` | `createdAt` |
| `properties.closed_date` | `resolvedAt` |

### Two Different APIs, Two Different Casing Conventions

HubSpot's CRM Tickets API uses **snake_case** field names (`createdate`, `closed_date`, `hs_pipeline_stage`). The Conversations API uses **camelCase** (`createdAt`, `closedAt`, `assignedTo`, `latestMessageTimestamp`). Both are correct on their respective endpoints — don't try to unify them in your fetcher.

Threads (`/conversations/v3/conversations/threads`) carry: `id`, `createdAt`, `closedAt`, `status`, `originalChannelId`, `originalChannelAccountId`, `latestMessageTimestamp`, `assignedTo`, `inboxId`, `associatedContactId`, `archived`, `spam`, `threadAssociations`.

Messages (`/conversations/v3/conversations/threads/{threadId}/messages`) carry: `id`, `conversationsThreadId`, `createdAt`, `direction` (`INCOMING` / `OUTGOING`), `senders[]`, `recipients[]`, `text`, `richText`, `attachments[]`, `channelId`, `channelAccountId`. Note `text` (plain) and `richText` (HTML), NOT `body` — that's another HubSpot quirk.

To find threads associated with a ticket, use `threadAssociations` on the thread (or filter list responses by the `associatedTicketId` query param if exposed).

### The Tickets ↔ Conversations Split (Critical)

The single biggest migration gotcha: **HubSpot tickets and conversations are separate object graphs**. Tickets carry status / priority / owner; Conversations carry the actual messages. They join via association IDs.

```ts
async function migrateHubspotTicket(ticket: HubspotTicket) {
  // Step 1: insert the ticket shell
  const ourTicket = await insertTicketShell(ticket);

  // Step 2: find associated conversation threads
  const threads = await fetchAssociatedThreads(ticket.id);
  if (threads.length === 0) {
    console.warn(`Ticket ${ticket.id} has no conversation threads — likely a bot-generated ticket`);
    return ourTicket.id;
  }

  // Step 3: pull messages per thread, in order, and insert as messages
  for (const thread of threads) {
    const messages = await fetchThreadMessages(thread.id);
    for (const m of messages) {
      await insertMessage(ourTicket.id, m);
    }
  }
}
```

Ticket without thread = silent data loss. Always assert `threads.length > 0` for tickets where you'd expect a customer message.

### Pipelines

HubSpot tickets live in a **pipeline** with custom stages. Get the active pipelines:

```bash
curl -H "Authorization: Bearer $HUBSPOT_TOKEN" \
  "https://api.hubapi.com/crm/v3/pipelines/tickets"
```

Build a per-pipeline status map. Don't assume "support pipeline" exists — many HubSpot accounts have multiple custom pipelines.

### Cutover

- Forms: replace HubSpot embedded chat / ticket forms with your `SupportWidget`.
- Email: HubSpot routes inbound to a per-account address; reroute to yours.
- Sunset: HubSpot Service Hub is bundled with the CRM, so "cancellation" usually means downgrading the seat tier, not killing the whole account.

## Provider 9: Salesforce Service Cloud

Enterprise leader. Migration is bespoke per-org due to field-level security and per-org custom fields. Use the **Bulk API 2.0**, not REST, for anything > 1000 records.

### Auth (Connected App Required)

OAuth2 with a connected app. **The username-password grant is blocked by default for orgs created Summer '23+** (per Salesforce's [Spring '24 release notes](https://help.salesforce.com/s/articleView?id=release-notes.rn_security_username-password_flow_blocked_by_default.htm)) and is being phased out broadly. Use **Web Server Flow + PKCE** for human-driven migrations, or **Client Credentials Flow** for headless service users.

```bash
# Web Server Flow (interactive — opens a browser to log in once, then you
# exchange the code for a refresh token to use programmatically).
# Step 1: send the user to:
#   https://login.salesforce.com/services/oauth2/authorize?
#     response_type=code&client_id=$CLIENT_ID&redirect_uri=$REDIRECT_URI
#     &code_challenge=$PKCE_CHALLENGE&code_challenge_method=S256
# Step 2: exchange the returned code:
curl -X POST https://login.salesforce.com/services/oauth2/token \
  -d "grant_type=authorization_code&client_id=$CLIENT_ID&client_secret=$CLIENT_SECRET&\
redirect_uri=$REDIRECT_URI&code=$AUTH_CODE&code_verifier=$PKCE_VERIFIER"

# OR — Client Credentials Flow for service-to-service (preferred for migration scripts):
curl -X POST https://login.salesforce.com/services/oauth2/token \
  -d "grant_type=client_credentials&client_id=$CLIENT_ID&client_secret=$CLIENT_SECRET"
# Requires the connected app to have "Client Credentials Flow" enabled and
# bound to a service-account user.
```

### Export (Bulk API 2.0)

```bash
# Use the latest stable API version. Spring '26 is v66.0; check
# https://developer.salesforce.com/docs/atlas.en-us.api_rest.meta/api_rest/dome_versions.htm
# for the current version (Salesforce ships three releases per year).
SF_API_VERSION=v66.0

# Create a query job
curl -H "Authorization: Bearer $SF_TOKEN" \
     -H "Content-Type: application/json" \
     -X POST "$SF_INSTANCE/services/data/$SF_API_VERSION/jobs/query" \
     -d '{"operation":"query","query":"SELECT Id, CaseNumber, Subject, Description, Status, Priority, ContactId, OwnerId, CreatedDate, ClosedDate, IsClosed FROM Case"}'

# Poll the job status, then fetch results when state = JobComplete
curl -H "Authorization: Bearer $SF_TOKEN" \
     "$SF_INSTANCE/services/data/$SF_API_VERSION/jobs/query/$JOB_ID/results"
# Returns CSV. Parse and migrate.
```

For comments and emails, run separate queries against `CaseComment` and `EmailMessage`:

```sql
SELECT Id, ParentId, CommentBody, IsPublished, CreatedById, CreatedDate FROM CaseComment
SELECT Id, ParentId, TextBody, HtmlBody, FromAddress, ToAddress, MessageDate FROM EmailMessage
```

### Field Mapping

| Salesforce | In-app |
|---|---|
| `Case.Id` | `external_id` (UUID-ish) |
| `Case.CaseNumber` (e.g., `00001234`) | secondary external ref |
| `Case.Subject` | `subject` |
| `Case.Description` | `description` |
| `Case.Status` (org-specific picklist) | `status` (custom map) |
| `Case.Priority` (`High\|Medium\|Low`) | `priority` (`p1\|p2\|p3`) |
| `Case.ContactId` → `Contact.Email` | `userId` (lookup by email) |
| `Case.OwnerId` → `User.Email` | `assignee` |
| `Case.CreatedDate` | `createdAt` |
| `Case.ClosedDate` | `resolvedAt` |
| `CaseComment.IsPublished` | filter; only `true` migrates |
| `EmailMessage` (incoming) | `senderType: customer` |
| `EmailMessage` (outgoing) | `senderType: support` |

### Three Things That Bite Every Salesforce Migration

1. **Custom fields per org**: every Salesforce org has unique `CustomField__c` columns. Get the schema via `GET /services/data/v59.0/sobjects/Case/describe` and preserve unmapped fields in `raw_payload`.

2. **Field-level security**: even with API access, certain fields may be hidden. The describe call tells you which fields the API user can read.

3. **Mixed comment surfaces**: Salesforce historically split case communications across `CaseComment` (internal/portal) and `EmailMessage` (email channel). Modern orgs may also have `FeedItem` (Chatter). You may need all three to reconstruct the full thread.

### Cutover

- Email-to-Case: Salesforce uses dedicated routing addresses. Update DNS to point support@ at your in-app inbound.
- Self-service: If they used the Salesforce Customer Portal / Experience Cloud, add a banner pointing to your new portal.
- Don't cancel before the org's fiscal Q renewal — Salesforce contracts are notoriously hard to exit mid-cycle.

## Provider 10: Front

Front is email-first; everything is a `Conversation`, not a "ticket." A migration fabricates one ticket per conversation.

### Export

```bash
# List conversations (paginated)
curl -H "Authorization: Bearer $FRONT_TOKEN" \
  "https://api2.frontapp.com/conversations?limit=100"

# Messages on a conversation
curl -H "Authorization: Bearer $FRONT_TOKEN" \
  "https://api2.frontapp.com/conversations/$CONV_ID/messages"
```

### Field Mapping

| Front | In-app |
|---|---|
| `conversation.id` | `external_id` |
| `conversation.subject` (often empty for chat threads) | `subject` (synth from first message body if blank) |
| `conversation.status` (`assigned\|unassigned\|archived\|trashed\|spam`) | `status` (see map below) |
| `conversation.assignee.email` | `assignee` |
| `conversation.recipient.handle` (email or phone) | `userId` (lookup by email; skip non-email channels for v1) |
| `conversation.tags[].name` | `tags` |
| `conversation.created_at` (epoch seconds) | `createdAt` (multiply by 1000 for JS Date) |
| `messages[].body` | `message` (HTML — strip to text or render) |
| `messages[].is_inbound` | `senderType` (`true` = customer, `false` = support) |
| `messages[].author.email` | sender email |

Status map (per [Front API conversation reference](https://dev.frontapp.com/reference/list-conversations)):
- `assigned` / `unassigned` → `open` (the conversation is live; just differs in whether someone is on it)
- `archived` → `closed`
- `trashed` → `closed` (and tag with `front:trashed` so you can filter later if needed)
- `spam` → `closed` (and tag with `spam`)

There is no literal `open` status in Front; the "open" notion is implied by `assigned` + `unassigned`.

### Front-Specific Gotchas

- **Subject can be empty**: chat-style conversations from Twitter/SMS/Intercom-imports often have `subject: ""`. Fall back to `messages[0].body.slice(0, 80)` for a synthetic subject.
- **Multi-channel**: Front bundles email + SMS + Twitter + Intercom + custom channels. The migration plan needs to decide whether non-email channels become tickets or get archived.
- **Epoch timestamps**: Front uses **seconds**, not milliseconds. `new Date(conv.created_at * 1000)`.
- **`is_inbound` semantics**: a teammate replying to a teammate (internal note) shows up as `is_inbound: false` AND has the team's domain. Front's "comments" (truly internal, not sent to customer) are a separate object — fetch via `GET /conversations/{id}/comments` if needed; usually safe to skip for migration.

### Cutover

- Email forwarding: Front exposes a per-inbox address; redirect via Front's UI to your in-app inbound.
- Channels: Twitter/SMS/Intercom integrations need to be rebuilt or dropped per project.
- Front has no "customer portal" to wind down — pure email/chat; cutover is mostly DNS work.

## Provider 11: Gorgias (Shopify Ecommerce)

If the project sells on Shopify, the support stack is overwhelmingly Gorgias rather than Zendesk (per [storeleads.app](https://storeleads.app/reports/shopify/app/helpdesk): 21,027 active Shopify installs, +22.5% YoY). Gorgias is a "ticket" platform but everything is shaped around order data.

### Auth

Basic auth with email + API key. The API key is per-user (not per-account). Get it from Settings → REST API.

### Export

```bash
# List tickets, paginated. Per-page limit is 30 (low!).
curl -u "$EMAIL:$GORGIAS_API_KEY" \
  "https://$SUBDOMAIN.gorgias.com/api/tickets?limit=30&order_by=created_datetime:asc"

# Messages on a ticket
curl -u "$EMAIL:$GORGIAS_API_KEY" \
  "https://$SUBDOMAIN.gorgias.com/api/tickets/$TICKET_ID/messages"

# Customers (for email lookup)
curl -u "$EMAIL:$GORGIAS_API_KEY" \
  "https://$SUBDOMAIN.gorgias.com/api/customers?limit=100"
```

### Field Mapping

| Gorgias | In-app |
|---|---|
| `id` | `external_id` |
| `subject` | `subject` |
| `status` (`open\|closed`) | `status` (only two states; map `open` → `open`, `closed` → `closed`) |
| `priority` (`low\|normal\|high\|urgent`) | `priority` (`p3..p0`) |
| `customer.email` | `userId` (lookup by email) |
| `assignee_user.email` | `assignee` |
| `tags[].name` | `tags` |
| `created_datetime` (ISO) | `createdAt` |
| `closed_datetime` (ISO) | `resolvedAt` |
| `messages[].sender.email` | sender lookup |
| `messages[].body_text` / `messages[].body_html` | `message` |
| `messages[].from_agent` (boolean) | `senderType` (`true` = support, `false` = customer) |
| `messages[].channel` (`email\|chat\|sms\|api\|...`) | `sourceChannel` |

### Gorgias-Specific Gotchas

- **Order linkage is critical**. Each ticket has a `meta.order_ids[]` (or surfaced via the customer's order history). For ecommerce migrations, preserve this in `raw_payload` — every customer reply will reference orders, and your in-app system needs to join them.
- **Macros (canned responses)** are first-class objects in Gorgias. If the project uses many, export them via `/api/macros` and convert to your KB articles.
- **Per-page limit of 30** means migrations of large accounts take a long time. Plan ~3 hours per 100k tickets.
- **Status enum is binary** — Gorgias only has `open` and `closed`, no equivalent of "awaiting customer". Customer reply on a closed ticket reopens it (Gorgias default behavior; check the project's settings before assuming).
- **Voice / SMS / chat tickets**: bundled the same as email. The `channel` field on each message tells you the original surface.

### Cutover

- Replace the Gorgias chat widget on the Shopify storefront with your `SupportWidget`.
- Email forwarding: each Gorgias inbox has a `*.gorgias.com` forwarding address. Update DNS to redirect to your in-app inbound.
- Order webhooks: if you used Gorgias' Shopify-order integration, you'll need to wire your in-app system directly to Shopify webhooks.

## Provider 12: Zoho Desk

Zoho Desk has 50,270+ verified company customers per [6sense](https://6sense.com/tech/helpdesk-tools/zoho-desk-market-share), with strong adoption in price-sensitive SMB and international markets (India, MENA). The catch: most Zoho Desk accounts are deeply integrated with the broader Zoho One suite (CRM, Books, Projects), so migrating off requires sorting which data lives where.

### Auth

OAuth2. Generate a self-client refresh token from Zoho's API console; trade it for an access token. The Desk API also **requires an `orgId` header** on every request (find it in Zoho Desk → Setup → Organization Profile → Data Center URL).

```bash
# Trade refresh token → access token (access tokens expire in 1 hour)
curl -X POST "https://accounts.zoho.com/oauth/v2/token" \
  -d "refresh_token=$ZOHO_REFRESH_TOKEN&client_id=$CLIENT_ID&client_secret=$CLIENT_SECRET&grant_type=refresh_token"
```

**Region routing**: Zoho has multiple regional data centers. The auth host AND API host must match the account's region:
- `.com` (US), `.eu` (EU), `.in` (India), `.com.au` (Australia)
- `.jp` (Japan), `.ca` (Canada), `.sa` (Saudi Arabia), `.uk` (UK)

E.g., a UK account uses `accounts.zoho.uk` for OAuth and `desk.zoho.uk` for the API. Wrong region → 404 with no useful error message. The right answer is "use the regional host that matches your account's data center"; check the customer's Zoho admin URL.

### Export

```bash
# Tickets — `limit` is capped at 50 per page (NOT 100). `from` is the offset.
# `orgId` is REQUIRED.
# `contact.email` and `assignee.email` only appear when `include=contacts,assignee`
# is passed; without it, those nested objects are omitted.
curl -H "Authorization: Zoho-oauthtoken $ACCESS_TOKEN" \
     -H "orgId: $ZOHO_ORG_ID" \
  "https://desk.zoho.com/api/v1/tickets?from=0&limit=50&include=contacts,assignee"

# Threads (Zoho's name for messages on a ticket)
curl -H "Authorization: Zoho-oauthtoken $ACCESS_TOKEN" \
     -H "orgId: $ZOHO_ORG_ID" \
  "https://desk.zoho.com/api/v1/tickets/$TICKET_ID/threads"

# Each thread's content (Zoho splits the list and the body across two calls)
curl -H "Authorization: Zoho-oauthtoken $ACCESS_TOKEN" \
     -H "orgId: $ZOHO_ORG_ID" \
  "https://desk.zoho.com/api/v1/tickets/$TICKET_ID/threads/$THREAD_ID"
```

### Field Mapping

| Zoho Desk | In-app |
|---|---|
| `id` | `external_id` |
| `ticketNumber` (e.g., `101`) | secondary external ref |
| `subject` | `subject` |
| `description` | `description` |
| `status` (`Open\|On Hold\|Escalated\|Closed`, project-specific) | `status` (custom map) |
| `priority` (`Low\|Medium\|High\|Urgent`, account-configurable) | `priority` (`p3..p0`) |
| `contact.email` (when included) | `userId` |
| `assignee.email` (when included) | `assignee` |
| `category` | `category` |
| `createdTime` (ISO) | `createdAt` |
| `closedTime` (ISO) | `resolvedAt` |
| `threads[].channel` (`EMAIL\|FORUMS\|TWITTER\|...`) | `sourceChannel` |
| `threads[].content` (HTML) | `message` |
| `threads[].author.type` (`AGENT\|CONTACT\|SYSTEM`) | `senderType` (`AGENT` → support; `CONTACT` → customer; skip `SYSTEM` events) |

### Zoho-Specific Gotchas

- **Two-call thread fetch**: list threads first, then call each thread by ID to get the body. Don't try to inline content on the list endpoint — Zoho rate-limits list responses.
- **Region routing**: `.com` ≠ `.eu` ≠ `.in`. Wrong region = 404 with no useful message.
- **`SYSTEM` thread type** captures status changes ("Agent X assigned this ticket"). These are NOT customer-visible messages — skip them or store them in audit log only.
- **Custom fields** ride alongside standard fields and have stable API names (no `customfield_*` prefix). Pull them via `?include=customFields` if the project uses them.
- **Department scoping**: Zoho Desk supports multi-department setups; tickets are scoped per department. The export must paginate over departments first if the customer uses more than one.

### Cutover

- Email forwarding: per-department address (`support@yourcompany.zohodesk.com`). Update DNS.
- Web forms: replace the Zoho Desk embed with your `SupportWidget`.
- Watch for Zoho One bundle pricing — the customer may be unable to truly cancel just Zoho Desk without changing their broader Zoho subscription. Surface this early in the cutover plan.

## Dual-Write During Migration

For ≥ 7 days, write incoming tickets to BOTH systems:

```ts
async function createTicket(input: TicketInput) {
  // Primary: in-app
  const newTicket = await db.insert(...).values({...input, source: "native"}).returning();

  // Shadow: legacy (best-effort)
  try {
    if (process.env.MIGRATION_DUAL_WRITE === "true") {
      await zendeskCreateTicket({...input});
    }
  } catch (e) {
    console.error("Dual-write to legacy failed:", e);
    // Don't fail the user-facing request
  }

  return newTicket[0];
}
```

When confidence high, flip `MIGRATION_DUAL_WRITE=false`.

## Customer Communication

Email at start, mid, and end of cutover:

```
Subject: Heads up — we're upgrading our support system

Hi,

Quick update: we're migrating support to a new in-app system over the next
two weeks. Your existing tickets and history will move with you.

If you have an active ticket, no action needed — just reply as usual.

The new portal lives at: <url>

Questions? Just reply.

— <team>
```

## Anti-Patterns

| Don't | Why |
|---|---|
| Migrate all data in one big-bang | Drift during the cutover; users in active threads lose context |
| Skip ID-mapping | Customer references "ticket #1234" → support can't find it in new system |
| Lose timestamps | Audit trail breaks; SLA history becomes unrecoverable |
| Migrate internal notes as customer-visible | Privacy disaster |
| Cut over without dual-write period | Inbound emails lost during DNS / inbox routing change |
| Cancel old subscription before all tickets are migrated | Some active tickets will live only in the dead provider |
| Migrate without testing the round-trip on staging | Production-only bugs surface at the worst moment |

## Validation Checklist

After migration:
- [ ] Total ticket count matches source
- [ ] Total message count matches source
- [ ] Sample 20 tickets manually: do the message bodies, timestamps, and statuses match?
- [ ] All `userId` look-ups succeeded (no orphan tickets)
- [ ] Outbound emails go from new domain
- [ ] Inbound emails route to new system
- [ ] Customer-portal old URL redirects to new
- [ ] Old provider canceled (only after 30+ days of no inbound traffic)

## Companion Refs

- [SCHEMA.md](SCHEMA.md) — target schema
- [EMAIL.md](EMAIL.md) — domain / from-address cutover
- [TEST-PLAN.md](TEST-PLAN.md) — tests to add for migration script
- `/user-support-triage-for-saas-and-open-source-projects` — `references/SAAS-THIRD-PARTY.md` for keeping the legacy system tidy during transition
