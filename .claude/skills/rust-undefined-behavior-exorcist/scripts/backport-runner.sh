#!/usr/bin/env bash
# backport-runner.sh — for a confirmed-UB EXP, check whether the UB reproduces
# in each supported-version release tag, producing a backport-candidate matrix.
#
# Usage:
#   backport-runner.sh <repo> <exp-id> <tag-1> [<tag-2> ...]
#                                              [--toolchain <tc>] [--runs N]
#
# Per BACKPORTING.md, the matrix tells you which releases need a backport patch:
#   - "YES — backport candidate" → UB reproduces; cherry-pick the fix
#   - "NO  — pre-introduction"   → UB not present; nothing to backport
#   - "SKIP — does not compile"  → tag pre-dates the test infrastructure
#
# Safety: does not use git worktrees and does not mutate the active checkout.
# Historical tags are materialized as non-git archive snapshots under the audit
# workspace so the user can inspect or clean them up explicitly later.
#
# Exit codes:
#   0 — matrix produced (may include SKIP entries)
#   1 — at least one tag failed catastrophically (not a verdict; an error)
#   2 — usage error / repo or repro missing
set -euo pipefail

case "${1:-}" in
    -h|--help)
        awk 'NR>1 && /^#/{sub(/^# ?/, ""); print; next} NR>1{exit}' "$0"
        exit 0
        ;;
esac

if [[ $# -lt 3 ]]; then
    echo "Usage: backport-runner.sh <repo> <exp-id> <tag-1> [<tag-2> ...] [--toolchain <tc>] [--runs N]" >&2
    exit 2
fi

REPO="$1"
EXP="$2"
shift 2

TAGS=()
TOOLCHAIN="nightly"
RUNS=3
WORKSPACE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --toolchain)    shift; TOOLCHAIN="$1" ;;
        --toolchain=*)  TOOLCHAIN="${1#--toolchain=}" ;;
        --runs)         shift; RUNS="$1" ;;
        --runs=*)       RUNS="${1#--runs=}" ;;
        --workspace)    shift; WORKSPACE="$1" ;;
        --workspace=*)  WORKSPACE="${1#--workspace=}" ;;
        *)              TAGS+=("$1") ;;
    esac
    shift
done

if [[ "${#TAGS[@]}" -eq 0 ]]; then
    echo "Need at least one tag." >&2
    exit 2
fi

REPO_REAL="$(realpath -m "$REPO")"
if [[ ! -d "$REPO_REAL/.git" ]]; then
    echo "Not a git repo: $REPO_REAL" >&2
    exit 2
fi

# Locate workspace + repro.  Pick the workspace by mtime, not by lexical name —
# users have all sorts of names (`smoke-X-DATE`, ISO-timestamp, `audit-N`); the
# most recently touched directory is the one the current audit lives in.  GNU
# find's `-printf '%T@'` gives a sortable epoch timestamp; tab + `cut -f2-`
# preserves paths that contain spaces.
if [[ -z "$WORKSPACE" ]]; then
    WORKSPACE=$(find "$REPO_REAL/.ub-exorcism" -mindepth 1 -maxdepth 1 -type d \
                     -printf '%T@\t%p\n' 2>/dev/null \
                | sort -rn | head -1 | cut -f2-)
    # Announce which one we picked — silent auto-detect on a stale dir is a
    # subtle footgun ("why is the matrix testing last week's reproducer?").
    [[ -n "$WORKSPACE" ]] && echo "Auto-selected workspace by mtime: $WORKSPACE" >&2
fi
if [[ -z "$WORKSPACE" || ! -d "$WORKSPACE" ]]; then
    echo "No workspace under $REPO_REAL/.ub-exorcism/" >&2
    exit 2
fi
REPRO_DIR="$WORKSPACE/experiments/$EXP"
REPRO_RS="$REPRO_DIR/repro.rs"
if [[ ! -f "$REPRO_RS" ]]; then
    echo "Reproducer missing: $REPRO_RS" >&2
    exit 2
fi

OUT="$WORKSPACE/phase5_experiment_results/backport_${EXP}.md"
mkdir -p "$(dirname "$OUT")"

# Snapshot base. These are audit artifacts, not git worktrees; do not auto-delete.
SNAP_BASE="$WORKSPACE/phase5_experiment_results/backport_${EXP}_snapshots"
LOG_BASE="$SNAP_BASE/logs"
mkdir -p "$SNAP_BASE" "$LOG_BASE"

safe_tag_name() {
    printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_'
}

