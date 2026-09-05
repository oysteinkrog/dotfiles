# CONVERGENCE.md — When to Stop a Phase, When to Stop the Session

<!-- TOC: Phase 4 Convergence | Phase 6 Convergence | Phase 7 Convergence | Whole-Session Convergence | Trajectory Convergence | Anti-Patterns in Convergence Detection | Operator-Pace vs Robot-Pace -->

Three different convergence checks operate at different scales:

1. **Per-phase reapply-until-quiet** — Phases 4, 6, 7
2. **Whole-session convergence** — when to stop tending altogether (mirror of `/vibing-with-ntm` OC-016)
3. **Trajectory convergence** — Phase 10 drift-check criterion

---

## Phase 4 Convergence — kill_rate ≥ add_rate

Brenner's bias toward exclusion (§147) is the convergence signal. A round is *productive* if more hypotheses are killed (or refined to higher confidence) than are newly added.

### Formula

```
kill_rate(round) = (# H-* flipped to refuted)
                 + (# H-* flipped to superseded)
                 + 0.5 × (# H-* flipped from medium → low confidence)

add_rate(round)  = (# new H-* with `state: proposed` or `state: active`)
                 + 0.3 × (# H-* flipped from low → medium confidence)

convergence_signal = kill_rate ≥ add_rate
```

The 0.5 / 0.3 weights are heuristic — they reflect that confidence-degrading is *some* progress (you've narrowed the prior) and confidence-upgrading is *some* regress (you've expanded the prior).

### Computing it

```bash
./scripts/convergence-check.sh <workspace> --phase=4 --round=N
```

The script reads bead-state changes since the previous round's commit (via `git log --since="<prev-round-time>" -- .beads/`) and computes the rates.

### Exit gate

- 1 round with `kill_rate ≥ add_rate` AND
- Every active `H-*` has ≥1 supporting `EV-*` AND
- Every active `H-*` has ≥1 attempted falsifier (which may have hit or missed)

If still not converged after 6 rounds: hard-stop, escalate to Phase 10 drift-check or operator hand-decision.

### What "trivial" means in this context

For Phases 6 and 7, "trivial edits" means:

- typo fixes
- formatting/wrapping changes
- citation re-anchoring without claim change
- clarification rewording without semantic change

Anything that changes a claim, adds/removes an `EV-*`, or flips a state is not trivial. The audit script `scripts/dump-session-report.sh § "trivial-edit detector"` flags suspect edits.

---

## Phase 6 Convergence — two consecutive trivial-only meta-synth passes

The meta-synthesizer iterates until two consecutive passes produce only trivial edits to:

- `distillations/meta_synthesis.md`
- `distillations/disagreement_register.md`

### Computing it

```bash
git diff <prev-pass-sha> -- distillations/meta_synthesis.md distillations/disagreement_register.md
```

If the diff is only typos / formatting / re-anchoring, the pass is trivial. Use `scripts/disagreement-register-lint.sh` to verify the register itself satisfies invariants (≥1 entry per pair).

### Exit gate

- 2 consecutive trivial passes
- `disagreement_register.md` has ≥(N choose 2) entries where N = model families in roster
- Every entry cites specific sections in the underlying per-model distillations

Hard cap: 4 meta-synthesis passes. Beyond that: escalate.

---

## Phase 7 Convergence — two consecutive trivial-only trio-rounds

Each pane runs all three fresh-eyes prompts; the round is trivial if all panes' findings are typo/formatting only.

### Computing it

```bash
br list --label=audit-finding --status=open --json | \
  jq --arg since "<prev-round-time>" '[.issues[]?
    | select((.updated_at // .created_at) > $since)
    | select((.description // "") | contains("severity: critical") or contains("severity: high"))
  ] | length'
```

Round is trivial when this count is 0 AND no `H-*` description `state:` changes occurred during the round.

### Exit gate

- 2 consecutive trivial trio-rounds
- 0 open `audit-finding` with severity `critical` or `high`
- `ubs` clean on any code in `deliverables/scripts/`

