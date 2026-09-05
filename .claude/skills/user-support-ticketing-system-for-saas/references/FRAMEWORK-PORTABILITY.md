# Framework Portability

This skill's default implementation is Next.js + Drizzle + Resend because
that is a useful concrete path for many SaaS projects. The deeper value,
however, is not tied to that stack. The universal part is the support-system
invariant set: service-layer mutations, state-machine conformance, audit,
permission keys, SLA clock semantics, tier-aware rate limits, and no silent
customer sends.

Use this page when adapting the skill to another framework without watering
down those invariants.

## Split The Work

| Universal | Framework-Specific |
|---|---|
| Ticket lifecycle state machine | Routes/controllers syntax |
| SLA deadline semantics | ORM migrations |
| Permission vocabulary | Auth middleware |
| Audit requirements | Audit table/library |
| Customer-visible send gate | Email/provider SDK |
| Triage adapter contract | Local script/API implementation |
| Conformance fixtures | Test runner wiring |

Do not copy Next.js file names into another framework when the framework has a
better native convention. Do preserve the invariants.

## Porting Contract

For a new framework adapter, document:

```markdown
# <Framework> Support Ticketing Port

- Service layer path:
- Migration path:
- Admin route/controller path:
- User route/controller path:
- Auth/permission hook:
- Email/send abstraction:
- Cron/job runner:
- Test runner:
- Triage adapter script:
- State-machine conformance command:
```

## Examples

| Stack | Service Layer | Routes | Jobs | Test Shape |
|---|---|---|---|---|
| Django | `support/services.py` | DRF views or Django views | Celery/management command | pytest + DB transaction |
| Rails | `app/services/support_tickets/*` | controllers | ActiveJob/Sidekiq | RSpec request + model specs |
| Express/Nest | `support-tickets.service.ts` | controllers/routers | BullMQ/cron | integration tests with real DB |
| Laravel | `app/Services/SupportTickets` | controllers | queues/scheduler | Pest/PHPUnit feature tests |
| Go | `internal/support` | chi/gin/http handlers | worker/cron package | integration tests against test DB |

## Porting Steps

1. Map the host project's auth, DB, email, cron, and admin UI conventions.
2. Create the state-machine transition function first.
3. Wire every mutation through that function.
4. Add conformance fixtures before building UI polish.
5. Add the triage adapter script and validate it.
6. Only then build provider migration and AI assist features.

## Red Lines

- No direct table writes from controllers.
- No status enum values without lifecycle semantics.
- No customer-visible sends from cron or AI assist.
- No silent admin notes that the owner thinks emailed the customer.
- No "temporary" route that bypasses permissions.
- No framework port that omits the triage handoff adapter.

## Acceptance Standard

A non-Next.js port is support-ready when:

- state-machine conformance passes;
- the triage adapter passes `validate-adapter-output.py`;
- equivalent admin/user flows exist;
- equivalent audit and permission checks exist;
- email send semantics match the confirmation and no-silent-send rules;
- the port's docs point back to the universal invariants rather than forking
  business logic.
