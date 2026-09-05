# Orchestration — Tier Selection, Fan-Out, and Parallelism Boundaries

Maps the run's shape to its agent topology. Adapted from [git-stash-janitor's ORCHESTRATION.md](../../git-stash-janitor/references/ORCHESTRATION.md), with three additions specific to branch-and-worktree work:

1. **Two units of management, one safety story** (Axiom 0): inventory and bundle are two parallelizable surfaces but produce a single shared bundle that gates everything destructive. The fan-out shape is therefore **diamond, not fan-out-fan-in**.
2. **A dedicated harmonization-planner subagent** at higher tiers (Comprehensive / Council) — Phase 7 is the conceptual centerpiece and gets its own fan-out per colliding-file group.
3. **The skill is typically run AFTER (or DURING) an agent swarm session** that itself created the pile being rationalized. The orchestration model accounts for this — concurrent agents may still be active in some worktrees, and the safety gates assume drift is normal (Axiom 12).

---

## Orchestration Tiers

Pick the tier based on counts (worktrees `W`, branches `B`), project complexity, and stake of the recovered work. Higher tiers consume more agent compute but produce stronger triage signal AND stronger harmonization plans.

| Tier | Workers | Models | When |
|---|---|---|---|
| Solo | 1 | 1 | <5 worktrees AND <30 branches; routine cleanup |
| Pair | 2 | 1 | up to 20 worktrees / up to 100 branches; typical post-swarm cleanup |
| Squad | 4–6 | 1–2 | 100–200 branches; mixed-language repo OR multiple branch families |
| Swarm | 8–12 | 2–3 | 200+ branches OR many file collisions; flagship project |
| Council | 12+ + triangulation | 3+ | B≥300 OR production-critical OR security-sensitive harmonization decisions |

