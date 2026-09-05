# NTM-PATTERNS-DEEP.md — Research-Session-Specific NTM Tactics

<!-- TOC: Why this layer | Pane affinity | Robot-mode patterns | Pipeline vs manual | Tmux layout | Account rotation | Cross-machine continuity | Performance tuning -->

`/ntm` skill covers the full NTM command surface. `/vibing-with-ntm` covers operator-loop tactics. This file documents NTM patterns *specifically* tuned for brennerbot research sessions.

For pure NTM operations, defer to `/ntm`. For pure operator-loop, defer to `/vibing-with-ntm`. Use this file when the *intersection* (research-session NTM tactics) matters.

---

## Why this layer

Research sessions have specific NTM needs that coding-swarm sessions don't:

- Per-H "thread continuity": Investigators stay on the same H across many rounds; pane-H affinity matters
- Cross-family balancing: distillation triangulation requires deliberate family mix
- Adjudicator rotation: enforced by methodology, not just by tooling
- Long-horizon sessions: hour-scale Phase 4 investigations need different cadence

This file captures those specific tactics.

---

## Pane affinity for cross-debate continuity

### Default: round-robin domain assignment

Per `assign-investigator-domains.sh`: each H is assigned to one Investigator pane round-robin. Simple but suboptimal for Phase 5 debate continuity.

### Better: H-pane affinity tracking

For T3+ sessions, maintain H→pane affinity in `phase0_scope_decision.md`:

```yaml
domain_assignments:
  - h: H-005
    primary_investigator: pane-3 (cc)
    secondary_investigator: pane-4 (cod)  # for backup if pane-3 saturates
    devils_advocate: pane-5 (gmi)
    # Phase 5 uses primary_investigator as champion
```

When pane-3 saturates (per S11 STRESS-TEST scenario), domain hands off to pane-4 with continuity bead. Phase 5 debates leverage continuity; champions know their H deeply.

### Rotation rules per Phase 5

- Champions: H's primary_investigator (NOT secondary unless primary unavailable)
- Adjudicator: NEITHER champion's family; preferably a family that hasn't adjudicated this H pair before
- Per OC-014 + OC-015 in OPERATOR-CARDS.md

---

## Robot-mode patterns for research

### Tick cadence per phase

Per OBSERVABILITY.md and `/vibing-with-ntm`:

| Phase | Cadence | Robot-mode tool |
|-------|---------|-----------------|
| 1 framing | n/a (operator+user) | none |
| 2 bootstrap | 4 min during onboarding | `wait-for-onboard-acks.sh` |
| 3 propose | 5-10 min | `--robot-tail`, `--robot-snapshot` |
| 4 investigate | 10-17 min | `tick.sh` (composed snapshot) |
| 5 debate | 5-10 min | `--robot-tail` per debate thread |
| 6 distill | 15-30 min | `--robot-tail` for distillation panes |
| 7 audit | 10-17 min | `tick.sh` + `convergence-check.sh` |

### Event-driven instead of polling

For Phase 4-7 (long phases), use `ntm --robot-wait=<session> --wait-until=attention` instead of fixed-cadence polling:

```bash
# Wait for any event (new mail, pane state change, etc):
ntm --robot-wait=<session> --wait-until=attention --timeout=15m

# Wait for specific events:
ntm --robot-wait=<session> --wait-until=action_required --attention-cursor=<cursor>
ntm --robot-wait=<session> --wait-until=mail_ack_required --attention-cursor=<cursor>
```

Saves operator context vs continuous polling.

### Quiet-mode tail capture

For Phase 4 rounds where panes work for ~20 min:

```bash
# Capture tail every 5 min instead of full snapshot:
ntm --robot-tail=<session> --panes=3,4,5,6,7 --lines=10
```

Smaller payload; faster operator review.

---

## Pipeline vs manual dispatch

### When to use pipelines

Pipelines (`assets/ntm-pipelines/*.yaml`) good for:

- Phases 2-8 in standard `fresh-question` mode (Squad, Pair, or Swarm)
- Resume sessions (`brennerbot-resume.yaml`)
- Compressed incident mode (`brennerbot-incident.yaml`)
- Repeat sessions on similar archetypes (re-use proven config)

### When to use manual dispatch

Manual dispatch (via `dispatch-marching-order.sh`) good for:

- Phase 1 framing (judgment-heavy)
- Mid-session re-rostering (operator decides rebalance)
- Custom operator-card application (e.g., MO-cross-domain-import, MO-quickie-pilot)
- Phase 9 handback (typically operator + synthesizer)
- Phase 10 drift (fresh general-purpose Agent)
- T1-T2 sessions where pipeline overhead exceeds session size

### Hybrid pattern

Most T3+ sessions use:

```
Phase 1: manual (operator framing)
Phase 2-7: pipeline runs autonomously
Phase 8: pipeline freezes; operator reviews
Phase 9: manual (handback writing)
Phase 10: manual (fresh agent dispatch)
```

The pipeline handles the mechanical Phase 2-7 work; the operator handles judgment-heavy phases.

---

## Tmux layout patterns

For Squad+ rosters, tmux layout matters for operator visibility:

### Recommended layout (Squad, 5 panes)

```
┌──────────────┬──────────────┐
│ pane 0       │ pane 1       │
│ (operator)   │ (Proposer)   │
├──────────────┼──────────────┤
│ pane 2       │ pane 3       │
│ (Investigator│ (Investigator│
│  cc)         │  cod)        │
├──────────────┼──────────────┤
│ pane 4       │ pane 5       │
│ (Devil's-Adv │ (Synthesizer │
│  gmi)        │  cc)         │
└──────────────┴──────────────┘
```

