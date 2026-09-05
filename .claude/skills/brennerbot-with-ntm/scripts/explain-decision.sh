#!/usr/bin/env bash
# explain-decision.sh — Explain why an H is in its current state
# Per references/BEADS-WORKFLOW-CHEATSHEET.md
#
# For an H bead, summarizes:
# - State + confidence
# - Supporting EVs (with W_composite)
# - Refuting EVs (with W_composite)
# - Outstanding critiques
# - Adjudicator decisions if any
# - Cited assumptions and their verification status
#
# Usage:
#   explain-decision.sh <H_ID-or-public-ref>
#   explain-decision.sh <H_ID-or-public-ref> --robot
#   explain-decision.sh <H_ID-or-public-ref> --workspace=<path>

set -uo pipefail

WORKSPACE_ARG="."
H_REF=""
ROBOT=0

indent_lines() {
    while IFS= read -r line; do
        printf '  %s\n' "$line"
    done <<< "$1"
}

require_value() {
    if [ -z "${2:-}" ]; then
        echo "[FATAL] $1 requires a value" >&2
        exit 2
    fi
}

while [ $# -gt 0 ]; do
    case "$1" in
        --workspace=*) WORKSPACE_ARG="${1#*=}"; shift ;;
        --workspace)
            require_value --workspace "${2:-}"
            WORKSPACE_ARG="$2"; shift 2
            ;;
        --robot)       ROBOT=1; shift ;;
        --help|-h)
            sed -n '2,15p' "$0" | sed 's/^# \?//'
            exit 0
            ;;
        # Anything else is treated as the H ref. (The previous `H-*)` case-label
        # was dead code: the catch-all `*)` next to it did the same thing.)
        *) H_REF="$1"; shift ;;
    esac
done

if [ -z "$H_REF" ]; then
    echo "[FATAL] H_ID required (e.g., H-001)" >&2
    exit 2
fi

WORKSPACE="$(cd "$WORKSPACE_ARG" 2>/dev/null && pwd)" \
    || { echo "[FATAL] Cannot cd to: $WORKSPACE_ARG" >&2; exit 1; }
cd "$WORKSPACE" || exit 1

if ! command -v br >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    echo "[FATAL] br and jq required" >&2
    exit 3
fi

