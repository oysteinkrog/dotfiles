#!/usr/bin/env bash
# resume-session.sh — Verify RESUME.md, restore ntm checkpoint, re-attach mail, dispatch MO-resume.md.
#
# Usage:
#   resume-session.sh --resume <RESUME.md path>           # full resume
#   resume-session.sh --dry-run --resume <RESUME.md path> # validate only

set -euo pipefail

# Portable sha256 wrapper (GNU `sha256sum` vs macOS/BSD `shasum -a 256`).
sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$@"
  else
    shasum -a 256 "$@"
  fi
}

DRY_RUN="false"
RESUME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN="true" ;;
    --resume=*) RESUME="${1#*=}" ;;
    --resume)
      # Don't bare-reference $2 under `set -u` — the script crashes uninformatively
      # when the user passes `--resume` with no following value. Probe via ${2:-}
      # so an unset $2 expands to empty, then emit a clean diagnostic.
      if [ -z "${2:-}" ]; then
        echo "Error: --resume requires a value (path to RESUME.md)" >&2
        exit 2
      fi
      RESUME="$2"; shift
      ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
  shift
done

if [ -z "$RESUME" ]; then
  echo "Usage: resume-session.sh [--dry-run] --resume <RESUME.md path>" >&2
  exit 2
fi

if [ ! -f "$RESUME" ]; then
  echo "Error: RESUME.md not found at $RESUME" >&2
  exit 1
fi

WORKSPACE="$(cd "$(dirname "$RESUME")/.." && pwd)"

# Parse RESUME.md (expects YAML body inside ```yaml fenced block)
parse_field() {
  local field="$1"
  # Crude: extract `<field>: <value>` from the YAML body
  awk -v f="$field" '/^'"$field"': / { sub(/^'"$field"': */, ""); print; exit }' "$RESUME" | tr -d '"' | head -c 200
}

SESSION_ID=$(parse_field session_id)
LAST_PHASE=$(parse_field last_phase_completed)
MODE=$(parse_field mode_to_resume)
QOR_HASH=$(parse_field question_of_record_hash)
QOR_PATH=$(parse_field question_of_record_path)
CORPUS_HASH=$(parse_field corpus_index_hash)
CORPUS_PATH=$(parse_field corpus_index_path)
DISAGREEMENT_HASH=$(parse_field disagreement_register_hash)
BEADS_HEAD=$(parse_field beads_head_sha)
NTM_ARCHIVE=$(parse_field ntm_checkpoint_archive)
NTM_ID=$(parse_field ntm_checkpoint_id)

