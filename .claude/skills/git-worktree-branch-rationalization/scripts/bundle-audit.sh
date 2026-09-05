#!/usr/bin/env bash
# bundle-audit.sh — Phase 3 / 10 / 11 deep audit of bundle integrity.
#
# Goes beyond verify-bundle.sh's byte-equality + round-trip gate. Verifies the
# *internal coherence* of the bundle:
#
#   A1  every branches.tsv row has a backup ref, a per-branch directory, and
#       a bundle list-heads entry at the recorded branch tip
#   A2  every worktrees.tsv row has a per-worktree directory
#   A3  every branches/<slug>/meta.txt is present and readable
#   A4  every branches/<slug>/commits.tsv row count matches `commits_ahead`
#   A5  every branches/<slug>/diff-vs-merge-base.diff is non-empty UNLESS
#       commits_ahead==0 AND files_changed==0 (already-merged labels)
#   A6  every branches/<slug>/format-patch/*.patch count matches commits_ahead
#       (when commits_ahead > 0)
#   A7  every dirty worktree has staged.diff + unstaged.diff + status.txt
#   A8  every worktree with untracked content has untracked.tar.gz AND
#       .untracked.list, and the tarball can list every manifest entry
#   A9  README.md is present and mentions every recovery recipe
#   A10 index.tsv cross-references the per-branch and per-worktree dirs
#
# Output: <workspace>/bundle_audit.log + a stdout summary.
#
# Exit codes:
#   0  every check passed
#   1  one or more findings (run is unsafe — halt before destructive phases)
#   2  preflight failed (inventory or bundle missing)

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=project-root.sh
. "$SCRIPT_DIR/project-root.sh"

