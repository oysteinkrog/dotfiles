#!/usr/bin/env bash
# verdict-stats.sh — Phase 6 / Phase 11 measurement aid.
#
# Generates triage statistics for SLO checking + handoff inclusion. From
# triage.tsv: per-verdict counts, mean/min/max confidence per verdict, count
# of files with ≥2 non-protected branches touching them (Phase 7 plan size),
# histogram of branches' ahead/behind, count of [gone]-upstream branches,
# count of branches matching each smell-pattern from BRANCH-WORKTREE-SMELLS.md.
#
# Output:
#   <workspace>/verdict_stats.tsv  (machine-readable rollup)
#   <workspace>/verdict_stats.md   (markdown summary for handoff_report.md)
#
# Exit codes:
#   0  ok
#   2  preflight failed (triage / inventory missing)

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=project-root.sh
. "$SCRIPT_DIR/project-root.sh"

usage() {
  cat <<USAGE
Usage: verdict-stats.sh <project-path>

Phase 6 / 11. Reads triage.tsv + branches.tsv; emits verdict_stats.tsv + a
markdown summary block for the handoff report.

Statistics produced:
  - per-verdict counts and confidence (mean / min / max)
  - count of files touched by ≥2 non-protected branches (Phase 7 plan size)
  - histogram of ahead / behind buckets
  - count of [gone]-upstream branches
  - count of branches matching each canonical smell pattern from
    references/BRANCH-WORKTREE-SMELLS.md

Env:
  WORKSPACE   Workspace dir override.

Exit codes:
  0  ok
  2  preflight failed
USAGE
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  '') usage >&2; exit 64 ;;
esac

PROJECT="$1"
PROJECT_ABS="$(resolve_project_root "$PROJECT")" || exit 2
WORKSPACE_DIR="$(resolve_workspace "$PROJECT_ABS")"
TRIAGE="$WORKSPACE_DIR/triage.tsv"
BRANCHES_TSV="$WORKSPACE_DIR/branches.tsv"

[[ -f "$TRIAGE"       ]] || { echo "ERROR: $TRIAGE missing"       >&2; exit 2; }
[[ -f "$BRANCHES_TSV" ]] || { echo "ERROR: $BRANCHES_TSV missing" >&2; exit 2; }

OUT_TSV="$WORKSPACE_DIR/verdict_stats.tsv"
OUT_MD="$WORKSPACE_DIR/verdict_stats.md"

# ---- Per-verdict counts + confidence ----
TOTAL=$(awk 'NR > 1' "$TRIAGE" | wc -l)
TOTAL_BR=$(awk -F'\t' 'NR > 1 && $1 == "branch"'   "$TRIAGE" | wc -l)
TOTAL_WT=$(awk -F'\t' 'NR > 1 && $1 == "worktree"' "$TRIAGE" | wc -l)

# Build verdict-level rollup TSV. We use awk's associative arrays plus
# uninitialized-string min/max sentinels so a real-zero confidence isn't
# silently overwritten (same lesson as git-stash-janitor's verdict-stats.sh).
awk -F'\t' '
  NR > 1 {
    counts[$3]++
    sum_conf[$3] += $4
    n_conf[$3]++
    if (min_conf[$3] == "" || $4 + 0 < min_conf[$3] + 0) min_conf[$3] = $4
    if (max_conf[$3] == "" || $4 + 0 > max_conf[$3] + 0) max_conf[$3] = $4
    apply[$5]++
  }
  END {
    printf "section\tverdict\tcount\tconf_mean\tconf_min\tconf_max\n"
    for (v in counts) {
      m = (n_conf[v] > 0 ? sum_conf[v] / n_conf[v] : 0)
      printf "verdict\t%s\t%d\t%.3f\t%.3f\t%.3f\n", v, counts[v], m, (min_conf[v]+0), (max_conf[v]+0)
    }
    for (a in apply) {
      printf "apply_strategy\t%s\t%d\t-\t-\t-\n", a, apply[a]
    }
  }
