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
    -u HEAVY_BUILD_SESSION -u HEAVY_BUILD_SESSION_PID \
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
# Hung high builds (2026-10-23): a high build under 0.05 cores for 15 min gets
# one event=hung-high line with its unit and directory, and one notice, once
# per build. Nothing is stopped.
PRIO=high CLS=other AGO=1000 ss "i i i i" > "$X/out1" 2>/dev/null; cp "$X/out1" "$T/out"
check "hung high: logged once with unit and cwd" '(( $(grep -c "log: event=hung-high unit=u cwd=${PWD// /%20} idle_s=[0-9]* " "$X/out1") == 1 ))'
check "hung high: stderr is not a file, so the notice is live.log" 'grep -q "event=hung-high .* notice=live.log " "$X/out1"'
check "hung high: one notice naming the unit and directory" '(( $(grep -c "say: note: this high-priority build has used under 0.05 cores .* Unit u, directory $PWD\." "$X/out1") == 1 ))'
check "hung high: the notice says it no longer counts as a job" 'grep -q "say: note: this high-priority build.*It no longer counts as a job or a high build" "$X/out1"'
check "hung high: nothing is stopped" '! grep -q "^systemctl" "$X/out1"'
PRIO=high CLS=other AGO=1000 ss "i i i" > "$X/out2" 2>"$X/err2"; cp "$X/out2" "$T/out"
check "hung high: with stderr in a file, the line names that file as the build's log" 'grep -q "event=hung-high .* notice=$X/err2 " "$X/out2"'
PRIO=high CLS=other AGO=700 ss "i i i" > "$X/out1" 2>/dev/null; cp "$X/out1" "$T/out"
check "hung high: not before 15 min (idle 700 s is only a stall)" '! grep -q "event=hung-high" "$X/out1" && grep -q "event=stall" "$X/out1"'
PRIO=normal CLS=other AGO=1000 ss "i i i" > "$X/out1" 2>/dev/null; cp "$X/out1" "$T/out"
check "hung high: not for a normal build" '! grep -q "event=hung-high" "$X/out1"'
PRIO=high CLS=app-run AGO=1000 ss "i i i" > "$X/out1" 2>/dev/null; cp "$X/out1" "$T/out"
check "hung high: not for an app run, which is idle between tests" '! grep -q "event=hung-high" "$X/out1"'
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
    eval "$(sed -n '/^WINE_DEFAULT_LINE=/p;/^SHARED_WINEPREFIX=/p;/^wine_server_dir()/,/^}/p;/^wineservers_for()/,/^}/p;/^wine_cmd()/,/^}/p;/^run_tests_prefix()/,/^}/p;/^app_prefix()/,/^}/p;/^wine_key()/,/^}/p' "$HB")"
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
UI=$K/home/.local/share/wineprefixes/motioncatalyst-ui
out=$(cls=app-run WINEPREFIX=$SH wk "$K/lane-new" bash -c "tools/wine/headless-mc.sh start hbc --hive /x")
check "wine key: app run gets its own ui-<name> prefix from headless-mc.sh start, not the shared one (got '$out')" '[[ $out == "wine:$UI-hbc" ]]'
out=$(cls=app-run WINEPREFIX=$UI-env/ wk "$K/lane-new" tools/wine/run-mc.sh a)
check "wine key: app run with WINEPREFIX = a ui-<name> prefix keys on it (got '$out')" '[[ $out == "wine:$UI-env" ]]'
out=$(cls=app-run WINEPREFIX=$SH wk "$K/lane-new" tools/wine/run-mc.sh a)
check "wine key: app run with no instance name gets no wine key (got '$out')" '[[ -z $out ]]'
out=$(cls=app-run NOPFX=1 wk "$K/lane-old" wine MotionCatalyst.exe)
check "wine key: app run in an old tree does not get the shared default key (got '$out')" '[[ -z $out ]]'
out=$(cls=wine-run-tests WINEPREFIX=$SH wk "$K/lane-new" tools/wine/headless-mc.sh start hbc)
check "wine key: other classes keep wine:<WINEPREFIX> (got '$out')" '[[ $out == "wine:$SH" ]]'
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
out=$(OWN_EST=0 est lowkey cargo-check)
check "estimate: with HEAVY_BUILD_OWN_EST=0, key history (max 3) below the class p90 (18) gets the p90 (got '$out')" '[[ $out == "18.0 history,mem=class-p90" ]]'
# Own history (2026-10-23): a key with 2 or more runs gets 1.2 x its own max
# when that is below the class estimate.
out=$(est lowkey cargo-check)
check "own history: 2 runs, max 3 GiB, gives 1.2 x 3 = 3.6 instead of the class p90 (got '$out')" '[[ $out == "3.6 history,mem=key-own" ]]'
row cargo-check onekey 2 0 ok
out=$(est onekey cargo-check)
check "own history: a key with 1 run keeps the class p90 (got '$out')" '[[ $out == "18.0 history,mem=class-p90" ]]'
row cargo-check bigown 15 0 ok
row cargo-check bigown 16 0 ok
out=$(est bigown cargo-check)
check "own history: 1.2 x 16 = 19.2 is above the class p90, so the class p90 (18) stays (got '$out')" '[[ $out == "18.0 history,mem=class-p90" ]]'
row cargo-check tinykey 0 0 ok
row cargo-check tinykey 0 0 ok
out=$(est tinykey cargo-check)
check "own history: never under 1 GiB (got '$out')" '[[ $out == "1.0 history,mem=key-own" ]]'
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
row wine-run-tests w1 2 0 ok
out=$(est w1 wine-run-tests)
check "own history: 2 runs at 2 GiB give 2.4 under the 6 GiB class floor (got '$out')" '[[ $out == "2.4 history,mem=key-own" ]]'
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
check "sig: a filtered run with no sig history gets the class p75 by default (got '$out')" '[[ $out == "16.0 class-history,mem=class-p75" ]]'
out=$(WINE_FALLBACK_PCT=75 est newkey wine-run-tests sigA 1)
check "sig: WINE_FALLBACK_PCT=75 gives the class p75 (got '$out')" '[[ $out == "16.0 class-history,mem=class-p75" ]]'
out=$(WINE_FALLBACK_PCT=90 est newkey wine-run-tests sigA 1)
check "sig: WINE_FALLBACK_PCT=90 still gives the class p90 (got '$out')" '[[ $out == "19.0 class-history,mem=class-p90" ]]'
check "sig: the HEAVY_BUILD_WINE_FALLBACK_PCT default is 75" 'grep -q "^  setting HEAVY_BUILD_WINE_FALLBACK_PCT 75$" "$HB"'
for i in 1 2 3 4; do rows wine-run-tests "a$i" 7 sigA; done
out=$(est newkey wine-run-tests sigA 1)
check "sig: under 5 sig runs falls back to the class p75 (got '$out')" '[[ $out == "15.0 class-history,mem=class-p75" ]]'
out=$(WINE_FALLBACK_PCT=90 est newkey wine-run-tests sigA 1)
check "sig: under 5 sig runs with WINE_FALLBACK_PCT=90 falls back to the class p90 (got '$out')" '[[ $out == "18.0 class-history,mem=class-p90" ]]'
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

# End to end: under 5 sig runs, the script's default falls back to the class
# p75 and logs mem=class-p75; HEAVY_BUILD_WINE_FALLBACK_PCT=90 brings p90 back.
for pct in "" 90; do
  setup
  read -r _ s <<< "$(sg wine-run-tests tools/wine/run-tests.sh Foo.Tests --filter Name~Bar)"
  mkdir -p "$T/state/heavy-build"
  for i in $(seq 1 20); do
    printf '%d\twine-run-tests\tc%d\t10\t20\t%d\t0\tok\t%d\t%d\t-\tother\n' "$(( EPOCHSECONDS - 60 ))" "$i" "$(( i * G ))" "$(( 24 * G ))" "$(( 22 * G ))" >> "$T/state/heavy-build/history.tsv"
  done
  (cd "$T/work" && exec env -u HEAVY_BUILD_MODE -u HEAVY_BUILD_ALLOW_RERUN -u HEAVY_BUILD_WINE_FALLBACK_PCT \
    XDG_RUNTIME_DIR="$T/run" XDG_STATE_HOME="$T/state" XDG_CONFIG_HOME="$T/config" \
    HB_CGROUP="$T/cg" HB_MACHINE_SESSION=/bin/false HEAVY_BUILD_PRIORITY=normal \
    HEAVY_BUILD_WAIT=3 HEAVY_BUILD_POLL=1 HEAVY_BUILD_FORCE=1 HEAVY_BUILD_KEY=none \
    ${pct:+HEAVY_BUILD_WINE_FALLBACK_PCT=$pct} \
    "$HB" tools/wine/run-tests.sh Foo.Tests --filter Name~Bar) > "$T/out" 2>&1
  if [[ -z $pct ]]; then
    check "sig: by default a filtered run with no sig history logs est=16.0G...mem=class-p75" 'grep -q "est=16.0G/[^ ]*mem=class-p75)" "$T/state/heavy-build/shadow.log"'
  else
    check "sig: HEAVY_BUILD_WINE_FALLBACK_PCT=90 logs est=19.0G...mem=class-p90" 'grep -q "est=19.0G/[^ ]*mem=class-p90)" "$T/state/heavy-build/shadow.log"'
  fi
  teardown
done


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
      -v slicemax="${ADM_SLICEMAX:-$A/none}" -v slicehigh="$A/none" -v cpupsifile="${ADM_CPUPSI:-$A/none}" -v claudepsifile="${ADM_CLAUDEPSI:-$A/none}" \
      -v sessionpsifile="${ADM_SESSIONPSI:-$A/none}" -v plevel="${ADM_PLEVEL:-none}" -v preason="${ADM_PREASON:-test reason}" -v lastnc="${ADM_LASTNC:-0}" -v slowgap=120 -v slowfastgap=30 -v slowfastgib=16 -v maxjobs=6 -v cpubudget=28 -v reserve=6 -v maxcpupsi="${ADM_MAXCPUPSI:-75}" -v maxmempsi=5 \
      -v starve=1800 -v solo=8 -v minswap=10 -v warm=120 -v poll=5 -v lowage=1800 -v tcpct=50 \
      -v agesecs=3600 -v ageslots=1 -v critage="${ADM_CRITAGE:-1800}" -v maxapp="${ADM_MAXAPP:-2}" -v cf="$1" -v cfslots="$2" -v cfreserve="$3" \
      -v realuse="${ADM_REALUSE:-0}" -v slicecurfile="${ADM_SLICECUR:-}" -v slicestatfile="${ADM_SLICESTAT:-}" -v sliceavg="${ADM_SLICEAVG:-}" -v sliceavgwin=30 \
      -v youngpct=70 -v youngmin=120 -v growpct="${ADM_GROWPCT:-100}" \
      -v memctl="${ADM_MC:-}" -v mcharmago="${ADM_MCHARMAGO:-}" -v mcfall="${ADM_MCFALL:-}" "$ADMIT_AWK" \
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

# Interactive gate: claude.slice and session.slice memory pressure, full
# avg10. some avg10 and app.slice no longer count.
ipsi() { printf 'some avg10=%s avg60=0.00 avg300=0.00 total=1\nfull avg10=%s avg60=0.00 avg300=0.00 total=1\n' "$2" "$3" > "$A/$1"; }
ipsi psi-full6 6.00 6.00
ipsi psi-some20 20.00 0.50
out=$(printf '%s\n' "$RUN_N" "$W_N" | ADM_CLAUDEPSI=$A/psi-full6 adm 0000000999000000000-1-n 0 1 12)
check "interactive: claude.slice full 6% holds builds (got '$out')" '[[ $out == "wait|interactive: claude.slice memory pressure (full) 6.0%, the limit is 5%|0" ]]'
out=$(printf '%s\n' "$RUN_N" "$W_N" | ADM_SESSIONPSI=$A/psi-full6 adm 0000000999000000000-1-n 0 1 12)
check "interactive: session.slice full 6% holds builds (got '$out')" '[[ $out == "wait|interactive: session.slice memory pressure (full) 6.0%, the limit is 5%|0" ]]'
out=$(printf '%s\n' "$RUN_N" "$W_N" | ADM_CLAUDEPSI=$A/psi-some20 ADM_SESSIONPSI=$A/psi-some20 adm 0000000999000000000-1-n 0 1 12)
check "interactive: some 20% with full 0.5% no longer holds builds (got '$out')" '[[ $out == start\|fits:* ]]'
check "interactive: the admission rule does not read app.slice any more" '! grep -q "apppsi\|app\.slice/memory\.pressure" "$HB"'

# Pressure level from pressure-coordinator (ADM_PLEVEL).
RUN_NEW='R u3 999950 4 2 1000600 4294967296 - 0 normal -'
RUN_NEWC='R u4 999950 4 2 1000600 4294967296 - 0 critical -'
W_N2='W 0000000999000000000-4-m 999000 normal 4 2 600 -'
for lv in none stale normal; do
  out=$(printf '%s\n' "$RUN_NEW" "$W_N" | ADM_PLEVEL=$lv adm 0000000999000000000-1-n 0 1 12)
  check "pressure $lv: a normal build starts as before (got '$out')" '[[ $out == start\|fits:* ]]'