ERRORS=""
verify_hash() {
  local file="$1" expected="$2" name="$3"
  if [ -z "$expected" ] || [ -z "$file" ]; then
    ERRORS="$ERRORS"$'\n'"  - $name: hash or path empty in RESUME.md"
    return
  fi
  # Resolve file: if absolute, use as-is; if relative, prepend WORKSPACE.
  local fullpath
  case "$file" in
    /*) fullpath="$file" ;;
    *)  fullpath="$WORKSPACE/$file" ;;
  esac
  local actual
  actual=$(sha256 "$fullpath" 2>/dev/null | awk '{print $1}')
  if [ -z "$actual" ]; then
    ERRORS="$ERRORS"$'\n'"  - $name: file $fullpath not found"
  elif [ "$actual" != "$expected" ]; then
    ERRORS="$ERRORS"$'\n'"  - $name: hash mismatch (expected $expected; actual $actual)"
  fi
}

verify_hash "$QOR_PATH" "$QOR_HASH" "question_of_record_hash"
verify_hash "$CORPUS_PATH" "$CORPUS_HASH" "corpus_index_hash"
verify_hash "distillations/disagreement_register.md" "$DISAGREEMENT_HASH" "disagreement_register_hash"

# Verify beads head reachable. NB: this branch was previously concatenating a
# literal "\n" two-char sequence (instead of $'\n'), which then printed garbled
# in the report below — the other ERRORS appenders correctly use $'\n'.
if [ -n "$BEADS_HEAD" ]; then
  if ! ( cd "$WORKSPACE" && git cat-file -e "$BEADS_HEAD" 2>/dev/null ); then
    ERRORS="$ERRORS"$'\n'"  - beads_head_sha $BEADS_HEAD not reachable in git"
  fi
fi

# Verify ntm checkpoint archive (warn if missing; don't abort)
if [ -n "$NTM_ARCHIVE" ] && [ ! -f "$WORKSPACE/$NTM_ARCHIVE" ]; then
  echo "Warning: ntm checkpoint archive $NTM_ARCHIVE missing — will respawn from roster" >&2
fi

# Report
if [ -n "$ERRORS" ]; then
  echo "RESUME.md verification failed:"
  printf '%s\n' "$ERRORS"
  exit 1
fi

echo "RESUME.md verification: OK"
echo "  Session: $SESSION_ID"
echo "  Last completed phase: $LAST_PHASE"
echo "  Mode to resume: $MODE"

if [ "$DRY_RUN" = "true" ]; then
  echo ""
  echo "Dry-run only; no actions taken."
  exit 0
fi

# Real resume:
echo ""
echo "Restoring ntm checkpoint..."
if [ -f "$WORKSPACE/$NTM_ARCHIVE" ]; then
  ntm checkpoint restore "$SESSION_ID" "$NTM_ID" || {
    echo "Warning: checkpoint restore failed; falling back to fresh spawn" >&2
  }
else
  echo "Spawning fresh panes from RESUME.md roster (checkpoint missing)..."
  # Extract roster from RESUME.md and spawn (simplified — production would parse YAML properly)
  echo "  Operator: review RESUME.md.roster and spawn panes manually if needed."
fi

echo ""
echo "Re-registering Agent Mail identities..."
"$(dirname "$0")/register-mail-identities.sh" --project-key="$WORKSPACE" --session="$SESSION_ID" --from-resume="$RESUME" || \
  echo "Warning: mail re-register failed; falling back to ntm-inbox" >&2

echo ""
echo "Dispatching MO-resume.md to each pane..."

# Per-pane fan-out. The previous form was a single dispatch with no
# --target-pane / --target-session, which dispatch-marching-order.sh rejects
# with exit 2 (target flags are mandatory unless --dry-run). Parse the roster
# from RESUME.md via parse-resume.sh and dispatch one MO-resume per pane with
# its role / domain / last_thread filled in (MO-resume.md uses the flat
# `<ROLE>`/`<DOMAIN>`/`<LAST_THREAD>` placeholders, not dotted notation).
NEXT_PHASE_NUM=$((LAST_PHASE + 1))
ROSTER_JSON=$("$(dirname "$0")/parse-resume.sh" --resume="$RESUME" 2>/dev/null || echo '{}')
ROSTER_LEN=$(printf '%s' "$ROSTER_JSON" | jq '.roster | length // 0' 2>/dev/null || echo 0)

if [ "$ROSTER_LEN" -lt 1 ]; then
  echo "  Warning: roster could not be parsed from $RESUME — operator must dispatch MO-resume manually per pane" >&2
else
  printf '%s' "$ROSTER_JSON" | jq -r '
    .roster[] | [
      (.pane | tostring),
      (.role // "unknown"),
      ((.domain // []) | if type == "array" then join(",") else tostring end),
      (.last_thread // "none")
    ] | @tsv
  ' 2>/dev/null | while IFS=$'\t' read -r pane role domain last_thread; do
    [ -z "$pane" ] && continue
    "$(dirname "$0")/dispatch-marching-order.sh" MO-resume \
      --target-pane="$pane" \
      --target-session="$SESSION_ID" \
      --PANE_N="$pane" \
      --SESSION_ID="$SESSION_ID" \
      --MODE_TO_RESUME="$MODE" \
      --NEXT_PHASE="$NEXT_PHASE_NUM" \
      --LAST_PHASE_COMPLETED="$LAST_PHASE" \
      --ROLE="$role" \
      --DOMAIN="${domain:-n/a}" \
      --LAST_THREAD="${last_thread:-n/a}" \
      || echo "  Warning: MO-resume dispatch to pane $pane failed" >&2
  done
fi

# Log resume
mkdir -p "$WORKSPACE/session-logs"
{
  echo "Resume at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "  Session: $SESSION_ID"
  echo "  Mode: $MODE"
  echo "  Last completed phase: $LAST_PHASE"
  echo "  Next phase: $((LAST_PHASE + 1))"
  echo "  RESUME.md: $RESUME"
} >> "$WORKSPACE/session-logs/resume-$(date -u +%Y%m%dT%H%M%SZ).md"

echo ""
echo "Resume complete. Next phase: $((LAST_PHASE + 1))"
echo "Operator: dispatch the phase-specific MO via ./scripts/dispatch-marching-order.sh."
