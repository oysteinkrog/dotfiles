#!/usr/bin/env bash
# Aiolos hook forwarder — gated.
#
# This script is wired into every Claude Code lifecycle hook in settings.json,
# so the cost of it running 10–20 times per turn matters. The script bails
# at line 1 unless ~/.config/aiolos/hooks-enabled exists. Total cost when
# disabled: bash startup + one stat(2). When enabled, see the spool design
# below — it appends to a local JSONL file and never blocks on the network.
#
# Toggle from your shell:
#   aiolos-hooks enable
#   aiolos-hooks disable
#   aiolos-hooks toggle
#   aiolos-hooks status

[ -f "$HOME/.config/aiolos/hooks-enabled" ] || exit 0

set +e

SPOOL="${AIOLOS_HOOK_SPOOL:-$HOME/.cache/aiolos-hooks/spool.jsonl}"
MAX_SPOOL_BYTES="${AIOLOS_HOOK_SPOOL_MAX:-10485760}"   # 10 MB cap

# Cap unbounded spool growth when the shipper isn't draining it.
if [ -f "$SPOOL" ]; then
  size=$(stat -c%s "$SPOOL" 2>/dev/null || echo 0)
  if [ "$size" -gt "$MAX_SPOOL_BYTES" ]; then
    exit 0
  fi
fi

mkdir -p "$(dirname "$SPOOL")" 2>/dev/null

# Read Claude Code's JSON payload off stdin and append it to the spool with
# a NUL separator so the shipper can handle pretty-printed multi-line JSON.
# `printf` is a bash builtin → no fork. Atomic append via O_APPEND.
PAYLOAD=$(cat)
[ -z "$PAYLOAD" ] && exit 0
printf '%s\0' "$PAYLOAD" >> "$SPOOL" 2>/dev/null

exit 0
