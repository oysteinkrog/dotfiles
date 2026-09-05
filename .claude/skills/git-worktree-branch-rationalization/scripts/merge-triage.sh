#!/usr/bin/env bash
# merge-triage.sh — Phase 6: merge per-batch triage tsvs into the canonical
# triage.tsv; emit triage_decision.md (decision table grouped by verdict,
# sorted by confidence, with collapsible details for large groups).
#
# Reads:  <workspace>/triage/batch_*.tsv
# Writes: <workspace>/triage.tsv
#         <workspace>/triage_decision.md
#
# Exit codes:
#   0  ok
#   1  no batch tsvs found
#   2  inventory missing

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=project-root.sh
. "$SCRIPT_DIR/project-root.sh"

log() { printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*"; }

usage() {
  cat <<USAGE
Usage: merge-triage.sh <project-path>

Phase 6: merge all per-batch triage TSVs into one canonical triage.tsv and
emit a markdown decision table for the user.

Env:
  WORKSPACE   Workspace dir override.

Exit codes:
  0  ok
  1  no batch TSVs found in <workspace>/triage/
  2  inventory missing
USAGE
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  '') usage >&2; exit 64 ;;
esac

PROJECT="$1"
PROJECT_ABS="$(resolve_project_root "$PROJECT")" || exit 2
WORKSPACE_DIR="$(resolve_workspace "$PROJECT_ABS")"
TRIAGE_DIR="$WORKSPACE_DIR/triage"
BRANCHES_TSV="$WORKSPACE_DIR/branches.tsv"
WORKTREES_TSV="$WORKSPACE_DIR/worktrees.tsv"

if [[ ! -d "$TRIAGE_DIR" ]]; then
  echo "ERROR: $TRIAGE_DIR does not exist (run triage-batch.sh first)" >&2
  exit 1
fi
batch_files=( "$TRIAGE_DIR"/batch_*.tsv )
if [[ ${#batch_files[@]} -eq 0 || ! -f "${batch_files[0]}" ]]; then
  echo "ERROR: no batch tsv files in $TRIAGE_DIR" >&2
  exit 1
fi

TRIAGE="$WORKSPACE_DIR/triage.tsv"
DECISION="$WORKSPACE_DIR/triage_decision.md"

# ---- Merge ----
head -1 "${batch_files[0]}" > "$TRIAGE"
for f in "${batch_files[@]}"; do
  awk 'NR > 1' "$f" >> "$TRIAGE"
done

# Sort by kind (branch/worktree), then verdict, then ASCENDING confidence so
# the most-ambiguous rows surface first within each verdict group — they're
# what the user most needs to see (per references/TRIAGE-RUBRIC.md and the
# triage-decision-template).
{
  head -1 "$TRIAGE"
  awk 'NR > 1' "$TRIAGE" | sort -t $'\t' -k1,1 -k3,3 -k4,4n
} > "$TRIAGE.sorted"
mv "$TRIAGE.sorted" "$TRIAGE"

n_rows=$(awk 'NR > 1' "$TRIAGE" | wc -l)
inv_branches=$(awk 'NR > 1' "$BRANCHES_TSV"  | wc -l)
inv_worktrees=$(awk 'NR > 1' "$WORKTREES_TSV" | wc -l)
expected=$((inv_branches + inv_worktrees))

if [[ "$n_rows" -lt "$expected" ]]; then
  log "WARNING: triage has $n_rows rows; inventory has $expected (some entries un-triaged)."
fi

# ---- Markdown decision table ----
verdict_count() { awk -F'\t' -v v="$1" 'NR > 1 && $3 == v' "$TRIAGE" | wc -l; }

n_already_merged=$(verdict_count already-merged)
n_novel=$(verdict_count novel-and-accretive)
n_partial=$(verdict_count partially-novel)
n_div=$(verdict_count divergent-refactor)
n_super=$(verdict_count superseded)
n_stale=$(verdict_count novel-but-stale)
n_garbage=$(verdict_count garbage)
n_dirty=$(verdict_count dirty-worktree-only)
n_proto=$(verdict_count protected-preserve)
n_unknown=$(verdict_count unknown)

# Helper: emit a markdown table for a verdict, escaping pipes/backticks.
table_for_verdict() {
  local target="$1" min_conf="${2:-0}"
  awk -F'\t' -v v="$target" -v mc="$min_conf" '
    function md_escape(s) { gsub(/\|/, "\\|", s); gsub(/`/, "\\`", s); return s }
    NR > 1 && $3 == v && $4+0 >= mc+0 {
      printf "| %s | %s | %s | %s | %s | %s |\n",
        $1, md_escape($2), $4, md_escape($5), md_escape($6), md_escape($7)
    }
  ' "$TRIAGE"
}

emit_section() {
  local emoji="$1" verdict="$2" header="$3" count="$4"
  [[ "$count" -eq 0 ]] && return 0
  printf '## %s %s — %s (%s)\n\n' "$emoji" "$verdict" "$header" "$count"
  if [[ "$count" -gt 30 ]]; then
    printf '<details><summary>Click to expand %s rows</summary>\n\n' "$count"
  fi
  printf '| kind | name/path | conf | strategy | evidence | files (preview) |\n'
  printf '|------|-----------|------|----------|----------|-----------------|\n'
  table_for_verdict "$verdict"
  if [[ "$count" -gt 30 ]]; then
    printf '\n</details>\n'
  fi
  printf '\n'
}

{
  printf '# Triage decision\n\n'
  printf '_%s entries triaged. Review below; reply with "go" to proceed._\n\n' "$n_rows"

  printf '## Verdict counts\n\n'
  printf '| verdict | count | proposed action |\n'
  printf '|---------|-------|-----------------|\n'
  printf '| novel-and-accretive   | %s | apply on rationalization branch |\n' "$n_novel"
  printf '| partially-novel       | %s | split-apply (novel commits/hunks only) |\n' "$n_partial"
  printf '| divergent-refactor    | %s | **harmonization candidate (Phase 7)** |\n' "$n_div"
  printf '| dirty-worktree-only   | %s | apply staged.diff + unstaged.diff + untracked |\n' "$n_dirty"
  printf '| already-merged        | %s | drop after Phase 10 authorization |\n' "$n_already_merged"
  printf '| superseded            | %s | drop after Phase 10 authorization |\n' "$n_super"
  printf '| novel-but-stale       | %s | manual decision (default: drop with note) |\n' "$n_stale"
  printf '| garbage               | %s | drop after Phase 10 authorization |\n' "$n_garbage"
  printf '| protected-preserve      | %s | NEVER removed (active worktree / canonical) |\n' "$n_proto"
  printf '| unknown               | %s | **must resolve before Phase 7** |\n' "$n_unknown"
  printf '\n'

  emit_section "⚠"  unknown               "needs user verdict"               "$n_unknown"
  emit_section "🔒" protected-preserve      "auto-protected (NEVER removed)"   "$n_proto"
  emit_section "✓"  novel-and-accretive   "apply as keepers"                 "$n_novel"
  emit_section "✂"  partially-novel       "split-apply (novel subset)"       "$n_partial"
  emit_section "◇"  divergent-refactor    "harmonize via variant matrix"     "$n_div"
  emit_section "💧" dirty-worktree-only   "apply captured worktree state"    "$n_dirty"
  emit_section "?"  novel-but-stale       "manual decision"                  "$n_stale"
  emit_section "🗑" already-merged        "drop after authorization"         "$n_already_merged"
  emit_section "🗑" superseded            "drop after authorization"         "$n_super"
  emit_section "🗑" garbage               "drop after authorization"         "$n_garbage"

  printf '## Next step\n\n'
  printf 'Reply with one of:\n'
  # shellcheck disable=SC2016
  printf -- '- `go` — proceed to Phase 7 (harmonization plan), then Phase 8 (apply keepers).\n'
  # shellcheck disable=SC2016
  printf -- '- `keep <branch> too` / `drop <branch>` — per-row override (recorded to user_overrides.tsv).\n'
  # shellcheck disable=SC2016
  printf -- '- `wait` / `stop` — abort. Bundle and backup refs remain intact.\n'
} > "$DECISION"

echo "wrote $TRIAGE      ($n_rows rows)"
echo "wrote $DECISION"
echo
echo "Verdict counts:"
awk -F'\t' 'NR > 1 {counts[$3]++} END {for (v in counts) printf "  %-26s %s\n", v, counts[v]}' "$TRIAGE"
