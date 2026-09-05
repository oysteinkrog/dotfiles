# Orchestration — Tier Selection, Fan-Out, Triangulation

Maps the run's shape to its agent topology. Adapted from documentation-website's orchestration model and saas-billing's tier-routing.

---

## Orchestration Tiers

Pick the tier based on stash count, project complexity, and stake of the recovered work. Higher tiers consume more agent compute but produce stronger triage signal.

| Tier   | Workers | Models | When |
|--------|---------|--------|------|
| Solo   | 1       | 1      | <10 stashes; routine cleanup; throwaway clone |
| Pair   | 2       | 1–2    | 10–40 stashes; typical agent-swarm aftermath |
| Squad  | 4–6     | 1–2    | 40–150 stashes; mixed-language repo; multiple stash families |
| Swarm  | 8–12+   | 2–3    | 150+ stashes; flagship project; novel-but-stale ratio >20% |
| Council | 12+ + triangulation | 3+ | 300+ stashes; production-critical; security-sensitive code in stashes |

**Mode mapping** (the `Quick / Standard / Comprehensive` modes from SKILL.md):
- Quick → Solo
- Standard → Pair or Squad
- Comprehensive → Squad / Swarm
- Comprehensive + adversarial review → Council

---

## Fan-Out Pattern

The skill's pipeline has two parallelizable phases (4 = triage, 8 = fresh-eyes) and one parallelizable sub-phase (Phase 1 archaeology when the project profile needs language specialists).

```
                Phase 0/1 PROFILE          serial
                Phase 2 INVENTORY          serial
                Phase 3 BUNDLE  (gate)     serial
                ──────────────────
                       │
       ┌───────────────┼───────────────┐
       ▼               ▼               ▼
   Worker A        Worker B   ...  Worker N         Phase 4 — parallel
   (stashes 0-19) (20-39)         (last batch)
       │               │               │
       └───────────────┴───────────────┘
                       ▼
              Phase 5 MERGE  (USER GATE)
                       │
              Phase 6 APPLY    serial (sequential by definition)
              Phase 7 SPLIT    serial
                       │
       ┌───────────────┼───────────────┐
       ▼               ▼               ▼
   Reviewer 1    Reviewer 2  ...   Reviewer 3      Phase 8 — parallel rounds
   (round 1 prompt) (round 2 prompt) (round 3 prompt)
                       │
              Phase 9 CLEANUP  (USER GATE)
              Phase 10 HANDOFF
```

---

## Worker Sizing

Phase 4 triage workers are sized for ~20 stashes each — empirically, that's where the marginal gain of adding workers flattens (per-worker setup cost amortizes well; cross-worker fingerprint deduplication still works at this granularity).

| Stash count | Recommended workers | Rationale |
|-------------|---------------------|-----------|
| 1–9         | 1                   | Solo agent; serial; faster than spawning |
| 10–40       | 2                   | Pair; one reviews the other's borderline verdicts |
| 40–80       | 3–4                 | One per ~20 stashes; minimal coordination overhead |
| 80–160      | 5–8                 | Each worker covers ~20; fingerprint cache shared via Mail thread |
| 160–320     | 10–12               | Diminishing returns past 12 due to file-reservation contention |
| 320+        | 12 + sharded fingerprint cache | Use the same ~20-stash batch rule; document any cache sharding in the run plan |

**Allocation rule:** never give a worker fewer than 5 stashes (overhead dominates) or more than 30 (head-of-line blocking). Adjust the `~20` heuristic based on per-stash diff size.

---

## Multi-Model Triangulation

When verdict ambiguity is high (confidence in the 0.6–0.8 band, or the project is security-sensitive), use multiple models for independent triage on the same batch. The intersection of their verdicts is the high-confidence subset; the disagreement set surfaces to user.

### When to triangulate

- Phase 4 (triage): when >15% of rows have confidence < 0.75 → run a second model on those rows only
- Phase 6 (apply, conflict resolution): when the manual resolution touches >50 lines or crosses architectural boundaries → second-opinion review
- Phase 8 (fresh-eyes): always, for Comprehensive mode
- Phase 11 (user-lens): always, when the run authored ≥3 keeper commits

### How to triangulate

1. **Same prompt, different models.** For each of Claude (Opus 4.7), Codex (GPT-5.5 or equivalent), and Gemini (3.1 Pro), submit the SAME triage worker prompt. Each writes to a model-specific TSV: `triage/batch_<id>_claude.tsv`, `..._codex.tsv`, `..._gemini.tsv`.
2. **Merge by intersection.** A row's verdict is high-confidence if all 3 models agree. If 2 of 3 agree, that's the majority verdict with confidence dropped 0.10. If all 3 disagree, it's `unknown` — surface to user.
3. **Document the triangulation in handoff.** The handoff report includes a "Triangulation summary: of N rows, M had unanimous verdicts, K had majority-only, L surfaced to user".

### Cost-benefit

Triangulation roughly triples the agent-compute cost of Phase 4. Empirically, on the asupersync corpus, triangulation:
- Caught 2 mis-classified `superseded` rows (different signatures missed by single-model)
- Confirmed 87/89 `superseded` verdicts unanimously (low value-add)
- Surfaced 6 borderline rows to user (high value-add)

So triangulation is most valuable when the rubric is operating near its confidence floor — exactly the rows that auto-classify wrong.

---

## Modes-of-Reasoning Composition

In addition to model diversification, the skill can apply *prompt diversification* — same model, different reading stances. Adapted from documentation-website's "literal/skeptical/junior/expert/adversarial" matrix.

