#!/usr/bin/env bash
# phase-readiness.sh — Am I ready to exit phase X?
#
# Checks the exit-gate criteria for the current phase per references/PHASES.md.
# Returns 0 if ready; 1 if not.
#
# Usage: phase-readiness.sh --phase=<N> [--workspace=<path>] [--session=<name>] [--mark-complete]
#
# With --mark-complete: when readiness check passes (and only then), writes
# .brenner_workspace/phase_<N>_complete.flag with an ISO-8601 UTC timestamp.
# This is the canonical mechanism for advancing the session-level phase counter
# that downstream scripts (tick.sh, drift-check.sh, audit-bead-invariants.sh,
# brennerbot-doctor.sh, dump-session-report.sh, liveness-check.sh, emit-quickref.sh,
# export-timeline.sh) all read from. Idempotent — re-running on an already-marked
# phase leaves the existing flag untouched.

set -uo pipefail

PHASE=""
WORKSPACE="."
MARK_COMPLETE="false"
SESSION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --phase=*) PHASE="${1#*=}" ;;
    --workspace=*) WORKSPACE="${1#*=}" ;;
    --session=*) SESSION="${1#*=}" ;;
    --mark-complete) MARK_COMPLETE="true" ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
  shift
done

if [ -z "$PHASE" ]; then
  echo "Usage: phase-readiness.sh --phase=<N> [--workspace=<path>] [--session=<name>] [--mark-complete]" >&2
  exit 2
fi

if ! SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; then
  echo "script directory not accessible" >&2
  exit 1
fi

WORKSPACE_INPUT="$WORKSPACE"
if ! WORKSPACE="$(cd "$WORKSPACE_INPUT" 2>/dev/null && pwd)"; then
  echo "workspace not accessible: $WORKSPACE_INPUT" >&2
  exit 1
fi

cd "$WORKSPACE" || { echo "workspace not accessible: $WORKSPACE" >&2; exit 1; }

if [ -z "$SESSION" ] && [ -f .brenner_workspace/phase0_scope_decision.md ]; then
  SESSION=$(grep -m1 -oE 'RS-[0-9]{8}-[a-z0-9-]+' .brenner_workspace/phase0_scope_decision.md 2>/dev/null || true)
fi

ALL_OK=1
ok() { printf '  ✓ %s\n' "$*"; }
fail() { printf '  ✗ %s\n' "$*"; ALL_OK=0; }
need_cmd() {
  local cmd="$1" purpose="$2"
  if command -v "$cmd" >/dev/null 2>&1; then
    return 0
  fi
  fail "$cmd not found; cannot verify $purpose"
  return 1
}
need_helper() {
  local helper="$1" purpose="$2"
  if [ -x "$SCRIPT_DIR/$helper" ]; then
    return 0
  fi
  fail "$helper not executable; cannot verify $purpose"
  return 1
}

