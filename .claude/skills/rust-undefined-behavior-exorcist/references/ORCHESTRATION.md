# Orchestration — Subagent Fan-out, Agent Mail, Beads Handoff

How the orchestrator fans work out, coordinates via MCP Agent Mail, and hands off to beads-driven execution.

---

## Orchestration Tiers

Pick based on the source repo's size and unsafe surface (Phase 0 partition).

| Tier | Shape | When |
|---|---|---|
| Solo | 1 worker, serial phases | <500 LOC of unsafe surface; minimal FFI |
| Pair | 2 workers, small fan-out | Typical crate; ≤5 modules of unsafe |
| Squad | 4–8 workers across buckets | Standard project (frankensqlite, asupersync) |
| Swarm | 12+ workers + triangulation | Flagship (FFI-heavy, custom allocator, lock-free DS) |

---

## Run-ID Convention

Every run gets a stable run-id used in mail threads and workspace artifacts:

```
<YYYY-MM-DD>-<short-project-slug>-<run-counter>
```

Example: `2026-05-14-frankensqlite-1`.

The run-id is recorded in `<workspace>/phase0_run.json` and embedded into every Agent Mail thread (`ub-exorcism-<run-id>-<phase>-<bucket>`).

The canonical workspace path is:

```
<source>/.ub-exorcism/<run-id>/
```

The workspace must stay inside the source repo being audited. Do not create a sibling `<project>__ub_exorcism_workspace` directory; artifact-writing scripts reject paths outside `<source>/.ub-exorcism/<run-id>/`.

---

## Agent Mail Setup

```python
ensure_project(project_key="/data/projects/frankensqlite")
register_agent(project_key, name="ub-orchestrator", program="claude", model="opus-4-7")
# One mail thread per phase + per bucket:
macro_prepare_thread(
    project_key,
    thread_id="ub-exorcism-2026-05-14-frankensqlite-1-phase2-aliasing",
    subject="[ub-exorcism] Phase 2 / aliasing"
)
```

### Standard reservations (tools and shared resources)

| Reservation | Reason | Granularity |
|---|---|---|
| `tool://miri/<config>` | One Miri run *per config* at a time; different MIRIFLAGS configs can run in parallel because they each build to a distinct target dir | exclusive *per config* |
| `tool://loom` | Loom runs are single-threaded by design | exclusive |
| `tool://fuzz-corpus/<target>` | Corpus writes must not interleave | exclusive |
| `resource://gpu-0` | For fuzz targets exercising GPU code | exclusive |
| `tool://sanitizer-build/<sanitizer>` | One TSan/ASan/MSan/LSan build at a time *per family*; cross-family compatible | exclusive *per family* |
| `path://<workspace>/UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md` | Single writer at a time during Phase 5 | exclusive, ttl 5min |
| `path://<source>/.beads/` | Beads CLI is not concurrency-safe; Phase 9 holds this for the polish loop | exclusive, ttl 3600s |

**Why per-config sub-locks:** Miri uses a separate target dir per `MIRIFLAGS` set; concurrent runs with *different* configs don't thrash compilation. Use sub-keys (`tool://miri/tree-borrows`, `tool://miri/strict-provenance`, ...) so the four miri-runner subagents in Phase 3 can fan out. The same applies to sanitizers: ASan and TSan can run concurrently (separate build dirs) but two TSan runs cannot.

Reservations use the macro:
```python
macro_file_reservation_cycle(
    project_key,
    agent_name="miri-runner-A",
    paths=["tool://miri/tree-borrows"],   # per-config sub-key; see "Why per-config sub-locks" below
    ttl_seconds=3600,
    exclusive=True,
    reason="ub-exorcism-<run-id>-phase3-miri-tb"
)
```

### Per-phase thread topology

```
Phase 1 RECON       — ub-exorcism-<run>-phase1-<module>     (one per module)
Phase 2 STATIC      — ub-exorcism-<run>-phase2-<bucket>     (one per bucket)
Phase 3 DYNAMIC     — ub-exorcism-<run>-phase3-<tool>       (one per tool family)
Phase 4 SYNTHESIS   — ub-exorcism-<run>-phase4              (single thread)
Phase 5 EXPERIMENT  — ub-exorcism-<run>-phase5-<exp-id>     (one per experiment)
Phase 6 IDEA-WIZARD — ub-exorcism-<run>-phase6              (single thread)
Phase 7 ITERATE     — re-uses 2–6 thread structure with -round-N suffix
Phase 8 REMEDIATION — ub-exorcism-<run>-phase8              (single thread)
Phase 9 BEADS       — ub-exorcism-<run>-phase9              (single thread)
Phase 10 FRESH EYES — ub-exorcism-<run>-phase10             (single thread)
Phase 11 SOAK       — ub-exorcism-<run>-phase11-<campaign>  (one per campaign, long-lived)
Phase 12 FINAL      — ub-exorcism-<run>-phase12             (single thread)
```

---

## Subagent Spawn Protocol

