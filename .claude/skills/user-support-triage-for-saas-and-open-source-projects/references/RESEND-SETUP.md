# Resend (Outbound Email) Setup

For SaaS projects that need to email customers (ticket lifecycle, refund confirmations, etc.) and don't yet have an email provider wired in. Resend is the default we recommend — it's the simplest path for Next.js projects.

If the project already uses SendGrid / Postmark / SES / Mailgun / SMTP, leave it. Document its env var names in `07-secrets.md` and reuse the existing `sendEmail` shape.

## Owner Walkthrough

```
🔧 OUTBOUND EMAIL — RESEND SETUP

Your project sends customer-facing email but I don't see RESEND_API_KEY in
your env. Three steps to wire this up:

1. Sign up + verify a sending domain
   → https://resend.com/signup
   → Add your domain, paste the DNS records into Cloudflare/Route53/etc.
   → Wait for verification (usually <5 min)

2. Generate an API key
   → Resend dashboard → API Keys → Create
   → Scope:  "Sending access" only  (least privilege)
   → Copy the key (it's shown ONCE)

3. Add to your project
   → Wherever you store secrets (Vercel envs / Doppler / 1Password / .env.local)
   → Variable name:  RESEND_API_KEY
   → Also set:  RESEND_FROM_EMAIL  (e.g. "support@yourdomain.com")
                RESEND_FROM_NAME   (e.g. "Acme Support")

4. (Optional) Webhook for delivery tracking
   → Resend dashboard → Webhooks → Add
   → URL:  https://<your-domain>/api/webhooks/resend
   → Events:  delivered, bounced, complained
   → Copy the signing secret → set RESEND_WEBHOOK_SECRET

Want me to scaffold the `sendEmail` helper + a webhook handler to record
delivery events? I can match your existing service-layer style.
```

## Minimal Helper (TypeScript / Next.js)

```ts
// src/lib/email/resend-client.ts
import { Resend } from "resend";

let _resend: Resend | null = null;

function client() {
  if (!_resend) _resend = new Resend(process.env.RESEND_API_KEY!);
  return _resend;
}

export async function sendEmail(params: {
  to: string;
  subject: string;
  html: string;
  text: string;
  metadata?: Record<string, string>;
}) {
  const result = await client().emails.send({
    from: `${process.env.RESEND_FROM_NAME} <${process.env.RESEND_FROM_EMAIL}>`,
    to: params.to,
    subject: params.subject,
    html: params.html,
    text: params.text,
    headers: { "X-Entity-Ref": params.metadata?.type ?? "ticket" },
  });
  if (result.error) throw new Error(result.error.message);
  return { id: result.data!.id };
}
```

## Pre-Send Checklist (Hard-Won)

Before *any* sendEmail call hits production:

- [ ] Domain verified in Resend dashboard (green check)
- [ ] SPF / DKIM / DMARC records published — `dig TXT yourdomain.com +short`
- [ ] MX records still point to your inbound provider (Cloudflare Email Routing, etc.) — Resend is *outbound only*
- [ ] Test send to a Gmail address actually arrives, not in spam
- [ ] Bounce / complaint handling wired (don't keep emailing addresses that bounce)
- [ ] Unsubscribe link present where required (transactional emails are exempt; marketing ones are not — keep them separate)
- [ ] Reply-to set to a monitored address, not `noreply@` (customers will reply)

## Common Pitfalls

- **MX vs sending domain confusion.** Sending email *from* `support@` does not require MX → Resend; MX still points to the inbound mail provider. Don't change MX when adding Resend.
- **Subdomain isolation.** Many teams use `mail.yourdomain.com` as the sending subdomain so any reputation hit on outbound doesn't affect the apex domain. Recommend during setup.
- **First-send greylisting.** Some recipients greylist new senders for hours; the first test message can take time.
- **Test and prod sharing one API key.** Bad — preview environments will email real users. Use separate keys per environment.
- **`from` mismatch.** If `RESEND_FROM_EMAIL` doesn't match a verified domain, send fails with a confusing error.

## After Setup — Document In `07-secrets.md`

```markdown
## Email (Resend)

| Var | Purpose |
|---|---|
| `RESEND_API_KEY`         | Sending access (scoped) |
| `RESEND_FROM_EMAIL`      | e.g. `support@yourdomain.com` (must match verified domain) |
| `RESEND_FROM_NAME`       | e.g. `Acme Support` |
| `RESEND_WEBHOOK_SECRET`  | Verifies webhook signatures from Resend → /api/webhooks/resend |

Stored in: <Vercel env / Doppler / etc.>
Owner / approver for new keys: <name>
Rotation cadence: <quarterly / annually / on-incident>
```
