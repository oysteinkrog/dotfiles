# METHODOLOGY-INTEGRATION.md — How the Pieces Fit

<!-- TOC: The big picture | Cross-cutting integrations | Skill-as-subroutine integrations | Data flow per artifact | Pipeline-as-orchestrator integrations | Session lifecycle dimension | Operator lifecycle integration | When integrations break | Extension surface -->

The skill has a lot of moving parts: 21 references, 24 marching orders, 22 scripts, 8 subagents, 5 pipelines. This file integrates them — what calls what, when, and why.

Mirrors saas-billing's METHODOLOGY-INTEGRATION pattern adapted for research methodology.

---

## The big picture (composition)

```
                         ┌─────────────────────────────────┐
                         │  USER ASKS A QUESTION           │
                         └──────────────┬──────────────────┘
                                        │
                                        ▼
                         ┌─────────────────────────────────┐
                         │  KICKOFF (KICKOFF-PROMPTS.md)   │
                         │   — pick mode, archetype, tier  │
                         └──────────────┬──────────────────┘
                                        │
                                        ▼
                         ┌─────────────────────────────────┐
                         │  bootstrap-session.sh           │
                         │   — workspace + beads + ntm     │
                         │   — calls check-skills.sh       │
                         │   — writes phase0_scope_*.md    │
                         └──────────────┬──────────────────┘
                                        │
                                        ▼
                                  ┌────────────┐
                                  │  Phase 1   │ ──→ MO-01-frame-question.md
                                  │  framing   │     [optional: MO-cass-mine.md]
                                  │            │     [optional: MO-corpus-curate.md]
                                  └─────┬──────┘     [code: /codebase-archaeology]
                                        │
                                        ▼
                                  ┌────────────┐
                                  │  Phase 2   │ ──→ MO-02-onboarding.md (per pane)
                                  │ bootstrap  │     [register-mail-identities.sh OR register-assignees.sh]
                                  └─────┬──────┘     [wait-for-onboard-acks.sh]
                                        │
                                        ▼
                                  ┌────────────┐
                                  │  Phase 3   │ ──→ MO-03a-propose.md (parallel)
                                  │  propose   │     ──→ subagents/idea-generator.md (optional)
                                  │  + triage  │     MO-03b-triage.md
                                  └─────┬──────┘     MO-03c-third-alternative.md (if F-301)
                                        │             [audit-bead-invariants.sh phase3_exit]
                                        ▼
                                  ┌────────────┐
                                  │  Phase 4   │ ◀── (loop, hard cap 6 rounds)
                                  │ investigate│     MO-04a-investigate.md (per H, parallel)
                                  └─────┬──────┘     MO-04b-devils-advocate.md (top-confidence H)
                                        │             MO-quickie-pilot.md (when blocked)
                                        │             MO-mode-flip-investigator-to-advocate.md (F-403)
                                        │             MO-anomaly-cluster.md (Tier 2; ΔE)
                                        │             [render-evidence-pack.sh per H]
                                        │             [convergence-check.sh --phase=4]
                                        ▼
                                  ┌────────────┐
                                  │  Phase 5   │ ──→ generate-debate-pairs.sh
                                  │   debate   │     MO-05a-cross-exam.md (per pair, parallel)
                                  └─────┬──────┘     MO-05b-adjudicate.md (per debate)
                                        │             MO-falsifier-fired.md (kill protocol)
                                        ▼
                                  ┌────────────┐
                                  │  Phase 6   │ ──→ list-distinct-model-families.sh
                                  │  distill   │     MO-06a-distill.md (per family, parallel)
                                  └─────┬──────┘     MO-06b-meta-synthesize.md
                                        │             [disagreement-register-lint.sh]
                                        │             [optional: /multi-model-triangulation]
                                        ▼
                                  ┌────────────┐
                                  │  Phase 7   │ ◀── (loop, hard cap 4 trio-rounds)
                                  │   audit    │     MO-07a-fresh-eyes.md (trio per pane)
                                  └─────┬──────┘     [run-ubs-on-deliverables.sh]
                                        │             [optional: subagents/red-team.md for T4+]
                                        │             [convergence-check.sh --phase=7]
                                        ▼
                                  ┌────────────┐
                                  │  Phase 8   │ ──→ MO-08-freeze.md
                                  │  freeze    │     [dump-session-report.sh --emit-resume]
                                  └─────┬──────┘     [resume-session.sh --dry-run verify]
                                        │             [render-artifact.sh] (build ARTIFACT.md)
                                        ▼
                                  ┌────────────┐
                                  │  Phase 9   │ ──→ MO-09-handback.md
                                  │  handback  │     ──→ subagents/handback-writer.md
                                  └─────┬──────┘     [audit-bead-invariants.sh handback_open_thread_tags]
                                        │
                                        ▼
                                  ┌────────────┐
                                  │  Phase 10  │ ──→ subagents/drift-auditor.md (FRESH agent)
                                  │   drift    │     MO-10-drift-check.md
                                  └─────┬──────┘     [drift-check.sh] (skeleton)
                                        │
                                        ▼
                              ┌─────────────────────┐
                              │  HANDBACK to user   │
                              │  + DRIFT-CHECK.md   │
                              │  + lessons in refs/ │
                              └─────────────────────┘
```

