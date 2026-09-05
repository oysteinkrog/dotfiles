# MULTI-REPO-AUDIT.md — Portfolio-Level Audit Across Many Projects

When you maintain N projects, you need a portfolio view: which projects are healthy, which are drifting, where are the worst false-closed rates concentrated? `/ru-multi-repo-workflow` provides the orchestration layer.

> **Goal.** One command audits every repo with `.beads/`, then rolls up a single `__audit_portfolio_summary.md` with one row per project. Health-at-a-glance.

---

## Portfolio directory layout

```
/data/projects/
├── frankensqlite/
│   ├── .beads/
│   └── beads_compliance_audit/             ← created INSIDE each project
├── beads_rust/
│   ├── .beads/
│   └── beads_compliance_audit/
├── ntm/
│   ├── .beads/
│   └── beads_compliance_audit/
├── ...
└── __audit_portfolio_summary.md            ← rolled up by this skill
└── __audit_portfolio.html                  ← optional HTML dashboard
```

---

## Discovery

`scripts/portfolio-audit.sh` (described below) discovers repos under a parent directory:

```bash
PARENT="${1:-/data/projects}"
discover_beads_repos() {
  find "$PARENT" -maxdepth 3 -type d -name '.beads' \
    -not -path '*/beads_compliance_audit/*' \
    -not -path '*/target/*' -not -path '*/node_modules/*' \
    -exec dirname {} \;
}
```