done
out=$(printf '%s\n' "$W_N" | ADM_PLEVEL=pause ADM_PREASON="memory full avg10 6.1%" adm 0000000999000000000-1-n 0 1 12)
check "pressure pause: a normal build waits, says why, clock held (got '$out')" '[[ $out == "wait|pressure: level pause, only high and critical builds start (memory full avg10 6.1%)|1" ]]'
out=$(printf '%s\n' "$W_L" | ADM_PLEVEL=pause adm 0000000999000000000-1-n 0 1 12)
check "pressure pause: a low build waits (got '$out')" '[[ $out == wait\|pressure:* ]]'
out=$(printf '%s\n' "$RUN_N" "$W_C" | ADM_PLEVEL=pause adm 0000000999000000000-2-c 0 1 12)
check "pressure pause: a critical build that passes the memory test starts (got '$out')" '[[ $out == start\|fits:* ]]'
out=$(printf '%s\n' "$RUN_N" "$W_H" | ADM_PLEVEL=pause adm 0000000999000000000-3-h 0 1 12)
check "pressure pause: a high build that passes the memory test starts (got '$out')" '[[ $out == start\|fits:* ]]'
out=$(printf '%s\n' "$RUN_N" "$W_36C" | ADM_PLEVEL=pause adm 0000000999000000000-2-c 0 1 12)
check "pressure pause: a critical build that fails the memory test waits for memory (got '$out')" '[[ $out == wait\|memory:* ]]'
out=$(printf '%s\n' "$RUN_N" 'W 0000000990000000000-1-n 990000 normal 4 2 600 -' "$W_C" | ADM_PLEVEL=pause adm 0000000999000000000-2-c 0 1 12)
check "pressure pause: an aged normal build waits for pressure and does not head the line, so the critical one starts (got '$out')" '[[ $out == start\|fits:* ]]'
out=$(printf '%s\n' "$RUN_N" 'W 0000000990000000000-1-n 990000 normal 4 2 600 -' "$W_C" | ADM_PLEVEL=pause adm 0000000990000000000-1-n 0 1 12)
check "pressure pause: that aged normal build waits for pressure (got '$out')" '[[ $out == wait\|pressure:* ]]'
# The slow gap: 30 s while MemAvailable is above 16 GiB, 120 s at or below.
printf 'MemAvailable: %d kB\nSwapTotal: 0 kB\nSwapFree: 0 kB\n' $(( 16 * 1048576 )) > "$A/meminfo16"
printf 'MemAvailable: %d kB\nSwapTotal: 0 kB\nSwapFree: 0 kB\n' $(( 23 * 1048576 )) > "$A/meminfo23"
printf 'MemAvailable: %d kB\nSwapTotal: 0 kB\nSwapFree: 0 kB\n' $(( 16 * 1048576 + 1024 )) > "$A/meminfo16p"
out=$(printf '%s\n' "$RUN_NEW" "$W_N" | ADM_MEMINFO=$A/meminfo16 ADM_PLEVEL=slow ADM_LASTNC=999950 ADM_PREASON="memory full avg10 2.4%" adm 0000000999000000000-1-n 0 1 12)
check "pressure slow, 16 GiB free: a normal build waits while the last normal start was 50 s ago, clock held (got '$out')" '[[ $out == "wait|pressure: level slow, 16.0 GiB free, one new build per 120 s; the last one started 50 s ago (memory full avg10 2.4%)|1" ]]'
out=$(printf '%s\n' "$RUN_NEW" "$W_N" | ADM_MEMINFO=$A/meminfo16 ADM_PLEVEL=slow ADM_LASTNC=999881 adm 0000000999000000000-1-n 0 1 12)
check "pressure slow, 16 GiB free: still waits at 119 s (got '$out')" '[[ $out == wait\|pressure:\ level\ slow,\ 16.0\ GiB\ free,\ one\ new\ build\ per\ 120\ s* ]]'
out=$(printf '%s\n' "$RUN_NEW" "$W_N" | ADM_MEMINFO=$A/meminfo16 ADM_PLEVEL=slow ADM_LASTNC=999880 adm 0000000999000000000-1-n 0 1 12)
check "pressure slow, 16 GiB free: starts at 120 s (got '$out')" '[[ $out == start\|fits:* ]]'
out=$(printf '%s\n' "$RUN_NEW" "$W_N" | ADM_MEMINFO=$A/meminfo23 ADM_PLEVEL=slow ADM_LASTNC=999950 adm 0000000999000000000-1-n 0 1 12)
check "pressure slow, 23 GiB free: a normal build starts 50 s after the last normal start (got '$out')" '[[ $out == start\|fits:* ]]'
out=$(printf '%s\n' "$RUN_NEW" "$W_N" | ADM_MEMINFO=$A/meminfo23 ADM_PLEVEL=slow ADM_LASTNC=999980 ADM_PREASON="memory full avg10 2.4%" adm 0000000999000000000-1-n 0 1 12)
check "pressure slow, 23 GiB free: waits 20 s after the last normal start, says 30 s and the free memory, clock held (got '$out')" '[[ $out == "wait|pressure: level slow, 23.0 GiB free, one new build per 30 s; the last one started 20 s ago (memory full avg10 2.4%)|1" ]]'
out=$(printf '%s\n' "$RUN_NEW" "$W_N" | ADM_MEMINFO=$A/meminfo23 ADM_PLEVEL=slow ADM_LASTNC=999970 adm 0000000999000000000-1-n 0 1 12)
check "pressure slow, 23 GiB free: starts at 30 s (got '$out')" '[[ $out == start\|fits:* ]]'
out=$(printf '%s\n' "$RUN_NEW" "$W_N" | ADM_MEMINFO=$A/meminfo16p ADM_PLEVEL=slow ADM_LASTNC=999950 adm 0000000999000000000-1-n 0 1 12)
check "pressure slow, just over 16 GiB free: the 30 s gap applies (got '$out')" '[[ $out == start\|fits:* ]]'
out=$(printf '%s\n' "$W_L" | ADM_MEMINFO=$A/meminfo23 ADM_PLEVEL=pause adm 0000000999000000000-1-n 0 1 12)
check "pressure pause, 23 GiB free: a low build still waits (got '$out')" '[[ $out == wait\|pressure:\ level\ pause* ]]'
out=$(printf '%s\n' "$W_N" | ADM_PLEVEL=slow ADM_LASTNC=999990 adm 0000000999000000000-1-n 0 1 12)
check "pressure slow: a build that started 10 s ago and already ended still spaces the next one (got '$out')" '[[ $out == wait\|pressure:\ level\ slow* ]]'
out=$(printf '%s\n' "$RUN_NEW" "$W_N" | ADM_PLEVEL=slow ADM_LASTNC=999000 adm 0000000999000000000-1-n 0 1 12)
check "pressure slow: a normal build starts when the last normal start was 1000 s ago (got '$out')" '[[ $out == start\|fits:* ]]'
out=$(printf '%s\n' "$RUN_N" "$W_N" | ADM_PLEVEL=slow ADM_LASTNC=1000500 adm 0000000999000000000-1-n 0 1 12)
check "pressure slow: a last start in the future is ignored (got '$out')" '[[ $out == start\|fits:* ]]'
out=$(printf '%s\n' "$RUN_NEWC" "$W_N" | ADM_PLEVEL=slow adm 0000000999000000000-1-n 0 1 12)
check "pressure slow: a critical build started 50 s ago does not hold a normal one (got '$out')" '[[ $out == start\|fits:* ]]'
out=$(printf '%s\n' "$RUN_NEW" "$W_C" | ADM_PLEVEL=slow ADM_LASTNC=999990 adm 0000000999000000000-2-c 0 1 12)
check "pressure slow: a critical build is not held (got '$out')" '[[ $out == start\|fits:* ]]'
out=$(printf '%s\n' "$W_N" "$W_N2" | ADM_PLEVEL=slow adm 0000000999000000000-1-n 0 1 12)
check "pressure slow: of two normal waiters the first starts (got '$out')" '[[ $out == start\|fits:* ]]'
out=$(printf '%s\n' "$W_N" "$W_N2" | ADM_PLEVEL=slow adm 0000000999000000000-4-m 0 1 12)
check "pressure slow: the second waits for the first (got '$out')" '[[ $out == wait\|pressure:\ level\ slow* ]]'

# Pressure level and the first build: no solo shortcut at slow or pause.
W_22C='W 0000000999000000000-2-c 999000 critical 22 2 600 -'
printf 'MemAvailable: %d kB\nSwapTotal: 0 kB\nSwapFree: 0 kB\n' $(( 10 * 1048576 )) > "$A/meminfo10"
out=$(printf '%s\n' "$W_22C" | ADM_MEMINFO=$A/meminfo10 adm 0000000999000000000-2-c 0 1 12)
check "first build, level none: 10 GiB available is enough for a 22 GiB build (got '$out')" '[[ $out == start\|fits:* ]]'
for lv in slow pause; do
  out=$(printf '%s\n' "$W_22C" | ADM_MEMINFO=$A/meminfo10 ADM_PLEVEL=$lv adm 0000000999000000000-2-c 0 1 12)
  check "first build, level $lv: a 22 GiB critical build with 10 GiB available waits for memory (got '$out')" '[[ $out == wait\|memory:\ needs\ 22.0* ]]'
done
printf '%s\n' $(( 16 * 1073741824 )) > "$A/slicemax16"
out=$(printf '%s\n' "$W_22C" | ADM_SLICEMAX=$A/slicemax16 ADM_PLEVEL=pause adm 0000000999000000000-2-c 0 1 12)
check "first build, level pause: the builds.slice cap applies too (got '$out')" '[[ $out == wait\|slice-cap:* ]]'
printf 'MemAvailable: %d kB\nSwapTotal: 0 kB\nSwapFree: 0 kB\n' $(( 6 * 1048576 )) > "$A/meminfo6"
out=$(printf '%s\n' "$W_C" | ADM_MEMINFO=$A/meminfo6 adm 0000000999000000000-2-c 0 1 12)
check "first build, level none: under the solo 8 GiB it still waits (got '$out')" '[[ $out == "wait|memory: 6.0 GiB available, the first build needs 8|0" ]]'

# A pressure-held waiter keeps no writer preference.
W_AGED_T='W 0000000990000000000-1-n 990000 normal 36 2 600 tree:/repo'
W_C_SUF='W 0000000999000000000-2-c 999000 critical 4 2 600 tree:/repo#s1'
out=$(printf '%s\n' "$RUN_N" "$W_AGED_T" "$W_C_SUF" | ADM_PLEVEL=pause adm 0000000999000000000-2-c 0 1 12)
check "pressure pause: a held normal waiter on tree:/repo does not block a critical tree:/repo#s1 by writer preference (got '$out')" '[[ $out == start\|fits:* ]]'
out=$(printf '%s\n' "$RUN_N" "$W_AGED_T" "$W_C_SUF" | adm 0000000999000000000-2-c 0 1 12)
check "pressure none: an aged normal waiter ranks behind critical, so it takes no writer preference over a critical build (got '$out')" '[[ $out == start\|fits:* ]]'
W_N_SUF='W 0000000999000000000-2-m 999000 normal 4 2 600 tree:/repo#s1'
out=$(printf '%s\n' "$RUN_N" "$W_AGED_T" "$W_N_SUF" | adm 0000000999000000000-2-m 0 1 12)
check "pressure none: the writer preference still holds a suffixed normal build behind it (got '$out')" '[[ $out == wait\|writer:* ]]'

# The give-up clock does not run while the pressure level holds a build,
# even when the interactive or swap gate is the reason shown.
out=$(printf '%s\n' "$RUN_N" "$W_N" | ADM_PLEVEL=pause ADM_CLAUDEPSI=$A/psi-full6 adm 0000000999000000000-1-n 0 1 12)
check "pressure pause + interactive gate: reason interactive, clock held (got '$out')" '[[ $out == wait\|interactive:*\|1 ]]'
out=$(printf '%s\n' "$RUN_N" "$W_N" | ADM_CLAUDEPSI=$A/psi-full6 adm 0000000999000000000-1-n 0 1 12)
check "pressure none + interactive gate: the clock runs (got '$out')" '[[ $out == wait\|interactive:*\|0 ]]'
printf 'MemAvailable: %d kB\nSwapTotal: %d kB\nSwapFree: %d kB\n' $(( 40 * 1048576 )) $(( 100 * 1048576 )) $(( 12 * 1048576 )) > "$A/meminfo-lowswap"
out=$(printf '%s\n' "$RUN_N" "$W_N" | ADM_MEMINFO=$A/meminfo-lowswap ADM_PLEVEL=slow ADM_LASTNC=999990 adm 0000000999000000000-1-n 0 1 12)
check "pressure slow + swap gate: reason swap, says 90% of swap, clock held (got '$out')" '[[ $out == "wait|swap: 2.0 GiB left before 90% of swap is used, need 10|1" ]]'
out=$(printf '%s\n' "$RUN_N" "$W_C" | ADM_MEMINFO=$A/meminfo-lowswap ADM_PLEVEL=pause adm 0000000999000000000-2-c 0 1 12)
check "pressure pause + swap gate: a critical build is not pressure-held, so its clock runs (got '$out')" '[[ $out == wait\|swap:*\|0 ]]'
check "gate text: no oomd limit left in heavy-build" '! grep -q "oomd limit" "$HB"'

# 9. Swap headroom. 20 GiB available, a normal build of 16 GiB next to a
# running one: 20 - 16 = 4 is under the 6 GiB reserve without headroom.
printf 'MemAvailable: %d kB\nSwapTotal: %d kB\nSwapFree: %d kB\n' $(( 20 * 1048576 )) $(( 96 * 1048576 )) $(( 64 * 1048576 )) > "$A/meminfo-sw"
printf 'MemAvailable: %d kB\nSwapTotal: %d kB\nSwapFree: %d kB\n' $(( 20 * 1048576 )) $(( 16 * 1048576 )) $(( 16 * 1048576 )) > "$A/meminfo-sw16"
mpsi() { printf 'some avg10=%s avg60=%s avg300=0.50 total=1\nfull avg10=0.00 avg60=0.00 avg300=0.00 total=1\n' "$1" "$2" > "$A/mempsi"; }
W_16='W 0000000999000000000-1-n 999000 normal 16 2 600 -'
mpsi 0.00 0.12
out=$(printf '%s\n' "$RUN_N" "$W_16" | ADM_MEMINFO=$A/meminfo-sw ADM_MEMPSI=$A/mempsi adm 0000000999000000000-1-n 0 1 12)
check "swap headroom: low pressure adds min(25% of 64, 8) = 8 GiB, so it starts and says so (got '$out')" '[[ $out == "start|fits: next in order (+8.0 swap headroom)|0" ]]'
out=$(printf '%s\n' "$RUN_N" "$W_16" | ADM_MEMINFO=$A/meminfo-sw ADM_MEMPSI=$A/mempsi ADM_PLEVEL=slow adm 0000000999000000000-1-n 0 1 12)
check "swap headroom: none at pressure level slow (got '$out')" '[[ $out == wait\|memory:* && $out != *headroom* ]]'
out=$(printf '%s\n' "$RUN_N" "${W_16/normal/critical}" | ADM_MEMINFO=$A/meminfo-sw ADM_MEMPSI=$A/mempsi ADM_PLEVEL=pause adm 0000000999000000000-1-n 0 1 12)
check "swap headroom: none for a critical build at pause either (got '$out')" '[[ $out == wait\|memory:* && $out != *headroom* ]]'
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

