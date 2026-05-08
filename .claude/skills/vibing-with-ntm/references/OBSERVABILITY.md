# Observability & Data Quality Judgment

<!-- TOC: Freshness Thresholds | Degradation Semantics | Attention Lifecycle | Per-Pane Truth | Git Log Ground Truth | Scope & Saturation | Convergence Termination | Three-Observation Rule -->

The swarm is only as honest as your last probe. Every orchestrator decision should answer two questions:

1. **Is this data fresh enough to act on?**
2. **Am I inferring or observing?**

Inference without observation is how swarms drift for hours while appearing productive.

## Source Freshness Thresholds

From `/dp/ntm/docs/freshness-contract.md`. Each source has its own cadence — apply the right threshold.

| Source | Fresh | Stale (acceptable) | Critical |
| --- | --- | --- | --- |
| `tmux` | <5s | 5–30s | >30s or "no server running" |
| `beads` | <30s | 30–300s | >300s |
| `mail` | <60s | 60–120s | >120s |
| `quota` (caam) | <300s | 300–900s | >900s |
| `rch` | <60s | 60–300s | >300s |
| `coordinator` | <30s | 30–120s | >120s |

Query source health explicitly:

```bash
ntm --robot-snapshot | jq '.source_health | to_entries[] | {source: .key, status: .value.status, freshness_sec: .value.freshness_sec}'
```

### Decision Rule Per Tier

| Tier | Rule | Example |
| --- | --- | --- |
| Fresh | Act normally. Trust the data. | Dispatch new bead assignment. |
| Stale | Act, but annotate the staleness to the agent. | "Beads data is 180s stale; re-check with `br list --json` before editing." |
| Critical | Do not act on this source. Escalate or resync. | Mail down for 10 min → fall back to `br update --assignee` soft lock. |

## Source Degradation Semantics

When a source is stale/unavailable, `--robot-snapshot` returns `degraded_features` on that source. These are features you **cannot trust** while the source is degraded.

| Source | Degraded Features | Implication | Workaround |
| --- | --- | --- | --- |
| `beads` | `ready_count`, `in_progress_list` | Work queue unreliable | Agents re-run `bv --robot-triage` locally; use `br list --json` directly |
| `mail` | `unread_count`, `urgent_threads` | Mail visibility incomplete | Poll inbox with `ntm --robot-mail-check`; fall back to bead-assignee lock |
| `quota` | `remaining_percent`, `resets_at` | Rate-limit truth unclear | Probe pane directly via ping; use `--robot-health-oauth` where possible |
| `tmux` | `agent_states`, `session_list` | Agent list stale | Sample live pane state via `--robot-is-working` |
| `rch` | `worker_health`, `build_queue` | Remote builds unreliable | Route to local `cargo/go/bun` until recovered |

## Attention Item Lifecycle

From `/dp/ntm/docs/robot-attention-state.md`. Every attention item has a state and transitions.

```
  new ─────▶ seen ─────▶ acknowledged ─────▶ (resolved)
    │          │
    │          └──▶ snoozed (timed) ─────▶ seen (when wakes)
    │
    └──▶ dismissed (operator explicit) ─────▶ (gone, will not re-surface unless underlying event re-fires)
```

States, triggers, and operator actions:

| State | Trigger | When You Should | When You Should Not |
| --- | --- | --- | --- |
| `new` | Event just fired | Read it within one tick | Ignore for >1 tick in a row |
| `seen` | Operator observed it | Act or snooze with reason | Leave indefinitely without a decision |
| `acknowledged` | Operator accepted responsibility | Follow up at next tick | Acknowledge without a plan |
| `snoozed` | Deferred with timer | Revisit when it re-surfaces | Snooze repeatedly (= dismissed-but-not-honest) |
| `dismissed` | Operator explicitly chose to ignore | Only when the underlying signal is known-false | Dismiss to silence noise — fix the noise source instead |
| `pinned` | Must stay visible | Use for long-running concerns | Pin every item (clutter) |

### Actionability Classes

Every attention item comes classified:

| Class | Meaning | Operator Response |
| --- | --- | --- |
| `action_required` | Immediate decision needed (rate limit, stuck pane, build break) | Act now. Do not advance the loop without resolving or explicitly deferring. |
| `interesting` | Worth noticing (file conflict warning, low context) | Inspect; may not need immediate action. |
| `background` | Informational (scheduled task fired, idle pane) | Monitor; no action required. |

