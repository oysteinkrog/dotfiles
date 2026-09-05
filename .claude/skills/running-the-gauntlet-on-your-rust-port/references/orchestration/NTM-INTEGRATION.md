# NTM Integration — How the Gauntlet Runs ON NTM

> **The One Rule.** NTM is the gauntlet's native orchestrator, not a side-channel viewer. Every dispatch in every phase routes through `ntm spawn`, `ntm send`, `ntm pipeline run`, or one of the `--robot-*` automation surfaces. Discover the contract first, then dispatch with the smallest reversible surface that proves what just happened.

This document is the load-bearing contract between this skill's 16-phase loop and the `ntm` skill's command surface (`~/.claude/skills/ntm/SKILL.md`). Cross-link liberally — do not re-derive the NTM mechanics here.

---

## Contents

- [Why NTM is the gauntlet's native orchestrator](#why-ntm-is-the-gauntlets-native-orchestrator)
- [The mandatory NTM loop (gauntlet-scoped)](#the-mandatory-ntm-loop-gauntlet-scoped)
- [Per-phase NTM dispatch table](#per-phase-ntm-dispatch-table)
- [Pane assignment per cc_N lane](#pane-assignment-per-cc_n-lane)
- [NTM serve API integration](#ntm-serve-api-integration)
- [Robot-mode discipline](#robot-mode-discipline)
- [Pipeline schema versioning](#pipeline-schema-versioning)
- [Failure modes and recovery](#failure-modes-and-recovery)
- [Anti-patterns](#anti-patterns)
- [Setup checklist](#setup-checklist)
- [Cross-references into the `/ntm` skill](#cross-references-into-the-ntm-skill)

---

## Why NTM is the gauntlet's native orchestrator

The gauntlet has four orchestration needs that map exactly onto NTM primitives. No other runner (bash background jobs, plain tmux, raw shell scripts, ad-hoc `&`/`wait`) provides all four:

| Gauntlet need | NTM primitive | Why other runners fail |
|---|---|---|
| **Live visibility** of 4–12 simultaneously executing subagents (cc_1 conformance, cc_2 perf, cc_3 surface, cc_4 soak), each emitting flamegraph paths, bench JSON, FailureBundle ids, oracle divergence counts | tmux panes per subagent, typed by agent kind (`cc`/`cod`/`gmi`); `ntm activity --watch` for live-state polling; `ntm --robot-tail` for non-retiling sampling | Bash `&` discards stdout interleaving; ANSI cursor escapes from one subagent overwrite another; no per-process activity classification |
| **Round-by-round dispatch decisions** (Phase 11 fires Phases 5–10 per round, gated on `convergence-tracker.sh`) | `ntm --robot-snapshot` JSON envelope; `ntm work triage --json` for prioritized work; `ntm --robot-attention --attention-cursor=<N>` to block until something actionable | Bash polling burns wall time; no structured event stream; cursors can't be replayed |
| **Declarative phase fan-out** (Phase 1 fans per crate, Phase 6 fans per behavior class, Phase 15 fans per soak runner) | NTM pipeline YAML schema v2.0 (`schema_version: "2.0"`) with `parallel:` blocks, `wait_for_acks`, `on_error: retry`, `loop:` for round-bound iteration | Bash heredocs aren't resumable; one failed subjob kills the whole `wait`; no per-step state file |
| **bv-integrated work distribution** — the gauntlet's bead graph (Phase 13) drives per-pane assignment for Phases 14+ | `ntm assign --auto --strategy=dependency` reads `bv --robot-triage`; `ntm work next` returns the highest-leverage ready bead; `--reserve-files` plumbs Agent Mail through the assignment | Hand-rolled work selection drifts from the bead graph within one round; no file-reservation handshake |

Concrete comparison — dispatching Phase 9 baseline (perf + conformance + surface in parallel):

```bash
# Bash background — what the gauntlet must NOT do
( cd $WORKSPACE && ./scripts/baseline-runner-perf.sh > perf.log 2>&1 ) &
( cd $WORKSPACE && ./scripts/baseline-runner-conformance.sh > conf.log 2>&1 ) &
( cd $WORKSPACE && ./scripts/baseline-runner-surface.sh > surf.log 2>&1 ) &
wait        # blocking; no per-job restart; no live tail; no Agent-Mail reservations
```

```bash
# NTM-native — what the gauntlet DOES
ntm pipeline run \
  .claude/skills/running-the-gauntlet-on-your-rust-port/assets/ntm-pipelines/gauntlet-phase-09-baseline.yaml \
  --session "$WORKSPACE_BASENAME" \
  --var workspace_path="$WORKSPACE" \
  --var port_path="$TARGET" \
  --var run_id="r$(date +%Y%m%d-%H%M%S)" \
  --background
ntm pipeline status run-<id>            # live status, not log tail
ntm --robot-attention --attention-cursor=<N>   # blocks until something actionable
```

The bash form gives you three logs and one exit code. The NTM form gives you per-pane activity, per-step status, per-failure restart, structured Agent Mail thread for the per-pillar results, and a resume path if the orchestrator crashes mid-run.

---

## The mandatory NTM loop (gauntlet-scoped)

Restated from `~/.claude/skills/ntm/SKILL.md § The Loop (Mandatory)`, scoped to the gauntlet's phases. Run this every time the orchestrator transitions phases or rounds:

```
1. DISCOVER   -> ntm --robot-capabilities; verify flags used by gauntlet pipelines still exist
              -> read this skill's PHASES.md for current phase contract
2. SNAPSHOT   -> ntm --robot-snapshot; inspect sources/degraded_sources, cursor, panes
              -> read <workspace>/phase<N-1>_*.md outputs from the prior phase
3. SELECT     -> choose the dispatch shape: pipeline YAML (declarative) vs ntm send (one-off)
              -> for round-bound work in Phase 11: always pipeline
4. PROVE      -> fill the gauntlet's NTM action card (below)
5. EXECUTE    -> ntm pipeline run --background (long phases) OR ntm --robot-send (one-shot)
6. VERIFY     -> ntm pipeline status; --robot-attention; check <workspace>/phase<N>_*.md outputs landed
              -> run convergence-tracker.sh if Phase 11
7. CLEANUP    -> ntm pipeline cleanup --older=7d after each completed phase 11 round
              -> release stale reservations; checkpoint the workspace if a major artifact landed
8. REPEAT     -> next phase or next round
```

### Gauntlet-NTM action card (paste this into the orchestrator's session log before any state-changing dispatch)

```markdown
## NTM dispatch: phase-<N>-<bucket> (round <R> if applicable)
- Pipeline file: assets/ntm-pipelines/gauntlet-phase-<NN>-<name>.yaml (or N/A for ntm send)
- Session name: <workspace basename, must equal NTM_PROJECTS_BASE/<basename> directory>
- Live contract checked: ntm --robot-capabilities contains pipeline-run, send, attention; YAML lints with `ntm pipeline lint`
- Evidence before: cursor=<N>; sources=<fresh|degraded list>; panes=<count>; <workspace>/phase<N-1>_*.md outputs present
- cc_N lane scope: cc_1/cc_2/cc_3/cc_4 panes targeted per the per-phase table; user pane excluded
- Reservations: tool://comprehensive-bench, tool://oracle-runner, resource://rch-worker-pool per ORCHESTRATION.md
- Blast radius: panes/files/sessions affected; --robot-send default excludes user pane
- Verification after: <workspace>/phase<N>_*.md exists; convergence-tracker.sh delta; specific artifact path
- Recovery: ntm pipeline cancel <run-id>; ntm --robot-smart-restart=<session> --panes=<N>; resume from <workspace>/<persistent-state>
```

If you cannot fill the card, do a read-only pass first: `ntm --robot-snapshot`, `ntm pipeline list`, `ls <workspace>/phase*.md`. Then dispatch.

---

## Per-phase NTM dispatch table

For every phase in the gauntlet's 16-phase loop, the recommended NTM dispatch shape. Pipeline YAMLs live at `assets/ntm-pipelines/`; marching-order templates at `assets/ntm-marching-orders/`. The convergence signal column tells the orchestrator when to consider the phase complete.

| Phase | NTM dispatch shape | Pane count | Model mix | Pipeline / MO | Convergence signal |
|---|---|---|---|---|---|
| **0** Bootstrap | `ntm spawn <session> --cc=1` (solo); `ntm send --pane=2 --file=phase0_bootstrap_prompt.md` | 1 | `cc=1:opus` | (no pipeline; one-shot) | `phase0_oracle_preflight.json.aggregate_outcome == "green"` |
| **1** RECON | `ntm pipeline run gauntlet-phase-01-recon.yaml` — fans per crate | N = len(crates) + 1 synthesizer | `cc=N:opus --cod=1` | `assets/ntm-pipelines/gauntlet-phase-01-recon.yaml` + `MO-recon-archaeology.md` | every `phase1_recon_<crate>.md` exists; `phase1_unified_recon.md` synthesizer done |
| **2** Pin + contract | `ntm send --pane=2 --file=phase2_scope_prompt.md` | 1 | `cc=1:opus` | (no pipeline; solo, deliberation-heavy) | `docs/contracts/parity_score_contract.toml` weight sum == 1.0 |
| **3** Oracle wiring | `ntm pipeline run gauntlet-phase-03-oracle-wiring.yaml` — per project class | 2–3 | `cc=2:opus --cod=1` | `assets/ntm-pipelines/gauntlet-phase-03-oracle-wiring.yaml` + `MO-oracle-wire.md` | `cargo test -p <port>-harness oracle::tests` green |
| **4** Golden capture | `ntm pipeline exec <session> --stage` (legacy; simple sequential) OR `ntm send --panes=2,3 --file=phase4_golden_prompt.md` | 2 | `cc=2:sonnet` | (no pipeline file required) | Tier 1/2/3 golden artifacts committed |
| **5** Perf harness | `ntm pipeline run gauntlet-phase-09-baseline.yaml` (subset: perf only) | 2 cc_2 panes | `cc=2:opus` | shared with phase 9 | `comprehensive_bench` skeleton + per-workload focused benches build green |
| **6** Conformance harness | `ntm pipeline run gauntlet-phase-06-conformance-harness.yaml` — fans per behavior class + per metamorphic family + per fault category + per crash boundary + per fuzz target + per e-process | 6–8 | `cc=3:opus --cod=2 --gmi=1` | `assets/ntm-pipelines/gauntlet-phase-06-conformance-harness.yaml` | every `crates/<port>-e2e/tests/<behavior>_oracle_e2e.rs` compiles + `oracle-runner` smoke green |
| **7** Surface inventory | `ntm send --pane=4 --file=phase7_surface_prompt.md` (cc_3 lane) | 1 cc_3 pane | `cc=1:opus` | (no pipeline; solo) | `feature_coverage_dashboard` exits 0; weight invariant verified |
| **8** Ledger + mandate | `ntm send --pane=2 --file=phase8_ledger_prompt.md` (solo seeding) | 1 | `cc=1:sonnet` | (no pipeline; solo) | three negative-ledger files + AGENTS.md mandate paragraph committed |
| **9** Baseline | `ntm pipeline run gauntlet-phase-09-baseline.yaml` — three pillars in parallel | 3+ (one per pillar; soak optional) | `cc=2:opus --cod=1` | `assets/ntm-pipelines/gauntlet-phase-09-baseline.yaml` + `MO-baseline-run.md` | three `phase9_baseline_<pillar>.md` files + `.bench-history/<family>.latest.json` per family committed |
| **10** Idea wizard | `ntm send --pane=2 --file=phase10_ideawiz_prompt.md` + `ntm send --pane=3 --file=phase10_advanced_methods_prompt.md` | 2 | `cc=2:opus` | (no pipeline; solo per role) | `phase10_idea_wizard.md` + `phase10_advanced_methods.md` exist |
| **11** Iterate | `ntm pipeline run gauntlet-phase-11-iterate.yaml` — round-cycle, loop until converged | 4–8 + coordinator | `cc=3:opus --cod=1 --gmi=1` | `assets/ntm-pipelines/gauntlet-phase-11-iterate.yaml` | `convergence-tracker.sh` exits 0 |
| **12** Remediation | `ntm send --panes=2,3,4 --file=phase12_remediation_prompt.md` (one per pillar) | 3 | `cc=3:opus` | (no pipeline; per-pillar parallel sends) | per-pillar `phase12_remediation_<pillar>.md` files exist |
| **13** Beads handoff | `ntm send --pane=2 --file=phase13_beads_prompt.md`; then `ntm assign --auto --strategy=dependency` | 1 author + N workers | `cc=2:opus` | (no pipeline; solo author, then assign-fanout) | `br dep cycles` empty; `bv --robot-insights` Cycles empty |
| **14** Fresh eyes | `ntm pipeline run gauntlet-phase-14-fresh-eyes.yaml` — 3 reviewers (+ triangulator + red-team for T3+) | 3–6 | `cc=2:opus --cod=2 --gmi=1` (multi-model mandatory) | `assets/ntm-pipelines/gauntlet-phase-14-fresh-eyes.yaml` + `MO-fresh-eyes-pass.md` | two consecutive rounds with zero NEW findings from all three reviewers |
| **15** Soak | `ntm pipeline run gauntlet-phase-15-soak.yaml` — seven rch-offloaded soak runners | 7 dispatched to `rch` | `cc=2:opus --cod=1 --gmi=1` | `assets/ntm-pipelines/gauntlet-phase-15-soak.yaml` + `MO-soak-dispatch.md` | every `<workspace>/soak/<runner>/summary.json` exists with pass verdict; no `TrueDivergence` |
| **16** Final | `ntm send --panes=2,3,4 --file=phase16_final_prompt.md` (three authors parallel) | 3 | `cc=3:opus` | (no pipeline; per-document parallel sends) | three documents + `certification_bundle/` exist |

**Reading this table for an actual run.** For Phase 11 round 7 (example):

```bash
ntm pipeline run \
  ~/.claude/skills/running-the-gauntlet-on-your-rust-port/assets/ntm-pipelines/gauntlet-phase-11-iterate.yaml \
  --session frankensqlite \
  --var workspace_path=/data/projects/frankensqlite__gauntlet_workspace \
  --var port_path=/data/projects/frankensqlite \
  --var run_id=r20260522-1830-3a8c1d2 \
  --var round=7 \
  --background
```

---

## Pane assignment per cc_N lane

The gauntlet's cc_N lane convention (`references/orchestration/ORCHESTRATION.md § Lane Assignment`) maps to specific NTM spawn shapes. Soft assignment by pillar — pane index 2 owns the cc_1 lane, etc. — minimizes MCP Agent Mail reservation collisions because most work stays in-lane.

| Lane | Spawn shape | Rationale |
|---|---|---|
| **cc_1** (conformance / oracle / differential / metamorphic / fault / crash-boundary) | `--cc=3 --cod=1` | Authoring `*_oracle_e2e.rs` is Claude-Opus-strong (long structured templates, careful invariant reasoning). Codex pane is for cross-checking divergence classification (different reading style catches `TrueDivergence` vs `FloatingPoint` mis-labels). 3 Claude panes = one per behavior-class group when fan-out is wide. |
| **cc_2** (performance / benches / profile-cards / hot-path counters / regression detector) | `--cc=2 --cod=2` | Bench authoring needs the long-context Claude pane for the `comprehensive_bench` skeleton; Codex panes are stronger at iterative microbench tuning + counter wiring (tighter feedback loop, more shell-loop affinity). 2:2 split lets the orchestrator dispatch perf-author + counter-instrumenter in parallel without contention. |
| **cc_3** (surface parity / coverage / feature universe / invariant catalog) | `--cc=2 --gmi=1` | FeatureUniverse + InvariantCatalog reasoning is exhaustive-listing work. Claude handles the long structured tables; Gemini (with its different attention pattern) is the cross-check for missed `pub` items and uncatalogued invariants. No Codex pane here — Codex's strength is incremental edits, not exhaustive enumeration. |
| **cc_4** (fault / crash / soak / e-process / BOCPD / adversarial) | `--cc=2 --cod=1 --gmi=1` | Mixed because soak runners need different cognitive modes: Claude for e-process / BOCPD mathematical reasoning; Codex for fuzz-corpus minimization (short tight loops); Gemini for adversarial-search lens. Long-running jobs dispatched via `rch exec` — these panes act as supervisors, not workers. |

Concrete swarm spawn for a typical T3 squad run (`frankenredis`, RESP-class, full gauntlet):

```bash
ntm spawn frankenredis \
  --cc=3 --cod=1 \                        # cc_1 lane: 3 Claude + 1 Codex
  --label conformance \                   # session name: frankenredis--conformance
  --stagger-mode=smart \
  --marching-orders=/tmp/cc1-onboard.txt
ntm spawn frankenredis \
  --cc=2 --cod=2 \                        # cc_2 lane: 2 Claude + 2 Codex
  --label perf \
  --stagger-mode=smart \
  --marching-orders=/tmp/cc2-onboard.txt
ntm spawn frankenredis \
  --cc=2 --gmi=1 \                        # cc_3 lane: 2 Claude + 1 Gemini
  --label surface \
  --stagger-mode=smart \
  --marching-orders=/tmp/cc3-onboard.txt
ntm spawn frankenredis \
  --cc=2 --cod=1 --gmi=1 \                # cc_4 lane: 2 Claude + 1 Codex + 1 Gemini
  --label soak \
  --stagger-mode=smart \
  --marching-orders=/tmp/cc4-onboard.txt
```

Four labeled sessions; the orchestrator dispatches per-phase pipeline runs against the relevant label (`--session=frankenredis--conformance` for Phase 6, etc.).

For T1/T2 (Solo/Pair), collapse the lanes into one session: `ntm spawn <port> --cc=2 --cod=1 --gmi=1 --no-user` and dispatch per-phase sends to specific pane indices instead of separate labels.

---

## NTM serve API integration

The gauntlet's orchestrator subagent (`subagents/ntm-orchestrator.md`) reads `ntm serve` JSON to make round-by-round dispatch decisions. `ntm serve --port 7337` exposes a REST surface with the same data the `--robot-*` flags return, but it's long-lived and the orchestrator can keep a connection open across an entire Phase 11 round.

```bash
# Start serve once, at orchestrator boot
ntm serve --port 7337 &

# Per-round: query JSON instead of forking ntm processes
curl -s http://localhost:7337/v1/snapshot | jq '.sessions[].panes[] | select(.session=="frankensqlite--conformance")'
curl -s http://localhost:7337/v1/work/triage | jq '.recommendations[:5]'
curl -s http://localhost:7337/v1/attention?cursor=42 | jq '.events[]'
```

The orchestrator uses these endpoints to:

1. **Bootstrap each round** — `/v1/snapshot` returns the current pane state across all four labeled sessions; the orchestrator detects which lane is idle and which is still working.
2. **Pick next dispatches** — `/v1/work/triage` returns bv-prioritized beads (during Phase 13+); the orchestrator decides whether to `ntm assign --auto` or to leave the swarm in flow.
3. **Block on actionable events** — `/v1/attention?cursor=N` is the structured-event analog to `--robot-attention`; the orchestrator can SSE-subscribe or long-poll. Cheaper than forking `ntm --robot-attention` per check.
4. **Cancel runaway pipelines** — `DELETE /v1/pipelines/<run-id>` cancels a Phase 15 soak runner that BOCPD has classified as `ShiftDetected` mid-run.

**Auth.** Default is `auth_mode = local` (loopback only); fine for the gauntlet's local orchestrator. If the orchestrator runs on a different host than the swarm sessions, use `api_key` mode and ship the key via env (`NTM_SERVE_API_KEY`) — never embedded in YAML.

See `~/.claude/skills/ntm/references/SERVE.md` for the full REST route map, auth modes, and OpenAPI endpoint.

---

## Robot-mode discipline

Every gauntlet command in automation MUST use `--robot-*`. Bare TUI surfaces (`ntm dashboard`, `ntm palette`, `ntm view`) are for the human operator. From `~/.claude/skills/ntm/SKILL.md`:

> `ntm view` retiles the operator's tmux layout and returns nothing useful to automation — never call it from automation.

### The gauntlet-specific robot-mode rules

1. **Spawn via `ntm spawn`, query/control via `--robot-*`.** Spawn is a one-shot startup; the orchestrator returns. From that point forward, every read is `ntm --robot-snapshot` / `--robot-tail` / `--robot-is-working`, and every dispatch is `ntm --robot-send` / `ntm pipeline run` / `ntm assign`.
2. **Tail with `--robot-tail`, never `tmux capture-pane` in scripts.** The robot surface is structured (`{pane_index, content, content_hash, last_render_ts}`); raw `capture-pane` loses the metadata.
3. **`--robot-format=toon` for any read >50KB.** Phase 11 round summaries can easily exceed the JSON cost; `toon` saves ~60% tokens at parity-of-content.
4. **`ntm send` is fine for one-off operator dispatches; `--robot-send` is required for pipeline-driven sends.** Reason: `ntm send` invokes CASS dedup which can prompt-block ("similar past send" → `Continue anyway? [y/N]`); `--robot-send` is non-interactive by contract and never blocks.
5. **Verify after every state change.** `ntm pipeline status <run-id>` after every `pipeline run`; `ntm --robot-tail --panes=<N> --lines=20` after every targeted send; `ntm --robot-snapshot | jq '.sessions[].panes[] | select(.activity_state == "ERROR")'` after every round.

### Example: Phase 9 baseline dispatch in robot-discipline

```bash
# WRONG (interactive surfaces, no structured feedback)
ntm dashboard frankensqlite                                  # human-only TUI
ntm send frankensqlite --all "Run the baseline"              # CASS dedup may block; --all hits user pane
tmux capture-pane -p -t frankensqlite:0.2                    # raw, no metadata

# RIGHT
ntm pipeline run assets/ntm-pipelines/gauntlet-phase-09-baseline.yaml \
  --session frankensqlite --var workspace_path=$WORKSPACE --background
RUN_ID=$(ntm pipeline list --json | jq -r '.runs[0].run_id')
ntm pipeline status "$RUN_ID" --json
ntm --robot-attention --attention-cursor=$(ntm --robot-snapshot --robot-format=toon | jq -r '.cursor')
ntm --robot-tail=frankensqlite --panes=2 --lines=50 --robot-format=toon
```

---

## Pipeline schema versioning

All gauntlet pipeline YAMLs pin `schema_version: "2.0"` at the top — this is the current NTM contract per `~/.claude/skills/ntm/references/PIPELINES.md § YAML schema (v2.0)`. The schema is enforced by `/dp/ntm/internal/pipeline/schema.go:11`. Pipelines that omit or specify a wrong version are rejected by `ntm pipeline lint`.

**Lint every pipeline before running:**

```bash
ntm pipeline lint assets/ntm-pipelines/gauntlet-phase-09-baseline.yaml
# Exit 0 = parses + validates; non-zero = bad schema, fix before dispatch
```

**Bump policy.** When NTM bumps the pipeline schema (e.g., 2.0 → 3.0), this skill's pipelines are migrated in one batch — never mix schema versions across the gauntlet's pipelines in the same run. Add the bump to the gauntlet workspace's `phase0_workspace_init.md` so the run knows which schema cohort it used.

---

## Failure modes and recovery

| Failure | Detection | Recovery |
|---|---|---|
| **Pane crashed** mid-phase | `ntm --robot-is-working=<session>` returns `crashed`; `ntm activity --json` shows `STALLED`/`ERROR` | `ntm spawn` with `--auto-restart` if not already; else `ntm --robot-restart-pane=<session> --panes=<N>` then re-dispatch the marching order via `ntm send --pane=<N> --file=<MO>` |
| **Pane stuck** (identical tail ≥3 ticks) | `ntm --robot-tail=<session> --panes=<N> --lines=30` hash unchanged across 3 ticks; `ntm --robot-health-restart-stuck=<session> --stuck-threshold=10m --dry-run` flags it | Follow the unstick ladder from `/vibing-with-ntm`: wake-ping → C-u + send → `--robot-smart-restart` → `--hard-kill` → `--robot-restart-pane` → add+kill. Re-dispatch the same MO with `--no-cass-check`. |
| **Pipeline failed** mid-step | `ntm pipeline status <run-id> --json` returns `state: failed` with `failed_step: <id>` | `ntm pipeline resume <run-id>` if the step is retryable; if the failure is a YAML problem, fix the YAML and `ntm pipeline run` fresh (Phase 11 rounds are idempotent if `round_<N>/` was not partially committed). For Phase 15 soak runners, cancel the run with `ntm pipeline cancel <run-id>` and re-dispatch with a longer `--duration`. |
| **Rate limit** on Claude / Codex / Gemini | `ntm --robot-health-oauth=<session> | jq '.panes[] | select(.rate_limited)'` returns ≥1 pane | `ntm rotate <session> --all-limited` swaps CAAM accounts; or `ntm --robot-switch-account=claude:<acct>`. For Phase 14 (multi-model triangulation), if one model is rate-limited and the round is mostly done, the remaining two models can finalize a partial round; document in `phase14_review_<reviewer>_round_<N>.md`. |
| **CASS dedup blocking sends** in Phase 11 (same prompt every round) | `ntm send` aborts with `similar past send` confirmation | In the per-round marching orders, append a round-rotating suffix: `"... Round ${round} at $(date +%H:%M)"`. Or switch to `--robot-send` (non-interactive, never prompts). Pipeline-driven sends already use `--robot-send` under the hood. |
| **`bv --robot-triage` returns empty** mid-Phase 13 | `ntm work queue-dry --format=json | jq '.queue_dry'` returns `true` | Stop assigning; the bead graph is genuinely empty. Run `ntm work queue-dry --ideate --format=json | jq '.ideation.guard'` to surface candidate beads, then preview with `--create-beads --yes` only if the operator confirms. |
| **Agent Mail down/degraded** | `ntm --robot-snapshot | jq '.sources, .degraded_sources'` shows `agent-mail: stale|unavailable` | Continue without it for ≤2 ticks; use `br update --assignee=...` as the soft coordination lock; backfill the per-phase thread once Agent Mail recovers. |
| **Convergence not reached at round 15** | `convergence-tracker.sh` still exits non-zero | Inspect `round_<N>/synthesis.md` — if every round is producing 2–3 new findings, the idea-wizard / advanced-methods panes are still surfacing real candidates → continue. If the same hypothesis keeps re-spawning, escalate to multi-model triangulation (Phase 14 prep). |

---

## Anti-patterns

| Bad move | Why it fails | Use instead |
|---|---|---|
| Bare `ntm` TUI commands in pipeline YAML (`ntm dashboard`, `ntm view`) | TUI retiles the operator's tmux; returns nothing structured; pipeline step never completes cleanly | Use `--robot-*` surfaces in YAML steps; `ntm view` is forbidden in automation by the `/ntm` skill |
| `ntm spawn` without first probing `ntm --robot-capabilities` | Spawn flags churn between NTM versions (e.g., `--stagger-mode` was added recently); a missing flag aborts the spawn after the orchestrator has committed to it | Probe capabilities at orchestrator boot; cache the contract; refuse to dispatch if a required flag is missing |
| `ntm send` without a marching-order template file | Free-text prompts drift between rounds; CASS dedup catches some but not all; agents do different work because they read different prompts | Always `ntm send --file=<assets/ntm-marching-orders/MO-*.md>`; templates use the `PANE_N` / `ROLE` / `MODEL` substitution convention |
| `ntm pipeline run` without `wait_for_acks` between dispatch steps | The orchestrator advances to the next step before subagents have actually picked up the prior step's prompt; downstream steps read stale state | Every `dispatch_*` step in a gauntlet pipeline has a `wait_for_acks` follow-step with a per-pane reply guard |
| `ntm pipeline run` foreground for Phase 15 soak | Soak runs for days; the orchestrator pane blocks; one rate-limit kills the whole run | Always `--background`; poll status via `ntm pipeline status <run-id>` or the serve API |
| `ntm send --all` without `-s/--skip-first` | Targets the user pane; the operator's zsh sees `zsh: command not found: <truncated-prompt>` and the dispatch fails silently | Use `--cc` / `--cod` / `--panes=2,3,4` explicit selectors; `--all` only with `-s` |
| Using `ntm assign --auto` before Phase 13 | Auto-assignment needs the polished bead graph; pre-Phase-13 assignment grabs unrelated work | `ntm assign` only after `bv --robot-insights | jq '(.Cycles // []) | length == 0'` passes (Phase 13 exit criterion) |
| Mixing `ntm pipeline exec` (legacy) with v2.0 pipelines in the same run | `exec` is the legacy sequential-stage form; it doesn't share state with v2.0 pipelines; rollback / resume semantics differ | Always use `ntm pipeline run` with the v2.0 YAML; reserve `exec` only for ad-hoc operator one-offs |
| Treating `ntm pipeline status` as truth without checking artifact landing | Pipeline can `succeed` (all steps returned 0) while the subagent inside a pane did not actually write `<workspace>/phase<N>_*.md` | After every pipeline completes: verify the artifact files exist with the expected schemas (`scripts/convergence-tracker.sh` does this for Phase 11) |
| Dispatching subagents that read the user's home tmux config | Tmux base-index, status-line, keybindings vary per operator; subagents see different layouts; pane targeting breaks | NTM normalizes pane addressing (`session:pane-index`); subagent prompts never reference raw tmux key chords; all targeting goes through `--panes=` |

---

## Setup checklist

Before the first gauntlet run on a fresh machine:

- [ ] `ntm deps -v` shows green (tmux, git, claude/cod/gmi CLIs installed)
- [ ] `NTM_PROJECTS_BASE` env var points at the parent directory of `<port>__gauntlet_workspace/` (so the session-name → directory mapping works)
- [ ] `ntm --robot-capabilities | jq '.commands[] | select(.name == "pipeline")'` returns the pipeline surface
- [ ] `ntm pipeline lint assets/ntm-pipelines/gauntlet-phase-09-baseline.yaml` exits 0 (proves the schema cohort is supported)
- [ ] `ntm safety install` was run; `~/.ntm/bin` is on `$PATH` ahead of `/usr/bin`
- [ ] `ntm policy show --all | jq '.allowed[]'` allows `cargo`, `rustup`, `git`, `rch`
- [ ] For multi-model triangulation (Phase 14, T3+): `ntm --robot-accounts-list` shows ≥1 healthy account per (`claude`, `codex`, `gemini`)
- [ ] `rch` is installed and `ntm --robot-rch-status` returns `healthy` workers
- [ ] Per-port `AGENTS.md` was read; the gauntlet skill's mandate paragraph was added per Phase 0
- [ ] `ntm serve --port 7337` is running (if the orchestrator subagent will use the REST surface)

---

## Cross-references into the `/ntm` skill

Don't re-derive — link.

| Topic | Where in `/ntm` |
|---|---|
| Full robot-mode flag index | `~/.claude/skills/ntm/references/ROBOT-MODE.md` |
| `ntm spawn` deep reference (agent counts, models, labels, stagger, recipes, personas) | `~/.claude/skills/ntm/references/SPAWN.md` |
| `ntm send` deep reference (selectors, file context, templates, CASS, dist-strategy) | `~/.claude/skills/ntm/references/SEND.md` |
| Pipeline schema v2.0 (steps, parallel, loops, when, output_parse, retry_backoff) | `~/.claude/skills/ntm/references/PIPELINES.md` |
| Work triage + assign (strategies, --reserve-files, watch mode) | `~/.claude/skills/ntm/references/WORK-AND-ASSIGN.md` |
| Serve API (REST routes, auth, OpenAPI) | `~/.claude/skills/ntm/references/SERVE.md` |
| Safety + policy + approvals (DCG passthrough, SLB) | `~/.claude/skills/ntm/references/SAFETY.md` |
| Integration surfaces (DCG, SLB, CAAM, RCH, quota) | `~/.claude/skills/ntm/references/INTEGRATIONS.md` |
| Operator-loop tending, unstick ladder, swarm anti-patterns | `~/.claude/skills/vibing-with-ntm/SKILL.md` |
| Marching-order template shape (origin) | `assets/ntm-marching-orders/MO-02-onboarding.md` |
| Pipeline example (origin shape) | `~/.claude/skills/ntm/assets/pipeline-example.yaml` |
| Deep-review squad pipeline (multi-phase fan-out template) | `assets/ntm-pipelines/deep-review-squad.yaml` |

### See Also (within this skill)

- [ORCHESTRATION.md](ORCHESTRATION.md) — cc_N lanes, reservations, rch offload, communication-purgatory doctrine
- [PARALLEL-FAN-OUT-COOKBOOK.md](PARALLEL-FAN-OUT-COOKBOOK.md) — 6 concrete fan-out patterns this integration layer dispatches via NTM
- [SKILL-BOOTSTRAP.md](SKILL-BOOTSTRAP.md) — Phase 0.5 detail
- [NTM-QUICKSTART.md](NTM-QUICKSTART.md) — "I have NTM, I have a port, 5-command walkthrough"
- [../../subagents/ntm-orchestrator.md](../../subagents/ntm-orchestrator.md) — the subagent that drives this integration
- [../../assets/ntm-pipelines/](../../assets/ntm-pipelines/) — 7 phase-specific pipeline YAMLs
- [../../assets/ntm-marching-orders/](../../assets/ntm-marching-orders/) — 5 phase-specific marching-order templates
