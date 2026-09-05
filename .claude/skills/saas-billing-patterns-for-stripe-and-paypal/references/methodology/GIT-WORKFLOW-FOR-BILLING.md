# Git Workflow for Billing Changes

> **Where this comes from.** AGENTS.md + standard git discipline + B45 admin operations + B140 incident response.

Billing changes need stricter git discipline than other changes. The blast radius is too large for the usual "merge to main, ship Friday" cadence.

For generic git practice see your project's existing conventions; this is the BILLING-SPECIFIC overlay that makes incidents traceable months later.

Use this file only when the run needs billing-specific traceability: incident forensics, provider migration, compliance evidence, or a billing PR template. Project AGENTS.md, repository branch policy, and human instructions still outrank this overlay.

---

## Commit message convention

```
<bundle>-<short-tag>: <imperative summary> (bd-<id>)

Refs: <bead/issue ID>
Pattern: references/patterns/<file>.md § <section>
Polish-bar: <dimension that this satisfies>
Regression test: __tests__/<path>
```

Example:

```
B40-staleness: add last_event_at WHERE to PayPal team handlers (bd-2vnz4)

Stale event replays could revive cancelled team orgs. Per pattern bundle
40-WEBHOOKS § replay-staleness gating.

Refs: bd-2vnz4
Pattern: references/patterns/40-WEBHOOKS.md § replay-staleness gating
Polish-bar: Dimension 5 (Stale-event ordering)
Regression test: __tests__/billing/team-stale-event-replay.test.ts
```

The structured trailer means git log filtering is cheap:

```bash
git log --grep "Polish-bar: Dimension 5"
git log --grep "^B40-"
git log --grep "bd-1m86f"
```

---

## Billing PR template

Save as `.github/PULL_REQUEST_TEMPLATE/billing.md`.

```markdown
## Summary
What this PR does.

## Pattern bundles affected
- B40 § replay-staleness gating

## Polish Bar dimensions satisfied
- Dimension 5 (Stale-event ordering)

## Operators applied
- ⏱ STALE-EVENT-GATE
- 🧪 PIN-THE-CONTRACT

## Regression tests added
- `__tests__/billing/team-stale-event-replay.test.ts`

## Drift-guards (if applicable)
- `LastEventAtCoverage.test.ts` updated

## Reviewer checklist
- [ ] No NEXT_PUBLIC_ exposure of secrets
- [ ] No hardcoded keys / webhook secrets
- [ ] AGENTS.md rules respected (no file deletion, no _v2 files, etc.)
- [ ] Polish Bar dimensions verified for touched files
- [ ] Regression tests cover happy + adversarial paths
- [ ] Drift-guards updated if invariants added
- [ ] No mock usage in billing tests (per § 69)
```

---

## Branch naming for billing work

Predictable prefix lets `git branch --list 'billing-*'` find all in-flight work.

```
billing-<mode>-<YYYYMMDD>             ← skill kickoff branch
billing-feature-<short-name>-<YYYYMMDD>
incident-<short-name>-<YYYYMMDD>
billing-greenfield-<YYYYMMDD>
billing-migration-<short-name>-<YYYYMMDD>
billing-cutover-stage-<N>-<YYYYMMDD>
```

---

## Per-PR size discipline (billing-specific)

Billing PRs should be SMALL — Phase 7 fresh-eyes effectiveness drops sharply with PR size.

| PR size | Acceptable? |
|---------|-------------|
| < 200 LOC | ✓ Standard |
| 200-500 LOC | ⚠ Split if possible |
| > 1000 LOC | ✗ Reject (except schema migration + backfill, which can be larger but mostly mechanical) |

Detailed review bands:

| PR size | Acceptable? | Notes |
|---------|-------------|-------|
| < 50 LOC | ✓ Ideal | Easy review |
| 50-200 LOC | ✓ OK | Standard |
| 200-500 LOC | ⚠ Caution | Split if possible |
| 500-1000 LOC | ⚠ Concerning | Must split unless it's a single coherent feature |
| > 1000 LOC | ✗ Reject | Almost certainly needs splitting |

Rationale: Phase 7 fresh-eyes effectiveness drops with PR size. A 200-LOC PR gets reviewed line-by-line; a 1000-LOC PR gets skimmed.

Exception: schema migrations + their backfills can be large; they're mostly one logical change.

---

## Reverting a billing commit

If a recently-merged commit causes incidents:

```bash
git revert <bad-commit-sha>     # creates a new commit; preserves history
git push origin main
```

