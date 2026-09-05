#!/usr/bin/env bash
# parse-resume.sh — Parse RESUME.md into JSON for downstream pipeline use.
#
# Usage: parse-resume.sh --resume=<RESUME.md> [--output=<path>]
#
# Output JSON contains: session_id, mode_to_resume, last_phase_completed,
# next_phase, question_of_record_path, question_of_record_hash,
# corpus_index_path, corpus_index_hash, disagreement_register_hash,
# beads_head_sha, ntm_checkpoint_archive, ntm_checkpoint_id,
# roster (array), open_threads (array).

set -uo pipefail

RESUME=""
OUTPUT="/dev/stdout"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --resume=*) RESUME="${1#*=}" ;;
    --output=*) OUTPUT="${1#*=}" ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
  shift
done

if [ -z "$RESUME" ] || [ ! -f "$RESUME" ]; then
  echo "Error: RESUME.md missing or not specified" >&2
  exit 1
fi
command -v jq >/dev/null 2>&1 || { echo "Error: jq required for JSON emission" >&2; exit 2; }

# Extract single-line scalar fields
get_scalar() {
  awk -v f="$1" '/^'"$1"': / { sub(/^'"$1"': */, ""); print; exit }' "$RESUME" | tr -d '"'
}

SESSION_ID=$(get_scalar session_id)
MODE=$(get_scalar mode_to_resume)
LAST_PHASE=$(get_scalar last_phase_completed)
QOR_PATH=$(get_scalar question_of_record_path)
QOR_HASH=$(get_scalar question_of_record_hash)
CORPUS_PATH=$(get_scalar corpus_index_path)
CORPUS_HASH=$(get_scalar corpus_index_hash)
# Read top-level disagreement_register_hash mirror written by dump-session-report.sh
# and the resume template — this lets the resume pipeline verify it without
# teaching get_scalar to walk nested YAML.
DISAGREEMENT_HASH=$(get_scalar disagreement_register_hash)
BEADS_HEAD=$(get_scalar beads_head_sha)
NTM_ARCHIVE=$(get_scalar ntm_checkpoint_archive)
NTM_ID=$(get_scalar ntm_checkpoint_id)

extract_roster_json() {
  awk '
    function clean(v) {
      sub(/^[[:space:]]*/, "", v)
      sub(/[[:space:]]*$/, "", v)
      if (v ~ /^".*"$/ || v ~ /^\047.*\047$/) v = substr(v, 2, length(v) - 2)
      return v
    }
    function set_field(line, key, val) {
      key = line
      sub(/:.*/, "", key)
      val = line
      sub(/^[^:]*:[[:space:]]*/, "", val)
      key = clean(key)
      val = clean(val)
      if (key == "pane") pane = val
      else if (key == "role") role = val
      else if (key == "model") model = val
      else if (key == "productive_ignorance") productive_ignorance = val
      else if (key == "domain") domain = val
      else if (key == "last_thread") last_thread = val
    }
    function flush() {
      if (have) print enc(pane) "\t" enc(role) "\t" enc(model) "\t" enc(productive_ignorance) "\t" enc(domain) "\t" enc(last_thread)
      pane = role = model = productive_ignorance = domain = last_thread = ""
      have = 0
    }
    function enc(v) { return v == "" ? "__BB_EMPTY__" : v }
    /^roster:/ { in_section = 1; next }
    in_section && /^[[:alnum:]_]+:/ { flush(); exit }
    in_section {
      line = $0
      if (line ~ /^  - /) {
        flush()
        have = 1
        sub(/^  - /, "", line)
        set_field(line)
      } else if (line ~ /^    [[:alnum:]_]+:/) {
        sub(/^    /, "", line)
        set_field(line)
      }
    }
    END { if (in_section) flush() }
  ' "$RESUME" | while IFS=$'\t' read -r pane role model productive_ignorance domain last_thread; do
    [ "$pane" = "__BB_EMPTY__" ] && pane=""
    [ "$role" = "__BB_EMPTY__" ] && role=""
    [ "$model" = "__BB_EMPTY__" ] && model=""
    [ "$productive_ignorance" = "__BB_EMPTY__" ] && productive_ignorance=""
    [ "$domain" = "__BB_EMPTY__" ] && domain=""
    [ "$last_thread" = "__BB_EMPTY__" ] && last_thread=""
    [ -n "$pane$role$model$productive_ignorance$domain$last_thread" ] || continue
    jq -nc \
      --arg pane "$pane" \
      --arg role "$role" \
      --arg model "$model" \
      --arg productive_ignorance "$productive_ignorance" \
      --arg domain "$domain" \
      --arg last_thread "$last_thread" \
      '{
        pane: (if ($pane | test("^[0-9]+$")) then ($pane | tonumber) else $pane end),
        role: $role,
        model: $model,
        productive_ignorance: (if $productive_ignorance == "true" then true elif $productive_ignorance == "false" then false else null end),
        domain: (
          if $domain == "" or $domain == "null" then null
          elif ($domain | startswith("[") and endswith("]")) then
            ($domain | sub("^\\["; "") | sub("\\]$"; "") | split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(. != "")))
          else [$domain]
          end
        ),
        last_thread: $last_thread
      }'
  done | jq -s '.'
}

