#!/usr/bin/env bash
# partial-split.sh — Phase 7: split a partially-novel stash diff to keep
# only specified hunks.
#
# Usage: partial-split.sh <project-path> <n> <hunks-to-keep>
#   <hunks-to-keep>: comma-separated list of 1-based hunk indexes, e.g. "2,3,5"
#   OR "all-except:1,4" to drop specific hunks
#
# HUNK NUMBERING: indexes are GLOBAL across the whole diff (counting `@@` lines
# in the order they appear). For a multi-file diff with file A having hunks 1,2
# and file B having hunks 1,2,3, the indexes are 1,2 (file A) then 3,4,5
# (file B). This matches `grep -c '^@@' <diff>`.
#
# Output: <bundle>/diffs/<NNN>.split.diff — the filtered diff
#
# This is a structural diff filter; it preserves @@ headers and context lines
# as they appear in the source. It does NOT modify code content with sed/awk.

set -euo pipefail

PROJECT="${1:?Usage: partial-split.sh <project-path> <n> <hunks-to-keep>}"
N="${2:?missing n}"
KEEP_SPEC="${3:?missing hunks-to-keep specifier}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=project-root.sh
. "$SCRIPT_DIR/project-root.sh"

PROJECT_ABS="$(resolve_project_root "$PROJECT")"
WORKSPACE="$PROJECT_ABS/.stash_janitor_workspace"

# Explicit pre-condition checks — same pattern as triage-batch.sh and
# apply-keeper.sh — surface clear messages instead of cryptic `cat` aborts.
if [[ ! -f "$WORKSPACE/bundle_path.txt" ]]; then
  echo "ERROR: Phase 3 has not completed yet ($WORKSPACE/bundle_path.txt missing)." >&2
  exit 8
fi
BUNDLE="$(cat "$WORKSPACE/bundle_path.txt")"
if [[ -z "$BUNDLE" || ! -d "$BUNDLE" ]]; then
  echo "ERROR: bundle path '$BUNDLE' is invalid (empty or missing directory)." >&2
  exit 8
fi
NPAD=$(printf '%03d' "$N")
SRC="$BUNDLE/diffs/$NPAD.diff"
DST="$BUNDLE/diffs/$NPAD.split.diff"

if [[ ! -f "$SRC" ]]; then
  echo "ERROR: $SRC not found" >&2
  exit 1
fi

# Parse hunks-to-keep
mode="keep"
case "$KEEP_SPEC" in
  all-except:*) mode="drop"; spec="${KEEP_SPEC#all-except:}" ;;
  *) mode="keep"; spec="$KEEP_SPEC" ;;
esac

# Build awk filter that walks the diff and decides per-hunk
awk -v mode="$mode" -v spec="$spec" '
  BEGIN {
    n = split(spec, a, ",")
    for (i = 1; i <= n; i++) targets[a[i]] = 1
    in_hunk = 0
    in_file_header = 1
    hunk_idx = 0
    file_kept = 0
    file_header = ""
  }

  /^diff --git / {
    # Flush buffered file header if a hunk in it was kept
    if (file_kept) printf "%s", file_buf
    file_buf = $0 "\n"
    file_kept = 0
    in_file_header = 1
    next
  }

  /^---|^\+\+\+|^index|^new file|^deleted file|^similarity|^rename|^copy|^Binary files/ {
    if (in_file_header) {
      file_buf = file_buf $0 "\n"
      next
    }
  }

  /^@@/ {
    in_file_header = 0
    hunk_idx++
    keep_this_hunk = 0
    if (mode == "keep") {
      if (targets[hunk_idx]) keep_this_hunk = 1
    } else {
      if (!targets[hunk_idx]) keep_this_hunk = 1
    }
    in_hunk = 1
    if (keep_this_hunk) {
      file_kept = 1
      printf "%s", file_buf
      file_buf = ""
      print
    }
    next
  }

  in_hunk && (/^[ +-]/ || /^\\/) {
    if (keep_this_hunk) print
    next
  }

  # Reset between files
  /^$/ { next }

  END {
    if (file_kept && file_buf != "") printf "%s", file_buf
  }
' "$SRC" > "$DST"

# Verify the split diff applies cleanly (dry-run)
if [[ ! -s "$DST" ]]; then
  echo "ERROR: split diff is empty (no hunks selected)" >&2
  exit 2
fi

# Capture the apply-check error (if any) instead of silencing it — the user
# needs the actual git output to diagnose a wrong split (e.g., kept a hunk
# whose context is no longer on HEAD; mid-rename hunks; offset drift).
CHECK_ERR_FILE="$WORKSPACE/.split_${NPAD}_check_err"
if check_err=$(git -C "$PROJECT_ABS" apply --3way --check "$DST" 2>&1); then
  echo "wrote $DST (apply --3way --check: clean)"
else
  printf '%s\n' "$check_err" > "$CHECK_ERR_FILE"
  echo "wrote $DST (apply --3way --check: FAILED — split may be wrong)" >&2
  echo "Git output:" >&2
  # Avoid `head` here: under `set -o pipefail`, a long diagnostic can SIGPIPE
  # the left side and abort before we print the saved diagnostic path.
  printf '  %s\n' "$check_err" | sed -n '1,10p' >&2
  echo "Full diagnostic written to $CHECK_ERR_FILE" >&2
  echo "Inspect manually: $DST" >&2
  exit 3
fi

# Stats. `grep -c '^@@'` always exits 0 here because we already verified DST
# is non-empty above (which requires at least one hunk), but guard with
# `|| true` defensively against pipefail abort on edge cases.
src_hunks=$({ grep -c '^@@' "$SRC" ; } || true)
dst_hunks=$({ grep -c '^@@' "$DST" ; } || true)
echo "Hunks: kept ${dst_hunks:-0} of ${src_hunks:-0}"