NEVER `git reset --hard` or force-push (per AGENTS.md). The audit trail matters.

---

## Tagging billing-significant releases

```bash
git tag -a billing-2026.05.05 -m "Triple-charge defense (bd-1m86f); incident postmortem"
git push --tags
```

Tags become the audit trail: "what was the billing system on May 5, 2026?" → `git checkout billing-2026.05.05`. Useful for SOC2 evidence.

---

## CHANGELOG.md for customer-facing billing changes

Sanitized of internal jargon (no "SA-02" / bead IDs):

```markdown
## 2026-05-05

### Billing
- Fixed: Triple-charge issue affecting some customers; refunds issued.
- Improved: Refund processing — access now revoked within 2 seconds.
```

Keeps customer support from being blindsided.

---

## Full branch naming convention

Use a branch family that distinguishes mode, bundle, migration stage, and incident scope:

```
billing-<mode>-<YYYYMMDD>          <- skill kickoff branch
billing-<mode>-<bundle>-<YYYYMMDD> <- per-bundle branch
billing-feature-<short-name>-<YYYYMMDD>
incident-<short-name>-<YYYYMMDD>
billing-greenfield-<YYYYMMDD>
billing-migration-<short-name>-<YYYYMMDD>
billing-cutover-stage-<N>-<YYYYMMDD>
billing-compliance-<framework>-<YYYYMMDD>
```

Examples:

- `billing-audit-and-fix-20260505`
- `billing-feature-team-plans-20260105`
- `incident-2026-05-04-triple-charge`
- `billing-greenfield-20260101`

The prefix lets `git branch --list 'billing-*'` find all in-flight billing work; the mode suffix lets auditors reconstruct why the branch existed.

---

## Incident commit example

Use incident-prefixed commits when the change exists because of a live or recently closed incident:

```
incident-2026-05-04-triple-charge: add cross-provider probe (bd-1m86f)

Refs: incident-2026-05-04-triple-charge
Pattern: references/patterns/30-CHECKOUT.md § Cross-provider duplicate-sub guard
Polish-bar: Dimension 4 (Hijack defense)
Regression test: __tests__/incidents/incident-2026-05-04-triple-charge.test.ts
```

That convention gives incident response three cheap git queries:

```bash
git log --grep "^incident-"
git log --grep "bd-1m86f"
git log --grep "Pattern: references/patterns/30-CHECKOUT.md"
```

---

## Full PR template additions

The quick PR template above is the minimum. For T3+ growth work, compliance work, or incident fixes, include the full evidence surface:

```markdown
# Title
<bundle>-<tag>: <imperative summary>

## Summary
What this PR does.

## Why
What problem this solves.

## Pattern bundles affected
- B40 § replay-staleness gating

## Polish Bar dimensions satisfied
- Dimension 5 (Stale-event ordering)

## Operators applied
- ⏱ STALE-EVENT-GATE
- 🧪 PIN-THE-CONTRACT

## Regression tests added
- `__tests__/billing/team-stale-event-replay.test.ts`
- `__tests__/billing/cross-provider-stale-event-replay.test.ts`

## Drift-guards (if applicable)
- `LastEventAtCoverage.test.ts` updated

## How I tested
- Real-DB integration tests pass.
- Stripe Test Clock drill: replayed cancelled-then-active sequence; no revival.
- Stripe Test Clock drill: replayed payment_succeeded after cancelled; no revival.

## Phase 7 fresh-eyes
- [x] Self-review (Round A)
- [x] Random-walk review (Round B)
- [x] Adversarial review (Round C)
- [ ] Multi-model triangulation (T4+ only; not required for T3)

## Polish Bar Coverage Matrix changes
[paste relevant rows from coverage matrix]

## Linked beads / issues
- bd-2vnz4
- closes incident-2026-05-04

## Reviewer checklist
- [ ] No NEXT_PUBLIC_ exposure of secrets
- [ ] No hardcoded keys / webhook secrets
- [ ] AGENTS.md rules respected (no file deletion, no _v2 files, etc.)
- [ ] All edited files include Polish Bar dimension verification
- [ ] Regression tests cover happy + adversarial paths
- [ ] Drift-guards updated if invariants added
- [ ] No mock usage in billing tests (per § 69)
```

---

## When to NOT merge

- Phase 7 fresh-eyes hasn't run.
- Drift-guard tests missing for new invariants.
- No regression test for a fix.
- AGENTS.md rules violated (e.g., file deletion).
- CI is red (any check failing).
- Customer-impact change without product approval.
- Schema change without DBA review.

