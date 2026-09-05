#!/usr/bin/env bash
# export-timeline.sh — Export session timeline as JSONL
# Per references/CROSS-SESSION-LEARNING.md and BRENNERBOT-AT-SCALE.md
#
# Builds a chronological JSONL of session events (bead state changes, phase
# completions, dispatches, audit findings, drift verdict). Useful for:
# - Cross-session pattern analysis (per /flywheel)
# - Replay/audit of session decisions
# - Telemetry aggregation for at-scale operators
#
# Usage:
#   export-timeline.sh                                # current dir → stdout
#   export-timeline.sh --workspace=<path> --out=<file>
#   export-timeline.sh --since=<ISO>                  # filter by date

set -uo pipefail

WORKSPACE_ARG="."
OUT_FILE=""
SINCE=""

require_value() {
    if [ -z "${2:-}" ]; then
        echo "[FATAL] $1 requires a value" >&2
        exit 2
    fi
}

while [ $# -gt 0 ]; do
    case "$1" in
        --workspace=*) WORKSPACE_ARG="${1#*=}"; shift ;;
        --workspace)   require_value --workspace "${2:-}"; WORKSPACE_ARG="$2"; shift 2 ;;
        --out=*)       OUT_FILE="${1#*=}"; shift ;;
        --out)         require_value --out "${2:-}"; OUT_FILE="$2"; shift 2 ;;
        --since=*)     SINCE="${1#*=}"; shift ;;
        --since)       require_value --since "${2:-}"; SINCE="$2"; shift 2 ;;
        --help|-h)
            sed -n '2,16p' "$0" | sed 's/^# \?//'
            exit 0
            ;;
        *) echo "[FATAL] unknown flag: $1" >&2; exit 2 ;;
    esac
done

WORKSPACE="$(cd "$WORKSPACE_ARG" 2>/dev/null && pwd)" \
    || { echo "[FATAL] Cannot cd to: $WORKSPACE_ARG" >&2; exit 1; }
cd "$WORKSPACE" || exit 1

if ! command -v br >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    echo "[FATAL] br and jq required" >&2
    exit 3
fi

# Choose output destination
if [ -n "$OUT_FILE" ]; then
    exec >"$OUT_FILE"
fi

# Helper: emit a JSONL line if SINCE is empty or event timestamp >= SINCE
emit() {
    local timestamp="$1"
    local event_type="$2"
    local payload="$3"
    if [ -n "$SINCE" ]; then
        # Compare timestamps as strings (ISO 8601 sorts lexicographically)
        if [[ "$timestamp" < "$SINCE" ]]; then
            return
        fi
    fi
    jq -nc \
        --arg t "$timestamp" \
        --arg type "$event_type" \
        --argjson payload "$payload" \
        '{timestamp: $t, type: $type, payload: $payload}'
}

# 1. Bead create/update events from beads jsonl
if [ -d .beads ]; then
    for bead_file in .beads/*.jsonl; do
        [ -f "$bead_file" ] || continue
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            ts=$(printf '%s' "$line" | jq -r '.created_at // .updated_at // ""')
            id=$(printf '%s' "$line" | jq -r '.id // ""')
            if [ -n "$ts" ] && [ -n "$id" ]; then
                payload=$(printf '%s' "$line" | jq -c '{id, title, type, status, labels}')
                emit "$ts" "bead_event" "$payload"
            fi
        done <"$bead_file"
    done
fi

# 2. Phase completions (mtime of phase_*_complete.flag files)
for n in 1 2 3 4 5 6 7 8 9 10; do
    flag=".brenner_workspace/phase_${n}_complete.flag"
    if [ -f "$flag" ]; then
        ts=$(stat -c '%y' "$flag" 2>/dev/null \
             || stat -f '%Sm' -t '%Y-%m-%dT%H:%M:%SZ' "$flag" 2>/dev/null)
        # Normalize to ISO-like
        iso=$(date -u -d "$ts" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
              || date -j -f '%Y-%m-%d %H:%M:%S %z' "$ts" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
              || echo "$ts")
        emit "$iso" "phase_complete" "$(jq -nc --argjson n "$n" '{phase: $n}')"
    fi
done

# 3. Audit findings (from audit-findings/ if present)
if [ -d audit-findings ]; then
    for af in audit-findings/AF-*.md; do
        [ -f "$af" ] || continue
        ts=$(stat -c '%y' "$af" 2>/dev/null \
             || stat -f '%Sm' -t '%Y-%m-%dT%H:%M:%SZ' "$af" 2>/dev/null)
        iso=$(date -u -d "$ts" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "$ts")
        af_id=$(basename "$af" .md)
        severity=$(grep -m1 -oE '^severity:[[:space:]]*[a-z]+' "$af" | head -1 | awk -F: '{gsub(/^[[:space:]]+/,"",$2); print $2}')
        emit "$iso" "audit_finding" "$(jq -nc --arg id "$af_id" --arg sev "${severity:-unknown}" '{id: $id, severity: $sev}')"
    done
fi

# 4. Drift check verdict if Phase 10 done
if [ -f deliverables/DRIFT-CHECK.md ]; then
    # Mirror the GNU/BSD stat dispatch used elsewhere in this script (lines
    # 97-98, 111-112). The previous form was GNU-only and would emit an empty
    # `iso` (and thus a malformed event) on macOS/BSD operator hosts.
    ts=$(stat -c '%y' deliverables/DRIFT-CHECK.md 2>/dev/null \
         || stat -f '%Sm' -t '%Y-%m-%dT%H:%M:%SZ' deliverables/DRIFT-CHECK.md 2>/dev/null)
    iso=$(date -u -d "$ts" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
          || date -j -f '%Y-%m-%d %H:%M:%S %z' "$ts" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
          || echo "$ts")
    verdict=$(grep -m1 -oE '^DRIFT VERDICT:[[:space:]]*[a-z-]+' deliverables/DRIFT-CHECK.md \
        | awk -F: '{gsub(/^[[:space:]]+/,"",$2); print $2}')
    emit "$iso" "drift_verdict" "$(jq -nc --arg v "${verdict:-unknown}" '{verdict: $v}')"
fi

# 5. Dispatch logs (from session-logs/ if present)
if [ -d session-logs ]; then
    for log in session-logs/dispatch-*.log; do
        [ -f "$log" ] || continue
        stamp=$(basename "$log" .log | sed 's/^dispatch-//')
        if [[ "$stamp" =~ ^([0-9]{8})T([0-9]{6})Z$ ]]; then
            ymd="${BASH_REMATCH[1]}"
            hms="${BASH_REMATCH[2]}"
            ts="${ymd:0:4}-${ymd:4:2}-${ymd:6:2}T${hms:0:2}:${hms:2:2}:${hms:4:2}Z"
        else
            raw_ts=$(stat -c '%y' "$log" 2>/dev/null \
                || stat -f '%Sm' -t '%Y-%m-%dT%H:%M:%SZ' "$log" 2>/dev/null \
                || echo "")
            ts=$(date -u -d "$raw_ts" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "$raw_ts")
        fi
        mo=$(awk -F': ' '/^MO: /{print $2; exit}' "$log")
        target_pane=$(awk -F': ' '/^Target pane: /{print $2; exit}' "$log")
        target_session=$(awk -F': ' '/^Target session: /{print $2; exit}' "$log")
        if [ -n "$ts" ] && [ -n "$mo" ]; then
            emit "$ts" "dispatch" "$(jq -nc --arg mo "$mo" --arg pane "$target_pane" --arg session "$target_session" --arg path "$log" '{mo: $mo, pane: $pane, session: $session, log: $path}')"
        fi
    done
fi