Hard cap: 4 trio-rounds. Beyond that: escalate to Phase 10 with the un-converged audit findings as drift evidence.

---

## Whole-Session Convergence (when to stop tending altogether)

Mirror of `/vibing-with-ntm` OC-016. Auto-terminate the operator loop when **all** of:

1. **Phase 7 audit converged ≥2 clean rounds.** Hard requirement.
2. **`git log --since="1 hour ago"` shows zero swarm commits** AND no new beads in the last 2 ticks AND every pane's tail contains convergence language ("exemplary", "already complete", "no fixes needed", "ready to ship", "LGTM"). **The convergence-language check requires ALL panes to show it; one pane with active output blocks termination.**
3. **`br ready --json`** returns 0 items AND `br list --status=in_progress --json` is empty or unchanged from previous tick.

When all three hold:
- Stop tending.
- Run Phase 8 freeze.
- Don't keep nudging — that produces prose, not knowledge.

### Liveness Truth Stack (mirror of `/vibing-with-ntm`)

Before believing whole-session convergence:

1. `tmux list-panes` — verify each agent CLI is still running (silent zsh exits are common)
2. `tmux capture-pane -p -S -50` per pane — ground truth for tail
3. `git log --since="15 minutes ago"` + `pgrep -af cargo|rustc|go|bun` — actual build activity
4. `ntm --robot-attention --attention-session=<session> --attention-cursor=<cursor>` — action-required, stalled, rate-limit, mail, context, and source-health hints
5. `ntm --robot-causality=<session> --causality-project=<workspace>` — cross-surface event timeline when pane, bead, mail, and pipeline signals disagree

If two layers disagree, resync before believing convergence.

### Tick cadence (during reapply-until-quiet phases)

| Phase state | Cadence |
|-------------|---------|
| Phase 2 onboarding active (panes booting) | 4 min |
| Phase 3/4/5 active (panes producing) | 10–17 min |
| Phase 6/7 saturating | 30 min |
| Investigating long-running probe | back off to 30 min |

Never sub-3-min poll. Use `ntm --robot-wait=<session> --wait-until=attention --timeout=15m` to get event-driven tending instead of polling.

---

## Trajectory Convergence (Phase 10 drift-check)

This is *not* a stop condition; it's the Phase 10 verdict. The drift auditor compares actual session trajectory to canonical Brenner per [DRIFT-RUBRIC.md](DRIFT-RUBRIC.md). Output:

- **Convergent trajectory** — applied operators in canonical order, with exit criteria all met. Phase 10 produces lessons; nothing structurally to fix.
- **Divergent trajectory** — operators skipped, phases reordered, or exit criteria relaxed. Drift auditor produces explicit replacement-test verdicts.

A divergent trajectory is fine if Phase 10 finds it justified (improvement). It is a regression if not.

---

## Anti-Patterns in Convergence Detection

| ✗ | Why |
|---|-----|
| Trust pane tail "ready to ship" without git log check | Convergence-language false positives are common (per `/vibing-with-ntm` AP-32) |
| Stop Phase 4 after 1 round without kill_rate measurement | Optimistic; you may have only added, not killed |
| Treat trivial-edit detector as trivial-meaning detector | A 1-line change can flip a claim — read the diff |
| Use whole-session convergence to skip Phase 8 freeze | Convergence is about *stopping tending*; Phase 8 is mechanical and always required |
| Let Phase 7 audit dominate by reopening Phase 4 questions | Audit findings → audit beads, not new H beads. Reopens require explicit operator decision and a new T-* test |
| Hard-cap a phase without escalating | Phase 4 hits 6 rounds → don't silently exit; escalate to Phase 10 with un-converged state as evidence |

---

## Operator-Pace vs Robot-Pace

When robot mode is enabled (autonomous unstick + cron-driven ticks), the operator's job is *judgment*: did convergence actually happen, or is it a false positive? Pause robot mode before calling whole-session convergence and verify the Liveness Truth Stack manually. Never let a robot-mode loop trigger Phase 8 freeze without an operator-confirmed pass.

When robot mode is disabled, the operator runs ticks at their own cadence; no special handling.
