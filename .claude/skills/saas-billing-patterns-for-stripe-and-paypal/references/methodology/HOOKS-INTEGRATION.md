# Hooks Integration — Pre-commit, CI, Deploy Gates

> **Where this comes from.** Cross-reference with `/cc-hooks` (Claude Code hook system) + `/dcg` (Destructive Command Guard). Plus standard CI/CD practice for billing systems.

The skill's drift-guards + audit scripts are useful only if they actually run. This file shows where to wire them. For generic CI/CD setup, see your project's existing pipeline; this is the BILLING-SPECIFIC wiring.

Use this file only when `phase0_scope_decision.md` activates billing drift-guards, provider audits, or billing-specific CI gates. Do not replace a project's general hook or CI architecture from this reference alone; copy only the billing checks that match the touched bundles.

---

## Pre-commit: billing-touching files only

```bash
# .husky/pre-commit (or pre-commit framework)
CHANGED=$(git diff --cached --name-only --diff-filter=ACM)
BILLING=$(echo "$CHANGED" | grep -E '(stripe|paypal|webhook|subscription|payment|billing)' || true)
[[ -z "$BILLING" ]] && exit 0

# Hardcoded-secret check (CRITICAL — blocks before push)
if echo "$BILLING" | xargs grep -lE 'sk_live_|sk_test_|whsec_[a-zA-Z0-9]{20}|NEXT_PUBLIC_.*(SECRET|TOKEN|WEBHOOK)' 2>/dev/null; then
  echo "✗ Hardcoded billing secret OR NEXT_PUBLIC_ exposing one. Refusing commit."
  exit 1
fi

# Quick billing-specific audits
./scripts/audit-webhook-200-on-error.sh . || exit 1
node ./scripts/audit-update-staleness-guards.mjs . || exit 1
./scripts/audit-cron-locks.sh . || exit 1
```

---

## CI: per-PR for billing paths

```yaml
# .github/workflows/billing-ci.yml
on:
  pull_request:
    paths:
      - 'src/lib/webhooks/**'
      - 'src/lib/services/{subscription,dunning,team-billing}.ts'
      - 'src/app/api/{stripe,paypal,cron}/**'
      - 'src/db/schema.ts'
      - 'src/lib/constants/**'
      - 'supabase/migrations/**'
      - 'src/env.ts'

jobs:
  drift-guards:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: yarn test --testPathPattern='__tests__/drift-guard/' --ci

  static-audits:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: ./scripts/audit-webhook-200-on-error.sh .
      - run: node ./scripts/audit-update-staleness-guards.mjs .
      - run: ./scripts/audit-cron-locks.sh .
      - run: node ./scripts/audit-exclusions-coverage.mjs .

  billing-integration-tests:
    runs-on: ubuntu-latest
    services:
      postgres: { image: postgres:16, env: { POSTGRES_PASSWORD: test, POSTGRES_DB: billing_test }, ports: ['5432:5432'] }
    env:
      DATABASE_URL: postgres://postgres:test@localhost:5432/billing_test
      STRIPE_SECRET_KEY: ${{ secrets.STRIPE_TEST_SECRET_KEY }}
      STRIPE_WEBHOOK_SECRET: ${{ secrets.STRIPE_TEST_WEBHOOK_SECRET }}
    steps:
      - uses: actions/checkout@v4
      - run: yarn drizzle-kit migrate
      - run: yarn test --testPathPattern='__tests__/billing/' --ci

  detect-billing-mocks:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: |
          if rg -l 'jest\.mock\(|vi\.mock\(|sinon\.stub\(' __tests__/billing/ 2>/dev/null; then
            echo "✗ Billing tests must NOT use mocks (per § 69)."
            exit 1
          fi
```

---

## CODEOWNERS for billing

