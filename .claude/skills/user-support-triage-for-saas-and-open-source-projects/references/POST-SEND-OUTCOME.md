# Post-Send Outcome Loop

The triage loop should not end at "reply sent." The skill becomes accretive
only when each session leaves a small, structured record that future agents can
learn from.

Treat this as Phase 6 after Act + Verify:

```
Ground truth -> Investigate -> Draft -> Confirm -> Act + Verify -> Outcome
```

## Outcome Record

Write one outcome record per triage session:

```
<project>/.claude/support-triage/outcomes/YYYY-MM-DD-<slug>.md
```

Template:

```markdown
# Triage Outcome - <project> - <date>

## Session

- Started with open items: <N>
- Closed: <N>
- Replied: <N>
- Internal notes only: <N>
- Code fixes shipped: <SHAs or none>
- Beads filed: <ids or none>
- Owner-approved sends: <count>
- Customer-visible sends without explicit owner approval: 0

## Decisions

| Item | Category | Theme Tags | Persona | Action | Evidence | Owner Approval |
|---|---|---|---|---|---|---|
| <id> | billing/access | billing.duplicate-charge | manager | reply + bug bead | <ticket/url/code path> | <timestamp/text> |

## Customer Psychology / Communication Notes

- Rage stage or sentiment: <friction|cost|helplessness|identity-threat|normal|detractor|promoter>
- Tactical move used: <none|mirror|label|accusation-audit|calibrated-question|strategic-no>
- Customer-effort count: <number of asks in the reply>
- Voice/register note: <what changed from the template>

## Compensation / Goodwill

- Compensation considered: <yes|no>
- Dials if used: H<1-5> F<1-5> L<1-5> V<1-5> => band <name>
- Remedy proposed/executed: <none|apology|credit|extension|refund|upgrade|owner-led>
- Approval/evidence: <owner approval or policy citation>

## What Worked

- <operator/template/runbook that saved time>

## What Failed Or Felt Slow

- <missing policy, missing adapter field, stale template, unclear runbook>

## KB / Template Gaps

- <gap> -> proposed destination (`09-knowledge-base.md`, `04-templates/...`)

## Product / Engineering Signals

- <recurring bug, confusing UX, docs gap, provider issue>

## Accretive Value Loop

- Loop selected: <docs|product-quality|onboarding|retention|pricing|automation|abuse-prevention|reliability|roadmap|not-accretive-this-session>
- Owner / destination: <person, repo issue, roadmap board, docs file, or none>
- Evidence threshold met: <single-high-severity|3+ repeats|trend metric|owner judgment|not yet>
- Next review date: <YYYY-MM-DD or none>

## Voice-of-Customer / Loopback

- Keeper verbatims: <exact quote, redacted; destination; consent status>
- Loopback needed: <ticket ids/users/theme and what shipped/future condition would trigger a reply>
- Theme proposal if no vocabulary exists: <proposed tag + evidence>

## Proposed Skill/Project Updates

- [ ] <bounded proposal, not auto-applied unless owner approves>
```

## Why This Exists

Without an outcome loop, the support skill repeats the same mistakes:

- same missing policy gets rediscovered;
- same product bug spawns new tickets;
- same template sounds wrong for the brand;
- same runbook ambiguity gets solved ad hoc;
- same adapter field is missing on every session.

The outcome record is the bridge from support labor to product intelligence.

## What Gets Promoted

After each session, promote only evidence-backed changes:

| Signal | Destination |
|---|---|
| Same question asked repeatedly | `09-knowledge-base.md` or docs site issue |
| Same reply rewritten by owner | `08-voice.md` and response template |
| Same policy ambiguity | `05-policies.md` with owner answer |
| Same product bug | bead / GitHub issue |
| Same manual lookup | adapter field or script enhancement |
| Same high-risk confusion | runbook patch and fire-drill fixture |
| Same provider failure | `07-secrets.md`, provider setup doc, or adapter retry rule |
| Same theme across support + NPS/cancel/sales/public streams | `VOICE-OF-CUSTOMER-LOOP.md` synthesis and product proposal |
| Same customer phrasing captures product value | `💎 KEEPER` entry, internal copy note, or consent request |
| Same shipped fix has identifiable reporters | `🔁 LOOPBACK` draft bundle |
| Same support class creates avoidable cost | deflection/self-service or automation proposal with estimated savings |

Do not let the agent silently rewrite the decision matrix or policies from one
session. Outcome records create proposals; the owner chooses what becomes
policy.

## Minimal Metrics

Track these even in tiny projects:

- first response time;
- time to owner approval;
- time to final verification;
- number of messages drafted vs sent;
- number of customer-visible sends blocked or rewritten by owner;
- number of new KB/template/runbook gaps found;
- number of recurring issues converted into bugs.
- number of theme-tagged items, loopbacks sent, keeper verbatims captured, and compensation bands used.
- number of outcome records with a named value loop owner versus `not-accretive-this-session`.

These are more useful than vanity ticket counts because they show friction in
the workflow.

## Outcome Review Cadence

For low-volume projects, review outcomes monthly. For active SaaS support,
review weekly.

Review questions:

1. Which support categories are growing?
2. Which templates get rewritten most often?
3. Which runbooks cause the most owner questions?
4. Which customer segments are overrepresented?
5. Which adapter gaps force manual work?
6. Which product changes would delete the largest ticket class?

## Acceptance Standard

A triage session is not complete until:

- open items were re-fetched after actions;
- a one-paragraph owner handoff exists;
- an outcome record exists or the session explicitly says "no action taken";
- follow-up beads/issues are filed for engineering work;
- KB/template/runbook proposals are captured without silently becoming policy.
- at least one accretive loop is selected, or `not-accretive-this-session` is written explicitly.
