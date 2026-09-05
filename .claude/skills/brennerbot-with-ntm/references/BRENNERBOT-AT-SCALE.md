# BRENNERBOT-AT-SCALE.md — Running 10+ Sessions Per Week

<!-- TOC: Why scale matters | Operational patterns | Session inventory management | Cross-session knowledge compounding | Quota and account hygiene | Operator rotation | Skill maintenance cadence | Anti-patterns | Telemetry | Composition with multi-pass-bug-hunting -->

Most documented patterns assume 1-2 sessions per week. Some users run brennerbot continuously — multiple sessions in flight, queue of pending work, weekly cadences. This file is for that operational regime.

For 1-2 sessions/week, this is informational. For 10+ sessions/week, mandatory reading.

---

## Why scale matters

At low volume:
- Operator-context drift handled per session
- Cross-session learning is occasional
- Quota management is manual

At scale:
- Multiple sessions compete for operator attention
- Cross-session patterns dominate over per-session insights
- Quota becomes a primary constraint
- Methodology evolution accelerates AND drifts faster

The patterns below scale brennerbot from "researcher's tool" to "team-level methodology infrastructure."

---

## Operational patterns

### P-Scale-1: Session intake queue

Maintain a queue of pending brennerbot questions:

```bash
# In ~/.brennerbot/queue.jsonl
{"id": "Q-2026-05-15-storage-eval", "question": "...", "tier": "T3", "submitted_by": "alice", "submitted_at": "...", "deadline": "..."}
{"id": "Q-2026-05-16-perf-incident", "question": "...", "tier": "T2", "submitted_by": "bob", ...}
```

Operator picks from queue per priority:
- Deadline-first
- Tier × stakes (T4+ trumps T2)
- Composability (multiple sessions on same domain → batch for cross-session learning)

### P-Scale-2: Time-boxed daily blocks

Don't run 10 sessions reactively; block time:

```
Mon 9-12: T2-T3 sessions (2-3 quick wins from queue)
Tue 9-17: One T3-T4 deep session
Wed 9-12: T2-T3 batch
Thu 9-17: One T3-T4 OR drift-check / cross-session reconciliation block
Fri AM:   Phase 10 retrospectives + skill maintenance
Fri PM:   Operator-buddy review for any T4+ session
```

Predictable cadence prevents burnout AND quota waste.

### P-Scale-3: Concurrent session caps

Don't run > 3 sessions concurrently regardless of operator capacity:

- Operator-context limits (per CONTEXT-MANAGEMENT-LONG-SESSIONS.md)
- Account-quota staircase (per DL-7)
- Cross-session contention (per OC-031 in /vibing-with-ntm)

Sequential is usually faster than parallel for individual session quality.

### P-Scale-4: Session reuse and resume preference

A T2 session that produces an open question is often better resumed (per `resume-session.sh`) than re-bootstrapped. Cross-session continuity > fresh-start ceremony.

```bash
# Bias the queue toward resumable existing sessions when feasible:
$ ls ~/brennerbot_sessions/*/RESUME.md | head -10
# (Operator scans for related work before bootstrapping new)
```

---

## Session inventory management

### I-1: Index of completed sessions

```bash
# Maintain a session-index file (per CROSS-SESSION-LEARNING.md schema):
~/.brennerbot/session-index.jsonl
{"id": "RS-2026-05-12-storage-eval", "topic": "PostgreSQL vs ScyllaDB", "tier": "T3", "verdict": "Defer migration; CDN extraction", "completed": "...", "drift_verdict": "convergent"}
```

Updated at every Phase 10. Provides the corpus for `/cass`-style search across brennerbot work.

### I-2: Session retention

For at-scale operators:
- T1-T2 sessions: keep workspace 30 days; archive after
- T3 sessions: keep 6 months; archive after
- T4-T5 sessions: keep indefinitely; mark for periodic re-evaluation

