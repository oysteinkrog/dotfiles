# Stripe Webhook Setup - Paste-Ready Instructions

## Before Pasting

Replace these placeholders:
- `WEBHOOK_URL` → Your webhook endpoint (e.g., `https://myapp.com/api/webhooks/stripe`)

---

## Instructions to Paste

**Step 1: Create Webhook Endpoint**

URL: `https://dashboard.stripe.com/webhooks`

1. Click "+ Add endpoint" button
2. In "Endpoint URL" field, enter: `WEBHOOK_URL`
3. Click "Select events"
4. Check these events:
   - `checkout.session.completed`
   - `customer.subscription.created`
   - `customer.subscription.updated`
   - `customer.subscription.deleted`
   - `invoice.payment_succeeded`
   - `invoice.payment_failed`
5. Click "Add events"
6. Click "Add endpoint"

**Step 2: Get Signing Secret**

1. Click on the webhook you just created
2. Under "Signing secret", click "Reveal"
3. Copy the secret (starts with `whsec_`)

Report back:
- Webhook signing secret (format: `whsec_xxxxxxxxxxxx`)

---

## After User Reports Secret

```bash
# 1. Update .env.local
echo "STRIPE_WEBHOOK_SECRET=whsec_xxxx" >> .env.local

# 2. Update Vault
vault kv patch secret/project-name STRIPE_WEBHOOK_SECRET="whsec_xxxx"

# 3. Update Vercel
echo "whsec_xxxx" | vercel env add STRIPE_WEBHOOK_SECRET production
```

## Testing

```bash
# Install Stripe CLI if needed
# Then forward webhooks to local dev:
stripe listen --forward-to localhost:3000/api/webhooks/stripe

# Trigger test event:
stripe trigger checkout.session.completed
```
