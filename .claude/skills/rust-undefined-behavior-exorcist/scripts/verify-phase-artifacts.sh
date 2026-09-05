#!/usr/bin/env bash
# verify-phase-artifacts.sh — after a parallel fan-out completes, verify that
# every declared output file actually exists on disk and is non-empty.
#
# Subagents occasionally complete WITHOUT producing the file they were told to
# write (wrong subagent_type=Explore, transient tool failure, OOM during write,
# etc.) The subagent may even return text that LOOKS like the file content but
# never persists it. This script is the orchestrator's safety net.
#
# Usage:
#   verify-phase-artifacts.sh <workspace> <phase-number>
#
# Workspace must be inside <source>/.ub-exorcism/<run-id>/.
#
# Exit codes:
#   0 — every declared output for this phase exists and is non-empty
#   1 — at least one declared output is missing or empty (specific path listed)
#   2 — usage error / workspace invalid / unknown phase / missing dep
set -euo pipefail

case "${1:-}" in
    -h|--help)
        awk 'NR>1 && /^#/{sub(/^# ?/, ""); print; next} NR>1{exit}' "$0"
        exit 0
        ;;
esac

if [[ $# -ne 2 ]]; then
    echo "Usage: verify-phase-artifacts.sh <workspace> <phase-number>" >&2
    exit 2
fi
WORKSPACE="$1"
PHASE="$2"

if ! command -v jq >/dev/null 2>&1; then
    echo "jq not installed (required for partition + buckets parsing)." >&2
    echo "Install via apt/brew/dnf." >&2
    exit 2
fi

WORKSPACE_REAL="$(realpath -m "$WORKSPACE")"
case "$WORKSPACE_REAL" in
    */.ub-exorcism/*) ;;
    *)
        echo "Workspace must be inside <source>/.ub-exorcism/<run-id>" >&2
        echo "Got: $WORKSPACE_REAL" >&2
        exit 2
        ;;
esac
WORKSPACE="$WORKSPACE_REAL"

declare -i MISSING=0 OK=0

require_file() {
    local rel="$1" desc="$2"
    local abs="$WORKSPACE/$rel"
    if [[ -s "$abs" ]]; then
        printf '  [✓] %s — %s\n' "$rel" "$desc"
        OK=$((OK+1))
    else
        printf '  [✗] %s — %s — MISSING or empty\n' "$rel" "$desc" >&2
        MISSING=$((MISSING+1))
    fi
}

require_glob_nonempty() {
    local pattern="$1" desc="$2"
    local hits
    hits=$(find "$WORKSPACE" -maxdepth 2 -path "$WORKSPACE/$pattern" 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$hits" -gt 0 ]]; then
        printf '  [✓] %-50s — %s (%d file(s))\n' "$pattern" "$desc" "$hits"
        OK=$((OK+1))
    else
        printf '  [✗] %-50s — %s — NO MATCHING FILES\n' "$pattern" "$desc" >&2
        MISSING=$((MISSING+1))
    fi
}

# Read partition sections from phase0_run.json or phase0_partition.json
read_sections() {
    local f
    for f in "$WORKSPACE/phase0_partition.json" "$WORKSPACE/phase0_run.json"; do
        if [[ -f "$f" ]]; then
            jq -r '.sections[]?.id // empty' "$f" 2>/dev/null && return 0
        fi
    done
    # Fall back to scanning phase1_notes/ for filenames if no partition file
    if [[ -d "$WORKSPACE/phase1_notes" ]]; then
        find "$WORKSPACE/phase1_notes" -maxdepth 1 -name '*.md' -exec basename {} .md \;
    fi
}

read_buckets() {
    local f
    for f in "$WORKSPACE/phase0_partition.json" "$WORKSPACE/phase0_run.json"; do
        if [[ -f "$f" ]]; then
            jq -r '.applicable_buckets[]? // empty' "$f" 2>/dev/null && return 0
        fi
    done
}

read_mode() {
    if [[ -f "$WORKSPACE/phase0_run.json" ]]; then
        jq -r '.mode // "Standard"' "$WORKSPACE/phase0_run.json" 2>/dev/null
    else
        echo "Standard"
    fi
}

echo "=== verify-phase-artifacts — workspace=$WORKSPACE phase=$PHASE ==="

case "$PHASE" in
    0)
        require_file "phase0_run.json"                "Run metadata"
        require_file "phase0_partition.json"          "Partition table"
        require_file "phase0_toolchain_inventory.json" "Toolchain inventory"
        require_file "preflight_smoke.json"           "Preflight smoke report"
        ;;
    1)
        require_file "phase1_unsafe_surface_inventory.md" "Unified inventory"
        while IFS= read -r section; do
            [[ -z "$section" ]] && continue
            if [[ ! -s "$WORKSPACE/phase1_notes/$section.md" ]]; then
                printf '  [✗] phase1_notes/%s.md — section digest MISSING\n' "$section" >&2
                MISSING=$((MISSING+1))
            else
                printf '  [✓] phase1_notes/%s.md — section digest\n' "$section"
                OK=$((OK+1))
            fi
        done < <(read_sections)
        ;;
    2)
        found_any=0
        while IFS= read -r bucket; do
            [[ -z "$bucket" ]] && continue
            require_file "phase2_findings_${bucket}.md" "Bucket $bucket findings"
            found_any=1
        done < <(read_buckets)
        if [[ "$found_any" -eq 0 ]]; then
            # No applicable_buckets metadata — fall back to "≥1 phase2_findings_*.md exists"
            require_glob_nonempty 'phase2_findings_*.md' "At least one bucket findings file"
        fi
        require_file "phase2_summary.md" "Phase 2 summary rollup"
        ;;
    3)
        require_file "phase3_dynamic_findings.md" "Dynamic findings table"
        if [[ ! -d "$WORKSPACE/phase3_raw" ]]; then
            printf '  [✗] phase3_raw/ — directory MISSING\n' >&2
            MISSING=$((MISSING+1))
        else
            raw_logs=$(find "$WORKSPACE/phase3_raw" -name '*.log' | wc -l | tr -d ' ')
            if [[ "$raw_logs" -gt 0 ]]; then
                printf '  [✓] phase3_raw/ — %d raw tool log(s)\n' "$raw_logs"
                OK=$((OK+1))
            else
                printf '  [✗] phase3_raw/ — no .log files\n' >&2
                MISSING=$((MISSING+1))
            fi
        fi
        ;;
    4)
        require_file "phase4_unified_findings.md"      "Unified findings (deduped, severity-ranked)"
        require_file "UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md" "Experiment registry v1"
        ;;
    5)
        if [[ ! -d "$WORKSPACE/phase5_experiment_results" ]]; then
            printf '  [✗] phase5_experiment_results/ — directory MISSING\n' >&2
            MISSING=$((MISSING+1))
        else
            exp_logs=$(find "$WORKSPACE/phase5_experiment_results" -name '*.log' | wc -l | tr -d ' ')
            if [[ "$exp_logs" -gt 0 ]]; then
                printf '  [✓] phase5_experiment_results/ — %d experiment log(s)\n' "$exp_logs"
                OK=$((OK+1))
            else
                printf '  [✗] phase5_experiment_results/ — no .log files\n' >&2
                MISSING=$((MISSING+1))
            fi
        fi
        require_file "phase5_round_summary.md" "Phase 5 round summary"
        # Per-experiment repros under experiments/
        if [[ -d "$WORKSPACE/experiments" ]]; then
            repro_count=$(find "$WORKSPACE/experiments" -name 'repro.rs' | wc -l | tr -d ' ')
            if [[ "$repro_count" -gt 0 ]]; then
                printf '  [✓] experiments/ — %d repro.rs file(s)\n' "$repro_count"
                OK=$((OK+1))
            else
                printf '  [✗] experiments/ — 0 repro.rs file(s); Phase 5 cannot run without reproducers\n' >&2
                MISSING=$((MISSING+1))
            fi
        else
            printf '  [✗] experiments/ — directory MISSING\n' >&2
            MISSING=$((MISSING+1))
        fi
        ;;
    6)
        mode=$(read_mode)
        rounds=2
        [[ "$mode" == "Exhaustive" ]] && rounds=3
        for r in $(seq 1 "$rounds"); do
            require_file "phase6_idea_wizard_round_${r}.md" "Round $r"
        done
        require_file "phase6_idea_wizard_rollup.md" "Rollup across rounds"
        ;;
    7)
        require_glob_nonempty 'phase7_convergence_round_*.json' "Convergence round JSONs"
        ;;
    8)
        require_file "phase8_remediation_plan.md" "Remediation plan"
        ;;
    9)
        require_file "phase9_beads_log.md" "Beads handoff log"
        ;;
    10)
        require_file "phase10_fresh_eyes_log.md" "Fresh-eyes review log"
        ;;
    11)
        mode=$(read_mode)
        if [[ "$mode" == "Exhaustive" ]]; then
            require_file "phase11_soak_designs.md" "Soak campaign designs"
            if [[ ! -d "$WORKSPACE/phase11_artifacts" ]]; then
                printf '  [✗] phase11_artifacts/ — directory MISSING\n' >&2
                MISSING=$((MISSING+1))
            else
                campaigns=$(find "$WORKSPACE/phase11_artifacts" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
                printf '  [✓] phase11_artifacts/ — %d campaign dir(s)\n' "$campaigns"
                OK=$((OK+1))
            fi
        else
            printf '  [✓] Mode=%s — Phase 11 artifacts not required\n' "$mode"
            OK=$((OK+1))
        fi
        ;;
    12)
        require_file "FINAL_UB_REPORT.md" "Final UB report"
        require_file "UB_RUNBOOK.md"      "UB runbook"
        ;;
    13)
        if [[ -f "$WORKSPACE/phase13_remediation_log.md" ]]; then
            printf '  [✓] phase13_remediation_log.md — Phase 13 was run; log present\n'
            OK=$((OK+1))
        else
            printf '  [✓] No phase13_remediation_log.md — Phase 13 was not run (OK; Phase 13 is opt-in)\n'
            OK=$((OK+1))
        fi
        ;;
    *)
        echo "Unknown phase number: $PHASE (expected 0–13)" >&2
        exit 2
        ;;
esac

echo
echo "=== Summary: $OK present · $MISSING missing ==="

if [[ "$MISSING" -gt 0 ]]; then
    echo
    echo "RESCUE: when a declared output is missing, the subagent may still have"
    echo "produced the content as response text. Check the subagent's last message"
    echo "and transcribe it into the expected file before re-running."
    exit 1
fi
exit 0
