#!/usr/bin/env bash
# assign-investigator-domains.sh — Domain-assign Investigator panes to active hypotheses.
#
# Per ROSTER-PLANS.md Domain Assignment: each Investigator owns specific H-IDs to prevent collision.
#
# Strategy: round-robin assignment of H-IDs to Investigator panes. Records assignments in
# phase0_scope_decision.md § roster.
#
# Usage: assign-investigator-domains.sh --session=<name> [--workspace=<path>] [--strategy=<round-robin|by-hypothesis-count>]

set -uo pipefail

SESSION=""
WORKSPACE="."
STRATEGY="round-robin"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --session=*) SESSION="${1#*=}" ;;
    --workspace=*) WORKSPACE="${1#*=}" ;;
    --strategy=*) STRATEGY="${1#*=}" ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
  shift
done

if [ -z "$SESSION" ]; then
  echo "Usage: assign-investigator-domains.sh --session=<name>" >&2
  exit 2
fi

WORKSPACE_INPUT="$WORKSPACE"
if ! WORKSPACE="$(cd "$WORKSPACE_INPUT" 2>/dev/null && pwd)"; then
  echo "workspace not accessible: $WORKSPACE_INPUT" >&2
  exit 1
fi
cd "$WORKSPACE" || { echo "workspace not accessible: $WORKSPACE" >&2; exit 1; }
command -v br >/dev/null 2>&1 || { echo "br CLI not found" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "jq not found" >&2; exit 2; }

# Get active H public refs. Brennerbot's hypothesis lifecycle lives in the bead
# description `state:` field; the Beads issue status stays open until session
# handback/closeout. Prefer external_ref/title refs like H-001 so domains,
# evidence-pack names, and description-level supports/refutes fields stay
# human-readable; fall back to the generated br id only for malformed legacy
# beads that lack a public ref.
H_LIST=()
while IFS= read -r id; do
  H_LIST+=("$id")
done < <(br list --label=hypothesis --status=open --json 2>/dev/null | jq -r '
  .issues[]?
  | select((.description // "") | test("(^|\\n)state:[[:space:]]*active([[:space:]]|$)"))
  | (.external_ref // "") as $external_ref
  | (try ((.title // "") | capture("^(?<ref>H-[0-9]+):").ref) catch "") as $title_ref
  | if $external_ref != "" then $external_ref
    elif $title_ref != "" then $title_ref
    else .id
    end
' 2>/dev/null)

if [ ${#H_LIST[@]} -eq 0 ]; then
  echo "No active hypotheses. Run Phase 3 triage and stamp state: active first." >&2
  exit 0
fi

# Get Investigator panes. Prefer the roster recorded by bootstrap-session.sh;
# otherwise infer from the live pane count. This must match ROSTER-PLANS.md:
# Pair -> pane 1; Squad -> panes 2-3; Swarm example -> panes 4-6. A stale
# filter here once selected Swarm proposer/devil/synthesizer panes and skipped
# two actual Investigators, which made Phase 4 dispatches land on the wrong
# roles.
INV_PANES=()
ROSTER=$(sed -n 's/^\*\*Roster:\*\*[[:space:]]*//p' "$WORKSPACE/.brenner_workspace/phase0_scope_decision.md" 2>/dev/null | head -1 | tr -d '\r')
case "$ROSTER" in
  solo) INV_PANES=(1) ;;
  pair) INV_PANES=(1) ;;
  squad|squad-no-mail) INV_PANES=(2 3) ;;
  swarm) INV_PANES=(4 5 6) ;;
esac

if [ ${#INV_PANES[@]} -eq 0 ] && command -v ntm >/dev/null 2>&1; then
  mapfile -t LIVE_PANES < <(ntm --robot-snapshot 2>/dev/null | jq -r --arg s "$SESSION" '
    .sessions[]? | select(.name == $s) | .panes[] | .index' 2>/dev/null | sort -n)
  if [ ${#LIVE_PANES[@]} -gt 0 ]; then
    max="${LIVE_PANES[$((${#LIVE_PANES[@]} - 1))]}"
    if [ "$max" -ge 8 ]; then
      INV_PANES=(4 5 6)
    elif [ "$max" -ge 5 ]; then
      INV_PANES=(2 3)
    elif [ "$max" -ge 2 ]; then
      INV_PANES=(1)
    fi
  fi
fi

if [ ${#INV_PANES[@]} -eq 0 ]; then
  echo "No roster or live pane data found; falling back to ROSTER-PLANS.md Squad convention: panes 2-3." >&2
  INV_PANES=(2 3)
fi

case "$STRATEGY" in
  round-robin|by-hypothesis-count) ;;
  *) echo "unknown strategy: $STRATEGY (expected round-robin or by-hypothesis-count)" >&2; exit 2 ;;
esac

# Assign: round-robin H to panes
echo "Domain assignment ($STRATEGY):"
declare -A ASSIGNMENTS
declare -A H_TO_PANE
i=0
for h in "${H_LIST[@]}"; do
  pane=${INV_PANES[$((i % ${#INV_PANES[@]}))]}
  ASSIGNMENTS[$pane]+="$h "
  H_TO_PANE[$h]="$pane"
  i=$((i + 1))
done

# Write a machine-readable H -> pane map. Several operator snippets consume
# this directly so manual dispatch loops don't have to parse the prose ledger.
mkdir -p "$WORKSPACE/.brenner_workspace"
MAP_FILE="$WORKSPACE/.brenner_workspace/h-pane-mapping.json"
{
  echo "{"
  first=1
  for h in "${H_LIST[@]}"; do
    [ "$first" -eq 0 ] && echo ","
    printf '  "%s": "%s"' "$h" "${H_TO_PANE[$h]}"
    first=0
  done
  echo ""
  echo "}"
} > "$MAP_FILE"

# Print and append to phase0_scope_decision.md
APPEND="$WORKSPACE/.brenner_workspace/phase0_scope_decision.md"
if [ -f "$APPEND" ]; then
  {
    echo ""
    echo "## Domain assignments — $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } >> "$APPEND"
fi

for pane in "${INV_PANES[@]}"; do
  [ -n "${ASSIGNMENTS[$pane]:-}" ] || continue
  HS="${ASSIGNMENTS[$pane]}"
  echo "  pane $pane: $HS"
  [ -f "$APPEND" ] && echo "- pane $pane: ${HS}" >> "$APPEND"
done

echo "Mapping written: $MAP_FILE"
