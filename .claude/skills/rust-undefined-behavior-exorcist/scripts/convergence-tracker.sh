#!/usr/bin/env bash
# convergence-tracker.sh — measure round-over-round new-finding counts.
#
# Usage: convergence-tracker.sh <workspace>
# <workspace> should be <source>/.ub-exorcism/<run-id>/.
#
# Writes <workspace>/phase7_convergence_round_<N>.json and exits:
#   0 — round is "quiet" AND a prior round was also quiet (loop can end)
#   1 — round is quiet but no prior quiet round (continue)
#   2 — round is not quiet (continue)
#  64 — usage / workspace not under .ub-exorcism / synthesis artifacts missing
set -euo pipefail

case "${1:-}" in
    -h|--help)
        sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
esac

if [[ $# -ne 1 ]]; then
    echo "Usage: convergence-tracker.sh <workspace>" >&2
    exit 2
fi

WORKSPACE="$1"

canonicalize_workspace() {
    local workspace_real source_real
    workspace_real="$(realpath -m "$WORKSPACE")"
    case "$workspace_real" in
        */.ub-exorcism/*) ;;
        *)
            echo "Workspace must be inside the audited source repo: <source>/.ub-exorcism/<run-id>" >&2
            echo "Got: $workspace_real" >&2
            exit 64
            ;;
    esac
    source_real="${workspace_real%%/.ub-exorcism/*}"
    source_real="$(realpath -m "$source_real")"
    if [[ ! -f "$source_real/Cargo.toml" ]]; then
        echo "Workspace must be inside a Rust source repo: <source>/.ub-exorcism/<run-id>" >&2
        echo "Expected Cargo.toml at: $source_real/Cargo.toml" >&2
        echo "Got: $workspace_real" >&2
        exit 64
    fi
    case "$workspace_real/" in
        "$source_real"/.ub-exorcism/*) WORKSPACE="$workspace_real" ;;
        *)
            echo "Workspace must be inside the audited source repo: <source>/.ub-exorcism/<run-id>" >&2
            echo "Source: $source_real" >&2
            echo "Got:    $workspace_real" >&2
            exit 64
            ;;
    esac
}

canonicalize_workspace
EXP_FILE="$WORKSPACE/UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md"
FINDINGS_FILE="$WORKSPACE/phase4_unified_findings.md"

[[ -f "$EXP_FILE" ]] || { echo "no $EXP_FILE — run synthesis first" >&2; exit 64; }
[[ -f "$FINDINGS_FILE" ]] || { echo "no $FINDINGS_FILE — run synthesis first" >&2; exit 64; }

# Determine round number from existing convergence files
N=0
for f in "$WORKSPACE"/phase7_convergence_round_*.json; do
    [[ -e "$f" ]] || continue
    r=$(basename "$f" .json | sed 's/.*round_//')
    (( r > N )) && N=$r
done
N=$((N + 1))

# Verdict counts
open=$(grep -c '\*\*Verdict:\*\* OPEN' "$EXP_FILE" || true)
confirmed=$(grep -c '\*\*Verdict:\*\* CONFIRMED_UB' "$EXP_FILE" || true)
no_evidence=$(grep -c '\*\*Verdict:\*\* NO_EVIDENCE' "$EXP_FILE" || true)
needs_refinement=$(grep -c '\*\*Verdict:\*\* NEEDS_REFINEMENT' "$EXP_FILE" || true)
deferred=$(grep -c '\*\*Verdict:\*\* DEFERRED' "$EXP_FILE" || true)

# New-findings count: diff against the previous round's snapshot
SNAP_NEW="$WORKSPACE/phase7_findings_snapshot_round_${N}.txt"
SNAP_PREV="$WORKSPACE/phase7_findings_snapshot_round_$((N - 1)).txt"
grep -oE '^## F-[0-9]+' "$FINDINGS_FILE" | sort -u > "$SNAP_NEW" || true

if [[ -f "$SNAP_PREV" ]]; then
    new_findings=$(comm -23 "$SNAP_NEW" "$SNAP_PREV" | wc -l | tr -d ' ')
else
    new_findings=$(wc -l < "$SNAP_NEW" | tr -d ' ')
fi

# New NEEDS_REFINEMENT count: diff against the previous round's needs-list.
# Walk the file: track the most recent `## EXP-NNN` header, then when we hit a
# NEEDS_REFINEMENT verdict line, record that header. `grep -B1` was wrong here
# because real experiment blocks have description/hypothesis lines between the
# header and the verdict.
NR_NEW="$WORKSPACE/phase7_needs_refinement_round_${N}.txt"
NR_PREV="$WORKSPACE/phase7_needs_refinement_round_$((N - 1)).txt"
awk '
    /^## EXP-/ { current = $0; next }
    /\*\*Verdict:\*\* NEEDS_REFINEMENT/ && current != "" {
        # Extract just the EXP-NNN token
        match(current, /EXP-[0-9A-Za-z-]+/)
        if (RSTART > 0) print "## " substr(current, RSTART, RLENGTH)
        current = ""
    }
' "$EXP_FILE" | sort -u > "$NR_NEW" || true
if [[ -f "$NR_PREV" ]]; then
    new_needs=$(comm -23 "$NR_NEW" "$NR_PREV" | wc -l | tr -d ' ')
else
    new_needs=$(wc -l < "$NR_NEW" | tr -d ' ')
fi

# Quiet condition
quiet=false
if [[ $open -eq 0 && $new_findings -lt 3 && $new_needs -eq 0 ]]; then
    quiet=true
fi

# Was the previous round quiet?
prev_quiet=false
if [[ -f "$WORKSPACE/phase7_convergence_round_$((N - 1)).json" ]]; then
    if grep -q '"quiet": true' "$WORKSPACE/phase7_convergence_round_$((N - 1)).json"; then
        prev_quiet=true
    fi
fi

# Write JSON
OUT="$WORKSPACE/phase7_convergence_round_${N}.json"
cat > "$OUT" <<JSON
{
  "round": $N,
  "verdicts": {
    "OPEN": $open,
    "CONFIRMED_UB": $confirmed,
    "NO_EVIDENCE": $no_evidence,
    "NEEDS_REFINEMENT": $needs_refinement,
    "DEFERRED": $deferred
  },
  "new_findings": $new_findings,
  "new_needs_refinement": $new_needs,
  "quiet": $quiet,
  "prev_quiet": $prev_quiet
}
JSON

cat "$OUT"

if [[ "$quiet" == "true" && "$prev_quiet" == "true" && $N -ge 10 ]]; then
    echo
    echo "CONVERGED after round $N (≥10 rounds, two consecutive quiet)."
    exit 0
elif [[ "$quiet" == "true" ]]; then
    echo
    echo "Round $N quiet. Run another round to confirm convergence."
    exit 1
else
    echo
    echo "Round $N NOT quiet (open=$open, new_findings=$new_findings, new_needs=$new_needs)."
    exit 2
fi
