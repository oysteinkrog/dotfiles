#!/usr/bin/env bash
# inventory-beads.sh — Phase 1: dump every bead with full payload and cross-reference git history.
#
# Usage:
#   inventory-beads.sh <project-path> <pass-dir>
#
# Outputs (in <pass-dir>):
#   inventory.jsonl       — one bead per line with summary fields
#   doctor.json           — raw br doctor --json
#   cycles.json           — raw br dep cycles --json (must be [])
#   dag.json              — bv --robot-graph --graph-format=json (only when bv installed)
#   beads/<id>/show.json  — full payload per bead
#   beads/<id>/git_xref.txt — commits mentioning the bead ID (closed beads only)
case "${1:-}" in --help|-h) awk '/^[^#]/&&NR>1{exit} NR>1{sub(/^# ?/,"");print}' "$0"; exit 0 ;; esac
set -euo pipefail

# Friendly usage message — prior versions emitted bash's terse default
# `inventory-beads.sh: line N: 2: pass dir`, which forced new operators to
# read the script header to discover that it takes 2 args.
_usage() {
  cat >&2 <<'USAGE'
Usage: inventory-beads.sh <project-path> <pass-dir>

  <project-path>  Absolute path to a project containing .beads/*.db
  <pass-dir>      Absolute path to <audit-dir>/passes/<timestamp>/

Optional env vars:
  INVENTORY_PARALLELISM   xargs -P value (default 8)

Run with --help for the full doc header.
USAGE
  exit 2
}
[ "${1:-}" ] || _usage
[ "${2:-}" ] || _usage
PROJECT="$1"
PASS_DIR="$2"

shopt -s nullglob
DBS=( "$PROJECT/.beads"/*.db )
shopt -u nullglob
if [ "${#DBS[@]}" -eq 0 ]; then
  echo "ERROR: no SQLite DB in $PROJECT/.beads/" >&2
  exit 2
fi
DB="${DBS[0]}"

mkdir -p "$PASS_DIR/beads"

br --db "$DB" doctor --json > "$PASS_DIR/doctor.json"
br --db "$DB" dep cycles --json > "$PASS_DIR/cycles.json" 2>/dev/null || echo '[]' > "$PASS_DIR/cycles.json"

# Optional: dependency graph export via bv. AUDIT-DIRECTORY-LAYOUT.md
# documents `dag.json` as a per-pass artifact "if available". bv may not be
# on PATH (it is a separate tool from br), so this is best-effort. We invoke
# from the project dir because bv auto-discovers `.beads/beads.jsonl` under
# the cwd. Per AGENTS.md, NEVER call bare `bv` (TUI); use `--robot-*` flags.
if command -v bv >/dev/null 2>&1; then
  ( cd "$PROJECT" && bv --robot-graph --graph-format=json ) > "$PASS_DIR/dag.json" 2>/dev/null \
    || echo '{}' > "$PASS_DIR/dag.json"
fi

# Inventory: handle the three shapes br has shipped over time:
#   1) bare array          [...]
#   2) object envelope      {"issues":[...], "total":N, "limit":N, "offset":N, ...}
#   3) JSONL (one per line)
# br list defaults to status=open and paginates (default limit:50). br supports
# `--limit 0` for "unlimited" — much simpler than offset-pagination loops.
RAW="$(br --db "$DB" list \
        --status=open --status=in_progress --status=blocked \
        --status=deferred --status=draft --status=closed \
        --status=tombstone --status=pinned \
        --priority-min=0 --priority-max=4 \
        --limit 0 \
        --json 2>/dev/null || true)"
if [ -z "$RAW" ]; then
  RAW="$(br --db "$DB" list --limit 0 --json 2>/dev/null || br --db "$DB" list --json)"
fi
if printf '%s' "$RAW" | jq -e 'type == "array"' >/dev/null 2>&1; then
  printf '%s' "$RAW" | jq -c '.[]' > "$PASS_DIR/inventory.jsonl"
elif printf '%s' "$RAW" | jq -e 'type == "object" and has("issues")' >/dev/null 2>&1; then
  printf '%s' "$RAW" | jq -c '.issues[]' > "$PASS_DIR/inventory.jsonl"
else
  printf '%s\n' "$RAW" > "$PASS_DIR/inventory.jsonl"
fi

# Per-bead show.json + git_xref.txt. Parallelized via xargs -P so large bead
# universes (1000+) don't take 7+ minutes to inventory. Inner work per bead
# is one `br show` plus (for closed beads) one `git log`. Output deterministic
# because each iteration writes to its own `$PASS_DIR/beads/$ID/` directory.
TOTAL=$(wc -l < "$PASS_DIR/inventory.jsonl" | tr -d ' ')
PARALLELISM="${INVENTORY_PARALLELISM:-8}"

per_bead() {
  local line="$1"
  local ID STATUS BD RAW_SHOW
  ID=$(printf '%s' "$line" | jq -r '.id // empty')
  [ -n "$ID" ] || return 0
  # Status may serialize as a string ("closed") OR as an object ({"Custom": "name"}).
  STATUS=$(printf '%s' "$line" | jq -r '
    .status |
    if type == "string" then .
    elif type == "object" then (to_entries[0].value | tostring)
    else "unknown" end
  ' 2>/dev/null || echo unknown)
  BD="$PASS_DIR/beads/$ID"
  mkdir -p "$BD"

  # Full payload via br show. `br show` may return an ARRAY (since one invocation
  # can show many beads). Normalize to a single object so downstream consumers
  # never need to defend against both shapes.
  RAW_SHOW=""
  RAW_SHOW="$(br --db "$DB" show "$ID" --format json 2>/dev/null || true)"
  if [ -z "$RAW_SHOW" ]; then
    RAW_SHOW="$(br --db "$DB" show "$ID" --json 2>/dev/null || true)"
  fi
  if [ -n "$RAW_SHOW" ]; then
    printf '%s' "$RAW_SHOW" | jq 'if type == "array" then .[0] else . end' > "$BD/show.json"
  else
    printf '%s' "$line" > "$BD/show.json"
  fi

  # Cross-reference git history for closed beads. `-F` (--fixed-strings) so
  # regex meta-chars in $ID (`.`, `+`, `[`, e.g. child-bead IDs like
  # `bd-foo.1`) aren't interpreted as a regex by git log, which would
  # silently match wrong commits — same fix as gather-evidence.sh and
  # anomaly-scan.sh.
  if [ "$STATUS" = "closed" ] && [ -d "$PROJECT/.git" ]; then
    git -C "$PROJECT" log --all -F --grep="$ID" --format='%H%x09%ad%x09%s' --date=iso \
      > "$BD/git_xref.txt" 2>/dev/null || true
  fi
}

export -f per_bead
export PROJECT PASS_DIR DB

# `xargs -P 0` would use unlimited parallelism — bound it to PARALLELISM
# (default 8) so we don't fork-bomb br + git on huge bead universes. -I {}
# binds each line as a single argument; -d '\n' makes whitespace-bearing
# bead bodies (rare but possible in JSONL) safe.
xargs -d '\n' -P "$PARALLELISM" -I {} bash -c 'per_bead "$@"' _ {} \
  < "$PASS_DIR/inventory.jsonl"

# Print summary to stderr.
echo "Inventoried $TOTAL beads to $PASS_DIR/inventory.jsonl (parallelism=$PARALLELISM)" >&2
br --db "$DB" stats --json | jq '.summary' >&2

# Aggregate project-wide git_xref coverage. A closed bead with no commit
# referencing its ID is the per-bead `anomaly_no_git_xref` finding; when MOST
# closed beads have no xref, that signals a project-wide commit-message
# convention gap — i.e. the team writes topic-style commit messages
# (`feat: add X`) instead of including the bead ID. In that case, every
# audit pass would otherwise penalize EVERY closed bead with the same
# anomaly. We emit this as a JSON summary at the pass-dir root so
# anomaly-scan.sh and master-report.py can recognize the project-wide
# convention gap and avoid double-counting it per-bead.
{
  CLOSED_TOTAL=0
  CLOSED_WITH_XREF=0
  for xrf in "$PASS_DIR"/beads/*/git_xref.txt; do
    [ -f "$xrf" ] || continue
    CLOSED_TOTAL=$((CLOSED_TOTAL + 1))
    if [ -s "$xrf" ]; then
      CLOSED_WITH_XREF=$((CLOSED_WITH_XREF + 1))
    fi
  done
  if [ "$CLOSED_TOTAL" -gt 0 ]; then
    PCT=$(awk -v a="$CLOSED_WITH_XREF" -v b="$CLOSED_TOTAL" 'BEGIN{ printf("%.1f", (a*100)/b) }')
  else
    PCT="0.0"
  fi

  # `WIDESPREAD=true` triggers the demotion of every closed bead's
  # `anomaly_no_git_xref` finding from MAJOR to NOTE in anomaly-scan.sh, so
  # the gating logic must not fire on noise. Two guards required:
  #   1. min-N guard — at least 10 closed beads. With 1-2 closed beads,
  #      the percentage is dominated by sample size, not by project convention.
  #      A 1-bead project with no xref would otherwise trigger the warning
  #      (0% < 30%) and silently demote a real per-bead defect.
  #   2. coverage threshold — < 30% of closed beads have any xref.
  WIDESPREAD="false"
  MIN_N_FOR_GAP=10
  if [ "$CLOSED_TOTAL" -ge "$MIN_N_FOR_GAP" ]; then
    if awk -v p="$PCT" 'BEGIN{ exit !(p < 30.0) }'; then
      WIDESPREAD="true"
    fi
  fi
  jq -n \
    --argjson total "$CLOSED_TOTAL" \
    --argjson with_xref "$CLOSED_WITH_XREF" \
    --arg pct "$PCT" \
    --argjson widespread "$WIDESPREAD" \
    --argjson min_n "$MIN_N_FOR_GAP" \
    '{
      closed_beads_total: $total,
      closed_beads_with_git_xref: $with_xref,
      coverage_pct: ($pct | tonumber),
      project_convention_gap_widespread: $widespread,
      threshold_pct: 30.0,
      min_n_for_gap_detection: $min_n,
      note: "When project_convention_gap_widespread=true, anomaly_no_git_xref findings on individual beads reflect a project-wide commit-message convention gap rather than per-bead defects. anomaly-scan.sh demotes these accordingly. Detection requires at least min_n_for_gap_detection closed beads to avoid noise on small projects."
    }' > "$PASS_DIR/git_xref_coverage.json"
  if [ "$WIDESPREAD" = "true" ]; then
    echo "WARNING: only $CLOSED_WITH_XREF/$CLOSED_TOTAL ($PCT%) closed beads have any commit referencing their ID — project-wide convention gap. Per-bead anomaly_no_git_xref findings will be demoted by anomaly-scan.sh." >&2
  elif [ "$CLOSED_TOTAL" -lt "$MIN_N_FOR_GAP" ] && [ "$CLOSED_TOTAL" -gt 0 ]; then
    echo "git_xref coverage: $CLOSED_WITH_XREF/$CLOSED_TOTAL ($PCT%) closed beads have a commit reference (n<$MIN_N_FOR_GAP — too few closed beads to assess project-wide convention)." >&2
  else
    echo "git_xref coverage: $CLOSED_WITH_XREF/$CLOSED_TOTAL ($PCT%) closed beads have a commit reference." >&2
  fi
}

# Print pass dir to stdout for the calling agent.
echo "$PASS_DIR"