If `/ru` is installed, prefer it (it has richer repo discovery and respects user's project list):

```bash
ru list --has-beads --json | jq -r '.[].path'
```

---

## Per-repo audit invocation

For each discovered repo, the orchestrator either:

1. **Runs a fresh audit pass** (Standard mode, report-only policy by default — don't flood N bead graphs with debt beads in one go).
2. **Re-uses the latest audit dir** if `manifest.json#pass_completed_at` is recent (within `--max-age-hours`, default 168 = 1 week).

Per-repo invocation:

```bash
~/.claude/skills/beads-compliance-and-completion-verification/scripts/run-pass.sh \
  "$REPO" \
  --threshold 700 \
  --policy report-only \
  --mode standard \
  >/tmp/portfolio-${REPO_NAME}.log 2>&1 &
```

The orchestrator parallelizes across repos (capped at the user's `--max-parallel`, default 4) and waits for all to finish.

---

## Roll-up format

After every per-repo audit completes, the orchestrator emits `__audit_portfolio_summary.md`:

```markdown
# Portfolio Compliance Summary
Generated: <UTC>  |  Projects audited: <N>  |  Threshold: 700

## Headline

| Metric | Value |
|--------|------:|
| Total beads across portfolio       | 4,892 |
| Total closed beads                  | 3,128 |
| Total false-closed across portfolio | 412 |
| Portfolio false-closed rate         | 13.2% |
| Median per-project score            | 760 |
| Number of converged projects        | 4 / 18 |

## Per-project ranking (by false-closed rate, worst first)

| Project | Closed | False-closed | Rate | Score median | Convergence | Last pass |
|---------|-------:|-------------:|-----:|-------------:|:-----------:|-----------|
| midas-edge        |  87 | 31 | 35.6% | 540 | ✗ | 2026-05-04 |
| asupersync        | 412 | 87 | 21.1% | 680 | ✗ | 2026-05-03 |
| frankensearch     | 198 | 28 | 14.1% | 760 | ✗ | 2026-05-05 |
| frankensqlite     | 234 | 19 |  8.1% | 820 | ~ | 2026-05-05 |
| beads_rust        | 412 | 18 |  4.4% | 880 | ✓ | 2026-05-04 |
| ntm               | 156 |  4 |  2.6% | 920 | ✓ | 2026-05-05 |
| ...               | ... | ... | ... | ... | ... | ... |

## Worst-of-the-worst beads (top 20 by score, lowest first)

| Bead | Project | Score | Title |
|------|---------|------:|-------|
| bd-XXX | midas-edge | 87 | Implement promo validation |
| bd-YYY | asupersync | 152 | Wire fuzzer into CI |
| ... | ... | ... | ... |

## Convergence trends across portfolio

(line chart in HTML version: median score over time across all projects)

## Recommended actions

1. **midas-edge** has the worst false-closed rate (35.6%). Run a focused
   Comprehensive-mode audit + initiate remediation work.
2. **asupersync** has 87 false-closed beads — high absolute count. Tier-by-
   priority and tackle P0/P1 first.
3. **4 of 18 projects converged.** Maintain those with weekly tripwire.
4. **2 projects (oldproject1, oldproject2) have stale audits (> 30 days
   old).** Re-run.
```

---

## Cross-repo bead dependencies

Some bead graphs cite IDs from other repos (rare but exists). Phase 7 of the per-repo audit doesn't catch cross-repo drift; the portfolio orchestrator does:

```bash
# Build a global map: bead-id → repo-path (using each repo's inventory.jsonl).
for AUDIT in "$PARENT"/*/beads_compliance_audit; do
  REPO=$(jq -r .project_path "$AUDIT/manifest.json")
  jq -r --arg repo "$REPO" '.id + "\t" + $repo' \
    "$AUDIT/passes/"*/inventory.jsonl | sort -u
done > /tmp/global_bead_map.tsv

# For each bead's evidence + spec + close reason, search for cross-repo bead IDs.
# Any reference to a bead in another repo is a candidate cross-repo dep.
```

If a bead in repo A references `bd-XYZ` and `bd-XYZ` lives in repo B, the cross-repo synthesis records:

```
| Producer (repo:bead) | Consumer (repo:bead) | Risk |
|----------------------|----------------------|------|
| beads_rust:bd-API-EXPORT | bv:bd-IMPORT-API | bv assumes API stable; verify on every beads_rust release |
```

---

## Portfolio audit script

`scripts/portfolio-audit.sh` (this skill provides):

```bash
#!/usr/bin/env bash
set -euo pipefail
PARENT="${1:-/data/projects}"
MAX_PARALLEL="${2:-4}"
MAX_AGE_HOURS="${3:-168}"

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"

discover_repos() {
  if command -v ru >/dev/null 2>&1; then
    ru list --has-beads --json 2>/dev/null | jq -r '.[].path' || true
  fi
  find "$PARENT" -maxdepth 3 -type d -name '.beads' \
    -not -path '*/beads_compliance_audit/*' \
    -not -path '*/target/*' -not -path '*/node_modules/*' \
    -exec dirname {} \; | sort -u
}

REPOS="$(discover_repos | sort -u)"
echo "Discovered repos:" >&2
echo "$REPOS" | sed 's/^/  /' >&2

# Parallel per-repo audit (poor man's version; use GNU parallel if installed).
N=0
for REPO in $REPOS; do
  AUDIT_DIR="$REPO/beads_compliance_audit"
  # Skip if recent pass exists.
  if [ -f "$AUDIT_DIR/manifest.json" ]; then
    LAST=$(jq -r '.pass_completed_at // empty' "$AUDIT_DIR/manifest.json")
    if [ -n "$LAST" ]; then
      AGE_HOURS=$(( ( $(date +%s) - $(date -d "$LAST" +%s) ) / 3600 ))
      if [ "$AGE_HOURS" -lt "$MAX_AGE_HOURS" ]; then
        echo "Skipping $REPO (last pass $AGE_HOURS hours ago)" >&2
        continue
      fi
    fi
  fi
  ( "$SKILL_DIR/scripts/run-pass.sh" "$REPO" --threshold 700 --policy report-only \
      >/tmp/portfolio-$(basename "$REPO").log 2>&1 ) &
  N=$((N+1))
  if [ $N -ge $MAX_PARALLEL ]; then
    wait -n
    N=$((N-1))
  fi
done
wait

# Roll up into the portfolio summary.
python3 "$SKILL_DIR/scripts/portfolio-rollup.py" "$PARENT" \
  > "$PARENT/__audit_portfolio_summary.md"
```

`scripts/portfolio-rollup.py` reads each audit dir's `manifest.json` + `REPORT.md` and produces the headline / ranking / cross-repo synthesis tables.

---

## Cadence for portfolio audits

| Portfolio size | Cadence |
|----------------|---------|
| < 5 projects | Weekly (Sunday) |
| 5–20 projects | Bi-weekly |
| 20+ projects | Monthly + per-repo tripwire daily |

The portfolio summary is much cheaper than re-running per-repo audits; consume it for triage, then drill into specific repos as needed.

---

## When a project shouldn't be in the portfolio

- Project has no `.beads/` directory (not using beads).
- Project's beads are deliberately stale (archive / read-only project).
- Project is owned by a separate team (their cadence, their audit).
- Project is a fork that diverged (audit the upstream, not the fork).

Maintain a `~/.audit_portfolio_excludes` file with one repo path per line; the discovery step honors it.

---

## Inviting other agents to a portfolio audit

For very large portfolios, spawn `/multi-agent-swarm-workflow` with one pane per repo:

```bash
ntm spawn portfolio-audit-$(date +%s) \
  --agents claude-code,codex \
  --weights 0.7,0.3 \
  --panes-per-repo 1 \
  --command-template '~/.claude/skills/beads-compliance-and-completion-verification/scripts/run-pass.sh {repo} --threshold 700 --policy report-only'
```

Each pane runs a full audit pass on one repo; the orchestrator pane runs the rollup at the end.

---

## Portfolio convergence

A *portfolio* converges when:
- Every project is individually converged.
- Cross-repo dependency drift is zero.
- Portfolio false-closed rate is < 5%.
- The number of "stuck" beads across the portfolio is decreasing pass-over-pass.

This is the high bar. In practice, individual projects converge first; the portfolio converges months later. That's healthy — don't optimize for the portfolio at the expense of per-project rigor.
