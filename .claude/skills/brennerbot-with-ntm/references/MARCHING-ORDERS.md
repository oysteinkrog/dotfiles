# MARCHING-ORDERS.md — Index, Parameter Grammar, Composition

<!-- TOC: Index | Parameter Grammar | Composition Cheat-Sheet | Marching-Order Authoring Rules | Anti-Patterns in Dispatch -->

Every dispatch in this skill is a stored, parameterized marching-order template. Operators don't free-write prompts mid-session — they pick a template, fill placeholders, and ship.

Templates live in `assets/marching-orders/MO-*.md`. This file is the **index + parameter grammar + composition rules**.

---

## Index

| Template | Phase | Purpose | Parameters |
|----------|-------|---------|------------|
| [MO-01-frame-question.md](../assets/marching-orders/MO-01-frame-question.md) | 1 | Brenner Step-0 framing | `<RAW_USER_ASK>` `<TARGET>` `<MODE>` `<SESSION_ID>` `<WORKSPACE_PATH>` |
| [MO-02-onboarding.md](../assets/marching-orders/MO-02-onboarding.md) | 2 | Brief a pane on its role | `<PANE_N>` `<ROLE>` `<MODEL>` `<SESSION_ID>` `<WORKSPACE_PATH>` `<QUESTION_OF_RECORD_PATH>` `<PEER_LIST>` `<COORDINATION_MODE>` `<PRODUCTIVE_IGNORANCE>` `<DOMAIN>` |
| [MO-03a-propose.md](../assets/marching-orders/MO-03a-propose.md) | 3 | Propose hypotheses | `<PANE_N>` `<SESSION_ID>` `<COUNT>` `<WORKSPACE_PATH>` |
| [MO-03b-triage.md](../assets/marching-orders/MO-03b-triage.md) | 3 | Dedupe + cluster + rank | `<PANE_N>` `<SESSION_ID>` |
| [MO-03c-third-alternative.md](../assets/marching-orders/MO-03c-third-alternative.md) | 3 | Force-inject "both could be wrong" | `<PANE_N>` `<SESSION_ID>` |
| [MO-04a-investigate.md](../assets/marching-orders/MO-04a-investigate.md) | 4 | Fill evidence pack for one H | `<PANE_N>` `<H_ID>` `<SESSION_ID>` |
| [MO-04b-devils-advocate.md](../assets/marching-orders/MO-04b-devils-advocate.md) | 4 | Attack the strongest H | `<PANE_N>` `<H_ID>` `<SESSION_ID>` |
| [MO-04c-evidence-pack.md](../assets/marching-orders/MO-04c-evidence-pack.md) | 4 | Per-H evidence pack template (the artifact, not the dispatch) | `<H_ID>` |
| [MO-05a-cross-exam.md](../assets/marching-orders/MO-05a-cross-exam.md) | 5 | Pairwise structured debate | `<PANE_N>` `<H_I>` `<H_J>` `<SESSION_ID>` `<ROUND>` |
| [MO-05b-adjudicate.md](../assets/marching-orders/MO-05b-adjudicate.md) | 5 | Adjudicate debate; flip H state | `<PANE_N>` `<DEBATE_ID>` `<SESSION_ID>` |
| [MO-06a-distill.md](../assets/marching-orders/MO-06a-distill.md) | 6 | Per-model-family distillation | `<PANE_N>` `<MODEL_FAMILY>` `<SESSION_ID>` `<WORKSPACE_PATH>` |
| [MO-06b-meta-synthesize.md](../assets/marching-orders/MO-06b-meta-synthesize.md) | 6 | Reconcile distillations | `<PANE_N>` `<SESSION_ID>` `<WORKSPACE_PATH>` |
| [MO-07a-fresh-eyes.md](../assets/marching-orders/MO-07a-fresh-eyes.md) | 7 | Verbatim trio of fresh-eyes prompts | `<PANE_N>` `<SESSION_ID>` |
| [MO-08-freeze.md](../assets/marching-orders/MO-08-freeze.md) | 8 | RESUME.md + checkpoint | `<PANE_N>` `<SESSION_ID>` `<WORKSPACE_PATH>` `<SKILL_SCRIPTS>` |
| [MO-09-handback.md](../assets/marching-orders/MO-09-handback.md) | 9 | One-page handback | `<PANE_N>` `<SESSION_ID>` `<WORKSPACE_PATH>` `<SKILL_SCRIPTS>` |
| [MO-10-drift-check.md](../assets/marching-orders/MO-10-drift-check.md) | 10 | Trajectory vs canonical Brenner | `<WORKSPACE_PATH>` |
| [MO-mode-flip-investigator-to-advocate.md](../assets/marching-orders/MO-mode-flip-investigator-to-advocate.md) | 4 | Flip a confirmation-biased investigator into devil's advocate | `<PANE_N>` `<H_ID>` `<SESSION_ID>` `<WORKSPACE_PATH>` |
| [MO-unstick-stuck-investigator.md](../assets/marching-orders/MO-unstick-stuck-investigator.md) | 4 | Specific-terse nudge for a stuck investigator | `<PANE_N>` `<H_ID>` `<LAST_OUTPUT_SHA>` |
| [MO-resume.md](../assets/marching-orders/MO-resume.md) | (post-resume) | Briefing after `resume-session.sh` | `<PANE_N>` `<ROLE>` `<DOMAIN>` `<LAST_THREAD>` `<LAST_PHASE_COMPLETED>` `<MODE_TO_RESUME>` `<NEXT_PHASE>` `<SESSION_ID>` |
| [MO-cass-mine.md](../assets/marching-orders/MO-cass-mine.md) | 0/1/mid | Mine cass for prior sessions per CASS-MINING-RECIPES.md | `<TOPIC>` `<DECISION_RULE>` |
| [MO-corpus-curate.md](../assets/marching-orders/MO-corpus-curate.md) | 1 | Phase 1 corpus ingestion + content-hash pinning | `<CORPUS_INPUT_PATH>` `<CORPUS_TYPE>` `<WORKSPACE_PATH>` |
| [MO-falsifier-fired.md](../assets/marching-orders/MO-falsifier-fired.md) | 4/5 | Formal kill protocol when a falsifier fires | `<H_ID>` `<EV_OR_T_ID>` `<PANE_N>` `<SESSION_ID>` |
| [MO-quickie-pilot.md](../assets/marching-orders/MO-quickie-pilot.md) | 4 | ≤30-min cheap pilot to de-risk a flagship investigation | `<PANE_N>` `<H_ID>` `<SESSION_ID>` |
| [MO-cross-domain-import.md](../assets/marching-orders/MO-cross-domain-import.md) | 3/4 | Import a pattern from an unrelated field (⊕) | `<PANE_N>` `<SOURCE_DOMAIN>` `<TARGET_QUESTION>` `<SESSION_ID>` |
| [MO-cross-family-debate.md](../assets/marching-orders/MO-cross-family-debate.md) | 4/5 | Force an H through a different model-family challenge | `<H_ID>` `<CHAMPION_PANE>` `<CHAMPION_FAMILY>` `<CHALLENGER_PANE>` `<CHALLENGER_FAMILY>` `<SESSION_ID>` |
| [MO-anomaly-cluster.md](../assets/marching-orders/MO-anomaly-cluster.md) | 4 | Promote clustered anomalies to a new H (origin:anomaly_spawned) | `<PANE_N>` `<CLUSTER_AN_IDS>` `<SHARED_FEATURE>` `<SESSION_ID>` |
| [MO-anomaly-quarantine.md](../assets/marching-orders/MO-anomaly-quarantine.md) | 4/7 | Quarantine an anomaly without patching the theory around it | `<ANOMALY_BEAD_ID>` `<RELATED_H_IDS>` `<SESSION_ID>` |
| [MO-debate-pair-selection.md](../assets/marching-orders/MO-debate-pair-selection.md) | 5 | Operator-side: select Phase 5 debate pairs with model-family discipline | `<SESSION_ID>` |
| [MO-debate-deadlock-resolution.md](../assets/marching-orders/MO-debate-deadlock-resolution.md) | 5 | Recover a debate that stopped producing discriminative signal | `<DEBATE_BEAD_ID>` `<H_PAIR>` `<SESSION_ID>` |
| [MO-evidence-verify.md](../assets/marching-orders/MO-evidence-verify.md) | 4/7 | Independent verification of an evidence bead | `<PANE_N>` `<EV_ID>` `<SESSION_ID>` |
| [MO-evidence-intake-url.md](../assets/marching-orders/MO-evidence-intake-url.md) | any | Ingest a URL as anchored evidence | `<URL>` `<RELEVANCE>` `<H_ID>` `<SESSION_ID>` `<PANE_N>` |
| [MO-evidence-intake-pdf.md](../assets/marching-orders/MO-evidence-intake-pdf.md) | any | Ingest a PDF as anchored evidence | `<PDF_INPUT>` `<RELEVANCE>` `<H_ID>` `<SESSION_ID>` `<PANE_N>` |
| [MO-evidence-promote.md](../assets/marching-orders/MO-evidence-promote.md) | 4/7 | Strengthen an EV to the target confidence tier | `<EV_ID>` `<TARGET_CONFIDENCE>` `<SESSION_ID>` `<PANE_N>` |
| [MO-context-saturated-rotation.md](../assets/marching-orders/MO-context-saturated-rotation.md) | any | Rotate a pane whose context window is saturated (≥85%) | `<SATURATED_PANE_N>` `<NEW_PANE_N>` `<H_OR_DOMAIN>` `<ROLE>` `<SESSION_ID>` |
| [MO-corpus-update.md](../assets/marching-orders/MO-corpus-update.md) | any | Mid-session corpus addition with decision rule | `<NEW_SOURCE_PATH>` `<RATIONALE>` `<SESSION_ID>` |
| [MO-stale-corpus-refresh.md](../assets/marching-orders/MO-stale-corpus-refresh.md) | any | Refresh volatile or drifted sources | `<DRIFTED_SOURCES>` `<SESSION_ID>` `<PANE_N>` |
| [MO-emergency-stop.md](../assets/marching-orders/MO-emergency-stop.md) | any | Operator-initiated halt with safe shutdown protocol | `<SESSION_ID>` `<WORKSPACE_PATH>` `<SKILL_SCRIPTS>` `<REASON>` `<DETAIL>` |
| [MO-incident-compressed.md](../assets/marching-orders/MO-incident-compressed.md) | incident mode | Single-pane compressed incident investigation | `<INCIDENT_DESCRIPTION>` `<TIME_BUDGET_MINUTES>` `<SESSION_ID>` |
| [MO-domain-handoff.md](../assets/marching-orders/MO-domain-handoff.md) | 4 | Cross-pane domain transfer with continuity bead | `<FROM_PANE_N>` `<TO_PANE_N>` `<DOMAIN>` `<REASON>` `<SESSION_ID>` |
| [MO-cass-archive-current.md](../assets/marching-orders/MO-cass-archive-current.md) | 8/10 | Tag session for cass-discoverability | `<SESSION_ID>` `<WORKSPACE_PATH>` `<SKILL_SCRIPTS>` `<ARCHETYPE>` `<TIER>` `<VERDICT>` |
| [MO-hypothesis-pre-registration.md](../assets/marching-orders/MO-hypothesis-pre-registration.md) | 3→4 | Lock falsifier with timestamp+hash before investigation | `<SESSION_ID>` `<COMMITMENT_DURATION>` `<WORKSPACE_PATH>` |
| [MO-roster-rebalance.md](../assets/marching-orders/MO-roster-rebalance.md) | any | Multi-pane roster reorganization | `<SESSION_ID>` `<REASON>` `<NEW_ROSTER>` `<WORKSPACE_PATH>` |
| [MO-pane-respawn.md](../assets/marching-orders/MO-pane-respawn.md) | any | Replace or re-onboard a dead pane without losing domain state | `<DEAD_PANE_ID>` `<NEW_FAMILY>` `<DOMAINS>` `<WORKSPACE_PATH>` |
| [MO-bead-linking.md](../assets/marching-orders/MO-bead-linking.md) | 3/4/5 | Add explicit bead relationships after new H/EV/T links are known | `<PARENT_BEAD>` `<CHILD_BEAD>` `<RELATIONSHIP_TYPE>` |
| [MO-confidence-downgrade.md](../assets/marching-orders/MO-confidence-downgrade.md) | 4/7 | Downgrade an H after contradictory evidence or audit findings | `<H_ID>` `<DOWNGRADE_REASON>` `<NEW_CONFIDENCE>` `<SESSION_ID>` |
| [MO-deliverable-rejection.md](../assets/marching-orders/MO-deliverable-rejection.md) | 9 | Reject and repair a handback or memo that fails the bar | `<DELIVERABLE_PATH>` `<REJECTION_REASON>` `<SESSION_ID>` |
| [MO-academic-replication.md](../assets/marching-orders/MO-academic-replication.md) | 4 | Replicate a load-bearing paper claim before citing it | `<PAPER_ID>` `<CLAIM>` `<H_ID>` `<EV_ID>` `<SESSION_ID>` |
| [MO-pre-publication-review.md](../assets/marching-orders/MO-pre-publication-review.md) | 7 | Adversarial review before external publication | `<DELIVERABLE_PATH>` `<PUBLICATION_VENUE>` `<SESSION_ID>` |
| [MO-dual-use-review.md](../assets/marching-orders/MO-dual-use-review.md) | 7 | Dual-use risk review for sensitive deliverables | `<DELIVERABLE_PATH>` `<DOMAIN>` `<SESSION_ID>` |
| [MO-post-mortem-formalization.md](../assets/marching-orders/MO-post-mortem-formalization.md) | post-incident | Turn an incident verdict into a formal post-mortem | `<INCIDENT_VERDICT_PATH>` `<SESSION_ID>` |
| [MO-cross-session-reconciliation.md](../assets/marching-orders/MO-cross-session-reconciliation.md) | 0/10 | Reconcile two workspaces that reached conflicting verdicts | `<W1_PATH>` `<W2_PATH>` `<RECONCILER_PANE>` |
| [MO-stress-test-self-check.md](../assets/marching-orders/MO-stress-test-self-check.md) | 0 | Pre-flight self-check for high-stakes sessions | `<TIER>` `<MODE>` `<ARCHETYPE>` `<OPERATOR_NAME>` |

