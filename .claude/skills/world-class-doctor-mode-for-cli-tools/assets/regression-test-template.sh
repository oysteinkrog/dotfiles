#!/usr/bin/env bash
# regression-test-template — assert.sh
#
# Companion to corrupt.sh. Runs the round-trip:
#   corrupt → <tool> doctor (no flags) returns 1
#   → <tool> doctor --fix returns 0
#   → <tool> doctor (no flags) returns 0  (assert healthy)
#   → <tool> doctor undo <run-id> returns 0
#   → cmp-strict against .fixture_baseline (assert byte-identical)
#
# Usage: assert.sh <target_dir>
# Exit 0 if pass, 1 if fail.

set -euo pipefail
target_dir="${1:?usage: assert.sh <target_dir>}"
fm_id="${FM_ID:-fm-<id>}"
tool="${TOOL:-<tool>}"

cd "$target_dir"

# 1. Diagnose: must report findings (exit 1).
diag=$( "$tool" doctor --json 2>/dev/null || true )
diag_exit=$(echo "$diag" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("exit_code","?"))')
[ "$diag_exit" = "1" ] || { echo "FAIL: diagnose exit_code=$diag_exit (expected 1)" >&2; exit 1; }

# 2. Fix: must succeed (exit 0). Capture stdout; use 'if !' so a non-zero
#    exit fails the assertion (don't rely on `cmd; var=$?` — `set -e` would
#    abort the script before `var=$?` runs).
if ! fix=$( "$tool" doctor --fix --json ); then
    echo "FAIL: --fix returned non-zero exit code" >&2
    exit 1
fi

# 3. Diagnose again: must be healthy (exit 0). Same `if !` pattern as above.
if ! "$tool" doctor --json --quiet > /dev/null 2>&1; then
    echo "FAIL: post-fix diagnose returned non-zero exit code" >&2
    exit 1
fi

# 4. Undo: must succeed and restore byte-identical to corrupted state.
run_id=$(echo "$fix" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("run_id"))')
"$tool" doctor undo "$run_id" --strict > /dev/null \
    || { echo "FAIL: undo failed" >&2; exit 1; }

# 5. Compare bytes. The .fixture_baseline IS the corrupted state.
#    `diff -r --brief` exits 0 only if every file matches and the trees have
#    the same set of files. Any difference (content or "Only in" file presence)
#    yields a non-zero exit; the `||` runs FAIL. Don't pipe through
#    `grep -v '^Only in'` — that silently masks "file present in baseline but
#    missing from target" and "file present in target but missing from
#    baseline", both of which are real undo failures.
diff -r --brief --exclude='.doctor' --exclude='.fixture_baseline' \
    "$target_dir/.fixture_baseline/" "$target_dir/" \
    || { echo "FAIL: undo not byte-identical to .fixture_baseline" >&2; exit 1; }

echo "PASS: round-trip for $fm_id" >&2