---

## Cross-cutting integrations

### Per-tick orchestrator

`scripts/tick.sh <workspace>` runs once every 10-17 min during Phases 4-7. It:

1. Reads phase progression flags (which phase is current)
2. Snapshots pane state via `ntm --robot-snapshot`
3. Counts beads by type/status
4. Runs `audit-bead-invariants.sh --check=phase<N>_round`
5. Runs `convergence-check.sh --phase=<N>` (if applicable)
6. Appends one-line entry to `tick_history.jsonl`

Outputs to operator's stdout — readable in 5 seconds.

### Anti-pattern detection

`audit-bead-invariants.sh --all` is the comprehensive check, run:

- After Phase 3 exit (`--check=phase3_exit`)
- Per Phase 4 round (`--check=phase4_round`)
- After Phase 7 exit (`--check=phase7_exit`)
- During Phase 9 (`--check=handback_open_thread_tags`)
- During Phase 10 (`--all` for drift-check input)

Each invariant violation maps to a F-### code (per FAILURE-TABLE.md).

### Convergence detection

`convergence-check.sh --phase=<N>` is run:

- End of each Phase 4 round (must pass to exit Phase 4)
- End of each Phase 6 meta-synthesis pass
- End of each Phase 7 trio-round

Exit 0 → converged; exit 1 → not yet. Operator decides whether to dispatch another round.

---

## Skill-as-subroutine integrations

This skill composes other skills. Specific call points:

| Phase | Helper skill | When invoked |
|-------|--------------|--------------|
| 0 | `/cass` (via subagents/cass-miner.md) | When mining prior sessions for context |
| 1 | `/codebase-archaeology` | code-investigation mode Phase 1 |
| 1 | `/codebase-report` | code-investigation mode Phase 1 |
| 1 | `/reality-check-for-project` | code-investigation mode Phase 7 (audit) |
| 3 | `/idea-wizard` (via subagents/idea-generator.md) | breadth in hypothesis generation |
| 3 | `/dueling-idea-wizards` | adversarial generation when stuck |
| 4-7 | `/vibing-with-ntm` | pane-state recovery, operator-loop tactics |
| 6 | `/multi-model-triangulation` | optional third reconciliation |
| 7 | `/multi-pass-bug-hunting` | when deliverables/scripts/ has nontrivial code |
| 7 | `/ubs` | code in deliverables/ must pass before Phase 8 |
| 8 | `/fixing-beads-problems` | when F-802 (bead drift) fires |
| 0/2 | `/agent-mail` | MCP coordination primitives |
| any | `/beads-br`, `/beads-bv` | bead state changes, graph triage |
| any | `/caam` | account rotation when rate-limited |
| any | `/dcg`, `/slb` | destructive-command guard |
| any | `/cc-hooks` | optional automation |
| any | `/vibing-with-ntm` automation guidance | recurring orchestrator ticks; use `/loop` or `/schedule` only if available |

