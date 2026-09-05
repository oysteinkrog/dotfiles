#!/usr/bin/env bash
# verify-bundle.sh — Phase 3 gate: byte-equality + bundle round-trip.
#
# Verifies, for every entry in the inventory:
#   - Branch backup ref SHA == live branch SHA (byte-equality).
#   - Branch diff-vs-merge-base, when re-derived from live state, is sha256-equal
#     to the bundle's diff file.
#   - Branch format-patch directory exists when commits_ahead > 0.
#   - Worktree status / staged.diff / unstaged.diff, when re-snapshotted, equal
#     the bundle's captures.
#   - Object bundle passes `git bundle verify`, `git bundle list-heads`
#     reports the full set of backup refs at the recorded branch tips, AND a
#     fresh bare repo can fetch the backup namespace from the pack.
#
# Output: <workspace>/bundle_verification.log (one line per check, OK / MISMATCH / MISSING).
#
# Exit codes:
#   0  every check passed
#   1  any mismatch (run is unsafe — halt before destructive phases)
#   2  inventory or bundle missing

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=project-root.sh
. "$SCRIPT_DIR/project-root.sh"

usage() {
  cat <<USAGE
Usage: verify-bundle.sh <project-path>

Phase 3 gate: byte-equality + bundle round-trip verification. Exits non-zero on
any mismatch; the run halts before destructive phases.

Env:
  WORKSPACE   Workspace dir override.

Exit codes:
  0  ok
  1  mismatches found (see <workspace>/bundle_verification.log)
  2  inventory or bundle missing
USAGE
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  '') usage >&2; exit 64 ;;
esac

PROJECT="$1"
PROJECT_ABS="$(resolve_project_root "$PROJECT")" || exit 2
WORKSPACE_DIR="$(resolve_workspace "$PROJECT_ABS")"
BRANCHES_TSV="$WORKSPACE_DIR/branches.tsv"
WORKTREES_TSV="$WORKSPACE_DIR/worktrees.tsv"
BUNDLE_PATH_FILE="$WORKSPACE_DIR/bundle_path.txt"
LOG="$WORKSPACE_DIR/bundle_verification.log"

if [[ ! -f "$BRANCHES_TSV" || ! -f "$WORKTREES_TSV" ]]; then
  echo "ERROR: inventory missing under $WORKSPACE_DIR (expected branches.tsv and worktrees.tsv)." >&2
  echo "  Fix: run scripts/discover-branches-worktrees.sh <project-path> first (Phase 2)." >&2
  exit 2
fi
if [[ ! -f "$BUNDLE_PATH_FILE" ]]; then
  echo "ERROR: $BUNDLE_PATH_FILE missing — run build-bundle.sh first." >&2
  exit 2
fi
BUNDLE="$(cat "$BUNDLE_PATH_FILE")"
if [[ ! -d "$BUNDLE" ]]; then
  echo "ERROR: bundle directory $BUNDLE does not exist." >&2
  exit 2
fi

: > "$LOG"

BACKUP_NS="refs/branch-rationalization-backup"
join_items() {
  local IFS=,
  printf '%s' "$*"
}

# Resolve canonical once, up front, for the diff round-trip.
PROFILE_JSON="$WORKSPACE_DIR/project_profile.json"
CANONICAL=""
if [[ -f "$PROFILE_JSON" ]]; then
  if command -v jq >/dev/null 2>&1; then
    CANONICAL=$(jq -r '.canonical_branch // ""' "$PROFILE_JSON" 2>/dev/null || true)
  elif command -v python3 >/dev/null 2>&1; then
    CANONICAL=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get('canonical_branch',''))" "$PROFILE_JSON" 2>/dev/null || true)
  fi
fi
if [[ -z "$CANONICAL" ]]; then
  echo "ERROR: cannot determine canonical branch from $PROFILE_JSON." >&2
  echo "  Fix: run scripts/discover-project.sh <project-path> first (Phase 1) so canonical_branch is detected and persisted." >&2
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

