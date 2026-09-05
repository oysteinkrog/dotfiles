# Project-Type Defaults

The patterns in this skill were mined from a Next.js App Router + Drizzle + Postgres (Supabase) + Vercel Cron + Resend stack. The semantics translate to other stacks, but the *file paths*, *idiomatic implementations*, and *which platform features substitute for which* differ.

`scripts/discover-stack.sh` detects the stack and recommends the template.

---

## Detection signals

The discoverer looks at:

- `package.json` `dependencies` for: `next`, `remix`, `@sveltejs/kit`, `nuxt`, `express`, `fastify`, `hono`, `stripe`, `@paypal/checkout-server-sdk`, `drizzle-orm`, `prisma`, `@supabase/supabase-js`, `pg`, `mysql2`, `@upstash/redis`, `resend`, `@react-email/components`.
- `pyproject.toml` / `requirements.txt` for: `fastapi`, `django`, `flask`, `stripe`, `paypalrestsdk`, `sqlalchemy`, `psycopg`.
- `Gemfile` for: `rails`, `stripe-ruby`.
- `mix.exs` for: `phoenix`, `stripity_stripe`.
- `vercel.json`, `.vercel/` for: cron schedules, env presence.
- File-tree heuristics: `src/app/api/.../webhook/`, `pages/api/.../webhook/`, `app/routes/api.../webhook.tsx`, etc.

Output: `phase0_stack.json`:
```json
{
  "framework": "next-app-router | next-pages-router | remix | sveltekit | nuxt | express | fastify | hono | fastapi | django | flask | rails | phoenix",
  "orm": "drizzle | prisma | sequelize | sqlalchemy | django-orm | activerecord | ecto | none",
  "db": "postgres | mysql | sqlite",
  "cron_host": "vercel | cloudrun | render | fly | github-actions | own-cron-server | none",
  "email": "resend | postmark | ses | sendgrid | mailgun | none",
  "providers": ["stripe", "paypal"],
  "deployment": "vercel | cloudflare-pages | self-hosted | railway | render | fly"
}
```

---

## Template: Next.js App Router + Drizzle + Postgres + Vercel + Resend (canonical)

This is the source guide's stack. Patterns apply directly.

| Concept | File path |
|---------|-----------|
| Webhook route | `src/app/api/{stripe,paypal}/webhook/route.ts` |
| Checkout route | `src/app/api/{stripe,paypal}/create-checkout/route.ts` |
| Verify-as-write route | `src/app/api/checkout/verify/route.ts` |
| Cron routes | `src/app/api/cron/<name>/route.ts` |
| Cron schedule | `vercel.json` `"crons": [{ "path": "...", "schedule": "..." }]` |
| Webhooks library | `src/lib/webhooks/inbound.ts` |
| Subscription service | `src/lib/services/subscription.ts` |
| Schema | `src/db/schema.ts` (Drizzle) |
| Migrations | `supabase/migrations/<timestamp>_<name>.sql` (or `drizzle/migrations/`) |
| Constants | `src/lib/constants/{business,stripe-config,routes,webhook-error-codes}.ts` |
| Env | `src/env.ts` (Zod-validated) |
| Email queue | `src/lib/email/{retry,dlq}.ts` |
| Analytics exclusions | `src/lib/analytics/exclusions.ts` |
| Admin events | `src/lib/events/admin-event-publishers.ts` |

Vercel-specific notes:
- Use Sensitive flag for every billing secret in Vercel project env.
- Use Production-only scope; Preview/Development use test-mode keys.
- Cron uses `Bearer $CRON_SECRET` auth via `vercel.json` headers.
- Edge runtime is OK for read-only routes; webhook routes MUST be Node runtime (Stripe SDK + crypto).

---

## Template: Next.js Pages Router + Prisma

Most patterns apply but routes and ORM idioms differ.

| Concept | File path |
|---------|-----------|
| Webhook route | `pages/api/{stripe,paypal}/webhook.ts` (export config: `{ api: { bodyParser: false } }`) |
| Checkout route | `pages/api/{stripe,paypal}/create-checkout.ts` |
| Verify route | `pages/api/checkout/verify.ts` |
| Cron routes | `pages/api/cron/<name>.ts` |
| Schema | `prisma/schema.prisma` |
| Migrations | `prisma/migrations/<timestamp>/migration.sql` |

