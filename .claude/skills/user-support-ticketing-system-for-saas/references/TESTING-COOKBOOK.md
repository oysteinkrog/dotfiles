# Testing Cookbook — Concrete Patterns For Ticketing Systems

This is the engineering-grade test manual for everything in this skill. The principle: **mock the boundary, never the logic**. Drizzle chain mocks for service-layer unit tests; real DB / real provider for integration; Playwright for E2E. No test doubles between.

For broader testing skill, see [`/testing-real-service-e2e-no-mocks`](../../testing-real-service-e2e-no-mocks/SKILL.md). This file is the **ticketing-system-specific** addendum: the precise mock shapes, fixtures, and assertions that match the canonical service layer.

---

## Section 1 — Service Layer Unit Tests (Mocked DB)

The service-layer functions (`createTicket`, `updateTicket`, `addMessage`, `updateSlaStatuses`, `getSlaMetrics`) are pure transformations over a `db` interface. Unit tests mock the Drizzle chain at exactly the right shape — get this wrong and the function silently flips into wrong branches.

### Drizzle Chain Mock Helpers

```ts
import { vi } from "vitest";

// SELECT path that resolves at .limit(N)
function buildSelectLimitChain(rows: unknown[]) {
  return {
    from: vi.fn().mockReturnValue({
      where: vi.fn().mockReturnValue({
        limit: vi.fn().mockResolvedValue(rows),
      }),
    }),
  };
}

// SELECT with INNER JOIN that resolves at .where(...)  (no .limit() in chain)
// CRITICAL: isEnterpriseUser awaits .where() directly. A chain that resolves
// at .limit() returns a non-Promise object from .where(); the subsequent .find()
// throws, the function's catch swallows it, and the user silently falls through
// to non-enterprise. Match the exact chain shape the function uses.
function buildJoinedSelectWhereChain(rows: unknown[]) {
  return {
    from: vi.fn().mockReturnValue({
      innerJoin: vi.fn().mockReturnValue({
        where: vi.fn().mockResolvedValue(rows),
      }),
    }),
  };
}

// SELECT used for count(*)
function buildSelectCountChain(count: number) {
  return {
    from: vi.fn().mockReturnValue({
      where: vi.fn().mockResolvedValue([{ count }]),
    }),
  };
}

// UPDATE chain
function buildUpdateChain(returnedRows: unknown[]) {
  let captured: Record<string, unknown> | undefined;
  const chain = {
    set: vi.fn().mockImplementation((updates) => { captured = updates; return chain; }),
    where: vi.fn().mockReturnThis(),
    returning: vi.fn().mockResolvedValue(returnedRows),
  };
  return { chain, getCaptured: () => captured };
}
```

**Why these matter.** Drizzle chains differ subtly between operations: `select().from().where().limit()` for paginated reads, `select().from().innerJoin().where()` for joined reads (no `limit`), `update().set().where().returning()` for writes. Mock helpers must match the shape of the chain the function under test actually uses.

### Lifecycle Conformance Tests (3 Required)

These three are the minimum bar for service-layer correctness. Source: `support-ticket-sla-lifecycle.test.ts` in the canonical implementation.

