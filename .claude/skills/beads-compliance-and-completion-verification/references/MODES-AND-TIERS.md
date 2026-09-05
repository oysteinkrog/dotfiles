# MODES-AND-TIERS.md — Mode Variants and Tier Routing

The audit can run at very different depths and scales. **Mode** picks the depth (which phases run, which artifacts are produced); **tier** picks the parallelism shape (single agent vs. swarm).

> **Both are auto-suggested at bootstrap.** The user can override at the up-front confirmation step. The choices are recorded in `manifest.json` so reproducibility is preserved.

---

## Mode variants

| Mode | Wall time | Phases run | Skips | When to use |
|------|----------:|-----------|-------|-------------|
| **Triage** | 5–15 min | 1, 2 (cheap), 3 (heuristic), 5 (heuristic), 8 (binary verdict only) | 4, 6, 7, 10 | Before standup; "is anything obviously rotten?" |
| **Standard** | 30–90 min | 1–9 | 10 (Phase 10 spot-check) | Default for periodic audits, monthly cadence |
| **Comprehensive** | 2–4 hours | 1–10, with multi-model triangulation in Phase 10 | nothing | Quarterly audit, pre-release, when stakes are high |
| **Tripwire** | 5 min, autonomous | 1, 2, 3, 5, 8, convergence-check | 4 (no test execution), 9 (report-only) | CI/cron mode; flags regression vs. last green pass |
| **Single-bead** | 1–5 min | All phases on ONE bead | Phase 7 cross-bead synthesis | Pre-merge audit; deep-dive on a single suspicious bead |
| **Re-verification** | 15–60 min | 1, then per-bead diff: only re-score beads whose evidence changed | Phases 2, 3 for unchanged beads | Subsequent passes after remediation |
| **Onboarding** | 1–3 hours | All, with lower threshold + CASS mining for project-specific patterns | nothing | First audit on a project that has never been audited |
| **Sample** | 25–60 min | All phases, but applied to a stratified 15–50-bead sample | none, but coverage is sampled | **Recommended default for 1500+ closed beads.** Comprehensive passes are usually unaffordable at that scale; sample preserves the headline signal at ~100× lower cost. Banner explicitly states "Sample audit — N of M closed beads audited." |

### Mode selection logic (auto-suggest at bootstrap)

```
if existing_audit_dir AND prior_pass_within_7_days:
    → re-verification
elif no_existing_audit_dir AND closed_beads > 50:
    → onboarding
elif called_from_CI:
    → tripwire
elif single bead ID provided:
    → single-bead
elif user_requested_quick_check:
    → triage
elif closed_beads >= 1500 AND not user_requested("comprehensive"):
    → sample          # Comprehensive on 1500+ closed beads is rarely affordable;
                      # sample mode preserves the headline signal cheaply.
elif closed_beads > 200 OR pre_release_context:
    → comprehensive
else:
    → standard (default)
```

### Per-mode artifact differences

