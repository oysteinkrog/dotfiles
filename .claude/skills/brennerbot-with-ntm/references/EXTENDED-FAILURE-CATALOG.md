# EXTENDED-FAILURE-CATALOG.md — Niche Failure Modes Beyond F-101..F-1003

<!-- TOC: When to use | F-2xx Phase-2 niches | F-3xx triage niches | F-4xx investigation niches | F-5xx debate niches | F-6xx synthesis niches | F-7xx audit niches | F-9xx handback niches | F-10xx drift niches | Cross-cutting | Lookup query -->

Mirrors saas-billing's EXTENDED-FAILURE-CATALOG. The main FAILURE-TABLE.md lists 30 common F-### codes. This file documents niche failures observed in real sessions — patterns rare enough to deserve distinct codes but rare enough to live in an extension catalog rather than the main table.

---

## When to consult this catalog

When the main FAILURE-TABLE.md doesn't seem to match the symptom, OR when Phase 10 drift-check surfaces a pattern that doesn't fit existing codes. New entries here graduate to FAILURE-TABLE.md if they prove common across sessions.

---

## F-2xx: Phase 2 niches

### F-204 — Pane onboarded but immediately compacts

**Symptom:** pane acks onboarding, then within 5 min reports context full and compacts/restarts.

**Diagnosis:** the onboarding briefing was too large (e.g., included the full corpus rather than just `intake/question_of_record.md`).

**Recovery:** trim onboarding briefing to ≤500 tokens. Reference corpus and roster role docs by path; don't paste them inline.

**Anti-pattern this catches:** AP-OB1 — over-eager onboarding briefing.

### F-205 — Pane onboarded with wrong session_id

**Symptom:** pane subsequent posts reference a different session_id than the operator intended.

**Diagnosis:** dispatcher passed wrong `<SESSION_ID>` parameter, OR pane copied the wrong ID from elsewhere.

**Recovery:** re-dispatch onboarding with explicit session_id; ask pane to update its identity in mail.

### F-206 — Onboarding race: pane acks before reading

**Symptom:** pane sends ready-ack within seconds of dispatch, far faster than reasonable for reading the onboarding doc.