```ts
describe("support ticket SLA lifecycle", () => {
  beforeEach(() => vi.clearAllMocks());

  it("normalizes terminal tickets to ok when resolved before the deadline", async () => {
    mockDbSelect.mockReturnValueOnce(
      buildSelectLimitChain([{
        id: "ticket-1", userId: "user-1", status: "open",
        createdAt: new Date(Date.now() - 60 * 60 * 1000),       // 1h ago
        slaDeadline: new Date(Date.now() + 4 * 60 * 60 * 1000), // 4h from now
        slaBreachedAt: null,
      }])
    );
    const { chain, getCaptured } = buildUpdateChain([{
      id: "ticket-1", status: "resolved", resolvedAt: new Date(), updatedAt: new Date(),
    }]);
    mockDbUpdate.mockReturnValue(chain);

    await updateTicket({ ticketId: "ticket-1", status: "resolved" });

    const captured = getCaptured()!;
    expect(captured.slaStatus).toBe("ok");
    expect(captured.slaBreachedAt).toBeNull();
    expect(captured.slaStatusUpdatedAt).toBeInstanceOf(Date);
    expect(captured.resolvedAt).toBeInstanceOf(Date);
  });

  it("marks reopened tickets as breached when the deadline has already passed", async () => {
    mockDbSelect.mockReturnValueOnce(
      buildSelectLimitChain([{
        id: "ticket-2", userId: "user-2", status: "resolved",
        createdAt: new Date(Date.now() - 6 * 60 * 60 * 1000),
        slaDeadline: new Date(Date.now() - 60 * 60 * 1000),  // 1h ago — past
        slaBreachedAt: null,
      }])
    );
    const { chain, getCaptured } = buildUpdateChain([{
      id: "ticket-2", status: "open", resolvedAt: null, updatedAt: new Date(),
    }]);
    mockDbUpdate.mockReturnValue(chain);

    await updateTicket({ ticketId: "ticket-2", status: "open" });

    const captured = getCaptured()!;
    expect(captured.resolvedAt).toBeNull();
    expect(captured.slaStatus).toBe("breached");
    expect(captured.slaBreachedAt).toBeInstanceOf(Date);
  });

  it("recomputes stored SLA status when priority changes the deadline", async () => {
    const createdAt = new Date();
    mockDbSelect
      .mockReturnValueOnce(buildSelectLimitChain([{
        id: "ticket-3", userId: "user-3", status: "open", createdAt,
        slaDeadline: new Date(createdAt.getTime() + 24 * 60 * 60 * 1000),
        slaBreachedAt: null,
      }]))
      // isEnterpriseUser uses joined-select-where shape; supply enterprise-coverage row
      .mockReturnValueOnce(buildJoinedSelectWhereChain([{
        orgId: "org-123",
        orgSubscriptionStatus: "active",
        stripeSubscriptionId: "sub_FAKEFAKEFAKE0001",  // non-test-mode shape
        paypalSubscriptionId: null,
      }]));

    const { chain, getCaptured } = buildUpdateChain([{
      id: "ticket-3", priority: "p0",
      slaDeadline: new Date(createdAt.getTime() + 60 * 60 * 1000),
      updatedAt: new Date(),
    }]);
    mockDbUpdate.mockReturnValue(chain);

    await updateTicket({ ticketId: "ticket-3", priority: "p0" });

    const captured = getCaptured()!;
    expect(captured.priority).toBe("p0");
    expect(captured.slaDeadline).toBeInstanceOf(Date);
    expect(captured.slaStatus).toBe("at_risk");  // 1h enterprise p0 deadline ≤ 2h warning
  });
});
```

### Why The Live-Subscription-ID Shape Matters In Tests

`hasLiveStripeSubscriptionId` rejects `sub_test_*` prefixed values. A test fixture using `stripeSubscriptionId: "sub_test_xyz"` will silently produce `isEnterprise: false` even though `subscriptionStatus` is `"active"`. The `at_risk` assertion then fails because the deadline computes against the 4h individual SLA (not 1h enterprise).

**Test fixture rule:** use `sub_FAKEFAKEFAKE0001` shape (live-id-shaped, deterministic, never accidentally a real id).

### Side-Effect Mocking — `scheduleSupportSideEffect`

```ts
vi.mock("@/lib/email/support", () => ({
  sendTicketCreatedEmail: vi.fn().mockResolvedValue(undefined),
  sendTicketResponseEmail: vi.fn().mockResolvedValue(undefined),
  sendTicketResolvedEmail: vi.fn().mockResolvedValue(undefined),
}));

// next/server's after() throws outside request scope; the fallback
// `void wrappedTask()` runs the side effect inline. Verify it ran:
test("createTicket triggers sendTicketCreatedEmail", async () => {
  await createTicket({ userId: "u1", subject: "test", description: "..." });
  await new Promise((r) => setTimeout(r, 0));  // flush microtasks
  expect(sendTicketCreatedEmail).toHaveBeenCalledWith(expect.objectContaining({
    ticketId: expect.any(String),
    userId: "u1",
    subject: "test",
  }));
});
```

The microtask flush is necessary because `after()`'s fallback executes asynchronously even when synchronous-looking.

### Logger Mock — Always Required

```ts
vi.mock("@/lib/logger", () => ({
  logger: { info: vi.fn(), warn: vi.fn(), debug: vi.fn(), error: vi.fn() },
}));
```

Without this, `logger.info(...)` throws in test environments where the logger isn't initialized. Mock once at module level.

---

## Section 2 — API Route Tests

