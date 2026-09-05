#!/usr/bin/env bash
# Walk tracked files; emit candidates.tsv with smell tags.
# Usage: inventory-candidates.sh <project> [--preview]
set -euo pipefail

project="${1:?usage: inventory-candidates.sh <project> [--preview]}"
preview="${2:-}"
cd "$project"

# Header
if [[ "$preview" != "--preview" ]]; then
    printf 'id\tblob_sha\tpath_at_HEAD\tsize_bytes\tmtime_iso\tsmell_tags\tfirst_committed_in\n'
fi

# Top-level junk-smell patterns (regex)
toplevel_smells_re='^(.*\.(sqlite|sqlite3|db|db3|sqlite-wal|sqlite-shm|sqlite-journal|sqlite3-wal|sqlite3-shm|db-wal|db-shm|db-journal|bak|swp|swo|orig|rej|patch|profraw|profdata|out|tmp|log|bck\..*)|nohup\.out|\.skill-loop-progress\.md|\.skill-.*-progress\.md|progress\.md|progress_bd-.*\.md|bd-[0-9a-z]+(\.[0-9]+)*\.md|wrangler_version\.txt|.*-version\.txt|test_runner\.rs|test_ptr|test_ptrmap\.c|rust_out|optzst|fix_beads\.sh|script_to_fix_.*\.sh|test\.js|test_.*\.js|test_.*\.c|check_db\.py|find_task\.py|fix_core\.py|fix_engine\.py|refactor_.*\.py|enhance_.*\.py|finalize_.*\.py|restore_.*\.py|reapply_.*\.py|debug_viz\.py|fix_viz_errors\.py|extract_.*\.py|coverage_report\.txt|coverage.*\.txt|coverage.*\.json|findings\.jsonl|ubs_.*\.jsonl|.*_AUDIT_REPORT\.md|.*_REPORT\.md|.*_AUDIT\.md|.*_FINDINGS\.md|MODES_OF_REASONING_.*\.md|AGENT_FRIENDLINESS_REPORT\.md|RESEARCH_FINDINGS\.md|OPPORTUNITY_MATRIX\.md|UPGRADE_LOG\.md|CHANGELOG_AGENT_FRIENDLY\.md|TOON_INTEGRATION_BRIEF\.md|PERFORMANCE_.*\.md|PERF_OPTIMIZATION_.*\.md|BENCHMARK_COMPARISON_.*\.md|BENCHMARKS\.md|COMPREHENSIVE_.*\.md|PROPOSED_.*\.md|PLAN_TO_.*\.md|PLAN_FOR_.*\.md|EXISTING_.*_STRUCTURE.*\.md|.*_SPECIFICATION\.md|MVCC_SPECIFICATION\.md|RICH_INTEGRATION_PLAN\.md|UNIT_INVARIANT_MATRIX\.md|FEATURE_PARITY\.md|RECOVERY_RUNBOOK\.md|SDK_DROP_IN_DECISION\.md|SECURITY_REVIEW_.*\.md|REVIEW_FINDINGS_.*\.md|CROSS_REVIEW_.*\.md|GOLANG_BEST_PRACTICES\.md|RUST_CLI_TOOLS\.md|SYNC_STRATEGY\.md|STATE_OF_THE_.*\.md|tasks\.md|TODO\.md|E2E_SCENARIO_.*\.md|CONFORMANCE\.md|EXTENSIONS\.md|ANALYSIS_OF_.*\.md|BEAD_AUDIT_REPORT\.md|COVERAGE\.md|.*_ARCHITECTURE_SUMMARY\.txt|SEARCH_PATTERNS_INDEX\.md|QUICK_REFERENCE\.md|.*_SEARCH_PATTERNS\.md|signing-.*\.key|signing-.*\.pub|.*\.pem|id_rsa|id_ed25519|id_ecdsa|id_dsa|.*credentials.*\.json|service-account.*\.json|.*_secret.*|.*-secret-.*|secret_.*|.*\.token|.*_token\.txt|\.env|TESTING\.md|deploy.*\.sh|.*viz.*\.py|.*visual.*\.py|debug_viz\.py)$'

