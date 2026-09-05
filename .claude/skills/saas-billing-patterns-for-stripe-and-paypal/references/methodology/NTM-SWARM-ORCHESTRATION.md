# NTM Swarm Orchestration for Billing Runs

> **Scope boundary.** This is a billing-specific coordination guardrail. For generic pane management, account health, terminal recovery, or NTM mechanics, use `/ntm`, `/vibing-with-ntm`, `/multi-agent-swarm-workflow`, or `/code-review-gemini-swarm-with-ntm` directly.

Use this file only after `phase0_scope_decision.md` says the run is T4+ or P0-with-multiple-bundles and the work needs multiple billing bundle owners at once.

Skip in Solo, Pair, and ordinary Squad tiers. A narrow feature, T1/T2 audit, or one-bundle incident should not load this file.

---

## When to use

- `audit-and-fix` mode on a multi-product billing platform (T4+).
- `compliance-pass` mode where evidence pack must be assembled fast.
- `harden-incident` mode for a P0 with multiple bundles affected.
- `migration` mode where parallel bundle work is needed.

## When not to use

- One bounded `add-feature` request.
- T1/T2 greenfield or early-stage audit.
- Generic CI, git, support, or process cleanup.
- A billing run with unresolved scope; finish `phase0_scope_decision.md` first.

---

## The swarm shape (core bundle-owner shape)

```
Orchestrator (you) — pane 0
├── B10 Schema implementer — pane 1
├── B20 Constants implementer — pane 2
├── B30 Checkout implementer — pane 3
├── B40 Webhooks implementer — pane 4
├── B50 Security implementer — pane 5
├── B60 State implementer — pane 6
├── B70 Dunning implementer — pane 7
├── B80 Teams implementer — pane 8
├── B90 Reliability implementer — pane 9
├── B100 Analytics implementer — pane 10
└── B110 Operations implementer — pane 11
```

Plus a "harmonizer" pane that watches for cross-bundle drift. This diagram is the core B10-B110 shape; add one owner for every activated extended bundle in `phase0_scope_decision.md` (for example B25, B35, B45, B55, B65, B75, B85, B95, B105, or B115-B145). Do not use the core diagram as a scope override.

---

## Spawning the swarm

```bash
# Per /ntm SKILL.md
ntm new --session billing-audit-${TIMESTAMP} --layout 4x3

# Send each pane its initial context. The scope decision, not this doc,
# is the source of truth for activated bundles.
ACTIVATED_BUNDLES=$(awk '/^- B[0-9]+/ { print $2 }' .billing_workspace/phase0_scope_decision.md | sort -u)
for bundle in $ACTIVATED_BUNDLES; do
  pane_idx=$(map_bundle_to_pane $bundle)
  ntm send --pane $pane_idx --message "$(cat .billing_workspace/kickoff_$bundle.md)"
done
```

Each pane gets a kickoff message that includes:
- The skill's SKILL.md path (for context).
- The pane's bundle name.
- The pane's tasks from `phase4_implementation_plan.md`.
- The Agent Mail credentials (for coordination).

---

## Coordination protocol

Every pane is its own agent. They MUST coordinate via Agent Mail (per `references/methodology/ORCHESTRATION.md`):

```
# At pane start:
ensure_project(project_key=<absolute project path>)
register_agent(project_key, program="claude-code", model="opus-4.7", agent_name="bundle-B40-implementer")

# Before editing a shared file:
file_reservation_paths(project_key, agent_name, paths=["src/lib/webhooks/inbound.ts"], ttl_seconds=3600, exclusive=true, reason="B40-task-T-018")

# Send updates to other panes via threads:
send_message(thread_id="billing-run-7-phase-5", subject="[B40] Started on canonical writer refactor", body="...", to=["bundle-B50-implementer"])
```

---

## Orchestrator loop (the main agent's job)

```
While Phase 5 not complete:
  1. macro_start_session() to refresh Agent Mail state
  2. Read panes' status (via ntm capture-pane or via Agent Mail messages)
  3. Detect blockers:
     - Pane stuck on file reservation? Resolve.
     - Pane completed bundle? Send next task.
     - Pane reported error? Investigate.
  4. Update phase4_implementation_plan.md with progress.
  5. Trigger harmonizer pane if cross-bundle changes detected.
  6. Sleep 5 min; loop.
```

This is the "vibing-with-ntm" pattern from `/vibing-with-ntm` — orchestrator stays in the loop until convergence.

---

