#!/usr/bin/env bash
# apply-keeper.sh — Phase 6: apply ONE keeper stash and run quality gates.
#
# Usage: apply-keeper.sh <project-path> <n>
#
# Idempotent: if the stash has already been applied (per apply_log.tsv),
# this script no-ops.

set -euo pipefail

PROJECT="${1:?Usage: apply-keeper.sh <project-path> <n>}"
N="${2:?missing stash index n}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=project-root.sh
. "$SCRIPT_DIR/project-root.sh"

PROJECT_ABS="$(resolve_project_root "$PROJECT")"
WORKSPACE="$PROJECT_ABS/.stash_janitor_workspace"
PROFILE="$WORKSPACE/project_profile.json"
APPLY_LOG="$WORKSPACE/apply_log.tsv"
INVENTORY="$WORKSPACE/inventory.tsv"

# Explicit pre-condition checks: surface clear messages instead of cryptic
# errors from `cat` / `set -e` aborts when the run hasn't progressed far
# enough.
if [[ ! -f "$WORKSPACE/bundle_path.txt" ]]; then
  echo "ERROR: Phase 3 has not completed yet ($WORKSPACE/bundle_path.txt missing)." >&2
  echo "Run scripts/build-bundle.sh and scripts/verify-bundle.sh first." >&2
  exit 8
fi
BUNDLE="$(cat "$WORKSPACE/bundle_path.txt")"
if [[ ! -d "$BUNDLE" ]]; then
  echo "ERROR: bundle path '$BUNDLE' does not exist (stale bundle_path.txt?)" >&2
  exit 8
fi
if [[ ! -f "$INVENTORY" ]]; then
  echo "ERROR: Phase 2 has not completed yet ($INVENTORY missing)." >&2
  exit 8
fi
if [[ ! -f "$PROFILE" ]]; then
  echo "ERROR: Phase 1 has not completed yet ($PROFILE missing)." >&2
  exit 8
fi

# Defense-in-depth: require Phase 5's user-authorization gate. Per
# subagents/triage-merger.md and references/MEASUREMENT.md, Phase 5 must
# capture the user's verbatim go-ahead in `phase5_user_authorization.txt`
# before any keepers are applied. The orchestrator (triage-merger subagent)
# normally writes this; checking for it here closes the same gap I closed
# for drop-confirmed.sh — without this guard, a misfired script invocation
# could commit keepers to the recovery branch with no recorded user consent.
# `PHASE5_AUTHORIZATION_OVERRIDE_OK=1` opts out for direct one-keeper use.
PHASE5_AUTH_FILE="$WORKSPACE/phase5_user_authorization.txt"
if [[ -z "${PHASE5_AUTHORIZATION_OVERRIDE_OK:-}" ]]; then
  if [[ ! -s "$PHASE5_AUTH_FILE" ]]; then
    echo "ERROR: phase5_user_authorization.txt is missing or empty." >&2
    echo "  $PHASE5_AUTH_FILE" >&2
    echo "Phase 5's triage-merger subagent records the user's verbatim go-ahead" >&2
    echo "(e.g., 'go', 'proceed', 'approved') here before any keeper apply runs." >&2
    echo "If you're invoking this script directly without Phase 5, set" >&2
    echo "PHASE5_AUTHORIZATION_OVERRIDE_OK=1 to bypass this check." >&2
    exit 8
  fi
fi

# Initialize log + workspace dirs if absent
mkdir -p "$WORKSPACE/conflicts"
if [[ ! -f "$APPLY_LOG" ]]; then
  printf 'n\tref\tnew_commit_sha\tfiles_changed\tgates_status\tduration_s\tpre_apply_drift\n' > "$APPLY_LOG"
fi

