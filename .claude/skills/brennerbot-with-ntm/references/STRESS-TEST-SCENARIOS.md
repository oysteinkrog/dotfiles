# STRESS-TEST-SCENARIOS.md — Methodology Resilience Tests

<!-- TOC: Why stress-test | The scenario format | S1 zero-refute investigation | S2 silent averaging | S3 audit acceptance | S4 mid-Phase-4 timeout | S5 multi-pane rate-limit | S6 user redirect | S7 corpus drift | S8 consensus capture | S9 Phase-10 critical | S10 cross-session conflict | S11 ⊙ pane corrupted | S12 falsifier softened | S13 single-source dominance | S14 anomaly storm | S15 model-family extinction | How to use scenarios -->

Mirrors wills-and-estate-planning's STRESS-TEST-SCENARIOS.md. Each scenario describes a methodology failure mode under realistic operating conditions, plus the recovery path. Treat these as test cases for the skill itself: a session that handles all 15 cleanly is methodologically robust.

---

## Why stress-test

Pristine examples (per CASE-STUDIES.md) show how the methodology *should* work. Stress tests show how it survives *real* operating conditions. Adopt this norm from chaos engineering: assume failures, design for them, exercise them.

Pre-launch (operator becoming proficient): run through all scenarios mentally. During-session: when a real failure mode fires, match it to the closest scenario; apply the recovery path.

---

## Scenario format

Each scenario:

```
S<N>: <one-line title>

**Setup:** how this state arises
**Symptoms:** observable signals (per OBSERVABILITY.md / red-flag-scan.sh patterns)
**Failure mode:** which F-### code, anti-pattern, or methodology break
**Recovery path:** specific MO + script + decision sequence
**Tier impact:** which tiers this is most acute for
**Phase-10 lesson:** what to commit if this recurs
```

---

## S1: Zero-refute investigation

**Setup:** Phase 4 round 3 in progress; Investigators have filed many `EV-*.supports[]` but zero `EV-*.refutes[]`. `convergence-check.sh --phase=4` reports `add_rate=4, kill_rate=0`.

**Symptoms:**
- All H still `state: active`
- Falsifier-firing rate metric = 0
- Pane tails contain confirmation language ("clearly supports", "as expected")
- `red-flag-scan.sh` matches "the answer is clearly"

**Failure mode:** F-403 confirmation bias.

**Recovery path:**
1. Dispatch `MO-mode-flip-investigator-to-advocate.md` to ≥1 Investigator.
2. If a top-confidence H exists, dispatch `MO-quickie-pilot.md` for a fast falsifier probe.
3. After 1 more round, if still kill_rate=0 and add_rate>0: hard-stop Phase 4; the Hs may be unfalsifiable. Apply `subagents/falsifier-grader.md`.
4. If grade is Poor across all Hs → return to Phase 1; the question framing produced unfalsifiable hypotheses.

**Tier impact:** all tiers; especially T2 where Devil's-Advocate role is shared.

**Phase-10 lesson:** if recurs, OPERATOR-CALIBRATION-LOG.md should track "rounds-to-first-refute" as a metric.

---

## S2: Silent averaging at Phase 6

**Setup:** Three per-family distillations submitted; meta-synthesizer drafted `meta_synthesis.md` reading like an average. `disagreement_register.md` has 0 entries.

**Symptoms:**
- `disagreement-register-lint.sh` exits non-zero
- Meta-synthesis text uses words like "broadly", "tends to", "generally"
- No specific per-family citation in the meta

**Failure mode:** F-601 silent averaging; F-603 no register.

**Recovery path:**
1. Reject meta. Re-dispatch `MO-06b-meta-synthesize.md` with explicit "find ≥1 substantive disagreement per pair (cc-vs-cod, cc-vs-gmi, cod-vs-gmi). Generate disagreements rather than averaging."
2. If 2nd attempt also empty → the per-family distillations are too thin; re-run `MO-06a-distill.md` per family with explicit "produce ≥3 distinct claims that you expect peers to disagree with."
3. If 3rd attempt also empty → operator has a discriminator-skill problem; switch meta-synthesizer family.
4. Optionally invoke `/multi-model-triangulation` directly for a third reconciliation.

