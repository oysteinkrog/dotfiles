#!/usr/bin/env bash
# bisect-ub.sh — git-bisect target script for UB findings.
#
# Two modes:
#   (1) Test mode (invoked by `git bisect run`):
#         bisect-ub.sh <repo-path> <exp-id> [--toolchain <tc>] [--runs N]
#       Exit 0 = good (no UB), 1 = bad (UB present), 125 = skip (no compile / flaky).
#
#   (2) Driver mode (invoke once to start a full bisection):
#         bisect-ub.sh --drive <repo-path> <exp-id> <good-ref> <bad-ref> [--toolchain <tc>]
#       This starts `git bisect`, runs this script in test mode at each step,
#       and produces a final report.
#
# Critical handling per BISECTION.md gotchas:
#   - G1: looks for out-of-tree reproducer at <workspace>/experiments/<exp>/repro.rs
#     (with its own Cargo.toml) so older commits that lack the in-tree test
#     still bisect.
#   - G2: runs the test --runs times (default 5) and requires unanimous PASS
#     for "good" or majority FAIL for "bad"; ambiguous → skip (125).
#   - G3: `--toolchain` flag pins RUSTUP_TOOLCHAIN; defaults to "nightly".
#   - G5: post-bisection report mentions if the landing commit is a merge.
#
# Workspace assumption: the EXP block is in
# <repo>/.ub-exorcism/<run-id>/UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md and the
# repro is at <repo>/.ub-exorcism/<run-id>/experiments/<exp>/repro.rs. If you
# pass an absolute workspace via $UB_EXORCISM_WORKSPACE env var, that overrides.
set -euo pipefail

case "${1:-}" in
    -h|--help)
        awk 'NR>1 && /^#/{sub(/^# ?/, ""); print; next} NR>1{exit}' "$0"
        exit 0
        ;;
esac

DRIVE=no
if [[ "${1:-}" == "--drive" ]]; then
    DRIVE=yes
    shift
fi

if [[ $# -lt 2 ]]; then
    echo "Usage:" >&2
    echo "  bisect-ub.sh <repo> <exp-id> [--toolchain <tc>] [--runs N]    # test mode (one commit)" >&2
    echo "  bisect-ub.sh --drive <repo> <exp-id> <good-ref> <bad-ref> [...]  # driver mode" >&2
    exit 2
fi

REPO="$1"
EXP="$2"
shift 2

TOOLCHAIN="nightly"
RUNS=5
GOOD_REF=""
BAD_REF=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --toolchain)    shift; TOOLCHAIN="$1" ;;
        --toolchain=*)  TOOLCHAIN="${1#--toolchain=}" ;;
        --runs)         shift; RUNS="$1" ;;
        --runs=*)       RUNS="${1#--runs=}" ;;
        --good)         shift; GOOD_REF="$1" ;;
        --bad)          shift; BAD_REF="$1" ;;
        *)
            if [[ "$DRIVE" == "yes" && -z "$GOOD_REF" ]]; then
                GOOD_REF="$1"
            elif [[ "$DRIVE" == "yes" && -z "$BAD_REF" ]]; then
                BAD_REF="$1"
            else
                echo "Unknown arg: $1" >&2; exit 2
            fi
            ;;
    esac
    shift
done

REPO_REAL="$(realpath -m "$REPO")"
if [[ ! -d "$REPO_REAL/.git" ]]; then
    echo "Not a git repo: $REPO_REAL" >&2
    exit 2
fi

# Locate workspace + repro
WORKSPACE="${UB_EXORCISM_WORKSPACE:-}"
if [[ -z "$WORKSPACE" ]]; then
    # Pick by mtime — workspace names vary (date, timestamp, slug); the most
    # recently touched directory is what the current audit is using. Tab + cut
    # -f2- handles paths containing spaces.
    WORKSPACE=$(find "$REPO_REAL/.ub-exorcism" -mindepth 1 -maxdepth 1 -type d \
                     -printf '%T@\t%p\n' 2>/dev/null \
                | sort -rn | head -1 | cut -f2-)
    # Announce the auto-pick so the operator sees which audit we're acting on —
    # silent auto-detect on a directory the operator forgot about is a classic
    # source of "why did it bisect against EXP-007 from last week's run?".
    [[ -n "$WORKSPACE" ]] && echo "Auto-selected workspace by mtime: $WORKSPACE" >&2
fi
if [[ -z "$WORKSPACE" || ! -d "$WORKSPACE" ]]; then
    echo "No .ub-exorcism/<run-id>/ workspace under $REPO_REAL. Set UB_EXORCISM_WORKSPACE." >&2
    exit 2
fi
REPRO_DIR="$WORKSPACE/experiments/$EXP"
REPRO_RS="$REPRO_DIR/repro.rs"
REPRO_TOML="$REPRO_DIR/Cargo.toml"

if [[ ! -f "$REPRO_RS" ]]; then
    echo "Missing reproducer: $REPRO_RS" >&2
    echo "Author one in $REPRO_DIR/ before bisecting (Phase 5 standalone-harness pattern)." >&2
    exit 2
fi

LOGDIR="$WORKSPACE/phase5_experiment_results"
mkdir -p "$LOGDIR"
BISECT_LOG="$LOGDIR/bisect_${EXP}.log"

