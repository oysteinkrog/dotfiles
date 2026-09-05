# OPERATOR-CARDS.md — Trigger / Recipe / Validator Cards for Micro-Decisions

<!-- TOC: Card schema | OC-001 to OC-040 | How to use cards | Card composition | Promotion to canonical -->

Mirrors `/vibing-with-ntm`'s OPERATOR-CARDS.md pattern. Each card is a *narrow* operational recipe — a specific micro-decision the operator faces during a session, with trigger conditions, recipe, and validator.

These cards are different from the 15 cognitive operators in OPERATORS.md (which are *methodology* operators). Operator cards are *operational* tactics during the session — how to make specific tick-time decisions.

---

## Card schema

Each card:

```
OC-NNN: <one-line title>

**Trigger:** when this card applies (specific signal observable during a tick)
**Recipe:** 3-7 line procedure
**Validator:** how to know the card was applied correctly
**Anti-pattern caught:** which AP-* it prevents
**Tier:** which tiers most acutely need it
**Composition:** which other cards / MOs work alongside
```

---

## Phase 1 cards

### OC-001: Reject unfalsifiable framing

**Trigger:** user proposes a question whose falsifier is "we'll know it when we see it" or absent.

**Recipe:**
1. Don't accept. Frame the rejection as: "the question is unfalsifiable as stated."
2. Probe for an observable: "If I came back in 1h with a sample of data and it showed X, would that count as the answer?"
3. Iterate until user produces a concrete observable OR
4. If user can't produce one in 3 attempts, decline the session politely; recommend a non-research approach (lookup, expert consultation, etc.).

**Validator:** intake/question_of_record.md § Falsifier non-empty AND `subagents/falsifier-grader.md` grade ≥ Acceptable.

**Anti-pattern caught:** AP-M01 (frame question without falsifier), F-103.

### OC-002: Probe for hidden trigger

**Trigger:** user gives "neutral" framing but the question feels artificially-distanced.

**Recipe:**
1. Ask: "What changed recently that made this question urgent now?"
2. Listen for incident, deadline, audit, customer complaint.
3. Reframe the question to include the trigger context.

**Validator:** intake/question_of_record.md § Provenance is specific (event, deadline, person), not vague ("we always wonder").

### OC-003: Force out-of-scope specificity

**Trigger:** user lists Scope but Out-of-Scope is empty or "everything else."

**Recipe:**
1. Push for ≥3 specific items in Out-of-Scope.
2. If user can't produce them, ask: "If during investigation I started looking at <X>, should I?"
3. Each "no" goes in Out-of-Scope.

**Validator:** Out-of-Scope ≥ 3 bullets, ratio Scope:Out-of-Scope between 0.5–2.

**Anti-pattern caught:** F-101 (question too broad).

---

## Phase 2 cards

### OC-004: Onboarding ack with summary

**Trigger:** dispatching `MO-02-onboarding.md` to a pane.

**Recipe:**
1. Tell the pane its ack must include: "I am pane N, role X, my falsifier-domain is Y, my immediate first action is Z."
2. Reject one-line "ready" acks.
3. If pane sends "ready" without summary, re-dispatch with "your ack must include the role + domain + first action."

**Validator:** every pane's onboarding ack contains all three elements.

**Anti-pattern caught:** F-206 (rubber-stamp ack).

### OC-005: Productive-ignorance file restriction

**Trigger:** assigning ⊙ role to a pane.

**Recipe:**
1. In MO-02 onboarding, include explicit: "you are FORBIDDEN from reading: corpus/, evidence/packs/, distillations/, OR any file outside intake/question_of_record.md until Phase 5."
2. Mention the restriction is methodology-level, not punitive.
3. Document the assignment in phase0_scope_decision.md.

**Validator:** the ⊙ pane never cites corpus content in its hypotheses.

**Anti-pattern caught:** S11 ⊙ pane corruption (per STRESS-TEST-SCENARIOS).

---

## Phase 3 cards

### OC-006: Detect false binary

**Trigger:** Phase 3 triage produces 2 active Hs that are mutual exclusives.

**Recipe:**
1. Apply ⊘ Level-Split: are they really at different levels (program vs interpreter, etc.)?
2. If yes: keep both; not a false binary.
3. If no: inject a third alternative via `MO-03c-third-alternative.md` per Brenner §103.

