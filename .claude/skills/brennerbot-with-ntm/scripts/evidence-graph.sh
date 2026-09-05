#!/usr/bin/env bash
# evidence-graph.sh — Render H → EV → source graph as DOT (Graphviz) or Mermaid
# Per references/EVIDENCE-WEIGHTING-TAXONOMY.md
#
# Builds a directed graph showing which evidence (EV-NNN) supports/refutes
# which hypotheses (H-NNN), and which sources (S-NNN) the evidence cites.
# Useful for visual sanity-check of evidence base and identifying lonely
# load-bearing EVs.
#
# Usage:
#   evidence-graph.sh > graph.dot          # default: dot format
#   evidence-graph.sh --format=mermaid     # mermaid format
#   evidence-graph.sh --workspace=<path>

set -uo pipefail

WORKSPACE="."
FORMAT="dot"

# Bareword arg forms below need an explicit empty-value guard. Without it,
# `score-ev.sh --workspace` (no value) would crash under `set -u` at the
# `$2` reference instead of emitting a clean FATAL — same class of bug
# that round-7 fixed in session-fork.sh's --purpose handling.
while [ $# -gt 0 ]; do
    case "$1" in
        --workspace=*) WORKSPACE="${1#*=}"; shift ;;
        --workspace)
            if [ -z "${2:-}" ]; then
                echo "[FATAL] --workspace requires a value" >&2
                exit 2
            fi
            WORKSPACE="$2"; shift 2
            ;;
        --format=*)    FORMAT="${1#*=}"; shift ;;
        --format)
            if [ -z "${2:-}" ]; then
                echo "[FATAL] --format requires a value" >&2
                exit 2
            fi
            FORMAT="$2"; shift 2
            ;;
        --help|-h)
            sed -n '2,14p' "$0" | sed 's/^# \?//'
            exit 0
            ;;
        *) echo "unknown flag: $1" >&2; exit 2 ;;
    esac
done

cd "$WORKSPACE" 2>/dev/null \
    || { echo "[FATAL] Cannot cd to: $WORKSPACE" >&2; exit 1; }

if ! command -v br >/dev/null 2>&1; then
    echo "[FATAL] br (beads) CLI not found" >&2
    exit 2
fi
if ! command -v jq >/dev/null 2>&1; then
    echo "[FATAL] jq not found" >&2
    exit 2
fi

# Collect H beads (label=hypothesis):
H_JSON=$(br list --label=hypothesis --json 2>/dev/null || echo '{"issues":[]}')
EV_JSON=$(br list --label=evidence --json 2>/dev/null || echo '{"issues":[]}')

