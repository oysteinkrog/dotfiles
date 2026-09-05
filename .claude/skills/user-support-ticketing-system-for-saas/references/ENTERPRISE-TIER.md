# Enterprise Tier (Optional)

For projects with enterprise customers needing tighter SLAs.

## Tier Resolution

```ts
function resolveTier(user: User, org: Org | null): Tier {
  if (org?.subscriptionTier === "enterprise") return "enterprise";
  if (user.subscriptionStatus === "active")   return "individual";
  return "free";
}
```

Resolved once at ticket creation; written into computation, never re-derived.

## Per-Org Override

Some enterprise customers negotiate custom SLAs. Add to `organizations`:

```ts
slaOverride: jsonb("sla_override"),  // { firstResponse: {...}, resolution: {...} } | null
```

Service-layer:
```ts
const config = org?.slaOverride ?? SLA_CONFIG[tier];
```

## Surface In Admin UI

Enterprise tickets are visually distinct on the admin queue:
- Org name shown prominently
- Tier pill: `ENTERPRISE` next to priority
- Custom-SLA tag if `slaOverride` is set

## Reporting

Enterprise contracts often require monthly SLA-compliance reports. Add a query:

```ts
async function getOrgSlaReport(orgId: string, periodStart: Date, periodEnd: Date) {
  // Total tickets in period
  // First-response SLA met %
  // Resolution SLA met %
  // Median first-response time
  // Median resolution time
  // Breach list (with cause)
}
```

Render as PDF / CSV from `/admin/support/sla-reports/[orgId]`.

## Renegotiation Hooks

When an enterprise plan is renegotiated, the `slaOverride` changes. **New tickets only** get the new SLA — keep existing tickets on their original config. Otherwise customers experience SLA shifts mid-flight, which surprises everyone.

## SLA Penalty Clauses

Some enterprise contracts have credit-back clauses for breached SLAs. Don't auto-issue credits — escalate breaches to a human via the cron's internal alert. Auto-credit is a foot-gun.
