# EXEMPLAR-SESSION-WALKTHROUGH.md — A Concrete Phase 1→10 Walkthrough

## Table of Contents

- Why a walkthrough
- The exemplar question
- Phase 1: Framing in 22 minutes
- Phase 2: Bootstrap in 8 minutes
- Phase 3: Hypotheses in 35 minutes
- Phase 4: Investigation in 2.5 hours
- Phase 5: Adversarial debate in 45 minutes
- Phase 6: Distillation in 65 minutes
- Phase 7: Audit in 50 minutes
- Phase 8: Freeze in 12 minutes
- Phase 9: Handback in 18 minutes
- Phase 10: Drift check in 25 minutes
- Total: 6h 10min
- What this walkthrough exemplifies
- What a fresh operator should learn
- Anti-patterns avoided

A concrete walkthrough of a real T3 (Strategic-tier) Squad-roster brennerbot session, end-to-end. The methodology in `references/PHASES.md` is abstract; this walkthrough is what it *looks like* in practice.

For new operators (per OPERATOR-ONBOARDING-CURRICULUM.md), read this twice before running your first T3. For experienced operators, skim to recalibrate.

---

## Why a walkthrough

The hardest part of brennerbot is connecting the abstract operator algebra (◊ ⊘ 𝓛 ≡ ✂ …) to the concrete tick-time decisions. References describe each operator individually; a walkthrough shows them composing under realistic time pressure with realistic ambiguity.

Specifically, this exemplar models:

- **What the operator's HANDS do** (which scripts, which dispatches, which checks)
- **What the operator's EYES watch for** (red-flag phrases, convergence numbers, anomalies)
- **What the operator DOESN'T do** (the deferrals to /vibing-with-ntm, /multi-pass-bug-hunting)
- **Realistic timing** — phases are not instantaneous; the operator is human-on-loop

---

## The exemplar question

> "Under workload class W (current 8k req/s read-heavy with 5% writes, forecast 80k req/s in 18 months, p99 ≤ 200ms target), should we migrate from PostgreSQL 15 to (a) keep PostgreSQL 16 + tune, (b) Citus on PostgreSQL, or (c) ScyllaDB? What's the load-bearing factor in the choice, and what's the migration plan?"

User context: a SaaS B2B company at growth stage; 4-engineer infra team; PostgreSQL 15 in production; pgbouncer connection pool; no read replicas yet; 24-month decision horizon.

Tier: T3 Strategic. Recipe match: R10 (Storage selection) + R14 (Migration risk) per DOMAIN-RECIPE-LIBRARY.md.

Roster: Squad. 5 panes:
- p1 (cc) — Proposer + Investigator-1
- p2 (cc) — Investigator-2
- p3 (cod) — Devil's-Advocate
- p4 (gmi) — Synthesizer + Adjudicator (rotating)
- p5 (cc) — Productive-ignorance pane (⊙)

Wall-time budget: 5h active (per WALL-TIME-BUDGET.md T3 row).

---

## Phase 1: Framing in 22 minutes

**Operator's first 60 seconds:**

```bash
$ SKILL_DIR=/path/to/installed/brennerbot-with-ntm
$ SKILL_SCRIPTS="$SKILL_DIR/scripts"
$ WORKSPACE="$HOME/brennerbot_sessions/storage-eval"

$ "$SKILL_SCRIPTS/check-skills.sh" "$WORKSPACE"
$ "$SKILL_SCRIPTS/bootstrap-session.sh" "$WORKSPACE" \
    "PG15 vs PG16+tune vs Citus vs ScyllaDB at workload W" \
    --mode=fresh-question --roster=squad
$ SESSION_ID="$(sed -n 's/^# Phase 0 Scope Decision — //p' "$WORKSPACE/.brenner_workspace/phase0_scope_decision.md")"
$ cd "$WORKSPACE"
```

Bootstrap creates the workspace, initializes git + beads, writes a starter `intake/question_of_record.md` template.

**Operator's next 8 minutes** — fill in the template by walking the user through FRAMING-WORKBOOK.md F1-F9:

```
F1 (Trigger): "What changed recently to make this question urgent now?"
  User: "Customer onboarding spike forecast for Q3 — capacity planning required."
F2 (Stakes): "What's the cost of acting wrong? Of inaction?"
  User: "Wrong choice = 6-month rollback cost ~$120k engineering + customer SLO breach.
         Inaction = SLO breach in Q3 forecasts."
F3 (Scope): "What's IN scope? OUT of scope?"
  User: IN: read-heavy workload, write at 5%, multi-region future.
       OUT: backup strategy (separate Q), real-time analytics (separate stack).
F4 (Paradox): "What makes this hard?"
  User: "Each option has a credible champion in the team; we keep going in circles."
F5 (Falsifier): "What evidence would prove a given option wrong?"
  User: After iteration:
   - PG15+tune wrong if benchmark p99 stays >250ms at forecast scale even with tuning
   - Citus wrong if shard-key choice forces cross-shard joins for >15% of queries
   - ScyllaDB wrong if write-throughput claims don't replicate at our query mix
F6 (Mode): fresh-question (per Mode Router)
F7 (Corpus): pgconf 2024 talks; Citus + ScyllaDB whitepapers; pgbouncer perf benchmarks; our prod metrics
F8 (Constraints): 4-engineer infra team; 24-month horizon; existing PG15 deploy
F9 (Tier): T3 Strategic
```