Test the route handlers separately from the service layer. Mock the service layer so route tests focus on auth, validation, response shape — not on lifecycle correctness.

### Admin PATCH Route — Reason Required

```ts
test("rejects update without reason", async () => {
  vi.mocked(requireAdmin).mockResolvedValue({ success: true, user: makeAdminUser() });
  vi.mocked(requireAdminMutation).mockResolvedValue({
    success: false,
    response: NextResponse.json({ error: "Reason required" }, { status: 400 }),
  });

  const req = new Request("http://x", {
    method: "PATCH",
    body: JSON.stringify({ ticketId: ticketId, status: "resolved" }),
  });
  const res = await PATCH(req);
  expect(res.status).toBe(400);
});

test("rejects no-op update", async () => {
  // existing.status === "open", request also sends status: "open"
  vi.mocked(requireAdmin).mockResolvedValue({ success: true, user: makeAdminUser() });
  mockDbQueryFindFirst.mockResolvedValueOnce({ id: ticketId, status: "open", priority: "p2", assignee: null });

  const res = await PATCH(makeReq({ ticketId, status: "open", reason: "x".repeat(8) }));
  expect(res.status).toBe(400);
  const body = await res.json();
  expect(body.errors.update).toContain("Update payload does not change any fields");
});
```

### Admin List Route — N+1 Detection

The most subtle regression in this route is reintroducing per-row joins. Test against query-count budget:

```ts
test("admin list does N+1-free fetch", async () => {
  const queryCounts = { select: 0, query: 0 };
  const wrappedDb = wrapDbForCounting(db, queryCounts);
  await GET.call({ db: wrappedDb }, makeAdminReq("?limit=50"));
  // 1 list + 1 user batch + 1 org batch + 2 count queries (status, priority) + 1 approaching-sla
  // Total budget: ≤ 8 queries regardless of row count
  expect(queryCounts.select + queryCounts.query).toBeLessThanOrEqual(8);
});
```

Use a query-counting wrapper around the test DB. Real numbers: 50 tickets enriched should fire at most ~8 queries; if your test fires 50+, the route reintroduced N+1.

### User-Side 404-Not-403

Customer-side ticket-detail must return `404` when the user lacks access — not `403` — so existence isn't leaked.

```ts
test("returns 404 (not 403) when user lacks ticket access", async () => {
  vi.mocked(requireUser).mockResolvedValue({ success: true, user: { userId: "user-A" } });
  // Ticket exists but belongs to user-B with no shared org
  mockGetTicketWithMessages.mockResolvedValueOnce(null);

  const res = await GET(makeReq(), { params: Promise.resolve({ id: ticketId }) });
  expect(res.status).toBe(404);
  const body = await res.json();
  expect(body.error.code).toBe("RESOURCE_NOT_FOUND");
  expect(body.error.message).not.toContain("denied");  // don't hint
  expect(body.error.message).not.toContain("permission");
});
```

### Compile-Time Block On `awaiting_customer`

```ts
test("rejects customer PATCH with awaiting_customer status", async () => {
  vi.mocked(requireUser).mockResolvedValue({ success: true, user: { userId: "u1" } });
  const res = await PATCH(makeReq({ status: "awaiting_customer" }), { params: Promise.resolve({ id: ticketId }) });
  expect(res.status).toBe(400);
  // Server-side Zod must reject; the TypeScript exclusion doesn't help curl.
});
```

---

## Section 3 — Integration Tests (Real DB, No Mocks)

Wire to a real Postgres instance for the full lifecycle. See [`/testing-real-service-e2e-no-mocks`](../../testing-real-service-e2e-no-mocks/SKILL.md) for setup.

### The Five Wire Points That MUST Be Tested

1. **Ticket creation triggers email**
   ```ts
   const before = await countTestEmails();
   const ticket = await createTicket({ userId, subject: "t", description: "..." });
   await waitForSideEffects(); // small delay for after() fallback
   const after = await countTestEmails();
   expect(after - before).toBe(1);
   const email = await getLatestTestEmail();
   expect(email.metadata).toMatchObject({ type: "support_ticket_created", ticketId: ticket.id });
   ```