# Resolve public refs such as H-001 to the generated br id. `br show` only
# accepts generated ids, while operators and EV links use public refs.
H_RECORD=$(br list --all --json 2>/dev/null | jq -c --arg ref "$H_REF" '
  .issues[]?
  | select(.id == $ref or .external_ref == $ref or ((.title // "") | startswith($ref + ":")))
  | (.external_ref // "") as $external_ref
  | (try ((.title // "") | capture("^(?<ref>H-[0-9]+):").ref) catch "") as $title_ref
  | {id: .id, public_ref: (if $external_ref != "" then $external_ref elif $title_ref != "" then $title_ref else .id end)}
' | head -1)

if [ -z "$H_RECORD" ]; then
    echo "[FATAL] H bead $H_REF not found" >&2
    exit 1
fi

H_ID=$(printf '%s\n' "$H_RECORD" | jq -r '.id')
H_PUBLIC_REF=$(printf '%s\n' "$H_RECORD" | jq -r '.public_ref')

# Verify H exists
H_JSON=$(br show "$H_ID" --json 2>/dev/null)
H_JSON=$(printf '%s' "$H_JSON" | jq -c 'if type == "array" then (.[0] // null) else . end' 2>/dev/null)
if [ -z "$H_JSON" ] || [ "$H_JSON" = "null" ]; then
    echo "[FATAL] H bead $H_REF not found" >&2
    exit 1
fi

# Extract H state, confidence, falsifier
H_DESC=$(echo "$H_JSON" | jq -r '.description // ""')
H_TITLE=$(echo "$H_JSON" | jq -r '.title // ""')
H_STATE=$(printf '%s' "$H_DESC" | grep -oE '^state:[[:space:]]*[a-z_]+' | head -1 | awk -F: '{gsub(/^[[:space:]]+/,"",$2); print $2}')
H_CONFIDENCE=$(printf '%s' "$H_DESC" | grep -oE '^confidence:[[:space:]]*[a-z]+' | head -1 | awk -F: '{gsub(/^[[:space:]]+/,"",$2); print $2}')
H_FALSIFIER=$(awk '/^falsifier:/,/^[a-z_]+:/{ if ($0 !~ /^[a-z_]+:/ || /^falsifier:/) print }' <<<"$H_DESC" \
    | sed 's/^falsifier:[[:space:]]*//' | head -3)

# Find supporting EVs. The previous `contains("supports: [\($h)]")` form only
# matched single-H bracket lists; per references/BEADS-SCHEMA.md:126 a single EV
# may carry `supports: [H-001, H-007]`, so multi-H lists were silently dropped
# from the explanation. Use the same `refs()` helper as scripts/render-evidence-pack.sh:
# capture the bracket list, split on commas, trim whitespace, then test membership.
EVS_JSON=$(br list --label=evidence --json 2>/dev/null)
SUPPORTING=$(echo "$EVS_JSON" | jq -r --arg h "$H_PUBLIC_REF" --arg br_id "$H_ID" '
    def refs($name): ((try ((.description // "") | capture($name + ":[[:space:]]*\\[(?<ids>[^\\]]*)\\]").ids) catch "") | split(",") | map(gsub("^[[:space:]]+|[[:space:]]+$"; "")));
    .issues[]? | refs("supports") as $refs | select(($refs | index($h)) or ($refs | index($br_id))) | .id
')
REFUTING=$(echo "$EVS_JSON" | jq -r --arg h "$H_PUBLIC_REF" --arg br_id "$H_ID" '
    def refs($name): ((try ((.description // "") | capture($name + ":[[:space:]]*\\[(?<ids>[^\\]]*)\\]").ids) catch "") | split(",") | map(gsub("^[[:space:]]+|[[:space:]]+$"; "")));
    .issues[]? | refs("refutes") as $refs | select(($refs | index($h)) or ($refs | index($br_id))) | .id
')

# Find critiques. Match the target field exactly so H-1 does not collect
# critiques for H-10 or unrelated prose mentioning `target: H-1`.
CRITIQUES=$(br list --label=critique --json 2>/dev/null \
    | jq -r --arg h "$H_PUBLIC_REF" --arg br_id "$H_ID" '
        def field($name):
          ((try ((.description // "") | capture("(^|\\n)" + $name + ":[[:space:]]*(?<value>[^\\n]+)").value) catch "")
           | gsub("^[[:space:]]+|[[:space:]]+$"; ""));
        .issues[]?
        | select(field("target") == $h or field("target") == $br_id)
        | ((.description // "") | match("severity:[[:space:]]*(?<s>\\w+)") // null) as $m
        | "\(.id) (severity: " + (if $m == null then "?" else $m.captures[0].string end) + ")"
    ' 2>/dev/null)

# Helper: extract W_composite for an EV
ev_w() {
    br show "$1" --json 2>/dev/null | jq -r 'if type == "array" then (.[0] // {}) else . end | .description // ""' \
        | grep -oE '^W_composite:[[:space:]]*[0-9.]+' \
        | head -1 | awk -F: '{gsub(/^[[:space:]]+/,"",$2); print $2}'
}

if [ "$ROBOT" -eq 1 ]; then
    # JSON output
    SUPPORT_JSON=$(printf '%s' "$SUPPORTING" | grep -v '^$' | while read -r ev; do
        printf '{"id":"%s","W":"%s"}\n' "$ev" "$(ev_w "$ev" || echo "?")"
    done | jq -s .)
    REFUTE_JSON=$(printf '%s' "$REFUTING" | grep -v '^$' | while read -r ev; do
        printf '{"id":"%s","W":"%s"}\n' "$ev" "$(ev_w "$ev" || echo "?")"
    done | jq -s .)
    CRIT_JSON=$(printf '%s' "$CRITIQUES" | grep -v '^$' | jq -Rs 'split("\n") | map(select(length > 0))')

    jq -n \
        --arg id "$H_PUBLIC_REF" \
        --arg br_id "$H_ID" \
        --arg title "$H_TITLE" \
        --arg state "${H_STATE:-unknown}" \
        --arg confidence "${H_CONFIDENCE:-unknown}" \
        --arg falsifier "$H_FALSIFIER" \
        --argjson supporting "$SUPPORT_JSON" \
        --argjson refuting "$REFUTE_JSON" \
        --argjson critiques "$CRIT_JSON" \
        '{id: $id, br_id: $br_id, title: $title, state: $state, confidence: $confidence,
          falsifier: $falsifier, supporting: $supporting, refuting: $refuting,
          critiques: $critiques}'
else
    cat <<EOF

=== Decision rationale for $H_PUBLIC_REF ===

Title:       $H_TITLE
br id:       $H_ID
State:       ${H_STATE:-unknown}
Confidence:  ${H_CONFIDENCE:-unknown}

Falsifier:
$(indent_lines "$H_FALSIFIER")

Supporting evidence:
EOF
    if [ -n "$SUPPORTING" ]; then
        echo "$SUPPORTING" | while read -r ev; do
            [ -z "$ev" ] && continue
            printf '  %s (W_composite: %s)\n' "$ev" "$(ev_w "$ev" || echo "?")"
        done
    else
        echo "  (none)"
    fi

    cat <<EOF

Refuting evidence:
EOF
    if [ -n "$REFUTING" ]; then
        echo "$REFUTING" | while read -r ev; do
            [ -z "$ev" ] && continue
            printf '  %s (W_composite: %s)\n' "$ev" "$(ev_w "$ev" || echo "?")"
        done
    else
        echo "  (none)"
    fi

    cat <<EOF

Outstanding critiques:
EOF
    if [ -n "$CRITIQUES" ]; then
        indent_lines "$CRITIQUES"
    else
        echo "  (none)"
    fi

    echo ""
    echo "Per CONFIDENCE-SCORING.md, the state ${H_STATE:-unknown} reflects the W"
    echo "aggregate of supporting vs refuting evidence. Use 'br show $H_ID --json' for"
    echo "full bead details, or run scripts/score-ev.sh on each EV to recompute W."
fi
