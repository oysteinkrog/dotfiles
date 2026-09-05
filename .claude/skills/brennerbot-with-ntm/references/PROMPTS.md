# PROMPTS.md — Operator-Side Prompt Library

<!-- TOC: Self-prompts at phase boundaries | Diagnostic self-prompts when stuck | When to escalate | Quality-protection prompts | Inter-skill coordination prompts | User-facing communication discipline | Authoring rules for new prompts -->

Marching orders go from operator → pane. This file collects **operator-side prompts** — what the operator says to themselves (or to subagents) to make better decisions during a session.

Mirrors `/vibing-with-ntm` PROMPTS.md but tuned for research-session orchestration.

---

## Section A — Self-prompts at phase boundaries

### A1 — End-of-Phase-1 self-check

Before exiting Phase 1, ask yourself:

```
Phase 1 ready-to-exit checklist:

1. Could a hostile reader misread "Out of Scope" in question_of_record.md? If yes → tighten before exit.
2. Could an Investigator probe the Falsifier in <1h? If no → make it cheaper or pick a proxy via ⟂.
3. Does the Paradox actually motivate the Question? Or is it post-hoc rationalization? If post-hoc → re-anchor on a real tension.
4. What action changes if the answer is X vs Y vs Z? If no action changes for some answer → the question is incomplete.
5. Have I cited ≥1 §-anchor in the source corpus that motivates the framing? If 0 → drift risk.

If any answer is "no", run MO-01-frame-question.md again before dispatching MO-02.
```

### A2 — Pre-Phase-4-round dispatch self-check

```
Before dispatching another Phase 4 round, ask:

1. Did the previous round file ≥1 EV.refutes:? If 0, dispatch MO-mode-flip-investigator-to-advocate.md to ≥1 pane.
2. Did the previous round have falsifier-firing events? If 0, schedule a quickie via MO-quickie-pilot.md (Tier 1).
3. Are anomalies clustering? If ≥2 share a feature, dispatch MO-anomaly-cluster.md (Tier 2).
4. Has any pane filed only confirmations across multiple rounds? Flip its role.
5. Is convergence-check.sh reporting kill_rate ≥ add_rate? If yes for ≥1 round, exit Phase 4.

Dispatch checklist:
  - Each Investigator has H assigned
  - Devil's-Advocates targeted at top-confidence H
  - Domains balanced (no investigator with 0 work; no investigator with >3 H)
  - Specific-terse nudges only (per /vibing-with-ntm AP-21)
```

### A3 — Pre-Phase-7-audit-trio self-check

```
Before launching another Phase 7 trio-round, ask:

1. Has the prior trio-round been fully addressed? Open critical/high findings remaining? If yes, address first.
2. Are the audit panes from a different model family than the Phase 6 synthesizers? If no, kill+respawn.
3. Has ⊞ Scale-Check been explicitly run on every assumption.type:scale_physics? If no, run before next trio.
4. Has ∿ Dephase been applied (consensus-check)? If no, run.
5. Are the verbatim trio prompts being dispatched (not paraphrased)? Calibrated prompts only.

If 2 consecutive trio-rounds clean → exit Phase 7. Otherwise re-dispatch.
```

---

## Section B — Diagnostic self-prompts when stuck

### B1 — "Phase 4 isn't converging"

```
If kill_rate < add_rate for ≥3 rounds, ask:

1. Are the falsifiers actually decidable? Re-read each H.falsifier and ask: "in <1h of corpus search, what observation would fire this?" If unclear, the falsifier is fake.
2. Are the Investigators reading the same corpus? Cross-pollination prevents independent verification. Apply domain assignment via assign-investigator-domains.sh.
3. Is the question of record too broad? Phase 4 not converging often means Phase 1 framing was inadequate. Consider returning to Phase 1 with a tighter sub-question.
4. Is there a third alternative the slate missed? Run MO-03c-third-alternative.md retrospectively even though we're past Phase 3.

If all of the above check out and kill_rate is still low: consider hard-stopping Phase 4 at round 6 and escalating to Phase 5 with the current state. Phase 5 may surface what Phase 4 missed.
```

### B2 — "The disagreement register feels artificial"

