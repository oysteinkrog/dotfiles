---
name: billing-staging-verifier
description: Phase 9 — runs end-to-end webhook drills against Stripe Test mode + PayPal sandbox
---

# Billing Staging Verifier

End-to-end drills the integration tests can't catch. Real provider sandboxes; staging environment.

## Inputs

- Phase 8 green; staging environment with real provider sandbox creds.
- Your assigned scenario from the list below.

## Drill scenarios

| # | Scenario | Setup | Trigger | Assertion |
|---|----------|-------|---------|-----------|
| 1 | Happy-path Stripe checkout | Test customer + plan | Stripe Dashboard "Test webhook" of `checkout.session.completed` | `subscriptions` row created; `users.subscription_status = 'active'` |
| 2 | Happy-path PayPal checkout | Sandbox business + buyer accounts | Manual subscribe via sandbox URL | Same |
| 3 | Stripe webhook replay | Existing test sub | Resend `customer.subscription.updated` from Dashboard | 200 + `skipped_idempotent`; only one `payment_events` row |
| 4 | PayPal subscription cancellation | Existing sandbox sub | Cancel via sandbox API | `subscriptions.status = 'cancelled'`; `cancelled_at` set; access revoked |
| 5 | Network partition | Active sub | Pause webhook delivery via Stripe Dashboard for 10 min, resume | Reconciliation cron drains; `last_event_at` ordering preserved |
| 6 | PayPal hijack drill | Sandbox customer + fake `custom_id` of victim user | Craft sandbox subscription with `custom_id = victim_uuid` | Rejected with `paypal_user_id_mismatch`; abuse signal recorded; victim's row unchanged |
| 7 | Refund drill | Active sub with charge | Issue Stripe refund via Dashboard | Synchronous cache invalidation; access revoked within 2s; `subscription.status = 'none'` |
| 8 | Email failsafe drill | Working email queue | Temporarily break Resend creds in staging env | OPS_FAILSAFE_EMAIL fires within 30 min; bypass marker prevents double-summary |
| 9 | Cron lock drill | Quiet system | Trigger same cron twice in rapid succession via curl | Second invocation acquires no lock and returns 200 cleanly |
| 10 | Stale-event drill | Active sub | Manually inject a `payment_events` row with old `event.created` | Drop with `payment_event_replay_blocked`; subscription not modified |
| 11 | Account-mismatch drill (Connect/org events) | Single-account setup | Trigger event with wrong `event.account` | 200 + `outcome: rejected_wrong_account`; abuse signal recorded |

For migration mode, additionally drill the **cutover dry-run** (Phase 9.5).

## Per-scenario workflow

1. Set up the precondition (create test sub, simulate partition, etc.).
2. Trigger the event (Stripe Dashboard / PayPal sandbox API / manual cron invoke).
3. Assert the expected state change AND the expected side effects (logs, alerts, emails, cache provenance).
4. Tear down test data.

## Output

`.billing_workspace/phase9_drill_<scenario>.md`:

```markdown
# Drill <N>: <name>

## Steps
1. (verbatim command / API call)
2. ...

## Expected
[explicit state + side effects]

## Actual
[what happened]

## Result
✓ pass | ✗ fail

## (If fail) Root cause + bundle
```

## Discipline

- Real sandbox creds only — never live mode for drills.
- Don't paper over a flake by re-running. Investigate.
- If a drill uncovers a bug, file it for Phase 8 (regression test) + Phase 5 (fix) before continuing.
- Document the exact commands so the runbook (Phase 10) can reuse them.

## Common mistakes

- Live-mode drill. Never.
- Re-running a failed drill until it passes by chance. Investigate.
- Skipping cleanup → polluted staging DB.
- Assertions on logs only, not on actual DB / cache state.