**Validator:** every Phase 3 exit has ≥1 H with `origin:third_alternative`.

**Anti-pattern caught:** F-301 (false binary).

### OC-007: Reject duplicate H

**Trigger:** triage detects two Hs with the same claim (verbatim or paraphrased).

**Recipe:**
1. Pick the better-worded H as canonical.
2. Mark the other as superseded with `parent: <canonical>`.
3. Don't keep both as active.

**Validator:** active H slate has no semantically equivalent pairs.

**Anti-pattern caught:** F-302 (hypothesis duplication).

### OC-008: Mandate confidence diversity

**Trigger:** all proposed Hs have `confidence:high`.

**Recipe:**
1. Suspect proposer anchored on consensus.
2. Force at least one H to `confidence:speculative` (often the third-alternative).
3. Diverse confidence forces real prior diversity.

**Validator:** Phase 3 exit has ≥2 confidence levels represented across the active slate.

---

## Phase 4 cards

### OC-009: Probe falsifier first

**Trigger:** Investigator about to begin a Phase 4 round.

**Recipe:**
1. First action: search for evidence that *fires* the H's falsifier (not supports the claim).
2. Document the search even if no falsifier found.
3. Only after the falsifier search file confirming EVs.

**Validator:** every Phase 4 round produces ≥1 falsifier-attempt EV per active H.

**Anti-pattern caught:** F-403 (confirmation bias).

### OC-010: Quickie before flagship

**Trigger:** Investigator about to start a >1h investigation on an H.

**Recipe:**
1. Per `MO-quickie-pilot.md`: design a ≤30-min cheap pilot first.
2. Run the pilot.
3. If pilot fires falsifier → kill the H; skip the flagship.
4. If pilot supports → run flagship with confidence.
5. If inconclusive → redesign pilot or proceed with flagship marked as risky.

**Validator:** every >1h flagship investigation has a quickie predecessor in the same H thread.

### OC-011: Escalate evidence inflation

**Trigger:** `convergence-check.sh --phase=4` shows `add_rate > kill_rate` for ≥2 rounds.

**Recipe:**
1. Run `MO-mode-flip-investigator-to-advocate.md` on at least one Investigator.
2. Run `subagents/falsifier-grader.md` on all active Hs.
3. If grader finds Poor falsifiers, return to Phase 1 framing for those Hs.

**Validator:** by next round, kill_rate ≥ add_rate OR explicit operator hard-stop.

### OC-012: Spawn anomaly-driven H

**Trigger:** ≥2 anomalies share a feature (per ΔE check).

**Recipe:**
1. Run `MO-anomaly-cluster.md`.
2. File a new H with `origin:anomaly_spawned`.
3. Phase 4 reopen on the new H if backlog allows.

**Validator:** clustered anomalies have a corresponding `origin:anomaly_spawned` H.

### OC-013: Volatile-source re-fetch

**Trigger:** any volatile source cited in an EV; current session wall-time >60min since last verification.

**Recipe:**
1. Re-fetch source.
2. Compute new content hash.
3. If matches stored hash: append "verified at <ISO>" to `analyses/official-source-log.md`.
4. If drifted: file F-102 protocol (per FAILURE-TABLE.md).

**Validator:** every volatile-class source has ≥1 verification event per hour during active investigation.

---

## Phase 5 cards

### OC-014: Family-cross champion pairing

**Trigger:** about to dispatch `MO-05a-cross-exam.md`.

**Recipe:**
1. Identify the pane that championed each H.
2. Verify both panes are different model families when possible.
3. If same family: swap one champion to a different family pane (the original Investigator hands off via `MO-domain-handoff.md`).

**Validator:** every DEBATE-* bead has champions from different families OR explicit "single-family-only-available" note in phase0_scope_decision.md.

**Anti-pattern caught:** F-504 (same-family champions).

### OC-015: Adjudicator rotation enforcement

**Trigger:** about to dispatch `MO-05b-adjudicate.md`.

**Recipe:**
1. Check `phase0_scope_decision.md § adjudicator_rotation`.
2. Pick a pane that is NEITHER (a) a champion of this debate NOR (b) the adjudicator of the previous debate.
3. Update the rotation log.

**Validator:** `scripts/check-rotation-rules.sh` Rule 1 + 2 pass.

