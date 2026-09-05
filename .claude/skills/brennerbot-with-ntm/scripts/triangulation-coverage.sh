#!/usr/bin/env bash
# triangulation-coverage.sh — Measure cross-family coverage of session
# Per references/TRIANGULATION.md and BRENNER-GAN-MECHANICS.md
#
# Reports how well the session has triangulated across model families:
# - Per-H: which families investigated it?
# - Per-EV: which families filed it?
# - Distillations: per-family coverage?
# - Audit: cross-family rotation satisfied?

set -uo pipefail

WORKSPACE="."
# Bareword arg forms need an explicit empty-value guard so that
# `triangulation-coverage.sh --workspace` (no value) emits a clean FATAL
# instead of crashing on `$2: unbound variable`.
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
        --help|-h)
            sed -n '2,9p' "$0" | sed 's/^# \?//'
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

echo "=== Triangulation Coverage Report ==="
echo "Workspace: $(pwd)"
echo "Date:      $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

# Helper: extract pane→family mapping from phase0_scope_decision.md
declare -A PANE_FAMILY
if [ -f .brenner_workspace/phase0_scope_decision.md ]; then
    while IFS= read -r line; do
        # Match patterns like "- pane: 3 ... family: cc" or "pane=3,family=gmi"
        pane=$(echo "$line" | grep -oE 'pane[:=][[:space:]]*[0-9]+' | grep -oE '[0-9]+')
        family=$(echo "$line" | grep -oE 'family[:=][[:space:]]*[a-z]+' | grep -oE '[a-z]+$')
        if [ -n "$pane" ] && [ -n "$family" ]; then
            PANE_FAMILY[$pane]="$family"
        fi
    done < .brenner_workspace/phase0_scope_decision.md
fi

# 1. Per-H family coverage
echo "## Per-H investigation coverage"
echo ""

H_IDS=$(br list --label=hypothesis --json 2>/dev/null \
    | jq -r '.issues[]?.id // empty')

if [ -z "$H_IDS" ]; then
    echo "(no H beads)"