**Tier impact:** worst at T3+ (triangulation is the load-bearing value).

**Phase-10 lesson:** OPERATORS.md may need to clarify ⊘ Level-Split's role in meta-synthesis.

---

## S3: Audit accepts everything

**Setup:** Phase 7 trio-round 1 complete; auditor panes filed 0 critical, 0 high findings. Tail content reads "exemplary, no fixes needed."

**Symptoms:**
- `red-flag-scan.sh` matches convergence-language phrases
- 0 audit-finding beads with severity ≥medium
- Operator's gut says "this is too clean"

**Failure mode:** F-701 audit-acceptance false-positive.

**Recovery path:**
1. Run `liveness-check.sh` to verify panes are *actually* reading artifacts.
2. Run `convergence-check.sh --phase=7` for explicit verdict.
3. Dispatch a SECOND trio-round with explicit "your task is to find methodology violations, not typos. Apply ⊞ Scale-Check, ∿ Dephase, ✂ re-verify."
4. If 2nd trio also empty AND no critical/high findings exist after `audit-bead-invariants.sh --all`: the artifact may genuinely be clean. Proceed to Phase 8 with operator confidence note.
5. For T4+: also run `subagents/red-team.md` for novel-attack search.

**Tier impact:** T3+ where rubber-stamping is most likely.

**Phase-10 lesson:** if recurs, MO-07a-fresh-eyes.md should add explicit "find ≥3 methodology gaps even if artifact looks clean" directive.

---

## S4: Mid-Phase-4 timeout

**Setup:** Phase 4 hits hard cap (round 6, T3 budget exhausted). 2 of 5 Hs still `state: active`; falsifiers attempted but inconclusive.

**Symptoms:**
- `wall-time-budget.md` budget breach
- `tick.sh` shows phase-4 rounds=6 with kill_rate < add_rate
- User starts asking "are we close?"

**Failure mode:** budget breach; no clean exit gate.

**Recovery path:**
1. Per WALL-TIME-BUDGET.md "Hard breach" protocol:
   - Don't extend silently
   - Decide: (a) escalate tier, (b) accept incomplete with caveats, (c) reframe
2. For (b): exit Phase 4 with the 2 unresolved Hs as `state: deferred`. Phase 5 adjudicates only the resolved ones. Phase 9 HANDBACK lists the deferred Hs in "What's still open" with `next-action`.
3. Recommend a follow-up session (resume mode) with `mode_to_resume: targeted-investigation` on the deferred Hs.

**Tier impact:** T2-T3 most common.

**Phase-10 lesson:** OPERATOR-CALIBRATION-LOG.md tracks "Phase 4 rounds-to-converge" per archetype × tier.

---

## S5: Multi-pane simultaneous rate-limit

**Setup:** All cc panes hit Claude rate limits simultaneously (e.g., quota reset boundary). Squad goes from 5 active to 1 active mid-Phase-4 round.

**Symptoms:**
- `ntm --robot-attention --attention-session=<session>` reports rate-limit/action-required hints; `ntm --robot-health-oauth=<session>` confirms rate_limited=true on multiple panes
- `liveness-check.sh` flags rate-limited panes
- Bead production drops

**Failure mode:** roster collapse; not a methodology bug but operational.

**Recovery path:**
1. Dispatch `MO-roster-rebalance.md` with `<REASON>=rate-limit-cluster`.
2. Apply `/vibing-with-ntm` OC-002 rotate: `ntm rotate <session> --all-limited`.
3. If rotation insufficient: respawn affected panes on different model families (cod, gmi).
4. Document the rebalance in `phase0_scope_decision.md § roster_changes`.
5. If only 1-2 panes remain, downgrade tier estimate (e.g., Squad-with-2-active is effectively Pair); update wall-time expectations.

**Tier impact:** Squad/Swarm. Solo/Pair handle gracefully (only 1-2 panes anyway).

**Phase-10 lesson:** for high-stakes T4+ sessions, pre-warm CAAM accounts to avoid simultaneous limit hits.

---

## S6: User redirect mid-session