emit_dot() {
    echo "digraph evidence_graph {"
    echo "  rankdir=LR;"
    echo "  node [shape=box, style=filled, fontname=Helvetica];"
    echo ""

    # Hypothesis nodes (color by state)
    echo "  // hypotheses"
    echo "$H_JSON" | jq -r '.issues[]? |
        .id as $id |
        (.title // "") as $title |
        (.description // "") as $desc |
        (($desc | capture("state:[[:space:]]*(?<s>[a-z]+)")? | .s) // "active") as $state |
        "  \"\($id)\" [label=\"\($id)\\n\($title | gsub("\""; ""))\", fillcolor=\"" +
            (if $state == "confirmed" then "#90ee90"
             elif $state == "refuted" then "#ffcccc"
             elif $state == "deferred" then "#dddddd"
             else "#fff8b3" end) + "\"];"
    ' 2>/dev/null

    # Evidence nodes (color by W_strength)
    echo ""
    echo "  // evidence"
    echo "$EV_JSON" | jq -r '.issues[]? |
        .id as $id |
        (.description // "") as $desc |
        (($desc | capture("W_composite:[[:space:]]*(?<w>[0-9.]+)")? | .w) // "0") as $w |
        (($desc | capture("W_strength:[[:space:]]*(?<s>[a-z-]+)")? | .s) // "unknown") as $strength |
        "  \"\($id)\" [shape=ellipse, label=\"\($id)\\nW=\($w)\", fillcolor=\"" +
            (if $strength == "strong" then "#bdf"
             elif $strength == "moderate" then "#dfd"
             elif $strength == "weak" then "#fec"
             elif $strength == "too-weak" then "#fdd"
             else "#eee" end) + "\"];"
    ' 2>/dev/null

    # Edges: EV → H (supports / refutes). Use `capture()` with a named group
    # (same pattern as the mermaid emitter below), NOT `match(...; "g")` —
    # the previous version chained `match(...; "g"); .captures[0].string`
    # inside parens, where `;` is not a valid jq separator (it's only a
    # function-argument separator), so the whole expression failed silently
    # under `2>/dev/null` and the DOT graph never showed any EV→H edges.
    echo ""
    echo "  // edges (EV → H)"
    echo "$EV_JSON" | jq -r '.issues[]? |
        .id as $eid |
        (.description // "") as $desc |
        ((try ($desc | capture("supports:[[:space:]]*\\[(?<list>[^\\]]*)\\]") | .list) catch "")) as $supports |
        select($supports != "") |
        ($supports | split(",") | map(gsub("\\s+"; ""))[]) as $h |
        select($h != "") |
        "  \"\($eid)\" -> \"\($h)\" [label=\"supports\", color=\"green\"];"
    ' 2>/dev/null

    echo "$EV_JSON" | jq -r '.issues[]? |
        .id as $eid |
        (.description // "") as $desc |
        ((try ($desc | capture("refutes:[[:space:]]*\\[(?<list>[^\\]]*)\\]") | .list) catch "")) as $refutes |
        select($refutes != "") |
        ($refutes | split(",") | map(gsub("\\s+"; ""))[]) as $h |
        select($h != "") |
        "  \"\($eid)\" -> \"\($h)\" [label=\"refutes\", color=\"red\"];"
    ' 2>/dev/null

    # Source nodes (drawn from EV.source_id field)
    echo ""
    echo "  // sources"
    SOURCES=$(echo "$EV_JSON" | jq -r '.issues[]? |
        (.description // "") |
        try (capture("source_id:[[:space:]]*(?<s>S-[A-Za-z0-9-]+)") | .s) catch empty
    ' 2>/dev/null | sort -u)
    while IFS= read -r src; do
        [ -z "$src" ] && continue
        printf '  "%s" [shape=cylinder, fillcolor="#eef"];\n' "$src"
    done <<< "$SOURCES"

    # Edges: source → EV
    echo ""
    echo "  // edges (source → EV)"
    echo "$EV_JSON" | jq -r '.issues[]? |
        .id as $eid |
        (.description // "") as $desc |
        ((try ($desc | capture("source_id:[[:space:]]*(?<s>S-[A-Za-z0-9-]+)") | .s) catch null)) as $src |
        select($src != null) |
        "  \"\($src)\" -> \"\($eid)\" [color=\"#888\", style=dashed];"
    ' 2>/dev/null

    echo "}"
}

emit_mermaid() {
    echo "flowchart LR"
    echo "  classDef confirmed fill:#90ee90"
    echo "  classDef refuted fill:#ffcccc"
    echo "  classDef deferred fill:#dddddd"
    echo "  classDef active fill:#fff8b3"
    echo "  classDef strong-ev fill:#bdf"
    echo "  classDef moderate-ev fill:#dfd"
    echo "  classDef weak-ev fill:#fec"
    echo "  classDef too-weak-ev fill:#fdd"
    echo "  classDef source fill:#eef"
    echo ""

    # Hypothesis nodes
    echo "$H_JSON" | jq -r '.issues[]? |
        .id as $id |
        (.title // "") as $title |
        (.description // "") as $desc |
        (($desc | capture("state:[[:space:]]*(?<s>[a-z]+)")? | .s) // "active") as $state |
        "  " + ($id | gsub("-"; "_")) + "[\"" + $id + "<br>" + ($title | gsub("\""; "&quot;")) + "\"]:::" + $state
    ' 2>/dev/null

    # Evidence nodes + edges
    echo ""
    echo "$EV_JSON" | jq -r '.issues[]? |
        .id as $eid |
        (.description // "") as $desc |
        (($desc | capture("W_composite:[[:space:]]*(?<w>[0-9.]+)")? | .w) // "0") as $w |
        (($desc | capture("W_strength:[[:space:]]*(?<s>[a-z-]+)")? | .s) // "unknown") as $strength |
        "  " + ($eid | gsub("-"; "_")) + "((\"" + $eid + "<br>W=" + $w + "\")):::" + $strength + "-ev"
    ' 2>/dev/null

    # Edges
    echo ""
    echo "$EV_JSON" | jq -r '.issues[]? |
        .id as $eid |
        (.description // "") as $desc |
        ((try ($desc | capture("supports:[[:space:]]*\\[(?<list>[^\\]]*)\\]") | .list) catch "")) as $supports |
        select($supports != "") |
        ($supports | split(",") | map(gsub("\\s+"; ""))[]) as $h |
        select($h != "") |
        "  " + ($eid | gsub("-"; "_")) + " -- supports --> " + ($h | gsub("-"; "_"))
    ' 2>/dev/null

    echo "$EV_JSON" | jq -r '.issues[]? |
        .id as $eid |
        (.description // "") as $desc |
        ((try ($desc | capture("refutes:[[:space:]]*\\[(?<list>[^\\]]*)\\]") | .list) catch "")) as $refutes |
        select($refutes != "") |
        ($refutes | split(",") | map(gsub("\\s+"; ""))[]) as $h |
        select($h != "") |
        "  " + ($eid | gsub("-"; "_")) + " -. refutes .-> " + ($h | gsub("-"; "_"))
    ' 2>/dev/null

    # Source nodes + source → EV edges. The DOT emitter has always included
    # these; Mermaid needs the same data or its graph omits provenance.
    echo ""
    echo "$EV_JSON" | jq -r '[
        .issues[]? |
        (.description // "") |
        try (capture("source_id:[[:space:]]*(?<s>S-[A-Za-z0-9-]+)") | .s) catch empty
      ] | unique[] |
        "  " + (gsub("-"; "_")) + "[(" + . + ")]:::source"
    ' 2>/dev/null

    echo "$EV_JSON" | jq -r '.issues[]? |
        .id as $eid |
        (.description // "") as $desc |
        ((try ($desc | capture("source_id:[[:space:]]*(?<s>S-[A-Za-z0-9-]+)") | .s) catch null)) as $src |
        select($src != null) |
        "  " + ($src | gsub("-"; "_")) + " -. source .-> " + ($eid | gsub("-"; "_"))
    ' 2>/dev/null
}

case "$FORMAT" in
    dot)     emit_dot ;;
    mermaid) emit_mermaid ;;
    *)
        echo "[FATAL] Unknown format: $FORMAT (expected: dot | mermaid)" >&2
        exit 2
        ;;
esac