# ---- Branch checks ----
while IFS= read -r row; do
  name=""
  slug=""
  commits_ahead=""
  tsv_read "$row" name slug head_sha last_date author subject ahead behind commits_ahead cherry_plus cherry_minus upstream upstream_status wt_path touched insertions deletions files_changed age_days prefix
  [[ "$name" == "name" ]] && continue
  [[ -z "$slug" ]] && continue
  branch_ref="refs/heads/$name"

  # 1. Backup ref byte-equality.
  backup_sha=$(git -C "$PROJECT_ABS" rev-parse --verify --quiet "$BACKUP_NS/$slug^{commit}" 2>/dev/null || echo "MISSING")
  live_sha=$(git -C "$PROJECT_ABS" rev-parse --verify --quiet "$branch_ref^{commit}" 2>/dev/null || echo "MISSING")
  if [[ "$live_sha" == "MISSING" ]]; then
    echo "MISMATCH branch $name REF: live ref vanished since inventory" >> "$LOG"
  elif [[ "$backup_sha" != "$live_sha" ]]; then
    echo "MISMATCH branch $name REF: live=$live_sha backup=$backup_sha" >> "$LOG"
  else
    echo "OK branch $name REF: $live_sha" >> "$LOG"
  fi

  # 2. Diff round-trip.
  diff_path="$BUNDLE/branches/$slug/diff-vs-merge-base.diff"
  if [[ ! -f "$diff_path" ]]; then
    echo "MISSING branch $name DIFF: $diff_path" >> "$LOG"
  else
    merge_base=$(git -C "$PROJECT_ABS" merge-base "$CANON_REF" "$branch_ref" 2>/dev/null || true)
    if [[ -z "$merge_base" ]]; then
      echo "MISSING branch $name DIFF: cannot resolve merge-base for round-trip" >> "$LOG"
    else
      live_hash=$(git -C "$PROJECT_ABS" diff --binary "$merge_base" "$branch_ref" 2>/dev/null | sha256sum | awk '{print $1}')
      bundle_hash=$(sha256sum "$diff_path" | awk '{print $1}')
      if [[ "$live_hash" != "$bundle_hash" ]]; then
        echo "MISMATCH branch $name DIFF: live_sha256=$live_hash bundle_sha256=$bundle_hash" >> "$LOG"
      else
        echo "OK branch $name DIFF: $live_hash" >> "$LOG"
      fi
    fi
  fi

  # 3. format-patch presence (when commits_ahead > 0).
  fp_dir="$BUNDLE/branches/$slug/format-patch"
  if [[ "${commits_ahead:-0}" -gt 0 ]]; then
    if [[ ! -d "$fp_dir" ]]; then
      echo "MISSING branch $name FORMAT-PATCH: directory absent ($fp_dir)" >> "$LOG"
    else
      n_patches=$(find "$fp_dir" -maxdepth 1 -type f -name '*.patch' 2>/dev/null | wc -l)
      if [[ "$n_patches" -lt 1 ]]; then
        echo "MISSING branch $name FORMAT-PATCH: 0 patches in $fp_dir" >> "$LOG"
      else
        echo "OK branch $name FORMAT-PATCH: $n_patches patch(es)" >> "$LOG"
      fi
    fi
  fi

  # 4. Meta presence.
  if [[ ! -f "$BUNDLE/branches/$slug/meta.txt" ]]; then
    echo "MISSING branch $name META: meta.txt absent" >> "$LOG"
  fi
done < "$BRANCHES_TSV"