**Rule:** Never act on `action_required` items based on stale data. Always check `source_health` for the source that generated the item first.

## Per-Pane Truth Checks

When the snapshot says "idle" but you suspect the pane is actually working (or vice versa), verify directly.

```bash
# 1. Is it really working?
ntm --robot-is-working=myproject --panes=5 --verbose
# Returns: is_working, is_idle, is_rate_limited, is_context_low, confidence, indicators

# 2. Is the agent alive (different from "working")?
ntm --robot-agent-health=myproject --panes=5 --verbose

# 3. What's actually in the pane right now?
ntm --robot-tail=myproject --lines=30 --panes=5

# 4. What does the OS say?
ps -fp $(tmux display -p -t myproject:0.5 '#{pane_pid}')
```

**Confidence scoring** (from `--robot-is-working`):

| Confidence | Meaning | Action |
| --- | --- | --- |
| >0.8 | High confidence in verdict | Trust and act |
| 0.5–0.8 | Indicators mixed | Cross-check with `--robot-agent-health` or tail |
| <0.5 | Very unsure | Do NOT restart; observe another tick first |

## Git Log as Ground Truth

The only reliable productivity signal is commits landing.

```bash
# Last hour of commits attributed to swarm agents (configure authors via .git/config or CODEOWNERS)
git -C /path/to/repo log --since="1 hour ago" --oneline --format='%ar %an %h %s' | head -30

# Just the count
git -C /path/to/repo log --since="1 hour ago" --oneline | wc -l

# Per-author
git -C /path/to/repo log --since="1 hour ago" --format='%an' | sort | uniq -c | sort -rn
```

**Productivity triangulation** (when deciding if a swarm is genuinely working):

1. `--robot-is-working` says ≥N panes busy → observation
2. `ps -eo comm | grep -cE '^(cargo|rustc|go|bun)$'` ≥1 → build processes running
3. `git log --since="30m ago"` shows ≥1 new commit → output landed

If all three hold: genuinely productive. If only 1 or 2, you might be watching prose generation.

## Scope & Saturation Limits

### Orchestrator attention budget

Evidence-based heuristic from real-world swarm operation:

| Operator tier | Max simultaneous projects | Max panes per project |
| --- | --- | --- |
| Single human | 1 project | 6 panes |
| Single orchestrator agent | 3 projects | 6 panes each (≤18 total) |
| 2-tier (meta-orchestrator + per-project) | 7+ projects | 6 panes each |

Beyond these tiers, panes sit idle at prompt boxes for hours before being nudged — the orchestrator simply cannot keep up.

### Context saturation watermark

Per-pane context use:

| Pane context % used | Interpretation | Action |
| --- | --- | --- |
| <60% | Healthy | Keep working |
| 60–85% | Getting tight | Keep working but avoid new large file reads |
| 85–92% | Pre-compact zone | Send "checkpoint + handoff" prompt |
| >92% | Imminent auto-compact | Preemptive restart (beats waiting for compaction) |

## Deterministic Convergence-Termination

The loop MUST terminate when:

1. `git log --since="1 hour ago"` = 0 commits
2. ≥2 consecutive ticks with every pane producing convergence language ("exemplary", "already complete", "no fixes needed", "ready to ship")
3. `br ready --json` = 0 items AND `br list --status=in_progress,claimed` unchanged between ticks

When all three hold: stop, report, exit. Infinite nudging a converged swarm is the most common way orchestrators waste tokens.

```bash
# Convergence detection primitive
commits_1h=$(git -C "$REPO" log --since="1 hour ago" --oneline | wc -l)
ready=$(br ready --json | jq '.issues | length')
inflight=$(br list --status=in_progress,claimed --json | jq '.issues | length')

if [ "$commits_1h" -eq 0 ] && [ "$ready" -eq 0 ] && [ "$inflight" -eq 0 ]; then
  echo "CONVERGED — terminate loop"
fi
```

## The Three-Observation Rule

Before any state-changing action (restart, rotate, reassign, escalate), have **three independent observations**:

1. Real-time signal (`--robot-is-working`, `--robot-health-oauth`)
2. Persistent signal (git log, bead state, coordinator conflicts)
3. Underlying system signal (ps, df, OAuth endpoint, tmux socket)

If any two disagree, resync before acting. If three agree, act with confidence. One observation is a guess, not a judgment.