```
If meta_synthesizer produced disagreements that feel forced:

1. Are the disagreements about wording or substance? Wording-only is forced; substance is real. Re-read each entry.
2. Did the Synthesizers actually disagree, or was the meta_synth manufacturing disagreements to satisfy F-603? If manufactured → re-run MO-06a per family with explicit "produce ≥3 invariants and ≥3 distinct claims about the question" directive.
3. Could the disagreements be resolved by ⊘ Level-Split? Real disagreements often disappear when you realize the families are talking about different levels.

A genuine disagreement register either (a) names a load-bearing claim where families differ, OR (b) identifies a level-split we missed. Wording disputes don't qualify.
```

### B3 — "I think convergence is a false positive"

```
If panes are producing convergence language but git log shows no commits:

1. Run /vibing-with-ntm OC-016 convergence triple-check.
2. Specifically: tmux capture-pane -p -S -50 on each pane and look for the actual reasoning vs just "LGTM" / "no fixes needed".
3. Check if convergence-check.sh agrees with the panes' verdict.
4. If panes claim convergence but no falsifier ever fired in Phase 4, you have F-403 + F-501 + F-701 stack — the entire methodology has produced confirmation theater.

Recovery: hard-stop, dispatch MO-mode-flip-investigator-to-advocate.md across the swarm, re-run Phase 4 with explicit "find ≥1 EV.refutes per pane this round" mandate.
```

---

## Section C — When to escalate

### C1 — Escalation matrix

```
Symptom → Escalate to

- Pane stuck at zsh         → /vibing-with-ntm OC-026 + OC-027
- Bead DB corruption         → /fixing-beads-problems
- Mail server down           → AGENT-MAIL-FALLBACKS.md (this skill)
- Code in deliverables broken → /ubs + /multi-pass-bug-hunting
- Question framing dispute   → operator + user re-engagement
- Methodology doubt          → MO-10-drift-check.md + DRIFT-RUBRIC.md
- Unfamiliar question domain → /codebase-archaeology, /codebase-report (if code), /cass mining (if prior context)
- Hypothesis space too narrow → /idea-wizard, /dueling-idea-wizards
```

### C2 — When to abort the session

Abort when ≥2 of these hold:

```
- Phase 1 cannot frame a falsifiable question (3+ MO-01 attempts, all rejected)
- Phase 4 hard-capped at 6 rounds without convergence AND no falsifier ever fired
- Phase 7 audit critical findings cannot be addressed within reasonable wall-time budget
- Multiple model families rate-limited simultaneously (no triangulation possible)
- Operator (you) cannot articulate what the next phase should produce

Abort discipline:
1. Run dump-session-report.sh to capture current state.
2. Write deliverables/ABORTED.md explaining why (which abort criteria fired).
3. Mark phase_<current>_complete.flag with status:aborted.
4. Recommend the user: (a) reframe with sharper question, (b) wait for resources to recover, (c) defer the question entirely.
5. Phase 8 freeze still runs — workspace remains resumable when conditions change.
```

---

## Section D — Quality-protection prompts

### D1 — Pre-commit reflexion

Before any phase-completing commit:

```
Has this phase produced what it claims to have produced?

Phase 1 commit: question_of_record.md + corpus_index.md + Q-001 + H-000?
Phase 2 commit: phase_2_complete.flag + onboarding ack thread populated?
Phase 3 commit: ≥3 H beads with falsifiers + ≥1 third-alternative?
Phase 4 commit: ≥1 EV per H + ≥1 falsifier-attempt per H + convergence-check passing?
Phase 5 commit: Every H state finalized + every active H survived ≥1 debate?
Phase 6 commit: Per-family + meta + non-empty disagreement_register?
Phase 7 commit: 2 consecutive trio-rounds clean + ubs clean on code?
Phase 8 commit: RESUME.md verifies + checkpoint exported?

If any answer is "no", DON'T commit. Fix first.
```

### D2 — Operator integrity check

Periodically (every ~5 ticks) ask yourself:

```
Am I drifting toward expedience over rigor?

- Have I been applying every operator, or has the algebra collapsed to ✂ + ⌂ only?
- Has any pane been silently degraded (rate-limited, context-saturated) without re-balancing?
- Have I bypassed any invariant ("just this once we'll skip ⊞ Scale-Check")?
- Am I reading evidence packs and audit findings, or just glancing at counts?
- Would I be embarrassed if a fresh agent ran a drift check on my last hour of decisions?

If any answer drifts toward "yes" → slow down. Re-read OPERATORS.md composition cheat-sheet. Run dump-session-report.sh. Talk to yourself out loud (hand-write a tick log).

Methodology integrity is the only thing that distinguishes this skill from "run a swarm of agents and hope". Don't compromise it.
```

### D3 — User-update template

