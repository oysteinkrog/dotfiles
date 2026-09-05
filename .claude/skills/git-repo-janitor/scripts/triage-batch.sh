#!/usr/bin/env bash
# Phase 4: triage one batch (range of candidate ids).
# Usage: triage-batch.sh <project> <batch-num> <start-id> <end-id>
set -euo pipefail

project="${1:?usage: triage-batch.sh <project> <batch-num> <start-id> <end-id>}"
batch="${2:?missing batch-num}"
start="${3:?missing start-id}"
end="${4:?missing end-id}"

cd "$project"
ws=".repo_janitor_workspace"
out="$ws/triage/batch_$(printf '%03d' $batch).tsv"
mkdir -p "$ws/triage"

# Header
printf 'id\tverdict\tconfidence\tevidence\tproposed_dest\tgitignore_pattern\n' > "$out"

# This script intentionally produces a "stub" verdict for each candidate;
# the LLM-driven triage-worker subagent does the actual reasoning.
# This script is for batch partitioning + simple-rule cases only.

while IFS=$'\t' read -r id blob_sha path size mtime smell first_sha; do
    [[ "$id" == "id" ]] && continue
    [[ -z "$id" ]] && continue
    # Force base-10 interpretation so leading zeros (e.g., "010") don't become octal.
    id_num=$((10#$id))
    if (( id_num < start )) || (( id_num > end )); then
        continue
    fi

    # Simple-rule defaults (can be overridden by the subagent)
    verdict="surface-to-user"
    confidence="0.5"
    evidence="smell=$smell"
    dest=""
    pat=""

    # Easy auto-classifications
    case "$smell" in
        *secret-suspect*) verdict="surface-to-user"; confidence="0.6"; evidence="$evidence;Phase 2.5 review needed" ;;
        *binary-elf*|*binary-mach-o*|*binary-pe*) verdict="delete-no-gitignore"; confidence="0.95"; evidence="$evidence;file-magic match" ;;
        *0-byte-stub*) verdict="delete-no-gitignore"; confidence="0.85"; evidence="$evidence;0-byte file" ;;
        *nohup-leak*) verdict="delete-and-gitignore"; confidence="0.97"; pat="nohup.out" ;;
        *skill-output*|*dot-pre-skill-state*) verdict="delete-and-gitignore"; confidence="0.95"; pat=".skill-loop-progress.md" ;;
        *sqlite-db*) verdict="delete-and-gitignore"; confidence="0.92"; pat="/storage*.sqlite3*" ;;
        *sqlite-wal-shm*) verdict="delete-and-gitignore"; confidence="0.95"; pat="/storage*.sqlite3*" ;;
        *editor-backup*) verdict="delete-and-gitignore"; confidence="0.96"; pat="*.bak" ;;
        *progress-report*) verdict="move"; confidence="0.85"; dest="docs/progress/" ;;
        *planning-doc*) verdict="move"; confidence="0.82"; dest="docs/planning/" ;;
        *audit-report*) verdict="move"; confidence="0.78"; dest="docs/audits/" ;;
        *reference-doc*|*txt-architecture-summary*) verdict="move"; confidence="0.78"; dest="docs/reference/" ;;
        *runbook-or-recovery*) verdict="move"; confidence="0.78"; dest="docs/operations/" ;;
        *visualization-script*) verdict="move"; confidence="0.85"; dest="scripts/visualization/" ;;
        *deploy-script*) verdict="move"; confidence="0.85"; dest="scripts/" ;;
        *coverage-output*) verdict="delete-and-gitignore"; confidence="0.93"; pat="coverage*.txt" ;;
        *random-jsonl-artifact*) verdict="delete-no-gitignore"; confidence="0.85" ;;
        *format-patch-blob*) verdict="delete-no-gitignore"; confidence="0.92" ;;
        *scratch-script*) verdict="surface-to-user"; confidence="0.65"; evidence="$evidence;needs ref-grep" ;;
        *multi-llm-plan-cluster*) verdict="move"; confidence="0.88"; dest="docs/planning/" ;;
    esac

    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$verdict" "$confidence" "$evidence" "$dest" "$pat" >> "$out"
done < "$ws/candidates.tsv"

echo "batch $batch ($start..$end) → $out"