### OC-016: Force evidence-grounded adjudication

**Trigger:** Adjudicator's draft post lacks specific EV-NNN citation.

**Recipe:**
1. Reject the post.
2. Demand: "Your verdict must cite the verbatim quote from at least one EV that fired the falsifier OR establishes the kill."
3. If Adjudicator can't produce, the H is `state: deferred` (not refuted).

**Validator:** every closed DEBATE-* has `falsifier_fired:` or explicit "no falsifier fired" note.

**Anti-pattern caught:** F-505 (rubber-stamp adjudication).

---

## Phase 6 cards

### OC-017: Independent per-family distillation

**Trigger:** about to dispatch `MO-06a-distill.md`.

**Recipe:**
1. Each family's synthesizer pane works in *isolation* — they do not see each other's distillations.
2. Coordinate only via `RS-...-INVEST-coord` for clarification questions, not synthesis.
3. After all families submit, then meta-synthesis (Phase 6b) reconciles.

**Validator:** distillations have distinct emphases; no cross-citation between by_<fam>.md files.

**Anti-pattern caught:** F-604 (distillations copy each other).

### OC-018: Mandate substantive disagreements

**Trigger:** meta-synthesis draft has empty or wording-only disagreement_register.

**Recipe:**
1. Per `disagreement-register-lint.sh`: reject.
2. Re-dispatch with explicit "find substantive disagreement on a load-bearing claim, not phrasing."
3. If after 2 attempts the register is still thin, escalate to Phase 4 reopen for the affected claims.

**Validator:** disagreement_register.md has ≥(N choose 2) substantive entries.

**Anti-pattern caught:** F-601 (silent averaging), F-605 (manufactured disagreements).

---

## Phase 7 cards

### OC-019: Audit panes from different families

**Trigger:** Phase 7 audit about to dispatch.

**Recipe:**
1. Identify which families wrote per-family distillations.
2. Audit panes must include ≥1 family different from the dominant per-family.
3. If insufficient family diversity, kill+respawn audit panes.

**Validator:** audit panes' family roster differs from synthesizer roster.

**Anti-pattern caught:** F-705 (audit pane = synthesizer pane).

### OC-020: Falsifier re-grading

**Trigger:** Phase 7 audit start.

**Recipe:**
1. Run `subagents/falsifier-grader.md` on all current H falsifiers.
2. Compare to Phase 3 falsifiers (or pre-registration).
3. Any softening → file audit-finding severity:high.

**Validator:** falsifier-grader output documents grade per H; no silent softening.

**Anti-pattern caught:** F-303 (drift), S12 (softening).

### OC-021: Run scale-physics re-check

**Trigger:** Phase 7 audit; any assumption with `type:scale_physics` exists.

**Recipe:**
1. For each scale_physics assumption, re-run the calculation independently.
2. If the math doesn't hold OR the inputs are wrong, file critical audit-finding.
3. The H depending on the assumption is affected.

**Validator:** every scale_physics assumption has a Phase 7 verification entry.

---

## Phase 8 cards

### OC-022: Six-layer pre-freeze gate

**Trigger:** about to dispatch `MO-08-freeze.md`.

**Recipe:**
1. Run `scripts/check-six-layer-validation.sh`.
2. If any layer 1-5 fails: address before freezing.
3. Don't freeze in failed state — produces invalid RESUME.md.

