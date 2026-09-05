# Full Schema (Drizzle / Postgres)

This is the default Drizzle / Postgres shape. Adapt naming, relations, and migration style to your project while preserving the state-machine, audit, SLA, and handoff invariants.

## Enums

```ts
export const supportCategoryEnum = pgEnum("support_category", [
  "auth", "billing", "access", "bug", "content_moderation", "other",
]);
export type SupportCategory = (typeof supportCategoryEnum.enumValues)[number];

export const supportStatusEnum = pgEnum("support_status", [
  "open", "acknowledged", "in_progress", "awaiting_customer", "resolved", "closed",
]);
export type SupportStatus = (typeof supportStatusEnum.enumValues)[number];

export const slaStatusEnum = pgEnum("sla_status", ["ok", "at_risk", "breached"]);
export type SlaStatus = (typeof slaStatusEnum.enumValues)[number];

export const ticketPriorityEnum = pgEnum("ticket_priority", [
  "p0",  // Critical: site down, data loss, security
  "p1",  // High: severe / blocking, no workaround
  "p2",  // Normal: bug or question with workaround
  "p3",  // Low: cosmetic, doc, feature request
]);
export type TicketPriority = (typeof ticketPriorityEnum.enumValues)[number];
```

## supportTickets (SLA-tracked)

See SKILL.md for the abridged schema. Key fields:

- `priority` — drives SLA deadlines
- `status` — drives the SLA pause logic
- `slaDeadline` — computed at create + on status transitions
- `slaStatus` — denormalized snapshot for fast filtering: `ok | at_risk | breached`
- `slaStatusUpdatedAt` — last time the cron updated it
- `slaBreachedAt` — sticky timestamp of first breach (don't clear on later status change)
- `assignee` — text identifier (admin user ID or display name; project's call)
- `resolvedAt` — set when status → `resolved`

Indexes: every filter dimension. Don't skip — admin list endpoint hits all of them.

## supportMessages (Threaded)

```ts
export const supportMessages = pgTable("support_messages", {
  id:          uuid().primaryKey().defaultRandom(),
  ticketId:    uuid().notNull().references(() => supportTickets.id, { onDelete: "cascade" }),
  senderId:    uuid().references(() => users.id),  // null for system messages
  senderType:  text().notNull(),                   // 'customer' | 'support' | 'system'
  message:     text().notNull(),
  attachmentUrl: text(),                           // optional; cap size at app layer
  createdAt:   timestamp({ withTimezone: true }).defaultNow().notNull(),
}, t => [
  index("support_messages_ticket_idx").on(t.ticketId),
  index("support_messages_created_idx").on(t.createdAt),
]);
```

## supportRequests (Legacy / Lightweight Contact Form — Optional)

If the project already has a simple "contact us" form, keep it as a separate lightweight table — don't conflate with SLA-tracked tickets. Migrate to tickets if SLA tracking becomes needed.

```ts
export const supportRequests = pgTable("support_requests", {
  id:           uuid().primaryKey().defaultRandom(),
  userId:       uuid().notNull().references(() => users.id, { onDelete: "cascade" }),
  category:     supportCategoryEnum().notNull(),
  status:       supportStatusEnum().default("open").notNull(),
  summary:      text().notNull(),
  details:      text(),
  pageUrl:      text(),
  screenshotUrl: text(),
  adminNotes:   text(),                  // admin-only — DO NOT skip the customer-email step
  source:       text().default("in_app").notNull(),
  resolvedAt:   timestamp({ withTimezone: true }),
  createdAt:    timestamp({ withTimezone: true }).defaultNow().notNull(),
  updatedAt:    timestamp({ withTimezone: true }).defaultNow().notNull(),
}, t => [
  index("support_requests_user_idx").on(t.userId),
  index("support_requests_status_idx").on(t.status),
  index("support_requests_category_idx").on(t.category),
  index("support_requests_created_idx").on(t.createdAt),
]);
```

**Critical:** if this table exists, wire `sendSupportRequestResponseEmail` into the PATCH handler. The single most damaging support bug in jsm history was admin-resolving a request without notifying the user.

## Relations

```ts
export const supportTicketsRelations = relations(supportTickets, ({ one, many }) => ({
  user:    one(users,         { fields: [supportTickets.userId], references: [users.id] }),
  org:     one(organizations, { fields: [supportTickets.orgId],  references: [organizations.id] }),
  messages: many(supportMessages),
}));

export const supportMessagesRelations = relations(supportMessages, ({ one }) => ({
  ticket: one(supportTickets, { fields: [supportMessages.ticketId], references: [supportTickets.id] }),
  sender: one(users,          { fields: [supportMessages.senderId], references: [users.id] }),
}));
```

## Migration Notes

- Run as one migration; the foreign keys make incremental migration brittle.
- Backfill: existing free-form support items should *not* be auto-migrated to tickets. Tickets carry SLAs that retroactively can't be honored. Migrate manually if the volume is small, or close-and-archive otherwise.
- `slaDeadline` may be null for tickets created during the migration window — the SLA engine treats null as "no deadline" rather than crashing.