**Operator's next 6 minutes** — codify the framing into Phase 1 deliverables:

```bash
$ vim "$WORKSPACE/intake/question_of_record.md"
# (Operator drafts; user reviews; iterate twice; user confirms)

$ vim "$WORKSPACE/intake/decision-rule.md"
# (Use subagents/decision-rule-extractor.md template)
```

**Operator's next 4 minutes** — pin corpus sources:

```bash
# Pin PostgreSQL official docs at version 16 release tag
git -C corpus/ingested/S-001-pg16-docs clone --depth 1 \
    --branch REL_16_STABLE https://github.com/postgres/postgres
sha256sum corpus/ingested/S-001-pg16-docs/.git/HEAD > corpus/ingested/S-001-pg16-docs/.hash

# Pin Citus paper PDF
mkdir -p corpus/ingested/S-002-citus-paper
curl -sL https://www.citusdata.com/static/citus-paper.pdf \
    -o corpus/ingested/S-002-citus-paper/main.pdf
sha256sum corpus/ingested/S-002-citus-paper/main.pdf | awk '{print $1}' \
    > corpus/ingested/S-002-citus-paper/.hash

# (Repeat for ScyllaDB whitepapers, perf benchmarks, prod metrics export)

$ vim corpus/corpus_index.md  # Index all 8 pinned sources
```

**Operator's last 4 minutes** — file Q-001 bead and run Phase 1 readiness check:

```bash
$ q_ref="Q-001"
$ q_id="$(br create "$q_ref: Storage choice for workload W" \
    --type=question --labels=q-of-record --priority=0 \
    --slug="$q_ref" --external-ref="$q_ref" --silent \
    --description="$(cat intake/question_of_record.md)")"
$ printf 'Created %s as br id %s\n' "$q_ref" "$q_id"

$ "$SKILL_SCRIPTS/phase-readiness.sh" --phase=1 --workspace=.
Phase 1 exit gate:
  ✓ intake/question_of_record.md exists
  ✓ Falsifier section non-empty
  ✓ corpus/corpus_index.md exists
  ✓ Q-001 bead present
Phase 1: READY TO EXIT

$ touch .brenner_workspace/phase_1_complete.flag
$ git add intake/question_of_record.md intake/decision-rule.md corpus/ingested corpus/corpus_index.md .beads .brenner_workspace/phase_1_complete.flag
$ git status
$ git commit -m "Phase 1 complete: framing"
```

**Phase 1 wall time: 22 minutes** (per WALL-TIME-BUDGET T3 split: 8% of 5h ≈ 24min).

---

## Phase 2: Bootstrap in 8 minutes

```bash
$ ntm spawn "$SESSION_ID" --cc=3 --cod=1 --gmi=1
$ ntm pipeline run .ntm/pipelines/brennerbot-squad.yaml \
    --session "$SESSION_ID" \
    --var workspace_path="$WORKSPACE" \
    --var session_id="$SESSION_ID" \
    --var question_of_record_path=intake/question_of_record.md \
    --var mode=corpus-distillation \
    --dry-run
# (ntm preflights the pipeline against the already-spawned session)

$ ntm pipeline run .ntm/pipelines/brennerbot-squad.yaml \
    --session "$SESSION_ID" \
    --var workspace_path="$WORKSPACE" \
    --var session_id="$SESSION_ID" \
    --var question_of_record_path=intake/question_of_record.md \
    --var mode=corpus-distillation

$ "$SKILL_SCRIPTS/wait-for-onboard-acks.sh" --session="$SESSION_ID" --timeout=300
[INFO] Waiting for 5 onboarding acks...
[INFO] Pane 1 (cc) acked at 15:14:22
[INFO] Pane 2 (cc) acked at 15:14:31
[INFO] Pane 3 (cod) acked at 15:14:38
[INFO] Pane 4 (gmi) acked at 15:14:45
[INFO] Pane 5 (cc/⊙) acked at 15:14:51
All onboarding acks received.

$ touch .brenner_workspace/phase_2_complete.flag
```

**Phase 2 wall time: 8 minutes** (T3 split: 3% of 5h ≈ 9min).

---

## Phase 3: Hypotheses in 35 minutes