**Setup:** Phase 4 in flight. User messages "actually wait, I want you to investigate <different angle> instead."

**Symptoms:** explicit user message; not a methodology signal.

**Failure mode:** scope creep risk.

**Recovery path:**
1. Pause swarm immediately.
2. Determine if the redirect is:
   - **Refinement** (same question, sharper sub-question) → continue current session; update intake/question_of_record.md with note; treat redirect as Phase 1 sub-framing
   - **Pivot** (different question; same domain) → run `MO-emergency-stop.md` with `<REASON>=user-redirect`; spawn fresh session via `bootstrap-session.sh`
   - **Abandonment** (user no longer wants the investigation) → emergency stop; archive session for later; do NOT delete
3. For (a) and (b), produce a partial HANDBACK before continuing/aborting so the user gets value from the work done so far.

**Tier impact:** all tiers.

**Phase-10 lesson:** if user-redirects are common, the question of record framing is too rigid; operator should ask sharper Phase 1 questions.

---

## S7: Corpus drift detected

**Setup:** Phase 6 distillation in progress. `audit-bead-invariants.sh § layout_invariants` reports a hash mismatch on `corpus/ingested/S-007/main.md`.

**Symptoms:**
- Hash mismatch flag
- Source content diff shows changes (third-party paper got revised, repo got commits, web page edited)
- Phase 4 EVs cite content that may no longer exist

**Failure mode:** F-102 corpus drift.

**Recovery path:**
1. Diff the source: what changed?
2. Identify cited EVs from this source. For each:
   - If cited content unchanged → update hash, note in provenance log "source revised; cited content unchanged"
   - If cited content drifted → mark `EV-*.verified=false` with reason; file `audit-finding`
3. For each affected H: re-investigate the changed claim; potentially flip state.
4. Per VERIFICATION-FIRST.md, append to `analyses/official-source-log.md`.
5. If many EVs affected → trigger Phase 4 reopen on the affected Hs.

**Tier impact:** T3+ where corpus integrity matters most.

**Phase-10 lesson:** for volatile-source sessions, increase verification cadence (per VERIFICATION-FIRST.md Recipe V3).

---

## S8: Consensus capture detected at Phase 7

**Setup:** Phase 7 audit reveals that the surviving "best-explanation H" matches what a domain expert would have proposed first, AND no genuine third-alternative was tested.

**Symptoms:**
- Phase 7 audit's ∿ Dephase check fails
- The confirmed H is "the obvious answer"
- Productive-ignorance pane never produced anything contrarian

**Failure mode:** ∿ Dephase failure; consensus capture.

**Recovery path:**
1. Audit explicitly asks: "Did our session reproduce a consensus prior, or did we genuinely test alternatives?"
2. If consensus: file `audit-finding` severity:high. Recommend Phase 4 reopen with explicit cross-domain ⊕ import (per `MO-cross-domain-import.md`) targeting a non-consensus framing.
3. Optionally run `subagents/red-team.md` for novel-attack search of the consensus claim.
4. If consensus-capture is justified (consensus IS correct): document the verification — what evidence rules out alternatives?

**Tier impact:** worst at T1-T2 (less rigorous triangulation); but theoretically possible at any tier.

**Phase-10 lesson:** consider promoting `subagents/red-team.md` to default for T3+ sessions whenever Phase 7 ∿ Dephase fails.

---

## S9: Phase 10 finds critical methodology violation

**Setup:** Drift auditor (per `subagents/drift-auditor.md`) reports verdict `divergent-regression` with R-001: "✂ Exclusion-Test was applied at Phase 3 only, never re-verified at Phase 4 or Phase 7. Multiple H states confirmed without falsifier-firing evidence."

**Symptoms:** explicit drift-check report; confirms suspicions about S1/S3.

**Failure mode:** F-1003-class methodology violation; the session's outputs may be unsound.

**Recovery path:**
1. The handback recommendation should NOT be acted on without remediation.
2. Options:
   - **Reopen Phase 7 audit** with explicit ✂ re-verification across all confirmed Hs
   - **Reopen Phase 5 debates** with explicit falsifier-firing requirement
   - **Mark session as methodologically incomplete**; recommend re-running with stricter discipline