When a helper skill is missing, [SKILL-FALLBACKS.md](SKILL-FALLBACKS.md) documents the inline degradation. The session never blocks on a missing helper skill (except `/ntm` and the `br` binary, which are hard-required).

---

## Data flow per artifact

### `intake/question_of_record.md`

| Reads | Writes | Read by |
|-------|--------|---------|
| operator + user | MO-01 | Every subsequent phase MO; check Phase 1 exit gate |

### `corpus/corpus_index.md`

| Reads | Writes | Read by |
|-------|--------|---------|
| operator + corpus-curator | MO-corpus-curate / corpus-curator subagent | Phase 4 investigators (search log appended) |

### `H-*` beads

| Reads | Writes | Read by |
|-------|--------|---------|
| MO-01 (H-000), MO-03a (H-001..N), MO-03c (third-alts) | proposers, triage | Investigators (Phase 4), Devil's-Advocates, Adjudicators (Phase 5), Synthesizers (Phase 6), Auditors (Phase 7), Drift auditor (Phase 10) |

### `EV-*` beads

| Reads | Writes | Read by |
|-------|--------|---------|
| MO-04a, MO-04b, MO-cass-mine | Investigators, Devil's-Advocates, cass-miner | Adjudicators (Phase 5), Synthesizers (Phase 6), Auditors (Phase 7) |

### `evidence/packs/EV-pack-H-NNN.md`

| Reads | Writes | Read by |
|-------|--------|---------|
| `render-evidence-pack.sh` from EV beads | Investigator (annotates Methodology section + Round Log) | Devil's-Advocate (Phase 4); Adjudicator (Phase 5); Synthesizer (Phase 6); Auditor (Phase 7) |

### `distillations/by_<family>.md`

| Reads | Writes | Read by |
|-------|--------|---------|
| MO-06a per family | Per-family Synthesizers (independent) | Meta-synthesizer (Phase 6b); Auditor (Phase 7); Drift auditor (Phase 10) |

### `distillations/meta_synthesis.md` + `disagreement_register.md`

| Reads | Writes | Read by |
|-------|--------|---------|
| MO-06b | Meta-synthesizer | Auditor (Phase 7); HANDBACK writer (Phase 9); Drift auditor (Phase 10) |

### `deliverables/HANDBACK.md`

| Reads | Writes | Read by |
|-------|--------|---------|
| MO-09 | Handback-writer | User; Drift auditor (Phase 10) |

### `deliverables/RESUME.md`

| Reads | Writes | Read by |
|-------|--------|---------|
| MO-08 | Phase 8 freeze pane + dump-session-report.sh --emit-resume | resume-session.sh; next session's Phase 0 |

### `deliverables/DRIFT-CHECK.md`

| Reads | Writes | Read by |
|-------|--------|---------|
| MO-10 | Fresh general-purpose Agent (drift-auditor subagent) | User; cross-session learning |

### `phase_<N>_complete.flag` files

| Reads | Writes | Read by |
|-------|--------|---------|
| Phase exit gates write these | dump-session-report.sh, drift-check.sh | tick.sh, audit-bead-invariants.sh |

---

## Pipeline-as-orchestrator integrations

The `assets/ntm-pipelines/*.yaml` files are ntm pipeline definitions that orchestrate Phases 2-8 automatically:

- `brennerbot-squad.yaml` — canonical 5-pane Squad
- `brennerbot-pair.yaml` — 2-pane minimal
- `brennerbot-swarm.yaml` — 8-12 pane Swarm
- `brennerbot-resume.yaml` — resume from RESUME.md
- `brennerbot-squad-no-mail.yaml` — Squad without Agent Mail (ntm-inbox fallback)