---

## Parameter Grammar

Placeholders use angle-bracket convention: `<PARAM_NAME>`. `scripts/dispatch-marching-order.sh` substitutes them via shell substitution at dispatch time.

```bash
# Render and dispatch:
./scripts/dispatch-marching-order.sh MO-04a-investigate \
  --PANE_N=3 \
  --H_ID=H-007 \
  --SESSION_ID=RS-20260506-event-log \
  --target-pane=3 \
  --target-session=brennerbot-event-log
```

**Auto-filled placeholders** (set by the dispatcher when enough context is available):

| Placeholder | Source |
|-------------|--------|
| `<TIMESTAMP_UTC>` | Always set from `date -u +%Y-%m-%dT%H:%M:%SZ` |
| `<SKILL_SCRIPTS>` | Always set to the installed skill's `scripts/` directory |
| `<WORKSPACE_PATH>` | Set from `--workspace=<path>` if the caller did not pass `--WORKSPACE_PATH=...` |
| `<SESSION_ID>` | Set from `<workspace>/.brenner_workspace/phase0_scope_decision.md` when `--workspace` or `--WORKSPACE_PATH` is available |
| `<QUESTION_OF_RECORD_PATH>` | Set to `<WORKSPACE_PATH>/intake/question_of_record.md` when a workspace path is available |

