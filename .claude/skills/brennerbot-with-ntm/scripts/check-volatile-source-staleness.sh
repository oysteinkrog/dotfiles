#!/usr/bin/env bash
# check-volatile-source-staleness.sh — Detect stale volatile-source verifications
# Per VERIFICATION-FIRST.md: volatile sources should be re-verified per cadence.
#
# Reports any source whose last_verified_at is older than the class-specific
# cadence threshold.

set -uo pipefail

WORKSPACE="${1:-.}"

cd "$WORKSPACE" 2>/dev/null || { echo "[FATAL] Cannot cd to: $WORKSPACE" >&2; exit 1; }

CORPUS_INDEX="corpus/corpus_index.md"
VERIFICATION_LOG=""
for candidate in analyses/official-source-log.md evidence/verification_log.md corpus/verification_log.md; do
    if [ -f "$candidate" ]; then
        VERIFICATION_LOG="$candidate"
        break
    fi
done

if [ ! -f "$CORPUS_INDEX" ]; then
    echo "[INFO] No corpus_index.md; nothing to check"
    exit 0
fi

NOW_EPOCH=$(date +%s)

declare -i STALE=0
declare -i HEALTHY=0
declare -i UNKNOWN=0

# Iterate over corpus index rows (skip header):
while IFS='|' read -r _empty1 source_id _title _author _date _path _hash _anchor metadata _empty2; do
    # Skip empty rows / header:
    source_id="$(echo "$source_id" | xargs)"
    case "$source_id" in
        ""|"---"|"S-NNN-NEW"|*"Source ID"*) continue ;;
    esac

    # Extract source class:
    CLASS="$(echo "$metadata" | grep -oE 'class:[a-z-]+' | head -1 | awk -F: '{print $2}')"
    [ -z "$CLASS" ] && { UNKNOWN=$((UNKNOWN + 1)); continue; }

    # Class-specific cadence (in seconds):
    case "$CLASS" in
        frozen)         CADENCE=$((365 * 24 * 3600)) ;;  # effectively never
        versioned)      CADENCE=$((30 * 24 * 3600)) ;;   # monthly check (just to confirm SHA still valid)
        live)           CADENCE=$((4 * 3600)) ;;          # 4h
        in-flight)      CADENCE=$((30 * 60)) ;;           # 30 min
        regulatory)     CADENCE=$((7 * 24 * 3600)) ;;     # weekly
        paywalled)      CADENCE=$((30 * 24 * 3600)) ;;
        *)              CADENCE=$((24 * 3600)) ;;         # default 24h
    esac

    # Find last verification entry for this source in the source-level verification log.
    # Use awk with exact-string field match (not grep with interpolation) — that
    # way an unusual source_id with regex metacharacters can't poison the
    # pattern. Schema: `| <ISO> | <source_id> | <class> | <event> | ... |`.
    if [ -n "$VERIFICATION_LOG" ]; then
        LAST_ISO=$(awk -F'|' -v sid="$source_id" '
            {
                # $3 is the source_id column (leading "|" makes $1 empty);
                # trim and compare exactly.
                sub(/^[[:space:]]+/, "", $3); sub(/[[:space:]]+$/, "", $3)
                if ($3 == sid) last = $2
            }
            END {
                if (last != "") {
                    sub(/^[[:space:]]+/, "", last); sub(/[[:space:]]+$/, "", last)
                    print last
                }
            }
        ' "$VERIFICATION_LOG" 2>/dev/null)
    else
        LAST_ISO=""
    fi

    if [ -z "$LAST_ISO" ]; then
        echo "UNKNOWN: $source_id (no verification log entry; class=$CLASS)"
        UNKNOWN=$((UNKNOWN + 1))
        continue
    fi

    # Convert ISO to epoch (try Linux GNU date format first, then macOS):
    LAST_EPOCH=$(date -d "$LAST_ISO" +%s 2>/dev/null \
        || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$LAST_ISO" +%s 2>/dev/null \
        || echo 0)

    if [ "$LAST_EPOCH" -eq 0 ]; then
        echo "UNKNOWN: $source_id (could not parse last_verified_at='$LAST_ISO')"
        UNKNOWN=$((UNKNOWN + 1))
        continue
    fi

    AGE=$(( NOW_EPOCH - LAST_EPOCH ))

    if [ "$AGE" -gt "$CADENCE" ]; then
        echo "STALE: $source_id (class=$CLASS, age=$((AGE / 60))min, cadence=$((CADENCE / 60))min)"
        STALE=$((STALE + 1))
    else
        HEALTHY=$((HEALTHY + 1))
    fi
done < "$CORPUS_INDEX"

echo "==="
echo "Healthy sources: $HEALTHY"
echo "Stale sources:   $STALE"
echo "Unknown:         $UNKNOWN"

if [ $STALE -gt 0 ]; then
    exit 1
fi
exit 0