| Reader stance | Prompt augmentation | Best applied to |
|--------------|---------------------|-----------------|
| Literal | "Read the diff as a textual pattern; don't interpret intent" | Empty-fingerprint rows (could be whitespace-only) |
| Skeptical | "Assume the rubric's classification is wrong. What evidence would prove it wrong?" | High-confidence rows (sanity check) |
| Junior | "If you're new to this codebase, what would you NOT understand about this diff?" | Conflict-resolution proposals (catches assumed context) |
| Expert | "What language-specific idioms or anti-patterns does this introduce?" | Novel-and-accretive verdicts before commit |
| Adversarial | "What could go wrong if this stash were applied? Compounding errors? Hidden dependencies?" | Phase 8 fresh-eyes round 2 |
| Forensic | "Reconstruct the developer's intent from the diff. What were they trying to accomplish?" | novel-but-stale verdicts (decide whether to rewrite) |

For Comprehensive runs, Phase 8 fresh-eyes uses three rounds with three different stances (e.g., adversarial → forensic → skeptical).

---

## Default Execution Model — Parallel Task Subagents

The skill is designed to run from a **single Claude Code session** with no external orchestration tooling required. The main agent uses the `Task` tool to spawn parallel subagents for the parallelizable phases (4 = triage, 8 = fresh-eyes). Sequential phases (3, 6, 7) run in the main agent or in a single dedicated subagent.

For a 127-stash repo running from a single session:
- Main agent runs Phases 0–3 directly
- Phase 4: spawn 4–6 Task-tool subagents in parallel (one Task call per ~20-stash batch)
- Phase 5: main agent merges, presents decision table, waits for user
- Phase 6: main agent (sequential by definition)
- Phase 7: single Task subagent for partial-split work
- Phase 8: each round runs 3 fresh-eyes prompts as 3 sequential Task subagents (per `subagents/fresh-eyes.md`); ≥2 rounds for Standard mode → 6+ subagent calls total
- Phase 9: main agent (gated by user authorization)
- Phase 10: main agent

This is the **default** and works in any environment that has Claude Code's Task tool. No NTM, no tmux, no extra setup.

Wall time on 127 stashes: typically 2–4 hours including user-gate latencies in Phases 5 and 9.

## Optional: NTM Swarm Topology

If the user already runs an [`/ntm`](../../ntm/SKILL.md) multi-pane swarm (multiple Claude Code / Codex / Gemini panes coordinated via tmux), the skill can map to that topology instead. This is **opt-in only** — invoke via "run stash-janitor under NTM" or similar; otherwise the default single-session model is used.

Under NTM:

```bash
ntm spawn --project <repo> --kind cc --count 1   # main orchestrator pane
ntm spawn --project <repo> --kind cc --count 4   # triage workers (Phase 4)
ntm spawn --project <repo> --kind cod --count 2  # codex reviewers (Phase 8 triangulation, optional)
ntm spawn --project <repo> --kind gmi --count 1  # gemini reviewer (Phase 8 triangulation, optional)
```

The orchestrator pane dispatches marching orders to workers via Agent Mail; worker panes write their batch TSVs and report back; the orchestrator merges and gates Phase 5.

When to choose NTM over the default:
- The user already runs NTM and prefers consistent ergonomics across skills
- The repo is very large (300+ stashes) and the user wants visible per-pane progress
- Multi-model triangulation across multiple Claude/Codex/Gemini accounts in parallel

When to stick with the default:
- Most runs (NTM adds setup overhead that isn't paid back below a few hundred stashes)
- The user isn't already invested in NTM
- The session is interactive and the user wants tight feedback loops

Wall time on 127 stashes under NTM: ~90 minutes wall-clock (vs. ~2–4 hours under default), at the cost of NTM setup overhead.

---

## Coordination Discipline

Every worker reserves its surface via Agent Mail before writing:

```
file_reservation_paths(
  project_key, agent_name,
  paths=[".stash_janitor_workspace/triage/batch_<id>.tsv"],
  ttl_seconds=3600,
  exclusive=true,
  reason="stash-janitor-<run-id>-phase4-batch-<id>"
)
```

Reservations are released when the worker finishes its batch (not at end of session — let other workers reuse the slot if appropriate).

The orchestrator uses the run-id as the Mail thread id. All inter-agent messages are threaded under it. Beads issue id == thread id.

---

## Rollback Contract

If a Phase 6 / Phase 7 apply fails the gates, the worker:
1. Attempts `git apply -R <diff>` to revert
2. If revert succeeds → marks `conflict-skipped`, continues to next keeper
3. If revert fails → halts the run, surfaces the dirty state to user, leaves `apply_log.tsv:gates_status=failed-<gate>` for resumption

Rollback NEVER uses `git reset --hard`, `git clean -fd`, `git checkout -- .` (all DCG-blocked) or `git stash` (would interleave with the canonical stash list).

---

## Tier Selection Cheat-Sheet

| Symptom | Suggested tier |
|---------|----------------|
| <10 stashes | Solo |
| 10–80 stashes, single language | Pair |
| 80+ stashes, single language | Squad |
| Mixed-language repo (Rust + TS + Python) | Squad with language-specialist subagents |
| Stashes reference deleted files heavily (>20% novel-but-stale) | Squad + archaeologist subagent |
| Production code recovery stakes | Swarm + multi-model triangulation |
| Compliance / audit context | Council with all 3 models + adversarial reader |
