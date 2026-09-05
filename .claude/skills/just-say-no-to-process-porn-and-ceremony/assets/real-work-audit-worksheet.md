# Real-Work Audit Worksheet

Look back over a bounded window of work (yours and, if you are
orchestrating, the swarm's) and answer honestly: can I honestly say this
work is truly in furtherance of the core goals, purpose, and underlying
features and functionality of the project, or is it process-related and
invisible to users?

Audit dispassionately, with zero ego: the window's cost is already sunk,
and the classification exists to steer the next block, not to grade anyone.
An honest CAPTURED verdict is a better outcome than a flattering HEALTHY
one.

Window audited: last ___ hours / last ___ commits / last ___ work items
Project's core purpose (one sentence, from the README or charter, not from
memory): ______________________

## Step 1 — Inventory (mechanical, no judgment yet)

Pull the actual record; do not reconstruct from memory:

```bash
git log --oneline --stat -<K>            # last K commits, what they touched
br list --status=closed --json --limit <M> --sort updated_at   # recent closes (if using beads; confirm your br version's sort/reverse flags give newest first)
br list --status=open --json --limit 50 | jq '[.issues[].title]'   # what's queued (bounded; this is an audit, not a dump)
```

For a swarm, also list what each pane/agent shipped in the window.

## Step 2 — Classify Every Item

For each commit / closed item, assign exactly one:

| Class | Meaning |
|---|---|
| USER | A user of the shipped product can see or feel it (feature, fix, perf, UX, docs a user reads) |
| ENABLER | Invisible to users but running code branches on it, or a named feature cannot ship without it (build fix, schema migration, gate for a named capability) |
| PROCESS | Only humans and status reports consume it (certificates, ledgers, dashboards, meta-reports, tracker hygiene, plan edits, governance rounds) |
| UNKNOWN | You cannot tell what it was for; treat as PROCESS until shown otherwise |

Tally:

- USER: ___ ENABLER: ___ PROCESS: ___ UNKNOWN: ___

The ratio is a **diagnostic for you, never a quota for the swarm**: the
moment a ratio becomes a target, agents optimize the label, not the work.

## Step 3 — The Hard Questions

1. Point to the single most user-visible thing shipped in this window. Could
   you demo it to the project owner in two minutes? What would you show?

   Answer: ______________________

2. If every PROCESS item in the window had simply not happened, what
   user-visible outcome would be different?

   Answer: ______________________

3. Did any ENABLER item actually enable something yet, or is it speculative
   infrastructure? Name the consumer that exercised it.

   Answer: ______________________

4. What is the oldest open item that a user would actually care about? Why
   did the window's effort go elsewhere?

   Answer: ______________________

5. For a swarm: which pane produced the most closes, and which produced the
   most user-visible capability? If those are different panes, what is the
   high-close pane actually farming?

   Answer: ______________________

6. Were any commits in the window plan/spec edits standing in for
   implementation, or follow-up items minted to close originals whose
   acceptance conditions were unmet? (Patterns RH-10 and RH-9 in the
   skill's references/REWARD-HACKING-CATALOG.md.)

   Answer: ______________________

## Step 4 — Verdict and Correction

- [ ] HEALTHY: user-visible progress dominates; process is bounded and
      gated. Continue.
- [ ] DRIFTING: process share is growing and question 2's answer was
      "nothing would differ." Apply the anti-ceremony redirect (in the
      skill's references/ENFORCEMENT.md) to the worst offender, possibly
      yourself, and reserve the next work block for the top USER item.
- [ ] CAPTURED: the window is mostly PROCESS/UNKNOWN and the deliverable
      count is flat. Fire the machinery-freeze prompt (same file) now, at
      yourself first. The deliverable is the deliverable.

Correction dispatched (what, to whom): ______________________
