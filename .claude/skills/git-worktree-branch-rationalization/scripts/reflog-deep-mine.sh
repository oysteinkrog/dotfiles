#!/usr/bin/env bash
# reflog-deep-mine.sh — Phase 0.5 / Phase 5 forensic reflog mining.
#
# discover-branches-worktrees.sh captures basic upstream_status. This script
# goes deeper: for each branch (or a subset) we walk the full reflog and
# detect:
#
#   - force-push events (`update by push` with non-fast-forward arrow)
#   - interactive-rebase passes (`rebase -i ...` entries)
#   - cherry-pick chains (`cherry-pick: ...` entries with abandonment)
#   - resets (any `reset:` entry, including `--hard`, `--mixed`, `--soft`)
#   - merge events (`merge ...` reflog rows)
#   - branch creation source (the very first reflog entry's parent)
#
# Output: one markdown file per branch with non-trivial history under
# <workspace>/reflog/<slug>.md. Branches with a trivial straight-line history
# are skipped (no markdown emitted) but counted in the index.
#
# A summary index is written to <workspace>/reflog/_index.md listing every
# slug + a one-line classification.
#
# Used by the archaeologist subagent for forensic intent reconstruction on
# `novel-but-stale` and `divergent-refactor` verdicts.
#
# Read-only. Resume-aware: skips a branch when its reflog tip hasn't moved
# since the last mine (signature stored in the per-slug markdown header).
#
# Exit codes:
#   0  index written (possibly with 0 non-trivial branches)
#   2  preflight failed (inventory missing)

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=project-root.sh
. "$SCRIPT_DIR/project-root.sh"

log() { printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*"; }

usage() {
  cat <<USAGE
Usage: reflog-deep-mine.sh <project-path> [<branch>...]

Phase 0.5 / Phase 5 forensic reflog miner. With no positional branches given,
mines every branch in branches.tsv. With one or more branch names, mines
only those.

Output:
  <workspace>/reflog/_index.md            — one-line classification per branch
  <workspace>/reflog/<slug>.md            — full per-branch history (only when
                                            the reflog has non-trivial events)

Detected events: force-push, interactive-rebase, cherry-pick chain,
reset (--hard/--mixed/--soft), merge, branch-creation-source.

Env:
  WORKSPACE                   Workspace dir override.
  REFLOG_MINE_FORCE=1         Re-mine even when reflog tip hasn't changed.

Exit codes:
  0  index written
  2  preflight failed
USAGE
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  '') usage >&2; exit 64 ;;
esac

PROJECT="$1"
shift
PROJECT_ABS="$(resolve_project_root "$PROJECT")" || exit 2
WORKSPACE_DIR="$(resolve_workspace "$PROJECT_ABS")"
BRANCHES_TSV="$WORKSPACE_DIR/branches.tsv"
[[ -f "$BRANCHES_TSV" ]] || { echo "ERROR: $BRANCHES_TSV missing" >&2; exit 2; }

REFLOG_DIR="$WORKSPACE_DIR/reflog"
mkdir -p "$REFLOG_DIR"
INDEX="$REFLOG_DIR/_index.md"

# Build subset filter.
declare -A WANTED
WANT_ALL=1
if [[ "$#" -gt 0 ]]; then
  WANT_ALL=0
  for b in "$@"; do
    WANTED["$b"]=1
  done
fi

# ---- Per-branch mine ----
declare -a INDEX_LINES=()
INDEX_LINES+=("# Reflog index — $(date -u +%FT%TZ)")
INDEX_LINES+=("")
INDEX_LINES+=("Project: \`$PROJECT_ABS\`")
INDEX_LINES+=("")
INDEX_LINES+=("| Branch | Slug | Tip | Events | Notes |")
INDEX_LINES+=("|--------|------|-----|--------|-------|")

declare -i N_NONTRIVIAL=0
declare -i N_TOTAL=0

while IFS= read -r row; do
  name=; slug=
  tsv_read "$row" name slug _head_sha _rest
  [[ "$name" == "name" ]] && continue
  [[ -z "$name" ]] && continue
  [[ "$WANT_ALL" -eq 0 && -z "${WANTED[$name]:-}" ]] && continue
  N_TOTAL=$((N_TOTAL+1))

  branch_ref="refs/heads/$name"
  if ! git -C "$PROJECT_ABS" rev-parse --verify --quiet "$branch_ref^{commit}" >/dev/null 2>&1; then
    INDEX_LINES+=("| \`$name\` | \`$slug\` | _missing_ | skipped | branch ref no longer exists |")
    continue
  fi

  reflog_tip=$(git -C "$PROJECT_ABS" reflog --format='%H' "$branch_ref" 2>/dev/null | head -1 || true)
  out="$REFLOG_DIR/$slug.md"

  # Resume check.
  sig="reflog-mine/v1 tip=$reflog_tip"
  if [[ -z "${REFLOG_MINE_FORCE:-}" && -f "$out" ]]; then
    if grep -qE "^<!-- signature: $sig -->$" "$out" 2>/dev/null; then
      # Re-use; just count if this was non-trivial.
      if grep -qE '^- (force-push|interactive-rebase|cherry-pick chain|reset|merge):' "$out" 2>/dev/null; then
        N_NONTRIVIAL=$((N_NONTRIVIAL+1))
        INDEX_LINES+=("| \`$name\` | \`$slug\` | \`${reflog_tip:0:12}\` | (cached) | (see \`$slug.md\`) |")
      else
        INDEX_LINES+=("| \`$name\` | \`$slug\` | \`${reflog_tip:0:12}\` | trivial | _no markdown emitted_ |")
      fi
      continue
    fi
  fi

  # Walk the reflog.
  reflog_lines=$(git -C "$PROJECT_ABS" reflog --format='%H%x09%gd%x09%gs' "$branch_ref" 2>/dev/null || true)
  declare -i n_force_push=0 n_rebase_i=0 n_cherry=0 n_reset_hard=0 n_reset=0 n_merge=0
  declare -a evt_lines=()
  while IFS=$'\t' read -r h gd subj; do
    [[ -z "$subj" ]] && continue
    case "$subj" in
      *"update by push"*|*"updating ref"*"forced"*)
        n_force_push=$((n_force_push+1))
        evt_lines+=("- force-push: \`${h:0:12}\` $gd — $subj")
        ;;
      *"rebase -i"*|*"rebase (interactive)"*)
        n_rebase_i=$((n_rebase_i+1))
        evt_lines+=("- interactive-rebase: \`${h:0:12}\` $gd — $subj")
        ;;
      *"cherry-pick:"*)
        n_cherry=$((n_cherry+1))
        evt_lines+=("- cherry-pick chain: \`${h:0:12}\` $gd — $subj")
        ;;
      *"reset: moving to"*"--hard"*|*"reset --hard"*)
        n_reset_hard=$((n_reset_hard+1))
        evt_lines+=("- reset (hard): \`${h:0:12}\` $gd — $subj")
        ;;
      *"reset:"*)
        n_reset=$((n_reset+1))
        evt_lines+=("- reset: \`${h:0:12}\` $gd — $subj")
        ;;
      *"merge "*|*"Merge branch"*)
        n_merge=$((n_merge+1))
        evt_lines+=("- merge: \`${h:0:12}\` $gd — $subj")
        ;;
    esac
  done <<< "$reflog_lines"

  # Branch creation source: the FIRST (earliest) reflog row.
  first_row=$(printf '%s\n' "$reflog_lines" | tail -1 || true)
  first_subj=$(printf '%s' "$first_row" | awk -F'\t' '{print $3}')
  first_sha=$(printf '%s' "$first_row" | awk -F'\t' '{print $1}')

  total_events=$((n_force_push + n_rebase_i + n_cherry + n_reset_hard + n_reset + n_merge))

  if [[ "$total_events" -gt 0 || -n "$first_subj" ]]; then
    {
      printf '<!-- signature: %s -->\n' "$sig"
      printf '# Reflog mine — `%s` (slug `%s`)\n\n' "$name" "$slug"
      printf 'Tip: `%s`\n' "${reflog_tip:0:12}"
      printf 'Mined: %s\n\n' "$(date -u +%FT%TZ)"
      printf '## Event counts\n\n'
      printf '| Event | Count |\n'
      printf '|-------|-------|\n'
      printf '| force-push       | %d |\n' "$n_force_push"
      printf '| interactive rebase | %d |\n' "$n_rebase_i"
      printf '| cherry-pick      | %d |\n' "$n_cherry"
      printf '| reset --hard     | %d |\n' "$n_reset_hard"
      printf '| other reset      | %d |\n' "$n_reset"
      printf '| merge            | %d |\n\n' "$n_merge"

      printf '## Branch creation source (earliest reflog entry)\n\n'
      if [[ -n "$first_subj" ]]; then
        printf -- '- sha: `%s`\n' "${first_sha:0:12}"
        printf -- '- subject: %s\n\n' "$first_subj"
      else
        printf '_(no early reflog entry — branch may pre-date current reflog window)_\n\n'
      fi

      if [[ ${#evt_lines[@]} -gt 0 ]]; then
        printf '## Events (newest first)\n\n'
        for line in "${evt_lines[@]}"; do printf '%s\n' "$line"; done
        printf '\n'
      fi
    } > "$out"
    if [[ "$total_events" -gt 0 ]]; then
      N_NONTRIVIAL=$((N_NONTRIVIAL+1))
      summary="${n_force_push}fp ${n_rebase_i}ri ${n_cherry}cp ${n_reset_hard}rh ${n_reset}r ${n_merge}m"
      INDEX_LINES+=("| \`$name\` | \`$slug\` | \`${reflog_tip:0:12}\` | $summary | see \`$slug.md\` |")
    else
      INDEX_LINES+=("| \`$name\` | \`$slug\` | \`${reflog_tip:0:12}\` | trivial+orig | see \`$slug.md\` |")
    fi
  else
    INDEX_LINES+=("| \`$name\` | \`$slug\` | \`${reflog_tip:0:12}\` | trivial | _no markdown emitted_ |")
  fi
done < "$BRANCHES_TSV"

INDEX_LINES+=("")
INDEX_LINES+=("---")
INDEX_LINES+=("")
INDEX_LINES+=("Total branches walked: $N_TOTAL — non-trivial reflogs: $N_NONTRIVIAL.")

{
  for line in "${INDEX_LINES[@]}"; do printf '%s\n' "$line"; done
} > "$INDEX"

log "wrote $INDEX (non-trivial: $N_NONTRIVIAL / $N_TOTAL)"
echo "$INDEX"
exit 0