The remaining dispatch snippets use the literal helper syntax from `MARCHING-ORDERS.md`: `dispatch-marching-order.sh <MO-name> --target-pane=<N> --target-session=<session> --<PLACEHOLDER>=<value>`. The normal path is still the pipeline run above.

```bash
# 3a — proposers generate Hs
$ "$SKILL_SCRIPTS/dispatch-marching-order.sh" \
    MO-03a-propose \
    --target-pane=1 \
    --target-session="$SESSION_ID" \
    --PANE_N=1 \
    --SESSION_ID="$SESSION_ID" \
    --COUNT=4

# Wait ~10 min for proposer to file Hs via beads...
$ "$SKILL_SCRIPTS/tick.sh" "$WORKSPACE"
[Tick at 15:25]
  Active panes: 5/5
  Beads filed: H-001, H-002, H-003, H-004 (4 hypotheses)
  ...

# 3b — triage
$ "$SKILL_SCRIPTS/dispatch-marching-order.sh" \
    MO-03b-triage \
    --target-pane=1 \
    --target-session="$SESSION_ID" \
    --PANE_N=1 \
    --SESSION_ID="$SESSION_ID"

# After triage: H-001, H-002, H-003 active; H-004 merged into H-001 (was duplicate)

# 3c — third-alternative check
$ "$SKILL_SCRIPTS/audit-bead-invariants.sh" --check=phase3_exit
✗ F-301: No H with origin:third_alternative
$ "$SKILL_SCRIPTS/dispatch-marching-order.sh" \
    MO-03c-third-alternative \
    --target-pane=5 \
    --target-session="$SESSION_ID" \
    --PANE_N=5 \
    --SESSION_ID="$SESSION_ID" \
    --H_A_ID=H-001 \
    --H_B_ID=H-002 \
    --H_A_CLAIM="PG16+tune meets the SLO" \
    --H_B_CLAIM="Citus is necessary at forecast scale"

# After third-alt: H-005 filed with origin:third_alternative
# (e.g., "What if we don't migrate but instead extract the read-heavy workload to a CDN-cached replica tier?")

$ "$SKILL_SCRIPTS/audit-bead-invariants.sh" --check=phase3_exit
✓ All Phase 3 invariants clean
$ touch .brenner_workspace/phase_3_complete.flag
```

**Phase 3 wall time: 35 minutes** (T3 split: 8% of 5h ≈ 24min, slightly over budget).

**Active H slate:**
- H-001 (Proposer): "PG16 + tuning satisfies the SLO at forecast scale"
- H-002 (Proposer): "Citus is necessary at forecast scale"
- H-003 (Proposer): "ScyllaDB's write-throughput claim transfers to our regime"
- H-005 (third-alternative, ⊙): "Read-heavy workload extraction to CDN-cached replica tier deferring DB migration"

---

## Phase 4: Investigation in 2.5 hours (3 rounds)

**Round 1 (50 min)** — assign Investigators per H:

```bash
$ "$SKILL_SCRIPTS/assign-investigator-domains.sh" --session="$SESSION_ID" --workspace="$WORKSPACE"
# Squad convention assigns investigators only: p2/p3 get the active H slate.
# The script also writes .brenner_workspace/h-pane-mapping.json.

$ for H in H-001 H-002 H-003 H-005; do
    PANE=$(jq -r ".\"$H\"" .brenner_workspace/h-pane-mapping.json)
    "$SKILL_SCRIPTS/dispatch-marching-order.sh" \
      MO-04a-investigate \
      --target-pane="$PANE" \
      --target-session="$SESSION_ID" \
      --PANE_N="$PANE" \
      --H_ID="$H" \
      --SESSION_ID="$SESSION_ID"
  done

# Wait ~30 min for round-1 evidence packs...
$ "$SKILL_SCRIPTS/tick.sh" "$WORKSPACE"
[Tick at 16:30]
  Beads: 12 EVs filed across 4 H this round
    H-001: 4 supporting EVs, 0 refuting (W_composite mostly 0.5-0.7)
    H-002: 3 supporting EVs, 1 refuting (Citus shard-key analysis EV-007 surfaces concern)
    H-003: 2 supporting EVs, 0 refuting (claim hasn't been replicated yet)
    H-005: 3 supporting EVs (one strong: EV-012 from prod metrics analysis)

$ "$SKILL_SCRIPTS/convergence-check.sh" --phase=4
Phase 4 round 1: kill_rate=0, add_rate=12 (12 EVs added; 0 H state changes)
Status: NOT CONVERGED. Recommended: run round 2 with Devil's-Advocate.
```

**Round 1 reflection:** add_rate=12 vs kill_rate=0 is an F-403 confirmation-bias risk. Apply OC-011 escalation.

**Round 2 (60 min)** — flip Devil's-Advocate aggressively + run quickie pilots:

```bash
# Mode-flip p3 explicitly to attack mode for top-confidence H
$ "$SKILL_SCRIPTS/dispatch-marching-order.sh" \
    MO-mode-flip-investigator-to-advocate \
    --target-pane=3 \
    --target-session="$SESSION_ID" \
    --PANE_N=3 \
    --H_ID=H-001

# Quickie pilot for ScyllaDB claim (cheaper than full replication)
$ "$SKILL_SCRIPTS/dispatch-marching-order.sh" \
    MO-quickie-pilot \
    --target-pane=2 \
    --target-session="$SESSION_ID" \
    --PANE_N=2 \
    --H_ID=H-003 \
    --SESSION_ID="$SESSION_ID"

# Cross-family debate for H-001 (PG16 tune)
$ "$SKILL_SCRIPTS/dispatch-marching-order.sh" \
    MO-cross-family-debate \
    --target-pane=4 \
    --target-session="$SESSION_ID" \
    --H_ID=H-001 \
    --CHAMPION_FAMILY=cc \
    --CHALLENGER_FAMILY=gmi \
    --SESSION_ID="$SESSION_ID"

# After 60 min:
$ "$SKILL_SCRIPTS/tick.sh"
  Beads round 2:
    H-001: 4 → 5 supporting; 0 → 2 refuting (DA found Q4 forecast load chart contradicting EV-002)
    H-002: 3 → 3 supporting; 1 → 2 refuting (cross-shard join rate exceeded 15% threshold per EV-018)
    H-003: 2 → 2 supporting; 0 → 1 refuting (quickie pilot showed write-mix degraded throughput per EV-019)
    H-005: 3 → 4 supporting; 0 → 0 refuting

$ "$SKILL_SCRIPTS/convergence-check.sh" --phase=4
Phase 4 round 2: kill_rate=2 (H-002 weakening, H-003 weakening), add_rate=4
Status: TRENDING TOWARD CONVERGENCE. Run round 3.
```

**Round 3 (40 min)** — finishing investigation, applying ⊞ Scale-Check rigorously:

```bash
$ for H in H-001 H-002 H-003 H-005; do
    PANE=$(jq -r ".\"$H\"" .brenner_workspace/h-pane-mapping.json)
    "$SKILL_SCRIPTS/dispatch-marching-order.sh" \
      MO-04a-investigate \
      --target-pane="$PANE" \
      --target-session="$SESSION_ID" \
      --PANE_N="$PANE" \
      --H_ID="$H" \
      --SESSION_ID="$SESSION_ID"
  done

# After 40 min:
  H-001: 5 supporting, 2 refuting → state stays active, confidence:medium
  H-002: 3 supporting, 4 refuting → state flips to refuted (cross-shard rate kills it)
  H-003: 2 supporting, 3 refuting → state flips to refuted (write-mix saturation)
  H-005: 5 supporting, 0 refuting → state stays active, confidence:high (strong Phase 5 candidate)

$ "$SKILL_SCRIPTS/convergence-check.sh" --phase=4
Phase 4 round 3: kill_rate=2, add_rate=2 → kill ≥ add. CONVERGED.
$ touch .brenner_workspace/phase_4_complete.flag
```

**Phase 4 wall time: 2.5 hours** (T3 split: 50% of 5h ≈ 2.5h).

---

## Phase 5: Adversarial debate in 45 minutes

