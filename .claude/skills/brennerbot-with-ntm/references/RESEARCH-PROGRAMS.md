# RESEARCH-PROGRAMS.md — Multi-Session Aggregation Above Single Sessions

<!-- TOC: Why programs | The Program lifecycle | The hypothesis funnel | Registry health metrics | Timeline events | Programs vs sessions vs reconciliation | When to start a program | The pause/resume/abandon flow | Per-program meta-metrics | Anti-patterns | Cross-references -->

A single brennerbot session answers a single research question. But many real research efforts span **months** and **dozens of sessions** — investigating cell fate determination, hardening an auth system, exploring a design space.

For these multi-session efforts, brennerbot adds the **Research Program** abstraction: a coherent multi-session container with hypothesis funnel, registry health, timeline events, and explicit lifecycle.

This file specifies the program abstraction, its dashboards, and when to use it.

Mined from `/dp/brenner_bot/README.md § Research Program Orchestration`.

---

## Why programs

Three failures of single-session-only:

1. **Hypothesis evolution invisible** — H-001 in session A becomes H-005 in session B becomes H-002 in session C; the lineage is hidden across artifacts
2. **Registry drift** — assumptions verified in session A get re-verified (or worse, re-falsified) in session B without anyone noticing
3. **No directional metric** — "are we converging on an answer over time?" can't be answered

Three benefits of programs:

1. **Hypothesis funnel** — proposed → active → killed/validated tracked across all sessions
2. **Registry health** — assumptions/anomalies/critiques aggregate per program, not per session
3. **Timeline events** — chronological view of major events across the program

---

## The Program lifecycle

```
active → paused → completed
              ↘ abandoned
```

States:
- `active`: ongoing; new sessions can be added
- `paused`: temporary halt with documented reason; can resume
- `completed`: research goal achieved; immutable
- `abandoned`: research halted; documented reason; immutable

Transitions:

```bash
brenner program create --name "Cell Fate Determination" --description "Investigating positional information"
brenner program pause RP-CELL-FATE-001 --reason "Waiting for CRISPR reagents"
brenner program resume RP-CELL-FATE-001
brenner program complete RP-CELL-FATE-001 --summary "Validated threshold model; gradient hypothesis killed"
brenner program abandon RP-CELL-FATE-001 --reason "Funding ended; see RP-NEURAL-CREST-001 for continuation"
```

`completed` and `abandoned` are terminal — but the program record is preserved (per AGENTS.md no-deletion rule).

---

## The hypothesis funnel

Per program, track:

```
Proposed → Active → Under Attack → Killed/Validated
    12        5           2            7 / 0
```

Funnel metrics:

| Metric | Formula |
|--------|---------|
| `proposal_rate` | new H per session-week |
| `activation_rate` | (active H) / (proposed H) |
| `attack_rate` | (under_attack H) / (active H) |
| `kill_rate` | (killed H) / (proposed H total) |
| `validation_rate` | (validated H) / (proposed H total) |
| `dormant_rate` | (dormant H) / (proposed H total) |

Healthy program: kill_rate + validation_rate ≥ 0.6 (most H reach a verdict). Unhealthy: dormant_rate > 0.4 (sessions are too-broadly-scoped or too-quickly-frozen).

---

## Registry health metrics

Per program, aggregate registry health:

```
Assumptions: 8 total
  - 5 verified
  - 2 challenged
  - 1 unchecked

Anomalies: 3 total
  - 1 resolved
  - 1 deferred
  - 1 active

Critiques: 5 total
  - 4 addressed
  - 1 active
```

Health thresholds:
- `unchecked_assumptions / total_assumptions` ≤ 20% → green; > 20% → flag
- `active_anomalies / total_anomalies` ≤ 30% → green
- `active_critiques / total_critiques` ≤ 20% → green; > 50% → red (program-level audit-finding)

Per Phase 7 audit at program-level: registry-health red flags are surfaced.

---

## Timeline events

Programs maintain a chronological event log:

```
2025-12-30 09:00  [hypothesis_proposed] H-RS20251230-001 created
2025-12-30 11:30  [test_executed] T-RS20251230-001 completed
2025-12-30 14:00  [hypothesis_killed] H-RS20251230-001 refuted by T-RS20251230-001
2026-01-05 10:15  [session_completed] RS-20260105 closed (verdict: H-005 validated)
2026-01-12 16:00  [program_paused] Reason: Waiting for CRISPR reagents
2026-02-20 09:30  [program_resumed]
2026-02-22 14:00  [hypothesis_validated] H-RS20260222-003 validated
```

Events are append-only; preserve audit trail across program lifetime.

Per BRENNERBOT-AT-SCALE.md: timelines are the basis for cross-program meta-analysis (e.g., "average time-to-validation across our 8 active programs is 6 weeks").

---

## Programs vs sessions vs reconciliation

| Concept | Scope | When to use |
|---------|-------|-------------|
| Session | Single research question | Default for any focused inquiry |
| Reconciliation | Multi-session conflict resolution | When ≥2 sessions reach divergent verdicts on similar questions |
| Program | Multi-session research effort | When the research goal requires ≥3 sessions and shared registry |