# The real-use rule (HEAVY_BUILD_REAL_USE=1): the slice-cap check starts
# from builds.slice memory.current plus what young builds may still take,
# and the cores check from builds.slice CPU use plus young builds' estimates.
gib() { printf '%s\n' $(( $1 * 1073741824 )) > "$A/$2"; }
gib 16 slicemax16
gib 5 slicecur5
gib 2 slicecur2
# An old build: started 10000 s ago, 600 s expected, estimate 12 GiB, holds 4 GiB.
RUN_OLD='R u5 990000 12 2 990600 4294967296 2000 0 normal -'
# A young build: started 50 s ago, estimate 12 GiB, holds 1 GiB.
RUN_YOUNG='R u6 999950 12 2 1000550 1073741824 - 0 normal -'
# Started 1000 s ago with 2000 s expected: past 2 min but under 70% of its wall.
RUN_LATE='R u7 999000 12 2 1001000 1073741824 1000 0 normal -'
W_6='W 0000000999000000000-1-n 999000 normal 6 2 600 -'
out=$(printf '%s\n' "$RUN_OLD" "$W_6" | ADM_SLICEMAX=$A/slicemax16 adm 0000000999000000000-1-n 0 1 12)
check "real use off: an old build is charged its 12 GiB estimate, so a 6 GiB build waits (got '$out')" '[[ $out == "wait|slice-cap: needs 6.0 GiB; builds hold 12.0 of the 16.0 GiB builds.slice cap (MemoryMax)|0" ]]'
out=$(printf '%s\n' "$RUN_OLD" "$W_6" | ADM_REALUSE=1 ADM_SLICECUR=$A/slicecur5 ADM_SLICEMAX=$A/slicemax16 adm 0000000999000000000-1-n 0 1 12)
check "real use: builds.slice uses 5 GiB and the old build is past its young window, so the 6 GiB build starts (got '$out')" '[[ $out == start\|fits:* ]]'
out=$(printf '%s\n' "$RUN_YOUNG" "$W_6" | ADM_REALUSE=1 ADM_SLICECUR=$A/slicecur2 ADM_SLICEMAX=$A/slicemax16 adm 0000000999000000000-1-n 0 1 12)
check "real use: a build 50 s old still counts its estimate, so the 6 GiB build waits and says why (got '$out')" '[[ $out == "wait|slice-cap: needs 6.0 GiB; builds.slice uses 2.0 GiB and running builds may take 11.0 more, of the 16.0 GiB cap (MemoryMax)|0" ]]'
out=$(printf '%s\n' "$RUN_LATE" "$W_6" | ADM_REALUSE=1 ADM_SLICECUR=$A/slicecur2 ADM_SLICEMAX=$A/slicemax16 adm 0000000999000000000-1-n 0 1 12)
check "real use: a build at 50% of its expected wall time is still young, so its estimate counts (got '$out')" '[[ $out == wait\|slice-cap:\ needs\ 6.0\ GiB\;\ builds.slice\ uses\ 2.0\ GiB\ and\ running\ builds\ may\ take\ 11.0\ more* ]]'
RUN_LATE_DONE='R u7 999000 12 2 1000400 1073741824 1000 0 normal -'
out=$(printf '%s\n' "$RUN_LATE_DONE" "$W_6" | ADM_REALUSE=1 ADM_SLICECUR=$A/slicecur2 ADM_SLICEMAX=$A/slicemax16 adm 0000000999000000000-1-n 0 1 12)
check "real use: a build at 71% of its expected wall time is no longer young, so the 6 GiB build starts (got '$out')" '[[ $out == start\|fits:* ]]'
out=$(printf '%s\n' "$RUN_OLD" "$W_6" | ADM_REALUSE=1 ADM_SLICECUR=$A/none ADM_SLICEMAX=$A/slicemax16 adm 0000000999000000000-1-n 0 1 12)
check "real use: without memory.current the old charged sum applies (got '$out')" '[[ $out == "wait|slice-cap: needs 6.0 GiB; builds hold 12.0 of the 16.0 GiB builds.slice cap (MemoryMax)|0" ]]'
out=$(printf '%s\n' "$RUN_OLD" 'F orphan1 3221225472 1000000 600 0 -' "$W_6" | ADM_REALUSE=1 ADM_SLICECUR=$A/slicecur5 ADM_SLICEMAX=$A/slicemax16 adm 0000000999000000000-1-n 0 1 12)
check "real use: a scope with no heavy-build still adds 2 GiB still to come (5 + 2 + 6 fits 16) (got '$out')" '[[ $out == start\|fits:* ]]'
gib 9 slicecur9
out=$(printf '%s\n' "$RUN_OLD" 'F orphan1 3221225472 1000000 600 0 -' "$W_6" | ADM_REALUSE=1 ADM_SLICECUR=$A/slicecur9 ADM_SLICEMAX=$A/slicemax16 adm 0000000999000000000-1-n 0 1 12)
check "real use: 9 + 2 + 6 is over 16, so it waits (got '$out')" '[[ $out == "wait|slice-cap: needs 6.0 GiB; builds.slice uses 9.0 GiB and running builds may take 2.0 more, of the 16.0 GiB cap (MemoryMax)|0" ]]'
out=$(printf '%s\n' "$RUN_OLD" "$W_6" "W 0000000999000000001-2-n 999000 normal 6 2 600 -" | ADM_REALUSE=1 ADM_SLICECUR=$A/slicecur5 ADM_SLICEMAX=$A/slicemax16 adm 0000000999000000001-2-n 0 1 12)
check "real use: a build let in ahead in the same walk counts its full estimate (5 + 6 + 6 is over 16) (got '$out')" '[[ $out == wait\|slice-cap:*may\ take\ 6.0\ more* ]]'
# Young-build growth (2026-10-23, HEAVY_BUILD_YOUNG_GROW_PCT, default 50):
# only that share of a young build's estimate minus what it holds is charged.
out=$(printf '%s\n' "$RUN_YOUNG" "$W_6" | ADM_GROWPCT=50 ADM_REALUSE=1 ADM_SLICECUR=$A/slicecur2 ADM_SLICEMAX=$A/slicemax16 adm 0000000999000000000-1-n 0 1 12)
check "young grow 50%: 2 + 11 x 50% + 6 = 13.5 fits 16, so the 6 GiB build starts (got '$out')" '[[ $out == start\|fits:* ]]'
out=$(printf '%s\n' "$RUN_YOUNG" "W 0000000999000000000-1-n 999000 normal 10 2 600 -" | ADM_GROWPCT=50 ADM_REALUSE=1 ADM_SLICECUR=$A/slicecur2 ADM_SLICEMAX=$A/slicemax16 adm 0000000999000000000-1-n 0 1 12)
check "young grow 50%: the reason says 5.5 GiB still to come (got '$out')" '[[ $out == "wait|slice-cap: needs 10.0 GiB; builds.slice uses 2.0 GiB and running builds may take 5.5 more, of the 16.0 GiB cap (MemoryMax)|0" ]]'
out=$(printf '%s\n' "$RUN_YOUNG" "$W_6" | ADM_GROWPCT=0 ADM_REALUSE=1 ADM_SLICECUR=$A/slicecur2 ADM_SLICEMAX=$A/slicemax16 adm 0000000999000000000-1-n 0 1 12)
check "young grow 0%: only what builds.slice holds counts (got '$out')" '[[ $out == start\|fits:* ]]'
# Young-build CPU counted once (2026-10-23): builds.slice's CPU average already
# holds what a young build used inside the window, so the build adds only its
# estimate minus that (floored at 0). 28 cores; builds.slice used 12.
W_8C='W 0000000999000000000-1-n 999000 normal 2 8 600 -'
# Estimate 10 cores, started 60 s ago, used 8 cores: 10 - 8 = 2 more.
RUN_YC60='R y1 999940 2 10 1000540 1073741824 8000 0 normal -'
out=$(printf '%s\n' "$RUN_YC60" "$W_8C" | ADM_REALUSE=1 ADM_SLICEAVG=12 adm 0000000999000000000-1-n 0 1 12)
check "young cpu: a 60 s old build using 8 of its 10 estimated cores adds 2, so 12 + 2 + 8 fits 28 (got '$out')" '[[ $out == start\|fits:* ]]'
# Started 15 s ago: half of its use falls in the 30 s window, 10 - 4 = 6 more.
RUN_YC15='R y1 999985 2 10 1000585 1073741824 8000 0 normal -'
out=$(printf '%s\n' "$RUN_YC15" "W 0000000999000000000-1-n 999000 normal 2 12 600 -" | ADM_REALUSE=1 ADM_SLICEAVG=12 adm 0000000999000000000-1-n 0 1 12)
check "young cpu: a 15 s old build counts half its use as already in the window (12 + 6 + 12 > 28) (got '$out')" '[[ $out == "wait|cores: needs 12.0, 18.0 of 28 in use (builds.slice used 12.0 over the last 30 s, plus 6.0 for builds that started recently)|0" ]]'
# Using more than its estimate: floored at 0.
RUN_YCHI='R y1 999940 2 10 1000540 1073741824 14000 0 normal -'
out=$(printf '%s\n' "$RUN_YCHI" "W 0000000999000000000-1-n 999000 normal 2 20 600 -" | ADM_REALUSE=1 ADM_SLICEAVG=20 adm 0000000999000000000-1-n 0 1 12)
check "young cpu: a build over its estimate adds 0, not less (20 + 0 + 20 > 28) (got '$out')" '[[ $out == "wait|cores: needs 20.0, 20.0 of 28 in use (builds.slice used 20.0 over the last 30 s, plus 0.0 for builds that started recently)|0" ]]'
# No measurement yet: the full estimate.
RUN_YCNA='R y1 999995 2 10 1000595 1073741824 - 0 normal -'
out=$(printf '%s\n' "$RUN_YCNA" "$W_8C" | ADM_REALUSE=1 ADM_SLICEAVG=12 adm 0000000999000000000-1-n 0 1 12)
check "young cpu: without a 60 s figure the full 10-core estimate counts (12 + 10 + 8 > 28) (got '$out')" '[[ $out == "wait|cores: needs 8.0, 22.0 of 28 in use (builds.slice used 12.0 over the last 30 s, plus 10.0 for builds that started recently)|0" ]]'

# Inactive page cache (memory.stat inactive_file) is taken off memory.current
# when slicestatfile is set (HEAVY_BUILD_SLICE_EXCLUDE_INACTIVE_FILE=1).
mstat() { printf 'anon %d\nfile %d\nactive_file %d\ninactive_file %d\n' 1 2 3 $(( $1 * 1073741824 )) > "$A/$2"; }
mstat 4 stat4
mstat 1 stat1
mstat 20 stat20
out=$(printf '%s\n' "$RUN_OLD" 'F orphan1 3221225472 1000000 600 0 -' "$W_6" | ADM_REALUSE=1 ADM_SLICECUR=$A/slicecur9 ADM_SLICESTAT=$A/stat4 ADM_SLICEMAX=$A/slicemax16 adm 0000000999000000000-1-n 0 1 12)
check "inactive cache: 9 GiB used minus 4 GiB inactive_file leaves 5, so 5 + 2 + 6 fits 16 (got '$out')" '[[ $out == start\|fits:* ]]'
out=$(printf '%s\n' "$RUN_OLD" 'F orphan1 3221225472 1000000 600 0 -' "$W_6" | ADM_REALUSE=1 ADM_SLICECUR=$A/slicecur9 ADM_SLICESTAT=$A/stat1 ADM_SLICEMAX=$A/slicemax16 adm 0000000999000000000-1-n 0 1 12)
check "inactive cache: 9 minus 1 leaves 8, 8 + 2 + 6 is 16 (fits at the cap) (got '$out')" '[[ $out == start\|fits:* ]]'
out=$(printf '%s\n' "$RUN_OLD" 'F orphan1 3221225472 1000000 600 0 -' "W 0000000999000000000-1-n 999000 normal 7 2 600 -" | ADM_REALUSE=1 ADM_SLICECUR=$A/slicecur9 ADM_SLICESTAT=$A/stat1 ADM_SLICEMAX=$A/slicemax16 adm 0000000999000000000-1-n 0 1 12)
check "inactive cache: the wait reason says how much was not counted (got '$out')" '[[ $out == "wait|slice-cap: needs 7.0 GiB; builds.slice uses 8.0 GiB (1.0 GiB inactive cache not counted) and running builds may take 2.0 more, of the 16.0 GiB cap (MemoryMax)|0" ]]'
out=$(printf '%s\n' "$RUN_YOUNG" "W 0000000999000000000-1-n 999000 normal 6 2 600 -" | ADM_REALUSE=1 ADM_SLICECUR=$A/slicecur2 ADM_SLICESTAT=$A/stat20 ADM_SLICEMAX=$A/slicemax16 adm 0000000999000000000-1-n 0 1 12)
check "inactive cache: more inactive_file than memory.current floors at 0 (got '$out')" '[[ $out == "wait|slice-cap: needs 6.0 GiB; builds.slice uses 0.0 GiB (2.0 GiB inactive cache not counted) and running builds may take 11.0 more, of the 16.0 GiB cap (MemoryMax)|0" ]]'
out=$(printf '%s\n' "$RUN_OLD" 'F orphan1 3221225472 1000000 600 0 -' "$W_6" | ADM_REALUSE=1 ADM_SLICECUR=$A/slicecur9 ADM_SLICEMAX=$A/slicemax16 adm 0000000999000000000-1-n 0 1 12)
check "inactive cache: switch off (no memory.stat) counts all 9 GiB and says nothing of cache (got '$out')" '[[ $out == "wait|slice-cap: needs 6.0 GiB; builds.slice uses 9.0 GiB and running builds may take 2.0 more, of the 16.0 GiB cap (MemoryMax)|0" ]]'
out=$(printf '%s\n' "$RUN_OLD" 'F orphan1 3221225472 1000000 600 0 -' "$W_6" | ADM_REALUSE=1 ADM_SLICECUR=$A/slicecur9 ADM_SLICESTAT=$A/none ADM_SLICEMAX=$A/slicemax16 adm 0000000999000000000-1-n 0 1 12)
check "inactive cache: a missing memory.stat counts all 9 GiB (got '$out')" '[[ $out == "wait|slice-cap: needs 6.0 GiB; builds.slice uses 9.0 GiB and running builds may take 2.0 more, of the 16.0 GiB cap (MemoryMax)|0" ]]'
out=$(printf '%s\n' "$RUN_OLD" "$W_6" | ADM_SLICESTAT=$A/stat4 ADM_SLICEMAX=$A/slicemax16 adm 0000000999000000000-1-n 0 1 12)
check "inactive cache: with real use off it changes nothing (got '$out')" '[[ $out == "wait|slice-cap: needs 6.0 GiB; builds hold 12.0 of the 16.0 GiB builds.slice cap (MemoryMax)|0" ]]'
check "inactive cache: HEAVY_BUILD_SLICE_EXCLUDE_INACTIVE_FILE defaults to 1" 'grep -q "^  setting HEAVY_BUILD_SLICE_EXCLUDE_INACTIVE_FILE 1$" "$HB"'
check "inactive cache: memory.stat is passed only when the switch and real use are on" 'grep -qF -- "-v slicestatfile=\"\$( (( REAL_USE && SLICE_EXCLUDE_INACTIVE_FILE )) && echo \"\$BSLICE/memory.stat\")\"" "$HB"'
# Switch off end to end: the plumbing gives an empty slicestatfile.
sw=$(SLICE_EXCLUDE_INACTIVE_FILE=0 REAL_USE=1 BSLICE=/x bash -c 'echo "[$( (( REAL_USE && SLICE_EXCLUDE_INACTIVE_FILE )) && echo "$BSLICE/memory.stat")]"')
check "inactive cache: HEAVY_BUILD_SLICE_EXCLUDE_INACTIVE_FILE=0 passes no memory.stat (got '$sw')" '[[ $sw == "[]" ]]'

# Cores under the real-use rule.
RUN_C_OLD='R u8 990000 4 16 990600 1073741824 22000 0 normal -'
RUN_C_YOUNG='R u9 999950 4 10 1000550 1073741824 - 0 normal -'
W_8C='W 0000000999000000000-1-n 999000 normal 4 8 600 -'
out=$(printf '%s\n' "$RUN_C_OLD" "$W_8C" | adm 0000000999000000000-1-n 0 1 12)
check "real use off: an old build that used 22 cores over 60 s is charged 22, so an 8-core build waits (got '$out')" '[[ $out == "wait|cores: needs 8.0, 22.0 of 28 are charged|0" ]]'
out=$(printf '%s\n' "$RUN_C_OLD" "$W_8C" | ADM_REALUSE=1 ADM_SLICEAVG=4.00 adm 0000000999000000000-1-n 0 1 12)
check "real use: builds.slice used 4 cores over the window, so the 8-core build starts (got '$out')" '[[ $out == start\|fits:* ]]'
out=$(printf '%s\n' "$RUN_C_OLD" "$RUN_C_YOUNG" "$W_8C" | ADM_REALUSE=1 ADM_SLICEAVG=12.00 adm 0000000999000000000-1-n 0 1 12)
check "real use: 12 measured plus 10 for a build 50 s old leaves no room for 8 cores (got '$out')" '[[ $out == "wait|cores: needs 8.0, 22.0 of 28 in use (builds.slice used 12.0 over the last 30 s, plus 10.0 for builds that started recently)|0" ]]'
out=$(printf '%s\n' "$RUN_C_OLD" "$W_8C" | ADM_REALUSE=1 ADM_SLICEAVG=24.00 adm 0000000999000000000-1-n 0 1 12)
check "real use: CPU use in builds.slice the charges do not see (24 cores) still holds the build (got '$out')" '[[ $out == wait\|cores:\ needs\ 8.0,\ 24.0\ of\ 28\ in\ use* ]]'
out=$(printf '%s\n' "$RUN_C_OLD" "$W_8C" | ADM_REALUSE=1 ADM_SLICEAVG= adm 0000000999000000000-1-n 0 1 12)
check "real use: with no CPU window yet the old charge applies (got '$out')" '[[ $out == "wait|cores: needs 8.0, 22.0 of 28 are charged|0" ]]'

