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
check "wine: job prefix without a wineserver is an orphan (got '$out')" '[[ $out == "$W/pfxB " ]]'
rm -f "$W/proc/201/cwd"
out=$(wo -)
check "wine: own WINEPREFIX without a wineserver is an orphan (got '$out')" '[[ $out == "$W/pfxA ?1 " ]]'
rm -rf -- "$W"

# 6. Memory estimates. class_table and estimate() are taken from heavy-build
# and run against a fake history.tsv.
E=$(mktemp -d "${TMPDIR:-/var/tmp}/hb-test.XXXXXX")
G=1073741824
row() {  # class key peak_gib exit reason [cap_gib]
  local cap=
  [[ -n ${6:-} ]] && cap=$'\t'$(( $6 * G ))
  printf '1\t%s\t%s\t10\t20\t%s\t%s\t%s%s\n' "$1" "$2" "$(( $3 * G ))" "$4" "$5" "$cap" >> "$E/hist"
}
est() {  # key class ; prints "mem source"
  (
    HIST=$E/hist
    eval "$(sed -n '/^class_table()/,/^}/p;/^EST_MEM_MAX_GIB=/p;/^estimate()/,/^}/p' "$HB")"
    estimate "$1" "$2" | awk '{print $1, $4}'
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
rm -rf -- "$E"

# 7. Classes for Wine test runs. run-tests.sh builds nothing when every
# project it is given ends in .dll.
cls() {
  (
    eval "$(sed -n '/^wine_tests_prebuilt()/,/^}/p;/^classify()/,/^}/p' "$HB")"
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
  "dotnet-build|dotnet build Foo.sln" ; do
  want=${c%%|*} cmd=${c#*|}
  # shellcheck disable=SC2086
  out=$(cls $cmd)
  check "classify: '$cmd' is $want (got '$out')" '[[ $out == "$want" ]]'
done
rm -rf -- "$T"

exit "$fail"
