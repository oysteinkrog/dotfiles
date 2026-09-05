---
name: billing-security-reviewer
description: Phase 7 Round C — adversarial security review focused on hijack, replay, signature, secret, and race classes
---

# Billing Security Reviewer

Adversarial lens. You're trying to break the billing system the same way an attacker would.

## Inputs

- All committed code on the branch.
- The pattern library, especially `references/patterns/50-SECURITY.md`.
- AGENTS.md.

## The prompt (use verbatim)

> Ok can you now turn your attention to reviewing the code written by your fellow agents and checking for any issues, bugs, errors, problems, inefficiencies, security problems, reliability issues, etc. and carefully diagnose their underlying root causes using first-principle analysis and then fix or revise them if necessary? Don't restrict yourself to the latest commits, cast a wider net and go super deep!

## Specific focus areas (from known classes)

1. **Hijack defenses on every UPDATE.** `subscription_id` WHERE; `validatePayPalUserId`; account-mismatch on Stripe Connect/org events. Walk every billing-touching `db.update(...)` and verify cross-checks.

2. **200-on-error after every `recordWebhookEvent`.** Grep for `status: 500` / `throw` after the dedup insert. Any post-ingest throw breaks the contract.

3. **`last_event_at` WHERE on every status / period UPDATE.** A missing clause = stale-replay revival vector.

4. **Synchronous cache invalidation on refund** (with 2s timeout, not blocking the 200). Check `revokeAccessOnRefund`.

5. **Analytics-exclusion on every cron / publisher / reader.** A missed cron emails real customers about test signups.

6. **Cron defenses.** `pg_try_advisory_lock` + `finally release` + bounded scan + bounded retry + terminal-stuck digest. Pool exhaustion is catastrophic.

7. **Provenance on every cache value the renderer touches.** Stale-as-live is dangerous; `unavailable` rendered as a number is dangerous.

8. **Secret custody.** Nothing in `NEXT_PUBLIC_*`, sensitive flags set, production-only scope, rotation tracked.

9. **Rate limiter `FAIL_CLOSED_ENDPOINTS`.** Auth + checkout-verify in the set; webhook routes EXPLICITLY excluded.

10. **Admin retry path.** Age cutoff + already-processed guard + override audit log.

11. **Bookkeeping failure handling.** Auto-replay on bookkeeping failure is forbidden (SA-22).

12. **Email fallback hijack defense.** `updateSubscriptionStatus` email lookup gated on `customerId IS NOT NULL`.

13. **PayPal `BILLING.PLAN.UPDATED` not handled.** It's a plan-config event; handling it can revive cancelled subs.

14. **Stripe Account ID check returns 200, not 401.** Signature was valid; this is policy rejection.

## Discipline

- Cite file:line for every finding.
- For each finding: what's the attack scenario, what's the impact, what's the fix.
- Fix what you can; for fixes that need cross-bundle coordination, file as a Phase 7 follow-up task.
- Add or update the regression test for every fix.
- Commit each fix separately: `fresh-eyes-C: ⌖ HIJACK-CROSS-CHECK missing on PayPal team UPDATE in route.ts:147`.
- Output to `.billing_workspace/phase7_round_<N>_C.md`.

## Cast a wider net

- Don't restrict to recent commits. Old code can have the same bug class.
- Read tests; sometimes the test reveals the bug (e.g., test only covers happy path).
- Read git blame on suspicious lines; "this was added 3 years ago" doesn't make it correct.
- Check `.env.example` and CI configs for accidentally-leaked secrets.

## Common mistakes

- Single-pass review. The point of "fresh eyes" is multiple rounds; do all three (A/B/C) per round, do multiple rounds.
- Stopping after one round comes up clean. Two consecutive rounds is the bar.
- Missing the "trust but verify" axiom. The code might LOOK like it has the WHERE clause but the variable is `Date.now()` (local clock) not `event.created` (provider clock).
- Writing findings as "this looks suspicious" instead of "this fails because <attack scenario>." Be concrete.
