---
name: brennerbot-with-ntm
description: >-
  Run Brenner-style hypothesis research on native NTM swarms. Use when investigating design
  spaces, adversarial audits, incident RCA, methodology distillation, or session resume/drift checks.
---

<!-- TOC: One Rule | Cold Start | Mandatory Loop | Hypothesis Opportunity Matrix | Phase Proof Card | Pathology Triggers | Pattern Tiers | Metrics Dashboard | Anti-Patterns | Operator Quickstart | Decision Tree | Red-Flag Phrases | Liveness Truth Stack | When to Use | Inputs | Up-Front Confirmations | Skill Bootstrap | Mode Router | Workspace Layout | 10-Phase Loop | Phase Quick Reference | Parallelism | Brenner Kernel | Operator Algebra | Roster | Beads Schema | Mail Conventions | Marching Orders | Failure Table | Convergence | Checklist | References | Scripts | Subagents | Assets | Self-Test -->

# BrennerBot With NTM

> **The One Rule.** A Brenner-style session is a *machine for deleting hypothesis space cheaply*, not a machine for accumulating evidence. Every operator move, every marching-order template, every bead schema field, and every Agent Mail thread convention in this skill exists to maximize **(expected mind-change × downstream option value) / (time × cost × ambiguity × infrastructure-dependence)** per round. When two phases compete, the one that kills more candidate hypotheses per token wins.

## Cold Start: Read This First

If you are a fresh agent with no BrennerBot context:

1. Read this top section through [Operator Quickstart](#operator-quickstart) before opening references.
2. Confirm Phase 0 inputs before creating a workspace or spawning panes.
3. Use native NTM pipeline/robot surfaces for Phases 2-8 whenever possible; if syntax is unclear, jump to `/ntm`.
4. Use `/vibing-with-ntm` for pane tending, unstick ladders, convergence, and queue-dry decisions.
5. Do not free-write research prompts. Dispatch the matching marching-order template and require an artifact path in the response.
6. Current runnable surfaces are `scripts/*.sh`, `assets/ntm-pipelines/*.yaml`, `br`, `ntm`, and Agent Mail MCP/CLI tools. Deep references may quote upstream prototype `brenner ...` commands as design sketches; do not treat those as runnable unless a local `brenner` binary is explicitly in scope.

The references are the library; this file is the operator route through it.

## The Loop (Mandatory)

```
0. PREFLIGHT   -> confirm target/workspace/tier/roster; check NTM capabilities + tools + CASS status
1. FRAME       -> write Q-001 + falsifier; no falsifier means no session
2. BOOTSTRAP   -> create workspace; spawn/attach panes; dry-run native NTM pipeline
3. PROPOSE     -> generate >=3 H beads, including a forced third alternative
4. TEST        -> assign discriminative EV/T/A work; prefer refuters over supporters
5. ATTACK      -> cross-exam surviving Hs; kill or downgrade on falsifier-fired evidence
6. DISTILL     -> per-family distillations; disagreement register before synthesis
7. AUDIT       -> fresh-eyes rounds until critical/high findings are gone
8. FREEZE      -> RESUME, causality, support bundle, checksums, pipeline state
9. HANDOFF     -> <=80-line HANDBACK with next actions for every live thread
10. DRIFT      -> compare actual loop to canonical method; feed one lesson back
```

Every phase emits an artifact. No artifact -> phase not done. Phase 0's artifact is the explicit scope/intake decision or resume decision in the workspace log; later phases use the named files, beads, pipeline state, reports, and handback artifacts below. Pane chatter is not a research product.

## Hypothesis Opportunity Matrix

Score each candidate hypothesis, evidence task, or debate target before spending swarm time:

```
Score = (MindChange x Falsifiability x OptionValue) / (Cost x Ambiguity x InfraRisk)

MindChange     1-5: would change the conclusion if true/false
Falsifiability 1-5: crisp test, refuter, or discriminative evidence exists now
OptionValue    1-5: unlocks future decisions or removes a whole branch
Cost           1-5: wall time, model quota, operator attention
Ambiguity      1-5: vague terms, moving target, weak source anchors
InfraRisk      1-5: depends on flaky tools, degraded mail, long builds, unavailable corpus
```

Only advance Score >= 2.0. Below that, either sharpen the H/T/EV until it scores, or kill/defer it explicitly. This score is a within-session triage heuristic, not a probability or cross-project quality metric; the denominator is intentionally harsh so vague, expensive, or infrastructure-dependent work loses to crisp refuters.

| Candidate | Mind | Falsify | Option | Cost | Ambig | Infra | Score | Decision |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| H with one decisive log query | 5 | 5 | 4 | 1 | 1 | 1 | 100.0 | run first |
| Plausible story with no refuter | 3 | 1 | 3 | 2 | 4 | 1 | 1.1 | sharpen or kill |
| Literature sweep requiring broad web search | 4 | 2 | 4 | 4 | 3 | 3 | 0.9 | defer unless T4+ |
| Third alternative with cheap benchmark | 4 | 4 | 5 | 2 | 2 | 1 | 20.0 | inject |

## Phase Proof Card

Before marking any phase complete, fill this card in the workspace log or operator notes:

```markdown
## Phase <N> proof
- Artifact(s): <paths created/updated>
- Beads: Q=<...> H=<...> EV=<...> T=<...> C=<...> D=<...> AF=<...>
- Falsifier status: <not applicable / fired / attempted / missing>
- NTM evidence: pipeline run id=<...>; attention cursor=<...>; causality captured=<yes/no>
- Cross-model disagreement: <none / register path / unresolved items>
- Quality gate: <script/test/lint/checksum command and result>
- Decision: <advance / repeat / kill H / downgrade / pause>
- Residual risk: <one sentence, or "none known">
```

If the card has a blank line, do not write `phase_<N>_complete.flag`.

## Brenner Pathology Triggers

| Pathology | Smell | Detector | First correction |
|---|---|---|---|
| Evidence hoarding | EV count grows, H states unchanged | `br list`, convergence check | force refuter assignment |
| Soft falsifier drift | falsifier relaxes after evidence appears | bead diff / artifact diff | reject edit; restore crisp falsifier |
| Binary trap | only two Hs survive Phase 3 | `audit-bead-invariants.sh` | mandatory MO-03c third alternative |
| Consensus fog | all families agree too early | disagreement register empty | dephase: assign adversarial roles |
| Citation theater | sources cited but no anchors/excerpts | citation lint / evidence pack | demand excerpt + anchor or mark the EV invalid |
| Debate theater | champions restate positions, no state changes | debate beads unchanged | adjudicator must kill/downgrade/escalate |
| Operator-as-investigator | coordinator starts doing research | tick log / no pane assignment | dispatch MO; operator returns to control loop |
| Pipeline amnesia | manual dispatch bypasses NTM state | no pipeline run id / causality | use native pipeline or record degraded path |
| Mail degradation hidden | Agent Mail fallback used silently | missing phase0 note | record coordination mode and risk |
| Handoff bloat | final answer becomes essay | HANDBACK >80 lines | compress to decisions, next actions, risks |

## Pattern Tiers

### Tier 1: Cheap Hypothesis Deletion

| Operator move | Use when | Proof |
|---|---|---|
| Sharp falsifier | H is vague | falsifier would kill H if observed |
| Refuter-first EV | all evidence supports | at least one disconfirming search/test |
| Third alternative | binary frame dominates | H with `origin:third_alternative` |
| Quickie pilot | H blocked on speculation | small experiment or proxy result |
| Anomaly quarantine | fact does not fit any H | AN bead linked to possible H spawn |

### Tier 2: Discriminative Structure

| Operator move | Use when | Proof |
|---|---|---|
| Debate pair | two Hs make competing predictions | adjudicator state change |
| Prediction lock | confidence likely to drift after result | pre-result prediction recorded |
| Evidence pack | source claims matter | EV supports/refutes with anchor |
| Cross-family distill | model bias matters | by_cc/by_cod/by_gmi plus disagreement register |
| Causality replay | run outcome disputed | `--robot-causality` timeline exported |

### Tier 3: Research-Program Moves

| Operator move | Use when | Guard |
|---|---|---|
| Swarm tier | T4/T5 or many independent Hs | quota/tool health checked |
| Native NTM pipeline | repeatable Phase 2-8 work | dry-run and cancel/resume path known |
| Ensemble mode | reasoning-mode diversity matters | explicit assignment and evaluation rubric |
| Session fork/replay | protocol/model comparison | original record/checksums preserved |
| Methodology evolution | drift lesson recurs | reference or MO update, not vague note |

## Metrics Dashboard (Report At Closeout)

| Metric | Target |
|---|---|
| Hypotheses killed/downgraded | nonzero for any serious investigation |
| Refute attempts per active H | >=1 before validation |
| Third alternatives injected | >=1 unless a recorded exception explains why |
| Evidence packs with anchors | 100% for cited external evidence |
| Debate pairs resolved | every active H pair that affects verdict |
| Distillation disagreement entries | >= N choose 2 for N model families |
| Fresh-eyes critical/high findings | 0 open at freeze |
| NTM replayability | pipeline state + causality/support bundle available |
| Handoff size | <=80 lines unless user asked for full report |
| Drift lessons fed back | >=1 concrete update or explicit "none" with proof |

## Anti-Patterns (The Short List)

| Bad move | Why it breaks the method | Correct move |
|---|---|---|
| Ask panes to "research X" without H/T/EV grammar | produces essays | dispatch a marching order with bead targets |
| Let support evidence accumulate before refuters | confirmation bias | refuter-first EV assignment |
| Treat Phase 6 synthesis as consensus | hides model-family disagreement | require disagreement register first |
| Use manual dispatch when native pipeline is healthy | loses resume/replay state | `ntm pipeline run` or `--robot-pipeline-run` |
| Skip Phase 10 because answer is "done" | method never improves | drift-check and feed one lesson back |
| Collapse high-stakes T4/T5 into autonomous mode | insufficient oversight | HITL gates + stress pass |
| Ignore degraded coordination | file/reservation conflicts become invisible | record fallback and reduce mutation scope |

---

## Operator Quickstart (read this first if you came in fresh)

**You are the operator.** This skill puts *you* — a single Claude Code instance — in charge of a multi-pane research swarm. The swarm panes are *separate* CLI agents (Claude Code / Codex / Gemini instances) running in tmux; you don't investigate the question yourself, you coordinate them. Everything below the One Rule is your operator manual.

**Pick the branch matching your starting state:**

- **🆕 Fresh trigger, no workspace yet** → walk the user through [Up-Front Confirmations](#up-front-confirmations-ask-before-starting) (8 questions), run [Skill Bootstrap](#skill-bootstrap-phase-05--right-after-inputs-before-phase-1), then enter the Decision Tree at Phase 1.
- **▶️ User pointed at an existing workspace with `RESUME.md`** → run `./scripts/resume-session.sh --dry-run --resume <path>` to verify hashes, then enter the Decision Tree at the recorded `last_phase_completed + 1`.
- **🔁 Mid-session continuation** → scan the [Decision Tree](#operator-decision-tree-run-this-every-tick); the first matching branch is your next phase.
- **🩺 User asked for a methodology drift check only** → mode `methodology-drift-check`; jump straight to Phase 10. The rest of the loop is read-only.
- **🚨 Production incident, time-pressed** → mode `incident-investigation`; run the compressed pipeline ([`brennerbot-incident.yaml`](assets/ntm-pipelines/brennerbot-incident.yaml)). It compresses Phases 1, 3, 4-inline-with-5, and 7 into one incident loop, skips methodology distillation / full freeze / drift, and produces `INCIDENT-VERDICT.md` instead of `HANDBACK.md`. A follow-up `post-mortem-formalization` mode runs the full loop later.
- **😵 Stuck/confused/saw a weird symptom** → check [Red-Flag Phrases](#red-flag-phrases-pane-tail-pattern-match), then [Failure Table](#failure-table-the-symptoms-youll-actually-see); pane-state issues defer to `/vibing-with-ntm`.

**What this skill does NOT do (defer to adjacent skills):**

| Concern | Skill |
|---------|-------|
| Stuck panes, rate-limit recovery, OAuth, robot-mode tending cadence | `/vibing-with-ntm` |
| Spawning panes, sending text to panes, tmux orchestration | `/ntm` |
| Bug-hunting on code that ends up in `deliverables/scripts/` | `/multi-pass-bug-hunting` + `/ubs` |
| Mining prior agent sessions for related work | `/cass` + `/flywheel` |
| Codebase exploration for Phase 1 corpus | `/codebase-archaeology` |
| Generating ideas for Phase 3 hypothesis breadth | `/idea-wizard`, `/dueling-idea-wizards` |

This skill is the *methodology*. Those skills are *the operator loop, the swarm primitives, and the analysis tools*. Compose, don't reimplement.

**One-line glossary** (the terms below are used throughout):

- **Pane** = one CLI agent in the swarm (cc / cod / gmi). You orchestrate ≥1 of these.
- **Bead** (canonical prefixes: `Q-NNN` question of record, `H-NNN` hypothesis, `EV-NNN` evidence, `T-NNN` test, `A-NNN` assumption, `AN-NNN` anomaly, `C-NNN` critique, `DEBATE-NNN` debate, `D-NNN` distillation, `AF-NNN` audit-finding) = an entry in the beads ledger (`br`). Full schema with field grammar is in [BEADS-SCHEMA.md](references/BEADS-SCHEMA.md); extended/optional types (`P-NNN` prediction, `CF-NNN` counterfactual, `INT-NNN` intervention, `RP-NNN` research-program, `RC-NNN` reconciliation, `REC-...` session record) are in [TAXONOMIES-COMPLETE-CATALOG.md](references/TAXONOMIES-COMPLETE-CATALOG.md).
- **MO** (marching order) = a parameterized prompt template in `assets/marching-orders/`. You dispatch these to panes via `dispatch-marching-order.sh`. Never free-write prompts.
- **Operator (cognitive)** = one of the 15 Brenner moves (◊ ⊘ 𝓛 ≡ ✂ ⟂ ↑ ⌂ 🔧 ⊞ 🤝 ΔE † ∿ ⊙) in [OPERATORS.md](references/OPERATORS.md). Distinct from "operator (you)".
- **Tier** (stakes-driven, per [TIER-TRIAGE.md](references/TIER-TRIAGE.md)) — T1 Curiosity (≤60min budget) / T2 Decision-supporting (≤3h) / T3 Strategic (≤5h) / T4 High-stakes (≤8h) / T5 Existential (multi-session). Distinct from **roster size** (Solo / Pair / Squad / Swarm — per [ROSTER-PLANS.md](references/ROSTER-PLANS.md)) which is *how many panes* you spawn; tier and roster correlate but aren't 1-to-1 (e.g. you can run T2 with Squad if quota allows, or T3 with Pair if a family is unavailable).
- **Tick** = one pass of the Decision Tree. Cadence is per [OBSERVABILITY.md](references/OBSERVABILITY.md) (4-30 min depending on phase).

## Current NTM Reality (May 2026)

The old version of this skill treated NTM as a tmux transport plus a few helper scripts. That is now stale. Current NTM is the native execution substrate for Brenner-style sessions:

| Capability | Use it for |
|---|---|
| `ntm pipeline run` / `--robot-pipeline-run` | Execute Brenner phase pipelines, not just dry-run them. `command:`, `template:`, `foreach:`, `foreach_pane:`, `branch:`, `on_failure`, Agent Mail steps, output vars, and resume state are live runtime features. |
| `--robot-attention`, `--robot-digest`, `--robot-events`, `--robot-wait` | The operator tick loop: wait for action-required state, replay cursor-bounded events, and resume after context loss. |
| `--robot-causality` | Reconstruct cross-surface timelines from audit, Agent Mail, pipeline, and session state for handoff/debugging. |
| `--robot-ensemble-*` | Inspect modes/presets/suggestions when a question needs explicit mode diversity; spawning may return `NOT_IMPLEMENTED` unless NTM was built with `-tags ensemble_experimental`, so fall back to normal roster roles or pipelines when unavailable. |
| `ntm work queue-dry --ideate` | When `br`/`bv` are empty, distinguish true stand-down from stale state and generate duplicate-guarded follow-up beads only after review. |
| `--robot-tools`, `--robot-schema`, `--robot-capabilities`, `--robot-safety-simulate`, `--robot-support-bundle` | Preflight tool health, discover exact JSON contracts, simulate risky plans, and freeze diagnostic evidence. |
| `--robot-jfp-*`, `--robot-xf-*`, `--robot-giil-fetch` | Pull in prompt/corpus/image/archive evidence through NTM's registered adapters when a research question needs those sources. |

Treat `/dp/brenner_bot` as the methodology source corpus and historical inspiration. Treat `/dp/ntm` as the live control plane. If this skill and `ntm --robot-capabilities` disagree, the installed NTM binary wins.

---

## Operator Decision Tree (run this every tick)

Run one tick. Pick the FIRST branch whose condition fires. Mirrors `/vibing-with-ntm` orchestrator decision tree, adapted for the brennerbot phase loop. In robot-mode sessions, each tick starts with the NTM attention loop:

```bash
ntm --robot-snapshot | jq '{latest_cursor, replay_window, sessions, _agent_hints}'
ntm --robot-attention --attention-cursor=<cursor> --attention-session=<session> --profile=operator
```

If the cursor is expired or missing, re-run `--robot-snapshot`; do not invent a local cursor.

```
Have we framed a falsifiable question of record yet?
  → NO  → Phase 1. Run MO-01-frame-question.md. Refuse to advance until intake/question_of_record.md has non-empty Falsifier.

Has the swarm been onboarded yet (panes acked MO-02)?
  → NO  → Phase 2. Run dispatch-onboarding via dispatch-marching-order.sh; wait via wait-for-onboard-acks.sh.

Does the slate include ≥3 H beads with ≥1 origin:third_alternative?
  → NO  → Phase 3. Run MO-03a → MO-03b → MO-03c (third-alternative) until invariant satisfied.

Is convergence-check.sh --phase=4 reporting kill_rate < add_rate, OR is any active H lacking refute attempts?
  → YES → Phase 4 round. Dispatch MO-04a per H + MO-04b on top-confidence H + MO-quickie-pilot when blocked.
        Apply MO-mode-flip-investigator-to-advocate.md if a pane shows confirmation bias (F-403).

Have all active H states finalized (no `active` left)?
  → NO  → Phase 5. Generate-debate-pairs.sh; dispatch MO-05a per pair; MO-05b per debate.
        Apply MO-falsifier-fired.md the moment a falsifier event is observed.

Does distillations/disagreement_register.md exist with ≥(N choose 2) entries (N = number of distinct model families distilling — typically 3 for cc/cod/gmi → 3 entries minimum)?
  → NO  → Phase 6. Dispatch MO-06a per model family in parallel; then MO-06b meta-synthesize.
        Run disagreement-register-lint.sh; reject empty registers.

Have 2 consecutive Phase 7 trio-rounds produced only trivial findings AND ubs clean on deliverables/scripts?
  → NO  → Phase 7. Dispatch MO-07a fresh-eyes trio across all panes; address critical/high findings.

Is `git status` clean, RESUME.md hash-verifies via resume-session.sh --dry-run, and ntm checkpoint exported?
  → NO  → Phase 8. Dispatch MO-08-freeze.md.

Has HANDBACK.md ≤80 lines been written with every unresolved H/EV tagged with next-action?
  → NO  → Phase 9. Dispatch MO-09-handback.md.

Has Phase 10 drift-check produced DRIFT-CHECK.md with ≥1 lesson committed back to references/?
  → NO  → Phase 10. Dispatch subagents/drift-auditor.md to a FRESH general-purpose Agent (NOT a swarm pane).

All 10 phase_*_complete.flag files present? → STOP. Session done.
```

**Marking a phase complete.** When the readiness check passes for phase N, write the flag so downstream tools (tick.sh, drift-check.sh, audit-bead-invariants.sh, brennerbot-doctor.sh, the "session done" gate above) can see it:

```bash
# Combined check + mark (preferred — only writes the flag if readiness passes):
./scripts/phase-readiness.sh --phase=<N> --mark-complete --workspace=<workspace>
```

For phases 8/9/10 the canonical marching orders (`MO-08-freeze.md`, `MO-09-handback.md`, `MO-10-drift-check.md`) write their flags directly. For phases 1–7 the operator marks the flag at exit; the canonical pattern in [EXEMPLAR-SESSION-WALKTHROUGH.md](references/EXEMPLAR-SESSION-WALKTHROUGH.md) is `phase-readiness.sh --phase=N --mark-complete` (or, equivalently, a manual `touch .brenner_workspace/phase_<N>_complete.flag` after readiness clears).

Every MO-*.md template, every script, every operator card is documented in full at the linked references. **Don't run a phase from this tree alone — read the matching MO and the section's slot in [PHASES.md](references/PHASES.md).**

---

## Red-Flag Phrases (Pane Tail Pattern Match)

During a tick, skim each pane's last ~30 lines for these substrings. Match → apply the card. This is the fastest classifier when you don't have time to read every pane. Mirrors `/vibing-with-ntm` red-flag phrase table tuned for research-session output.

| Pane tail contains | State | Card to apply |
|---|---|---|
| "exemplary", "no fixes needed", "ready to ship", "LGTM", "looks good" with no `EV-*` cite | Convergence-language false-positive on research output | OC-016 convergence triple-check; if no falsifier fired in Phase 4, it's F-701 |
| "I'll investigate" / "I'll look into" / "thinking about it" with no bead filed in 30+ min | Pane stuck in prose | MO-unstick-stuck-investigator.md variant B |
| "the answer is clearly X" without falsifier cite | Confirmation bias | F-403 → MO-mode-flip-investigator-to-advocate.md |
| "both X and Y are valid" without level-split rationale | False-binary collapse via averaging | F-302 → MO-03c retroactively |
| "ready for validation" / "MISSION ACCOMPLISHED" | Handoff-failure language (per `/vibing-with-ntm` AP-43) | OC-036 + MO-unstick variant E |
| "hypothesis is broadly supported" without `EV-*` count | Vibes-only support | reject post; require `EV-*` citations |
| "perhaps", "it might be", "tends to" in distillation | Hedging in distillation (anti-Brenner per § 229) | re-dispatch MO-06a with explicit "state with confidence; cite EVs" directive |
| "no third alternative needed" / "the binary is genuine" | Refusing to inject third alternative | F-301 → MO-03c is mandatory; per Brenner §103 |
| "the falsifier is too narrow" / "let's relax the falsifier" | Soft-falsifier drift | refuse — per ✂ discipline, falsifiers don't relax |
| "we should defer this for now" applied to a falsifier-fired H | Refusing to kill | F-501 → adjudicator must apply † |
| "rate limit" / "you've hit your limit" / "resets at" | Rate-limit blocker | `/vibing-with-ntm` OC-001 + OC-002 |
| `[Pasted text]` / pane stuck on bare zsh prompt | Pane wedged | `/vibing-with-ntm` OC-026 + OC-027 |
| "FILE_RESERVATION_CONFLICT" or "from_agent not registered" | Agent Mail issue | `/agent-mail` recovery; fall back per AGENT-MAIL-FALLBACKS.md |
| Same artifact diff for 3+ rounds in Phase 6 | Phase 6 over-converged on one frame | apply ∿ Dephase audit |
| Multiple "AN-NNN" filed sharing a feature | Anomaly cluster (per ΔE) | spawn new H with `origin:anomaly_spawned` |

When in doubt, scroll through pane tail manually with `tmux capture-pane -p -S -50` and verify.

---

## Liveness Truth Stack (research-context)

Before acting on any "swarm is converged / pane is stuck / phase is done" judgment, verify in this order — each layer catches lies from the one above:

1. **`tmux list-panes -F '#{pane_current_command} #{pane_pid}'`** — is the agent CLI even running? Silent zsh exits are common.
2. **`tmux capture-pane -p -S -30`** — ground truth for transient state. `--robot-tail` can sample stale buffer for several ticks.
3. **`git log --since='15 minutes ago' -- intake/ corpus/ evidence/ distillations/`** — are *artifacts* landing? Pane chatter without artifact commits is prose-without-knowledge.
4. **`br list --status=in_progress --status=closed --json | jq '.issues | length'`** — is the bead ledger advancing? An hour with zero bead state changes is a stuck phase regardless of pane chatter.
5. **`./scripts/audit-bead-invariants.sh --check=phase<N>_round`** — are mandatory invariants holding? An "advancing" phase that violates invariants is regression.
6. **`./scripts/convergence-check.sh --phase=<N>`** — is the convergence formula actually satisfied? Pane verdict ≠ formula verdict.
7. **`ntm --robot-attention --attention-session=<session>` / `ntm --robot-wait=<session> --wait-until=action_required`** — canonical event-driven operator state.
8. **`ntm --robot-causality=<session> --causality-project=<workspace>`** — cross-surface timeline when artifacts, panes, Agent Mail, and pipeline status disagree.
9. **`./scripts/tick.sh <workspace>`** — one-screen consolidated snapshot.

If any two layers disagree, resync before acting. The full `/vibing-with-ntm` Liveness Truth Stack applies underneath this — pane-state issues escalate there.

---

> **What this skill produces.** A *resumable research workspace* at a user-confirmed path (usually `~/brennerbot_sessions/<slug>/` or an explicit project-local path) containing: a question of record, a Brenner-style 7-section artifact, an evidence ledger (beads + markdown packs), per-pane Agent Mail threads, a triangulated distillation set (one per model family + one meta), a fresh-eyes audit log, an ntm pipeline definition, a `RESUME.md` reproducer, a one-page `HANDBACK.md` briefing, and a `DRIFT-CHECK.md` that compares actual session trajectory to the canonical Brenner method. **No port of brenner_bot's TypeScript code.** The artifact is a runbook + ntm session state.

---

## What This Skill Is For

You point this skill at a research target and ask one of these:

1. *"Investigate the design space for a bio-inspired alternative to nanochat."*
2. *"Find the best on-disk format for an append-only event log under 1KB events."*
3. *"What's the right architecture for X codebase given constraints Y, Z?"*
4. *"Audit our methodology for Z and surface where the consensus is wrong."*
5. *"Resume the prior brennerbot session at `<path>` for another investigation pass."*
6. *"Methodology drift check: how did our last session diverge from canonical Brenner?"*

The skill answers each by routing through the same kernel (Brenner method, triangulated from three independent expert distillations), the same operator algebra (15 named cognitive moves), and the same 10-phase loop (frame → bootstrap → propose → investigate → debate → distill → audit → freeze → handback → drift-check).

**Source corpus** (the basis for every operator, every marching-order, every failure mode in this skill): `/dp/brenner_bot/complete_brenner_transcript.md`, `/dp/brenner_bot/quote_bank_restored_primitives.md`, and the three independent expert distillations:
- `final_distillation_of_brenner_method_by_opus45.md`
- `final_distillation_of_brenner_method_by_gpt_52_extra_high_reasoning.md`
- `final_distillation_of_brenner_method_by_gemini3.md`

The triangulated kernel is in [KERNEL.md](references/KERNEL.md). When the three distillations disagree, this skill records the disagreement explicitly and lets the operator pick — never silently averages.

---

## Inputs

- **Research target** (required) — one of:
  - A research question (string): `"what is the best on-disk format for X?"`
  - A path to a codebase: `/data/projects/<repo>` (treat code as corpus + as the target system)
  - A path to a corpus directory of papers/transcripts/markdown: `/data/.../corpus/`
  - A `RESUME.md` reproducer file from a prior session
- **Workspace path** (asked, with default) — `~/brennerbot_sessions/<slug>/` unless the user provides an explicit path. **Confirm before creating.** Do not silently create sibling directories beside a target repo.
- **Mode** (auto-detected, user-overridable; see Mode Router) — `fresh-question` | `resume-session` | `code-investigation` | `corpus-distillation` | `methodology-drift-check` | `incident-investigation`.
- **Model mix** (asked) — which CLIs to spawn: any subset of `{cc (Claude Code), cod (Codex), gmi (Gemini)}`. Default: all three for triangulation. T1 minimum: 1 cc.
- **Parallelism aggression** (asked) — `solo` (1 pane) | `pair` (2) | `squad` (5) | `swarm` (8–12). Default: `squad`.
- **Robot mode** (asked) — auto-recover stuck/rate-limited panes via `/vibing-with-ntm` autonomous unstick? Default: yes.
- **Coordination substrate** (asked) — `agent-mail` (preferred for cross-pane debate) | `ntm-inbox` (fallback when Agent Mail down). Default: `agent-mail` with `ntm-inbox` fallback.

---

## Up-Front Confirmations (Ask Before Starting)

Before creating any directory or spawning any pane, present this and wait for the user's answer:

1. **Research target?** Confirm the absolute path or the verbatim question.
2. **Workspace path?** Confirm `<default>` or take user override. We will `git init` it.
3. **Mode?** Show auto-detected mode + reasoning; let user override.
4. **Roster size + model mix?** Default is `squad` (5 panes: 1 proposer + 2 investigators + 1 devil's-advocate + 1 synthesizer; an adjudicator role rotates through panes). For `swarm`, we spawn the full 5-role canonical roster as separate panes plus extras (see [ROSTER-PLANS.md](references/ROSTER-PLANS.md)).
5. **Robot mode + autonomous recovery?** Default on. Off means you tend ticks manually.
6. **Coordination?** Default Agent Mail with ntm-inbox fallback. Tell user the thread-id convention will be `RS-<YYYYMMDD>-<slug>`.
7. **Resume or fresh?** If workspace exists, offer `resume-session` (re-enters phase loop where it left off via `RESUME.md`) or `fresh-pass` (additional investigation round on top of existing artifact).
8. **Helper skill inventory.** Run `./scripts/check-skills.sh <workspace>` (the workspace root, NOT `.brenner_workspace/`) for a preview; it prints JSON to stdout. After the workspace exists, either let `bootstrap-session.sh` write `<workspace>/.brenner_workspace/phase0_skill_inventory.json`, or redirect manually with `./scripts/check-skills.sh <workspace> > <workspace>/.brenner_workspace/phase0_skill_inventory.json`. For any missing skill referenced below, if the user has `jsm` installed and authenticated, offer `jsm install <name>` for: `/ntm`, `/vibing-with-ntm`, `/agent-mail`, `/beads-br`, `/beads-bv`, `/cass`, `/cass-memory`, `/flywheel`, `/multi-model-triangulation`, `/operationalizing-expertise`, `/idea-wizard`, `/multi-pass-bug-hunting`, `/ubs`, `/open-beads-weighted-tmux-agent-sessions`. Don't block a phase if a helper skill is missing — note it in `phase0_skill_inventory.json` and proceed with the inline fallback in [SKILL-FALLBACKS.md](references/SKILL-FALLBACKS.md).

---

## Skill Bootstrap (Phase 0.5 — right after inputs, before Phase 1)

```bash
./scripts/bootstrap-session.sh <workspace-path> "<research-question-or-target>" --mode=<mode> --roster=<roster>
```

This script (idempotent; safe on resume; runs in this order):

1. `mkdir -p <workspace>/{intake,corpus/ingested,evidence/packs,evidence/excerpts,distillations,deliverables/scripts,session-logs/ntm-pipeline-runs,.brenner_workspace,.ntm,.beads}`
2. `git init` if not already; write a default `.gitignore` (excluding `.ntm/checkpoints/*.tar.gz` except `latest`, `tick_history.jsonl`, pipeline-run captures)
3. `br init --prefix=bb` (bead labels are applied by the Phase 1+ MOs when they create beads — see [BEADS-SCHEMA.md](references/BEADS-SCHEMA.md))
4. Write `.brenner_workspace/phase0_skill_inventory.json` from `check-skills.sh <workspace>`
5. Auto-detect mode if not overridden (presence of `RESUME.md` → `resume-session`; `.git` dir in target → `code-investigation`; dir of `.md`/`.pdf`/`.txt` → `corpus-distillation`)
6. Generate slug + `SESSION_ID = RS-<UTC date>-<slug>` from the question/target
7. Write `.brenner_workspace/phase0_scope_decision.md` (mode, roster, model mix, robot-mode, coordination, resume-from, phase plan; idempotent — won't overwrite an existing file)
8. Print summary + per-mode next-steps. The script does NOT `git add` or commit anything; staging/commit is the operator's job at end of Phase 1.

If `jsm` isn't installed and the user wants the helper skills:

```bash
curl -fsSL https://jeffreys-skills.md/install.sh | bash
jsm login
```

Full bootstrap detail: [SKILL-FALLBACKS.md](references/SKILL-FALLBACKS.md).

---

## Mode Router

Pick the primary mode first. The phase loop is the same; the **stop conditions and required artifacts** differ.

| Mode | Use when | Must finish with |
|------|----------|------------------|
| `fresh-question` | New research question, no prior workspace | All 10 phases; full distillation set + handback |
| `code-investigation` | Target is a codebase; questions revolve around its design space, weaknesses, alternatives | Phases 1–10, with Phase 1 corpus = code archaeology output, Phase 4 evidence packs cite specific files/commits |
| `corpus-distillation` | Target is a directory of papers/transcripts/markdown | Phases 1–10, with Phase 4 evidence-pack excerpts mandatory verbatim with source anchors |
| `resume-session` | Prior `RESUME.md` exists; user wants another pass | Skip Phase 1 framing; re-enter Phase 4 (more investigation) or Phase 6 (more distillation) per the resume token |
| `methodology-drift-check` | Compare past session trajectory to canonical Brenner | Phase 10 only (the rest is read-only); produce `DRIFT-CHECK.md` |
| `incident-investigation` | Production incident; rapid hypothesis triage under time pressure | Compressed incident loop: Phase 1, Phase 3, Phase 4 investigation inline with Phase 5 adjudication, and Phase 7 lightweight audit. Skip formal Phase 2 bootstrap plus Phases 6, 8, 9, and 10. The compressed loop emits `deliverables/INCIDENT-VERDICT.md`; post-mortem-formalization mode handles the full handback/drift loop later. |

Auto-detect heuristics in `bootstrap-session.sh`: presence of `RESUME.md` → `resume-session`. Target is a `.git` repo → `code-investigation`. Target is a directory of `.md` / `.pdf` / `.txt` → `corpus-distillation`. Otherwise → `fresh-question`.

Full mode definitions, exit criteria, and required artifacts: [OPERATING-MODES.md](references/OPERATING-MODES.md).

---

## Workspace Layout

```
<workspace>/
├── intake/
│   ├── question_of_record.md       # Brenner Step-0 framing
│   ├── target_inventory.md         # what we are investigating (path/question/corpus)
│   └── session_history.md          # cumulative log across resumes
├── corpus/
│   ├── ingested/                   # primary sources, organized by source-id
│   ├── corpus_index.md             # one row per source: id, title, authors, date, anchor scheme
│   └── search_log.md               # every corpus search + result count + top hits
├── evidence/
│   ├── packs/                      # one .md per hypothesis: EV-pack-H-001.md, etc.
│   ├── excerpts/                   # verbatim quotes with §-anchors (like brenner_bot quote_bank)
│   └── verification_log.md         # every evidence record's verification step + outcome
├── distillations/
│   ├── by_cc.md                    # Claude Code's distillation
│   ├── by_cod.md                   # Codex's distillation
│   ├── by_gmi.md                   # Gemini's distillation
│   ├── meta_synthesis.md           # reconciled across model families
│   └── disagreement_register.md    # explicit list of where the three distillations diverge
├── deliverables/
│   ├── HANDBACK.md                 # one-page "what we found, what's still open"
│   ├── RESUME.md                   # exact reproducer for next session
│   ├── ARTIFACT.md                 # canonical 7-section research artifact
│   └── DRIFT-CHECK.md              # methodology drift vs canonical Brenner
├── session-logs/
│   ├── round-*.md                  # per-round operator notes
│   └── ntm-pipeline-runs/          # captured pipeline outputs
├── .brenner_workspace/
│   ├── phase0_scope_decision.md
│   ├── phase0_skill_inventory.json
│   ├── phase_*_complete.flag       # phase exit markers (idempotent re-entry)
│   └── tick_history.jsonl          # operator-tick log
├── .ntm/                           # ntm pipeline + project local config
├── .beads/                         # beads_rust state (jsonl)
└── .git/
```

Full layout discipline (which agents own which directory, which subagent writes which artifact): [WORKSPACE-LAYOUT.md](references/WORKSPACE-LAYOUT.md).

---

## The 10-Phase Loop (Mandatory Spine)

```
Phase 1  TARGET FRAMING & CORPUS ASSEMBLY    Brenner Step-0; ingest sources; stand up beads schema
Phase 2  SWARM BOOTSTRAP                     spawn ntm panes; wire Agent Mail; dispatch onboarding
Phase 3  HYPOTHESIS GENERATION (parallel)    proposers + triage; mandatory third-alternative
Phase 4  INVESTIGATION (heavily parallel)    investigators + devil's-advocates fill evidence packs
Phase 5  CROSS-EXAMINATION & ADVERSARIAL     pairwise debate threads; adjudicator scores
Phase 6  SYNTHESIS & DISTILLATION            one distillation per model family + meta-synthesis
Phase 7  FRESH-EYES AUDIT                    three calibrated review prompts × 2 clean rounds
Phase 8  SESSION RESUMABILITY & FREEZING     RESUME.md + git commit + ntm checkpoint export
Phase 9  OPERATOR HANDBACK                   one-page briefing; unresolved-thread tagging
Phase 10 METHODOLOGY DRIFT CHECK             trajectory vs canonical Brenner; feed back into refs/
```

**Phases 4 and 6 are reapply-until-quiet** — keep dispatching rounds until the marginal hypothesis kill rate falls below the marginal hypothesis add rate (this is the same convergence criterion brenner_bot's `session robot` mode uses; see [CONVERGENCE.md](references/CONVERGENCE.md)). Phase 7's two consecutive clean rounds are the explicit termination gate before Phase 8.

**Phase 7 fresh-eyes prompts (verbatim, calibrated — same trio used by `/documentation-website-for-software-project` and `/saas-billing-patterns-for-stripe-and-paypal`):**

1. *"Carefully read over all of the artifact and evidence packs you and the other panes just produced with 'fresh eyes' looking super carefully for any obvious bugs, errors, problems, issues, confusion, missing falsifiers, omitted hypotheses, unsupported leaps, etc. Carefully fix anything you uncover."*
2. *"Sort of randomly explore the evidence packs and distillations in this workspace, choosing files to deeply investigate and trace their citations through the related evidence and corpus excerpts. Once you understand the purpose of each piece in the larger context of the question of record, do a super careful, methodical, and critical check with 'fresh eyes' to find any obvious bugs, problems, errors, silly mistakes."*
3. *"Turn your attention to reviewing the distillations and evidence packs written by your fellow panes and check for any issues, bugs, errors, problems, inefficiencies, security problems, reliability issues. Diagnose underlying root causes using first-principle analysis. Don't restrict yourself to the latest commits — cast a wider net and go super deep."*

Each pane runs all three. Repeat the trio until two consecutive trio-rounds produce only trivial edits. Then run `ubs` (if available) on any code/scripts in `deliverables/` and the linters; fix everything.

### Mode variants on the phase loop

| Mode | Phases run | Key omissions / additions |
|------|-----------|---------------------------|
| `fresh-question` | All 10 | Default |
| `code-investigation` | All 10; Phase 1 = `/codebase-archaeology` first | Phase 4 evidence packs cite file paths + line numbers + commit SHAs |
| `corpus-distillation` | All 10; Phase 1 ingests corpus into `corpus/ingested/` with `§`-anchor scheme | Phase 4 evidence excerpts mandatory verbatim |
| `resume-session` | Read `RESUME.md`, jump to indicated phase | Skip Phase 1 framing; reuse beads + Agent Mail threads |
| `methodology-drift-check` | Phase 10 only | Read-only over prior `session-logs/`; compare trajectory to [DRIFT-RUBRIC.md](references/DRIFT-RUBRIC.md) |
| `incident-investigation` | 1→3→5(with Phase 4 inline)→7 (compressed) | Skip formal 2/6/8/9/10; compressed loop emits `INCIDENT-VERDICT.md` (not full `HANDBACK.md`) |

Full per-phase playbook with exit criteria + exact prompts: [PHASES.md](references/PHASES.md) and [MARCHING-ORDERS.md](references/MARCHING-ORDERS.md).

---

## Phase-By-Phase Quick Reference

This is the spine. Each cell links to deeper detail. Use this table when running the skill — every other section in SKILL.md exists to support these rows.

| Phase | What it does | Beads written/read | Mail threads | Parallelizable? | Key marching order(s) | Failure modes (see [FAILURE-TABLE.md](references/FAILURE-TABLE.md)) | Exit gate |
|-------|--------------|--------------------|--------------|-----------------|------------------------|---------------------------------------------------------------------|-----------|
| 1 Framing+Corpus | Question of record (Brenner Step-0); ingest sources; init beads | seeds `Q-001`; creates corpus index | none yet | mostly sequential; corpus chunk-ingest can fan out | [MO-01-frame-question.md](assets/marching-orders/MO-01-frame-question.md) | F-101 question too broad; F-102 corpus drift; F-103 no falsifier specified | `intake/question_of_record.md` exists; `corpus_index.md` ≥1 row; `Q-001` bead created with `falsifier:` field non-empty |
| 2 Swarm Bootstrap | Spawn ntm panes; assign roles; wire Agent Mail; install pre-commit guard | reads `Q-001` for briefing | opens `RS-<date>-<slug>` main session thread plus per-role threads | onboarding dispatch is parallel | [MO-02-onboarding.md](assets/marching-orders/MO-02-onboarding.md) | F-201 pane stuck at zsh; F-202 mail register timeout; F-203 role collision | `ntm --robot-snapshot` shows N panes alive; each has acked onboarding mail |
| 3 Hypothesis Generation | Proposer panes emit `H-NNN` beads; triage panes dedupe + cluster + rank | writes `H-NNN`; labels `hypothesis`; required fields: `claim`, `mechanism`, `falsifier`, `expected_evidence`, `category`, `origin` | per-hypothesis thread `RS-...-H-NNN` | **fully parallel** across proposers; triage is sequential after | [MO-03a-propose.md](assets/marching-orders/MO-03a-propose.md), [MO-03b-triage.md](assets/marching-orders/MO-03b-triage.md), [MO-03c-third-alternative.md](assets/marching-orders/MO-03c-third-alternative.md) | F-301 false-binary slate (no third alternative); F-302 hypothesis duplication; F-303 unfalsifiable hypotheses | ≥3 distinct hypotheses + at least one labeled `origin:third_alternative` (per Brenner §103) |
| 4 Investigation | Investigators fill per-hypothesis evidence packs (markdown + beads); devil's advocates attack the strongest in parallel | writes `EV-NNN` beads (`evidence`); reads/updates `H-NNN`; writes `C-NNN` beads (`critique`) on attacks | inbound: per-hypothesis thread; cross-pane: `RS-...-INVEST-coord` | **heavily parallel**: one investigator per hypothesis; devil's advocates stage independently | [MO-04a-investigate.md](assets/marching-orders/MO-04a-investigate.md), [MO-04b-devils-advocate.md](assets/marching-orders/MO-04b-devils-advocate.md), [MO-04c-evidence-pack.md](assets/marching-orders/MO-04c-evidence-pack.md) | F-401 evidence inflation (more EV without H state change); F-402 contradictory-evidence loop; F-403 confirmation-only bias; F-404 missing potency check | `kill_rate ≥ add_rate` for the round (see [CONVERGENCE.md](references/CONVERGENCE.md)); ≥1 EV per surviving H; every kill-claim has a citing EV |
| 5 Cross-Examination | Pairwise adversarial debate on surviving hypotheses; adjudicator scores | writes `DEBATE-NNN` beads; updates `state:` in `H-*` descriptions (active→confirmed\|refuted\|superseded\|deferred); writes `A-NNN` (assumptions) | one thread per debate pair: `RS-...-DEBATE-<H_I>-vs-<H_J>`; adjudication thread `RS-...-ADJUDICATE` | **parallel across hypothesis pairs** | [MO-05a-cross-exam.md](assets/marching-orders/MO-05a-cross-exam.md), [MO-05b-adjudicate.md](assets/marching-orders/MO-05b-adjudicate.md) | F-501 attachment to favored hypothesis (no kills); F-502 adjudicator bias; F-503 debate stuck on rhetoric not evidence | every active hypothesis has survived ≥1 adversarial pass with rebuttals on record |
| 6 Synthesis+Distillation | One distillation per model family (cc/cod/gmi); then meta-synthesizer reconciles | writes `D-NNN` beads (`distillation`); reads everything | inbound: full session; cross-model thread `RS-...-META-DISTILL` | per-model parallel; meta is sequential after; **invoke `/multi-model-triangulation` here** | [MO-06a-distill.md](assets/marching-orders/MO-06a-distill.md), [MO-06b-meta-synthesize.md](assets/marching-orders/MO-06b-meta-synthesize.md) | F-601 distillations agree by averaging (silently); F-602 model-family bias; F-603 missing disagreement register | `distillations/by_*.md` × N model families + `meta_synthesis.md` + `disagreement_register.md` all exist; meta cites the disagreements |
| 7 Fresh-Eyes Audit | Three calibrated review prompts × 2 clean rounds; ubs/multi-pass-bug-hunting on any code | writes `AF-NNN` beads (label=`audit-finding`); flips H states if findings warrant | per-pane thread `RS-...-AUDIT-pN` | parallel across panes | [MO-07a-fresh-eyes.md](assets/marching-orders/MO-07a-fresh-eyes.md) (the verbatim trio above) | F-701 audit accepts everything (rubber-stamp); F-702 audit reopens settled questions on rhetoric; F-703 ubs warnings ignored | 2 consecutive trio-rounds with only trivial edits |
| 8 Resumability+Freezing | Write `RESUME.md`; `br sync`; commit; `ntm checkpoint save`; export checkpoint archive | none new; freezes existing | none | mostly sequential | [MO-08-freeze.md](assets/marching-orders/MO-08-freeze.md) | F-801 missing RESUME.md tokens; F-802 uncommitted bead drift; F-803 ntm checkpoint missing pane state | `git status` clean; `br sync --flush-only` clean; `ntm --robot-snapshot` shows quiescent state; checkpoint archive exists |
| 9 Operator Handback | One-page `HANDBACK.md`; tag every unresolved thread listed in "What's still open" | reads everything | none | sequential, single agent | [MO-09-handback.md](assets/marching-orders/MO-09-handback.md) | F-901 handback too long (>1 page); F-902 missing unresolved-thread tags; F-903 no recommendation for next loop | `HANDBACK.md` ≤1 page; every unresolved `H-*` and `EV-*` listed in "What's still open" has a `next-action:` field |
| 10 Methodology Drift Check | Compare trajectory to canonical Brenner; flag improvements/regressions; feed back into `references/` | none | optional `RS-...-DRIFT` thread | single fresh agent (use `/idea-wizard` or general-purpose) | [MO-10-drift-check.md](assets/marching-orders/MO-10-drift-check.md) | F-1001 drift check rationalizes drift as improvement; F-1002 missing baseline anchor; F-1003 lessons not fed back | `DRIFT-CHECK.md` cites specific Brenner operators that were skipped/violated/improved-on |

Each marching-order template, beads schema field, mail thread convention, parallelism rule, and recovery move is documented in full in the linked files. **Don't run a phase from this table alone — read the matching `MO-*.md` and the section's slot in `PHASES.md`.**

---

## Parallelism Model

The 10 phases naturally cluster into **fan-out**, **bottleneck**, and **fan-in** stages:

```
                                                                                 ┌─→ pane(cc) distill ─┐
Phase 1 framing ──→ Phase 2 bootstrap ──→ Phase 3 propose ──→ Phase 4 investigate ─→ Phase 5 debate ──→ ┤   pane(cod) distill ├──→ Phase 6 meta ──→ Phase 7 audit (×2) ──→ 8 freeze ──→ 9 handback ──→ 10 drift
   (sequential)          (parallel        (parallel              (heavily               (parallel        └─→ pane(gmi) distill ─┘    (sequential)         (parallel)         (seq)        (seq)         (seq)
                          dispatch)        proposers,             parallel:              across
                                           sequential             1 inv per H,           hypothesis
                                           triage)                + devil's              pairs)
                                                                  advocates)
```

**Coordination.** Use [/agent-mail](../agent-mail/SKILL.md) file reservations any time multiple panes could touch the same artifact (especially `deliverables/ARTIFACT.md`, `distillations/meta_synthesis.md`, and `evidence/packs/EV-pack-*.md` during cross-investigation). Thread id schema:

| Surface | Thread id |
|---------|-----------|
| Master | `RS-<YYYYMMDD>-<slug>` |
| Per hypothesis | `RS-<YYYYMMDD>-<slug>-H-<NNN>` |
| Pairwise debate | `RS-...-DEBATE-<H_I>-vs-<H_J>` (e.g. `RS-...-DEBATE-H-001-vs-H-002` — bead IDs interpolated verbatim) |
| Investigation coord | `RS-...-INVEST-coord` |
| Adjudication | `RS-...-ADJUDICATE` |
| Per-pane audit | `RS-...-AUDIT-p<N>` |
| Meta-distillation | `RS-...-META-DISTILL` |
| Drift check | `RS-...-DRIFT` |

Subjects always prefix with `[<thread-id>]`. Full thread template + body conventions: [AGENT-MAIL-CONVENTIONS.md](references/AGENT-MAIL-CONVENTIONS.md).

**Roster size — pick based on question scope, model availability, and machine RAM** (distinct from the stakes-driven **Tier** T1–T5 above; roster is *how many panes*, tier is *how high the stakes*):

| Roster | Shape | When |
|--------|-------|------|
| Solo | 1 pane (cc) | Quick sanity check; questions you suspect have a known answer; <30 min budget |
| Pair | 2 panes (cc + cod) | Two-perspective triangulation; minimal swarm; ~1h budget |
| Squad | 5 panes (1 proposer + 2 investigators + 1 devil's-advocate + 1 synthesizer; adjudicator role rotates) | Default for most research questions; ~3–5h budget |
| Swarm | 8–12 panes — full canonical 5-role roster across model families + extras for parallel hypothesis investigation | Complex design space; multi-model triangulation; ≥half-day budget |

Multi-model triangulation (cc + cod + gmi) is reserved for Phase 4 investigation (where independent reads catch different evidence) and Phase 6 distillation (where independent syntheses are the *point*). For Phase 7 audit, mix at least two model families when possible. Full tier rules: [ROSTER-PLANS.md](references/ROSTER-PLANS.md).

---

## The Brenner Kernel (Triangulated, Skill-Internal)

The three independent expert distillations agree on these two axioms and the operator basis. Where they disagree, [DISAGREEMENT-REGISTER-OF-DISTILLATIONS.md](references/DISAGREEMENT-REGISTER-OF-DISTILLATIONS.md) records the divergence and our chosen synthesis.

**Axiom 1 — Reality has a generative grammar.** Phenomena are *produced* by causal machinery operating on discoverable rules. Science is the reverse-engineering of that machinery; experiments are the queries that force the grammar to reveal itself.

**Axiom 2 — To understand is to be able to reconstruct.** A theory is not yet understood until you can specify how to *build* the phenomenon from primitives. Description is not understanding; reconstruction is. (Gedanken Organism Standard: could you, given the inputs and initial conditions, compute the output?)

**The Generative Loop (Brenner's signature move).** Starting from a paradox noticed through cross-domain vision, split levels and reduce dimensions to extract invariants, then materialize as an exclusion test — powered by amplification in a well-chosen system you can build yourself — constrained by physical reality, with honest exception handling and willingness to kill.

```
WHILE understanding incomplete:
    ◊  Hunt for paradoxes in current model
    ⊘  Check for level confusions (program/interpreter, message/machine)
    𝓛  Reduce dimensionality; find tractable representation
    ⊞  Calculate scale; stay imprisoned in physics
    ≡  Identify invariants at that level
    ⌂  Materialize: "what would I see if this were true?"
    ✂  Derive forbidden patterns → exclusion test
    ⟂  Transpose to optimal organism/system (or in our case: optimal proxy)
    🔧 Build what you need (don't wait for infrastructure)
    ↑  Amplify signal (abundance, selection, regime)
    ⤴  Run the cheapest decisive experiment first ("quickie", §99)   # scheduling rule, not a 16th operator — see note below
    IF forbidden pattern observed:
        †  Kill model; GOTO ◊
    ELIF unexpected anomaly:
        ΔE Quarantine; continue
    ELIF expected pattern observed:
        update model; reduce hypothesis space
    IF field industrializing:
        ∿  Dephase; find new paradox
```

This is not metaphor. Each operator maps to a concrete move in this skill — see [OPERATORS.md](references/OPERATORS.md) for the full card library (15 operators × {trigger, recipe, marching-order module, validator, failure mode}).

**On `⤴` ("quickie") in the pseudocode above.** The 15-operator basis is canonical. The `⤴` glyph is a *scheduling rule* (§99 — when multiple amplifying tests are available, run the cheapest decisive one first), not a separate operator. It's spelled with a glyph for parity with the rest of the loop, but it has no entry in OPERATORS.md and doesn't change the operator count. Its dedicated marching order is [MO-quickie-pilot.md](assets/marching-orders/MO-quickie-pilot.md), which composes ⤴ with `↑ Amplify` and `⌂ Materialize`.

Full triangulated kernel + axiom-by-axiom evidence tracing back to the source corpus (`§`-anchored): [KERNEL.md](references/KERNEL.md).

---

## Operator Algebra (Cognitive Moves Mapped to NTM/Beads/Mail)

Composable Brenner moves. Apply them to any hypothesis, evidence pack, debate, or distillation. Each operator has a question that, if it fails, names a section/template to fix.

| Glyph | Name | Question (the operator's trigger) | Where it lands in the skill |
|-------|------|-----------------------------------|------------------------------|
| `◊` | **Paradox-Hunt** | "What two well-attested facts seem to contradict each other right now?" | Phase 1 question framing; Phase 4 evidence accumulation; written into `intake/question_of_record.md` and `evidence/packs/*` |
| `⊘` | **Level-Split** | "Am I conflating program with interpreter? message with machine? mapping with text?" | Phase 3 hypothesis triage; flips false-dichotomy slates into 3+ alternatives |
| `𝓛` | **Recode/Dimensional-Reduction** | "What encoding makes the rival hypotheses' predictions diverge?" | Phase 3 hypothesis statement; Phase 5 debate prep |
| `≡` | **Invariant-Extract** | "What property holds regardless of detail and constrains every hypothesis?" | Phase 4 evidence pack `key_findings`; Phase 6 distillation kernel |
| `✂` | **Exclusion-Test** | "What pattern is *forbidden* under this hypothesis?" | Mandatory `falsifier:` field on every `H-*` bead (see [BEADS-SCHEMA.md](references/BEADS-SCHEMA.md)) |
| `⟂` | **Object-Transpose** | "What proxy/substrate would make this test cheap?" | Phase 4 investigation choice of corpus shard, code shard, or external query |
| `↑` | **Amplify** | "Where is the signal naturally large? digital readout? selection?" | Phase 4 investigation methodology; Phase 5 cross-exam discriminator choice |
| `⌂` | **Materialize** | "If the hypothesis is true, what would I *see*?" | Phase 3 `expected_evidence` field on every `H-*` bead; Phase 4 investigator marching orders |
| `🔧` | **DIY/Bricolage** | "Can I build the test now instead of waiting?" | Phase 4 — investigators are *encouraged* to write quick scripts in `deliverables/scripts/` rather than block on missing tooling |
| `⊞` | **Scale-Check** | "Does the math/physics actually permit this?" | Mandatory `assumption_ledger` entries with `type:scale_physics`; Phase 7 audit verifies |
| `🤝` | **GAN/Conversation** | "Have I externalized this hypothesis to another mind?" | Phase 5 cross-examination is *literally* the Brenner-Crick GAN; debate threads are the artifact |
| `ΔE` | **Exception-Quarantine** | "Are anomalies clustering or scattered?" | `anomaly_register` section of `ARTIFACT.md`; clustering anomalies trigger Phase 4 reopen |
| `†` | **Theory-Kill** | "Has this hypothesis failed its falsifier? Then kill it now." | Phase 5 `state: refuted`; Phase 7 audit flags un-killed-but-failed hypotheses |
| `∿` | **Dephase** | "Is the swarm in-phase with consensus? Then we're not learning." | Phase 7 audit flag; Phase 10 drift-check rubric line |
| `⊙` | **Productive-Ignorance** | "Is the expert's tight prior closing off live alternatives?" | Roster role assignment: at least one investigator pane should be told to read minimally and reason from first principles |

Operator composition is multiplicative. The full card library with marching-order modules, validators, and failure-mode tables: [OPERATORS.md](references/OPERATORS.md). Composition cheat-sheet (which operators to apply in what order at each phase): [OPERATORS.md § Composition cheat-sheet](references/OPERATORS.md#composition-cheat-sheet).

---

## Roster & Roles

The five canonical roles (mapped from brenner_bot's three-role roster + extra coverage):

| Role | brenner_bot equivalent | Pane responsibility | Reads | Writes | Default model preference |
|------|------------------------|---------------------|-------|--------|--------------------------|
| **Proposer** | hypothesis_generator | Generate candidate hypotheses; mandatory third-alternative injection | corpus, prior `H-*` beads | new `H-*` beads with `origin: proposed | third_alternative` | cod (Codex) — broad generation |
| **Investigator** | (split off from test_designer) | Fill per-hypothesis evidence packs; cite verbatim with `§`-anchors; design potency checks | one assigned `H-*`, corpus | `EV-*` beads + `evidence/packs/EV-pack-H-NNN.md` | cc (Claude) — careful reading |
| **Devil's-Advocate** | adversarial_critic | Attack the strongest hypothesis; file `C-*` critiques + counter-evidence | top 2–3 `H-*` by current confidence | `C-*` beads + counter-`EV-*` | gmi (Gemini) — adversarial framing |
| **Synthesizer** | (new) | Produce per-model-family distillation; reconcile evidence packs | full session state | `D-*` beads + `distillations/by_<model>.md` | matches its own model family |
| **Adjudicator** | (rotates among critic + synthesizer) | Score adversarial debates; flip hypothesis states; manage anomaly register | debate threads | adjudication notes; `state:` updates on `H-*` descriptions | cc (Claude) — judgment |

**Role assignment rules:**

1. **At least one Proposer must be told to apply ⊙ Productive-Ignorance** — read minimally before generating, then expand later.
2. **At least one Devil's-Advocate must be a different model family than the strongest-confidence Proposer** — to break in-phase reasoning.
3. **The Synthesizer pool must include at least 2 model families** for Phase 6 to produce real triangulation.
4. **The Adjudicator role rotates** to prevent attachment; never the same pane two debates in a row.

**Pane-to-role binding** is dispatched in Phase 2 onboarding (`MO-02-onboarding.md`) and recorded in `phase0_scope_decision.md`. Roles can be re-bound mid-session via Phase 4 mode-flip prompts (see `MARCHING-ORDERS.md § Mode-Switch`). Full role spec + per-role marching-order templates + escalation paths: [ROSTER-PLANS.md](references/ROSTER-PLANS.md).

---

## Beads Schema (the hypothesis ledger)

Beads (`br`) is the hypothesis/evidence/debate ledger. Each bead type maps to a concept from brenner_bot's CLI but is implemented purely via `br create --labels` + structured description fields.

| Type | Prefix | Label | Key fields (in description as `field: value` blocks) | State machine |
|------|--------|-------|------------------------------------------------------|---------------|
| Question of record | `Q-NNN` | `q-of-record` | `question`, `falsifier`, `scope`, `out_of_scope`, `mode` | open → closed |
| Hypothesis | `H-NNN` | `hypothesis` | `claim`, `mechanism`, `falsifier`, `expected_evidence`, `category` (mechanistic\|phenomenological\|boundary\|auxiliary\|third_alternative), `origin` (proposed\|third_alternative\|refinement\|anomaly_spawned), `confidence` (high\|medium\|low\|speculative), `parent` | proposed → active → confirmed\|refuted\|superseded\|deferred *(short bead-level vocabulary; the conceptual 9-state FSM in [HYPOTHESIS-LIFECYCLE-STATE-MACHINE.md](references/HYPOTHESIS-LIFECYCLE-STATE-MACHINE.md) maps to these — see § State-name mapping there)* |
| Evidence | `EV-NNN` | `evidence` | `type` (paper\|experiment\|observation\|prior_session\|expert_opinion\|code_artifact), `source`, `excerpts`, `relevance`, `supports[]`, `refutes[]`, `informs[]`, `verified` | unverified → verified |
| Test/probe | `T-NNN` | `test` | `discriminates_between` (H1, H2, ...), `potency_check`, `expected_signal`, `cost_estimate` | designed → ready → in_progress → completed\|blocked\|abandoned |
| Assumption | `A-NNN` | `assumption` | `statement`, `type` (background\|methodological\|boundary\|scale_physics), `affects` (`H-*`, `T-*`), `load_description` | unchecked → challenged → verified\|falsified |
| Anomaly | `AN-NNN` | `anomaly` | `observation`, `conflicts_with[]`, `source_type` | active → resolved\|deferred\|paradigm_shifting |
| Critique | `C-NNN` | `critique` | `target` (`H-*`, `T-*`, `A-*`, `framing`, `methodology`), `attack`, `severity` (minor\|moderate\|serious\|critical), `evidence_to_confirm` | active → addressed\|dismissed\|accepted |
| Debate | `DEBATE-NNN` | `debate` | `pair` (H<i> vs H<j>), `rounds`, `current_winner`, `adjudication` | open → settled |
| Distillation | `D-<family>-NNN` (e.g. `D-cc-001`, `D-meta-001`) | `distillation` | `by_model` (cc\|cod\|gmi\|meta), `kernel_axioms[]`, `disagreements[]` | draft → final |
| Audit finding | `AF-NNN` | `audit-finding` | `severity`, `target_artifact`, `recommendation` | open → addressed\|deferred |

**Mandatory invariants** (enforced at Phase 7 audit; mirror `scripts/audit-bead-invariants.sh` checks):

- Every `hypothesis` bead **must** have a non-empty `falsifier:` field. Hypotheses without falsifiers are not hypotheses; they're moods. *(check_every_H_has_falsifier)*
- Every `hypothesis` bead **must** have a non-empty `expected_evidence:` field — the `⌂ Materialize` answer to "if this H were true, what would I see?". *(check_every_H_has_expected_evidence)*
- Every `H-*` in state `refuted` **must** carry a `refuted_by:` field (underscore, not hyphen — the audit script greps the underscore form) pointing at the specific `EV-*` or `T-*` that triggered the kill. *(check_every_refuted_has_refuted_by)*
- Every `H-*` in state `confirmed` **must** have survived ≥1 adversarial debate (referenced `DEBATE-*`) and have ≥2 `EV-*` supporting it from independent sources. *(check_every_confirmed_has_debate)*
- Every `H-*` in state `superseded` **must** carry a `parent: H-NNN` field pointing at the replacement.
- Every `assumption` of `type:scale_physics` **must** carry a `calculation:` block showing the math. *(check_every_scale_physics_has_calculation)*
- The hypothesis slate **must** include at least one `origin:third_alternative` (the "both could be wrong" guard from §103). *(check_third_alternative_present)*

Full schema with field grammar, validation queries, and example records: [BEADS-SCHEMA.md](references/BEADS-SCHEMA.md).

---

## Agent Mail Thread Conventions

Threads are the *substrate* of cross-pane debate. Brenner's "conversational science" (§66) is operationalized here as Agent Mail thread discipline.

**Thread-id schema** (already shown above): `RS-<YYYYMMDD>-<slug>[-H-NNN | -DEBATE-<H_I>-vs-<H_J> | -INVEST-coord | -ADJUDICATE | -AUDIT-pN | -META-DISTILL | -DRIFT]` — `<H_I>`/`<H_J>` are bead IDs interpolated verbatim (e.g. `H-001`, `H-014`).

**Per-thread body conventions** (see [AGENT-MAIL-CONVENTIONS.md](references/AGENT-MAIL-CONVENTIONS.md) for the templates):

- Per-hypothesis thread (`RS-...-H-NNN`): every reply must cite at least one `EV-*` bead. Replies without evidence get rejected by adjudicator marching orders.
- Pairwise debate thread (`RS-...-DEBATE-<H_I>-vs-<H_J>`): structured rounds — `[opening]`, `[rebuttal]`, `[counter-rebuttal]`, `[adjudication]`. Max 3 rounds before adjudicator must rule.
- Investigation coord thread: who-claims-what; reservation conflicts; cross-pane handoffs.
- Audit thread: per-pane fresh-eyes findings, severity-tagged.
- Meta-distillation thread: where the model-family distillations are reconciled and disagreements registered.

**File reservations** when investigators are filling evidence packs or synthesizers are merging distillations: lease the specific file pattern (e.g. `evidence/packs/EV-pack-H-007.md`) for `ttl_seconds=3600`. Conflict resolution: oldest-claim-wins; loser flips role to devil's-advocate against the winner's hypothesis (this is a *feature* — it accelerates Phase 5).

If Agent Mail is unavailable: fall back to `ntm-inbox` mode (use `ntm mail` wrapping or pure `br update --assignee=`). Thread id stays the same — just persisted in beads metadata. See [AGENT-MAIL-FALLBACKS.md](references/AGENT-MAIL-FALLBACKS.md).

---

## Marching-Orders Library

Every dispatch in this skill is a stored, parameterized marching-order template. Operators don't free-write prompts in the middle of a session — they pick a template, fill placeholders, and ship.

| Template | Phase | Purpose |
|----------|-------|---------|
| [MO-01-frame-question.md](assets/marching-orders/MO-01-frame-question.md) | 1 | Brenner Step-0: turn raw user ask into a question of record with mandatory falsifier and scope |
| [MO-02-onboarding.md](assets/marching-orders/MO-02-onboarding.md) | 2 | Brief a pane on its role, the question of record, and the coordination substrate |
| [MO-03a-propose.md](assets/marching-orders/MO-03a-propose.md) | 3 | Generate candidate hypotheses with mandatory `claim/mechanism/falsifier/expected_evidence` |
| [MO-03b-triage.md](assets/marching-orders/MO-03b-triage.md) | 3 | Dedupe + cluster + rank proposed hypotheses |
| [MO-03c-third-alternative.md](assets/marching-orders/MO-03c-third-alternative.md) | 3 | Force-inject "both could be wrong" — Brenner §103 |
| [MO-04a-investigate.md](assets/marching-orders/MO-04a-investigate.md) | 4 | Fill evidence pack for one hypothesis; cite verbatim |
| [MO-04b-devils-advocate.md](assets/marching-orders/MO-04b-devils-advocate.md) | 4 | Attack the strongest hypothesis with counter-evidence |
| [MO-04c-evidence-pack.md](assets/marching-orders/MO-04c-evidence-pack.md) | 4 | Per-hypothesis evidence pack template that the investigator fills |
| [MO-05a-cross-exam.md](assets/marching-orders/MO-05a-cross-exam.md) | 5 | Pairwise structured debate (opening / rebuttal / counter / adjudication) |
| [MO-05b-adjudicate.md](assets/marching-orders/MO-05b-adjudicate.md) | 5 | Score the debate; flip `state:` in `H-*` descriptions |
| [MO-06a-distill.md](assets/marching-orders/MO-06a-distill.md) | 6 | Per-model-family distillation (one per cc/cod/gmi) |
| [MO-06b-meta-synthesize.md](assets/marching-orders/MO-06b-meta-synthesize.md) | 6 | Reconcile distillations + register disagreements |
| [MO-07a-fresh-eyes.md](assets/marching-orders/MO-07a-fresh-eyes.md) | 7 | The verbatim trio of fresh-eyes prompts |
| [MO-08-freeze.md](assets/marching-orders/MO-08-freeze.md) | 8 | Write `RESUME.md`; commit; ntm checkpoint export |
| [MO-09-handback.md](assets/marching-orders/MO-09-handback.md) | 9 | Produce the one-page operator briefing |
| [MO-10-drift-check.md](assets/marching-orders/MO-10-drift-check.md) | 10 | Compare actual trajectory to canonical Brenner |
| [MO-cross-family-debate.md](assets/marching-orders/MO-cross-family-debate.md) | 4–5 | Force adversarial probing by a different model family (per Brenner-Crick GAN) |
| [MO-evidence-intake-url.md](assets/marching-orders/MO-evidence-intake-url.md) | any | Ingest a URL as EV with verification-first discipline |
| [MO-evidence-intake-pdf.md](assets/marching-orders/MO-evidence-intake-pdf.md) | any | Ingest a PDF as EV (page-anchor scheme, DOI annotation) |
| [MO-evidence-verify.md](assets/marching-orders/MO-evidence-verify.md) | 4 / 7 | Independent re-verification of an EV bead |
| [MO-academic-replication.md](assets/marching-orders/MO-academic-replication.md) | 4 | Replicate published results before citing as load-bearing EV (T4+) |
| [MO-pre-publication-review.md](assets/marching-orders/MO-pre-publication-review.md) | 7 | Adversarial pre-publication review for T4+ external deliverables |
| [MO-dual-use-review.md](assets/marching-orders/MO-dual-use-review.md) | 7 | Dual-use ethics review for sensitive outputs |
| [MO-post-mortem-formalization.md](assets/marching-orders/MO-post-mortem-formalization.md) | all | Deep post-mortem (5-whys, action items, cross-incident pattern detection) |
| [MO-cross-session-reconciliation.md](assets/marching-orders/MO-cross-session-reconciliation.md) | 0 / 10 | Reconcile two sessions on the same question that reach different verdicts |
| [MO-stress-test-self-check.md](assets/marching-orders/MO-stress-test-self-check.md) | 0 | Pre-flight self-check before T3+ session bootstrap |
| [MO-quickie-pilot.md](assets/marching-orders/MO-quickie-pilot.md) | 4 | Cheap ≤30-min probe before a flagship investigation; kill or strengthen H 5-10× cheaper |
| [MO-falsifier-fired.md](assets/marching-orders/MO-falsifier-fired.md) | 4 / 5 | When a falsifier-firing observation surfaces — the bead-update + cascade discipline |
| [MO-evidence-promote.md](assets/marching-orders/MO-evidence-promote.md) | 4 / 7 | Promote a low-confidence EV to high-confidence via axis-strengthening |
| [MO-anomaly-quarantine.md](assets/marching-orders/MO-anomaly-quarantine.md) | 4 / 7 | Quarantine anomalies without patching the theory (per Brenner §110) |
| [MO-stale-corpus-refresh.md](assets/marching-orders/MO-stale-corpus-refresh.md) | any | Refresh corpus when staleness detected; categorize impact |
| [MO-confidence-downgrade.md](assets/marching-orders/MO-confidence-downgrade.md) | 4 / 7 | Formal procedure to downgrade an H's confidence with audit trail |
| [MO-debate-deadlock-resolution.md](assets/marching-orders/MO-debate-deadlock-resolution.md) | 5 | When adversarial debate doesn't converge — diagnose D1-D6 and recover |
| [MO-deliverable-rejection.md](assets/marching-orders/MO-deliverable-rejection.md) | 9 | When HANDBACK fails sanity check (R1-R8) — reject, fix, re-produce |
| [MO-pane-respawn.md](assets/marching-orders/MO-pane-respawn.md) | any | Spawn fresh pane when one dies (rate-limit cliff, OAuth, context-saturation) |
| [MO-bead-linking.md](assets/marching-orders/MO-bead-linking.md) | 3 / 4 / 5 | Formalize description + `br dep` links between beads (cycle-safe) |

Plus operator-mode-flip templates (e.g., `MO-mode-flip-investigator-to-advocate.md`) and unstick-recovery templates (`MO-unstick-stuck-investigator.md`). Full library + parameter grammar + composition cheat sheet: [MARCHING-ORDERS.md](references/MARCHING-ORDERS.md).

---

## NTM Pipeline Definition (the canonical 5-role roster)

The standard squad roster ships as an ntm pipeline definition. To reuse:

```bash
ntm spawn RS-YYYYMMDD-slug --cc=3 --cod=1 --gmi=1
ntm pipeline run .ntm/pipelines/brennerbot-squad.yaml \
  --session RS-YYYYMMDD-slug \
  --var workspace_path=/abs/path/to/workspace \
  --var session_id=RS-YYYYMMDD-slug \
  --var question_of_record_path=intake/question_of_record.md \
  --var mode=corpus-distillation \
  --var model_mix=cc:3,cod:1,gmi:1 \
  --dry-run
```

Preflight with `--dry-run` before handing the session to the pipeline. `ntm pipeline run` expects the tmux session named by `--session` to already exist; for greenfield sessions, spawn the roster first and pass the same name as `--var session_id=...` because the command steps call helper scripts that inspect that live NTM session. These YAMLs require the schema-expanded ntm pipeline runner; older installed `ntm` builds reject fields such as `inputs`, `command`, `foreach_pane`, and `after`. If the dry-run fails on schema fields, build/upgrade `ntm` from the live `/dp/ntm` checkout. Manual `scripts/dispatch-marching-order.sh` fallback is only for that degraded run, not the normal workflow.

All six executable BrennerBot pipeline assets now run on current NTM; they are not documentation-only approximations. The May 2026 Phase-B push shipped runtime support for the orchestration primitives this methodology needs: `command:`, `template:`, `foreach:`, `foreach_pane:`, branch/control-flow, output parsing, Agent Mail pipeline steps, resume-safe foreach state, pane-assignment strategies, and structured step logs. `--dry-run` is still the first gate, but a clean dry-run should usually be followed by a real `ntm pipeline run` or `--robot-pipeline-run` instead of manual dispatch.

Manual `scripts/dispatch-marching-order.sh` remains useful for ad hoc interventions, Phase 1 framing, Phase 9 handback, Phase 10 drift-check, and recovery from an explicitly failed step. It is no longer the normal path for Phase 2-8 execution.

Pipeline file (template): [NTM-PIPELINES.md](references/NTM-PIPELINES.md) describes the canonical 5-role pipeline plus variants (`brennerbot-pair.yaml`, `brennerbot-swarm.yaml`, `brennerbot-resume.yaml`). The drop-in pipeline YAML lives at [`assets/ntm-pipelines/brennerbot-squad.yaml`](assets/ntm-pipelines/brennerbot-squad.yaml).

The pipeline orchestrates Phases 2 (bootstrap), 3 (propose+triage), 4 (investigate, with fan-out by hypothesis), 5 (debate pairs), 6 (per-model + meta), 7 (audit ×2), 8 (freeze). Phases 9–10 are operator-driven, not pipeline-driven. For incident mode, `brennerbot-incident.yaml` has an NTM E2E fixture proving command + foreach + template dispatch against mocked panes and an `INCIDENT-VERDICT.md` output.

When Agent Mail is unavailable, prefer fixing Agent Mail or using a read-only/preview mode. If the user explicitly accepts degraded coordination, use [`assets/ntm-pipelines/brennerbot-squad-no-mail.yaml`](assets/ntm-pipelines/brennerbot-squad-no-mail.yaml), which routes coordination through NTM pane messages + bead assignees and records the degraded source.

---

## Failure Table (the symptoms you'll actually see)

Compact lookup. Each failure code F-### is documented in full in [FAILURE-TABLE.md](references/FAILURE-TABLE.md) with diagnosis, recovery moves, and which `/vibing-with-ntm` operator card applies if the failure is a stuck-pane class.

| Code | Phase | Symptom | First-aid recovery move | Escalate to |
|------|-------|---------|-------------------------|-------------|
| F-101 | 1 | Question is too broad ("design the future of X") | Force user through `MO-01-frame-question.md` with `scope` and `out-of-scope` filled | abort + reframe |
| F-102 | 1 | Corpus drift mid-session | Pin corpus version with content-hash in `corpus/corpus_index.md` | flag in `RESUME.md` |
| F-103 | 1 | No falsifier specified | The bead is invalid; reject and re-propose | back to MO-01 |
| F-201 | 2 | Pane lands at zsh, no agent process | `/vibing-with-ntm` OC-026 pid audit + OC-027 two-step relaunch | `/vibing-with-ntm` |
| F-202 | 2 | Mail register times out | Fall back to `ntm-inbox` per [AGENT-MAIL-FALLBACKS.md](references/AGENT-MAIL-FALLBACKS.md); flag in scope_decision | `/agent-mail` |
| F-203 | 2 | Two panes claim same role | Adjudicator (Phase 5 rotation rule) reassigns | back to MO-02 |
| F-301 | 3 | Hypothesis slate has only 2 alternatives (false binary) | Dispatch `MO-03c-third-alternative.md` | mandatory; per Brenner §103 |
| F-302 | 3 | Two H-* beads describe the same hypothesis | Triage marks the duplicate `state: superseded`, adds `parent: H-NNN`, and links it to the canonical H with `br dep add <duplicate> <canonical>`; keep Beads status open until session closeout | re-run MO-03b |
| F-303 | 3 | Hypothesis with no `falsifier:` field | Bead validation rejects; pane must add or kill | back to MO-03a |
| F-401 | 4 | Evidence count grows but no `H-*` state changes | Apply ✂ Exclusion-Test operator to every EV; require each EV to either kill or strengthen | per OPERATORS.md |
| F-402 | 4 | Same evidence cited as both supporting and refuting | Adjudication thread; force the Investigator and Devil's-Advocate to agree on the *interpretation*; if they can't, log as `anomaly` | Phase 5 escalation |
| F-403 | 4 | All EVs support; none refute | The pane is in confirmation mode — flip them via `MO-mode-flip-investigator-to-advocate.md` | per OPERATORS.md |
| F-404 | 4 | Test missing potency check | Reject the test bead; require chastity-vs-impotence (§50) distinction | back to MO-04 |
| F-501 | 5 | Adjudicator never kills any H | Rotate adjudicator (per role rotation rule); apply † Theory-Kill operator | Phase 7 audit will catch this |
| F-502 | 5 | Adjudicator favors one model family's H | Triangulation: re-adjudicate via different model family pane | mandatory rotation |
| F-503 | 5 | Debate stuck on rhetoric, not evidence | Force structured-rounds template; reject responses without `EV-*` citations | back to MO-05a |
| F-601 | 6 | Distillations agree by averaging out disagreements | Disagreement register is empty → reject; mandate at least 1 explicit disagreement per pair of distillations | back to MO-06b |
| F-602 | 6 | Single model family's distillation dominates | Add explicit weight rule in `meta_synthesis.md`; if persistent, flag as drift in Phase 10 | Phase 10 |
| F-603 | 6 | `disagreement_register.md` missing | Mandatory artifact; Phase 6 cannot exit without it | back to MO-06b |
| F-701 | 7 | Audit accepts everything ("LGTM × 5") | Convergence-language false positive; verify with [`scripts/convergence-check.sh`](scripts/convergence-check.sh) before believing | per /vibing-with-ntm OC-016 |
| F-702 | 7 | Audit reopens settled questions on rhetoric | Audit findings must cite specific `EV-*` or `H-*`, not vibes; reject vibes-only audits | back to MO-07 |
| F-703 | 7 | `ubs` warnings on code in `deliverables/scripts/` ignored | Hard-block Phase 8 freeze until clean | use `/ubs` |
| F-801 | 8 | `RESUME.md` missing required tokens | Refuse to commit; the resume token grammar is non-optional | per [RESUME-PROTOCOL.md](references/RESUME-PROTOCOL.md) |
| F-802 | 8 | Beads drift between `.beads/` and JSONL | `br sync --flush-only`; resolve via `/fixing-beads-problems` | `/fixing-beads-problems` |
| F-803 | 8 | ntm checkpoint missing per-pane state | Re-run `ntm checkpoint save <session>`; verify with `ntm checkpoint show <session> <id>` | per [DURABILITY.md](../ntm/references/DURABILITY.md) in /ntm |
| F-901 | 9 | Handback exceeds 1 page | Compress; the value of a one-pager is one page | reject and re-summarize |
| F-902 | 9 | Unresolved-thread tags missing | Every unresolved `H-*` and `EV-*` listed in "What's still open" MUST have `next-action:` | reject |
| F-1001 | 10 | Drift check rationalizes drift as improvement | Force the rubric: only "improvement" if a Brenner principle was *replaced* by something measurably stronger | per [DRIFT-RUBRIC.md](references/DRIFT-RUBRIC.md) |
| F-1002 | 10 | Missing baseline anchor | Cite specific Brenner operators / §-anchors that were skipped | mandatory |
| F-1003 | 10 | Lessons not fed back into `references/` | Phase 10 not done until at least one ref file is updated or one new entry added to `OPERATORS.md` | back to MO-10 |

Use the failure table as a tick lookup. When in doubt, escalate to `/vibing-with-ntm` for any pane-state or coordination class failure — that skill is the operator-loop reference for stuck panes.

---

## Convergence & Resumability

### Convergence (when to stop a phase)

**Phase 4 (investigation) convergence:** The round's `kill_rate ≥ add_rate` for hypotheses, AND every active hypothesis has at least one EV in support AND one EV that *survived an attack*. Quantitatively: this is the same kill-vs-add criterion brenner_bot's `session robot` mode uses. See [CONVERGENCE.md](references/CONVERGENCE.md) for the exact formula and the [`scripts/convergence-check.sh`](scripts/convergence-check.sh) helper that computes it.

**Phase 6 (synthesis) convergence:** Two consecutive meta-synthesis passes produce only trivial edits (typo-level), AND the disagreement register has stabilized (no new entries in last pass).

**Phase 7 (audit) convergence:** Two consecutive trio-rounds (each pane runs all three fresh-eyes prompts) produce only trivial edits.

**Whole-session convergence (when to stop tending):** All of:
1. Phase 7 audit converged twice clean.
2. `git log --since="1 hour ago"` shows zero swarm commits AND no new beads in last 2 ticks AND every pane's tail contains convergence language.
3. `br ready --json` returns 0 items AND `br list --status=in_progress --json` is empty or unchanged.

When all three hold, **stop tending and run Phase 8 freeze.** Don't keep nudging — that produces prose, not knowledge. Same termination logic as `/vibing-with-ntm` OC-016.

### Resumability (the RESUME.md token)

`RESUME.md` is the single source of truth for resuming a session. Every session must produce one in Phase 8. Schema (see [RESUME-PROTOCOL.md](references/RESUME-PROTOCOL.md) for full grammar):

```yaml
session_id: RS-<YYYYMMDD>-<slug>
mode_to_resume: <fresh-pass | targeted-investigation | distillation-only | drift-check | audit-only>
last_phase_completed: <int 1-10>
question_of_record_hash: sha256(intake/question_of_record.md)
roster:
  - pane: 1
    role: proposer
    model: cc
    last_thread: RS-...-H-001
  - pane: 2
    ...
ntm_checkpoint: .ntm/checkpoints/<id>.tar.gz
beads_head: <git sha of last commit touching .beads/>
agent_mail_threads:
  - RS-...-H-001
  - RS-...-DEBATE-H1-vs-H2
open_threads:
  - id: RS-...-H-005
    next_action: "investigate counter-evidence claimed in EV-014"
disagreement_register_hash: sha256(distillations/disagreement_register.md)
```

To resume: `./scripts/resume-session.sh --resume <workspace>/deliverables/RESUME.md`. The script verifies hashes, restores `ntm checkpoint`, re-attaches Agent Mail threads, and dispatches `MO-resume.md` to each pane. Full resume protocol: [RESUME-PROTOCOL.md](references/RESUME-PROTOCOL.md).

---

## Anti-Patterns (Never Do)

| ✗ | Why | Fix |
|---|-----|-----|
| Frame the question without a falsifier | A question without a falsifier is a mood, not research (per Brenner §147 + Axiom 2) | MO-01 mandatory `falsifier:` field |
| Generate hypotheses without the third-alternative guard | Per §103 ("both could be wrong") false-binary defaults are the most common methodological failure | MO-03c is mandatory; Phase 3 cannot exit without an `origin:third_alternative` bead |
| Investigators only file confirming evidence | Per §147 ("exclusion is always a tremendously good thing") confirmation-only is anti-Brenner | Phase 4 mandates ≥1 attempted falsifier per H per round; F-403 catches it |
| Synthesize by averaging the model-family distillations | Defeats the *point* of triangulation; you want disagreement, not consensus | MO-06b mandates `disagreement_register.md` |
| Adjudicator decides debates on rhetoric | Per Brenner's "seven-cycle log paper" §62 — only the signal-vs-noise call counts | F-503 fix: structured rounds + `EV-*` citations required |
| Run Phase 7 audit on the same model family that did Phase 6 | Loses the cross-model fresh-eyes value | Mandatory model-family rotation between 6 and 7 |
| Skip Phase 8 freeze | The session is not done until it's resumable | Pre-flight checklist requires `RESUME.md` + clean `git status` |
| Rationalize methodology drift as improvement | The drift check exists *because* drift looks like improvement from the inside | DRIFT-RUBRIC.md requires citing the replaced Brenner operator |
| Block on "perfect" corpus before starting | Brenner's anti-overpreparation principle (§65 — "the best thing is just to start") | Allow Phase 4 to surface corpus gaps; ingest more in next round |
| Treat anomalies as patches to the main theory | §110 exception-quarantine — anomalies go in `anomaly_register`, not into the theory | Phase 4 + 7 audit catches |
| Use a single pane (cc-only) for triangulation | One model family produces one set of blind spots; the *whole point* of multi-model is to surface them | Mandatory ≥2 model families for Phase 6 (skill exits with warning if Solo or Pair tier produces only one distillation) |
| Use `ntm view` from a marching order | Retiles the operator's tmux layout; never call from automation (per `/ntm` gotchas) | Use `ntm --robot-tail=<session>` instead |
| Edit `.beads/*.jsonl` directly | Per `/beads-br` rules — only via `br` | If you see drift, escalate to `/fixing-beads-problems` |
| Allow new review-bead creation when backlog > 100 | Per `/vibing-with-ntm` review-bead inflation anti-pattern | Switch to close-the-backlog rotation |
| Run hard-deletes (`rm -rf`, `git reset --hard`) on the workspace | Per AGENTS.md RULE 1 + IRREVERSIBLE GIT rules | Always ask explicit user permission |

Full anti-pattern catalog with the bead-trail / failure-code / operator-card mapping for each: [ANTI-PATTERNS.md](references/ANTI-PATTERNS.md).

---

## Pre-Flight & End Checklist

Before declaring the session complete, verify:

- [ ] Workspace path confirmed; `git init` done; mode + roster + model mix recorded in `phase0_scope_decision.md`
- [ ] `phase0_skill_inventory.json` shows referenced helper skills (or noted as missing+fallback)
- [ ] `intake/question_of_record.md` exists and has non-empty `falsifier:` field
- [ ] `corpus/corpus_index.md` has ≥1 row; corpus content-hashes recorded
- [ ] `Q-001` bead created and closed at end of Phase 1
- [ ] Phase 2 onboarding mail acked by every pane (`ntm mail inbox <session> --json`)
- [ ] Phase 3 hypothesis slate has ≥3 distinct hypotheses including ≥1 `origin:third_alternative`
- [ ] Phase 4 ran until kill_rate ≥ add_rate AND every active H has ≥1 supporting EV that survived attack
- [ ] Phase 5 every active H survived ≥1 adversarial debate with rebuttals on record
- [ ] Phase 6 distillations exist per model family + `meta_synthesis.md` + non-empty `disagreement_register.md`
- [ ] Phase 7 fresh-eyes ran ≥2 trio-rounds clean; `ubs` clean on any code/scripts in deliverables
- [ ] Phase 8 `RESUME.md` exists with all required tokens; `git status` clean; `br sync --flush-only` clean; `ntm checkpoint` exported
- [ ] Phase 9 `HANDBACK.md` ≤1 page; every unresolved `H-*`/`EV-*` listed in "What's still open" has a `next-action:` field
- [ ] Phase 10 `DRIFT-CHECK.md` cites specific Brenner operators that were applied/skipped/replaced; ≥1 ref file updated or new operator entry added

Run [`scripts/dump-session-report.sh`](scripts/dump-session-report.sh) to produce the structured pass/fail summary.

---

## Reference Index

### Methodology
| Need | File |
|------|------|
| Triangulated Brenner kernel + axiom-by-axiom evidence trace | [KERNEL.md](references/KERNEL.md) |
| Track A source corpus + quote bank + provenance | [SOURCE-CORPUS.md](references/SOURCE-CORPUS.md) |
| Where the three distillations disagree + chosen synthesis | [DISAGREEMENT-REGISTER-OF-DISTILLATIONS.md](references/DISAGREEMENT-REGISTER-OF-DISTILLATIONS.md) |
| 15 cognitive operators × {trigger, recipe, marching-order module, validator, failure mode} | [OPERATORS.md](references/OPERATORS.md) |
| Mode definitions + exit criteria + required artifacts | [OPERATING-MODES.md](references/OPERATING-MODES.md) |
| Niche / advanced operating modes (academic-replication, peer-review, hypothesis-pre-registration, meta-analysis, living-review, etc) | [EXTENDED-OPERATING-MODES.md](references/EXTENDED-OPERATING-MODES.md) |
| Tier triage T1-T5 (curiosity → existential) | [TIER-TRIAGE.md](references/TIER-TRIAGE.md) |
| Wall-time budgets per tier × phase | [WALL-TIME-BUDGET.md](references/WALL-TIME-BUDGET.md) |
| Per-phase playbook with exact prompts + exit gates | [PHASES.md](references/PHASES.md) |
| Marching-orders library — every template with parameter grammar | [MARCHING-ORDERS.md](references/MARCHING-ORDERS.md) |
| Verbatim per-mode kickoff prompts | [KICKOFF-PROMPTS.md](references/KICKOFF-PROMPTS.md) |
| Operator-side prompt library (self-prompts, escalations, user updates) | [PROMPTS.md](references/PROMPTS.md) |
| Roster plans by tier (Solo/Pair/Squad/Swarm) + role rotation rules | [ROSTER-PLANS.md](references/ROSTER-PLANS.md) |
| Question archetypes (A1-A10) — methodology tuning per question shape | [QUESTION-ARCHETYPES.md](references/QUESTION-ARCHETYPES.md) |
| Archetype start-packs — fast-start configurations | [ARCHETYPE-START-PACKS.md](references/ARCHETYPE-START-PACKS.md) |
| Research domain adjustments (backend, biology, social science, etc) | [EXTENDED-PROJECT-TYPES.md](references/EXTENDED-PROJECT-TYPES.md) |
| Worked case studies per archetype | [CASE-STUDIES.md](references/CASE-STUDIES.md) |
| Workspace layout discipline | [WORKSPACE-LAYOUT.md](references/WORKSPACE-LAYOUT.md) |
| Corpus authoring + maintenance methodology | [CORPUS-CURATION.md](references/CORPUS-CURATION.md) |
| Question-of-record framing template | [QUESTION-OF-RECORD-TEMPLATE.md](references/QUESTION-OF-RECORD-TEMPLATE.md) |
| Convergence formulas (kill-rate vs add-rate, audit clean rounds) | [CONVERGENCE.md](references/CONVERGENCE.md) |
| Measurable session quality metrics | [METRICS.md](references/METRICS.md) |
| Confidence scoring rubric across hypotheses, evidence, distillations | [CONFIDENCE-SCORING.md](references/CONFIDENCE-SCORING.md) |
| Multi-model triangulation harness | [TRIANGULATION.md](references/TRIANGULATION.md) |
| cass mining recipes (per failure class, per archetype) | [CASS-MINING-RECIPES.md](references/CASS-MINING-RECIPES.md) |
| Live-source verification discipline | [VERIFICATION-FIRST.md](references/VERIFICATION-FIRST.md) |
| Cross-session learning + lesson commitment protocol | [CROSS-SESSION-LEARNING.md](references/CROSS-SESSION-LEARNING.md) |
| Cross-session drift rollup consumed by `scripts/drift-trend.sh` | [CROSS-SESSION-DRIFT-CATALOG.md](references/CROSS-SESSION-DRIFT-CATALOG.md) |
| Resume protocol — RESUME.md grammar + verification | [RESUME-PROTOCOL.md](references/RESUME-PROTOCOL.md) |
| Drift check rubric (canonical Brenner vs actual trajectory) | [DRIFT-RUBRIC.md](references/DRIFT-RUBRIC.md) |
| Failure-code catalog (F-101..F-1003) with diagnosis + recovery | [FAILURE-TABLE.md](references/FAILURE-TABLE.md) |
| Niche failure modes beyond the main table (F-2xx..F-CX5) | [EXTENDED-FAILURE-CATALOG.md](references/EXTENDED-FAILURE-CATALOG.md) |
| Anti-pattern catalog | [ANTI-PATTERNS.md](references/ANTI-PATTERNS.md) |
| What to watch during a session (signal catalog + cadence) | [OBSERVABILITY.md](references/OBSERVABILITY.md) |
| How the methodology pieces integrate (data flow + composition) | [METHODOLOGY-INTEGRATION.md](references/METHODOLOGY-INTEGRATION.md) |
| Quote bank from world-class research-method writeups (Watson-Crick, Dijkstra, Popper, etc) | [EXEMPLARS.md](references/EXEMPLARS.md) |
| Architecture Decision Records (T4+ load-bearing decisions) | [ADR-PATTERNS.md](references/ADR-PATTERNS.md) |
| Optional Claude Code hooks for automation | [HOOKS-INTEGRATION.md](references/HOOKS-INTEGRATION.md) |
| Inline fallbacks for missing helper skills | [SKILL-FALLBACKS.md](references/SKILL-FALLBACKS.md) |
| Methodology resilience tests (S1-S15 stress-test scenarios) | [STRESS-TEST-SCENARIOS.md](references/STRESS-TEST-SCENARIOS.md) |
| Adaptive Phase 1 question-of-record framing (F1-F9) | [FRAMING-WORKBOOK.md](references/FRAMING-WORKBOOK.md) |
| Six-layer pre-Phase-8 validation regime | [SIX-LAYER-VALIDATION.md](references/SIX-LAYER-VALIDATION.md) |
| Operator cards — narrow trigger/recipe/validator for tick-time decisions (OC-001..031) | [OPERATOR-CARDS.md](references/OPERATOR-CARDS.md) |
| How to write good critiques (specificity, severity, GAN voice) | [CRITIQUE-CRAFT.md](references/CRITIQUE-CRAFT.md) |
| Composing brennerbot with adjacent skills (codebase-archaeology, multi-pass-bug-hunting, etc) | [SKILL-COMPOSITION-PATTERNS.md](references/SKILL-COMPOSITION-PATTERNS.md) |
| Deep post-mortem playbook (5-whys, action items, cross-incident pattern detection) | [POST-MORTEM-FORMALIZATION-PLAYBOOK.md](references/POST-MORTEM-FORMALIZATION-PLAYBOOK.md) |
| Promoted cross-incident patterns shared across post-mortem sessions | [INCIDENT-PATTERN-CATALOG.md](references/INCIDENT-PATTERN-CATALOG.md) |
| Reconciling cross-session conflicts (Type 1-4 reconciliation) | [RECONCILIATION-OF-PRIOR-SESSIONS.md](references/RECONCILIATION-OF-PRIOR-SESSIONS.md) |
| Promoted cross-session reconciliation patterns and resolution rules | [RECONCILIATION-CATALOG.md](references/RECONCILIATION-CATALOG.md) |
| Research-session-specific NTM tactics (pane affinity, robot-mode, account rotation) | [NTM-PATTERNS-DEEP.md](references/NTM-PATTERNS-DEEP.md) |
| New-operator onboarding curriculum (Weeks 1-4, trust ladder, buddy system) | [OPERATOR-ONBOARDING-CURRICULUM.md](references/OPERATOR-ONBOARDING-CURRICULUM.md) |
| Per-question-shape recipe library (R1-R15 cookbook) | [DOMAIN-RECIPE-LIBRARY.md](references/DOMAIN-RECIPE-LIBRARY.md) |
| 5-axis evidence weighting taxonomy (W_source, W_verification, W_independence, W_recency, W_domain_fit) | [EVIDENCE-WEIGHTING-TAXONOMY.md](references/EVIDENCE-WEIGHTING-TAXONOMY.md) |
| Concrete Phase 1 framing failures with diagnoses (AE-1.1..AE-1.10) | [PHASE-1-ANTI-EXAMPLES.md](references/PHASE-1-ANTI-EXAMPLES.md) |
| Concrete Phase 7 audit failures with diagnoses (AE-7.1..AE-7.10) | [PHASE-7-ANTI-EXAMPLES.md](references/PHASE-7-ANTI-EXAMPLES.md) |
| Reusable operator-to-user prompts for framing, mid-session, handback (P1.1-P7.5) | [OPERATOR-PROMPT-LIBRARY.md](references/OPERATOR-PROMPT-LIBRARY.md) |
| Voice / structure / tightening rules for the one-page HANDBACK | [HANDBACK-VOICE-GUIDE.md](references/HANDBACK-VOICE-GUIDE.md) |
| Cost-aware execution (token + quota + wall-time + attention envelopes) | [COST-AWARE-EXECUTION.md](references/COST-AWARE-EXECUTION.md) |
| Crick-Brenner GAN mechanics (generator/discriminator across model families) | [BRENNER-GAN-MECHANICS.md](references/BRENNER-GAN-MECHANICS.md) |
| Track-A quote-bank methodology (corpus → quotes → kernel → operators → validators) | [QUOTE-BANK-METHODOLOGY.md](references/QUOTE-BANK-METHODOLOGY.md) |
| Agent-ergonomic skill design decisions (per /sw guidance) | [AGENT-ERGONOMICS-FOR-OPERATORS.md](references/AGENT-ERGONOMICS-FOR-OPERATORS.md) |
| Long-running living-review patterns (cadence, drift handling, promotion) | [LIVING-DOCUMENTATION-PATTERNS.md](references/LIVING-DOCUMENTATION-PATTERNS.md) |
| Operator algebra: composing the 15 cognitive operators in canonical chains | [OPERATOR-LIBRARY-COMPOSITION.md](references/OPERATOR-LIBRARY-COMPOSITION.md) |
| Designing mechanizable validators (V1-V5 types, per-operator + per-phase) | [VALIDATOR-DESIGN-PATTERNS.md](references/VALIDATOR-DESIGN-PATTERNS.md) |
| Concrete Phase 1→10 walkthrough of a real T3 session (~6h, with timing + dispatches) | [EXEMPLAR-SESSION-WALKTHROUGH.md](references/EXEMPLAR-SESSION-WALKTHROUGH.md) |
| Operator's first 90 seconds: per-mode flows + common mistakes | [FIRST-90-SECONDS.md](references/FIRST-90-SECONDS.md) |
| Concrete `br` commands per phase, copy-paste-ready | [BEADS-WORKFLOW-CHEATSHEET.md](references/BEADS-WORKFLOW-CHEATSHEET.md) |
| Inter-pane deadlocks specific to brennerbot (DL-1..DL-10 with detection + recovery) | [DEADLOCK-PATTERNS-MULTI-PANE.md](references/DEADLOCK-PATTERNS-MULTI-PANE.md) |
| Doctor rubric: 7-pillar workspace health check for inherited / mid-flight workspaces | [BRENNERBOT-DOCTOR-RUBRIC.md](references/BRENNERBOT-DOCTOR-RUBRIC.md) |
| Script + MO ergonomics for pane consumers (per /agent-ergonomics-cli) | [AGENT-API-DESIGN-FOR-INVESTIGATORS.md](references/AGENT-API-DESIGN-FOR-INVESTIGATORS.md) |
| Operator's own context budget — Stage 1-4 drift, compaction, handoff | [CONTEXT-MANAGEMENT-LONG-SESSIONS.md](references/CONTEXT-MANAGEMENT-LONG-SESSIONS.md) |
| Meta: how brennerbot itself operationalizes Track-A (per /operationalizing-expertise) | [SKILL-AS-METHODOLOGY-PATTERN.md](references/SKILL-AS-METHODOLOGY-PATTERN.md) |
| Running 10+ sessions/week — operational patterns, quota fleet, methodology evolution | [BRENNERBOT-AT-SCALE.md](references/BRENNERBOT-AT-SCALE.md) |
| Methodology evolution log — quarterly schema for tracking skill changes (written by `subagents/methodology-historian.md`) | [METHODOLOGY-EVOLUTION-LOG.md](references/METHODOLOGY-EVOLUTION-LOG.md) |
| Brenner method's specific vocabulary — ~25 terms (Don't Worry, digital handle, anti-analogy, etc.) for cross-pane compression | [BRENNER-VOCABULARY.md](references/BRENNER-VOCABULARY.md) |
| Compact summary of Brenner's Ten Principles + per-principle anti-patterns + operator mapping | [TEN-PRINCIPLES.md](references/TEN-PRINCIPLES.md) |
| The six required oscillations (Imagination↔Focus, Passion↔Ruthlessness, etc) — meta-discipline for the operator | [REQUIRED-CONTRADICTIONS.md](references/REQUIRED-CONTRADICTIONS.md) |
| Brenner's implicit Bayesianism — formal Brenner-to-Bayes mapping + objective function + posterior update math | [BAYESIAN-FRAMEWORK.md](references/BAYESIAN-FRAMEWORK.md) |
| The canonical 7-section research artifact (Research Thread, Hypothesis Slate, Predictions, Tests, Assumptions, Anomalies, Critique) | [ARTIFACT-7-SECTION-SCHEMA.md](references/ARTIFACT-7-SECTION-SCHEMA.md) |
| 50+ machine-checkable lint rules for the 7-section artifact (severity E/W/I, section codes M/S/R/H/P/T/A/X/C) | [ARTIFACT-LINTER-RULES.md](references/ARTIFACT-LINTER-RULES.md) |
| 7-step discriminative-test design protocol with KL-divergence ranking + cost-benefit | [DISCRIMINATIVE-TEST-DESIGN.md](references/DISCRIMINATIVE-TEST-DESIGN.md) |
| Anti-analogy + plausibility-filter discipline — preempt bad investigations before Phase 4 | [ANTI-ANALOGY-AND-PLAUSIBILITY.md](references/ANTI-ANALOGY-AND-PLAUSIBILITY.md) |
| 30-90 min compressed Brenner loop (6-step protocol) for non-incident small questions | [QUICK-LOOP-MODE.md](references/QUICK-LOOP-MODE.md) |
| Per-operator calibration tracking — quarterly metrics, coaching triggers, log schema | [OPERATOR-CALIBRATION-LOG.md](references/OPERATOR-CALIBRATION-LOG.md) |
| The 9-state hypothesis lifecycle FSM (draft / proposed / active / under_attack / assumption_undermined / refined / dormant / killed / validated) with valid transitions, side effects, state invariants | [HYPOTHESIS-LIFECYCLE-STATE-MACHINE.md](references/HYPOTHESIS-LIFECYCLE-STATE-MACHINE.md) |
| Tribunal + objection register — adversarial review as hard gate; severity calibration; action taxonomy; block-until-clean Phase 8 | [TRIBUNAL-AND-OBJECTION-REGISTER.md](references/TRIBUNAL-AND-OBJECTION-REGISTER.md) |
| Delta protocol fail-fast contract — fenced JSON blocks, inline-delta failure mode, lenient parser tolerance, conflict resolution | [DELTA-PROTOCOL-FAIL-FAST.md](references/DELTA-PROTOCOL-FAIL-FAST.md) |
| Evidence pack protocol with EV-NNN#E&lt;n&gt; anchor scheme — excerpt-first, supports/refutes graph, cross-session reuse | [EVIDENCE-PACK-PROTOCOL.md](references/EVIDENCE-PACK-PROTOCOL.md) |
| Citation provenance taxonomy — 6 categories, 10+ anchor formats, fake-anchor disqualifier, inference vs verbatim discipline | [CITATION-PROVENANCE-RULES.md](references/CITATION-PROVENANCE-RULES.md) |
| Per-role 14-criterion evaluation rubric with multipliers + 7-dimension session score + pass/fail gates | [EVALUATION-RUBRIC-14-CRITERIA.md](references/EVALUATION-RUBRIC-14-CRITERIA.md) |
| Session replay + reproducibility — NTM causality/events/pipeline state, SessionRecord schema, content hashing, replay modes, reproducibility tarball | [SESSION-REPLAY-AND-REPRODUCIBILITY.md](references/SESSION-REPLAY-AND-REPRODUCIBILITY.md) |
| Robot mode — NTM-native attention loop, pipeline autonomy, HITL gates, health escalation, stress rounds, convergence detection | [ROBOT-MODE-AUTONOMOUS-ORCHESTRATION.md](references/ROBOT-MODE-AUTONOMOUS-ORCHESTRATION.md) |
| Counterfactual exploration — 4 types (hypothesis / assumption / evidence / framing), brittleness scoring, counterfactual_register section | [WHAT-IF-COUNTERFACTUAL-EXPLORER.md](references/WHAT-IF-COUNTERFACTUAL-EXPLORER.md) |
| Hypothesis similarity + cross-session quote matching — vector embeddings, semantic-quote sidebar pattern, auto-reconciliation triggers | [HYPOTHESIS-SIMILARITY-AND-CROSS-SESSION-SEARCH.md](references/HYPOTHESIS-SIMILARITY-AND-CROSS-SESSION-SEARCH.md) |
| Failure-mode analytics — 5 outcome categories, 10-pattern catalog (P-1..P-10), cross-session pattern detection, calibration coupling | [FAILURE-MODE-ANALYTICS.md](references/FAILURE-MODE-ANALYTICS.md) |
| Research programs — multi-session aggregation, hypothesis funnel, registry health, timeline events, lifecycle (active/paused/completed/abandoned) | [RESEARCH-PROGRAMS.md](references/RESEARCH-PROGRAMS.md) |
| Architectural design principles — CLI-First, Deterministic Merging, Fail-Closed Security, No-Mocks Testing | [DESIGN-PRINCIPLES-CLI-FIRST.md](references/DESIGN-PRINCIPLES-CLI-FIRST.md) |
| Pilot retrospective protocol — 4-section format (worked/failed/changes/discovered-beads), cross-pilot pattern detection, quarterly rollup | [PILOT-RETROSPECTIVE-PROTOCOL.md](references/PILOT-RETROSPECTIVE-PROTOCOL.md) |
| Cryptographic prediction lock — SHA-256 sealed pre-registration; 4 lock states (draft/locked/revealed/amended); 5 prediction types; integrity score + robustness multiplier | [PREDICTION-LOCK-CRYPTOGRAPHIC.md](references/PREDICTION-LOCK-CRYPTOGRAPHIC.md) |
| Hypothesis arena + boldness scoring — competitive head-to-head testing; 4 boldness tiers (vague=1.0× / specific=1.5× / precise=2.0× / surprising=3.0×); discriminative-power-per-test | [HYPOTHESIS-ARENA-AND-BOLDNESS-SCORING.md](references/HYPOTHESIS-ARENA-AND-BOLDNESS-SCORING.md) |
| Multi-agent tribunal personas — 4 personas (Devil's Advocate / Experiment Designer / Brenner Channeler / Synthesis) with tone calibration across 4 dimensions, invocation triggers, phase-grouped activation | [MULTI-AGENT-TRIBUNAL-PERSONAS.md](references/MULTI-AGENT-TRIBUNAL-PERSONAS.md) |
| Operator intervention recording — 6 intervention types, 4 severity levels, audit schema, replay handling | [OPERATOR-INTERVENTION-RECORDING.md](references/OPERATOR-INTERVENTION-RECORDING.md) |
| Complete bead-attribute taxonomy catalog — every enum across H/T/A/X/C/EV/P/INT/Persona/Provenance + ID prefix lookup table | [TAXONOMIES-COMPLETE-CATALOG.md](references/TAXONOMIES-COMPLETE-CATALOG.md) |
| Three-distillations crosswalk — Opus / GPT / Gemini renderings, invariants, unique contributions, how to use them together | [THREE-DISTILLATIONS-CROSSWALK.md](references/THREE-DISTILLATIONS-CROSSWALK.md) |
| Agent roster + presets — explicit role-mapping (no string-match heuristics); roster modes (role_separated / unified); 3 edge-case rules; preset library | [AGENT-ROSTER-AND-PRESETS.md](references/AGENT-ROSTER-AND-PRESETS.md) |
| Message body schema per type — 10 subject prefixes (KICKOFF / DELTA[role] / COMPILED / CRITIQUE / ACK / CLAIM / HANDOFF / BLOCKED / QUESTION / INFO) + ACK semantics | [MESSAGE-BODY-SCHEMA-PER-TYPE.md](references/MESSAGE-BODY-SCHEMA-PER-TYPE.md) |
| Jargon dictionary — 100+ terms across 6 categories, progressive disclosure (short / long / analogy / why), tooltip + glossary patterns | [JARGON-DICTIONARY-PROGRESSIVE-DISCLOSURE.md](references/JARGON-DICTIONARY-PROGRESSIVE-DISCLOSURE.md) |
| Test execution + binding workflow — 5 test states, execute → bind (matched/violated/uncalled) → suggest-kills, mandatory potency-check | [TEST-EXECUTION-AND-BINDING.md](references/TEST-EXECUTION-AND-BINDING.md) |
| Lab-mode authorization — 4-layer defense-in-depth, fail-closed env gate, Cloudflare Access OR shared secret, timing-safe HMAC, 404-not-401 information hiding | [LAB-MODE-AUTHORIZATION.md](references/LAB-MODE-AUTHORIZATION.md) |
| Experiment capture + result encoding — run/record/encode/post pipeline, ExperimentResult schema, default output paths, threat model | [EXPERIMENT-CAPTURE-AND-RESULT-ENCODING.md](references/EXPERIMENT-CAPTURE-AND-RESULT-ENCODING.md) |
| Domain-aware confound detection — 5 universal confound classes + per-archetype libraries, detection signals, confound-as-critique pattern | [DOMAIN-AWARE-CONFOUND-DETECTION.md](references/DOMAIN-AWARE-CONFOUND-DETECTION.md) |
| Excerpt format + corpus workflow — search CLI, building strategies (operator-driven / domain-driven / section-driven), per-operator canonical anchors | [EXCERPT-FORMAT-AND-CORPUS-WORKFLOW.md](references/EXCERPT-FORMAT-AND-CORPUS-WORKFLOW.md) |
| Coach mode — progressive scaffolding for new operators; 3 coaching levels (beginner/intermediate/advanced), auto-promotion criteria, quality checkpoints, learn-by-doing inversion | [COACH-MODE-GUIDED-LEARNING.md](references/COACH-MODE-GUIDED-LEARNING.md) |
| Parser robustness — lenient-but-not-silent invariant; tolerated variations (target_id in ADD; field aliases); strict failures (missing fence, missing target_id for EDIT) | [PARSER-ROBUSTNESS-AND-LENIENT-TOLERANCE.md](references/PARSER-ROBUSTNESS-AND-LENIENT-TOLERANCE.md) |
| Sharpening + revision editors — sharpen (intent unchanged; tighter expression) vs revise (intent changed; new H lineage); per-target editor patterns; versioning + history preservation | [SHARPENING-AND-REVISION-EDITORS.md](references/SHARPENING-AND-REVISION-EDITORS.md) |
| Session + domain templates — reusable bootstrap configuration; SessionTemplate + DomainTemplate composition; per-archetype canonical templates; template-version contract | [SESSION-AND-DOMAIN-TEMPLATES.md](references/SESSION-AND-DOMAIN-TEMPLATES.md) |
| Storage performance at scale — incremental index updates (O(1) per save); cross-process file locking; compound + simple ID formats; fast-path deletion | [STORAGE-PERFORMANCE-AT-SCALE.md](references/STORAGE-PERFORMANCE-AT-SCALE.md) |
| API security command whitelist — strict whitelist for experiment execution; path-injection prevention (reject `/` and `\`); HMAC-normalized timing-safe comparison; rate limiting via X-Real-IP | [API-SECURITY-COMMAND-WHITELIST.md](references/API-SECURITY-COMMAND-WHITELIST.md) |
| The limits of Brenner method — 8 limits (no falsifier; subjective; ultra-rapid; data-poor; unbounded space; values; meaning; triangulation noise) and what to use instead | [THE-LIMITS-OF-BRENNER-METHOD.md](references/THE-LIMITS-OF-BRENNER-METHOD.md) |
| Group cognition patterns from multi-pane — 5 emergent patterns (oscillation, role-emergent specialization, convergence cascades, info-bottleneck, meta-pane self-correction); implications for human teams + AI ensembles | [GROUP-COGNITION-PATTERNS-FROM-MULTI-PANE.md](references/GROUP-COGNITION-PATTERNS-FROM-MULTI-PANE.md) |
| Post-brennerbot methodologies — 5 emerging directions (continuous research; federated multi-org; methodology-of-methodology; hybrid human-AI at scale; cross-domain export); capability gaps | [POST-BRENNERBOT-METHODOLOGIES.md](references/POST-BRENNERBOT-METHODOLOGIES.md) |
| The operator as researcher of researchers — meta-cognitive discipline; 4 disciplines (calibration tracking, bias surfacing, intensity choice, stepping back); the genius-mode trap | [THE-OPERATOR-AS-RESEARCHER-OF-RESEARCHERS.md](references/THE-OPERATOR-AS-RESEARCHER-OF-RESEARCHERS.md) |

### Schemas & Conventions
| Need | File |
|------|------|
| Beads label/field schema for hypothesis/evidence/test/etc | [BEADS-SCHEMA.md](references/BEADS-SCHEMA.md) |
| Agent Mail thread conventions | [AGENT-MAIL-CONVENTIONS.md](references/AGENT-MAIL-CONVENTIONS.md) |
| Agent Mail fallback (ntm-inbox + bead assignees) | [AGENT-MAIL-FALLBACKS.md](references/AGENT-MAIL-FALLBACKS.md) |
| ntm pipeline definitions for canonical 5-role roster + variants | [NTM-PIPELINES.md](references/NTM-PIPELINES.md) |

---

## Scripts

| Script | Purpose |
|--------|---------|
| `scripts/check-skills.sh` | Inventory which referenced helper skills are installed; emit JSON for `phase0_skill_inventory.json` |
| `scripts/install-referenced-skills.sh` | Bulk-install missing skills via `jsm` |
| `scripts/bootstrap-session.sh` | Idempotent workspace + beads + ntm + Agent Mail bootstrap (Phase 0.5) |
| `scripts/resume-session.sh` | Resume from `RESUME.md` — verify hashes, restore checkpoint, re-attach mail threads |
| `scripts/parse-resume.sh` | Parse RESUME.md into JSON for downstream pipeline use |
| `scripts/log-resume.sh` | Append a resume event to session-logs/ |
| `scripts/dump-session-report.sh` | Phase-by-phase pass/fail + unresolved-thread inventory; emit RESUME.md draft |
| `scripts/tick.sh` | One-tick orchestrator snapshot (every 10–17 min during Phases 4–7) |
| `scripts/liveness-check.sh` | Apply Liveness Truth Stack — check if swarm is "actually live" |
| `scripts/red-flag-scan.sh` | Scan pane tails for red-flag phrases per SKILL.md table |
| `scripts/emit-quickref.sh` | One-screen health dashboard per METRICS.md |
| `scripts/phase-readiness.sh` | Check phase exit-gate criteria — am I ready to exit phase X? |
| `scripts/convergence-check.sh` | Compute kill_rate vs add_rate; report Phase 4/6/7 convergence status |
| `scripts/dispatch-marching-order.sh` | Render an `MO-*.md` template with placeholders + dispatch via `ntm --robot-send` |
| `scripts/audit-bead-invariants.sh` | Verify mandatory invariants (every H has falsifier, every refuted H has `refuted_by`, etc.) |
| `scripts/render-evidence-pack.sh` | Render `evidence/packs/EV-pack-H-NNN.md` from EV beads of a given H |
| `scripts/render-artifact.sh` | Assemble the canonical 7-section ARTIFACT.md from beads |
| `scripts/render-decision-memo.sh` | Render decision memo (A7 archetype Phase 9 form) |
| `scripts/render-threat-catalog.sh` | Render threat catalog (A6 archetype Phase 9 form) |
| `scripts/render-incident-verdict.sh` | Render INCIDENT-VERDICT.md (incident-investigation mode) |
| `scripts/disagreement-register-lint.sh` | Verify `distillations/disagreement_register.md` has ≥1 entry per pair of model-family distillations |
| `scripts/drift-check.sh` | Compare session trajectory to canonical Brenner; emit `DRIFT-CHECK.md` skeleton |
| `scripts/drift-trend.sh` | Cross-session drift verdict trend analysis |
| `scripts/quote-bank-extract.sh` | Build per-operator quote bank from corpus + evidence packs |
| `scripts/check-rotation-rules.sh` | Verify Adjudicator/Synthesizer rotation rules per ROSTER-PLANS.md |
| `scripts/generate-debate-pairs.sh` | Generate Phase 5 debate pair list from active hypotheses |
| `scripts/run-phase5-debate-loop.sh` | File Phase 5 debate beads and dispatch both champion orientations for one round |
| `scripts/register-mail-identities.sh` | Register Agent Mail identity per pane |
| `scripts/register-assignees.sh` | Fallback: register pane identities via bead assignees (ntm-inbox mode) |
| `scripts/wait-for-onboard-acks.sh` | Block until every pane has acked Phase 2 onboarding |
| `scripts/list-distinct-model-families.sh` | Print model families present in the swarm |
| `scripts/assign-investigator-domains.sh` | Domain-assign Investigator panes to active hypotheses |
| `scripts/run-ubs-on-deliverables.sh` | Run /ubs on deliverables/scripts/; F-703 hard-block |
| `scripts/check-six-layer-validation.sh` | Pre-Phase-8 mandatory layer-1-5 sweep; per SIX-LAYER-VALIDATION.md |
| `scripts/export-reproducibility-package.sh` | Export workspace as reproducibility tarball with manifest |
| `scripts/check-anchor-density.sh` | Verify EV beads have sufficient verbatim-quote anchor density |
| `scripts/check-volatile-source-staleness.sh` | Detect stale volatile-source verifications (per VERIFICATION-FIRST.md) |
| `scripts/session-fork.sh` | Fork existing workspace for triangulation / red-team subsession / alt-direction exploration |
| `scripts/operator-self-assessment.sh` | End-of-week calibration for new operators (per OPERATOR-ONBOARDING-CURRICULUM.md) |
| `scripts/cross-incident-pattern.sh` | Detect cross-incident patterns across post-mortems |
| `scripts/score-ev.sh` | Compute composite W from 5 evidence axes; update bead descriptions |
| `scripts/evidence-graph.sh` | Render H → EV → source graph (DOT or Mermaid) for visual sanity-check |
| `scripts/triangulation-coverage.sh` | Measure cross-family coverage (per-H, per-distillation, per-audit) |
| `scripts/falsifier-quality-trend.sh` | Track operator falsifier-writing quality across sessions |
| `scripts/brennerbot-doctor.sh` | 7-pillar workspace health check (per BRENNERBOT-DOCTOR-RUBRIC.md); supports `--robot` JSON |
| `scripts/explain-decision.sh` | Given an H bead, summarize state + supporting/refuting EVs + critiques |
| `scripts/export-timeline.sh` | Chronological JSONL of session events (bead/phase/audit/drift) |

Scripts contribute zero context tokens — they are executed, not loaded.

---

## Subagents

Each subagent is a Markdown brief that the operator hands to a `general-purpose` Agent. They take the role-specific marching order, the relevant subset of the workspace, and a clear scope of write authority.

| Subagent | Phase | Purpose |
|----------|-------|---------|
| `subagents/proposer.md` | 3 | Generate hypotheses with mandatory falsifier+expected_evidence |
| `subagents/triage.md` | 3 | Dedupe + cluster + rank proposed hypotheses |
| `subagents/investigator.md` | 4 | Fill evidence pack for one hypothesis |
| `subagents/devils-advocate.md` | 4–5 | Attack the strongest hypothesis with counter-evidence |
| `subagents/adjudicator.md` | 5 | Score adversarial debates; flip H states |
| `subagents/synthesizer-by-model.md` | 6 | Per-model-family distillation |
| `subagents/meta-synthesizer.md` | 6 | Reconcile distillations + register disagreements |
| `subagents/fresh-eyes-auditor.md` | 7 | Run the verbatim trio of fresh-eyes prompts |
| `subagents/red-team.md` | 7 (T4+) | Adversarial novel-attack red team beyond Devil's-Advocate |
| `subagents/handback-writer.md` | 9 | One-page operator briefing |
| `subagents/decision-memo-writer.md` | 9 (A7) | Decision memo with reversibility analysis + dissent |
| `subagents/threat-catalog-writer.md` | 9 (A6) | Threat catalog with attack-class taxonomy |
| `subagents/incident-verdict-writer.md` | 9 (incident mode) | Compressed incident verdict |
| `subagents/drift-auditor.md` | 10 | Trajectory vs canonical Brenner; FRESH agent only |
| `subagents/cass-miner.md` | 0/1 | Mine prior `cass` sessions per CASS-MINING-RECIPES.md |
| `subagents/idea-generator.md` | 3 | Wraps `/idea-wizard` for breadth in hypothesis generation |
| `subagents/corpus-curator.md` | 1 | Ingest sources with content-hash + §-anchor scheme |
| `subagents/bayesian-scorer.md` | 6 / 9 | Assign informal posterior weights per Bayesian substrate |
| `subagents/falsifier-grader.md` | 3 / 7 | Grade falsifier quality on 5-dimension rubric |
| `subagents/reconciler.md` | 0 / 10 | Cross-session reconciler (FRESH agent, NOT swarm pane) |
| `subagents/framing-workbook-conductor.md` | 1 | Adaptive Phase 1 framing via FRAMING-WORKBOOK.md F1-F9 |
| `subagents/post-mortem-formalizer.md` | all | Operator for post-mortem-formalization mode |
| `subagents/ethics-reviewer.md` | 7 | Dual-use ethics review for sensitive outputs |
| `subagents/onboarding-mentor.md` | n/a | Buddy for new operators in OPERATOR-ONBOARDING-CURRICULUM weeks 1-4 |
| `subagents/evidence-grader.md` | 4 / 7 | Grade EV beads on 5-axis W rubric; updates bead descriptions |
| `subagents/decision-rule-extractor.md` | 1 (A7 archetype) | Probe user until decision rule is explicit |
| `subagents/methodology-historian.md` | quarterly | Track methodology evolution across sessions |
| `subagents/calibration-coach.md` | quarterly | Coach operators on calibration drift (D-Cal-1..5) |
| `subagents/operator-buddy.md` | T3+ long sessions | Shadow observer surfacing drift signals to primary operator (read-only) |

---

## Assets

| Asset | Purpose |
|-------|---------|
| `assets/marching-orders/MO-*.md` | Verbatim marching-order templates (one per phase, plus mode-flips and unstick recoveries) |
| `assets/ntm-pipelines/brennerbot-squad.yaml` | Canonical 5-role pipeline |
| `assets/ntm-pipelines/brennerbot-pair.yaml` | 2-role pipeline (cc + cod) |
| `assets/ntm-pipelines/brennerbot-swarm.yaml` | 8–12 role pipeline |
| `assets/ntm-pipelines/brennerbot-resume.yaml` | Resume from `RESUME.md` |
| `assets/ntm-pipelines/brennerbot-squad-no-mail.yaml` | Squad with Agent Mail unavailable |
| `assets/ntm-pipelines/brennerbot-incident.yaml` | Compressed incident-investigation mode (≤60min; Phase 1, Phase 3, Phase 4 inline with Phase 5, and Phase 7; emits INCIDENT-VERDICT.md) |
| `assets/ntm-pipelines/brennerbot-living-review.yaml` | **(spec, not executable)** Living-review tick (cadence-driven Phase 4+7 refresh) — phase outline for operator-driven runs |
| `assets/ntm-pipelines/brennerbot-post-mortem.yaml` | **(spec, not executable)** Post-mortem-formalization mode pipeline (4-6h, all 10 phases) — phase outline for operator-driven runs |
| `assets/ntm-pipelines/brennerbot-design-review.yaml` | **(spec, not executable)** A1-archetype design review (cross-domain + scale-physics + adversarial) — phase outline for operator-driven runs |
| `assets/ntm-pipelines/brennerbot-academic.yaml` | **(spec, not executable)** Academic-replication mode (paper distillation + replication discipline) — phase outline for operator-driven runs |
| (executable pipelines above carry `schema_version: "2.0"`; spec-only pipelines lack it and use `phases:` keys instead of `steps:`) | |
| `assets/templates/question-of-record-template.md` | The Step-0 framing template |
| `assets/templates/evidence-pack-template.md` | Per-hypothesis EV pack |
| `assets/templates/distillation-template.md` | Per-model-family distillation |
| `assets/templates/handback-template.md` | The one-page briefing |
| `assets/templates/resume-template.md` | The `RESUME.md` skeleton |
| `assets/templates/disagreement-register-template.md` | Where the model-family distillations diverge |
| `assets/templates/decision-memo-template.md` | A7 archetype Phase 9 deliverable |
| `assets/templates/threat-catalog-template.md` | A6 archetype Phase 9 deliverable |
| `assets/templates/incident-verdict-template.md` | Incident-investigation compressed-loop deliverable |
| `assets/templates/audit-finding-template.md` | Schema for filing `audit-finding` beads |
| `assets/templates/critique-template.md` | Schema for filing `critique` beads |
| `assets/templates/post-mortem-template.md` | Phase 9 post-mortem report (post-mortem-formalization mode) |
| `assets/templates/reconciliation-memo-template.md` | Cross-session reconciliation memo |
| `assets/templates/onboarding-checklist-template.md` | Per-week operator onboarding checklist |
| `assets/templates/ethics-review-template.md` | Dual-use ethics review |
| `assets/templates/calibration-report-template.md` | Per-operator calibration coaching report |
| `assets/templates/evidence-grade-template.md` | Phase 4/7 evidence grading report |
| `assets/templates/brennerbot-doctor-report-template.md` | Workspace doctor report (7-pillar verdict + recovery sequencing) |

---

## Related Skills (used as subroutines)

This skill is deliberately a **methodology layer over a swarm**. It composes the tools below; it does not reimplement them. When a question is purely about one of these adjacent concerns, invoke that skill directly.

| Concern | Skill |
|---------|-------|
| Full ntm command catalog, spawn mixes, recipes, `ntm work ...`, robot-mode reference | `/ntm` |
| Operator loop, autonomous unstick, attention-feed tending, marching-order discipline, anti-patterns, convergence termination | `/vibing-with-ntm` (the *operator* manual; this skill ships the *methodology* manual) |
| MCP Agent Mail primitives, register, reserve, send, inbox, macros | `/agent-mail` |
| Bead state changes, dependencies, `br ready` | `/beads-br` |
| Graph-aware triage (PageRank / critical path / cycles) | `/beads-bv` |
| Mining prior agent sessions for relevant prior research | `/cass` |
| Procedural memory context and `cm` playbook lookups | `/cass-memory` |
| Mining a methodology from session history (e.g., extracting your *own* lessons) | `/flywheel`, `/operationalizing-expertise` |
| Multi-model triangulation harness (Claude + Codex + Gemini) | `/multi-model-triangulation` |
| Hypothesis generation breadth | `/idea-wizard`, `/dueling-idea-wizards` |
| Bug hunting on any code/scripts produced as deliverables | `/multi-pass-bug-hunting`, `/ubs` |
| Weighted swarm spawning when bead backlog drives roster size | `/open-beads-weighted-tmux-agent-sessions` |
| Codebase-mode framing (Phase 1 archaeology) | `/codebase-archaeology`, `/codebase-report` |
| Reality check on a project against its README/plan | `/reality-check-for-project` |
| Mode-of-reasoning project analysis (symbolic vs neural / fast vs deep) | `/modes-of-reasoning-project-analysis` |
| Cron / loop / schedule for unattended convergence ticks | `/vibing-with-ntm` automation guidance; use `/loop` or `/schedule` only if those slash tools are actually available |
| Account rotation, CAAM quota | `/caam` |
| Destructive-command guard (when scripts in deliverables touch fs) | `/dcg`, `/slb` |
| Hooks for automated tick cadence | `/cc-hooks` |
| Agent fungibility (role rotation philosophy) | `/agent-fungibility-philosophy` |
| Adjacent dual-agent flywheel pattern | `/flywheel-with-two-agents-per-repo` |
| Past `brenner` CLI commands (this skill is the methodology; `/brenner` is the CLI pointer) | `/brenner` (thin pointer; this skill is much bigger scope) |
| Workmanship + validation tooling for `.claude/skills/*` directories | `/sw`, `/sc` |

If a referenced skill is missing on the user's machine and they have `jsm` installed and authenticated, offer `jsm install <name>` for each — see Skill Bootstrap above. Don't block a phase if a polish skill is missing — note it in `phase0_skill_inventory.json` and proceed with the inline fallback in [SKILL-FALLBACKS.md](references/SKILL-FALLBACKS.md).

---

## Self-Test

Trigger phrases that should activate this skill:

- "Investigate the design space for a bio-inspired alternative to nanochat"
- "Use brennerbot to figure out the best on-disk format for an append-only event log under 1KB events"
- "Run a multi-agent research session on `<question>` with hypothesis triage and adversarial debate"
- "Spin up a brennerbot swarm on this codebase to find the design weaknesses"
- "Resume the brennerbot session at `<workspace>` for another investigation pass"
- "Set up a Brenner-style hypothesis-and-evidence loop using ntm panes"
- "Triangulate a research question across cc + cod + gmi with adversarial debate"
- "What's the right architecture for X given constraints Y, Z? Use a multi-pane research swarm to figure it out"
- "Methodology drift check: how did our last brennerbot session diverge from canonical Brenner?"
- "Run a Brenner-style audit on this design doc with proposers, devil's advocates, and a synthesizer"
- "Use current NTM native BrennerBot pipelines to run an incident hypothesis loop"
- "Resume a Brenner-style NTM pipeline run and reconstruct what happened with causality/events"

Trigger-phrase probe + smoke test on a tiny synthetic question: [SELF-TEST.md](SELF-TEST.md).

---

## Meta-Note On Skill Size

This SKILL.md exceeds 500 lines deliberately. Running a 10-phase, multi-pane, multi-model research session has a large in-the-moment lookup surface — failure tables, beads invariants, mail thread schemes, marching-order indices, convergence rules, role rotation rules — because an operator tick has a few seconds' budget and the wrong classification wastes hours.

The body is still progressively disclosed: the **Phase-By-Phase Quick Reference** table and the **Failure Table** are designed to handle ~80% of tick decisions without scrolling further. References load on demand; scripts contribute zero context tokens; assets are copy-paste templates. The size guideline matters precisely because you have to know *why* it exists before knowing when to break it.

The companion `/vibing-with-ntm` skill makes the same trade-off and articulates it explicitly. This skill follows the same pattern: spine first, depth on demand, justify the excess.