2. **Status transitions pause/resume SLA**
   ```ts
   const ticket = await createTicket(...);
   const initialDeadline = ticket.slaDeadline!;

   // Support reply → awaiting_customer (pauses)
   await addMessage({ ticketId: ticket.id, senderId: adminId, senderType: "support", message: "..." });
   await sleep(2000);  // simulate customer wait
   let updated = await getTicket(ticket.id);
   expect(updated.status).toBe("awaiting_customer");

   // Customer reply → in_progress + extended deadline
   await addMessage({ ticketId: ticket.id, senderId: ticket.userId, senderType: "customer", message: "..." });
   updated = await getTicket(ticket.id);
   expect(updated.status).toBe("in_progress");
   expect(updated.slaDeadline!.getTime()).toBeGreaterThan(initialDeadline.getTime());
   const extendedBy = updated.slaDeadline!.getTime() - initialDeadline.getTime();
   expect(extendedBy).toBeGreaterThanOrEqual(2000);  // at least the 2s pause
   ```

3. **Breach cron flips slaStatus + records audit**
   ```ts
   const ticket = await createTestTicketWithDeadline(new Date(Date.now() - 60_000));  // 1min past
   const result = await updateSlaStatuses(2);
   expect(result.breached).toContainEqual(expect.objectContaining({ id: ticket.id }));
   const updated = await getTicket(ticket.id);
   expect(updated.slaStatus).toBe("breached");
   expect(updated.slaBreachedAt).toBeInstanceOf(Date);
   const audit = await getAuditLogFor(ticket.id);
   expect(audit).toContainEqual(expect.objectContaining({
     userId: null,                                  // system-attributed
     eventType: "support.sla_breached",
   }));
   ```

4. **Admin reply emails customer**
   ```ts
   await addMessage({ ticketId, senderId: adminId, senderType: "support", message: "..." });
   await waitForSideEffects();
   const email = await getLatestTestEmail();
   expect(email.metadata.type).toBe("support_ticket_response");
   expect(email.to).toBe(customerEmail);
   ```

5. **Priority change recomputes deadline (only on open)**
   ```ts
   const ticket = await createTicket({ ...defaults, priority: "p2" });
   const initial = ticket.slaDeadline!;

   await updateTicket({ ticketId: ticket.id, priority: "p0" });
   const afterChange = await getTicket(ticket.id);
   expect(afterChange.slaDeadline!.getTime()).toBeLessThan(initial.getTime());

   // Resolve the ticket
   await updateTicket({ ticketId: ticket.id, status: "resolved" });
   const finalDeadline = (await getTicket(ticket.id)).slaDeadline;

   // Subsequent priority change on resolved ticket must NOT touch deadline
   await updateTicket({ ticketId: ticket.id, priority: "p3" });
   const afterFinalChange = await getTicket(ticket.id);
   expect(afterFinalChange.slaDeadline).toEqual(finalDeadline);  // unchanged
   ```

### Real-Email Test Setup

Use the project's email provider sandbox, a local SMTP capture tool (Mailpit/MailHog), or a test-only outbox table. The invariant is that integration tests verify the email pipeline end-to-end without delivering to real customers.

```ts
// .env.test
RESEND_API_KEY=re_test_xxx                // provider test key, if available
TEST_EMAIL_INBOX=<provider sandbox or local capture endpoint>
```

```ts
async function getLatestTestEmail() {
  const r = await fetch(process.env.TEST_EMAIL_INBOX!, {
    headers: { Authorization: `Bearer ${process.env.RESEND_API_KEY}` },
  });
  const { emails } = await r.json();
  return emails[0];
}
```

Never hit the real provider in CI unless the provider explicitly supports a non-delivering test environment and the domain/recipient are locked to test accounts. Mock servers (Mailpit, MailHog, Ethereal) or a transactional-email outbox table are usually safer and more reproducible.

---

## Section 4 — Lifecycle Conformance Fixtures

These fixtures are the portable contract. Every implementation of the state machine must pass:

