# Orchestration Tiers

How parallelism scales with candidate count and stakes.

---

## Tiers

| Tier | Workers (Phase 4) | Default execution | Wall time est. | When |
|------|-------------------|-------------------|----------------|------|
| Solo | 1 | Main agent only | 20–40 min | <25 candidates; routine cleanup |
| Pair | 2 | 2 parallel Task subagents | 1–2 h | 25–60 candidates |
| Squad | 4–6 | 4–6 parallel Task subagents | 2–4 h | 60–200 candidates |
| Swarm | 8–12 | 8–12 parallel Task subagents | 4–8 h | 200–500 candidates |
| Council | 12+ | Task subagents + multi-model triangulation | 8+ h | 500+ candidates; production-critical; security-sensitive |

The skill's default execution at every tier uses Claude via the Task tool. Multi-model triangulation (Codex / Gemini in addition to Claude) is opt-in at any tier and required for Council; see `MULTI-MODEL-TRIANGULATION.md`.

---

## Phase-by-phase parallelism

| Phase | Solo | Pair | Squad | Swarm | Council |
|-------|------|------|-------|-------|---------|
| 1 Profile | 1 | 1 | 1 | 1 | 1 + triangulation |
| 2 Inventory | 1 | 1 | 1 | 1 + parallel ref-graph | 1 + parallel ref-graph |
| 2.5 Secret scan | 1 | 1 | 1 | 1 | 1 |
| 3 Bundle | 1 | 1 | 1 | 1 + parallel verify | 1 + double-verify |
| 4 Triage | 1 | 2 | 4–6 | 8–12 | 12+ + archaeologist + triangulator |
| 5 Merge | 1 | 1 | 1 | 1 + idea-wizard cross-check | 1 + multi-model adjudication |
| 6 Apply moves | 1 | 1 | 1 | 1 (sequential) | 1 + multi-model conflict review |
| 7 Apply deletes | 1 | 1 | 1 | 1 | 1 |
| 8 Apply gitignore | 1 | 1 | 1 | 1 | 1 |
| 9 Fresh-eyes | 1 round | ≥2 rounds | ≥2 rounds | ≥3 rounds | ≥3 rounds, 3 models |
| 10 Handoff | 1 | 1 | 1 | 1 + bv triage | 1 + bv triage + skill-feedback |
| 11 User-lens | skip | skip | skip | optional | optional |

---

## Optional: NTM Swarm Topology

If the user already runs NTM (multi-pane tmux orchestrator), the skill can use NTM panes instead of Task subagents:

```bash
# Spawn 6 cc panes for triage
ntm spawn <project> 6 cc
# Each pane gets a batch range from candidates.tsv
ntm broadcast 'triage-worker batch <NNN> <project>'
```

NTM is a parallel alternative; it provides:
- Visual progress (each pane runs its own tmux window)
- Persistent sessions across context limits
- Better for long-running Comprehensive runs that span many hours

The skill works without NTM; NTM is an opt-in topology for users who prefer it.

---

## When to escalate tier

If a Standard run is taking >4h and Phase 4 isn't done: escalate to Squad. If the user-facing categorized plan in Phase 5 has many `surface-to-user` rows: escalate to Swarm with archaeologist subagent. If verdict-confidence is consistently <0.8: escalate to Council with multi-model triangulation.

The escalation can happen mid-run; the skill's resumability handles it.

---

## Coordination primitives

When multiple workers are running:

- **Agent Mail file reservations** — workers reserve their batch tsv path so two workers don't collide.
- **Beads thread-id** — `repo-janitor-<run-id>` is the thread id for all coordination messages.
- **Workspace tsv ownership** — each worker writes ONLY to `<workspace>/triage/batch_<NNN>.tsv` for its assigned batch. The merger (Phase 5) reads all of them.

When Agent Mail isn't available, the main agent serializes worker invocations to avoid races.