Each subagent receives at invocation:
- `WORKSPACE` — absolute path to the workspace dir
- `SOURCE_PATH` — absolute path to the Rust project being audited
- `RUN_ID` — the run-id
- `PHASE` — phase number
- Phase-specific context (e.g., `BUCKET=aliasing`, `EXP_ID=EXP-007`, `MODULE=fsqlite-mvcc`)

Each subagent reads its corresponding entry in [AGENT-PROMPTS.md](AGENT-PROMPTS.md) for the verbatim instructions.

Each subagent's output is the workspace markdown file for its phase + bucket/module/experiment. It does *not* return narrative text — the orchestrator reads the workspace files for status.

### Failure handling

A subagent that fails (panics, timeouts, returns an error):
1. Writes a `phaseN_<owner>_FAILED.md` with diagnostic info
2. Posts a mail message to its thread with `subject="[FAIL] <reason>"` and `ack_required=true`
3. The orchestrator either: respawns (transient), demotes the finding to `NEEDS_REFINEMENT`, or escalates to the user

Compaction-safe: the orchestrator's resume protocol reads `phaseN_<owner>_FAILED.md` to know what to redo.

---

## Beads Handoff (Phase 9)

After `phase8_remediation_plan.md` is finalized, the `bead-author` subagent:

1. **Reserve** `path://<source-repo>/.beads/` exclusive with TTL 1h.
2. **Init beads** if not already: `br init` in the source repo.
3. **Invoke the conversion prompt** from `/beads-workflow`'s "EXACT PROMPT — Plan to Beads Conversion" against `phase8_remediation_plan.md`:
   > OK so now read ALL of phase8_remediation_plan.md; please take ALL of that and elaborate on it and use it to create a comprehensive and granular set of beads for all this with tasks, subtasks, and dependency structure overlaid, with detailed comments so that the whole thing is totally self-contained and self-documenting (including relevant background, reasoning/justification, considerations, etc.-- anything we'd want our "future self" to know about the goals and intentions and thought process and how it serves the over-arching goals of the project.). The beads should be so detailed that we never need to consult back to the original markdown plan document. Remember to ONLY use the `br` tool to create and modify the beads and add the dependencies. Use ultrathink.

4. **Polish 4–5 rounds**, each with this prompt:
   > Reread AGENTS dot md so it's still fresh in your mind. Check over each bead super carefully — are you sure it makes sense? Is it optimal? Could we change anything to make the system work better for users? If so, revise the beads. It's a lot easier and faster to operate in "plan space" before we start implementing these things! DO NOT OVERSIMPLIFY THINGS! DO NOT LOSE ANY FEATURES OR FUNCTIONALITY! Also, make sure that as part of these beads, we include comprehensive unit tests and e2e test scripts with great, detailed logging so we can be sure that everything is working perfectly after implementation. Remember to ONLY use the `br` tool to create and modify the beads and to add the dependencies to beads. Use ultrathink.

5. **Validate after every polish round**:
   ```bash
   br dep cycles                                # exit code must be 0 + empty output
   bv --robot-insights | jq -e '.Cycles | length == 0'
   # Every remediation bead has at least one test-bead dep AND one docs-bead dep:
   bv --robot-insights | jq -e '
     [.beads[] |
       select(.title | test("Remediat|Fix UB"; "i")) |
       select(([.dependencies // [] | .[] | .target_title]
               | map(test("test|miri|loom|fuzz|property"; "i")) | any) and
              ([.dependencies // [] | .[] | .target_title]
               | map(test("docs|SAFETY|comment"; "i")) | any))]
     | length == ([.beads[] | select(.title | test("Remediat|Fix UB"; "i"))] | length)
   '
   ```
6. **Sync + commit** with explicit user permission:
   ```bash
   br sync --flush-only
   git -C <source-repo> add .beads/
   git -C <source-repo> commit -m "UB-exorcism beads (run <run-id>)"
   ```

---

## Triangulation Hooks

For high-stakes findings (Phase 8 remediation decisions on custom allocator / lock-free DS / FFI surface), the orchestrator invokes `/multi-model-triangulation`:

> Triangulate this remediation decision. Original UB: EXP-NNN. Candidate rewrites: A (rubric: …), B (rubric: …), C (rubric: …). Which is optimal and why? If you disagree with our pick, explain.

The triangulation result is recorded in `phase8_remediation_plan.md` under the finding's `## Triangulation` heading, with both consensus and dissent preserved.

---

## Compaction Survival

The orchestrator can be dropped and resumed at any point. Resume protocol:

1. Read `<workspace>/phase0_run.json` for the run-id and mode.
2. Walk the phase artifacts in order:
   - `phase1_unsafe_surface_inventory.md` — if missing, restart at Phase 1
   - every `phase2_findings_<bucket>.md` — if any is missing or empty, redo that bucket
   - `phase3_dynamic_findings.md` — same
   - `phase4_unified_findings.md` — same
   - `UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md` — count OPEN verdicts; resume Phase 5 if any remain
   - `phase7_convergence_round_<N>.json` — find the highest N; that's the round we're in
3. Re-establish Agent Mail context: read recent threads matching `ub-exorcism-<run-id>-*`.
4. Continue from the first incomplete phase.

The workspace markdowns are *always* the source of truth. The orchestrator never relies on in-memory state.