```
# .github/CODEOWNERS
src/lib/webhooks/                @billing-team @senior-engineers
src/lib/services/subscription.ts @billing-team @senior-engineers
src/app/api/{stripe,paypal}/     @billing-team @senior-engineers
src/db/schema.ts                 @billing-team @senior-engineers @database-team
supabase/migrations/             @billing-team @senior-engineers @database-team
src/lib/constants/business.ts    @billing-team @product
src/env.ts                       @senior-engineers @sre
```

Branch protection: require reviews from CODEOWNERS for billing-touching PRs.

---

## Pre-deploy gate (production-bound builds)

```yaml
on:
  push:
    branches: [main]

jobs:
  pre-deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: ./scripts/audit-bundle-leakage.sh .
      - env: { STRIPE_SECRET_KEY: ${{ secrets.STRIPE_AUDIT_KEY }} }
        run: ./scripts/audit-stripe-event-coverage.sh .
      - env: { VERCEL_TOKEN: ${{ secrets.VERCEL_TOKEN }} }
        run: ./scripts/audit-vercel-env.sh .
```

If any fail → deploy BLOCKED. No override without manual sign-off.

---

## Daily provider-state audit (continuous evidence per B120)

```yaml
# .github/workflows/daily-billing-audit.yml
name: Daily Billing Audit

on:
  schedule:
    - cron: '0 8 * * *'  # 08:00 UTC daily

jobs:
  audit:
    runs-on: ubuntu-latest
    env:
      STRIPE_SECRET_KEY: ${{ secrets.STRIPE_AUDIT_KEY }}
      PAYPAL_CLIENT_ID: ${{ secrets.PAYPAL_CLIENT_ID }}
      PAYPAL_CLIENT_SECRET: ${{ secrets.PAYPAL_CLIENT_SECRET_READ }}
    steps:
      - uses: actions/checkout@v4
      - run: ./scripts/provider-diagnostics.sh > .billing_workspace/provider_audit_$(date +%Y%m%d).md
      - run: ./scripts/audit-trial-discount-deal.sh
      - run: ./scripts/audit-stripe-event-coverage.sh .
      - uses: actions/upload-artifact@v4
        with:
          name: billing-audit-${{ github.run_id }}
          path: .billing_workspace/
          retention-days: 730  # 2 years for tax / SOC2
      # Alert on drift
      - run: |
          if grep -q "✗" .billing_workspace/provider_audit_*.md; then
            curl -X POST $SLACK_BILLING_WEBHOOK -d "Drift detected in daily billing audit"
            exit 1
          fi
```

The 2-year retention is the SOC2 evidence backbone (per B120).

---

## Billing-specific gates summary

| Gate | When | What it enforces |
|------|------|------------------|
| Pre-commit | Every billing-touching commit | No hardcoded secrets; basic static audits |
| PR | Every billing-path PR | Drift-guards + integration tests + no-mocks |
| CODEOWNERS | Merge approval | Senior + billing-team review |
| Pre-deploy | Promotion to production | No secrets in bundle + provider-state matches |
| Daily | 08:00 UTC daily | Continuous evidence + drift detection |

That's the billing-specific CI surface. For generic project CI, defer to your existing pipeline.

---

## Full pre-commit hook

Use the short hook above when you need a fast starter. Use this full version when the billing system is active, customer-facing, or incident-prone:

```bash
# .git/hooks/pre-commit (or via husky / lefthook / pre-commit)
#!/usr/bin/env bash
set -e

# Find changed billing-touching files
CHANGED=$(git diff --cached --name-only --diff-filter=ACM)
BILLING_CHANGED=$(echo "$CHANGED" | grep -E '(stripe|paypal|webhook|subscription|payment|billing)' || true)

if [[ -z "$BILLING_CHANGED" ]]; then
  exit 0  # No billing changes; skip
fi

echo "Running billing pre-commit checks on:"
echo "$BILLING_CHANGED" | sed 's/^/  /'

# Check 1: No NEXT_PUBLIC_*_SECRET / *_KEY exposure
if echo "$BILLING_CHANGED" | xargs grep -l 'NEXT_PUBLIC_.*\(SECRET\|TOKEN\|WEBHOOK\)' 2>/dev/null; then
  echo "NEXT_PUBLIC_* exposes a secret-class env var. See B20 § secret custody."
  exit 1
fi

# Check 2: No hardcoded sk_live_* / sk_test_* / whsec_*
if echo "$BILLING_CHANGED" | xargs grep -l 'sk_live_\|sk_test_\|whsec_[a-zA-Z0-9]\{20\}' 2>/dev/null; then
  echo "Hardcoded Stripe key or webhook secret found. Never commit these."
  exit 1
fi

# Check 3: type-check the billing files
yarn tsc --noEmit $(echo "$BILLING_CHANGED" | tr '\n' ' ') || exit 1

# Check 4: run drift-guards
yarn test --testPathPattern='__tests__/(billing|drift-guard)/' || exit 1

# Check 5: 200-on-error audit
./scripts/audit-webhook-200-on-error.sh . || exit 1

# Check 6: staleness guard audit
node ./scripts/audit-update-staleness-guards.mjs . || exit 1

echo "Pre-commit billing checks passed."
```

Wire via husky (`.husky/pre-commit`) or a pre-commit framework (`.pre-commit-config.yaml`).

---

## Full per-PR CI example

The summary workflow above is intentionally compact. This fuller version includes runtime setup, explicit services, and a UBS check for changed webhook Rust/TypeScript-adjacent surfaces where your project supports it:

```yaml
# .github/workflows/billing-ci.yml
name: Billing CI

on:
  pull_request:
    paths:
      - 'src/lib/webhooks/**'
      - 'src/lib/services/subscription.ts'
      - 'src/lib/services/dunning.ts'
      - 'src/lib/services/team-billing.ts'
      - 'src/app/api/stripe/**'
      - 'src/app/api/paypal/**'
      - 'src/app/api/cron/**'
      - 'src/db/schema.ts'
      - 'supabase/migrations/**'
      - 'src/env.ts'
      - 'src/lib/constants/**'

jobs:
  drift-guards:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
      - run: yarn install --frozen-lockfile
      - run: yarn test --testPathPattern='__tests__/drift-guard/' --ci

  static-analysis:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: ./scripts/audit-webhook-200-on-error.sh .
      - run: node ./scripts/audit-update-staleness-guards.mjs .
      - run: ./scripts/audit-cron-locks.sh .
      - run: node ./scripts/audit-exclusions-coverage.mjs .

  integration-tests:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16
        env:
          POSTGRES_PASSWORD: test
          POSTGRES_DB: billing_test
        ports: ['5432:5432']
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
    env:
      DATABASE_URL: postgres://postgres:test@localhost:5432/billing_test
      STRIPE_SECRET_KEY: ${{ secrets.STRIPE_TEST_SECRET_KEY }}
      STRIPE_WEBHOOK_SECRET: ${{ secrets.STRIPE_TEST_WEBHOOK_SECRET }}
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
      - run: yarn install --frozen-lockfile
      - run: yarn drizzle-kit migrate
      - run: yarn test --testPathPattern='__tests__/billing/' --ci

  detect-billing-mocks:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: ./scripts/detect-billing-mocks.sh

  ubs:
    runs-on: ubuntu-latest
    if: contains(github.event.pull_request.changed_files.*.filename, 'src/lib/webhooks/')
    steps:
      - uses: actions/checkout@v4
      - run: ubs $(git diff --name-only origin/main HEAD -- src/lib/webhooks/)
```

All jobs must pass for the PR to merge.

---

## Expanded CODEOWNERS template