# Pre-flight: refuse to start if the index has unmerged paths from a prior
# failed apply. Without this, the apply-check + apply both succeed for a
# different file, but `git commit` later refuses with "Committing is not
# possible because you have unmerged files" — the script aborts mid-flight
# WITHOUT logging a failure row, so apply_log.tsv silently lacks the attempt.
# Discovered during the integration-test run when stash N's failed apply left
# UU markers on src/util.py and stash N+1 (touching only src/lib.py) hit the
# unmerged-index error at commit time.
unmerged=$(git -C "$PROJECT_ABS" diff --name-only --diff-filter=U 2>/dev/null || true)
if [[ -n "$unmerged" ]]; then
  echo "ERROR: index has unmerged paths from a prior failed apply:" >&2
  while IFS= read -r path; do
    [[ -n "$path" ]] && printf '  %s\n' "$path" >&2
  done <<< "$unmerged"
  echo "Resolve the conflict markers in those files, then either:" >&2
  echo "  - git add <path>     # mark resolved, then re-run apply-keeper.sh" >&2
  echo "  - get explicit user approval for a path-specific discard/recovery plan" >&2
  echo "    (see references/INCIDENT-PLAYBOOK.md § I3; do not auto-overwrite files)" >&2
  echo "Or set APPLY_KEEPER_INDEX_UNMERGED_OVERRIDE_OK=1 to ignore this check (NOT recommended)." >&2
  if [[ -z "${APPLY_KEEPER_INDEX_UNMERGED_OVERRIDE_OK:-}" ]]; then
    printf '%s\t%s\t\t\tindex-unmerged-from-prior-apply\t\t\n' "${N:-?}" "stash@{${N:-?}}" >> "$APPLY_LOG"
    exit 12
  fi
fi

# Idempotence: skip if already applied
if awk -F'\t' -v n="$N" 'NR > 1 && $1 == n && $3 != "" {found=1} END {exit !found}' "$APPLY_LOG"; then
  echo "n=$N already applied (per apply_log.tsv); skipping."
  exit 0
fi

NPAD=$(printf '%03d' "$N")
DIFF="$BUNDLE/diffs/$NPAD.diff"
if [[ ! -f "$DIFF" ]]; then
  echo "ERROR: bundle diff not found at $DIFF" >&2
  exit 2
fi
UNTRACKED_DIR="$BUNDLE/stashed-untracked/$NPAD"
HAS_TRACKED_DIFF=false
if grep -q '^diff --git ' "$DIFF"; then
  HAS_TRACKED_DIFF=true
fi
HAS_UNTRACKED_FILES=false
if [[ -d "$UNTRACKED_DIR" ]] && [[ -n "$(find "$UNTRACKED_DIR" -mindepth 1 -print -quit)" ]]; then
  HAS_UNTRACKED_FILES=true
fi
if [[ "$HAS_TRACKED_DIFF" != "true" && "$HAS_UNTRACKED_FILES" != "true" ]]; then
  echo "ERROR: stash@{$N} has neither tracked diff content nor materialized untracked files" >&2
  printf '%s\t%s\t\t\tparse-failed\t\t%s\n' "$N" "stash@{$N}" "empty bundle artifacts" >> "$APPLY_LOG"
  exit 6
fi

# Read profile through a real JSON parser. project_profile.json is emitted with
# normal JSON escaping, so regex extraction truncates commands containing
# embedded quotes or backslashes and can run the wrong gates.
profile_json_value() {
  local key="$1" out
  if command -v jq >/dev/null 2>&1; then
    if ! out=$(jq -r --arg key "$key" '.[$key] | if . == null then "" elif type == "boolean" then tostring elif type == "string" then . else tostring end' "$PROFILE"); then
      echo "ERROR: unable to parse $PROFILE as JSON." >&2
      exit 8
    fi
    printf '%s' "$out"
    return
  fi
  if command -v python3 >/dev/null 2>&1; then
    if ! out=$(python3 - "$PROFILE" "$key" <<'PY'
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
    print(str(value))
PY
    ); then
      echo "ERROR: unable to parse $PROFILE as JSON." >&2
      exit 8
    fi
    printf '%s' "$out"
    return
  fi
  echo "ERROR: need jq or python3 to parse $PROFILE." >&2
  exit 8
}
TEST_CMD=$(profile_json_value test_command)
TYPECHECK_CMD=$(profile_json_value typecheck_command)
LINT_CMD=$(profile_json_value lint_command)
UBS_AVAILABLE=$(profile_json_value ubs_available)
PRIMARY_BRANCH=$(profile_json_value primary_branch)

