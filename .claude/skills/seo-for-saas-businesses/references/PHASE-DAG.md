# PHASE-DAG — Dependency Graph

## TOC

Hard dependencies · Soft dependencies · Parallelizable · Spawning agents in parallel · Re-entry points · Mode-specific shortcuts

```
                          1 — Discovery
                                │
              ┌────────┬────────┼────────┬─────────┐
              ▼        ▼        ▼        ▼         ▼
        2 — Keyword 3 — Tech 4 — Cont 5 — IA  8 — Analytics (wire)
              │        │        │        │         │
              └────────┴───┬────┴────────┘         │
                           ▼                        │
                       6 — Impl ◄───────────────────┘
                           │
                           ▼
                       10 — Fresh-eyes (≥2 clean passes)
                           │
                           ▼
                       11 — Deploy
                           │
                           ▼
                       12 — Verify
                           │
                           ▼
                       8 — Analytics (review) ◄── continuous
                           │
                           ▼
                       7 — Authority (parallel after Impl)
                           │
                           ▼
                       9 — Experimentation
                           │
                           ▼
                       13 — Compounding
```

## Hard dependencies

| Phase | Blocks | Why |
|---|---|---|
| 1 | 3, 4, 5, 8 | No diagnosis without baseline |
| 2 | 4, 5 | Page format and IA depend on intent map |
| 3 | 6 | Implementation requires audit |
| 4 | 6 | Code PRs may publish content |
| 5 | 6 | Link-graph PR depends on IA |
| 6 | 10, 11, 12 | Cannot review or deploy what isn't written |
| 10 | 11 | Two clean passes before ship |
| 11 | 12 | Cannot verify before deploy |

## Soft dependencies

| Phase | Soft-depends on | Notes |
|---|---|---|
| 7 | 6 | Linkable assets typically need to be built and live before outreach |
| 8 | 6 | Dashboard becomes useful once changes ship; wiring can begin earlier |
| 9 | 6, 8 | Experiments need observability + a baseline |
| 13 | 12 | Compounding-wins ideation reviews the live site |

## Parallelizable

- **Within Phase 1:** discovery-crawler, gsc-extractor, cwv-collector, log-analyst run in parallel (`scripts/crawl.ts`, GSC API pull, CrUX API pull, log filter).
- **Within Phase 2:** competitor-researcher per competitor, cluster-researcher per cluster.
- **Within Phase 3:** audit-area subagents per area (crawl, index, render, schema, links, perf, infra, meta, a11y, intl, logs).
- **Within Phase 4:** cluster-writer per cluster.
- **Within Phase 6:** impl-pr per PR.
- **Within Phase 7:** asset-builder per asset.
- **Within Phase 9:** experiment-runner per experiment.
- **Within Phase 10:** fresh-eyes-bughunt, fresh-eyes-trace, fresh-eyes-cross-review run in parallel.

## Spawning agents in parallel

When a phase fans out, spawn the subagents in a single message with multiple tool uses:

```
Agent({ description: "discovery crawl", subagent_type: "Explore", prompt: ... })
Agent({ description: "gsc extract", ... })
Agent({ description: "cwv collect", ... })
Agent({ description: "log analyst", ... })
```

Each subagent writes to its dedicated file under `analyses/`; the orchestrator merges.

## Re-entry points

These phases can be re-entered repeatedly:

- **Phase 4 (content):** each cluster as an independent backlog. Run until marginal lift shrinks.
- **Phase 7 (authority):** ongoing; one campaign at a time.
- **Phase 9 (experimentation):** continuous queue.
- **Phase 13 (compounding):** quarterly.

## Mode-specific shortcuts

| Mode | Skips | Goes deep on |
|---|---|---|
| `traffic-drop-triage` | 4, 5, 7, 9 (initially) | 1, 3, 8 → diagnosis before fix |
| `programmatic-launch-review` | 7, 9 | 5 (IA), 6 (programmatic gates), 12 (verify pre-launch) |
| `migration` | 4 (new content) | [MIGRATION-CHECKLIST](MIGRATION-CHECKLIST.md), then 1, 3, 6, 11, 12 |
| `ai-visibility-pass` | 5 (already in place) | [AI-VISIBILITY](AI-VISIBILITY.md), then 4 rewrites with extractability focus, then 12 for AI bot view |
| `core-update-response` | new content; experimentation | 1, 3, [TRAFFIC-DROP-PLAYBOOK](TRAFFIC-DROP-PLAYBOOK.md) |
| `lifecycle-content` | 7 | 4 with lifecycle-specific briefs (implementation, migration, security, procurement, troubleshooting) |
| `maintenance` | 2, 4 (no new content) | 3 (lite), 8 review, content decay sweep, schema revalidation |
