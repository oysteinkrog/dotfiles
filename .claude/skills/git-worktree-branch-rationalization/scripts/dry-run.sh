#!/usr/bin/env bash
# dry-run.sh — Top-level dry-run mode.
#
# Reads triage.tsv + (optionally) harmonization_plan.md and predicts every
# Phase 8 + Phase 10 action without executing any of them. Emits:
#   <workspace>/dry_run_report.md          — human-readable enumeration of
#                                            cherry-picks, squash-merges,
#                                            harmonized-synthesis stubs,
#                                            predicted conflicts (via
#                                            git merge-tree), worktree
#                                            removals (with disk freed),
#                                            branch deletions (with backup-ref
#                                            names).
#   <workspace>/expected_outcomes.json     — machine-readable expectations the
#                                            real run can compare against.
#
# Read-only — never mutates the repo, the bundle, or the workspace beyond the
# two output files. Per AGENTS.md: never runs `git reset --hard`, never
# `rm -rf`, never `git push --delete`, never `git branch -D` (only predicts).
#
# Resume-aware: re-running with the same triage.tsv hash + same plan hash
# reuses the existing report rather than recomputing.
#
# Exit codes:
#   0  report written (or current)
#   2  preflight failed (triage.tsv / branches.tsv / project_profile.json missing)
#   3  bundle path file missing (for backup-ref name prediction)

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=project-root.sh
. "$SCRIPT_DIR/project-root.sh"

log() { printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*"; }

usage() {
  cat <<USAGE
Usage: dry-run.sh <project-path>

Top-level dry-run. Predicts every Phase 8 + Phase 10 action from triage.tsv +
(optionally) harmonization_plan.md without executing any of them. Emits
<workspace>/dry_run_report.md and <workspace>/expected_outcomes.json.

Read-only on the repo, bundle, and workspace (apart from the two output
files). Resume-aware: re-running with the same inputs reuses the report.

Env:
  WORKSPACE                   Workspace dir override.
  RATIONALIZATION_BRANCH      Override the predicted rationalization branch
                              name (default: branch-rationalization-<DATE>).
  DRY_RUN_FORCE=1             Force regeneration even when inputs unchanged.

Exit codes:
  0  report written or current
  2  preflight failed (inventory / triage missing)
  3  bundle path file missing
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
WORKTREES_TSV="$WORKSPACE_DIR/worktrees.tsv"
PROFILE="$WORKSPACE_DIR/project_profile.json"
PROTECTED="$WORKSPACE_DIR/protected.tsv"
PLAN="$WORKSPACE_DIR/harmonization_plan.md"
BUNDLE_PATH_FILE="$WORKSPACE_DIR/bundle_path.txt"
REPORT="$WORKSPACE_DIR/dry_run_report.md"
EXPECTED="$WORKSPACE_DIR/expected_outcomes.json"

for f in "$TRIAGE" "$BRANCHES_TSV" "$WORKTREES_TSV" "$PROFILE"; do
  [[ -f "$f" ]] || { echo "ERROR: $f missing" >&2; exit 2; }
done
if [[ ! -f "$BUNDLE_PATH_FILE" ]]; then
  echo "ERROR: $BUNDLE_PATH_FILE missing — run build-bundle.sh first." >&2
  exit 3
fi
BUNDLE="$(cat "$BUNDLE_PATH_FILE")"

profile_value() {
  local key="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -r --arg key "$key" '.[$key] // ""' "$PROFILE"
    return
  fi
  python3 - "$PROFILE" "$key" <<'PY'
import json, sys
with open(sys.argv[1], encoding='utf-8') as f: data = json.load(f)
v = data.get(sys.argv[2], "")
if isinstance(v, bool): print("true" if v else "false")
elif v is None: print("")
else: print(v)
PY
}
CANONICAL=$(profile_value canonical_branch)
MERGE_STYLE=$(profile_value merge_style)
DATE_TAG=$(date -u +%Y-%m-%d)
PROFILE_RB=$(profile_value rationalization_branch)
[[ -z "$PROFILE_RB" ]] && PROFILE_RB="branch-rationalization-$DATE_TAG"
RB="${RATIONALIZATION_BRANCH:-$PROFILE_RB}"

if git -C "$PROJECT_ABS" rev-parse --verify --quiet "refs/heads/$CANONICAL^{commit}" >/dev/null 2>&1; then
  CANON_REF="refs/heads/$CANONICAL"
elif git -C "$PROJECT_ABS" rev-parse --verify --quiet "refs/remotes/origin/$CANONICAL^{commit}" >/dev/null 2>&1; then
  CANON_REF="refs/remotes/origin/$CANONICAL"
else
  echo "ERROR: canonical branch '$CANONICAL' does not resolve." >&2
  exit 2
fi
CANON_TIP=$(git -C "$PROJECT_ABS" rev-parse "$CANON_REF" 2>/dev/null || echo "")

# Resume-aware signature.
hash_of() { sha256sum "$1" 2>/dev/null | awk '{print $1}'; }
SIG_TRIAGE=$(hash_of "$TRIAGE")
SIG_PLAN=""
[[ -f "$PLAN" ]] && SIG_PLAN=$(hash_of "$PLAN")
SIG_PROFILE=$(hash_of "$PROFILE")
SIG="dry-run/v1 triage=$SIG_TRIAGE plan=$SIG_PLAN profile=$SIG_PROFILE rb=$RB"

if [[ -z "${DRY_RUN_FORCE:-}" && -f "$REPORT" ]]; then
  if grep -qxF "<!-- signature: $SIG -->" "$REPORT" 2>/dev/null; then
    log "dry-run inputs unchanged; reusing $REPORT"
    echo "current: $REPORT"
    exit 0
  fi
fi

# Build branch->slug map and per-branch metadata.
declare -A BRANCH_SLUG
declare -A BRANCH_HEAD
while IFS= read -r row; do
  name=; slug=; head_sha=
  tsv_read "$row" name slug head_sha _last_date _author _subject _ahead _behind _commits_ahead _cherry_plus _cherry_minus _upstream _upstream_status _wt_path _touched _insertions _deletions _files_changed _age_days _prefix
  [[ "$name" == "name" ]] && continue
  [[ -z "$name" ]] && continue
  BRANCH_SLUG[$name]="$slug"
  BRANCH_HEAD[$name]="$head_sha"
done < "$BRANCHES_TSV"

declare -A WT_DIRTY
while IFS= read -r row; do
  path=; dirty=
  tsv_read "$row" path _branch _detached _bare _locked _prunable _last_sha _last_date dirty _staged_size _unstaged_size _untracked_size _untracked_count _age_days _inside_main _active _subm
  [[ "$path" == "path" ]] && continue
  [[ -z "$path" ]] && continue
  WT_DIRTY[$path]="${dirty:-0}"
done < "$WORKTREES_TSV"

declare -A IS_PROTECTED
if [[ -f "$PROTECTED" ]]; then
  while IFS= read -r row; do
    kind=; name_or_path=
    tsv_read "$row" kind name_or_path _rest
    [[ "$kind" == "kind" ]] && continue
    [[ -z "$name_or_path" ]] && continue
    IS_PROTECTED["$kind:$name_or_path"]=1
  done < "$PROTECTED"
fi

# Disk size for a worktree path. Best-effort; missing path returns 0.
worktree_size_bytes() {
  local p="$1"
  if [[ -d "$p" ]]; then
    du -sb "$p" 2>/dev/null | awk '{print $1}'
  else
    echo 0
  fi
}
human_bytes() {
  local b="${1:-0}"
  if [[ -z "$b" || ! "$b" =~ ^[0-9]+$ ]]; then b=0; fi
  awk -v b="$b" 'BEGIN {
    split("B KiB MiB GiB TiB", units);
    i=1; while (b >= 1024 && i < 5) { b/=1024; i++ }
    if (i == 1) printf "%d %s", b, units[i];
    else printf "%.2f %s", b, units[i];
  }'
}

# ---- Tally pass ----
declare -i CT_CHERRY=0 CT_SQUASH=0 CT_REBASE=0 CT_HARMONIZE=0 CT_SPLIT=0 CT_DIRTY=0 CT_NOOP=0
declare -i CT_DELETE_BR=0 CT_REMOVE_WT=0 CT_PROTECT_REFUSAL=0 CT_CONFLICT_PRED=0
declare -i TOTAL_BYTES_FREED=0

# Buffer per-section markdown. We write the final report at the end.
APPLY_LINES=()
CONFLICT_LINES=()
DELETE_LINES=()
REMOVE_LINES=()
HARMONIZE_LINES=()
NOOP_LINES=()

# Predict per-cherry-pick commit message stub the apply layer will use.
predicted_commit_message() {
  local strategy="$1" name="$2" verdict="$3"
  local subject=""
  if [[ -n "${BRANCH_HEAD[$name]:-}" ]]; then
    subject=$(git -C "$PROJECT_ABS" log -1 --format='%s' "${BRANCH_HEAD[$name]}" 2>/dev/null || echo "")
  fi
  case "$strategy" in
    cherry-pick)         printf 'recover %s from %s [%s]' "${subject:-changes}" "$name" "$verdict" ;;
    squash-merge)        printf 'recover %s from %s (squash) [%s]' "${subject:-changes}" "$name" "$verdict" ;;
    rebase-and-merge)    printf 'recover %s from %s (rebase) [%s]' "${subject:-changes}" "$name" "$verdict" ;;
    harmonized-synthesis) printf '<harmonized-synthesis stub — main agent fills via Edit per harmonization_plan.md>' ;;
    split-commits-hunks) printf 'recover novel-subset hunks from %s [%s]' "$name" "$verdict" ;;
    dirty-worktree-only) printf 'recover dirty-state from %s [%s]' "$name" "$verdict" ;;
    *)                   printf '(no-op for %s [%s])' "$name" "$verdict" ;;
  esac
}

