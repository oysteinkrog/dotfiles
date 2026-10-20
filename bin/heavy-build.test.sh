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
      -v agesecs=3600 -v ageslots=1 -v cf="$1" -v cfslots="$2" -v cfreserve="$3" "$ADMIT_AWK" \
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

exit "$fail"
