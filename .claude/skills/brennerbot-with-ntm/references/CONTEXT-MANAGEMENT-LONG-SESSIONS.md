# CONTEXT-MANAGEMENT-LONG-SESSIONS.md — Operator's Own Context Budget

<!-- TOC: Why operator-context matters | The operator's context budget | The 4 stages of operator-context drift | Mitigation strategies | When to compact | When to hand off | When to checkpoint | What goes in vs what gets externalized | Resume from compaction | Operator memory hygiene | Anti-patterns -->

The operator (you, the Claude Code instance running this skill) has a finite context window. T3-T4 sessions run 5-12 hours. Without discipline, the operator's own context fills with pane chatter, bead state dumps, and partial reads — degrading the operator's tick-time decisions.

This file is about operator-context management as an explicit methodology concern. It's distinct from the panes' context (which is per-pane and managed via OC-009 from /vibing-with-ntm).

---

## Why operator-context matters

The skill assumes the operator can:
- Hold the full Decision Tree in mind
- Recall recent failure modes (red-flag table)
- Track per-pane states (5+ panes)
- Synthesize tick-to-tick continuity

A degraded-context operator:
- Forgets which pane was assigned which H
- Repeats already-failed dispatches
- Misclassifies symptoms (rate-limit vs context-saturation)
- Misses anomaly clusters (forgot the prior anomalies)

For T3+ sessions, deliberate context-budget management is the difference between converging in 5 hours and timing out at 8.

---

## The operator's context budget

A typical operator's context window (Claude with 1M context):

```
1,000,000 tokens
- 50,000  System prompt + skill description
- 100,000 SKILL.md (loaded on trigger)
- 50,000  Active references (Decision Tree, Failure Table, current MO)
- 200,000 Recent pane tail captures (last 30 ticks × 5 panes × ~1300 tokens)
- 150,000 Bead state dumps (br list outputs across ticks)
- 100,000 User conversation history
- 50,000  Operator's working notes
- 300,000 Reserve for ad-hoc lookups (sub-references, scripts, etc.)
```

That's ~700k used + 300k reserve at peak. For T1-T3 the reserve is comfortable; for T4 the reserve gets tight; for T5 the operator MUST manage explicitly.

---

## The 4 stages of operator-context drift

### Stage 1: Healthy (0-30% of session wall-time)

- Operator has full mental model
- Tick decisions land in <30 seconds
- Cross-tick continuity is clean

### Stage 2: Compressed (30-60%)

- Operator starts referring back to recent tick logs
- Some bead IDs blur ("did p3 file EV-014 or was it p4?")
- Tick decisions take 60+ seconds

### Stage 3: Drifting (60-85%)

- Operator misses anomaly clusters they would have caught earlier
- Repeats dispatches that already failed
- Pane chatter starts looking similar across rounds (red-flag phrases blur)

### Stage 4: Saturated (>85%)

- Operator's tick decisions are no better than random
- Methodology drift is invisible from inside (per F-1003 silently)
- Phase 7 audit, if attempted, will be rubber-stamped (F-701)

If operator hits Stage 4, the session is in trouble. Stop and compact OR hand off.

---

## Mitigation strategies

### M-1: Externalize state aggressively

Don't hold pane states in operator-context; query them on demand:

```bash
# Don't memorize:
#   "p1 has 4 EVs, p2 has 3, p3 has 2..."
# Instead, query:
$ ./scripts/tick.sh ~/brennerbot_sessions/<session>
[Tick at <ISO>]
  Pane states: ...
  Bead summary: ...
```

The operator reads the tick output once, acts, doesn't need to re-internalize.

### M-2: Use scripts for aggregate views

`./scripts/emit-quickref.sh` produces a one-screen dashboard of session health. Refresh per-tick instead of mentally reconstructing.

### M-3: Defer reference reading

Don't read all of references/ at the start. Read only:
- SKILL.md (mandatory)
- The MO for the current phase
- The reference cited by a current red-flag

Other references are on-demand. The skill explicitly designs progressive disclosure for this reason.

### M-4: Compact pane tail captures

Per OBSERVABILITY.md tick cadence: capture pane tails at appropriate intervals. Don't capture more frequently than necessary.

```bash
# Don't every 60 seconds:
ntm --robot-tail=<session> --lines=200  # 200 lines × 5 panes × ~6.5 tok/line = 6,500 tok per tick
                                 # × 30 ticks = 195k tokens (almost 20% of budget)

# Do every 10-17 minutes (per OBSERVABILITY.md):
ntm --robot-tail=<session> --lines=50   # 50 × 5 × 6.5 = 1,625 tok per tick
                                 # × 18 ticks (over 5h) = 29k tokens (~3% of budget)
```

Same coverage; 6-7× less token burn.

### M-5: Use beads as long-term memory

Beads (`.beads/beads.db` plus `.beads/issues.jsonl`) are persistent across the session. Query them when you need state, don't memorize.

```bash
# Operator forgot which H is currently confirmed:
$ br list --label=hypothesis --json | jq -r '.issues[]? | select((.description // "") | contains("state: confirmed")) | .id'
```

### M-6: Externalize tick-to-tick continuity to logs

Per OBSERVABILITY.md, write per-tick summaries to `session-logs/round-N.md`. The operator can re-read these instead of holding all in memory.

---

## When to compact

Compact (write a summary, then drop pane-tail captures from context) when:

- Session wall-time > 60% of tier budget AND
- Operator notices Stage 2-3 drift symptoms AND
- A natural phase boundary is approaching (Phase 4 round end, Phase 5 → 6, etc.)