If no workspace path is available, pass `--SESSION_ID=...` and
`--QUESTION_OF_RECORD_PATH=...` explicitly. The dispatcher validates only the
parameters declared by the selected MO, so missing declared placeholders fail
before anything is sent to a pane.

---

## Composition Cheat-Sheet

When dispatching multiple panes for the same phase, follow these compositions:

### Phase 3 (parallel proposal + sequential triage)

```
ALL Proposers in parallel:
    MO-03a-propose.md (with PANE_N varying per pane)
WAIT for all to file beads
ONE Triage pane:
    MO-03b-triage.md
IF triage detects false binary:
    MO-03c-third-alternative.md to Triage pane
```

### Phase 4 (parallel investigation; devil's advocates running independently)

```
PER active H:
    Assign one Investigator pane (round-robin or by domain affinity)
    MO-04a-investigate.md (PANE_N, H_ID, SESSION_ID)

PER top-2 highest-confidence H:
    Assign one Devil's-Advocate pane (DIFFERENT model family from Investigator)
    MO-04b-devils-advocate.md

EACH ROUND:
    Run scripts/convergence-check.sh
    IF kill_rate < add_rate AND round < 6:
        Repeat above
    ELSE:
        Exit Phase 4
```

### Phase 5 (parallel pairs)

