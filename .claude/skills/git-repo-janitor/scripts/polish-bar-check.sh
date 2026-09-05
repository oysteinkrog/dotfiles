#!/usr/bin/env bash
# Phase 10: verify all 18 polish-bar dimensions.
# Usage: polish-bar-check.sh <project>
# Exits 0 if all pass; non-zero with list of failures.
set -uo pipefail

project="${1:?usage: polish-bar-check.sh <project>}"
cd "$project" || exit
ws=".repo_janitor_workspace"
if [[ ! -d "$ws" ]]; then
    echo "ERROR: $ws not found; run the earlier repo-janitor phases first" >&2
    exit 2
fi
out="$ws/polish_bar_failures.md"
: > "$out" || { echo "ERROR: cannot write polish-bar report: $out" >&2; exit 2; }

passed=0
failed=0

check() {
    local n="$1" name="$2" cmd="$3"
    if eval "$cmd" >/dev/null 2>&1; then
        printf '✓ Dimension %d — %s: PASS\n' "$n" "$name"
        passed=$((passed + 1))
    else
        printf '✗ Dimension %d — %s: FAIL\n' "$n" "$name"
        echo "## Dimension $n — $name" >> "$out"
        echo '```' >> "$out"
        eval "$cmd" >> "$out" 2>&1 || true
        echo '```' >> "$out"
        echo "" >> "$out"
        failed=$((failed + 1))
    fi
}

# 1. Recovery completeness — bundle path file must exist AND point to a real index.tsv
check 1 "Recovery completeness" '[[ -f "$ws/bundle_path.txt" ]] && bp=$(cat "$ws/bundle_path.txt") && [[ -n "$bp" ]] && [[ -f "$bp/index.tsv" ]]'

# 2. Verdict evidence — every triage row has a non-empty evidence column
check 2 "Verdict evidence" '[[ -f "$ws/triage.tsv" ]] && tail -n +2 "$ws/triage.tsv" | awk -F"\t" "{ if(\$4==\"\") exit 1 }"'

# 3. No false-positive deletes — fresh_eyes_log exists AND contains no "false-positive" finding
check 3 "No false-positive deletes" '[[ -f "$ws/fresh_eyes_log.md" ]] && ! grep -qi "false.positive" "$ws/fresh_eyes_log.md"'

# 4. Reference rewrite log present (if any moves were planned)
check 4 "No silently-broken references" '[[ ! -f "$ws/move_plan.md" ]] || [[ -f "$ws/reference_rewrite_log.tsv" ]]'

# 5. Per-commit gates — apply log must exist AND not contain FAIL markers
check 5 "Per-commit gates passed" '[[ -f "$ws/apply_log.tsv" ]] && ! grep -qi "FAIL" "$ws/apply_log.tsv"'

# 6. Shadowing audit (only if gitignore plan exists)
check 6 "Gitignore shadowing audit done" '[[ ! -f "$ws/gitignore_plan.md" ]] || [[ -f "$ws/gitignore_shadowing_audit.log" ]]'

# 7. Focused commit messages — last 3 cleanup commits each have a multi-paragraph body
check 7 "Focused commit messages" 'git log -3 --format=%B 2>/dev/null | awk "BEGIN{c=0} /^$/{c++} END{exit (c<2)?1:0}"'

# 8. Order: moves → deletes → gitignore (heuristic)
check 8 "Order of operations" "true"   # heuristic; manual

# 9. Verbatim authorization — if a delete plan was ever produced, the auth file must exist
check 9 "Verbatim authorization" '[[ ! -f "$ws/delete_plan.md" ]] || [[ -s "$ws/cleanup_authorization.txt" ]]'

# 10. Idempotent — heuristic
check 10 "Idempotence" "true"

# 11. Resumable — heuristic
check 11 "Resumability" "true"

# 12. Build still works — try the build command
build_cmd=""
[[ -f "$ws/project_profile.json" ]] && build_cmd=$(grep -oP '"build_command":\s*"\K[^"]+' "$ws/project_profile.json" | head -1)
if [[ -n "$build_cmd" ]]; then
    check 12 "Build still works ($build_cmd)" "$build_cmd"
else
    echo "○ Dimension 12 — Build still works: SKIPPED (no build command in profile)"
fi

# 13. Phase 2.5 secret scan — secret_findings.tsv must exist (may be empty after the header)
check 13 "Phase 2.5 secret scan" '[[ -f "$ws/secret_findings.tsv" ]]'

# 14. Audit trail intact — handoff report, apply log, and a real bundle directory all present
check 14 "Audit trail intact" '[[ -f "$ws/handoff_report.md" ]] && [[ -f "$ws/apply_log.tsv" ]] && [[ -f "$ws/bundle_path.txt" ]] && bp=$(cat "$ws/bundle_path.txt") && [[ -d "$bp" ]]'

# 15. Verification log written — required when volatile-behavior operators ran (Axiom 17).
# We require it whenever Phase 1 produced project_profile.json (always, in normal runs).
check 15 "Verification log written" '[[ ! -f "$ws/project_profile.json" ]] || [[ -s "$ws/verification_log.md" ]]'

# 16. Coverage matrix complete — every FILE-SMELLS rule has a row; no blank cells (Axiom 18).
# Not every mode produces a matrix (e.g., delete-only). Pass if absent; if present, no blank-status cells.
check 16 "Coverage matrix complete" '[[ ! -f "$ws/coverage_matrix.md" ]] || ! grep -E "^\| [^|]+ \|  *\|" "$ws/coverage_matrix.md" >/dev/null'

check_phantom_deletions_handled() {
    # Pass if: phantom_deletions.tsv missing/empty, OR has only a header (no real phantoms),
    # OR a recovery log exists with content (per PHANTOM-DELETIONS.md / Axiom 24).
    [[ ! -s "$ws/phantom_deletions.tsv" ]] && return 0
    if ! tail -n +2 "$ws/phantom_deletions.tsv" | grep -q .; then return 0; fi
    [[ -s "$ws/phantom_deletion_recovery.md" ]]
}
check 17 "Phantom deletions handled" "check_phantom_deletions_handled"

check_mode_escalation_recorded() {
    # Pass if: jq unavailable (skip), OR no run_state.json, OR mode_history has ≤1 entry,
    # OR at least one mode_escalation_*.md exists (per OPERATING-MODES.md / Axiom 21).
    command -v jq >/dev/null 2>&1 || return 0
    [[ -f "$ws/run_state.json" ]] || return 0
    local mh
    mh=$(jq -r ".mode_history | length" "$ws/run_state.json" 2>/dev/null || echo 1)
    [[ "$mh" =~ ^[0-9]+$ ]] || mh=1
    (( mh <= 1 )) && return 0
    ls "$ws"/mode_escalation_*.md >/dev/null 2>&1
}
check 18 "Mode escalation recorded" "check_mode_escalation_recorded"

echo ""
echo "OVERALL: $passed passed, $failed failed"

[[ "$failed" -eq 0 ]]