# Run the repro at one tag using its own archive snapshot
check_one_tag() {
    local tag="$1"
    local safe_tag snap

    safe_tag="$(safe_tag_name "$tag")"
    snap="$SNAP_BASE/${safe_tag}_$(date -u +%Y%m%dT%H%M%SZ)_$$"
    mkdir -p "$snap"

    # Create a non-git snapshot at the tag.
    if ! (git -C "$REPO_REAL" archive "$tag" | tar -x -C "$snap") >/dev/null 2>&1; then
        echo "ERROR — could not archive tag $tag (does the tag exist?)"
        return
    fi

    # Build check first — if it doesn't compile, SKIP
    if ! (cd "$snap" && RUSTUP_TOOLCHAIN="$TOOLCHAIN" cargo check --all-targets 2>/dev/null); then
        echo "SKIP — does not compile under +$TOOLCHAIN at $tag"
        return
    fi

    # Vote across $RUNS executions of the standalone repro under Miri.
    local pass=0 fail=0
    for i in $(seq 1 "$RUNS"); do
        # The standalone repro at $REPRO_DIR has its own Cargo.toml pointing
        # back to the parent crate via path-dep. Copy it into the snapshot
        # area and re-point the copy at this tag's snapshot.
        if [[ -f "$REPRO_DIR/Cargo.toml" ]]; then
            local repro_run_dir="$SNAP_BASE/repro_${safe_tag}_${i}_$$"
            cp -a "$REPRO_DIR" "$repro_run_dir"
            local repro_toml="$repro_run_dir/Cargo.toml"
            # Edit only the copied Cargo.toml. `sed -i` portability: BSD requires
            # an extension arg, GNU accepts both — pass an explicit `.bak`.
            if ! sed -i.bak "s|^path = .*|path = \"$snap\"|" "$repro_toml" 2>/dev/null; then
                echo "    sed rewrite failed at $tag; copied repro left at $repro_run_dir" >&2
            else
                # Capture miri output to a file first, THEN grep separately.
                # Piping miri | grep is wrong under pipefail: miri exits non-zero
                # when UB is found (test failure), and pipefail propagates THAT
                # exit code instead of grep's match. The result: pipefail says
                # "pipeline failed" → we'd record "no UB" when there IS UB.
                local logfile="$LOG_BASE/${safe_tag}_miri_${i}.log"
                set +e
                (cd "$repro_run_dir" && \
                    RUSTUP_TOOLCHAIN="$TOOLCHAIN" \
                    MIRIFLAGS="${MIRIFLAGS:--Zmiri-disable-isolation}" \
                    cargo +"$TOOLCHAIN" miri test) > "$logfile" 2>&1
                set -e
                if grep -q "Undefined Behavior" "$logfile" 2>/dev/null; then
                    fail=$((fail+1))
                else
                    pass=$((pass+1))
                fi
                continue
            fi
        else
            # Loose repro — capture output to file then grep (same pipefail issue)
            local logfile="$LOG_BASE/${safe_tag}_miri_${i}.log"
            set +e
            (cd "$snap" && \
                RUSTUP_TOOLCHAIN="$TOOLCHAIN" \
                MIRIFLAGS="${MIRIFLAGS:--Zmiri-disable-isolation}" \
                cargo +"$TOOLCHAIN" miri run "$REPRO_RS") > "$logfile" 2>&1
            set -e
            if grep -q "Undefined Behavior" "$logfile" 2>/dev/null; then
                fail=$((fail+1))
            else
                pass=$((pass+1))
            fi
        fi
    done

    if [[ "$fail" -ge $(( (RUNS + 1) / 2 )) ]]; then
        echo "YES — backport candidate (UB reproduces: $fail/$RUNS runs)"
    elif [[ "$pass" -eq "$RUNS" ]]; then
        echo "NO — pre-introduction (clean: $pass/$RUNS runs)"
    else
        echo "AMBIGUOUS — pass=$pass fail=$fail / $RUNS runs (flaky; investigate)"
    fi
}

{
    echo "# Backport matrix for $EXP"
    echo
    echo "Generated $(date -u +%FT%TZ) by backport-runner.sh"
    echo "Reproducer: $REPRO_RS"
    echo "Toolchain: $TOOLCHAIN · Runs per tag: $RUNS"
    echo "Snapshots: $SNAP_BASE"
    echo
    echo "| Tag | Verdict |"
    echo "|---|---|"
    for tag in "${TAGS[@]}"; do
        verdict="$(check_one_tag "$tag")"
        # shellcheck disable=SC2016 # Markdown backticks in the table format are literal.
        printf '| `%s` | %s |\n' "$tag" "$verdict"
    done
    echo
    echo "**Action:** for every 'YES — backport candidate' row, cherry-pick the remediation commit onto the corresponding release branch + re-test. See the rust-undefined-behavior-exorcist BACKPORTING.md reference."
} | tee "$OUT"

echo
echo "Matrix written to $OUT"
exit 0