```
# .github/CODEOWNERS

# Billing core — requires senior approval
src/lib/webhooks/                  @billing-team @senior-engineers
src/lib/services/subscription.ts   @billing-team @senior-engineers
src/lib/services/dunning.ts        @billing-team
src/lib/services/team-billing.ts   @billing-team @senior-engineers
src/app/api/stripe/                @billing-team @senior-engineers
src/app/api/paypal/                @billing-team @senior-engineers
src/app/api/cron/                  @billing-team
src/db/schema.ts                   @billing-team @senior-engineers @database-team
supabase/migrations/               @billing-team @senior-engineers @database-team
src/lib/constants/business.ts      @billing-team @product
src/lib/constants/stripe-config.ts @billing-team @senior-engineers
src/env.ts                         @senior-engineers @sre
```

Branch protection should require reviews from CODEOWNERS for billing-touching PRs.

---

## Full pre-deploy gate

Before promoting a build to production:

```yaml
# .github/workflows/billing-pre-deploy.yml
name: Billing Pre-Deploy Verification

on:
  push:
    branches: [main]
  workflow_dispatch:

jobs:
  pre-deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      # Verify build secrets are intact
      - run: ./scripts/audit-bundle-leakage.sh .

      # Verify provider state hasn't drifted (read-only)
      - env:
          STRIPE_SECRET_KEY: ${{ secrets.STRIPE_AUDIT_KEY }}
        run: ./scripts/audit-stripe-event-coverage.sh .

      # Verify env scope is correct
      - env:
          VERCEL_TOKEN: ${{ secrets.VERCEL_TOKEN }}
        run: ./scripts/audit-vercel-env.sh .

      # Verify integration tests pass against staging DB
      - env:
          DATABASE_URL: ${{ secrets.STAGING_DATABASE_URL }}
        run: yarn test --testPathPattern='__tests__/billing/' --ci

      # ALL must pass before promote
      - run: echo "Pre-deploy gate passed; safe to promote."
```

If any fail, the deploy is blocked. No override without manual sign-off.

---

## Claude Code hooks (per `/cc-hooks`)

For developer machines with Claude Code installed, configure hooks in `~/.claude/settings.json`:

```json
{
  "hooks": [
    {
      "event": "PreToolUse",
      "matcher": "Bash",
      "command": "if echo \"$CLAUDE_TOOL_INPUT_command\" | grep -E 'git push|git reset --hard|rm -rf|DROP TABLE'; then echo 'Destructive billing-context command; ask user' >&2; exit 1; fi"
    },
    {
      "event": "PostToolUse",
      "matcher": "Edit",
      "command": "if echo \"$CLAUDE_TOOL_INPUT_file_path\" | grep -E '(stripe|paypal|webhook|subscription)/'; then echo 'Billing file edited. Run drift-guards before committing.' >&2; fi"
    }
  ]
}
```

This makes Claude Code aware that billing context demands extra caution.

---

## Destructive Command Guard for billing

Per `/dcg` skill: configure dcg to block destructive commands in billing-context directories:

```bash
# In dcg config
[contexts]
billing = "src/lib/webhooks/|src/lib/services/(subscription|dunning|team-billing)|src/app/api/(stripe|paypal|cron)|src/db/schema.ts|supabase/migrations/"

[blocks]
destructive_in_billing = "(rm -rf|git reset --hard|git clean -fd|TRUNCATE|DROP)"
```

Any command matching `destructive_in_billing` while the working context touches billing is blocked. User override must be explicit and auditable.

---

## Per-PR provider-catalog audit

For teams with a read-only Stripe API key in CI:

```yaml
# .github/workflows/billing-provider-audit.yml
name: Provider Catalog Audit (PR)

on:
  pull_request:
    paths:
      - 'src/lib/constants/business.ts'
      - 'src/lib/constants/stripe-config.ts'

jobs:
  audit:
    runs-on: ubuntu-latest
    env:
      STRIPE_SECRET_KEY: ${{ secrets.STRIPE_AUDIT_KEY }}
    steps:
      - uses: actions/checkout@v4
      - run: ./scripts/provider-diagnostics.sh > .billing_workspace/provider_audit.md
      - run: |
          if grep -q '"valid_count": 0' .billing_workspace/provider_audit.md; then
            echo "No active coupons (matches BUSINESS policy)"
          else
            echo "Active coupons detected; PR must explain"
            exit 1
          fi
```

