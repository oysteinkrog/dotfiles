#!/usr/bin/env bash
# generate-debate-pairs.sh — Generate Phase 5 debate pair list from active hypotheses.
#
# Strategy: pair each H with its strongest rival (the one whose falsifier is closest to its
# expected_evidence — the most likely to fire).
#
# Output format is the NTM foreach.pairs format. The first field is a
# BrennerBot public debate ref, not necessarily the actual generated `br` id.
# `run-phase5-debate-loop.sh` files the bead and writes a resolved pairs file
# whose first field is the actual `br` id for adjudication.
#   DEBATE-001|H-001|H-002|%1|%3
#
# Usage: generate-debate-pairs.sh [--workspace=<path>]

set -uo pipefail

WORKSPACE="."
while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace=*) WORKSPACE="${1#*=}" ;;
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
command -v br >/dev/null 2>&1 || { echo "br CLI not found" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "jq not found" >&2; exit 2; }

# Get all hypotheses still in `state: active` (those that survived Phase 4 investigation
# and need adversarial review). Filtering by bead `--status=open` alone would include H's
# already transitioned to `refuted`/`confirmed`/`superseded`/`deferred` (bead status stays
# open until session-end `br close`), so we'd waste Phase 5 debating dead horses. Inspect
# the description-level `state:` field — only `active` H's belong in cross-exam.
H_LIST=$(br list --label=hypothesis --status=open --json 2>/dev/null \
  | jq -r '
      .issues[]?
      | select((.description // "") | test("(^|\\n)state:[[:space:]]*active([[:space:]]|$)"))
      | (.external_ref // "") as $external_ref
      | (try ((.title // "") | capture("^(?<ref>H-[0-9]+):").ref) catch "") as $title_ref
      | if $external_ref != "" then $external_ref
        elif $title_ref != "" then $title_ref
        else .id
        end
    ' 2>/dev/null)

if [ -z "$H_LIST" ]; then
  exit 0
fi

# Convert to array without shell word-splitting or glob expansion.
mapfile -t H_ARR <<< "$H_LIST"
N=${#H_ARR[@]}

if [ "$N" -lt 2 ]; then
  # Cannot debate one H against itself
  exit 0
fi

# Strategy: produce pairs where each H is paired with at least one rival.
# For N=2: one pair.
# For N=3: pairs (0,1) and (1,2) — every H appears at least once.
# For N=4+: pair (0,1), (2,3), and a "wildcard" pair (0,2) to mix.
# For N=6+: same structure but with wildcards distributed.

declare -a PAIRS

normalize_pane() {
  local raw="${1:-}"
  raw="${raw%%,*}"
  raw="${raw//[[:space:]]/}"
  case "$raw" in
    %*) printf '%s\n' "$raw" ;;
    p[0-9]*) printf '%%%s\n' "${raw#p}" ;;
    [0-9]*) printf '%%%s\n' "$raw" ;;
    *) printf '%s\n' "${raw:-unknown}" ;;
  esac
}

champion_for_h() {
  local h_ref="$1"
  local h_id
  local mapped
  local raw
  if [ -f ".brenner_workspace/h-pane-mapping.json" ]; then
    mapped=$(jq -r --arg h "$h_ref" '.[$h] // empty' .brenner_workspace/h-pane-mapping.json 2>/dev/null)
    if [ -n "$mapped" ]; then
      normalize_pane "$mapped"
      return 0
    fi
  fi

  h_id=$(br list --all --json 2>/dev/null \
    | jq -r --arg ref "$h_ref" '
        .issues[]?
        | select(.id == $ref or .external_ref == $ref or ((.title // "") | startswith($ref + ":")))
        | .id
      ' 2>/dev/null \
    | head -1)
  if [ -z "$h_id" ]; then
    printf 'unknown\n'
    return 0
  fi
  raw=$(br show "$h_id" --json 2>/dev/null | jq -r '
    (if type == "array" then (.[0] // {}) else . end) as $issue
    | ($issue.assignee // $issue.owner_pane //
       (try (($issue.description // "") | capture("(?m)(^|\\n)(assignee|owner_pane|champion_pane):[[:space:]]*(?<pane>[^[:space:]]+)").pane) catch "") //
       "")
  ' 2>/dev/null)
  normalize_pane "$raw"
}

if [ "$N" -eq 2 ]; then
  PAIRS+=("${H_ARR[0]}|${H_ARR[1]}")
elif [ "$N" -eq 3 ]; then
  PAIRS+=("${H_ARR[0]}|${H_ARR[1]}")
  PAIRS+=("${H_ARR[1]}|${H_ARR[2]}")
else
  # Pair adjacent H's first (stride 2)
  i=0
  while [ "$i" -lt "$((N - 1))" ]; do
    PAIRS+=("${H_ARR[$i]}|${H_ARR[$((i + 1))]}")
    i=$((i + 2))
  done
  # If N is odd, the final H[N-1] is unpaired by the stride loop — pair it with H[0]
  # so every hypothesis gets at least one adversarial round.
  if [ "$((N % 2))" -eq 1 ]; then
    PAIRS+=("${H_ARR[0]}|${H_ARR[$((N - 1))]}")
  fi
  # Add a cross-block wildcard pair (always {H[0], H[2]}) so the first two adjacent-pair
  # blocks are linked — N≥4 guarantees H[2] exists.
  if [ "$N" -ge 4 ]; then
    PAIRS+=("${H_ARR[0]}|${H_ARR[2]}")
  fi
fi

idx=1
for p in "${PAIRS[@]}"; do
  h_i="${p%%|*}"
  h_j="${p#*|}"
  debate_id=$(printf 'DEBATE-%03d' "$idx")
  champ_i=$(champion_for_h "$h_i")
  champ_j=$(champion_for_h "$h_j")
  if [ "$champ_i" = "unknown" ] || [ "$champ_j" = "unknown" ]; then
    echo "warning: missing champion pane for $debate_id ($h_i=$champ_i, $h_j=$champ_j)" >&2
  fi
  printf '%s|%s|%s|%s|%s\n' "$debate_id" "$h_i" "$h_j" "$champ_i" "$champ_j"
  idx=$((idx + 1))
done