| Artifact | Triage | Standard | Comprehensive | Tripwire | Single-bead | Re-verify | Onboarding | Sample |
|----------|:------:|:--------:|:-------------:|:--------:|:-----------:|:---------:|:----------:|:------:|
| inventory.jsonl              | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ (full inventory; sample selected from it) |
| spec.json (per bead)         | ✓ | ✓ | ✓ | ✓ | ✓ | only changed | ✓ | sample only |
| evidence.json                | heuristic | ✓ | ✓ | heuristic | ✓ | only changed | ✓ | sample only |
| compliance.json (raw runs)   | — | ✓ | ✓ | — | ✓ | only changed | ✓ | sample only |
| theater.json                 | ✓ | ✓ | ✓ | ✓ | ✓ | only changed | ✓ | sample only |
| test_depth.json              | — | ✓ | ✓ | — | ✓ | only changed | ✓ | sample only |
| synthesis.md                 | — | ✓ | ✓ | — | — | ✓ | ✓ | sample-scoped |
| scorecard.md                 | binary verdict | full | full + triangulated | binary | full | only changed | full | full per sampled bead |
| REPORT.md                    | minimal | full | full + trends | minimal | one-bead | full | full + onboarding notes | full + "Sample audit — N of M" banner |
| remediation.md               | report-only | per policy | per policy | report-only | report-only | per policy | report-only (review first) | report-only (review first) |
| convergence.json             | — | — | ✓ | ✓ | — | ✓ | — (first pass) | — (sampled passes don't converge) |
| sample.txt                   | — | — | — | — | — | — | — | ✓ (the 15–50 sampled bead IDs, one per line) |

---

## Tier routing (by bead universe size)

The number of beads in the inventory determines the parallelism shape. Tier auto-suggests subagent count and orchestration approach.

> **Hard cap:** never exceed **10 concurrent agents**, regardless of how
> many closed beads the project has. Past field testing showed that NTM panes,
> Agent Mail file-reservation contention, and prompt-cache thrashing all
> degrade rapidly past this point — bigger swarms produce *less* throughput,
> not more, and confuse one another.

| Tier | Closed-bead count | Parallelism | Orchestration | Coordination |
|------|:-----------------:|:-----------:|---------------|--------------|
| **Solo**        | < 20            | 1 (serial)         | Main agent runs every phase itself                        | None needed |
| **Pair**        | 20–150          | 2–3 subagents      | Main agent fans Phase 2-6 across a small pool             | Local file flock; no Agent Mail needed |
| **Squad**       | 150–500         | 4–5 subagents      | Main agent + per-phase subagent pool                      | `/agent-mail` `file_reservation_paths` for shared fixtures |
| **Battalion**   | 500–1000        | 6–7 subagents      | Multiple subagent batches with per-batch coordinator      | `/agent-mail` + start of `/ntm` panes |
| **Swarm**       | 1000–1500       | 8–9 subagents      | `/multi-agent-swarm-workflow` over `/ntm` panes           | Full Agent Mail coordination + `/bv` for triage |
| **Mega-swarm**  | 1500+ **OR** Sample mode preferred | **10** (hard cap)  | Same as Swarm — additional bead mass queues, doesn't widen the swarm | Full coordination; consider Sample mode (below) |

### Sample mode for very large universes (≥ 1500 closed beads)

When the closed-bead universe is large enough that a comprehensive pass is
genuinely unaffordable (cost, wall time, or both), prefer **Sample mode**:

* Pick a stratified sample of 15–50 beads:
  * 5 highest PageRank "keystone" beads (`bv --robot-insights | jq '.Influencers'`)
  * 5 top "bottleneck" beads (`bv --robot-insights | jq '.HITSAuthorities'` etc.)
  * 5–40 random recent closures, weighted to P0/P1
* Run the full 10-phase pipeline against the sample only.
* The master report banner explicitly states "Sample audit — N of M closed
  beads audited" so downstream readers don't mistake it for a comprehensive pass.

The 10-agent cap applies to Sample mode too: even with a 1,644-bead universe,
the audit is cheaper to run on 15 beads with 10 agents than to widen the swarm
to chase the long tail of thinly-relevant beads. Sample mode is the
**recommended** mode for projects past 1,500 closed beads unless a quarterly
comprehensive audit is explicitly required (compliance, regulatory, post-incident).

Mode router selects Sample mode automatically when `closed_beads ≥ 1500` AND
no `--mode comprehensive` override is present.

### Solo tier playbook

```bash
# Use the wrapper script for end-to-end execution.
./scripts/run-pass.sh <project> --threshold 700 --policy completion-debt
```

### Pair tier playbook

```bash
# Bootstrap, then fan Phase 2-6 across 2-4 subagents.
PASS_DIR=$(./scripts/bootstrap-audit.sh <project> 700 standard)
./scripts/inventory-beads.sh <project> "$PASS_DIR"

# Spawn 2 subagents, each handling half the beads (alphabetical split).
# Each subagent is /subagents/bead-spec-extractor.md → ...evidence-gatherer →
# ...compliance-verifier → ...theater-detector → ...test-depth-auditor.
```

### Squad tier playbook

Use `/agent-mail` to coordinate. Reserve shared resources:
- DB ports (each compliance-verifier gets a unique port).
- Fixture files (any file under `tests/fixtures/`).
- The audit dir's `passes/<UTC>/` (only the orchestrator writes here).

```python
# Pseudo-orchestrator
agent_mail.macro_start_session(project_key=PROJECT, agent_name="orchestrator")
for batch in chunks(closed_beads, batch_size=10):
    spawn_subagent(
        kind="compliance-verifier",
        beads=batch,
        port=allocate_port(),
        thread_id=f"audit-{PASS_ID}-batch-{batch_index}",
    )
```

### Battalion / Swarm / Mega-swarm tier playbook

Use `/multi-agent-swarm-workflow`. Pick agent count from the tier table —
**never exceed 10**, even for 5000-bead projects. If the math says you need
more, you actually need Sample mode instead.

```bash
# Spawn weighted ntm panes per /open-beads-weighted-tmux-agent-sessions.
# Each pane runs a phase 2-6 subagent on a slice of the bead universe.
# Phase 7 / 8 / 9 / 10 run on a single coordinator pane.
#
# Replace --beads-per-agent so total agents ≤ 10. For a 1,200-bead universe
# at Swarm tier (8-9 agents), aim for ~150 beads/agent.
ntm spawn audit-swarm-$(date +%s) \
  --agents "claude-code,codex,gemini" \
  --weights "0.5,0.3,0.2" \
  --beads-per-agent 150 \
  --policy completion-debt
```

The orchestrator pane periodically:
1. Polls per-pane progress (`ntm tail <pane-name>`).
2. Re-distributes beads if a pane goes rate-limited.
3. Once Phase 6 is complete on every bead, runs Phase 7 → 8 → 9 → 10 itself.

### Why the 10-agent cap

Field-testing on real audits past `coding_agent_session_search` (1,644 closed
beads) found three failure modes that get worse linearly past 10 concurrent
agents:

1. **Agent Mail file-reservation thrash.** With 12+ agents claiming
   `tests/fixtures/**` simultaneously, the conflict-retry loop grows to dominate
   wall time.
2. **NTM pane saturation / jank.** ntm's polling becomes laggy past about a
   dozen panes; orchestrator instructions miss panes.
3. **Prompt-cache fragmentation.** Each agent has its own cache. With many
   agents on tight deadlines, the prompt cache hit rate drops and per-bead
   token spend climbs.

So the rule is: **scale work via Sample mode, not via more agents**.

---

## Mode × Tier matrix

| Tier ↓ \ Mode →   | Triage | Standard | Comprehensive | Tripwire | Single-bead | Re-verify | Onboarding | Sample |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| Solo (1)          | ✓ | ✓ | ✓ (slow) | ✓ | ✓ | ✓ | ✓ (slow) | ✓ |
| Pair (2-3)        | ✓ | ✓ | ✓ | ✓ | n/a | ✓ | ✓ | ✓ |
| Squad (4-5)       | overkill | ✓ | ✓ | overkill | n/a | ✓ | ✓ | ✓ |
| Battalion (6-7)   | overkill | ✓ | ✓ | overkill | n/a | ✓ | ✓ | ✓ |
| Swarm (8-9)       | overkill | overkill | ✓ | overkill | n/a | ✓ | ✓ | ✓ |
| Mega-swarm (10)   | overkill | overkill | ✓ (queues) | overkill | n/a | ✓ | ✓ | **recommended** |

The intersection cells indicate which mode/tier combinations make sense. Don't use Swarm/Mega-swarm for Triage — the spin-up cost dominates the work. For Mega-swarm tier (1500+ closed beads), Sample mode is the recommended default unless a comprehensive audit is explicitly required.

---

## Cost / time accounting

The manifest records (per pass):

```json
"cost": {
  "wall_time_seconds": 1234,
  "subagent_invocations": 47,
  "estimated_token_cost_usd": 0.85,
  "tier": "squad",
  "mode": "standard",
  "parallelism": 6
}
```

These are populated by the orchestrator at end-of-pass. Trends across passes (in `trends.md`) help the user predict cost for future audits.

### Rough cost heuristics (for budgeting)

| Tier        | Tokens per bead (avg) | Cost per bead @ Opus |
|-------------|----------------------:|---------------------:|
| Solo        | 8,000                 | $0.06                |
| Pair        | 6,000 (some context shared) | $0.045         |
| Squad       | 5,000                 | $0.04                |
| Battalion   | 4,500                 | $0.034               |
| Swarm       | 4,000 (best amortization) | $0.03            |
| Mega-swarm  | 4,000 (capped at 10)  | $0.03                |

A 200-closed-bead audit at Squad tier ≈ 200 × $0.04 = **$8** in Opus tokens. (Subscription accounts amortize this to $0.)

For Mega-swarm tier on 1,644 closed beads: comprehensive ≈ 1,644 × $0.03 = $49 (real money). Sample mode at 15 beads ≈ 15 × $0.03 = **$0.45**, ~100× cheaper while preserving the headline signal.

---

## Mode/tier override at confirmation

The skill should always show the auto-suggested mode + tier and let the user override:

```
Auto-suggested: mode=standard, tier=squad (you have 247 closed beads).
  - Estimated wall time: 60-90 min
  - Estimated cost: ~$10 in tokens (free if on Claude Max)
  - Phases run: 1-9 (Phase 10 spot-check skipped)

Override?
  [s]tandard (default), [t]riage, [c]omprehensive, t[r]ipwire,
  [o]nboarding, [1]single-bead, [v]erification
```
