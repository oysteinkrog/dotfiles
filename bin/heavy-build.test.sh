#!/usr/bin/env bash
# Tests for heavy-build's give-up clock and the manager hold file.
# Runs heavy-build in shadow mode against private runtime, state, config and
# cgroup dirs. A live blocker ticket sits first in line, so no build starts.
#
# Usage: heavy-build.test.sh [path-to-heavy-build]
set -uo pipefail

HB=$(readlink -f -- "${1:-$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/heavy-build}")
fail=0

# Sets up a sandbox in $T with a live blocker ticket ahead of every waiter.
setup() {
  T=$(mktemp -d "${TMPDIR:-/var/tmp}/hb-test.XXXXXX")
  mkdir -p "$T/run/heavy-build.queue" "$T/state" "$T/config" "$T/cg" "$T/work"
  sleep 600 &
  blocker=$!
  local st
  st=$(awk '{sub(/.*\) /, ""); split($0, a, " "); print a[20]}' "/proc/$blocker/stat")
  printf '%s %s\nnormal 1 1 1 -\n' "$blocker" "$st" > "$T/run/heavy-build.queue/0000000000000000001-$blocker-blocker"
}

teardown() {
  kill "$blocker" 2>/dev/null
  wait "$blocker" 2>/dev/null
  rm -rf -- "$T"
}

# Runs heavy-build in the sandbox in the background; sets hbpid.
run_hb() {
  (cd "$T/work" && exec env -u HEAVY_BUILD_MODE \
    XDG_RUNTIME_DIR="$T/run" XDG_STATE_HOME="$T/state" XDG_CONFIG_HOME="$T/config" \
    HB_CGROUP="$T/cg" HB_MACHINE_SESSION=/bin/false HEAVY_BUILD_PRIORITY=normal \
    HEAVY_BUILD_WAIT=3 HEAVY_BUILD_POLL=1 HEAVY_BUILD_FORCE=1 \
    "$HB" true) > "$T/out" 2>&1 &
  hbpid=$!
}

check() {
  if eval "$2"; then echo "ok: $1"; else echo "FAIL: $1"; fail=1; sed 's/^/  | /' "$T/out"; fi
}

# 1. Without a hold the clock runs, so it gives up with 75 after about 3 s.
setup
run_hb
start=$SECONDS
wait "$hbpid"; rc=$?
check "no hold: gives up with exit 75" '(( rc == 75 ))'
check "no hold: gives up within 10 s" '(( SECONDS - start <= 10 ))'
teardown

# 2. With a hold the clock stays at 0; when the hold lifts it starts from 0.
setup
echo "test hold" > "$T/run/heavy-build.hold"
run_hb
sleep 7
alive=0; kill -0 "$hbpid" 2>/dev/null && alive=1
check "hold: still waiting after 7 s (over 2x HEAVY_BUILD_WAIT)" '(( alive == 1 ))'
rm -f "$T/run/heavy-build.hold"
lifted=$SECONDS
wait "$hbpid"; rc=$?
took=$(( SECONDS - lifted ))
check "hold lifted: gives up with exit 75" '(( rc == 75 ))'
check "hold lifted: clock starts from 0 (gave up ${took}s after lift, want 2..10)" '(( took >= 2 && took <= 10 ))'
check "refuse is logged with stuck_s at about 3" 'grep -q "decision=refuse.*stuck_s=[3-5] " "$T/state/heavy-build/shadow.log"'
teardown

exit "$fail"
