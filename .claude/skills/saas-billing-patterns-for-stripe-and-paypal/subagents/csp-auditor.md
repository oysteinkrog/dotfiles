---
name: billing-csp-auditor
description: Audits CSP headers on checkout pages for Stripe Elements / Checkout / Radar (and PayPal SDK if rendered)
---

# CSP Auditor

For § 78a.5 / B55. Verifies the Content-Security-Policy headers allow Stripe (and PayPal if applicable) without weakening the policy elsewhere.

## Inputs

- Production / staging URL of checkout pages.
- Whether PayPal SDK is rendered (vs. pure redirect).
- Other third parties that may need CSP allowlisting (Supabase, analytics).

## Output

`.billing_workspace/csp_audit.md`:

```markdown
# CSP Audit

## Pages audited
- /pricing → CSP: <directives summary>
- /checkout → CSP: <directives summary>
- /dashboard?from=checkout → CSP: <directives summary>

## Stripe directives present
- `script-src https://js.stripe.com`: ✓
- `script-src https://m.stripe.network`: ✓
- `frame-src https://checkout.stripe.com`: ✓
- `frame-src https://js.stripe.com`: ✓
- `frame-src https://hooks.stripe.com`: ✓
- `frame-src https://m.stripe.network`: ✓
- `connect-src https://api.stripe.com`: ✓
- `connect-src https://m.stripe.network`: ✓

## Anti-clickjacking + form-action
- `frame-ancestors 'none'`: ✓
- `form-action 'self'`: ✓
- `base-uri 'self'`: ✓
- `object-src 'none'`: ✓

## PayPal directives (if SDK rendered)
- `script-src https://www.paypal.com/sdk/js`: <yes/no>
- PayPal frame/script origins: <list>

## Findings
[any missing directives that would break Stripe or PayPal; any over-permissive directives]
```

## Procedure

1. For each checkout-relevant URL:
   ```bash
   curl -sI <url> | grep -i 'content-security-policy'
   ```
2. Parse the CSP header into directives.
3. Check each Stripe-required directive is present.
4. If PayPal SDK is rendered: check PayPal-required directives.
5. Check anti-clickjacking + form-action protections.
6. Flag any over-permissive directives (`'unsafe-inline'`, `'unsafe-eval'`, wildcards in src lists).

## Drift triggers

| Drift | Severity |
|-------|----------|
| Stripe directive missing on /checkout | High (Stripe Elements fails silently) |
| `frame-ancestors` missing or `*` | High (clickjacking risk) |
| `'unsafe-eval'` on /checkout | High (XSS risk) |
| `script-src 'unsafe-inline'` on /checkout | High (XSS risk) |
| PayPal SDK rendered without PayPal CSP additions | High |
| CSP header missing entirely on /checkout | Critical |

## Drift-guard test

```ts
// __tests__/billing/csp-coverage.test.ts
describe('CSP on checkout pages', () => {
  test('checkout response includes Stripe directives', async () => {
    const response = await fetch('/checkout');
    const csp = response.headers.get('content-security-policy');
    expect(csp).toBeDefined();
    expect(csp).toMatch(/script-src.*https:\/\/js\.stripe\.com/);
    expect(csp).toMatch(/frame-src.*https:\/\/checkout\.stripe\.com/);
    expect(csp).toMatch(/frame-ancestors\s+'none'/);
  });
});
```

## Integration

- Phase 5 (B55 implementation).
- Phase 9 staging drill (live page-load test).
- Compliance-pass mode (evidence file in pack).
- Triggered after any CSP / Next.js middleware change.