This catches "engineer accidentally created a Stripe coupon to test" before merge.

---

## Block billing changes during release freeze

If your team has a release freeze period, such as before a SOC2 audit or during peak season:

```yaml
# .github/branch-protection-rules
required-status-checks:
  - billing-ci
  - drift-guards
  - integration-tests
  - detect-billing-mocks

restrict-pushes:
  - paths:
      - 'src/lib/webhooks/**'
      - 'src/db/schema.ts'
    during:
      - 2026-12-15 to 2027-01-05  # holiday freeze
      - 2026-09-01 to 2026-09-15  # SOC2 audit window
```

Combined with CODEOWNERS, billing changes during freeze require explicit override.

---

## Hooks for incident response

When an incident is open, enable extra-strict hooks:

```bash
# Open an incident bead
br create --title "P0: triple-charge incident" --type incident --priority 0
INCIDENT_BEAD=$(br list --json | jq -r '.[] | select(.title=="...") | .id')

# Set CC hook to enforce extra discipline during incident
echo '{"hooks": [{"event": "PreToolUse", "matcher": "Edit", "command": "echo Active incident bead: '"$INCIDENT_BEAD"'. Document this change in the postmortem."}]}' >> ~/.claude/settings.json

# Resolve incident
br close $INCIDENT_BEAD --reason "..."
# Remove the hook
```

Forces every edit during the incident to be intentionally documented.

---

## Hook performance + reliability

Hooks must be fast. Slow hooks get disabled.

| Hook | Target latency |
|------|----------------|
| Pre-commit | < 5 seconds |
| CI per-job | < 5 minutes |
| Pre-deploy gate | < 10 minutes |
| Daily audit | < 1 hour |

If hooks exceed budget, profile and optimize. Never let hooks become routinely skipped.

---

## Hook bypass audit

Some hooks support `--no-verify` (git pre-commit). Audit who uses it:

```bash
# In CI: scan recent commits for evidence of bypass
git log --pretty=fuller --since='7 days ago' \
  | grep -E '(no.verify|skip.ci|bypass)'  # log warnings
```

Bypass should be rare and documented. More than one bypass per week per engineer is a process problem.

---

## Common hooks integration mistakes

- **No pre-commit hooks.** Bugs reach CI; CI catches; cycle wasted.
- **Hooks too slow.** Engineers disable; bugs reach CI anyway.
- **No CI integration test for billing.** Regressions caught in production.
- **No CODEOWNERS.** Anyone can merge billing changes; mistakes happen.
- **No pre-deploy gate.** Drift between code and production state.
- **Daily audit silent on drift.** Drift accumulates and is discovered during compliance review.
- **Bypass too easy.** Hooks become advisory rather than enforcing.
- **Hooks block legitimate work.** Engineers learn to work around them; this defeats the point.
- **No hook performance budget.** Hooks grow indefinitely; eventually unusable.
- **Incident-time hooks left enabled.** Long after incident, hooks slow normal work.

---

## Integration with existing methodology

- `references/methodology/POLISH-BAR.md` defines the dimensions; hooks enforce them.
- `references/methodology/PHASES.md` Phase 7 fresh-eyes is what hooks scale — every commit gets some Phase 7 lens via the hook.
- `references/patterns/110-OPERATIONS.md § Drift-guard tests` defines the tests; hooks run them.
- `references/patterns/120-COMPLIANCE-EVIDENCE.md` captures what hooks produce for compliance.

The hooks are the operational tooth that gives the patterns bite.