# Predict whether `git merge-tree <CANON_TIP> <branch>` produces a conflict.
# `git merge-tree --write-tree` exits non-zero on conflict (git ≥2.38).
predict_conflict() {
  local name="$1"
  if [[ -z "${BRANCH_HEAD[$name]:-}" ]]; then
    echo "unknown"
    return
  fi
  if git -C "$PROJECT_ABS" merge-tree --write-tree --no-messages "$CANON_TIP" "${BRANCH_HEAD[$name]}" >/dev/null 2>&1; then
    echo "clean"
  else
    # Attempt a textual hint via the older trivial-merge form for a brief
    # conflict-section count.
    local conflicts
    conflicts=$(git -C "$PROJECT_ABS" merge-tree "$CANON_TIP" "$CANON_TIP" "${BRANCH_HEAD[$name]}" 2>/dev/null | grep -c '<<<<<<' || true)
    echo "conflict:${conflicts:-?}"
  fi
}

# ---- Walk triage rows ----
HEADER=$(head -1 "$TRIAGE")
if [[ "$HEADER" != *"verdict"* ]]; then
  echo "ERROR: $TRIAGE has no verdict column (unexpected schema)." >&2
  exit 2
fi

while IFS= read -r row; do
  kind=; name_or_path=; verdict=; apply_strategy=
  tsv_read "$row" kind name_or_path verdict _confidence apply_strategy _evidence _files_touched
  [[ "$kind" == "kind" ]] && continue
  [[ -z "$kind" ]] && continue

  if [[ "$kind" == "branch" ]]; then
    name="$name_or_path"
    slug="${BRANCH_SLUG[$name]:-$(slugify_branch "$name")}"
    backup_ref="refs/branch-rationalization-backup/$slug"
    is_prot=0
    [[ -n "${IS_PROTECTED[branch:$name]:-}" ]] && is_prot=1

    # Apply-side prediction.
    case "$apply_strategy" in
      cherry-pick)
        CT_CHERRY=$((CT_CHERRY+1))
        msg=$(predicted_commit_message cherry-pick "$name" "$verdict")
        cf=$(predict_conflict "$name")
        APPLY_LINES+=("- [cherry-pick] \`$name\` (verdict=$verdict, slug=\`$slug\`) → \`$msg\` — merge-tree=$cf")
        if [[ "$cf" == conflict:* ]]; then
          CT_CONFLICT_PRED=$((CT_CONFLICT_PRED+1))
          CONFLICT_LINES+=("- branch \`$name\` (cherry-pick): merge-tree predicts $cf onto $CANONICAL")
        fi
        ;;
      squash-merge)
        CT_SQUASH=$((CT_SQUASH+1))
        msg=$(predicted_commit_message squash-merge "$name" "$verdict")
        cf=$(predict_conflict "$name")
        APPLY_LINES+=("- [squash-merge] \`$name\` → \`$msg\` — merge-tree=$cf")
        if [[ "$cf" == conflict:* ]]; then
          CT_CONFLICT_PRED=$((CT_CONFLICT_PRED+1))
          CONFLICT_LINES+=("- branch \`$name\` (squash-merge): merge-tree predicts $cf onto $CANONICAL")
        fi
        ;;
      rebase-and-merge)
        CT_REBASE=$((CT_REBASE+1))
        msg=$(predicted_commit_message rebase-and-merge "$name" "$verdict")
        cf=$(predict_conflict "$name")
        APPLY_LINES+=("- [rebase-and-merge] \`$name\` → \`$msg\` — merge-tree=$cf")
        if [[ "$cf" == conflict:* ]]; then
          CT_CONFLICT_PRED=$((CT_CONFLICT_PRED+1))
          CONFLICT_LINES+=("- branch \`$name\` (rebase): merge-tree predicts $cf onto $CANONICAL")
        fi
        ;;
      harmonized-synthesis)
        CT_HARMONIZE=$((CT_HARMONIZE+1))
        HARMONIZE_LINES+=("- branch \`$name\` (verdict=$verdict): main agent must Edit per \`harmonization_plan.md\` — synthesis stub commit will land")
        ;;
      split-commits-hunks)
        CT_SPLIT=$((CT_SPLIT+1))
        APPLY_LINES+=("- [split-commits-hunks] \`$name\` → novel subset only (Phase 8b)")
        ;;
      dirty-worktree-only)
        CT_DIRTY=$((CT_DIRTY+1))
        APPLY_LINES+=("- [dirty-worktree-only] \`$name\` → captured staged/unstaged/untracked applied as separate commits")
        ;;
      *)
        CT_NOOP=$((CT_NOOP+1))
        NOOP_LINES+=("- branch \`$name\` (verdict=$verdict): no apply (will be retired in Phase 10)")
        ;;
    esac

    # Delete-side prediction. Protected branches never enter the deletion
    # list. applied-keepers are deletable AFTER apply succeeds; here we record
    # the prediction.
    if [[ "$is_prot" -eq 1 ]]; then
      CT_PROTECT_REFUSAL=$((CT_PROTECT_REFUSAL+1))
    else
      case "$verdict" in
        garbage|superseded|already-merged|novel-but-stale|divergent-refactor|novel-and-accretive|partially-novel|dirty-worktree-only)
          # Branches whose content is being applied also become deletable after
          # the apply commits land.
          CT_DELETE_BR=$((CT_DELETE_BR+1))
          del_kind="-d"
          # Only `garbage` and `novel-but-stale`/`divergent-refactor` (opt-in)
          # would need -D; the others should be -d after apply.
          case "$verdict" in
            garbage|novel-but-stale|divergent-refactor) del_kind="-d (or -D with explicit ack)" ;;
          esac
          DELETE_LINES+=("- \`git branch $del_kind $name\` — backup-ref: \`$backup_ref\` (slug=\`$slug\`) — verdict=$verdict")
          ;;
      esac
    fi
  elif [[ "$kind" == "worktree" ]]; then
    p="$name_or_path"
    is_prot=0
    [[ -n "${IS_PROTECTED[worktree:$p]:-}" ]] && is_prot=1
    if [[ "$is_prot" -eq 1 ]]; then
      CT_PROTECT_REFUSAL=$((CT_PROTECT_REFUSAL+1))
      continue
    fi
    case "$verdict" in
      garbage|superseded|already-merged|novel-but-stale|divergent-refactor|dirty-worktree-only|none-default-drop)
        CT_REMOVE_WT=$((CT_REMOVE_WT+1))
        bytes=$(worktree_size_bytes "$p")
        TOTAL_BYTES_FREED=$((TOTAL_BYTES_FREED + ${bytes:-0}))
        human=$(human_bytes "${bytes:-0}")
        force_hint=""
        if [[ "${WT_DIRTY[$p]:-0}" -gt 0 ]]; then
          force_hint=" (dirty — needs WORKTREE_FORCE_OK=1; bundle has staged/unstaged/untracked)"
        fi
        REMOVE_LINES+=("- \`git worktree remove $p\`$force_hint — frees ~$human (verdict=$verdict)")
        ;;
    esac
  fi