These thresholds match [SKILL.md § Parallelism Model](../SKILL.md#parallelism-model) (the canonical source).

**Mode mapping** (the `Quick / Standard / Comprehensive / Council` modes from [SKILL.md § Mode Variants](../SKILL.md#mode-variants)):

- Quick → Solo
- Standard → Pair or Squad
- Comprehensive → Squad / Swarm
- Council → Council

> **Why:** Per [SKILL.md § Parallelism Model](../SKILL.md#parallelism-model): "Inventory and bundle creation are serial (one source of truth). Triage and harmonization are the large parallelizable phases. Apply is sequential (each apply changes the 3-way base for later applies and can flip verdicts)."

---

## Fan-Out Pattern (the Diamond)

The skill's pipeline has three parallelizable phases (5 = triage, 7 = harmonization-per-file, 9 = fresh-eyes-rounds) and two strictly serial phases (3 = bundle, 8 = apply). The fan-out shape is a diamond — fan-out at Phase 5, fan-in at Phase 6, fan-out again at Phase 7, fan-in at Phase 8, fan-out at Phase 9, single-thread at Phase 10.

```
        Phase 0/1 INTAKE + PROFILE       serial
        Phase 2 INVENTORY                serial (two passes; same subagent)
        Phase 3 BUNDLE  (HARD GATE)      serial
        ─────────────────
                │
   ┌────────────┼────────────┐
   ▼            ▼            ▼
Triage A     Triage B  ...  Triage N      Phase 5 — parallel
(~10 entries)                              (W/B distributed across batches)
   │            │            │
   └────────────┴────────────┘
                ▼
       Phase 6 MERGE (USER GATE)          single agent
                │
   ┌────────────┼────────────┐
   ▼            ▼            ▼
Harmonize     Harmonize ... Harmonize     Phase 7 — parallel per colliding-file group
file A        file B        file N        (Comprehensive/Council only; inline at lower tiers)
   │            │            │
   └────────────┴────────────┘
                ▼
     Phase 7 PLAN MERGE (USER GATE)       single agent (writes harmonization_plan.md)
                ▼
     Phase 8 APPLY (sequential)           single applier; one row at a time;
                                          per-apply gates; ⊞ RE-FINGERPRINT between rows
                ▼
     Phase 8b SPLIT-APPLY (sequential)    single splitter
                ▼
   ┌────────────┼────────────┐
   ▼            ▼            ▼
Fresh-eyes   Fresh-eyes  ... Fresh-eyes   Phase 9 — parallel ROUNDS
Round 1      Round 2          Round 3     (each round is independent fresh agent;
(Literal)    (Forensic)       (Adversarial) different reading stance per round)
   │            │            │
   └────────────┴────────────┘
                ▼
   Phase 10 CLEANUP (USER GATE)           single conductor; serial within each bucket
                ▼
   Phase 11 HANDOFF                       single reporter
```

The diamond shape is critical: file-reservation discipline depends on the workers in each parallel band having disjoint write surfaces. See § Coordination Discipline below.

---

## Worker Sizing

Phase 5 triage workers are sized for **~10 entries each** (vs. ~20 for git-stash-janitor) — empirically, branches require more per-entry work than stashes (signature sampling, cherry-vs-canonical, files-touched aggregation) and ~10 is where marginal gain flattens.

| W + B (total non-protected entries) | Recommended workers | Rationale |
|---|---|---|
| 1–9 | 1 | Solo agent; serial; faster than spawning |
| 10–30 | 2 | Pair; one reviews the other's borderline verdicts at merge time |
| 30–80 | 3–4 | One per ~10 entries; minimal coordination overhead |
| 80–160 | 5–8 | Each worker covers ~10–20; fingerprint cache shared via Mail thread |
| 160–320 | 10–12 | Diminishing returns past 12 due to file-reservation contention |
| 320+ | 12 + sharded fingerprint cache | Use the same ~10–20-entry batch rule; document any cache sharding in the run plan |

**Allocation rule:** never give a worker fewer than 5 entries (overhead dominates) or more than 25 (head-of-line blocking). Adjust based on per-entry diff size — a branch with 50+ commits and 200 files-touched takes 5x the time of a branch with 1 commit and 3 files-touched.

Phase 7 harmonization-planner workers are sized **per colliding-file group**, not per branch. Each group gets one worker. Groups are independent (one file's harmonization doesn't affect another's). Cap at 12 parallel planners for Council mode.

---

## Parallelism Boundaries (NON-NEGOTIABLE)

These are the parallelizability rules per phase. Violating them produces incorrect verdicts or destructive races.

| Phase | Parallelism | Why |
|---|---|---|
| 0 INTAKE | Serial (main agent) | One conversation with the user; no fan-out point |
| 1 PROFILE | Serial (1 subagent) | The profile is consumed by every subsequent phase; one source of truth (Axiom 4) |
| 2 INVENTORY | Serial (1 subagent, two passes) | Pass A reads worktree state; Pass B reads branch state; the two TSVs share the join key (branch name) — interleaved writes would corrupt the join. **Why:** Axiom 0: "Two units of management, one safety story" |
| 3 BUNDLE | Serial (1 subagent) | The bundle is the irreversibility boundary; byte-equality + round-trip verification is one transaction. **Why:** Axiom 3, Axiom 4 |
| 4 PROTECTION | Serial (USER GATE) | A user gate cannot fan out |
| 5 TRIAGE | **Parallel** (N workers) | Workers' batches are disjoint; each worker reads the bundle (read-only) and writes its own batch TSV. Reservations on `{WORKSPACE}/triage/batch_<id>.tsv` per worker via Agent Mail |
| 6 MERGE | Serial (USER GATE) | Single source of truth for `triage.tsv`; the merger reads all batch TSVs and writes the union |
| 7 HARMONIZE | **Parallel per file** (N workers) | Each colliding-file group is independent. Workers read the bundle + their group's variants (read-only) and write to a per-group section of `harmonization_plan.md` (or to per-group temp files that the Phase 7 merger concatenates) |
| 7-merge | Serial | The harmonization_plan.md is one document; user reviews it as a whole |
| 8 APPLY | **Strictly serial** | Each apply changes the 3-way base for later applies and can flip downstream verdicts via `⊞ RE-FINGERPRINT`. **Why:** Axiom 13 — per-apply gates run on every commit, not at the end. Two parallel applies would race on the rationalization branch's tip and corrupt it |
| 8b SPLIT-APPLY | Serial | Same reason as 8 — the rationalization branch's tip is mutated |
| 9 FRESH-EYES | **Parallel rounds** | Each round is an independent agent reading the rationalization branch's commits. Rounds are read-only on the source code; only the fresh_eyes_log.md is written, append-only with per-round prefixes |
| 10 CLEANUP | Serial (USER GATE → conductor) | Each removal/deletion is restated verbatim; concurrent removals would race on `.git/refs/heads/` and `.git/worktrees/` |
| 11 HANDOFF | Serial | One report; one beads issue; one Mail thread update |

**The hard rule:** if you find yourself wanting to parallelize Phase 8 or 8b, STOP — it's a footgun. Multi-model triangulation on Phase 8 is "second-opinion review of each apply", not "two parallel applies". Per Axiom 13, the per-apply gates are non-negotiable, and they're also non-parallel.

---

## Coordination Discipline (Agent Mail)

Every parallel worker reserves its write surface via Agent Mail before writing. Reservations are released when the worker finishes its batch (not at end of session — let other workers reuse the slot if appropriate).

### Phase 5 (triage) reservations

```
agent_mail.file_reservation_paths(
  project_key="<basename>",
  agent_name="<worker_id>",
  paths=[".worktree_branch_rationalization_workspace/triage/batch_<id>.tsv"],
  ttl_seconds=3600,
  exclusive=true,
  reason="branch-rationalization-<run-id>-phase5-batch-<id>",
  thread_id="branch-rationalization-<run-id>"
)
```

### Phase 7 (per-file harmonization) reservations

```
agent_mail.file_reservation_paths(
  project_key="<basename>",
  agent_name="<planner_id>",
  paths=[
    ".worktree_branch_rationalization_workspace/harmonization/file_<sanitized-path>.md"
  ],
  ttl_seconds=3600,
  exclusive=true,
  reason="branch-rationalization-<run-id>-phase7-file-<sanitized-path>",
  thread_id="branch-rationalization-<run-id>"
)
```

### Phase 9 (fresh-eyes rounds) reservations

```
agent_mail.file_reservation_paths(
  project_key="<basename>",
  agent_name="<reviewer_id>",
  paths=[
    ".worktree_branch_rationalization_workspace/fresh_eyes_round_<N>.md"
  ],
  ttl_seconds=1800,
  exclusive=true,
  reason="branch-rationalization-<run-id>-phase9-round-<N>",
  thread_id="branch-rationalization-<run-id>"
)
```

### Run-level advisory reservations (no exclusivity)

The orchestrator holds advisory (non-exclusive) reservations on the high-traffic surfaces for the duration of the run:

```
agent_mail.file_reservation_paths(
  project_key="<basename>",
  agent_name="orchestrator",
  paths=[".git/worktrees/**", ".git/refs/heads/**"],
  ttl_seconds=14400,
  exclusive=false,
  reason="branch-rationalization-<run-id>"
)
```

These don't block other agents — they advertise that this run is in progress so concurrent agents can choose to delay destructive operations.

The run-id is the Mail thread id. All inter-agent messages are threaded under it. Beads issue id == thread id where possible.

---

## Recovery from Worker Failure

A parallel worker can fail in three ways. Each has a deterministic recovery.

### F1 — A Phase 5 triage worker times out or crashes

**Symptoms:** the batch TSV is empty or partial; the Mail reservation is released by TTL.

**Recovery:**
1. The orchestrator detects via batch-TSV-not-final at the merge step.
2. Re-spawn a fresh worker for the SAME batch (idempotent — workers re-read the bundle and re-fingerprint from scratch).
3. New worker reserves the same TSV path (the prior reservation expired).
4. Other workers' batches are not affected.

### F2 — A Phase 7 harmonization-planner worker disagrees with itself across runs

**Symptoms:** re-spawning the same worker on the same group produces a different synthesis proposal (non-determinism in stance interpretation).

**Recovery:**
1. The orchestrator records BOTH proposals.
2. Surface the disagreement to the user.
3. Optionally invoke triangulation (Path A → B → C per [MULTI-MODEL-TRIANGULATION.md](MULTI-MODEL-TRIANGULATION.md)) to break the tie.
4. The user's decision goes into `user_overrides.tsv`; future re-runs use it as input.

### F3 — A Phase 9 fresh-eyes round produces no findings AND the gates also pass — but a subsequent round finds substantive issues

**Symptoms:** termination would have triggered after round 2 (two clean rounds), but round 3 finds a real bug.

**Recovery:**
1. Re-spawn rounds 4 and 5 with the same stances as 2 and 3.
2. If they also find real issues: termination criteria reset (need ≥2 clean rounds in a row again).
3. If the same finding repeats 3 rounds without resolution: per [INCIDENT-PLAYBOOK.md I4](INCIDENT-PLAYBOOK.md#i4), surface to user as blocking-unresolvable.

### F4 — A Phase 8 apply silently rolls back a previous apply

**Symptoms:** the rationalization branch's tip after apply N+1 is the same SHA as before apply N (the rebase / squash-merge undid the prior commit).

**Recovery:**
1. The orchestrator detects via `apply_log.tsv`'s recorded SHAs vs. the current HEAD.
2. HALT immediately. Do NOT continue Phase 8.
3. Inspect: which commit was rolled back? Why? (Most often a rebase-and-merge that reordered against a recently-applied keeper.)
4. Restore via `git reset --keep <prior-tip-sha>` (note: `--keep` is safer than `--hard` and DCG-allowed, but still surface to user before running). If user OKs: continue from the next row.
5. If user does not OK: stop the run; the rationalization branch is in an unsafe state.

---

## Default Execution Model — Single Claude Code Session

The skill is designed to run from a **single Claude Code session** with no external orchestration tooling required. The main agent uses the `Task` tool to spawn parallel subagents for the parallelizable phases (5 = triage, 7 = harmonization fan-out, 9 = fresh-eyes). Sequential phases (3, 6, 8, 10) run in the main agent or in a single dedicated subagent.

For a 213-branch + 47-worktree repo running from a single session at Squad tier:

- Main agent runs Phases 0–4 directly (with one project-profiler subagent in Phase 1, one inventory-agent in Phase 2, one bundle-builder in Phase 3)
- Phase 5: spawn 6 Task-tool subagents in parallel (one Task call per ~10-entry batch, batched across the ~187 non-protected entries)
- Phase 6: main agent merges, presents decision table, waits for user
- Phase 7: spawn 1 harmonization-planner subagent (Standard/Comprehensive — fan out per colliding-file group only at Comprehensive+)
- Phase 8: main agent OR single keeper-applier subagent (sequential by definition)
- Phase 8b: 1 partial-splitter subagent
- Phase 9: each round runs as a sequential Task subagent (3 rounds × different reading stances per Comprehensive); ≥2 rounds for Standard → 6+ subagent calls total; or in true parallel for Comprehensive (rounds spawned simultaneously, each reading different files)
- Phase 10: main agent (gated by user authorization) + cleanup-conductor subagent
- Phase 11: handoff-reporter subagent

This is the **default** and works in any environment that has Claude Code's Task tool. No NTM, no tmux, no extra setup.

Wall time on 213 branches + 47 worktrees: typically 3–6 hours including user-gate latencies in Phases 4, 6, 7, 10.

---

## Optional: NTM Swarm Topology

If the user already runs an [`/ntm`](../../ntm/SKILL.md) multi-pane swarm (multiple Claude Code / Codex / Gemini panes coordinated via tmux), the skill can map onto that topology instead. This is **opt-in only** — invoke via "run branch-rationalization under NTM" or similar; otherwise the default single-session model is used.

Under NTM:

```
ntm spawn --project <repo> --kind cc --count 1   # main orchestrator pane
ntm spawn --project <repo> --kind cc --count 6   # triage workers (Phase 5)
ntm spawn --project <repo> --kind cc --count 4   # harmonization planners (Phase 7)
ntm spawn --project <repo> --kind cod --count 2  # codex reviewers (Phase 7 + Phase 9 triangulation)
ntm spawn --project <repo> --kind gmi --count 1  # gemini reviewer (Phase 9 round 3)
```

The orchestrator pane dispatches marching orders to workers via Agent Mail; worker panes write their batch / harmonization TSVs and report back; the orchestrator merges and gates Phases 6, 7, 10.

When to choose NTM over the default:

- The user already runs NTM and prefers consistent ergonomics across skills
- The repo is very large (300+ branches) and the user wants visible per-pane progress
- Multi-model triangulation across multiple Claude/Codex/Gemini accounts in parallel
- Council mode where a dedicated Codex pane and a dedicated Gemini pane reviewing every harmonization proposal pays back the NTM setup cost

When to stick with the default:

- Most runs (NTM adds setup overhead that isn't paid back below ~150 branches)
- The user isn't already invested in NTM
- The session is interactive and the user wants tight feedback loops
- The user is solo-running this on a personal project

Wall time on 213 branches + 47 worktrees under NTM: ~2–3 hours wall-clock (vs. ~3–6 hours under default), at the cost of NTM setup overhead.

> **Why:** Per [`/ntm`](../../ntm/SKILL.md) skill: NTM panes give visible per-pane progress for long-running parallel work, and integrate cleanly with Agent Mail for coordination. The branch-rationalization skill's diamond fan-out shape maps cleanly to NTM's pane-per-role topology.

---

## Optional: Multi-Agent Swarm Integration

If the user already runs an NTM + Agent Mail + Beads + BV swarm pattern for general multi-agent coding, this skill can plug into that workflow:

1. **Beads issues for each phase.** The orchestrator creates a parent beads issue (`br create --title "branch+worktree rationalization on <basename>"`) and child issues for each phase that needs human-tracking (Phase 4 protection review, Phase 6 triage approval, Phase 7 harmonization review, Phase 10 cleanup authorization).
2. **BV-tracked dependencies.** Phase 8 keepers may unblock follow-up work; `bv --robot-triage` after Phase 11 surfaces newly-actionable beads.
3. **Agent Mail thread for the run.** All workers use the same `thread_id=branch-rationalization-<run-id>`. The orchestrator posts a final summary to that thread linking to the handoff report.
4. **Concurrent agents respect the file reservations.** Other agents working in the same project see the advisory reservations on `.git/worktrees/**` and `.git/refs/heads/**` and can choose to delay destructive work.

This integration is automatic when [`/agent-mail`](../../agent-mail/SKILL.md), [`/beads-br`](../../beads-br/SKILL.md), and [`/beads-bv`](../../beads-bv/SKILL.md) are available — the orchestrator detects them at Phase 0 and uses them. No user action required beyond having the skills installed.

> **Why:** Branch-rationalization is a specialization of the broader swarm pattern (NTM + Agent Mail + Beads + BV) with a specific phase loop and bundle-discipline.

---

## Running After (or During) a Swarm

The hard-won insight from the user's past sessions:

> **Agent-swarm work creates exactly the worktree+branch pile this skill rationalizes — the orchestration model must account for this skill being run AFTER a swarm session, possibly with concurrent agents still active.**

The cass-mined sessions where the user manually rationalized branches/worktrees show recurring patterns:

- "autostash resulted in merge conflicts requiring manual resolution" → concurrent-agent commits during a rebase produced state the user had to disentangle. Mapped to: **Axiom 12 — treat concurrent-agent drift as if you made it.** [KEY-INSIGHTS.md §I-3](KEY-INSIGHTS.md) anchors this.
- "agents kept modifying files while I was working" → file-reservation discipline. Mapped to: **the Mail-reservation pattern in this section.**
- "branches/worktrees don't work with dozens of concurrent agents" → file-reservations on canonical instead of branch-per-agent for swarm sessions, but for rationalization runs the same insight inverts: when rationalizing AFTER such a swarm, the worktrees and branches that DO exist need careful inventory + the rationalization itself uses file reservations to coordinate with any still-running agents.

### After-Swarm Mode (specialization)

[KICKOFF-PROMPTS.md § After-Swarm Mode](KICKOFF-PROMPTS.md#after-swarm-mode-specialized-variant) defines the specialization. Topology highlights:

1. **Phase 0 explicitly asks** "Are any agents still actively working in this repo or its worktrees right now?"
2. **Active-agent worktrees go straight into `protected.tsv`** with reason `active-agent-session`. They are NOT triaged. They are NOT removed.
3. **File reservations are longer** (`ttl_seconds=7200` or more) to span the rationalization run.
4. **Phase 5 triage workers re-check `git rev-parse refs/heads/<name>`** before reading any branch's diff; if the live SHA differs from the bundle's recorded SHA, the branch was advanced by a concurrent agent. The triage subject is the bundle's frozen SHA, with a note in the verdict.
5. **Phase 8 WORKING-TREE-DRIFT check runs before EVERY apply** (not just at the start of the phase). Per Axiom 12, the skill never disturbs concurrent work; it just notes the drift.
6. **Phase 10 re-snapshots dirty worktrees before each `git worktree remove`** — if any agent has modified the worktree since the bundle's capture, the new dirty state goes into a NEW bundle subdirectory (`worktrees/<wt_slug>-<timestamp>/`) before the removal proceeds.

### Why this matters

The default orchestration model assumes the project is quiescent. The After-Swarm Mode model assumes the opposite — drift is normal, every gate runs as if the working tree could change at any moment, and the skill's behavior is robust to that drift instead of fragile to it.

The user's hard-won lesson: trying to "freeze" the project before rationalization fails (you can't reliably freeze concurrent agents you don't control). The right move is to design every gate to be drift-tolerant.

---

## Tier Selection Cheat-Sheet

| Symptom | Suggested tier | Reason |
|---|---|---|
| <2 worktrees AND <30 branches | Solo (Quick mode) | Worker overhead dominates |
| 5–20 worktrees, 30–80 branches, single language | Pair (Standard) | One reviews the other's borderlines |
| 20+ worktrees, 80+ branches, single language | Squad (Standard / Comprehensive) | Multiple branch families warrant family-grouping |
| Mixed-language repo (Rust + TS + Python) | Squad with language-specialist subagents (Comprehensive) | Per-language fingerprinting gives stronger signal |
| ≥10 colliding-file groups | Squad+ with dedicated harmonization-planner | Phase 7 fan-out per file group |
| ≥3 dirty worktrees with >10 untracked files each | Squad+ + After-Swarm Mode | Concurrent agents likely active; harden gates |
| Production code recovery stakes | Swarm + multi-model triangulation (Comprehensive) | Errors compound; second-opinion review on every harmonization |
| Compliance / audit context | Council with all 3 models + adversarial reader | Council's plan-level + per-bucket re-confirmation |
| Resume of an interrupted prior run | Same tier as original + integrity-check pass | Phase 3 re-verifies the existing bundle; Phase 8 reads `apply_log.tsv` to skip already-applied rows |

---

## Cross-References

- Phase definitions + per-phase fan-out width: [PHASES.md](PHASES.md)
- Verbatim per-mode kickoff text: [KICKOFF-PROMPTS.md](KICKOFF-PROMPTS.md)
- Per-subagent prompt templates: [AGENT-PROMPTS.md](AGENT-PROMPTS.md)
- Multi-model paths (A → B → C): [MULTI-MODEL-TRIANGULATION.md](MULTI-MODEL-TRIANGULATION.md)
- Reading stances per phase: [MODES-OF-REASONING.md](MODES-OF-REASONING.md)
- Recovery from worker failures (the F1–F4 series above): [INCIDENT-PLAYBOOK.md](INCIDENT-PLAYBOOK.md)
- The Polish Bar dimensions (verification of orchestration outputs): [POLISH-BAR.md](POLISH-BAR.md)