' "$TRIAGE" > "$OUT_TSV"

# ---- Phase-7 collision-driver: files touched by ≥2 non-protected branches ----
# Build a file → branches map from branches.tsv touched_files column. The
# touched_files column is comma-separated (newlines would have broken the row).
COLLISION_INPUT="$WORKSPACE_DIR/.verdict_stats.collisions.tmp"
: > "$COLLISION_INPUT"
while IFS= read -r row; do
  name=""; touched=""
  tsv_read "$row" name slug head_sha last_date author subject ahead behind commits_ahead cherry_plus cherry_minus upstream upstream_status wt_path touched insertions deletions files_changed age_days prefix
  [[ "$name" == "name" ]] && continue
  [[ -z "$touched" ]] && continue
  # Skip protected-by-pattern branches in the collision count: they're not
  # candidates for harmonization.
  case "$name" in
    release/*|hotfix/*|dependabot/*|renovate/*|gh-pages) continue ;;
  esac
  # Split comma-list and emit one (file, branch) tuple per row.
  IFS=',' read -ra files <<< "$touched"
  for f in "${files[@]}"; do
    [[ -z "$f" ]] && continue
    printf '%s\t%s\n' "$f" "$name" >> "$COLLISION_INPUT"
  done
done < "$BRANCHES_TSV"

COLLISION_FILES=0
COLLISION_PAIRS=0
if [[ -s "$COLLISION_INPUT" ]]; then
  COLLISION_FILES=$(awk -F'\t' '{counts[$1]++} END {n=0; for (f in counts) if (counts[f] >= 2) n++; print n}' "$COLLISION_INPUT")
  COLLISION_PAIRS=$(awk -F'\t' '{counts[$1]++} END {p=0; for (f in counts) if (counts[f] >= 2) p += counts[f]; print p}' "$COLLISION_INPUT")
fi
printf 'collision\tfiles_with_2plus_branches\t%s\t-\t-\t-\n' "$COLLISION_FILES" >> "$OUT_TSV"
printf 'collision\tcollision_pairs\t%s\t-\t-\t-\n'           "$COLLISION_PAIRS" >> "$OUT_TSV"

# Move-not-delete the temp helper file (Rule 1). Pick a fresh archive path so
# reruns do not overwrite earlier audit breadcrumbs.
if [[ -f "$COLLISION_INPUT" ]]; then
  archived_collisions="$WORKSPACE_DIR/.verdict_stats.collisions.tmp.archived"
  suffix=0
  while [[ -e "$archived_collisions" ]]; do
    suffix=$((suffix + 1))
    archived_collisions="$WORKSPACE_DIR/.verdict_stats.collisions.tmp.archived-$suffix"
  done
  mv "$COLLISION_INPUT" "$archived_collisions" 2>/dev/null || true
fi

# ---- ahead / behind histogram + [gone] count ----
# Buckets: 0, 1, 2-5, 6-20, 21-100, 100+.
AHEAD_HIST=$(awk -F'\t' '
  NR > 1 {
    a = $7 + 0
    if (a == 0)        b="0"
    else if (a == 1)   b="1"
    else if (a <= 5)   b="2-5"
    else if (a <= 20)  b="6-20"
    else if (a <= 100) b="21-100"
    else               b="100+"
    counts[b]++
  }
  END {
    for (k in counts) printf "ahead_bucket\t%s\t%d\t-\t-\t-\n", k, counts[k]
  }
' "$BRANCHES_TSV")
BEHIND_HIST=$(awk -F'\t' '
  NR > 1 {
    a = $8 + 0
    if (a == 0)        b="0"
    else if (a == 1)   b="1"
    else if (a <= 5)   b="2-5"
    else if (a <= 20)  b="6-20"
    else if (a <= 100) b="21-100"
    else               b="100+"
    counts[b]++
  }
  END {
    for (k in counts) printf "behind_bucket\t%s\t%d\t-\t-\t-\n", k, counts[k]
  }
' "$BRANCHES_TSV")
[[ -n "$AHEAD_HIST"  ]] && printf '%s\n' "$AHEAD_HIST"  >> "$OUT_TSV"
[[ -n "$BEHIND_HIST" ]] && printf '%s\n' "$BEHIND_HIST" >> "$OUT_TSV"

GONE_COUNT=$(awk -F'\t' 'NR > 1 && $13 == "gone"' "$BRANCHES_TSV" | wc -l)
printf 'upstream\tgone\t%s\t-\t-\t-\n' "$GONE_COUNT" >> "$OUT_TSV"

# ---- Smell-pattern hits (taxonomy from BRANCH-WORKTREE-SMELLS.md) ----
match_count() {
  local pattern="$1"
  awk -F'\t' -v re="$pattern" 'NR > 1 && $1 ~ re' "$BRANCHES_TSV" | wc -l
}
SM_AGENT=$(match_count       '^agent[-/].+(attempt|try|run|pass)[-_]?[0-9]+$')
SM_WIP=$(match_count         '^wip[-/]')
SM_AGENT_CLI=$(match_count   '^(cc|cod|gmi|claude|codex|gemini|grok)[-/]')
SM_PRE=$(match_count         '^(pre|before)[-/](deploy|release|merge|push|migration|cutover|refactor|risky-op)')
SM_RELEASE=$(match_count     '^release[-/]')
SM_HOTFIX=$(match_count      '^hotfix[-/]')
SM_DEPBOT=$(match_count      '^(dependabot|renovate)[-/]')
SM_TICKET=$(match_count      '^[A-Z]+-[0-9]+')
SM_USER_SAND=$(match_count   '/sandbox|/scratch')
SM_FEATURE=$(match_count     '^feature[-/]')
SM_INTEG=$(match_count       '^(develop|staging|next|trunk)$')
SM_TRAIN=$(match_count       '^train[-/]')
SM_CHERRY=$(match_count      '^cherry-pick|^cherry-')
SM_REVERT=$(match_count      '^revert[-/]')
SM_MERGE=$(match_count       '^merge-.+-into-')

{
  printf 'smell\tagent_attempt\t%s\t-\t-\t-\n'    "$SM_AGENT"
  printf 'smell\twip\t%s\t-\t-\t-\n'              "$SM_WIP"
  printf 'smell\tagent_cli_prefix\t%s\t-\t-\t-\n' "$SM_AGENT_CLI"
  printf 'smell\tpre_or_before\t%s\t-\t-\t-\n'    "$SM_PRE"
  printf 'smell\trelease\t%s\t-\t-\t-\n'          "$SM_RELEASE"
  printf 'smell\thotfix\t%s\t-\t-\t-\n'           "$SM_HOTFIX"
  printf 'smell\tdependabot_renovate\t%s\t-\t-\t-\n' "$SM_DEPBOT"
  printf 'smell\tticket_id\t%s\t-\t-\t-\n'        "$SM_TICKET"
  printf 'smell\tuser_sandbox\t%s\t-\t-\t-\n'     "$SM_USER_SAND"
  printf 'smell\tfeature\t%s\t-\t-\t-\n'          "$SM_FEATURE"
  printf 'smell\tintegration\t%s\t-\t-\t-\n'      "$SM_INTEG"
  printf 'smell\ttrain\t%s\t-\t-\t-\n'            "$SM_TRAIN"
  printf 'smell\tcherry_pick\t%s\t-\t-\t-\n'      "$SM_CHERRY"
  printf 'smell\trevert\t%s\t-\t-\t-\n'           "$SM_REVERT"
  printf 'smell\tmerge_into\t%s\t-\t-\t-\n'       "$SM_MERGE"
} >> "$OUT_TSV"

# ---- Markdown summary (for handoff_report inclusion) ----
{
  printf '## Verdict statistics\n\n'
  printf 'Triage rows: **%s** (branches=%s, worktrees=%s)\n\n' "$TOTAL" "$TOTAL_BR" "$TOTAL_WT"

  printf '### Per-verdict\n\n'
  printf '| verdict | count | mean conf | min conf | max conf |\n'
  printf '|---------|------:|----------:|---------:|---------:|\n'
  awk -F'\t' '$1 == "verdict" { printf "| %s | %s | %s | %s | %s |\n", $2, $3, $4, $5, $6 }' "$OUT_TSV"
  printf '\n'

  printf '### Apply strategies\n\n'
  printf '| strategy | count |\n|----------|------:|\n'
  awk -F'\t' '$1 == "apply_strategy" { printf "| %s | %s |\n", $2, $3 }' "$OUT_TSV"
  printf '\n'

  printf '### Phase 7 collision driver\n\n'
  printf -- '- Files touched by **≥2 non-protected branches**: **%s**\n' "$COLLISION_FILES"
  printf -- '- (file, branch) pairs in those collisions: **%s**\n\n' "$COLLISION_PAIRS"

  printf '### Ahead / behind histogram\n\n'
  printf '| bucket | ahead | behind |\n|--------|------:|-------:|\n'
  for b in 0 1 2-5 6-20 21-100 100+; do
    a=$(awk -F'\t' -v b="$b" '$1 == "ahead_bucket" && $2 == b {print $3}' "$OUT_TSV")
    bh=$(awk -F'\t' -v b="$b" '$1 == "behind_bucket" && $2 == b {print $3}' "$OUT_TSV")
    printf '| %s | %s | %s |\n' "$b" "${a:-0}" "${bh:-0}"
  done
  printf '\n'

  printf '### Upstream tracking\n\n'
  # shellcheck disable=SC2016
  printf -- '- `[gone]` upstream branches: **%s** (do NOT auto-prune; smell B15)\n\n' "$GONE_COUNT"

  printf '### Smell-pattern hits (BRANCH-WORKTREE-SMELLS.md)\n\n'
  printf '| smell | count |\n|-------|------:|\n'
  awk -F'\t' '$1 == "smell" { printf "| %s | %s |\n", $2, $3 }' "$OUT_TSV"
  printf '\n'

  # Health flags — same SLO posture as git-stash-janitor's verdict-stats.
  unknown_pct=$(awk -F'\t' -v t="$TOTAL" 'BEGIN{n=0} NR > 1 && $3 == "unknown" {n++} END {printf "%.1f", (t > 0 ? 100*n/t : 0)}' "$TRIAGE")
  partial_pct=$(awk -F'\t' -v t="$TOTAL" 'BEGIN{n=0} NR > 1 && $3 == "partially-novel" {n++} END {printf "%.1f", (t > 0 ? 100*n/t : 0)}' "$TRIAGE")
  conf_low_pct=$(awk -F'\t' -v t="$TOTAL" 'BEGIN{n=0} NR > 1 && $4 + 0 < 0.75 {n++} END {printf "%.1f", (t > 0 ? 100*n/t : 0)}' "$TRIAGE")
  printf '### SLO health flags\n\n'
  printf -- '- Unknown rate: **%s%%** (healthy <5%%; investigate if >10%%)\n' "$unknown_pct"
  printf -- '- Partially-novel rate: **%s%%** (healthy <10%%; investigate if >20%%)\n' "$partial_pct"
  printf -- '- Confidence < 0.75: **%s%%** (consider triangulation if >15%%)\n' "$conf_low_pct"
} > "$OUT_MD"

echo "wrote $OUT_TSV"
echo "wrote $OUT_MD"
echo
echo "=== Verdict statistics ==="
awk -F'\t' '$1 == "verdict" { printf "  %-22s %s\n", $2, $3 }' "$OUT_TSV"
echo
echo "Phase-7 collision driver: $COLLISION_FILES file(s) with ≥2 branches"
echo "[gone] upstream branches: $GONE_COUNT"
exit 0