```bash
$ "$SKILL_SCRIPTS/generate-debate-pairs.sh"
[3 debates queued]
  DEBATE-001: H-001 (PG16 tune) vs H-005 (CDN extraction)
  DEBATE-002: H-005 (CDN extraction) vs H-002 (Citus, refuted)
  DEBATE-003: H-005 (CDN extraction) vs H-003 (ScyllaDB, refuted)

$ "$SKILL_SCRIPTS/check-rotation-rules.sh"  # verify cross-family champions per OC-014

# DEBATE-001 initially had p1(cc) vs p5(cc), so do not dispatch yet.
# F-504 fires: both champions are same-family. Rebalance H-005 to p4(gmi).
$ "$SKILL_SCRIPTS/dispatch-marching-order.sh" \
    MO-domain-handoff \
    --target-pane=4 \
    --target-session="$SESSION_ID" \
    --FROM_PANE_N=5 \
    --TO_PANE_N=4 \
    --DOMAIN=H-005 \
    --REASON=rebalance
# Now p4 (gmi) champions H-005 vs p1 (cc) champion of H-001 — cross-family ✓

# Round 1 openings, one dispatch per champion pane.
$ "$SKILL_SCRIPTS/dispatch-marching-order.sh" \
    MO-05a-cross-exam \
    --target-pane=1 \
    --target-session="$SESSION_ID" \
    --PANE_N=1 \
    --H_I=H-001 \
    --H_J=H-005 \
    --SESSION_ID="$SESSION_ID" \
    --ROUND=1
$ "$SKILL_SCRIPTS/dispatch-marching-order.sh" \
    MO-05a-cross-exam \
    --target-pane=4 \
    --target-session="$SESSION_ID" \
    --PANE_N=4 \
    --H_I=H-005 \
    --H_J=H-001 \
    --SESSION_ID="$SESSION_ID" \
    --ROUND=1

# After 30 min of structured debate (4 rounds: opening, rebuttal, counter, close):
# Adjudicator p3 (cod) verdict per MO-05b-adjudicate.md:
#   "H-005 wins on falsifier-strength grounds; H-001 deferred with explicit
#    caveats per A-007 (depends on PG16 query-plan-cache improvements)"

# Refuted Hs (H-002, H-003) get formal closure dispatch
$ "$SKILL_SCRIPTS/dispatch-marching-order.sh" \
    MO-falsifier-fired \
    --target-pane=2 \
    --target-session="$SESSION_ID" \
    --H_ID=H-002 \
    --EV_OR_T_ID=EV-018 \
    --PANE_N=2 \
    --SESSION_ID="$SESSION_ID"
$ "$SKILL_SCRIPTS/dispatch-marching-order.sh" \
    MO-falsifier-fired \
    --target-pane=3 \
    --target-session="$SESSION_ID" \
    --H_ID=H-003 \
    --EV_OR_T_ID=EV-019 \
    --PANE_N=3 \
    --SESSION_ID="$SESSION_ID"

$ "$SKILL_SCRIPTS/audit-bead-invariants.sh" --check=phase5_exit
  ✓ Every active H state finalized
  ✓ Every refuted H has refuted_by reference
  ✓ Every DEBATE bead has falsifier_fired or maintained-with-evidence
  ✓ Adjudicator rotation: p3(cod) audited debate where champions were p1(cc)+p4(gmi). Cross-family ✓.
$ touch .brenner_workspace/phase_5_complete.flag
```

**Phase 5 wall time: 45 minutes** (T3 split: 17% of 5h ≈ 51min).

---

## Phase 6: Distillation in 65 minutes

```bash
# 6a — per-family distillation (parallel)
$ for FAM in cc cod gmi; do
    PANE=$("$SKILL_SCRIPTS/list-distinct-model-families.sh" --pick="$FAM")
    "$SKILL_SCRIPTS/dispatch-marching-order.sh" \
      MO-06a-distill \
      --target-pane="$PANE" \
      --target-session="$SESSION_ID" \
      --PANE_N="$PANE" \
      --FAMILY="$FAM" \
      --SESSION_ID="$SESSION_ID"
  done

# Wait 35 min for parallel distillations
$ ls distillations/
  by_cc.md      (12 KB)
  by_cod.md     (10 KB)
  by_gmi.md     (14 KB)

# 6b — meta-synthesis
$ "$SKILL_SCRIPTS/dispatch-marching-order.sh" \
    MO-06b-meta-synthesize \
    --target-pane=4 \
    --target-session="$SESSION_ID" \
    --PANE_N=4 \
    --META_FAM=gmi \
    --DOMINANT_PER_FAM=cc \
    --SESSION_ID="$SESSION_ID"
# (gmi as meta-synthesizer because cc is dominant per-family, per OC-017 cross-family rule)

# Wait 25 min...
$ ls distillations/
  by_cc.md  by_cod.md  by_gmi.md  meta_synthesis.md  disagreement_register.md

$ "$SKILL_SCRIPTS/disagreement-register-lint.sh" --workspace=.
✓ disagreement_register.md has 4 substantive entries:
  - D-001 (cc vs gmi): on weight of operational complexity
  - D-002 (cc vs cod): on PG16 query-plan-cache reliability
  - D-003 (cod vs gmi): on time horizon for re-evaluation
  - D-004 (cc vs gmi): on whether H-005's CDN-tier counts as "migration"

$ "$SKILL_SCRIPTS/audit-bead-invariants.sh" --check=phase6_exit
  ✓ Per-family distillations exist (cc, cod, gmi)
  ✓ meta_synthesis.md exists
  ✓ disagreement_register has ≥(3 choose 2)=3 entries (we have 4)
$ touch .brenner_workspace/phase_6_complete.flag
```

**Phase 6 wall time: 65 minutes** (T3 split: 12% of 5h ≈ 36min — over budget but justified by 4 substantive D-entries).

---

## Phase 7: Audit in 50 minutes

