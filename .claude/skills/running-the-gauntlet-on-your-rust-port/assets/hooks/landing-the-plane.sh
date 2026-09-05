#!/usr/bin/env bash
# landing-the-plane.sh — Stop hook.
#
# On session end, check for unfinished business:
#   - uncommitted changes
#   - unpushed commits
#   - unsynced .beads/ store
#   - workspace state that suggests the agent quit mid-round
#
# Emits the "Landing the Plane" reminder block (per AGENTS.md) so the next
# agent picking up where this one left off has a clean handoff.
#
# Hook contract:
#   stdin:  JSON {} (Stop event payload, fields vary by client)
#   exit 0: always (informational only)

set -euo pipefail

# --- Read stdin (we don't actually need it for Stop, but consume it cleanly) -
cat >/dev/null 2>&1 || true

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# --- Locate workspace --------------------------------------------------------
PARENT_DIR="$(dirname "$PROJECT_DIR")"
WORKSPACE="$(ls -d "$PARENT_DIR"/*__gauntlet_workspace 2>/dev/null | head -1 || true)"

# --- Section 1: uncommitted changes in the target port ----------------------
PORT_DIRTY=""
if [[ -d "$PROJECT_DIR/.git" ]] || git -C "$PROJECT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  if ! git -C "$PROJECT_DIR" diff --quiet 2>/dev/null || \
     ! git -C "$PROJECT_DIR" diff --cached --quiet 2>/dev/null; then
    PORT_DIRTY="$(git -C "$PROJECT_DIR" status --short 2>/dev/null | head -20)"
  fi
fi

# --- Section 2: uncommitted changes in the workspace ------------------------
WORKSPACE_DIRTY=""
if [[ -n "$WORKSPACE" && -d "$WORKSPACE/.git" ]]; then
  if ! git -C "$WORKSPACE" diff --quiet 2>/dev/null || \
     ! git -C "$WORKSPACE" diff --cached --quiet 2>/dev/null; then
    WORKSPACE_DIRTY="$(git -C "$WORKSPACE" status --short 2>/dev/null | head -20)"
  fi
fi

# --- Section 3: unpushed commits --------------------------------------------
PORT_UNPUSHED=""
if git -C "$PROJECT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  # If there's no upstream, skip silently (might be a fresh branch).
  UPSTREAM="$(git -C "$PROJECT_DIR" rev-parse --abbrev-ref --symbolic-full-name "@{u}" 2>/dev/null || true)"
  if [[ -n "$UPSTREAM" ]]; then
    COUNT="$(git -C "$PROJECT_DIR" rev-list --count "${UPSTREAM}..HEAD" 2>/dev/null || echo 0)"
    if [[ "$COUNT" -gt 0 ]]; then
      PORT_UNPUSHED="${COUNT} commits ahead of ${UPSTREAM}"
    fi
  fi
fi

# --- Section 4: .beads/ sync state ------------------------------------------
BEADS_UNSYNCED=""
BEADS_DIR=""
for CANDIDATE in "$PROJECT_DIR/.beads" "$WORKSPACE/.beads"; do
  if [[ -n "$CANDIDATE" && -d "$CANDIDATE" ]]; then
    BEADS_DIR="$CANDIDATE"
    break
  fi
done
if [[ -n "$BEADS_DIR" ]]; then
  # Heuristic: if beads.db is newer than the most recent .jsonl by > 60s,
  # the DB has changes the JSONL doesn't reflect (br sync --flush-only drift).
  DB_MTIME="$(stat -c %Y "$BEADS_DIR/beads.db" 2>/dev/null || echo 0)"
  JSONL_LATEST="$(find "$BEADS_DIR" -maxdepth 2 -name '*.jsonl' -type f -printf '%T@\n' 2>/dev/null \
    | sort -n | tail -1 | cut -d. -f1)"
  JSONL_LATEST="${JSONL_LATEST:-0}"
  if [[ "$DB_MTIME" -gt "$((JSONL_LATEST + 60))" ]]; then
    BEADS_UNSYNCED="beads.db newer than most recent .jsonl by $((DB_MTIME - JSONL_LATEST))s"
  fi
fi

# --- Section 5: emit only if something to report ----------------------------
if [[ -z "$PORT_DIRTY" && -z "$WORKSPACE_DIRTY" && -z "$PORT_UNPUSHED" && -z "$BEADS_UNSYNCED" ]]; then
  # Clean exit; nothing to report.
  exit 0
fi

cat >&2 <<'EOF'
========================================================================
[gauntlet] LANDING THE PLANE — session-end reminder

You're about to end this session with unfinished business. Before
declaring done, walk through this checklist (per AGENTS.md):
EOF

if [[ -n "$PORT_DIRTY" ]]; then
  cat >&2 <<EOF

  [ ] Uncommitted changes in the target port:
$(printf '%s\n' "$PORT_DIRTY" | sed 's/^/        /')
      → commit or stash with a descriptive name (NEVER bare `git stash`)
EOF
fi

if [[ -n "$WORKSPACE_DIRTY" ]]; then
  cat >&2 <<EOF

  [ ] Uncommitted changes in the gauntlet workspace:
$(printf '%s\n' "$WORKSPACE_DIRTY" | sed 's/^/        /')
      → commit so the next agent has a clean resume state
EOF
fi

if [[ -n "$PORT_UNPUSHED" ]]; then
  cat >&2 <<EOF

  [ ] ${PORT_UNPUSHED}
      → push so collaborators see your work; or document why holding
EOF
fi

if [[ -n "$BEADS_UNSYNCED" ]]; then
  cat >&2 <<EOF

  [ ] Beads store drift: ${BEADS_UNSYNCED}
      → run `br sync --flush-only` then commit .beads/*.jsonl
EOF
fi

cat >&2 <<'EOF'

If you intentionally chose to leave any of these for the next agent,
add a one-line note to the workspace's session log so they know.

See: references/methodology/CONVERGENCE.md § compaction-survival
See: AGENTS.md § Landing the Plane
========================================================================
EOF

# Stop hooks are advisory; never block session end.
exit 0
