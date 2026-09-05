#!/usr/bin/env bash
# session-fork.sh — Fork an existing brennerbot workspace into a new session
# Useful when: (1) running multiple variants on same question for triangulation,
# (2) creating a checkpoint to explore an alternative direction without losing
# original, (3) preparing a /pre-publication-review red-team subsession.

set -euo pipefail

SOURCE_WS="${1:?Usage: $0 <source_workspace> <fork_name> [--purpose <purpose>]}"
FORK_NAME="${2:?Usage: $0 <source_workspace> <fork_name> [--purpose <purpose>]}"
PURPOSE="general"

# Parse optional --purpose flag. Defend against `--purpose` being passed as
# the final arg without a value: under `set -u`, an unguarded `$2` reference
# would abort with a `unbound variable` message that doesn't tell the user
# what's actually wrong.
shift 2
while [ $# -gt 0 ]; do
    case "$1" in
        --purpose)
            if [ $# -lt 2 ]; then
                echo "[FATAL] --purpose requires a value" >&2
                exit 2
            fi
            PURPOSE="$2"
            shift 2
            ;;
        *)
            echo "[WARN] ignoring unknown argument: $1" >&2
            shift
            ;;
    esac
done

if [ ! -d "$SOURCE_WS" ]; then
    echo "[FATAL] Source workspace not found: $SOURCE_WS" >&2
    exit 1
fi

if [ ! -f "$SOURCE_WS/.brenner_workspace/phase0_scope_decision.md" ]; then
    echo "[FATAL] Not a valid brennerbot workspace" >&2
    exit 1
fi

# Resolve source to an absolute path so dirname/basename produce sensible
# results when the user passes "." or a path with a trailing slash. Use the
# `|| { ... exit 1; }` form because POSIX `set -e` does NOT abort on a failed
# command substitution inside a plain assignment — without this guard a
# permission-denied cd would leave SOURCE_WS_ABS empty and the later
# `cp -R "$SOURCE_WS_ABS" ...` would produce a confusing "cp: ''" error
# instead of pointing at the real cause.
SOURCE_WS_ABS="$(cd "$SOURCE_WS" && pwd)" \
    || { echo "[FATAL] Could not resolve source workspace path: $SOURCE_WS" >&2; exit 1; }
PARENT_DIR="$(dirname "$SOURCE_WS_ABS")"
FORK_PATH="$PARENT_DIR/$FORK_NAME"

if [ -e "$FORK_PATH" ]; then
    echo "[FATAL] Fork target already exists: $FORK_PATH" >&2
    exit 1
fi

# Plain recursive copy (the previous comment claimed hardlinking, but `cp -R`
# does not hardlink — `cp -al` would, on GNU coreutils only). For our
# workspace sizes (≤100MB typical) the duplication cost is acceptable, and
# avoiding hardlinks means modifications to the fork can't accidentally
# mutate the source.
cp -R "$SOURCE_WS_ABS" "$FORK_PATH"

# Mark as fork:
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
SOURCE_ID="$(basename "$SOURCE_WS_ABS")"

cat >> "$FORK_PATH/.brenner_workspace/phase0_scope_decision.md" <<EOF

## Fork metadata
- forked_from: $SOURCE_ID
- forked_at: $TIMESTAMP
- fork_purpose: $PURPOSE
- new_session_id: $FORK_NAME

EOF

# Create fork-specific README:
cat > "$FORK_PATH/FORK-README.md" <<EOF
# Forked Session: $FORK_NAME

**Forked from:** $SOURCE_ID
**Forked at:** $TIMESTAMP
**Purpose:** $PURPOSE

## What this fork preserves

- All beads from source (you may want to re-create beads with new IDs to avoid bead-database conflicts)
- All evidence packs
- All distillations (if Phase 6+ already done)
- Drift-check (if Phase 10 done)

## What you should do next

1. Review .brenner_workspace/phase0_scope_decision.md and update for fork-specific scope
2. If beads will conflict with source's beads, re-create them with new IDs
3. Update intake/question_of_record.md if the fork explores a different question
4. Document the fork's hypotheses (if different) in a new H bead with origin:fork

## What NOT to do

- Don't delete source workspace; both should coexist
- Don't push fork to same git ref as source; use distinct branch
- Don't share bead IDs across fork and source (if both running concurrently)

EOF

# Update beads workspace marker (per beads' workspace tracking):
if [ -d "$FORK_PATH/.beads" ]; then
    echo "[INFO] Fork has its own .beads/ directory; bead IDs should be re-issued"
fi

echo "=== Fork Created ==="
echo "Source:   $SOURCE_WS_ABS"
echo "Fork:     $FORK_PATH"
echo "Purpose:  $PURPOSE"
echo "==="
echo "Next step: cd $FORK_PATH && cat FORK-README.md"