```bash
# Trio-round 1: cross-family audit panes
$ "$SKILL_SCRIPTS/dispatch-marching-order.sh" \
    MO-07a-fresh-eyes \
    --target-pane=2 \
    --target-session="$SESSION_ID" \
    --PANE_N=2 \
    --ARTIFACTS="meta_synthesis.md;disagreement_register.md;deliverables/draft-DECISION-MEMO.md" \
    --SESSION_ID="$SESSION_ID"
$ "$SKILL_SCRIPTS/dispatch-marching-order.sh" \
    MO-07a-fresh-eyes \
    --target-pane=3 \
    --target-session="$SESSION_ID" \
    --PANE_N=3 \
    --ARTIFACTS="meta_synthesis.md;disagreement_register.md;deliverables/draft-DECISION-MEMO.md" \
    --SESSION_ID="$SESSION_ID"
$ "$SKILL_SCRIPTS/dispatch-marching-order.sh" \
    MO-07a-fresh-eyes \
    --target-pane=4 \
    --target-session="$SESSION_ID" \
    --PANE_N=4 \
    --ARTIFACTS="meta_synthesis.md;disagreement_register.md;deliverables/draft-DECISION-MEMO.md" \
    --SESSION_ID="$SESSION_ID"

# After 25 min:
$ ls audit-findings/
  AF-001.md (severity:medium): "EV-014 cited Patel 2024; verbatim quote misattributed (was actually Smith 2024)"
  AF-002.md (severity:high): "Scale-physics calculation in A-007 didn't account for connection-pool contention; recompute"
  AF-003.md (severity:low): "HANDBACK draft has 'might consider' hedge language; per HANDBACK-VOICE-GUIDE.md, replace"

# Address findings
# AF-001: p1 corrects citation in EV-014
# AF-002: p1 + p4 recompute scale-physics; A-007 confirmed but with caveat
# AF-003: HANDBACK draft updated to imperative voice

# Trio-round 2 (15 min), then address AF-004 if it appears.
$ "$SKILL_SCRIPTS/dispatch-marching-order.sh" MO-07a-fresh-eyes --target-pane=2 --target-session="$SESSION_ID" --PANE_N=2 --SESSION_ID="$SESSION_ID"
$ "$SKILL_SCRIPTS/dispatch-marching-order.sh" MO-07a-fresh-eyes --target-pane=3 --target-session="$SESSION_ID" --PANE_N=3 --SESSION_ID="$SESSION_ID"
$ "$SKILL_SCRIPTS/dispatch-marching-order.sh" MO-07a-fresh-eyes --target-pane=4 --target-session="$SESSION_ID" --PANE_N=4 --SESSION_ID="$SESSION_ID"

$ "$SKILL_SCRIPTS/convergence-check.sh" --phase=7 --workspace=.
Phase 7: 2 consecutive trio-rounds with 0 critical/high. CONVERGED.

$ "$SKILL_SCRIPTS/check-six-layer-validation.sh" --workspace=.
=== Six-Layer Validation Check ===
Layer 1 (bead invariants): PASS
Layer 2 (convergence):     PASS
Layer 3 (marching-order):  PASS
Layer 4 (rotation rules):  PASS
Layer 5 (cross-session):   PASS
Layer 6 (external review): N/A (T3)
Verdict: READY FOR PHASE 8

$ touch .brenner_workspace/phase_7_complete.flag
```

**Phase 7 wall time: 50 minutes** (T3 split: 10% of 5h ≈ 30min — over budget by 20min for legitimate findings).

---

## Phase 8: Freeze in 12 minutes

```bash
$ "$SKILL_SCRIPTS/dispatch-marching-order.sh" \
    MO-08-freeze \
    --target-pane=4 \
    --target-session="$SESSION_ID" \
    --PANE_N=4 \
    --SESSION_ID="$SESSION_ID"

# Operator drafts RESUME.md per template
$ vim deliverables/RESUME.md

$ "$SKILL_SCRIPTS/resume-session.sh" --dry-run --resume deliverables/RESUME.md
[INFO] verifying RESUME.md hashes...
question_of_record_hash: matches ✓
disagreement_register_hash: matches ✓
verification: OK

$ ntm checkpoint save "$SESSION_ID" -m "Phase 8 freeze"
$ NTM_CHECKPOINT_ID=$(ntm checkpoint list "$SESSION_ID" --json | jq -r '.checkpoints[-1].id')
$ mkdir -p .ntm/checkpoints
$ ntm checkpoint export "$SESSION_ID" "$NTM_CHECKPOINT_ID" --output=".ntm/checkpoints/${NTM_CHECKPOINT_ID}.tar.gz"

$ git add deliverables/RESUME.md .ntm/checkpoints .brenner_workspace .beads
$ git commit -m "Phase 8 freeze: storage-eval session checkpoint"
$ touch .brenner_workspace/phase_8_complete.flag
```

**Phase 8 wall time: 12 minutes** (T3 split: 3% of 5h ≈ 9min).

---

## Phase 9: Handback in 18 minutes

