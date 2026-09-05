#!/bin/bash
# purge-scratchpads.sh [AGE_DAYS] [--yes]
#
# Age-gated purge of Claude Code session scratchpads (/tmp/claude-1000/<proj>/<session>/)
# and loose top-level /tmp litter (claude-edit-tracker-*, br-*-msg.txt, stray logs...).
#
# DRY-RUN BY DEFAULT: prints what would be deleted and the estimated reclaim.
# Pass --yes to actually delete. Default age gate: 30 days.
#
# Safety:
#  - a session dir is deleted only if NO file inside was modified within AGE_DAYS
#  - dirs that are (or contain) a live process cwd are skipped
#  - the invoking process's own cwd tree is therefore protected automatically
#  - loose-file pass only touches files owned by the current user, -maxdepth 1
#
# First real run (2026-08-27): 1,979 session dirs + 12,374 loose files, ~22 GiB freed.
set -u
AGE_DAYS=30
DO_IT=0
for a in "$@"; do
  case "$a" in
    --yes) DO_IT=1;;
    ''|*[!0-9]*) echo "usage: purge-scratchpads.sh [AGE_DAYS] [--yes]" >&2; exit 2;;
    *) AGE_DAYS=$a;;
  esac
done
LOG=/tmp/purge-scratchpads-$(date +%Y%m%d-%H%M%S).log
: > "$LOG"
MODE_LABEL=$([ $DO_IT -eq 1 ] && echo DELETING || echo DRY-RUN)
echo "== purge-scratchpads: $MODE_LABEL, age gate ${AGE_DAYS}d, log $LOG =="

# Snapshot live process cwds once
LIVE_CWDS=$(for p in /proc/[0-9]*/cwd; do readlink "$p" 2>/dev/null; done | sort -u)

is_live() { # $1 = dir; true if any live cwd is inside it
  local d="${1%/}"
  while IFS= read -r c; do
    case "$c" in "$d"|"$d"/*) return 0;; esac
  done <<< "$LIVE_CWDS"
  return 1
}

freed=0 deleted=0 skipped_live=0
for proj in /tmp/claude-1000/*/; do
  [ -d "$proj" ] || continue
  for sess in "$proj"*/; do
    [ -d "$sess" ] || continue
    # keep if anything inside is newer than the age gate
    if [ -n "$(find "$sess" -mtime -"$AGE_DAYS" -print -quit 2>/dev/null)" ]; then
      continue
    fi
    if is_live "$sess"; then
      echo "SKIP-LIVE $sess" | tee -a "$LOG"; skipped_live=$((skipped_live+1)); continue
    fi
    sz=$(du -sk "$sess" 2>/dev/null | cut -f1)
    if [ $DO_IT -eq 1 ]; then
      rm -rf "$sess" 2>>"$LOG" && { deleted=$((deleted+1)); freed=$((freed+${sz:-0})); echo "DEL ${sz:-?}K $sess" >> "$LOG"; }
    else
      deleted=$((deleted+1)); freed=$((freed+${sz:-0})); echo "WOULD-DEL ${sz:-?}K $sess" | tee -a "$LOG" >/dev/null
    fi
  done
  [ $DO_IT -eq 1 ] && rmdir "$proj" 2>/dev/null  # remove project dir if now empty
done

# Loose top-level /tmp litter older than the gate (own files only)
if [ $DO_IT -eq 1 ]; then
  loose=$(find /tmp -maxdepth 1 -type f -user "$(id -un)" -mtime +"$AGE_DAYS" -print -delete 2>>"$LOG" | wc -l)
else
  loose=$(find /tmp -maxdepth 1 -type f -user "$(id -un)" -mtime +"$AGE_DAYS" -print 2>/dev/null | tee -a "$LOG" | wc -l)
fi

verb=$([ $DO_IT -eq 1 ] && echo deleted || echo "would delete")
echo "==== $MODE_LABEL done: $verb $deleted session dirs (~$((freed/1024/1024)) GiB), $loose loose files, $skipped_live skipped (live). Details: $LOG ===="
[ $DO_IT -eq 0 ] && echo "Re-run with --yes to apply."
