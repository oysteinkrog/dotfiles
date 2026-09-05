# SOUNDNESS-DEBT.md — Stakeholder-Facing Debt Tracking

Soundness obligations are a form of technical debt. The skill makes the debt VISIBLE — to the maintainer, the team, the security org, the customers.

The artifact: `<audit-dir>/soundness-debt-dashboard.md`, auto-generated and updated by continuous mode.

---

## What the dashboard shows

The dashboard answers four questions in one page:

1. **What's the debt right now?** — total counts by bucket.
2. **Where's the debt concentrated?** — heat map by module / crate.
3. **What's the trend?** — debt over time (weekly).
4. **What's worth doing first?** — top 10 highest-risk items, with cost / benefit.

---

## Dashboard format

```markdown
# Soundness Debt Dashboard — <Project> — <YYYY-MM-DD>

> Last updated: <UTC timestamp>
> Audit baseline: <commit-hash> dated <date>
> Drift cycles since baseline: <N>

## At a glance

| Bucket | Count | Risk-points | Avg per site |
|--------|-------|-------------|--------------|
| (A) STRICTLY_UNAVOIDABLE | <a> | <pts> | <avg> |
| (B) PERF_ONLY | <b> | <pts> | <avg> |
| (C) REFACTORABLE | <c> | <pts> | <avg> |
| `pre-existing-ub-N` (out of scope) | <p> | <pts> | <avg> |
| **Total open soundness debt** | <total_sites> | **<total_pts>** | <avg> |

## Heat map: debt by crate

| Crate | Sites | Risk-pts | Trend (4 wk) |
|-------|-------|----------|--------------|
| frankenlibc-sys | 142 | 1820 | ▼ -12 |
| frankenfs | 67 | 890 | ▼ -45 |
| frankenfs-cache | 12 | 240 | ▶ 0 |
| frankenfs-net | 8 | 180 | ▲ +8 |
| ... | ... | ... | ... |

## Trend (last 12 weeks)

```
Risk pts: 4500 ─┐
                │ ▄
                │ ▆ ▄
                │ █ ▆ ▆ ▄
                │ █ █ ▆ ▆ ▄
                │ █ █ █ █ ▆ ▆ ▄
                │ █ █ █ █ █ ▆ ▆ ▄
                │ █ █ █ █ █ █ █ ▆ ▆
                │ █ █ █ █ █ █ █ █ █
        3000 ──┘ █ █ █ █ █ █ █ █ █ █ █ █
                  W1 W2 W3 W4 W5 W6 W7 W8 W9 W10 W11 W12
```

**Velocity.** Closing ~120 risk-pts per week. Half-life of current backlog: ~24 weeks.

## Top 10 highest-risk

| Rank | Site | Class | Risk | Cluster | ETA |
|------|------|-------|------|---------|-----|
| 1 | site-0142 | (C) | 80 | R-001 | 1-2 weeks |
| 2 | site-0421 | (C) | 72 | R-001 | (same cluster) |
| 3 | site-0203 | (A) | 50 | none | hardening; 1 day |
| 4 | ... |

## Velocity

| Period | Closed | New (drift) | Net |
|--------|--------|-------------|-----|
| Last 7 days | 12 | 2 | -10 |
| Last 30 days | 48 | 6 | -42 |
| Last 90 days | 142 | 18 | -124 |

## Harness state

- Last `verify.sh` run: <date> (<duration>)
- Result: **GREEN** (all 9 checks pass)
- Geiger: <current> (delta vs baseline: <delta>)
- Cumulative miri runtime: <hours> since baseline

## Open `pre-existing-ub-N` beads

| Bead | Severity | Filed | Status |
|------|----------|-------|--------|
| pre-existing-ub-1 | high | 2026-04-12 | open; deferred to v2.0 |
| pre-existing-ub-2 | medium | 2026-04-22 | in_progress (see PR #1234) |
| ... |

## Next actions

1. **This week.** Close top 3 sites (~200 risk-pts).
2. **Next sprint.** Tackle cluster R-001 (4 sites; ~280 risk-pts).
3. **Before v2.0 release.** Address pre-existing-ub-1 (high severity).

## How to read this

- **Risk-pts** = `BLAST × LIKELIHOOD × DISCOVERABILITY` per [RISK-SCORING.md](RISK-SCORING.md).
- **Trend arrows** = ▼ decreasing (good), ▲ increasing (drift), ▶ stable.
- **(A) sites are obligations** — they stay; we harden their SAFETY comments + clippy lints.
- **(B) sites are gated** by the `safe-only` Cargo feature; downstream users can opt in.
- **(C) sites are work-in-progress** — refactor into safe code with property-test equivalence.
```

---

## Generation cadence

The dashboard is regenerated:

- **At baseline audit end** — sets the initial dashboard.
- **At every drift cron run** — updates totals + adds a snapshot to the trend.
- **At PR merge** — updates "closed sites" + velocity.

The data sources:

- `<audit-dir>/unsafe-inventory.jsonl` (current)
- `<audit-dir>/risk-scores.json` (computed per [RISK-SCORING.md](RISK-SCORING.md))
- `<audit-dir>/audit/synthesis/refactor-clusters.md` (for grouping)
- `<audit-dir>/drift/clean-streak.log` (for trend)
- `br ready --json | jq` (for cluster status)

Run `node scripts/compute-risk-score.mjs <audit-dir>` to refresh `risk-scores.json` and the risk summary. The drift detector or maintainer then refreshes `soundness-debt-dashboard.md` from the dashboard template and those data sources; this skill does not ship a separate dashboard-update script.

---

## Sharing the dashboard

The dashboard is markdown — readable in any Git host's preview. Common publishing channels:

- **Project README.** Embed via `<details>` or link.
- **GitHub Pages.** Auto-published from `<audit-dir>/`.
- **Slack / Discord.** A bot posts the weekly dashboard summary to a channel.
- **Stakeholder email.** Auto-mailed on the monthly cadence.

---

## Anti-patterns

- **Hiding the dashboard.** It's most valuable when SHARED with stakeholders. A private dashboard doesn't drive accountability.
- **Vanity metrics.** "We closed 100 sites!" is meaningful only if the risk-points closed are also reported. Site count alone can be gamed by closing trivial sites.
- **Dashboard without trend.** A single snapshot is less informative than a trend. Always include the last 12 weeks (or audit's lifetime, whichever is shorter).
- **Dashboard with no actions.** If the dashboard doesn't say "what to do this week," it's a report, not a tool.

---

## Per-stakeholder views

The dashboard supports different audiences:

- **Maintainers** — see the full dashboard, focus on Top 10 + clusters.
- **Security team** — sees Top 10 + pre-existing-ub beads.
- **Customers (read-only)** — sees the SECURITY.md summary derived from the dashboard's "At a glance" section. See [SECURITY-MD-GENERATION.md](SECURITY-MD-GENERATION.md).
- **Internal reviewers** — sees per-cluster status + velocity.

A single source-of-truth file with multiple consumers.

---

## Compounding effect

Over time, the dashboard demonstrates the audit's compounding value:

- **Quarter 1.** Baseline audit; dashboard shows "we have X debt."
- **Quarter 2.** First wave of (C) refactors lands; dashboard shows "X dropped by 30%."
- **Quarter 3.** Continuous mode catches drift early; dashboard shows "drift contained."
- **Quarter 4.** Pre-release-gate uses dashboard as evidence; "release confidence is high."

Each quarter, the dashboard is a tangible artifact of "what changed." This is the skill's accretive value made visible.