```yaml
fixtures:
  - id: customer-create
    initial: { status: null }
    event: { type: customer_create, priority: p2, tier: individual }
    expected:
      status: open
      slaDeadline: createdAt + 24h
      slaStatus: ok

  - id: support-reply-pauses
    initial: { status: open, slaDeadline: t+12h }
    event: { type: support_reply, at: t+2h }
    expected:
      status: awaiting_customer
      slaDeadline: t+12h        # frozen, not reset

  - id: customer-reply-resumes-with-pause-extension
    initial: { status: awaiting_customer, slaDeadline: t+12h, lastSupportMessageAt: t+2h }
    event: { type: customer_reply, at: t+8h }
    expected:
      status: in_progress
      slaDeadline: t+18h        # 12h + (8h - 2h) = 18h

  - id: customer-reply-on-resolved-no-reopen
    initial: { status: resolved }
    event: { type: customer_reply }
    expected:
      status: resolved          # unchanged
      messageInserted: true     # row written, but no status flip

  - id: admin-resolve-before-deadline
    initial: { status: in_progress, slaDeadline: t+24h, slaBreachedAt: null }
    event: { type: admin_set_status, status: resolved, at: t+4h }
    expected:
      status: resolved
      slaStatus: ok
      slaBreachedAt: null
      resolvedAt: t+4h

  - id: admin-resolve-after-deadline
    initial: { status: in_progress, slaDeadline: t-1h, slaBreachedAt: null }
    event: { type: admin_set_status, status: resolved, at: t }
    expected:
      status: resolved
      slaStatus: breached
      slaBreachedAt: t
      resolvedAt: t

  - id: reopen-past-deadline-immediately-breached
    initial: { status: resolved, slaDeadline: t-7d, slaBreachedAt: null }
    event: { type: admin_set_status, status: open, at: t }
    expected:
      status: open
      slaStatus: breached
      slaBreachedAt: t
      resolvedAt: null
```

Implement each as a service-layer test; if any fail, the state machine has drifted.

---

## Section 5 — Mock-Free DB Patterns

For service-layer tests that need real DB semantics (transactions, constraints, jsonb behavior), use a per-test transaction-rollback pattern:

```ts
import { db } from "@/lib/db/client";

beforeEach(async () => {
  await db.execute(sql`BEGIN`);
});
afterEach(async () => {
  await db.execute(sql`ROLLBACK`);
});
```

This gives every test a clean state without re-seeding. ~10x faster than truncate-between-tests.

For tests that need parallelism, use schema-per-test:

```ts
const testSchema = `test_${randomUUID().replace(/-/g, "")}`;
await db.execute(sql.raw(`CREATE SCHEMA ${testSchema}`));
process.env.DATABASE_SCHEMA = testSchema;
// ... run migrations against this schema, run tests, drop schema after
```

---

## Section 6 — Playwright E2E Patterns

The full customer-and-admin journey lives in Playwright. See [`/e2e-testing-for-webapps`](../../e2e-testing-for-webapps/SKILL.md) for setup.

```ts
test("customer files ticket → admin sees → admin replies → customer reads email", async ({ browser }) => {
  // Customer files ticket
  const customer = await browser.newContext({ storageState: "tests/auth/customer.json" });
  const cPage = await customer.newPage();
  await cPage.goto("/support");
  await cPage.click('[data-testid="new-ticket"]');
  await cPage.fill('[name="subject"]', "Cannot export skills");
  await cPage.fill('[name="description"]', "When I click export, nothing happens.");
  await cPage.click('button:has-text("Create Ticket")');
  await expect(cPage.locator('[data-testid="reference-id"]')).toBeVisible();

  // Admin sees in queue
  const admin = await browser.newContext({ storageState: "tests/auth/admin.json" });
  const aPage = await admin.newPage();
  await aPage.goto("/admin/support/tickets");
  await aPage.click('text=Cannot export skills');
  await expect(aPage.locator('text=Cannot export skills')).toBeVisible();

  // Admin replies (with reason)
  await aPage.fill('[data-testid="reply-textarea"]', "Try refreshing the page first.");
  await aPage.click('button:has-text("Send")');
  await aPage.fill('[data-testid="reason-input"]', "first response");
  await aPage.click('button:has-text("Submit")');

  // Customer receives email (via test inbox)
  const email = await waitForEmail({ to: customerEmail, type: "support_ticket_response" });
  expect(email.html).toContain("Try refreshing the page first.");

  // Customer's UI flips to in_progress on next view
  await cPage.reload();
  await expect(cPage.locator('text=Waiting for your reply')).toBeVisible();
});
```

### Auth Bypass For E2E

Don't run real Google OAuth in tests. Use storage-state fixtures with pre-authenticated sessions:

```ts
// tests/global-setup.ts
const ctx = await browser.newContext();
const page = await ctx.newPage();
await page.goto("/api/test-auth/login?email=customer@test.local");  // test-only route
await ctx.storageState({ path: "tests/auth/customer.json" });
```

