# Monorepo Recipe

A monorepo (`turborepo`, `nx`, `rush`, `bazel`-managed, or just a multi-package directory tree) hosts multiple CLI tools. Each tool MAY have its own doctor; they MAY share a chokepoint library.

This file pins the patterns for applying the skill to a monorepo.

---

## Monorepo layout (canonical)

```
monorepo/
├── packages/                          ← TS / JS workspaces
│   ├── tool-a/
│   │   ├── package.json (bin: tool-a)
│   │   ├── src/
│   │   ├── doctor/                    ← per-tool doctor module
│   │   │   ├── detectors/
│   │   │   ├── fixers/
│   │   │   └── index.ts
│   │   └── tests/doctor_fixtures/
│   ├── tool-b/
│   │   └── ... (same shape)
│   └── doctor-core/                   ← shared chokepoint library
│       ├── src/mutate.ts              ← THE chokepoint
│       ├── src/capabilities.ts
│       └── src/runtime.ts
├── crates/                            ← Rust workspaces (alternate layout)
│   ├── tool-a/
│   ├── tool-b/
│   └── doctor-core/
├── tools/                             ← Bazel / Buck targets (another layout)
└── doctor-mode-pass-1.lock            ← cross-package lock during pass
```

The skill's `discover-cli.sh` recognizes each layout and emits per-package binaries.

---

## Per-tool vs. shared workspaces

Three valid choices:

### Choice 1 — One workspace per tool (recommended)

Each tool's pass produces its own `<tool>__doctor_workspace/`:

```
monorepo__doctor_workspace/
├── tool-a__workspace/
│   ├── manifest.json
│   ├── analysis/
│   └── ...
├── tool-b__workspace/
│   └── ...
└── shared_workspace/             ← optional; for cross-tool concerns
```

**Pros:** per-tool isolation; passes can be independent; per-tool scorecard tracking.
**Cons:** more workspaces to manage; cross-tool concerns (shared lockfiles) need a separate workspace.

### Choice 2 — One workspace for the whole monorepo

```
monorepo__doctor_workspace/
├── manifest.json (lists all tools)
├── per_tool_analysis/
│   ├── tool-a/
│   ├── tool-b/
│   └── doctor-core/
└── ...
```

**Pros:** unified scorecard; cross-tool concerns naturally surface.
**Cons:** larger workspace; one tool's regression blocks others'; harder to attribute scores.

### Choice 3 — Per-tool workspaces + a "monorepo-wide" workspace

Combines both. The per-tool workspaces handle each tool's pass; the monorepo workspace tracks cross-cutting (the shared `mutate()` chokepoint, the lockfile family, the build system).

**Recommended for monorepos with > 5 tools.**

---

## Shared `mutate()` chokepoint

For monorepos, the `mutate()` chokepoint MUST be in a shared package (`doctor-core` per [recipes/multi-binary-toolkit.md](../recipes/multi-binary-toolkit.md)). Each tool depends on it.

This means:
- One audit (`scripts/validate-doctor.sh` over `doctor-core`) covers all tools.
- One concurrency primitive (the `.doctor/.doctor.lock` file at monorepo root) serializes all tools.
- One `actions.jsonl` schema across all tools.

```typescript
// packages/doctor-core/src/mutate.ts (TS example)
export async function mutate(ctx: MutateContext, path: string, op: Op): Promise<ActionResult> { ... }
```

```typescript
// packages/tool-a/src/doctor/index.ts
import { mutate, Op } from "@monorepo/doctor-core";
// ... uses mutate() ...
```

---

## Per-tool capabilities, cross-referenced

Each tool's `capabilities --json` lists siblings:

```jsonc
// tool-a doctor capabilities --json
{
  "schema_version": "1.0",
  "tool": "tool-a",
  "siblings": [
    {"name": "tool-b", "doctor_subcommand": "tool-b doctor", "shared_write_scopes": ["packages/shared/"]},
    {"name": "doctor-core", "exposes": "mutate(), Op enum, runtime"}
  ],
  "subsystems": ["state_files", "configs", "schemas"],
  ...
}
```

Agents discovering tool-a learn about tool-b automatically.

---

## Cross-tool failure modes

Monorepo-specific FMs that emerge from coupling:

```
fm-monorepo-version-skew-shared-dep
  symptoms: tool-a depends on shared-utils v1.2; tool-b depends on v1.4; runtime conflict.
  detector: read each tool's lockfile; check shared-dep versions.
  fixer: refuse — version reconciliation is the user's call.

fm-monorepo-circular-dep
  symptoms: tool-a depends on tool-b; tool-b depends on tool-a; build cycles.
  detector: build the dep graph; check for cycles.
  fixer: refuse — manual intervention required.

fm-monorepo-orphan-package
  symptoms: a package directory exists but is in no workspace declaration.
  detector: enumerate packages on disk vs. workspace declarations.
  fixer: refuse (could be deliberate); manual remediation lists orphans.

fm-monorepo-shared-state-file-multi-writer
  symptoms: tool-a's doctor wrote to a shared file; tool-b's doctor's lock claim missed.
  detector: read each tool's actions.jsonl; check for shared-file writes that crossed lock boundaries.
  fixer: refuse — diagnose-only; document the violation.
```

These are Phase 1 archaeology candidates for monorepo passes.

---

## Pass cadence for monorepos

Stage advancement is per-tool:

| Tool | Stage | Notes |
|------|-------|-------|
| tool-a (mature) | Stage 7 | Quarterly re-score |
| tool-b (new) | Stage 4 | First pass landing |
| doctor-core | Stage 6 | Owns the chokepoint; high-impact |

The pass on tool-a doesn't block tool-b. They progress independently. The monorepo-wide pass (per Choice 3) runs less frequently — quarterly cross-cutting check.

---

## Build-system-aware passes

For monorepos with sophisticated build systems (Bazel, Buck, Pants):

- The doctor's invocation goes through `bazel run //tool-a:doctor` rather than direct binary.
- The `discover-cli.sh` accommodates this by reading `BUILD.bazel` files for `binary` rules.
- The `mutate()` chokepoint can use the build system's hermetic-execution sandbox to bound write scope.

For simpler monorepos (turborepo, pnpm workspaces):

- Each package has its own `package.json::bin`.
- `discover-cli.sh` enumerates them.
- The doctor invocations are direct.

---

## Coordination across tools during a pass

When passing tools concurrently:

| Resource | Coordination |
|----------|--------------|
| The shared `doctor-core/src/mutate.ts` | Agent Mail reservation; thread `monorepo-pass-N-shared-mutate` |
| The shared `package.json::engines` | Reservation; cross-tool review |
| The monorepo's `tsconfig.base.json` / `Cargo.toml` workspace section | Reservation; one tool at a time |
| Per-tool sources | Independent; per-tool reservations only |

NTM swarms (per [open-beads-weighted-tmux-agent-sessions](../../open-beads-weighted-tmux-agent-sessions/SKILL.md)) work well: spawn one agent per tool, each in its own pane, with weighted backlog allocation.

---

## Testing in monorepos

Per [testing-conformance-harnesses](../../testing-conformance-harnesses/SKILL.md), conformance harnesses cross-test that all tools' doctors emit compatible artifacts:

```bash
# Run each tool's doctor on a shared corrupted fixture; verify all produce
# valid actions.jsonl; verify their schemas align.
for tool in tool-a tool-b; do
    "$tool" doctor --fix --json | jq -e '.schema_version' > /dev/null
done
```

For Pattern 14 (build-system) doctor variants in monorepos, additional cross-package tests:
- Lockfile coherence (every package's lockfile entry matches the workspace's resolved version).
- Phantom-dep detection across packages.
- Workspace-wide cache integrity.

---

## Operator considerations

The metrics (per [METRICS.md](METRICS.md)) become per-tool dashboards plus a monorepo-wide rollup:

```
monorepo_aggregate_score = weighted_avg(per_tool_aggregate_score, weight=tool_traffic)
```

If `tool-a` is high-traffic and `tool-b` is low, regressions in tool-a weigh more. The dashboard shows both per-tool trends and the rollup.

---

## When monorepos shouldn't use this skill

- Very small monorepos (< 3 tools, < 1k LOC each). Apply Pattern 1 individually; skip the cross-cutting work.
- Monorepos where each tool is a separate language stack with no shared code. Apply Pattern 1 per-tool; treat them as independent projects in the same git repo.
- Monorepos managed by an external build system you don't control (e.g., a vendor's). The wrapper-doctor pattern (Pattern 8) applies; per-tool doctors aren't worth building.

---

## Common pitfalls (monorepos)

- **Sharing too much.** Trying to share more than `mutate()` + capabilities + runtime invariably creates coupling pain. Resist.
- **Per-tool passes that touch shared code without coordination.** Use Agent Mail reservations on the shared paths, every time.
- **Inconsistent doctor versions across tools.** All tools in a monorepo should bump `doctor_version` together (release the monorepo as one), not independently.
- **Monorepo-wide locks blocking per-tool work.** The shared lock is for shared state; per-tool work uses per-tool sub-locks (e.g., `.doctor/.tool-a.lock`).
