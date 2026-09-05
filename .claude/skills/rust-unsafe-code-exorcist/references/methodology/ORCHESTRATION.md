# ORCHESTRATION.md — Multi-Agent Coordination

This audit benefits from parallelism but only along specific axes. Wrong-axis parallelism (e.g., parallel agents fighting over the same `audit/sites/.../site-0142.md`) produces conflicts and lost work. This file specifies the parallelism boundaries.

---

## Partition axes (allowed)

| Phase | Partition axis | Why this axis |
|-------|----------------|---------------|
| 1 — Enumerate | Per crate (workspace) or per top-level module (single crate) | Enumeration tools (ast-grep, cargo-geiger, cargo expand) run per crate naturally |
| 2 — Write-up | Per crate / per module (same as Phase 1 owner) | Continuity of context > marginal parallelism gain |
| 3 — Synthesize | Single agent | Global view requires reading everything |
| 4 — Classify | Per pass, single agent; iteratively (multiple passes) | Cross-site consistency matters; one classifier per pass |
| 5 — Plan-draft | Per refactor cluster (parallel) | Each cluster is self-contained |
| 6 — Adversarial | Per pass, single agent; iteratively | Same as Phase 4; fresh-eyes integrity |
| 7 — Fresh-eyes review | Per pass, single agent (or model-diverse parallel) | Reviewing requires global perspective; can parallelize across models |
| 7 — Tool runs (miri, careful, loom, fuzz, mutants, geiger) | Sequenced (per the runbook order) | Tools have ordering dependencies (e.g., loom depends on cfg) |
| 8 — Bead conversion | Single agent | Bead graph is global |
| 9 — Harness build | Single agent | verify.sh is global |
| 10 — Reviewer-empathy | Single agent (or model-diverse parallel) | Single perspective is the point |

---

## Conflict prevention

When two agents could touch the same file, use [MCP Agent Mail](../../../agent-mail/SKILL.md) file reservations.

### Phase 1+2

```
file_reservation_paths(
    project_key="<audit-dir>",
    agent_name="<enumerator-A>",
    paths=["phase1/<crate-A>__*", "audit/sites/<crate-A>/**"],
    ttl_seconds=7200,
    exclusive=true,
    reason="unsafe-exorcist-phase1+2-crateA"
)
```

Each per-crate agent reserves only its own crate's paths. No cross-crate writes in Phase 1+2.

### Phase 3 (synthesis)

```
file_reservation_paths(
    project_key="<audit-dir>",
    agent_name="<synthesizer>",
    paths=["audit/synthesis/**"],
    ttl_seconds=3600,
    exclusive=true,
    reason="unsafe-exorcist-phase3"
)
```

Single agent; just guards against late Phase 2 writes overrunning into Phase 3.

### Phase 4 (classify) and Phase 6 (adversarial)

Each iterative pass writes into its OWN per-pass file (`pass1_summary.jsonl`, `pass2_summary.jsonl`, ...). The synthesizer agent that computes convergence reads them all but writes only the convergence diff.

```
file_reservation_paths(
    project_key="<audit-dir>",
    agent_name="<classifier-pass-N>",
    paths=["audit/classification/pass<N>_*", "audit/classification/site-*.md"],
    ttl_seconds=3600,
    exclusive=true,
    reason="unsafe-exorcist-phase4-passN"
)
```

The per-site `site-<id>.md` files have an exclusive reservation per pass to prevent racing rewrites.

### Phase 5 (plan-draft)

Per cluster:

```
file_reservation_paths(
    project_key="<audit-dir>",
    agent_name="<planner-<cluster>>",
    paths=["audit/plans/site-<id>.md for each member site"],
    ttl_seconds=7200,
    exclusive=true,
    reason="unsafe-exorcist-phase5-<cluster>"
)
```

Cluster boundaries must be disjoint at the site level. If a site participates in two clusters (rare), the planner agent of cluster A and cluster B coordinate via Agent Mail thread `unsafe-exorcist-cross-cluster-<site-id>`.

### Phase 7 (fresh-eyes)

