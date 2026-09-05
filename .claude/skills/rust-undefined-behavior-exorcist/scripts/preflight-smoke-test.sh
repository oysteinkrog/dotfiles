#!/usr/bin/env bash
# preflight-smoke-test.sh — validate a Rust project is auditable BEFORE
# committing to a full /rust-undefined-behavior-exorcist run.
#
# Usage:
#   preflight-smoke-test.sh <source-dir>             # writes to <source>/.ub-exorcism/preflight_smoke.json
#   preflight-smoke-test.sh <source-dir> <workspace> # writes to <workspace>/preflight_smoke.json (per-run)
#
# The two-arg form is what Phase 0 uses — it writes the report directly into
# the per-run workspace so the artifact lives next to phase0_*.json. The one-arg
# form is for ad-hoc "is this project auditable at all?" checks.
#
# Runs ~30-60 seconds of fast checks. Catches the most common reasons a run
# would waste an hour before failing — missing nightly, broken cargo metadata,
# unbuildable miri sysroot, fsqlite-style giant compile blocking miri, no fuzz
# targets when the audit expects them, etc.
#
# Exit codes:
#   0 — all checks passed; audit can proceed
#   1 — recoverable failure (specific check failed; report says which)
#   2 — fatal (no nightly toolchain, source dir invalid, etc.)
set -euo pipefail

case "${1:-}" in
    -h|--help)
        awk 'NR>1 && /^#/{sub(/^# ?/, ""); print; next} NR>1{exit}' "$0"
        exit 0
        ;;
esac

