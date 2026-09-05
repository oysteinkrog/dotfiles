#!/usr/bin/env bash
# drift-monitor.sh — between full audits, detect drift signals that warrant a
# spot-audit. See LIFECYCLE.md §Drift detection.
#
# Usage:
#   drift-monitor.sh <workspace> [--baseline-ref <git-ref>] [--source <dir>]
#
# Compares the CURRENT state of the audited source against a BASELINE git ref
# (default: the commit at which the prior full audit landed — auto-detected
# from the bead-graph commit history if not provided).
#
# Drift signals checked:
#   1. New `unsafe` blocks since baseline → HIGH (spot-audit)
#   2. Modified `unsafe` blocks since baseline → HIGH (re-run EXP)
#   3. Cargo.toml dep additions → MEDIUM
#   4. rust-toolchain.toml bump → LOW (re-run Miri matrix)
#   5. New `extern "C"` blocks → HIGH (re-run FFI bucket)
#   6. New `loom::` symbol use → HIGH (re-author loom model)
#   7. cargo-audit fresh advisories → as severity reports
#
# Exit codes:
#   0 — no drift detected (or all detected is LOW)
#   1 — HIGH/MEDIUM drift detected (recommend spot-audit)
#   2 — usage error / workspace invalid / git unavailable
set -euo pipefail

case "${1:-}" in
    -h|--help)
        awk 'NR>1 && /^#/{sub(/^# ?/, ""); print; next} NR>1{exit}' "$0"
        exit 0
        ;;
esac

if [[ $# -lt 1 ]]; then
    echo "Usage: drift-monitor.sh <workspace> [--baseline-ref <ref>] [--source <dir>]" >&2
    exit 2
fi

WORKSPACE="$1"
shift

BASELINE_REF=""
SOURCE_OVERRIDE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --baseline-ref)    shift; BASELINE_REF="$1" ;;
        --baseline-ref=*)  BASELINE_REF="${1#--baseline-ref=}" ;;
        --source)          shift; SOURCE_OVERRIDE="$1" ;;
        --source=*)        SOURCE_OVERRIDE="${1#--source=}" ;;
        *)                 echo "Unknown flag: $1" >&2; exit 2 ;;
    esac
    shift
done

WORKSPACE_REAL="$(realpath -m "$WORKSPACE")"
case "$WORKSPACE_REAL" in
    */.ub-exorcism/*) ;;
    *)
        echo "Workspace must be inside <source>/.ub-exorcism/<run-id>" >&2
        exit 2
        ;;
esac
WORKSPACE="$WORKSPACE_REAL"
SOURCE="${SOURCE_OVERRIDE:-${WORKSPACE%%/.ub-exorcism/*}}"

if [[ ! -d "$SOURCE/.git" ]]; then
    echo "Source is not a git repo: $SOURCE" >&2
    exit 2
fi

# Auto-detect baseline: the commit immediately after the prior audit's bead-graph commit.
# Heuristic: the most recent commit message containing "Land UB-exorcism beads".
if [[ -z "$BASELINE_REF" ]]; then
    BASELINE_REF=$(cd "$SOURCE" && git log --grep='Land UB-exorcism beads' --format='%H' -n1 2>/dev/null || true)
    if [[ -z "$BASELINE_REF" ]]; then
        # Fall back to the workspace's git-tracked phase1 inventory's last-modified commit
        if [[ -f "$WORKSPACE/phase1_unsafe_surface_inventory.md" ]]; then
            BASELINE_REF=$(cd "$SOURCE" && git log --format='%H' -n1 -- "$WORKSPACE/phase1_unsafe_surface_inventory.md" 2>/dev/null || true)
        fi
    fi
fi

if [[ -z "$BASELINE_REF" ]]; then
    echo "Could not auto-detect baseline ref. Pass --baseline-ref <commit-or-tag>." >&2
    exit 2
fi

HEAD_REF=$(cd "$SOURCE" && git rev-parse HEAD)
echo "=== drift-monitor — baseline=$BASELINE_REF head=$HEAD_REF ==="

declare -i HIGH=0 MEDIUM=0 LOW=0

# Counter helper
report() {
    local sev="$1" desc="$2"
    case "$sev" in
        HIGH)   HIGH=$((HIGH+1));   printf '  [HIGH]   %s\n' "$desc" ;;
        MEDIUM) MEDIUM=$((MEDIUM+1)); printf '  [MEDIUM] %s\n' "$desc" ;;
        LOW)    LOW=$((LOW+1));     printf '  [LOW]    %s\n' "$desc" ;;
    esac
}

# 1+2. unsafe-block diff
echo
echo "── unsafe-block additions/modifications ──"
unsafe_diff=$(cd "$SOURCE" && git diff "$BASELINE_REF" HEAD -- '*.rs' 2>/dev/null \
              | grep -E '^[+-].*(^|[^a-zA-Z])unsafe[[:space:]]*(fn|impl|trait|extern|\{)' || true)
int_count() { local out; out=$(printf '%s\n' "$1" | grep -c "$2" 2>/dev/null || true); out="${out//[^0-9]/}"; echo "${out:-0}"; }
if [[ -n "$unsafe_diff" ]]; then
    new_unsafe=$(int_count "$unsafe_diff" '^+')
    rm_unsafe=$(int_count  "$unsafe_diff" '^-')
    [[ "$new_unsafe" -gt 0 ]] && report HIGH "$new_unsafe new 'unsafe' line(s) since baseline — spot-audit and add SAFETY comments"
    [[ "$rm_unsafe" -gt 0 ]] && report LOW "$rm_unsafe 'unsafe' line(s) removed since baseline — verify the migration is sound"
else
    echo "  (no unsafe-block diff)"
fi

# 3. Cargo.toml dep additions
echo
echo "── Cargo.toml dependency additions ──"
cargo_diff=$(cd "$SOURCE" && git diff "$BASELINE_REF" HEAD -- '**/Cargo.toml' 2>/dev/null \
             | grep -E '^\+[a-zA-Z0-9_-]+ *=' || true)