When an operator wants the swarm to run unattended, they invoke a pipeline:

```bash
ntm pipeline run .ntm/pipelines/brennerbot-squad.yaml --session RS-YYYYMMDD-slug --var workspace_path=<workspace> --var session_id=RS-YYYYMMDD-slug ...
```

The pipeline orchestrates dispatch + waits + convergence checks + commits. Phases 1, 9, 10 are operator-driven (not pipeline-driven) because they require human + fresh-agent judgment.

---

## Session lifecycle dimension

Across many sessions, persistent learning lives in:

| Artifact | Persists across sessions | Updated by |
|----------|--------------------------|------------|
| `references/OPERATORS.md` | yes | Phase 10 lessons |
| `references/ARCHETYPE-START-PACKS.md` | yes | Phase 10 surfaces new archetypes |
| `references/QUESTION-ARCHETYPES.md` | yes | Phase 10 surfaces new question shapes |
| `references/CASS-MINING-RECIPES.md` | yes | Phase 10 surfaces new mining patterns |
| `references/ANTI-PATTERNS.md` | yes | Phase 10 surfaces new failure modes |
| `references/DISAGREEMENT-REGISTER-OF-DISTILLATIONS.md` | yes | Phase 10 surfaces new methodology disagreements |

Per-session ephemeral artifacts (workspace's intake/, evidence/, distillations/, deliverables/) live in the workspace and don't propagate. This is the lifecycle Track A pattern: *the corpus persists; the analysis is per-session*.

---

## Operator lifecycle integration

The operator's role across a session:

| Phase | Operator activity |
|-------|-------------------|
| 0 (kickoff) | Read user ask; pick archetype + mode + tier; confirm with user |
| 1 (framing) | Q&A with user; ensure falsifier is observable; commit |
| 2 (bootstrap) | Dispatch pipeline OR manual dispatch; wait for onboarding acks |
| 3-7 (loops) | Tick every 10-17 min; address F-### codes; verify convergence |
| 8 (freeze) | Verify RESUME.md; commit; checkpoint |
| 9 (handback) | Read HANDBACK.md; ensure ≤80 lines + every listed unresolved thread tagged |
| 10 (drift) | Dispatch fresh agent; commit lessons back to references/ |

The operator is always a *human-in-the-loop* for Phases 0, 1, 8, 9, 10. Phases 3-7 can run unattended (with robot mode + autonomous unstick from /vibing-with-ntm) or attended.

---

## When integrations break

If a script can't find another script, OR a marching order can't find its template, OR a pipeline can't find its dependencies — the integration is broken. Check:

1. `chmod +x` on all scripts? (`scripts/*.sh`)
2. References use relative paths from skill root (`references/`, `assets/`)?
3. Subagent files exist for every reference in MOs?
4. Pipelines reference scripts that exist?

Run `scripts/check-skills.sh <workspace>` regularly to catch broken inter-skill integrations.

Run `bash -n scripts/*.sh` to catch syntax errors.

Run `/sw validate <skill-path>` to catch SKILL.md → references graph errors.

---

## Extension surface

When extending the methodology:

- New operator → `OPERATORS.md` + new MO + new validator + entry in this file's data-flow table
- New phase variant → `OPERATING-MODES.md` + new pipeline YAML + entries in PHASES.md
- New archetype → `QUESTION-ARCHETYPES.md` + `ARCHETYPE-START-PACKS.md`
- New failure mode → `FAILURE-TABLE.md` + `ANTI-PATTERNS.md` + recovery MO
- New script → this file's "Per-tick orchestrator" or pipeline section

Phase 10 drift-check should propose extensions when a session reveals a recurring pattern. Don't pre-emptively add — the corpus of session experience drives evolution.
