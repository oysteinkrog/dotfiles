#!/usr/bin/env bash
# time-machine-audit.sh — Run an audit pass against a HISTORICAL commit.
#
# Use case: a production incident happened at commit X. Which beads at THAT
# point in history should have caught it? Re-run the audit AS-OF that commit
# so the rubric judges the past-state of the project, not today's.
#
# Strategy:
#   1. Stash any uncommitted changes in the project repo (so they survive).
#   2. Record current branch / SHA so we can restore.
#   3. Check out the target ref in a NEW WORKTREE (so other agents on the
#      project can keep working — no locking, no surprises).
#   4. Run a normal audit pass against the worktree, with manifest tagged
#      `as_of_ref=<ref>` and `as_of_sha=<resolved-sha>`.
#   5. Retain the worktree for diagnosis (preserves the audit pass dir and all
#      historical artifacts; cleanup is a human decision).
#
# Worktrees are used INSTEAD of `git checkout` so that the project's main
# working tree is never disturbed — that's a hard requirement when other
# agents are concurrently working on the project (per AGENTS.md).
#
# Usage:
#   time-machine-audit.sh <project-path> <git-ref> [run-pass.sh args...]
#
# Examples:
#   time-machine-audit.sh /data/projects/foo abc123 --threshold 700
#   time-machine-audit.sh /data/projects/foo HEAD~30 --mode comprehensive
#   time-machine-audit.sh /data/projects/foo v1.2.3 --policy report-only
case "${1:-}" in --help|-h) awk '/^[^#]/&&NR>1{exit} NR>1{sub(/^# ?/,"");print}' "$0"; exit 0 ;; esac
set -euo pipefail

PROJECT="${1:?project path required}"
REF="${2:?git ref (sha / branch / tag) required}"
shift 2

[ -d "$PROJECT/.git" ] || { echo "ERROR: $PROJECT is not a git repo" >&2; exit 2; }
PROJECT="$(cd "$PROJECT" && pwd)"

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS="$SKILL_DIR/scripts"

# Resolve REF to a SHA so the manifest records something stable (the ref might
# move under us if someone re-tags or force-pushes). Fail fast if unknown.
RESOLVED_SHA="$(git -C "$PROJECT" rev-parse --verify "$REF^{commit}" 2>/dev/null)" || {
  echo "ERROR: could not resolve git ref '$REF' in $PROJECT" >&2
  exit 3
}
echo "Time-machine audit:" >&2
echo "  project:      $PROJECT" >&2
echo "  ref:          $REF" >&2
echo "  resolved sha: $RESOLVED_SHA" >&2

# Worktree path: /tmp/<basename>__time_machine_<short-sha>__<unix>
SHORT="${RESOLVED_SHA:0:10}"
TS="$(date -u +%s)"
WORKTREE="/tmp/$(basename "$PROJECT")__time_machine_${SHORT}__${TS}"

cleanup() {
  if [ -d "$WORKTREE" ]; then
    echo "Retained time-machine worktree for diagnosis: $WORKTREE" >&2
  fi
  if [ -n "${TMP:-}" ] && [ -e "$TMP" ]; then
    echo "Retained manifest-tag tmp file for diagnosis: $TMP" >&2
  fi
}
trap cleanup EXIT

echo "Creating worktree at $WORKTREE (detached HEAD)..." >&2
git -C "$PROJECT" worktree add --detach "$WORKTREE" "$RESOLVED_SHA" >/dev/null

# AUDIT_DIR for time-machine: include the SHA in the dir name so AS-OF audits
# don't trample present-day audits. They live next to the project's normal
# audit dir (also inside the project tree).
AUDIT_DIR="$PROJECT/beads_compliance_audit_asof_${SHORT}"

if [ ! -d "$AUDIT_DIR" ]; then
  echo "Time-machine audit dir does not exist; will be created at $AUDIT_DIR" >&2
fi

# We deliberately call run-pass.sh against the WORKTREE so all br/.beads
# operations happen against the historical state. bootstrap-audit.sh creates
# beads_compliance_audit/ INSIDE the worktree; we move that to the persistent
# AS-OF home after the run.
echo "Running pass against worktree (this is the same code path as a normal pass)..." >&2
WORKTREE_AUDIT_DIR="${WORKTREE}/beads_compliance_audit"

# We swallow the run-pass.sh exit code so cleanup (worktree removal) always
# runs even on failure — but we DO record it so the final exit code is honest.
set +e
"$SCRIPTS/run-pass.sh" "$WORKTREE" "$@"
RUN_PASS_RC=$?
set -e
if [ "$RUN_PASS_RC" -ne 0 ]; then
  echo "WARNING: run-pass.sh exited $RUN_PASS_RC; the audit may be incomplete." >&2
fi

# Move the worktree's audit dir to its persistent home (named with SHA).
if [ -d "$WORKTREE_AUDIT_DIR" ]; then
  if [ -d "$AUDIT_DIR" ]; then
    # Append THIS pass into the existing time-machine audit dir.
    NEW_PASS_DIR="$(ls -1d "$WORKTREE_AUDIT_DIR/passes"/*/ 2>/dev/null | sort | tail -1)"
    if [ -n "$NEW_PASS_DIR" ]; then
      DEST="$AUDIT_DIR/passes/$(basename "$NEW_PASS_DIR")"
      mkdir -p "$AUDIT_DIR/passes"
      mv "$NEW_PASS_DIR" "$DEST"
      cp "$WORKTREE_AUDIT_DIR/REPORT.md" "$AUDIT_DIR/REPORT.md" 2>/dev/null || true
      cp "$WORKTREE_AUDIT_DIR/manifest.json" "$AUDIT_DIR/manifest.json" 2>/dev/null || true
      echo "Appended pass to existing $AUDIT_DIR" >&2
    fi
    echo "Retained temporary worktree audit dir for diagnosis: $WORKTREE_AUDIT_DIR" >&2
  else
    mv "$WORKTREE_AUDIT_DIR" "$AUDIT_DIR"
    echo "Created $AUDIT_DIR" >&2
  fi

  # Tag the latest pass's manifest with as_of metadata.
  LATEST_PASS="$(ls -1d "$AUDIT_DIR/passes"/*/ 2>/dev/null | sort | tail -1)"
  if [ -n "$LATEST_PASS" ] && [ -f "$LATEST_PASS/manifest.json" ]; then
    TMP="$(mktemp)"
    jq --arg ref "$REF" --arg sha "$RESOLVED_SHA" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       '.as_of_ref=$ref | .as_of_sha=$sha | .audit_kind="time-machine" | .audit_invoked_at=$now' \
       "$LATEST_PASS/manifest.json" > "$TMP"
    mv "$TMP" "$LATEST_PASS/manifest.json"
    echo "Tagged $LATEST_PASS/manifest.json with as_of_sha=$RESOLVED_SHA" >&2
  fi
fi

echo ""
if [ "$RUN_PASS_RC" -ne 0 ]; then
  echo "Time-machine audit FINISHED WITH WARNINGS (run-pass.sh exited $RUN_PASS_RC). AS-OF: $REF ($RESOLVED_SHA)" >&2
  echo "Audit dir (may be partial): $AUDIT_DIR" >&2
  exit "$RUN_PASS_RC"
fi
echo "Time-machine audit complete. AS-OF: $REF ($RESOLVED_SHA)" >&2
echo "Audit dir: $AUDIT_DIR" >&2