if [[ -n "$cargo_diff" ]]; then
    add_count=$(echo "$cargo_diff" | wc -l | tr -d ' ')
    report MEDIUM "$add_count new dependency line(s) — run dependency-soundness check on newcomers"
    echo "$cargo_diff" | head -5 | sed 's/^/        /'
    [[ "$add_count" -gt 5 ]] && echo "        ... ($((add_count - 5)) more)"
else
    echo "  (no new dependencies)"
fi

# 4. rust-toolchain.toml bump
echo
echo "── Toolchain bump ──"
tc_diff=$(cd "$SOURCE" && git diff "$BASELINE_REF" HEAD -- 'rust-toolchain.toml' 'rust-toolchain' 2>/dev/null || true)
if [[ -n "$tc_diff" ]]; then
    report LOW "rust-toolchain bumped — re-run Miri full matrix (scripts/run-miri-matrix.sh)"
else
    echo "  (toolchain unchanged)"
fi

# 5. extern "C" additions
echo
echo "── New extern \"C\" blocks ──"
ffi_diff=$(cd "$SOURCE" && git diff "$BASELINE_REF" HEAD -- '*.rs' 2>/dev/null \
           | grep -E '^\+.*extern[[:space:]]+"C"' || true)
if [[ -n "$ffi_diff" ]]; then
    add_count=$(echo "$ffi_diff" | wc -l | tr -d ' ')
    report HIGH "$add_count new extern \"C\" line(s) — re-run Phase 1 RECON + Phase 2 FFI bucket"
else
    echo "  (no new FFI surfaces)"
fi

# 6. loom symbol additions
echo
echo "── New loom:: symbol use ──"
loom_diff=$(cd "$SOURCE" && git diff "$BASELINE_REF" HEAD -- '*.rs' 2>/dev/null \
            | grep -E '^\+.*loom::' || true)
if [[ -n "$loom_diff" ]]; then
    add_count=$(echo "$loom_diff" | wc -l | tr -d ' ')
    report HIGH "$add_count new loom:: symbol use(s) — author/refresh a loom model for the new primitive"
else
    echo "  (no new loom symbols)"
fi

# 7. cargo audit fresh advisories
echo
echo "── RustSec advisories ──"
if command -v cargo-audit >/dev/null 2>&1; then
    audit_out=$(cd "$SOURCE" && cargo audit --quiet 2>&1 || true)
    # grep -cE returns 0 on no-match (with exit 1); use || true and trim to a single int
    vulns=$(printf '%s\n' "$audit_out" | grep -cE '^(error|Crate):' 2>/dev/null || true)
    vulns="${vulns:-0}"
    vulns="${vulns//[^0-9]/}"   # strip anything not a digit
    vulns="${vulns:-0}"
    if [[ "$vulns" -gt 0 ]]; then
        report HIGH "$vulns RustSec advisory hit(s) — see cargo audit output"
        echo "$audit_out" | head -10 | sed 's/^/        /'
    else
        echo "  (cargo audit clean)"
    fi
else
    report LOW "cargo-audit not installed — install with: cargo install cargo-audit"
fi

# ── Summary
echo
echo "═══ drift-monitor summary ═══"
echo "  HIGH:   $HIGH"
echo "  MEDIUM: $MEDIUM"
echo "  LOW:    $LOW"

if [[ "$HIGH" -gt 0 ]]; then
    echo
    echo "RECOMMENDATION: schedule a spot-audit (1–3 h) for the HIGH-severity drift items."
    echo "Pre-Phase-1 archetype: re-detect via preflight-smoke-test.sh; the new partition"
    echo "may differ from the baseline run."
    exit 1
elif [[ "$MEDIUM" -gt 0 ]]; then
    echo
    echo "RECOMMENDATION: dependency-soundness check on new deps; routine spot-audit not"
    echo "required unless the new deps touch unsafe surface."
    exit 1
fi

echo
echo "No HIGH/MEDIUM drift since baseline."
exit 0