extract_open_threads_json() {
  awk '
    function clean(v) {
      sub(/^[[:space:]]*/, "", v)
      sub(/[[:space:]]*$/, "", v)
      if (v ~ /^".*"$/ || v ~ /^\047.*\047$/) v = substr(v, 2, length(v) - 2)
      return v
    }
    function set_field(line, key, val) {
      key = line
      sub(/:.*/, "", key)
      val = line
      sub(/^[^:]*:[[:space:]]*/, "", val)
      key = clean(key)
      val = clean(val)
      if (key == "bead") bead = val
      else if (key == "state") state = val
      else if (key == "next_action") next_action = val
      else if (key == "owner_pane") owner_pane = val
    }
    function flush() {
      if (have) print enc(bead) "\t" enc(state) "\t" enc(next_action) "\t" enc(owner_pane)
      bead = state = next_action = owner_pane = ""
      have = 0
    }
    function enc(v) { return v == "" ? "__BB_EMPTY__" : v }
    /^open_threads:/ { in_section = 1; next }
    in_section && /^[[:alnum:]_]+:/ { flush(); exit }
    in_section {
      line = $0
      if (line ~ /^  - /) {
        flush()
        have = 1
        sub(/^  - /, "", line)
        set_field(line)
      } else if (line ~ /^    [[:alnum:]_]+:/) {
        sub(/^    /, "", line)
        set_field(line)
      }
    }
    END { if (in_section) flush() }
  ' "$RESUME" | while IFS=$'\t' read -r bead state next_action owner_pane; do
    [ "$bead" = "__BB_EMPTY__" ] && bead=""
    [ "$state" = "__BB_EMPTY__" ] && state=""
    [ "$next_action" = "__BB_EMPTY__" ] && next_action=""
    [ "$owner_pane" = "__BB_EMPTY__" ] && owner_pane=""
    [ -n "$bead$state$next_action$owner_pane" ] || continue
    jq -nc \
      --arg bead "$bead" \
      --arg state "$state" \
      --arg next_action "$next_action" \
      --arg owner_pane "$owner_pane" \
      '{
        bead: $bead,
        state: $state,
        next_action: $next_action,
        owner_pane: (if $owner_pane == "" or $owner_pane == "null" then null else $owner_pane end)
      }'
  done | jq -s '.'
}

# Derived: next phase = last_phase_completed + 1, capped at 10. Emit it so
# the resume pipeline (brennerbot-resume.yaml) can substitute ${next_phase}
# directly instead of recomputing — the pipeline previously referenced
# ${next_phase} that was neither in inputs nor in this JSON output.
LAST_PHASE_INT="${LAST_PHASE:-0}"
case "$LAST_PHASE_INT" in
  ''|*[!0-9]*) LAST_PHASE_INT=0 ;;  # non-integer fallback
esac
NEXT_PHASE=$((LAST_PHASE_INT + 1))
[ "$NEXT_PHASE" -gt 10 ] && NEXT_PHASE=10

ROSTER_JSON="$(extract_roster_json)"
OPEN_THREADS_JSON="$(extract_open_threads_json)"

# Use jq rather than printf so quoted paths, backslashes, and malformed phase
# text cannot corrupt the JSON record. The section parsers intentionally cover
# the RESUME.md template subset this skill emits: top-level arrays of simple
# key/value maps under roster: and open_threads:.
jq -n \
  --arg session_id "$SESSION_ID" \
  --arg mode_to_resume "$MODE" \
  --argjson last_phase_completed "$LAST_PHASE_INT" \
  --argjson next_phase "$NEXT_PHASE" \
  --arg question_of_record_path "$QOR_PATH" \
  --arg question_of_record_hash "$QOR_HASH" \
  --arg corpus_index_path "$CORPUS_PATH" \
  --arg corpus_index_hash "$CORPUS_HASH" \
  --arg disagreement_register_hash "$DISAGREEMENT_HASH" \
  --arg beads_head_sha "$BEADS_HEAD" \
  --arg ntm_checkpoint_archive "$NTM_ARCHIVE" \
  --arg ntm_checkpoint_id "$NTM_ID" \
  --argjson roster "$ROSTER_JSON" \
  --argjson open_threads "$OPEN_THREADS_JSON" \
  '{
    session_id: $session_id,
    mode_to_resume: $mode_to_resume,
    last_phase_completed: $last_phase_completed,
    next_phase: $next_phase,
    question_of_record_path: $question_of_record_path,
    question_of_record_hash: $question_of_record_hash,
    corpus_index_path: $corpus_index_path,
    corpus_index_hash: $corpus_index_hash,
    disagreement_register_hash: $disagreement_register_hash,
    beads_head_sha: $beads_head_sha,
    ntm_checkpoint_archive: $ntm_checkpoint_archive,
    ntm_checkpoint_id: $ntm_checkpoint_id,
    roster: $roster,
    open_threads: $open_threads
  }' > "$OUTPUT"