# ---- Worktree checks ----
while IFS= read -r row; do
  path=""
  untracked_count=""
  tsv_read "$row" path branch detached bare locked prunable last_sha last_date dirty staged_size unstaged_size untracked_size untracked_count age_days inside_main active subm
  [[ "$path" == "path" ]] && continue
  san=$(sanitize_path "$path")
  wt_dir="$BUNDLE/worktrees/$san"
  if [[ ! -d "$wt_dir" ]]; then
    echo "MISSING worktree $path DIR: $wt_dir" >> "$LOG"
    continue
  fi

  status_file="$wt_dir/status.txt"
  staged_file="$wt_dir/staged.diff"
  unstaged_file="$wt_dir/unstaged.diff"

  if [[ ! -f "$status_file" ]]; then
    echo "MISSING worktree $path STATUS: status.txt absent" >> "$LOG"
  fi
  if [[ ! -f "$staged_file" ]]; then
    echo "MISSING worktree $path STAGED: staged.diff absent" >> "$LOG"
  fi
  if [[ ! -f "$unstaged_file" ]]; then
    echo "MISSING worktree $path UNSTAGED: unstaged.diff absent" >> "$LOG"
  fi

  # status round-trip — only when the path still exists.
  if [[ -d "$path" ]]; then
    if [[ -f "$status_file" ]]; then
      live_status_hash=$(git -C "$path" status --porcelain=v2 --untracked-files=all 2>/dev/null | sha256sum | awk '{print $1}')
      bundle_status_hash=$(sha256sum "$status_file" | awk '{print $1}')
      if [[ "$live_status_hash" != "$bundle_status_hash" ]]; then
        echo "MISMATCH worktree $path STATUS: live=$live_status_hash bundle=$bundle_status_hash (drift since bundle)" >> "$LOG"
      else
        echo "OK worktree $path STATUS" >> "$LOG"
      fi
    fi

    # staged/unstaged diff round-trip.
    if [[ -f "$staged_file" ]]; then
      live_staged_hash=$(git -C "$path" diff --binary --cached 2>/dev/null | sha256sum | awk '{print $1}')
      bundle_staged_hash=$(sha256sum "$staged_file" | awk '{print $1}')
      if [[ "$live_staged_hash" != "$bundle_staged_hash" ]]; then
        echo "MISMATCH worktree $path STAGED: live=$live_staged_hash bundle=$bundle_staged_hash" >> "$LOG"
      else
        echo "OK worktree $path STAGED" >> "$LOG"
      fi
    fi

    if [[ -f "$unstaged_file" ]]; then
      live_unstaged_hash=$(git -C "$path" diff --binary 2>/dev/null | sha256sum | awk '{print $1}')
      bundle_unstaged_hash=$(sha256sum "$unstaged_file" | awk '{print $1}')
      if [[ "$live_unstaged_hash" != "$bundle_unstaged_hash" ]]; then
        echo "MISMATCH worktree $path UNSTAGED: live=$live_unstaged_hash bundle=$bundle_unstaged_hash" >> "$LOG"
      else
        echo "OK worktree $path UNSTAGED" >> "$LOG"
      fi
    fi
  else
    echo "OK worktree $path STATUS: path absent at verify time (bundle captured pre-removal)" >> "$LOG"
  fi

  # untracked.tar.gz presence when expected.
  if [[ "${untracked_count:-0}" -gt 0 ]]; then
    if [[ ! -s "$wt_dir/.untracked.list" ]]; then
      echo "MISSING worktree $path UNTRACKED: .untracked.list absent or empty (count=$untracked_count)" >> "$LOG"
    else
      echo "OK worktree $path UNTRACKED-MANIFEST: present" >> "$LOG"
    fi
    if [[ ! -f "$wt_dir/untracked.tar.gz" ]]; then
      echo "MISSING worktree $path UNTRACKED: untracked.tar.gz absent (count=$untracked_count)" >> "$LOG"
    elif [[ -s "$wt_dir/.untracked.list" ]] && ! tar --null -tzf "$wt_dir/untracked.tar.gz" -T "$wt_dir/.untracked.list" >/dev/null 2>&1; then
      echo "MISMATCH worktree $path UNTRACKED: tarball cannot list manifest entries" >> "$LOG"
    else
      echo "OK worktree $path UNTRACKED: tarball present" >> "$LOG"
    fi
    if [[ ! -s "$wt_dir/.untracked.sha256" ]]; then
      echo "MISSING worktree $path UNTRACKED-HASHES: .untracked.sha256 absent or empty (count=$untracked_count)" >> "$LOG"
    elif [[ -d "$path" ]]; then
      live_untracked_hash=$(untracked_content_manifest_hash_for_root "$path" <(git -C "$path" ls-files --others --exclude-standard -z | sort -z) 2>/dev/null || echo "MISSING")
      bundle_untracked_hash=$(sha256sum "$wt_dir/.untracked.sha256" 2>/dev/null | awk '{print $1}')
      if [[ "$live_untracked_hash" != "$bundle_untracked_hash" ]]; then
        echo "MISMATCH worktree $path UNTRACKED-HASHES: live=$live_untracked_hash bundle=$bundle_untracked_hash" >> "$LOG"
      else
        echo "OK worktree $path UNTRACKED-HASHES: $live_untracked_hash" >> "$LOG"
      fi
    fi
  fi
done < "$WORKTREES_TSV"

