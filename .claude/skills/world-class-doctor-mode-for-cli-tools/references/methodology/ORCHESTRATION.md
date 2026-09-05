# Orchestration — Tiers, Fan-Out, Multi-Model Triangulation

The skill works at four orchestration tiers. Pick based on tool size, available compute, and triangulation appetite.

| Tier | Workers | When | Triangulation |
|------|---------|------|---------------|
| Solo | 1, serial | Tiny tool, ≤ 3 subsystems, ≤ 10 failure modes | None |
| Pair | 2, fan-out on Phase 1/2/4 | Typical CLI, 3–6 subsystems, 10–30 FMs | peer-claude |
| Squad | 4–6, parallel by subsystem | Full CLI suite, 6–12 subsystems, 30–60 FMs | peer-claude or multi-model |
| Swarm | 8–12, beads-driven | Multi-binary toolkit; rewriting an entire diagnostic surface | multi-model in Phase 4 / 7 |

---

## Solo

Single agent runs every phase serially. No fan-out, no Agent Mail, no triangulation. Fastest to start; lowest verification quality.

When to use:
- Pre-1.0 tool with a tiny scope
- Quick `audit-only` runs
- Local experimentation

Limitations:
- Phase 7 fresh-eyes still works (the same agent re-reads its own code with the calibrated prompts), but the "fresh" qualifier is weaker without a fresh subagent.
- No multi-model verification on the irreversible paths.

---

## Pair

Two agents. Phase 1 fans out by subsystem (typically 2–4 subsystems per agent). Phase 4 does the same. Phase 3 collapses to one (by convention, the agent that drew the higher-priority subsystems in Phase 1).

When to use:
- Default for typical CLI tools.
- When `peer-claude` triangulation is enough (one Claude reviewing another).

Coordination:
- Agent Mail file reservations on shared files (`mutate()`, capabilities schema, `--help` text generator).
- Thread id `doctor-<pass>-<phase>-<subsystem>`.
- Beads for inter-agent task handoff.

---

## Squad

4–6 agents. Phase 1, 2, and 4 fan out fully across subsystems. Phase 5 fans out across fixers. Phase 7 dispatches three fresh-eyes agents (one per round) plus an optional triangulator.

When to use:
- Full CLI suite (typical mature project).
- When `multi-model` triangulation is desirable for high-stakes paths.

Coordination:
- Agent Mail with per-subsystem thread.
- Beads with `priority` and `blocked_by` to enforce Phase 3 → Phase 4 ordering.
- File reservations: required.
- One "lead" agent (typically the synthesizer in Phase 3) coordinates Phase 4 dispatch.

---

## Swarm

8–12+ agents. Phase 4 dispatches one implementer per spec; Phase 5 dispatches one safety-runner per fixer; Phase 7 runs the three fresh-eyes prompts in parallel across multiple agents (each agent gets one prompt) per round.

When to use:
- Multi-binary toolkit (e.g., `cargo` + `cargo-deny` + `cargo-audit`).
- Rewriting an entire CLI's diagnostic surface from scratch.
- When the user has compute headroom (e.g., 22 Claude Max accounts; user's setup).

Coordination:
- NTM (terminal multiplexer) for spawning the panes.
- BV (issue triage engine) for task assignment.
- Beads as the source-of-truth for what's done, in progress, blocked.
- Agent Mail for the file reservations and inter-pane chat.
- Multi-model triangulation in Phase 4 (top-N specs) and Phase 7 (fresh-eyes).

Reference patterns:
- `multi-agent-swarm-workflow` skill: full orchestrator playbook.
- `vibing-with-ntm`: tending the swarm.
- `open-beads-weighted-tmux-agent-sessions`: weighting agents by backlog.

---

## Multi-model triangulation (Phase 4 / Phase 7)

Triangulation invokes Codex and Gemini in parallel via the `/multi-model-triangulation` skill. Reserved for:

- **Phase 4**: top-N high-priority specs, the `mutate()` chokepoint, irreversible paths, `--force` paths.
- **Phase 7**: each of the three calibrated review prompts can be sent to all three models simultaneously.

Output: a comparison report (`<workspace>/triangulation_<phase>_<round>.md`). Disagreements are filed as beads if they name a real bug; stylistic disagreements are noted but not actionable.

Cost: triangulation costs 3× tokens per pass. Use selectively — not every phase, not every prompt.

---

## When NOT to fan out

Phase 3 (synthesis) is single-agent by design. The synthesizer's job is to harmonize all the parallel work; fanning out the synthesizer defeats the purpose.

Phase 6 (scorecard) is single-agent. The scorecard generator runs once per pass.

Phase 8 (integration) is single-agent. Wiring is sequential.

Phase 10 cold prober is fresh-context — fanning out (multiple cold probers, each on a distinct task) is fine, but each must remain isolated from the others.

---

## Pacing

Each pass takes:

| Tier | Wall time | Cost | Fresh-eyes rounds |
|------|-----------|------|-------------------|
| Solo | 1–2 hours | 1× | 2–3 (same agent re-reading) |
| Pair | 2–4 hours | 2.5× | 2 (one fresh subagent) |
| Squad | 4–8 hours | 6× | 2–3 (per round, per model if multi-model) |
| Swarm | 8–16 hours | 12×+ | 2 across 3 models = 6 reads per round |

Termination thresholds (median uplift < 25, no regression > 50, two clean fresh-eyes) usually take 1–3 passes for `add` mode and 1–2 passes for `upgrade` mode at any tier.