# slice_cpu: builds.slice CPU use from shared samples.
scpu() {  # usage_usec samples-lines... ; prints "slice_cores slice_win lines-kept"
  (
    BSLICE=$A/bs; CPUDIR=$A/cpud; SLICE_CPU_SECS=30
    mkdir -p "$BSLICE" "$CPUDIR"
    printf 'usage_usec %s\nuser_usec 0\n' "$1" > "$BSLICE/cpu.stat"; shift
    if (( $# )); then printf '%s\n' "$@" > "$CPUDIR/builds.slice.samples"; else rm -f "$CPUDIR/builds.slice.samples"; fi
    eval "$(sed -n '/^now_us()/p;/^slice_cpu()/,/^}/p' "$HB")"
    now_us() { echo 1000000000000000; }
    slice_cpu
    printf '%s %s %s' "${slice_cores:--}" "$slice_win" "$(wc -l < "$CPUDIR/builds.slice.samples")"
  )
}
out=$(scpu 5000000000)
check "slice cpu: the first sample gives no reading yet and is kept (got '$out')" '[[ $out == "- 0 1" ]]'
out=$(scpu 5000000000 "$(( 1000000000000000 - 10000000 )) 4900000000")
check "slice cpu: a sample only 10 s old gives no reading; a new sample is added after 5 s (got '$out')" '[[ $out == "- 0 2" ]]'
out=$(scpu 5000000000 "$(( 1000000000000000 - 60000000 )) 4400000000" "$(( 1000000000000000 - 2000000 )) 4990000000")
check "slice cpu: 600 s of CPU over 60 s is 10 cores; no new sample 2 s after the last (got '$out')" '[[ $out == "10.00 60 2" ]]'
out=$(scpu 5000000000 "$(( 1000000000000000 - 200000000 )) 1000000000" "$(( 1000000000000000 - 40000000 )) 4800000000")
check "slice cpu: a sample over 120 s old is dropped; 200 s over 40 s is 5 cores (got '$out')" '[[ $out == "5.00 40 2" ]]'
out=$(scpu 5000000000 "$(( 1000000000000000 - 60000000 )) 6000000000")
check "slice cpu: a sample with more usage than now (counter reset) is dropped (got '$out')" '[[ $out == "- 0 1" ]]'
check "slice cpu: the samples file is written with a temp file and mv" 'sed -n "/^slice_cpu()/,/^}/p" "$HB" | grep -q "mv -f \"\$f.\$\$\" \"\$f\""'

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
out=$(unset HEAVY_BUILD_WINE_FALLBACK_PCT; rconf WINE_FALLBACK_PCT)
check "settings: the Wine fallback percentile defaults to 75 (got '$out')" '[[ $out == "75 " ]]'
out=$(HEAVY_BUILD_WINE_FALLBACK_PCT=150 rconf WINE_FALLBACK_PCT)
check "settings: a Wine fallback percentile over 100 goes back to 75 (got '$out')" '[[ $out == "75 " ]]'
out=$(HEAVY_BUILD_WINE_FALLBACK_PCT=90 rconf WINE_FALLBACK_PCT)
check "settings: HEAVY_BUILD_WINE_FALLBACK_PCT=90 is kept (got '$out')" '[[ $out == "90 " ]]'
out=$(unset HEAVY_BUILD_SLICE_EXCLUDE_INACTIVE_FILE; rconf SLICE_EXCLUDE_INACTIVE_FILE)
check "settings: the inactive-cache switch defaults to on (got '$out')" '[[ $out == "1 " ]]'
out=$(HEAVY_BUILD_SLICE_EXCLUDE_INACTIVE_FILE=0 rconf SLICE_EXCLUDE_INACTIVE_FILE)
check "settings: HEAVY_BUILD_SLICE_EXCLUDE_INACTIVE_FILE=0 turns it off (got '$out')" '[[ $out == "0 " ]]'
printf 'HEAVY_BUILD_SWAP_HEADROOM_PCT=10\nHEAVY_BUILD_SWAP_HEADROOM_GIB=4\n' > "$A/hb.conf"
out=$(HEAVY_BUILD_SWAP_HEADROOM_GIB=0 rconf SWAP_HEADROOM_PCT SWAP_HEADROOM_GIB)
check "settings: the file sets them and the environment wins (got '$out')" '[[ $out == "10 0 " ]]'
rm -f "$A/hb.conf"
out=$(unset HEAVY_BUILD_MAX_CPU_PSI; rconf MAX_CPU_PSI)
check "settings: the CPU pressure limit defaults to 75% (got '$out')" '[[ $out == "75 " ]]'
echo HEAVY_BUILD_MAX_CPU_PSI=60 > "$A/hb.conf"
out=$(unset HEAVY_BUILD_MAX_CPU_PSI; rconf MAX_CPU_PSI)
check "settings: HEAVY_BUILD_MAX_CPU_PSI in the file still wins over the default (got '$out')" '[[ $out == "60 " ]]'
rm -f "$A/hb.conf"
out=$(unset HEAVY_BUILD_REAL_USE HEAVY_BUILD_YOUNG_PCT HEAVY_BUILD_YOUNG_MIN_SECS HEAVY_BUILD_SLICE_CPU_SECS; rconf REAL_USE YOUNG_PCT YOUNG_MIN_SECS SLICE_CPU_SECS)
check "settings: the real-use rule is on by default, young is 70% or 120 s, CPU window 30 s (got '$out')" '[[ $out == "1 70 120 30 " ]]'
out=$(unset HEAVY_BUILD_OWN_EST; rconf OWN_EST)
check "settings: own-history estimates are on by default (got '$out')" '[[ $out == "1 " ]]'
out=$(unset HEAVY_BUILD_YOUNG_GROW_PCT; rconf YOUNG_GROW_PCT)
check "settings: young-build growth is charged at 50% by default (got '$out')" '[[ $out == "50 " ]]'
out=$(HEAVY_BUILD_YOUNG_GROW_PCT=150 rconf YOUNG_GROW_PCT)
check "settings: a young-build growth share over 100 falls back to 50 (got '$out')" '[[ $out == "50 " ]]'
printf 'HEAVY_BUILD_REAL_USE=0
HEAVY_BUILD_MEM_RESERVE_GIB=4
' > "$A/hb.conf"
out=$(unset HEAVY_BUILD_REAL_USE HEAVY_BUILD_MEM_RESERVE_GIB; rconf REAL_USE MEM_RESERVE_GIB)
check "settings: HEAVY_BUILD_REAL_USE=0 in the file turns it off, and the reserve comes from the file (got '$out')" '[[ $out == "0 4 " ]]'
out=$(unset HEAVY_BUILD_SLICE_CPU_SECS; HEAVY_BUILD_SLICE_CPU_SECS=2 rconf SLICE_CPU_SECS)
check "settings: a CPU window under 5 s goes back to 30 (got '$out')" '[[ $out == "30 " ]]'

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

# pressure_level: reads the coordinator's level file and pressure hold.
plv() {  # prints "plevel|preason"
  (
    PHOLD=$A/phold PLEVEL_FILE=$A/plevel PRESSURE=${PRESSURE:-1} PRESSURE_STALE_SECS=30 PRESSURE_STALE_SLOW_SECS=600 PHOLD_MAX_SECS=600
    eval "$(sed -n '/^pressure_level()/,/^}/p' "$HB")"
    pressure_level
    echo "$plevel|$preason"
  )
}
rm -f "$A/phold" "$A/plevel"
out=$(plv)
check "pressure_level: no files is none (got '$out')" '[[ $out == "none|" ]]'
echo "level=slow since=$(( EPOCHSECONDS - 100 )) updated=$(( EPOCHSECONDS - 3 )) reason=\"memory full avg10 2.4%\" top=claude-1.scope:3.0%" > "$A/plevel"
out=$(plv)
check "pressure_level: a fresh level file gives its level and reason (got '$out')" '[[ $out == "slow|memory full avg10 2.4%" ]]'
out=$(PRESSURE=0 plv)
check "pressure_level: HEAVY_BUILD_PRESSURE=0 turns it off (got '$out')" '[[ $out == "none|" ]]'
echo "level=pause since=1 updated=$(( EPOCHSECONDS - 31 )) reason=\"x\" top=-" > "$A/plevel"
out=$(plv)
check "pressure_level: a level file 31 s old is slow, and says why (got '$out')" '[[ $out == "slow|the level file was not updated for 31 s, so slow until 600 s" ]]'
echo "level=normal since=1 updated=$(( EPOCHSECONDS - 400 )) reason=\"x\" top=-" > "$A/plevel"
out=$(plv)
check "pressure_level: a normal level file 400 s old is slow too (got '$out')" '[[ $out == slow\|* ]]'
echo "level=pause since=1 updated=$(( EPOCHSECONDS - 601 )) reason=\"x\" top=-" > "$A/plevel"
out=$(plv)
check "pressure_level: a level file 601 s old is stale (got '$out')" '[[ $out == "stale|" ]]'
echo "level=pause since=1 updated=$(( EPOCHSECONDS + 60 )) reason=\"x\" top=-" > "$A/plevel"
out=$(plv)
check "pressure_level: updated= 60 s in the future is stale (got '$out')" '[[ $out == "stale|" ]]'
echo "garbage" > "$A/plevel"
out=$(plv)
check "pressure_level: a file it cannot parse is none (got '$out')" '[[ $out == "none|" ]]'
echo "level=normal since=1 updated=$EPOCHSECONDS reason=\"all signals low\" top=-" > "$A/plevel"
echo "expires=$(( EPOCHSECONDS + 30 )) pressure-coordinator: level pause (memory full avg10 6.1%)" > "$A/phold"
out=$(plv)
check "pressure_level: a pressure hold in force is pause, with its text (got '$out')" '[[ $out == "pause|pressure-coordinator: level pause (memory full avg10 6.1%)" ]]'
echo "expires=$(( EPOCHSECONDS - 1 )) pressure-coordinator: level pause (old)" > "$A/phold"
out=$(plv)
check "pressure_level: an expired pressure hold is ignored (got '$out')" '[[ $out == "normal|all signals low" ]]'
: > "$A/phold"
out=$(plv)
check "pressure_level: an empty pressure hold is no hold (got '$out')" '[[ $out == "normal|all signals low" ]]'
echo "pressure-coordinator: level pause (no expiry)" > "$A/phold"
out=$(plv)
check "pressure_level: a pressure hold without expires= is no hold (got '$out')" '[[ $out == "normal|all signals low" ]]'
echo "expires=$(( EPOCHSECONDS + 3600 )) far away" > "$A/phold"
out=$(plv)
check "pressure_level: a pressure hold 3600 s ahead is not trusted (got '$out')" '[[ $out == "normal|all signals low" ]]'
rm -f "$A/phold"; mkdir "$A/phold"
out=$(plv 2>&1); rc=$?
check "pressure_level: a hold that cannot be read (gone between -e and read) is no hold, no crash under set -u (rc $rc, got '$out')" '(( rc == 0 )) && [[ $out == "normal|all signals low" ]]'
rmdir "$A/phold"
out=$(
  set -u
  PHOLD=$A/phold PLEVEL_FILE=$A/plevel PRESSURE=1 PRESSURE_STALE_SECS=30 PRESSURE_STALE_SLOW_SECS=600 PHOLD_MAX_SECS=600
  eval "$(sed -n '/^pressure_level()/,/^}/p' "$HB")"
  # The hold file is there for -e and gone for read: the race from the review.
  eval "$(declare -f pressure_level | sed 's|\[\[ -e \$PHOLD \]\]|{ [[ -e $PHOLD ]] \&\& rm -f -- "$PHOLD"; }|')"
  echo "expires=$(( EPOCHSECONDS + 30 )) x" > "$PHOLD"
  pressure_level; echo "$plevel|$preason"
) 2>&1; rc=$?
check "pressure_level: the hold removed between -e and read is no hold (rc $rc, got '$out')" '(( rc == 0 )) && [[ $out == "normal|all signals low" ]]'
rm -f "$A/phold" "$A/plevel"
out=$(unset HEAVY_BUILD_PRESSURE HEAVY_BUILD_PRESSURE_STALE_SECS; rconf PRESSURE PRESSURE_STALE_SECS)
check "settings: the pressure level is on, stale after 30 s, by default (got '$out')" '[[ $out == "1 30 " ]]'
out=$(unset HEAVY_BUILD_PRESSURE_STALE_SLOW_SECS; rconf PRESSURE_STALE_SLOW_SECS)
check "settings: a stale level counts as slow for 600 s by default (got '$out')" '[[ $out == "600 " ]]'
out=$(unset HEAVY_BUILD_SLOW_GAP_SECS HEAVY_BUILD_SLOW_FAST_GAP_SECS HEAVY_BUILD_SLOW_FAST_MIN_GIB; rconf SLOW_GAP_SECS SLOW_FAST_GAP_SECS SLOW_FAST_MIN_GIB)
check "settings: the slow gap is 120 s, or 30 s above 16 GiB free, by default (got '$out')" '[[ $out == "120 30 16 " ]]'
printf 'HEAVY_BUILD_SLOW_GAP_SECS=90\nHEAVY_BUILD_SLOW_FAST_GAP_SECS=20\nHEAVY_BUILD_SLOW_FAST_MIN_GIB=24\n' > "$A/hb.conf"
out=$(unset HEAVY_BUILD_SLOW_GAP_SECS HEAVY_BUILD_SLOW_FAST_GAP_SECS HEAVY_BUILD_SLOW_FAST_MIN_GIB; rconf SLOW_GAP_SECS SLOW_FAST_GAP_SECS SLOW_FAST_MIN_GIB)
check "settings: the slow gap keys are read from heavy-build.conf (got '$out')" '[[ $out == "90 20 24 " ]]'
rm -f "$A/hb.conf"
rm -rf -- "$A"

# sweep_stale: a scope whose heavy-build is gone is stopped only when it
# holds nothing but Wine leftovers. Anything else stays (event=sweep-skip),
# however idle. A scope whose heavy-build runs is never touched.
SW=$(mktemp -d "${TMPDIR:-/var/tmp}/hb-test.XXXXXX")
T=$SW; : > "$T/out"
swscope() {  # unit "pid:comm ..." ; makes a populated scope with those processes
  local d=$SW/bs/$1.scope pc
  rm -rf -- "$d"; mkdir -p "$d"; echo "populated 1" > "$d/cgroup.events"; : > "$d/cgroup.procs"
  for pc in $2; do
    echo "${pc%%:*}" >> "$d/cgroup.procs"
    mkdir -p "$SW/proc/${pc%%:*}"; echo "${pc#*:}" > "$SW/proc/${pc%%:*}/comm"
  done
}
swp() {  # runs sweep_stale; prints its log lines and systemctl calls
  (
    BSLICE=$SW/bs JDIR=$SW/jobs CPUDIR=$SW/cpu PROC=$SW/proc
    mkdir -p "$JDIR" "$CPUDIR"
    eval "$(grep '^WINE_LEFTOVERS=' "$HB")"
    eval "$(sed -n '/^scope_procs()/,/^}/p;/^only_wine_leftovers()/,/^}/p;/^hb_alive()/,/^}/p;/^proc_start()/,/^}/p;/^sweep_stale()/,/^}/p' "$HB")"
    log_line() { echo "LOG $*"; }
    systemctl() { echo "CALL $*"; }
    sweep_stale
  )
}
dead=heavy-build-999999991-1 alive=heavy-build-$$-1
mkdir -p "$SW/jobs"
echo "$dead 999999991 12345" > "$SW/jobs/$dead"
swscope "$dead" "5001:wineserver 5002:winedevice.exe"
out=$(swp)
check "sweep: a dead heavy-build's scope with only Wine leftovers is stopped (got '$out')" '[[ $out == *"event=sweep unit=$dead reason=wine-leftovers"* && $out == *"CALL --user kill --signal=KILL $dead.scope"* && $out == *"CALL --user stop $dead.scope"* ]]'
echo "$dead 999999991 12345" > "$SW/jobs/$dead"
swscope "$dead" "5003:cargo"
out=$(swp)
check "sweep: a dead heavy-build's scope with an idle cargo is not stopped, logged sweep-skip (got '$out')" '[[ $out == *"event=sweep-skip unit=$dead"* && $out != *CALL* ]]'
out=$(swp)
check "sweep: the sweep-skip is logged once (got '$out')" '[[ -z $out ]]'
rm -f -- "$SW/cpu/$dead.noted"
swscope "$dead" "5001:wineserver 5004:dotnet"
out=$(swp)
check "sweep: Wine leftovers next to a real process are not stopped (got '$out')" '[[ $out == *"event=sweep-skip"* && $out != *CALL* ]]'
rm -rf -- "$SW/bs/$dead.scope"
echo "$alive $$ $(awk '{sub(/.*\) /, ""); split($0, a, " "); print a[20]}' /proc/$$/stat)" > "$SW/jobs/$alive"
swscope "$alive" "5001:wineserver"
out=$(swp)
check "sweep: a scope whose heavy-build still runs is never touched (got '$out')" '[[ -z $out ]]'
check "sweep: no idle-CPU stop rule left in sweep_stale" '! sed -n "/^sweep_stale()/,/^}/p" "$HB" | grep -q "why=idle\|cpu_rate"'
rm -rf -- "$SW"

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
hbx --status; rc=$?
check "options: an unknown option like --status is exit 2, not a queued command (got $rc)" '(( rc == 2 )) && grep -q "unknown option" "$T/out"'
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
# The high-cap: a high waiter held by it is never the head of the line, so an
# old one (past the 1800 s starve time) does not stop normal builds behind it.
RUN_H1='R h1 990000 4 2 1000600 4294967296 - 0 high -'
RUN_H2='R h2 990000 4 2 1000600 4294967296 - 0 high -'
W_HOLD='W 0000000990000000000-3-h 990000 high 4 2 600 -'
W_NEW='W 0000000999000000001-2-b 999001 normal 4 2 600 -'
out=$(printf '%s\n' "$RUN_H1" "$RUN_H2" "$W_HOLD" | adm 0000000990000000000-3-h 0 1 12)
check "high-cap: a third high build waits (got '$out')" '[[ $out == wait\|high-cap:* ]]'
out=$(printf '%s\n' "$RUN_H1" "$RUN_H2" "$W_HOLD" "$W_NEW" | adm 0000000999000000001-2-b 0 1 12)
check "high-cap: a normal build behind an old capped high waiter starts as next in order (got '$out')" '[[ $out == "start|fits: next in order|0" ]]'
out=$(printf '%s\n' "$RUN_H1" "$W_HOLD" "$W_NEW" | adm 0000000990000000000-3-h 0 1 12)
check "high-cap: with one high build running, the high waiter starts first (got '$out')" '[[ $out == start\|fits:* ]]'
# Idle builds (stalled=1: under 0.05 cores for 10 min) count neither for the
# high-cap nor for the job limit, and the reason names them. On 2026-10-23 a
# hung Wine suite held a high slot and a job slot for about 50 min.
RUN_H1I='R h1 990000 4 2 1000600 4294967296 - 1 high -'
RUN_H2I='R h2 990000 4 2 1000600 4294967296 - 1 high -'
out=$(printf '%s\n' "$RUN_H1" "$RUN_H2I" "$W_HOLD" | adm 0000000990000000000-3-h 0 1 12)
check "idle: one active and one idle high build do not block a second high build (got '$out')" '[[ $out == "start|fits: next in order (idle, not counted as a job or a high build: h2)|0" ]]'
out=$(printf '%s\n' "$RUN_H1I" "$RUN_H2I" "$W_HOLD" | adm 0000000990000000000-3-h 0 1 12)
check "idle: two idle high builds do not block a third high build (got '$out')" '[[ $out == "start|fits: next in order (idle, not counted as a job or a high build: h1,h2)|0" ]]'
RUN_J='R b%d 999000 4 2 1000600 4294967296 - %d normal -'
out=$(printf "$RUN_J\n" 1 0 2 0 3 0 4 0 5 0 6 1 | cat - <(echo "$W_BLD") | adm 0000000999000000001-2-b 0 1 12)
check "idle: 5 active builds and 1 idle one leave a job slot (got '$out')" '[[ $out == "start|fits: next in order (idle, not counted as a job or a high build: b6)|0" ]]'
out=$(printf "$RUN_J\n" 1 0 2 0 3 0 4 0 5 0 6 0 | cat - <(echo "$W_BLD") | adm 0000000999000000001-2-b 0 1 12)
check "idle: 6 active builds still fill the 6 job slots (got '$out')" '[[ $out == "wait|jobs: 6 builds run, the limit is 6|0" ]]'
out=$(printf "$RUN_J\n" 1 0 2 0 3 0 4 0 5 0 6 0 7 1 | cat - <(echo "$W_BLD") | adm 0000000999000000001-2-b 0 1 12)
check "idle: an idle build is named even when the waiter still waits (got '$out')" '[[ $out == "wait|jobs: 6 builds run, the limit is 6 (idle, not counted as a job or a high build: b7)|0" ]]'
out=$(printf '%s\n' 'R b1 999000 4 2 1000600 4294967296 - 1 normal -' "$W_BLD" | ADM_MEMINFO=<(printf 'MemAvailable: %d kB\nSwapTotal: 0 kB\nSwapFree: 0 kB\n' $(( 9 * 1048576 ))) adm 0000000999000000001-2-b 0 1 12)
check "idle: with only an idle build running, the full memory test still applies (got '$out')" '[[ $out == wait\|memory:* ]]'
# Aged critical builds (2026-10-23, approved by Oystein): a critical build
# that has waited 1800 s goes ahead of high builds, and with the starve rule
# holds the cores it needs. While it waits for memory, other critical builds
# that fit may pass it. An aged normal build ranks behind critical ones.
# 28 cores, 20 charged by two running builds: 8 free.
RUN_X1='R x1 990000 4 10 999000 4294967296 - 0 normal -'
RUN_X2='R x2 990000 4 10 999000 4294967296 - 0 normal -'
W_CAGED='W 0000000990000000000-1-c 990000 critical 4 10 300 -'
W_CAGED5='W 0000000990000000000-1-c 990000 critical 4 5 300 -'
W_CYOUNG='W 0000000999000000000-1-c 999000 critical 4 5 300 -'
W_HNEW='W 0000000999500000000-3-h 999500 high 4 5 60 -'
out=$(printf '%s\n' "$RUN_X1" "$RUN_X2" "$W_CAGED5" "$W_HNEW" | adm 0000000990000000000-1-c 0 1 12)
check "aged critical: one that waited 10000 s starts ahead of a newer high build when only one fits (got '$out')" '[[ $out == "start|fits: next in order|0" ]]'
out=$(printf '%s\n' "$RUN_X1" "$RUN_X2" "$W_CAGED5" "$W_HNEW" | adm 0000000999500000000-3-h 0 1 12)
check "aged critical: the high build then waits for cores (got '$out')" '[[ $out == wait\|cores:* ]]'
out=$(printf '%s\n' "$RUN_X1" "$RUN_X2" "$W_CAGED" "$W_HNEW" | adm 0000000999500000000-3-h 0 1 12)
check "aged critical: a high build that fits may not pass an aged critical head that waits for cores (got '$out')" '[[ $out == "wait|starve: 0000000990000000000-1-c has waited 166 min, so nothing may pass it|1" ]]'
out=$(printf '%s\n' "$RUN_X1" "$RUN_X2" "$W_CYOUNG" "$W_HNEW" | adm 0000000999500000000-3-h 0 1 12)
check "aged critical: a critical build that waited 1000 s still ranks behind high (got '$out')" '[[ $out == start\|fits:* ]]'
out=$(printf '%s\n' "$RUN_X1" "$RUN_X2" "$W_CAGED" "$W_HNEW" | ADM_CRITAGE=0 adm 0000000999500000000-3-h 0 1 12)
check "aged critical: HEAVY_BUILD_CRIT_AGE_SECS=0 turns it off (got '$out')" '[[ $out == start\|fits:* ]]'
# The memory exception: the aged critical head needs 36 GiB of the 40 (reserve 6).
printf 'MemAvailable: %d kB\nSwapTotal: 0 kB\nSwapFree: 0 kB\n' $(( 40 * 1048576 )) > "$A/meminfo40"
W_CBIG='W 0000000990000000000-1-c 990000 critical 36 2 300 -'
W_CSMALL='W 0000000995000000000-2-c 995000 critical 4 2 300 -'
W_HSMALL='W 0000000999500000000-3-h 999500 high 4 2 60 -'
RUN_M='R m1 990000 8 2 999000 8589934592 - 0 normal -'
out=$(printf '%s\n' "$RUN_M" "$W_CBIG" "$W_CSMALL" "$W_HSMALL" | ADM_MEMINFO=$A/meminfo40 adm 0000000990000000000-1-c 0 1 12)
check "aged critical, memory: the big head waits for memory (got '$out')" '[[ $out == wait\|memory:* ]]'
out=$(printf '%s\n' "$RUN_M" "$W_CBIG" "$W_CSMALL" "$W_HSMALL" | ADM_MEMINFO=$A/meminfo40 adm 0000000995000000000-2-c 0 1 12)
check "aged critical, memory: another critical build that fits passes it (got '$out')" '[[ $out == "start|fits: the aged critical build 0000000990000000000-1-c waits for memory, and critical builds that fit may pass it|0" ]]'
out=$(printf '%s\n' "$RUN_M" "$W_CBIG" "$W_CSMALL" "$W_HSMALL" | ADM_MEMINFO=$A/meminfo40 adm 0000000999500000000-3-h 0 1 12)
check "aged critical, memory: a high build still may not pass it (got '$out')" '[[ $out == wait\|starve:* ]]'
# An aged normal build (waited 3600 s) ranks behind a critical one.
W_NAGED='W 0000000990000000000-1-n 990000 normal 4 5 300 -'
W_CNEW='W 0000000999000000000-2-c 999000 critical 4 5 300 -'
out=$(printf '%s\n' "$RUN_X1" "$RUN_X2" "$W_NAGED" "$W_CNEW" | adm 0000000999000000000-2-c 0 1 12)
check "aging slot: a critical build starts ahead of an aged normal one when only one fits (got '$out')" '[[ $out == start\|fits:* ]]'
out=$(printf '%s\n' "$RUN_X1" "$RUN_X2" "$W_NAGED" "$W_CNEW" | adm 0000000990000000000-1-n 0 1 12)
check "aging slot: the aged normal build then waits for cores (got '$out')" '[[ $out == wait\|cores:* ]]'
out=$(printf '%s\n' "$RUN_X1" "$W_NAGED" 'W 0000000999000000000-2-n 999000 normal 4 5 300 -' | adm 0000000990000000000-1-n 0 1 12)
check "aging slot: an aged normal build still goes ahead of other normal builds (got '$out')" '[[ $out == start\|aged:* ]]'
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
  (cd "$T/work" && exec env -u HEAVY_BUILD_MODE -u HEAVY_BUILD_TIMEOUT -u HEAVY_BUILD_SESSION -u HEAVY_BUILD_SESSION_PID HBT="$T" PATH="$T/bin:$PATH" \
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
check "app scope: MemoryHigh=10G, MemoryMax=20G, MemorySwapMax=8G, no RuntimeMaxSec" 'grep -q "MemoryHigh=10G -p MemoryMax=20G -p MemorySwapMax=8G" "$T/calls" && ! grep -q RuntimeMaxSec "$T/calls"'
check "app scope: the whole scope is stopped when the command ends" 'grep -qx "systemctl --user stop $u" "$T/calls"'
check "app history: class app-run, exit 143, reason stopped, MemoryHigh 10 GiB" 'awk -F"\t" -v g=$G '\''$2 == "app-run" && $7 == 143 && $8 == "stopped" && $10 == 10 * g'\'' "$T/state/heavy-build/history.tsv" | grep -q .'
teardown2

# heavy-build itself gets TERM (headless-mc.sh stop): an app run logs
# reason stopped, a build logs cancelled.
for c in app-run:stopped build:cancelled; do
  setup2
  printf '#!/usr/bin/env bash\nsleep 30\n' > "$T/slow.sh"; chmod +x "$T/slow.sh"
  if [[ ${c%%:*} == app-run ]]; then hbe -- --class app-run --ready-file "$T/ready" "$T/slow.sh"
  else hbe -- --ready-file "$T/ready" "$T/slow.sh"; fi
  for _ in $(seq 1 100); do [[ -e $T/ready ]] && break; sleep 0.1; done
  kill -TERM "$hbpid"; wait "$hbpid"; rc=$?
  check "TERM to heavy-build: ${c%%:*} exits 143 and logs reason ${c#*:} (rc $rc)" '(( rc == 143 )) && awk -F"\t" -v r="${c#*:}" '\''$7 == 143 && $8 == r'\'' "$T/state/heavy-build/history.tsv" | grep -q .'
  teardown2
done

# A detected app run takes HEAVY_BUILD_APP_MEM_HIGH_GIB from the conf file.
setup2
printf 'HEAVY_BUILD_APP_MEM_HIGH_GIB=14\n' > "$T/config/heavy-build.conf"
mkdir -p "$T/w2/tools/wine"; printf '#!/bin/sh\nexit 0\n' > "$T/w2/tools/wine/run-mc.sh"; chmod +x "$T/w2/tools/wine/run-mc.sh"
hbe -- "$T/w2/tools/wine/run-mc.sh" a
wait "$hbpid"; rc=$?
check "app scope: run-mc.sh is detected and HEAVY_BUILD_APP_MEM_HIGH_GIB=14 gives MemoryHigh=14G (rc $rc)" '(( rc == 0 )) && grep -q "MemoryHigh=14G -p MemoryMax=28G" "$T/calls" && awk -F"\t" '\''$2 == "app-run" && $7 == 0 && $8 == "ok"'\'' "$T/state/heavy-build/history.tsv" | grep -q .'
teardown2

# App runs get CPUQuota from HEAVY_BUILD_APP_CPU_QUOTA (default 800%); 0 or
# empty means none; builds never get one.
# Each case: label|env setting or -|conf line or -|class (app or build)|expected quota or none
for c in "default|-|-|app|800" "env override|HEAVY_BUILD_APP_CPU_QUOTA=400|-|app|400" \
  "conf override|-|HEAVY_BUILD_APP_CPU_QUOTA=1200|app|1200" "env beats conf|HEAVY_BUILD_APP_CPU_QUOTA=300|HEAVY_BUILD_APP_CPU_QUOTA=1200|app|300" \
  "env 0 disables|HEAVY_BUILD_APP_CPU_QUOTA=0|-|app|none" "env empty disables|HEAVY_BUILD_APP_CPU_QUOTA=|-|app|none" \
  "conf 0 disables|-|HEAVY_BUILD_APP_CPU_QUOTA=0|app|none" "conf empty disables|-|HEAVY_BUILD_APP_CPU_QUOTA=|app|none" \
  "build unaffected|-|-|build|none" "build unaffected by env|HEAVY_BUILD_APP_CPU_QUOTA=400|-|build|none"; do
  IFS='|' read -r lbl ev cf kind want <<< "$c"
  setup2
  [[ $cf != - ]] && printf '%s\n' "$cf" > "$T/config/heavy-build.conf"
  printf '#!/bin/sh\nexit 0\n' > "$T/ok.sh"; chmod +x "$T/ok.sh"
  args=("$T/ok.sh"); [[ $kind == app ]] && args=(--class app-run "$T/ok.sh")
  if [[ $ev != - ]]; then hbe "$ev" -- "${args[@]}"; else hbe -- "${args[@]}"; fi
  wait "$hbpid"; rc=$?
  if [[ $want == none ]]; then
    check "cpu quota: $lbl gives no CPUQuota (rc $rc)" '(( rc == 0 )) && grep -q "^systemd-run .*MemoryHigh=" "$T/calls" && ! grep -q CPUQuota "$T/calls"'
  else
    check "cpu quota: $lbl gives CPUQuota=$want% (rc $rc)" '(( rc == 0 )) && grep -q "^systemd-run .* -p CPUQuota=$want% " "$T/calls"'
  fi
  if [[ $kind == app ]]; then
    lw=$want; [[ $want != none ]] && lw="$want%"
    check "cpu quota: $lbl logs cpu_quota=$lw on the start line" 'grep -q "decision=start .* cpu_quota=$lw " "$T/state/heavy-build/shadow.log"'
  else
    check "cpu quota: $lbl logs no cpu_quota" '! grep -q cpu_quota "$T/state/heavy-build/shadow.log"'
  fi
  teardown2
done

# MemoryMax is twice MemoryHigh but never over builds.slice memory.max.
setup2
printf 'HEAVY_BUILD_APP_MEM_HIGH_GIB=30\n' > "$T/config/heavy-build.conf"
mkdir -p "$T/cg/user.slice/user-$UID.slice/user@$UID.service/builds.slice"
echo $(( 42 * G )) > "$T/cg/user.slice/user-$UID.slice/user@$UID.service/builds.slice/memory.max"
mkdir -p "$T/w2/tools/wine"; printf '#!/bin/sh\nexit 0\n' > "$T/w2/tools/wine/run-mc.sh"; chmod +x "$T/w2/tools/wine/run-mc.sh"
hbe -- "$T/w2/tools/wine/run-mc.sh" a
wait "$hbpid"; rc=$?
check "scope caps: MemoryHigh 30G gives MemoryMax 42G, the builds.slice memory.max (rc $rc)" '(( rc == 0 )) && grep -q "MemoryHigh=30G -p MemoryMax=42G -p MemorySwapMax=8G" "$T/calls"'
check "scope caps: history column 9 is the real MemoryMax, 42 GiB" 'awk -F"\t" -v g=$G '\''$9 == 42 * g'\'' "$T/state/heavy-build/history.tsv" | grep -q .'
teardown2

# Live mode: a normal start records its time for the slow rule; a high one does not.
setup2
printf 'HEAVY_BUILD_MODE=live\n' > "$T/config/heavy-build.conf"
hbe -- true
wait "$hbpid"; rc=$?
v=$(cat "$T/run/heavy-build.last-normal-start" 2>/dev/null)
check "live: a normal start writes heavy-build.last-normal-start (rc $rc, got '$v')" '(( rc == 0 )) && [[ $v =~ ^[0-9]+$ ]] && (( EPOCHSECONDS - v < 30 ))'
rm -f "$T/run/heavy-build.last-normal-start"
hbe HEAVY_BUILD_PRIORITY=high HEAVY_BUILD_REASON=test -- true
wait "$hbpid"; rc=$?
check "live: a high start does not write it (rc $rc)" '(( rc == 0 )) && [[ ! -e $T/run/heavy-build.last-normal-start ]]'
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

# End to end: the level goes into each decision line as pressure=<level>,
# and the interactive gate reads claude.slice from the cgroup tree.
setup
mkdir -p "$T/state/pressure"
echo "level=slow since=1 updated=$EPOCHSECONDS reason=\"test slow\" top=-" > "$T/state/pressure/level"
run_hb
wait "$hbpid"
check "log: decision lines say pressure=slow" 'grep -q "decision=wait .*pressure=slow " "$T/state/heavy-build/shadow.log"'
check "log: the refuse line says pressure=slow" 'grep -q "decision=refuse .*pressure=slow " "$T/state/heavy-build/shadow.log"'
teardown
setup
u=$T/cg/user.slice/user-$UID.slice/user@$UID.service
mkdir -p "$u/app.slice" "$u/claude.slice"
printf 'some avg10=90.00 avg60=0 avg300=0 total=1\nfull avg10=90.00 avg60=0 avg300=0 total=1\n' > "$u/app.slice/memory.pressure"
run_hb
wait "$hbpid"
check "interactive: app.slice at 90% does not gate (budget rule)" '! grep -q "interactive:" "$T/state/heavy-build/shadow.log"'
teardown
setup
u=$T/cg/user.slice/user-$UID.slice/user@$UID.service
mkdir -p "$u/claude.slice"
printf 'some avg10=9.00 avg60=0 avg300=0 total=1\nfull avg10=9.00 avg60=0 avg300=0 total=1\n' > "$u/claude.slice/memory.pressure"
run_hb
wait "$hbpid"
check "interactive: claude.slice full 9% gates (budget rule)" 'grep -q "interactive: claude.slice memory pressure (full) 9.0%" "$T/state/heavy-build/shadow.log"'
teardown


# 9. The memory controller (HEAVY_BUILD_MEM_CONTROLLER=1, awk memctl=1).
A=$(mktemp -d "${TMPDIR:-/var/tmp}/hb-test.XXXXXX")
T=$A; : > "$T/out"
mi() { printf 'MemAvailable: %d kB\nSwapTotal: 0 kB\nSwapFree: 0 kB\n' $(( $1 * 1048576 )); }
RUN_OLD4='R o1 999000 4 2 999500 4294967296 - 0 normal -'
W_10='W 0000000999000000000-1-n 999000 normal 10 2 600 -'
W_4='W 0000000999000000000-1-n 999000 normal 4 2 600 -'
W_1='W 0000000999000000000-1-n 999000 normal 1 2 600 -'
W_H1='W 0000000999000000000-3-h 999000 high 1 2 600 -'
out=$(printf '%s\n' "$RUN_OLD4" "$W_10" | ADM_MEMINFO=<(mi 13) adm 0000000999000000000-1-n 0 1 12)
check "memctl off: a 10 GiB build with 13 GiB free waits for the reserve (got '$out')" '[[ $out == wait\|memory:\ needs\ 10.0\ GiB\;* ]]'
out=$(printf '%s\n' "$RUN_OLD4" "$W_10" | ADM_MC=1 ADM_MEMINFO=<(mi 13) adm 0000000999000000000-1-n 0 1 12)
check "memctl on: the same build starts, 13 - 0 - 50% of 10 leaves 8 of the 6 target (got '$out')" '[[ $out == start\|fits:* ]]'
out=$(printf '%s\n' "$RUN_OLD4" 'W 0000000999000000000-1-n 999000 normal 16 2 600 -' | ADM_MC=1 ADM_MEMINFO=<(mi 13) adm 0000000999000000000-1-n 0 1 12)
check "memctl on: a 16 GiB build would leave 5 of the 6 target, so it waits (got '$out')" '[[ $out == "wait|memory: needs 16.0 GiB, charged 50%; 13.0 available, 0.0 still to come for young builds, target 6|0" ]]'
out=$(printf '%s\n' "$RUN_OLD4" "$W_1" | ADM_MC=1 ADM_MEMINFO=<(mi 2) adm 0000000999000000000-1-n 0 1 12)
check "memctl on: nothing starts under the 3 GiB hard floor (got '$out')" '[[ $out == "wait|memory: 2.0 GiB available, the memory controller starts nothing under 3|0" ]]'
out=$(printf '%s\n' 'R y1 999970 8 2 1000600 1073741824 - 0 normal -' "$W_4" | ADM_MC=1 ADM_MEMINFO=<(mi 13) adm 0000000999000000000-1-n 0 1 12)
check "memctl on: a build 30 s old is charged its full estimate, 13 - 7 - 2 < 6 (got '$out')" '[[ $out == wait\|memory:*7.0\ still\ to\ come\ for\ young\ builds* ]]'
out=$(printf '%s\n' 'R y1 999910 8 2 1000600 1073741824 - 0 normal -' "$W_4" | ADM_MC=1 ADM_MEMINFO=<(mi 13) adm 0000000999000000000-1-n 0 1 12)
check "memctl on: at 90 s it is charged 50%, 13 - 3 - 2 >= 6, so it starts (got '$out')" '[[ $out == start\|fits:* ]]'
out=$(printf '%s\n' 'R o2 999000 20 2 999500 1073741824 - 0 normal -' "$W_4" | ADM_MC=1 ADM_MEMINFO=<(mi 13) adm 0000000999000000000-1-n 0 1 12)
check "memctl on: an old build is expected to take nothing more (got '$out')" '[[ $out == start\|fits:* ]]'
out=$(printf '%s\n' "$RUN_OLD4" "$W_1" "$W_H1" | ADM_MC=1 ADM_MCHARMAGO=30 ADM_MEMINFO=<(mi 20) adm 0000000999000000000-1-n 0 1 12)
check "memctl on: the brake holds a normal build, clock held (got '$out')" '[[ $out == wait\|pressure:\ memory\ controller\ brake*\|1 ]]'
out=$(printf '%s\n' "$RUN_OLD4" "$W_1" "$W_H1" | ADM_MC=1 ADM_MCHARMAGO=30 ADM_MEMINFO=<(mi 20) adm 0000000999000000000-3-h 0 1 12)
check "memctl on: the brake does not hold a high build (got '$out')" '[[ $out == start\|fits:* ]]'
out=$(printf '%s\n' "$RUN_OLD4" "$W_1" | ADM_MC=1 ADM_MCHARMAGO=61 ADM_MEMINFO=<(mi 20) adm 0000000999000000000-1-n 0 1 12)
check "memctl on: 61 s calm releases the brake (got '$out')" '[[ $out == start\|fits:* ]]'
out=$(printf '%s\n' "$RUN_OLD4" "$W_1" | ADM_MC=1 ADM_MCFALL=3000 ADM_MEMINFO=<(mi 20) adm 0000000999000000000-1-n 0 1 12)
check "memctl on: MemAvailable fell 2.9 GiB in 15 s, so it waits (got '$out')" '[[ $out == wait\|pressure:\ memory\ controller,\ MemAvailable\ fell\ 2.9\ GiB* ]]'
out=$(printf '%s\n' "$RUN_OLD4" "$W_1" | ADM_MC=1 ADM_LASTNC=999980 ADM_MEMINFO=<(mi 13) adm 0000000999000000000-1-n 0 1 12)
check "memctl on: 13 GiB free, one start per 30 s, the last 20 s ago (got '$out')" '[[ $out == wait\|pressure:\ memory\ controller,\ 13.0\ GiB\ free,\ one\ new\ build\ per\ 30\ s* ]]'
out=$(printf '%s\n' "$RUN_OLD4" "$W_1" | ADM_MC=1 ADM_LASTNC=999980 ADM_MEMINFO=<(mi 20) adm 0000000999000000000-1-n 0 1 12)
check "memctl on: 20 GiB free, one start per 15 s, so it starts (got '$out')" '[[ $out == start\|fits:* ]]'
out=$(printf '%s\n' "$RUN_OLD4" "$W_1" | ADM_MC=1 ADM_LASTNC=999950 ADM_MEMINFO=<(mi 8) adm 0000000999000000000-1-n 0 1 12)
check "memctl on: 8 GiB free, one start per 60 s, the last 50 s ago (got '$out')" '[[ $out == wait\|pressure:\ memory\ controller,\ 8.0\ GiB\ free,\ one\ new\ build\ per\ 60\ s* ]]'
out=$(printf '%s\n' "$RUN_OLD4" "$W_1" | ADM_PLEVEL=slow ADM_LASTNC=999950 ADM_MEMINFO=<(mi 13) adm 0000000999000000000-1-n 0 1 12)
check "memctl off: level slow at 13 GiB holds 120 s (got '$out')" '[[ $out == wait\|pressure:\ level\ slow* ]]'
out=$(printf '%s\n' "$RUN_OLD4" "$W_1" | ADM_MC=1 ADM_PLEVEL=slow ADM_LASTNC=999950 ADM_MEMINFO=<(mi 13) adm 0000000999000000000-1-n 0 1 12)
check "memctl on: level slow is replaced by the 30 s pace (got '$out')" '[[ $out == start\|fits:* ]]'
out=$(printf '%s\n' "$RUN_OLD4" "$W_1" | ADM_MC=1 ADM_PLEVEL=pause ADM_MEMINFO=<(mi 20) adm 0000000999000000000-1-n 0 1 12)
check "memctl on: level pause still holds a normal build (got '$out')" '[[ $out == wait\|pressure:\ level\ pause* ]]'
out=$(printf '%s\n' "$W_10" | ADM_MC=1 ADM_MEMINFO=<(mi 12) adm 0000000999000000000-1-n 0 1 12)
check "memctl on: with no build running the solo rule still decides (got '$out')" '[[ $out == start\|fits:* ]]'

# mem_watch: the sampler behind the brake and the fall test.
mwn=0
mw() {  # vmstat_pswpin avail_gib full10 ; samples file on stdin ; prints "swapin fall harm_ago samples"
  local M=$A/mw$(( ++mwn ))
  mkdir -p "$M/pressure" "$M/cpu"
  printf 'pgpgin 1\npswpin %s\npswpout 1\n' "$1" > "$M/vmstat"
  printf 'MemTotal: 65753100 kB\nMemAvailable: %d kB\n' $(( $2 * 1048576 )) > "$M/meminfo"
  printf 'some avg10=1.00 avg60=0 avg300=0 total=1\nfull avg10=%s avg60=0 avg300=0 total=1\n' "$3" > "$M/pressure/memory"
  cat > "$M/cpu/mem.samples"
  (
    eval "$(sed -n '/^mem_watch() {/,/^}/p' "$HB")"
    PROC=$M MEMINFO=$M/meminfo CPUDIR=$M/cpu MC_CALM_SECS=60 MC_BRAKE_GIB=10 MC_BRAKE_SWAPIN=2000 MC_BRAKE_FULL_PCT=10
    mem_watch
    echo "$mc_swapin $mc_fall $mc_harm_ago $(wc -l < "$M/cpu/mem.samples")"
  )
}
now=$EPOCHSECONDS
out=$(printf '%s 0 %d 0\n' $(( now - 20 )) $(( 8 * 1048576 )) | mw 60000 8 0.5)
check "mem_watch: 60000 pages in 20 s is 3000/s, under 10 GiB, so the brake fires now (got '$out')" '[[ $out == "3000 0 0 2" ]]'
out=$(printf '%s 0 %d 0\n' $(( now - 20 )) $(( 12 * 1048576 )) | mw 60000 12 0.5)
check "mem_watch: the same swap-in with 12 GiB free is no harm (got '$out')" '[[ $out == "3000 0 999999 2" ]]'
out=$(printf '%s 0 %d 0\n' $(( now - 20 )) $(( 20 * 1048576 )) | mw 0 8 12.5)
check "mem_watch: memory full 12.5% under 10 GiB is harm (got '$out')" '[[ $out == "0 0 0 2" ]]'
out=$(printf '%s 0 %d 0\n%s 0 %d 1\n' $(( now - 20 )) $(( 20 * 1048576 )) $(( now - 10 )) $(( 15 * 1048576 )) | mw 0 12 0)
check "mem_watch: 15 to 12 GiB in 10 s is a 3072 MiB fall, harm 10 s ago (got '$out')" '[[ $out == "0 3072 10 3" ]]'
out=$(printf '%s 0 %d 1\n' $(( now - 200 )) $(( 20 * 1048576 )) | mw 0 12 0)
check "mem_watch: a sample older than the window is dropped (got '$out')" '[[ $out == "-1 0 999999 1" ]]'
rm -rf -- "$A"

# 12. Lane priority (HEAVY_BUILD_LANE_PRIO=1 and ~/.config/heavy-build.lanes).
# run_lp runs heavy-build like run_hb, with session, grove and registry files
# that live in the sandbox. tk prints line N of the waiter's ticket.
HBP=$(dirname "$HB")/heavy-build-prio
run_lp() {
  printf '%s\n' "${LP_CLASS:-}" > "$T/class"
  printf '#!/bin/sh\ncat %q\n' "$T/class" > "$T/ms"; chmod +x "$T/ms"
  run_hb HB_MACHINE_SESSION="$T/ms" MACHINE_SESSION_REGISTRY="$T/none.toml" \
    MACHINE_SESSION_SESSIONS_DIR="$T/sess" MACHINE_SESSION_GROVE_REPOS="$T/repos.json" \
    CLAUDE_PID= CLAUDE_AGENT_NAME= HEAVY_BUILD_AGENT= CLAUDE_CODE_CHILD_SESSION= \
    HEAVY_BUILD_SESSION= HEAVY_BUILD_SESSION_PID= "$@"
}
tk() {
  local f
  f=$(ls "$T/run/heavy-build.queue/" 2>/dev/null | grep -v '^0000' | grep -v '\.tmp$' | head -1)
  [[ -n $f ]] && sed -n "${1}p" "$T/run/heavy-build.queue/$f"
}
# wait_tk N REGEX: waits up to 6 s for ticket line N to match.
wait_tk() {
  local i
  for i in $(seq 1 30); do [[ $(tk "$1") =~ $2 ]] && return 0; sleep 0.2; done
  return 1
}
lplog() { cat "$T/state/heavy-build/shadow.log" 2>/dev/null; }
on='HEAVY_BUILD_LANE_PRIO=1'

# Missing file, flag on: priority works as today, a caller's high stays high.
setup
run_lp "$on" HEAVY_BUILD_PRIORITY=high HEAVY_BUILD_REASON=test HB_LANE_IDENT="theme - - $T/work"
wait_tk 2 '^high '; got=$(tk 2)
wait "$hbpid"
check "lanes: no file, caller high stays high (got '$got')" '[[ $got == high\ * ]]'
check "lanes: no file, no prio-change line" '! lplog | grep -q "event=prio-"'
teardown

# Empty file (only a comment): the same.
setup
printf '# nothing yet\n\n' > "$T/config/heavy-build.lanes"
run_lp "$on" HEAVY_BUILD_PRIORITY=high HEAVY_BUILD_REASON=test HB_LANE_IDENT="theme - - $T/work"
wait_tk 2 '^high '; got=$(tk 2)
wait "$hbpid"
check "lanes: empty file, caller high stays high (got '$got')" '[[ $got == high\ * ]] && ! lplog | grep -q "event=prio-"'
teardown

# Flag off: a matching rule changes nothing; the ticket still says who sent it.
setup
printf 'theme low\n' > "$T/config/heavy-build.lanes"
run_lp HB_LANE_IDENT="theme - - $T/work"
wait_tk 2 '^normal '; got=$(tk 2); l3=$(tk 3)
wait "$hbpid"
check "lanes: flag off, rule ignored (got '$got')" '[[ $got == normal\ * ]] && ! lplog | grep -q "event=prio-"'
check "lanes: flag off, line 3 still names session and agent (got '$l3')" '[[ $l3 == "session=- agent=- lane=theme owner=- dirs=$T/work via=-" ]]'
teardown

# A lane rule sets the priority, and the ticket and log say so.
setup
printf 'other high\ntheme low  # 21 of 76 jobs\n' > "$T/config/heavy-build.lanes"
printf 'HEAVY_BUILD_LANE_PRIO=1\n' > "$T/config/heavy-build.conf"
run_lp HB_LANE_IDENT="theme - - $T/work"
wait_tk 2 '^low '; got=$(tk 2); l3=$(tk 3)
wait "$hbpid"
check "lanes: theme low matches the lane tag (got '$got')" '[[ $got == low\ * ]]'
check "lanes: ticket line 3 is the ident (got '$l3')" '[[ $l3 == "session=- agent=- lane=theme owner=- dirs=$T/work via=-" ]]'
check "lanes: logged once as prio_from=normal prio_to=low with the rule" '(( $(lplog | grep -c "event=prio-change prio_from=normal prio_to=low rule=\"theme low  # 21 of 76 jobs\"") == 1 ))'
check "lanes: the waiter says its new priority" 'grep -q "heavy-build: priority low (was normal): theme low" "$T/out"'
teardown

# Session name and grove owner match too; first matching rule wins.
setup
printf 'hotfix-a high\nlane9 low\n' > "$T/config/heavy-build.lanes"
run_lp "$on" HB_LANE_IDENT="lane9 hotfix-a - $T/work"
wait_tk 2 '^high '; a=$(tk 2); wait "$hbpid"
teardown
setup
printf 'release-* high\n' > "$T/config/heavy-build.lanes"
run_lp "$on" HB_LANE_IDENT="- - release-1 $T/work"
wait_tk 2 '^high '; b=$(tk 2); wait "$hbpid"
check "lanes: grove owner matches, first rule wins (got '$a')" '[[ $a == high\ * ]]'
check "lanes: a glob matches the session name (got '$b')" '[[ $b == high\ * ]]'
teardown

# Precedence: a critical session beats a low rule and a caller's low.
setup
printf 'theme low\n' > "$T/config/heavy-build.lanes"
LP_CLASS=critical run_lp "$on" HEAVY_BUILD_PRIORITY=low HB_LANE_IDENT="theme - - $T/work"
wait_tk 2 '^critical '; got=$(tk 2)
wait "$hbpid"
check "lanes: critical session beats the rule and the caller (got '$got')" '[[ $got == critical\ * ]]'
check "lanes: logged as a change to critical" 'lplog | grep -q "event=prio-change prio_from=low prio_to=critical rule=\"critical: this session is critical"'
teardown

# A rule beats the caller's own priority.
setup
printf 'theme normal\n' > "$T/config/heavy-build.lanes"
run_lp "$on" HEAVY_BUILD_PRIORITY=low HB_LANE_IDENT="theme - - $T/work"
wait_tk 2 '^normal '; got=$(tk 2)
wait "$hbpid"
check "lanes: rule normal beats caller low (got '$got')" '[[ $got == normal\ * ]]'
teardown

# A caller's own high without a matching rule is demoted, said and logged once.
setup
printf 'other high\n' > "$T/config/heavy-build.lanes"
run_lp "$on" HEAVY_BUILD_PRIORITY=high HEAVY_BUILD_REASON=test HB_LANE_IDENT="theme - - $T/work"
wait_tk 2 '^normal '; got=$(tk 2)
wait "$hbpid"
check "lanes: self-set high without a rule runs as normal (got '$got')" '[[ $got == normal\ * ]]'
check "lanes: demotion said once" '(( $(grep -c "priority normal, not high: the manager session owns build priority" "$T/out") == 1 ))'
check "lanes: demotion logged once" '(( $(lplog | grep -c "event=prio-demoted asked=high reason=\"test\"") == 1 ))'
check "lanes: and one prio-change line" '(( $(lplog | grep -c "event=prio-change prio_from=high prio_to=normal") == 1 ))'
teardown

# A caller's high with a matching high rule stays high, with no demotion.
setup
printf 'theme high\n' > "$T/config/heavy-build.lanes"
run_lp "$on" HEAVY_BUILD_PRIORITY=high HEAVY_BUILD_REASON=test HB_LANE_IDENT="theme - - $T/work"
wait_tk 2 '^high '; got=$(tk 2)
wait "$hbpid"
check "lanes: caller high with a high rule stays high (got '$got')" '[[ $got == high\ * ]] && ! lplog | grep -q "event=prio-"'
teardown

# A pausable session stays low unless a rule says otherwise.
setup
printf 'other high\n' > "$T/config/heavy-build.lanes"
LP_CLASS=pausable run_lp "$on" HEAVY_BUILD_PRIORITY= HB_LANE_IDENT="theme - - $T/work"
wait_tk 2 '^low '; a=$(tk 2); wait "$hbpid"
teardown
setup
printf 'theme high\n' > "$T/config/heavy-build.lanes"
LP_CLASS=pausable run_lp "$on" HEAVY_BUILD_PRIORITY= HB_LANE_IDENT="theme - - $T/work"
wait_tk 2 '^high '; b=$(tk 2); wait "$hbpid"
check "lanes: pausable without a rule stays low (got '$a')" '[[ $a == low\ * ]]'
check "lanes: pausable with a high rule goes high (got '$b')" '[[ $b == high\ * ]]'
teardown

# Live re-rank: a waiting build follows set and clear, and only changes once each.
setup
printf 'other high\n' > "$T/config/heavy-build.lanes"
run_lp "$on" HEAVY_BUILD_WAIT=60 HB_LANE_IDENT="theme - - $T/work"
wait_tk 2 '^normal '; a=$(tk 2); l1a=$(tk 1)
XDG_CONFIG_HOME="$T/config" XDG_RUNTIME_DIR="$T/run" XDG_STATE_HOME="$T/state" "$HBP" set theme high "release work" > /dev/null
wait_tk 2 '^high '; b=$(tk 2); l1b=$(tk 1)
sleep 2
XDG_CONFIG_HOME="$T/config" XDG_RUNTIME_DIR="$T/run" XDG_STATE_HOME="$T/state" "$HBP" clear theme > /dev/null
wait_tk 2 '^normal '; c=$(tk 2)
sleep 2
kill "$hbpid" 2>/dev/null; wait "$hbpid" 2>/dev/null
check "re-rank: normal, then high after set, then normal after clear (got '$a' '$b' '$c')" '[[ $a == normal\ * && $b == high\ * && $c == normal\ * ]]'
check "re-rank: ticket line 1 is kept (got '$l1a' '$l1b')" '[[ -n $l1a && $l1a == "$l1b" ]]'
check "re-rank: the rest of line 2 is kept" '[[ ${a#normal } == "${b#high }" ]]'
check "re-rank: two prio-change lines, one per change" '(( $(lplog | grep -c "event=prio-change") == 2 )) && lplog | grep -q "prio_from=normal prio_to=high rule=\"theme high by=manager  # release work\"" && lplog | grep -q "prio_from=high prio_to=normal rule=\"none: lane priority is off or the lanes file has no rules\""'
teardown

# Bad lines are skipped with a warning; the good line after them still works.
setup
printf 'theme critical\njust-one-word\na b c\n/x/* low\n' > "$T/config/heavy-build.lanes"
run_lp "$on" HB_LANE_IDENT="theme - - /x/y"
wait_tk 2 '^low '; got=$(tk 2)
wait "$hbpid"
check "lanes: bad lines skipped, the path rule after them applies (got '$got')" '[[ $got == low\ * ]]'
check "lanes: one warning per bad line (3)" '(( $(grep -c "warning: .*heavy-build.lanes line [123] skipped" "$T/out") == 3 ))'
teardown

# The real ident: grove lane tag, grove owner and path globs, read from the sandbox.
setup
mkdir -p "$T/grove/.grove" "$T/sess"
printf '{"repos": {"r": {"work_dir": "%s"}}}\n' "$T/grove" > "$T/repos.json"
printf '{"projects": {"mylane": {"path": "%s", "owner": {"session_name": "ownr"}}}}\n' "$T/work" > "$T/grove/.grove/registry.json"
printf 'mylane low\n' > "$T/config/heavy-build.lanes"
run_lp "$on"
wait_tk 2 '^low '; got=$(tk 2); l3=$(tk 3)
wait "$hbpid"
check "ident: grove lane tag found from the directory (got '$got')" '[[ $got == low\ * ]]'
check "ident: line 3 has lane, owner and the directory (got '$l3')" '[[ $l3 == "session=- agent=- lane=mylane owner=ownr dirs=$T/work"* ]]'
printf '%s* high\n' "${T%/*}/hb-test" > "$T/config/heavy-build.lanes"
run_lp "$on"
wait_tk 2 '^high '; got=$(tk 2)
wait "$hbpid"
check "ident: a path glob matches the directory (got '$got')" '[[ $got == high\ * ]]'
printf '%s high\n' "$T" > "$T/config/heavy-build.lanes"
run_lp "$on"
wait_tk 2 '^high '; got=$(tk 2)
wait "$hbpid"
check "ident: a plain path matches directories under it (got '$got')" '[[ $got == high\ * ]]'
teardown

# The real ident: the Claude session is found among heavy-build's ancestors.
setup
mkdir -p "$T/sess"
printf '{"pid": %s, "name": "hotfix-b"}\n' "$$" > "$T/sess/$$.json"
printf 'hotfix-* high\n' > "$T/config/heavy-build.lanes"
run_lp "$on"
wait_tk 2 '^high '; got=$(tk 2); l3=$(tk 3)
wait "$hbpid"
check "ident: session name from an ancestor's session file (got '$got' '$l3')" '[[ $got == high\ * && $l3 == "session=hotfix-b agent=- lane=- "* && $l3 == *" via=parent" ]]'
teardown

# CLAUDE_PID names the session when no ancestor has a session file.
setup
mkdir -p "$T/sess"
sleep 300 & sp=$!
printf '{"pid": %s, "name": "via-env"}\n' "$sp" > "$T/sess/$sp.json"
run_lp CLAUDE_PID="$sp" CLAUDE_AGENT_NAME="hb lane"
wait_tk 3 'session=via-env'; l3=$(tk 3)
wait "$hbpid"; kill "$sp" 2>/dev/null; wait "$sp" 2>/dev/null
check "ident: CLAUDE_PID gives the session, CLAUDE_AGENT_NAME the agent (got '$l3')" '[[ $l3 == "session=via-env agent=hb_lane "* && $l3 == *" via=claude-pid" ]]'
teardown

# The SessionStart hook's variables: HEAVY_BUILD_SESSION_PID wins when it is
# a live session; the name counts only when no pid is given; a pid that is
# gone falls through to the parent processes, never to the name.
setup
mkdir -p "$T/sess"
sleep 300 & sp=$!
printf '{"pid": %s, "name": "sess-a"}\n' "$sp" > "$T/sess/$sp.json"
printf '{"pid": %s, "name": "parent-sess"}\n' "$$" > "$T/sess/$$.json"
run_lp HEAVY_BUILD_SESSION=sess-a
wait_tk 3 'session=sess-a'; a=$(tk 3); wait "$hbpid"
run_lp HEAVY_BUILD_SESSION=sess-a-old-name HEAVY_BUILD_SESSION_PID="$sp"
wait_tk 3 'session=sess-a'; b=$(tk 3); wait "$hbpid"
run_lp HEAVY_BUILD_SESSION=gone HEAVY_BUILD_SESSION_PID=1
wait_tk 3 'session=parent-sess'; c=$(tk 3); wait "$hbpid"
run_lp HEAVY_BUILD_SESSION=sess-a HEAVY_BUILD_SESSION_PID=1
wait_tk 3 'session=parent-sess'; d=$(tk 3); wait "$hbpid"
run_lp HEAVY_BUILD_SESSION=parent-sess HEAVY_BUILD_SESSION_PID="$sp"
wait_tk 3 'session=sess-a'; e=$(tk 3); wait "$hbpid"
kill "$sp" 2>/dev/null; wait "$sp" 2>/dev/null
check "ident: HEAVY_BUILD_SESSION alone names a live session, beats the parent (got '$a')" '[[ $a == "session=sess-a "* && $a == *" via=env-name" ]]'
check "ident: with a gone pid, a name another live session has is not used (got '$d')" '[[ $d == "session=parent-sess "* && $d == *" via=parent" ]]'
check "ident: a live pid beats a name that another live session has (got '$e')" '[[ $e == "session=sess-a "* && $e == *" via=env-pid" ]]'
check "ident: a renamed session is found by HEAVY_BUILD_SESSION_PID (got '$b')" '[[ $b == "session=sess-a "* && $b == *" via=env-pid" ]]'
check "ident: a name and pid with no live session fall through to the parent (got '$c')" '[[ $c == "session=parent-sess "* && $c == *" via=parent" ]]'
teardown

# Who submitted: every log line and history column 14 name session and agent.
setup2
hbe CLAUDE_AGENT_NAME=lp-agent HB_LANE_IDENT="- - sess1 $T/work" -- true
wait "$hbpid"; rc=$?
check "owner: history column 14 is session/agent (rc $rc)" '(( rc == 0 )) && awk -F"\t" '\''$14 == "sess1/lp-agent"'\'' "$T/state/heavy-build/history.tsv" | grep -q .'
check "owner: every log line ends with session= agent=" 'n=$(cat "$T"/state/heavy-build/*.log | wc -l); (( n > 0 )) && (( $(cat "$T"/state/heavy-build/*.log | grep -c " session=sess1 agent=lp-agent$") == n ))'
check "owner: decision lines keep job= then decision= (buildqueue-fetch reads them so)" 'grep -qE "^[^ ]+ mode=[^ ]+ job=[^ ]+ decision=" "$T"/state/heavy-build/*.log'
teardown2
setup2
hbe CLAUDE_AGENT_NAME= HEAVY_BUILD_AGENT= CLAUDE_CODE_CHILD_SESSION=1 HB_LANE_IDENT="- - - $T/work" -- true
wait "$hbpid"
a=$(awk -F"\t" '{print $14}' "$T/state/heavy-build/history.tsv")
teardown2
setup2
hbe CLAUDE_AGENT_NAME= HEAVY_BUILD_AGENT= CLAUDE_CODE_CHILD_SESSION= HB_LANE_IDENT="- - - $T/work" -- true
wait "$hbpid"
b=$(awk -F"\t" '{print $14}' "$T/state/heavy-build/history.tsv")
check "owner: an unnamed subagent is -/subagent, none is -/- (got '$a' '$b')" '[[ $a == "-/subagent" && $b == "-/-" ]]'
teardown2

# A rule may name its setter with by=; heavy-build ignores it, a bad by= is skipped.
setup
printf 'theme low by=oystein  # panel\nwork high by=bad/name\n' > "$T/config/heavy-build.lanes"
run_lp "$on" HB_LANE_IDENT="theme - - $T/work"
wait_tk 2 '^low '; got=$(tk 2)
wait "$hbpid"
check "lanes: by= is allowed after the priority (got '$got')" '[[ $got == low\ * ]] && lplog | grep -q "rule=\"theme low by=oystein  # panel\""'
check "lanes: a bad by= skips the line with a warning" 'grep -q "heavy-build.lanes line 2 skipped" "$T/out"'
teardown

# Estimate refresh (HEAVY_BUILD_EST_REFRESH=1): a waiter follows a conf change
# and, every HEAVY_BUILD_EST_REFRESH_SECS, new history. The key's two runs
# peaked at 16 GiB with 2 GiB non-file, so EST_NONFILE 0 -> 1 lowers it.
est_hist() {  # PEAK_GIB NONFILE_GIB: one history line for this test's key
  local h
  h=$(printf '%s\0' "$T/work" true | md5sum | cut -c1-8)
  mkdir -p "$T/state/heavy-build"
  printf '%s\tother\t%s\t30\t10\t%s\t0\tok\tNA\tNA\t-\t-\t%s\n' "$EPOCHSECONDS" "$h" $(( $1 * 1073741824 )) $(( $2 * 1073741824 )) >> "$T/state/heavy-build/history.tsv"
}
mem2() { tk 2 | awk '{print $2}'; }
setup
est_hist 16 2; est_hist 16 2
printf 'HEAVY_BUILD_EST_REFRESH=1\nHEAVY_BUILD_EST_NONFILE=0\n' > "$T/config/heavy-build.conf"
run_lp HEAVY_BUILD_WAIT=60
wait_tk 2 '^normal '; a=$(mem2)
printf 'HEAVY_BUILD_EST_REFRESH=1\nHEAVY_BUILD_EST_NONFILE=1\n' > "$T/config/heavy-build.conf"
for _ in $(seq 1 30); do [[ $(mem2) != "$a" ]] && break; sleep 0.2; done
b=$(mem2); l1=$(tk 1)
sleep 2
kill "$hbpid" 2>/dev/null; wait "$hbpid" 2>/dev/null
check "est refresh: a conf change re-estimates a waiting build (got '$a' then '$b')" '[[ $a == 16.0 ]] && awk -v b="$b" "BEGIN { exit !(b + 0 > 0 && b + 0 < 16) }"'
check "est refresh: logged once with est_from and est_to" '(( $(lplog | grep -c "event=est-change est_from=16.0G/") == 1 )) && lplog | grep -q "est_to=${b}G/"'
check "est refresh: ticket line 1 kept (got '$l1')" '[[ $l1 =~ ^[0-9]+\ [0-9]+$ ]]'
teardown
setup
est_hist 16 2; est_hist 16 2
printf 'HEAVY_BUILD_EST_REFRESH=1\nHEAVY_BUILD_EST_REFRESH_SECS=2\n' > "$T/config/heavy-build.conf"
run_lp HEAVY_BUILD_WAIT=60
wait_tk 2 '^normal '; a=$(mem2)
est_hist 16 12
for _ in $(seq 1 30); do [[ $(mem2) != "$a" ]] && break; sleep 0.2; done
b=$(mem2)
kill "$hbpid" 2>/dev/null; wait "$hbpid" 2>/dev/null
check "est refresh: new history is picked up on the timer (got '$a' then '$b')" '[[ $a != "$b" ]] && awk -v a="$a" -v b="$b" "BEGIN { exit !(b + 0 > a + 0) }"'
teardown
setup
est_hist 16 2; est_hist 16 2
printf 'HEAVY_BUILD_EST_NONFILE=0\n' > "$T/config/heavy-build.conf"
run_lp HEAVY_BUILD_WAIT=60
wait_tk 2 '^normal '; a=$(mem2)
printf 'HEAVY_BUILD_EST_NONFILE=1\n' > "$T/config/heavy-build.conf"
sleep 3; b=$(mem2)
kill "$hbpid" 2>/dev/null; wait "$hbpid" 2>/dev/null
check "est refresh: off by default, the estimate stays (got '$a' then '$b')" '[[ $a == 16.0 && $b == 16.0 ]] && ! lplog | grep -q "event=est-change"'
teardown

# heavy-build-prio: set replaces in place, clear removes, writes atomically.
setup
hp() { XDG_CONFIG_HOME="$T/config" XDG_RUNTIME_DIR="$T/run" XDG_STATE_HOME="$T/state" "$HBP" "$@" > "$T/hp.out" 2>&1; }
hp set theme low "21 of 76"; r1=$?
hp set '/var/tmp/claude/cass*' low; hp set theme normal; r2=$?
check "prio set: replaces the theme rule in place, by=manager by default (rc $r1 $r2)" '(( r1 == 0 && r2 == 0 )) && [[ $(cat "$T/config/heavy-build.lanes") == $'\''theme normal by=manager\n/var/tmp/claude/cass* low by=manager'\'' ]]'
hp set --by oystein theme high "from the panel"; r=$?
check "prio set: --by oystein overwrites the manager's rule (rc $r)" '(( r == 0 )) && grep -qx "theme high by=oystein  # from the panel" "$T/config/heavy-build.lanes"'
check "prio set: lanes.log has time, old, new and by" 'grep -qE "^[0-9T:+-]+ action=set match=theme old=\"theme normal by=manager\" new=\"theme high by=oystein  # from the panel\" by=oystein$" "$T/state/heavy-build/lanes.log"'
hp set theme normal; r=$?
hp set --by "bad name" theme low; rb=$?
check "prio set: a --by with a space is refused (rc $rb)" '(( r == 0 && rb == 2 ))'
hp set x critical; r=$?
check "prio set: critical is refused with exit 2 (rc $r)" '(( r == 2 )) && ! grep -q "^x " "$T/config/heavy-build.lanes"'
hp set "two words" low; r=$?
check "prio set: a match with a space is refused (rc $r)" '(( r == 2 ))'
printf '1 2\nnormal 1 1 1 tree:/var/tmp/claude/cass-stream/wt -\n' > "$T/run/heavy-build.queue/1792997206715365108-9-aa"
printf '1 2\nnormal 1 1 1 - -\nsession=s1 agent=a1 lane=theme owner=- dirs=/w via=env-pid\n' > "$T/run/heavy-build.queue/1792997206715365109-9-ab"
hp list; r=$?
check "prio list: counts waiting jobs per rule and shows by= (rc $r)" '(( r == 0 )) && grep -q "theme  *normal by=manager  *waiting=1" "$T/hp.out" && grep -q "cass\*  *low  *by=manager  *waiting=1" "$T/hp.out"'
check "prio list: a ticket from an older heavy-build is matched on its key directories" 'grep -q "1792997206715365108-9-aa normal rule:2 session=? agent=? lane=? owner=? dirs=/var/tmp/claude/cass-stream/wt" "$T/hp.out"'
check "prio list: shows who submitted each job" 'grep -q "1792997206715365109-9-ab normal rule:1 session=s1 agent=a1 lane=theme" "$T/hp.out"'
check "prio list: shows how the session was found" 'grep -q "1792997206715365109-9-ab .* via=env-pid$" "$T/hp.out" && grep -q "1792997206715365108-9-aa .* via=?$" "$T/hp.out"'
hp clear --by oystein theme; r1=$?; hp clear theme; r2=$?
check "prio clear: logged with by" 'grep -q "action=clear match=theme old=\"theme normal by=manager\" new=\"-\" by=oystein$" "$T/state/heavy-build/lanes.log"'
check "prio clear: removes the rule, then exit 1 when there is none (rc $r1 $r2)" '(( r1 == 0 && r2 == 1 )) && ! grep -q "^theme" "$T/config/heavy-build.lanes"'
hp clear '/var/tmp/claude/cass*'
check "prio clear: the last rule leaves an empty file and no temp file" '[[ -e $T/config/heavy-build.lanes && ! -s $T/config/heavy-build.lanes ]] && ! ls "$T/config" | grep -q "\.tmp"'
teardown

# 13. Re-exec (HEAVY_BUILD_REEXEC=1): a waiter whose script is replaced goes on
# with the new code, as the same process, with the same ticket and arguments.
# The waiter runs a copy at $T/hb, which the test replaces with mv as an
# install does. setup2 stubs systemd-run, so once the blocker is gone the
# build really runs here.
re_blocker() {
  sleep 600 & blocker=$!
  local st
  st=$(awk '{sub(/.*\) /, ""); split($0, a, " "); print a[20]}' "/proc/$blocker/stat")
  printf '%s %s\nnormal 1 1 1 -\n' "$blocker" "$st" > "$T/run/heavy-build.queue/0000000000000000001-$blocker-blocker"
}
re_install() {  # replaces $T/hb by a new file (new inode), from $1 or the candidate
  cp -- "${1:-$HBREAL}" "$T/hb.new" && chmod +x "$T/hb.new" && mv -f -- "$T/hb.new" "$T/hb"
}
re_tk() { ls "$T/run/heavy-build.queue/" | grep -v '^0000' | grep -v '\.tmp$'; }
re_wait_log() {  # PATTERN [N]: waits up to 8 s for N (default 1) log lines matching
  local i
  for i in $(seq 1 40); do (( $(cat "$T/state/heavy-build/shadow.log" 2>/dev/null | grep -c -- "$1") >= ${2:-1} )) && return 0; sleep 0.2; done
  return 1
}
HBREAL=$HB

setup2
re_blocker
printf 'HEAVY_BUILD_REEXEC=1\n' > "$T/config/heavy-build.conf"
re_install
# A later waiter (a live process) behind ours, to show the place is kept.
HB=$T/hb hbe -- bash -c 'printf "%s|" "$@" > "$0"; env > "$0.env"' "$T/ran" "a b" c
for _ in $(seq 1 40); do [[ -n $(re_tk) ]] && break; sleep 0.2; done
sleep 120 & later=$!
lst=$(awk '{sub(/.*\) /, ""); split($0, a, " "); print a[20]}' "/proc/$later/stat")
printf '%s %s\nnormal 1 1 1 -\n' "$later" "$lst" > "$T/run/heavy-build.queue/9999999999999999999-$later-later"
re_wait_log 'decision=wait'
t1=$(re_tk | grep -v later); l1=$(head -1 "$T/run/heavy-build.queue/$t1")
re_install
re_wait_log 'event=reexec from='; r=$?
re_wait_log 'event=reexec-adopted'
sleep 2
t2=$(re_tk | grep -v later); l2=$(head -1 "$T/run/heavy-build.queue/$t2" 2>/dev/null)
alive=0; kill -0 "$hbpid" 2>/dev/null && alive=1
check "reexec: logged once when the script is replaced (r $r)" '(( r == 0 )) && (( $(grep -c "event=reexec from=" "$T/state/heavy-build/shadow.log") == 1 ))'
check "reexec: same process, same ticket file and line 1 (got '$t1' '$t2')" '(( alive )) && [[ -n $t1 && $t1 == "$t2" && $l1 == "$l2" ]] && [[ $l1 == "$hbpid "* ]]'
check "reexec: the new code adopted the ticket, still position 2 of 3" 'grep -q "event=reexec-adopted ticket=$t1" "$T/state/heavy-build/shadow.log" && tail -n 3 "$T/out" | grep -q "position 2 of 3"'
check "reexec: only one ticket for this build" '(( $(re_tk | grep -c -- "-$hbpid-") == 1 ))'
kill "$blocker"; wait "$blocker" 2>/dev/null
wait "$hbpid"; rc=$?
kill "$later" 2>/dev/null; wait "$later" 2>/dev/null
check "reexec: the build then runs with its original arguments (rc $rc, got '$(cat "$T/ran" 2>/dev/null)')" '(( rc == 0 )) && [[ $(cat "$T/ran") == "a b|c|" ]]'
check "reexec: the build does not see HB_ADOPT_TICKET" '[[ -s $T/ran.env ]] && ! grep -q "HB_ADOPT\|HB_REEXEC_IDS" "$T/ran.env"'
teardown2

# A broken new script: skipped once, the waiter stays; a good one after it re-execs.
setup2
re_blocker
printf 'HEAVY_BUILD_REEXEC=1\n' > "$T/config/heavy-build.conf"
re_install
HB=$T/hb hbe -- true
re_wait_log 'decision=wait'
printf '#!/usr/bin/env bash\n{ if then\n' > "$T/broken"
re_install "$T/broken"
re_wait_log 'event=reexec-skip'
sleep 3
alive=0; kill -0 "$hbpid" 2>/dev/null && alive=1
check "reexec: a script that fails bash -n is skipped once and the waiter stays" '(( alive )) && (( $(grep -c "event=reexec-skip.*fails bash -n" "$T/state/heavy-build/shadow.log") == 1 )) && ! grep -q "event=reexec from=" "$T/state/heavy-build/shadow.log"'
printf '#!/usr/bin/env bash\n{ echo old; }\n' > "$T/noadopt"
re_install "$T/noadopt"
re_wait_log 'cannot take back a ticket'; r=$?
check "reexec: a script without HB_ADOPT_TICKET is skipped (r $r)" '(( r == 0 )) && kill -0 "$hbpid" 2>/dev/null'
re_install
re_wait_log 'event=reexec-adopted'; r=$?
check "reexec: a good script after them still re-execs (r $r)" '(( r == 0 )) && (( $(grep -c "event=reexec from=" "$T/state/heavy-build/shadow.log") == 1 ))'
kill "$hbpid" 2>/dev/null; wait "$hbpid" 2>/dev/null
kill "$blocker"; wait "$blocker" 2>/dev/null
check "reexec: TERM after a re-exec still removes the ticket" '[[ -z $(re_tk) ]]'
teardown2

# Switch off (the default): a replaced script changes nothing.
setup2
re_blocker
re_install
HB=$T/hb hbe -- true
re_wait_log 'decision=wait'
re_install
sleep 3
check "reexec: off by default, no re-exec" '! grep -q "event=reexec" "$T/state/heavy-build/shadow.log" && kill -0 "$hbpid" 2>/dev/null'
kill "$hbpid" 2>/dev/null; wait "$hbpid" 2>/dev/null
kill "$blocker"; wait "$blocker" 2>/dev/null
teardown2
HB=$HBREAL

# 13b. Re-exec review fixes (Astra, 2026-10-26).
# A slow submit: machine-session takes 3 s when HEAVY_BUILD_PRIORITY is unset.
re_slow() { printf '#!/bin/sh\nsleep 3\necho normal\n' > "$T/slowms"; chmod +x "$T/slowms"; }

# Fix 1: the new file is not executable. The waiter runs it with bash, so it
# re-execs and stays.
setup2
re_blocker
printf 'HEAVY_BUILD_REEXEC=1\n' > "$T/config/heavy-build.conf"
re_install
HB=$T/hb hbe -- true
re_wait_log 'decision=wait'
cp -- "$HBREAL" "$T/hb.new" && chmod 644 "$T/hb.new" && mv -f -- "$T/hb.new" "$T/hb"
re_wait_log 'event=reexec-adopted'; r=$?
sleep 2
check "reexec fix 1: a new script without +x still re-execs, the waiter stays (r $r)" '(( r == 0 )) && kill -0 "$hbpid" 2>/dev/null && [[ -n $(re_tk) ]]'
# The script gone: no re-exec, the waiter stays.
mv -f -- "$T/hb" "$T/hb.gone"
sleep 3
check "reexec fix 1: a removed script is not run, the waiter stays" 'kill -0 "$hbpid" 2>/dev/null && [[ -n $(re_tk) ]] && (( $(grep -c "event=reexec from=" "$T/state/heavy-build/shadow.log") == 1 ))'
kill "$hbpid" 2>/dev/null; wait "$hbpid" 2>/dev/null
kill "$blocker"; wait "$blocker" 2>/dev/null
teardown2

# Fix 1: started by a bare name (bash hb, from its own directory).
setup2
re_blocker
printf 'HEAVY_BUILD_REEXEC=1\n' > "$T/config/heavy-build.conf"
cp -- "$HBREAL" "$T/work/hb"
HB=bash hbe -- hb true
re_wait_log 'decision=wait'
cp -- "$HBREAL" "$T/work/hb.new" && mv -f -- "$T/work/hb.new" "$T/work/hb"
re_wait_log 'event=reexec-adopted'; r=$?
sleep 1
check "reexec fix 1: a waiter started as 'bash hb' re-execs by its absolute path (r $r)" '(( r == 0 )) && kill -0 "$hbpid" 2>/dev/null && [[ -n $(re_tk) ]]'
kill "$hbpid" 2>/dev/null; wait "$hbpid" 2>/dev/null
kill "$blocker"; wait "$blocker" 2>/dev/null
teardown2

# Fix 2: a re-exec'd process (simulated: a shell writes a ticket naming
# itself, then execs heavy-build with HB_ADOPT_TICKET) that gets TERM during
# its slow setup removes the ticket.
re_adopted() {  # starts it in the background; sets hbpid and adtk
  adtk=$T/run/heavy-build.queue/1700000000000000000-ad-$1
  (cd "$T/work" && exec env -u HEAVY_BUILD_MODE HBT="$T" PATH="$T/bin:$PATH" \
    XDG_RUNTIME_DIR="$T/run" XDG_STATE_HOME="$T/state" XDG_CONFIG_HOME="$T/config" \
    HB_CGROUP="$T/cg" HB_PROC="$T/proc" HB_MACHINE_SESSION="$T/slowms" HEAVY_BUILD_PRIORITY= \
    HEAVY_BUILD_WAIT=100 HEAVY_BUILD_POLL=1 HEAVY_BUILD_FORCE=1 HEAVY_BUILD_KEY=none \
    bash -c 'st=$(awk '\''{sub(/.*\) /, ""); split($0, a, " "); print a[20]}'\'' /proc/$$/stat)
      printf "%s %s\nnormal 1 1 1 - -\n" $$ "$st" > "$0"
      exec env HB_ADOPT_TICKET="$0" HB_ADOPT_STATE="$(( EPOCHSECONDS - 50 )) 7 - -" "$1" true' "$adtk" "$HBREAL") > "$T/out" 2>&1 &
  hbpid=$!
}
setup2
re_blocker; re_slow
re_adopted x
sleep 1
had=0; [[ -e $adtk ]] && had=1
kill -TERM "$hbpid"; wait "$hbpid"; rc=$?
check "reexec fix 2: TERM during setup after a re-exec removes the inherited ticket (rc $rc, had $had)" '(( had == 1 && rc == 143 )) && [[ ! -e $adtk ]]'
kill "$blocker"; wait "$blocker" 2>/dev/null
teardown2