Prisma-specific notes:
- Prisma's UNIQUE-on-multi-column needs `@@unique([provider, eventId])` in schema.
- Partial UNIQUE indexes need raw migration SQL (Prisma doesn't model them directly).
- For 23505 detection, catch `Prisma.PrismaClientKnownRequestError` with `e.code === 'P2002'`.
- Transactions: `prisma.$transaction([...])` is the analog of Drizzle's `db.transaction(async tx => ...)`.

---

## Template: Remix / SvelteKit / Nuxt

| Concept | Remix | SvelteKit | Nuxt |
|---------|-------|-----------|------|
| Webhook route | `app/routes/api.stripe.webhook.tsx` (action) | `src/routes/api/stripe/webhook/+server.ts` | `server/api/stripe/webhook.post.ts` |
| Checkout route | `app/routes/api.create-checkout.tsx` | `src/routes/api/create-checkout/+server.ts` | `server/api/create-checkout.post.ts` |
| Cron | NOT built-in — use external worker (Cloud Run, Render Cron, GitHub Actions) | NOT built-in — same | NOT built-in — same |
| ORM | usually Drizzle / Prisma | usually Drizzle / Prisma | usually Drizzle / Prisma |
| Email | usually Resend / Postmark | same | same |

Cron note: without a built-in cron, you need a separate worker. Patterns translate but you must:
- Implement the advisory-lock pattern explicitly (the worker calls `pg_try_advisory_lock` itself).
- Bound the per-run scan size; the worker's wall-time budget defines `LIMIT N`.
- Use a JWT or shared-secret header for the cron invocation; never expose the cron route unauth.

---

## Template: Express / Fastify / Hono

Patterns apply directly; framework-specific idioms differ.

| Concept | Express | Fastify | Hono |
|---------|---------|---------|------|
| Webhook route | `app.post('/api/stripe/webhook', express.raw({type:'*/*'}), handler)` | `fastify.post('/api/stripe/webhook', { config: { rawBody: true } }, handler)` | `app.post('/api/stripe/webhook', async (c) => { const body = await c.req.text(); ... })` |
| Cron | external (no built-in) | external | external |
| Sig verification | `stripe.webhooks.constructEvent(rawBody, sigHeader, secret)` | same | same |

Express specifically: do NOT add `express.json()` BEFORE the webhook route — you need the raw body for signature verification. Use `express.raw({ type: '*/*' })` for the webhook routes only.

---

## Template: FastAPI / Django / Flask (Python)

Pattern semantics same; idiomatic translation:

| Concept | FastAPI / Django / Flask |
|---------|-------------------------|
| Webhook | `@app.post('/api/stripe/webhook')` (FastAPI) / `@csrf_exempt` view (Django) / `@app.route('/api/stripe/webhook', methods=['POST'])` (Flask) |
| Idempotency key generation | `stripe.Subscription.create(idempotency_key=key, **params)` |
| 23505 detection | `psycopg.errors.UniqueViolation` (`raise IntegrityError`) |
| Transactions | `with db.transaction():` (Django) / `async with db.transaction():` (encode/databases) |
| Cron | Celery beat / APScheduler / external (Cloud Run scheduled jobs) |
| Pydantic schema for `payment_events` | `class PaymentEvent(BaseModel): provider: str; event_id: str; ...` |

PayPal Python SDK notes:
- The `paypalrestsdk` library is older and partially deprecated; prefer `requests` + their REST API directly.
- For sandbox vs. production, use the OAuth2 token URL switching (`api.sandbox.paypal.com` vs `api.paypal.com`).

---

## Template: Rails (Ruby)

Most pattern semantics translate; Rails idioms:

| Concept | Rails |
|---------|-------|
| Webhook | `routes.rb`: `post '/api/stripe/webhook', to: 'webhooks#stripe'` + skip `protect_from_forgery` |
| Sig verification | `Stripe::Webhook.construct_event(payload, sig_header, secret)` |
| Idempotency | `Stripe::Subscription.create(params, idempotency_key: key)` |
| 23505 detection | `rescue ActiveRecord::RecordNotUnique` |
| Transactions | `ActiveRecord::Base.transaction do ... end` |
| Cron | `whenever` gem + cron OR Sidekiq scheduled jobs |
| Schema | `db/schema.rb` + migrations |

Strong-parameters caveat: don't accept `metadata.user_id` as a permitted param — it's an attacker-controlled field.

---

## Template: Phoenix (Elixir)

Pattern semantics same; Elixir idioms:

| Concept | Phoenix |
|---------|---------|
| Webhook | router.ex: `post "/api/stripe/webhook", WebhookController, :stripe` (with raw body Plug) |
| Sig verification | `Stripity.Stripe.Webhook.construct_event(payload, sig_header, secret)` |
| Idempotency | `Stripity.Stripe.Subscriptions.create(params, idempotency_key: key)` |
| 23505 detection | match `{:error, %Ecto.Changeset{errors: [..., {:unique_constraint, _}]}}` |
| Transactions | `Ecto.Multi` |
| Cron | `Quantum` (`quantum-elixir`) or `Oban` jobs |
| Schema | Ecto schema modules + migrations |

Process model: each request gets its own process — concurrency is free, but advisory locks across processes still need Postgres `pg_try_advisory_lock`.

---

## Template: Cloudflare Workers / Edge runtime

Significant adjustments needed:

| Pattern | Adjustment |
|---------|-----------|
| Postgres pool | Use Hyperdrive + connection pooling — long-lived connections from Worker isolates aren't available |
| Cron | Cron Triggers (`crons` in `wrangler.toml`); bounded by Worker CPU + memory limits |
| Stripe SDK | Use `stripe` v14+ which supports Edge runtime; OR use `fetch` directly |
| PayPal SDK | No SDK supports Edge — use `fetch` directly to PayPal REST API |
| Crypto for sig verification | Use `Web Crypto` API; the older `node:crypto` Stripe SDK path won't work |
| `process.env` | Replace with `env.STRIPE_SECRET` (passed into the fetch handler) |
| Long-running provider calls | Workers have 30s wall-time; pause/resume Stripe calls (80s+) WON'T fit — offload to a Durable Object or external worker |

The intent-then-act pattern is even more important on Workers because of the wall-time limit. Never run a slow provider call inside a transaction; always commit the intent first.

---

## Template: Polyglot monorepo (Turborepo / Nx)

If billing lives in its own package within a monorepo:

- Single canonical billing package (`packages/billing/`); apps depend on it.
- Never duplicate the writers in each app — that's how the 13-instance API-version drift happens.
- Shared `payment_events` table; per-app subscription tables MAY exist if products are truly distinct.
- Cron jobs live in the deployable that has DB access; not in the SDK package.

Pattern that bites: a `next-app` and a `node-worker` both define their own `Stripe()` client with different API versions → drift. Fix: the billing package exports the singleton.

---

## When the stack doesn't match any template

The patterns are about *semantics*, not *idioms*. For an unsupported stack:

1. Read the source guide's pattern (e.g., `40-WEBHOOKS § 5-step contract`).
2. Identify the semantic invariants: signature → dedup-insert → handler → 200-on-error → mark-processed.
3. Translate each invariant into your stack's idiom.
4. Pin the contract with a regression test in your stack's testing framework.

If the translation is non-trivial, file a PR against this skill adding the template — your work helps future users.

---

## Database adjustments

### MySQL

- `UNIQUE (provider, event_id)` — same as Postgres.
- Partial UNIQUE indexes: not supported directly. Workaround: a generated column that's NULL when not pending, and a UNIQUE on that generated column.
- 23505 → MySQL emits error code 1062 (`ER_DUP_ENTRY`).
- `ON CONFLICT DO NOTHING` → `INSERT IGNORE` or `ON DUPLICATE KEY UPDATE`.
- Advisory locks: `GET_LOCK('cron_name', 0)` — release with `RELEASE_LOCK('cron_name')`.

### SQLite (early-stage)

- Single-writer DB; advisory locks N/A (use file-level locks or skip).
- `payment_events.payload` as `TEXT` containing JSON string.
- `UNIQUE (provider, event_id)` works.
- Cron concurrency assumption: only one writer; the lock is implicit.
- Plan to migrate to Postgres before scaling beyond a single host.

### Postgres-compatible (Neon, Aurora Serverless, CockroachDB)

- Most patterns apply directly.
- CockroachDB: advisory locks NOT supported; use SELECT FOR UPDATE on a sentinel row instead.
- Aurora Serverless V1: cold-start latency on lambda-style invocation; reserve a connection earlier in the cron.

---

## Email provider adjustments

| Provider | DLQ pattern | Failsafe |
|----------|-------------|----------|
| Resend | Use `email_jobs` + `email_dlq` tables; failsafe via OPS_FAILSAFE_EMAIL inbox different from primary | canonical |
| Postmark | Same pattern; Postmark has its own message stream concept that doesn't replace the DLQ |
| SES | Same pattern; SES doesn't have built-in retry — your queue is the only retry path |
| SendGrid | Same pattern |
| Mailgun | Same pattern |

The pattern is provider-agnostic: durable queue + DLQ + failsafe-different-channel. Don't trust any provider's "we'll retry" — they all have outages.

---

## Cron host adjustments

| Host | Schedule format | Auth |
|------|-----------------|------|
| Vercel Cron | `vercel.json` `"crons": [{ "path": "...", "schedule": "0 * * * *" }]` | `Authorization: Bearer $CRON_SECRET` set in Headers |
| Cloud Run Jobs | `gcloud scheduler jobs create http ...` | OIDC token |
| Render Cron | dashboard or `render.yaml` | bearer header |
| Fly.io | `fly.toml` `[[cron]]` | bearer header |
| GitHub Actions | `.github/workflows/cron.yml` `on: schedule:` | uses repo SECRETS as bearer |
| Self-hosted | system cron / systemd timers | local bearer |

Auth invariant: NEVER expose a cron route unauth. Use a bearer secret + IP allowlist if available.

Wall-time invariant: Vercel's serverless function timeout (300s on Pro plan) caps how long any cron tick can run. Bound the per-run scan accordingly.