If running multi-model parallel (Claude + Codex + Gemini), each model writes to its own file:
- `audit/phase7/review-pass-<R>-claude.md`
- `audit/phase7/review-pass-<R>-codex.md`
- `audit/phase7/review-pass-<R>-gemini.md`

Then a single synthesizer reads all three and writes the consensus + dissent.

---

## Thread-ID convention

```
unsafe-exorcist-<run-id>-<phase>[-<partition>]
```

Examples:
- `unsafe-exorcist-2026-05-13-1430-phase1-frankenlibc`
- `unsafe-exorcist-2026-05-13-1430-phase4-pass3`
- `unsafe-exorcist-2026-05-13-1430-phase7-claude`
- `unsafe-exorcist-2026-05-13-1430-cross-cluster-site-0142`

The `<run-id>` is set in Phase 0 (timestamp) and used by EVERY message + reservation.

---

## Orchestrator agent

A single orchestrator agent runs the whole audit. The orchestrator:

1. Sets `run_id`.
2. Sends per-phase kickoff prompts to worker agents.
3. Monitors via Agent Mail inbox + `TaskList` (the harness-level task system, not beads).
4. Computes convergence (Phase 4, Phase 6, Phase 7).
5. Hands off to the next phase when convergence is reached AND the polish-bar dimensions are satisfied for the previous phase's sites.

The orchestrator does NOT do per-site work — that's delegated to worker subagents. The orchestrator's role is bookkeeping + sequencing + escalation.

---

## Tier-to-shape table (mirror of SKILL.md, expanded)

| Tier | Workers | Phase 1+2 | Phase 3 | Phase 4 | Phase 5 | Phase 6 | Phase 7 | When to choose |
|------|---------|-----------|---------|---------|---------|---------|---------|----------------|
| Solo | 1 | serial | serial | serial | serial | serial | serial | <20 sites; single module |
| Pair | 2 | parallel by module | shared | shared | parallel by cluster | shared | shared | 20–100 sites; single crate |
| Squad | 4–6 | parallel by crate | single | single | parallel by cluster | single | model-diverse parallel | 100–500 sites; workspace |
| Swarm | 8–12+ | parallel by crate, beads-driven | single | iterative single | parallel by cluster, beads-driven | iterative single | model-diverse parallel (3 models) | >500 sites; polyrepo; macro-heavy |

"Shared" = same agent that owned Phase 1+2 also does that phase for the partition; "Single" = one agent does it across all partitions; "Iterative" = multiple sequential passes.

---

## Failure / recovery

### Agent crashes mid-phase

The audit dir is the authoritative state. Any agent can be respawned and given the same instructions; it picks up where the previous one left off:
- Phase 1+2: enumerate scans for missing inventory rows; site-analyzer scans for missing write-ups.
- Phase 4: a fresh pass is run; the prior pass's output is just one data point.
- Phase 5: per-cluster plans are independent; missing cluster plans are re-run.

The orchestrator detects "stuck" agents (no progress in 15 min) by reading their Agent Mail inbox + TaskList state. If stuck, the orchestrator sends a continuation prompt; if still stuck, the agent is restarted.

### Rate limits

If a worker agent hits its provider rate limit, the orchestrator pauses that worker, redistributes its remaining work to other workers (where independent), and resumes when the limit recovers. See [vibing-with-ntm](../../../vibing-with-ntm/SKILL.md) for the recovery protocol if running under NTM.

### Convergence stuck

