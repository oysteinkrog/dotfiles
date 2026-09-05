#!/usr/bin/env bash
# convergence-check.sh — Compute kill_rate vs add_rate for Phase 4, audit clean rounds for Phase 6/7.
#
# Usage:
#   convergence-check.sh --phase=4 [--workspace=<path>] [--prev-sha=<SHA>] [--round=N]
#   convergence-check.sh --phase=6 [--workspace=<path>]
#   convergence-check.sh --phase=7 [--workspace=<path>]
#
# Phase 4 boundary selection (in priority order):
#   1. --prev-sha=<SHA> if explicitly provided
#   2. SHA stored at .brenner_workspace/phase_4_round_<N-1>_end_sha when --round=N is provided
#   3. Oldest commit touching .beads/ in the last 2 hours (heuristic for "this round started here")
#   4. HEAD~1 fallback when only one .beads/ commit exists
#
# Exit code 0: converged. Exit code 1: not yet converged.

set -uo pipefail

WORKSPACE="."
PHASE=""
ROUND=""
PREV_SHA_ARG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --phase=*) PHASE="${1#*=}" ;;
    --workspace=*) WORKSPACE="${1#*=}" ;;
    --round=*) ROUND="${1#*=}" ;;
    --prev-sha=*) PREV_SHA_ARG="${1#*=}" ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
  shift
done

if [ -z "$PHASE" ]; then
  echo "Usage: convergence-check.sh --phase=<4|6|7> [--workspace=<path>] [--prev-sha=<SHA>] [--round=N]" >&2
  exit 2
fi

verify_commit() {
  local sha="$1"
  if ! (cd "$WORKSPACE" && git rev-parse --verify --quiet "$sha^{commit}" >/dev/null); then
    echo "Invalid git commit boundary: $sha" >&2
    exit 2
  fi
}

