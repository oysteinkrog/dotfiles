#!/usr/bin/env bash
# Tests for machine-monitor. Each test runs in a subshell with a fake /proc,
# a fake claude.slice cgroup dir, its own state dir and stubbed commands.
# Run: bash ~/.dotfiles/bin/machine-monitor.test.sh
set -uo pipefail
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
SCRIPT=$HERE/machine-monitor
mkdir -p /var/tmp/claude; ROOT=$(mktemp -d /var/tmp/claude/machine-monitor-test.XXXXXX)
trap 'rm -rf -- "$ROOT"' EXIT
pass=0 fail=0

setup() {
  T=$ROOT/$1; mkdir -p "$T/proc/pressure" "$T/cg" "$T/state"
  export MM_PROC=$T/proc MM_CGROUP=$T/cg MM_STATE=$T/state MM_NOTIFY=0 MM_LIB=1
  export MM_RECLAIMABLE=$T/reclaimable
  # shellcheck source=machine-monitor
  source "$SCRIPT" > /dev/null
  # Stubs: no real system calls.
  mm_journal() { :; }
  mm_user_show() { :; }
  mm_user_active() { echo active; }
  mm_system_active() { echo active; }
  mm_user_failed() { :; }
  mm_system_failed() { :; }
  mm_sudo_slab_mb() { echo "SUDO CALLED" >> "$T/sudo"; echo 5; }
}
events() { cat "$MM_EVENTS" 2>/dev/null; }
nevents() { events | grep -c -- "${1:-.}"; }
meminfo() { printf 'SwapTotal: %d kB\nSwapFree: %d kB\nSUnreclaim: %d kB\n' "$1" "$2" "${3:-0}" > "$MM_PROC/meminfo"; }
mkproc() { # mkproc PID COMM PPID CGROUP ARG... (environ from MKPROC_ENV)
  local d=$MM_PROC/$1; mkdir -p "$d"
  echo "$2" > "$d/comm"
  echo "$1 ($2) S $3 0 0" > "$d/stat"
  echo "0::$4" > "$d/cgroup"
  shift 4; printf '%s\0' "$@" > "$d/cmdline"
  printf '%s\0' ${MKPROC_ENV:-HOME=/x} > "$d/environ"
}

# Run one test in a subshell; on failure show its events.log.
t() {
  if ( "$1" > "$ROOT/$1.out" || { sed 's/^/     | /' "$MM_EVENTS" "$ROOT/$1.out" 2>/dev/null; exit 1; } ); then
    pass=$((pass + 1)); echo "ok   $1"
  else
    fail=$((fail + 1)); echo "FAIL $1"
  fi
}

# ---- band logic ----
test_band_up_hysteresis() {
  setup band_up
  local seq=(10 76 80 70 86 84 78 76 60 76) out=()
  for v in "${seq[@]}"; do band_up k "$v" "75 85" 8; out+=("$BAND:$BAND_CHANGE"); done
  # 76 enters 75; 70 stays (not below 67); 86 enters 85; 84 and 78 stay (not below 77);
  # 76 drops to 75; 60 drops to 0; 76 enters 75 again.
  [[ "${out[*]}" == "0:none 75:up 75:none 75:none 85:up 85:none 85:none 75:down 0:down 75:up" ]]
}
test_band_down_disk() {
  setup band_down
  local seq=(250 190 180 149 152 156 90 59 70) out=()
  for v in "${seq[@]}"; do band_down k "$v" "200 150 100 75 60" 5; out+=("$BAND:$BAND_CHANGE"); done
  [[ "${out[*]}" == "0:none 200:up 200:none 150:up 150:none 200:down 100:up 60:up 75:down" ]] || { echo "${out[*]}"; return 1; }
}
test_level_for() { setup lvl; [[ $(level_for 75 "75 85") == warn && $(level_for 85 "75 85") == crit ]]; }
test_state_survives_restart() {
  setup restart; band_up k 80 "75 85" 8
  source "$SCRIPT" > /dev/null; band_up k 80 "75 85" 8
  [[ $BAND_CHANGE == none && $BAND == 75 ]]
}