```
PER hypothesis pair:
    Open thread RS-...-DEBATE-<H_I>-vs-<H_J>   # bead IDs interpolated verbatim, e.g. RS-...-DEBATE-H-001-vs-H-002
    Dispatch MO-05a-cross-exam.md to two panes (different model families when possible)
    Run 1-3 rounds of opening/rebuttal/counter
    Dispatch MO-05b-adjudicate.md to a rotating Adjudicator (NEVER same pane two debates in a row)
```

### Phase 6 (per-family parallel; meta sequential)

```
PER model family in roster {cc, cod, gmi}:
    Assign Synthesizer pane of that family
    Dispatch MO-06a-distill.md
WAIT for all
ONE Meta-synthesizer pane (different family from dominant):
    Dispatch MO-06b-meta-synthesize.md
IF disagreement_register has fewer than (N choose 2) entries:
    Reject and re-dispatch with explicit directive
```

### Phase 7 (parallel trio per pane × N rounds)

```
EACH ROUND:
    Dispatch MO-07a-fresh-eyes.md to ALL panes in parallel
    Each pane runs all three prompts and files audit-finding beads
    Operator collects findings, addresses or defers
    IF 2 consecutive rounds had only trivial findings:
        Exit Phase 7
    ELSE:
        Repeat
```

