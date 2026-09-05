#!/usr/bin/env bash
# drop-confirmed.sh — Phase 9: drop ONE stash with hard verbatim-confirm flag.
#
# Usage:
#   drop-confirmed.sh <project-path> <n> confirm=YES_DROP_<N>
#
# The third argument MUST exactly equal "confirm=YES_DROP_<N>" with N matching
# the stash index. This makes accidental invocation impossible (a typo or
# argument-order mistake fails the gate).
#
# This script never runs `git stash clear`. It drops exactly one stash, by ref.
# Backup ref at refs/stash-backup/<NNN> remains intact.

set -euo pipefail

PROJECT="${1:?Usage: drop-confirmed.sh <project-path> <n> confirm=YES_DROP_<N>}"
N="${2:?missing n}"
CONFIRM="${3:-}"

EXPECTED="confirm=YES_DROP_${N}"
if [[ "$CONFIRM" != "$EXPECTED" ]]; then
  echo "REFUSED: confirmation flag must be exactly \"$EXPECTED\"" >&2
  echo "Got: \"$CONFIRM\"" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=project-root.sh
. "$SCRIPT_DIR/project-root.sh"

PROJECT_ABS="$(resolve_project_root "$PROJECT")"
WORKSPACE="$PROJECT_ABS/.stash_janitor_workspace"
INVENTORY="$WORKSPACE/inventory.tsv"
CLEANUP_LOG="$WORKSPACE/cleanup_log.tsv"
NPAD=$(printf '%03d' "$N")

# Defense-in-depth: also require the plan-level authorization that the
# cleanup-conductor subagent records when the user types their verbatim
# authorization phrase (per AGENTS.md "Mandatory explicit plan"). The
# per-call `confirm=YES_DROP_<N>` flag protects against accidental
# invocation; this file protects against scripted invocation that bypasses
# the user-text gate. The user can override with CLEANUP_AUTHORIZATION_OVERRIDE_OK=1
# for direct-invocation use cases (e.g., the user manually drops one stash
# without going through the cleanup-conductor flow).
AUTH_FILE="$WORKSPACE/cleanup_authorization.txt"
AUTHORIZATION_RE='^[[:space:]]*yes[[:space:]]+i[[:space:]]+understand[[:space:]]+and[[:space:]]+want[[:space:]]+to[[:space:]]+drop[[:space:]]+all[[:space:]]+[0-9]+[[:space:]]+stash(es)?[[:space:]]+per[[:space:]]+the[[:space:]]+plan[[:space:]]+above[[:space:]]*$'
if [[ -z "${CLEANUP_AUTHORIZATION_OVERRIDE_OK:-}" ]]; then
  if [[ ! -s "$AUTH_FILE" ]]; then
    echo "REFUSED: cleanup_authorization.txt is missing or empty." >&2
    echo "  $AUTH_FILE" >&2
    echo "The cleanup-conductor subagent records the user's verbatim plan-level" >&2
    echo "authorization here before any drops happen. If you're invoking this script" >&2
    echo "directly without that orchestration, set CLEANUP_AUTHORIZATION_OVERRIDE_OK=1." >&2
    exit 7
  fi
  if ! grep -Eiq "$AUTHORIZATION_RE" "$AUTH_FILE"; then
    echo "REFUSED: cleanup_authorization.txt does not contain the exact cleanup authorization sentence." >&2
    echo "Expected a line exactly like: yes I understand and want to drop all <N> stashes per the plan above" >&2
    echo "If the user's authorization is in a different form, update $AUTH_FILE accordingly," >&2
    echo "or set CLEANUP_AUTHORIZATION_OVERRIDE_OK=1 to bypass this check." >&2
    exit 7
  fi
fi

# The inventory row is the stable identity for this drop. `stash@{N}` is only a
# stack position, and messages are not unique; verify both the live stash and
# backup ref point at the exact SHA captured before any cleanup.
if [[ ! -f "$INVENTORY" ]]; then
  echo "REFUSED: inventory not found at $INVENTORY." >&2
  echo "Run discover-stashes.sh and build-bundle.sh before dropping anything." >&2
  exit 3
fi
EXPECTED_SHA=$(awk -F'\t' -v n="$N" 'NR > 1 && $1 == n {print $3}' "$INVENTORY")
if [[ -z "$EXPECTED_SHA" ]]; then
  echo "REFUSED: inventory.tsv has no row for n=$N." >&2
  echo "Re-run inventory and re-build cleanup plan." >&2
  exit 3