case "$PHASE" in
  1)
    echo "Phase 1 exit gate:"
    if [ -f intake/question_of_record.md ]; then
      ok "intake/question_of_record.md exists"
    else
      fail "intake/question_of_record.md MISSING"
    fi
    if [ -f intake/question_of_record.md ]; then
      FALSIFIER=$(awk '
        /^## Falsifier/ { flag=1; next }
        flag && /^## / { flag=0 }
        flag && /[A-Za-z]/ { count++ }
        END { print count+0 }
      ' intake/question_of_record.md 2>/dev/null)
      if [ "$FALSIFIER" -gt 0 ]; then ok "Falsifier section non-empty"; else fail "Falsifier section EMPTY"; fi
    fi
    if [ -f corpus/corpus_index.md ]; then
      ok "corpus/corpus_index.md exists"
    else
      fail "corpus/corpus_index.md MISSING"
    fi
    if need_cmd br "Q-001 bead" && need_cmd jq "Q-001 bead JSON"; then
      Q1=$(br list --label=q-of-record --json 2>/dev/null | jq '.issues | length' 2>/dev/null || echo 0)
      if [ "$Q1" -ge 1 ]; then
        ok "Q-001 bead present"
      else
        fail "Q-001 bead MISSING"
      fi
    fi
    ;;

  2)
    echo "Phase 2 exit gate:"
    if need_cmd ntm "Phase 2 pane roster" && need_cmd jq "Phase 2 pane roster JSON"; then
      if [ -n "$SESSION" ]; then
        PANES=$(ntm --robot-snapshot 2>/dev/null | jq --arg s "$SESSION" '[.sessions[]? | select(.name == $s) | .panes[]?] | length' 2>/dev/null || echo 0)
        if [ "$PANES" -ge 1 ]; then
          ok "ntm shows $PANES panes for session $SESSION"
        else
          fail "ntm shows 0 panes for session $SESSION"
        fi
      else
        PANES=$(ntm --robot-snapshot 2>/dev/null | jq '[.sessions[]?.panes[]?] | length' 2>/dev/null || echo 0)
        if [ "$PANES" -ge 1 ]; then
          ok "ntm shows $PANES panes (no session id available to scope check)"
        else
          fail "ntm shows 0 panes"
        fi
      fi
    fi
    ;;

  3)
    echo "Phase 3 exit gate:"
    if need_helper audit-bead-invariants.sh "phase3_exit invariants"; then
      if "$SCRIPT_DIR/audit-bead-invariants.sh" --workspace="$WORKSPACE" --check=phase3_exit 2>&1 | grep -q "Audit clean"; then
        ok "phase3_exit invariants clean"
      else
        fail "phase3_exit invariants violated"
      fi
    fi
    ;;

  4)
    echo "Phase 4 exit gate:"
    if need_helper convergence-check.sh "Phase 4 convergence"; then
      if "$SCRIPT_DIR/convergence-check.sh" --phase=4 --workspace="$WORKSPACE" 2>&1 | grep -q "CONVERGED"; then
        ok "Phase 4 convergence: kill_rate ≥ add_rate"
      else
        fail "Phase 4 not converged"
      fi
    fi
    if need_helper audit-bead-invariants.sh "phase4 invariants"; then
      if "$SCRIPT_DIR/audit-bead-invariants.sh" --workspace="$WORKSPACE" --check=phase4_round 2>&1 | grep -q "Audit clean"; then
        ok "phase4 invariants clean"
      else
        fail "phase4 invariants violated"
      fi
    fi
    ;;

  5)
    echo "Phase 5 exit gate:"
    if need_cmd br "Phase 5 hypothesis states" && need_cmd jq "Phase 5 hypothesis state JSON"; then
      # Phase 5 exits when every H has transitioned out of `state: active` and
      # `state: proposed` into a finalized state (confirmed | refuted | superseded
      # | deferred). The check inspects the description-level `state:` field, NOT
      # the bead's lifecycle `--status` (which stays `open` until session-end
      # `br close`). Counting bead-level open status here was the previous bug —
      # it made Phase 5 readiness impossible to pass.
      UNFINALIZED=$(br list --label=hypothesis --json 2>/dev/null \
        | jq '[.issues[]? | select((.description // "") | test("(^|\\n)state:[[:space:]]*(active|proposed)([[:space:]]|$)"))] | length' 2>/dev/null) \
        || UNFINALIZED=0
      UNFINALIZED=${UNFINALIZED:-0}
      if [ "$UNFINALIZED" -le 0 ]; then
        ok "no H in state: active or state: proposed (all hypotheses finalized to confirmed/refuted/superseded/deferred)"
      else
        fail "$UNFINALIZED hypothesis(es) still in state: active/proposed — Phase 5 cross-exam not complete"
      fi
    fi
    ;;

  6)
    echo "Phase 6 exit gate:"
    if [ -f distillations/meta_synthesis.md ]; then
      ok "meta_synthesis.md exists"
    else
      fail "meta_synthesis.md MISSING"
    fi
    if [ -f distillations/disagreement_register.md ]; then
      ok "disagreement_register.md exists"
    else
      fail "disagreement_register.md MISSING"
    fi
    if need_helper disagreement-register-lint.sh "disagreement-register lint"; then
      if "$SCRIPT_DIR/disagreement-register-lint.sh" --workspace="$WORKSPACE" 2>&1 | grep -q "lint clean"; then
        ok "disagreement-register lint clean"
      else
        fail "disagreement-register lint failed"
      fi
    fi
    if need_helper convergence-check.sh "Phase 6 convergence"; then
      if "$SCRIPT_DIR/convergence-check.sh" --phase=6 --workspace="$WORKSPACE" 2>&1 | grep -q "CONVERGED"; then
        ok "Phase 6 convergence: 2 consecutive trivial meta-synthesis passes"
      else
        fail "Phase 6 not converged (requires two consecutive trivial meta-synthesis passes)"
      fi
    fi
    ;;

  7)
    echo "Phase 7 exit gate:"
    if need_helper convergence-check.sh "Phase 7 convergence"; then
      if "$SCRIPT_DIR/convergence-check.sh" --phase=7 --workspace="$WORKSPACE" 2>&1 | grep -q "CONVERGED"; then
        ok "Phase 7 convergence: 2 consecutive trivial trio-rounds"
      else
        fail "Phase 7 not converged"
      fi
    fi
    if need_helper run-ubs-on-deliverables.sh "deliverable UBS gate"; then
      if "$SCRIPT_DIR/run-ubs-on-deliverables.sh" --workspace="$WORKSPACE" >/dev/null 2>&1; then
        ok "ubs clean on deliverables"
      else
        fail "ubs reports issues — F-703 hard-block"
      fi
    fi
    ;;

  8)
    echo "Phase 8 exit gate:"
    if [ -f deliverables/RESUME.md ]; then
      ok "RESUME.md exists"
    else
      fail "RESUME.md MISSING"
    fi
    if [ -f deliverables/RESUME.md ]; then
      if need_helper resume-session.sh "RESUME.md hash verification"; then
        if "$SCRIPT_DIR/resume-session.sh" --dry-run --resume "$WORKSPACE/deliverables/RESUME.md" 2>&1 | grep -q "verification: OK"; then
          ok "RESUME.md hash-verifies"
        else
          fail "RESUME.md hash-verification failed"
        fi
      fi
    fi
    if need_cmd git "Phase 8 clean git status"; then
      if GIT_STATUS_OUTPUT=$(cd "$WORKSPACE" && git status --short 2>/dev/null); then
        if [ -n "$GIT_STATUS_OUTPUT" ]; then
          GIT_STATUS=$(printf '%s\n' "$GIT_STATUS_OUTPUT" | wc -l | tr -d ' ')
        else
          GIT_STATUS=0
        fi
        if [ "$GIT_STATUS" = "0" ]; then
          ok "git status clean"
        else
          fail "git has $GIT_STATUS uncommitted changes"
        fi
      else
        fail "git status failed; workspace is not a git repo or git metadata is inaccessible"
      fi
    fi
    ;;

  9)
    echo "Phase 9 exit gate:"
    if [ -f deliverables/HANDBACK.md ]; then
      ok "HANDBACK.md exists"
    else
      fail "HANDBACK.md MISSING"
    fi
    if [ -f deliverables/HANDBACK.md ]; then
      LINES=$(wc -l < deliverables/HANDBACK.md)
      if [ "$LINES" -le 80 ]; then
        ok "HANDBACK.md ≤80 lines ($LINES)"
      else
        fail "HANDBACK.md is $LINES lines, must be ≤80"
      fi
    fi
    if need_helper audit-bead-invariants.sh "handback unresolved-thread tags"; then
      if "$SCRIPT_DIR/audit-bead-invariants.sh" --workspace="$WORKSPACE" --check=handback_open_thread_tags 2>&1 | grep -q "Audit clean"; then
        ok "unresolved-thread next-action tags present"
      else
        fail "unresolved threads missing next-action: tags"
      fi
    fi
    ;;

  10)
    echo "Phase 10 exit gate:"
    if [ -f deliverables/DRIFT-CHECK.md ]; then
      ok "DRIFT-CHECK.md exists"
      # Check Lessons section has ≥1 non-placeholder L-NNN entry
      # (lessons live in DRIFT-CHECK.md per the Phase 10 protocol; the operator separately commits
      # corresponding updates to the skill's references/, which lives outside the workspace.)
      # Count L-NNN lesson entries inside the "## Lessons" section, bounded by the next
      # major heading or '---' separator. The previous awk range pattern was buggy because
      # the start pattern matched the end pattern on the same line; using state-flag awk
      # to walk lines instead.
      LESSONS=$(awk '
        /^## .*[Ll]essons/ { flag=1; next }
        flag && /^### L-[0-9]+/ { count++ }
        flag && /^---/ { flag=0 }
        flag && /^## / { flag=0 }
        END { print count+0 }
      ' deliverables/DRIFT-CHECK.md 2>/dev/null)
      LESSONS=${LESSONS:-0}
      if [ "$LESSONS" -ge 1 ]; then
        ok "DRIFT-CHECK.md has $LESSONS lesson entry/entries"
      else
        fail "DRIFT-CHECK.md has 0 lesson entries (L-NNN format) — F-1003"
      fi
      # Verify VERDICT line at top
      if head -3 deliverables/DRIFT-CHECK.md 2>/dev/null | grep -qE '^DRIFT VERDICT:'; then
        ok "DRIFT VERDICT line present"
      else
        fail "DRIFT-CHECK.md missing 'DRIFT VERDICT:' line at top"
      fi
    else
      fail "DRIFT-CHECK.md MISSING"
    fi
    ;;

  *)
    echo "Unknown phase: $PHASE" >&2
    exit 2
    ;;
esac

if [ "$ALL_OK" = "1" ]; then
  echo ""
  echo "Phase $PHASE: READY TO EXIT"
  if [ "$MARK_COMPLETE" = "true" ]; then
    FLAG=".brenner_workspace/phase_${PHASE}_complete.flag"
    if [ -f "$FLAG" ]; then
      echo "  (flag $FLAG already exists; left untouched)"
    else
      mkdir -p .brenner_workspace
      echo "Phase $PHASE complete at $(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$FLAG"
      echo "  ✓ wrote $FLAG"
    fi
  fi
  exit 0
else
  echo ""
  echo "Phase $PHASE: NOT READY (see ✗ items above)"
  if [ "$MARK_COMPLETE" = "true" ]; then
    echo "  (--mark-complete ignored: readiness check failed)"
  fi
  exit 1
fi