# ---- swap, slab, psi, disk, btrfs ----
test_swap_once_per_band() {
  setup swap
  meminfo 100 20; check_swap; check_swap        # 80%: one warn
  meminfo 100 10; check_swap                    # 90%: one crit
  meminfo 100 50; check_swap                    # 50%: back
  [[ $(nevents 'warn SWAP') == 1 && $(nevents 'crit SWAP') == 1 && $(nevents 'info SWAP') == 1 ]]
}
test_sunreclaim_steps() {
  setup sunr
  meminfo 1 1 $((5 * 1048576)); check_sunreclaim; check_sunreclaim
  meminfo 1 1 $((9 * 1048576)); check_sunreclaim
  [[ $(nevents SUNRECLAIM) == 2 ]]
}
psi() { printf 'some avg10=1.00 avg60=%s avg300=%s total=1\nfull avg10=0 avg60=0 avg300=0 total=0\n' "$2" "$3" > "$MM_PROC/pressure/$1"; }
cpu() { check_psi cpu PSI_CPU "80 90" "300 120" 70 15; }
test_psi_cpu_short_peaks_quiet() {
  setup psi_peaks
  # 85% for 4.5 min, a dip, 85% again for 4.5 min: never 5 min straight.
  local t
  for t in 0 30 60 90 120 150 180 210 240 270; do MM_NOW=$t; psi cpu 85.10 40.00; cpu; done
  MM_NOW=300; psi cpu 50.00 40.00; cpu
  for t in 330 360 390 420 450 480 510 540 570 600; do MM_NOW=$t; psi cpu 85.10 40.00; cpu; done
  [[ $(nevents PSI_CPU) == 0 && $PSI_CPU == 85 ]]
}
test_psi_cpu_sustained_warn_then_crit() {
  setup psi_sust
  local t
  for t in 0 60 120 180 240 300 330; do MM_NOW=$t; psi cpu 82.00 50.00; cpu; done   # warn at 300
  for t in 360 420 480; do MM_NOW=$t; psi cpu 93.00 60.00; cpu; done                # crit at 480
  MM_NOW=510; psi cpu 70.00 60.00; cpu                                              # 70 >= 90-15? no: drops
  [[ $(nevents 'warn PSI_CPU cpu pressure some avg60 82%') == 1 && $(nevents 'crit PSI_CPU cpu pressure some avg60 93%') == 1 \
     && $(grep -n 'warn PSI_CPU' "$MM_EVENTS" | cut -d: -f1) == 1 && $(nevents 'info PSI_CPU') == 1 && $(state_get psi_cpu) == 0 ]]
}
test_psi_cpu_avg300_warns_at_once() {
  setup psi_300
  MM_NOW=0; psi cpu 75.00 71.00; cpu; MM_NOW=30; cpu
  [[ $(nevents 'warn PSI_CPU') == 1 && $(state_get psi_cpu) == 80 ]]
}
test_psi_cpu_hysteresis() {
  setup psi_hyst
  MM_NOW=0; psi cpu 75.00 71.00; cpu                    # warn via avg300
  MM_NOW=30; psi cpu 66.00 60.00; cpu                   # 66 >= 80-15: stays
  MM_NOW=60; psi cpu 64.00 60.00; cpu                   # 64 < 65: back
  [[ $(nevents 'warn PSI_CPU') == 1 && $(nevents 'info PSI_CPU cpu pressure back to 64%') == 1 ]]
}
test_psi_mem_sustained() {
  setup psi_mem
  local t
  for t in 0 30 60 90; do MM_NOW=$t; psi memory 12.00 3.00; check_psi memory PSI_MEM "10 30" "300 120" 10 5; done
  MM_NOW=120; psi memory 2.00 3.00; check_psi memory PSI_MEM "10 30" "300 120" 10 5   # under 2 min: quiet
  for t in 150 210 270 330 390 450; do MM_NOW=$t; psi memory 12.00 3.00; check_psi memory PSI_MEM "10 30" "300 120" 10 5; done
  [[ $(nevents 'warn PSI_MEM memory pressure some avg60 12%') == 1 && $(grep -c PSI_MEM "$MM_EVENTS") == 1 ]]
}
test_disk_levels() {
  setup disk
  local f
  mm_df_avail_gib() { echo "$FAKE_FREE"; }; for FAKE_FREE in 190 140 95 72; do check_disk; done
  [[ $(nevents 'info DISK 190') == 1 && $(nevents 'info DISK 140') == 1 && $(nevents 'warn DISK 95') == 1 && $(nevents 'crit DISK 72') == 1 ]]
}
test_btrfs_metadata() {
  setup btrfs
  mm_btrfs_meta() { echo 100 90; }; mm_btrfs_unalloc() { echo $((1 << 30)); }
  check_btrfs; check_btrfs
  mm_btrfs_meta() { echo 100 70; }; check_btrfs
  [[ $(nevents 'warn BTRFS') == 1 && $(nevents 'info BTRFS') == 1 ]]
}

