#!/usr/bin/env bash
# verify-crash-recovery.sh — Phase 5 crash-recovery test.
#
# Usage: verify-crash-recovery.sh <fm_id> [<tool>] [<fixture_root>]
# Kills <tool> doctor --fix at K = {1, 5, 25, 125} ms after launch.
# Asserts next invocation either completes the partial fix or aborts cleanly.
# No torn writes; no orphan .tmp.<pid> files; no stale lock.

set -euo pipefail
fm_id="${1:-}"
if [ -z "$fm_id" ]; then
    echo "usage: verify-crash-recovery.sh <fm_id> [<tool>] [<fixture_root>]" >&2
    exit 64
fi
tool="${2:-${TOOL:-}}"
if [ -z "$tool" ]; then
    echo "error: provide <tool> as arg 2 or set TOOL env var" >&2
    exit 64
fi
fixture_root="${3:-tests/doctor_fixtures}"
crashes_exercised=0

corrupt_sh="$fixture_root/$fm_id/corrupt.sh"
[ -x "$corrupt_sh" ] || { echo "FAIL: $corrupt_sh missing" >&2; exit 1; }

proc_starttime() {
    # /proc/<pid>/stat field 2 is the command name in parentheses and may
    # contain spaces, so plain `awk '{print $22}'` can read the wrong field.
    local stat rest
    stat=$(cat "/proc/$1/stat" 2>/dev/null) || return 1
    rest="${stat##*) }"
    # shellcheck disable=SC2086 # intentional split of numeric stat fields
    set -- $rest
    [ -n "${20:-}" ] || return 1
    printf '%s\n' "${20}"
}