id=0
git ls-files . | while IFS= read -r path; do
    # Check top-level only for the broad patterns; non-top-level usually safe
    is_toplevel=false
    case "$path" in
        */*) is_toplevel=false ;;
        *) is_toplevel=true ;;
    esac

    smell_tags=""

    # Top-level pattern check
    if [[ "$is_toplevel" == "true" ]]; then
        bn=$(basename "$path")
        if [[ "$bn" =~ $toplevel_smells_re ]]; then
            # Tag based on the matched pattern
            case "$bn" in
                *.sqlite|*.sqlite3|*.db|*.db3) smell_tags+="sqlite-db," ;;
                *-wal|*-shm|*-journal|*.sqlite-wal|*.sqlite-shm) smell_tags+="sqlite-wal-shm," ;;
                nohup.out) smell_tags+="nohup-leak," ;;
                .skill-*-progress.md|.skill-loop-progress.md) smell_tags+="skill-output,dot-pre-skill-state," ;;
                progress.md|progress_bd-*.md|bd-*.md) smell_tags+="progress-report," ;;
                *.bak|*~|*.swp|*.swo|*.orig|*.rej|*.bck.*) smell_tags+="editor-backup," ;;
                *.patch) smell_tags+="format-patch-blob," ;;
                *.profraw|*.profdata|coverage*.txt|coverage*.json|coverage_report.*|lcov.info) smell_tags+="coverage-output," ;;
                findings.jsonl|ubs_*.jsonl) smell_tags+="random-jsonl-artifact," ;;
                *_REPORT.md|*_AUDIT_REPORT.md|*_AUDIT.md|*_FINDINGS.md|MODES_OF_REASONING_*.md|RESEARCH_FINDINGS.md|AGENT_FRIENDLINESS_REPORT.md|OPPORTUNITY_MATRIX.md|BEAD_AUDIT_REPORT.md|ANALYSIS_OF_*.md) smell_tags+="agent-output,audit-report," ;;
                COMPREHENSIVE_*.md|PROPOSED_*.md|PLAN_TO_*.md|PLAN_FOR_*.md|EXISTING_*_STRUCTURE*.md|*_SPECIFICATION.md|MVCC_SPECIFICATION.md|RICH_INTEGRATION_PLAN.md|UNIT_INVARIANT_MATRIX.md|FEATURE_PARITY.md|RECOVERY_RUNBOOK.md|SECURITY_REVIEW_*.md|REVIEW_FINDINGS_*.md|CROSS_REVIEW_*.md|SDK_DROP_IN_DECISION.md|STATE_OF_THE_*.md|tasks.md|TODO.md|UPGRADE_LOG.md|CHANGELOG_AGENT_FRIENDLY.md|TOON_INTEGRATION_BRIEF.md|PERFORMANCE_*.md|PERF_OPTIMIZATION_*.md|BENCHMARK_*.md|BENCHMARKS.md|CONFORMANCE.md|EXTENSIONS.md|GOLANG_BEST_PRACTICES.md|RUST_CLI_TOOLS.md|SYNC_STRATEGY.md|TESTING.md|E2E_SCENARIO_*.md|COVERAGE.md|GUIDE.md|*_GUIDE.md|project_idea_and_guide.md) smell_tags+="planning-doc," ;;
                SEARCH_PATTERNS_INDEX.md|QUICK_REFERENCE.md|*_ARCHITECTURE_SUMMARY.txt|*_SEARCH_PATTERNS.md) smell_tags+="reference-doc,txt-architecture-summary," ;;
                signing-*.key|*.pem|id_rsa|id_ed25519|id_ecdsa|id_dsa|*credentials*.json|service-account*.json|*_secret*|*-secret-*|secret_*|*.token|*_token.txt|.env) smell_tags+="secret-suspect," ;;
                check_db.py|find_task.py|fix_*.py|refactor_*.py|enhance_*.py|finalize_*.py|restore_*.py|reapply_*.py|debug_*.py|extract_*.py|fix_beads.sh|script_to_fix_*.sh|test.js|test_*.js|test_*.c|test_runner.rs) smell_tags+="scratch-script," ;;
                *viz.py|*visual.py|*viz_*.py) smell_tags+="visualization-script," ;;
                deploy*.sh) smell_tags+="deploy-script," ;;
                test_ptr|rust_out|optzst|*_test) smell_tags+="binary-elf,compiled-out," ;;
                *.tmp|*.log) smell_tags+="random-artifact," ;;
                multi-llm-plan-marker)
                    : # placeholder
                    ;;
            esac
            # Multi-LLM cluster
            case "$bn" in
                *__GPT.md|*__OPUS.md|*__GEMINI.md|*__CODEX.md|*__CLAUDE_WEB.md|*__GPT_PRO.md|*_ROUND_*__*.md) smell_tags+="multi-llm-plan-cluster," ;;
            esac
            # 0-byte stub
            if [[ -f "$path" ]] && [[ "$(stat -c%s "$path" 2>/dev/null || stat -f%z "$path")" == "0" ]]; then
                smell_tags+="0-byte-stub,"
            fi
        fi
    fi

    # Cross-cutting: anywhere-junky
    case "$path" in
        */__pycache__/*|*.pyc|*.pyo) smell_tags+="python-cache," ;;
        target/*|*/target/*|target_*/*) smell_tags+="rust-build-leakage," ;;
        node_modules/*|*/node_modules/*) smell_tags+="node-modules-leakage," ;;
    esac

    # Magic-byte-based binary detection at top level
    if [[ "$is_toplevel" == "true" ]] && [[ -f "$path" ]]; then
        # Cheap header sniff
        head_bytes=$(head -c4 "$path" 2>/dev/null | od -An -tx1 | tr -d ' \n' || echo "")
        case "$head_bytes" in
            7f454c46) smell_tags+="binary-elf," ;;
            504b0304) smell_tags+="binary-zip," ;;  # zip / docx / jar
            cafebabe|cafefeba|feedface|feedfacf) smell_tags+="binary-mach-o," ;;
        esac
    fi

    smell_tags="${smell_tags%,}"
    [[ -z "$smell_tags" ]] && continue   # skip non-junk

    if [[ "$preview" == "--preview" ]]; then
        echo "$path"
        continue
    fi

    blob_sha=$(git ls-files -s "$path" 2>/dev/null | awk '{print $2}' | head -1 || echo "")
    size=$(stat -c%s "$path" 2>/dev/null || stat -f%z "$path" 2>/dev/null || echo 0)
    raw_mtime=$(stat -c%y "$path" 2>/dev/null || stat -f%Sm -t '%Y-%m-%d %H:%M:%S' "$path" 2>/dev/null || echo "")
    if [[ -n "$raw_mtime" ]]; then
        mtime=$(echo "$raw_mtime" | cut -d' ' -f1-2 | tr ' ' 'T' | cut -c1-19)
        mtime="${mtime}Z"
    else
        mtime=""
    fi
    first_sha=$(git log --diff-filter=A --format='%H' -- "$path" 2>/dev/null | tail -1 || echo "")
    [[ -z "$first_sha" ]] && first_sha=$(git log --format='%H' -- "$path" 2>/dev/null | tail -1 || echo "unknown")
    [[ -z "$first_sha" ]] && first_sha="unknown"

    printf '%03d\t%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$blob_sha" "$path" "$size" "$mtime" "$smell_tags" "$first_sha"
    id=$((id + 1))
done