fi

BACKUP_SHA=$(git -C "$PROJECT_ABS" rev-parse --verify --quiet "refs/stash-backup/$NPAD^{commit}" 2>/dev/null || true)
if [[ -z "$BACKUP_SHA" ]]; then
  echo "REFUSED: backup ref refs/stash-backup/$NPAD does not exist." >&2
  echo "Without the backup ref, this drop is not reversible. Halting." >&2
  exit 3
fi
if [[ "$BACKUP_SHA" != "$EXPECTED_SHA" ]]; then
  echo "REFUSED: backup ref refs/stash-backup/$NPAD points at the wrong stash." >&2
  echo "  Expected SHA from inventory: $EXPECTED_SHA" >&2
  echo "  Backup ref currently:        $BACKUP_SHA" >&2
  echo "Without the matching backup ref, this drop is not reversible. Halting." >&2
  exit 3
fi

LIVE_SHA=$(git -C "$PROJECT_ABS" rev-parse --verify --quiet "stash@{$N}^{commit}" 2>/dev/null || true)
if [[ -z "$LIVE_SHA" ]]; then
  echo "REFUSED: stash@{$N} no longer exists (already dropped by another process?). Halting." >&2
  exit 4
fi
if [[ "$LIVE_SHA" != "$EXPECTED_SHA" ]]; then
  echo "REFUSED: stash list has shifted." >&2
  echo "  Expected stash@{$N} SHA: $EXPECTED_SHA" >&2
  echo "  Found    stash@{$N} SHA: $LIVE_SHA" >&2
  echo "Re-run inventory and re-build cleanup plan." >&2
  exit 5
fi

# Resolve the current ref (the message must match what we expect).
# The inventory's `message` column has git's "On <branch>: " / "WIP on <branch>: <sha> "
# prefix stripped; we strip the same prefix from the live message before comparing.
strip_git_prefix() {
  printf '%s' "$1" | sed -E 's/^WIP on [^:]+: [0-9a-f]+ //; s/^On [^:]+: //'
}
EXPECTED_MSG=$(awk -F'\t' -v n="$N" 'NR > 1 && $1 == n {print $7}' "$INVENTORY")
# Capture EVERYTHING after the first '|' so messages containing '|' aren't
# truncated. (awk -F'|' ... print $2 only emits between first and second '|'.)
ACTUAL_RAW=$(git -C "$PROJECT_ABS" stash list --format='%gd|%s' \
              | grep -F "stash@{$N}|" \
              | head -1 \
              | cut -d'|' -f2-)
ACTUAL_MSG=$(strip_git_prefix "$ACTUAL_RAW")

# Sanity check (don't be strict if there's no expected message — only error
# if the messages exist and disagree)
if [[ -n "$EXPECTED_MSG" && "$EXPECTED_MSG" != "$ACTUAL_MSG" ]]; then
  echo "REFUSED: stash list has shifted." >&2
  echo "  Expected stash@{$N}: $EXPECTED_MSG" >&2
  echo "  Found    stash@{$N}: $ACTUAL_MSG" >&2
  echo "Re-run inventory and re-build cleanup plan." >&2
  exit 5
fi

# Initialize log if absent
if [[ ! -f "$CLEANUP_LOG" ]]; then
  printf 'n\tpre_drop_index\tref_dropped\tverdict\ttimestamp_utc\tmessage\n' > "$CLEANUP_LOG"
fi

# Determine the CLEANUP verdict (which bucket this drop belongs to in the
# Phase 9 ordering: garbage → superseded → novel-but-stale → applied-keeper).
# This is NOT the same as the triage verdict for stashes that were applied:
# a "novel-and-accretive" stash that was successfully applied in Phase 6 must
# be dropped in the "applied-keeper" bucket (last), not the "novel-and-accretive"
# bucket (which doesn't exist in Phase 9's order). polish-bar-check P6 enforces
# this ordering using the cleanup_log's verdict column.
VERDICT="unknown"
if [[ -f "$WORKSPACE/triage.tsv" ]]; then
  VERDICT=$(awk -F'\t' -v n="$N" 'NR > 1 && $1 == n {print $2}' "$WORKSPACE/triage.tsv")
  VERDICT=${VERDICT:-unknown}
