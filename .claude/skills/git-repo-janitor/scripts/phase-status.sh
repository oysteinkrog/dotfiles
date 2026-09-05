#!/usr/bin/env bash
# Examine .repo_janitor_workspace/ and report which phases have completed,
# which artifacts are present, and what's the next step.
#
# Usage: phase-status.sh <project>
#
# Exits 0 always (this is informational). Outputs Markdown.
set -uo pipefail

project="${1:?usage: phase-status.sh <project>}"
cd "$project" || { echo "ERROR: cannot enter project: $project" >&2; exit 1; }
ws=".repo_janitor_workspace"

if [[ ! -d "$ws" ]]; then
    echo "# Phase status: NOT STARTED"
    echo ""
    echo "No workspace at $ws. The skill has not been run on this project yet."
    echo ""
    echo "Next step: run Quick Start (see SKILL.md), or invoke the skill explicitly."
    exit 0
fi

# Helper: check if a file exists and is non-empty (returns 0 if yes)
exists_nonempty() { [[ -s "$1" ]]; }
# Helper: check if a file exists at all (may be empty)
exists() { [[ -e "$1" ]]; }
# Helper: emit a status row
row() {
    local marker="$1" label="$2" detail="${3:-}"
    if [[ -n "$detail" ]]; then
        printf '  %s %-42s %s\n' "$marker" "$label" "$detail"
    else
        printf '  %s %s\n' "$marker" "$label"
    fi
}

echo "# Phase status for $project"
echo ""
echo "Workspace: $ws"
date_str=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo "Checked at: $date_str"
echo ""

# Phase 0 / 0.5 — bootstrap
echo "## Phase 0 / 0.5 — Bootstrap"
exists_nonempty "$ws/project_profile.json" \
    && row "✓" "project_profile.json" "$(jq -r '.archetype // "?"' "$ws/project_profile.json" 2>/dev/null)" \
    || row "✗" "project_profile.json" "MISSING (run discover-project.sh)"
exists_nonempty "$ws/verification_log.md" \
    && row "✓" "verification_log.md" \
    || row "✗" "verification_log.md" "MISSING (run verify-git-version.sh)"
exists_nonempty "$ws/phase0_skill_inventory.json" \
    && row "✓" "phase0_skill_inventory.json" \
    || row "○" "phase0_skill_inventory.json" "(optional; check-skills.sh)"
exists_nonempty "$ws/phase0_scope_decision.md" \
    && row "✓" "phase0_scope_decision.md" \
    || row "○" "phase0_scope_decision.md" "(scope-decide.sh)"
echo ""

# Phase 1 / 1.5 — profile + safety
echo "## Phase 1 / 1.5 — Profile + safety"
exists "$ws/phantom_deletions.tsv" \
    && row "✓" "phantom_deletions.tsv" "$(tail -n +2 "$ws/phantom_deletions.tsv" 2>/dev/null | wc -l) phantoms" \
    || row "○" "phantom_deletions.tsv" "(detect-phantom-deletions.sh)"
exists "$ws/submodule_warnings.tsv" \
    && row "✓" "submodule_warnings.tsv" "$(tail -n +2 "$ws/submodule_warnings.tsv" 2>/dev/null | wc -l) issues" \
    || row "○" "submodule_warnings.tsv" "(detect-submodule-issues.sh; only if .gitmodules)"
echo ""

# Phase 2 / 2.5 — inventory + secret scan + coverage
echo "## Phase 2 / 2.5 — Inventory + secret scan"
exists_nonempty "$ws/candidates.tsv" \
    && row "✓" "candidates.tsv" "$(tail -n +2 "$ws/candidates.tsv" 2>/dev/null | wc -l) candidates" \
    || row "✗" "candidates.tsv" "MISSING (run inventory-candidates.sh)"
exists_nonempty "$ws/reference_graph.json" \
    && row "✓" "reference_graph.json" \
    || row "○" "reference_graph.json" "(inventory-agent subagent)"
exists "$ws/secret_findings.tsv" \
    && row "✓" "secret_findings.tsv" "$(tail -n +2 "$ws/secret_findings.tsv" 2>/dev/null | wc -l) secrets" \
    || row "✗" "secret_findings.tsv" "MISSING (Phase 2.5 is non-negotiable)"
exists_nonempty "$ws/coverage_matrix.md" \
    && row "✓" "coverage_matrix.md" \
    || row "○" "coverage_matrix.md" "(coverage-mapper subagent)"
echo ""

# Phase 3 — bundle
echo "## Phase 3 — Recovery bundle"
if exists_nonempty "$ws/bundle_path.txt"; then
    bundle_path=$(cat "$ws/bundle_path.txt")
    if [[ -d "$bundle_path" ]]; then
        bundle_files=$(find "$bundle_path/working-tree-copies" -type f 2>/dev/null | wc -l)
        row "✓" "bundle_path.txt" "$bundle_path ($bundle_files copies)"
    else
        row "✗" "bundle_path.txt" "$bundle_path (DIR MISSING)"
    fi
