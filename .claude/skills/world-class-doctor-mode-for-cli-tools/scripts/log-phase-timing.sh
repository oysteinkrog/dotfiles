#!/usr/bin/env bash
set -euo pipefail
# log-phase-timing.sh — record a per-phase / per-subagent timing event.
#
# Subagents and orchestrators call this at start and end of each phase
# segment. The script appends one line to <workspace>/phases_timing.jsonl
# (created if missing, append-only otherwise). Feeds dashboard.py.
#
# Usage:
#   log-phase-timing.sh --workspace WS --phase N --subagent NAME --event start|finish
#                       [--agent-id ID] [--note "..."]
#
# Args:
#   --workspace WS      workspace dir
#   --phase N           phase number (0..10) per PHASES.md
#   --subagent NAME     subagent identifier (e.g., "archaeologist", "implementer")
#   --event TYPE        "start" or "finish"
#   --agent-id ID       opaque agent id for cross-pass correlation
#   --note "..."        optional one-liner; goes to .note field
#
# Output: appends one JSONL record:
#   {"schema_version": "1.0", "phase": 1, "subagent_name": "archaeologist",
#    "event": "start", "started_at": "2026-05-07T14:23:00Z",
#    "agent_id": "...", "note": "..."}
# Or finish:
#   {... "event": "finish", "finished_at": "...", "duration_ms": 12345}
#
# duration_ms is computed only when --event=finish AND a prior matching
# start record exists in the file (matched by phase + subagent + agent_id).
#
# Exit: 0 success, 64 usage.

usage() {
    echo "usage: log-phase-timing.sh --workspace WS --phase N --subagent NAME --event start|finish [--agent-id ID] [--note STR]" >&2
}

workspace=""
phase=""
subagent=""
event=""
agent_id=""
note=""
need_value() {
    [ -n "${2:-}" ] || { echo "log-phase-timing: $1 requires a value" >&2; usage; exit 64; }
    case "$2" in --*) echo "log-phase-timing: $1 requires a value, got option-like token: $2" >&2; usage; exit 64 ;; esac
}

while [ $# -gt 0 ]; do
    case "$1" in
        --workspace) need_value "$1" "${2:-}"; workspace="$2"; shift 2 ;;
        --phase)     need_value "$1" "${2:-}"; phase="$2"; shift 2 ;;
        --subagent)  need_value "$1" "${2:-}"; subagent="$2"; shift 2 ;;
        --event)     need_value "$1" "${2:-}"; event="$2"; shift 2 ;;
        --agent-id)  need_value "$1" "${2:-}"; agent_id="$2"; shift 2 ;;
        --note)      need_value "$1" "${2:-}"; note="$2"; shift 2 ;;
        -h|--help)   usage; exit 0 ;;
        *) echo "log-phase-timing: unknown arg $1" >&2; usage; exit 64 ;;
    esac
done

[ -n "$workspace" ] || { usage; exit 64; }
[ -n "$phase" ] || { usage; exit 64; }
[ -n "$subagent" ] || { usage; exit 64; }
case "$phase" in
    ''|*[!0-9]*)
        echo "log-phase-timing: --phase must be a non-negative integer" >&2
        usage
        exit 64
        ;;
esac
case "$event" in start|finish) ;; *) usage; exit 64 ;; esac

mkdir -p "$workspace"
out="$workspace/phases_timing.jsonl"
now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
now_ms=$(python3 -c 'import time; print(int(time.time()*1000))')

if [ "$event" = "start" ]; then
    jq -nc \
        --arg sv "1.0" \
        --argjson phase "$phase" \
        --arg subagent "$subagent" \
        --arg event "start" \
        --arg started_at "$now" \
        --argjson started_at_ms "$now_ms" \
        --arg agent_id "$agent_id" \
        --arg note "$note" \
        '{
            schema_version: $sv,
            phase: $phase,
            subagent_name: $subagent,
            event: $event,
            started_at: $started_at,
            started_at_ms: $started_at_ms,
            agent_id: (if $agent_id == "" then null else $agent_id end),
            note: (if $note == "" then null else $note end)
         }' >> "$out"
else
    # Find the most recent matching start record.
    started_at_ms=0
    if [ -s "$out" ]; then
        candidate=$(jq -rs --argjson phase "$phase" --arg subagent "$subagent" --arg agent_id "$agent_id" '
            reverse
            | map(select(.event == "start"
                         and .phase == $phase
                         and .subagent_name == $subagent
                         and (.agent_id // "") == $agent_id)
                  | .started_at_ms)
            | .[0] // empty
        ' "$out" 2>/dev/null || true)
        case "$candidate" in
            ''|*[!0-9]*) started_at_ms=0 ;;
            *) started_at_ms="$candidate" ;;
        esac
    fi
    if [ "$started_at_ms" -gt 0 ]; then
        duration_ms=$((now_ms - started_at_ms))
        [ "$duration_ms" -lt 0 ] && duration_ms=0
    else
        duration_ms=null
    fi
    jq -nc \
        --arg sv "1.0" \
        --argjson phase "$phase" \
        --arg subagent "$subagent" \
        --arg event "finish" \
        --arg finished_at "$now" \
        --argjson duration_ms "$duration_ms" \
        --arg agent_id "$agent_id" \
        --arg note "$note" \
        '{
            schema_version: $sv,
            phase: $phase,
            subagent_name: $subagent,
            event: $event,
            finished_at: $finished_at,
            duration_ms: $duration_ms,
            agent_id: (if $agent_id == "" then null else $agent_id end),
            note: (if $note == "" then null else $note end)
         }' >> "$out"
fi
