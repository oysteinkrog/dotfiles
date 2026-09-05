#!/usr/bin/env bash
# run-phase5-debate-loop.sh — File Phase 5 debate beads and dispatch both champions.
#
# Usage:
#   run-phase5-debate-loop.sh --workspace=<path> --session=<ntm-session-id> [--round=1|2|3]

set -euo pipefail

WORKSPACE=""
SESSION_ID=""
ROUND="1"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace=*) WORKSPACE="${1#*=}" ;;
    --session=*) SESSION_ID="${1#*=}" ;;
    --round=*) ROUND="${1#*=}" ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
  shift
done

if [ -z "$WORKSPACE" ] || [ -z "$SESSION_ID" ]; then
  echo "usage: run-phase5-debate-loop.sh --workspace=<path> --session=<ntm-session-id> [--round=1|2|3]" >&2
  exit 2
fi
case "$ROUND" in
  1|2|3) ;;
  *) echo "invalid --round=$ROUND (expected 1, 2, or 3)" >&2; exit 2 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_INPUT="$WORKSPACE"
if ! WORKSPACE="$(cd "$WORKSPACE_INPUT" 2>/dev/null && pwd)"; then
  echo "workspace not found: $WORKSPACE_INPUT" >&2
  exit 2
fi
command -v br >/dev/null 2>&1 || { echo "br CLI not found" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "jq not found" >&2; exit 2; }

mkdir -p "$WORKSPACE/.brenner_workspace"
PAIRS_FILE="$WORKSPACE/.brenner_workspace/debate-pairs.pairs"
RESOLVED_PAIRS_FILE="$WORKSPACE/.brenner_workspace/debate-pairs.resolved.pairs"

if [ "$ROUND" = "1" ]; then
  "$SCRIPT_DIR/generate-debate-pairs.sh" --workspace="$WORKSPACE" > "$PAIRS_FILE"
elif [ ! -s "$PAIRS_FILE" ]; then
  echo "Missing frozen debate pair file: $PAIRS_FILE" >&2
  echo "Run round 1 first so Phase 5 debates keep the same pairings across rounds." >&2
  exit 2
fi

if [ ! -s "$PAIRS_FILE" ]; then
  : > "$RESOLVED_PAIRS_FILE"
  touch "$WORKSPACE/.brenner_workspace/phase_5_debate_rounds_complete.flag"
  echo "No active debate pairs; skipping Phase 5 cross-exam dispatch."
  exit 0
fi

: > "$RESOLVED_PAIRS_FILE"

cd "$WORKSPACE"

strip_pane_prefix() {
  local raw="$1"
  raw="${raw#%}"
  raw="${raw#p}"
  printf '%s' "$raw"
}

find_debate_id_by_ref() {
  local debate_ref="$1"
  br list --label=debate --status=open --json \
    | jq -r --arg ref "$debate_ref" '
        .issues[]?
	        | (.description // "") as $desc
	        | select(
	            .id == $ref
	            or .external_ref == $ref
	            or ($desc | startswith("debate_ref: " + $ref + "\n"))
            or ($desc | contains("\ndebate_ref: " + $ref + "\n"))
          )
        | .id
      ' \
    | head -1
}

ensure_debate_bead() {
  local debate_ref="$1"
  local h_i="$2"
  local h_j="$3"
  local champ_i="$4"
  local champ_j="$5"
  local existing

  existing=$(find_debate_id_by_ref "$debate_ref")
  if [ -n "$existing" ]; then
    echo "Debate bead already exists: $debate_ref -> $existing" >&2
    printf '%s\n' "$existing"
    return 0
  fi

  br create "$debate_ref: $h_i vs $h_j cross-exam" \
    --type=task --labels=debate --priority=2 \
    --slug="$debate_ref" --external-ref="$debate_ref" --silent \
    --description="$(cat <<EOF
debate_ref: $debate_ref
pair: $h_i vs $h_j
champions: {$h_i: p$champ_i, $h_j: p$champ_j}
adjudicator: TBD
state: open
rounds: 3
session: $SESSION_ID
mail_thread: ${SESSION_ID}-DEBATE-${h_i}-vs-${h_j}
falsifier_fired: null
adjudication: null
EOF
)"
}

while IFS='|' read -r debate_ref h_i h_j champ_i_ref champ_j_ref; do
  [ -n "$debate_ref" ] || continue
  if [ "$champ_i_ref" = "unknown" ] || [ "$champ_j_ref" = "unknown" ]; then
    echo "Missing champion pane for $debate_ref: $h_i=$champ_i_ref $h_j=$champ_j_ref" >&2
    exit 1
  fi

  champ_i=$(strip_pane_prefix "$champ_i_ref")
  champ_j=$(strip_pane_prefix "$champ_j_ref")
  if [ "$champ_i" = "unknown" ] || [ "$champ_j" = "unknown" ]; then
    echo "Missing champion pane for $debate_ref: $h_i=$champ_i_ref $h_j=$champ_j_ref" >&2
    exit 1
  fi

  debate_id=$(ensure_debate_bead "$debate_ref" "$h_i" "$h_j" "$champ_i" "$champ_j")
  printf '%s|%s|%s|%s|%s\n' "$debate_id" "$h_i" "$h_j" "$champ_i_ref" "$champ_j_ref" >> "$RESOLVED_PAIRS_FILE"

  "$SCRIPT_DIR/dispatch-marching-order.sh" MO-05a-cross-exam \
    --PANE_N="$champ_i" --H_I="$h_i" --H_J="$h_j" --SESSION_ID="$SESSION_ID" --ROUND="$ROUND" \
    --workspace="$WORKSPACE" --target-pane="$champ_i" --target-session="$SESSION_ID"
  "$SCRIPT_DIR/dispatch-marching-order.sh" MO-05a-cross-exam \
    --PANE_N="$champ_j" --H_I="$h_j" --H_J="$h_i" --SESSION_ID="$SESSION_ID" --ROUND="$ROUND" \
    --workspace="$WORKSPACE" --target-pane="$champ_j" --target-session="$SESSION_ID"
done < "$PAIRS_FILE"

if [ "$ROUND" = "3" ]; then
  touch "$WORKSPACE/.brenner_workspace/phase_5_debate_rounds_complete.flag"
  echo "Dispatched final Phase 5 debate round 3."
  echo "Marked Phase 5 debate rounds complete; adjudication may now start."
else
  echo "Dispatched Phase 5 debate round $ROUND. Do not adjudicate until all intended rounds have posted."
fi
