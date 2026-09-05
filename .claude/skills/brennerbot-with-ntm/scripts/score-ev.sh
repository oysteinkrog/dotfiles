#!/usr/bin/env bash
# score-ev.sh — Compute composite W for an EV bead from its 5 axes
# Per references/EVIDENCE-WEIGHTING-TAXONOMY.md
#
# Reads W_source, W_verification, W_independence, W_recency, W_domain_fit
# from the EV bead description; computes W_composite as the product;
# updates the bead.
#
# Usage:
#   score-ev.sh <EV_ID>            # update single EV
#   score-ev.sh --all              # rescore all EV beads in current workspace
#   score-ev.sh --check <EV_ID>    # report W without modifying

set -uo pipefail

WORKSPACE="."
ACTION="update"
TARGET=""

require_value() {
    # $1 = flag name (for the error message)
    # $2 = the actual value (caller must pass it via "${2:-}" so an unset
    #      script-$2 expands to an empty string under set -u rather than
    #      tripping unbound-variable).
    # The previous version passed "$@" instead, which let the flag itself
    # land as $2 inside the helper and bypass the empty-check, crashing
    # later at `WORKSPACE="$2"` instead of producing a clean FATAL.
    if [ -z "${2:-}" ]; then
        echo "[FATAL] $1 requires a value" >&2
        exit 2
    fi
}

while [ $# -gt 0 ]; do
    case "$1" in
        --workspace=*) WORKSPACE="${1#*=}"; shift ;;
        --workspace)
            require_value --workspace "${2:-}"
            WORKSPACE="$2"; shift 2
            ;;
        --all)         ACTION="all"; shift ;;
        --check)
            require_value --check "${2:-}"
            ACTION="check"; TARGET="$2"; shift 2
            ;;
        --help|-h)
            sed -n '2,12p' "$0" | sed 's/^# \?//'
            exit 0
            ;;
        # Anything else is treated as the target EV ID. (The previous
        # `EV-*|*-NNN)` case-label was dead code: the `*-NNN` pattern only
        # matches the literal placeholder `EV-NNN`, not real IDs like
        # `EV-001`, and the catch-all `*)` branch did the same thing
        # anyway.)
        *) TARGET="$1"; shift ;;
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

# Helper: extract a W axis value from a description; defaults to 0.6 if missing.
# Defaults are deliberately moderate so missing axes don't artificially inflate
# the composite — they nudge it down toward "needs investigation".
extract_axis() {
    local desc="$1" axis="$2"
    local value
    value=$(printf '%s' "$desc" \
        | grep -oE "${axis}:[[:space:]]*[0-9]+(\.[0-9]+)?" \
        | head -1 \
        | sed -E "s/${axis}:[[:space:]]*//")
    if [ -z "$value" ]; then
        case "$axis" in
            W_verification) echo "0.6" ;;  # initial pin default
            *)              echo "0.5" ;;  # generic moderate
        esac
    else
        echo "$value"
    fi
}

# Helper: compute composite W as product of 5 axes (kept in [0,1])
compute_composite() {
    local s="$1" v="$2" i="$3" r="$4" d="$5"
    awk -v s="$s" -v v="$v" -v i="$i" -v r="$r" -v d="$d" \
        'BEGIN {
            w = s * v * i * r * d
            if (w < 0) w = 0
            if (w > 1) w = 1
            printf "%.3f", w
        }'
}

# Helper: classify W into strength bucket per EVIDENCE-WEIGHTING-TAXONOMY.md
classify() {
    local w="$1"
    awk -v w="$w" 'BEGIN {
        if (w >= 0.7)      print "strong"
        else if (w >= 0.4) print "moderate"
        else if (w >= 0.2) print "weak"
        else               print "too-weak"
    }'
}

score_one() {
    local ev_id="$1" check_only="$2"

    local desc
    desc=$(br show "$ev_id" --json 2>/dev/null | jq -r 'if type == "array" then (.[0] // {}) else . end | .description // empty')
    if [ -z "$desc" ]; then
        echo "[WARN] $ev_id: no description (skipping)" >&2
        return 1
    fi

    local s v i r d w cls
    s=$(extract_axis "$desc" W_source)
    v=$(extract_axis "$desc" W_verification)
    i=$(extract_axis "$desc" W_independence)
    r=$(extract_axis "$desc" W_recency)
    d=$(extract_axis "$desc" W_domain_fit)
    w=$(compute_composite "$s" "$v" "$i" "$r" "$d")
    cls=$(classify "$w")

    printf '%-12s  src=%s ver=%s ind=%s rec=%s dom=%s  →  W=%s (%s)\n' \
        "$ev_id" "$s" "$v" "$i" "$r" "$d" "$w" "$cls"

    [ "$check_only" = "true" ] && return 0

    # Update the bead — replace any existing W_composite line, or append one.
    local new_desc
    if printf '%s' "$desc" | grep -qE '^W_composite:'; then
        new_desc=$(printf '%s' "$desc" \
            | sed -E "s/^W_composite:[[:space:]]*[0-9.]+/W_composite: $w/")
    else
        new_desc="$desc"$'\n'"W_composite: $w"
    fi

    if printf '%s' "$new_desc" | grep -qE '^W_strength:'; then
        new_desc=$(printf '%s' "$new_desc" \
            | sed -E "s/^W_strength:[[:space:]]*[a-z-]+/W_strength: $cls/")
    else
        new_desc="$new_desc"$'\n'"W_strength: $cls"
    fi

    # Capture stderr separately so we can surface the actual reason on
    # failure. The previous `>/dev/null 2>&1` masked everything, so the
    # operator only saw "br update failed" with no diagnostic.
    local update_err
    update_err=$(br update "$ev_id" --description="$new_desc" 2>&1 >/dev/null) \
        || {
            echo "[WARN] $ev_id: br update failed: ${update_err:-(no stderr)}" >&2
            return 1
        }
}

case "$ACTION" in
    update)
        if [ -z "$TARGET" ]; then
            echo "Usage: score-ev.sh <EV_ID> | --all | --check <EV_ID>" >&2
            exit 2
        fi
        score_one "$TARGET" false
        ;;
    check)
        if [ -z "$TARGET" ]; then
            echo "[FATAL] --check requires an EV ID" >&2
            exit 2
        fi
        score_one "$TARGET" true
        ;;
    all)
        EV_IDS=$(br list --label=evidence --json 2>/dev/null \
            | jq -r '.issues[]?.id // empty')
        if [ -z "$EV_IDS" ]; then
            echo "[INFO] no EV beads found" >&2
            exit 0
        fi
        declare -i RESCORED=0 FAILED=0
        # process-substitution avoids the subshell-leak problem
        # (a pipe-to-while would not propagate counter increments).
        while IFS= read -r ev_id; do
            [ -z "$ev_id" ] && continue
            if score_one "$ev_id" false; then
                RESCORED=$((RESCORED + 1))
            else
                FAILED=$((FAILED + 1))
            fi
        done < <(printf '%s\n' "$EV_IDS")
        echo "==="
        echo "Rescored: $RESCORED"
        echo "Failed:   $FAILED"
        ;;
esac