If Phase 4 or Phase 6 fails to converge in ~10 passes:
- Inspect the flip ratio per pass; identify the sites that keep flipping.
- Spawn a single-site investigation agent: read the write-up + classification carefully, identify why classification is unstable, propose a refined rubric clarification.
- If the rubric itself needs revision, this is rare but valid — update [CLASSIFICATION-RUBRIC.md](CLASSIFICATION-RUBRIC.md) (in the audit dir's copy, not the skill itself).

### Tool failure (Phase 7/9)

Miri / loom / fuzz / mutants / geiger can each fail in non-finding ways (network, dependency, compilation error). The harness builder must include retry-with-exponential-backoff for transient failures AND fail loudly for compilation errors.

---

## NTM integration (Swarm tier)

For Swarm-tier runs, use [NTM](../../../ntm/SKILL.md) for orchestration:

```bash
ntm spawn --name unsafe-exorcist-<run-id> \
          --panes 12 \
          --policy safe \
          --robot \
          --pipeline unsafe-exorcist
```

The pipeline definition (per [NTM](../../../ntm/SKILL.md)):

```yaml
# unsafe-exorcist.pipeline.yml
phases:
  - name: phase1-enumerate
    partition: per_crate
    agent: subagents/enumerator.md
    weight: 1
  - name: phase2-write-up
    depends_on: phase1-enumerate
    partition: per_crate
    agent: subagents/site-analyzer.md
    weight: 1
  - name: phase3-synthesize
    depends_on: phase2-write-up
    partition: global
    agent: subagents/synthesizer.md
    weight: 1
  # ... etc
```

NTM panes claim per-phase, per-partition work via beads (created in Phase 8 of the prior run, OR seeded by the orchestrator's initial partition). [vibing-with-ntm](../../../vibing-with-ntm/SKILL.md) tends the swarm — restart wedged panes, redistribute work on convergence, flip to review-only when classification stabilizes.

---

## Multi-model triangulation

For Phase 6 adversarial + Phase 7 fresh-eyes + Phase 10 maintainer-empathy on the HIGHEST-RISK sites:

```
Site selection: top-N risky sites
  - (C) with confidence < 0.7
  - (A) where any reviewer commented "feels under-explored"
  - Sites in the soundness-surface with diff size = large

Per selected site, send to each model:
  - Claude (current model)
  - Codex (via /multi-model-triangulation)
  - Gemini Ultra (via /multi-model-triangulation)
  - Grok (via /multi-model-triangulation)

Each model reads the same materials (write-up + classification + plan) and answers:
  1. Do you agree with the bucket?
  2. Do you spot any soundness issue in the proposed safe rewrite?
  3. Specific objections by line number.

Synthesize:
  - Where all three (Codex + Gemini + Grok) agree with Claude → high confidence.
  - Where one or more disagree → re-classify or refine plan; document in audit/phase10/triangulation-output.md.
```

See [TRIANGULATION.md](TRIANGULATION.md) for the detailed prompt-and-aggregate flow.

---

## Operational metrics

The orchestrator emits these per phase, written to `<audit-dir>/audit/phase<N>_metrics.json`:

```json
{
  "phase": 4,
  "started_at": "2026-05-13T14:30:00Z",
  "completed_at": "2026-05-13T15:42:00Z",
  "passes": 3,
  "final_flip_ratio": 0.027,
  "a_to_c_flips_final": 0,
  "sites": 247,
  "buckets": {"A": 18, "B": 32, "C": 197},
  "agent_minutes": 142,
  "model_tokens": 4500000,
  "agents_spawned": 7,
  "agents_crashed": 0,
  "agents_recovered": 0
}
```

Use these to (a) detect runaway phases (token spend > expected), (b) bill / report agent time, (c) plan future runs (similar projects of similar size will spend similar resources).

---

## Anti-patterns (orchestration-specific)

- **Spawning agents without file reservations.** Two agents writing to the same `audit/sites/.../site-0142.md` clobber each other. Always reserve first.
- **Per-site parallelism in Phase 5.** Sites in the SAME cluster need to be planned together (the cluster's safe wrapper subsumes them). Per-cluster parallelism is fine; per-site is too fine-grained.
- **Cross-model parallelism on every phase.** Multi-model triangulation is for Phase 6/7/10 review only — running every phase across 3 models triples cost without proportional value. The first-pass work is single-model.
- **Reading the prior pass before producing your own (Phase 4/6).** This defeats the iterative-fresh-eyes purpose. Each pass is independent; convergence is the comparison.
- **Folding pre-existing-UB into refactor scope to widen the agent's "wins".** Per AGENTS.md, pre-existing UB is filed separately. The agent's win count is irrelevant.
