# ROBOT-MODE-AUTONOMOUS-ORCHESTRATION.md — Native NTM Robot Mode

<!-- TOC: Why robot mode | Native NTM surfaces | The 3 robot modes | HITL step mode | Per-agent health reporting | Escalation | Robot-stress mode | Convergence detection | Operator notes file | Per-mode safety contract | Anti-patterns | Cross-references -->

For long-running sessions or 10+-session-per-week operators (per BRENNERBOT-AT-SCALE.md), manual orchestration is the bottleneck. Current NTM now provides the native robot substrate for Brenner-style work: cursor-bearing attention feeds, executable pipelines, wait conditions, Agent Mail pipeline steps, causality timelines, support bundles, queue-dry ideation, and machine-readable schemas.

This file specifies the NTM-native robot-mode contract. It exists to make autonomous orchestration **safe** — not to replace operator judgment.

Mined from the BrennerBot methodology corpus, then updated against current `/dp/ntm` commit history, beads, CASS traces, and `ntm --robot-capabilities`.

---

## Why robot mode

Full-manual orchestration:
- 10-17 min per tick (per OBSERVABILITY.md)
- 30-50 ticks per T3 session
- 5-12 hours of operator wall time
- Bottleneck: operator attention

NTM robot mode shifts most ticks to autonomous:
- Operator engages at HITL checkpoints (Phase 1, 5, 7, 9 by default)
- NTM pipelines handle Phase 2-8 routine execution, including command/template/foreach/Agent Mail steps
- `--robot-attention` and `--robot-wait` handle event-driven tending instead of fixed polling
- Operator wall time drops to 1-2 hours per T3 session

**But:** without strong invariants, autonomous mode silently drifts. Robot mode adds:
- Per-agent health reporting + timeout escalation
- HITL step mode (run one round; pause for review)
- Convergence detection (auto-stop when kill_rate ≥ add_rate threshold)
- Operator notes file and causality/support bundles (any-time intervention + audit trail)

---

## Native NTM surfaces

Use these instead of the old `brenner session robot ...` commands:

| Need | NTM surface |
|---|---|
| Discover exact command/flag schema | `ntm --robot-capabilities`; `ntm --robot-schema=<type>` |
| Bootstrap baseline + cursor | `ntm --robot-snapshot` |
| Steady-state tending | `ntm --robot-attention --attention-cursor=<cursor> --attention-session=<session> --profile=operator` |
| Raw replay/debug | `ntm --robot-events --since-cursor=<cursor> --events-limit=100` |
| Non-blocking summary | `ntm --robot-digest --profile=operator` |
| Wait for specific state | `ntm --robot-wait=<session> --wait-until=action_required --attention-cursor=<cursor>` |
| Execute phase pipeline | `ntm pipeline run <file> --session <session>` or `ntm --robot-pipeline-run=<file> --session=<session>` |
| Inspect/cancel pipeline | `ntm pipeline status <run-id> --json`; `ntm --robot-pipeline=<run-id>`; `ntm --robot-pipeline-cancel=<run-id>` |
| Reconstruct what happened | `ntm --robot-causality=<session> --causality-project=<workspace>` |
| Freeze diagnostics | `ntm --robot-support-bundle=<session> --bundle-output=<path>` |
| Empty queue handling | `ntm work queue-dry --ideate --format=json` |
| Tool health | `ntm --robot-tools` |
| Diverse reasoning-mode swarm | `ntm --robot-ensemble-suggest=<question>` and `ntm --robot-ensemble-spawn=<session> --question=<question> ...` |

Cursor rule: every autonomous loop starts with `--robot-snapshot`, uses the returned cursor for `--robot-attention`, and resyncs with snapshot if the cursor expires.

---

## The 3 robot modes

There is no separate BrennerBot runtime command in the NTM-native flow. The "mode" is an operator policy implemented with NTM pipeline, attention, wait, and send/interrupt surfaces.

### `autonomous`

Full-autonomous: run all rounds until convergence or max-rounds reached.

