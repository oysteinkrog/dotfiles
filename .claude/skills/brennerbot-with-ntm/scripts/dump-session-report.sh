#!/usr/bin/env bash
# dump-session-report.sh — Phase-by-phase pass/fail + unresolved-thread inventory.
#
# Usage:
#   dump-session-report.sh [--workspace=<path>]              # human-readable report
#   dump-session-report.sh --emit-resume [--workspace=<path>] [--qor-hash=...] [--corpus-hash=...] [--disagreement-hash=...] [--beads-head=...] [--checkpoint-archive=...] [--checkpoint-id=...] [--session=...]
#                                                              # emit RESUME.md.draft

# shellcheck disable=SC2016 # jq programs are single-quoted intentionally.
set -uo pipefail

# Portable sha256: GNU/Linux ships `sha256sum`; macOS/BSD ships `shasum -a 256`.
# The output format is the same — `<hash> <space> <space|*> <filename>` — so
# downstream `awk '{print $1}'` continues to extract just the hash. The repo
# otherwise dispatches GNU/BSD differences (stat, date), so doing the same here
# keeps the script runnable on operator macOS hosts.
sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$@"
  else
    shasum -a 256 "$@"
  fi
}

WORKSPACE="."
EMIT_RESUME="false"
QOR_HASH=""
CORPUS_HASH=""
DISAGREEMENT_HASH=""
BEADS_HEAD=""
CHECKPOINT_ARCHIVE=""
CHECKPOINT_ID=""
SESSION=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace=*) WORKSPACE="${1#*=}" ;;
    --emit-resume) EMIT_RESUME="true" ;;
    --qor-hash=*) QOR_HASH="${1#*=}" ;;
    --corpus-hash=*) CORPUS_HASH="${1#*=}" ;;
    --disagreement-hash=*) DISAGREEMENT_HASH="${1#*=}" ;;
    --beads-head=*) BEADS_HEAD="${1#*=}" ;;
    --checkpoint-archive=*) CHECKPOINT_ARCHIVE="${1#*=}" ;;
    --checkpoint-id=*) CHECKPOINT_ID="${1#*=}" ;;
    --session=*) SESSION="${1#*=}" ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
  shift
done

WORKSPACE_INPUT="$WORKSPACE"
if ! WORKSPACE="$(cd "$WORKSPACE_INPUT" 2>/dev/null && pwd)"; then
  echo "workspace not accessible: $WORKSPACE_INPUT" >&2
  exit 1
fi
cd "$WORKSPACE" || { echo "workspace not accessible: $WORKSPACE" >&2; exit 1; }
command -v br >/dev/null 2>&1 || { echo "br CLI not found" >&2; exit 3; }
command -v jq >/dev/null 2>&1 || { echo "jq not found" >&2; exit 3; }

count_beads_by() {
  local label="$1" status="${2:-}"
  # Use an array rather than a space-separated string so a label/status that
  # ever contained whitespace wouldn't silently merge into a single arg.
  local -a args=("--label=$label")
  [ -n "$status" ] && args+=("--status=$status")
  br list "${args[@]}" --json 2>/dev/null | jq '.issues | length' 2>/dev/null || echo 0
}

count_hypotheses_by_state() {
  local state="$1"
  br list --label=hypothesis --json 2>/dev/null \
    | jq --arg state "$state" '[.issues[]? | select((.description // "") | test("(^|\\n)state:[[:space:]]*" + $state + "([[:space:]]|$)"))] | length' 2>/dev/null || echo 0
}

emit_rows_or_empty_list() {
  local filter="$1" result
  result=$(jq -r "$filter" 2>/dev/null)
  if [ -n "$result" ]; then
    printf '%s\n' "$result"
  else
    echo "  []"
  fi
}