usage() {
  cat <<USAGE
Usage: bundle-audit.sh <project-path>

Phase 3 / 10 / 11 deep audit of bundle internal coherence. Goes beyond
verify-bundle.sh's byte-equality gate. Writes <workspace>/bundle_audit.log.

Env:
  WORKSPACE   Workspace dir override.

Exit codes:
  0  every check passed
  1  findings present (do NOT proceed to destructive phases)
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
BRANCHES_TSV="$WORKSPACE_DIR/branches.tsv"
WORKTREES_TSV="$WORKSPACE_DIR/worktrees.tsv"
BUNDLE_PATH_FILE="$WORKSPACE_DIR/bundle_path.txt"

for f in "$BRANCHES_TSV" "$WORKTREES_TSV" "$BUNDLE_PATH_FILE"; do
  if [[ ! -f "$f" ]]; then
    echo "ERROR: $f missing — run prior phases first." >&2
    exit 2
  fi
done
BUNDLE="$(cat "$BUNDLE_PATH_FILE")"
if [[ ! -d "$BUNDLE" ]]; then
  echo "ERROR: bundle directory $BUNDLE does not exist." >&2
  exit 2
fi

LOG="$WORKSPACE_DIR/bundle_audit.log"
INDEX="$BUNDLE/index.tsv"
README="$BUNDLE/README.md"
PACK="$BUNDLE/object-bundle.pack"

: > "$LOG"
findings=0
note() { printf '[%s] %s\n' "$1" "$2" | tee -a "$LOG" >/dev/null; }
fail() { note FAIL "$1"; findings=$((findings + 1)); }
pass() { note PASS "$1"; }
warn() { note WARN "$1"; }
join_items() {
  local IFS=,
  printf '%s' "$*"
}

BACKUP_NS="refs/branch-rationalization-backup"

# A9: README presence + canonical recipe coverage. Done first so a missing
# README doesn't cascade silent failures further down.
if [[ -f "$README" ]]; then
  missing_recipes=()
  grep -qE 'backup ref'                            "$README" || missing_recipes+=("backup-ref recovery")
  grep -qE 'object[ -]bundle|object-bundle\.pack'  "$README" || missing_recipes+=("object-bundle fetch")
  grep -qE 'diff-vs-merge-base|git apply'          "$README" || missing_recipes+=("per-branch diff apply")
  grep -qE 'format-patch|git am'                   "$README" || missing_recipes+=("format-patch series apply")
  grep -qE 'staged\.diff|unstaged\.diff|untracked' "$README" || missing_recipes+=("worktree dirty-state restoration")
  if [[ "${#missing_recipes[@]}" -eq 0 ]]; then
    pass "README.md mentions every recovery recipe (5/5)"
  else
    fail "README.md missing recipe sections: $(join_items "${missing_recipes[@]}")"
  fi
else
  fail "README.md missing at $README"
fi

# A10 setup: parse index.tsv into per-bundle-path lookup table.
declare -A INDEX_PATHS=()
INDEX_ROWS=0
if [[ -f "$INDEX" ]]; then
  while IFS= read -r row; do
    kind=""
    name_or_path=""
    slug=""
    bundle_paths=""
    tsv_read "$row" kind name_or_path slug _head_sha _merge_base _ahead _behind _smell _intake_protected _verdict bundle_paths
    [[ "$kind" == "kind" ]] && continue
    [[ -z "$kind" ]] && continue
    INDEX_ROWS=$((INDEX_ROWS + 1))
    while IFS= read -r bundle_path; do
      [[ -z "$bundle_path" ]] && continue
      INDEX_PATHS["$bundle_path"]="$kind|$name_or_path|$slug"
    done < <(printf '%s\n' "$bundle_paths" | tr ',' '\n')
  done < "$INDEX"
  pass "index.tsv has $INDEX_ROWS data rows"
else
  fail "index.tsv missing at $INDEX"
fi

# A1+A3+A4+A5+A6 — per-branch checks.
declare -A BUNDLE_HEADS=()
if [[ -f "$PACK" ]]; then
  # `git bundle list-heads` prints one '<sha> <ref>' per line. Capture and
  # turn into a ref -> sha map so recovery-tip checks are O(1).
  while IFS=' ' read -r sha ref _rest; do
    [[ -z "${sha:-}" || -z "${ref:-}" ]] && continue
    BUNDLE_HEADS["$ref"]="$sha"
  done < <(git -C "$PROJECT_ABS" bundle list-heads "$PACK" 2>/dev/null || true)
  if bundle_fetch_roundtrip "$PACK" "$BACKUP_NS" "$WORKSPACE_DIR"; then
    pass "object-bundle.pack fetches backup namespace into a fresh object database"
  else
    fail "object-bundle.pack is not fetchable; recovery would fail despite list-heads output"
  fi
fi

br_total=0
while IFS= read -r row; do
  name=""; slug=""; head_sha=""; commits_ahead=""; files_changed=""
  tsv_read "$row" name slug head_sha _last_date _author _subject _ahead _behind commits_ahead _cherry_plus _cherry_minus _upstream _upstream_status _wt_path _touched _insertions _deletions files_changed _age_days _prefix
  [[ "$name" == "name" ]] && continue
  [[ -z "$slug" ]] && continue
  br_total=$((br_total + 1))

  # A1 — backup ref
  if ! git -C "$PROJECT_ABS" rev-parse --verify --quiet "$BACKUP_NS/$slug^{commit}" >/dev/null 2>&1; then
    fail "branch $name: backup ref $BACKUP_NS/$slug missing"
  fi

  # A1 — pack carries the backup ref
  if [[ -f "$PACK" ]]; then
    pack_sha="${BUNDLE_HEADS[$BACKUP_NS/$slug]:-}"
    if [[ -z "$pack_sha" ]]; then
      fail "branch $name: $BACKUP_NS/$slug not present in object-bundle.pack list-heads"
    elif [[ -n "$head_sha" && "$pack_sha" != "$head_sha" ]]; then
      fail "branch $name: $BACKUP_NS/$slug in object-bundle.pack points to $pack_sha, expected $head_sha"
    fi
  else
    fail "branch $name: object-bundle.pack missing; cannot verify bundled backup ref $BACKUP_NS/$slug"
  fi

  br_dir="$BUNDLE/branches/$slug"
  if [[ ! -d "$br_dir" ]]; then
    fail "branch $name: bundle directory missing ($br_dir)"
    continue
  fi

  # A3 — meta.txt
  if [[ ! -f "$br_dir/meta.txt" ]]; then
    fail "branch $name: meta.txt missing"
  fi

  # A4 — commits.tsv row count vs commits_ahead
  if [[ -f "$br_dir/commits.tsv" ]]; then
    cs_rows=$(awk 'NR > 1' "$br_dir/commits.tsv" | wc -l)
    if [[ "${commits_ahead:-0}" -ne "$cs_rows" ]]; then
      fail "branch $name: commits.tsv has $cs_rows rows, branches.tsv says commits_ahead=$commits_ahead"
    fi
  else
    fail "branch $name: commits.tsv missing"
  fi

  # A5 — diff-vs-merge-base.diff non-empty unless commits_ahead==0
  diff_path="$br_dir/diff-vs-merge-base.diff"
  if [[ ! -f "$diff_path" ]]; then
    fail "branch $name: diff-vs-merge-base.diff missing"
  elif [[ "${commits_ahead:-0}" -gt 0 ]] && [[ "${files_changed:-0}" -gt 0 ]]; then
    if [[ ! -s "$diff_path" ]]; then
      fail "branch $name: diff-vs-merge-base.diff is empty (commits_ahead=$commits_ahead, files_changed=$files_changed)"
    fi
  fi

  # A6 — format-patch count vs commits_ahead
  fp_dir="$br_dir/format-patch"
  if [[ "${commits_ahead:-0}" -gt 0 ]]; then
    if [[ ! -d "$fp_dir" ]]; then
      fail "branch $name: format-patch directory missing"
    else
      n_patches=$({ find "$fp_dir" -maxdepth 1 -type f -name '*.patch' 2>/dev/null || true; } | wc -l)
      if [[ "$n_patches" -ne "${commits_ahead:-0}" ]]; then
        fail "branch $name: format-patch has $n_patches patches, commits_ahead=$commits_ahead"
      fi
    fi
  fi

  # A10 — index reference
  expected_rel="branches/$slug/"
  if [[ -n "${INDEX_PATHS[$expected_rel]:-}" ]]; then
    indexed="${INDEX_PATHS[$expected_rel]}"
    if [[ "${indexed%%|*}" != "branch" ]]; then
      fail "branch $name: index.tsv labels $expected_rel as ${indexed%%|*}, not 'branch'"
    fi
  else
    fail "branch $name: $expected_rel not present in index.tsv"
  fi
done < "$BRANCHES_TSV"
[[ "$br_total" -gt 0 ]] && pass "audited $br_total branch row(s) against bundle"

# A2 + A7 + A8 + A10 — per-worktree checks.
wt_total=0
while IFS= read -r row; do
  path=""; untracked_count=""
  tsv_read "$row" path _branch _detached _bare _locked _prunable _last_sha _last_date _dirty _staged_size _unstaged_size _untracked_size untracked_count _age_days _inside_main _active _subm
  [[ "$path" == "path" ]] && continue
  [[ -z "$path" ]] && continue
  wt_total=$((wt_total + 1))

  san=$(sanitize_path "$path")
  wt_dir="$BUNDLE/worktrees/$san"
  if [[ ! -d "$wt_dir" ]]; then
    fail "worktree $path: bundle directory missing ($wt_dir)"
    continue
  fi

  # A7 — staged + unstaged + status always present; per build-bundle.sh the
  # files exist even when empty. Treat "missing file" as a hard failure;
  # "empty file" is fine when the worktree is clean.
  for required in staged.diff unstaged.diff status.txt meta.txt; do
    if [[ ! -e "$wt_dir/$required" ]]; then
      fail "worktree $path: $required missing"
    fi
  done

  # A8 — untracked content iff present.
  if [[ "${untracked_count:-0}" -gt 0 ]]; then
    if [[ ! -s "$wt_dir/.untracked.list" ]]; then
      fail "worktree $path: .untracked.list missing/empty (count=$untracked_count)"
    fi
    if [[ ! -s "$wt_dir/.untracked.sha256" ]]; then
      fail "worktree $path: .untracked.sha256 missing/empty (count=$untracked_count)"
    elif [[ -d "$path" ]]; then
      live_untracked_hash=$(untracked_content_manifest_hash_for_root "$path" <(git -C "$path" ls-files --others --exclude-standard -z | sort -z) 2>/dev/null || echo "MISSING")
      bundle_untracked_hash=$(sha256sum "$wt_dir/.untracked.sha256" 2>/dev/null | awk '{print $1}')
      if [[ "$live_untracked_hash" != "$bundle_untracked_hash" ]]; then
        fail "worktree $path: untracked content drifted since bundle (live=$live_untracked_hash bundle=$bundle_untracked_hash)"
      fi
    fi
    if [[ ! -f "$wt_dir/untracked.tar.gz" ]]; then
      fail "worktree $path: untracked.tar.gz missing (count=$untracked_count)"
    elif [[ -s "$wt_dir/.untracked.list" ]]; then
      if ! tar --null -tzf "$wt_dir/untracked.tar.gz" -T "$wt_dir/.untracked.list" >/dev/null 2>&1; then
        fail "worktree $path: untracked.tar.gz cannot list every manifest entry"
      fi
    fi
  else
    # If untracked_count==0 but the tarball IS present, that's an inconsistency.
    if [[ -f "$wt_dir/untracked.tar.gz" ]]; then
      warn "worktree $path: untracked.tar.gz exists but inventory says count=0"
    fi
  fi

  # A10 — index reference
  expected_rel="worktrees/$san/"
  if [[ -n "${INDEX_PATHS[$expected_rel]:-}" ]]; then
    indexed="${INDEX_PATHS[$expected_rel]}"
    if [[ "${indexed%%|*}" != "worktree" ]]; then
      fail "worktree $path: index.tsv labels $expected_rel as ${indexed%%|*}, not 'worktree'"
    fi
  else
    fail "worktree $path: $expected_rel not present in index.tsv"
  fi
done < "$WORKTREES_TSV"
[[ "$wt_total" -gt 0 ]] && pass "audited $wt_total worktree row(s) against bundle"

# Reverse: every dir under branches/ and worktrees/ should be referenced from
# the inventory. Catches stragglers from earlier runs that were never cleaned.
if [[ -d "$BUNDLE/branches" ]]; then
  while IFS= read -r d; do
    rel="branches/$(basename "$d")/"
    if [[ -z "${INDEX_PATHS[$rel]:-}" ]]; then
      warn "stray bundle dir not in index: $rel"
    fi
  done < <(find "$BUNDLE/branches" -mindepth 1 -maxdepth 1 -type d 2>/dev/null || true)
fi
if [[ -d "$BUNDLE/worktrees" ]]; then
  while IFS= read -r d; do
    rel="worktrees/$(basename "$d")/"
    if [[ -z "${INDEX_PATHS[$rel]:-}" ]]; then
      warn "stray bundle dir not in index: $rel"
    fi
  done < <(find "$BUNDLE/worktrees" -mindepth 1 -maxdepth 1 -type d 2>/dev/null || true)
fi

echo
echo "=== Bundle audit summary ==="
echo "Branches audited:  $br_total"
echo "Worktrees audited: $wt_total"
echo "Findings:          $findings"
echo "Log: $LOG"

if [[ "$findings" -gt 0 ]]; then
  echo
  echo "*** GATE FAILURE ***"
  echo "Internal bundle coherence checks failed. Inspect $LOG."
  echo "Do NOT proceed to destructive phases."
  exit 1
fi
exit 0