---

## Branch protection rules

For the `main` branch:

```yaml
# .github/branch-protection.yml (or in GitHub UI)
require_status_checks:
  - billing-ci
  - drift-guards
  - integration-tests
  - tsc-strict
  - lint
  - detect-billing-mocks
  - audit-bundle-leakage (for production-bound)

require_reviews:
  - count: 2  # billing PRs require 2 approvers (one must be billing-team CODEOWNER)

dismiss_stale_reviews_on_push: true
require_code_owner_review: true

restrict_force_push: true
restrict_delete: true

require_signed_commits: true  # for SOC2 evidence
```

---

## Squash vs merge commits

For billing: prefer **squash** for feature PRs; **merge** for cherry-picked hotfixes because merge commits preserve the cherry-pick history.

The squash commit message follows the convention above. Don't squash if the individual commits are meaningful, such as schema migration + backfill + NOT NULL in three separate commits to preserve revertability.

---

## Cherry-pick strategy for hotfixes

When a hotfix needs to land in main plus a release branch:

```bash
# Develop fix on a feature branch
git checkout -b incident-2026-05-04-triple-charge main
# ... commit fix
git push origin incident-2026-05-04-triple-charge
# Open PR to main; review + merge

# Cherry-pick to release branch
git checkout release-2026.q2
git cherry-pick <fix-commit-sha>
git push origin release-2026.q2
```

The commit message gets a `(cherry picked from commit X)` trailer when using `git cherry-pick -x`.

---

## Git log queries for forensics

```bash
# All billing changes in last 30 days
git log --since='30 days ago' --pretty=format:'%h %ad %s' --date=short -- 'src/lib/webhooks/' 'src/lib/services/' 'src/app/api/stripe/' 'src/app/api/paypal/'

# Who touched updateSubscriptionStatus most recently
git log -10 --pretty=format:'%h %an %ad %s' --date=short -- 'src/lib/webhooks/inbound.ts'

# All commits referencing a specific bead
git log --grep "bd-1m86f"

# Bisect to find the commit that introduced a bug
git bisect start
git bisect bad HEAD
git bisect good <known-good-sha>
# git bisect runs through commits; mark each good/bad
```

---

## Release notes per billing change

For customer-affecting changes, update `CHANGELOG.md` with customer-facing language:

```markdown
# CHANGELOG.md

## 2026-05-05

### Billing
- Fixed: Triple-charge issue affecting some Stripe + PayPal customers (bd-1m86f).
  - We've contacted all affected customers and issued refunds.
  - Implemented cross-provider duplicate detection at checkout to prevent recurrence.
- Improved: Refund processing — access is now revoked within 2 seconds of refund (previously up to 5 minutes).
- Added: Dispute response automation. We can now respond to chargeback disputes within 24 hours of receipt.
```

Customer-facing release notes are sanitized of internal jargon: no `SA-02`, no raw exploit detail, and no implementation-only failure names.

---

## Revert discipline

If a recently merged commit causes incidents:

```bash
# Identify the commit
git log -10

# Revert (creates a new commit; preserves history)
git revert <bad-commit-sha>
git push origin main

# After revert: file an incident bead, write postmortem, then plan the proper fix.
```

Do not use history rewrite to hide the bad commit. The audit trail is evidence.

---

## Co-authorship

When pair-programming or AI-assisted:

```
git commit -m "B40-staleness: add last_event_at WHERE (bd-2vnz4)

Co-Authored-By: <Pair Engineer Name> <email@example.com>
Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

Acknowledge AI assistance in commits when your project policy expects it. SOC2 evidence and future learning are both stronger when the operator record is honest.

---

## Common git mistakes

- **Force-pushing to main / shared branches.** Dangerous and usually forbidden by project rules.
- **`git reset --hard` to "fix" a botched merge.** Loses work and audit evidence. Use `git revert` instead.
- **Squashing commits that should be separate.** Schema migration + code change should often be separate for revertability.
- **Commit messages without bead/issue refs.** Future forensics cannot trace why.
- **Force-pushing during incident response.** Breaks coordination and hides evidence.
- **Branch naming inconsistency.** `git branch --list 'billing-*'` no longer finds half the branches.
- **PRs without Phase 7 fresh-eyes.** Bugs ship.
- **PRs > 1000 LOC.** Reviewers skim; bugs ship.
- **Tags missing on billing-significant releases.** Audit trail incomplete.
- **No `CHANGELOG.md` update for customer-facing changes.** Support team gets blindsided by customer questions.
