#!/usr/bin/env bash
# Phase 0.5: emit phase0_scope_decision.md skeleton from interview log + project profile.
# Usage: scope-decide.sh <project>
set -euo pipefail

project="${1:?usage: scope-decide.sh <project>}"
cd "$project"
ws=".repo_janitor_workspace"
mkdir -p "$ws"

profile="$ws/project_profile.json"
interview="$ws/interview_log.md"
out="$ws/phase0_scope_decision.md"

archetype="unknown"
mode="full"
file_count=0

if [[ -f "$profile" ]]; then
    if command -v jq >/dev/null 2>&1; then
        archetype=$(jq -r '.archetype // "unknown"' "$profile")
    fi
fi

file_count=$(git ls-files | wc -l)

# Compute tier
tier="T1"
if   (( file_count > 100000 )); then tier="T5"
elif (( file_count > 20000 )); then tier="T4"
elif (( file_count > 1000 )); then tier="T3"
elif (( file_count > 100 )); then tier="T2"
else tier="T1"
fi

# Complexity overlay
complexity=0
[[ -f .gitmodules ]] && complexity=$((complexity + 1))
if command -v git-lfs >/dev/null 2>&1; then
    if [[ -n "$(git lfs ls-files 2>/dev/null | head -1)" ]]; then
        complexity=$((complexity + 1))
    fi
fi
gitignore_lines=0
if [[ -f .gitignore ]]; then
    gitignore_lines=$(wc -l < .gitignore 2>/dev/null || echo 0)
fi
[[ "$gitignore_lines" -gt 200 ]] && complexity=$((complexity + 1))

cat > "$out" <<EOF
## Phase 0 Scope Decision — $(basename "$project") $(date -u +%Y-%m-%d)

**Mode:** ${MODE:-$mode}
**Tier:** $tier ($file_count tracked files) + $complexity complexity points
**Archetype:** $archetype
**Run intent:** ${INTENT:-"<one-line intent from interview Stage 1>"}

### REQUIRED (always run for this mode)
- [ ] Phase 0 — confirm inputs
- [ ] Phase 0.5 — skill bootstrap; this scope decision
- [ ] Phase 1 — project profile + archetype + branch policy
- [ ] Phase 2 — candidate inventory + reference graph
- [ ] Phase 2.5 — secret scan (NON-NEGOTIABLE per Axiom 15)
- [ ] Phase 3 — recovery bundle + byte-equality verify
- [ ] Phase 4 — triage with verdicts
- [ ] Phase 5 — categorized plan + user confirm

### CONDITIONAL (will run if applicable)
- [ ] Phase 6 — moves (only if move plan non-empty)
- [ ] Phase 7 — deletes (only if delete plan non-empty AND verbatim auth received)
- [ ] Phase 8 — gitignore (only if gitignore plan non-empty)
- [ ] Phase 9 — fresh-eyes (per mode rules)
- [ ] Phase 10 — handoff

### CONDITIONAL-SKIPPED
- [ ] Phase 9 fresh-eyes round 3 (T2 default; user can opt in)
- [ ] Phase 11 user-lens review (skipped unless user explicitly asks)

### NOT DOING (explicit exclusions)
- [ ] (filled in based on interview Stage 1+2 + MEMORY.md + AGENTS.md)

### CONDITIONAL BUNDLES
$(case "$archetype" in
  single-rust-crate)
    cat <<-BUNDLES
- [x] core_smells (always)
- [x] secret_smells (always; Phase 2.5)
- [x] rust_artifact_smells
- [x] sqlite_smells (rust often has dev DBs)
- [x] planning_doc_smells
- [ ] python_cache_smells (no Python detected)
- [ ] node_modules_smells (no Node detected)
- [ ] go_test_artifact_smells (no Go detected)
BUNDLES
    ;;
  claude-skill-repo)
    cat <<-BUNDLES
- [x] core_smells (always)
- [x] secret_smells (always; Phase 2.5)
- [x] agent_tooling_smells
- [x] planning_doc_smells
- [x] progress_report_smells
- [x] multi_llm_plan_smells
- [ ] rust_artifact_smells (typically)
- [ ] python_cache_smells (typically)
- [ ] node_modules_smells (typically)
BUNDLES
    ;;
  polyglot-monorepo)
    cat <<-BUNDLES
- [x] core_smells (always)
- [x] secret_smells (always; Phase 2.5)
- [x] (per-subtree language smells; populated after Phase 2)
- [x] planning_doc_smells
BUNDLES
    ;;
  *)
    echo "- [x] core_smells (always)"
    echo "- [x] secret_smells (always; Phase 2.5)"
    ;;
esac)

### ESTIMATED SCOPE
- Wall time: \$(estimate based on tier)
- Candidates: ~\$(scripts/inventory-candidates.sh "$project" --preview | wc -l) (preview)
- Recovery commits: estimate based on plan
- Reference rewrites: estimate based on Phase 4
- User attention required: \$gates count

### ESCALATION POSSIBILITIES
This run COULD escalate to:
- \`harden-secret-leak\` (if Phase 2.5 finds a real secret)
- \`triage-only\` (if Phase 4 finds 200+ broken refs in move plan)
- \`recover-from-bad-cleanup\` (if Phase 6 build breaks repeatedly)
- \`batch\` (if user asks for multi-repo)

If any escalation triggers, I will halt and ask before proceeding.

EOF

echo "scope decision written to $out"
echo "Review and edit before running Phase 1."
