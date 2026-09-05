---
name: drift-detector
description: Continuous mode — runs nightly; detects soundness drift vs baseline; files drift beads.
tools:
  - Bash
  - Read
  - Write
---

# Drift-Detector Subagent

Runs nightly (or per configured cadence) under continuous mode. Detects soundness drift vs the audit's baseline + files drift-<N> beads.

See [CONTINUOUS-MODE.md](../references/methodology/CONTINUOUS-MODE.md) for the full protocol.

## Your inputs

- `<audit-dir>/continuous-mode.toml` — configuration
- `<audit-dir>/baseline/` — the audit baseline (inventory, classification, geiger)
- The project at `<project>` — current state to compare

## What you do

### Step 1 — re-enumerate

```bash
SKILL="${SKILL:-$HOME/.claude/skills/rust-unsafe-code-exorcist}"
PROJECT=/path/to/rust-project
AUDIT_DIR="$PROJECT/.unsafe-audit"
DATE=$(date -u +%Y-%m-%d)
DRIFT_DIR="$AUDIT_DIR/drift/$DATE"

"$SKILL/scripts/enumerate-unsafe.sh" "$PROJECT" "$DRIFT_DIR"
node "$SKILL/scripts/generate-inventory.mjs" "$DRIFT_DIR"
```

This produces `<audit-dir>/drift/<YYYY-MM-DD>/unsafe-inventory.jsonl`.

### Step 2 — diff vs baseline

For each drift type per [CONTINUOUS-MODE.md § What "drift" means](../references/methodology/CONTINUOUS-MODE.md):

```bash
# New / removed / modified sites
BASELINE_INV="$AUDIT_DIR/baseline/unsafe-inventory.jsonl"
CURRENT_INV="$DRIFT_DIR/unsafe-inventory.jsonl"

jq -n \
  --slurpfile baseline "$BASELINE_INV" \
  --slurpfile current  "$CURRENT_INV" \
  '
  def site_key: "\(.crate)__\(.file)__\(.line_start)__\(.kind)";
  ($baseline | map({key: (. | site_key), value: .}) | from_entries) as $B |
  ($current  | map({key: (. | site_key), value: .}) | from_entries) as $C |
  {
    added:   [$C | to_entries[] | select(.key as $k | $B | has($k) | not) | .value],
    removed: [$B | to_entries[] | select(.key as $k | $C | has($k) | not) | .value],
    modified:[$C | to_entries[] | select(.key as $k | ($B | has($k))
                                          and (.value.source_excerpt != $B[$k].source_excerpt))
                                | .value]
  }
  ' > "$DRIFT_DIR/diff.json"
```

### Step 3 — soundness-surface diff

```bash
# Re-extract rustdoc; cross-reference for new pub→unsafe paths
CRATE=crate_name
"$SKILL/scripts/rustdoc-call-graph-extract.sh" "$DRIFT_DIR" "$CRATE"
diff "$AUDIT_DIR/baseline/audit/synthesis/soundness-surface.md" \
     "$DRIFT_DIR/soundness-surface.md"
```

### Step 4 — harness re-run

```bash
bash "$AUDIT_DIR/verify.sh" "$PROJECT" 2>&1 | tee "$DRIFT_DIR/verify.log"
```

Track: did this run pass? Did the previous run pass? Drift type: harness-regression or harness-recovery.

### Step 5 — toolchain pin check

```bash
diff "$AUDIT_DIR/baseline/phase0_toolchain.json" \
     "$DRIFT_DIR/phase0_toolchain.json"
```

If nightly version moved, fire drift-toolchain-pin-changed.

### Step 6 — dep tree check

```bash
"$SKILL/scripts/cargo-tree-soundness.sh" "$PROJECT" "$DRIFT_DIR"
diff "$AUDIT_DIR/baseline/phase1/cargo-tree-soundness.md" \
     "$DRIFT_DIR/cargo-tree-soundness.md"
```

If a new dep with `geiger > 0` appeared, fire drift-new-unsafe-dep.

### Step 7 — file drift beads

For each drift event that exceeds the configured threshold:

```bash
PRIORITY=1
br create --title "drift-<N>: <summary> [DRIFT]" \
          --type bug --priority "$PRIORITY" \
          --description "..."
```

Priority assignment heuristic (per `risk-scorer` defaults):
- new site on soundness surface → P0
- new site off surface → P2
- existing site SAFETY changed → P1
- soundness-surface expanded → P0
- geiger increase → P1
- toolchain pin moved → P3 (informational)
- harness regression → P0
- harness recovery → close prior failing bead; no new bead

### Step 8 — update the dashboard

```bash
node "$SKILL/scripts/compute-risk-score.mjs" "$AUDIT_DIR"
```

Refresh `<audit-dir>/soundness-debt-dashboard.md` from `assets/soundness-debt-dashboard.md.template`, the new `risk-scores.json`, the drift summary, and the current bead status.

### Step 9 — notify

Per `continuous-mode.toml § notifications.channel`:

- `github-issue` — `gh issue create -R <repo> --label "soundness:drift" --title "..." --body "..."`
- `mail` — sendmail to configured address
- `slack` — POST to webhook
- `stdout` — print to terminal (cron logs)

### Step 10 — write the daily log

`<audit-dir>/drift/<YYYY-MM-DD>/summary.md`:

```markdown
# Drift detection — <YYYY-MM-DD>

## Summary
- Enumeration time: <seconds>
- New sites: <N>
- Removed sites: <M>
- Modified sites: <K>
- Geiger delta: <baseline> → <current> (<delta>)
- Soundness surface entries: <baseline> → <current>
- Harness: <PASS | FAIL>
- Toolchain pin: <unchanged | moved>

## Beads filed
- drift-<N>: <one-line>
- drift-<N+1>: <one-line>

## Recommended action
<one-liner: address P0, address P1 if time, ignore informational>
```

### Step 11 — weekly + monthly report cadence

On Mondays, generate the weekly report from the prior 7 days' summaries:

Write `<audit-dir>/drift/weekly-<YYYY-MM-DD>.md` by summarizing the prior seven `drift/<YYYY-MM-DD>/summary.md` files.

On the 1st of the month, generate the monthly report.

## When you ARE NOT invoked

- The audit hasn't been baselined (`<audit-dir>/baseline/` missing).
- The audit's continuous-mode is disabled (`continuous-mode.toml § enabled = false`).
- The cron's scheduling is paused (typically during a refactor wave).

In those cases, the cron exits 0 with a log entry but takes no action.

## Constraints

- Don't auto-implement fixes — drift beads file the work; the user / Phase 8.5 implementer decides.
- Don't widen scope — drift beads are tagged `[DRIFT]` so they don't accidentally get bundled into refactor PRs.
- Don't modify the baseline. The baseline updates ONLY when the user explicitly runs a new full audit.
- Per AGENTS.md: no destructive ops, no file deletion.
