# Incident Response Playbook

This is the framework `harden-incident` mode operates inside. The goal: a billing incident becomes regression test + alarm + pattern bundle entry, not just a fixed bug.

---

## The five phases of a billing incident

```
1. DETECTION  → How did we learn? (alarm vs. customer ticket vs. self-discovery)
2. CONTAINMENT → Stop the bleed (suspend cron, rotate key, manually fix N rows)
3. INVESTIGATION → Root cause via 5-whys + code reading
4. REMEDIATION → Code fix + regression test + drift-guard
5. POSTMORTEM → Document; share; pattern-library entry
```

Match each phase to a workspace artifact. If you skip any phase, the incident class will recur.

---

## Phase 1 — Detection

### Who detected? Severity classification

| Source | Severity floor | Reason |
|--------|----------------|--------|
| Customer support ticket | High (≥7) | We failed to detect ourselves |
| Operator manual audit | Medium (5-6) | Detection works partially |
| Active alarm fired | Medium-High (6-8) | Detection works; question is response time |
| Code review caught before deploy | Low (3-4) | Detection works pre-prod |
| Drift-guard test caught in CI | Low (3) | Drift detection works |

Always attach a numeric severity (per RISK-SCORING.md) and capture the detection source.

### Time markers

Record exact timestamps in `phase0_incident_brief.md`:
- T0 — first occurrence (provider clock if known; estimated from logs otherwise)
- T1 — first customer-affected occurrence
- T2 — first internal detection
- T3 — first response action
- T4 — bleeding stopped
- T5 — fix deployed
- T6 — verification (no recurrence in 24h)

---

## Phase 2 — Containment

The "stop the bleed" decision tree:

```
Is the incident actively producing customer harm RIGHT NOW?
├─ YES → CONTAIN before investigating
│  ├─ Charge-related → suspend the relevant Stripe webhook? (only if you can replay later)
│  ├─ Email-related  → pause the cron via dashboard / env-var-flip
│  ├─ Auth-related   → flip a kill-switch flag
│  └─ Data-corruption → revert the offending migration if recent; otherwise paper-fix N rows
└─ NO  → investigate first; containment may be unnecessary
```

### Containment moves library

| Symptom | Containment move | Reversibility |
|---------|------------------|---------------|
| Triple-charge class | Manually refund affected customers via Stripe Dashboard (NOT API); cancel duplicate subs via Dashboard | Reversible (refunds can be issued) |
| Hijack class | Revoke the attacker's PayPal subscription via Dashboard; do NOT cancel webhook (need it for evidence) | Irreversible — but contains attacker |
| Webhook-storm class | Add `STRIPE_ACCOUNT_ID` check or temporarily reject events not from your account | Reversible (revert env change) |
| Replay-revival class | Manually reset state for affected rows; gate the broken handler behind a feature flag | Reversible |
| Email-storm class | Pause the cron via vercel.json crons config; clear DLQ rows that should not retry | Reversible |
| Cron pool exhaustion | Restart the affected service; add a temporary connection-limit env var | Reversible |
| Secret leak class | ROTATE THE LEAKED SECRET IMMEDIATELY (Stripe Dashboard / PayPal Dashboard / Vercel env); do NOT wait for the postmortem | Irreversible (correct response) |

**Rule:** containment moves should be reversible. Irreversible moves require user authorization.

---

## Phase 3 — Investigation (5 whys + code reading)

### The 5-whys template

```
Symptom (user-visible): <what the customer experienced>

Why 1 (proximate cause in code): <which code path failed>
Why 2 (architectural cause): <which invariant was missing>
Why 3 (process cause): <how did this code reach production?>
Why 4 (detection cause): <why didn't an alarm fire?>
Why 5 (institutional cause): <why didn't an earlier postmortem catch this class?>
```

Stop at the level where the answer becomes "we made an explicit choice." If you reach "we have no postmortem culture," the incident is bigger than this fix.

### Code-reading discipline

For EVERY incident:
1. Read the failing handler/cron/route TOP TO BOTTOM. Don't trust the partial view.
2. Read the test file (if any). Often the bug is "test only covered happy path."
3. `git blame` the failing line. The previous fix in that area is often the culprit.
4. Read the bead trail (if `br` is in use) for the area. You're often re-discovering a known issue.
5. Search the source guide § Failure-mode catalog (`110-OPERATIONS.md § 72`) — your incident likely matches one of the 38 documented classes.

### Symptom → likely failure-mode class

Quick-lookup table for common symptoms:

| Symptom | Likely class | First place to check |
|---------|--------------|----------------------|
| Customer charged 2-3 times for one subscription | Triple-charge (`bd-1m86f`) | Cross-provider duplicate-sub guard; customer reuse |
| User upgraded for free without paying | Hijack (PayPal individual or team, or Stripe Connect account-mismatch) | `validatePayPalUserId`, `subscription_id` in WHERE, `STRIPE_ACCOUNT_ID` check |
| User's subscription "came back" after cancellation | Stale-event replay revival | `last_event_at` WHERE clause; reconcile-cancelled-orgs guard |
| User refunded but still has access | Synchronous cache invalidation missing (SA-02) | `revokeAccessOnRefund` cache invalidation path |
| Past-due user never got dunning email | `wasEmailDeliveredSince` checking `queued` instead of `sent` | dunning service email-dedup logic |
| Newsletter got sent but refund alert sat in queue | Email priority not set | `inferEmailJobPriority` for the email type |
| Activity feed shows test signups | Analytics exclusion missing on a publisher | New publisher's path through admin events |
| MRR card shows $0 during outage | Cache returned stale 0 instead of `unavailable` | `getCurrentMrrSnapshot` provenance handling |
| Cron stopped finishing | Pool exhaustion from missing `finally release` OR unbounded scan | The failing cron's lock-release path |
| Webhook fires but state never updates | Handler throwing → cron reconciling but with same bug | Handler exception path; check 200-on-error |
| Deleted user keeps getting billed | Orphan-cancel queue missing or not draining | `orphan_subscription_cancels` table + retry cron |

