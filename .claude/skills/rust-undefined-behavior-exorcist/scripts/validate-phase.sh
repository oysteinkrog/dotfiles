#!/usr/bin/env bash
# validate-phase.sh — run the per-phase gates documented in VALIDATION.md.
#
# Usage:
#   validate-phase.sh <workspace> <phase-number>
#   validate-phase.sh <workspace> all          # run every phase that has a phase0_run.json present
#
# Workspace MUST be inside <source>/.ub-exorcism/<run-id>/ (same contract as
# the other gate scripts in this skill).
#
# Exit codes:
#   0 — every mechanizable gate passed (qualitative gates surfaced as MANUAL but not blocking)
#   1 — at least one mechanizable gate failed
#   2 — usage error / workspace invalid / phase number out of range / missing dep
#
# The script is a faithful mechanization of VALIDATION.md's per-phase checklists.
# Qualitative gates (those requiring human judgment, like "Partition posted to
# user before Phase 1 fan-out") are reported as [MANUAL] but do NOT count against
# the exit status — the orchestrator surfaces them to the user for explicit
# attestation.
set -euo pipefail

case "${1:-}" in
    -h|--help)
        awk 'NR>1 && /^#/{sub(/^# ?/, ""); print; next} NR>1{exit}' "$0"
        exit 0
        ;;
esac

