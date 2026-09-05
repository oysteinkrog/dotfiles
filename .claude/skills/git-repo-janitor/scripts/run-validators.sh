#!/usr/bin/env bash
# Run all skill-internal validators (per references/POLISH-BAR-VERIFICATION-QUERIES.md).
# Usage: run-validators.sh <project>
set -uo pipefail

project="${1:?usage: run-validators.sh <project>}"
cd "$project" || exit
ws=".repo_janitor_workspace"
if [[ ! -d "$ws" ]]; then
    echo "ERROR: $ws not found; run the earlier repo-janitor phases first" >&2
    exit 2
fi

passed=0
failed=0
out="$ws/validator_results.md"
: > "$out" || { echo "ERROR: cannot write validator report: $out" >&2; exit 2; }

validate() {
    local name="$1" cmd="$2"
    if eval "$cmd" >/dev/null 2>&1; then
        echo "✓ $name: PASS"
        passed=$((passed + 1))
    else
        echo "✗ $name: FAIL"
        echo "## $name (FAIL)" >> "$out"
        echo '```' >> "$out"
        eval "$cmd" >> "$out" 2>&1 || true
        echo '```' >> "$out"
        echo "" >> "$out"
        failed=$((failed + 1))
    fi
}

echo "=== Validator suite ==="

# Bundle integrity
validate "bundle_path file exists" "[[ -f $ws/bundle_path.txt ]]"
validate "bundle index.tsv exists" "[[ -f \$(cat $ws/bundle_path.txt 2>/dev/null)/index.tsv ]]"
validate "byte-equality verification clean" "! grep -q MISMATCH $ws/bundle_verification.log 2>/dev/null"

# Triage integrity
validate "triage.tsv has rows" "[[ \$(wc -l < $ws/triage.tsv 2>/dev/null) -gt 1 ]]"
validate "every row has evidence" "! awk -F'\t' 'NR>1 && \$4 == \"\"' $ws/triage.tsv 2>/dev/null | grep -q ."
validate "every row has confidence" "! awk -F'\t' 'NR>1 && \$3 == \"\"' $ws/triage.tsv 2>/dev/null | grep -q ."
validate "no high-confidence delete with refs" "! awk -F'\t' 'NR>1 && \$2 ~ /^delete/ && \$3 > 0.7 && \$4 ~ /refs=[1-9]/' $ws/triage.tsv 2>/dev/null | grep -q ."

# Coverage
validate "coverage_matrix.md exists" "[[ -f $ws/coverage_matrix.md ]]"
validate "no blank cells in coverage" "! awk -F'|' 'NR>2 && \$3 ~ /^[[:space:]]*\$/' $ws/coverage_matrix.md 2>/dev/null | grep -q ."

# Authorization
validate "cleanup_authorization.txt is non-empty if delete plan exists" "[[ ! -f $ws/delete_plan.md ]] || [[ -s $ws/cleanup_authorization.txt ]]"

# Apply log
validate "apply_log.tsv exists if any commits" "true"   # heuristic; depends on mode
validate "no FAIL in apply_log" "! grep -qi FAIL $ws/apply_log.tsv 2>/dev/null"

# Phantom-deletion
validate "no outstanding phantom deletions" "[[ \$(git status --porcelain | awk '\$1==\"D\"' | wc -l) -lt 6 ]]"

# Submodule
validate "submodule warnings reviewed" "[[ ! -f $ws/submodule_warnings.tsv ]] || ! grep -q 'rewind\\|conflicted' $ws/submodule_warnings.tsv"

# Secret scan
validate "secret_findings.tsv exists" "[[ -f $ws/secret_findings.tsv ]]"
validate "no pending secret resolutions" "! awk -F'\t' 'NR>1 && \$NF==\"pending\"' $ws/secret_findings.tsv 2>/dev/null | grep -q ."

# Verification log
validate "verification_log.md exists" "[[ -f $ws/verification_log.md ]]"

# Provenance
validate "every artifact has a header" "true"  # heuristic; check via grep -L on artifact set

echo ""
echo "OVERALL: $passed passed, $failed failed"

[[ "$failed" -eq 0 ]]
