#!/usr/bin/env bash
# fixture-template — corrupt.sh
#
# Reproducibly creates a broken state for a specific failure mode.
# Replace <fm-id> and the corruption recipe with the real values.
#
# Usage: corrupt.sh <target_dir>
# Output: a workspace at <target_dir> in the broken state for fm-<id>;
#         a baseline copy at <target_dir>/.fixture_baseline/ used by the
#         undo round-trip verification.

set -euo pipefail
target_dir="${1:?usage: corrupt.sh <target_dir>}"

# 1. Initialize a clean isolated workspace.
mkdir -p "$target_dir"
cd "$target_dir"

# 2. Run the project's bootstrap. Replace TOOL_BIN/init with the real bootstrap
#    command (cargo new, npm init, etc.) — no defaults that might phone home or
#    make network calls.
tool_bin="${TOOL_BIN:?replace TOOL_BIN with the fixture bootstrap command}"
"$tool_bin" init --quiet 2>&1 || { echo "fixture: bootstrap failed" >&2; exit 1; }

# 3. Add deterministic content so the corruption is meaningful.
#    Replace this block with project-specific seed data.
echo "seed:fixture:fm-<id>" > seed.txt

# 4. Apply the corruption recipe. THIS MUST BE DETERMINISTIC.
#    No `date`, no `$RANDOM`, no `$$`, no time-of-day.
#    Examples:
#
#    a) Truncate a critical file to half its bytes:
#         dd if=.beads/beads.db of=/tmp/half bs=1 count=$(($(stat -c%s .beads/beads.db) / 2))
#         mv /tmp/half .beads/beads.db
#
#    b) Corrupt one record in a JSONL file:
#         awk 'NR==5{$0=substr($0,1,length($0)-3)"...]"}1' \
#             .beads/issues.jsonl > /tmp/jsonl
#         mv /tmp/jsonl .beads/issues.jsonl
#
#    c) Plant a stale lock file:
#         echo '{"pid": 99999999, "started_at": "2020-01-01T00:00:00Z"}' \
#             > .beads/beads.lock
#
#    Replace the line below with the real recipe.

echo "<corruption-recipe>" > broken_state_marker.txt

# 5. Snapshot the broken state for byte-comparison after `<tool> doctor undo`.
mkdir -p "$target_dir/.fixture_baseline"
# Copy everything except the .fixture_baseline directory itself.
# NOTE: `cp --parents` is GNU coreutils-only. macOS ships BSD cp, which
# does not support --parents. Portable alternative (Linux/macOS/BSD) using tar:
#   ( cd "$target_dir" && tar cf - --exclude=.fixture_baseline --exclude=./.fixture_baseline . ) | \
#       ( cd "$target_dir/.fixture_baseline" && tar xf - )
( cd "$target_dir" && tar cf - --exclude=.fixture_baseline --exclude=./.fixture_baseline . ) | \
    ( cd "$target_dir/.fixture_baseline" && tar xf - )

echo "fixture corrupt.sh: target_dir=$target_dir baseline=$target_dir/.fixture_baseline" >&2
