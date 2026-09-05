# METHODOLOGY-EVOLUTION-LOG.md — Tracking How brennerbot Evolves Over Time

<!-- TOC: Why an evolution log | Schema | How to populate | Per-quarter cadence | Per-session entries (atypical) | Reading the log | When evolution stalls | When evolution races | Composition with subagents/methodology-historian.md -->

This log tracks how the brennerbot skill itself evolves session-over-session. Mainly maintained by `subagents/methodology-historian.md` running quarterly; new entries surface from Phase 10 lesson commitments and from at-scale operators (per BRENNERBOT-AT-SCALE.md).

For a fresh agent reading this skill, this log shows you which references are *fresh* (shaped by recent sessions) and which are *settled* (haven't changed in many months — likely well-tested).

---

## Why an evolution log

Without it:
- Cumulative methodology improvements get lost in git history
- Operators don't know which references are battle-tested vs experimental
- Cross-session learning compounds invisibly (or not at all)

With it:
- Each quarter's diff is visible at a glance
- Lesson sources are tracked back to specific sessions
- Operators reading the skill can spot trends ("X has been tightened 3 times in 6 months")

Per /operationalizing-expertise + SKILL-AS-METHODOLOGY-PATTERN.md, this log is the explicit Phase 10 lesson-loop output.

---

## Schema

Each entry:

```markdown
## <Quarter> (e.g., Q3 2026)

### New artifacts

- references/<file>.md (added <ISO>)
  Addresses: <one-line>
  Source: <session ID or "skill maintainer">

### Updated artifacts

- references/<file>.md (revised <ISO>)
  Change: <one-line>
  Source: L-NNN from <session>

### Deprecated / superseded

- references/<file>.md § <section> (marked deprecated <ISO>)
  Reason: <one-line>
  Migration: <one-line> or "see <new file>"

### Phase 10 lessons committed (in window)

| Lesson ID | Source session | Gap addressed | Committed to |
|-----------|----------------|---------------|--------------|
| ... | ... | ... | ... |

### Recurring patterns

(Patterns identified across multiple sessions in the quarter; if seen ≥3 times → promotable to canonical.)

- <pattern 1>: <count> occurrences. Recommendation: <action>.

### Stability metrics

- Sessions per quarter: <count>
- Lessons committed per session: <ratio>
- Reference file change rate: <files/quarter>
- New MO additions: <count>
```

---

## How to populate

### Quarterly cadence (recommended)

Per `subagents/methodology-historian.md`:

1. Identify the time window (last 90 days)
2. `git log --since="$(date -d '90 days ago' +%Y-%m-%d)" --name-only --diff-filter=AM -- references/`
3. For each changed file: read the diff, classify the change (bug fix / clarification / new pattern / corrected guidance)
4. Aggregate by category
5. Append a new `## <Quarter>` entry to this file
6. Commit

For at-scale operators (per BRENNERBOT-AT-SCALE.md), this is part of the Friday morning skill maintenance block.

### Per-session entries (atypical)

Most sessions don't warrant a per-session entry; their lessons land in the quarterly digest. Exceptions:

- T5 sessions where the methodology itself was re-triangulated
- Sessions whose lessons changed ≥3 reference files
- Major-revision sessions (kernel update, new operator added)

For those, add a one-paragraph entry under the corresponding quarter's "Recurring patterns" section.

---

## Reading the log

For a new operator:

- Scan recent quarters to see which areas are evolving fast (operator-context, deadlock patterns, evidence weighting → fresh; kernel, axioms → settled)
- Sections with many entries this quarter signal *active improvement*; check those references for the latest patterns
- Sections with no entries in 2+ quarters are settled

For a session operator:

- Before bootstrapping, check the most-recent quarter for any methodology changes that affect your domain
- After Phase 10, decide if your session's lessons warrant adding to the running quarter's pending entries

---

## When evolution stalls

If no entries for 2+ consecutive quarters:

- Either the methodology has matured (good — no new gaps surface)
- Or operators are skipping Phase 10 / not committing lessons (bad — silent drift)

Investigate via `subagents/methodology-historian.md` "Evolution gaps" report.

---

## When evolution races

If >1 reference change per week sustained:

- Operators may be over-correcting (each session's lesson is a structural change)
- New patterns may not be stabilizing
- Recommend: pause methodology changes for 2-4 weeks; observe whether changes hold up

This log surfaces the rate of change. Use it.

---

## Composition with subagents/methodology-historian.md

The historian is the canonical writer of this log. Operators don't write entries directly — they file Phase 10 lessons in their session's DRIFT-CHECK.md, and the historian aggregates quarterly.

For acute changes (e.g., a critical methodology bug surfaced; the skill must update immediately), operators may write a per-session entry inline. Mark it `## <Date> (per-session: <session>)` so it's distinguishable from quarterly aggregations.

---

## Initial state

This log is empty (no quarters yet) until the first quarterly run of `subagents/methodology-historian.md`. The first quarterly entry will likely cover several months of skill evolution prior to log creation, retroactively classified.

To bootstrap the historian's first run:

```bash
# Identify approximate skill creation:
git -C <skill-repo> log --reverse --pretty=format:'%ad %s' --date=short | head -3

# Run historian against the full history:
Agent({
  description: "Initial methodology evolution log",
  subagent_type: "general-purpose",
  prompt: "<contents of subagents/methodology-historian.md, with TIME_WINDOW=since-skill-creation>"
})
```

---

## Cross-references

- [subagents/methodology-historian.md](../subagents/methodology-historian.md) — the canonical writer
- [CROSS-SESSION-LEARNING.md](CROSS-SESSION-LEARNING.md) — per-session lesson commitment
- [SKILL-AS-METHODOLOGY-PATTERN.md](SKILL-AS-METHODOLOGY-PATTERN.md) — meta-context (this log is the Stage 5 evolution feedback)
- [BRENNERBOT-AT-SCALE.md](BRENNERBOT-AT-SCALE.md) — quarterly maintenance cadence
- [AGENT-API-DESIGN-FOR-INVESTIGATORS.md](AGENT-API-DESIGN-FOR-INVESTIGATORS.md) — references this log for versioning script changes