```bash
ntm --robot-pipeline-run=.ntm/pipelines/brennerbot-squad.yaml \
  --session=RS-YYYYMMDD-slug \
  --vars='{"workspace_path":"/abs/workspace","session_id":"RS-YYYYMMDD-slug","mode":"fresh-question"}' \
  --pipeline-background
ntm --robot-attention --attention-session=RS-YYYYMMDD-slug --attention-cursor=<cursor> --profile=operator
```

Per-round behavior:
1. Run the phase pipeline or current loop body.
2. Wait through `--robot-attention` / `--robot-wait` for action-required, pipeline-completed, error, or timeout state.
3. Parse + apply deltas through the phase scripts and bead invariants.
4. Compute convergence (kill_rate / add_rate ratio).
5. If converged -> stop; else next round.
6. If max-rounds reached -> stop; emit "did-not-converge" verdict and support bundle.

**Use when:** session is mid-Phase-4 or Phase-6, methodology is well-tested, operator can't be present.

### `step`

HITL: run **one round**, then exit. Operator reviews; re-runs to advance.

```bash
ntm pipeline run .ntm/pipelines/brennerbot-squad.yaml \
  --session RS-YYYYMMDD-slug \
  --start-from phase_4_loop \
  --var workspace_path=/abs/workspace \
  --var session_id=RS-YYYYMMDD-slug

# Operator reviews artifact, beads, mail thread, attention digest.
ntm --robot-causality=RS-YYYYMMDD-<slug> --causality-project=/abs/workspace --causality-since=2h
```

**Use when:** operator wants per-round oversight; building trust with autonomous orchestration; high-stakes session.

### `stress`

Adversarial stress test on **surviving hypotheses**.

```bash
ntm --robot-send=RS-YYYYMMDD-<slug> \
  --type=gmi \
  --msg="$(sed "s/H_ID/H-001/g" assets/marching-orders/MO-pre-publication-review.md)"
ntm --robot-wait=RS-YYYYMMDD-<slug> --wait-until=idle --type=gmi --timeout=30m
```

For each H in target state (`validated` or `active`):
1. Spawn fresh Devil's-Advocate pane (different model family from original critic)
2. Provide H + supporting evidence
3. Demand: produce ≥1 critique with severity ≥ serious, OR explicit "no attack found" with reason
4. File critiques per Tribunal protocol

**Use when:** Phase 7 audit; pre-publication review (per MO-pre-publication-review.md); T4+ sessions before HANDBACK. Prefer `--robot-ensemble-spawn` when the stress round needs reasoning-mode diversity, not just a different model family.

---

## HITL step mode

Step mode is the **default safety net** for new operators or high-stakes work:

```
Step 1: Phase 1 framing (manual)
Step 2: Phase 2 bootstrap (auto)
Step 3: Phase 3 hypothesis (auto, single round)  ← HITL pause
Step 4: Phase 4 round 1 (auto)                   ← HITL pause
Step 5: Phase 4 round 2 (auto)                   ← HITL pause
...
Step N: Phase 5 cross-exam (manual)
...
```

The HITL pause produces a **summary**:

```
=== Step 4 complete ===
Phase: 4 (investigation)
Round: 1 of estimated ~3
Deltas applied: 7 (3 ADD-EV, 2 ADD-C, 2 EDIT-H confidence)
Hypothesis state changes: H1 active → under_attack (per C-002)
Convergence: kill_rate=0, add_rate=0.4 (ratio 0; not converged)
Time elapsed: 12 minutes (vs estimated 15)
Per-agent health: cc=ok, cod=ok, gmi=warning (slow response)

Operator decision:
  [c]ontinue → next round
  [a]bort → halt session
  [m]anual → pause for manual intervention
  [r]eview → open artifact in browser
```

The operator decides. No autonomous progression past a pause.

For T1-T2: skip HITL; use autonomous.
For T3: HITL at Phase 3, 5, 7.
For T4+: HITL after every round.

---

## Per-agent health reporting

Robot mode tracks per-agent health every round:

| Status | Meaning | Auto-action |
|--------|---------|-------------|
| `ok` | Response within budget; valid deltas | Continue |
| `slow` | Response took >75% of timeout | Warning; reduce next round's budget |
| `warning` | Response took 100% of timeout but completed | Log; consider replacement |
| `timeout` | No response within timeout | Evidence-first escalation (next section) |
| `error` | Response received but failed parsing | Log delta-protocol failure (per DELTA-PROTOCOL-FAIL-FAST.md) |
| `disconnected` | Pane crashed or lost connection | Mark dead; next round skip + alert |