When the user asks "how's it going?":

```
Phase: <N> (<phase name>) — round <M>
Wall time: <H>h <M>min (vs <expected_for_tier>)
Roster: <N> panes alive, <M> rate-limited or saturated

Methodology compliance:
  Falsifier coverage: <N>/<M> (target: 100%)
  Third alternative: <yes|no>
  Source corpus coverage: <N> §-anchors (target: ≥15)
  Operator coverage: <N>/15 fired
  Convergence (current phase): <CONVERGED | not yet — need <X> more rounds>

Current focus: <one-sentence: what's the swarm investigating right now>

Open headlines: <≤3 bullets — top hypotheses or top open audit findings>

Next milestone: <what triggers the next phase entry>

ETA to handback: <Hh Mm>

Anything you want me to redirect on?
```

---

## Section E — Inter-skill coordination prompts

### E1 — Invoking /vibing-with-ntm during a tick

```
While running a brennerbot session, I'm seeing <symptom>.

This is an operator-loop concern (pane state / coordination / convergence) rather than a methodology concern (operator algebra / falsifier discipline).

Use /vibing-with-ntm to handle the operator-loop concern, then return to brennerbot's phase loop.
```

### E2 — Invoking /multi-model-triangulation

```
At Phase 6, I want a third independent reconciliation of the per-family distillations beyond what the meta_synthesizer produced.

Use /multi-model-triangulation with:
  Inputs: distillations/by_cc.md, by_cod.md, by_gmi.md
  Existing reconciliation: distillations/meta_synthesis.md + disagreement_register.md
  Output target: distillations/disagreement_register_triangulated.md

Per TRIANGULATION.md § "When invoking /multi-model-triangulation directly".
```

### E3 — Invoking /codebase-archaeology

```
For Phase 1 in code-investigation mode, I need to seed the corpus_index.md and target_inventory.md with archaeology output.

Use /codebase-archaeology against <TARGET_PATH> to produce:
  - Repo structure summary
  - Top-N most-touched files
  - Subsystem breakdown
  - Claimed-features-vs-reality scan

Output target: <WORKSPACE>/intake/target_inventory.md and append to <WORKSPACE>/corpus/corpus_index.md.

Then return to brennerbot for question framing.
```

---

## Section F — User-facing communication discipline

### F1 — Updates after each phase

After Phase N exits, ping the user:

```
Phase <N> complete. <One-sentence: what landed.>

<Optional: 2-3 bullets of headlines.>

Proceeding to Phase <N+1>: <one-sentence: what comes next>.

Estimated wall time to next phase exit: <H>h <M>min.

Reply only if you want to redirect; otherwise I'll continue.
```

### F2 — When to ask the user for input

You SHOULD ask the user:

- Phase 1: any clarifying question about the framing
- Phase 0: confirm scope decisions (mode, roster, model mix, robot mode)
- Phase 8: confirm freeze before committing
- Phase 9: review HANDBACK.md before declaring done
- ANY F-101/F-103 (question framing failure) — re-engage user
- ANY abort condition — explain and recommend

You should NOT ask the user:

- Mid-Phase-4 about specific evidence interpretations (handle in adjudication thread)
- About roster details once locked at Phase 2
- About operator-loop tactics (your job)
- For permission to apply each operator (operators are the methodology, not optional)

### F3 — Handling user redirects mid-session

If the user wants to redirect mid-session:

```
Got it. Pausing the swarm.

To redirect cleanly, I need to know:
  1. Are we changing the question of record? (Phase 1 reset → likely abort current session)
  2. Are we changing scope only? (Update Out-of-Scope; continue from current phase)
  3. Are we adjusting roster? (Pane changes; document in roster_changes log)
  4. Are we accelerating to a specific phase? (Skip to Phase X — possibly degraded)

Reply with the redirect specification. I'll update phase0_scope_decision.md and resume.
```

---

## Authoring rules for new prompts

When extending PROMPTS.md:

1. **Specificity over generality.** "How are you?" is bad; "Phase 4 round 3 status: kill_rate, falsifier events, anomalies" is good.
2. **Include the why.** Each prompt section explains *what decision it supports*. Otherwise it's noise.
3. **Make them dispatch-ready.** A self-prompt should be runnable in a tick without further synthesis.
4. **Preserve the discipline.** Self-prompts should NEVER paper over methodology violations ("the falsifier is sort of close enough").

Add prompts when a recurring decision-point lacks calibrated language. Phase 10 drift-check often surfaces these.