Sessions can exist without programs. Programs **require** sessions (a program with 0 sessions is just a name).

Per RECONCILIATION-OF-PRIOR-SESSIONS.md: reconciliation events between sessions in the same program are program-level events (logged in the timeline).

---

## When to start a program

Triggers:

- **Research goal spans ≥3 anticipated sessions** (e.g., "investigate cell fate determination" — too broad for one session)
- **Multi-week or multi-month duration** with intermittent sessions
- **Multiple operators contributing** to the same overarching question
- **Stakeholder asks "what's the status of <topic>?"** — programs answer this; sessions don't

Don't start a program for:
- Single-session questions ("which library should we use?")
- One-off audits ("review this PR")
- Reactive incident-investigation (use post-mortem-formalization mode instead)

For T1-T2 sessions: never need a program.
For T3 sessions: rare; usually fits in one session.
For T4+: programs are common (typically 4-12 sessions).
For T5 (existential): programs are mandatory; existential questions span months.

---

## The pause/resume/abandon flow

### Pause

```bash
brenner program pause RP-... --reason "Waiting for X"
```

Effects:
- All sessions in the program lock to read-only
- Timeline event: `program_paused`
- HANDBACK includes "Program Status: Paused (reason)"
- Operator can still query historical sessions; can't add new ones

Use when: external blockers (data, reagents, decisions) prevent forward progress.

### Resume

```bash
brenner program resume RP-...
```

Effects:
- Sessions can be added again
- Timeline event: `program_resumed`

### Complete

```bash
brenner program complete RP-... --summary "..."
```

Effects:
- Program is locked; no more sessions
- Final summary is the program-level HANDBACK
- Timeline event: `program_completed`
- Per BRENNERBOT-AT-SCALE.md: completed programs feed methodology-evolution-log

Use when: research goal is achieved (validated H found OR all H killed without successor).

### Abandon

```bash
brenner program abandon RP-... --reason "Funding ended"
```

Effects:
- Program is locked
- `--reason` is mandatory; abandonment requires justification
- Timeline event: `program_abandoned`
- Sessions remain queryable (per AGENTS.md no-deletion)

Use when: external factors (funding, scope change, redundancy with another program) end the research.

Per AGENTS.md: abandonment ≠ deletion. The program record persists indefinitely.

---

## Per-program meta-metrics

Beyond hypothesis funnel + registry health, programs track:

| Metric | Description |
|--------|-------------|
| `time_to_first_validation` | wall-time from program creation to first validated H |
| `time_to_first_kill` | wall-time to first killed H |
| `session_density` | sessions per week of active program time |
| `cross_session_reconciliations` | count of Type-N reconciliations across program sessions |
| `meta_kill_rate` | kills per total H proposed across all program sessions |
| `meta_validation_rate` | validations per total H |

These aggregate across sessions and inform program-level Phase 10 drift checks.

---

## Anti-patterns

| ✗ | Why |
|---|-----|
| Start a program for every session | Programs add overhead; only when multi-session |
| Don't pause when blocked; let "active" rot | Stale "active" programs pollute pool dashboards |
| Abandon without reason | Reason is mandatory; lost-context risk |
| Continue adding sessions after `complete` | Completion is terminal; create a successor program if research re-opens |
| Skip program-level Phase 7 audit | Single-session audits miss cross-session drift |
| Treat program HANDBACK as session HANDBACK | Different scope; HANDBACK-VOICE-GUIDE.md applies but tier-up |
| Lose program ID across sessions | Cross-link via session metadata `program_id: RP-...` |

---

## CLI reference

```bash
brenner program create --name "..." --description "..."
brenner program list
brenner program list --status active
brenner program show RP-...
brenner program dashboard RP-...
brenner program add-session RP-... --session RS-...
brenner program remove-session RP-... --session RS-...
brenner program pause RP-... --reason "..."
brenner program resume RP-...
brenner program complete RP-... --summary "..."
brenner program abandon RP-... --reason "..."
```

---

## Cross-references

- [HYPOTHESIS-LIFECYCLE-STATE-MACHINE.md](HYPOTHESIS-LIFECYCLE-STATE-MACHINE.md) — H state aggregation in funnel
- [RECONCILIATION-OF-PRIOR-SESSIONS.md](RECONCILIATION-OF-PRIOR-SESSIONS.md) — cross-session conflict resolution
- [TRIBUNAL-AND-OBJECTION-REGISTER.md](TRIBUNAL-AND-OBJECTION-REGISTER.md) — registry of program-level critiques
- [BRENNERBOT-AT-SCALE.md](BRENNERBOT-AT-SCALE.md) — multi-program coordination
- [HANDBACK-VOICE-GUIDE.md](HANDBACK-VOICE-GUIDE.md) — program-level summaries
- [METHODOLOGY-EVOLUTION-LOG.md](METHODOLOGY-EVOLUTION-LOG.md) — completed programs feed back
- /dp/brenner_bot/README.md § Research Program Orchestration — feature source