# ---- Object-bundle round-trip ----
PACK="$BUNDLE/object-bundle.pack"
if [[ -f "$PACK" ]]; then
  if git -C "$PROJECT_ABS" bundle verify "$PACK" >/dev/null 2>&1; then
    echo "OK bundle VERIFY: $PACK" >> "$LOG"
  else
    echo "MISMATCH bundle VERIFY: git bundle verify failed for $PACK" >> "$LOG"
  fi
  # list-heads should report at least one ref under $BACKUP_NS.
  heads=$(git -C "$PROJECT_ABS" bundle list-heads "$PACK" 2>/dev/null || true)
  declare -A PACK_HEAD_SHAS=()
  while IFS=' ' read -r sha ref _rest; do
    [[ -z "${sha:-}" || -z "${ref:-}" ]] && continue
    PACK_HEAD_SHAS["$ref"]="$sha"
  done <<< "$heads"
  n_heads=0
  for ref in "${!PACK_HEAD_SHAS[@]}"; do
    case "$ref" in
      "$BACKUP_NS"/*) n_heads=$((n_heads + 1)) ;;
    esac
  done
  missing_heads=()
  mismatched_heads=()
  while IFS= read -r row; do
    slug=""; head_sha=""
    tsv_read "$row" _name slug head_sha _rest
    [[ -z "$slug" || "$slug" == "slug" ]] && continue
    expected_ref="$BACKUP_NS/$slug"
    pack_sha="${PACK_HEAD_SHAS[$expected_ref]:-}"
    if [[ -z "$pack_sha" ]]; then
      missing_heads+=("$expected_ref")
    fi
    if [[ -n "$pack_sha" && -n "$head_sha" && "$pack_sha" != "$head_sha" ]]; then
      mismatched_heads+=("$expected_ref expected=$head_sha pack=$pack_sha")
    fi
  done < "$BRANCHES_TSV"
  if [[ "${#missing_heads[@]}" -gt 0 ]]; then
    echo "MISMATCH bundle LIST-HEADS: missing ${#missing_heads[@]} backup ref(s): $(join_items "${missing_heads[@]:0:5}")" >> "$LOG"
  elif [[ "${#mismatched_heads[@]}" -gt 0 ]]; then
    echo "MISMATCH bundle LIST-HEADS: ${#mismatched_heads[@]} backup ref(s) point at wrong commit(s): $(join_items "${mismatched_heads[@]:0:3}")" >> "$LOG"
  elif [[ "$n_heads" -lt 1 ]]; then
    echo "MISMATCH bundle LIST-HEADS: 0 backup-namespace heads in pack" >> "$LOG"
  else
    echo "OK bundle LIST-HEADS: $n_heads backup-namespace head(s) at recorded branch tips" >> "$LOG"
  fi
  if bundle_fetch_roundtrip "$PACK" "$BACKUP_NS" "$WORKSPACE_DIR"; then
    echo "OK bundle FETCH: backup namespace fetches into a fresh object database" >> "$LOG"
  else
    echo "MISMATCH bundle FETCH: git fetch from object-bundle.pack failed; recovery would fail" >> "$LOG"
  fi
else
  # An empty backup-ref set legitimately produces no pack (pre-flight refused
  # to create one). Record honestly but don't fail.
  n_refs=$(git -C "$PROJECT_ABS" for-each-ref "$BACKUP_NS/" 2>/dev/null | wc -l)
  if [[ "$n_refs" -gt 0 ]]; then
    echo "MISSING bundle PACK: object-bundle.pack absent despite $n_refs backup refs" >> "$LOG"
  else
    echo "OK bundle PACK: skipped (no backup refs)" >> "$LOG"
  fi
fi

# ---- Roll up ----
count_lines() {
  local out
  out=$(grep -cE "$1" "$LOG" 2>/dev/null || true)
  printf '%s' "${out:-0}"
}
MISMATCHES=$(count_lines '^MISMATCH|^MISSING' "$LOG")
OK_ROWS=$(count_lines '^OK ' "$LOG")

echo
echo "Verification complete:"
echo "  OK rows:            $OK_ROWS"
echo "  Mismatch / missing: $MISMATCHES"
echo
echo "Full log: $LOG"

if [[ "$MISMATCHES" -gt 0 ]]; then
  echo
  echo "*** GATE FAILURE ***"
  echo "Some bundle artifacts do not match the live state."
  echo "Inspect $LOG for details. Do NOT proceed to destructive phases."
  exit 1
fi

echo "Gate passed. Bundle is byte-equality + round-trip verified."
exit 0