**Validator:** Layers 1–5 pass before freeze (Layer 6 = external review is N/A for T1–T3 sessions and may legitimately remain `PENDING` for T4+ when the human/external reviewer hasn't returned a verdict yet — Layer 6 is not a freeze blocker, only a publish blocker; see [SIX-LAYER-VALIDATION.md § Pre-Phase-8 mandatory check](SIX-LAYER-VALIDATION.md#pre-phase-8-mandatory-check)).

### OC-023: RESUME.md dry-run before commit

**Trigger:** RESUME.md drafted.

**Recipe:**
1. Run `./scripts/resume-session.sh --dry-run --resume RESUME.md`.
2. If errors: fix; re-run.
3. Only after dry-run passes, commit RESUME.md.

**Validator:** RESUME.md verifies on dry-run; subsequent resume succeeds.

**Anti-pattern caught:** F-801 (broken RESUME.md).

---

## Phase 9 cards

### OC-024: Handback line-count enforcement

**Trigger:** HANDBACK.md drafted.

**Recipe:**
1. `wc -l < deliverables/HANDBACK.md`. Must be ≤80.
2. If exceeded: compress; not extend.
3. Compress by removing redundancy, not deleting load-bearing content.

**Validator:** HANDBACK.md ≤80 lines.

### OC-025: Unresolved-thread next-action enforcement

**Trigger:** HANDBACK.md "What's still open" section.

**Recipe:**
1. Every H/EV/AF/D mentioned in this section MUST have `next-action:` field.
2. Run `scripts/audit-bead-invariants.sh --check=handback_open_thread_tags`.
3. If missing: add per-thread next-action.

**Validator:** audit passes.

**Anti-pattern caught:** F-902.

---

## Phase 10 cards

### OC-026: Drift verdict from fresh agent

**Trigger:** dispatching Phase 10 drift check.

**Recipe:**
1. Drift auditor MUST be a fresh general-purpose Agent, NOT a swarm pane.
2. Use the Agent tool with `subagent_type: "general-purpose"`.
3. Operator does NOT participate in the drift verdict; auditor independent.

**Validator:** drift-auditor pane is not in the original session's roster.

**Anti-pattern caught:** AP-O11 (drift from swarm pane).

### OC-027: Lesson commitment

**Trigger:** Phase 10 drift produces lessons.

**Recipe:**
1. Each L-NNN must have a corresponding update to references/ in the skill repo.
2. Operator commits the change.
3. Mark L-NNN as Committed in DRIFT-CHECK.md with skill commit SHA.

**Validator:** every L-NNN has Committed annotation.

**Anti-pattern caught:** F-1003 (lessons not fed back).

---

## Cross-cutting cards

### OC-028: Tick-cadence discipline

**Trigger:** operator about to "check on the swarm."

**Recipe:**
1. Per OBSERVABILITY.md tick cadence: 4 min during nucleation, 10-17 min steady, 30 min deep work.
2. Use `tick.sh` for each tick — don't free-form-monitor.
3. Don't sub-3-min poll.

**Validator:** `.brenner_workspace/tick_history.jsonl` has timestamps consistent with cadence.

### OC-029: Liveness verification before action

**Trigger:** operator about to take pane-state-changing action (kill, restart, redirect).

**Recipe:**
1. Run `liveness-check.sh` first.
2. Triangulate with ≥3 independent observations (per OBSERVABILITY.md three-observation rule).
3. Only act if liveness state is unambiguous.

**Validator:** session-logs/round-N.md documents the liveness check before each pane action.

### OC-030: Wall-time soft-breach response

**Trigger:** any phase's wall-time > 130% of tier estimate.

**Recipe:**
1. Note in session-logs/round-N.md.
2. Continue but accelerate (drop optional sub-steps).
3. If wall-time > 150%: hard-breach; pause and decide per WALL-TIME-BUDGET.md.

**Validator:** explicit decision recorded in phase0_scope_decision.md.

### OC-031: User-update cadence

**Trigger:** every phase exit OR every 30 min during active phases.

**Recipe:**
1. Per PROMPTS.md § F1 user-update template.
2. One-paragraph update; don't drop user out of context.
3. End with "Reply only if you want to redirect; otherwise I'll continue."

**Validator:** user updates posted at every phase exit.

---

## Promotion to canonical

When a card is consistently applied across many sessions, consider promoting it:

- Card's procedure becomes the default in a `MO-*.md` template
- Card's anti-pattern caught becomes a hard invariant
- Card's validator becomes a check in `audit-bead-invariants.sh` or similar

The cards here are tactical; canonical procedures are strategic. Promote when a card has prevented the same failure ≥3 times across sessions (per CROSS-SESSION-LEARNING.md).

---

## How to use cards

### During a tick

When facing a micro-decision, scan card titles for relevance. The 31 cards above are not exhaustive — add as you discover patterns.

### Pre-launch checklist

For T3+ sessions, the operator should know all OC-001 through OC-031 by reflex. Practice via STRESS-TEST-SCENARIOS.md.

### Phase 10 drift

Drift auditor checks: which cards fired? Which should have but didn't? Cards that consistently aren't applied get promoted to canonical OR demoted (rare).
