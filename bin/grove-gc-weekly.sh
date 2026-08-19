#!/bin/bash
# Weekly grove gc audit (bd-grove-lifecycle-p0ur.11).
# Invoked by Windows Task Scheduler task "grove-gc-weekly" via:
#   wsl.exe -e bash -lc /c/users/oystein/.dotfiles/bin/grove-gc-weekly.sh
# Runs grove gc --yes: auto-applies ONLY the mechanically safe categories
# (1 stale registry entries, 4 expired-clean .scratch ephemerals, 5 stale-clean
# harness worktrees, 6 git worktree prune) — pinned by tests in the grove repo;
# everything else stays report-only. Writes a dated report and appends one
# JSON trend line to gc-history.jsonl.
# Scheduled Sunday 06:00 to stay clear of build windows (~8 min of drvfs I/O).
set -u
GROVE=/c/users/oystein/.cargo/bin/grove
WORK=/c/work/desktop
OUT="$WORK/.grove/gc-report-$(date +%F).txt"
HIST="$WORK/.grove/gc-history.jsonl"

"$GROVE" gc --yes --repo desktop > "$OUT" 2>&1
rc=$?

# Stale build-output sweep (user-approved 2026-08-19): BUILD*/ dirs are
# regenerable, multi-GB, and dominate per-worktree disk. Delete any
# <worktree>/BUILD* whose own mtime AND whose worktree root mtime are both
# older than 14 days, unless a live process has its cwd inside the worktree.
# Only cost on a false positive: one full rebuild.
build_swept=0
now=$(date +%s)
for b in "$WORK"/*/BUILD*/; do
  [ -d "$b" ] || continue
  wt="$(dirname "$b")"
  b_age=$(( (now - $(stat -c %Y "$b")) / 86400 ))
  wt_age=$(( (now - $(stat -c %Y "$wt")) / 86400 ))
  [ "$b_age" -ge 14 ] && [ "$wt_age" -ge 14 ] || continue
  live=0
  for pid in /proc/[0-9]*; do
    case "$(readlink "$pid/cwd" 2>/dev/null)" in "$wt"|"$wt"/*) live=1; break;; esac
  done
  [ "$live" -eq 0 ] || { echo "[build-sweep] skip live: $b" >> "$OUT"; continue; }
  sz=$(du -sk "$b" 2>/dev/null | cut -f1)
  rm -rf "$b" && { echo "[build-sweep] removed $b (${sz}KB, build ${b_age}d, worktree ${wt_age}d)" >> "$OUT"; build_swept=$((build_swept+1)); }
done
echo "[build-sweep] swept $build_swept stale BUILD dirs" >> "$OUT"

wt_total=$(git -C "$WORK/master" worktree list --porcelain 2>/dev/null | grep -c '^worktree ')
reg_total=$(jq -r '.projects | length' "$WORK/.grove/registry.json" 2>/dev/null || echo -1)
unreg=$(comm -23 \
  <(git -C "$WORK/master" worktree list --porcelain | sed -n 's/^worktree //p' | grep -v '/master$' | sort) \
  <(jq -r '.projects | to_entries[] | .value.path' "$WORK/.grove/registry.json" | sort) | wc -l)
scratch=$(ls -d "$WORK/.scratch"/*/ 2>/dev/null | wc -l)
archive_kb=$(du -sk "$WORK/.archive" 2>/dev/null | cut -f1 || echo 0)

printf '{"date":"%s","gc_exit":%d,"worktrees":%d,"registered":%s,"unregistered":%d,"scratch":%d,"archive_kb":%d}\n' \
  "$(date -u +%FT%TZ)" "$rc" "$wt_total" "$reg_total" "$unreg" "$scratch" "$archive_kb" >> "$HIST"