else
    row "✗" "bundle_path.txt" "MISSING (run build-bundle.sh)"
fi
exists_nonempty "$ws/bundle_verification.log" \
    && row "✓" "bundle_verification.log" "$(grep -c '^.*OK' "$ws/bundle_verification.log" 2>/dev/null || echo 0) verified" \
    || row "✗" "bundle_verification.log" "MISSING (run verify-bundle.sh — Phase 3 GATE)"
echo ""

# Phase 4 / 4.5 — triage
echo "## Phase 4 / 4.5 — Triage"
if [[ -d "$ws/triage" ]]; then
    batch_count=$(ls "$ws"/triage/batch_*.tsv 2>/dev/null | wc -l)
    row "✓" "triage/" "$batch_count batches"
else
    row "○" "triage/" "(triage-worker subagents)"
fi
exists_nonempty "$ws/triage.tsv" \
    && row "✓" "triage.tsv" "$(tail -n +2 "$ws/triage.tsv" 2>/dev/null | wc -l) verdicts" \
    || row "○" "triage.tsv" "(merge-triage.sh)"
echo ""

# Phase 5 — merge & confirm
echo "## Phase 5 — Plan & confirm (USER GATE)"
exists_nonempty "$ws/move_plan.md" \
    && row "✓" "move_plan.md" \
    || row "○" "move_plan.md"
exists_nonempty "$ws/delete_plan.md" \
    && row "✓" "delete_plan.md" \
    || row "○" "delete_plan.md"
exists_nonempty "$ws/gitignore_plan.md" \
    && row "✓" "gitignore_plan.md" \
    || row "○" "gitignore_plan.md"
exists "$ws/user_overrides.tsv" \
    && row "✓" "user_overrides.tsv" \
    || row "○" "user_overrides.tsv"
echo ""

# Phase 6 / 7 / 8 — apply
echo "## Phase 6 / 7 / 8 — Apply (mutation phases)"
exists "$ws/apply_log.tsv" \
    && row "✓" "apply_log.tsv" "$(tail -n +2 "$ws/apply_log.tsv" 2>/dev/null | wc -l) ops" \
    || row "○" "apply_log.tsv"
exists "$ws/reference_rewrite_log.tsv" \
    && row "✓" "reference_rewrite_log.tsv" "$(tail -n +2 "$ws/reference_rewrite_log.tsv" 2>/dev/null | wc -l) rewrites" \
    || row "○" "reference_rewrite_log.tsv"
exists_nonempty "$ws/cleanup_authorization.txt" \
    && row "✓" "cleanup_authorization.txt" \
    || row "○" "cleanup_authorization.txt" "(required if Phase 7 ran)"
echo ""

# Phase 9 / 10 — verify + handoff
echo "## Phase 9 / 10 — Fresh-eyes + handoff"
exists_nonempty "$ws/fresh_eyes_log.md" \
    && row "✓" "fresh_eyes_log.md" "$(grep -c '^### Round' "$ws/fresh_eyes_log.md" 2>/dev/null || echo 0) rounds" \
    || row "○" "fresh_eyes_log.md"
exists_nonempty "$ws/handoff_report.md" \
    && row "✓" "handoff_report.md" \
    || row "○" "handoff_report.md"
echo ""

# Suggested next step
echo "## Suggested next step"
if ! exists_nonempty "$ws/project_profile.json"; then
    echo "  → Phase 0.5: bootstrap (see SKILL.md § Skill Bootstrap)"
elif ! exists_nonempty "$ws/candidates.tsv"; then
    echo "  → Phase 2: run inventory-candidates.sh"
elif ! exists "$ws/secret_findings.tsv"; then
    echo "  → Phase 2.5: run leak-scanner subagent"
elif ! exists_nonempty "$ws/bundle_path.txt"; then
    echo "  → Phase 3: run build-bundle.sh + verify-bundle.sh (HARD GATE)"
elif ! exists_nonempty "$ws/triage.tsv"; then
    echo "  → Phase 4: run triage-worker subagents in parallel"
elif ! exists_nonempty "$ws/move_plan.md" && ! exists_nonempty "$ws/delete_plan.md"; then
    echo "  → Phase 5: run triage-merger subagent (USER GATE follows)"
elif ! exists "$ws/apply_log.tsv"; then
    echo "  → Phase 6: run move-applier (after user OK on Phase 5 plan)"
elif ! exists_nonempty "$ws/fresh_eyes_log.md"; then
    echo "  → Phase 9: run fresh-eyes subagent for ≥2 rounds"
elif ! exists_nonempty "$ws/handoff_report.md"; then
    echo "  → Phase 10: run handoff-reporter subagent"
else
    echo "  → All artifacts present. Run: bash \$SKILL/scripts/polish-bar-check.sh \"\$PROJECT\""
fi