# Fix 2: the rerun guard does not refuse an adopted waiter; it does refuse a new one.
setup2
re_blocker
h=$(printf '%s\0' "$T/work" true | md5sum | cut -c1-8)
mkdir -p "$T/state/heavy-build"
for i in 1 2; do printf '%s\tother\t%s\t30\t10\t1000\t1\tfail\tNA\tNA\t-\t-\tNA\n' $(( EPOCHSECONDS - 60 )) "$h" >> "$T/state/heavy-build/history.tsv"; done
printf '#!/bin/sh\necho normal\n' > "$T/slowms"; chmod +x "$T/slowms"
re_adopted y
sleep 4
alive=0; kill -0 "$hbpid" 2>/dev/null && alive=1
check "reexec fix 2: an adopted waiter skips the rerun guard and keeps waiting" '(( alive )) && [[ -e $adtk ]] && ! grep -q "rerun-refuse" "$T/state/heavy-build/shadow.log" && grep -q "event=reexec-adopted ticket=${adtk##*/}" "$T/state/heavy-build/shadow.log"'
kill "$hbpid" 2>/dev/null; wait "$hbpid" 2>/dev/null
check "reexec fix 2: its clock came along (queued about 50 s ago)" 'grep -qE "event=reexec-adopted .*queued_s=(5[0-9]|6[0-9]) " "$T/state/heavy-build/shadow.log"'
hbe HEAVY_BUILD_PRIORITY=normal -- true
wait "$hbpid"; rc=$?
check "reexec fix 2: the same command, newly queued, is refused with 76 (rc $rc)" '(( rc == 76 ))'
kill "$blocker"; wait "$blocker" 2>/dev/null
teardown2

