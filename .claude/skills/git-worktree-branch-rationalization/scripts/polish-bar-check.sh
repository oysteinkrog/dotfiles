#!/usr/bin/env bash
# polish-bar-check.sh — verify the run satisfied all 10 Polish Bar dimensions.
#
# Dimensions (per SKILL.md § The Polish Bar):
#   P1  recovery-completeness     every entry has all bundle layers + verify clean
#   P2  verdict-evidence          every triage row has a verdict + evidence
#   P3  no-phantom-keepers        no novel-and-accretive without proof of novelty
#   P4  harmonization-fidelity    every collision file has a harmonization_plan entry
#   P5  per-apply-gates           every applied keeper has gates_status=passed
#   P6  focused-commit-messages   apply-log SHAs have focused recovery messages
#   P7  order-of-cleanup          worktrees first, then branches in verdict order
#   P8  verbatim-authorization    cleanup_authorization.txt contains the phrase
#   P9  idempotent-on-clean-repo  empty-inventory run produces no commits/cleanup
#   P10 resumable                 apply-log has no duplicate (kind,target) commits
#
# Exit code = number of failed dimensions.

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=project-root.sh
. "$SCRIPT_DIR/project-root.sh"

usage() {
  cat <<USAGE
Usage: polish-bar-check.sh <project-path>

Verify all 10 Polish Bar dimensions. Exit code = number of failed dimensions.

Env:
  WORKSPACE   Workspace dir override.

Exit codes:
  0  all dimensions passed
  N  N dimensions failed
USAGE
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  '') usage >&2; exit 64 ;;
esac

PROJECT="$1"
PROJECT_ABS="$(resolve_project_root "$PROJECT")" || exit 2
WORKSPACE_DIR="$(resolve_workspace "$PROJECT_ABS")"
BUNDLE="$(cat "$WORKSPACE_DIR/bundle_path.txt" 2>/dev/null || echo "")"
BRANCHES_TSV="$WORKSPACE_DIR/branches.tsv"
WORKTREES_TSV="$WORKSPACE_DIR/worktrees.tsv"
TRIAGE="$WORKSPACE_DIR/triage.tsv"
APPLY_LOG="$WORKSPACE_DIR/apply_log.tsv"
CLEANUP_LOG="$WORKSPACE_DIR/cleanup_log.tsv"
VERIFY_LOG="$WORKSPACE_DIR/bundle_verification.log"
PLAN="$WORKSPACE_DIR/harmonization_plan.md"
AUTH="$WORKSPACE_DIR/cleanup_authorization.txt"

# Two acceptable authorization-phrase shapes (kept in sync with drop-retire-confirmed.sh).
AUTH_RE_COUNT='^[[:space:]]*yes[[:space:]]+i[[:space:]]+understand[[:space:]]+and[[:space:]]+want[[:space:]]+to[[:space:]]+remove[[:space:]]+[0-9]+[[:space:]]+worktrees?[[:space:]]+and[[:space:]]+delete[[:space:]]+[0-9]+[[:space:]]+branch(es)?[[:space:]]+per[[:space:]]+the[[:space:]]+plan[[:space:]]+above[[:space:]]*$'
AUTH_RE_SHORT='^[[:space:]]*yes[[:space:]]+i[[:space:]]+understand[[:space:]]+and[[:space:]]+want[[:space:]]+to[[:space:]]+rationalize[[:space:]]+per[[:space:]]+the[[:space:]]+plan[[:space:]]+above[[:space:]]*$'

FAILS=0
pass() { printf '  \033[32mPASS\033[0m  %s\n' "$1"; }
fail() { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; FAILS=$((FAILS + 1)); }
warn() { printf '  \033[33mWARN\033[0m  %s\n' "$1"; }
join_items() {
  local IFS=,
  printf '%s' "$*"
}

echo "Polish Bar checks for $PROJECT_ABS"
echo