else
    # For each H, find EVs that reference it; collect filer families
    while IFS= read -r h_id; do
        [ -z "$h_id" ] && continue

        # Find EVs supporting/refuting/informing this H. Use a word-boundary regex
        # rather than `contains($hid)` — substring match would falsely include EVs
        # that reference H-10/H-11 etc. when the target is H-1, polluting the
        # per-H family count.
        related_evs=$(br list --label=evidence --json 2>/dev/null \
            | jq -r --arg hid "$h_id" '
                .issues[]? |
                select((.description // "") | test("\\b" + $hid + "\\b")) |
                .id
            ' 2>/dev/null)

        # For each related EV, extract imported_by pane → family
        families=()
        while IFS= read -r ev_id; do
            [ -z "$ev_id" ] && continue
            pane=$(br show "$ev_id" --json 2>/dev/null \
                | jq -r 'if type == "array" then (.[0] // {}) else . end | .description // ""' \
                | grep -oE 'imported_by:[[:space:]]*[a-zA-Z0-9-]+' \
                | head -1 \
                | sed -E 's/imported_by:[[:space:]]*//')
            # Extract pane number
            pane_num=$(printf '%s' "$pane" | grep -oE '[0-9]+' | head -1)
            if [ -n "$pane_num" ] && [ -n "${PANE_FAMILY[$pane_num]:-}" ]; then
                families+=("${PANE_FAMILY[$pane_num]}")
            fi
        done <<< "$related_evs"

        # Dedupe. Use array length for `count` rather than `grep -c . || echo 0`
        # — that idiom produces "0\n0" when the input is empty (grep -c emits
        # "0" with exit 1, the OR fires, echo emits another "0"), which then
        # breaks the downstream `printf %d`. The unconditional reset of
        # h_unique on every iteration matters: mapfile's conditional
        # assignment alone would leak the previous iteration's values into
        # an H whose own families[] is empty.
        h_unique=()
        if [ ${#families[@]} -gt 0 ]; then
            mapfile -t h_unique < <(printf '%s\n' "${families[@]}" | sort -u)
        fi
        unique=$(printf '%s\n' "${h_unique[@]+${h_unique[@]}}" \
                 | grep -v '^$' | tr '\n' ',' | sed 's/,$//')
        count=${#h_unique[@]}
        printf '  %-12s  %d families: %s\n' "$h_id" "$count" "${unique:-(none)}"
    done <<< "$H_IDS"
fi

# 2. Distillation per-family coverage
echo ""
echo "## Distillation per-family coverage"
echo ""

if [ -d distillations ]; then
    for fam in cc cod gmi; do
        if [ -f "distillations/by_${fam}.md" ]; then
            lines=$(wc -l < "distillations/by_${fam}.md")
            printf '  by_%s.md: present (%d lines)\n' "$fam" "$lines"
        else
            printf '  by_%s.md: MISSING\n' "$fam"
        fi
    done

    if [ -f distillations/meta_synthesis.md ]; then
        echo "  meta_synthesis.md: present"
    else
        echo "  meta_synthesis.md: MISSING"
    fi

    if [ -f distillations/disagreement_register.md ]; then
        # Count substantive entries: lines starting with "## D-NNN" or "- D-NNN".
        # File existence is already guarded above, so grep -c emits "0" with
        # exit 1 if no matches; suppress that exit code without doubling the
        # output (the same `|| echo 0` trap warned about elsewhere in this file).
        entries=$(grep -cE '^(## |- )D-[0-9]+' distillations/disagreement_register.md 2>/dev/null) || true
        entries=${entries:-0}
        echo "  disagreement_register.md: $entries entries"
    else
        echo "  disagreement_register.md: MISSING"
    fi
else
    echo "  (distillations/ directory not present — Phase 6 not yet started)"
fi

# 3. Audit pane diversity
echo ""
echo "## Phase 7 audit pane diversity"
echo ""

if [ -d audit-findings ]; then
    audit_panes=$(grep -hroE 'by_pane:[[:space:]]*[a-zA-Z0-9-]+' audit-findings/ 2>/dev/null \
        | sort -u | wc -l)
    audit_families=()
    while IFS= read -r pane_line; do
        pane_num=$(echo "$pane_line" | grep -oE '[0-9]+' | head -1)
        if [ -n "$pane_num" ] && [ -n "${PANE_FAMILY[$pane_num]:-}" ]; then
            audit_families+=("${PANE_FAMILY[$pane_num]}")
        fi
    done < <(grep -hroE 'by_pane:[[:space:]]*[a-zA-Z0-9-]+' audit-findings/ 2>/dev/null | sort -u)

    # Same `grep -c . || echo 0` avoidance as the per-H block above.
    audit_unique=()
    if [ ${#audit_families[@]} -gt 0 ]; then
        mapfile -t audit_unique < <(printf '%s\n' "${audit_families[@]}" | sort -u)
    fi
    unique_audit=$(printf '%s\n' "${audit_unique[@]+${audit_unique[@]}}" \
                  | grep -v '^$' | tr '\n' ',' | sed 's/,$//')
    count_audit=${#audit_unique[@]}
    printf '  Audit panes: %d distinct\n' "$audit_panes"
    printf '  Audit families: %d (%s)\n' "$count_audit" "${unique_audit:-(none)}"
else
    echo "  (audit-findings/ directory not present — Phase 7 not yet started)"
fi

# 4. Roster diversity
echo ""
echo "## Roster diversity"
echo ""

if [ "${PANE_FAMILY[*]+set}" = "set" ]; then
    distinct_families=$(printf '%s\n' "${PANE_FAMILY[@]}" | awk 'NF' | sort -u | wc -l | tr -d ' ')
else
    distinct_families=0
fi
echo "  Distinct families in roster: $distinct_families"
if [ "$distinct_families" -eq 0 ]; then
    echo "  ⚠ No roster family mapping found — triangulation coverage unknown"
elif [ "$distinct_families" -lt 2 ]; then
    echo "  ⚠ Single-family roster — triangulation degraded (per Solo tier)"
elif [ "$distinct_families" -lt 3 ]; then
    echo "  ⚠ Two-family roster — triangulation partial (T2 typical)"
else
    echo "  ✓ Three+ family roster (T3+ healthy)"
fi

echo ""
echo "==="
echo "Coverage report complete."
