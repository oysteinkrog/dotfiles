#!/usr/bin/env bash
# polish-bar-check.sh — Verify run satisfied all 10 Polish Bar dimensions.
#
# Reads workspace artifacts; reports per-dimension pass/fail. Exit 0 if all
# dimensions pass; exit 1 if any fail.

set -euo pipefail

PROJECT="${1:?Usage: polish-bar-check.sh <project-path>}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=project-root.sh
. "$SCRIPT_DIR/project-root.sh"

PROJECT_ABS="$(resolve_project_root "$PROJECT")"
WORKSPACE="$PROJECT_ABS/.stash_janitor_workspace"
BUNDLE="$(cat "$WORKSPACE/bundle_path.txt" 2>/dev/null || echo "")"
INVENTORY="$WORKSPACE/inventory.tsv"
TRIAGE="$WORKSPACE/triage.tsv"
APPLY_LOG="$WORKSPACE/apply_log.tsv"
PARTIAL_LOG="$WORKSPACE/partial_split_log.tsv"
CLEANUP_LOG="$WORKSPACE/cleanup_log.tsv"
VERIFY_LOG="$WORKSPACE/bundle_verification.log"
AUTHORIZATION_RE='^[[:space:]]*yes[[:space:]]+i[[:space:]]+understand[[:space:]]+and[[:space:]]+want[[:space:]]+to[[:space:]]+drop[[:space:]]+all[[:space:]]+[0-9]+[[:space:]]+stash(es)?[[:space:]]+per[[:space:]]+the[[:space:]]+plan[[:space:]]+above[[:space:]]*$'

FAILS=0
pass() { printf '  \033[32mPASS\033[0m  %s\n' "$1"; }
fail() { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; FAILS=$((FAILS + 1)); }
warn() { printf '  \033[33mWARN\033[0m  %s\n' "$1"; }

