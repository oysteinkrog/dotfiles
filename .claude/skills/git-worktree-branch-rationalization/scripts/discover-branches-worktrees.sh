#!/usr/bin/env bash
# discover-branches-worktrees.sh — Phase 2: two-pass inventory.
#
# Pass A (worktrees): parses `git worktree list --porcelain` and captures
# path, branch (or detached HEAD), bare/locked/prunable flags, last commit,
# dirty state (staged + unstaged + untracked), age, in-or-out-of-main flag,
# active-worktree flag (matches the user's CWD), per-worktree submodule state
# hint.
#
# Pass B (branches): walks `git for-each-ref refs/heads` and for each branch
# captures ahead/behind vs canonical, last commit, age, author, subject,
# upstream-tracking status, count of commits not on canonical, `git cherry -v`
# `+`/`-` summary (the patch-id giveaway for squash-merged or rebase-landed
# branches), the worktree path if checked out, touched-files list, and a
# per-line diffstat (insertions/deletions/files).
#
# Output:
#   <workspace>/worktrees.tsv
#   <workspace>/branches.tsv
#   <workspace>/inventory_grouped.md
#
# Exit codes:
#   0  ok
#   2  Phase 1 not run yet (project_profile.json missing)
#   3  not a git work tree

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=project-root.sh
. "$SCRIPT_DIR/project-root.sh"

log() { printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*"; }

usage() {
  cat <<USAGE
Usage: discover-branches-worktrees.sh <project-path>

Phase 2 of the git-worktree-branch-rationalization skill. Two-pass inventory:
worktrees first, then branches. Writes worktrees.tsv, branches.tsv, and
inventory_grouped.md.

Env:
  WORKSPACE    Workspace dir override.

Exit codes:
  0  ok
  2  project_profile.json missing (run discover-project.sh first)
  3  not a git work tree
USAGE
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  '') usage >&2; exit 64 ;;
esac

PROJECT="$1"
PROJECT_ABS="$(resolve_project_root "$PROJECT")" || exit 3
WORKSPACE_DIR="$(resolve_workspace "$PROJECT_ABS")"
PROFILE="$WORKSPACE_DIR/project_profile.json"

if [[ ! -f "$PROFILE" ]]; then
  echo "ERROR: $PROFILE missing — run discover-project.sh first." >&2
  exit 2
fi

mkdir -p "$WORKSPACE_DIR"

profile_value() {
  local key="$1" out
  if command -v jq >/dev/null 2>&1; then
    jq -r --arg key "$key" '.[$key] // ""' "$PROFILE"
    return
  fi
  if command -v python3 >/dev/null 2>&1; then
    out=$(python3 - "$PROFILE" "$key" <<'PY'
import json, sys
with open(sys.argv[1], encoding='utf-8') as f:
    data = json.load(f)
v = data.get(sys.argv[2], "")
if isinstance(v, bool): print("true" if v else "false")
elif v is None: print("")
else: print(v)
PY
    )
    printf '%s' "$out"
    return
  fi
  echo "ERROR: need jq or python3 to parse $PROFILE." >&2
  exit 8
}

CANONICAL=$(profile_value canonical_branch)
if [[ -z "$CANONICAL" ]]; then
  echo "ERROR: project_profile.json has no canonical_branch." >&2
  exit 2
fi
if git -C "$PROJECT_ABS" rev-parse --verify --quiet "refs/heads/$CANONICAL^{commit}" >/dev/null 2>&1; then
  CANON_REF="refs/heads/$CANONICAL"
elif git -C "$PROJECT_ABS" rev-parse --verify --quiet "refs/remotes/origin/$CANONICAL^{commit}" >/dev/null 2>&1; then
  CANON_REF="refs/remotes/origin/$CANONICAL"
else
  echo "ERROR: canonical branch '$CANONICAL' does not resolve." >&2
  exit 2
fi

# The user's CWD when they invoked the skill: the path of the active worktree.
# `git rev-parse --show-toplevel` gives the work tree of the cwd, and this
# script's PROJECT_ABS resolution already passed through that. We capture the
# raw git-worktree path the user is in for the active-flag column.
ACTIVE_WT_PATH="$PROJECT_ABS"

WORKTREES_TSV="$WORKSPACE_DIR/worktrees.tsv"
BRANCHES_TSV="$WORKSPACE_DIR/branches.tsv"
INVENTORY_MD="$WORKSPACE_DIR/inventory_grouped.md"

# ---- Pass A: worktrees ----
printf 'path\tbranch\tdetached\tbare\tlocked\tprunable\tlast_sha\tlast_date\tdirty\tstaged_size\tunstaged_size\tuntracked_size\tuntracked_count\tage_days\tinside_main_repo\tactive\tsubmodules_initialized\n' \
  > "$WORKTREES_TSV"

# Parse `git worktree list --porcelain` output. Format: blocks separated by
# blank lines, each with `worktree <path>`, possibly `bare`, `HEAD <sha>`,
# `branch <ref>` or `detached`, `locked [reason]`, `prunable [reason]`.
NOW_EPOCH=$(date -u +%s)

parse_worktrees() {
  local block_path="" block_sha="" block_branch="" block_bare=false
  local block_detached=false block_locked=false block_prunable=false
  emit() {
    [[ -z "$block_path" ]] && return 0
    local branch="${block_branch#refs/heads/}"
    [[ "$block_detached" == "true" ]] && branch="(detached)"
    local last_date age_days
    last_date=$(git -C "$PROJECT_ABS" log -1 --format='%cI' "$block_sha" 2>/dev/null || echo "")
    if [[ -n "$last_date" ]]; then
      local last_epoch
      last_epoch=$(date -u -d "$last_date" +%s 2>/dev/null || echo "$NOW_EPOCH")
      age_days=$(( (NOW_EPOCH - last_epoch) / 86400 ))
    else
      age_days=-1
    fi

    # Dirty-state probes only run on present, non-bare, non-prunable worktrees.
    local dirty=false staged_size=0 unstaged_size=0 untracked_size=0 untracked_count=0
    local submodules_init=false
    if [[ "$block_bare" != "true" && -d "$block_path" ]]; then
      local status_out
      status_out=$(git -C "$block_path" status --porcelain=v2 --untracked-files=all 2>/dev/null || true)
      if [[ -n "$status_out" ]]; then
        dirty=true
        staged_size=$(git -C "$block_path" diff --cached --numstat 2>/dev/null | awk '{s+=$1+$2} END {print s+0}')
        unstaged_size=$(git -C "$block_path" diff --numstat 2>/dev/null | awk '{s+=$1+$2} END {print s+0}')
      fi

      # Count untracked files from git's NUL-delimited file list, not porcelain
      # status. Plain status can be disabled by status.showUntrackedFiles and
      # quoted path output is not a safe recovery inventory format.
      local ut_total=0 ut_count=0 p
      while IFS= read -r -d '' p; do
        [[ -z "$p" ]] && continue
        ut_count=$((ut_count + 1))
        if [[ -e "$block_path/$p" || -L "$block_path/$p" ]]; then
          local sz
          sz=$(stat -c%s "$block_path/$p" 2>/dev/null || echo 0)
          ut_total=$((ut_total + sz))
        fi
      done < <(git -C "$block_path" ls-files --others --exclude-standard -z 2>/dev/null || true)
      if [[ "$ut_count" -gt 0 ]]; then
        dirty=true
      fi
      untracked_size=$ut_total
      untracked_count=$ut_count
      # Submodule init hint: `.gitmodules` exists AND at least one sm dir is non-empty.
      if [[ -f "$block_path/.gitmodules" ]]; then
        if git -C "$block_path" submodule status 2>/dev/null | grep -qE '^[+ -]'; then
          submodules_init=true
        fi
      fi
    fi

    local inside_main=false
    case "$block_path" in
      "$PROJECT_ABS"|"$PROJECT_ABS"/*) inside_main=true ;;
    esac
    local is_active=false
    [[ "$block_path" == "$ACTIVE_WT_PATH" ]] && is_active=true

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$block_path" "$branch" "$block_detached" "$block_bare" \
      "$block_locked" "$block_prunable" "$block_sha" "$last_date" \
      "$dirty" "$staged_size" "$unstaged_size" "$untracked_size" "$untracked_count" \
      "$age_days" "$inside_main" "$is_active" "$submodules_init" >> "$WORKTREES_TSV"

    block_path=""; block_sha=""; block_branch=""; block_bare=false
    block_detached=false; block_locked=false; block_prunable=false
  }
  while IFS= read -r line; do
    case "$line" in
      "")              emit ;;
      worktree\ *)     block_path="${line#worktree }" ;;
      HEAD\ *)         block_sha="${line#HEAD }" ;;
      branch\ *)       block_branch="${line#branch }" ;;
      bare)            block_bare=true ;;
      detached)        block_detached=true ;;
      locked|locked\ *)   block_locked=true ;;
      prunable|prunable\ *) block_prunable=true ;;
    esac
  done < <(git -C "$PROJECT_ABS" worktree list --porcelain 2>/dev/null)
  emit
}
parse_worktrees

# ---- Pass B: branches ----
printf 'name\tslug\thead_sha\tlast_date\tauthor\tsubject\tahead\tbehind\tcommits_ahead\tcherry_plus\tcherry_minus\tupstream\tupstream_status\tworktree_path\ttouched_files\tinsertions\tdeletions\tfiles_changed\tage_days\tprefix_family\n' \
  > "$BRANCHES_TSV"

# Build a map of branch → worktree path from the worktrees.tsv we just wrote.
declare -A WT_MAP=()
while IFS= read -r row; do
  path=; branch=; detached=
  tsv_read "$row" path branch detached _bare _locked _prunable _sha _date _dirty _ss _us _uts _utc _age _inside _active _subm
  [[ "$path" == "path" ]] && continue
  if [[ "$detached" != "true" && -n "$branch" ]]; then
    WT_MAP["$branch"]="$path"
  fi
done < "$WORKTREES_TSV"

# Also use `git branch -vv` once for the `[gone]` upstream signal.
declare -A GONE_MAP=()
while IFS= read -r line; do
  # Format: "* name sha [origin/upstream: gone] subject" or similar.
  # Parse name + the bracket span if present.
  branch_name=$(printf '%s' "$line" | awk '{ if ($1 == "*") print $2; else print $1 }')
  if [[ -n "$branch_name" ]] && echo "$line" | grep -qE '\[[^]]*: gone\]'; then
    GONE_MAP["$branch_name"]=gone
  fi
done < <(git -C "$PROJECT_ABS" branch -vv 2>/dev/null || true)

while IFS= read -r name; do
  [[ -z "$name" ]] && continue
  # Skip the canonical branch in the per-branch inventory — it's the baseline,
  # not a candidate for rationalization.
  [[ "$name" == "$CANONICAL" ]] && continue

  slug=$(slugify_branch "$name")
  branch_ref="refs/heads/$name"
  upstream_track=$(git -C "$PROJECT_ABS" for-each-ref --format='%(upstream:track)' "$branch_ref" 2>/dev/null || true)
  head_sha=$(git -C "$PROJECT_ABS" rev-parse --verify "$branch_ref^{commit}" 2>/dev/null || true)
  cdate=$(git -C "$PROJECT_ABS" log -1 --format='%cI' "$branch_ref" 2>/dev/null || true)
  author=$(git -C "$PROJECT_ABS" log -1 --format='%an' "$branch_ref" 2>/dev/null || true)
  subject=$(git -C "$PROJECT_ABS" log -1 --format='%s' "$branch_ref" 2>/dev/null || true)

  # Ahead/behind vs canonical (rev-list --left-right --count canon...branch).
  ahead=0; behind=0
  if rl=$(git -C "$PROJECT_ABS" rev-list --left-right --count "$CANON_REF...$branch_ref" 2>/dev/null); then
    behind=$(printf '%s' "$rl" | awk '{print $1}')
    ahead=$(printf '%s' "$rl" | awk '{print $2}')
  fi

  # Commits not on canonical (count form). This is the same as `ahead` from
  # rev-list, but we record it explicitly for the harmonization-plan pass.
  commits_ahead=$(git -C "$PROJECT_ABS" rev-list --count "$CANON_REF..$branch_ref" 2>/dev/null || echo 0)

  # `git cherry -v <canonical> <branch>` — patch-id equivalence summary.
  # `+` lines: this commit's patch-id is NOT on canonical (still novel).
  # `-` lines: this commit's patch-id IS on canonical (squash-merged or
  # rebase-landed). All `-` lines means the branch's content is on canonical
  # even though SHAs differ.
  cherry_plus=0; cherry_minus=0
  if cherry=$(git -C "$PROJECT_ABS" cherry "$CANON_REF" "$branch_ref" 2>/dev/null); then
    cherry_plus=$(printf '%s\n' "$cherry"  | grep -c '^+' || true)
    cherry_minus=$(printf '%s\n' "$cherry" | grep -c '^-' || true)
  fi

  # Upstream tracking ref.
  upstream=$(git -C "$PROJECT_ABS" for-each-ref --format='%(upstream:short)' "$branch_ref" 2>/dev/null || true)
  upstream_status=present
  [[ -z "$upstream" ]] && upstream_status=none
  [[ -n "${GONE_MAP[$name]:-}" ]] && upstream_status=gone

  # Worktree path if this branch is checked out somewhere.
  wt_path="${WT_MAP[$name]:-}"

  # Touched files + diffstat vs canonical merge-base.
  merge_base=$(git -C "$PROJECT_ABS" merge-base "$CANON_REF" "$branch_ref" 2>/dev/null || true)
  touched=""; insertions=0; deletions=0; files_changed=0
  if [[ -n "$merge_base" ]]; then
    # Touched files (unique, sorted, comma-separated for the TSV cell — newlines
    # would break the row format).
    touched=$(git -C "$PROJECT_ABS" diff --name-only "$merge_base" "$branch_ref" 2>/dev/null | sort -u | paste -sd, - || echo "")
    if numstat=$(git -C "$PROJECT_ABS" diff --numstat "$merge_base" "$branch_ref" 2>/dev/null); then
      insertions=$(printf '%s\n' "$numstat" | awk '$1 ~ /^[0-9]+$/ {s+=$1} END {print s+0}')
      deletions=$(printf '%s\n' "$numstat" | awk '$2 ~ /^[0-9]+$/ {s+=$2} END {print s+0}')
      files_changed=$(printf '%s\n' "$numstat" | awk 'NF>=2' | wc -l)
    fi
  fi

  # Age in days.
  age_days=-1
  if [[ -n "$cdate" ]]; then
    last_epoch=$(date -u -d "$cdate" +%s 2>/dev/null || echo "$NOW_EPOCH")
    age_days=$(( (NOW_EPOCH - last_epoch) / 86400 ))
  fi

  # Prefix family — first /-delimited segment, or first '-' segment, or
  # 'no-prefix'.
  prefix=$(printf '%s' "$name" | awk -F'[/-]' '{print $1}')
  [[ -z "$prefix" ]] && prefix="no-prefix"

  # Sanitize embedded tabs/newlines in subject and author to keep TSV well-formed.
  subj_clean=$(printf '%s' "$subject" | tr '\t\n' '  ')
  auth_clean=$(printf '%s' "$author"  | tr '\t\n' '  ')

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$name" "$slug" "$head_sha" "$cdate" "$auth_clean" "$subj_clean" \
    "$ahead" "$behind" "$commits_ahead" "$cherry_plus" "$cherry_minus" \
    "$upstream" "$upstream_status" "$wt_path" "$touched" \
    "$insertions" "$deletions" "$files_changed" "$age_days" "$prefix" \
    >> "$BRANCHES_TSV"

  # Drop discarded var to silence shellcheck about unused upstream_track.
  : "$upstream_track"

done < <(git -C "$PROJECT_ABS" for-each-ref refs/heads --format='%(refname:lstrip=2)' 2>/dev/null)

# ---- inventory_grouped.md ----
WT_ROWS=$(awk 'NR > 1' "$WORKTREES_TSV" | wc -l)
BR_ROWS=$(awk 'NR > 1' "$BRANCHES_TSV"  | wc -l)

{
  printf '# Inventory (worktrees + branches)\n\n'
  printf '_Generated: %s_\n\n' "$(date -u +%FT%TZ)"
  printf -- '- worktrees (incl. main): %s\n' "$WT_ROWS"
  printf -- "- branches (excl. canonical \`%s\`): %s\n\n" "$CANONICAL" "$BR_ROWS"

  printf '## Worktrees\n\n'
  if [[ "$WT_ROWS" -eq 0 ]]; then
    printf '_No worktrees._\n\n'
  else
    printf '| path | branch | dirty | locked | prunable | active | age (d) |\n'
    printf '|------|--------|-------|--------|----------|--------|---------|\n'
    awk -F'\t' 'NR > 1 {
      gsub(/\|/, "\\|", $1); gsub(/\|/, "\\|", $2)
      printf "| %s | %s | %s | %s | %s | %s | %s |\n", $1, $2, $9, $5, $6, $16, $14
    }' "$WORKTREES_TSV"
    printf '\n'
  fi

  printf '## Branches grouped by name-prefix family\n\n'
  if [[ "$BR_ROWS" -eq 0 ]]; then
    printf '_No non-canonical branches._\n\n'
  else
    awk -F'\t' 'NR > 1 {
      family = $20
      rows[family] = rows[family] sprintf("- `%s`  (ahead %s / behind %s,  cherry +%s -%s,  upstream=%s,  age=%sd)\n", \
        $1, $7, $8, $10, $11, $13, $19)
      counts[family]++
    }
    END {
      n = asorti(counts, sorted, "@val_num_desc")
      for (i = 1; i <= n; i++) {
        f = sorted[i]
        printf "### `%s/*` (%d branches)\n\n%s\n", f, counts[f], rows[f]
      }
    }' "$BRANCHES_TSV"
  fi
} > "$INVENTORY_MD"

echo "wrote $WORKTREES_TSV ($WT_ROWS worktree rows)"
echo "wrote $BRANCHES_TSV  ($BR_ROWS branch rows, excl. canonical $CANONICAL)"
echo "wrote $INVENTORY_MD"