Archive = move to `~/brennerbot_archive/<year-month>/` (don't delete).

### I-3: Session search

Use `/cass` for cross-session content search:

```bash
$ cass search "PostgreSQL" --robot --limit 10
# Returns brennerbot sessions touching PostgreSQL
```

For per-bead search:

```bash
# Bead search across active sessions:
$ for ws in ~/brennerbot_sessions/*/; do
    br -C "$ws/.beads" list --json | jq -r --arg ws "$ws" '.issues[]?
      | select((.description // "") | contains("PostgreSQL"))
      | "\($ws): \(.id) \(.title)"'
  done
```

---

## Cross-session knowledge compounding

### C-1: Quarterly synthesis

Every quarter, run a synthesis session that's MEAN BRENNERBOT — applies the methodology to its own corpus:

- Collect last quarter's sessions
- Run a brennerbot session asking "what patterns recur across these sessions?"
- Phase 10 lessons committed back to references/

This is meta-Phase-10 (per `methodology-historian.md` subagent).

### C-2: Living reviews per topic area

For recurring topics (e.g., "our storage stack", "our CI/CD reliability"), use `living-review` mode (per LIVING-DOCUMENTATION-PATTERNS.md). Quarterly refresh ticks instead of fresh sessions.

This compounds knowledge instead of restarting.

### C-3: Pattern catalogs

When ≥3 sessions surface the same pattern, promote to a catalog entry:

- `references/INCIDENT-PATTERN-CATALOG.md` (per POST-MORTEM-FORMALIZATION-PLAYBOOK.md)
- `references/RECONCILIATION-CATALOG.md` (per RECONCILIATION-OF-PRIOR-SESSIONS.md)
- `references/CROSS-SESSION-DRIFT-CATALOG.md` (per CROSS-SESSION-LEARNING.md)
- `references/METHODOLOGY-EVOLUTION-LOG.md` (per `methodology-historian.md` subagent)

Promoted catalogs feed back into recipes.

---

## Quota and account hygiene

### Q-1: Account fleet

For 10+ sessions/week:
- ≥6 cc accounts (3 active + 3 reserve)
- ≥4 cod accounts (2 active + 2 reserve)
- ≥3 gmi accounts (2 active + 1 reserve)

Per `/caam`. Pre-warm reserves.

### Q-2: Daily quota check

Before block-time starts:

```bash
$ caam ls --provider=claude --json | jq '[.[] | {id, daily_remaining, expires_at}]'
$ caam ls --provider=codex --json | jq ...
$ caam ls --provider=gemini --json | jq ...
```

If aggregate daily-remaining < 5 sessions: defer some queue items.

### Q-3: Rotation discipline

Per /vibing-with-ntm OC-002. Rotate proactively before hitting limits, not reactively after.

### Q-4: Cross-session quota optimization

Sequential T3 sessions can share warm-cache benefits if questions are related:

```bash
# Same operator runs 2 storage-related T3 sessions in succession.
# Account 1 (cc) reads PostgreSQL docs in session 1; cache hits in session 2.
# Token cost in session 2 ~30% lower.
```

Schedule related sessions back-to-back when possible.

---

## Operator rotation

### O-1: Buddy system at scale

Pair operators across sessions:
- Operator A primary for session X
- Operator B reviewer for session X (per OPERATOR-ONBOARDING-CURRICULUM.md buddy)
- Sometimes swap roles

This catches operator-specific blind spots; provides cross-training.

### O-2: Operator specialization

After 3+ months, operators tend to specialize:

- "Domain specialist" — deep on a specific research domain
- "Methodology specialist" — runs more drift-checks; maintains references/
- "Adversarial specialist" — runs A6 (security audit) sessions
- "Multi-session specialist" — handles reconciliation work

Per OPERATOR-ONBOARDING-CURRICULUM.md "Specialty paths." For team-scale brennerbot, formalize.

### O-3: Rotating Phase 10 reviewer

Phase 10 drift-check should be a fresh general-purpose Agent (per OC-026). For team scale, also rotate which human operator reviews drift findings:

```
Week 1: Operator A reviews drift outputs
Week 2: Operator B reviews
...
```

Cross-rotation surfaces operator-specific drift patterns.

---

## Skill maintenance cadence

At scale, the skill itself evolves.

### M-1: Weekly: lesson commit batching

```
Friday morning:
  - Aggregate Phase 10 lessons from the week
  - Apply via Edit (not auto-script per AGENTS.md)
  - Commit with attribution to source sessions
```

### M-2: Monthly: methodology review

```
First Monday of month:
  - Run methodology-historian.md across last quarter
  - Identify recurring patterns
  - Promote stable patterns to canonical
```

### M-3: Quarterly: pattern catalog audit

```
Quarterly:
  - Review INCIDENT-PATTERN-CATALOG.md
  - Review RECONCILIATION-CATALOG.md
  - Review METHODOLOGY-EVOLUTION-LOG.md
  - Prune patterns no longer relevant
  - Surface patterns ready for canonical promotion
```

### M-4: Annually: kernel re-triangulation

Once a year:
- Run a fresh T4 brennerbot session that re-triangulates KERNEL.md against the latest distillations
- Compare to existing kernel
- Document drift
- Update if substantive

This is methodology evolution at the highest level.

---

## Telemetry

For at-scale operations, collect:

```bash
# Per session:
- session_id
- tier
- mode
- wall_time
- token_burn (per family)
- account_rotations
- F-### codes triggered
- drift_verdict
- lessons_committed_count
- handback_lines

# Aggregate weekly:
- sessions_completed
- sessions_aborted
- mean_wall_time_per_tier
- mean_F_codes_per_session
- mean_drift_verdict_distribution
- new_lessons_committed

# Aggregate monthly:
- methodology_changes (file diffs in references/)
- pattern_promotions (e.g., to INCIDENT-PATTERN-CATALOG.md)
- new_operator_onboardings_completed
```

Track in a simple JSONL file; build dashboards via tools of choice. Per OBSERVABILITY.md philosophy.

---

## Anti-patterns

| ✗ | Why |
|---|-----|
| Run >3 concurrent sessions | Operator-context overload |
| Skip Phase 10 to save time | Cross-session learning compounds; you'll regret it |
| One operator runs everything | Single point of failure; no buddy review |
| Bootstrap 10 sessions, never resume | Loses cross-session continuity |
| Ad-hoc methodology changes | Track-A discipline (per /operationalizing-expertise) |
| Skip pre-flight quota check | DL-7 quota staircase mid-session |
| Run T4 sessions without buddy | Per OPERATOR-ONBOARDING-CURRICULUM.md trust ladder |
| Catalog-promote patterns after 1 instance | Bar is ≥3 sessions of stable use |
| Archive workspaces by deletion | Per AGENTS.md no-delete; use `mv` to archive |
| Treat skill as static | Skill evolves; weekly/monthly/quarterly maintenance is mandatory |

---

## Composition with /multi-pass-bug-hunting

For at-scale operators, brennerbot deliverables often contain code (deliverables/scripts/) that needs bug-hunting before user acts. The composition:

```
brennerbot Phase 7 audit → produces deliverables/scripts/
   ↓
Phase 7.5 (informal): /multi-pass-bug-hunting on deliverables/scripts/
   ↓
findings folded into brennerbot AF-* beads
   ↓
Phase 8 freeze
```

Per SKILL-COMPOSITION-PATTERNS.md.

---

## When at-scale isn't right yet

For new teams adopting brennerbot:

- Start with 1-2 sessions/week for 4-8 weeks
- Build operator depth via OPERATOR-ONBOARDING-CURRICULUM.md
- Once 2+ operators are buddy-rated, scale to 5-10/week
- Reach 10+/week only after pattern catalogs are populated

Premature scaling produces low-quality output that erodes trust in the methodology.

---

## Cross-references

- [LIVING-DOCUMENTATION-PATTERNS.md](LIVING-DOCUMENTATION-PATTERNS.md) — long-running questions vs fresh sessions
- [CROSS-SESSION-LEARNING.md](CROSS-SESSION-LEARNING.md) — lesson commitment loop
- [OPERATOR-ONBOARDING-CURRICULUM.md](OPERATOR-ONBOARDING-CURRICULUM.md) — buddy system
- [POST-MORTEM-FORMALIZATION-PLAYBOOK.md](POST-MORTEM-FORMALIZATION-PLAYBOOK.md) — incident pattern catalog
- [RECONCILIATION-OF-PRIOR-SESSIONS.md](RECONCILIATION-OF-PRIOR-SESSIONS.md) — reconciliation catalog
- [METHODOLOGY-EVOLUTION-LOG.md](METHODOLOGY-EVOLUTION-LOG.md) — methodology drift tracking
- [/cass](../../cass/SKILL.md) — cross-session search
- [/caam](../../caam/SKILL.md) — quota management at scale
- [SKILL-COMPOSITION-PATTERNS.md](SKILL-COMPOSITION-PATTERNS.md) — composition with adjacent skills