# ---- slab from slab-guard's journal lines ----
test_slab_rate_from_journal() {
  setup slab
  MM_NOW=1000; check_slab                       # first run: sets the start point
  mm_journal() { [[ $* == *"-p crit"* ]] && return; printf '1010.5 h slab-guard[1]: kmalloc-128 100 MB\n1070.2 h slab-guard[1]: kmalloc-128 400 MB\n'; }
  MM_NOW=1080; check_slab                       # 300 MB in 60 s
  mm_journal() { [[ $* == *"-p crit"* ]] && return; printf '1130.0 h slab-guard[1]: kmalloc-128 700 MB\n'; }
  MM_NOW=1140; check_slab                       # still growing: no repeat
  [[ $(nevents 'crit SLAB kmalloc-128 growing 300 MB/min, now 400 MB') == 1 && $(nevents 'crit SLAB') == 1 && ! -e $T/sudo ]]
}
test_slab_guard_crit_line() {
  setup slabcrit
  MM_NOW=1000; check_slab
  mm_journal() { [[ $* == *"-p crit"* ]] && echo '1050.0 h slab-guard[1]: over limit, removed EDID overrides'; }
  MM_NOW=1060; check_slab; MM_NOW=1120; check_slab
  [[ $(nevents 'crit SLAB slab-guard: over limit') == 1 ]]
}
test_slab_silent_uses_sudo_rarely() {
  setup slabsilent
  MM_NOW=1000; check_slab
  local t; for t in 2000 2060 2120 2310; do MM_NOW=$t; check_slab; done
  # Silent since 1000: one warn; sudo at 2000 and 2310 only (5 min apart).
  [[ $(nevents 'warn SLAB no slab-guard line') == 1 && $(grep -c SUDO "$T/sudo") == 2 ]]
}

# ---- OOM ----
test_oom_lines() {
  setup oom
  MM_NOW=1000; check_oom
  mm_journal() { printf '1001.0 h kernel: Out of memory: Killed process 42 (cc1plus)\n999.0 h kernel: Out of memory: Killed process 7 (old)\n1002.0 h foo[1]: unrelated\n'; }
  MM_NOW=1030; check_oom
  [[ $(nevents 'crit OOM') == 1 && $(nevents 'cc1plus') == 1 && $(nevents '(old)') == 0 ]]
}

# ---- agent-mail ----
test_agent_mail_state_and_reclaimable() {
  setup am
  mkdir -p "$MM_RECLAIMABLE"; check_agent_mail
  mm_user_active() { echo failed; }; touch "$MM_RECLAIMABLE/a"; check_agent_mail; check_agent_mail
  [[ $(nevents 'warn AGENT_MAIL agent-mail.service now failed') == 1 && $(nevents 'reclaimable entries: 0 -> 1') == 1 ]]
}

# ---- cass ----
test_cass_checks() {
  setup cass
  MKPROC_ENV=CASS_AUTO_REFRESH=0 mkproc 10 cass 1 /user.slice/claude.slice/claude-1.scope cass search foo
  mkproc 11 cass 1 /user.slice/claude.slice/claude-1.scope cass search bar
  MKPROC_ENV=CASS_AUTO_REFRESH=0 mkproc 12 cass 1 /user.slice/claude.slice/claude-1.scope cass index --full
  MKPROC_ENV=CASS_AUTO_REFRESH=0 mkproc 13 cass 1 /user.slice/app.slice/cass-maintenance.service cass index --full
  check_cass; check_cass
  [[ $(nevents 'running without the wrapper: pid 11') == 1 && $(nevents 'outside its unit: pid 12') == 1 && $(nevents CASS) == 2 ]]
}

# ---- process counts ----
test_proc_counts() {
  setup procs
  local i
  for i in $(seq 100 111); do mkproc "$i" gpg-agent 1 /x gpg-agent; done
  for i in $(seq 200 204); do mkproc "$i" git 1 /x git; done
  mkproc 300 wineserver 1 /x wineserver; mkproc 301 winedevice.exe 1 /x x
  check_procs; check_procs
  [[ $(nevents 'warn PROCS 12 gpg-agent') == 1 && $(nevents 'git processes') == 0 && $PROC_COUNTS == "gpg-agent=12 git=5 wine=2" ]]
}
test_tasks_per_scope() {
  setup tasks
  mkdir -p "$MM_CGROUP/claude-1.scope" "$MM_CGROUP/claude-2.scope"
  echo 2100 > "$MM_CGROUP/claude-1.scope/pids.current"; echo 50 > "$MM_CGROUP/claude-2.scope/pids.current"
  check_tasks; check_tasks
  rm -r "$MM_CGROUP/claude-1.scope"; check_tasks
  [[ $(nevents 'crit TASKS claude-1 has 2100 tasks') == 1 && $(nevents TASKS) == 1 && ! -e $MM_STATE/s/tasks_claude-1 ]]
}

