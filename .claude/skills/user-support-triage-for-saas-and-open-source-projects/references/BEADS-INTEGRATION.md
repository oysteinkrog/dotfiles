# Beads (br) Integration For Triage

Triage produces follow-up work — bug fixes, KB articles, refunds queued, retros, escalations. Without a tracking system, this work evaporates. The beads (`br`) CLI is the local-first issue tracker that catches it.

## Why Beads (Not GitHub Issues / Linear)

- **Local-first**: works offline; survives the project being archived
- **Dependency graph**: bv (companion) ranks beads by who's blocked
- **AI-friendly**: structured JSON output that subagents can read
- **No vendor lock-in**: JSONL files in the project repo; `git`-managed

If the project already uses Linear / Jira / GitHub Issues — mirror to those, but keep beads as the source of truth for triage-driven work.

## Bead Types For Triage

| Type | Trigger | Priority default |
|---|---|---|
| `bug` | Reproducible defect surfaced by a ticket | p2 |
| `kb-gap` | 3+ tickets on same topic, no article exists | p3 |
| `kb-fix` | Existing article wrong / outdated | p2 |
| `feature-request` | Customer ask, owner-approved | p3 |
| `refund-followup` | Refund issued, postmortem due | p2 |
| `csat-followup` | Detractor verbatim needing call | p1 |
| `security-fix` | From security disclosure | p0 / p1 |
| `outage-postmortem` | Per `POST-INCIDENT-RETRO.md` | p1 |
| `policy-clarification` | Triage hit a TBD-OWNER policy gap | p2 |
| `voice-drift` | Voice mismatch in own replies | p3 |

## Naming Convention

```
<type>: <one-line> [ticket:<id>]
```

Examples:
- `bug: webhook retry skips idempotency guard [ticket:SUP-1234]`
- `kb-gap: how to set up SSO with Okta [ticket:SUP-2001,SUP-2010,SUP-2015]`
- `refund-followup: $250 refund issued; investigate root cause [ticket:SUP-1500]`
- `security-fix: SSRF in image proxy (CVE pending) [ticket:SUP-3000]`

The `[ticket:...]` suffix lets bv backlinks resolve.

## Per-Phase Bead Operations

| Phase | Bead op |
|---|---|
| ★ ORIENT | (none — not yet ready for backlog) |
| 🔍 REPRO | (none) |
| ⚖ DECIDE | If decision is "fix later", file the bead |
| ✉ DRAFT | (none) |
| 📤 SEND | After send, file beads for follow-up work |
| 🐞 BEAD | The dedicated operator — runs after every ticket |

## Bead Body Template

```markdown
# <type>: <title>

## Source
Ticket(s): <id> [link]
Reporter(s): <count of distinct users>
Tier: <free/individual/enterprise>

## Symptom
<what the user reported>

## Investigation
<what we found>

## Suspected root cause
<file:line, commit SHA, or "unknown — needs investigation">

## Proposed fix
<one-line approach>

## Effort estimate
<S/M/L>

## Acceptance criteria
- [ ] <test that proves fix>
- [ ] <regression guard>
```

## Filing Beads From Triage

```bash
br create \
  --type bug \
  --priority p2 \
  --title "webhook retry skips idempotency guard" \
  --body-file /tmp/bead-body.md \
  --label "from:support,ticket:SUP-1234"
```

The `from:support` label lets you query "all beads filed from triage" across time.

## Linking Tickets To Beads

Bidirectional links:
- The ticket reply mentions the bead ID: "Tracked as bead-789."
- The bead body cites the ticket: `Ticket(s): SUP-1234`.

Customer-facing impact: customer can ask "what's the status of bead-789?" and get a real answer when they check back.

## Querying The Triage Backlog

```bash
# All open triage-driven bugs
br list --type bug --label from:support --status=open

# By priority
br list --label from:support --priority p0,p1 --status=open

# Stale beads (open > 30 days)
br list --label from:support --status=open --stale=30d

# What's blocking the most other beads (use bv for ranking)
bv prioritize --label from:support
```

## Closing Beads From Resolution

When a bug bead is fixed and shipped:

```bash
br close <id> \
  --reason "fixed in commit <sha>; deployed in <release>" \
  --label "shipped:<version>"
```

The customer who originally reported it gets a follow-up email (the 🔁 VERIFY operator picks this up):

```
Heads-up: the issue you reported (ticket SUP-1234) is fixed. Shipped in
v2.34.1. Let me know if you still see it.
```

This closes the loop — most companies forget this step. Customers remember.

## Beads That Outlive The Ticket

Some beads survive for months:
- Long-tail bugs that are low-priority but never fixed
- Feature requests that aren't on the roadmap yet
- Compliance/audit items with annual cadence

For these, don't close the customer ticket on file — close the immediate ticket with "we won't fix this now" honesty + the bead ID for tracking.

## Periodic Reviews

| Frequency | What to review |
|---|---|
| Weekly | Open p0/p1 beads from support; any stuck > 7d |
| Monthly | All `kb-gap` beads — promote ready ones to articles |
| Monthly | `feature-request` beads — owner triage to roadmap |
| Quarterly | Stale `bug` beads — close with "won't fix" or escalate |

## Anti-Patterns

| Don't | Why |
|---|---|
| File a bead for every ticket | Backlog explodes; signal-to-noise drops |
| Close beads without notifying the original reporter | Loop never closes for customer |
| File without acceptance criteria | Re-litigated when picked up later |
| Use beads as a TODO list for the support agent's day | They're for product/eng work, not personal queue |
| Skip the link from bead to ticket | Future agent can't trace why we did the work |
| Let `kb-gap` beads pile up without acting | Defeats the deflection purpose |

## Companion Refs

- [TRIAGE-WORKFLOW.md](TRIAGE-WORKFLOW.md) — when to file beads in the workflow
- [KB-FEEDBACK-LOOP.md](KB-FEEDBACK-LOOP.md) — kb-gap → article pipeline
- [POST-INCIDENT-RETRO.md](POST-INCIDENT-RETRO.md) — retro action items as beads
- `/br` — beads CLI reference
- `/bv` — graph-aware bead prioritization
