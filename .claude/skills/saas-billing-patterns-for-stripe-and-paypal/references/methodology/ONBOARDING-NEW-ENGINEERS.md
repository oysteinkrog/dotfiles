# Onboarding New Engineers to a Billing System

> **For team leads.** When a new engineer joins, billing is the highest-stakes-of-anything-they'll-touch system. This file is the curriculum.

A new engineer who modifies billing code without context can introduce class-of-bug incidents within their first week. The cure: structured onboarding before they touch the code.

---

## The 4-week curriculum

### Week 1 — Pattern absorption (no code yet)

**Reading list (in order):**

1. The 16 north-star principles (`references/patterns/00-NORTH-STAR.md`) — read 3 times; they should be memorizable.
2. The architecture diagram — should be able to draw it on a whiteboard from memory by end of Week 1.
3. `references/methodology/OPERATORS.md` — 21 operators; flashcards.
4. `references/patterns/145-EXTENDED-FAILURE-CATALOG.md` — all 38 classes; they should recognize symptoms.
5. The bead dictionary (`references/source/BEAD-DICTIONARY.md`) — naming convention awareness.

**Exercises:**
- Draw the architecture diagram on a whiteboard.
- For 5 random failure classes, narrate: symptom, root cause, fix, regression test name.
- Quiz: given a code snippet, name which operators apply.

**Deliverable:**
- A 1-page personal note: "what I learned about billing this week." No code yet.

### Week 2 — Codebase exploration (read-only)

**Reading list:**

1. The bundle docs in order: B00 → B10 → B20 → ... → B145.
2. The `src/lib/webhooks/inbound.ts` (or equivalent) — line by line.
3. The `src/lib/services/subscription.ts` — line by line.
4. The webhook routes `src/app/api/{stripe,paypal}/webhook/route.ts` — line by line.
5. ONE complete cron handler — line by line.

**Exercises:**
- Trace a customer's lifecycle: signup → checkout → first webhook → first invoice → cancellation.
- Identify every Polish Bar dimension in the canonical writer (`updateSubscriptionStatus`).
- Find one subtle bug in the codebase (intentional plant or genuine; mentor verifies).

**Deliverable:**
- A 3-page write-up: "the architecture as I now understand it." Mentor reviews + corrects.

### Week 3 — First contributions (low-risk)

**Suitable starter tasks:**

- Add a missing Polish Bar regression test for an existing pattern.
- Add a missing operator mention to a pattern doc.
- Add a runbook for an alarm that doesn't have one.
- Add a fixture to the adversarial corpus.
- Refactor a small utility (with mentor pairing).

**NOT suitable starter tasks:**

- Webhook handler changes.
- Schema migrations.
- Cron handler changes.
- Anything in `updateSubscriptionStatus`.
- Anything that touches money.

**Process:**
- Pair with a senior on PR.
- Run Phase 7 fresh-eyes on the new engineer's PR before merging.
- Review post-mortem of any incidents in the engineer's PR area.

### Week 4 — Independent work + on-call shadowing

**Suitable independent tasks:**