Operator pane in top-left for visibility. Investigators next (most active during Phase 4). Devil's-advocate adjacent. Synthesizer in corner (most active in Phase 6).

### Recommended layout (Swarm, 10 panes)

```
┌──────┬──────┬──────┐
│ p0   │ p1   │ p2   │  Operator + 2 Proposers
├──────┼──────┼──────┤
│ p3   │ p4   │ p5   │  3 Investigators
├──────┼──────┼──────┤
│ p6   │ p7   │ p8   │  2 Devil's + 1 Synth
├──────┼──────┼──────┤
│ p9   │ p10  │ p11  │  2 Synth + Meta-synth
└──────┴──────┴──────┘
```

Use `ntm` recipes (per `/ntm` `recipes show`) for repeatable layouts.

### Anti-pattern

Don't fan-out too wide (3+ columns). Operator has limited eye-attention; 2-3 columns max. For Swarm, vertical scroll is OK.

---

## Account rotation patterns

Per `/vibing-with-ntm` OC-002 (rate-limit rotate). For research sessions specifically:

### Pre-warm accounts

For T3+ sessions, pre-warm CAAM accounts before bootstrap:

```bash
# Cycle through cc accounts before starting
caam ls --provider=claude
caam use jeff2718281@... --provider=claude
# Verify quota:
ntm --robot-quota-status
```

This avoids the S5 (multi-pane simultaneous rate-limit) scenario.

### Per-pane account binding

For Squad+ tier with multiple cc panes, bind each cc pane to a different account:

```bash
ntm spawn RS-YYYYMMDD-<slug> --cc=3 --cc-accounts="jeff1@...,jeff2@...,jeff3@..."
```

Distributes quota; reduces simultaneous rate-limit risk.

### Mid-session rotation

If pane-3 hits rate limit:

```bash
# 1. Check attention + OAuth state:
ntm --robot-attention --attention-session=<session> --attention-cursor=<cursor>
ntm --robot-health-oauth=<session> --panes=3

# 2. Rotate pane-3's account:
ntm rotate <session> --pane=3 --account=jeff_alt@...

# 3. Verify recovery:
ntm --robot-tail=<session> --panes=3 --lines=20
```

If rotation fails, kill+respawn with fresh account.

---

## Cross-machine continuity

For multi-day or distributed sessions:

### Checkpoint export

```bash
# At end of work-session day:
ntm checkpoint save <session> -m "End of Day 1"
ntm checkpoint export <session> <id>
# Archive lives at .ntm/checkpoints/<id>.tar.gz

# Move to other machine:
scp <id>.tar.gz user@other-machine:~/

# Import on other machine:
ntm checkpoint import <id>.tar.gz
```

Combined with `RESUME.md` (per RESUME-PROTOCOL.md), sessions are fully portable.

### Cursor expiry across machines

NTM cursors are per-server monotonic. Across machines, cursor must be re-bootstrapped:

```bash
# After resume on new machine:
ntm --robot-snapshot  # gets fresh cursor for this machine
```

Then continue with new cursor.

---

## Performance tuning

### Large corpus sessions

For corpus >500MB:

```bash
# Avoid --lines=2000 tail captures (large payloads)
ntm --robot-tail=<session> --lines=50

# Use --robot-format=toon (more compact than JSON)
export NTM_ROBOT_FORMAT=toon
ntm --robot-snapshot
```

### Many panes (Swarm 10+)

Avoid full snapshot every tick:

```bash
# Cheaper alternatives:
ntm --robot-terse           # 1-line state per session
ntm --robot-attention --attention-session=<session> --attention-cursor=<cursor>  # delta + action hints
ntm --robot-is-working=<session>   # legacy boolean per pane only; use as supporting detail
```

### Long-running sessions

For sessions running >4h:

```bash
# Periodic checkpoint to recover from crashes:
*/30 * * * * ntm checkpoint save <session> -m "auto-snapshot"
```

Cron-driven; combine with `/loop` skill or system cron.

---

## Specific anti-patterns for research-session NTM

| ✗ | Why |
|---|-----|
| Spawn Squad without explicit role assignment | Panes claim overlapping roles (F-203) |
| Use `ntm view` from automation | Retiles operator's tmux; never useful in pipelines (per /ntm gotchas) |
| Send via `--all` without `-s/--skip-first` | Hits operator's zsh; produces "command not found" noise |
| Skip pre-warming accounts for T4+ | Higher S5 (rate-limit cluster) risk |
| Cursor caching across days | Stale; re-snapshot daily |
| Same checkpoint on multiple machines simultaneously | State conflicts; one machine should "own" the session |
| `ntm send` without `--no-cass-check` in robot loops | CASS dedup pause blocks loops silently |
| Use `--robot-restart-pane` casually | Destroys pane state; use only after smart-restart fails |

---

## Composition with /vibing-with-ntm

For any operational concern (stuck pane, rate limit, OAuth, context saturation), defer to `/vibing-with-ntm` cards:

- OC-001 rate-limit probe
- OC-002 rotate
- OC-003 stuck-pane ladder
- OC-016 convergence triple-check
- OC-026 pid audit
- OC-031 cross-session contention

This file is *additive* — research-specific patterns ON TOP of vibing-with-ntm's general operator loop.

---

## Phase 10 lesson loop

When a session reveals a useful new NTM pattern:

1. Document trigger condition + recipe
2. Add to this file
3. Phase 10 lesson commits the change

Patterns that recur ≥3 times across sessions get promoted to canonical (per CROSS-SESSION-LEARNING.md). The catalog grows with operator experience.