# ---- P1: Recovery completeness ----
echo "P1: Recovery completeness"
if [[ -f "$BRANCHES_TSV" && -f "$WORKTREES_TSV" ]]; then
  N_BR=$(awk 'NR > 1' "$BRANCHES_TSV" | wc -l)
  N_WT=$(awk 'NR > 1' "$WORKTREES_TSV" | wc -l)
  N_REFS=$(git -C "$PROJECT_ABS" for-each-ref refs/branch-rationalization-backup/ 2>/dev/null | wc -l)
  N_BUNDLE_BR=0; N_BUNDLE_WT=0
  if [[ -n "$BUNDLE" && -d "$BUNDLE" ]]; then
    N_BUNDLE_BR=$({ find "$BUNDLE/branches"  -mindepth 1 -maxdepth 1 -type d 2>/dev/null || true; } | wc -l)
    N_BUNDLE_WT=$({ find "$BUNDLE/worktrees" -mindepth 1 -maxdepth 1 -type d 2>/dev/null || true; } | wc -l)
  fi
  # Branches: backup refs >= inventory; per-branch dir exists.
  if [[ "$N_REFS" -ge "$N_BR" && "$N_BUNDLE_BR" -ge "$N_BR" ]]; then
    pass "branches: $N_BR inventory, $N_REFS backup refs, $N_BUNDLE_BR bundle dirs"
  else
    fail "branches: inventory=$N_BR refs=$N_REFS bundle_dirs=$N_BUNDLE_BR (counts mismatch)"
  fi
  if [[ "$N_BUNDLE_WT" -ge "$N_WT" ]]; then
    pass "worktrees: $N_WT inventory, $N_BUNDLE_WT bundle dirs"
  else
    fail "worktrees: inventory=$N_WT bundle_dirs=$N_BUNDLE_WT"
  fi
  if [[ -f "$VERIFY_LOG" ]] && grep -qE '^MISMATCH|^MISSING' "$VERIFY_LOG"; then
    fail "bundle_verification.log has mismatches"
  else
    pass "bundle verification clean (or log absent on empty-run)"
  fi
else
  fail "branches.tsv or worktrees.tsv missing"
fi

# ---- P2: Verdict evidence ----
echo
echo "P2: Verdict evidence"
if [[ -f "$TRIAGE" ]]; then
  EMPTY=$(awk -F'\t' 'NR > 1 && ($3 == "" || $3 == "unknown")' "$TRIAGE" | wc -l)
  if [[ "$EMPTY" -eq 0 ]]; then
    pass "every triage row has a verdict (no empty/unknown)"
  else
    fail "$EMPTY rows have empty/unknown verdict"
  fi
  NO_EV=$(awk -F'\t' 'NR > 1 && ($6 == "" || $6 == "-")' "$TRIAGE" | wc -l)
  if [[ "$NO_EV" -eq 0 ]]; then
    pass "every triage row has evidence text"
  else
    warn "$NO_EV rows have empty evidence column"
  fi
else
  fail "triage.tsv missing"
fi

