# Triage Workflow (6-Phase Loop)

Follow this every triage session, in order. Skipping phases produces wrong fixes and broken trust — see [ANTI-PATTERNS.md](ANTI-PATTERNS.md).

## Phase 1 — Ground Truth (Do Not Respond Yet)

Goal: pull *every* open item across *every* channel. Don't trust any in-memory count.

```bash
PROJECT="<project-path>"
SUR=$(jq -r '.surfaces | join(",")' "$PROJECT/.claude/support-triage/_detection.json")

# Dispatch by surface — see <project>/.claude/support-triage/scripts/list-open.sh
$PROJECT/.claude/support-triage/scripts/list-open.sh > /tmp/open-items.json
python3 <skill>/scripts/validate-adapter-output.py /tmp/open-items.json
jq '.[] | {surface, provider, id, age_hours, sla: .sla.status, status, priority}' /tmp/open-items.json
```

For each surface, also pull SLA / breach data. **Acknowledge breached items immediately** (status only, no message — see Phase 4). Then stop and read everything before drafting anything.

If the adapter fails, do not pretend the queue is empty. Treat the adapter error
as the first support item: fix credentials, rate limits, or adapter mapping
before customer triage.

## Phase 2 — Investigate (Verify Independently)

For each open item:

| Step | Why |
|---|---|
| Read the full ticket including all messages | Context lost in summary loses signal |
| Reproduce against production | "Works on my machine" ≠ works for the user |
| Pin the user's version (CLI, app, browser) | Version determines which fixes they have |
| Check git log for relevant fixes — `git log --oneline -20` | Often already fixed but not deployed |
| Verify the fix actually deployed — Vercel timestamp vs commit timestamp | Auto-deploy may be off |
| Cross-reference admin / internal notes for accuracy | Old notes go stale |

**Scan for shared root causes across tickets before responding to any individually.** Two "different" reports often share one bug.

## Phase 3 — Draft (Bundle, Don't Spray)

Apply the [DECISION-MATRIX.md](DECISION-MATRIX.md) to each item, then customize a template from [RESPONSE-TEMPLATES.md](RESPONSE-TEMPLATES.md). Project-specific templates in `<project>/.claude/support-triage/04-templates/` override the generic ones.

Output format for owner review:

```
═══════════════════════════════════════════════════════════════
DRAFT BUNDLE — <project> — <date>
═══════════════════════════════════════════════════════════════

OPEN ITEMS:  <N>
SLA BREACHED:  <M>  (acknowledged at <timestamp>, no message yet)
SHARED ROOT CAUSES IDENTIFIED:  <K>

───────────────────────────────────────────────────────────────
ITEM 1 — <ticket-id> — <subject>
  user:    <email-or-handle>
  channel: <tickets|github|zendesk|...>
  age:     <hours>h    sla:  <ok|at_risk|breached>
  classify: <category from decision matrix>
  finding:  <root cause hypothesis>
  drafted action: <reply | status update | both | none>

  DRAFT REPLY:
  ┌─────────────────────────────────────────────────────────
  │ <reply text>
  └─────────────────────────────────────────────────────────

  PROPOSED STATUS: open → acknowledged → in_progress → resolved
  CODE CHANGE NEEDED?  yes/no — <SHA or "n/a">

───────────────────────────────────────────────────────────────
ITEM 2 ...
```

**Do not send anything yet.** This is a draft for the owner.

## Phase 4 — Owner Review (The Confirmation Gate)

Show the entire draft bundle in one pass. Owner can:

- ✅ Approve all → proceed to Phase 5
- ✏️ Edit specific replies → re-show those before sending
- 🛑 Decline a draft → mark "ack only, no message"
- 🤔 Ask for more research on one → pause that item, send the rest

Mechanics that don't need owner approval (still fine to do during Phase 1–3):

- Acknowledging an SLA-breached ticket (status: open → acknowledged) — stops the SLA clock without messaging the customer
- Internal admin notes (not customer-visible)
- Filing beads for follow-up bugs
- Updating ticket priority based on new evidence

Mechanics that **always** need owner approval:

- Posting any customer-facing message (email, ticket reply, Discord DM, etc.)
- Refunds / subscription cancellations
- Pushing code changes to production
- Closing an issue with comment (the comment is customer-visible)

## Phase 5 — Act (Send → Update → Verify)

```
For each approved item:
  1. Send reply via the surface's API
     - Custom DB → POST /api/admin/support/tickets/{id}/messages
     - GitHub  → gh issue comment N -F /tmp/reply.md
     - Zendesk → POST /api/v2/tickets/{id}/comments
     - etc.
  2. Update status:  open → acknowledged → in_progress → resolved
  3. If code fix:  fix → typecheck/test/UBS → deploy → verify against production
  4. File bead if more work remains:  br create "<title>" --type bug --priority p1
  5. Note in admin / internal channel that the loop closed
```

After all sends, **re-fetch the open list** and verify nothing was missed:

```bash
$PROJECT/.claude/support-triage/scripts/list-open.sh | jq 'length'
```

If the count dropped to expected, move to Phase 6. If not, find the missed items
and loop back.

## Phase 6 — Outcome (Make The Skill Accretive)

Write the outcome record described in [POST-SEND-OUTCOME.md](POST-SEND-OUTCOME.md):

```
$PROJECT/.claude/support-triage/outcomes/YYYY-MM-DD-<slug>.md
```

Capture:

- what changed;
- which sends were owner-approved;
- which drafts were rejected or heavily edited;
- which policies were missing;
- which KB/template/runbook gaps appeared;
- which product or engineering bugs should become beads/issues;
- which adapter fields or scripts slowed the session.

Do not silently update policy from one session. Outcome records create bounded
proposals; the owner decides what becomes policy.

## Fire-Drill Mode

To rehearse without touching live providers:

```bash
SUPPORT_TRIAGE_FIXTURE=/path/to/fixture-open-items.json \
  <skill>/scripts/triage-cycle.sh "$PROJECT"
```

The fixture must pass the adapter validator. Fire drills should prove the same
workflow routes correctly and preserves the no-send confirmation gate.

## Session-End Hand-Off

Write a one-paragraph summary to the owner:

```
Triage session — <project> — <date> — <duration>

Open items at start:  <N>
Closed:               <closed_count>
Replied:              <replied_count>
Code fixes shipped:   <SHAs or "none">
Beads filed:          <bead_ids>
Still open:           <remaining_count>  (<reason>)
Outcome record:       <path or "none; no action taken">

Next action: <what owner should do, if anything>
```