if [[ $# -lt 1 ]]; then
    echo "Usage: preflight-smoke-test.sh <source-dir> [<workspace>]" >&2
    echo "  Writes preflight_smoke.json under <workspace> (if given) or <source>/.ub-exorcism/." >&2
    exit 2
fi

SOURCE="$1"
WORKSPACE="${2:-}"   # optional — if provided, write report into <workspace>/

if [[ ! -d "$SOURCE" ]]; then
    echo "Source dir not found: $SOURCE" >&2
    exit 2
fi
if [[ ! -f "$SOURCE/Cargo.toml" ]]; then
    echo "Not a Rust source root (no Cargo.toml): $SOURCE" >&2
    exit 2
fi

# Validate the workspace path BEFORE doing 30s of cargo work. When a workspace
# is given (Phase 0's two-arg form), it must be inside <source>/.ub-exorcism/
# — silently writing somewhere else would mutate the wrong tree.
if [[ -n "$WORKSPACE" ]]; then
    WORKSPACE_REAL="$(realpath -m "$WORKSPACE")"
    SOURCE_REAL="$(realpath -m "$SOURCE")"
    case "$WORKSPACE_REAL" in
        "$SOURCE_REAL"/.ub-exorcism/*) ;;
        *)
            echo "Workspace must be inside <source>/.ub-exorcism/<run-id>" >&2
            echo "  source:    $SOURCE_REAL" >&2
            echo "  workspace: $WORKSPACE_REAL" >&2
            echo "Either drop the second argument to use the shared <source>/.ub-exorcism/ location," >&2
            echo "or pass a workspace inside $SOURCE_REAL/.ub-exorcism/<run-id>/." >&2
            exit 2
            ;;
    esac
fi

# Some projects have src/, some are workspaces with crates/*/src/. Detect the
# "where do we grep for src patterns" path. Fall back to repo root if neither.
if [[ -d "$SOURCE/src" ]]; then
    SRC_SCAN_PATH="$SOURCE/src"
elif [[ -d "$SOURCE/crates" ]]; then
    SRC_SCAN_PATH="$SOURCE/crates"
else
    SRC_SCAN_PATH="$SOURCE"
fi

# rg is preferred but not guaranteed. Fall back to grep -r where possible.
if command -v rg >/dev/null 2>&1; then
    RG="rg"
else
    RG=""    # signals "use grep -r fallback"
fi

# JSON value sanitizer — strips control bytes and escapes backslashes + quotes.
json_safe() {
    local s="${1:-}"
    s="${s//\\/\\\\}"      # backslash first
    s="${s//\"/\\\"}"      # then quotes
    s="${s//$'\n'/ }"       # newlines -> spaces
    s="${s//$'\r'/ }"       # CRs -> spaces
    s="${s//$'\t'/ }"       # tabs -> spaces
    printf '%s' "$s"
}

cd "$SOURCE"
echo "=== Preflight smoke test: $SOURCE ==="

# Status accumulator. We continue past failures and report all at the end.
declare -A OK=()
declare -A NOTE=()

check() {
    local id="$1" desc="$2"
    shift 2
    if "$@" >/dev/null 2>&1; then
        OK[$id]="yes"
        printf '  [✓] %s\n' "$desc"
    else
        OK[$id]="no"
        printf '  [✗] %s\n' "$desc"
    fi
}

check_with_note() {
    local id="$1" desc="$2"
    shift 2
    local out
    if out=$("$@" 2>&1); then
        OK[$id]="yes"
        NOTE[$id]="$(echo "$out" | head -1)"
        printf '  [✓] %s — %s\n' "$desc" "${NOTE[$id]}"
    else
        OK[$id]="no"
        NOTE[$id]="$(echo "$out" | head -1)"
        printf '  [✗] %s — %s\n' "$desc" "${NOTE[$id]}"
    fi
}

# ---- The checks ------------------------------------------------------------

# 1. Stable rust toolchain is callable
check rustup_present "rustup on PATH" command -v rustup

# 2. Nightly toolchain installed
check nightly_installed "nightly toolchain installed" \
    bash -c 'rustup toolchain list 2>/dev/null | grep -q ^nightly'

# 3. Cargo metadata works (the no.1 way a broken Cargo.toml burns time later)
check cargo_metadata "cargo metadata --offline works" \
    cargo metadata --format-version 1 --offline

# 4. cargo check passes on the lib target with --offline (smoke;
#    forces deps to be resolved against the existing Cargo.lock)
check_with_note cargo_check_lib "cargo check --lib --offline" \
    cargo check --lib --offline --message-format=short

# 5. Nightly cargo check (different toolchain may flag stuff)
check_with_note cargo_check_nightly "cargo +nightly check --lib --offline" \
    cargo +nightly check --lib --offline --message-format=short

# 6. Does `cargo +nightly miri --version` succeed? (Miri component present)
check miri_available "cargo +nightly miri --version" \
    cargo +nightly miri --version

# 7. Test discovery — heuristic via file inventory (avoid `cargo test --no-run`,
#    which compiles the test binaries and is multi-minute on real projects).
INLINE_TEST_FILES="0"
INTEG_TEST_FILES="0"
# rg/grep exit 1 on "no matches"; with set -o pipefail that would abort the
# script via set -e. Wrap each in `{ ...; } || true` to make the no-match case
# a successful 0-line pipeline.
if [[ -n "$RG" ]]; then
    INLINE_TEST_FILES="$({ rg -l --type rust '#\[test\]|#\[tokio::test\]|#\[cfg\(test\)\]' "$SRC_SCAN_PATH" 2>/dev/null || true; } | wc -l | tr -d ' ')"
else
    INLINE_TEST_FILES="$({ grep -rl --include='*.rs' -E '#\[test\]|#\[tokio::test\]|#\[cfg\(test\)\]' "$SRC_SCAN_PATH" 2>/dev/null || true; } | wc -l | tr -d ' ')"
fi
if [[ -d "$SOURCE/tests" ]]; then
    INTEG_TEST_FILES="$({ find "$SOURCE/tests" -maxdepth 2 -name '*.rs' 2>/dev/null || true; } | wc -l | tr -d ' ')"
fi
TEST_TOTAL=$((INLINE_TEST_FILES + INTEG_TEST_FILES))
if [[ "$TEST_TOTAL" -gt 0 ]]; then
    OK[has_tests]="yes"
    NOTE[has_tests]="inline=$INLINE_TEST_FILES integration=$INTEG_TEST_FILES"
    printf '  [✓] tests detected (inline-test files: %d, integration files: %d)\n' "$INLINE_TEST_FILES" "$INTEG_TEST_FILES"
else
    OK[has_tests]="no"
    NOTE[has_tests]="no #[test] files found"
    printf '  [⚠] no #[test] files discovered; reproducer harness will need its own crate\n'
fi

# 8. Fuzz target inventory (informational; not all projects have one)
FUZZ_DIR="$SOURCE/fuzz/fuzz_targets"
FUZZ_COUNT=0
if [[ -d "$FUZZ_DIR" ]]; then
    FUZZ_COUNT="$({ find "$FUZZ_DIR" -maxdepth 1 -name '*.rs' 2>/dev/null || true; } | wc -l | tr -d ' ')"
    OK[has_fuzz]="yes"
    NOTE[has_fuzz]="$FUZZ_COUNT targets"
    printf '  [✓] fuzz/ present (%d targets)\n' "$FUZZ_COUNT"
else
    OK[has_fuzz]="no"
    NOTE[has_fuzz]="no fuzz/ dir"
    printf '  [ ] no fuzz/ directory; Phase 3 fuzz step will need authoring\n'
fi

# 9. Look for forbid-unsafe and FFI markers to inform archetype
FORBID_UNSAFE="no"
if [[ -n "$RG" ]]; then
    if rg -F "#![forbid(unsafe_code)]" "$SRC_SCAN_PATH" >/dev/null 2>&1; then
        FORBID_UNSAFE="yes"
    fi
else
    if grep -rF --include='*.rs' "#![forbid(unsafe_code)]" "$SRC_SCAN_PATH" >/dev/null 2>&1; then
        FORBID_UNSAFE="yes"
    fi
fi
FFI_PRESENT="no"
if [[ -n "$RG" ]]; then
    if rg -nq 'extern "C"|extern fn|#\[no_mangle\]|#\[link\(' "$SRC_SCAN_PATH" 2>/dev/null; then
        FFI_PRESENT="yes"
    fi
else
    if grep -rqE --include='*.rs' 'extern "C"|extern fn|#\[no_mangle\]|#\[link\(' "$SRC_SCAN_PATH" 2>/dev/null; then
        FFI_PRESENT="yes"
    fi
fi
# Count actual unsafe { blocks (not files-with-matches). Guarded against the
# zero-match-exits-1 case under pipefail.
if [[ -n "$RG" ]]; then
    UNSAFE_BLOCKS="$({ rg --no-heading --no-filename 'unsafe[[:space:]]*\{' "$SRC_SCAN_PATH" --type rust 2>/dev/null || true; } | wc -l | tr -d ' ')"
else
    UNSAFE_BLOCKS="$({ grep -rE --include='*.rs' 'unsafe[[:space:]]*\{' "$SRC_SCAN_PATH" 2>/dev/null || true; } | wc -l | tr -d ' ')"
fi
UNSAFE_BLOCKS="${UNSAFE_BLOCKS:-0}"
printf '  [i] archetype hints: forbid_unsafe=%s ffi_present=%s unsafe_blocks=%s\n' \
    "$FORBID_UNSAFE" "$FFI_PRESENT" "$UNSAFE_BLOCKS"

# 10. Disk space on the cargo target dir — miri builds a full sysroot,
# easily 5-10 GB. A run that fills disk wastes everyone's day.
TARGET_DIR="${CARGO_TARGET_DIR:-$SOURCE/target}"
TARGET_PARENT="$(dirname "$TARGET_DIR")"
mkdir -p "$TARGET_PARENT" 2>/dev/null || true
AVAIL_KB="$(df -k "$TARGET_PARENT" 2>/dev/null | awk 'NR==2 {print $4}' || echo 0)"
AVAIL_GB="$((AVAIL_KB / 1024 / 1024))"
if [[ "$AVAIL_GB" -ge 20 ]]; then
    OK[disk_space]="yes"
    printf '  [✓] %d GB free on %s (≥20 GB recommended)\n' "$AVAIL_GB" "$TARGET_PARENT"
else
    OK[disk_space]="no"
    printf '  [⚠] only %d GB free on %s (Miri sysroot can exceed 10 GB)\n' "$AVAIL_GB" "$TARGET_PARENT"
fi

# ---- Report ----------------------------------------------------------------

FAILED="0"
for k in "${!OK[@]}"; do
    [[ "${OK[$k]}" == "no" ]] && FAILED=$((FAILED + 1))
done

echo
echo "=== Summary ==="
printf '  %d check(s) failed\n' "$FAILED"

# Write the report. Priority:
#   1. If <workspace> was provided (Phase 0's two-arg form), write into it.
#      This puts the report next to phase0_*.json under the per-run workspace.
#   2. Else if <source>/.ub-exorcism/ exists, write into it (shared across runs).
#   3. Else fall back to /tmp.
if [[ -n "$WORKSPACE" ]]; then
    # WORKSPACE_REAL was already validated at the top of the script.
    mkdir -p "$WORKSPACE_REAL"
    REPORT_DIR="$WORKSPACE_REAL"
elif [[ -d "$SOURCE/.ub-exorcism" ]]; then
    REPORT_DIR="$SOURCE/.ub-exorcism"
else
    REPORT_DIR="/tmp"
fi
REPORT_FILE="$REPORT_DIR/preflight_smoke.json"

{
    printf '{\n'
    printf '  "timestamp": "%s",\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '  "source": "%s",\n' "$(json_safe "$SOURCE")"
    printf '  "checks": {\n'
    first=1
    for k in rustup_present nightly_installed cargo_metadata cargo_check_lib cargo_check_nightly miri_available has_tests has_fuzz disk_space; do
        [[ $first -eq 1 ]] || printf ',\n'
        first=0
        printf '    "%s": {"ok": "%s", "note": "%s"}' "$k" "${OK[$k]:-untested}" "$(json_safe "${NOTE[$k]:-}")"
    done
    printf '\n  },\n'
    printf '  "archetype_hints": {\n'
    printf '    "forbid_unsafe": "%s",\n' "$FORBID_UNSAFE"
    printf '    "ffi_present": "%s",\n' "$FFI_PRESENT"
    printf '    "unsafe_blocks_count": "%s"\n' "$UNSAFE_BLOCKS"
    printf '  },\n'
    printf '  "failed_count": %d\n' "$FAILED"
    printf '}\n'
} > "$REPORT_FILE"

echo "  Report: $REPORT_FILE"

# Hard-fail signals (the audit cannot proceed without these)
if [[ "${OK[nightly_installed]:-no}" != "yes" ]] || \
   [[ "${OK[cargo_metadata]:-no}"     != "yes" ]] || \
   [[ "${OK[cargo_check_lib]:-no}"    != "yes" ]]; then
    echo
    echo "FATAL: required check failed. Audit cannot proceed until resolved."
    exit 2
fi

if [[ "$FAILED" -gt 0 ]]; then
    echo
    echo "WARNING: $FAILED non-fatal check(s) failed. Audit can proceed but"
    echo "Phase 3 dynamic steps may need workarounds (see TROUBLESHOOTING.md)."
    exit 1
fi

echo
echo "All checks passed. Proceed to Phase 0 partition + Phase 1 fan-out."
exit 0
