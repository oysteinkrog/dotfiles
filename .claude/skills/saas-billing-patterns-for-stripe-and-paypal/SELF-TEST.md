# Self-Test

## Trigger phrases (should activate this skill)

- "Audit my Stripe webhook code for security issues"
- "We had a duplicate-charge incident — help me harden the billing system"
- "Implement Stripe + PayPal subscriptions in this Next.js project from scratch"
- "Add team plans with seat-based pricing and pause/resume to our billing"
- "Build the MRR / churn / cohort reporting backend for our SaaS"
- "Add a dunning ladder with grace period and SCA routing"
- "Migrate from Lemon Squeezy to dual Stripe + PayPal"
- "Why does our PayPal `subscription.cancelled` handler revive cancelled orgs?"
- "Set up a webhook reconciliation cron with advisory locks"
- "We need to pass SOC2 — audit our billing secret custody"
- "The new admin events feed shows test signups as new subscribers"
- "Add real-DB integration tests for our billing code (no mocks)"
- "Help me design the schema for our subscription billing"
- "Our refund handler doesn't revoke access immediately — fix it"
- "Build a customer health score with churn forecasting"

## Trigger phrases (should NOT activate this skill — adjacent or off-target)

- "Add a payment field to a one-off contact form" — single-payment, no subscription, no provider integration
- "Set up the auth system" — adjacent to billing but not billing itself; should defer to auth/supabase skill
- "Configure Vercel cron for our newsletter" — cron-but-not-billing
- "Generate share images for our pricing page" — UI/marketing
- "Estimate our cloud costs for next year" — finance/forecasting unrelated to billing code
- "Set up NTM for our agents" — generic orchestration; use NTM/swarm skills unless the scope is a T4+ billing run
- "Add pre-commit hooks to every repo" — generic hooks/CI; use hook/CI skills unless billing drift-guards are the ask
- "Write our standard git workflow" — generic repo process; use this skill only for billing traceability overlay
- "Build the SaaS admin dashboard" — generic admin surface; use this skill only for billing admin operations
- "Improve support ticket triage" — generic support workflow; use this skill only when payment/refund/subscription tickets drive the workflow

## Scope-creep regression probes

These prompts should activate the skill but keep optional references dormant unless the stated trigger appears.

| Prompt | Expected scope decision |
|--------|-------------------------|
| "Add an MRR card to admin" | `add-feature`; include B100 and touched admin read path only; skip NTM, migration, marketplace, compliance |
| "Add team plans" | `add-feature`; include B80 plus crossed schema/checkout/webhook/security/state/reliability bundles; skip tax/marketplace unless present |
| "Audit billing for SOC2" | `compliance-pass`; include B120 and evidence-producing bundles; forbid unrelated new features |
| "We had duplicate charges yesterday" | `harden-incident`; fix incident blast radius first, then expand only touched bundles |
| "Run a T2 billing audit" | Solo/Pair/Squad; do not load `NTM-SWARM-ORCHESTRATION.md` |

Validation question for each probe: did the response propose `.billing_workspace/phase0_scope_decision.md` with included bundles, skipped bundles, and a not-doing list? If not, the skill has regressed.

## Smoke test on a tiny project

```bash
# 1. Spin up a throwaway Next.js project
mkdir /tmp/billing-skill-smoke && cd /tmp/billing-skill-smoke
bunx create-next-app@latest . --ts --app --no-tailwind --no-src-dir --no-eslint --no-import-alias --turbopack
echo '{"dependencies":{"stripe":"^14.0.0","drizzle-orm":"^0.30.0"}}' > .billing-fixture.json

# 2. Run discover-stack from this skill
bash scripts/discover-stack.sh /tmp/billing-skill-smoke

# Expected output:
# Framework: next-app-router
# ORM: none (since we didn't actually install drizzle)
# Providers: none (since we didn't add stripe to real package.json)
# Recommended mode: greenfield
```

## Smoke test on this skill itself

```bash
# 1. Verify SKILL.md frontmatter is parseable
head -10 SKILL.md | grep -E '^name:|^description:'

# 2. Verify all referenced patterns exist
for f in references/patterns/*.md; do
  if ! [[ -f "$f" ]]; then
    echo "MISSING: $f"
  fi
done

# 3. Verify all referenced subagents exist
for f in subagents/*.md; do
  if ! [[ -f "$f" ]]; then
    echo "MISSING: $f"
  fi
done

# 4. Verify all referenced methodology refs exist
for f in references/methodology/*.md; do
  if ! [[ -f "$f" ]]; then
    echo "MISSING: $f"
  fi
done

# 5. Verify all scripts are executable
for s in scripts/*.sh scripts/*.mjs; do
  if [[ ! -x "$s" ]]; then
    echo "NOT EXECUTABLE: $s"
  fi
done

# 6. Generate coverage matrix skeleton
node scripts/generate-coverage-matrix.mjs > /tmp/coverage-matrix-test.md
test -s /tmp/coverage-matrix-test.md && echo "OK: matrix skeleton generated" || echo "FAIL: empty matrix"
```

## End-to-end dry-run on a real project (operator validation)

```bash
TARGET=/data/projects/some-saas-project
WORKSPACE="$TARGET/.billing_workspace"
mkdir -p "$WORKSPACE"

# Phase 0
bash scripts/check-skills.sh "$WORKSPACE"
bash scripts/discover-stack.sh "$TARGET"

# Phase 1 (manual: spawn archaeologist subagents per bundle)
# Phase 2 (skeleton)
node scripts/generate-coverage-matrix.mjs > "$WORKSPACE/phase2_coverage_matrix.md"

# Spot audits
node scripts/audit-update-staleness-guards.mjs "$TARGET" > "$WORKSPACE/audit_staleness.json"
bash scripts/audit-webhook-200-on-error.sh "$TARGET" > "$WORKSPACE/audit_200_on_error.txt"
bash scripts/audit-cron-locks.sh "$TARGET" > "$WORKSPACE/audit_cron_locks.txt"
node scripts/audit-exclusions-coverage.mjs "$TARGET" > "$WORKSPACE/audit_exclusions.json"
```

The manual subagent steps (archaeology → coverage → risk → plan → implement → harmonize → fresh-eyes → tests → drills → runbooks) are spawned by the main agent reading this skill's SKILL.md and following the phase loop.

## Validation checklist (when forking / extending this skill)

- [ ] Frontmatter starts at line 1 (no blank line before `---`).
- [ ] Description is third-person and includes "Use when" triggers.
- [ ] SKILL.md body < ~600 lines (this one is intentionally larger; the bulk is in references).
- [ ] Every reference in the SKILL.md exists.
- [ ] Every subagent in the SKILL.md exists.
- [ ] Every script is executable + has a shebang.
- [ ] Source-guide reference path is correct (`COMPREHENSIVE_GUIDE_TO_SAAS_BILLING_PATTERNS_WITH_STRIPE_AND_PAYPAL.md`).
- [ ] No hardcoded `/data/projects/jeffreys-skills.md` references outside source-provenance context; never use it as the target project.