emit_resume_open_threads() {
  local result
  result=$(
    {
      br list --label=hypothesis --status=open --json 2>/dev/null | jq -r '
        .issues[]?
        | (((.description // "") | capture("(^|\\n)state:[[:space:]]*(?<x>\\w+)")? | .x) // "open") as $state
        | select($state == "active" or $state == "proposed" or $state == "deferred")
        | (.external_ref // "") as $external_ref
        | (try ((.title // "") | capture("^(?<ref>H-[0-9]+):").ref) catch "") as $title_ref
        | (if $external_ref != "" then $external_ref elif $title_ref != "" then $title_ref else .id end) as $bead_ref
        | "  - bead: \($bead_ref)\n    state: \($state)\n    next_action: \"FILL IN\"\n    owner_pane: null"
      ' 2>/dev/null
      br list --label=evidence --status=open --json 2>/dev/null | jq -r '
        .issues[]?
        | select((.description // "") | test("(^|\\n)verified:[[:space:]]*false([[:space:]]|$)"))
        | (.external_ref // "") as $external_ref
        | (try ((.title // "") | capture("^(?<ref>EV-[0-9]+):").ref) catch "") as $title_ref
        | (if $external_ref != "" then $external_ref elif $title_ref != "" then $title_ref else .id end) as $bead_ref
        | "  - bead: \($bead_ref)\n    state: unverified\n    next_action: \"FILL IN\"\n    owner_pane: null"
      ' 2>/dev/null
    } | sed '/^[[:space:]]*$/d'
  )
  if [ -n "$result" ]; then
    printf '%s\n' "$result"
  else
    echo "  []"
  fi
}

last_contiguous_phase_completed() {
  local n last=0
  for n in 1 2 3 4 5 6 7 8 9 10; do
    if [ -f "$WORKSPACE/.brenner_workspace/phase_${n}_complete.flag" ]; then
      last=$n
    else
      break
    fi
  done
  printf '%s\n' "$last"
}

emit_resume() {
  # Extract session id from phase0_scope_decision.md heading: "# Phase 0 Scope Decision — RS-..."
  local SESSION_ID_FALLBACK="${SESSION:-$(grep -m1 -oE 'RS-[0-9]{8}-[a-z0-9-]+' "$WORKSPACE/.brenner_workspace/phase0_scope_decision.md" 2>/dev/null || echo 'RS-UNKNOWN')}"
  cat <<EOF
# RESUME.md draft — emitted by dump-session-report.sh at $(date -u +%Y-%m-%dT%H:%M:%SZ)
#
# Operator: review and add free-text fields (session_label, next_loop_recommendation.reason, open_threads[].next_action),
# then promote to RESUME.md.

\`\`\`yaml
session_id: $SESSION_ID_FALLBACK
session_label: <FILL IN: one-line label>
mode_to_resume: fresh-pass
last_phase_completed: $(last_contiguous_phase_completed)
created_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)
operator_signature: <FILL IN>

question_of_record_path: intake/question_of_record.md
question_of_record_hash: $QOR_HASH

corpus_index_path: corpus/corpus_index.md
corpus_index_hash: $CORPUS_HASH

# Top-level mirror so resume-session.sh's parse_field can verify it via the
# same root-level lookup it uses for question_of_record_hash and corpus_index_hash.
# Same value as distillations.disagreement_register.hash below.
disagreement_register_hash: $DISAGREEMENT_HASH

beads_head_sha: $BEADS_HEAD
ntm_checkpoint_archive: $CHECKPOINT_ARCHIVE
ntm_checkpoint_id: $CHECKPOINT_ID

distillations:
  per_model:
$(for F in "$WORKSPACE"/distillations/by_*.md; do
  [ -f "$F" ] || continue
  M=$(basename "$F" .md | sed 's/^by_//')
  H=$(sha256 "$F" | awk '{print $1}')
  echo "    - by: $M"
  echo "      path: distillations/by_$M.md"
  echo "      hash: $H"
done)
  meta:
    path: distillations/meta_synthesis.md
    hash: $(sha256 "$WORKSPACE/distillations/meta_synthesis.md" 2>/dev/null | awk '{print $1}')
  disagreement_register:
    path: distillations/disagreement_register.md
    hash: $DISAGREEMENT_HASH

roster: <FILL IN: extract from phase0_scope_decision.md>

agent_mail:
  available: true
  threads_open: <FILL IN>

open_threads:
$(emit_resume_open_threads)

audit_findings_open:
$(br list --label=audit-finding --status=open --json 2>/dev/null | emit_rows_or_empty_list '.issues[]? | (((.description // "") | capture("(^|\\n)severity:[[:space:]]*(?<x>\\w+)")? | .x) // "unknown") as $sev | (((.description // "") | capture("(^|\\n)target_artifact:[[:space:]]*(?<x>[^\\n]+)")? | .x) // "<FILL IN>") as $target | (.external_ref // "") as $external_ref | (try ((.title // "") | capture("^(?<ref>AF-[0-9]+):").ref) catch "") as $title_ref | (if $external_ref != "" then $external_ref elif $title_ref != "" then $title_ref else .id end) as $af_ref | "  - id: \($af_ref)\n    severity: \($sev)\n    target: \($target)\n    next_action: \"FILL IN\""')

next_loop_recommendation:
  phase: <FILL IN: 4 | 6 | 7 | 10 | none-converged>
  duration_estimate_hours: <FILL IN>
  reason: "<FILL IN>"

resume_token_version: 1.0
\`\`\`
EOF
}

if [ "$EMIT_RESUME" = "true" ]; then
  emit_resume
  exit 0
fi

# Otherwise, human-readable report
echo "=== brennerbot-with-ntm session report ==="
echo "Workspace: $WORKSPACE"
echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

# Phase flags
echo "Phase completion flags:"
for N in 1 2 3 4 5 6 7 8 9 10; do
  flag="$WORKSPACE/.brenner_workspace/phase_${N}_complete.flag"
  if [ -f "$flag" ]; then
    echo "  Phase $N: ✓ ($(cat "$flag"))"
  else
    echo "  Phase $N: ✗"
  fi
done

# Bead counts
echo ""
echo "Bead inventory:"
echo "  Hypotheses (active):    $(count_hypotheses_by_state active)"
echo "  Hypotheses (refuted):   $(count_hypotheses_by_state refuted)"
echo "  Hypotheses (confirmed): $(count_hypotheses_by_state confirmed)"
echo "  Evidence:               $(count_beads_by evidence)"
echo "  Tests:                  $(count_beads_by test)"
echo "  Assumptions:            $(count_beads_by assumption)"
echo "  Anomalies:              $(count_beads_by anomaly)"
echo "  Critiques:              $(count_beads_by critique)"
echo "  Debates:                $(count_beads_by debate)"
echo "  Distillations:          $(count_beads_by distillation)"
echo "  Audit findings (open):  $(count_beads_by audit-finding open)"

# Artifact presence
echo ""
echo "Required artifacts:"
for ART in \
  "intake/question_of_record.md" \
  "corpus/corpus_index.md" \
  "distillations/meta_synthesis.md" \
  "distillations/disagreement_register.md" \
  "deliverables/RESUME.md" \
  "deliverables/HANDBACK.md" \
  "deliverables/DRIFT-CHECK.md"; do
  if [ -f "$WORKSPACE/$ART" ]; then
    echo "  ✓ $ART"
  else
    echo "  ✗ $ART"
  fi
done

# Per-model distillations
echo ""
echo "Per-model distillations:"
for F in "$WORKSPACE"/distillations/by_*.md; do
  [ -f "$F" ] && echo "  ✓ $(basename "$F")"
done

# Bead invariant violations
echo ""
echo "Bead invariant violations:"
if [ -x "$SCRIPT_DIR/audit-bead-invariants.sh" ]; then
  "$SCRIPT_DIR/audit-bead-invariants.sh" --all --workspace="$WORKSPACE" 2>/dev/null | head -20
else
  echo "  (audit-bead-invariants.sh not available)"
fi

echo ""
echo "Workspace OK." >&2