# Critical safety check: refuse to apply when HEAD is on the primary branch or
# detached. Per PHASES.md § Phase 6, the orchestrator must create or resume a
# recovery branch before invoking apply-keeper. If this script is run without
# that setup, keeper commits would land directly on the primary branch —
# polluting it with un-reviewed experimental recoveries — or on a detached HEAD
# where the commit is unreachable from any branch.
#
# The user can override with RECOVERY_BRANCH_OVERRIDE_OK=1 if they truly want
# to apply on a non-recovery branch (e.g., manual cherry-pick into a feature
# branch). Default: refuse.
CURRENT_BRANCH=$(git -C "$PROJECT_ABS" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
if [[ -z "${RECOVERY_BRANCH_OVERRIDE_OK:-}" ]]; then
  if [[ -z "$PRIMARY_BRANCH" ]]; then
    echo "ERROR: project_profile.json is missing primary_branch." >&2
    echo "Cannot prove HEAD is off the primary branch, so refusing to apply keeper commits." >&2
    echo "Run scripts/discover-project.sh again or fill project_profile.json.primary_branch before Phase 6." >&2
    echo "Or set RECOVERY_BRANCH_OVERRIDE_OK=1 to accept the current branch target intentionally." >&2
    exit 8
  fi
  if [[ -z "$CURRENT_BRANCH" ]]; then
    echo "ERROR: HEAD is detached. Keeper commits would be unreachable from any branch." >&2
    echo "Create a recovery branch first:" >&2
    echo "  rb=stash-recovery-\$(date -u +%Y-%m-%d)" >&2
    echo "  git show-ref --verify --quiet \"refs/heads/\$rb\" && git checkout \"\$rb\" || git checkout -b \"\$rb\" <primary-branch>" >&2
    echo "Or set RECOVERY_BRANCH_OVERRIDE_OK=1 to apply anyway (records on detached HEAD)." >&2
    exit 8
  fi
  if [[ "$CURRENT_BRANCH" == "$PRIMARY_BRANCH" ]]; then
    echo "ERROR: HEAD is on the primary branch '$PRIMARY_BRANCH'." >&2
    echo "Per PHASES.md Phase 6, keepers must land on a recovery branch first:" >&2
    echo "  rb=stash-recovery-\$(date -u +%Y-%m-%d)" >&2
    echo "  git show-ref --verify --quiet \"refs/heads/\$rb\" && git checkout \"\$rb\" || git checkout -b \"\$rb\" $PRIMARY_BRANCH" >&2
    echo "Or set RECOVERY_BRANCH_OVERRIDE_OK=1 to commit on $PRIMARY_BRANCH directly (NOT recommended)." >&2
    exit 8
  fi
fi

# Read stash metadata. Use tab as IFS because DATE and MSG can contain spaces
# (date has "2026-05-06 17:31:25 -0400"; messages can have any whitespace).
IFS=$'\t' read -r REF SHA DATE MSG <<< "$(awk -F'\t' -v n="$N" -v OFS='\t' \
  'NR > 1 && $1 == n {print $2, $3, $5, $7; exit}' "$INVENTORY")"

if [[ -z "$REF" || -z "$SHA" ]]; then
  echo "ERROR: stash row n=$N not found in inventory" >&2
  exit 5
fi

START=$(date +%s)

# Working-tree-drift snapshot. EXCLUDE the skill's own workspace path —
# `.stash_janitor_workspace/` lives inside the project tree and contains 10+
# artifacts (inventory.tsv, triage.tsv, apply_log.tsv, conflicts/, etc.) that
# show up as untracked in `git status --porcelain=v2`. Without the exclude,
# DRIFT would ALWAYS report "concurrent: N files modified" — the signal would
# be permanently positive and useless. The exclude pathspec is the same one
# recovery-test.sh uses for its dirty-tree gate.
WT_PRE="$WORKSPACE/wt_pre_apply_$NPAD.txt"
git -C "$PROJECT_ABS" status --porcelain=v2 -- . ':(exclude).stash_janitor_workspace' > "$WT_PRE"
DRIFT="none"
if [[ -s "$WT_PRE" ]]; then
  DRIFT="concurrent: $(wc -l < "$WT_PRE") files modified"
fi

echo "Applying stash@{$N} ($MSG)..."

# Apply-check first. Capture stderr to a variable so we only write the
# conflict-context file on actual failure (otherwise an empty file accumulates
# in conflicts/ even on success, polluting the workspace).
CONFLICT_FILE="$WORKSPACE/conflicts/stash_${NPAD}.context.md"
if [[ "$HAS_TRACKED_DIFF" == "true" ]]; then
  if ! check_err=$(git -C "$PROJECT_ABS" apply --3way --check "$DIFF" 2>&1); then
    echo "ERROR: apply-check failed for n=$N"
    # Single-quoted format strings are intentional: the literal backticks in the
    # markdown are not shell expansions. Variable values are passed via %s.
    # shellcheck disable=SC2016
    {
      printf '# Apply-check failure: stash@{%s}\n\n' "$N"
      printf 'Bundle diff: `%s`\n\n' "$DIFF"
      printf '## Git output\n\n```\n%s\n```\n' "$check_err"
    } > "$CONFLICT_FILE"
    echo "Conflict context written to $CONFLICT_FILE"
    echo "Surface to user for manual resolution."
    printf '%s\t%s\t\t\tapply-check-failed\t\t%s\n' "$N" "$REF" "$DRIFT" >> "$APPLY_LOG"
    exit 3
  fi
else
  echo "  apply-check: skipped (stash has untracked files only)"
fi

# Apply for real. Even though --check passed, the apply itself can fail when
# `--3way` produces conflict markers — typically because a *previously applied
# keeper in this same run* modified the same file, so `--check` (which tests
# patch validity, not 3-way merge feasibility against the live tree) passed but
# the actual 3-way merge couldn't auto-resolve. Also possible: a concurrent
# agent edited a target file between check and apply.
#
# Either way, the working tree may now contain conflict markers. Surface
# honestly, attempt revert, and halt — never leave the user staring at a
# half-applied stash with no diagnostic and no cleanup.
if [[ "$HAS_TRACKED_DIFF" == "true" ]]; then
  if ! apply_err=$(git -C "$PROJECT_ABS" apply --3way "$DIFF" 2>&1); then
    echo "ERROR: apply failed for n=$N (despite passing apply-check)"
    echo "Likely causes (in order of frequency):"
    echo "  1. A previously applied keeper this run touched the same file (3-way merge can't auto-resolve)"
    echo "  2. A concurrent agent edited a target file between check and apply"
    # Single-quoted format strings are intentional (markdown literal backticks).
    # shellcheck disable=SC2016
    {
      printf '# Apply failure (post-check): stash@{%s}\n\n' "$N"
      printf 'Bundle diff: `%s`\n\n' "$DIFF"
      printf '## Git output\n\n```\n%s\n```\n' "$apply_err"
      printf '\n## Working-tree state at failure\n\n```\n'
      # Exclude the skill's own workspace from the diagnostic so the user sees
      # the real conflict signal (their working tree's tracked-file state and
      # any non-skill untracked files) without 10+ lines of skill-artifact noise.
      git -C "$PROJECT_ABS" status --porcelain=v2 -- . ':(exclude).stash_janitor_workspace' 2>&1
      printf '```\n'
    } > "$CONFLICT_FILE"
    echo "Context written to $CONFLICT_FILE"

    # Attempt to revert the partial apply so the next keeper-apply (or any
    # subsequent operation) starts from a clean tree. Without this, the
    # working tree carries `<<<<<<<` conflict markers from this stash forward,
    # and continuing would compound the dirty state. `git apply -R --3way`
    # reverses the patch via 3-way merge if possible.
    echo "Attempting revert of partial apply..."
    if git -C "$PROJECT_ABS" apply -R --3way "$DIFF" 2>/dev/null; then
      echo "  ✓ Reverted; working tree returned to pre-apply state."
    else
      # Revert via patch failed. Fall back to per-path reset for ONLY the paths
      # the apply touched (NOT a global checkout — Axiom 7: never disturb
      # concurrent agents' work). Use the unstaged-conflict markers to find
      # the affected paths.
      conflicted=$(git -C "$PROJECT_ABS" diff --name-only --diff-filter=U 2>/dev/null || true)
      if [[ -n "$conflicted" ]]; then
        echo "  ✗ Revert via patch failed; conflicted paths still dirty:"
        while IFS= read -r path; do
          [[ -n "$path" ]] && printf '    %s\n' "$path" >&2
        done <<< "$conflicted"
        echo "  Inspect: cat $CONFLICT_FILE  &&  git status" >&2
        echo "  Manual recovery requires an explicit user-approved path-specific plan." >&2
        echo "  See references/INCIDENT-PLAYBOOK.md § I3 before overwriting any file." >&2
      else
        echo "  ✓ No conflicted paths remain; tree appears clean."
      fi
    fi

    printf '%s\t%s\t\t\tapply-failed-after-check\t\t%s\n' "$N" "$REF" "$DRIFT" >> "$APPLY_LOG"
    exit 9
  fi
fi

# Untracked files (if present). Use a tar pipe so dotfiles, nested directories,
# and executable bits are preserved. `git stash show -p --binary` does not include these.
#
# Pre-check for path conflicts. The tar pipe would silently OVERWRITE any
# existing path in the working tree, which could clobber a concurrent agent's
# file at the same path — Axiom 7 violation. If any destination path already
# exists, halt and surface to the user; let them decide whether the conflict
# is "their own from a prior partial run" (safe to overwrite) or "another
# agent's work" (don't touch).
if [[ "$HAS_UNTRACKED_FILES" == "true" ]]; then
  CONFLICTS_LIST="$WORKSPACE/.apply_${NPAD}_untracked_conflicts.list"
  : > "$CONFLICTS_LIST"
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    f="${f#./}"
    # `-e` is false for broken symlinks because it dereferences the target.
    # A broken symlink is still an existing filesystem node that tar extraction
    # could replace, so treat `-L` as a conflict too.
    if [[ -e "$PROJECT_ABS/$f" || -L "$PROJECT_ABS/$f" ]]; then
      printf '%s\n' "$f" >> "$CONFLICTS_LIST"
    fi
  done < <( cd "$UNTRACKED_DIR" && find . \( -type f -o -type l \) -print 2>/dev/null )

  if [[ -s "$CONFLICTS_LIST" ]]; then
    n_conf=$(wc -l < "$CONFLICTS_LIST")
    echo "ERROR: untracked-files copy would overwrite $n_conf existing path(s):" >&2
    head -5 "$CONFLICTS_LIST" | sed 's/^/  /' >&2
    [[ "$n_conf" -gt 5 ]] && echo "  ... ($n_conf total; see $CONFLICTS_LIST)" >&2
    echo
    echo "These paths could be:" >&2
    echo "  (a) concurrent agents' work — DO NOT clobber (Axiom 7)" >&2
    echo "  (b) leftovers from a prior partial run of this stash" >&2
    echo
    echo "Halting; surface to user to decide. If these are leftovers from a prior partial run:" >&2
    echo "  mv <path> <path>.prior-partial-${NPAD}  # then re-run apply-keeper.sh" >&2
    printf '%s\t%s\t\t\tuntracked-conflict\t\t%s\n' "$N" "$REF" "$DRIFT" >> "$APPLY_LOG"
    exit 11
  fi

  if ! ( cd "$UNTRACKED_DIR" && tar -cf - . ) | ( cd "$PROJECT_ABS" && tar -xf - ); then
    echo "ERROR: failed to copy materialized untracked files for stash@{$N}" >&2
    printf '%s\t%s\t\t\tuntracked-copy-failed\t\t%s\n' "$N" "$REF" "$DRIFT" >> "$APPLY_LOG"
    exit 10
  fi

  # Track which paths we just created so we can surface them on gate failure.
  UNTRACKED_COPIED_LIST="$WORKSPACE/.apply_${NPAD}_untracked_copied.list"
  ( cd "$UNTRACKED_DIR" && find . \( -type f -o -type l \) -print 2>/dev/null ) \
    | sed 's#^\./##' > "$UNTRACKED_COPIED_LIST"
fi

DIFF_FILES_LIST="$WORKSPACE/.apply_${NPAD}_files.list"
: > "$DIFF_FILES_LIST"
if [[ "$HAS_TRACKED_DIFF" == "true" ]]; then
  # Parse paths from the AUTHORITATIVE per-file lines (`--- a/<path>`,
  # `+++ b/<path>`, `rename from <X>`, `rename to <Y>`, `Binary files
  # a/<X> and b/<Y> differ`) instead of from the `diff --git a/X b/Y`
  # line alone. The `diff --git` line is genuinely ambiguous when X == Y
  # and both contain the substring ' b/' (e.g., a file at `foo b/bar.py`):
  # the previous "find LAST ` b/`" heuristic picks the wrong delimiter
  # and emits malformed paths. Fuzz fixture 07 surfaced this.
  awk '
    # Defensive: strip trailing whitespace (some tooling emits `--- a/foo<TAB>date`
    # in non-git unified diffs; git itself never does, but be robust either way).
    function clean(p) { sub(/[[:space:]]+$/, "", p); return p }
    function emit(p) { p = clean(p); if (p != "" && p != "/dev/null" && !seen[p]++) print p }
    /^--- a\// { p = $0; sub(/^--- a\//, "", p); emit(p); next }
    /^\+\+\+ b\// { p = $0; sub(/^\+\+\+ b\//, "", p); emit(p); next }
    # `rename from`/`rename to` cover pure renames (no content change, so no
    # --- / +++ lines). The path follows a single space.
    /^rename from / { p = $0; sub(/^rename from /, "", p); emit(p); next }
    /^rename to /   { p = $0; sub(/^rename to /,   "", p); emit(p); next }
    # Binary files: `Binary files a/<X> and b/<Y> differ`. Use a regex
    # capture-style split — git always emits this exact phrasing.
    /^Binary files a\// {
      line = $0
      sub(/^Binary files a\//, "", line)
      # Now: "<old> and b/<new> differ"
      split_pos = index(line, " and b/")
      if (split_pos > 0) {
        old = substr(line, 1, split_pos - 1)
        rest = substr(line, split_pos + length(" and b/"))
        new = rest; sub(/ differ$/, "", new)
        emit(old); emit(new)
      }
    }
  ' "$DIFF" >> "$DIFF_FILES_LIST"
  # Full binary patches (`git stash show -p --binary`) for tracked binary
  # modifications can omit ---/+++ file headers and instead contain only
  # `diff --git`, `index`, and `GIT binary patch` blocks. Always add binary
  # numstat paths, not just as an empty-list fallback: mixed text+binary
  # stashes would otherwise stage the text files and leave binary changes
  # unstaged. Let git parse its own patch format so paths containing spaces or
  # the substring " b/" stay intact.
  git -C "$PROJECT_ABS" apply --numstat "$DIFF" 2>/dev/null \
    | awk -F'\t' '$1 == "-" && $2 == "-" && NF >= 3 && $3 != "" {print $3}' >> "$DIFF_FILES_LIST" || true
fi
if [[ "$HAS_UNTRACKED_FILES" == "true" ]]; then
  ( cd "$UNTRACKED_DIR" && find . \( -type f -o -type l \) -print ) \
    | sed 's#^\./##' >> "$DIFF_FILES_LIST"
fi
sort -u "$DIFF_FILES_LIST" -o "$DIFF_FILES_LIST"

# Quality gates
GATES_STATUS="passed"
run_gate() {
  local name="$1"
  local cmd="$2"
  if [[ -z "$cmd" ]]; then
    echo "  $name: <skipped, not configured>"
    return 0
  fi
  echo "  $name: $cmd"
  if ! ( cd "$PROJECT_ABS" && eval "$cmd" ); then
    GATES_STATUS="failed-${name}"
    return 1
  fi
}

if ! run_gate test "$TEST_CMD"; then GATES_STATUS="failed-test"; fi
if [[ "$GATES_STATUS" == "passed" ]] && ! run_gate typecheck "$TYPECHECK_CMD"; then GATES_STATUS="failed-typecheck"; fi
if [[ "$GATES_STATUS" == "passed" ]] && ! run_gate lint "$LINT_CMD"; then GATES_STATUS="failed-lint"; fi
if [[ "$GATES_STATUS" == "passed" && "$UBS_AVAILABLE" == "true" ]]; then
  if ! ( cd "$PROJECT_ABS" && ubs . ); then
    GATES_STATUS="failed-ubs"
  fi
fi

DURATION=$(($(date +%s) - START))

if [[ "$GATES_STATUS" != "passed" ]]; then
	  echo "ERROR: gates failed: $GATES_STATUS"
	  echo
	  echo "The working tree has the half-applied stash. To recover:"
	  if [[ "$HAS_TRACKED_DIFF" == "true" ]]; then
	    echo "  1. \`git apply -R --3way $DIFF\` to attempt automatic tracked-diff revert"
	  else
	    echo "  1. No tracked diff was applied; only untracked files were copied."
	  fi
	  echo "  2. If automatic revert fails, inspect \`git status\` and \`git diff\`;"
	  echo "     undo only the specific paths from $DIFF_FILES_LIST."
	  echo "  3. Mark this stash conflict-skipped in triage.tsv and continue"
	  echo
	  if [[ "$HAS_TRACKED_DIFF" == "true" ]]; then
	    echo "Attempting automatic revert via 'git apply -R --3way'..."
	    # `--3way` lets the revert resolve via 3-way merge if a concurrent agent
	    # modified a target file between our apply and our revert. Without --3way
	    # the revert can fail spuriously even when the underlying intent is clear.
	    if git -C "$PROJECT_ABS" apply -R --3way "$DIFF" 2>/dev/null; then
	      echo "  ✓ Reverted tracked diff cleanly."
	    else
	      echo "  ✗ Automatic tracked-diff revert failed. Working tree is dirty; investigate manually."
	      echo "    Inspect: git status; git diff"
	      echo "    See references/INCIDENT-PLAYBOOK.md § I3 for safe recovery steps."
	    fi
	  else
	    echo "Skipping tracked-diff revert because there is no tracked diff to reverse."
	  fi
	  if [[ "$HAS_UNTRACKED_FILES" == "true" && -s "${UNTRACKED_COPIED_LIST:-/dev/null}" ]]; then
	    n_copied=$(wc -l < "$UNTRACKED_COPIED_LIST")
	    echo
	    echo "  $n_copied untracked file(s) were copied from the bundle into the working tree:"
	    head -5 "$UNTRACKED_COPIED_LIST" | sed 's/^/    /'
	    [[ "$n_copied" -gt 5 ]] && echo "    ... ($n_copied total; see $UNTRACKED_COPIED_LIST)"
	    echo
	    echo "  Per AGENTS.md Rule #1, the skill does NOT delete these for you."
	    echo "  To remove them yourself (after confirming none are concurrent-agent work):"
	    echo "    while IFS= read -r f; do mv \"\$f\" \"\$f.untracked-revert-${NPAD}\"; done < $UNTRACKED_COPIED_LIST"
	  fi
  printf '%s\t%s\t\t\t%s\t%s\t%s\n' "$N" "$REF" "$GATES_STATUS" "$DURATION" "$DRIFT" >> "$APPLY_LOG"
  exit 4
fi

# Stage ONLY the files that this stash's diff touches. Per AGENTS.md "Note for
# Codex/GPT-5.5", we must NOT stage concurrent agents' modifications. The
# bundle's diff is the authoritative list of files this apply changed.
#
# Capture BOTH the `a/` (old) and `b/` (new) paths so renames register both
# the deletion and the addition. Use `git add -A --` to handle add/modify/
# delete uniformly (plain `git add` errors on missing files).
	if [[ ! -s "$DIFF_FILES_LIST" ]]; then
  echo "ERROR: no changed paths were found to stage" >&2
  printf '%s\t%s\t\t\tparse-failed\t\t%s\n' "$N" "$REF" "$DRIFT" >> "$APPLY_LOG"
  exit 6
fi

while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  # `-A` stages add/modify/delete uniformly. The `|| true` tolerates the case
  # where a rename's old path was already removed from the index by the apply
  # itself (`git apply --3way` updates the index for renames); in that case
  # `git add` reports "pathspec did not match" but the deletion is already
  # staged. We verify final staging via the diff-cached check below.
  git -C "$PROJECT_ABS" add -A -- "$f" 2>/dev/null || true
done < "$DIFF_FILES_LIST"

# Sanity check: verify every path in the bundle's diff is now reflected in the
# index (added/modified/deleted relative to HEAD). `git diff --cached
# --name-only` with no filter already covers all three cases, so a single
# call is sufficient. Paths that don't appear are typically no-ops or rename
# halves already handled by --3way; record but don't fail.
UNSTAGED_BUNDLE_PATHS="$WORKSPACE/.apply_${NPAD}_unstaged.list"
: > "$UNSTAGED_BUNDLE_PATHS"
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  if git -C "$PROJECT_ABS" diff --cached --name-only -- "$f" 2>/dev/null | grep -qFx "$f"; then
    : # path is staged (add / modify / delete vs. HEAD)
  else
    echo "$f" >> "$UNSTAGED_BUNDLE_PATHS"
  fi
done < "$DIFF_FILES_LIST"

# Guard: if NOTHING is staged, there's nothing to commit. Possible causes:
# (a) the stash's diff was equal to current HEAD (no-op apply); (b) the
# apply touched paths that were rejected; (c) bug in the awk extractor.
# `git commit` would fail with "nothing to commit" and set -e would abort
# unhelpfully — surface honestly instead.
if git -C "$PROJECT_ABS" diff --cached --quiet; then
  echo "WARNING: nothing staged after apply for stash@{$N}"
  if [[ -s "$UNSTAGED_BUNDLE_PATHS" ]]; then
    echo "  Bundle paths that didn't stage: $(wc -l < "$UNSTAGED_BUNDLE_PATHS")"
    echo "  See $UNSTAGED_BUNDLE_PATHS for the list."
  fi
  echo "  Likely a no-op stash (content already on HEAD) — re-classify in triage."
  printf '%s\t%s\t\t\tno-op-apply\t%s\t%s\n' "$N" "$REF" "$DURATION" "$DRIFT" >> "$APPLY_LOG"
  exit 7
fi

# Commit. Use printf with %s placeholders (NOT unquoted heredoc) so a stash
# message containing $(...) or backticks does NOT execute as shell code.
# Group the redirects (SC2129 hardening) so the file is opened once.
COMMIT_MSG_FILE="$WORKSPACE/commit_msg_${NPAD}.txt"
{
  printf 'recover content from stashed WIP (stash@{%s})\n\n' "$N"
  printf 'Originally drafted in stash@{%s} (sha %s, dated %s).\n' "$N" "$SHA" "$DATE"
  printf 'Stash message: %s\n\n' "$MSG"
  printf 'Recovered via: git apply --3way <bundle>/diffs/%s.diff\n' "$NPAD"
} > "$COMMIT_MSG_FILE"
git -C "$PROJECT_ABS" commit -F "$COMMIT_MSG_FILE"

NEW_SHA=$(git -C "$PROJECT_ABS" rev-parse HEAD)
# Honest file count: paths actually changed by the new commit, not the
# count of bundle-paths-extracted (which double-counts renames as 2).
N_FILES=$(git -C "$PROJECT_ABS" diff --name-only "${NEW_SHA}^..${NEW_SHA}" 2>/dev/null | wc -l)

printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
  "$N" "$REF" "$NEW_SHA" "$N_FILES" "$GATES_STATUS" "$DURATION" "$DRIFT" >> "$APPLY_LOG"

echo
echo "✓ Applied stash@{$N} as commit $NEW_SHA"
echo "  Files changed: $N_FILES"
echo "  Gates: $GATES_STATUS"
echo "  Duration: ${DURATION}s"
echo
echo "*** Note: the auto-generated commit message is generic. The keeper-applier"
echo "    subagent should rewrite it with a focused why-explanation BEFORE this"
echo "    commit reaches a PR. Use \`git commit --amend\` while still on the"
echo "    recovery branch and not yet pushed."