write_git_tree_manifest() {
  local treeish="$1"
  local out="$2"
  git -C "$PROJECT_ABS" ls-tree -r -z "$treeish" \
    | while IFS=$'\t' read -r -d '' meta path; do
        mode=${meta%% *}
        rest=${meta#* }
        type=${rest%% *}
        object=${rest##* }
        printf '%s\t%s\t%s\t%s\n' "$mode" "$type" "$object" "$path"
      done \
    | sort > "$out"
}

write_materialized_tree_manifest() {
  local root="$1"
  local out="$2"
  (
    cd "$root"
    find . \( -type f -o -type l \) -print0 \
      | while IFS= read -r -d '' path; do
          rel=${path#./}
          if [[ -L "$path" ]]; then
            mode=120000
            target=$(readlink "$path")
            object=$(printf '%s' "$target" | git -C "$PROJECT_ABS" hash-object --stdin)
          else
            if [[ -x "$path" ]]; then mode=100755; else mode=100644; fi
            object=$(git -C "$PROJECT_ABS" hash-object -- "$root/$rel")
          fi
          printf '%s\tblob\t%s\t%s\n' "$mode" "$object" "$rel"
        done
  ) | sort > "$out"
}

echo "Polish Bar checks for $PROJECT_ABS"
echo

echo "P1: Recovery completeness"
if [[ -f "$INVENTORY" && -f "$VERIFY_LOG" ]]; then
	  # The bundle directory may legitimately be gone (user moved it after run
	  # completion) while the workspace is intact. `ls`/`find`/`awk` all exit
	  # non-zero on a missing directory or file; under `set -euo pipefail`
	  # `var=$(failing | wc -l)` aborts the script. Wrap each with `|| true`
	  # inside braces so the wc input is empty + count is 0 instead of abort.
	  N_INV=$(awk 'NR > 1' "$INVENTORY" | wc -l)
	  N_REF=$({ git -C "$PROJECT_ABS" for-each-ref refs/stash-backup/ 2>/dev/null || true ; } | wc -l)
	  if [[ -n "$BUNDLE" ]]; then
	    # Match ONLY the canonical <NNN>.diff pattern (at least 3 digits + .diff). The
	    # naive `*.diff` glob also matches Phase 7's <NNN>.split.diff outputs,
	    # which would inflate the count and produce a spurious "counts mismatch"
	    # FAIL on any run where partial-split.sh actually ran. Same fix applied
	    # to bundle-audit.sh — discovered during the integration-test run.
	    N_DIFFS=$({ find "$BUNDLE/diffs" -maxdepth 1 -type f -regextype posix-extended -regex '.*/[0-9]{3,}\.diff' 2>/dev/null || true ; } | wc -l)
	    N_META=$({ find "$BUNDLE/meta"  -maxdepth 1 -type f -name '*.txt'  2>/dev/null || true ; } | wc -l)
	    N_INDEX=$({ awk 'NR > 1' "$BUNDLE/index.tsv" 2>/dev/null || true ; } | wc -l)
	  else
	    N_DIFFS=0
	    N_META=0
	    N_INDEX=0
	  fi
	  if [[ "$N_INV" -eq "$N_REF" && "$N_INV" -eq "$N_DIFFS" && "$N_INV" -eq "$N_META" && "$N_INV" -eq "$N_INDEX" ]]; then
	    pass "every stash has backup ref + diff + meta + index row (n=$N_INV)"
	  else
	    fail "counts mismatch: inv=$N_INV refs=$N_REF diffs=$N_DIFFS meta=$N_META index=$N_INDEX"
	  fi
	  if grep -qE '^MISMATCH|^MISSING' "$VERIFY_LOG"; then
	    fail "verification log has mismatches"
	  else
	    pass "byte-equality verified"
	  fi
		  UNTRACKED_BAD=0
		  UNTRACKED_TOTAL=0
		  while IFS=$'\t' read -r n _ref _sha _parent_sha _date _author _message _files _ins _dels has_untracked; do
		    [[ "$has_untracked" == "true" ]] || continue
		    UNTRACKED_TOTAL=$((UNTRACKED_TOTAL + 1))
		    npad=$(printf '%03d' "$n")
		    untracked_dir="$BUNDLE/stashed-untracked/$npad"
		    expected_manifest="$WORKSPACE/.polish_${npad}_expected_untracked.tsv"
		    actual_manifest="$WORKSPACE/.polish_${npad}_actual_untracked.tsv"
		    if [[ ! -d "$untracked_dir" ]] || [[ -z "$(find "$untracked_dir" -mindepth 1 -print -quit 2>/dev/null)" ]]; then
		      UNTRACKED_BAD=$((UNTRACKED_BAD + 1))
		    elif ! write_git_tree_manifest "refs/stash-backup/$npad^3" "$expected_manifest"; then
		      UNTRACKED_BAD=$((UNTRACKED_BAD + 1))
		    elif ! write_materialized_tree_manifest "$untracked_dir" "$actual_manifest"; then
		      UNTRACKED_BAD=$((UNTRACKED_BAD + 1))
		    elif ! cmp -s "$expected_manifest" "$actual_manifest"; then
		      UNTRACKED_BAD=$((UNTRACKED_BAD + 1))
		    fi
		  done < <(awk -F'\t' 'NR > 1' "$INVENTORY")
		  if [[ "$UNTRACKED_BAD" -eq 0 ]]; then
		    pass "every has_untracked=true stash has byte-equal materialized untracked files (n=$UNTRACKED_TOTAL)"
		  else
		    fail "$UNTRACKED_BAD has_untracked=true rows lack byte-equal materialized untracked files"
		  fi
else
  fail "inventory or verification log missing"
fi

echo
echo "P2: Verdict evidence"
if [[ -f "$TRIAGE" ]]; then
  EMPTY_VERDICT=$(awk -F'\t' 'NR > 1 && ($2 == "" || $2 == "unknown")' "$TRIAGE" | wc -l)
  if [[ "$EMPTY_VERDICT" -eq 0 ]]; then
    pass "every row has a verdict"
  else
    fail "$EMPTY_VERDICT rows have empty/unknown verdict"
  fi
else
  fail "triage.tsv missing"
fi

echo
echo "P3: No phantom keepers"
if [[ -f "$TRIAGE" ]]; then
  PHANTOM=$(awk -F'\t' 'NR > 1 && $2 == "novel-and-accretive" && $4 != "" && !match($4, /no symbols/)' "$TRIAGE" | wc -l)
  if [[ "$PHANTOM" -eq 0 ]]; then
    pass "no novel-and-accretive rows with symbols on main"
  else
    fail "$PHANTOM novel-and-accretive rows have evidence on main"
  fi
fi

echo
echo "P4: Per-apply gates"
# Both apply_log.tsv (Phase 6) and partial_split_log.tsv (Phase 7) record
# gates_status in column 5. Both kinds of recovery commit must have passed
# their gates; previously this check only validated Phase 6 keepers, leaving
# Phase 7 split-applies unverified by the polish bar.
P4_BAD_TOTAL=0
for log in "$APPLY_LOG" "$PARTIAL_LOG"; do
  [[ -f "$log" ]] || continue
  bad=$(awk -F'\t' 'NR > 1 && $5 != "passed" && $5 != "" && !match($5, /pre-existing-ok/)' "$log" | wc -l)
  P4_BAD_TOTAL=$((P4_BAD_TOTAL + bad))
done
if [[ -f "$APPLY_LOG" || -f "$PARTIAL_LOG" ]]; then
  if [[ "$P4_BAD_TOTAL" -eq 0 ]]; then
    pass "every applied keeper (Phase 6 + Phase 7) passed gates"
  else
    fail "$P4_BAD_TOTAL apply/split-apply rows have non-passing gates_status"
  fi
else
  pass "no apply or partial-split logs (no keepers to validate)"
fi

echo
echo "P5: Focused commit messages"
# Subject regex accepts ALL of the four commit-message conventions the
# discover-project script knows about (project_profile.json:commit_message_convention):
#   - conventional:  ^feat: recover... / fix(scope): recover...
#   - ticket-id:     ^BACK-1234: recover... / JIRA-99: recover...
#   - gitmoji:       ^:zap: recover... / :sparkles: recover...
#   - freeform:      ^recover... (no prefix)
# The verbs are recover|restore|reapply (case-insensitive — some conventions
# capitalize the first letter of the imperative).
SUBJECT_REGEX='^((feat|fix|test|perf|refactor|chore|build|ci|docs|style|revert)(\([^)]+\))?: |[A-Z][A-Z0-9_]*-[0-9]+: |:[a-z_]+: )?(recover|restore|reapply)\b'

check_message_contract() {
  local log_path="$1"
  local out_bad="$2" out_stale="$3"
  local n _ref sha _files _gates _duration _drift msg subj bad=0 stale=0
  while IFS=$'\t' read -r n _ref sha _files _gates _duration _drift; do
    [[ "$n" == "n" || -z "${sha:-}" ]] && continue
    msg=$(git -C "$PROJECT_ABS" log -1 --format='%s%n%b' "$sha" 2>/dev/null || true)
    if [[ -z "$msg" ]]; then
      # SHA in log doesn't resolve — recovery branch deleted, force-pushed,
      # or commit was amended away. Not a polish-bar failure for the message
      # contract; record separately so the user can decide whether to investigate.
      stale=$((stale + 1))
      continue
    fi
    # Use `sed -n '1p'` instead of `head -1` to avoid SIGPIPE: head closes its
    # stdin after the first line, killing printf with exit 141 when the message
    # body has many lines. sed reads all stdin, prints only line 1 — no SIGPIPE.
    subj=$(printf '%s\n' "$msg" | sed -n '1p')
    if ! printf '%s' "$subj" | grep -qiE "$SUBJECT_REGEX"; then
      bad=$((bad + 1)); continue
    fi
    if ! printf '%s' "$msg" | grep -qE 'stash@\{[0-9]+\}'; then
      bad=$((bad + 1)); continue
    fi
    if printf '%s' "$msg" | grep -q '^Co-Authored-By:'; then
      bad=$((bad + 1))
    fi
  done < "$log_path"
  printf -v "$out_bad" '%s' "$bad"
  printf -v "$out_stale" '%s' "$stale"
}

P5_BAD_TOTAL=0
P5_STALE_TOTAL=0
for log in "$APPLY_LOG" "$PARTIAL_LOG"; do
  [[ -f "$log" ]] || continue
  bad_count=0; stale_count=0
  check_message_contract "$log" bad_count stale_count
  P5_BAD_TOTAL=$((P5_BAD_TOTAL + bad_count))
  P5_STALE_TOTAL=$((P5_STALE_TOTAL + stale_count))
done

if [[ -f "$APPLY_LOG" || -f "$PARTIAL_LOG" ]]; then
  if [[ "$P5_BAD_TOTAL" -eq 0 ]]; then
    pass "applied keeper commit messages (Phase 6 + Phase 7) cite stash source and use recovery subject"
  else
    fail "$P5_BAD_TOTAL applied keeper commit messages fail the recovery-message contract"
  fi
  if [[ "$P5_STALE_TOTAL" -gt 0 ]]; then
    warn "$P5_STALE_TOTAL apply/split-apply rows reference SHAs that no longer resolve (recovery branch deleted/amended?)"
  fi
else
  pass "apply/partial-split logs absent (no keeper messages to check)"
fi

echo
echo "P6: Order of drops"
if [[ -f "$CLEANUP_LOG" ]]; then
  if awk -F'\t' '
      BEGIN {
        # Cleanup bucket order from PHASES.md § Phase 9:
        #   garbage → superseded → novel-but-stale → applied-keeper
        # `superseded-by-newer-stash` is the merge-triage subagent verdict for
        # within-family-supersession (see FAILURE-MODES.md F9, STASH-SMELLS.md
        # Smell 1) — it shares the supersession bucket with `superseded`.
        verdict_order["garbage"] = 1
        verdict_order["superseded"] = 2
        verdict_order["superseded-by-newer-stash"] = 2
        verdict_order["novel-but-stale"] = 3
        verdict_order["applied-keeper"] = 4
        bad = 0
        last_v = 0
        last_n = ""
        prev_verdict = ""
      }
      NR > 1 {
        v = verdict_order[$4]
        if (!v) {
          # Unmapped verdict in cleanup_log: drop-confirmed.sh verdict-bucket
          # gate now refuses these, but if a row exists with an unmapped verdict
          # (e.g., from an old run before the gate existed, or via the override
          # env var), surface it as a violation rather than silently passing.
          # Without this check, P6 would have missed the scale-test scenario
          # where 3 novel-and-accretive stashes were dropped — verdict_order
          # has no entry for novel-and-accretive, so v=0, and the v<last_v
          # check skipped silently.
          print "BUCKET VIOLATION: row " NR " has verdict [" $4 "] not in {garbage,superseded,superseded-by-newer-stash,novel-but-stale,applied-keeper}"
          bad++
          next
        }
        if (v < last_v) {
          print "ORDER VIOLATION (verdict): row " NR " " $4
          bad++
        }
        if ($4 == prev_verdict) {
          if (last_n != "" && $1 >= last_n) {
            print "ORDER VIOLATION (index): row " NR " n=" $1 " >= prev=" last_n
            bad++
          }
        } else {
          last_n = ""
        }
        last_v = v
        prev_verdict = $4
        last_n = $1
      }
      END { exit (bad ? 1 : 0) }
    ' "$CLEANUP_LOG"
  then
    pass "drops in correct bucket order, descending index"
  else
    fail "drop order violation (see output above)"
  fi
else
  # Without this branch, the P6 section emits its header but no PASS/FAIL line —
  # the user reading the output sees an empty dimension and doesn't know if
  # P6 is "pass-by-vacuity" or "the script crashed mid-check". Surface it.
  pass "cleanup_log absent (no Phase 9 drops to validate ordering)"
fi

echo
echo "P8: Idempotent empty-run behavior"
if [[ -f "$INVENTORY" ]]; then
  N_INV=$(awk 'NR > 1' "$INVENTORY" | wc -l)
  if [[ "$N_INV" -eq 0 ]]; then
    BAD_EMPTY_RUN=0
    if [[ -f "$APPLY_LOG" ]] && [[ "$(awk 'NR > 1 && $3 != ""' "$APPLY_LOG" | wc -l)" -gt 0 ]]; then BAD_EMPTY_RUN=1; fi
    if [[ -f "$CLEANUP_LOG" ]] && [[ "$(awk 'NR > 1' "$CLEANUP_LOG" | wc -l)" -gt 0 ]]; then BAD_EMPTY_RUN=1; fi
    if [[ "$BAD_EMPTY_RUN" -eq 0 ]]; then
      pass "zero-stash run did not author apply/drop records"
    else
      fail "zero-stash run has apply/drop records"
    fi
  else
    pass "not an empty-run invocation (idempotence smoke not applicable)"
  fi
else
  fail "inventory.tsv missing"
fi

echo
echo "P9: Resumable mid-run"
if [[ -f "$APPLY_LOG" ]]; then
  DUP_APPLIES=$(awk -F'\t' 'NR > 1 && $3 != "" {seen[$1]++} END {for (n in seen) if (seen[n] > 1) dup++; print dup + 0}' "$APPLY_LOG")
  if [[ "$DUP_APPLIES" -eq 0 ]]; then
    pass "apply_log has no duplicate applied stash indexes"
  else
    fail "$DUP_APPLIES stash indexes were applied more than once"
  fi
else
  pass "apply_log absent (no Phase 6 applies to resume)"
fi

echo
echo "P10: No phantom side effects"
if [[ -n "$BUNDLE" && -d "$BUNDLE" ]]; then
  pass "bundle directory still exists"
else
  fail "bundle directory missing"
fi
if [[ -f "$INVENTORY" ]]; then
  N_INV=$(awk 'NR > 1' "$INVENTORY" | wc -l)
  N_REF=$(git -C "$PROJECT_ABS" for-each-ref refs/stash-backup/ 2>/dev/null | wc -l)
  if [[ "$N_REF" -ge "$N_INV" ]]; then
    pass "backup refs still exist for inventory rows"
  else
    fail "backup refs missing after run: refs=$N_REF inventory=$N_INV"
  fi
fi

echo
echo "P7: Verbatim authorization"
AUTH="$WORKSPACE/cleanup_authorization.txt"
if [[ -s "$AUTH" ]] && grep -Eiq "$AUTHORIZATION_RE" "$AUTH"; then
  pass "authorization file present with specific phrase"
else
  if [[ -f "$CLEANUP_LOG" ]] && [[ "$(awk 'NR > 1' "$CLEANUP_LOG" | wc -l)" -gt 0 ]]; then
    fail "cleanup happened but no/vague authorization in $AUTH"
  else
    pass "no cleanup occurred (authorization not required)"
  fi
fi

echo
echo "Total fails: $FAILS"
exit $FAILS
