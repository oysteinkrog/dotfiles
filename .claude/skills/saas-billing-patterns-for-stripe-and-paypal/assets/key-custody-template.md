# Secret Custody Matrix

> **Template.** Copy to `.billing_workspace/phase10_secret_custody.md`. Fill in. Update on every rotation.

## Inventory

| Secret | Used by | Storage | Sensitive flag | Production-only? | Rotation cadence | Last rotated | Custody (who can read/rotate) |
|--------|---------|---------|----------------|------------------|------------------|--------------|-------------------------------|
| STRIPE_SECRET_KEY | webhook handler + checkout + admin | Vercel env | ✓ | ✓ | quarterly (90d) | <YYYY-MM-DD> | engineering-leads (read), CTO (rotate) |
| STRIPE_WEBHOOK_SECRET | webhook handler | Vercel env | ✓ | ✓ | annual + on-demand (180d) | <YYYY-MM-DD> | engineering-leads (read), CTO (rotate) |
| STRIPE_PUBLISHABLE_KEY | client (NEXT_PUBLIC) | Vercel env | — | ✓ | n/a (publishable) | n/a | n/a |
| STRIPE_PRICE_PRO_MONTHLY | constants | Vercel env (config, not secret) | — | ✓ (production) | per-pricing-change | <YYYY-MM-DD> | engineering-leads + product-leads |
| STRIPE_AUDIT_KEY (read-only restricted) | provider-catalog audit cron | Vercel env (CI) | ✓ | ✓ | annual (365d) | <YYYY-MM-DD> | engineering-leads + auditor |
| PAYPAL_CLIENT_ID | server | Vercel env | ✓ | ✓ | annual (180d) | <YYYY-MM-DD> | engineering-leads (read), CTO (rotate) |
| PAYPAL_CLIENT_SECRET | server | Vercel env | ✓ | ✓ | annual (180d) | <YYYY-MM-DD> | engineering-leads (read), CTO (rotate) |
| PAYPAL_WEBHOOK_ID | webhook handler | Vercel env | ✓ | ✓ | (rare) | <YYYY-MM-DD> | engineering-leads |
| SUPABASE_SERVICE_ROLE_KEY | webhook + cron + admin | Vercel env | ✓ | ✓ | annual (365d) | <YYYY-MM-DD> | engineering-leads (read), CTO (rotate) |
| SUPABASE_ANON_KEY | client (NEXT_PUBLIC) | Vercel env | — | n/a | n/a (public) | n/a | n/a |
| CRON_SECRET | cron auth | Vercel env | ✓ | ✓ | quarterly (90d) | <YYYY-MM-DD> | engineering-leads |
| RESEND_API_KEY | email queue | Vercel env | ✓ | ✓ | annual (365d) | <YYYY-MM-DD> | engineering-leads |
| OPS_FAILSAFE_RESEND_KEY | failsafe send (DIFFERENT Resend account) | Vercel env | ✓ | ✓ | annual (365d) | <YYYY-MM-DD> | CTO + on-call lead |
| ADMIN_EMAIL | recipient | Vercel env (config) | — | ✓ | n/a | n/a | n/a |
| OPS_FAILSAFE_EMAIL | recipient (different inbox) | Vercel env (config) | — | ✓ | n/a | n/a | n/a |

## Rotation log

| Date | Secret | Reason | Rotated by | Verified by | Old key revoked at |
|------|--------|--------|------------|-------------|---------------------|
| <YYYY-MM-DD> | <secret> | <reason> | <name> | <name> | <YYYY-MM-DD HH:MM UTC> |

## Rotation procedure

For each secret, the steps are documented in `<project>/docs/runbooks/secret-rotation.md`. Standard pattern:

1. Generate new value via provider Dashboard.
2. Update Vercel env (Production scope only).
3. Trigger redeploy.
4. Verify webhook still receives events (Stripe Dashboard "Test webhook" button or PayPal sandbox).
5. Update this matrix's `Last rotated` cell + add row to rotation log.
6. After 24h-confirmation period, revoke old value in provider Dashboard.
7. Update rotation log with `Old key revoked at`.

## Compromise procedure

If any secret is suspected leaked (Slack message, public commit, exposed in logs, etc.):

1. **Rotate immediately** (skip cadence).
2. **Audit logs** for unauthorized use during the exposure window:
   - Stripe Dashboard → API key activity log
   - PayPal Dashboard → API access log
   - Supabase Dashboard → query log (for service_role key)
3. **Notify** engineering-leads + on-call.
4. **Update** `compliance_events` table with `secret_rotated_emergency` event.
5. **Postmortem** if customer-affecting (per assets/postmortem-template.md).

## Drift-guards

- `secret-custody-completeness.test.ts` — every billing env var listed in `src/env.ts` has a matrix row above.
- `secret-custody-rotation-cadence.test.ts` — each secret's `Last rotated` is within its documented cadence.

If either drift-guard fails: review this matrix; rotate stale secrets; commit the update.
