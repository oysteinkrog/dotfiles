# Decision Matrix (Generic — Customize Per Project During Onboarding)

This is the starter matrix. The onboarding pass writes a project-specific override into `<project>/.claude/support-triage/03-decision-matrix.md`, which takes precedence.

## Universal Categories

| User signal | Category | Action | Template |
|---|---|---|---|
| Vague / "X is broken" with no detail | NEED-INFO | Ask for repro, version, error output | REQUEST-INFO |
| Install fails (any OS) | INSTALL-FAIL | Verify across OS, request env details | INSTALL-FAIL |
| Login / auth fails | AUTH-FAIL | Check token / session / migration state | AUTH-FAIL |
| 5xx error | SERVER-ERROR | `curl` the endpoint; check Sentry / logs; check deploy status | SERVER-ERROR |
| 429 / rate-limit on paid user | TIER-MISMATCH | Verify entitlement; check limiter logic | RATE-LIMIT |
| "I paid but no access" | BILLING-DISCREPANCY | Check `payment_events` table / provider dashboard | BILLING |
| Refund request | REFUND | Owner approval required; follow refund SOP | REFUND |
| Subscription cancelled but charged | BILLING-DISCREPANCY | Same as above + check provider switch / `customerId` | BILLING |
| Bug confirmed reproducible | CODE-BUG | File bead; fix if quick; deploy; verify | CODE-BUG |
| Bug already fixed / shipped | CODE-FIXED | Confirm version mapping; ask user to upgrade | CODE-FIXED |
| Bug, can't reproduce | CANT-REPRO | Request: exact version, OS, repro steps | REQUEST-INFO |
| Question / how-to | QUESTION | Answer + link to docs; suggest moving to community channel | QUESTION |
| Feature request, sensible | FEATURE-REQUEST | Acknowledge, log to roadmap (no commit) | FEATURE-REQUEST |
| Feature request, scope creep | DECLINE | Polite decline with reasoning | DECLINE-FEATURE |
| Cosmetic / logging / harmless | COSMETIC | Acknowledge; track for cleanup; reassure user it's not affecting them | COSMETIC |
| Infra (DNS, MX, CDN) | INFRA | Diagnose; surface to owner if user-side; track to fix if our-side | INFRA |
| Hostile / abusive user | HOSTILE | Lock or close per project policy; do not engage | (no template) |
| Security report (vuln) | SECURITY | **STOP.** Privately escalate to owner; do not respond publicly | (private) |
| SLA breached | ACK-NOW | Acknowledge immediately (status only); investigate, then full reply | ACKNOWLEDGE |
| Duplicate of N | DUPE | Reference the canonical, close as duplicate | DUPLICATE |
| Stale (180+ days, OSS) | STALE | Close with stale-template comment | STALE |

## Decision Heuristics

### When in doubt, classify NEED-INFO
A bad classification leads to a confidently-wrong reply. NEED-INFO is always safe.

### Always check for shared root cause first
Before classifying ticket #2 individually, ask: does it share a hypothesis with ticket #1? Often the answer is yes. Classify both as the same `CODE-BUG`, fix once.

### Billing tickets are highest-stakes
Always:
- Verify the user's actual subscription state in the provider dashboard, not just the app DB
- Check `customerId` provider — Stripe `cus_*` vs PayPal `payer_id` mismatches are silent
- Search recent `payment_events` for `processedAt IS NULL`
- Refunds always need owner approval; never auto-process

### "We deployed a fix" requires verification
Cross-reference the fix commit timestamp against the production deployment timestamp. Auto-deploy is sometimes off. Vercel's "Latest deployment" timestamp is the ground truth.

### One layer down, one fix more
When you fix one bug during triage, run the user's full scenario one more time. The first fix often unmasks a second.

## Reply-Send Decision

For each classified ticket, pick ONE of:

```
A. ACK-ONLY (no message; stops SLA clock)
   When: SLA breached during initial pull, before owner has reviewed drafts.

B. SEND-DRAFT (after owner approval)
   When: Standard reply path. Always show owner first.

C. INTERNAL-NOTE (no customer message)
   When: We need to log progress for the next agent / owner without messaging the user.

D. ESCALATE-PRIVATELY (no public response)
   When: Security report, hostile user, ambiguous high-stakes situation.

E. WAIT (no action; defer)
   When: Need more research / a deploy / owner decision before responding.
```

## Output Format For Owner Review

When presenting a draft bundle, every item carries this header:

```
[ITEM-12]  classify=BILLING-DISCREPANCY  template=BILLING  send=B (SEND-DRAFT)
           confidence=high   sla=at_risk (4.2h until breach)
           shared root cause:  none / shared with [ITEM-7]
```

Helps owner skim quickly and approve in batches.