```bash
$ "$SKILL_SCRIPTS/dispatch-marching-order.sh" \
    MO-09-handback \
    --target-pane=4 \
    --target-session="$SESSION_ID" \
    --PANE_N=4 \
    --OUTPUT_PATH=deliverables/HANDBACK.md \
    --SESSION_ID="$SESSION_ID"

# After 8 min draft, operator reviews against HANDBACK-VOICE-GUIDE.md:
$ wc -l deliverables/HANDBACK.md
71 deliverables/HANDBACK.md  # ✓ ≤80 lines

$ "$SKILL_SCRIPTS/audit-bead-invariants.sh" --check=handback_unresolved_thread_tags
  ✓ Every unresolved H/EV listed in "What's still open" has next-action tag

# Render the longer DECISION-MEMO too (per A7 archetype)
$ "$SKILL_SCRIPTS/render-decision-memo.sh" --workspace=.
Decision memo emitted: deliverables/DECISION-MEMO.md

# Brief the user with HANDBACK + DECISION-MEMO via OPERATOR-PROMPT-LIBRARY P5.1
# (User reads, asks 2 clarifying questions, accepts.)

$ touch .brenner_workspace/phase_9_complete.flag
```

**HANDBACK contents** (truncated; see actual file for full):

```markdown
# HANDBACK — RS-2026-05-12-storage-eval

**Verdict:** Defer DB migration. Implement read-heavy workload extraction to
CDN-cached replica tier (H-005). Re-evaluate at 2027-Q1 or if forecast scale
revises upward by ≥3×.
**Confidence:** medium-high
**Action recommended:** Architecture spike for CDN-replica-tier extraction by
2026-06-15. ADR scheduled for engineering review on 2026-05-22.

## Reasoning
Phase 4 round 3 demonstrated that PG16 + tuning (H-001) meets the SLO at
forecast scale only with non-trivial caveats (A-007 connection-pool contention).
Citus (H-002) was refuted by EV-018: cross-shard join rate exceeds 15% in our
specific query mix. ScyllaDB (H-003) was refuted by EV-019: claimed write
throughput degrades sub-linearly under our 95/4/1 read/range/write mix.
H-005 (CDN extraction) is supported by 5 EVs including EV-012's prod-metrics
analysis showing 78% of read traffic is cacheable.
[...]
```

**Phase 9 wall time: 18 minutes** (T3 split: 5% of 5h ≈ 15min — slightly over).

---

## Phase 10: Drift check in 25 minutes

```bash
# Dispatch fresh general-purpose agent (not a swarm pane) per OC-026.
$ codex exec "<contents of subagents/drift-auditor.md, with workspace=.>"

# After ~15 min:
$ cat deliverables/DRIFT-CHECK.md
DRIFT VERDICT: convergent

## Methodology compliance
- ✂ Exclusion-Test applied at every Phase 4 round ✓
- ⊕ Cross-domain imports: applied (queue-theory + erasure-coding patterns)
- 🤝 GAN: cross-family champions in DEBATE-001 ✓
- ∿ Dephase: applied at Phase 7 (no consensus capture detected)
- ⊙ Productive-ignorance: p5 produced H-005 from first-principles ✓

## Lessons
### L-001: Recipe match earlier saves 30 min
Round 3 of Phase 4 was where ⊞ Scale-Check became load-bearing. Recipe R10
(per DOMAIN-RECIPE-LIBRARY.md) front-loads ⊞ Scale-Check at Phase 1.
Recommendation: dispatch MO-stress-test-self-check.md for T3+ sessions to
catch this earlier.

### L-002: ⊙ pane productivity
Pane p5 (productive-ignorance) produced the winning H-005. Per OC-005,
the file-access restriction was honored throughout. This is exemplary; commit
to OPERATOR-CALIBRATION-LOG.md as a positive pattern.

# Lesson L-001 commit:
$ vim references/STRESS-TEST-SCENARIOS.md  # Add R10-specific note
$ git add references/STRESS-TEST-SCENARIOS.md
$ git commit -m "Round-N lesson: recipe match earlier saves time"

$ touch .brenner_workspace/phase_10_complete.flag
$ git add deliverables/DRIFT-CHECK.md references/STRESS-TEST-SCENARIOS.md .brenner_workspace/phase_10_complete.flag
$ git commit -m "Phase 10 drift check + lesson commitment"
```

**Phase 10 wall time: 25 minutes** (T3 split: ~7% of 5h ≈ 21min).

---

## Total: 6h 10min

(T3 budget = 5h active. Hard cap = 8h. We were 23% over budget but stayed under hard cap. Per WALL-TIME-BUDGET.md soft-breach protocol: document in scope_decision but acceptable.)

Per-phase breakdown:

| Phase | Budget | Actual | Delta |
|-------|--------|--------|-------|
| 1 framing | 24 min | 22 min | -2 |
| 2 bootstrap | 9 min | 8 min | -1 |
| 3 hypotheses | 24 min | 35 min | +11 |
| 4 investigation (3 rounds) | 150 min | 150 min | 0 |
| 5 debate | 51 min | 45 min | -6 |
| 6 distillation | 36 min | 65 min | +29 |
| 7 audit | 30 min | 50 min | +20 |
| 8 freeze | 9 min | 12 min | +3 |
| 9 handback | 15 min | 18 min | +3 |
| 10 drift | 21 min | 25 min | +4 |
| **Total** | **5h 9min** | **6h 10min** | **+61** |

Phase 6 was the biggest over-budget (4 disagreement entries vs 3 minimum required, justifiable). Phase 7 over-budget because of legitimate audit findings (AF-002 was high severity, recompute necessary).

---

## What this walkthrough exemplifies

1. **The methodology is enforced at runtime, not just documented.** Every gate has a script. Operators don't say "I think we're done with Phase 4"; they run `convergence-check.sh --phase=4`.

2. **Phases compose; they don't run in isolation.** Phase 4's confirmation-bias signal (round 1's add_rate=12, kill_rate=0) triggers OC-011 escalation before Phase 5. The escalation produces stronger evidence for Phase 5 to adjudicate.

3. **Cross-family discipline isn't optional.** When DEBATE-001 was set up with both champions on cc (F-504 violation), the operator stopped and ran MO-domain-handoff.md before proceeding.

4. **The third-alternative often wins.** H-005 came from the productive-ignorance pane (⊙) in Phase 3 and ended up the recommended action. Per Brenner §103.

5. **Audit findings are legitimately critical.** AF-002 (medium severity) reopened a scale-physics calculation. Phase 7 isn't a rubber-stamp.

6. **HANDBACK gives the verdict in <5 lines.** The user reads "Defer DB migration. Implement read-heavy CDN extraction." and can act. The longer DECISION-MEMO is for engineering review.

7. **Phase 10 is where lessons commit.** L-001 ("Recipe match earlier") got added to references/. The next R10 session benefits.

8. **Wall-time budgets are guides, not hard rules.** Going 20% over for legitimate findings is fine. Going 50%+ over without documented reason is OC-030 soft-breach territory.

---

## What a fresh operator should learn

After reading this walkthrough, you should be able to answer:

1. **What does the operator type in the first minute?** `bootstrap-session.sh`. Then `vim intake/question_of_record.md` after the FRAMING-WORKBOOK F1-F9 walk.

2. **When in Phase 4 do you stop?** When `convergence-check.sh --phase=4` reports kill_rate ≥ add_rate AND every active H has at least one supporting EV that survived attack.

3. **Why are there 3 distillations + a meta?** Triangulation. cc/cod/gmi each produce their own (per Phase 6a). Meta-synthesis (Phase 6b) reconciles, surfacing where they disagree (`disagreement_register.md`). Anti-F-601 silent averaging.

4. **What's the operator not doing?** Investigating questions, reading sources, writing evidence packs. The panes do that. The operator coordinates: who reads what, who debates whom, when to stop a phase, when to flip a pane to advocate.

5. **What's "ready to push" mean?** Phase 8 freeze done + RESUME.md hash-verifies + ntm checkpoint exported. Phase 9 produces HANDBACK. Phase 10 produces DRIFT-CHECK + commits lessons to references/.

---

## Anti-patterns avoided

This exemplar avoided:

| ✗ | What would have happened |
|---|--------------------------|
| Skipping Phase 1 third-alternative | H-005 would never have surfaced; we'd have picked among 3 sub-optimal options |
| Same-family DEBATE-001 (F-504) | Cross-family blind spot; might have confirmed H-001 incorrectly |
| Same-pane Phase 7 audit (F-705) | AF-002 (scale-physics recompute) likely missed |
| Skipping Phase 10 drift | L-001 lesson never committed; next R10 session repeats the over-budget Phase 3 |
| Hedge-language HANDBACK | User reads "we *might* consider..." and defers decision; AF-003 caught this |

Per ANTI-PATTERNS.md and FAILURE-TABLE.md.

---

## Cross-references

- `PHASES.md` — abstract phase definitions this walkthrough instantiates
- `DOMAIN-RECIPE-LIBRARY.md` — R10 (storage selection) + R14 (migration risk)
- `WALL-TIME-BUDGET.md` — per-tier per-phase budgets
- `SIX-LAYER-VALIDATION.md` — Layer 1-5 checks performed at Phase 8
- `HANDBACK-VOICE-GUIDE.md` — verdict-first writing for HANDBACK
- `OPERATOR-PROMPT-LIBRARY.md` — P5.1 handback prompt
- `CRITIQUE-CRAFT.md` — severity calibration (used in AF-001..AF-003)
- `BRENNER-GAN-MECHANICS.md` — generator/discriminator/adjudicator mechanics applied in DEBATE-001
- `CASE-STUDIES.md` — additional shorter case studies