Health output:

```json
{
  "round": 4,
  "agents": {
    "BlueLake": { "status": "ok", "duration_ms": 14000, "deltas_applied": 3 },
    "PurpleMountain": { "status": "warning", "duration_ms": 87000, "deltas_applied": 2, "note": "98% of timeout used" },
    "GreenValley": { "status": "timeout", "duration_ms": 90000, "deltas_applied": 0, "note": "escalation required; replacement likely" }
  }
}
```

Per Phase 7 audit + OPERATOR-CALIBRATION-LOG.md, persistent `slow`/`warning` for the same pane indicates model-fit issue (e.g., the model is too small for the role's complexity).

---

## Escalation

When an agent times out, NTM-native robot mode escalates from evidence to intervention:

1. **Classify** with `ntm --robot-wait=<session> --wait-until=attention` plus `ntm --robot-tail=<session> --panes=<N> --lines=80`.
2. **Differentiate** stalled generation, rate limit, OAuth/login failure, dead pane, and mere long reasoning. Do not treat all silence as equivalent.
3. **Interrupt** with `ntm --robot-interrupt=<session> --panes=<N> --msg='<short recovery instruction>'` when the pane is alive but stuck on the wrong task.
4. **Respawn/replace** through the session roster path when the process exited, auth is broken, or the model family is a bad role fit.
5. **Record** the degraded state in the bead/mail thread and, for hard failures, capture `ntm --robot-support-bundle=<session>`.
6. **Continue or abort** according to the tier's HITL contract.

The escalation is **deterministic**: fixed timeout budget, fixed evidence checks, fixed intervention ladder. Avoid "wait until it feels stuck" and avoid raw process-kill primitives unless the project policy and user have explicitly authorized them.

Why? Because in autonomous mode, indefinite waits cascade. One stuck pane delays the round; delayed rounds delay convergence; delayed convergence wastes operator wall time. But blind termination also destroys evidence and can discard useful partial reasoning, so NTM's current operator loop prefers robot facts first.

---

## Robot-stress mode (separate)

After Phase 5 / Phase 7, surviving hypotheses (`active` or `validated`) get **adversarially stressed**:

```bash
ntm --robot-ensemble-spawn=RS-YYYYMMDD-<slug> \
  --question="Stress-test H-001 and H-003 against their evidence chains" \
  --agents=cc,cod,gmi \
  --assignment=adversarial_review \
  --allow-advanced
```

For each target:
1. **Fresh Devil's-Advocate** spawned (different model family from original session's critic)
2. **Briefing**: full H + evidence + assumption chain + prior critiques
3. **Mandate**: "find ≥1 attack with severity ≥ serious, OR explicitly state 'no attack found' with the reasoning trail"
4. **Output**: structured critique (per Tribunal protocol)

The mandate is asymmetric — the stress critic must EITHER find a flaw OR document why none was found. "Looks fine" is not acceptable.

If the stress mode finds critical flaws → H transitions back to `under_attack`; session may need re-opening.
If the stress mode finds nothing → that's evidence the hypothesis is robust → contributes to validated-state confidence.

---

## Convergence detection

Robot autonomous mode auto-stops when convergence is reached:

```
convergence_score(round) = (kill_rate × 0.5) + (audit_finding_rate_inverse × 0.3) + (state_stability × 0.2)
```

Where:
- `kill_rate` = (Hs killed this round) / (total active Hs at round start)
- `audit_finding_rate_inverse` = 1 - (audit findings this round / max baseline)
- `state_stability` = % of H beads with same state as previous round

Threshold default: 0.7. Above → stop; below → continue.

Per CONVERGENCE.md: this matches the operator's intuition for "we've reached methodology saturation." 3 consecutive rounds at convergence > threshold → guarantee stop.

Operator can override:

```bash
./scripts/convergence-check.sh --phase=4 --threshold=0.85   # stricter
./scripts/convergence-check.sh --phase=4 --threshold=0.50   # looser; for T1-T2
```

---

## Operator notes file