# Fix 3: an install during the slow setup still counts as a change.
setup2
re_blocker; re_slow
printf 'HEAVY_BUILD_REEXEC=1\n' > "$T/config/heavy-build.conf"
re_install
HB=$T/hb hbe HB_MACHINE_SESSION="$T/slowms" HEAVY_BUILD_PRIORITY= -- true
sleep 1
re_install
re_wait_log 'event=reexec-adopted'; r=$?
check "reexec fix 3: a script replaced during setup is picked up in the wait loop (r $r)" '(( r == 0 )) && kill -0 "$hbpid" 2>/dev/null'
kill "$hbpid" 2>/dev/null; wait "$hbpid" 2>/dev/null
kill "$blocker"; wait "$blocker" 2>/dev/null
teardown2
HB=$HBREAL

# --help: no chained build in an example, no background-shell advice.
help=$("$HB" --help 2>&1)
check "help: no cargo build && cargo test example" '! grep -q "heavy-build bash -c .*cargo build && cargo test" <<< "$help"'
check "help: no advice to run in the background" '! grep -q "run it in the$" <<< "$help" && ! grep -qi "run it in the background" <<< "$help"'
check "help: suggests a systemd user unit for long builds" 'grep -q "systemd-run --user --unit=<name> --collect --same-dir heavy-build <cmd>" <<< "$help"'

exit "$fail"
