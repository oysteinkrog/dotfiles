#!/usr/bin/env bash
# render-evidence-pack.sh — Render evidence/packs/EV-pack-H-NNN.md from EV beads.
#
# Usage: render-evidence-pack.sh <H_ID-or-public-ref> [--workspace=<path>] [--out=<path>]

set -uo pipefail

H_REF="${1:?usage: render-evidence-pack.sh <H_ID-or-public-ref> [--workspace=<path>]}"
shift

WORKSPACE="."
OUT=""
CALLER_PWD="$PWD"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace=*) WORKSPACE="${1#*=}" ;;
    --out=*) OUT="${1#*=}" ;;
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

# Resolve public refs such as H-001 to the generated br id. `br show` does not
# resolve external_ref values, but operators and EV links should use public refs.
H_RECORD=$(br list --all --json 2>/dev/null | jq -c --arg ref "$H_REF" '
  .issues[]?
  | select(.id == $ref or .external_ref == $ref or ((.title // "") | startswith($ref + ":")))
  | (.external_ref // "") as $external_ref
  | (try ((.title // "") | capture("^(?<ref>H-[0-9]+):").ref) catch "") as $title_ref
  | {id: .id, public_ref: (if $external_ref != "" then $external_ref elif $title_ref != "" then $title_ref else .id end)}
' | head -1)

if [ -z "$H_RECORD" ]; then
  echo "Error: hypothesis $H_REF not found" >&2
  exit 1
fi

H_ID=$(printf '%s\n' "$H_RECORD" | jq -r '.id')
H_PUBLIC_REF=$(printf '%s\n' "$H_RECORD" | jq -r '.public_ref')

if [ -z "$OUT" ]; then
  OUT="$WORKSPACE/evidence/packs/EV-pack-$H_PUBLIC_REF.md"
elif [[ "$OUT" != /* ]]; then
  OUT="$CALLER_PWD/$OUT"
fi
mkdir -p "$(dirname "$OUT")" || { echo "failed to create output directory: $(dirname "$OUT")" >&2; exit 1; }

# Get H bead. br show --json returns an array even for one ID in current br.
H_DESC=$(br show "$H_ID" --json 2>/dev/null | jq -r 'if type == "array" then (.[0] // {}) else . end | .description // ""')

if [ -z "$H_DESC" ]; then
  echo "Error: hypothesis $H_REF not found" >&2
  exit 1
fi

# Extract fields from H description
get_field() {
  echo "$H_DESC" | awk -v f="$1" '/^'"$1"': / { sub(/^'"$1"': */, ""); print; exit }'
}

CLAIM=$(get_field claim)
MECHANISM=$(get_field mechanism)
FALSIFIER=$(get_field falsifier)
EXPECTED=$(get_field expected_evidence)
CATEGORY=$(get_field category)
ORIGIN=$(get_field origin)
CONFIDENCE=$(get_field confidence)
STATE=$(get_field state)
STATE=${STATE:-unknown}

# Header
if {
  cat <<EOF
# Evidence Pack — $H_PUBLIC_REF

**Hypothesis claim:** $CLAIM
**Mechanism:** $MECHANISM
**Falsifier:** $FALSIFIER
**Expected evidence:** $EXPECTED
**Category:** $CATEGORY
**Origin:** $ORIGIN
**Confidence (current):** $CONFIDENCE
**State (current):** $STATE

---

## Methodology

(Investigator: fill in Proxy choice, Amplification, Materialization log, Falsifier probe sections.)

---

## Evidence Records

### Supporting

EOF

  br list --label=evidence --json 2>/dev/null | \
    jq -r --arg h "$H_PUBLIC_REF" --arg br_id "$H_ID" 'def refs($name): ((try ((.description // "") | capture($name + ":[[:space:]]*\\[(?<ids>[^\\]]*)\\]").ids) catch "") | split(",") | map(gsub("^[[:space:]]+|[[:space:]]+$"; ""))); .issues[]? | refs("supports") as $refs | select(($refs | index($h)) or ($refs | index($br_id))) | "#### \(.id) — \(.title // "")\n- **Description:**\n```\n\(.description // "")\n```\n"'

  echo ""
  echo "### Refuting"
  echo ""

  br list --label=evidence --json 2>/dev/null | \
    jq -r --arg h "$H_PUBLIC_REF" --arg br_id "$H_ID" 'def refs($name): ((try ((.description // "") | capture($name + ":[[:space:]]*\\[(?<ids>[^\\]]*)\\]").ids) catch "") | split(",") | map(gsub("^[[:space:]]+|[[:space:]]+$"; ""))); .issues[]? | refs("refutes") as $refs | select(($refs | index($h)) or ($refs | index($br_id))) | "#### \(.id) — \(.title // "")\n- **Description:**\n```\n\(.description // "")\n```\n"'

  echo ""
  echo "### Informing"
  echo ""

  br list --label=evidence --json 2>/dev/null | \
    jq -r --arg h "$H_PUBLIC_REF" --arg br_id "$H_ID" 'def refs($name): ((try ((.description // "") | capture($name + ":[[:space:]]*\\[(?<ids>[^\\]]*)\\]").ids) catch "") | split(",") | map(gsub("^[[:space:]]+|[[:space:]]+$"; ""))); .issues[]? | refs("informs") as $refs | select(($refs | index($h)) or ($refs | index($br_id))) | "#### \(.id) — \(.title // "")\n- **Description:**\n```\n\(.description // "")\n```\n"'

  cat <<EOF

---

## Assumption Ledger
EOF

  br list --label=assumption --json 2>/dev/null | \
    jq -r --arg h "$H_PUBLIC_REF" --arg br_id "$H_ID" 'def refs($name): ((try ((.description // "") | capture($name + ":[[:space:]]*\\[(?<ids>[^\\]]*)\\]").ids) catch "") | split(",") | map(gsub("^[[:space:]]+|[[:space:]]+$"; ""))); .issues[]? | refs("affects") as $refs | select(($refs | index($h)) or ($refs | index($br_id))) | "### \(.id) — \(.title // "")\n```\n\(.description // "")\n```\n"'

  cat <<EOF

---

## Anomaly Register
EOF

  br list --label=anomaly --json 2>/dev/null | \
    jq -r --arg h "$H_PUBLIC_REF" --arg br_id "$H_ID" 'def refs($name): ((try ((.description // "") | capture($name + ":[[:space:]]*\\[(?<ids>[^\\]]*)\\]").ids) catch "") | split(",") | map(gsub("^[[:space:]]+|[[:space:]]+$"; ""))); .issues[]? | refs("conflicts_with") as $refs | select(($refs | index($h)) or ($refs | index($br_id))) | "### \(.id) — \(.title // "")\n```\n\(.description // "")\n```\n"'

  cat <<EOF

---

## Critique Trail
EOF

  br list --label=critique --json 2>/dev/null | \
    jq -r --arg h "$H_PUBLIC_REF" --arg br_id "$H_ID" 'def field($name): (try ((.description // "") | capture("(^|\\n)" + $name + ":[[:space:]]*(?<id>[^[:space:]\\n]+)").id) catch ""); .issues[]? | select(field("target") == $h or field("target") == $br_id) | "### \(.id) — \(.title // "")\n```\n\(.description // "")\n```\n"'

  cat <<EOF

---

## Round Log

(Investigator: append round entries here.)

---

## Phase 5 Adjudication (if reached)

(Adjudicator: fill in after debate.)

---

## Next-Action

(Investigator: fill in based on current state.)
EOF

} > "$OUT"; then
  :
else
  echo "failed to write evidence pack: $OUT" >&2
  exit 1
fi

echo "Rendered: $OUT"