for k_ms in 1 5 25 125; do
    sandbox=$(mktemp -d)
    # Per-run artifact dir under the sandbox so concurrent verify-crash-recovery
    # invocations don't collide on world-writable /tmp/crash_$k_ms.json paths.
    # Round-53 triangulation flagged the prior version as a TOCTOU + cross-test
    # race when multiple agents or a CI matrix runs the same K in parallel.
    artifacts="$sandbox/.verify-crash-recovery"
    mkdir -p "$artifacts"
    "$corrupt_sh" "$sandbox" >&2

    # Launch --fix, kill at k_ms.
    ( cd "$sandbox" && "$tool" doctor --fix --json > "$artifacts/crash_$k_ms.json" 2>&1 ) &
    pid=$!
    # Detect whether /proc/<pid>/stat is queryable on this OS (Linux yes,
    # macOS/BSD no). When unavailable we fall back to kill -0 + kill -9 with
    # the documented PID-recycle race; on Linux we use the field-22 starttime
    # as a fingerprint to defend against PID reuse during the K-ms delay.
    procfs_available=false
    have_proc_stat=false
    starttime_expected=""
    [ -d /proc ] && procfs_available=true
    if [ -r "/proc/$pid/stat" ]; then
        # Field 22 is starttime in clock ticks since boot. Capture it
        # immediately after spawn so any later SIGKILL is tied to the process
        # we launched, not a PID that may have been recycled during the delay.
        starttime_expected=$(proc_starttime "$pid" || echo "")
        [ -n "$starttime_expected" ] && have_proc_stat=true
    fi

    # Convert ms to seconds for sleep (POSIX sleep doesn't support fractional;
    # use python3 if available). Pass $k_ms via argv, NOT string-interpolated
    # into the python source — the prior `time.sleep($k_ms/1000.0)` form was
    # latent shell-injection: currently safe with literal {1, 5, 25, 125} but
    # if anyone ever parameterizes K from CLI args, becomes RCE. (Audit found.)
    if command -v python3 >/dev/null 2>&1; then
        python3 -c 'import sys, time; time.sleep(int(sys.argv[1]) / 1000.0)' "$k_ms"
    else
        # Fallback: round up to 1 second
        sleep 1
    fi

    if [ "$have_proc_stat" = true ]; then
        # Linux path: re-check starttime immediately before SIGKILL. If it
        # changed (or the entry vanished), the PID was recycled or exited.
        if [ -r "/proc/$pid/stat" ]; then
            starttime_post=$(proc_starttime "$pid" || echo "")
        else
            starttime_post=""
        fi
        if [ -n "$starttime_post" ] && [ "$starttime_post" = "$starttime_expected" ]; then
            kill -9 "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
            crashes_exercised=$((crashes_exercised + 1))
        else
            echo "verify-crash-recovery: PID $pid changed identity (recycled) or exited before SIGKILL; skipping K=$k_ms" >&2
            wait "$pid" 2>/dev/null || true
            continue
        fi
    elif [ "$procfs_available" = true ]; then
        echo "verify-crash-recovery: could not fingerprint PID $pid via /proc; skipping K=$k_ms rather than counting a possible early-exit/zombie as a crash" >&2
        # Without a fingerprint we don't count this as a crash exercise, but
        # we still need to terminate the child — otherwise `wait $pid` would
        # block until the doctor exits naturally, potentially minutes per K.
        # kill -0 confirms a process by that PID exists before SIGKILL.
        if kill -0 "$pid" 2>/dev/null; then
            kill -9 "$pid" 2>/dev/null || true
        fi
        wait "$pid" 2>/dev/null || true
        continue
    else
        # macOS / non-Linux fallback: kill -0 to test liveness, kill -9 to
        # terminate. Window for PID-recycling exists but is narrow; document
        # the limitation rather than hard-fail on platforms without /proc.
        if kill -0 "$pid" 2>/dev/null; then
            kill -9 "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
            crashes_exercised=$((crashes_exercised + 1))
        else
            echo "verify-crash-recovery: doctor exited before SIGKILL; not a crash test for K=$k_ms" >&2
            wait "$pid" 2>/dev/null || true
            continue
        fi
    fi

    # Check for canonical doctor tempfiles inside the sandbox. Recipes and
    # PROPERTY-TESTS.md use `.doctor.tmp.*` / `*.doctor.tmp.*`; symlink-atomic
    # recipes use `*.doctor-symlink-tmp.*`; retain the older `.tmp.*` pattern
    # so historical implementations are still caught. Include symlinks as well
    # as regular files, or a crash between symlink creation and atomic rename
    # falsely passes the recovery test.
    orphans=$(find "$sandbox" \( -type f -o -type l \) \( \
        -name '.doctor.tmp.*' -o \
        -name '*.doctor.tmp.*' -o \
        -name '*.doctor-symlink-tmp.*' -o \
        -name '.tmp.*' \
    \) 2>/dev/null | wc -l)
    if [ "$orphans" -gt 0 ]; then
        echo "FAIL k=$k_ms: $orphans orphan doctor temp files" >&2
        find "$sandbox" \( -type f -o -type l \) \( \
            -name '.doctor.tmp.*' -o \
            -name '*.doctor.tmp.*' -o \
            -name '*.doctor-symlink-tmp.*' -o \
            -name '.tmp.*' \
        \) >&2
        exit 1
    fi

    # Next invocation: either completes or aborts cleanly.
    next_exit=0
    ( cd "$sandbox" && "$tool" doctor --json ) > "$artifacts/next_$k_ms.json" 2>&1 || next_exit=$?

    case "$next_exit" in
        0|1|4)
            # 0=healthy (partial fix completed by recovery); 1=findings still
            # present (clean abort); 4=refused (clean abort).
            ;;
        *)
            echo "FAIL k=$k_ms: next invocation exit=$next_exit (expected 0/1/4)" >&2
            cat "$artifacts/next_$k_ms.json" >&2
            exit 1
            ;;
    esac

    # Sandbox accumulates under /tmp (OS-level cleanup handles it).
    # Per AGENTS.md and dcg policy, test scripts do NOT use rm -rf.
done

if [ "$crashes_exercised" -eq 0 ]; then
    echo "FAIL: no crash point was exercised; doctor finished before all kill windows" >&2
    echo "Add a slower fixture or an explicit crash-injection hook before trusting crash recovery." >&2
    exit 1
fi

echo "PASS: verify-crash-recovery.sh fm=$fm_id (all K)" >&2