if [[ $# -ne 2 ]]; then
    echo "Usage: validate-phase.sh <workspace> <phase-number|all>" >&2
    exit 2
fi

WORKSPACE="$1"
PHASE="$2"

if ! command -v jq >/dev/null 2>&1; then
    echo "jq not installed (required for toolchain-inventory + dep-cycles parsing)." >&2
    echo "Install via apt/brew/dnf." >&2
    exit 2
fi

# ── Canonicalize workspace + source ────────────────────────────────────────
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
SOURCE="${WORKSPACE%%/.ub-exorcism/*}"

if [[ ! -d "$WORKSPACE" ]]; then
    echo "Workspace dir not found: $WORKSPACE" >&2
    exit 2
fi
if [[ ! -f "$SOURCE/Cargo.toml" ]]; then
    echo "Source has no Cargo.toml: $SOURCE" >&2
    exit 2
fi

# ── Counters ───────────────────────────────────────────────────────────────
declare -i PASS=0 FAIL=0 MANUAL=0

pass()   { PASS=$((PASS+1)); printf '  [✓] %s\n' "$1"; }
fail()   { FAIL=$((FAIL+1)); printf '  [✗] %s\n' "$1"; }
manual() { MANUAL=$((MANUAL+1)); printf '  [?] MANUAL: %s\n' "$1"; }

# Test that a file exists and is non-empty.
file_nonempty() {
    local f="$1" desc="$2"
    if [[ -s "$WORKSPACE/$f" ]]; then pass "$desc ($f)"; else fail "$desc ($f) — missing or empty"; fi
}

# Test that `grep -c PATTERN FILE` returns 0 (i.e., NO matches).
grep_count_zero() {
    local pat="$1" file="$2" desc="$3"
    if [[ ! -f "$WORKSPACE/$file" ]]; then fail "$desc — file $file missing"; return; fi
    local c
    c=$(grep -cE "$pat" "$WORKSPACE/$file" 2>/dev/null || true)
    if [[ "$c" -eq 0 ]]; then pass "$desc"; else fail "$desc — $c match(es) in $file"; fi
}

# Test a jq predicate on a JSON file.
jq_assert() {
    local file="$1" predicate="$2" desc="$3"
    if [[ ! -f "$WORKSPACE/$file" ]]; then fail "$desc — file $file missing"; return; fi
    if jq -e "$predicate" "$WORKSPACE/$file" >/dev/null 2>&1; then
        pass "$desc"
    else
        fail "$desc — predicate failed on $file"
    fi
}

# ── Per-phase gates ────────────────────────────────────────────────────────

phase_0() {
    echo "── Phase 0: Bootstrap gates ──"
    file_nonempty "phase0_toolchain_inventory.json" "Toolchain inventory captured"
    # Required tools all 'status:ok' AND 'smoke_test_passed:yes' (or user-accepted degraded)
    if [[ -f "$WORKSPACE/phase0_toolchain_inventory.json" ]]; then
        local bad
        bad=$(jq -r '
            .tools // {} |
            to_entries |
            map(select(.value.status != "ok" or .value.smoke_test_passed != "yes")) |
            length
        ' "$WORKSPACE/phase0_toolchain_inventory.json" 2>/dev/null || echo "0")
        if [[ "$bad" -eq 0 ]]; then
            pass "Every toolchain entry is status:ok AND smoke_test_passed:yes"
        else
            manual "Toolchain has $bad degraded entry/entries (user must explicitly accept)"
        fi
    fi
    file_nonempty "preflight_smoke.json" "Preflight smoke ran"
    if [[ -f "$WORKSPACE/preflight_smoke.json" ]]; then
        jq_assert "preflight_smoke.json" '.failed_count == 0' "Preflight failed_count == 0"
    fi
    file_nonempty "phase0_partition.json" "Partition persisted"
    manual "Partition table confirmed by user BEFORE Phase 1 fan-out"
}

phase_1() {
    echo "── Phase 1: RECON gates ──"
    file_nonempty "phase1_unsafe_surface_inventory.md" "Unsafe-surface inventory written"
    # Inventory has ≥1 row per discovered site
    if [[ -f "$WORKSPACE/phase1_unsafe_surface_inventory.md" ]]; then
        local rows
        # grep -c writes "0" to stdout even when it exits non-zero on no-match,
        # so `|| echo "0"` would concatenate to "0\n0" and break the integer
        # test below. Use `|| true` + default-substitute the empty-file case.
        rows=$(grep -cE '^\| F-[0-9]+' "$WORKSPACE/phase1_unsafe_surface_inventory.md" 2>/dev/null || true)
        rows="${rows:-0}"
        if [[ "$rows" -gt 0 ]]; then
            pass "Inventory has $rows F-NNN row(s)"
        else
            fail "Inventory has zero F-NNN rows"
        fi
    fi
    # Each partition section has a digest
    if [[ -f "$WORKSPACE/phase0_partition.json" && -d "$WORKSPACE/phase1_notes" ]]; then
        local missing=0
        for section in $(jq -r '.sections[]?.id // empty' "$WORKSPACE/phase0_partition.json" 2>/dev/null); do
            if [[ ! -s "$WORKSPACE/phase1_notes/$section.md" ]]; then
                missing=$((missing+1))
                fail "Phase1 digest missing: phase1_notes/$section.md"
            fi
        done
        [[ "$missing" -eq 0 ]] && pass "Every partition section has a phase1_notes digest"
    else
        manual "Per-section phase1_notes/<section>.md (couldn't auto-check without phase0_partition.json)"
    fi
    manual "Main agent posted per-section summary + asked user if any section needs re-research"
}

phase_2() {
    echo "── Phase 2: STATIC SWEEP gates ──"
    # Every bucket subagent produced a findings file
    local hits
    hits=$(find "$WORKSPACE" -maxdepth 1 -name 'phase2_findings_*.md' 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$hits" -gt 0 ]]; then
        pass "$hits phase2_findings_<bucket>.md file(s) present"
    else
        fail "No phase2_findings_<bucket>.md files found"
    fi
    file_nonempty "phase2_summary.md" "phase2_summary.md rollup written"
    manual "Findings cross-reference back to phase1 F-NNN rows"
}

phase_3() {
    echo "── Phase 3: DYNAMIC SWEEP gates ──"
    file_nonempty "phase3_dynamic_findings.md" "Dynamic findings written"
    # Raw tool output captured
    if [[ -d "$WORKSPACE/phase3_raw" ]]; then
        local raw_count
        raw_count=$(find "$WORKSPACE/phase3_raw" -name '*.log' 2>/dev/null | wc -l | tr -d ' ')
        if [[ "$raw_count" -gt 0 ]]; then
            pass "$raw_count raw tool log(s) in phase3_raw/"
        else
            fail "phase3_raw/ exists but contains no .log files"
        fi
    else
        fail "phase3_raw/ directory missing"
    fi
    # Each scheduled axis has either a verdict line or an explicit SKIPPED-with-rationale
    if [[ -f "$WORKSPACE/phase3_dynamic_findings.md" ]]; then
        local missing_verdict
        missing_verdict=$(grep -cE '^- (PASS|FAIL|SKIPPED)' "$WORKSPACE/phase3_dynamic_findings.md" 2>/dev/null || true)
        missing_verdict="${missing_verdict:-0}"
        if [[ "$missing_verdict" -gt 0 ]]; then
            pass "phase3_dynamic_findings has $missing_verdict per-axis verdict line(s)"
        else
            manual "phase3_dynamic_findings.md lacks per-axis verdict lines (verify manually)"
        fi
    fi
    # Miri axis differ ran (free signal)
    if [[ -f "$WORKSPACE/phase3_raw/miri_axis_diff.md" ]]; then
        pass "Miri axis-differ ran (phase3_raw/miri_axis_diff.md present)"
    else
        manual "Miri axis differ not yet run (./scripts/miri-axis-differ.sh \"\$WORKSPACE\")"
    fi
}

phase_4() {
    echo "── Phase 4: SYNTHESIS gates ──"
    file_nonempty "phase4_unified_findings.md" "Unified findings table written"
    file_nonempty "UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md" "Experiment registry written"

    # Every OPEN finding has ≥1 experiment
    if [[ -f "$WORKSPACE/phase4_unified_findings.md" && -f "$WORKSPACE/UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md" ]]; then
        local findings exps diff_count
        findings=$(grep -oE '^## F-[0-9]+' "$WORKSPACE/phase4_unified_findings.md" 2>/dev/null | sort -u || true)
        exps=$(grep -oE 'Finding ref:\*\* F-[0-9]+' "$WORKSPACE/UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md" 2>/dev/null | awk '{print $NF}' | sort -u || true)
        # awk is used instead of `grep -c '^<' || echo "0"` because the latter
        # combined with pipefail concatenates both outputs when the upstream
        # `diff` exits non-zero (different inputs → diff exits 1 → pipeline exit 1
        # → `|| echo "0"` runs alongside the already-captured grep count, yielding
        # "N\n0" which then fails the integer test below).
        diff_count=$(diff <(echo "$findings") <(awk '{print "## " $0}' <<< "$exps") 2>/dev/null \
                     | awk '/^</ {n++} END {print n+0}')
        if [[ "$diff_count" -eq 0 ]]; then
            pass "Every F-NNN has ≥1 EXP entry"
        else
            fail "$diff_count F-NNN without EXP coverage"
        fi
    fi
}

phase_5() {
    echo "── Phase 5: EXPERIMENT EXECUTION gates ──"
    grep_count_zero '\*\*Verdict:\*\* OPEN' \
        "UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md" \
        "No OPEN verdicts remain"
    file_nonempty "phase5_round_summary.md" "phase5_round_summary.md written"
    # Per-experiment logs
    if [[ -d "$WORKSPACE/phase5_experiment_results" ]]; then
        local log_count
        log_count=$(find "$WORKSPACE/phase5_experiment_results" -name '*.log' | wc -l | tr -d ' ')
        if [[ "$log_count" -gt 0 ]]; then
            pass "$log_count per-experiment log(s) in phase5_experiment_results/"
        else
            fail "phase5_experiment_results/ has no .log files"
        fi
    else
        fail "phase5_experiment_results/ directory missing"
    fi
}

phase_6() {
    echo "── Phase 6: IDEA-WIZARD gates (multi-round) ──"
    # Detect mode from phase0_run.json (default to Standard = 2 rounds)
    local mode rounds
    mode="Standard"
    if [[ -f "$WORKSPACE/phase0_run.json" ]]; then
        mode=$(jq -r '.mode // "Standard"' "$WORKSPACE/phase0_run.json" 2>/dev/null || echo "Standard")
    fi
    if [[ "$mode" == "Exhaustive" ]]; then rounds=3; else rounds=2; fi
    pass "Mode detected: $mode → expecting $rounds round(s)"
    # Each round file exists
    for r in $(seq 1 "$rounds"); do
        file_nonempty "phase6_idea_wizard_round_${r}.md" "Round $r idea-wizard output"
    done
    file_nonempty "phase6_idea_wizard_rollup.md" "Rollup across rounds"
    # No "TBD" verdicts in any round
    for r in $(seq 1 "$rounds"); do
        if [[ -f "$WORKSPACE/phase6_idea_wizard_round_${r}.md" ]]; then
            grep_count_zero 'TBD|UNDECIDED' "phase6_idea_wizard_round_${r}.md" "Round $r — no TBD verdicts"
        fi
    done
}

phase_7() {
    echo "── Phase 7: CONVERGENCE gates ──"
    local round_files
    mapfile -t round_files < <(find "$WORKSPACE" -maxdepth 1 -name 'phase7_convergence_round_*.json' | sort -V)
    if [[ "${#round_files[@]}" -lt 2 ]]; then
        fail "Need at least 2 convergence round files (got ${#round_files[@]})"
        return
    fi
    pass "${#round_files[@]} convergence round file(s) found"
    # Last two rounds must both be quiet
    local last="${round_files[-1]}"
    local prev="${round_files[-2]}"
    if jq -e '.quiet == true' "$last" >/dev/null 2>&1 && jq -e '.quiet == true' "$prev" >/dev/null 2>&1; then
        pass "Last 2 rounds are both quiet (convergence)"
    else
        fail "Last 2 rounds not both quiet"
    fi
    # Round count meets archetype floor
    local archetype
    archetype=$(jq -r '.archetype // ""' "$WORKSPACE/phase0_run.json" 2>/dev/null || true)
    case "$archetype" in
        forbid_unsafe|pure_safe) floor=3 ;;
        forbid_unsafe_exhaustive) floor=5 ;;
        *)                       floor=10 ;;
    esac
    if [[ "${#round_files[@]}" -ge "$floor" ]]; then
        pass "Round count ${#round_files[@]} ≥ archetype floor $floor"
    else
        fail "Round count ${#round_files[@]} < archetype floor $floor for archetype '$archetype'"
    fi
}

phase_8() {
    echo "── Phase 8: REMEDIATION DESIGN gates ──"
    file_nonempty "phase8_remediation_plan.md" "Remediation plan written"
    if [[ -f "$WORKSPACE/phase8_remediation_plan.md" ]]; then
        # Each remediation has ≥1 candidate AND a runner-up
        local rems chosen runners
        rems=$(grep -cE '^## R-[0-9]+' "$WORKSPACE/phase8_remediation_plan.md" 2>/dev/null || true)
        chosen=$(grep -cE '^- \*\*Chosen:\*\*' "$WORKSPACE/phase8_remediation_plan.md" 2>/dev/null || true)
        runners=$(grep -cE '^- \*\*Runner-up:\*\*' "$WORKSPACE/phase8_remediation_plan.md" 2>/dev/null || true)
        rems="${rems:-0}"; chosen="${chosen:-0}"; runners="${runners:-0}"
        if [[ "$rems" -gt 0 && "$chosen" -eq "$rems" && "$runners" -eq "$rems" ]]; then
            pass "$rems remediation(s), each with Chosen + Runner-up"
        else
            fail "Remediation plan structure: $rems R-NNN, $chosen Chosen, $runners Runner-up"
        fi
    fi
    manual "Rubric scores present and rationale documented"
}

phase_9() {
    echo "── Phase 9: BEADS HANDOFF gates ──"
    file_nonempty "phase9_beads_log.md" "Beads log written"
    # `br dep cycles` must be empty (run against source repo)
    # Use --json: text mode prints "✓ No dependency cycles detected." even when
    # clean, so a naive `wc -l` always reports ≥1 and the gate flips false.
    if command -v br >/dev/null 2>&1; then
        local cycles
        cycles=$(cd "$SOURCE" && br dep cycles --json 2>/dev/null \
                 | jq -r '.count // 0' 2>/dev/null || echo "0")
        cycles="${cycles//[^0-9]/}"
        cycles="${cycles:-0}"
        if [[ "$cycles" -eq 0 ]]; then
            pass "br dep cycles empty"
        else
            fail "br dep cycles reports $cycles cycle(s)"
        fi
    else
        manual "br not in PATH; cannot verify dep cycles"
    fi
    # No hedge close-reasons
    if command -v br >/dev/null 2>&1; then
        local hedges
        hedges=$({
            cd "$SOURCE" && br list --status closed --json 2>/dev/null
        } | jq -r '.issues[]? | select(.close_reason // "" | test("Forced close|hedge"; "i")) | .id' \
          | wc -l | tr -d ' ' || true)
        hedges="${hedges//[^0-9]/}"
        hedges="${hedges:-0}"
        if [[ "$hedges" -eq 0 ]]; then
            pass "No hedge close-reasons"
        else
            fail "$hedges bead(s) closed with hedge text"
        fi
    fi
    manual "Every remediation bead has ≥1 test bead dep AND ≥1 docs bead dep"
}

phase_10() {
    echo "── Phase 10: FRESH-EYES REVIEW gates ──"
    file_nonempty "phase10_fresh_eyes_log.md" "Fresh-eyes log written"
    # Each of the 3 prompts ran ≥2x clean (look for round/iter markers)
    if [[ -f "$WORKSPACE/phase10_fresh_eyes_log.md" ]]; then
        local iter_count
        iter_count=$(grep -cE '^### iter|^## iter|^### round|^## round' "$WORKSPACE/phase10_fresh_eyes_log.md" 2>/dev/null || true)
        iter_count="${iter_count:-0}"
        if [[ "$iter_count" -ge 6 ]]; then
            pass "Found $iter_count iter/round markers (≥6 expected for 3 prompts × 2 iters)"
        else
            manual "Only $iter_count iter markers — verify the three prompts each ran ≥2× clean"
        fi
    fi
}

phase_11() {
    echo "── Phase 11: SOAK gates (Exhaustive only) ──"
    local mode="Standard"
    if [[ -f "$WORKSPACE/phase0_run.json" ]]; then
        mode=$(jq -r '.mode // "Standard"' "$WORKSPACE/phase0_run.json" 2>/dev/null || echo "Standard")
    fi
    if [[ "$mode" != "Exhaustive" ]]; then
        pass "Mode is $mode — Phase 11 not required"
        return
    fi
    file_nonempty "phase11_soak_designs.md" "Soak campaign designs written"
    if [[ -d "$WORKSPACE/phase11_artifacts" ]]; then
        local campaigns
        campaigns=$(find "$WORKSPACE/phase11_artifacts" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
        if [[ "$campaigns" -gt 0 ]]; then
            pass "$campaigns soak campaign artifact dir(s)"
        else
            fail "phase11_artifacts/ empty"
        fi
    fi
}

phase_12() {
    echo "── Phase 12: FINAL ARTIFACTS gates ──"
    file_nonempty "FINAL_UB_REPORT.md" "Final UB report written"
    file_nonempty "UB_RUNBOOK.md" "UB runbook written"
    manual "User notified with summary + recommendation"
    manual "Auto-remediation offer made (Phase 13 opt-in prompt fired)"
}

phase_13() {
    echo "── Phase 13: AUTO-REMEDIATION gates (skip if not run) ──"
    if [[ ! -f "$WORKSPACE/phase13_remediation_log.md" ]]; then
        pass "Phase 13 was not run — gates skipped"
        return
    fi
    # All CLOSED-WITH-FIX entries have a matching commit
    local missing_commits=0
    while IFS= read -r bead_id; do
        if ! (cd "$SOURCE" && git log --grep="$bead_id" --oneline 2>/dev/null | grep -q "$bead_id"); then
            fail "CLOSED-WITH-FIX bead $bead_id has no matching commit"
            missing_commits=$((missing_commits+1))
        fi
    done < <(awk '/^## /{id=$2} /^- Outcome: CLOSED-WITH-FIX/{print id}' "$WORKSPACE/phase13_remediation_log.md")
    [[ "$missing_commits" -eq 0 ]] && pass "All CLOSED-WITH-FIX beads have a matching commit"

    # All DEFERRED-NEEDS-HUMAN beads carry the label
    if command -v br >/dev/null 2>&1; then
        local missing_labels=0
        while IFS= read -r bead_id; do
            if ! (cd "$SOURCE" && br show "$bead_id" --json 2>/dev/null \
                  | jq -e '.labels[]? | select(. == "phase13-needs-human-review")' >/dev/null); then
                fail "DEFERRED-NEEDS-HUMAN bead $bead_id missing label"
                missing_labels=$((missing_labels+1))
            fi
        done < <(awk '/^## /{id=$2} /^- Outcome: DEFERRED-NEEDS-HUMAN/{print id}' "$WORKSPACE/phase13_remediation_log.md")
        [[ "$missing_labels" -eq 0 ]] && pass "All DEFERRED-NEEDS-HUMAN beads carry the label"
    fi

    # No destructive git in the reflog since Phase 13 start
    # (awk for the same reason as in phase_4 — `grep -c ... || echo "0"` under
    # pipefail concatenates outputs and breaks the integer test below.)
    local destructive
    destructive=$(cd "$SOURCE" && git reflog 2>/dev/null \
                  | awk '/reset --hard|clean -fd|push --force/ {n++} END {print n+0}')
    if [[ "$destructive" -eq 0 ]]; then
        pass "No destructive git operations in reflog"
    else
        fail "$destructive destructive git operation(s) in reflog"
    fi
}

# ── Dispatch ───────────────────────────────────────────────────────────────
echo "=== validate-phase.sh — workspace=$WORKSPACE phase=$PHASE ==="

run_phase() {
    case "$1" in
        0)  phase_0  ;;
        1)  phase_1  ;;
        2)  phase_2  ;;
        3)  phase_3  ;;
        4)  phase_4  ;;
        5)  phase_5  ;;
        6)  phase_6  ;;
        7)  phase_7  ;;
        8)  phase_8  ;;
        9)  phase_9  ;;
        10) phase_10 ;;
        11) phase_11 ;;
        12) phase_12 ;;
        13) phase_13 ;;
        *)
            echo "Unknown phase number: $1 (expected 0–13 or 'all')" >&2
            exit 2
            ;;
    esac
}

if [[ "$PHASE" == "all" ]]; then
    for p in 0 1 2 3 4 5 6 7 8 9 10 11 12 13; do
        run_phase "$p"
    done
else
    run_phase "$PHASE"
fi

echo
echo "=== Summary: $PASS passed · $FAIL failed · $MANUAL needs manual review ==="

if [[ "$FAIL" -gt 0 ]]; then
    exit 1
fi
exit 0