fi
APPLY_LOG="$WORKSPACE/apply_log.tsv"
if [[ -f "$APPLY_LOG" ]] && awk -F'\t' -v n="$N" \
     'NR > 1 && $1 == n && $3 != "" && $5 == "passed" {found=1} END {exit !found}' \
     "$APPLY_LOG"; then
  # This stash was successfully applied (apply_log has a non-empty new_commit_sha
  # and gates_status=passed). Its cleanup-bucket is "applied-keeper", regardless
  # of the original triage verdict.
  VERDICT=applied-keeper
fi

# Refuse to drop a stash whose effective verdict isn't one of the documented
# cleanup buckets. Without this check, drop-confirmed.sh will happily drop a
# `novel-and-accretive` stash that was NEVER applied as a keeper — losing the
# recovery payload from the live stash list (it's still in the bundle and
# backup ref, so the LAYERED safety story holds, but this still represents a
# silent contract violation: the user authorized "drop garbage/superseded/
# stale/applied-keeper", not "drop unapplied novel work"). Also catches the
# `unknown` verdict, which means triage didn't classify the stash and the
# user must resolve it before any drop. Override with
# DROP_VERDICT_OVERRIDE_OK=1 if the user explicitly authorizes a non-bucket
# drop (e.g., they're cleaning up a known-redundant novel stash by hand).
case "$VERDICT" in
  garbage|superseded|superseded-by-newer-stash|novel-but-stale|applied-keeper) ;;
  *)
    if [[ -z "${DROP_VERDICT_OVERRIDE_OK:-}" ]]; then
      echo "REFUSED: stash@{$N} verdict='$VERDICT' is not a cleanup-bucket verdict." >&2
      echo "Allowed verdicts for drop: garbage, superseded, superseded-by-newer-stash," >&2
      echo "novel-but-stale, applied-keeper." >&2
      echo "" >&2
      if [[ "$VERDICT" == "novel-and-accretive" ]]; then
        echo "n=$N is classified novel-and-accretive but apply_log shows no successful apply." >&2
        echo "Apply it first via apply-keeper.sh, OR re-classify it in triage.tsv if it's actually" >&2
        echo "redundant (then verdict will become superseded/garbage and drop is allowed)." >&2
      elif [[ "$VERDICT" == "unknown" ]]; then
        echo "n=$N triage verdict is 'unknown' — the user must resolve it before any drop." >&2
      fi
      echo "Or set DROP_VERDICT_OVERRIDE_OK=1 to authorize a non-bucket drop explicitly." >&2
      exit 13
    fi
    ;;
esac

# Restate the verbatim command before executing
echo "About to run: git stash drop stash@{$N}"
echo "  (n=$N: \"$ACTUAL_MSG\", verdict=$VERDICT)"
echo "  Backup ref refs/stash-backup/$NPAD will remain intact."
echo

# Execute. Capture errors so a race-induced failure (the stash got dropped
# between our line-49 check and now) leaves a row in cleanup_log instead of
# aborting the script with `set -e` and no audit trail.
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
DROP_ERR_FILE="$WORKSPACE/.drop_${NPAD}_err"
if ! git -C "$PROJECT_ABS" stash drop "stash@{$N}" 2>"$DROP_ERR_FILE"; then
  drop_err=$(cat "$DROP_ERR_FILE" 2>/dev/null || echo "<no error captured>")
  echo "ERROR: git stash drop failed for stash@{$N}: $drop_err" >&2
  printf '%s\t%s\t%s\tdrop-failed: %s\t%s\t%s\n' \
    "$N" "stash@{$N}" "refs/stash-backup/$NPAD" \
    "$(printf '%s' "$drop_err" | tr '\t\n' '  ')" \
    "$TIMESTAMP" "$ACTUAL_MSG" \
    >> "$CLEANUP_LOG"
  echo "Backup ref refs/stash-backup/$NPAD remains intact; recovery still possible." >&2
  exit 6
fi

# Log success
printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
  "$N" "stash@{$N}" "refs/stash-backup/$NPAD" "$VERDICT" "$TIMESTAMP" "$ACTUAL_MSG" \
  >> "$CLEANUP_LOG"

echo "✓ Dropped stash@{$N}; backup ref refs/stash-backup/$NPAD intact."
