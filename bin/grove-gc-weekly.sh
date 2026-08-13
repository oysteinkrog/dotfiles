#!/bin/bash
# Weekly grove gc audit (bd-grove-lifecycle-p0ur.11).
# Invoked by Windows Task Scheduler task "grove-gc-weekly" via:
#   wsl.exe -e bash -lc /c/users/oystein/.dotfiles/bin/grove-gc-weekly.sh
# Report-only: runs grove gc --dry-run, writes a dated report, and appends one
# JSON trend line to gc-history.jsonl. Never deletes anything.
# Scheduled Sunday 06:00 to stay clear of build windows (~8 min of drvfs I/O).
set -u
GROVE=/c/users/oystein/.cargo/bin/grove
WORK=/c/work/desktop
OUT="$WORK/.grove/gc-report-$(date +%F).txt"
HIST="$WORK/.grove/gc-history.jsonl"

"$GROVE" gc --dry-run --repo desktop > "$OUT" 2>&1
rc=$?

wt_total=$(git -C "$WORK/master" worktree list --porcelain 2>/dev/null | grep -c '^worktree ')
reg_total=$(jq -r '.projects | length' "$WORK/.grove/registry.json" 2>/dev/null || echo -1)
unreg=$(comm -23 \
  <(git -C "$WORK/master" worktree list --porcelain | sed -n 's/^worktree //p' | grep -v '/master$' | sort) \
  <(jq -r '.projects | to_entries[] | .value.path' "$WORK/.grove/registry.json" | sort) | wc -l)
scratch=$(ls -d "$WORK/.scratch"/*/ 2>/dev/null | wc -l)
archive_kb=$(du -sk "$WORK/.archive" 2>/dev/null | cut -f1 || echo 0)

printf '{"date":"%s","gc_exit":%d,"worktrees":%d,"registered":%s,"unregistered":%d,"scratch":%d,"archive_kb":%d}\n' \
  "$(date -u +%FT%TZ)" "$rc" "$wt_total" "$reg_total" "$unreg" "$scratch" "$archive_kb" >> "$HIST"