---

## Phase 4 — Remediation

### The fix MUST include all five:

1. **Code fix** — the smallest change that closes the failure mode.
2. **Regression test** — pinned to the bead/incident name; covers BOTH happy and the adversarial case.
3. **Drift-guard** — if the failure was an implicit invariant, add a CI test that asserts the invariant.
4. **Alarm** — if the failure took longer to detect than acceptable, wire a real-time alarm.
5. **Documentation** — pattern bundle entry (in `references/patterns/`) AND runbook entry.

If any of these five is missing, the incident is "fixed" but the class will recur.

### Fix sequence (for the implementer)

1. Reproduce the bug locally against the broken code (write the regression test first).
2. Confirm the test fails red.
3. Apply the smallest change that satisfies the test.
4. Confirm the test fails red on the broken code AND passes green on the fix.
5. Run the full test suite + linters.
6. Run Phase 7 fresh-eyes on the fix (mandatory; under-pressure code is bug-prone).
7. Commit with message naming the incident: `harden-incident: fix triple-charge class (incident-2026-05-04)`.

---

## Phase 5 — Postmortem

### The postmortem template

Write to `.billing_workspace/phase10_postmortem.md` (or `<project>/docs/postmortems/<date>-<short-name>.md` if the user has a postmortems convention).

```markdown
# Postmortem: <short name>

## Summary
- **Detected:** <timestamp> via <source>
- **Contained:** <timestamp> by <action>
- **Resolved:** <timestamp> by <commit hash>
- **Severity:** <P0|P1|P2|P3>
- **Customer impact:** <count of users affected; $$ refunds issued; trust impact>
- **Failure-mode class:** <e.g., Triple-charge (`bd-1m86f`)>

## What happened (timeline)
- T0 (yyyy-mm-dd hh:mm UTC): ...
- T1 ...
- T2 (detection): ...
- T3 (response started): ...
- T4 (bleeding stopped): ...
- T5 (fix deployed): ...
- T6 (verification, no recurrence in 24h): ...

## What we expected
[The intended behavior. Cite the pattern bundle / Polish Bar dimension that was supposed to enforce this.]

## Root cause (5 whys)
1. (proximate code) ...
2. (architectural) ...
3. (process) ...
4. (detection) ...
5. (institutional) ...

## Fix
- **Commit:** <sha> — <message>
- **Files touched:** <list>
- **Pattern bundle updated:** <e.g., references/patterns/40-WEBHOOKS.md § XYZ>
- **Regression test:** <test name>
- **Drift-guard added:** <test name | n/a>

## What we'll detect next time
- **New alarm:** <name + condition + paging policy>
- **New runbook:** <docs/runbooks/<name>.md>

## Customer communication
- [Did we proactively notify? When? Via what channel?]
- [Did we issue refunds? On what timeline?]
- [Public communication if any?]

## Action items
- [ ] <item> — owner: <name> — due: <date>
- [ ] ...

## Lessons learned (1-3 sentences for the team)
[Specific, action-oriented. NOT "we should be more careful." DO say "we should add account-mismatch checks to all webhook routes that may receive Connect events."]
```

### Sharing the postmortem

- Internal: post to engineering channel, link in the bead, add to the team's postmortem index.
- Customer-facing: if customer impact was visible, write a sanitized public postmortem (refund'd customers get a personal email; broader impact gets a status-page note).
- Industry: if it was a novel failure class, consider sharing on engineering blogs / X — but only after coordinating with the user.

---

## Postmortem culture rules

These are non-negotiable for the team operating this skill:

1. **Blameless.** Postmortems name bugs, not engineers. The right question is "how did our system allow this engineer to make this mistake?"
2. **Action items have owners + due dates.** A list of action items without owners is a wish list.
3. **Action items get tracked.** Use beads / GitHub issues / equivalent. The follow-through is the postmortem; the document alone is not.
4. **Read past postmortems before writing a new one.** Recurring classes signal the action items from past postmortems were not followed through.
5. **Time-bounded.** Write the postmortem within 1 week of the incident. Older postmortems become memoirs, not documents.

---

## Common mistakes

- **Writing the postmortem during containment.** No. Contain first; investigate; then document.
- **Skipping the regression test.** "We fixed it; no need to test now." Wrong; write the test first, then the fix, so the test pins the contract.
- **Action items without owners.** Wish list, not plan.
- **5-whys that stop at "the engineer didn't read AGENTS.md."** Why didn't they? Was AGENTS.md not enforced in code review? Is there a pre-commit hook? The institutional why matters.
- **Postmortem becomes a finger-pointing document.** Re-write blamelessly. Focus on system, not person.
- **Skipping Phase 7 fresh-eyes "because it's a small fix."** The smallest fix under incident pressure is the most likely to introduce a NEW bug.
- **Not surfacing the new pattern to the pattern library.** A novel incident class that's not in the bundles will be re-encountered by future agents using this skill.

---

## When the incident is bigger than the fix

Some incidents reveal that the system needs more than a code fix:

- **Pattern is missing from the pattern library** → file PR against this skill.
- **Operator is missing from OPERATORS.md** → propose a new operator with trigger + failure-mode + prompt module.
- **Class is missing from the failure-mode catalog** → add row to `110-OPERATIONS.md § 72`.
- **Bundle is missing from the skill** → propose adding a new bundle (rare, but happens — e.g., adding B55 Observability bundle after a Prometheus-alert-class incident).

In those cases, the postmortem includes a "skill expansion" action item with a PR link.