- Add a new pattern bundle (if the project's catalog needs one).
- Implement a non-critical drift-guard.
- Refactor a non-billing utility that's imported by billing.

**On-call shadow:**
- Shadow on-call for 1 week.
- Read every alarm that fires; understand which class it indicates.
- Help triage 1 real customer ticket (with mentor present).

**Deliverable:**
- An independent PR that adds genuine value (not busywork).
- A 1-page reflection: "what I'd want a future new engineer to know."

---

## The "billing trust ladder"

| Level | Trust | Allowed |
|-------|-------|---------|
| L0 | New (Week 1) | Read-only |
| L1 | Onboarded (Week 4) | Low-risk PRs (drift-guards, runbooks, fixtures) |
| L2 | Pairing-required (Month 2-3) | Webhook tweaks, schema migrations, cron changes — but ALWAYS paired with L4+ |
| L3 | Reviewer-required (Month 3-6) | Independent PRs, but require L4+ on review |
| L4 | Trusted (6+ months) | Approve PRs of any complexity |
| L5 | Steward (1+ year) | Modify the patterns themselves; design new bundles; mentor new engineers |

Don't give L3 trust before L1 onboarding is complete. Skipping the ladder is how class-of-bug incidents happen.

---

## What every billing engineer must know cold

After onboarding, an engineer should recall WITHOUT reading docs:

- The 16 north-star principles (paraphrased OK; the spirit must be exact).
- The architecture diagram (3-write-paths + 3-alarm-paths).
- The 5-step webhook ingestion contract.
- Why we always return 200 after recordWebhookEvent.
- Why we use `last_event_at` instead of `updated_at`.
- Why pause/resume happens OUTSIDE the DB transaction.
- The hijack defense pattern (validatePayPalUserId + subscription_id WHERE).
- Why we have 3 alarm channels (per-event, stale-pipeline, email failsafe).
- The synchronous-cache-invalidation rule on refunds (with the 2s timeout).
- The Polish Bar dimensions that apply to their daily work.

If they can't, they're not ready for L2 trust.

---

## Knowledge-transfer artifacts

The team should maintain:

1. **A "billing concepts deck"** — 30-slide presentation; given to new engineers in Week 1.
2. **A "code walkthrough video"** — 1 hour; senior engineer narrates the canonical writer + checkout flow.
3. **A "incident postmortem index"** — every postmortem committed to `docs/postmortems/`; new engineer reads all in Week 2.
4. **A "billing FAQ"** — questions team members repeatedly answer; one document; updated as new questions arise.

These artifacts live in `docs/onboarding/billing/` and are updated quarterly.

---

## Buddy system

Pair every new engineer with a "billing buddy" (an L4+ engineer):

- Buddy is on Slack DM ALL hours during Weeks 1-4.
- Buddy reviews every PR during Months 1-3.
- Buddy is the first escalation for any "is this safe?" question.
- After Month 3: buddy graduates new engineer to L3.

Buddy time is paid; track it as engineering investment, not overhead.

---

## On-call readiness check

Before a new engineer joins the on-call rotation:

- [ ] Read every runbook in `docs/runbooks/`.
- [ ] Shadowed 2 weeks of on-call (no primary responsibility).
- [ ] Resolved 1 real Sev2 with a mentor.
- [ ] Knows the escalation paths cold.
- [ ] Has access to all needed tools (admin UI, Stripe Dashboard, PayPal Dashboard, Sentry, etc.).
- [ ] Knows the secret-rotation runbook.
- [ ] Knows where the postmortem template lives.

Skipping any of these → on-call burnout + bad incident handling.

---

## Anti-patterns in onboarding

- **"Sink-or-swim" onboarding.** Throw at billing immediately. Predictable outcome: incident in Week 2.
- **"Documentation is overrated; just read code."** Code without context is noise.
- **No mentor.** New engineer has no one to ask "is this right?"
- **No on-call shadow.** First time on-call is the first real Sev1.
- **Promote to L4 in Month 6 because deadline pressure.** Skipping L2/L3 = class-of-bug incidents.
- **No retro on incidents the new engineer caused.** Same mistakes recur.
- **Onboarding artifacts not maintained.** New engineer reads stale info; learns wrong patterns.

---

## Red flags during onboarding

If you see any of these in Weeks 1-4, slow down and reset:

- New engineer can't draw the architecture diagram by end of Week 1.
- New engineer skips reading and goes straight to coding.
- New engineer's first PR has obvious Polish Bar violations.
- New engineer doesn't ask questions for 3 days straight.
- New engineer commits without buddy review.
- New engineer pushes to main without PR.

Each is a signal to extend onboarding by 1 week.

---

## Quarterly engineering review

Every quarter, the team reviews:

- New incidents per engineer (calibrated by trust level).
- Quality of onboarding artifacts (any stale?).
- Trust-ladder progressions (any premature?).
- Buddy investment (any underutilized?).

Adjust the curriculum based on what's NOT working.

---

## Integration with the skill

- The skill itself is the canonical onboarding curriculum.
- `references/patterns/` is the syllabus.
- `references/methodology/OPERATORS.md` is the flashcard deck.
- `references/patterns/145-EXTENDED-FAILURE-CATALOG.md` is the case-study book.
- `assets/postmortem-template.md` is the artifact format new engineers learn.
- `subagents/knowledge-transfer.md` (if present) is the hands-on guide for pairing.