Test-only routes must be GUARDED — `if (process.env.ENABLE_TEST_AUTH !== "true") return 404`. Never expose in prod.

---

## Section 7 — Visual Regression For SLA-Status Pills

The persisted-vs-recomputed `slaStatus` distinction is invisible in unit tests but obvious in screenshots. Use Playwright visual regression on the admin queue:

```ts
test("ticket pills render correctly across status combinations", async ({ page }) => {
  await seedTickets([
    { status: "in_progress", slaDeadline: "+1h", slaStatus: "at_risk" },
    { status: "awaiting_customer", slaDeadline: "+24h", slaStatus: "ok" },
    { status: "awaiting_customer", slaDeadline: "-1h", slaStatus: "breached" },
    { status: "resolved", slaDeadline: "-2h", slaStatus: "breached" },  // Missed
    { status: "resolved", slaDeadline: "+2h", slaStatus: "ok" },        // Met
  ]);
  await page.goto("/admin/support/tickets");
  await expect(page.locator('[data-testid="ticket-list"]')).toHaveScreenshot("queue-pills.png");
});
```

A regression in `formatSlaStatus` → screenshot diff.

---

## Section 8 — Anti-Patterns In Tests

| ✗ | Why |
|---|---|
| Mocking the service layer in service-layer tests | Tests pass; production logic is untested. Mock only at the DB boundary. |
| Asserting `expect(result).toBeDefined()` instead of specific shape | A bug that returns `{}` passes; meaningful regression is invisible. |
| Mocking `after()` with `vi.fn()` and not flushing | Side effects appear to run but never actually execute. Always microtask-flush. |
| Re-using a single test ticket across tests | Test order dependence — flake when run in isolation. Each test creates its own ticket. |
| Asserting on Drizzle internals (`.toHaveBeenCalledWith({ where: ... })`) | Fragile to query refactors. Assert on captured `.set()` arguments and DB state, not query syntax. |
| `expect(...).toEqual(somDate)` without `toEqual(expect.any(Date))` | Date equality across processes is fragile. Match the type, not the exact value. |
| Skipping the lifecycle conformance fixtures because "they're slow" | They're 50ms each. Run them. |
| Snapshot testing of the API JSON without filtering volatile fields | `createdAt` differs between runs — every test fails. Filter with `expect.any(String)` or normalize. |
| `await sleep(0)` to "flush microtasks" | Doesn't actually flush. Use `await new Promise((r) => setImmediate(r))` or `await flushMicrotasks()`. |

---

## Section 9 — Test File Organization

```
src/lib/services/__tests__/
  support-tickets.test.ts                          # general unit tests
  support-ticket-sla-lifecycle.test.ts             # the 3-conformance suite
  support-ticket-priority-change.test.ts           # priority recomputation
  support-ticket-pause-resume.test.ts              # pause-duration extension
  support-ticket-cron.test.ts                      # updateSlaStatuses + Slack alerter
  support-tickets-metrics.test.ts                  # getSlaMetrics

src/app/api/support/tickets/__tests__/
  route.test.ts                                    # POST + GET (user-side)
  [id]-route.test.ts                               # detail
  [id]-messages-route.test.ts                      # add message

src/app/api/admin/support/tickets/__tests__/
  routes.test.ts                                   # combined GET + PATCH
  route.test.ts                                    # alternative shape per project
  [id]-messages-route.test.ts                      # admin replies

src/lib/email/__tests__/support.test.ts            # send* functions
src/lib/query/__tests__/support-tickets-hooks.test.tsx  # hooks
src/lib/validation/__tests__/support.test.ts       # zod schemas
src/components/support/__tests__/                  # component tests
```

Each file owns its domain. Cross-file mocking is a smell.

---

## Section 10 — CI Gate Minimums

Before merge to `main`:
- [ ] All unit tests pass (`bun test`)
- [ ] All integration tests pass (`bun test:integration` against real Postgres)
- [ ] All E2E tests pass (`bun test:e2e`)
- [ ] Lifecycle conformance suite explicitly green (cron-skipped CI runs are NOT acceptable)
- [ ] Coverage on service-layer ≥ 90% (line + branch)
- [ ] Visual regression snapshots match
- [ ] Lint, types, build all green

The lifecycle suite is the *one* set of tests that should NEVER be skipped or `.skip()`'d. If they take too long, fix the speed; don't disable them.