done < "$TRIAGE"

# ---- Harmonization plan summary ----
HARMONIZE_FILES_COUNT=0
if [[ -f "$PLAN" ]]; then
  HARMONIZE_FILES_COUNT=$(awk '/^### `/{count++} END {print count+0}' "$PLAN" 2>/dev/null)
fi

# ---- Write report ----
TOTAL_BYTES_FREED_HUMAN=$(human_bytes "$TOTAL_BYTES_FREED")
{
  printf '<!-- signature: %s -->\n' "$SIG"
  printf '# Dry-run report — %s\n\n' "$(date -u +%FT%TZ)"
  printf 'Project:               `%s`\n' "$PROJECT_ABS"
  printf 'Canonical:             `%s` (`%s` @ `%s`)\n' "$CANONICAL" "$CANON_REF" "${CANON_TIP:0:12}"
  printf 'Rationalization branch: `%s` (predicted; not created by this dry run)\n' "$RB"
  printf 'Merge style (profile): `%s`\n' "${MERGE_STYLE:-unknown}"
  printf 'Bundle:                `%s`\n\n' "$BUNDLE"
  printf 'This is a **dry run**. No git operations were executed against the repo.\n'
  printf 'Compare these predictions against the actual run by diffing\n'
  printf '`expected_outcomes.json` with the live counts in `apply_log.tsv` /\n'
  printf '`cleanup_log.tsv` after the real Phase 8 / Phase 10.\n\n'

  printf '## Phase 8 apply predictions\n\n'
  printf '| Strategy             | Count |\n'
  printf '|----------------------|-------|\n'
  printf '| cherry-pick          | %d |\n' "$CT_CHERRY"
  printf '| squash-merge         | %d |\n' "$CT_SQUASH"
  printf '| rebase-and-merge     | %d |\n' "$CT_REBASE"
  printf '| harmonized-synthesis | %d |\n' "$CT_HARMONIZE"
  printf '| split-commits-hunks  | %d |\n' "$CT_SPLIT"
  printf '| dirty-worktree-only  | %d |\n' "$CT_DIRTY"
  printf '| no-op                | %d |\n\n' "$CT_NOOP"

  if [[ ${#APPLY_LINES[@]} -gt 0 ]]; then
    printf '### Apply enumeration\n\n'
    for line in "${APPLY_LINES[@]}"; do printf '%s\n' "$line"; done
    printf '\n'
  fi

  printf '## Predicted conflicts (via `git merge-tree`)\n\n'
  printf 'Conflict count: **%d**\n\n' "$CT_CONFLICT_PRED"
  if [[ ${#CONFLICT_LINES[@]} -gt 0 ]]; then
    for line in "${CONFLICT_LINES[@]}"; do printf '%s\n' "$line"; done
    printf '\n'
  else
    printf 'No conflicts predicted by `git merge-tree`.\n\n'
  fi

  printf '## Harmonization plan summary\n\n'
  if [[ -f "$PLAN" ]]; then
    printf 'Plan file: `%s` — %d file entries.\n\n' "$PLAN" "$HARMONIZE_FILES_COUNT"
    if [[ ${#HARMONIZE_LINES[@]} -gt 0 ]]; then
      for line in "${HARMONIZE_LINES[@]}"; do printf '%s\n' "$line"; done
      printf '\n'
    fi
  else
    printf 'No `harmonization_plan.md` present (run harmonization-plan.sh if any\n'
    printf 'files were touched by ≥2 non-protected branches).\n\n'
  fi

  printf '## Phase 10 worktree removal predictions\n\n'
  printf 'Worktree removals: **%d** — total disk freed (estimated): **%s**.\n\n' \
    "$CT_REMOVE_WT" "$TOTAL_BYTES_FREED_HUMAN"
  if [[ ${#REMOVE_LINES[@]} -gt 0 ]]; then
    for line in "${REMOVE_LINES[@]}"; do printf '%s\n' "$line"; done
    printf '\n'
  fi

  printf '## Phase 10 branch deletion predictions\n\n'
  printf 'Branch deletions: **%d** (protected refusals: %d).\n\n' \
    "$CT_DELETE_BR" "$CT_PROTECT_REFUSAL"
  if [[ ${#DELETE_LINES[@]} -gt 0 ]]; then
    for line in "${DELETE_LINES[@]}"; do printf '%s\n' "$line"; done
    printf '\n'
  fi

  if [[ ${#NOOP_LINES[@]} -gt 0 ]]; then
    printf '## No-apply rows (verdict drops without a recovery commit)\n\n'
    for line in "${NOOP_LINES[@]}"; do printf '%s\n' "$line"; done
    printf '\n'
  fi

  printf '## Reversibility reminder\n\n'
  printf 'Every branch listed above has a backup ref under\n'
  printf '`refs/branch-rationalization-backup/<slug>` AND a recovery payload in\n'
  printf 'the bundle at `%s`. Per AGENTS.md, the dry run never deletes anything;\n' "$BUNDLE"
  printf 'the real Phase 10 still requires verbatim user authorization.\n'
} > "$REPORT"

# ---- Write expected_outcomes.json ----
{
  printf '{\n'
  printf '  "schema": "dry-run/v1",\n'
  printf '  "generated_at": '; json_string "$(date -u +%FT%TZ)"; printf ',\n'
  printf '  "project": '; json_string "$PROJECT_ABS"; printf ',\n'
  printf '  "canonical": '; json_string "$CANONICAL"; printf ',\n'
  printf '  "canonical_tip": '; json_string "$CANON_TIP"; printf ',\n'
  printf '  "rationalization_branch": '; json_string "$RB"; printf ',\n'
  printf '  "bundle": '; json_string "$BUNDLE"; printf ',\n'
  printf '  "expected_apply": {\n'
  printf '    "cherry_pick": %d,\n'           "$CT_CHERRY"
  printf '    "squash_merge": %d,\n'          "$CT_SQUASH"
  printf '    "rebase_and_merge": %d,\n'      "$CT_REBASE"
  printf '    "harmonized_synthesis": %d,\n'  "$CT_HARMONIZE"
  printf '    "split_commits_hunks": %d,\n'   "$CT_SPLIT"
  printf '    "dirty_worktree_only": %d,\n'   "$CT_DIRTY"
  printf '    "noop": %d\n'                   "$CT_NOOP"
  printf '  },\n'
  printf '  "expected_conflicts": %d,\n' "$CT_CONFLICT_PRED"
  printf '  "expected_cleanup": {\n'
  printf '    "worktree_removals": %d,\n'    "$CT_REMOVE_WT"
  printf '    "branch_deletions": %d,\n'     "$CT_DELETE_BR"
  printf '    "protected_refusals": %d,\n'   "$CT_PROTECT_REFUSAL"
  printf '    "bytes_freed_estimate": %d\n'  "$TOTAL_BYTES_FREED"
  printf '  },\n'
  printf '  "harmonization_files": %d\n' "$HARMONIZE_FILES_COUNT"
  printf '}\n'
} > "$EXPECTED"

log "wrote $REPORT"
log "wrote $EXPECTED"
echo "summary: cherry=$CT_CHERRY squash=$CT_SQUASH rebase=$CT_REBASE harmonize=$CT_HARMONIZE split=$CT_SPLIT dirty=$CT_DIRTY noop=$CT_NOOP conflicts=$CT_CONFLICT_PRED"
echo "         worktrees-to-remove=$CT_REMOVE_WT branches-to-delete=$CT_DELETE_BR protected=$CT_PROTECT_REFUSAL freed=$TOTAL_BYTES_FREED_HUMAN"
exit 0