3. The Phase 10 lesson: update `references/OPERATORS.md ✂ Exclusion-Test` card with explicit "must fire at Phase 4 + Phase 7 re-verification" emphasis. Update `references/PHASES.md` Phase 7 audit checklist.

**Tier impact:** all tiers; T4+ catastrophic if undetected.

**Phase-10 lesson:** add `scripts/check-six-layer-validation.sh` (per SIX-LAYER-VALIDATION.md) to be run before Phase 8 freeze.

---

## S10: Cross-session conflict (resume + new sessions disagree)

**Setup:** Resumed prior session whose verdict was `H-005 confirmed`. New investigation in current resume produces `H-005 refuted` based on new evidence.

**Symptoms:** the two sessions, treating the same question, reach opposite verdicts.

**Failure mode:** not a bug — could mean (a) prior session was wrong, (b) current session is wrong, or (c) the question is genuinely under-determined.

**Recovery path:**
1. Per `references/CROSS-SESSION-LEARNING.md`: don't silently override prior. Cross-session conflicts go in `CROSS-SESSION-DRIFT-CATALOG.md`.
2. Run `subagents/reconciler.md` (Tier-4 subagent) to compare:
   - What evidence did each session use?
   - Did the corpus change between sessions (per VERIFICATION-FIRST.md drift check)?
   - Did the question change (per RESUME.md hash verification)?
3. If corpus drifted: current session's verdict probably correct; document.
4. If corpus identical: meta-question. Run a T5-style multi-session triangulation (per CROSS-SESSION-LEARNING.md "Cross-session triangulation").
5. Document in `deliverables/RECONCILIATION-MEMO.md`.

**Tier impact:** T4+ where multi-session work is common.

**Phase-10 lesson:** add `references/RECONCILIATION-OF-PRIOR-SESSIONS.md` (Tier-4 reference if not already present).

---

## S11: ⊙ Productive-Ignorance pane corrupted

**Setup:** The pane assigned the productive-ignorance role started reading the corpus despite onboarding said "read only the question of record."

**Symptoms:**
- Pane's hypotheses cite specific corpus content
- Pane chats about prior literature
- Phase 3 distinct-from-corpus-informed slate doesn't materialize

**Failure mode:** ⊙ role corruption.

**Recovery path:**
1. Detect via Phase 3 triage: do all Hs cite corpus? If yes, the ⊙ pane failed.
2. Two responses:
   - **Lenient:** accept the contamination; note that this session lacks ⊙ contribution; downgrade Phase 6 distillation expectations (no minority-from-ignorance perspective)
   - **Strict:** kill the ⊙ pane, respawn with explicit "you are FORBIDDEN from reading any file outside intake/question_of_record.md until Phase 5"
3. For T4+ sessions, prefer strict.

**Tier impact:** worst when ⊙'s contribution is critical (e.g., A10 first-principles archetype).

**Phase-10 lesson:** ROSTER-PLANS.md ⊙ pane onboarding should include explicit file-access restrictions; `MO-02-onboarding.md` may need a stricter directive.

---

## S12: Falsifier softened mid-Phase-4

**Setup:** A `H-*.falsifier` field was edited during Phase 4 (specifically: tightened-from-difficult to easier-to-pass).

**Symptoms:**
- `audit-bead-invariants.sh § every_H_has_falsifier` passes (falsifier text is non-empty)
- But the falsifier is now too lenient
- `subagents/falsifier-grader.md` would grade it Weak/Poor

**Failure mode:** F-303-class — silent post-hoc rationalization.