# ── test-mode: run the reproducer N times, vote on verdict ─────────────────
test_one_commit() {
    # If the repo at the current commit doesn't compile, return 125 (skip).
    if ! (cd "$REPO_REAL" && \
          RUSTUP_TOOLCHAIN="$TOOLCHAIN" cargo check --all-targets --offline 2>/dev/null \
          || RUSTUP_TOOLCHAIN="$TOOLCHAIN" cargo check --all-targets 2>/dev/null); then
        echo "[$(git -C "$REPO_REAL" rev-parse --short HEAD)] does not compile — skipping" | tee -a "$BISECT_LOG"
        return 125
    fi

    local pass=0 fail=0
    # Use cargo-output-to-file + separate-grep instead of piping miri | grep
    # because: miri exits non-zero when UB is found; under `set -o pipefail`,
    # the pipeline's exit code reflects miri's failure, NOT grep's match.
    # That makes `if (miri | grep -q "Undefined Behavior")` always false when
    # UB is found — flipping the verdict. The file-based version is correct.
    local runlog
    for i in $(seq 1 "$RUNS"); do
        runlog="$BISECT_LOG.run.$i"
        if [[ -f "$REPRO_TOML" ]]; then
            set +e
            (cd "$REPRO_DIR" && \
                RUSTUP_TOOLCHAIN="$TOOLCHAIN" \
                MIRIFLAGS="${MIRIFLAGS:--Zmiri-disable-isolation}" \
                cargo +"$TOOLCHAIN" miri test) > "$runlog" 2>&1
            set -e
            tee -a "$BISECT_LOG" < "$runlog" >/dev/null
            # Standalone-cargo-project repro: PASS iff Miri reports test result: ok
            if grep -q "test result: ok" "$runlog" 2>/dev/null; then
                pass=$((pass+1))
            else
                fail=$((fail+1))
            fi
        else
            # Loose repro.rs — invoke directly under miri
            set +e
            (cd "$REPO_REAL" && \
                RUSTUP_TOOLCHAIN="$TOOLCHAIN" \
                MIRIFLAGS="${MIRIFLAGS:--Zmiri-disable-isolation}" \
                cargo +"$TOOLCHAIN" miri run "$REPRO_RS") > "$runlog" 2>&1
            set -e
            tee -a "$BISECT_LOG" < "$runlog" >/dev/null
            # Loose repro: FAIL iff Miri printed "Undefined Behavior"
            if grep -q "Undefined Behavior" "$runlog" 2>/dev/null; then
                fail=$((fail+1))
            else
                pass=$((pass+1))
            fi
        fi
    done

    local sha
    sha=$(git -C "$REPO_REAL" rev-parse --short HEAD)
    echo "[$sha] runs=$RUNS pass=$pass fail=$fail" | tee -a "$BISECT_LOG"

    # Decision rule per BISECTION.md G2:
    #   pass == RUNS → good (exit 0)
    #   fail >= ceil(RUNS/2) → bad (exit 1)
    #   else → ambiguous, skip (exit 125)
    if [[ "$pass" -eq "$RUNS" ]]; then
        return 0
    fi
    local half=$(( (RUNS + 1) / 2 ))
    if [[ "$fail" -ge "$half" ]]; then
        return 1
    fi
    return 125
}

# ── drive-mode: start a bisect session, run, report ────────────────────────
drive_bisect() {
    if [[ -z "$GOOD_REF" || -z "$BAD_REF" ]]; then
        echo "Drive mode requires <good-ref> <bad-ref>." >&2
        exit 2
    fi
    echo "=== bisect-ub: $EXP from $GOOD_REF (good) to $BAD_REF (bad) ===" | tee "$BISECT_LOG"
    (
        cd "$REPO_REAL"
        git bisect start "$BAD_REF" "$GOOD_REF"
        # The bisect-run command invokes THIS script in test mode.
        git bisect run "$0" "$REPO_REAL" "$EXP" \
            --toolchain "$TOOLCHAIN" --runs "$RUNS"
    ) 2>&1 | tee -a "$BISECT_LOG"

    # Capture final result
    local first_bad
    first_bad=$({
        cd "$REPO_REAL" && git bisect log 2>/dev/null
    } | grep -E '^# first bad commit:' | head -1 || true)
    echo "$first_bad" | tee -a "$BISECT_LOG"

    if [[ -n "$first_bad" ]]; then
        local sha
        sha=$(echo "$first_bad" | awk '{print $5}')
        # G5: check if it's a merge commit
        if (cd "$REPO_REAL" && git cat-file -p "$sha" | grep -c '^parent ' | grep -q '^[2-9]'); then
            echo "WARNING (G5): introducer is a merge commit. Re-run with --first-parent to dig in." | tee -a "$BISECT_LOG"
        fi
    fi

    (cd "$REPO_REAL" && git bisect reset) >>"$BISECT_LOG" 2>&1
    echo "Bisect log saved to $BISECT_LOG"
}

if [[ "$DRIVE" == "yes" ]]; then
    drive_bisect
else
    # test mode: this script is being invoked by `git bisect run`.
    set +e
    test_one_commit
    rc=$?
    set -e
    exit "$rc"
fi
