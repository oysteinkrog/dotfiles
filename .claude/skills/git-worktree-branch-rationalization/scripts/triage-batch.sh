#!/usr/bin/env bash
# triage-batch.sh — Phase 5 worker: triage one batch of branches and worktrees.
#
# Usage:
#   triage-batch.sh <project-path> <batch-id> [<branches.list>]
#
# When <branches.list> is supplied, only branches/worktrees listed there are
# processed. Otherwise the entire branches.tsv + worktrees.tsv inventory is.
#
# For each BRANCH the worker:
#   ✦ FINGERPRINT: extract introduced symbol names from diff-vs-merge-base
#   ◐ VERIFY-ON-CANONICAL: grep canonical for each fingerprint
#     (cherry-check, patch-id flavor): git cherry -v <canonical> <branch>
#     (apply-check, no apply):         git merge-tree <canonical> <branch>
# and emits one row to <workspace>/triage/batch_<id>.tsv with verdict + evidence.
#
# For each WORKTREE the worker classifies dirty-state-only / garbage / protected.
#
# Output TSV columns:
#   kind  name_or_path  verdict  confidence  apply_strategy  evidence  files_touched

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=project-root.sh
. "$SCRIPT_DIR/project-root.sh"

log() { printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*"; }

usage() {
  cat <<USAGE
Usage: triage-batch.sh <project-path> <batch-id> [<branches.list>]

Phase 5 worker. Emits <workspace>/triage/batch_<batch-id>.tsv with verdicts for
the requested branches/worktrees.

Branches.list (optional): one entry per line. Branch entries are bare names;
worktree entries are absolute paths prefixed with 'wt:' (e.g.
\`wt:/data/projects/foo-wt-debug\`).

Env:
  WORKSPACE   Workspace dir override.

Exit codes:
  0  ok
  2  preflight failed (inventory or bundle missing)
USAGE
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  '') usage >&2; exit 64 ;;
esac

PROJECT="$1"
BATCH_ID="${2:?missing batch-id}"
LIST_FILE="${3:-}"

PROJECT_ABS="$(resolve_project_root "$PROJECT")" || exit 2
WORKSPACE_DIR="$(resolve_workspace "$PROJECT_ABS")"
PROFILE="$WORKSPACE_DIR/project_profile.json"
BRANCHES_TSV="$WORKSPACE_DIR/branches.tsv"
WORKTREES_TSV="$WORKSPACE_DIR/worktrees.tsv"
BUNDLE_PATH_FILE="$WORKSPACE_DIR/bundle_path.txt"
PROTECTED_TSV="$WORKSPACE_DIR/protected.tsv"

for f in "$PROFILE" "$BRANCHES_TSV" "$WORKTREES_TSV" "$BUNDLE_PATH_FILE"; do
  if [[ ! -f "$f" ]]; then
    echo "ERROR: $f missing — run prior phases first." >&2
    exit 2
  fi
done
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
ACTIVE_BRANCH=$(profile_value active_branch)
MERGE_STYLE=$(profile_value merge_style)
if git -C "$PROJECT_ABS" rev-parse --verify --quiet "refs/heads/$CANONICAL^{commit}" >/dev/null 2>&1; then
  CANON_REF="refs/heads/$CANONICAL"
elif git -C "$PROJECT_ABS" rev-parse --verify --quiet "refs/remotes/origin/$CANONICAL^{commit}" >/dev/null 2>&1; then
  CANON_REF="refs/remotes/origin/$CANONICAL"
else
  echo "ERROR: canonical branch '$CANONICAL' does not resolve locally or as origin/$CANONICAL." >&2
  exit 2
fi

TRIAGE_DIR="$WORKSPACE_DIR/triage"
mkdir -p "$TRIAGE_DIR"
OUT="$TRIAGE_DIR/batch_${BATCH_ID}.tsv"

# Header
printf 'kind\tname_or_path\tverdict\tconfidence\tapply_strategy\tevidence\tfiles_touched\n' > "$OUT"

# ---- Helpers ----

# Extract introduced symbols from a unified diff: function/type/test/class names
# in `+` lines.
fingerprint_diff() {
  local diff="$1"
  { grep -hE '^\+.*\b(fn|def|function|class|struct|enum|trait|interface|type|const|let|static|impl|module|namespace) [A-Za-z_][A-Za-z0-9_]*' "$diff" 2>/dev/null || true; } \
    | sed -E 's/^\+.*\b(fn|def|function|class|struct|enum|trait|interface|type|const|let|static|impl|module|namespace) +([A-Za-z_][A-Za-z0-9_]*).*/\2/' \
    | sort -u
}

meaningful_fingerprint_diff() {
  local diff="$1"
  fingerprint_diff "$diff" | while IFS= read -r sym; do
    [[ -z "$sym" ]] && continue
    case "$sym" in main|new|init|run|build|test|setup|teardown|default|self|this|args|kwargs) continue ;; esac
    printf '%s\n' "$sym"
  done
}

# Files in a unified diff.
files_in_diff() {
  local diff="$1"
  { grep -E '^diff --git a/' "$diff" 2>/dev/null || true; } \
    | sed -E 's@^diff --git a/(.*) b/.*@\1@' \
    | sort -u
}

files_in_worktree_bundle() {
  local path="$1" san wt_dir
  san=$(sanitize_path "$path")
  wt_dir="$BUNDLE/worktrees/$san"
  {
    [[ -f "$wt_dir/staged.diff" ]] && files_in_diff "$wt_dir/staged.diff"
    [[ -f "$wt_dir/unstaged.diff" ]] && files_in_diff "$wt_dir/unstaged.diff"
    [[ -s "$wt_dir/.untracked.list" ]] && tr '\0' '\n' < "$wt_dir/.untracked.list"
  } | awk 'NF > 0' | sort -u
}

file_preview_csv() {
  sed -n '1,20p' | paste -sd, -
}

# Grep canonical for each fingerprint symbol; emit "found|total".
verify_on_canonical() {
  local diff="$1" found=0 total=0 sym
  while IFS= read -r sym; do
    [[ -z "$sym" ]] && continue
    total=$((total + 1))
    if git -C "$PROJECT_ABS" grep -q -F -- "$sym" "$CANON_REF" 2>/dev/null; then
      found=$((found + 1))
    fi
  done < <(meaningful_fingerprint_diff "$diff")
  printf '%s|%s' "$found" "$total"
}

# `git merge-tree` apply-check (no apply, no working-tree mutation).
apply_check_merge_tree() {
  local branch="$1"
  local branch_ref="refs/heads/$branch" merge_base
  merge_base=$(git -C "$PROJECT_ABS" merge-base "$CANON_REF" "$branch_ref" 2>/dev/null || true)
  if [[ -z "$merge_base" ]]; then
    echo unknown
    return
  fi
  # `git merge-tree --write-tree` returns 0 with conflicts in stderr/stdout.
  # Use the older form which prints conflict markers — count occurrences.
  local out
  if ! out=$(git -C "$PROJECT_ABS" merge-tree "$merge_base" "$CANON_REF" "$branch_ref" 2>/dev/null); then
    echo unknown
    return
  fi
  if printf '%s' "$out" | grep -q '<<<<<<< '; then
    echo conflict
  else
    echo clean
  fi
}

# Cherry summary (already-on-canonical detection via patch-id).
cherry_summary() {
  local branch="$1"
  local branch_ref="refs/heads/$branch" out plus minus
  if ! out=$(git -C "$PROJECT_ABS" cherry "$CANON_REF" "$branch_ref" 2>/dev/null); then
    printf '0|0'
    return
  fi
  plus=$(printf  '%s\n' "$out" | grep -c '^+' || true)
  minus=$(printf '%s\n' "$out" | grep -c '^-' || true)
  printf '%s|%s' "$plus" "$minus"
}

profile_protected_patterns() {
  if command -v jq >/dev/null 2>&1; then
    jq -r '.protected_patterns[]?' "$PROFILE" 2>/dev/null
    return
  fi
  python3 - "$PROFILE" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)
for pattern in data.get("protected_patterns", []):
    print(pattern)
PY
}

protected_branch_reason() {
  local branch="$1" pattern
  [[ "$branch" == "$CANONICAL" ]] && { echo "canonical branch"; return 0; }
  [[ -n "$ACTIVE_BRANCH" && "$branch" == "$ACTIVE_BRANCH" ]] && { echo "active branch"; return 0; }
  while IFS= read -r pattern; do
    [[ -z "$pattern" ]] && continue
    # shellcheck disable=SC2053  # glob match against branch names is intentional.
    [[ "$branch" == $pattern ]] && { echo "protected pattern: $pattern"; return 0; }
  done < <(profile_protected_patterns)
  if [[ -f "$PROTECTED_TSV" ]]; then
    if awk -F'\t' -v n="$branch" 'NR > 1 && $1 == "branch" && $2 == n {found=1} END {exit !found}' "$PROTECTED_TSV"; then
      echo "protected.tsv entry"
      return 0
    fi
  fi
  return 1
}

# Prefer-strategy hint based on merge_style + branch shape.
choose_apply_strategy() {
  local commits_ahead="$1" verdict="$2"
  case "$verdict" in
    already-merged|garbage|superseded) echo none ;;
    novel-but-stale)                   echo none-default-drop ;;
    divergent-refactor)                echo harmonized-synthesis ;;
    partially-novel)                   echo split-commits-hunks ;;
    novel-and-accretive)
      if   [[ "$commits_ahead" -le 1 ]]; then echo cherry-pick
      elif [[ "$MERGE_STYLE" == "squash" ]]; then echo squash-merge
      elif [[ "$MERGE_STYLE" == "rebase-and-merge" ]]; then echo rebase-and-merge
      else echo cherry-pick; fi ;;
    *) echo unknown ;;
  esac
}

# ---- Build the entries-to-process list ----
declare -a ENTRIES=()
if [[ -n "$LIST_FILE" && -f "$LIST_FILE" ]]; then
  while IFS= read -r ln; do
    [[ -z "$ln" || "$ln" =~ ^[[:space:]]*# ]] && continue
    ENTRIES+=("$ln")
  done < "$LIST_FILE"
else
  while IFS= read -r row; do
    tsv_read "$row" name _rest
    [[ "$name" == "name" ]] && continue
    [[ -z "$name" ]] && continue
    ENTRIES+=("$name")
  done < "$BRANCHES_TSV"
  while IFS= read -r row; do
    tsv_read "$row" path _rest
    [[ "$path" == "path" ]] && continue
    [[ -z "$path" ]] && continue
    ENTRIES+=("wt:$path")
  done < "$WORKTREES_TSV"
fi

# ---- Per-entry triage ----
for entry in "${ENTRIES[@]}"; do
  if [[ "$entry" == wt:* ]]; then
    # ===== Worktree row =====
    path="${entry#wt:}"
    # Look up worktree row in inventory.
    row=$(awk -F'\t' -v p="$path" 'NR > 1 && $1 == p {print; exit}' "$WORKTREES_TSV" || true)
    if [[ -z "$row" ]]; then
      printf 'worktree\t%s\tunknown\t0.40\tnone\tnot-in-inventory\t-\n' "$path" >> "$OUT"
      continue
    fi
    branch=; dirty=; staged_size=0; unstaged_size=0; untracked_size=0; untracked_count=0; active=
    tsv_read "$row" _path branch _detached _bare _locked _prunable _last_sha _last_date dirty staged_size unstaged_size untracked_size untracked_count _age_days _inside_main active _subm

    if [[ "$active" == "true" ]]; then
      printf 'worktree\t%s\tprotected-preserve\t1.00\tnone\tactive worktree (user CWD); never removed\t-\n' "$path" >> "$OUT"
      continue
    fi
    if [[ "$dirty" == "true" ]]; then
      total_lines=$(( staged_size + unstaged_size ))
      ev="dirty: staged=$staged_size unstaged=$unstaged_size untracked_files=$untracked_count untracked_bytes=$untracked_size"
      if [[ "$total_lines" -eq 0 && "$untracked_count" -eq 0 ]]; then
        printf 'worktree\t%s\tgarbage\t0.85\tnone\t%s\t-\n' "$path" "$ev" >> "$OUT"
      else
        files_csv=$(files_in_worktree_bundle "$path" | file_preview_csv || echo "")
        [[ -z "$files_csv" ]] && files_csv="-"
        printf 'worktree\t%s\tdirty-worktree-only\t0.80\tdirty-worktree-only\t%s\t%s\n' "$path" "$ev" "$files_csv" >> "$OUT"
      fi
    else
      printf 'worktree\t%s\tgarbage\t0.90\tnone\tclean worktree, no novel content; removable\t-\n' "$path" >> "$OUT"
    fi
    continue
  fi

  # ===== Branch row =====
  name="$entry"
  row=$(awk -F'\t' -v n="$name" 'NR > 1 && $1 == n {print; exit}' "$BRANCHES_TSV" || true)
  if [[ -z "$row" ]]; then
    printf 'branch\t%s\tunknown\t0.30\tnone\tnot-in-inventory\t-\n' "$name" >> "$OUT"
    continue
  fi
  slug=; head_sha=; last_date=; author=; subject=; ahead=; behind=; commits_ahead=0
  cherry_plus=; cherry_minus=; upstream=; upstream_status=; wt_path=; touched=
  insertions=; deletions=; files_changed=0; age_days=; prefix=
  tsv_read "$row" _name slug head_sha last_date author subject ahead behind commits_ahead cherry_plus cherry_minus upstream upstream_status wt_path touched insertions deletions files_changed age_days prefix

  if protected_reason=$(protected_branch_reason "$name"); then
    printf 'branch\t%s\tprotected-preserve\t1.00\tnone\t%s; never enters apply or cleanup\t-\n' "$name" "$protected_reason" >> "$OUT"
    continue
  fi

  diff_path="$BUNDLE/branches/$slug/diff-vs-merge-base.diff"
  if [[ ! -f "$diff_path" ]]; then
    printf 'branch\t%s\tunknown\t0.30\tnone\tdiff-not-in-bundle\t-\n' "$name" >> "$OUT"
    continue
  fi

  # Cherry summary from inventory (we already computed in Phase 2). Fall back to
  # computing fresh if inventory doesn't have it.
  cs=$(cherry_summary "$name")
  cp_now=${cs%|*}; cm_now=${cs#*|}

  # All `-` lines (cherry shows no `+` lines): every patch-id is on canonical.
  if [[ "$cp_now" -eq 0 && "$cm_now" -gt 0 ]]; then
    files_csv=$(files_in_diff "$diff_path" | file_preview_csv || echo "")
    printf 'branch\t%s\talready-merged\t0.95\tnone\tgit cherry: 0 novel patch-ids, %s already-on-canonical\t%s\n' \
      "$name" "$cm_now" "$files_csv" >> "$OUT"
    continue
  fi

  # Empty branch (no commits ahead) — could be a label only.
  if [[ "${commits_ahead:-0}" -eq 0 ]]; then
    printf 'branch\t%s\talready-merged\t0.99\tnone\tno commits ahead of canonical\t-\n' "$name" >> "$OUT"
    continue
  fi

  # Verify on canonical.
  vc=$(verify_on_canonical "$diff_path")
  found=${vc%|*}; total=${vc#*|}
  if [[ "$total" -eq 0 ]]; then
    fp_frac=0
  else
    fp_frac=$(awk -v f="$found" -v t="$total" 'BEGIN { printf "%.2f", f/t }')
  fi

  ac=$(apply_check_merge_tree "$name")

  files_csv=$(files_in_diff "$diff_path" | file_preview_csv || echo "")

  # Verdict tree.
  verdict=unknown; conf=0.50; ev="ambiguous"
  if [[ "$total" -eq 0 && "${files_changed:-0}" -gt 0 ]]; then
    # No introduced symbols but files changed: could be config/whitespace/binary.
    verdict=unknown
    conf=0.50
    ev="empty fingerprint despite files_changed=$files_changed; surface to user"
  elif awk -v fp="$fp_frac" 'BEGIN { exit !(fp >= 0.90) }'; then
    verdict=superseded
    conf=$(awk -v fp="$fp_frac" 'BEGIN { printf "%.2f", 0.85 + 0.10 * fp }')
    ev="$found/$total fingerprint symbols on canonical (≥90%)"
  elif awk -v fp="$fp_frac" 'BEGIN { exit !(fp <= 0.05) }' && [[ "$ac" == "clean" ]]; then
    verdict=novel-and-accretive
    conf=$(awk -v fp="$fp_frac" 'BEGIN { printf "%.2f", 0.80 + 0.15 * (1 - fp) }')
    ev="0/$total fingerprint on canonical; merge-tree clean"
  elif awk -v fp="$fp_frac" 'BEGIN { exit !(fp <= 0.05) }' && [[ "$ac" == "conflict" ]]; then
    verdict=novel-but-stale
    conf=0.65
    ev="novel content, but merge-tree reports conflicts (canonical has moved)"
  elif awk -v fp="$fp_frac" 'BEGIN { exit !(fp >= 0.30 && fp < 0.90) }'; then
    # Mid-range: divergent on the same symbols. Flag for harmonization (Axiom 16).
    verdict=divergent-refactor
    conf=0.70
    ev="$found/$total symbols overlap canonical with potentially-different signatures (harmonization candidate)"
  elif awk -v fp="$fp_frac" 'BEGIN { exit !(fp > 0.05 && fp < 0.30) }'; then
    verdict=partially-novel
    conf=0.65
    ev="$found/$total symbols on canonical, rest novel; split-apply candidate"
  else
    verdict=unknown
    conf=0.55
    ev="fp=$fp_frac apply-check=$ac"
  fi

  # Cherry signal: if there ARE `-` lines among `+` lines, force at least
  # partially-novel (some content already merged, rest is new).
  if [[ "$cm_now" -gt 0 && "$cp_now" -gt 0 && "$verdict" != "divergent-refactor" ]]; then
    if [[ "$verdict" == "novel-and-accretive" ]]; then
      verdict=partially-novel
      ev="$ev; git cherry: $cm_now already-merged + $cp_now novel"
      conf=0.70
    fi
  fi

  strategy=$(choose_apply_strategy "${commits_ahead:-0}" "$verdict")

  printf 'branch\t%s\t%s\t%s\t%s\t%s\t%s\n' "$name" "$verdict" "$conf" "$strategy" "$ev" "$files_csv" >> "$OUT"

  : "$head_sha" "$last_date" "$author" "$subject" "$ahead" "$behind" "$cherry_plus" "$cherry_minus" "$upstream" "$upstream_status" "$wt_path" "$touched" "$insertions" "$deletions" "$age_days" "$prefix"
done

# Summary
echo "wrote $OUT ($((${#ENTRIES[@]})) entries)"
echo "Verdict counts in this batch:"
awk -F'\t' 'NR > 1 {print $3}' "$OUT" | sort | uniq -c