## Billing completion truth stack

Pane text is a signal, not evidence. A billing bundle is complete only when these agree:

1. **Scope truth:** the bundle is included in `phase0_scope_decision.md` or was added there with a later trigger.
2. **Artifact truth:** the pane wrote the promised archaeology, coverage, plan, implementation, test, or evidence artifact.
3. **Repo truth:** the diff touches the assigned billing files and no unrelated bundle was expanded.
4. **Verification truth:** the pane ran the bundle's required tests, audits, or provider read-only checks and recorded output.
5. **Coordination truth:** Agent Mail reservations/messages or the fallback coordination table match the claimed state.

If a pane has generic tool trouble, switch to `/vibing-with-ntm` or `/ntm` for recovery. This billing file should not grow a terminal-debugging appendix.

---

## Per-bundle dependency wave

Per ORCHESTRATION.md § Wave model, NTM execution goes in waves. The core dependency wave is:

```
Wave 1 (parallel): B10 Schema, B20 Constants
  → both must finish before any Wave 2 starts.

Wave 2 (parallel): B40 Webhooks, B30 Checkout, B50 Security

Wave 3 (parallel): B60 State, B80 Teams

Wave 4 (parallel): B70 Dunning, B90 Reliability, B100 Analytics

Wave 5 (sequential): B110 Operations
```

Place activated extended bundles in the earliest safe wave based on their dependencies: B25/B35/B45/B55 can usually start after B10/B20; B65 waits for the bundle it tests; B75/B85/B95/B105/B115-B145 depend on their touched schema/provider surfaces. If unsure, serialize the extended bundle behind the core bundle it extends.

The orchestrator script:

```bash
# Wave 1
spawn_panes B10 B20
wait_for_panes B10 B20  # blocks until both complete

# Wave 2
spawn_panes B40 B30 B50
wait_for_panes B40 B30 B50

# ... etc
```

`wait_for_panes` polls Agent Mail for "completed" thread messages.

---

## Evidence capture from each pane

Every pane produces artifacts in `.billing_workspace/`:

```
.billing_workspace/
├── pane_B10_log.md
├── pane_B20_log.md
├── ...
├── pane_orchestrator_log.md
└── phase5_summary.md  (orchestrator-aggregated)
```

The orchestrator periodically aggregates pane logs into `phase5_summary.md` so the human user can see overall progress.

Each pane log must stay billing-specific:

```markdown
# Pane <bundle> Log

Scope: <bundle and task ids>
Files reserved:
Files changed:
Pattern sections read:
Polish Bar dimensions affected:
Tests/audits run:
Open blockers:
Ready for harmonization: <yes/no>
```

---

## Termination protocol

Phase 5 termination:

```
All panes report "completed" via Agent Mail thread.
Orchestrator runs verify-source-coverage.sh + verify polish-bar checks.
If all green:
  ntm send --pane all --message "Phase 5 complete; tear down panes."
  ntm kill --session billing-audit-${TIMESTAMP}
Else:
  Investigate red gates; re-spawn relevant panes.
```

Before killing panes, do a convergence triple-check:

1. **Artifact check:** every pane's promised artifact exists and is non-placeholder.
2. **Repo check:** changed files match the task plan; no assigned file is silently uncommitted, untested, or absent.
3. **Coordination check:** Agent Mail/beads or fallback coordination says the same work is complete.

Only after all three agree should the orchestrator tear down panes.

---

## Common NTM swarm mistakes

- **Spawn 12 panes without coordination.** Merge conflicts every commit.
- **No Agent Mail file reservations.** Multiple panes edit the same file.
- **Orchestrator treats pane prose as completion.** Billing completion requires artifacts, repo diff, verification, and coordination evidence.
- **No wave model.** B40 starts before B10 finishes; depends on schema that doesn't exist.
- **No termination protocol.** Panes run forever; cost explodes.
- **Triangulation panes share the same Agent Mail identity.** Can't tell who said what.
- **Swarm used for T2 work.** Coordination overhead exceeds the value of parallelism.

---

## Integration with existing methodology

- `ORCHESTRATION.md` defines the wave model + tiers.
- `TRIANGULATION.md` defines the consensus rules.
- THIS file defines billing-specific evidence gates for a T4+ swarm.
- `MULTI-MODEL-TRIANGULATION-PROMPTS.md` defines the per-model prompts.

Reading order for a swarm run: ORCHESTRATION → THIS file → TRIANGULATION + PROMPTS.
