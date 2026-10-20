#!/usr/bin/env bash
# Tests for heavy-build's give-up clock, the manager hold file, estimates,
# classes and the critical-first switch.
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

# Runs heavy-build in the sandbox in the background; sets hbpid. Arguments
# are extra VAR=value settings for its environment.
run_hb() {
  (cd "$T/work" && exec env -u HEAVY_BUILD_MODE -u HEAVY_BUILD_ALLOW_RERUN \
    -u HEAVY_BUILD_RERUN_FAILS -u HEAVY_BUILD_RERUN_SECS \
    XDG_RUNTIME_DIR="$T/run" XDG_STATE_HOME="$T/state" XDG_CONFIG_HOME="$T/config" \
    HB_CGROUP="$T/cg" HB_MACHINE_SESSION=/bin/false HEAVY_BUILD_PRIORITY=normal \
    HEAVY_BUILD_WAIT=3 HEAVY_BUILD_POLL=1 HEAVY_BUILD_FORCE=1 "$@" \
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
check "no hold: says exit 75, nothing ran, and the next step" 'grep -q "heavy-build: exit 75, not run: gave up after .*Nothing ran. Do not resubmit at once; try again later or tell the manager session." "$T/out"'
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

# 4. A hold whose expires= time has passed counts as gone, and says so once.
setup
printf 'expired test hold\nexpires=%s\n' "$(( EPOCHSECONDS - 60 ))" > "$T/run/heavy-build.hold"
run_hb
start=$SECONDS
wait "$hbpid"; rc=$?
check "expired hold: gives up with exit 75 like no hold" '(( rc == 75 ))'
check "expired hold: gives up within 10 s" '(( SECONDS - start <= 10 ))'
check "expired hold: logged once" '(( $(grep -c "event=hold-expired.*hold expired" "$T/state/heavy-build/shadow.log") == 1 ))'
teardown

# 5. expires= at the start of the first line: the hold holds until then.
setup
echo "expires=$(( EPOCHSECONDS + 6 )) short test hold" > "$T/run/heavy-build.hold"
run_hb
start=$SECONDS
sleep 5
alive=0; kill -0 "$hbpid" 2>/dev/null && alive=1
check "hold with expires: still waiting before it expires" '(( alive == 1 ))'
wait "$hbpid"; rc=$?
took=$(( SECONDS - start ))
check "hold with expires: gives up with 75 after it expires (took ${took}s, want 8..16)" '(( rc == 75 && took >= 8 && took <= 16 ))'
check "hold with expires: logged once" '(( $(grep -c "event=hold-expired" "$T/state/heavy-build/shadow.log") == 1 ))'
check "hold file is left in place" '[[ -e $T/run/heavy-build.hold ]]'
teardown

# 10. The rerun guard, end to end. heavy-build runs `true` in $T/work, so its
# history key is the hash of that directory and command.
hkey() { printf '%s\0' "$T/work" true | md5sum | cut -c1-8; }
hrow() {  # seconds_ago exit reason [state] ; appends a history line for `true` in $T/work
  local st=
  (( $# >= 4 )) && st=$'\t'$4
  mkdir -p "$T/state/heavy-build"
  printf '%s\tother\t%s\t10\t5\t1000\t%s\t%s\t%s\t%s%s\n' "$(( EPOCHSECONDS - $1 ))" "$(hkey)" "$2" "$3" 19327352832 17179869184 "$st" >> "$T/state/heavy-build/history.tsv"
}
setup
hrow 300 1 fail -
hrow 200 1 fail -
run_hb
start=$SECONDS
wait "$hbpid"; rc=$?
check "rerun guard: two fails outside git, then refused with exit 76 (got $rc)" '(( rc == 76 ))'
check "rerun guard: refused at once" '(( SECONDS - start <= 2 ))'
check "rerun guard: starts with exit 76 and says to filter" 'grep -q "heavy-build: exit 76, not run: this exact command failed.*rerun only the failing test with a filter" "$T/out"'
check "rerun guard: says why and how to override" 'grep -q "failed 2 times in a row in the last 30 min with no change in $T/work; read the last log.*HEAVY_BUILD_ALLOW_RERUN=1" "$T/out"'
check "rerun guard: logs decision=rerun-refuse" 'grep -q "decision=rerun-refuse reason=\"rerun: failed 2 times" "$T/state/heavy-build/shadow.log"'
run_hb HEAVY_BUILD_ALLOW_RERUN=1
wait "$hbpid"; rc=$?
check "rerun guard: HEAVY_BUILD_ALLOW_RERUN=1 lets it queue (gives up with 75, got $rc)" '(( rc == 75 ))'
check "rerun guard: the override is logged" 'grep -q "event=rerun-allowed fails=2" "$T/state/heavy-build/shadow.log"'
run_hb HEAVY_BUILD_RERUN_FAILS=0
wait "$hbpid"; rc=$?
check "rerun guard: HEAVY_BUILD_RERUN_FAILS=0 turns it off (got $rc)" '(( rc == 75 ))'
hrow 100 0 ok -
run_hb
wait "$hbpid"; rc=$?
check "rerun guard: a success after the fails resets it (got $rc)" '(( rc == 75 ))'
teardown

# In a git tree: a new commit or an edit since the last failure lets it run.
setup
G1() { git -C "$T/work" -c user.name=t -c user.email=t@t "$@" >/dev/null 2>&1; }
G1 init -q && echo a > "$T/work/f" && G1 add f && G1 commit -qm one
tst() { (cd "$T/work" && eval "$(sed -n '/^tree_state()/,/^}/p' "$HB")" && tree_state); }
s1=$(tst)
check "tree state: HEAD plus a status hash in a git tree (got '$s1')" '[[ $s1 =~ ^[0-9a-f]{12}-[0-9a-f]{8}$ ]]'
hrow 300 1 fail "$s1"
hrow 200 1 fail "$s1"
run_hb
wait "$hbpid"; rc=$?
check "rerun guard: two fails with the same tree state, refused (got $rc)" '(( rc == 76 ))'
echo b > "$T/work/f"
s2=$(tst)
check "tree state: an edit changes it (got '$s2')" '[[ $s2 != "$s1" ]]'
run_hb
wait "$hbpid"; rc=$?
check "rerun guard: an edit since the last failure lets it run (got $rc)" '(( rc == 75 ))'
G1 commit -qam two
s3=$(tst)
check "tree state: a new commit changes HEAD (got '$s3')" '[[ ${s3:0:12} != "${s1:0:12}" ]]'
run_hb
wait "$hbpid"; rc=$?
check "rerun guard: a new HEAD since the last failure lets it run (got $rc)" '(( rc == 75 ))'
teardown

# rerun_check against fake history lines.
R=$(mktemp -d "${TMPDIR:-/var/tmp}/hb-test.XXXXXX")
T=$R; : > "$T/out"
rr() {  # state ; prints rerun_check output
  (
    HIST=$R/hist RERUN_FAILS=${RF:-2} RERUN_SECS=1800
    eval "$(sed -n '/^rerun_check()/,/^}/p' "$HB")"
    rerun_check k "$1"
  )
}
rl() { printf '%s\tother\tk\t10\t5\t1000\t%s\t%s\t1\t1\t%s\n' "$(( EPOCHSECONDS - $1 ))" "$2" "$3" "$4" >> "$R/hist"; }
: > "$R/hist"; rl 900 1 fail S; rl 600 2 fail S
out=$(rr S)
check "rerun_check: two fails, same state, refused (got '$out')" '[[ $out == "2 600" ]]'
out=$(rr S2)
check "rerun_check: a different state allows it (got '$out')" '[[ -z $out ]]'
out=$(rr -)
check "rerun_check: unknown current state falls back to time only (got '$out')" '[[ $out == "2 600" ]]'
: > "$R/hist"; rl 900 1 fail S; rl 800 0 ok S; rl 600 1 fail S
out=$(rr S)
check "rerun_check: fail, ok, fail is not two in a row (got '$out')" '[[ -z $out ]]'
: > "$R/hist"; rl 2000 1 fail S; rl 600 1 fail S
out=$(rr S)
check "rerun_check: a fail older than 30 min does not count (got '$out')" '[[ -z $out ]]'
: > "$R/hist"; rl 900 1 fail S; rl 600 1 cancelled S
out=$(rr S)
check "rerun_check: a cancelled run ends the streak (got '$out')" '[[ -z $out ]]'
: > "$R/hist"; rl 600 1 fail S
out=$(rr S)
check "rerun_check: one fail is not enough (got '$out')" '[[ -z $out ]]'
: > "$R/hist"
printf '%s\tother\tk\t10\t5\t1000\t1\tfail\t1\t1\n' "$(( EPOCHSECONDS - 900 ))" "$(( EPOCHSECONDS - 600 ))" >> "$R/hist"
out=$(rr S)
check "rerun_check: lines from before column 11 never refuse (got '$out')" '[[ -z $out ]]'
: > "$R/hist"; rl 900 1 fail S; rl 700 1 fail S; rl 600 1 fail S
out=$(RF=3 rr S)
check "rerun_check: HEAVY_BUILD_RERUN_FAILS=3 needs three (got '$out')" '[[ $out == "3 600" ]]'
rm -rf -- "$R"

# 3. The wineserver check uses the job's WINEPREFIX, and never guesses
# ~/.wine for a Wine process without one. The functions are taken from
# heavy-build and run against a fake /proc, so no Wine runs.
W=$(mktemp -d "${TMPDIR:-/var/tmp}/hb-test.XXXXXX")
mkdir -p "$W/proc" "$W/winetmp" "$W/home/.wine" "$W/pfxA" "$W/pfxB" "$W/scope"
fakeproc() {  # pid comm [env...]
  local p=$1 c=$2; shift 2
  mkdir -p "$W/proc/$p"
  echo "$c" > "$W/proc/$p/comm"
  echo "0::/user.slice/x" > "$W/proc/$p/cgroup"
  if (( $# )); then printf '%s\0' "$@" > "$W/proc/$p/environ"; else : > "$W/proc/$p/environ"; fi
}
fakeproc 101 app.exe "WINEPREFIX=$W/pfxA" PATH=/usr/bin
fakeproc 102 services.exe PATH=/usr/bin
printf '101\n102\n' > "$W/scope/cgroup.procs"
wo() {  # job-WINEPREFIX (or -) ; prints wine_orphans output on one line
  (
    PROC=$W/proc WINE_TMP=$W/winetmp HOME=$W/home
    eval "$(grep -m1 '^WINE_LEFTOVERS=' "$HB")"
    eval "$(sed -n '/^wine_server_dir()/,/^}/p;/^wineservers_for()/,/^}/p;/^wine_orphans()/,/^}/p' "$HB")"
    if [[ $1 == - ]]; then unset WINEPREFIX; else export WINEPREFIX=$1; fi
    wine_orphans "$W/scope" | tr '\n' ' '
  )
}
fakeproc 201 wineserver
sdir=$(PROC=$W/proc WINE_TMP=$W/winetmp; eval "$(sed -n '/^wine_server_dir()/,/^}/p' "$HB")"; wine_server_dir "$W/pfxA")
mkdir -p "$sdir" && ln -s "$sdir" "$W/proc/201/cwd"
T=$W; : > "$T/out"
out=$(wo -)
check "wine: no job prefix, unknown process skipped, not ~/.wine (got '$out')" '[[ $out == "?1 " ]]'
out=$(wo "$W/pfxA")
check "wine: job prefix with a live wineserver is no orphan (got '$out')" '[[ -z $out ]]'
out=$(wo "$W/pfxB")
check "wine: job prefix with only Wine service processes left is shutting down, no orphan (got '$out')" '[[ -z $out ]]'
fakeproc 103 testhost.exe PATH=/usr/bin
printf '101\n102\n103\n' > "$W/scope/cgroup.procs"
out=$(wo "$W/pfxB")
check "wine: job prefix with a test client and no wineserver is an orphan (got '$out')" '[[ $out == "$W/pfxB " ]]'
printf '101\n102\n' > "$W/scope/cgroup.procs"
rm -f "$W/proc/201/cwd"
out=$(wo -)
check "wine: a process's own WINEPREFIX that is not the job's is only noted (got '$out')" '[[ $out == "~$W/pfxA ?1 " ]]'
out=$(wo "$W/pfxA")
check "wine: the job's own prefix without a wineserver is an orphan (got '$out')" '[[ $out == "$W/pfxA " ]]'
rm -rf -- "$W"

# 3b. Only the run's own prefixes count. wine_own lists them, wine_fb is the
# prefix for a process without WINEPREFIX, wine_runs the base of run-tests.sh's
# -run<pid> fallback.
W=$(mktemp -d "${TMPDIR:-/var/tmp}/hb-test.XXXXXX")
mkdir -p "$W/proc" "$W/winetmp" "$W/home" "$W/own" "$W/own-run42" "$W/other" "$W/scope"
T=$W; : > "$T/out"
wo2() {  # own fb runs ; prints wine_orphans output on one line
  (
    PROC=$W/proc WINE_TMP=$W/winetmp HOME=$W/home
    eval "$(grep -m1 '^WINE_LEFTOVERS=' "$HB")"
    eval "$(sed -n '/^wine_server_dir()/,/^}/p;/^wineservers_for()/,/^}/p;/^wine_orphans()/,/^}/p' "$HB")"
    unset WINEPREFIX
    wine_own=$1 wine_fb=$2 wine_runs=$3
    wine_orphans "$W/scope" | tr '\n' ' '
  )
}
fakeproc 401 testhost.exe "WINEPREFIX=$W/other"
fakeproc 402 winedevice.exe "WINEPREFIX=$W/own"
printf '401\n402\n' > "$W/scope/cgroup.procs"
out=$(wo2 "$W/own" "" "")
check "wine own: another prefix without a wineserver is only noted, own leftovers are no orphan (got '$out')" '[[ $out == "~$W/other " ]]'
fakeproc 403 dotnet.exe "WINEPREFIX=$W/own/"
printf '401\n402\n403\n' > "$W/scope/cgroup.procs"
out=$(wo2 "$W/own" "" "")
check "wine own: own prefix with a test client and no wineserver is an orphan (got '$out')" '[[ $out == "$W/own ~$W/other " ]]'
fakeproc 404 testhost.exe "WINEPREFIX=$W/own-run42"
printf '404\n' > "$W/scope/cgroup.procs"
out=$(wo2 "$W/own" "" "$W/own")
check "wine own: run-tests.sh's <prefix>-run<pid> counts as own (got '$out')" '[[ $out == "$W/own-run42 " ]]'
out=$(wo2 "$W/x"$'\n'"$W/own-run42" "" "")
check "wine own: a wine: key prefix in the list counts as own (got '$out')" '[[ $out == "$W/own-run42 " ]]'
out=$(wo2 "$W/own" "" "")
check "wine own: <prefix>-run<pid> without wine_runs is another prefix (got '$out')" '[[ $out == "~$W/own-run42 " ]]'
fakeproc 405 testhost.exe
printf '405\n' > "$W/scope/cgroup.procs"
out=$(wo2 "$W/own" "$W/own" "")
check "wine own: a process without WINEPREFIX uses wine_fb (got '$out')" '[[ $out == "$W/own " ]]'
out=$(wo2 "$W/own" "" "$W/own")
check "wine own: with no wine_fb it is skipped, not guessed (got '$out')" '[[ $out == "?1 " ]]'
rm -r -f -- "$W"

# 3c. sample_scope end to end with HEAVY_BUILD_WINE_ORPHAN=stop: a run that
# stops a second prefix of its own is left alone; a run whose own wineserver
# dies is warned and stopped. Also the idle Wine log (log only).
X=$(mktemp -d "${TMPDIR:-/var/tmp}/hb-test.XXXXXX")
mkdir -p "$X/proc" "$X/winetmp" "$X/home" "$X/own" "$X/second" "$X/bs/u.scope"
xproc() {  # pid comm [env...]
  local p=$1 c=$2; shift 2
  mkdir -p "$X/proc/$p"
  echo "$c" > "$X/proc/$p/comm"
  echo "0::/user.slice/x" > "$X/proc/$p/cgroup"
  if (( $# )); then printf '%s\0' "$@" > "$X/proc/$p/environ"; else : > "$X/proc/$p/environ"; fi
}
echo 1000000 > "$X/bs/u.scope/memory.current"
echo 'populated 1' > "$X/bs/u.scope/cgroup.events"
# ss PLAN: one sample per word: i (no CPU used), a (10 s of CPU), s (sleep
# 1.2 s, then no CPU). Settings: OWN, AGO (s since last activity), IDLE, CLS.
ss() {
  (
    PROC=$X/proc WINE_TMP=$X/winetmp HOME=$X/home BSLICE=$X/bs unit=u cmdline=x
    eval "$(sed -n '/^WINE_LEFTOVERS=/p;/^now_us()/p;/^wine_server_dir()/,/^}/p;/^wineservers_for()/,/^}/p;/^wine_orphans()/,/^}/p;/^sample_scope()/,/^}/p' "$HB")"
    say() { echo "say: $*"; }
    log_line() { echo "log: $*"; }
    systemctl() { echo "systemctl $*"; }
    write_state() { :; }
    psi_watch() { :; }
    unset WINEPREFIX
    S_t=() S_u=() s_lo=0 peak=0 stalled_cpu=0 stalled_wine=0 stall_warned= orphan_seen=0 orphan_since=
    orphan_warned= orphan_stopped= orph_unknown_logged= orph_other_logged= wine_idle_logged=
    STALL_SECS=600 WINE_IDLE_SECS=${IDLE:-900} ORPHAN_STOP_SECS=0 HEAVY_BUILD_WINE_ORPHAN=stop
    cls=${CLS:-wine-run-tests} wine_own=${OWN-} wine_fb=${OWN-} wine_runs= wine_main=${OWN-}
    last_active=$(( $(now_us) - ${AGO:-0} * 1000000 ))
    local u=1000 w
    for w in $1; do
      [[ $w == a ]] && u=$(( u + 10000000 ))
      [[ $w == s ]] && sleep 1.2
      echo "usage_usec $u" > "$X/bs/u.scope/cpu.stat"
      sample_scope
      sleep 0.01
    done
  )
}
xproc 501 wineserver
sdir=$(PROC=$X/proc WINE_TMP=$X/winetmp; eval "$(sed -n '/^wine_server_dir()/,/^}/p' "$HB")"; wine_server_dir "$X/own")
mkdir -p "$sdir" && ln -s "$sdir" "$X/proc/501/cwd"
xproc 502 dotnet.exe "WINEPREFIX=$X/own"
xproc 503 winedevice.exe "WINEPREFIX=$X/second"
xproc 504 services.exe "WINEPREFIX=$X/second"
xproc 505 explorer.exe "WINEPREFIX=$X/second"
printf '502\n503\n504\n505\n' > "$X/bs/u.scope/cgroup.procs"
T=$X
OWN=$X/own ss "i i i i" > "$X/out1"; cp "$X/out1" "$T/out"
check "wine stop: a second prefix the run stopped itself gives no warning" '! grep -q "wineserver for" "$X/out1"'
check "wine stop: and no stop with HEAVY_BUILD_WINE_ORPHAN=stop" '! grep -q "^systemctl" "$X/out1"'
check "wine stop: it is logged once as event=wine-orphan-other" '(( $(grep -c "event=wine-orphan-other unit=u prefix=$X/second " "$X/out1") == 1 ))'
xproc 506 testhost.exe "WINEPREFIX=$X/second"
printf '502\n503\n506\n' > "$X/bs/u.scope/cgroup.procs"
OWN=$X/own ss "i i i" > "$X/out1"; cp "$X/out1" "$T/out"
check "wine stop: even a client left in the second prefix stops nothing" '! grep -q "wineserver for\|^systemctl" "$X/out1"'
ss "i i i" > "$X/out1"; cp "$X/out1" "$T/out"
check "wine stop: a run with no Wine prefix of its own is never warned or stopped" '! grep -q "wineserver for\|^systemctl" "$X/out1"'
rm -f "$X/proc/501/cwd"
OWN=$X/own ss "i i i" > "$X/out1"; cp "$X/out1" "$T/out"
check "wine stop: the run's own wineserver gone still warns" 'grep -q "say: warning: the wineserver for $X/own is gone" "$X/out1"'
check "wine stop: and HEAVY_BUILD_WINE_ORPHAN=stop still stops it" 'grep -q "^systemctl --user stop u.scope" "$X/out1"'
check "wine stop: logged as event=wine-orphan with the own prefix" 'grep -q "event=wine-orphan unit=u prefix=$X/own " "$X/out1"'
xproc 507 winedevice.exe "WINEPREFIX=$X/own"
printf '507\n504\n' > "$X/bs/u.scope/cgroup.procs"
OWN=$X/own ss "i i i" > "$X/out1"; cp "$X/out1" "$T/out"
check "wine stop: own prefix with only service processes left is shutting down, no warning, no stop" '! grep -q "wineserver for\|^systemctl" "$X/out1"'

# Idle Wine test runs: one line per idle spell, never a stop.
: > "$X/bs/u.scope/cgroup.procs"
OWN=$X/own AGO=5 IDLE=1 ss "i i i a s i i" > "$X/out1"; cp "$X/out1" "$T/out"
check "wine idle: logged once per idle spell (2 spells, 2 lines)" '(( $(grep -c "log: event=wine-idle prefix=$X/own idle_s=[0-9]* unit=u " "$X/out1") == 2 ))'
check "wine idle: one stderr note per spell" '(( $(grep -c "say: note: this Wine test run has used under 0.05 cores" "$X/out1") == 2 ))'
check "wine idle: nothing is stopped" '! grep -q "^systemctl" "$X/out1"'
check "wine idle: idle_s counts from the last activity" 'grep -m1 "event=wine-idle" "$X/out1" | grep -q "idle_s=5 "'
CLS=other OWN=$X/own AGO=5 IDLE=1 ss "i i i" > "$X/out1"; cp "$X/out1" "$T/out"
check "wine idle: not logged for other classes" '! grep -q "event=wine-idle" "$X/out1"'
CLS=wine-run-tests-prebuilt AGO=5 IDLE=1 ss "i i" > "$X/out1"; cp "$X/out1" "$T/out"
check "wine idle: logged for wine-run-tests-prebuilt, prefix - when unknown" 'grep -q "event=wine-idle prefix=- idle_s=" "$X/out1"'
OWN=$X/own AGO=5 ss "i i i" > "$X/out1"; cp "$X/out1" "$T/out"
check "wine idle: not before HB_WINE_IDLE_SECS (900 s)" '! grep -q "event=wine-idle" "$X/out1"'
rm -r -f -- "$X"

# 3d. The wine: lock key of a run-tests.sh command follows the prefix that
# tree's run-tests.sh will use. Three fake trees: the guard script (PR #13900),
# the per-worktree script without the guard (master today), an old script.
K=$(mktemp -d "${TMPDIR:-/var/tmp}/hb-test.XXXXXX")
mkdir -p "$K/proc" "$K/winetmp" "$K/home/.local/share/wineprefixes/motioncatalyst"
for t in lane-new lane-mid lane-old; do
  mkdir -p "$K/$t/tools/wine"
  echo 'WINEPREFIX=${WINEPREFIX:-$HOME/.local/share/wineprefixes/motioncatalyst}' > "$K/$t/tools/wine/wine-env.sh"
done
printf '%s\n' 'WINEPREFIX=$HOME/.local/share/wineprefixes/motioncatalyst-tests-x' 'MC_TESTS_SHARED_PREFIX' > "$K/lane-new/tools/wine/run-tests.sh"
printf '%s\n' 'WINEPREFIX=$HOME/.local/share/wineprefixes/motioncatalyst-tests-x' > "$K/lane-mid/tools/wine/run-tests.sh"
printf '%s\n' 'source wine-env.sh' > "$K/lane-old/tools/wine/run-tests.sh"
SH=$K/home/.local/share/wineprefixes/motioncatalyst
wk() {  # top cmd... ; prints wine_key output; WINEPREFIX etc. come from the caller (- as top: unset WINEPREFIX first)
  (
    cd "$1" || exit 1
    [[ ${NOPFX:-} == 1 ]] && unset WINEPREFIX
    PROC=$K/proc WINE_TMP=$K/winetmp HOME=$K/home
    eval "$(sed -n '/^WINE_DEFAULT_LINE=/p;/^SHARED_WINEPREFIX=/p;/^wine_server_dir()/,/^}/p;/^wineservers_for()/,/^}/p;/^wine_cmd()/,/^}/p;/^run_tests_prefix()/,/^}/p;/^wine_key()/,/^}/p' "$HB")"
    wine_key "$@"
  )
}
T=$K; : > "$T/out"
out=$(WINEPREFIX=$SH wk "$K/lane-new" tools/wine/run-tests.sh Foo.Tests)
check "wine key: new script with WINEPREFIX = shared prefix gets no wine key (got '$out')" '[[ -z $out ]]'
out=$(WINEPREFIX=$SH/ wk "$K/lane-new" bash -c "tools/wine/run-tests.sh Foo.Tests")
check "wine key: same with a trailing slash, inside bash -c (got '$out')" '[[ -z $out ]]'
out=$(WINEPREFIX=$SH MC_TESTS_SHARED_PREFIX=1 wk "$K/lane-new" tools/wine/run-tests.sh Foo.Tests)
check "wine key: new script with MC_TESTS_SHARED_PREFIX=1 keeps wine:<shared> (got '$out')" '[[ $out == "wine:$SH" ]]'
out=$(WINEPREFIX=$K/mine wk "$K/lane-new" tools/wine/run-tests.sh Foo.Tests)
check "wine key: new script with another WINEPREFIX keys on it (got '$out')" '[[ $out == "wine:$K/mine" ]]'
out=$(NOPFX=1 wk "$K/lane-new" tools/wine/run-tests.sh Foo.Tests)
check "wine key: new script without WINEPREFIX gets no wine key (got '$out')" '[[ -z $out ]]'
out=$(WINEPREFIX=$SH wk "$K/lane-mid" tools/wine/run-tests.sh Foo.Tests)
check "wine key: per-worktree script without the guard runs in WINEPREFIX = shared, keeps wine:<shared> (got '$out')" '[[ $out == "wine:$SH" ]]'
out=$(NOPFX=1 wk "$K/lane-mid" tools/wine/run-tests.sh Foo.Tests)
check "wine key: per-worktree script without WINEPREFIX gets no wine key (got '$out')" '[[ -z $out ]]'
out=$(WINEPREFIX=$SH wk "$K/lane-old" tools/wine/run-tests.sh Foo.Tests)
check "wine key: old script with WINEPREFIX = shared keeps wine:<shared> (got '$out')" '[[ $out == "wine:$SH" ]]'
out=$(NOPFX=1 wk "$K/lane-old" tools/wine/run-tests.sh Foo.Tests)
check "wine key: old script without WINEPREFIX keeps the shared default key (got '$out')" '[[ $out == "wine:$SH" ]]'
out=$(WINEPREFIX=$SH wk "$K/lane-old" "$K/lane-new/tools/wine/run-tests.sh" Foo.Tests)
check "wine key: the command's own run-tests.sh decides, not the current tree's (got '$out')" '[[ -z $out ]]'
out=$(WINEPREFIX=$SH wk "$K/lane-new" tools/wine/headless-mc.sh start)
check "wine key: other Wine commands keep wine:<WINEPREFIX> (got '$out')" '[[ $out == "wine:$SH" ]]'
out=$(WINEPREFIX=$SH wk "$K/lane-new" cargo test)
check "wine key: a non-Wine command gets none (got '$out')" '[[ -z $out ]]'
out=$(cd "$K/lane-new" && PROC=$K/proc HOME=$K/home AgentOutputSuffix=-a && unset WINEPREFIX \
  && eval "$(sed -n '/^SHARED_WINEPREFIX=/p;/^run_tests_prefix()/,/^}/p' "$HB")" && run_tests_prefix "$K/lane-new" tools/wine/run-tests.sh)
check "wine key: run_tests_prefix names the per-worktree prefix with the suffix (got '$out')" '[[ $out == "own $K/home/.local/share/wineprefixes/motioncatalyst-tests-lane-new-a" ]]'
rm -r -f -- "$K"

# 6. Memory estimates. class_table and estimate() are taken from heavy-build
# and run against a fake history.tsv.
E=$(mktemp -d "${TMPDIR:-/var/tmp}/hb-test.XXXXXX")
G=1073741824
row() {  # class key peak_gib exit reason [cap_gib]
  local cap=
  [[ -n ${6:-} ]] && cap=$'\t'$(( $6 * G ))
  printf '1\t%s\t%s\t10\t20\t%s\t%s\t%s%s\n' "$1" "$2" "$(( $3 * G ))" "$4" "$5" "$cap" >> "$E/hist"
}
est() {  # key class [sig filtered] ; prints "mem source"
  (
    HIST=$E/hist
    eval "$(sed -n '/^class_table()/,/^}/p;/^EST_MEM_MAX_GIB=/p;/^SIG_DAYS=/p;/^estimate()/,/^}/p' "$HB")"
    estimate "$@" | awk '{print $1, $4}'
  )
}
T=$E; : > "$T/out"
: > "$E/hist"
for i in $(seq 1 20); do row cargo-check "other$i" "$i" 0 ok; done
out=$(est newkey cargo-check)
check "estimate: a new key uses the class p90 (got '$out')" '[[ $out == "19.0 class-history,mem=class-p90" ]]'
row cargo-check lowkey 2 0 ok
row cargo-check lowkey 3 1 fail
out=$(est lowkey cargo-check)
check "estimate: key history (max 3) below the class p90 (18) gets the p90 (got '$out')" '[[ $out == "18.0 history,mem=class-p90" ]]'
: > "$E/hist"
row cargo-check oomkey 3 0 ok
row cargo-check oomkey 8 137 fail
row cargo-check oomkey 30 143 cancelled
out=$(est oomkey cargo-check)
check "estimate: exit 137 without a cap counts as 1.25 x its peak (got '$out')" '[[ $out == "10.0 history,mem=key" ]]'
row cargo-check oomkey 9 1 oom 14
out=$(est oomkey cargo-check)
check "estimate: an OOM run counts as at least its recorded cap (got '$out')" '[[ $out == "14.0 history,mem=key" ]]'
# A run held at its MemoryHigh is censored: it counts as 1.25 x that cap.
rowh() {  # class key peak_gib exit reason max_gib high_gib ; peak may have decimals, high may be -
  awk -v c="$1" -v k="$2" -v p="$3" -v e="$4" -v r="$5" -v m="$6" -v h="$7" -v G="$G" 'BEGIN {
    printf "1\t%s\t%s\t10\t20\t%d\t%s\t%s\t%d%s\n", c, k, p * G, e, r, m * G, (h == "-" ? "" : sprintf("\t%d", h * G)) }' >> "$E/hist"
}
: > "$E/hist"
rowh cargo-check capkey 16 0 ok 18 16
out=$(est capkey cargo-check)
check "estimate: an ok run at 100% of its 16 GiB MemoryHigh counts as 20 GiB (got '$out')" '[[ $out == "20.0 history,mem=key" ]]'
: > "$E/hist"
rowh cargo-check capkey 15.7 1 fail 18 16
out=$(est capkey cargo-check)
check "estimate: a failed run at 98% of MemoryHigh counts as capped too (got '$out')" '[[ $out == "20.0 history,mem=key" ]]'
: > "$E/hist"
rowh cargo-check capkey 15.6 0 ok 18 16
out=$(est capkey cargo-check)
check "estimate: a run at 97.5% of MemoryHigh keeps its own peak (got '$out')" '[[ $out == "15.6 history,mem=key" ]]'
: > "$E/hist"
rowh cargo-check capkey 16 0 ok 18 -
out=$(est capkey cargo-check)
check "estimate: an older line without column 10 uses MemoryMax minus 2 GiB as the cap (got '$out')" '[[ $out == "20.0 history,mem=key" ]]'
: > "$E/hist"
rowh cargo-check capkey 10 0 ok 18 16
out=$(est capkey cargo-check)
check "estimate: a run well under its cap keeps its own peak (got '$out')" '[[ $out == "10.0 history,mem=key" ]]'
: > "$E/hist"
rowh cargo-check capkey 20 0 ok 24 20
out=$(est capkey cargo-check)
check "estimate: a capped run never goes past the 22 GiB estimate cap (got '$out')" '[[ $out == "22.0 history,mem=cap" ]]'
: > "$E/hist"
for i in $(seq 1 6); do row wine-run-tests "w$i" 2 0 ok; done
out=$(est newkey wine-run-tests)
check "estimate: the class floor (6) wins over a lower p90 (got '$out')" '[[ $out == "6.0 class-history,mem=floor" ]]'
for i in $(seq 7 20); do row wine-run-tests "w$i" 2 0 ok; done
row wine-run-tests leakkey 17 0 ok
out=$(est leakkey wine-run-tests)
check "estimate: a key that used 17 GiB keeps its own peak over the floor (got '$out')" '[[ $out == "17.0 history,mem=key" ]]'
: > "$E/hist"
out=$(est newkey wine-run-tests)
check "estimate: a new wine-run-tests key with no class history gets 6 GiB (got '$out')" '[[ $out == "6.0 class,mem=class" ]]'
out=$(est newkey wine-run-tests-prebuilt)
check "estimate: a new wine-run-tests-prebuilt key gets 3 GiB (got '$out')" '[[ $out == "3.0 class,mem=class" ]]'
for i in $(seq 1 6); do row wine-run-tests-prebuilt "p$i" 1 0 ok; done
out=$(est newkey wine-run-tests-prebuilt)
check "estimate: the prebuilt floor (3) wins over a lower p90 (got '$out')" '[[ $out == "3.0 class-history,mem=floor" ]]'
row wine-run-tests bigkey 30 0 ok
out=$(est bigkey wine-run-tests)
check "estimate: never above the 22 GiB scope cap (got '$out')" '[[ $out == "22.0 history,mem=cap" ]]'
out=$(est newkey jb-inspectcode)
check "estimate: a new jb-inspectcode key gets 18 GiB (got '$out')" '[[ $out == "18.0 class,mem=class" ]]'
for i in $(seq 1 6); do row jb-inspectcode "j$i" 4 0 ok; done
out=$(est newkey jb-inspectcode)
check "estimate: the jb-inspectcode floor (18) wins over a lower p90 (got '$out')" '[[ $out == "18.0 class-history,mem=floor" ]]'
out=$(est newkey dotnet-build-sln)
check "estimate: a new dotnet-build-sln key gets 16 GiB (got '$out')" '[[ $out == "16.0 class,mem=class" ]]'
for i in $(seq 1 5); do row dotnet-build-sln "s$i" 7 0 ok; done
out=$(est newkey dotnet-build-sln)
check "estimate: dotnet-build-sln uses its own p90 once it has 5 runs (got '$out')" '[[ $out == "7.0 class-history,mem=class-p90" ]]'

# Filtered Wine test runs are estimated from their sig (history column 12).
rows() {  # class key peak_gib sig [age_s] [max_gib high_gib] ; peak may have decimals
  awk -v c="$1" -v k="$2" -v p="$3" -v s="$4" -v a="${5:-60}" -v m="${6:-24}" -v h="${7:-22}" -v now="$EPOCHSECONDS" -v G="$G" 'BEGIN {
    printf "%d\t%s\t%s\t10\t20\t%d\t0\tok\t%d\t%d\t-\t%s\n", now - a, c, k, p * G, m * G, h * G, s }' >> "$E/hist"
}
classrows() { local i; for i in $(seq 1 20); do rows wine-run-tests "c$i" "$i" other; done; }
: > "$E/hist"; classrows
out=$(est newkey wine-run-tests)
check "sig: without a sig the class p90 still decides (got '$out')" '[[ $out == "19.0 class-history,mem=class-p90" ]]'
out=$(est newkey wine-run-tests sigA 1)
check "sig: a filtered run with no sig history gets the class p75 (got '$out')" '[[ $out == "16.0 class-history,mem=class-p75" ]]'
for i in 1 2 3 4; do rows wine-run-tests "a$i" 7 sigA; done
out=$(est newkey wine-run-tests sigA 1)
check "sig: under 5 sig runs falls back to the class p75 (got '$out')" '[[ $out == "15.0 class-history,mem=class-p75" ]]'
rows wine-run-tests a5 7 sigA
out=$(est newkey wine-run-tests sigA 1)
check "sig: 5 sig runs use their p90 (got '$out')" '[[ $out == "7.0 class-history,mem=sig-p90" ]]'
rows wine-run-tests a6 17 sigA 1300000
out=$(est newkey wine-run-tests sigA 1)
check "sig: a sig run older than 14 days does not count (got '$out')" '[[ $out == "7.0 class-history,mem=sig-p90" ]]'
rows wine-run-tests a7 18 sigA 60 20 16
out=$(est newkey wine-run-tests sigA 1)
check "sig: a capped sig run counts as 1.25 x its MemoryHigh (got '$out')" '[[ $out == "20.0 class-history,mem=sig-p90" ]]'
: > "$E/hist"; classrows
rows wine-run-tests big 12 sigB
out=$(est newkey wine-run-tests sigB 1)
check "sig: under 5 sig runs, a sig peak under the class p75 keeps the p75 (got '$out')" '[[ $out == "15.0 class-history,mem=class-p75" ]]'
rows wine-run-tests big 21 sigB
out=$(est newkey wine-run-tests sigB 1)
check "sig: under 5 sig runs, the highest sig peak wins when over the p75 (got '$out')" '[[ $out == "21.0 class-history,mem=sig-max" ]]'
out=$(est big wine-run-tests)
check "sig: a full-suite run keeps the key peak over the class p90 (got '$out')" '[[ $out == "21.0 history,mem=key" ]]'
out=$(est big wine-run-tests sigB 0)
check "sig: a run without a filter ignores its sig (got '$out')" '[[ $out == "21.0 history,mem=key" ]]'
: > "$E/hist"
for i in $(seq 1 20); do rows wine-run-tests "c$i" 2 other; done
for i in $(seq 1 9); do rows wine-run-tests "s$i" 3 sigC; done
out=$(est newkey wine-run-tests sigC 1)
check "sig: under 10 sig runs, the 6 GiB class floor holds (got '$out')" '[[ $out == "6.0 class-history,mem=floor" ]]'
rows wine-run-tests s10 3 sigC
out=$(est newkey wine-run-tests sigC 1)
check "sig: 10 sig runs may go down to 4 GiB (got '$out')" '[[ $out == "4.0 class-history,mem=floor" ]]'
for i in $(seq 1 10); do rows wine-run-tests "d$i" 4.5 sigD; done
out=$(est newkey wine-run-tests sigD 1)
check "sig: 10 sig runs between 4 and 6 GiB use their own p90 (got '$out')" '[[ $out == "4.5 class-history,mem=sig-p90" ]]'
for i in $(seq 1 10); do rows wine-run-tests-prebuilt "e$i" 1 sigE; done
out=$(est newkey wine-run-tests-prebuilt sigE 1)
check "sig: the 3 GiB prebuilt floor is not raised to 4 (got '$out')" '[[ $out == "3.0 class-history,mem=floor" ]]'

# append_history writes MemoryHigh in column 10 and logs a capped run.
ah() {  # peak_bytes ; prints "col9 col10 capped-log-lines"
  (
    STATE=$E/st HIST=$E/st/history.tsv MODE=live jobid=t unit=u cmdline=x est_mem=6.6 cls=dotnet-build hash=h
    start_ts=$EPOCHSECONDS usec_last=1000000 cap_high=16 peak=$1
    eval "$(sed -n '/^say()/p;/^log_line()/,/^}/p;/^append_history()/,/^}/p' "$HB")"
    mkdir -p "$E/st"; : > "$HIST"; : > "$E/st/live.log"
    append_history 0 ok 2>/dev/null
    echo "$(cut -f9,10 "$HIST" | tr '\t' ' ') $(grep -c event=capped "$E/st/live.log")"
  )
}
out=$(ah $(( 16 * G )))
check "history: a run at its cap gets MemoryHigh in column 10 and event=capped (got '$out')" '[[ $out == "$(( 18 * G )) $(( 16 * G )) 1" ]]'
out=$(ah $(( 8 * G )))
check "history: a run under its cap is not logged as capped (got '$out')" '[[ $out == "$(( 18 * G )) $(( 16 * G )) 0" ]]'
out=$(
  STATE=$E/st HIST=$E/st/history.tsv MODE=live jobid=t unit=u cmdline=x est_mem=6 cls=wine-run-tests hash=h
  start_ts=$EPOCHSECONDS usec_last=1000000 cap_high=16 peak=$G sig=abc12345 tstate=
  eval "$(sed -n '/^say()/p;/^log_line()/,/^}/p;/^append_history()/,/^}/p' "$HB")"
  : > "$HIST"; append_history 0 ok 2>/dev/null; cut -f11,12 "$HIST" | tr '\t' ' '
)
check "history: the Wine test sig goes in column 12 (got '$out')" '[[ $out == "- abc12345" ]]'
rm -rf -- "$E"

# 7. Classes for Wine test runs. run-tests.sh builds nothing when every
# project it is given ends in .dll.
cls() {
  (
    eval "$(sed -n '/^wine_tests_prebuilt()/,/^}/p;/^dotnet_sln()/,/^}/p;/^classify()/,/^}/p' "$HB")"
    classify "$@"
  )
}
T=$(mktemp -d "${TMPDIR:-/var/tmp}/hb-test.XXXXXX"); : > "$T/out"
for c in \
  "wine-run-tests|tools/wine/run-tests.sh" \
  "wine-run-tests|tools/wine/run-tests.sh SwingCatalyst.Test.Unit.Windows" \
  "wine-run-tests|tools/wine/run-tests.sh --filter Foo SwingCatalyst.Test.Unit.Windows" \
  "wine-run-tests|tools/wine/run-tests.sh a/Foo.Tests.dll SwingCatalyst.Test.Unit.Windows" \
  "wine-run-tests|./tools/wine/run-tests.sh --filter x.dll" \
  "wine-run-tests-prebuilt|tools/wine/run-tests.sh a/b/Foo.Tests.dll" \
  "wine-run-tests-prebuilt|./tools/wine/run-tests.sh --filter Name~Bar --include-gpu a/Foo.dll b/Bar.dll" \
  "wine-run-tests-prebuilt|./tools/wine/run-tests.sh --filter=Name~Bar a/Foo.dll" \
  "wine-run-tests-prebuilt|bash -c tools/wine/run-tests.sh a/Foo.dll && echo done" \
  "jb-inspectcode|jb inspectcode src/motioncatalyst/MotionCatalyst.sln" \
  "jb-inspectcode|inspectcode Foo.sln --output=x.xml" \
  "jb-inspectcode|dotnet jb inspectcode Foo.sln" \
  "jb-inspectcode|/opt/jb/inspectcode.sh Foo.sln" \
  "dotnet-build-sln|dotnet build Foo.sln" \
  "dotnet-build-sln|dotnet test Foo.slnx -c Release" \
  "dotnet-build-sln|dotnet msbuild -m src/motioncatalyst/MotionCatalyst.sln" \
  "dotnet-build-sln|msbuild /m /p:Configuration=Release /home/x/Foo.sln" \
  "dotnet-build-sln|bash -c dotnet build Foo.sln; echo done" \
  "dotnet-build|dotnet build Foo.csproj" \
  "dotnet-test|dotnet test Foo.Tests.csproj" \
  "dotnet-build|dotnet publish Foo.sln" ; do
  want=${c%%|*} cmd=${c#*|}
  # shellcheck disable=SC2086
  out=$(cd "$T" && cls $cmd)
  check "classify: '$cmd' is $want (got '$out')" '[[ $out == "$want" ]]'
done
# No project argument, or a directory: MSBuild picks the .sln when the
# directory has one and no project file.
mkdir -p "$T/s" "$T/p" "$T/b" && : > "$T/s/A.sln" && : > "$T/p/A.csproj" && : > "$T/b/A.slnx" && : > "$T/b/A.csproj"
out=$(cd "$T/s" && cls dotnet build)
check "classify: 'dotnet build' in a dir with only a .sln is dotnet-build-sln (got '$out')" '[[ $out == dotnet-build-sln ]]'
out=$(cd "$T/s" && cls dotnet test --filter X)
check "classify: 'dotnet test --filter X' there is dotnet-build-sln (got '$out')" '[[ $out == dotnet-build-sln ]]'
out=$(cd "$T" && cls dotnet build -c Release s)
check "classify: 'dotnet build -c Release s' (a dir with a .sln) is dotnet-build-sln (got '$out')" '[[ $out == dotnet-build-sln ]]'
out=$(cd "$T/p" && cls dotnet build)
check "classify: 'dotnet build' in a dir with a project file is dotnet-build (got '$out')" '[[ $out == dotnet-build ]]'
out=$(cd "$T/b" && cls dotnet build)
check "classify: 'dotnet build' in a dir with both is dotnet-build (got '$out')" '[[ $out == dotnet-build ]]'
rm -rf -- "$T"

# 7b. Wine test sigs: the same tests from another tree, lane or prefix get the
# same sig; other projects, flags or filters get another.
sg() {
  (
    eval "$(sed -n '/^wine_sig()/,/^}/p' "$HB")"
    wine_sig "$@"
  )
}
a=$(sg wine-run-tests bash tools/wine/run-tests.sh SwingCatalyst.Test.Unit.Windows --filter 'FullyQualifiedName~A|FullyQualifiedName~B')
b=$(sg wine-run-tests /home/x/work/desktop/lane-2/tools/wine/run-tests.sh --filter "FullyQualifiedName~A|FullyQualifiedName~B" SwingCatalyst.Test.Unit.Windows)
c=$(sg wine-run-tests tools/wine/run-tests.sh SwingCatalyst.Test.Unit.Windows --filter FullyQualifiedName~C)
d=$(sg wine-run-tests tools/wine/run-tests.sh SwingCatalyst.Test.Unit.Windows)
e=$(sg wine-run-tests tools/wine/run-tests.sh SwingCatalyst.Test.Unit.Windows --all-categories)
f=$(sg wine-run-tests-prebuilt tools/wine/run-tests.sh --filter=X /a/BUILD/SwingCatalyst.Test.Unit.dll)
g=$(sg wine-run-tests-prebuilt tools/wine/run-tests.sh --filter=X /b/other/SwingCatalyst.Test.Unit.dll)
h=$(sg wine-run-tests tools/wine/run-tests.sh A B --filter-for A=X)
i=$(sg wine-run-tests tools/wine/run-tests.sh B A --filter-for A=X)
check "wine_sig: a filtered run is marked 1 (got '$a')" '[[ $a == "1 "???????? ]]'
check "wine_sig: order, quotes and the tree path do not change the sig ('$a' vs '$b')" '[[ $a == "$b" ]]'
check "wine_sig: another filter gets another sig ('$a' vs '$c')" '[[ $a != "$c" ]]'
check "wine_sig: no filter is marked 0, another flag changes the sig ('$d' vs '$e')" '[[ $d == "0 "???????? && $d != "$e" ]]'
check "wine_sig: a .dll from another build dir has the same sig ('$f' vs '$g')" '[[ $f == "1 "* && $f == "$g" ]]'
check "wine_sig: --filter-for counts as a filter, project order does not matter ('$h' vs '$i')" '[[ $h == "1 "* && $h == "$i" ]]'
out=$(sg wine-run-tests cargo test)
check "wine_sig: no run-tests.sh prints nothing (got '$out')" '[[ -z $out ]]'

# End to end: a filtered run-tests.sh command is estimated from its sig's
# history, logged as mem=sig-p90. The blocker ticket keeps it from starting.
setup
read -r _ s <<< "$(sg wine-run-tests tools/wine/run-tests.sh Foo.Tests --filter Name~Bar)"
mkdir -p "$T/state/heavy-build"
for i in $(seq 1 6); do
  printf '%d\twine-run-tests\tk%d\t10\t20\t%d\t0\tok\t%d\t%d\t-\t%s\n' "$(( EPOCHSECONDS - 60 ))" "$i" "$(( 7 * G ))" "$(( 24 * G ))" "$(( 22 * G ))" "$s" >> "$T/state/heavy-build/history.tsv"
done
(cd "$T/work" && exec env -u HEAVY_BUILD_MODE -u HEAVY_BUILD_ALLOW_RERUN \
  XDG_RUNTIME_DIR="$T/run" XDG_STATE_HOME="$T/state" XDG_CONFIG_HOME="$T/config" \
  HB_CGROUP="$T/cg" HB_MACHINE_SESSION=/bin/false HEAVY_BUILD_PRIORITY=normal \
  HEAVY_BUILD_WAIT=3 HEAVY_BUILD_POLL=1 HEAVY_BUILD_FORCE=1 HEAVY_BUILD_KEY=none \
  "$HB" tools/wine/run-tests.sh Foo.Tests --filter Name~Bar) > "$T/out" 2>&1
check "sig: a filtered run-tests.sh command logs est=7.0G...mem=sig-p90" 'grep -q "est=7.0G/[^ ]*mem=sig-p90)" "$T/state/heavy-build/shadow.log"'
teardown


# 8. The critical-first switch. The admission awk (ADMIT_AWK) and
# critical_first_on are taken from heavy-build and run against fake input.
A=$(mktemp -d "${TMPDIR:-/var/tmp}/hb-test.XXXXXX")
T=$A; : > "$T/out"
printf 'MemAvailable: %d kB\nSwapTotal: 0 kB\nSwapFree: 0 kB\n' $(( 40 * 1048576 )) > "$A/meminfo"
adm() {  # me cf cfslots cfreserve ; R and W lines on stdin ; prints "decision|reason|prioheld"
  local me=$1; shift
  (
    eval "$(sed -n "/^ADMIT_AWK='/,/^}'\$/p" "$HB")"
    awk -v now=1000000 -v me="$me" -v cpuquiet=999 -v cpuhold=30 -v meminfo="${ADM_MEMINFO:-$A/meminfo}" \
      -v mempsifile="${ADM_MEMPSI:-$A/none}" -v swpct="${ADM_SWPCT:-25}" -v swcap="${ADM_SWCAP:-8}" \
      -v slicemax="$A/none" -v slicehigh="$A/none" -v cpupsifile="${ADM_CPUPSI:-$A/none}" -v claudepsifile="$A/none" \
      -v apppsifile="$A/none" -v maxjobs=6 -v cpubudget=28 -v reserve=6 -v maxcpupsi="${ADM_MAXCPUPSI:-75}" -v maxmempsi=5 \
      -v starve=1800 -v solo=8 -v minswap=10 -v warm=120 -v poll=5 -v lowage=1800 -v tcpct=50 \
      -v agesecs=3600 -v ageslots=1 -v maxapp="${ADM_MAXAPP:-2}" -v cf="$1" -v cfslots="$2" -v cfreserve="$3" "$ADMIT_AWK" \
      | awk -F'\t' '{print $1 "|" $3 "|" $5}'
  )
}
RUN_N='R u1 999000 4 2 1000600 4294967296 - 0 normal -'
RUN_C='R u2 999000 4 2 1000600 4294967296 - 0 critical -'
W_N='W 0000000999000000000-1-n 999000 normal 4 2 600 -'
W_L='W 0000000999000000000-1-n 999000 low 4 2 600 -'
W_C='W 0000000999000000000-2-c 999000 critical 4 2 600 -'
W_H='W 0000000999000000000-3-h 999000 high 4 2 600 -'
W_BIG='W 0000000999000000000-1-n 999000 normal 30 2 600 -'
out=$(printf '%s\n' "$RUN_N" "$W_N" | adm 0000000999000000000-1-n 0 1 12)
check "critical-first off: a normal build starts next to a normal one (got '$out')" '[[ $out == start\|fits:* ]]'
out=$(printf '%s\n' "$RUN_N" "$W_N" | adm 0000000999000000000-1-n "" "" "")
check "critical-first unset: same as off (got '$out')" '[[ $out == start\|fits:* ]]'
out=$(printf '%s\n' "$RUN_N" "$W_N" | adm 0000000999000000000-1-n 1 1 12)
check "critical-first: the non-critical slot is full, so a normal build waits, clock held (got '$out')" '[[ $out == "wait|critical-first: 1 normal or low builds run, the limit is 1 while critical builds go first|1" ]]'
out=$(printf '%s\n' "$RUN_N" "$W_L" | adm 0000000999000000000-1-n 1 1 12)
check "critical-first: a low build waits too (got '$out')" '[[ $out == wait\|critical-first:* ]]'
out=$(printf '%s\n' "$RUN_C" "$W_N" | adm 0000000999000000000-1-n 1 1 12)
check "critical-first: a running critical build does not use the non-critical slot (got '$out')" '[[ $out == start\|fits:* ]]'
out=$(printf '%s\n' "$RUN_N" "$W_N" | adm 0000000999000000000-1-n 1 2 12)
check "critical-first: noncrit_slots=2 lets a second normal build start (got '$out')" '[[ $out == start\|fits:* ]]'
out=$(printf '%s\n' "$W_BIG" | adm 0000000999000000000-1-n 0 1 12)
check "critical-first off: a 30 GiB build starts with 40 GiB free (got '$out')" '[[ $out == start\|fits:* ]]'
out=$(printf '%s\n' "$W_BIG" | adm 0000000999000000000-1-n 1 1 12)
check "critical-first: a 30 GiB normal build would leave 10 of 12 GiB, so it waits (got '$out')" '[[ $out == wait\|critical-first:\ needs\ 30.0\ GiB* ]]'
out=$(printf '%s\n' "$W_BIG" | adm 0000000999000000000-1-n 1 1 10)
check "critical-first: reserve_gib=10 lets it start (got '$out')" '[[ $out == start\|fits:* ]]'
out=$(printf '%s\n' "$RUN_N" "$W_C" | adm 0000000999000000000-2-c 1 1 12)
check "critical-first: a critical build is not held by the slot cap (got '$out')" '[[ $out == start\|fits:* ]]'
out=$(printf '%s\n' "$RUN_N" "$W_H" | adm 0000000999000000000-3-h 1 1 12)
check "critical-first: a high build is not held by the slot cap (got '$out')" '[[ $out == start\|fits:* ]]'
out=$(printf '%s\n' 'W 0000000999000000000-2-c 999000 critical 30 2 600 -' | adm 0000000999000000000-2-c 1 1 12)
check "critical-first: a 30 GiB critical build uses the normal reserve (got '$out')" '[[ $out == start\|fits:* ]]'
out=$(printf '%s\n' "$RUN_N" "$W_C" "$W_N" | adm 0000000999000000000-1-n 1 1 12)
check "critical-first: the normal build behind a started critical one still waits (got '$out')" '[[ $out == wait\|critical-first:* ]]'

# The give-up clock under critical-first: a normal or low wait for memory is
# held (prioheld 1) while the switch is on, and runs when it is off.
printf 'MemAvailable: %d kB\nSwapTotal: %d kB\nSwapFree: %d kB\n' $(( 40 * 1048576 )) $(( 10 * 1048576 )) 1048576 > "$A/meminfo-lowswap"
W_36N='W 0000000999000000000-1-n 999000 normal 36 2 600 -'
W_36L='W 0000000999000000000-1-n 999000 low 36 2 600 -'
W_36C='W 0000000999000000000-2-c 999000 critical 36 2 600 -'
W_36H='W 0000000999000000000-3-h 999000 high 36 2 600 -'
out=$(printf '%s\n' "$RUN_N" "$W_36N" | adm 0000000999000000000-1-n 0 2 12)
check "give-up clock: critical-first off, a memory wait runs the clock (got '$out')" '[[ $out == wait\|memory:*\|0 ]]'
out=$(printf '%s\n' "$RUN_N" "$W_36N" | adm 0000000999000000000-1-n 1 2 12)
check "give-up clock: critical-first on, a normal build's memory wait is held (got '$out')" '[[ $out == wait\|memory:*\|1 ]]'
out=$(printf '%s\n' "$RUN_N" "$W_36L" | adm 0000000999000000000-1-n 1 2 12)
check "give-up clock: critical-first on, a low build's memory wait is held (got '$out')" '[[ $out == wait\|memory:*\|1 ]]'
out=$(printf '%s\n' "$RUN_N" "$W_36C" | adm 0000000999000000000-2-c 1 2 12)
check "give-up clock: critical-first on, a critical build's memory wait still runs the clock (got '$out')" '[[ $out == wait\|memory:*\|0 ]]'
out=$(printf '%s\n' "$RUN_N" "$W_36H" | adm 0000000999000000000-3-h 1 2 12)
check "give-up clock: critical-first on, a high build's memory wait still runs the clock (got '$out')" '[[ $out == wait\|memory:*\|0 ]]'
out=$(printf '%s\n' "$RUN_N" "$W_36N" | ADM_MEMINFO=$A/meminfo-lowswap adm 0000000999000000000-1-n 1 2 12)
check "give-up clock: critical-first on, a swap wait still runs the clock (got '$out')" '[[ $out == wait\|swap:*\|0 ]]'

# CPU pressure: 70% passes the 75% default limit, 80% does not.
printf 'some avg10=70.00 avg60=50.00 avg300=40.00 total=1\n' > "$A/cpupsi70"
printf 'some avg10=80.00 avg60=50.00 avg300=40.00 total=1\n' > "$A/cpupsi80"
out=$(printf '%s\n' "$RUN_N" "$W_N" | ADM_CPUPSI=$A/cpupsi70 adm 0000000999000000000-1-n 0 1 12)
check "cpu pressure: 70% is under the 75% limit, so it starts (got '$out')" '[[ $out == start\|fits:* ]]'
out=$(printf '%s\n' "$RUN_N" "$W_N" | ADM_CPUPSI=$A/cpupsi80 adm 0000000999000000000-1-n 0 1 12)
check "cpu pressure: 80% is over the 75% limit, so it waits (got '$out')" '[[ $out == "wait|cpu-pressure: 80.0%, the limit is 75%|0" ]]'
out=$(printf '%s\n' "$RUN_N" "$W_N" | ADM_CPUPSI=$A/cpupsi70 ADM_MAXCPUPSI=60 adm 0000000999000000000-1-n 0 1 12)
check "cpu pressure: a limit of 60% holds a build at 70% (got '$out')" '[[ $out == wait\|cpu-pressure:* ]]'

# 9. Swap headroom. 20 GiB available, a normal build of 16 GiB next to a
# running one: 20 - 16 = 4 is under the 6 GiB reserve without headroom.
printf 'MemAvailable: %d kB\nSwapTotal: %d kB\nSwapFree: %d kB\n' $(( 20 * 1048576 )) $(( 96 * 1048576 )) $(( 64 * 1048576 )) > "$A/meminfo-sw"
printf 'MemAvailable: %d kB\nSwapTotal: %d kB\nSwapFree: %d kB\n' $(( 20 * 1048576 )) $(( 16 * 1048576 )) $(( 16 * 1048576 )) > "$A/meminfo-sw16"
mpsi() { printf 'some avg10=%s avg60=%s avg300=0.50 total=1\nfull avg10=0.00 avg60=0.00 avg300=0.00 total=1\n' "$1" "$2" > "$A/mempsi"; }
W_16='W 0000000999000000000-1-n 999000 normal 16 2 600 -'
mpsi 0.00 0.12
out=$(printf '%s\n' "$RUN_N" "$W_16" | ADM_MEMINFO=$A/meminfo-sw ADM_MEMPSI=$A/mempsi adm 0000000999000000000-1-n 0 1 12)
check "swap headroom: low pressure adds min(25% of 64, 8) = 8 GiB, so it starts and says so (got '$out')" '[[ $out == "start|fits: next in order (+8.0 swap headroom)|0" ]]'
out=$(printf '%s\n' "$RUN_N" "$W_16" | ADM_MEMINFO=$A/meminfo-sw16 ADM_MEMPSI=$A/mempsi adm 0000000999000000000-1-n 0 1 12)
check "swap headroom: 25% of 16 GiB SwapFree adds 4 GiB (got '$out')" '[[ $out == "start|fits: next in order (+4.0 swap headroom)|0" ]]'
W_23='W 0000000999000000000-1-n 999000 normal 23 2 600 -'
out=$(printf '%s\n' "$RUN_N" "$W_23" | ADM_MEMINFO=$A/meminfo-sw ADM_MEMPSI=$A/mempsi adm 0000000999000000000-1-n 0 1 12)
check "swap headroom: shown in the memory reason when it is not enough (got '$out')" '[[ $out == "wait|memory: needs 23.0 GiB; 20.0 available (+8.0 swap headroom), 0.0 still to come for running builds, reserve 6|0" ]]'
mpsi 2.50 0.40
out=$(printf '%s\n' "$RUN_N" "$W_16" | ADM_MEMINFO=$A/meminfo-sw ADM_MEMPSI=$A/mempsi adm 0000000999000000000-1-n 0 1 12)
check "swap headroom: avg10 2.5 adds nothing, so it waits for memory (got '$out')" '[[ $out == "wait|memory: needs 16.0 GiB; 20.0 available, 0.0 still to come for running builds, reserve 6|0" ]]'
mpsi 0.50 1.20
out=$(printf '%s\n' "$RUN_N" "$W_16" | ADM_MEMINFO=$A/meminfo-sw ADM_MEMPSI=$A/mempsi adm 0000000999000000000-1-n 0 1 12)
check "swap headroom: avg60 1.2 adds nothing either (got '$out')" '[[ $out == wait\|memory:* && $out != *headroom* ]]'
out=$(printf '%s\n' "$RUN_N" "$W_16" | ADM_MEMINFO=$A/meminfo-sw ADM_MEMPSI=$A/none adm 0000000999000000000-1-n 0 1 12)
check "swap headroom: no pressure file adds nothing (got '$out')" '[[ $out == wait\|memory:* && $out != *headroom* ]]'
mpsi 0.00 0.00
out=$(printf '%s\n' "$RUN_N" "$W_16" | ADM_MEMINFO=$A/meminfo-sw ADM_MEMPSI=$A/mempsi ADM_SWPCT=0 adm 0000000999000000000-1-n 0 1 12)
check "swap headroom: HEAVY_BUILD_SWAP_HEADROOM_PCT=0 turns it off (got '$out')" '[[ $out == wait\|memory:* && $out != *headroom* ]]'
out=$(printf '%s\n' "$RUN_N" "${W_16/ 16 / 17 }" | ADM_MEMINFO=$A/meminfo-sw ADM_MEMPSI=$A/mempsi ADM_SWCAP=2 adm 0000000999000000000-1-n 0 1 12)
check "swap headroom: HEAVY_BUILD_SWAP_HEADROOM_GIB=2 caps it at 2 GiB (got '$out')" '[[ $out == "wait|memory: needs 17.0 GiB; 20.0 available (+2.0 swap headroom),"* ]]'
out=$(printf '%s\n' "$W_16" | ADM_MEMINFO=$A/meminfo-sw ADM_MEMPSI=$A/mempsi adm 0000000999000000000-1-n 1 1 12)
check "swap headroom: counts in the critical-first reserve too (20 + 8 - 16 = 12) (got '$out')" '[[ $out == "start|fits: next in order (+8.0 swap headroom)|0" ]]'
mpsi 3.00 3.00
out=$(printf '%s\n' "$W_16" | ADM_MEMINFO=$A/meminfo-sw ADM_MEMPSI=$A/mempsi adm 0000000999000000000-1-n 1 1 12)
check "swap headroom: not in the critical-first reserve under pressure (got '$out')" '[[ $out == "wait|critical-first: needs 16.0 GiB; 20.0 available, "* ]]'

# Settings: defaults, the config file, and the environment over the file.
rconf() {  # var... ; prints their values after read_conf
  (
    CONF=$A/hb.conf
    eval "$(sed -n '/^read_conf()/,/^}/p;/^setting()/,/^}/p' "$HB")"
    read_conf
    for v; do printf '%s ' "${!v}"; done
  )
}
rm -f "$A/hb.conf"
out=$(unset HEAVY_BUILD_SWAP_HEADROOM_PCT HEAVY_BUILD_SWAP_HEADROOM_GIB; rconf SWAP_HEADROOM_PCT SWAP_HEADROOM_GIB)
check "settings: swap headroom defaults are 25% and 8 GiB (got '$out')" '[[ $out == "25 8 " ]]'
printf 'HEAVY_BUILD_SWAP_HEADROOM_PCT=10\nHEAVY_BUILD_SWAP_HEADROOM_GIB=4\n' > "$A/hb.conf"
out=$(HEAVY_BUILD_SWAP_HEADROOM_GIB=0 rconf SWAP_HEADROOM_PCT SWAP_HEADROOM_GIB)
check "settings: the file sets them and the environment wins (got '$out')" '[[ $out == "10 0 " ]]'
rm -f "$A/hb.conf"
out=$(unset HEAVY_BUILD_MAX_CPU_PSI; rconf MAX_CPU_PSI)
check "settings: the CPU pressure limit defaults to 75% (got '$out')" '[[ $out == "75 " ]]'
echo HEAVY_BUILD_MAX_CPU_PSI=60 > "$A/hb.conf"
out=$(unset HEAVY_BUILD_MAX_CPU_PSI; rconf MAX_CPU_PSI)
check "settings: HEAVY_BUILD_MAX_CPU_PSI in the file still wins over the default (got '$out')" '[[ $out == "60 " ]]'

cfo() {  # prints "rc cf_on cf_slots cf_reserve expiry-log-lines"
  (
    CRITF=$A/cf STATE=$A/state MODE=live jobid=test critf_expired_logged=
    eval "$(sed -n '/^log_line()/,/^}/p;/^critical_first_on()/,/^}/p' "$HB")"
    critical_first_on; rc=$?
    critical_first_on
    echo "$rc $cf_on $cf_slots $cf_reserve $(cat "$A/state/live.log" 2>/dev/null | grep -c critical-first-expired)"
  )
}
rm -f "$A/cf"
out=$(cfo)
check "critical-first: no switch file means off (got '$out')" '[[ $out == "1 0 1 12 0" ]]'
: > "$A/cf"
out=$(cfo)
check "critical-first: an empty switch file is on with defaults (got '$out')" '[[ $out == "0 1 1 12 0" ]]'
printf 'kpp sprint\nnoncrit_slots=2\nreserve_gib=16\nexpires=%s\n' "$(( EPOCHSECONDS + 600 ))" > "$A/cf"
out=$(cfo)
check "critical-first: reads noncrit_slots, reserve_gib and a future expires (got '$out')" '[[ $out == "0 1 2 16 0" ]]'
printf 'expires=%s kpp sprint\n' "$(( EPOCHSECONDS - 60 ))" > "$A/cf"
out=$(cfo)
check "critical-first: an expired switch is off and logged once (got '$out')" '[[ $out == "1 0 1 12 1" ]]'
check "critical-first: the switch file is left in place" '[[ -e $A/cf ]]'
rm -rf -- "$A"

# append_history trims to HISTORY_LINES (default 20000, kept at 10% over).
H=$(mktemp -d "${TMPDIR:-/var/tmp}/hb-test.XXXXXX")
ah() {  # $1 = HISTORY_LINES value or empty; prints line count after one append
  (
    HIST=$H/hist STATE=$H start_ts=$EPOCHSECONDS EPOCHSECONDS=$EPOCHSECONDS usec_last= peak=0 cls=other hash=k sig=- tstate=-
    [[ -n $1 ]] && HISTORY_LINES=$1
    say() { :; }; log_line() { :; }
    eval "$(sed -n '/^append_history()/,/^}/p' "$HB")"
    append_history 0 ok
    wc -l < "$HIST"
  )
}
seq 1 2000 | sed 's/.*/1\tother\tk\t1\t1\t1\t0\tok/' > "$H/hist"
out=$(ah 1000)
check "history trim: HISTORY_LINES=1000 trims 2,000 lines to 1000 (got '$out')" '[[ $out == 1000 ]]'
seq 1 1050 | sed 's/.*/1\tother\tk\t1\t1\t1\t0\tok/' > "$H/hist"
out=$(ah 1000)
check "history trim: within 10% over the limit nothing is trimmed (got '$out')" '[[ $out == 1051 ]]'
seq 1 5000 | sed 's/.*/1\tother\tk\t1\t1\t1\t0\tok/' > "$H/hist"
out=$(ah "")
check "history trim: default keeps 5,000 lines, no 2,000 cut (got '$out')" '[[ $out == 5001 ]]'
grep -q 'setting HEAVY_BUILD_HISTORY_LINES 20000' "$HB"
check "history trim: HEAVY_BUILD_HISTORY_LINES defaults to 20000 in the settings list" '(( $? == 0 ))'
rm -rf -- "$H"


# 11. App runs (class app-run): detection, options, the app-run cap, the
# --wait-timeout and the --ready-file, and the scope stop when the command ends.
T=$(mktemp -d "${TMPDIR:-/var/tmp}/hb-test.XXXXXX"); : > "$T/out"
for c in \
  "app-run|tools/wine/headless-mc.sh start one --hive /x" \
  "app-run|/home/x/work/desktop/lane/tools/wine/run-mc.sh" \
  "app-run|bash tools/wine/run-mc.sh convert-take-to-raw-data a b" \
  "app-run|wine MotionCatalyst.exe --hiveDir Z:\\h" \
  "app-run|env WINEPREFIX=/p wine64 /b/MotionCatalyst.exe" \
  "app-run|bash -c cd /b && exec wine UiMcpHost.exe --transport http --port 5000" \
  "wine-script|wine SwingCatalyst.Tool.exe" \
  "other|cat MotionCatalyst.exe.config" \
  "other|my-headless-mc.shx start" \
  "wine-run-tests|tools/wine/run-tests.sh MotionCatalyst.Test.UI" ; do
  want=${c%%|*} cmd=${c#*|}
  # shellcheck disable=SC2086
  out=$(cd "$T" && cls $cmd)
  check "classify: '$cmd' is $want (got '$out')" '[[ $out == "$want" ]]'
done
out=$(cd "$T" && CLASS_ARG=app-run cls cargo build)
check "classify: --class app-run wins over the command (got '$out')" '[[ $out == app-run ]]'
rm -rf -- "$T"

# Bad options are usage errors (exit 2), before anything queues.
T=$(mktemp -d "${TMPDIR:-/var/tmp}/hb-test.XXXXXX"); : > "$T/out"
hbx() { (cd "$T" && exec env XDG_RUNTIME_DIR="$T/run" XDG_STATE_HOME="$T/state" XDG_CONFIG_HOME="$T/config" "$HB" "$@") > "$T/out" 2>&1; }
hbx --class build true; rc=$?
check "options: --class takes only app-run (exit 2, got $rc)" '(( rc == 2 )) && grep -q "takes only app-run" "$T/out"'
hbx --wait-timeout soon true; rc=$?
check "options: --wait-timeout must be seconds (exit 2, got $rc)" '(( rc == 2 ))'
hbx --class app-run; rc=$?
check "options: no command after the options is exit 2 (got $rc)" '(( rc == 2 ))'
hbx --ready-file; rc=$?
check "options: --ready-file needs a path (exit 2, got $rc)" '(( rc == 2 ))'
rm -rf -- "$T"

# The app-run cap in the admission walk. Running R lines carry the class in
# field 12, W lines in field 9. Old lines without a class still read.
A=$(mktemp -d "${TMPDIR:-/var/tmp}/hb-test.XXXXXX")
T=$A; : > "$T/out"
printf 'MemAvailable: %d kB\nSwapTotal: 0 kB\nSwapFree: 0 kB\n' $(( 60 * 1048576 )) > "$A/meminfo"
RUN_A1='R a1 999000 8 1 1014400 4294967296 - 0 normal - app-run'
RUN_A2='R a2 999000 8 1 1014400 4294967296 - 0 normal - app-run'
RUN_B='R b1 999000 4 2 1000600 4294967296 - 0 normal - cargo-test'
W_APP='W 0000000999000000000-1-a 999000 normal 8 1.5 14400 - app-run'
W_APPC='W 0000000999000000000-1-a 999000 critical 8 1.5 14400 - app-run'
W_BLD='W 0000000999000000001-2-b 999001 normal 4 2 600 - cargo-test'
out=$(printf '%s\n' "$RUN_A1" "$RUN_B" "$W_APP" | adm 0000000999000000000-1-a 0 1 12)
check "app-cap: a second app run starts next to one (got '$out')" '[[ $out == start\|fits:* ]]'
out=$(printf '%s\n' "$RUN_A1" "$RUN_A2" "$W_APP" | adm 0000000999000000000-1-a 0 1 12)
check "app-cap: a third app run waits, and its give-up clock runs (got '$out')" '[[ $out == "wait|app-cap: 2 app runs hold job slots, the limit is 2|0" ]]'
out=$(printf '%s\n' "$RUN_A1" "$RUN_A2" "$W_APPC" | adm 0000000999000000000-1-a 0 1 12)
check "app-cap: a critical app run waits for the cap too (got '$out')" '[[ $out == wait\|app-cap:* ]]'
out=$(printf '%s\n' "$RUN_A1" "$RUN_A2" "$W_APP" "$W_BLD" | adm 0000000999000000001-2-b 0 1 12)
check "app-cap: a build behind a capped app run starts as next in order, not as backfill (got '$out')" '[[ $out == "start|fits: next in order|0" ]]'
out=$(printf '%s\n' "$RUN_A1" "$RUN_A2" "$W_APP" | ADM_MAXAPP=3 adm 0000000999000000000-1-a 0 1 12)
check "app-cap: HEAVY_BUILD_MAX_APP_RUNS=3 lets a third start (got '$out')" '[[ $out == start\|fits:* ]]'
out=$(printf '%s\n' "$RUN_A1" "$RUN_A2" "$W_APP" | ADM_MAXAPP=0 adm 0000000999000000000-1-a 0 1 12)
check "app-cap: HEAVY_BUILD_MAX_APP_RUNS=0 turns the cap off (got '$out')" '[[ $out == start\|fits:* ]]'
out=$(printf '%s\n' 'W 0000000999000000000-1-a 999000 normal 8 1.5 14400 - app-run' 'W 0000000999000000000-1-c 999000 normal 8 1.5 14400 - app-run' 'W 0000000999000000000-1-d 999000 normal 8 1.5 14400 - app-run' | adm 0000000999000000000-1-d 0 1 12)
check "app-cap: of three app runs let in at once, the third waits (got '$out')" '[[ $out == wait\|app-cap:* ]]'
out=$(printf '%s\n' "$RUN_A1" "$RUN_A2" 'R b1 999000 4 2 1000600 4294967296 - 0 normal -' 'R b2 999000 4 2 1000600 4294967296 - 0 normal -' 'R b3 999000 4 2 1000600 4294967296 - 0 normal -' 'R b4 999000 4 2 1000600 4294967296 - 0 normal -' "$W_BLD" | adm 0000000999000000001-2-b 0 1 12)
check "app runs count as jobs: 2 app runs and 4 old-format builds fill the 6 slots (got '$out')" '[[ $out == "wait|jobs: 6 builds run, the limit is 6|0" ]]'
rm -rf -- "$A"

# Estimates: runs that ended by a signal (stopped or cancelled) still count
# for app-run, and the 6 GiB floor holds.
E=$(mktemp -d "${TMPDIR:-/var/tmp}/hb-test.XXXXXX")
est2() { (HIST=$E/hist; eval "$(sed -n '/^class_table()/,/^}/p;/^estimate()/,/^}/p' "$HB")"; EST_MEM_MAX_GIB=22; estimate "$1" "$2"); }
: > "$E/hist"
out=$(est2 k1 app-run)
check "app estimate: no history gives 8 GiB and 4 h (got '$out')" '[[ $out == "8.0 1.5 14400 class,mem=class" ]]'
for i in 1 2 3 4 5 6; do printf '%s\tapp-run\tk%s\t3600\t900\t%s\t143\tstopped\t12884901888\t10737418240\t-\t-\n' "$EPOCHSECONDS" "$i" "$(( 3 * G ))" >> "$E/hist"; done
out=$(est2 k9 app-run)
check "app estimate: stopped runs count, and the 6 GiB floor holds (got '$out')" '[[ $out == "6.0 0.2 3600 class-history,mem=floor" ]]'
printf '%s\tapp-run\tk1\t3600\t900\t%s\t143\tcancelled\t12884901888\t10737418240\t-\t-\n' "$EPOCHSECONDS" "$(( 9 * G ))" >> "$E/hist"
out=$(est2 k1 app-run)
check "app estimate: a cancelled run's 9 GiB peak counts for its key (got '$out')" '[[ $out == 9.0\ * ]]'
printf '%s\tcargo-test\tk2\t60\t60\t%s\t143\tfail\tNA\tNA\t-\t-\n' "$EPOCHSECONDS" "$(( 20 * G ))" >> "$E/hist"
out=$(est2 k2 cargo-test)
check "estimate: other classes still skip signal-ended runs (got '$out')" '[[ $out == 13.3\ * ]]'
rm -rf -- "$E"

# End to end with fake systemd-run and systemctl on PATH (no real scope).
# setup2: a sandbox with no blocker, 64 GiB free, shadow mode.
setup2() {
  T=$(mktemp -d "${TMPDIR:-/var/tmp}/hb-test.XXXXXX")
  mkdir -p "$T/run/heavy-build.queue" "$T/state" "$T/config" "$T/cg" "$T/work" "$T/bin" "$T/proc"
  printf 'MemTotal: %d kB\nMemAvailable: %d kB\nSwapTotal: 0 kB\nSwapFree: 0 kB\n' $(( 96 * 1048576 )) $(( 64 * 1048576 )) > "$T/proc/meminfo"
  printf '%s\n' '#!/usr/bin/env bash' 'echo "systemd-run $*" >> "$HBT/calls"' \
    'while (( $# )); do case $1 in -p) shift 2 ;; --*) shift ;; *) break ;; esac; done' 'exec "$@"' > "$T/bin/systemd-run"
  printf '%s\n' '#!/usr/bin/env bash' 'echo "systemctl $*" >> "$HBT/calls"' > "$T/bin/systemctl"
  chmod +x "$T/bin/systemd-run" "$T/bin/systemctl"
}
teardown2() { rm -rf -- "$T"; }
hbe() {  # VAR=value... -- args ; runs heavy-build in the sandbox in the background
  local -a ev=()
  while [[ $1 != -- ]]; do ev+=("$1"); shift; done; shift
  (cd "$T/work" && exec env -u HEAVY_BUILD_MODE -u HEAVY_BUILD_TIMEOUT HBT="$T" PATH="$T/bin:$PATH" \
    XDG_RUNTIME_DIR="$T/run" XDG_STATE_HOME="$T/state" XDG_CONFIG_HOME="$T/config" \
    HB_CGROUP="$T/cg" HB_PROC="$T/proc" HB_MACHINE_SESSION=/bin/false HEAVY_BUILD_PRIORITY=normal \
    HEAVY_BUILD_WAIT=100 HEAVY_BUILD_POLL=1 HEAVY_BUILD_FORCE=1 HEAVY_BUILD_KEY=none "${ev[@]}" \
    "$HB" "$@") > "$T/out" 2>&1 &
  hbpid=$!
}
setup2
echo stale > "$T/ready"
printf '%s\n' '#!/usr/bin/env bash' \
  'for _ in $(seq 1 50); do grep -q ^unit= "$1" 2>/dev/null && break; sleep 0.1; done' \
  'cp -- "$1" "$1.seen"; env > "$1.env"; kill -TERM $$' > "$T/app.sh"
chmod +x "$T/app.sh"
hbe -- --class app-run --ready-file "$T/ready" "$T/app.sh" "$T/ready"
wait "$hbpid"; rc=$?
check "ready file: an app run that dies from TERM exits 143 (got $rc)" '(( rc == 143 ))'
check "ready file: the stale file is replaced by one that names the scope" 'grep -q "^unit=heavy-build-[0-9]*-[0-9]*\.scope$" "$T/ready.seen" && grep -q "^admitted=[0-9]*$" "$T/ready.seen" && grep -q "^child_pid=[0-9]*$" "$T/ready.seen" && ! grep -q stale "$T/ready.seen"'
check "ready file: removed when heavy-build exits" '[[ ! -e $T/ready ]]'
u=$(sed -n 's/^unit=//p' "$T/ready.seen")
check "ready file: the command sees HEAVY_BUILD_UNIT=$u and no HEAVY_BUILD_READY_FILE or HEAVY_BUILD_CLASS" 'grep -qx "HEAVY_BUILD_UNIT=$u" "$T/ready.env" && ! grep -q "^HEAVY_BUILD_READY_FILE=\|^HEAVY_BUILD_CLASS=" "$T/ready.env"'
check "app scope: MemoryHigh=10G, MemoryMax=12G, no RuntimeMaxSec" 'grep -q "MemoryHigh=10G -p MemoryMax=12G" "$T/calls" && ! grep -q RuntimeMaxSec "$T/calls"'
check "app scope: the whole scope is stopped when the command ends" 'grep -qx "systemctl --user stop $u" "$T/calls"'
check "app history: class app-run, exit 143, reason stopped, MemoryHigh 10 GiB" 'awk -F"\t" -v g=$G '\''$2 == "app-run" && $7 == 143 && $8 == "stopped" && $10 == 10 * g'\'' "$T/state/heavy-build/history.tsv" | grep -q .'
teardown2

# A detected app run takes HEAVY_BUILD_APP_MEM_HIGH_GIB from the conf file.
setup2
printf 'HEAVY_BUILD_APP_MEM_HIGH_GIB=14\n' > "$T/config/heavy-build.conf"
mkdir -p "$T/w2/tools/wine"; printf '#!/bin/sh\nexit 0\n' > "$T/w2/tools/wine/run-mc.sh"; chmod +x "$T/w2/tools/wine/run-mc.sh"
hbe -- "$T/w2/tools/wine/run-mc.sh" a
wait "$hbpid"; rc=$?
check "app scope: run-mc.sh is detected and HEAVY_BUILD_APP_MEM_HIGH_GIB=14 gives MemoryHigh=14G (rc $rc)" '(( rc == 0 )) && grep -q "MemoryHigh=14G -p MemoryMax=16G" "$T/calls" && awk -F"\t" '\''$2 == "app-run" && $7 == 0 && $8 == "ok"'\'' "$T/state/heavy-build/history.tsv" | grep -q .'
teardown2

# A build's ready file works the same, and a build keeps its own caps.
setup2
hbe -- --ready-file "$T/r2" bash -c 'for _ in $(seq 1 50); do [[ -s $0 ]] && exit 0; sleep 0.1; done; exit 9' "$T/r2"
wait "$hbpid"; rc=$?
check "ready file: works for a build too (rc $rc)" '(( rc == 0 )) && grep -q "MemoryHigh=16G" "$T/calls"'
teardown2

# --wait-timeout: gives up with exit 77 after that long in line, even on hold.
setup
echo "test hold" > "$T/run/heavy-build.hold"
run_hb HEAVY_BUILD_WAIT=100 HEAVY_BUILD_WAIT_TIMEOUT=3
start=$SECONDS
wait "$hbpid"; rc=$?
check "wait timeout: exit 77 during a hold (got $rc)" '(( rc == 77 ))'
check "wait timeout: within 10 s" '(( SECONDS - start <= 10 ))'
check "wait timeout: logged as decision=refuse reason=wait-timeout" 'grep -q "decision=refuse reason=\"wait-timeout: not let in within 3s" "$T/state/heavy-build/shadow.log"'
check "wait timeout: says exit 77, nothing ran, and the next step" 'grep -q "heavy-build: exit 77, not run: --wait-timeout 3s ran out.*Nothing ran. Try again later, or give a longer --wait-timeout." "$T/out"'
teardown

# --help: no chained build in an example, no background-shell advice.
help=$("$HB" --help 2>&1)
check "help: no cargo build && cargo test example" '! grep -q "heavy-build bash -c .*cargo build && cargo test" <<< "$help"'
check "help: no advice to run in the background" '! grep -q "run it in the$" <<< "$help" && ! grep -qi "run it in the background" <<< "$help"'
check "help: suggests a systemd user unit for long builds" 'grep -q "systemd-run --user --unit=<name> --collect --same-dir heavy-build <cmd>" <<< "$help"'

exit "$fail"