Compaction protocol:

1. Operator runs `./scripts/tick.sh` for full status
2. Operator writes a compact summary to `session-logs/compaction-<N>.md`:

```markdown
# Compaction <N> — <ISO>

## State at compaction
- Phase: <current>
- Active H: <list>
- Killed H: <list>
- Pane assignments: <table>
- Anomalies: <list>

## Recent decisions (last 30 min)
- <decision 1>
- <decision 2>

## Pending dispatches
- <pending 1>
- <pending 2>
```

3. Operator can drop older pane-tail captures from working memory; refer to compaction summary for context

This is analogous to what `/loop` and `/cass-memory` do for memory management; the operator does it manually here.

---

## When to hand off

If operator-context drifts to Stage 3 with no relief in sight (heavy session, complex multi-phase work), consider handoff:

- **Operator-buddy handoff** (per OPERATOR-ONBOARDING-CURRICULUM.md): a second operator takes over with the doctor report (per BRENNERBOT-DOCTOR-RUBRIC.md)
- **Self-handoff via /casr**: the current operator writes a complete session-state package; resumes in a fresh session/context

Handoff is preferable to pushing through Stage 4 — degraded decisions waste more time than the handoff overhead.

---

## When to checkpoint

Every Phase exit AND every compaction is a natural checkpoint. At checkpoint:

```bash
# 1. ntm checkpoint
ntm checkpoint save brennerbot-<session> -m "Phase 4 round 2 complete"

# 2. git commit
git add intake/ corpus/ evidence/ distillations/ deliverables/ .brenner_workspace/ .beads/ .ntm/checkpoints/
git status
git commit -m "Phase 4 round 2 complete"

# 3. RESUME.md preview (if Phase 8-ready)
<path-to-brennerbot-with-ntm>/scripts/dump-session-report.sh > deliverables/SESSION-REPORT-<ISO>.md
```

Checkpoints let the operator (or a successor operator) recover to a known-good state.

---

## What goes in operator-context vs what gets externalized

### IN operator-context (high-frequency lookup)

- Decision Tree (always)
- Red-Flag Phrases (always)
- Current phase's MO
- Last 1-2 tick outputs
- Active failure-mode codes (F-### in play)
- Top-3 H/EV with state
- Current adjudicator + champion mapping

### EXTERNALIZED (query on demand)

- Full BEADS-SCHEMA detail → query when filing/updating
- Full FAILURE-TABLE → query when matching a symptom
- All references/ docs → load when relevant
- Per-pane chatter > 10 ticks old → in `session-logs/round-N.md`
- Cross-session prior verdicts → /cass / /flywheel
- Specific quote excerpts → corpus/ files

The discipline: keep ~30k tokens in active operator-context; externalize the rest.

---

## Resume from compaction

If you're a fresh operator (or the same operator after compaction), the resume protocol:

1. **Read the most recent compaction summary** (`session-logs/compaction-<N>.md`)
2. **Read the latest RESUME.md** if Phase 8 occurred
3. **Run `./scripts/tick.sh`** for current state
4. **Read SKILL.md Operator Quickstart + Decision Tree**
5. **Decide next phase** per Decision Tree

The compaction summary + tick output + RESUME.md gives you ~95% of session context in <2k tokens.

---

## Operator memory hygiene

Quarterly (per Phase 10 cross-session learning), reflect on operator-context patterns:

- Which sessions ran into Stage 4? Why?
- What context-management patterns helped?
- What externalization should be added (new scripts, new logs)?

Update OPERATOR-CALIBRATION-LOG.md with patterns. Promote successful patterns to canonical.

---

## Anti-patterns

| ✗ | Why |
|---|-----|
| Capture pane tails every minute | Burns context; OBSERVABILITY.md cadence is 4-30 min |
| Read all references/ at session start | Context overload; load on-demand |
| Hold all pane states in head | Externalize to tick logs |
| Skip compaction during long sessions | Stage 4 is approached silently |
| Refuse to hand off | Drift compounds; quality drops more than handoff cost |
| Compact mid-phase | Lose intra-phase continuity; compact at phase boundaries |
| Don't track tick history | Can't reflect on operator-context patterns |
| Resume after long break without reading compaction summary | Fresh-context blind spot |

---

## When operator-context isn't the bottleneck

For T1-T2 sessions (≤3h), operator-context typically stays in Stage 1-2. Mitigation strategies above are nice-to-have, not mandatory.

For T3 (5h), apply M-1 through M-3 routinely. M-4/M-5 mitigations help.

For T4-T5 (8h+), compaction is mandatory at phase boundaries. Externalization-by-default. Plan for context budget like you plan for token budget.

---

## Cross-references

- [OBSERVABILITY.md](OBSERVABILITY.md) — tick cadence (M-4 implementation)
- `/loop` and [/cass-memory](../../cass-memory/SKILL.md) — memory management for autonomous loops
- `/casr` — cross-agent session resumer (operator handoff)
- [WALL-TIME-BUDGET.md](WALL-TIME-BUDGET.md) — total session time
- [scripts/tick.sh](../scripts/tick.sh) — externalized state aggregator
- [scripts/dump-session-report.sh](../scripts/dump-session-report.sh) — checkpoint summary
- [BRENNERBOT-DOCTOR-RUBRIC.md](BRENNERBOT-DOCTOR-RUBRIC.md) — Pillar 1+4 health check at compaction
- [OPERATOR-ONBOARDING-CURRICULUM.md](OPERATOR-ONBOARDING-CURRICULUM.md) — buddy handoff protocol
