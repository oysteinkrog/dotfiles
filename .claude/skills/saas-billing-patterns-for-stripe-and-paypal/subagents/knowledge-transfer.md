---
name: billing-knowledge-transfer
description: Onboards new engineers per ONBOARDING-NEW-ENGINEERS.md — 4-week curriculum, trust ladder, buddy system
---

# Billing Knowledge Transfer

For team leads onboarding a new engineer to the billing system. Per `ONBOARDING-NEW-ENGINEERS.md`.

## Inputs

- New engineer's name + role + start date.
- Current billing system state (which tier, which bundles in use).
- Available L4+ engineer to be the buddy.

## Output

- Personalized 4-week curriculum.
- Initial trust level assignment (L0).
- Buddy pairing.
- Weekly check-in schedule.
- Specific reading list per week.
- Specific exercises per week.
- Specific PR-review pairing per week.

## Procedure

### Week 1 plan

```
Reading list (in order):
1. references/patterns/00-NORTH-STAR.md (3 readings; should memorize)
2. The architecture diagram (whiteboard exercise)
3. references/methodology/OPERATORS.md (flashcards)
4. references/patterns/145-EXTENDED-FAILURE-CATALOG.md (recognition exercises)
5. references/source/BEAD-DICTIONARY.md (naming awareness)

Exercises:
- Day 3: Whiteboard the architecture diagram from memory.
- Day 4: Quiz — given 5 random failure-class IDs, narrate symptom + root cause + fix.
- Day 5: Code-snippet operator quiz.

Deliverable end of Week 1: 1-page personal note "what I learned about billing."
Reviewed by: buddy.
```

### Week 2 plan

```
Reading list:
1. references/patterns/00-NORTH-STAR.md → 145 (every bundle, in order)
2. src/lib/webhooks/inbound.ts (line by line)
3. src/lib/services/subscription.ts (line by line)
4. src/app/api/{stripe,paypal}/webhook/route.ts (line by line)
5. ONE complete cron handler (line by line)

Exercises:
- Trace a customer lifecycle (signup → checkout → renewal → cancel).
- Identify every Polish Bar dimension in `updateSubscriptionStatus`.
- Find one subtle bug (planted or genuine; buddy verifies).

Deliverable end of Week 2: 3-page architecture write-up.
Reviewed by: senior engineer + buddy.
```

### Week 3 plan

```
Suitable starter PRs (low-risk):
- Add missing Polish Bar regression test for an existing pattern.
- Add a missing operator mention to a pattern doc.
- Add a runbook for an alarm without one.
- Add a fixture to the adversarial corpus.

Forbidden tasks (Week 3):
- Webhook handler changes.
- Schema migrations.
- Cron handler changes.
- updateSubscriptionStatus modifications.
- Anything touching money.

Process:
- Pair with senior on every PR.
- Phase 7 fresh-eyes runs on the new engineer's PRs.
- Review post-mortem of any incidents in the new engineer's PR area.

Deliverable end of Week 3: First merged PR.
```

### Week 4 plan

```
Suitable independent PRs (still low-risk):
- New pattern bundle (if needed).
- Implement a non-critical drift-guard.
- Refactor a non-billing utility imported by billing.

On-call shadow:
- Shadow on-call for 1 week (no primary responsibility).
- Read every alarm; identify class.
- Help triage 1 real customer ticket (mentor present).

Deliverable end of Week 4:
- Independent PR with genuine value.
- 1-page "what I'd want a future new engineer to know" reflection.
- Trust ladder promotion to L1.
```

## Trust ladder progression

| Level | Trust | When |
|-------|-------|------|
| L0 | New | Week 1 |
| L1 | Onboarded | End of Week 4 |
| L2 | Pairing-required | Month 2-3 (with L4+ pair) |
| L3 | Reviewer-required | Month 3-6 (with L4+ reviewer) |
| L4 | Trusted | 6+ months; can approve |
| L5 | Steward | 1+ year; can modify patterns + mentor |

## Discipline

- Don't skip the curriculum because "deadline pressure."
- Don't promote to L4 in Month 6 unless they've genuinely achieved L4 quality.
- Buddy time is paid engineering investment, not overhead.
- Slow down if any red flag (per ONBOARDING-NEW-ENGINEERS.md § Red flags).

## Common pitfalls

- Sink-or-swim onboarding → incident in Week 2.
- No buddy → new engineer guesses.
- No on-call shadow → first time is a real Sev1.
- Premature promotion → class-of-bug incidents.
- No retro on incidents in onboarding → same mistakes recur.

## Integration

- Engineering manager runs this when new engineer joins.
- Coordinates with senior engineer (acts as buddy).
- Outputs feed into engineering performance review.
- Updates `docs/onboarding/billing/` artifacts based on what the new engineer's experience reveals.
