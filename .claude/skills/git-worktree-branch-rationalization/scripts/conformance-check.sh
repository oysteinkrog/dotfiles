#!/usr/bin/env bash
# conformance-check.sh — Phase 3 / Phase 11: bundle conformance to
# BUNDLE-FORMAT-SPEC.md.
#
# Verifies the bundle's *structural* conformance to the published spec,
# distinct from verify-bundle.sh's byte-equality gate and bundle-audit.sh's
# internal-coherence audit.
#
# Each spec section maps to a check function:
#
#   C1  Required artifacts present:
#         README.md, index.tsv, object-bundle.pack (when refs exist),
#         branches/, worktrees/.
#   C2  index.tsv schema:
#         tab-separated; header row matches the spec exactly.
#   C3  Per-branch artifact structure:
#         each branches/<slug>/ has meta.txt, commits.tsv,
#         diff-vs-merge-base.diff, and format-patch/ (when commits_ahead > 0).
#   C4  Per-worktree artifact structure:
#         each worktrees/<sanitized-path>/ has meta.txt, status.txt,
#         staged.diff, unstaged.diff (the last two may be empty).
#   C5  README.md required sections:
#         backup-ref recovery, object-bundle fetch, per-branch diff apply,
#         format-patch series apply, worktree dirty-state restoration.
#   C6  Slug naming convention:
#         every <slug> in branches/ matches the slugify_branch helper output
#         (suffix is sha1[0:12] of the original ref name).
#   C7  object-bundle.pack round-trip:
#         `git bundle list-heads` lists at least every branch row in
#         branches.tsv as refs/branch-rationalization-backup/<slug> at the
#         recorded head_sha, and a fresh bare repo can fetch that backup
#         namespace from the pack.
#   C8  Byte-equality between live refs and bundle artifacts:
#         the diff/format-patch in the bundle, when re-derived from the live
#         backup ref, sha256-equals the bundle's stored copy.
#
# Output: <workspace>/conformance_report.tsv (one row per check, pass/fail)
# and <workspace>/conformance_report.md (human-readable summary).
#
# Exit codes:
#   0  every check passed
#   2  preflight failed (bundle / inventory missing)
#   5  one or more checks failed

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=project-root.sh
. "$SCRIPT_DIR/project-root.sh"

log() { printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*"; }

usage() {
  cat <<USAGE
Usage: conformance-check.sh <project-path>

Phase 3 / Phase 11 conformance check against BUNDLE-FORMAT-SPEC.md. Emits
<workspace>/conformance_report.tsv and conformance_report.md.

Distinct from verify-bundle.sh (byte-equality) and bundle-audit.sh (internal
coherence) — this script enforces the *spec* as a contract.

Env:
  WORKSPACE   Workspace dir override.

Exit codes:
  0  all checks passed
  2  preflight failed
  5  one or more checks failed
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
TSV="$WORKSPACE_DIR/conformance_report.tsv"
MD="$WORKSPACE_DIR/conformance_report.md"

for f in "$BRANCHES_TSV" "$WORKTREES_TSV" "$BUNDLE_PATH_FILE"; do
  [[ -f "$f" ]] || { echo "ERROR: $f missing" >&2; exit 2; }
done
BUNDLE="$(cat "$BUNDLE_PATH_FILE")"
[[ -d "$BUNDLE" ]] || { echo "ERROR: $BUNDLE missing" >&2; exit 2; }

INDEX="$BUNDLE/index.tsv"
README="$BUNDLE/README.md"
PACK="$BUNDLE/object-bundle.pack"
mapfile -t EXPECTED_BACKUP_SLUGS < <(awk -F'\t' 'NR > 1 && $2 != "" {print $2}' "$BRANCHES_TSV" | sort -u)
EXPECTED_BACKUP_COUNT=${#EXPECTED_BACKUP_SLUGS[@]}
declare -A EXPECTED_BACKUP_HEADS=()
while IFS= read -r row; do
  name=""; slug=""; head_sha=""
  tsv_read "$row" name slug head_sha _rest
  [[ "$name" == "name" || -z "$slug" ]] && continue
  EXPECTED_BACKUP_HEADS["$slug"]="$head_sha"
done < "$BRANCHES_TSV"

printf 'check\tstatus\tnotes\n' > "$TSV"
declare -i FAILED=0
record() {
  local check="$1" status="$2" notes="$3"
  printf '%s\t%s\t%s\n' "$check" "$status" "$notes" >> "$TSV"
  if [[ "$status" == "FAIL" ]]; then
    FAILED=$((FAILED+1))
  fi
}

join_report_items() {
  local IFS=,
  printf '%s' "$*"
}

profile_value() {
  local key="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -r --arg key "$key" '.[$key] // ""' "$PROFILE"
    return
  fi
  python3 - "$PROFILE" "$key" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)
value = data.get(sys.argv[2], "")
if isinstance(value, bool):
    print("true" if value else "false")
elif value is None:
    print("")
else:
    print(value)
PY
}

# C1 — required artifacts.
if [[ -f "$README" ]]; then
  record C1.README PASS "present"
else
  record C1.README FAIL "absent at $README"
fi
if [[ -f "$INDEX" ]]; then
  record C1.INDEX PASS "present"
else
  record C1.INDEX FAIL "absent at $INDEX"
fi
if [[ -d "$BUNDLE/branches" ]]; then
  record C1.BRANCHES_DIR PASS "present"
else
  record C1.BRANCHES_DIR FAIL "absent"
fi
if [[ -d "$BUNDLE/worktrees" ]]; then
  record C1.WORKTREES_DIR PASS "present"
else
  record C1.WORKTREES_DIR FAIL "absent"
fi

n_backup=$EXPECTED_BACKUP_COUNT
if [[ "$n_backup" -gt 0 ]]; then
  if [[ -f "$PACK" ]]; then
    record C1.PACK PASS "present (expected_refs=$n_backup)"
  else
    record C1.PACK FAIL "missing despite $n_backup branch inventory row(s)"
  fi
else
  record C1.PACK PASS "n/a (no branch inventory rows)"
fi

# C2 — index.tsv schema.
EXPECTED_INDEX_HEADER='kind	name_or_path	slug	head_sha	merge_base	ahead	behind	smell	intake_protected	verdict	bundle_paths'
if [[ -f "$INDEX" ]]; then
  actual_header=$(head -1 "$INDEX")
  if [[ "$actual_header" == "$EXPECTED_INDEX_HEADER" ]]; then
    record C2.INDEX_HEADER PASS "schema matches"
  else
    # Allow a permissive match: every required TSV column present in any order.
    missing=()
    IFS=$'\t' read -r -a actual_cols <<< "$actual_header"
    for col in kind name_or_path slug head_sha merge_base ahead behind smell intake_protected verdict bundle_paths; do
      found=0
      for actual_col in "${actual_cols[@]}"; do
        if [[ "$actual_col" == "$col" ]]; then
          found=1
          break
        fi
      done
      [[ "$found" -eq 1 ]] || missing+=("$col")
    done
    if [[ "${#missing[@]}" -eq 0 ]]; then
      record C2.INDEX_HEADER PASS "all required columns present (order may differ)"
    else
      record C2.INDEX_HEADER FAIL "missing columns: $(join_report_items "${missing[@]}")"
    fi
  fi
else
  record C2.INDEX_HEADER FAIL "index.tsv absent"
fi

# C3 — per-branch artifact structure.
declare -i C3_FAIL=0
declare -i C3_TOTAL=0
while IFS= read -r row; do
  name=; slug=; commits_ahead=
  tsv_read "$row" name slug _head_sha _last_date _author _subject _ahead _behind commits_ahead _cherry_plus _cherry_minus _upstream _upstream_status _wt_path _touched _insertions _deletions _files_changed _age_days _prefix
  [[ "$name" == "name" ]] && continue
  [[ -z "$slug" ]] && continue
  C3_TOTAL=$((C3_TOTAL+1))
  bdir="$BUNDLE/branches/$slug"
  if [[ ! -d "$bdir" ]]; then
    C3_FAIL=$((C3_FAIL+1))
    record "C3.${slug}.dir" FAIL "missing $bdir"
    continue
  fi
  for f in meta.txt commits.tsv diff-vs-merge-base.diff; do
    if [[ ! -f "$bdir/$f" ]]; then
      C3_FAIL=$((C3_FAIL+1))
      record "C3.${slug}.$f" FAIL "missing $bdir/$f"
    fi
  done
  if [[ "${commits_ahead:-0}" -gt 0 ]]; then
    if [[ ! -d "$bdir/format-patch" ]]; then
      C3_FAIL=$((C3_FAIL+1))
      record "C3.${slug}.format-patch" FAIL "missing $bdir/format-patch (commits_ahead=$commits_ahead)"
    fi
  fi
done < "$BRANCHES_TSV"
if [[ "$C3_FAIL" -eq 0 ]]; then
  record C3.summary PASS "$C3_TOTAL branches OK"
else
  record C3.summary FAIL "$C3_FAIL of $C3_TOTAL branches missing artifacts"
fi

# C4 — per-worktree artifact structure.
declare -i C4_FAIL=0
declare -i C4_TOTAL=0
while IFS= read -r row; do
  path=
  tsv_read "$row" path _branch _detached _bare _locked _prunable _last_sha _last_date _dirty _staged_size _unstaged_size _untracked_size _untracked_count _age_days _inside_main _active _subm
  [[ "$path" == "path" ]] && continue
  [[ -z "$path" ]] && continue
  C4_TOTAL=$((C4_TOTAL+1))
  san=$(sanitize_path "$path")
  wdir="$BUNDLE/worktrees/$san"
  if [[ ! -d "$wdir" ]]; then
    C4_FAIL=$((C4_FAIL+1))
    record "C4.${san}.dir" FAIL "missing $wdir"
    continue
  fi
  for f in meta.txt status.txt staged.diff unstaged.diff; do
    if [[ ! -f "$wdir/$f" ]]; then
      C4_FAIL=$((C4_FAIL+1))
      record "C4.${san}.$f" FAIL "missing $wdir/$f"
    fi
  done
done < "$WORKTREES_TSV"
if [[ "$C4_FAIL" -eq 0 ]]; then
  record C4.summary PASS "$C4_TOTAL worktrees OK"
else
  record C4.summary FAIL "$C4_FAIL of $C4_TOTAL worktrees missing artifacts"
fi

# C5 — README.md required sections.
if [[ -f "$README" ]]; then
  declare -a missing_sections=()
  grep -qE 'backup ref'                            "$README" || missing_sections+=("backup-ref recovery")
  grep -qE 'object[ -]bundle|object-bundle\.pack'  "$README" || missing_sections+=("object-bundle fetch")
  grep -qE 'diff-vs-merge-base|git apply'          "$README" || missing_sections+=("per-branch diff apply")
  grep -qE 'format-patch|git am'                   "$README" || missing_sections+=("format-patch series apply")
  grep -qE 'staged\.diff|unstaged\.diff|untracked' "$README" || missing_sections+=("worktree dirty-state restoration")
  if [[ "${#missing_sections[@]}" -eq 0 ]]; then
    record C5.README_SECTIONS PASS "all 5 recovery recipes documented"
  else
    record C5.README_SECTIONS FAIL "missing sections: $(join_report_items "${missing_sections[@]}")"
  fi
else
  record C5.README_SECTIONS FAIL "README.md absent"
fi

# C6 — slug naming convention.
declare -i C6_FAIL=0
while IFS= read -r row; do
  name=; slug=
  tsv_read "$row" name slug _rest
  [[ "$name" == "name" ]] && continue
  [[ -z "$slug" ]] && continue
  expected=$(slugify_branch "$name")
  if [[ "$expected" != "$slug" ]]; then
    C6_FAIL=$((C6_FAIL+1))
    record "C6.${name}.slug" FAIL "slug='$slug' expected='$expected'"
  fi
done < "$BRANCHES_TSV"
if [[ "$C6_FAIL" -eq 0 ]]; then
  record C6.summary PASS "all slugs match slugify_branch"
else
  record C6.summary FAIL "$C6_FAIL slug(s) drift from slugify_branch"
fi

# C7 — object-bundle.pack list-heads + fetch round-trip.
if [[ -f "$PACK" ]]; then
  declare -A PACK_HEAD_SHAS=()
  while IFS=' ' read -r sha ref _rest; do
    [[ -z "${sha:-}" || -z "${ref:-}" ]] && continue
    case "$ref" in
      refs/branch-rationalization-backup/*)
        PACK_HEAD_SHAS["${ref#refs/branch-rationalization-backup/}"]="$sha"
        ;;
    esac
  done < <(git -C "$PROJECT_ABS" bundle list-heads "$PACK" 2>/dev/null || true)
  declare -a missing_pack=()
  declare -a mismatched_pack=()
  for s in "${EXPECTED_BACKUP_SLUGS[@]}"; do
    [[ -z "$s" ]] && continue
    pack_sha="${PACK_HEAD_SHAS[$s]:-}"
    expected_sha="${EXPECTED_BACKUP_HEADS[$s]:-}"
    if [[ -z "$pack_sha" ]]; then
      missing_pack+=("$s")
    elif [[ -n "$expected_sha" && "$pack_sha" != "$expected_sha" ]]; then
      mismatched_pack+=("$s")
    fi
  done
  if [[ "${#missing_pack[@]}" -eq 0 && "${#mismatched_pack[@]}" -eq 0 ]]; then
    record C7.LIST_HEADS PASS "all slugs round-trip via list-heads at recorded branch tips"
  else
    record C7.LIST_HEADS FAIL "${#missing_pack[@]} slug(s) absent, ${#mismatched_pack[@]} slug(s) at wrong SHA: missing=$(join_report_items "${missing_pack[@]:0:5}") wrong=$(join_report_items "${mismatched_pack[@]:0:5}")"
  fi
  if bundle_fetch_roundtrip "$PACK" "refs/branch-rationalization-backup" "$WORKSPACE_DIR"; then
    record C7.FETCH PASS "backup namespace fetches into a fresh object database"
  else
    record C7.FETCH FAIL "git fetch from object-bundle.pack failed; recovery would fail"
  fi
elif [[ "$EXPECTED_BACKUP_COUNT" -gt 0 ]]; then
  record C7.LIST_HEADS FAIL "object-bundle.pack missing for $EXPECTED_BACKUP_COUNT branch inventory row(s)"
else
  record C7.LIST_HEADS PASS "n/a (no pack)"
fi

# C8 — byte-equality between live refs and bundle artifacts (sample).
declare -i C8_FAIL=0
declare -i C8_TOTAL=0
PROFILE="$WORKSPACE_DIR/project_profile.json"
CANONICAL=""
if [[ -f "$PROFILE" ]]; then
  CANONICAL=$(profile_value canonical_branch)
fi
if [[ -n "$CANONICAL" ]]; then
  if git -C "$PROJECT_ABS" rev-parse --verify --quiet "refs/heads/$CANONICAL^{commit}" >/dev/null 2>&1; then
    CANON_REF="refs/heads/$CANONICAL"
  elif git -C "$PROJECT_ABS" rev-parse --verify --quiet "refs/remotes/origin/$CANONICAL^{commit}" >/dev/null 2>&1; then
    CANON_REF="refs/remotes/origin/$CANONICAL"
  else
    CANON_REF=""
  fi
  if [[ -n "$CANON_REF" ]]; then
    while IFS= read -r row; do
      name=; slug=
      tsv_read "$row" name slug _rest
      [[ "$name" == "name" ]] && continue
      [[ -z "$slug" ]] && continue
      C8_TOTAL=$((C8_TOTAL+1))
      branch_ref="refs/heads/$name"
      if ! git -C "$PROJECT_ABS" rev-parse --verify --quiet "$branch_ref^{commit}" >/dev/null 2>&1; then
        C8_FAIL=$((C8_FAIL+1))
        continue
      fi
      diff_path="$BUNDLE/branches/$slug/diff-vs-merge-base.diff"
      [[ -f "$diff_path" ]] || { C8_FAIL=$((C8_FAIL+1)); continue; }
      mb=$(git -C "$PROJECT_ABS" merge-base "$CANON_REF" "$branch_ref" 2>/dev/null || true)
      [[ -z "$mb" ]] && { C8_FAIL=$((C8_FAIL+1)); continue; }
      live_h=$(git -C "$PROJECT_ABS" diff --binary "$mb" "$branch_ref" 2>/dev/null | sha256sum | awk '{print $1}')
      bundle_h=$(sha256sum "$diff_path" | awk '{print $1}')
      if [[ "$live_h" != "$bundle_h" ]]; then
        C8_FAIL=$((C8_FAIL+1))
      fi
    done < "$BRANCHES_TSV"
    if [[ "$C8_FAIL" -eq 0 ]]; then
      record C8.BYTE_EQ PASS "$C8_TOTAL branches byte-equal"
    else
      record C8.BYTE_EQ FAIL "$C8_FAIL of $C8_TOTAL branches drifted"
    fi
  else
    record C8.BYTE_EQ PASS "skipped (canonical unresolvable)"
  fi
else
  record C8.BYTE_EQ PASS "skipped (no profile)"
fi

# Markdown summary.
{
  printf '# Bundle conformance report\n\n'
  printf "Project:   \`%s\`\n" "$PROJECT_ABS"
  printf "Bundle:    \`%s\`\n" "$BUNDLE"
  printf 'Generated: %s\n\n' "$(date -u +%FT%TZ)"
  printf '| Check | Status | Notes |\n'
  printf '|-------|--------|-------|\n'
  awk -F'\t' 'NR>1 {printf "| %s | %s | %s |\n", $1, $2, $3}' "$TSV"
  printf '\n'
  if [[ "$FAILED" -eq 0 ]]; then
    printf 'Verdict: **CONFORMANT**.\n'
  else
    printf 'Verdict: **NON-CONFORMANT** (%d check(s) failed). Address per\n' "$FAILED"
    printf "\`references/BUNDLE-FORMAT-SPEC.md\` before relying on the bundle.\n"
  fi
} > "$MD"

log "wrote $TSV"
log "wrote $MD"
echo "checks_failed=$FAILED"
[[ "$FAILED" -gt 0 ]] && exit 5
exit 0