**Diagnosis:** pane is rubber-stamping onboarding (doesn't actually load context).

**Recovery:** require ack to include a 1-sentence summary of role + domain + question. Reject acks without this signal.

---

## F-3xx: Phase 3 triage niches

### F-304 — Hypothesis with circular falsifier

**Symptom:** `H-*.falsifier` semantically equivalent to `not H-*.claim` ("hypothesis fails if hypothesis is wrong").

**Diagnosis:** placeholder falsifier; not actually testable.

**Recovery:** reject. Falsifier must describe a CONCRETE OBSERVABLE, not a tautology. Per ✂ Exclusion-Test card.

### F-305 — Hypothesis confidence not assigned

**Symptom:** `H-*.confidence` field empty or `?`.

**Diagnosis:** proposer skipped the field.

**Recovery:** default to `speculative` and require Phase 4 round 1 to upgrade or downgrade.

### F-306 — Triage ranks hypothesis without comparing falsifiers

**Symptom:** Triage pane assigns confidence based on how compelling the *claim* sounds, not based on how *testable* the falsifier is.

**Diagnosis:** Triage pane drifted into rhetoric.

**Recovery:** dispatch `MO-03b-triage.md` again with explicit "rank by falsifier-testability, not by claim-elegance" directive.

### F-307 — Slate has third alternative but it's degenerate

**Symptom:** the `origin:third_alternative` H is "we don't know" or "it depends" or trivial in some way.

**Diagnosis:** triage pane filed a placeholder to satisfy the invariant without actually thinking.

**Recovery:** reject the degenerate third alternative. Run `MO-03c-third-alternative.md` again with operator clarification: "real third alternative must reject the SHARED ASSUMPTION of the binary, not be a non-answer."

---

## F-4xx: Phase 4 investigation niches

### F-405 — Evidence cluster from single source

**Symptom:** an `H-*` has 5+ supporting EVs, but ALL cite the same paper / repo / blog post.

**Diagnosis:** correlated evidence; not independent confirmation.

**Recovery:** require ≥2 *independent sources* before counting toward `confidence:high`. Demote H to `confidence:medium` until diversified.

### F-406 — Investigator answers different question than assigned

**Symptom:** the per-H thread shows the Investigator producing evidence that's interesting but doesn't address `<H_ID>.expected_evidence`.

**Diagnosis:** scope drift; investigator pursuing their own curiosity.

**Recovery:** re-dispatch `MO-04a-investigate.md` with explicit "your first deliverable is verbatim citation confirming/denying expected_evidence" directive.

### F-407 — Quickie pilot result misinterpreted

**Symptom:** quickie returned negative; investigator continues with flagship investigation as if quickie were positive (or inconclusive).

**Diagnosis:** sunk-cost bias; investigator wants to do the flagship.

**Recovery:** explicitly invoke `MO-falsifier-fired.md` if the quickie's negative result fired the H's falsifier. Otherwise, document the inconclusive result and proceed with reduced confidence.

### F-408 — Anomaly silently incorporated into H

**Symptom:** an `AN-*` bead's observation appears in `H-*.description § Detail` without being filed as anomaly bead.

**Diagnosis:** investigator patched the anomaly into the theory rather than quarantining (per ΔE).

**Recovery:** reject the H description amendment. Re-file the anomaly properly. If anomaly clusters, run `MO-anomaly-cluster.md`.

### F-409 — Evidence pack inflation without round structure

**Symptom:** EV-pack-H-007.md grows by 50% each round; Round Log section is missing or vague.

**Diagnosis:** investigator dumps but doesn't structure.

**Recovery:** require Round Log entries per round (timestamp, EVs filed, falsifier probe result, operators applied, next-action).

### F-410 — Cass-mined EV cited as primary source

**Symptom:** a `EV-*` with `type:prior_session` is cited in distillation as if it were primary evidence.

**Diagnosis:** cass-mined content was treated as authoritative without re-verification.

**Recovery:** mark `verified:false` on cass-mined EVs by default; require independent verification before they count toward confirmed-state H.

---

## F-5xx: Phase 5 debate niches

### F-504 — Both champions same model family despite available diversity

**Symptom:** debate thread shows two cc panes championing H-005 vs H-006, with cod and gmi panes available but not used.

**Diagnosis:** operator pair-selection skipped 🤝 GAN discipline.

**Recovery:** apply `MO-debate-pair-selection.md`; re-pair with cross-family champions.

### F-505 — Adjudicator never reads cited EV

**Symptom:** adjudication post lists "I rule for H-005" without verbatim quote from any cited EV.

**Diagnosis:** rubber-stamp adjudication.

**Recovery:** reject. Adjudicator must include verbatim quote from at least one decisive EV.

### F-506 — Debate turns into negotiation

**Symptom:** champions softening positions toward each other; "well, you're partly right..." in counter-rebuttal.

**Diagnosis:** debate substituted for adversarial probing; collapsed to consensus-seeking.

**Recovery:** halt debate; remind champions per `MO-05a-cross-exam.md` that compromise is anti-Brenner. If champions can't sharpen disagreement, escalate to adjudicator immediately.

### F-507 — H survives debate but no DEBATE-* bead filed

**Symptom:** post-Phase 5, a `state: confirmed` H exists without any `DEBATE-*.adjudication` bead.

**Diagnosis:** state was flipped without proper adjudication infrastructure.

**Recovery:** retroactively file `DEBATE-*` bead documenting which actual debate (if any) settled the H. If no actual debate occurred, downgrade H to `state: active` and force a real Phase 5 round.

---

## F-6xx: Phase 6 synthesis niches

### F-604 — Per-family distillation copies meta-synthesis

**Symptom:** by_cod.md and by_gmi.md look suspiciously similar to meta_synthesis.md.

**Diagnosis:** synthesizers read each other's outputs; cross-pollination defeats triangulation.

**Recovery:** re-run Phase 6 synthesizers in parallel WITHOUT inter-family read access. Each synthesizer gets only the source materials, not peer outputs.

### F-605 — Disagreement register entries are forced

**Symptom:** disagreement register has the required count, but each entry is a wording dispute or cosmetic difference.

**Diagnosis:** meta-synthesizer manufactured disagreements to satisfy F-603.

**Recovery:** reject. Each disagreement must name a *substantive* claim difference, not phrasing. Run `MO-06b-meta-synthesize.md` again with explicit substantive-disagreement directive.

### F-606 — Distillation imports framing from prior session

**Symptom:** distillation cites prior brennerbot session's distillation as authoritative without independent reasoning.

**Diagnosis:** cross-session inheritance bypasses fresh triangulation.

**Recovery:** prior-session distillation can be a *reference*, not a *foundation*. Synthesizers must re-derive their family's view from current evidence, not from prior conclusions.

### F-607 — Bayesian substrate inconsistent across distillations

**Symptom:** by_cc.md says H-005 is `posterior:high`; by_cod.md says `posterior:low` — without registered disagreement.

**Diagnosis:** synthesizers used different priors but didn't surface it.

**Recovery:** the meta-synthesizer must register this as a disagreement explicitly: "cc reads H-005 as high-confidence due to <reasons>; cod reads as low-confidence due to <reasons>."

---

## F-7xx: Phase 7 audit niches

### F-704 — Audit trio-round produces only typo findings while critical issue exists

**Symptom:** Phase 7 trio-round 2 reports only typo findings; ubs is clean; but a clear methodology violation (e.g., F-501 throughout) was never flagged.

**Diagnosis:** auditors are scanning for typos rather than methodology.

**Recovery:** re-dispatch `MO-07a-fresh-eyes.md` with explicit "your task is to find methodology violations, not typos. Apply ⊞, ∿, ✂ re-verify per the prompt."

### F-705 — Audit pane is one of the original swarm panes

**Symptom:** pane that wrote `by_cc.md` distillation is now auditing it.

**Diagnosis:** Phase 7 rotation rule violated.

**Recovery:** kill+respawn the audit panes on different model families per ROSTER-PLANS.md. Re-dispatch.

### F-706 — Audit accepts critical finding but doesn't address it

**Symptom:** `AF-NNN.severity:critical` exists with `status:open`; Phase 7 is "marked converged."

**Diagnosis:** convergence criterion was relaxed.

**Recovery:** Phase 7 cannot exit with open critical findings. Address or downgrade to `high`/`medium` with explicit reasoning. F-703 hard-block applies.

---

## F-9xx: Phase 9 handback niches

### F-904 — Handback recommends a phase that's already complete

**Symptom:** `next_loop_recommendation.phase: 4` but Phase 4 already completed and the open threads aren't actually Phase 4 work.

**Diagnosis:** handback writer mis-categorized the open work.

**Recovery:** rewrite. Open threads belong to the phase that would naturally address them, not the phase that produced them.

### F-905 — Handback "Risk register" hand-waves

**Symptom:** Risk entries like "things might go wrong" without specifics.

**Diagnosis:** lazy risk register.

**Recovery:** each risk entry must name (a) the specific risk, (b) the trigger that would manifest it, (c) the mitigation. Per HANDBACK template.

### F-906 — Handback omits volatile-source caveat

**Symptom:** session had volatile sources but HANDBACK doesn't list them.

**Diagnosis:** verification-first protocol skipped at handback.

**Recovery:** add the `## Volatile-source caveat` section per VERIFICATION-FIRST.md.

---

## F-10xx: Phase 10 drift niches

### F-1004 — Drift verdict "convergent" despite missing operator

**Symptom:** verdict is `convergent`; one of the 15 operators never fired.

**Diagnosis:** drift auditor missed the gap.

**Recovery:** re-run drift check with explicit "verify all 15 operators fired or document why not" directive.

### F-1005 — Lessons committed without addressing the regression

**Symptom:** Phase 10 produced a regression R-001; lessons section has L-001..L-003 but none address R-001.

**Diagnosis:** auditor proposed unrelated improvements; ignored the actual regression.

**Recovery:** lessons must address ≥1 regression each (or explicitly document why a regression is being deferred).

### F-1006 — Same drift verdict three sessions in a row

**Symptom:** three consecutive sessions with `divergent-improvement` for the same I-001 (same replacement).

**Diagnosis:** the "improvement" should be promoted to canonical (no longer a deviation), OR the methodology is genuinely wrong and we keep "improving" it without committing.

**Recovery:** at the third occurrence, commit the change to canonical. Update OPERATORS.md / MARCHING-ORDERS.md / etc. to reflect the new canonical.

---

## Cross-cutting niches

### F-CX1 — Workspace contains multiple sessions intermixed

**Symptom:** `intake/` contains question_of_record_v1.md AND question_of_record_v2.md.

**Diagnosis:** operator started Phase 1 twice without reframing properly.

**Recovery:** the workspace serves ONE session. Start a separate, explicitly named session workspace before writing v2; OR if v2 is a refinement, document via `parent:` reference and pick one as canonical. Do not clean this up by deleting files unless the operator gives explicit deletion approval.

### F-CX2 — RESUME.md exists but session was never properly frozen

**Symptom:** RESUME.md present but `phase_8_complete.flag` missing.

**Diagnosis:** Phase 8 was abandoned mid-execution.

**Recovery:** verify whether Phase 8 actually completed. If not, re-run Phase 8. If RESUME.md is from a previous session, archive it under a date-stamped name.

### F-CX3 — Phase numbering skips

**Symptom:** `phase_3_complete.flag` and `phase_5_complete.flag` exist but not `phase_4_complete.flag`.

**Diagnosis:** Phase 4 silently skipped; or operator manually created the wrong flag.

**Recovery:** Phase 4 cannot be skipped. If it was, the work is methodologically defective. Audit retroactively (`audit-bead-invariants.sh phase4_round`) and either complete Phase 4 or restart from Phase 3 exit.

### F-CX4 — git workspace dirty across multiple operations

**Symptom:** `git status` shows uncommitted changes from multiple panes/operations; can't tell what's incremental and what's stale.

**Diagnosis:** insufficient commit cadence.

**Recovery:** commit per-phase per WORKSPACE-LAYOUT.md discipline. Don't let dirty state accumulate; it makes resume + drift-check unreliable.

### F-CX5 — Subagent invoked from a swarm pane (drift-auditor specifically)

**Symptom:** Phase 10 drift check ran from inside the brennerbot session's pane (e.g., pane 1 of the squad).

**Diagnosis:** AP-O11 violation. Drift check must be a fresh agent.

**Recovery:** re-run drift check from a fresh `general-purpose` Agent dispatched outside the session. Discard the pane-internal drift check.

---

## Lookup query

```bash
# Find F-### codes mentioned in this session's audit-finding beads:
br list --label=audit-finding --json | \
  jq -r '.issues[]? | try ((.description // "") | match("F-[0-9]+").string) catch empty' | \
  sort -u
```

---

## Promotion to FAILURE-TABLE.md

When an extended F-### appears in ≥3 sessions, promote it to FAILURE-TABLE.md (move the entry, leave a forwarding pointer here). The main FAILURE-TABLE.md is the operator's tick-time lookup; this catalog is for unusual cases.

Phase 10 drift-check should periodically scan extended-failure occurrences and propose promotions.