**Recovery path:**
1. Compare current falsifier to Phase 3 snapshot (or pre-registration if hypothesis-pre-registration mode).
2. If softened: restore the original falsifier text with an explicit note in `phase0_scope_decision.md`.
3. If sharpened legitimately: file as a separate refinement H per `MO-falsifier-fired.md` discipline (don't edit the original).
4. For pre-registered sessions: this is a hard violation; session may need re-running.

**Tier impact:** all tiers; T4+ catastrophic if undetected.

**Phase-10 lesson:** Phase 7 audit must run `subagents/falsifier-grader.md` for every H, not just newly proposed ones.

---

## S13: Single-source dominance in evidence

**Setup:** All `EV-*` cited for a confirmed H come from the same paper / repo / blog post, even if there are 5+ EVs.

**Symptoms:**
- Per-H supporting EV count looks healthy
- But EV.source field for all of them points to the same source ID
- M-403 (per METRICS.md) shows correlated evidence

**Failure mode:** evidence-correlation; F-405 from EXTENDED-FAILURE-CATALOG.

**Recovery path:**
1. Run M-403 metric per H. If `independent_supports < 2`, downgrade H from `confidence:high` to `medium` (per CONFIDENCE-SCORING.md).
2. Phase 4 reopen on the affected H: explicitly seek independent corroboration.
3. If no independent source can be found: the H may be valid but un-corroborated; mark accordingly in HANDBACK.md.

**Tier impact:** T3+ where confidence levels matter most.

**Phase-10 lesson:** update CONFIDENCE-SCORING.md to require explicit independence count for `confidence:high`.

---

## S14: Anomaly storm

**Setup:** Phase 4 round 4 has produced 7+ anomaly beads; many cluster on the same feature.

**Symptoms:**
- `anomaly` bead count growing
- Cluster check identifies ≥3 clustered anomalies

**Failure mode:** not a bug per se — a paradigm shift signal (per Brenner ΔE).

**Recovery path:**
1. Per `MO-anomaly-cluster.md`: promote the cluster to a new H with `origin:anomaly_spawned`.
2. The cluster suggests the existing hypothesis space MISSED something. Phase 4 reopen the new H with high priority.
3. If the cluster persists across multiple rounds, Phase 6 distillation must explicitly address: did our framing exclude the anomaly-pattern? Was our scope too narrow?
4. Possibly trigger a Phase 1 reframe ("the question of record may have been wrong-framed").

**Tier impact:** all tiers; can be a major positive signal at T4 ("we've found something").

**Phase-10 lesson:** anomaly clusters are valuable; ensure ΔE Exception-Quarantine is firing at every Phase 4 round.

---

## S15: Model-family extinction

**Setup:** During a Swarm-tier session, all gmi panes go down (Gemini provider outage). Roster reduces from 10 to 7 panes (cc + cod only).

**Symptoms:** `ntm --robot-attention --attention-session=<session>` reports provider/agent-health degradation; `ntm --robot-health-oauth=<session>` confirms gmi is down; `list-distinct-model-families.sh` returns only `cc` and `cod`.

**Failure mode:** triangulation degradation.

**Recovery path:**
1. Document in `phase0_scope_decision.md § triangulation_degraded`.
2. If Phase 6 hasn't run yet: proceed with 2-family triangulation; expect smaller disagreement_register (1 entry minimum vs 3).
3. If Phase 6 has run with 3 families and gmi went down before audit: Phase 7 audit must NOT exclude the gmi distillation; if needed, kill+respawn one cc pane on different model-family-equivalent (a different cc account / different system prompt).
4. For T4+ where 3-family triangulation is critical: hard-stop session per `MO-emergency-stop.md` with `<REASON>=external-event`. Resume when gmi is available.

**Tier impact:** worst at T4+.

**Phase-10 lesson:** for T4+ sessions, pre-confirm provider availability AND have a contingency family ready.

---

## How to use scenarios

### During session

When a real failure mode fires, match the symptoms to the closest scenario. Apply the recovery path. Document which scenario matched in `session-logs/round-N.md`.

### Pre-session (operator preparation)

Before running a T3+ session, walk through scenarios mentally. For each, ensure you know which MO/script/decision applies. Operators should be fluent in S1-S15 before T4+.

### Phase 10 drift audit

The drift auditor (per `subagents/drift-auditor.md`) checks: did any scenarios fire in this session, and were they handled well? Document in DRIFT-CHECK.md if novel scenarios emerged.

### Skill maintenance

Phase 10 lessons may surface new scenarios not in this catalog. Add them following the format above. Periodically review and prune scenarios that are no longer realistic given methodology improvements.