# ---- duplicate sessions ----
test_dup_sessions() {
  setup dup
  local A=43134cfc-a1c3-4c0f-a88b-6be49997876c B=b817f468-3981-48b7-af52-fdea57a9a00c
  # Session A: two aiolos-rc wrappers, each with a claude binary child.
  mkproc 10 bash 1 /c/claude-10.scope bash aiolos-rc --resume "$A"
  mkproc 11 2.1.295 10 /c/claude-10.scope /v/2.1.295 --resume "$A"
  mkproc 20 bash 1 /c/claude-20.scope bash aiolos-rc --resume "$A"
  mkproc 21 2.1.295 20 /c/claude-20.scope /v/2.1.295 --resume "$A"
  # Session B: one binary with a same-id child (not a duplicate).
  mkproc 30 claude 1 /c/claude-30.scope claude --resume "$B"
  mkproc 31 claude 30 /c/claude-30.scope claude --resume "$B"
  check_dup_sessions; check_dup_sessions
  rm -r "$MM_PROC/21"; check_dup_sessions
  [[ $(nevents "warn DUP_SESSION session $A runs 2 times: 11(claude-10.scope) 21(claude-20.scope)") == 1 \
     && $(nevents "$B") == 0 && $(nevents "info DUP_SESSION session $A runs once again") == 1 ]]
}

# ---- timers ----
test_timer_skip_and_fail() {
  setup timers
  MM_WATCHED_UNITS="cass-maintenance build-sweep grove-gc"
  mm_user_show() {
    case $1 in
      cass-maintenance.service) printf 'Result=exec-condition\nConditionResult=no\nActiveState=inactive\nConditionTimestampMonotonic=5\nInactiveExitTimestampMonotonic=5\n' ;;
      build-sweep.service) printf 'Result=exit-code\nConditionResult=yes\nActiveState=failed\nConditionTimestampMonotonic=7\nInactiveExitTimestampMonotonic=7\n' ;;
      grove-gc.service) printf 'Result=success\nConditionResult=no\nActiveState=inactive\nConditionTimestampMonotonic=0\nInactiveExitTimestampMonotonic=0\n' ;;
    esac
  }
  check_timers; check_timers
  [[ $(nevents 'warn TIMER cass-maintenance.service did not run cleanly: result exec-condition') == 1 \
     && $(nevents 'warn TIMER build-sweep.service did not run cleanly: result exit-code') == 1 \
     && $(nevents grove-gc) == 0 ]]
}
test_timer_condition_skip_new_run() {
  setup timers2
  MM_WATCHED_UNITS=cass-maintenance
  mm_user_show() { printf 'Result=success\nConditionResult=no\nActiveState=inactive\nConditionTimestampMonotonic=%s\nInactiveExitTimestampMonotonic=1\n' "$RUN"; }
  RUN=5; check_timers; check_timers; RUN=9; check_timers
  [[ $(nevents 'was skipped: a condition failed') == 2 ]]
}
test_timer_inactive_and_slab_guard_down() {
  setup timers3
  MM_WATCHED_UNITS=disk-guard
  mm_user_active() { [[ $1 == disk-guard.timer ]] && echo inactive || echo active; }
  mm_system_active() { echo failed; }
  check_timers; check_timers
  mm_user_active() { echo active; }; mm_system_active() { echo active; }; check_timers
  [[ $(nevents 'warn TIMER disk-guard.timer is inactive') == 1 && $(nevents 'crit TIMER slab-guard.service is failed') == 1 \
     && $(nevents 'info TIMER disk-guard.timer active again') == 1 && $(nevents 'slab-guard.service active again') == 1 ]]
}
test_failed_units_info_once() {
  setup failed
  MM_WATCHED_UNITS=""
  mm_user_failed() { printf 'obex.service\nwtr-a1.scope\nrun-p1.service\n'; }
  mm_system_failed() { echo systemd-udev-settle.service; }
  check_timers; check_timers
  [[ $(nevents 'info TIMER obex.service is in the failed state') == 1 && $(nevents 'udev-settle') == 1 && $(nevents 'wtr-a1') == 0 && $(nevents 'run-p1') == 0 ]]
}

# ---- output ----
test_emit_formats() {
  setup emit
  local out; out=$(emit warn SWAP "swap 80% used")
  [[ $out == "<4>SWAP warn: swap 80% used" ]] && events | grep -qE '^[0-9T:+-]+ warn SWAP swap 80% used$'
}

for f in $(declare -F | awk '{print $3}' | grep '^test_'); do t "$f"; done
echo "passed $pass, failed $fail"
(( fail == 0 ))