---

## Marching-Order Authoring Rules

When extending the library:

1. **One template per cognitive move.** Don't bundle multiple operators into a single MO; that defeats the operator algebra.
2. **Parameters are explicit.** Every `<PLACEHOLDER>` must be documented at the top of the template with its expected value.
3. **First action must be specific.** The first instruction in the body should produce a concrete artifact (file path, bead id, quote) within 5 minutes — not "think about the question."
4. **Ship-or-surface SLA inherited from `/vibing-with-ntm`.** Every template includes: "Within 60 minutes, either commit a real diff / file a bead / surface a specific blocker — no prose mental models."
5. **AGENTS.md compliance.** First instruction is always "Read the governing `AGENTS.md` and `<WORKSPACE_PATH>/intake/question_of_record.md` end-to-end." Prefer `<WORKSPACE_PATH>/AGENTS.md` when it exists; otherwise use the nearest repo-level `AGENTS.md` that governs the target. Cache after Phase 2 onboarding to save context; fresh panes after restart do a full re-read.
6. **Convergence language ban.** Templates explicitly forbid output of "exemplary", "already complete", "no fixes needed" without an accompanying `EV-*` citation. (Per `/vibing-with-ntm` AP-32.)

---

## Anti-Patterns in Dispatch

| ✗ | Why |
|---|-----|
| Free-writing a prompt mid-session | Loses operator-algebra discipline; unreproducible at resume |
| Bundling Phase 3a + Phase 3b dispatch into one template | Phase 3a is parallel; Phase 3b is sequential — they cannot share a template |
| Sending a marching order without `<SESSION_ID>` | Beads filed will not link back to the session; resume breaks |
| Dispatching MO-04a to a pane with no `H_ID` parameter | Pane has nothing to investigate — wastes a turn |
| Dispatching MO-05b to the same pane that championed an H in the debate | Adjudicator bias guaranteed |
| Dispatching MO-06b to the same pane that wrote a per-family distillation | Meta-synthesis must be from a different perspective |
| Dispatching MO-07a to ONLY the panes that did Phase 6 | Fresh-eyes value depends on rotation — kill+respawn or use different panes |