# ---- P3: No phantom keepers ----
echo
echo "P3: No phantom keepers"
if [[ -f "$TRIAGE" && -f "$BRANCHES_TSV" ]]; then
  PHANTOM=$(awk -F'\t' '
    FNR == NR {
      if (FNR > 1 && $1 != "") cherry_plus[$1] = $10 + 0
      next
    }
    FNR > 1 && $1 == "branch" && $3 == "novel-and-accretive" {
      has_absence_proof = ($6 ~ /grep-empty|no symbols( found)?|0\/[0-9]+[[:space:]]+fingerprint|0[[:space:]]+matches/)
      if (!has_absence_proof || !($2 in cherry_plus) || cherry_plus[$2] < 1) bad++
    }
    END {print bad+0}
  ' "$BRANCHES_TSV" "$TRIAGE")
  if [[ "$PHANTOM" -eq 0 ]]; then
    pass "every novel-and-accretive branch cites absence proof and cherry_plus>=1"
  else
    fail "$PHANTOM novel-and-accretive branch row(s) lack absence proof or cherry_plus>=1"
  fi
elif [[ -f "$TRIAGE" ]]; then
  fail "branches.tsv missing; cannot verify novel-and-accretive cherry_plus evidence"
fi

# ---- P4: Harmonization fidelity ----
echo
echo "P4: Harmonization fidelity"
if [[ -f "$TRIAGE" ]]; then
  # Files touched by ≥2 harmonization-eligible verdicts must each appear in plan.
  mapfile -t expected_harmonization_files < <(awk -F'\t' '
    NR > 1 && $3 ~ /^(novel-and-accretive|partially-novel|divergent-refactor|dirty-worktree-only)$/ && $7 != "" && $7 != "-" {
      n=split($7, touched_files, ",")
      for (i=1;i<=n;i++) {
        if (touched_files[i] != "") {
          fbr[touched_files[i] SUBSEP $1 ":" $2]=1
          seen[touched_files[i]]=1
        }
      }
    }
    END {
      for (f in seen) {
        d=0
        for (k in fbr) {
          split(k, parts, SUBSEP)
          if (parts[1] == f) d++
        }
        if (d >= 2) print f
      }
    }' "$TRIAGE" | sort)
  expected=${#expected_harmonization_files[@]}
  if [[ ! -f "$PLAN" ]]; then
    if [[ "$expected" -eq 0 ]]; then
      pass "no harmonization required and plan absent (consistent)"
    else
      fail "$expected file(s) need harmonization but harmonization_plan.md is missing"
    fi
  else
    pass "harmonization_plan.md exists"
    declare -A plan_has=()
    while IFS= read -r plan_file; do
      [[ -z "$plan_file" ]] && continue
      plan_has["$plan_file"]=1
    done < <(awk '/^### `/{line=$0; sub(/^### `/, "", line); sub(/`[[:space:]]*$/, "", line); print line}' "$PLAN" 2>/dev/null)

    missing_harmonization_files=()
    for expected_file in "${expected_harmonization_files[@]}"; do
      [[ -n "${plan_has[$expected_file]:-}" ]] || missing_harmonization_files+=("$expected_file")
    done
    if [[ "${#missing_harmonization_files[@]}" -gt 0 ]]; then
      fail "${#missing_harmonization_files[@]}/$expected required harmonization file(s) missing from plan: $(join_items "${missing_harmonization_files[@]:0:5}")"
    elif [[ "$expected" -eq 0 ]]; then
      pass "harmonization plan reports no required syntheses (acceptable)"
    else
      pass "$expected required file(s) covered by the harmonization plan"
    fi
  fi
fi

# ---- P5: Per-apply gates ----
echo
echo "P5: Per-apply gates"
if [[ -f "$APPLY_LOG" ]]; then
  BAD=$(awk -F'\t' 'NR > 1 && $4 != "" && $6 != "passed" && $6 !~ /^skipped/' "$APPLY_LOG" | wc -l)
  if [[ "$BAD" -eq 0 ]]; then
    pass "every applied keeper passed gates"
  else
    fail "$BAD apply-log rows have non-passing gates_status"
  fi
else
  pass "no apply log (no Phase 8 commits to validate)"
fi

# ---- P6: Focused commit messages ----
echo
echo "P6: Focused commit messages"
SUBJECT_RE='^(harmonize|recover|restore|reapply)\b'
if [[ -f "$APPLY_LOG" ]]; then
  bad=0; total=0
  while IFS=$'\t' read -r kind target strategy sha files gates duration drift; do
    [[ "$kind" == "kind" ]] && continue
    [[ -z "$sha" ]] && continue
    total=$((total + 1))
    msg=$(git -C "$PROJECT_ABS" log -1 --format='%s%n%b' "$sha" 2>/dev/null || echo "")
    subj=$(printf '%s\n' "$msg" | sed -n '1p')
    if ! printf '%s' "$subj" | grep -qiE "$SUBJECT_RE"; then bad=$((bad + 1)); continue; fi
    if ! printf '%s' "$msg" | grep -qE "$target|branch-rationalization"; then bad=$((bad + 1)); fi
    : "$strategy" "$files" "$gates" "$duration" "$drift"
  done < "$APPLY_LOG"
  if [[ "$bad" -eq 0 ]]; then
    pass "$total applied commit message(s) cite source + use recovery/harmonize verb"
  else
    fail "$bad/$total commit messages fail the focused-message contract"
  fi
else
  pass "no apply log (nothing to validate)"
fi

# ---- P7: Order of cleanup ----
echo
echo "P7: Order of cleanup"
if [[ -f "$CLEANUP_LOG" ]]; then
  if awk -F'\t' '
    BEGIN {
      verdict_order["garbage"]            = 1
      verdict_order["superseded"]         = 2
      verdict_order["already-merged"]     = 3
      verdict_order["novel-but-stale"]    = 4
      verdict_order["divergent-refactor"] = 5
      verdict_order["novel-and-accretive"]= 6
      verdict_order["partially-novel"]    = 6
      verdict_order["dirty-worktree-only"]= 6
      bad = 0
      last_kv = 0
    }
    NR > 1 {
      phase = $1
      kind = $2
      verdict = $4
      if (phase !~ /^[A-G]$/) { print "ORDER VIOLATION: bad phase " phase; bad++; next }
      k = (kind == "worktree") ? 1 : ((kind == "branch") ? 2 : 0)
      if (!k) { print "ORDER VIOLATION: unknown kind " kind; bad++; next }
      if (k < last_kv) { print "ORDER VIOLATION (kind): row " NR " " kind; bad++ }
      last_kv = k
      if (kind == "worktree" && phase != "A") {
        print "ORDER VIOLATION: worktree row " NR " not in Phase A"; bad++
      }
      # within branches, verdict ordering
      if (kind == "branch") {
        if (phase == "A") { print "ORDER VIOLATION: branch row " NR " in Phase A"; bad++ }
        v = verdict_order[verdict]
        if (!v) { print "BUCKET VIOLATION: row " NR " verdict " verdict; bad++; next }
        if (NR > 1) {
          if (last_v_branch && v < last_v_branch) {
            print "ORDER VIOLATION (verdict): row " NR " " verdict
            bad++
          }
          last_v_branch = v
        } else {
          last_v_branch = v
        }
      }
    }
    END { exit (bad ? 1 : 0) }
  ' "$CLEANUP_LOG"; then
    pass "cleanup-log order: worktrees-first, then branches in verdict order"
  else
    fail "order violation in cleanup_log.tsv (see above)"
  fi
else
  pass "cleanup_log absent (no Phase 10 ops to validate ordering)"
fi

# ---- P8: Verbatim authorization ----
echo
echo "P8: Verbatim authorization"
if [[ -f "$CLEANUP_LOG" ]] && [[ "$(awk 'NR > 1' "$CLEANUP_LOG" | wc -l)" -gt 0 ]]; then
  if [[ -s "$AUTH" ]] && { grep -Eiq "$AUTH_RE_COUNT" "$AUTH" || grep -Eiq "$AUTH_RE_SHORT" "$AUTH"; }; then
    pass "cleanup_authorization.txt contains the verbatim phrase"
  else
    fail "cleanup happened but authorization file missing or vague"
  fi
  if awk -F'\t' 'NR > 1 && $5 == "" {bad=1} END {exit bad}' "$CLEANUP_LOG"; then
    pass "cleanup_log.tsv records the verbatim command for every operation"
  else
    fail "cleanup_log.tsv has cleanup rows without command_run"
  fi
else
  pass "no cleanup occurred (authorization not required)"
fi

# ---- P9: Idempotent on a clean repo ----
echo
echo "P9: Idempotent on a clean repo"
if [[ -f "$BRANCHES_TSV" && -f "$WORKTREES_TSV" ]]; then
  N_BR=$(awk 'NR > 1' "$BRANCHES_TSV" | wc -l)
  N_WT=$(awk 'NR > 1' "$WORKTREES_TSV" | wc -l)
  if [[ "$N_BR" -eq 0 && "$N_WT" -eq 0 ]]; then
    BAD=0
    [[ -f "$APPLY_LOG"   ]] && [[ "$(awk 'NR > 1 && $4 != ""' "$APPLY_LOG" | wc -l)" -gt 0 ]] && BAD=1
    [[ -f "$CLEANUP_LOG" ]] && [[ "$(awk 'NR > 1' "$CLEANUP_LOG" | wc -l)" -gt 0 ]] && BAD=1
    if [[ "$BAD" -eq 0 ]]; then
      pass "empty-inventory run produced no apply or cleanup rows"
    else
      fail "empty-inventory run has apply/cleanup rows"
    fi
  else
    pass "non-empty inventory (idempotence smoke not applicable this run)"
  fi
fi

# ---- P10: Resumable ----
echo
echo "P10: Resumable"
if [[ -f "$APPLY_LOG" ]]; then
  DUP=$(awk -F'\t' 'NR > 1 && $4 != "" {seen[$1 "/" $2]++} END {dup=0; for (k in seen) if (seen[k] > 1) dup++; print dup}' "$APPLY_LOG")
  if [[ "$DUP" -eq 0 ]]; then
    pass "apply-log has no duplicate (kind,target) commits"
  else
    fail "$DUP (kind,target) pair(s) applied more than once"
  fi
else
  pass "apply-log absent (no Phase 8 commits to resume)"
fi

# ---- Roll up ----
echo
echo "Total fails: $FAILS"
exit "$FAILS"