case "$PHASE" in
  4)
    # kill_rate ≥ add_rate for the round
    # Resolve PREV_SHA in priority order (see header).
    CURRENT_SHA=$(cd "$WORKSPACE" && git log -1 --format=%H -- .beads/ 2>/dev/null || echo "")

    if [ -z "$CURRENT_SHA" ]; then
      echo "Phase 4: no commits to .beads/ yet; not converged"
      exit 1
    fi

    PREV_SHA=""
    if [ -n "$PREV_SHA_ARG" ]; then
      PREV_SHA="$PREV_SHA_ARG"
    elif [ -n "$ROUND" ] && [ "$ROUND" -gt 1 ] 2>/dev/null; then
      ROUND_FILE="$WORKSPACE/.brenner_workspace/phase_4_round_$((ROUND - 1))_end_sha"
      [ -f "$ROUND_FILE" ] && PREV_SHA=$(cat "$ROUND_FILE")
    fi
    if [ -z "$PREV_SHA" ]; then
      PREV_SHA=$(cd "$WORKSPACE" && git log --since="2 hours ago" --format=%H -- .beads/ 2>/dev/null | tail -1 || echo "")
    fi
    if [ -z "$PREV_SHA" ] || [ "$PREV_SHA" = "$CURRENT_SHA" ]; then
      # Fall back to HEAD~1 of .beads/ history
      PREV_SHA=$(cd "$WORKSPACE" && git log -2 --format=%H -- .beads/ 2>/dev/null | tail -1 || echo "")
    fi
    if [ -z "$PREV_SHA" ] || [ "$PREV_SHA" = "$CURRENT_SHA" ]; then
      echo "Phase 4: only one commit to .beads/ (no prior boundary to diff against); not converged"
      exit 1
    fi
    verify_commit "$PREV_SHA"

    # Count bead state changes since PREV_SHA. Heuristic: scan added lines for state-change markers.
    # The bead JSONL field shape may vary by br version; we match permissively.
    if ! DIFF_OUT=$(cd "$WORKSPACE" && git diff "$PREV_SHA" "$CURRENT_SHA" -- .beads/ 2>&1); then
      echo "Phase 4: failed to diff .beads/ between $PREV_SHA and $CURRENT_SHA" >&2
      printf '%s\n' "$DIFF_OUT" >&2
      exit 2
    fi
    KILLED=$(echo "$DIFF_OUT" | grep -cE '^\+.*state["[:space:]]*[:=]["[:space:]]*refuted' || true)
    SUPERSEDED=$(echo "$DIFF_OUT" | grep -cE '^\+.*state["[:space:]]*[:=]["[:space:]]*superseded' || true)
    # A state transition on an existing hypothesis appears as a removed JSONL row
    # plus an added JSONL row. Do not count the added refuted/superseded row as
    # a newly introduced hypothesis, or a kill can inflate both sides.
    NEW_H=$(printf '%s\n' "$DIFF_OUT" \
      | awk '/^\+.*"label[s]?".*hypothesis/ && !/state["[:space:]]*[:=]["[:space:]]*(refuted|superseded)/ { count++ } END { print count + 0 }')
    # Strip non-numeric in case grep -c output is empty.
    KILLED=${KILLED:-0}; SUPERSEDED=${SUPERSEDED:-0}; NEW_H=${NEW_H:-0}

    KILL_RATE=$((KILLED + SUPERSEDED))
    ADD_RATE=$NEW_H

    echo "Phase 4 convergence check:"
    echo "  Killed: $KILLED  Superseded: $SUPERSEDED  New hypotheses: $NEW_H"
    echo "  kill_rate=$KILL_RATE  add_rate=$ADD_RATE"

    if [ "$KILL_RATE" -ge "$ADD_RATE" ]; then
      echo "  → CONVERGED"
      exit 0
    else
      echo "  → not converged"
      exit 1
    fi
    ;;

  6)
    # Two consecutive trivial passes on meta_synthesis.md + disagreement_register.md
    if [ ! -f "$WORKSPACE/distillations/meta_synthesis.md" ] || [ ! -f "$WORKSPACE/distillations/disagreement_register.md" ]; then
      echo "Phase 6 artifacts missing; not converged"
      exit 1
    fi

    # Get last 2 commits touching meta_synthesis.md
    mapfile -t COMMITS < <(
      cd "$WORKSPACE" \
        && git log --format=%H -- distillations/meta_synthesis.md distillations/disagreement_register.md \
        | sed -n '1,3p'
    )

    if [ ${#COMMITS[@]} -lt 3 ]; then
      echo "Fewer than 2 passes; not yet converged"
      exit 1
    fi

    # Trivial = only typo/whitespace/wrap diffs. NB: the `grep -c ... || echo 0`
    # idiom would emit "0\n0" when the diff is empty (grep -c outputs "0" + exits
    # 1 on no matches, then the fallback adds a second "0"), corrupting the `-lt`
    # comparison below. Suppress the exit code without doubling the output.
    DIFF1=$(cd "$WORKSPACE" && git diff "${COMMITS[1]}" "${COMMITS[0]}" -- distillations/ | grep -cE '^[+-][^+-]') || true
    DIFF1=${DIFF1:-0}
    DIFF2=$(cd "$WORKSPACE" && git diff "${COMMITS[2]}" "${COMMITS[1]}" -- distillations/ | grep -cE '^[+-][^+-]') || true
    DIFF2=${DIFF2:-0}

    echo "Phase 6 convergence check:"
    echo "  Diff (last pass): $DIFF1 lines"
    echo "  Diff (prev pass): $DIFF2 lines"

    # Heuristic: <5 changed lines = trivial
    if [ "$DIFF1" -lt 5 ] && [ "$DIFF2" -lt 5 ]; then
      echo "  → CONVERGED"
      exit 0
    else
      echo "  → not converged"
      exit 1
    fi
    ;;

  7)
    # Two consecutive trio-rounds with no critical/high audit findings
    CRITICAL_HIGH_OPEN=$(cd "$WORKSPACE" && br list --label=audit-finding --status=open --json 2>/dev/null | \
      jq '[.issues[]? | select(((.description // "") | contains("severity: critical")) or ((.description // "") | contains("severity: high")))] | length' 2>/dev/null || echo 0)

    echo "Phase 7 convergence check:"
    echo "  Open critical+high findings: $CRITICAL_HIGH_OPEN"

    if [ "$CRITICAL_HIGH_OPEN" -gt 0 ]; then
      echo "  → not converged (critical/high findings open)"
      exit 1
    fi

    # Compute "2 hours ago" timestamp portably (GNU date, BSD date, Python fallback).
    TWO_HOURS_AGO=$(date -u -d '2 hours ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
      || date -u -v-2H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
      || python3 -c "from datetime import datetime, timedelta, timezone; print((datetime.now(timezone.utc) - timedelta(hours=2)).strftime('%Y-%m-%dT%H:%M:%SZ'))" 2>/dev/null \
      || echo "1970-01-01T00:00:00Z")

    # Now check trivial-only rounds: count audit findings created in last 2 hours
    NEW_FINDINGS=$(cd "$WORKSPACE" && br list --label=audit-finding --json 2>/dev/null | \
      jq --arg t "$TWO_HOURS_AGO" '[.issues[]? | select((.created_at // "1970-01-01") >= $t)] | length' 2>/dev/null || echo 0)
    NEW_FINDINGS=${NEW_FINDINGS:-0}

    if [ "$NEW_FINDINGS" -le 2 ]; then
      echo "  → CONVERGED (last 2 rounds: ≤2 trivial findings)"
      exit 0
    else
      echo "  → not converged (last 2 rounds: $NEW_FINDINGS findings)"
      exit 1
    fi
    ;;

  *)
    echo "Unknown phase: $PHASE" >&2
    exit 2
    ;;
esac