Even in autonomous mode, the operator can intervene asynchronously via a notes file:

```bash
echo "Pause at Phase 5; I want to review H-3 manually before debate" > workspace/operator-notes.md
```

The robot reads this file at the start of every round. If the file mentions:
- "Pause at Phase X" → enter HITL step mode at that phase
- "Skip Phase X" → skip (only valid for optional phases)
- "Force kill H-NNN" → manual KILL operation
- "Abort" → halt session, emit partial HANDBACK

BrennerBot established the useful behavior here: no notes is OK, but silent failure to read an expected notes file is not. In NTM-native runs, preserve that contract by logging the note-file status and making operator interventions visible through the causality timeline.

This gives the operator an **always-available off-ramp** without abandoning the session.

---

## Per-mode safety contract

| Mode | Operator wall time | Auto-stop conditions | HITL pauses |
|------|---------------------|----------------------|-------------|
| `autonomous` | ~5% of session | Convergence > threshold; max-rounds reached; abort signal | None unless operator-notes.md says |
| `step` | ~50% of session | Always pauses after each round | Every round |
| `stress` | ~10% of session | All targets processed | Pre-launch confirmation only |

For T4+ sessions: never use `autonomous` without HITL pauses. Per BRENNERBOT-AT-SCALE.md operator-buddy pattern: a shadow operator monitors even autonomous mode.

---

## Anti-patterns

| ✗ | Why |
|---|-----|
| Run T4+ session in `autonomous` without HITL | High-stakes verdicts need operator review |
| Skip per-agent health monitoring | Slow panes silently degrade convergence |
| Kill or respawn panes without robot evidence | Destroys partial work and hides the true failure mode |
| Ignore convergence-score; force max-rounds | Wastes budget; methodology saturated |
| Run stress mode on `active` H without prior Phase 5 debate | Premature stress; debate hasn't happened |
| Re-stress with same model family as original critic | Same biases; no new attack surface |
| Edit operator-notes.md mid-round | Race; notes read at round start |
| Treat `disconnected` agent as transient | Investigate; could be model API outage, OOM, etc. |
| Skip robot-stress for T4+ sessions | Per safety contract: T4+ verdicts need post-survival adversarial pass |

---

## Composition with brennerbot phases

| Phase | Robot-mode default |
|-------|---------------------|
| 1 framing | manual (no robot mode) |
| 2 bootstrap | autonomous (low-risk) |
| 3 hypothesis | step (HITL after first round) |
| 4 investigation | autonomous (with HITL every 3 rounds) |
| 5 cross-exam | step (HITL after each pair) |
| 6 distillation | autonomous |
| 7 audit | step (HITL) |
| 7+: stress | stress mode |
| 8 freeze | manual |
| 9 handback | manual |
| 10 drift | autonomous |

For T1-T2: most phases autonomous.
For T3: defaults above.
For T4+: most phases step; stress mandatory; operator-buddy active.

---

## Cross-references

- [HYPOTHESIS-LIFECYCLE-STATE-MACHINE.md](HYPOTHESIS-LIFECYCLE-STATE-MACHINE.md) — state transitions in autonomous mode
- [CONVERGENCE.md](CONVERGENCE.md) — convergence formula
- [DELTA-PROTOCOL-FAIL-FAST.md](DELTA-PROTOCOL-FAIL-FAST.md) — health reporting tied to parser failures
- [TRIBUNAL-AND-OBJECTION-REGISTER.md](TRIBUNAL-AND-OBJECTION-REGISTER.md) — robot-stress files critiques
- [BRENNERBOT-AT-SCALE.md](BRENNERBOT-AT-SCALE.md) — operator-buddy pattern
- [OPERATOR-CALIBRATION-LOG.md](OPERATOR-CALIBRATION-LOG.md) — per-agent health trends
- [SESSION-REPLAY-AND-REPRODUCIBILITY.md](SESSION-REPLAY-AND-REPRODUCIBILITY.md) — record robot session for replay
- [NTM-PIPELINES.md](NTM-PIPELINES.md) — executable phase pipelines
- [OPERATOR-INTERVENTION-RECORDING.md](OPERATOR-INTERVENTION-RECORDING.md) — notes/intervention audit trail
